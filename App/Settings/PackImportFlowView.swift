import SwiftUI
import PackImport
import TadakDomain

// 외부 채움글 1-c 4단계 — 가져오기 시트: 4-A 읽는 중 · 4-B·4-C 글자 확인 · 구분자 고르기 · 4-E·4-F·4-H·4-I 미리보기 · 4-G 거부
// (계획서 `external-snippet-packs-1c-plan.md` 3-3절·5절 4행, 시안 4-A~4-C·4-E~4-I, PDR 5-1·5-2·5-3b·5-5, AC-17·18·19·34).
//
// 상태는 `PackImportSession`(값) 하나다. 무거운 일(파일 제한 읽기·디코드·파싱·겹침 계산)은 전부 메인 밖(`PackFileReader.read`·
// `PackImportSession.perform`)이고, 결과는 세대를 맞춰 받는다 — 취소하거나 선택을 바꾸면 늦게 온 결과는 버려진다. 시트가 닫히면 원본을 비운다.
// **확정(저장)은 5단계다** — 미리보기의 「다음」은 자리만 있다(눌리지 않는다).
// 보안: 파일 내용·이름은 로그·분석 이벤트로 내보내지 않는다. 오류 문구에도 없다(사유 코드는 위치 번호뿐, AC-34). 파일 이름은 화면에도 보이지 않는다.

/// 시트 하나 = 가져오기 한 번
struct PackImportRequest: Identifiable {
    enum Origin {
        /// 파일 선택기가 준 보안 범위 URL — 열고 읽고 바로 해제한다(`PackFileReader`)
        case file(URL)
        case paste(String)
        /// 선택기가 파일을 주지 못했다
        case pickFailed
    }

    let id = UUID()
    let origin: Origin

    var kind: PackImportSource.Kind {
        if case .paste = origin { return .paste }
        return .file
    }
}

/// 시트를 닫은 이유 — 4-G 「다른 파일 고르기」면 부른 화면이 선택기를 다시 연다
enum PackImportExit: Equatable {
    case closed
    case pickAnotherFile
}

