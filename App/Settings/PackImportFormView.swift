import SwiftUI
import PackImport
import TadakDomain

// 외부 채움글 1-c 5단계 — 「팩 정보」 폼(5-A 번호형 · 5-B 문구형 · 5-C 틀 검사) · 같은 이름 확인(U3) · 가져오기 거부(4-J) · 완료(4-M)
// (계획서 `external-snippet-packs-1c-plan.md` 3-4절·5절 5행, 시안 5-A·5-B·5-C·4-J·4-M·U2·U3, PDR 5-6·9-1·9-2·10-1~10-4, AC-3·AC-20~24).
//
// 상태는 패키지 값 둘이다 — 폼 칸 `PackImportForm`, 확정 흐름 `PackImportConfirmation`. 무거운 일(성경 전체 n 틀 검사·최종 컴파일·커밋)은
// 전부 메인 밖(`PackTemplateReview.perform`·`PackImportConfirmation.perform` → `PackStoreClient`)이다. 문구는 전부 `PackFormCopy`·`PackNoticeCopy`.
// 보안: 팩 이름·출처·틀은 사용자 입력이다 — **화면에 표시만** 하고 로그·분석 이벤트로 내보내지 않는다.

/// 「팩 정보」 — 미리보기의 「다음」으로 밀어 넣는다. 「가져오기」가 확정이다
struct PackImportFormView: View {
    @Binding var form: PackImportForm
    @Binding var confirmation: PackImportConfirmation
    /// 미리보기 때 읽은 목록 — 같은 이름·틀 소유(주황)·이름 표시
    let library: PackImpact.Library?
    /// D2·A3 「정리하기」 — 가져오기 시트 안에서 정리 화면을 밀어 넣는다(폼 값을 지킨다)
    let onOrganize: @MainActor () -> Void
    /// 목록 복구를 마쳤다 — 시트가 목록을 다시 읽는다
    let onLibraryChanged: @MainActor () -> Void
    /// 화면에 다시 왔다(정리 화면에서 돌아옴)
    let onReturn: @MainActor () -> Void

    @State private var review: [PackTemplateReview.Status] = []
    /// `review`가 검사한 틀 칸 — 지금 칸과 다르면 그 결과는 낡았다(입력 중)
    @State private var reviewedTemplates: [String] = []
    /// 「따로 추가」를 고른 뒤 — 이름을 고칠 때까지 이름 칸 아래 안내
    @State private var separated = false
    @State private var showsRecovery = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            if let failure = generalFailure {
                Section {
                    Label(PackFormCopy.compileFailure(failure), systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }
            nameSection
            if form.mode == .numbered {
                templateSection
            }
            licenseSection
        }
        .settingsFormWidth()
        .navigationTitle(PackFormCopy.formTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(PackFormCopy.importButton) { run(confirmation.confirm(form)) }
                    .disabled(!canImport)
            }
        }
        .overlay {
            if confirmation.phase == .working {
                ProgressView()
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onAppear(perform: onReturn)
        // 틀 검사(성경 전체 n · 소유 · 가림)는 메인 밖 — 입력이 멈추고 0.3초 뒤에 돈다. 목록·바꿀 팩이 바뀌어도 다시
        .task(id: ReviewKey(templates: form.templates, revision: library?.revision, replacing: sameName?.id)) {
            guard form.mode == .numbered else { return }
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            let templates = form.templates
            let result = await PackTemplateReview.perform(templates, library: library, replacing: sameName?.id)
            guard !Task.isCancelled else { return }
            review = result
            reviewedTemplates = templates
        }
        .onChange(of: confirmation.focusesName) { _, focuses in
            guard focuses else { return }
            separated = true
            nameFocused = true
            confirmation.nameFocused()
        }
        .onChange(of: form.name) { separated = false }
        // U3 — 바꾸기 / 따로 추가 / 취소. 버튼이 모두 상태를 옮기므로 닫힘 바인딩은 아무것도 하지 않는다
        .alert(PackFormCopy.sameNameTitle, isPresented: Binding(get: { askingSameName != nil }, set: { _ in }),
               presenting: askingSameName) { existing in
            Button(PackFormCopy.replaceButton) { run(confirmation.chooseReplace()) }
            Button(PackFormCopy.separateButton) { confirmation.chooseSeparate() }
            Button(PackFormCopy.cancel, role: .cancel) { confirmation.cancelSameName() }
        } message: { existing in
            Text(PackFormCopy.sameNameMessage(existing.name ?? PackNoticeCopy.unnamedPack))
        }
        // 4-J 등 거부 — D1 「꺼 둔 채로 가져오기」·닫기, D2 정리하기·꺼 둔 채로·닫기, D3 확인.
        // U3처럼 **버튼마다 상태를 한 번 옮기고 닫힘 바인딩은 아무것도 하지 않는다**(화면 확인 N-1 — 아래 `noticeBinding`)
        .packChangeNoticeAlert(noticeBinding, in: .importFlow, onDismiss: { confirmation.dismissNotice() }) { action in
            switch action {
            case .importDisabled:
                if let work = confirmation.importDisabled() { run(work) } else { confirmation.dismissNotice() }
            case .organize:
                confirmation.dismissNotice()
                onOrganize()
            case .recoverLibrary:
                confirmation.dismissNotice()
                showsRecovery = true
            default:
                confirmation.dismissNotice()
            }
        }
        .packLibraryRecovery(isPresented: $showsRecovery, onFinish: onLibraryChanged)
    }

    // MARK: - 5-A·5-B 이름

    private var nameSection: some View {
        Section {
            HStack {
                TextField(PackFormCopy.namePlaceholder, text: $form.name)
                    .focused($nameFocused)
                    .submitLabel(.done)
                if form.isNameFromFile { Tag(text: PackFormCopy.fromFileTag) }
                Text(PackFormCopy.counter(form.name, limit: PackLimits.name))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(form.nameIssue == .nameTooLong ? .red : .secondary)
            }
        } header: {
            Text(PackFormCopy.nameLabel)
        } footer: {
            if let line = nameFooter {
                Text(line.text)
                    .foregroundStyle(line.color)
            }
        }
    }

    private var nameFooter: (text: String, color: Color)? {
        if form.nameIssue == .nameTooLong || confirmation.formFailure == .nameTooLong {
            return (PackFormCopy.compileFailure(.nameTooLong), .red)
        }
        if sameName != nil { return (separated ? PackFormCopy.separateHint : PackFormCopy.sameNameHint, .orange) }
        if form.meta.issues.contains(.nameTooLong), form.name.isEmpty { return (PackFormCopy.nameTooLongFromFile, .secondary) }
        if form.meta.name == nil, form.name.isEmpty { return (PackFormCopy.nameEmptyFromFile, .secondary) }
        return nil
    }

    // MARK: - 5-A·5-C 틀(번호형만)

    private var templateSection: some View {
        Section {
            ForEach(Array(form.templates.indices), id: \.self) { index in
                templateRow(index)
            }
            .onDelete { offsets in offsets.sorted(by: >).forEach { form.removeTemplate(at: $0) } }
            .deleteDisabled(!form.canRemoveTemplate)
            if form.canAddTemplate {
                Button {
                    form.addTemplate()
                } label: {
                    Label(PackFormCopy.addTemplate, systemImage: "plus")
                }
            }
            if let example = form.chipExample {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PackFormCopy.chipPreviewHeader)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(example.trigger)
                        .font(.body.monospacedDigit())
                    Text(PackNoticeCopy.usageResult(example.title))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(PackFormCopy.templatesHeader)
        } footer: {
            Text(PackFormCopy.templatesFooter + "\n" + PackFormCopy.reviewFooter)
        }
    }

    private func templateRow(_ index: Int) -> some View {
        let status = rowStatus(index)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                TextField(PackFormCopy.templatePlaceholder, text: Binding(
                    get: { form.templates.indices.contains(index) ? form.templates[index] : "" },
                    set: { form.setTemplate($0, at: index) }))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if index == 0 {
                    if form.isTemplateFromFile(at: 0) { Tag(text: PackFormCopy.fromFileTag) }
                } else {
                    Tag(text: PackFormCopy.aliasTag)
                }
                statusIcon(status)
            }
            if let line = rowLines(status) {
                Text(line.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(line.color)
                if let detail = line.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// 칸 상태 — 지금 칸을 검사한 결과가 있으면 그것(빨강·주황·✓), 입력 중이면 즉시 검사(스키마 빨강)만, 확정 때 거부된 칸이면 그 사유
    private func rowStatus(_ index: Int) -> PackTemplateReview.Status? {
        if reviewedTemplates == form.templates, review.indices.contains(index) { return review[index] }
        if let failure = form.templateFailure(at: index) { return .invalid(failure) }
        if case .pattern(index, let failure) = confirmation.formFailure { return .invalid(failure) }
        return nil
    }

    /// 칸 상태 아이콘 — VoiceOver 이름은 문구 표(`PackFormCopy.templateStatusLabel` 「통과」·「가져올 수 없음」·「알림」). 숨겨 두면 칸 행이
    /// 하나로 합쳐지지 않을 때(입력칸이 든 행) 기호 기본 이름 「선택됨」으로 읽혔다(화면 확인 N-7)
    @ViewBuilder
    private func statusIcon(_ status: PackTemplateReview.Status?) -> some View {
        if let status, let label = PackFormCopy.templateStatusLabel(status) {
            Group {
                switch status {
                case .ok: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .invalid: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                case .outranked, .shadowed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .empty: EmptyView()
                }
            }
            .accessibilityLabel(label)
        }
    }

    private func rowLines(_ status: PackTemplateReview.Status?) -> (title: String, detail: String?, color: Color)? {
        guard let status else { return nil }
        if case .invalid(let failure) = status {
            return (PackFormCopy.templateFailure(failure), PackFormCopy.templateFailureExample(failure), .red)
        }
        let name: (String) -> String = { library?.name(of: $0) ?? PackNoticeCopy.unnamedPack }
        guard let title = PackFormCopy.reviewTitle(status, name: name) else { return nil }
        return (title, PackFormCopy.reviewDetail(status, replacing: sameName != nil, name: name), .orange)
    }

    // MARK: - 5-A·5-B 출처(R27 — 코드 식별자는 `license` 그대로) · 파일 출처는 미리 골라 둔다(R28, `PackImportForm`)

    private var licenseSection: some View {
        Section {
            ForEach(form.licenseChoices, id: \.self) { choice in
                Button {
                    form.licenseChoice = choice
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(PackFormCopy.licenseLabel(choice))
                                .foregroundStyle(.primary)
                            if choice == .fromFile, let text = form.meta.license {
                                Text("「\(text)」")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        if form.licenseChoice == choice {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(form.licenseChoice == choice ? .isSelected : [])
            }
            if form.licenseChoice == .custom {
                HStack {
                    TextField(PackFormCopy.customLicensePlaceholder, text: $form.customLicense, axis: .vertical)
                    Text(PackFormCopy.counter(form.customLicense, limit: PackLimits.license))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(form.licenseIssue == .licenseTooLong ? .red : .secondary)
                }
            }
        } header: {
            Text(PackFormCopy.licenseHeader)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if form.licenseChoice == .custom, form.licenseIssue == .licenseTooLong {
                    Text(PackFormCopy.compileFailure(.licenseTooLong)).foregroundStyle(.red)
                }
                if form.meta.issues.contains(.licenseTooLong) { Text(PackFormCopy.licenseTooLongFromFile) }
                Text(PackFormCopy.licenseFooter(hasFileLicense: form.meta.license != nil))
            }
        }
    }

    // MARK: - 상태

    private var sameName: PackSummary? { form.sameNamePack(in: library?.packs.map(\.summary) ?? []) }

    /// 지금 칸을 검사한 결과에 빨강이 있으면 꺼진다(입력 중의 낡은 결과는 보지 않는다 — 확정 때 최종 컴파일이 다시 막는다)
    private var canImport: Bool {
        guard confirmation.phase == .editing, form.isComplete else { return false }
        guard reviewedTemplates == form.templates else { return true }
        return !review.contains(where: \.blocksImport)
    }

    private var askingSameName: PackSummary? {
        if case .askingSameName(let existing) = confirmation.phase { return existing }
        return nil
    }

    /// 칸에 붙일 수 없는 최종 검사 사유(폼으로는 생길 수 없는 것) — 맨 위 한 줄
    private var generalFailure: PackCompileFailure? {
        switch confirmation.formFailure {
        case .templateNotAllowed?, .noValidRecords?, .tooManyPatterns?, .templateRequired?, .nameMissing?, .licenseMissing?,
             .licenseTooLong?: confirmation.formFailure
        default: nil
        }
    }

    /// 거부 알림 — 보이는지는 단계가 정하고, **닫힘(set)은 아무것도 하지 않는다**(U3 알림과 같다). 닫기·동작 버튼이 각자 상태를 옮긴다.
    /// ★ 화면 확인 N-1 — 예전에는 여기서 `dismissNotice()`를 불렀는데, 이 바인딩은 확정 흐름 값을 통째로 읽고-고쳐-쓴다. 알림 버튼 동작
    /// (「꺼 둔 채로」 → `working`) 뒤에 닫힘이 **동작 전에 읽은 값**으로 되쓰면 단계가 폼으로 돌아가 저장 결과를 버렸고, 폼에 남은 채
    /// 다시 누르면 같은 이름 팩이 하나 더 생겼다(재현 3회). 결과는 이제 그 일과 함께 받아(`receive(_:for:)`) 순서와 상관없이 완료로 간다
    private var noticeBinding: Binding<PackChangeNotice?> {
        Binding(get: {
            if case .rejected(let notice) = confirmation.phase { return notice }
            return nil
        }, set: { _ in })
    }

    private func run(_ work: PackImportConfirmation.Work?) {
        guard let work else { return }
        Task {
            let result = await PackImportConfirmation.perform(work, client: .live)
            confirmation.receive(result, for: work)
        }
    }

    private struct ReviewKey: Equatable {
        let templates: [String]
        let revision: Int?
        let replacing: String?
    }
}

/// 「파일에서」·「별칭」 꼬리표
private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }
}

// MARK: - 4-M 완료

/// 완료 — 가져온 팩 이름·개수 · 건너뛴 수 · 쉬게 된 팩(G1·G2) · 「이렇게 써 보세요」 · 「채움글로 돌아가기」
struct PackImportCompletionSections: View {
    let completion: PackImportCompletion
    let onBack: @MainActor () -> Void

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text(PackFormCopy.doneTitle(completion.kind))
                    .font(.title3.weight(.semibold))
                Text(PackFormCopy.doneSummary(name: completion.name, count: completion.itemCount))
                    .font(.subheadline)
                if completion.skippedCount > 0 {
                    Text(PackFormCopy.skippedLine(completion.skippedCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }

        if let notice = completion.notice {
            Section {
                SnippetNoticeBanner(message: notice.message)
            }
        }

        Section {
            ForEach(Array(completion.examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.trigger)
                        .font(.body.monospacedDigit())
                    Text(PackNoticeCopy.usageResult(body: example.body))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            if !completion.examples.isEmpty { Text(PackFormCopy.tryHeader) }
        } footer: {
            Text(footer)
        }

        Section {
            Button(action: onBack) {
                // 큰 글자에서 잘리지 않게 줄을 바꾼다(화면 확인 N-6)
                Text(PackFormCopy.backToSnippets)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private var footer: String {
        let state = completion.isEnabled ? PackFormCopy.nextTimeLine : PackFormCopy.disabledLine
        return completion.kind == .replaced ? PackFormCopy.replacedLine + " " + state : state
    }
}