struct PackImportFlowView: View {
    let request: PackImportRequest
    let onExit: @MainActor (PackImportExit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var session = PackImportSession()
    @State private var path: [Destination] = []
    @State private var showsPartialConfirmation = false
    /// 지금 목록(4-I 겹침 계산 입력·겹친 팩 이름) — 시트를 열 때 한 번 읽는다. 시트가 열린 동안 목록은 바뀌지 않는다
    /// (가져오기 화면 밖으로 나가야 바꿀 수 있다). 못 읽으면 nil — 겹침 안내 없이 미리보기
    @State private var library: PackImpact.Library?

    enum Destination: Hashable {
        case guide, allRows, allSkipped
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                phaseContent
            }
            .settingsFormWidth()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .guide: PackImportGuideView()
                case .allRows: allRowsView
                case .allSkipped: allSkippedView
                }
            }
            .overlay {
                // 글자 방식·칸 나누기를 바꿔 다시 읽는 중(4-A 화면으로 넘어가지 않는다)
                if session.isWorking, session.phase != .reading {
                    ProgressView()
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task { await start() }
        // 끌어 내려 닫아도 원본을 비운다
        .onDisappear { session.cancel() }
        .alert(PackImportCopy.partialConfirmTitle(currentPreview?.importCount ?? 0), isPresented: $showsPartialConfirmation) {
            Button(PackImportCopy.cancel, role: .cancel) {}
            Button(PackImportCopy.partialConfirmAction(currentPreview?.importCount ?? 0)) { session.confirmPartialImport() }
        } message: {
            Text(PackImportCopy.partialConfirmMessage(skipped: currentPreview?.draft.skipped.count ?? 0))
        }
    }

    // MARK: - 단계별 화면

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .idle, .reading:
            readingContent
        case .encoding(let review):
            encodingContent(review)
        case .delimiter(let candidates):
            delimiterContent(candidates)
        case .preview(let preview):
            PackImportPreviewSections(
                preview: preview, kind: request.kind, partialConfirmed: session.partialImportConfirmed,
                canReviewEncoding: session.lastReview != nil, isWorking: session.isWorking,
                summary: { id in library?.pack(id)?.summary },
                onDelimiter: { run(session.chooseDelimiter($0)) },
                onReviewEncoding: { session.reviewEncodingAgain() },
                onShowAll: { path.append(.allRows) }, onShowAllSkipped: { path.append(.allSkipped) },
                onHowToFix: { path.append(.guide) }, onPartial: { showsPartialConfirmation = true })
        case .failed(let problem):
            failureContent(problem)
        }
    }

    /// 4-A — 파일 이름은 보이지 않는다
    private var readingContent: some View {
        Section {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(PackImportCopy.readingTitle(request.kind))
                    .font(.headline)
                Text(PackImportCopy.readingMessage(request.kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .accessibilityElement(children: .combine)
        }
        .listRowBackground(Color.clear)
    }

    /// 4-B·4-C — 두 방식 중 고르기, 고른 쪽 표본, 둘 다 읽히면 다른 쪽 표본(흐리게), 행·여러 줄 본문·읽기 실패
    @ViewBuilder
    private func encodingContent(_ review: PackEncodingReview) -> some View {
        Section {
            Picker(PackImportCopy.encodingLabel, selection: Binding(
                get: { review.selected },
                set: { run(session.chooseEncoding($0)) }
            )) {
                ForEach(PackEncodingReview.Encoding.allCases, id: \.self) { encoding in
                    Text(PackImportCopy.encodingName(encoding)).tag(encoding)
                }
            }
            .pickerStyle(.segmented)
            .disabled(session.isWorking)
        } header: {
            Text(PackImportCopy.encodingQuestion)
        } footer: {
            Text(PackImportCopy.encodingStatus(review))
        }

        let selected = review.reading(review.selected)
        if !selected.samples.isEmpty {
            Section {
                ForEach(Array(selected.samples.enumerated()), id: \.offset) { _, sample in
                    sampleRow(sample)
                }
            } header: {
                Text(PackImportCopy.samplesHeader(review))
            }
        }
        if review.bothReadable {
            Section {
                ForEach(Array(review.reading(review.other).samples.enumerated()), id: \.offset) { _, sample in
                    sampleRow(sample)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(PackImportCopy.alternativeHeader(review))
            } footer: {
                Text(PackImportCopy.alternativeFooter)
            }
        }

        Section {
            if let rows = review.recordCount {
                LabeledContent(PackImportCopy.rowsLabel, value: PackImportCopy.count(rows))
            }
            if let multiline = review.multilineBodyCount {
                LabeledContent(PackImportCopy.multilineLabel, value: PackImportCopy.count(multiline))
            }
            LabeledContent(PackImportCopy.failedLabel, value: "\(selected.failedLines)")
        } footer: {
            Text(PackImportCopy.encodingFooter)
        }
    }

    private func sampleRow(_ sample: String?) -> some View {
        Text(sample ?? PackImportCopy.unreadableSample)
            .foregroundStyle(sample == nil ? .secondary : .primary)
            .lineLimit(2)
    }

    /// 구분자 후보가 둘 이상(5-2 #3) — 고르면 원본에서 다시 읽는다(시안 컷 없음)
    private func delimiterContent(_ candidates: [CSVDelimiter]) -> some View {
        Section {
            ForEach(candidates, id: \.self) { delimiter in
                Button {
                    run(session.chooseDelimiter(delimiter))
                } label: {
                    LabeledContent(PackImportCopy.delimiterName(delimiter)) {
                        Text(verbatim: delimiter == .tab ? "⇥" : String(delimiter.rawValue))
                            .font(.body.monospaced())
                    }
                }
                .disabled(session.isWorking)
            }
            if session.lastReview != nil {
                Button(PackImportCopy.reviewEncodingAgain) { session.reviewEncodingAgain() }
                    .disabled(session.isWorking)
            }
        } header: {
            Text(PackImportCopy.delimiterQuestion)
        } footer: {
            Text(PackImportCopy.delimiterFooter)
        }
    }

    /// 4-G — 큰 ✕ + 제목 + 사유 한 줄(파일 내용 없음). 머리글 사유면 머리글 예시, 유효 0이면 건너뛴 이유. 다음 행동 둘 — 만드는 법 · 다른 파일
    @ViewBuilder
    private func failureContent(_ problem: PackImportProblem) -> some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
                Text(PackImportCopy.failureTitle(request.kind))
                    .font(.title3.weight(.semibold))
                Text(PackImportCopy.failureMessage(problem, source: request.kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }

        if PackImportCopy.showsHeaderExample(problem) {
            Section {
                ForEach(PackImportCopy.headerExamples, id: \.self) { example in
                    Text(example)
                        .font(.body.monospaced())
                }
            } header: {
                Text(PackImportCopy.headerExampleHeader)
            } footer: {
                Text(PackImportCopy.failureFooter(problem, source: request.kind))
            }
        } else if case .noValidRecords(let preview) = problem {
            Section {
                ForEach(PackImportCopy.skipGroups(preview.draft.skipped), id: \.label) { group in
                    LabeledContent(group.label, value: PackImportCopy.skipReasonCount(group.count))
                }
                Button(PackImportCopy.showAllSkipped) { path.append(.allSkipped) }
            } header: {
                Text(PackImportCopy.skipReasonsHeader)
            } footer: {
                Text(PackImportCopy.failureFooter(problem, source: request.kind))
            }
        } else {
            Section {
            } footer: {
                Text(PackImportCopy.failureFooter(problem, source: request.kind))
            }
        }

        Section {
            Button(PackImportCopy.guideTitle) { path.append(.guide) }
            if request.kind == .file {
                Button(PackImportCopy.pickAnotherFile) { close(.pickAnotherFile) }
            } else {
                Button(PackImportCopy.backToPaste) { close(.closed) }
            }
        }
    }

    // MARK: - 전체 보기

    private var currentPreview: PackImportPreview? {
        switch session.phase {
        case .preview(let preview): preview
        case .failed(.noValidRecords(let preview)): preview
        default: nil
        }
    }

    /// U5 「전체 보기」 — 받을 항목 전부(번호형은 번호순)
    @ViewBuilder
    private var allRowsView: some View {
        if let preview = currentPreview {
            List {
                PackImportRowsSection(draft: preview.draft, limit: nil)
            }
            .navigationTitle(PackImportCopy.allRowsTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 건너뛴 행 전부 — 위치와 이유만(5-5)
    @ViewBuilder
    private var allSkippedView: some View {
        if let preview = currentPreview {
            List {
                Section {
                    ForEach(Array(preview.draft.skipped.enumerated()), id: \.offset) { _, skipped in
                        SkippedRow(skipped: skipped)
                    }
                } footer: {
                    Text(PackImportCopy.skippedFooter)
                }
            }
            .navigationTitle(PackImportCopy.allSkippedTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 도구 막대

    private var title: String {
        switch session.phase {
        case .encoding: PackImportCopy.encodingTitle
        case .delimiter: PackImportCopy.delimiterTitle
        case .preview: PackImportCopy.previewTitle
        case .idle, .reading, .failed: PackImportCopy.flowTitle
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if case .failed = session.phase {
                Button(PackImportCopy.close) { close(.closed) }
            } else {
                Button(PackImportCopy.cancel) { close(.closed) }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            switch session.phase {
            case .encoding(let review):
                Button(PackImportCopy.next) { session.confirmEncoding() }
                    .disabled(session.isWorking || !review.reading(review.selected).isReadable)
            case .preview(let preview):
                // 4-H는 「다음」이 없다(자동 진행 금지, R10). 확정은 5단계 — 지금은 자리만(눌리지 않는다)
                if !preview.draft.requiresConfirmation || session.partialImportConfirmed {
                    Button(PackImportCopy.next) {}
                        .disabled(true)
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: - 메인 밖 일

    /// 4-A를 먼저 띄우고(시작 표), 단축어 겹침 입력(지금 목록)을 읽은 뒤 원본을 싣는다. 파일은 제한 읽기(cap+1, 보안 범위 즉시 해제)
    private func start() async {
        let ticket = session.begin(request.kind)
        // 목록 읽기(변환본을 열어 단축어를 모은다)와 파일 제한 읽기를 함께 — 둘 다 메인 밖
        async let loadedLibrary = PackStoreClient.live.impactLibrary()
        let source: Result<PackImportSource, PackImportProblem> = switch request.origin {
        case .paste(let text): .success(.paste(text))
        case .file(let url): await PackFileReader.read(url).map { .file($0) }
        case .pickFailed: .failure(.fileUnreadable)
        }
        library = await loadedLibrary
        switch source {
        case .success(let source): run(session.load(source, ticket: ticket))
        case .failure(let problem): session.failToLoad(problem, ticket: ticket)
        }
    }

    /// 다시 읽기(인코딩·구분자 변경)도 같은 목록으로 겹침을 센다
    private func run(_ run: PackImportSession.Run?) {
        guard let run else { return }
        let library = self.library
        Task {
            let computation = await PackImportSession.perform(run, library: library)
            session.receive(computation)
        }
    }

    private func close(_ exit: PackImportExit) {
        session.cancel()
        onExit(exit)
        dismiss()
    }
}

// MARK: - 미리보기 (4-E · 4-F · 4-H · 4-I)

/// 미리보기 절들 — 숫자 둘 → (4-H면 배너·건너뛴 이유·두 버튼) → 종류·틀·칸 나누기 → 건너뛴 행 → 알림 줄 → 단축어 확인 → 처음 n개
private struct PackImportPreviewSections: View {
    let preview: PackImportPreview
    let kind: PackImportSource.Kind
    let partialConfirmed: Bool
    let canReviewEncoding: Bool
    let isWorking: Bool
    /// 겹친 팩의 이름·켬/끔(4-I 「(꺼짐)」) — 겹침을 센 그 목록의 읽기 모델
    let summary: (String) -> PackSummary?
    let onDelimiter: @MainActor (CSVDelimiter) -> Void
    let onReviewEncoding: @MainActor () -> Void
    let onShowAll: @MainActor () -> Void
    let onShowAllSkipped: @MainActor () -> Void
    let onHowToFix: @MainActor () -> Void
    let onPartial: @MainActor () -> Void

    /// 4-F 건너뛴 행을 미리보기에 바로 보이는 수 — 넘으면 「건너뛴 행 모두 보기」
    private static let shownSkipped = 5

    private var draft: PackDraft { preview.draft }
    /// 4-H — 절반 넘게 건너뛰고 아직 확인 전
    private var holds: Bool { draft.requiresConfirmation && !partialConfirmed }

    var body: some View {
        Section {
            HStack(spacing: 12) {
                stat(preview.importCount, PackImportCopy.importCountLabel, tint: .primary)
                stat(draft.skipped.count,
                     draft.requiresConfirmation ? PackImportCopy.skippedLabel(percent: preview.skippedPercent) : PackImportCopy.skippedLabel,
                     tint: draft.requiresConfirmation ? .red : (draft.skipped.isEmpty ? .primary : .orange))
            }
            .padding(.vertical, 6)
        }

        if holds {
            Section {
                SnippetNoticeBanner(message: PackImportCopy.manySkippedBanner(kind))
            }
            Section {
                ForEach(PackImportCopy.skipGroups(draft.skipped), id: \.label) { group in
                    LabeledContent(group.label, value: PackImportCopy.skipReasonCount(group.count))
                }
                Button(PackImportCopy.showAllSkipped, action: onShowAllSkipped)
            } header: {
                Text(PackImportCopy.skipReasonsHeader)
            }
            Section {
                Button(action: onHowToFix) {
                    Text(PackImportCopy.howToFix).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: onPartial) {
                    Text(PackImportCopy.importOnly(preview.importCount)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .listRowBackground(Color.clear)
        }

        Section {
            LabeledContent(PackImportCopy.kindLabel, value: PackImportCopy.modeName(draft.mode))
            if draft.mode == .numbered, let template = PackImportCopy.fileTemplate(draft.meta.templateSpecs) {
                LabeledContent(PackImportCopy.fileTemplateLabel) {
                    Text(template).font(.body.monospaced())
                }
            }
            // 칸 나누기를 바꾸면 원본에서 다시 읽는다(5-2 #4)
            Picker(PackImportCopy.delimiterLabel, selection: Binding(get: { draft.delimiter }, set: onDelimiter)) {
                ForEach(CSVDelimiter.allCases, id: \.self) { delimiter in
                    Text(PackImportCopy.delimiterName(delimiter)).tag(delimiter)
                }
            }
            .disabled(isWorking)
            if canReviewEncoding {
                Button(PackImportCopy.reviewEncodingAgain, action: onReviewEncoding)
                    .disabled(isWorking)
            }
        }

        if !holds, !draft.skipped.isEmpty {
            Section {
                ForEach(Array(draft.skipped.prefix(Self.shownSkipped).enumerated()), id: \.offset) { _, skipped in
                    SkippedRow(skipped: skipped)
                }
                if draft.skipped.count > Self.shownSkipped {
                    Button(PackImportCopy.showAllSkipped, action: onShowAllSkipped)
                }
            } header: {
                Text(PackImportCopy.skippedHeader(count: draft.skipped.count))
            } footer: {
                Text(PackImportCopy.skippedFooter)
            }
        }

        let notes = infoNotes
        if !notes.isEmpty {
            Section {
                ForEach(notes, id: \.self) { note in
                    NoteRow(message: note, details: [], isWarning: false)
                }
            }
        }

        if let overlap = preview.overlap, !overlap.isEmpty {
            let lines = PackImportCopy.overlapLines(overlap, summary: summary)
            let warnings = lines.filter(\.isWarning)
            if !warnings.isEmpty {
                Section {
                    ForEach(warnings, id: \.message) { line in
                        NoteRow(message: line.message, details: line.details, isWarning: true)
                    }
                } header: {
                    Text(PackImportCopy.overlapHeader)
                } footer: {
                    Text(PackImportCopy.overlapFooter)
                }
            }
            let infos = lines.filter { !$0.isWarning }
            if !infos.isEmpty {
                Section {
                    ForEach(infos, id: \.message) { line in
                        NoteRow(message: line.message, details: line.details, isWarning: false)
                    }
                } header: {
                    if warnings.isEmpty { Text(PackImportCopy.overlapHeader) }
                }
            }
        }

        Section {
            PackImportRowsSection(draft: draft, limit: draft.mode == .numbered ? 5 : 3)
            Button(PackImportCopy.showAll, action: onShowAll)
        } header: {
            Text(PackImportCopy.firstRowsHeader(count: min(preview.importCount, draft.mode == .numbered ? 5 : 3)))
        } footer: {
            if draft.ignoredColumnCount > 0 {
                Text(PackImportCopy.ignoredColumns(draft.ignoredColumnCount))
            }
        }
    }

    /// 같은 번호·단축어 · 문자 정리 · 따옴표 — 파랑 정보(4-F 아래)
    private var infoNotes: [String] {
        var notes: [String] = []
        if draft.duplicateCount > 0 { notes.append(PackImportCopy.duplicates(draft.duplicateCount, mode: draft.mode)) }
        if draft.sanitizedCharacterCount > 0 { notes.append(PackImportCopy.sanitized(draft.sanitizedCharacterCount)) }
        if draft.strayQuoteCount > 0 { notes.append(PackImportCopy.strayQuotes(draft.strayQuoteCount)) }
        return notes
    }

    private func stat(_ value: Int, _ label: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: "\(value)")
                .font(.title.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 받을 항목 줄 — 번호형 「번호 · 제목」 + 본문 첫 줄, 문구형 제목 + 단축어
private struct PackImportRowsSection: View {
    let draft: PackDraft
    /// nil이면 전부
    let limit: Int?

    var body: some View {
        switch draft.mode {
        case .numbered:
            ForEach(limited(draft.items), id: \.n) { item in
                row(title: item.title.isEmpty ? "\(item.n)" : "\(item.n) · \(item.title)", detail: firstLine(item.body))
            }
        case .phrases:
            ForEach(Array(limited(draft.entries).enumerated()), id: \.offset) { _, entry in
                row(title: entry.title, detail: PackImportCopy.triggersLine(entry.triggers))
            }
        }
    }

    private func limited<Element>(_ elements: [Element]) -> [Element] {
        limit.map { Array(elements.prefix($0)) } ?? elements
    }

    private func firstLine(_ body: String) -> String {
        let line = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? body
        return line.count < body.count ? line + "…" : line
    }

    private func row(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .lineLimit(1)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 건너뛴 행 — 위치와 사유 + 고치는 법(내용 없음, 5-5)
private struct SkippedRow: View {
    let skipped: SkippedRecord

    var body: some View {
        NoteRow(message: PackImportCopy.skipTitle(skipped), details: [PackImportCopy.skipFix(skipped.reason)], isWarning: true)
    }
}

/// 경고(주황 ⚠)·정보(파랑 ⓘ) 한 줄 + 작은 둘째 줄들
private struct NoteRow: View {
    let message: String
    let details: [String]
    let isWarning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(isWarning ? .orange : .blue)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline)
                ForEach(details, id: \.self) { detail in
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
