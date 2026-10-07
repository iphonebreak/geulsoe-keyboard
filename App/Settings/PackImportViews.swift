import SwiftUI
import UniformTypeIdentifiers
import PackImport
import TadakDomain

// 외부 채움글 1-c 4단계 — 가져오기 입구: 3-A 첫 화면 · 3-B 만드는 법 · 3-C 샘플 받기(6단계) · 3-D 파일 고르기 · 3-E 붙여넣기
// (계획서 `external-snippet-packs-1c-plan.md` 3-2절·5절 4·6행, 시안 `docs/design/external-snippet-packs/index.html` 3-A~3-E).
// 문구는 전부 `PackImportCopy` — 판(`PackCopySet`, 1.3.0은 CSV 전용판)이 바꾸는 줄도 그 표가 판에서 읽는다. 이 화면에 문구를 직접 쓰지 않는다
// (U6·금칙어·숫자·AC-35 검사가 `swift test`로 돈다 — AC-35 검색은 이 파일의 문자열도 본다).
// 고른 파일·붙인 글은 `PackImportFlowView`(4-A~4-I)가 읽는다.
//
// 보안: 파일 내용·붙인 글은 **메모리에만** 있다 — 로그·파일·분석 이벤트로 내보내지 않는다. 클립보드는 「붙여넣기」를 눌렀을 때만 읽는다(시스템
// `PasteButton` — 누르기 전에는 읽지 않고 확인 창도 없다). 샘플 받기는 번들의 고정 파일(가짜 내용)을 앱 임시 폴더에 보이는 이름으로 복사해
// 시스템 공유 시트로 넘긴다 — 사용자 입력은 담기지 않고, 무엇을 받았는지 기록하지 않는다.

/// 3-D 파일 선택기가 받는 형식 — 판을 따른다(`PackImportFileTypes`, 1-e ③): CSV 전용판은 `.csv`·`.tsv`·`.txt`(계획서 3-2절)만,
/// xlsx 중심판은 엑셀 통합 문서를 더한다. 나머지는 선택기에서 고를 수 없다
let packImportContentTypes: [UTType] = PackImportFileTypes.allowed(for: .selected)

// MARK: - 3-A 첫 화면

/// 「외부 채움글 추가」 — 주 버튼 하나(CSV 파일 가져오기) · 처음이라면(만드는 법 · 샘플 받기) · 그 밖의 방법(붙여넣기)
struct PackImportStartView: View {
    /// 가져오기를 마쳤다(4-M) — 채움글 화면으로 돌아가 그 팩 행을 강조한다(U5). 가져오기 시트가 **닫힌 뒤** 부른다
    let onFinished: @MainActor (_ packID: String) -> Void

    @State private var showsImporter = false
    @State private var request: PackImportRequest?
    /// 4-G 「다른 파일 고르기」 — 가져오기 시트가 닫힌 뒤 선택기를 다시 연다
    @State private var picksAgain = false
    /// 가져오기 시트가 완료를 알렸다 — 시트가 닫히면(버튼·끌어 내림) 목록으로
    @State private var completedPackID: String?
    /// 3-C 공유 시트에 넘길 샘플 사본(보이는 이름) — 준비되기 전·실패한 파일은 알약이 안 보인다
    @State private var sampleLinks: [PackSample.File: URL] = [:]

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text(PackImportCopy.heroTitle)
                        .font(.title3.weight(.semibold))
                    Text(PackImportCopy.heroMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    // 아이콘·글자를 직접 놓는다 — `Label`은 목록 행에서 아이콘이 강조색(버튼 바탕과 같은 색)으로 칠해져 평소엔 안 보이면서
                    // 자리만 차지했고, 큰 글자에서 글자가 「CSV 파」에서 잘렸다(화면 확인 N-6). 글자는 줄을 바꿔 다 보인다
                    Button {
                        showsImporter = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .accessibilityHidden(true)
                            Text(PackImportCopy.pickFile)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                NavigationLink {
                    PackImportGuideView()
                } label: {
                    Label(PackImportCopy.guideTitle, systemImage: "book")
                }
                ForEach(PackSample.Kind.allCases, id: \.self) { kind in
                    PackSampleRow(kind: kind, links: PackSample.files(kind).compactMap { file in sampleLinks[file].map { (file, $0) } })
                }
            } header: {
                Text(PackImportCopy.firstTimeHeader)
            }
            // 풋터(「샘플은 가짜 내용이에요 …」)는 뺐다(사장님 실기 2026-10-07)

            Section {
                // xlsx 중심판에만 — 주 버튼이 엑셀이라 CSV를 따로 둔다(CSV 전용판은 nil)
                if let row = PackImportCopy.otherFileRow {
                    Button {
                        showsImporter = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.title)
                                Text(row.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc")
                        }
                    }
                }
                NavigationLink {
                    PackPasteView(onFinished: onFinished)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(PackImportCopy.pasteTitle)
                            Text(PackImportCopy.pasteRowDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "doc.on.clipboard")
                    }
                }
            } header: {
                Text(PackImportCopy.otherWaysHeader)
            } footer: {
                // CSV 전용판은 풋터가 없다(「엑셀에서는 …」 통째로 뺐다, 사장님 실기 2026-10-07). xlsx 중심판만 받지 않는 파일 안내
                if let footer = PackImportCopy.startFooter {
                    Text(footer)
                }
            }
        }
        .settingsFormWidth()
        .navigationTitle(PackNoticeCopy.addPack)
        .navigationBarTitleDisplayMode(.inline)
        // 3-C — 샘플 사본을 메인 밖에서 만든다(고정 파일 2개, 수 KB)
        .task {
            sampleLinks = await PackSample.prepareForSharing(PackSample.Kind.allCases.flatMap { PackSample.files($0) })
        }
        // 3-D — 고르지 않고 닫으면 아무 일도 없다. 고른 파일은 아직 읽지 않는다(크기 확인·제한 읽기는 가져오기 시트가 메인 밖에서)
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: packImportContentTypes) { result in
            switch result {
            case .success(let url): request = PackImportRequest(origin: .file(url))
            case .failure: request = PackImportRequest(origin: .pickFailed)
            }
        }
        .sheet(item: $request, onDismiss: {
            if let packID = completedPackID {
                completedPackID = nil
                onFinished(packID)
            } else if picksAgain {
                picksAgain = false
                showsImporter = true
            }
        }) { request in
            PackImportFlowView(request: request) { exit in
                switch exit {
                case .pickAnotherFile: picksAgain = true
                case .completed(let packID): completedPackID = packID
                case .closed: break
                }
            }
        }
    }
}

// MARK: - 3-A 「처음이라면」 샘플 줄 · 3-C 샘플 받기

/// 번호형·문구형 샘플 한 줄 — 오른쪽 형식 알약(CSV판은 「CSV」 하나)을 누르면 그 파일로 시스템 공유 시트가 열린다(파일에 저장·AirDrop·메일…).
/// 받는 쪽에는 보이는 이름(「번호형 샘플.csv」)으로 남는다
private struct PackSampleRow: View {
    let kind: PackSample.Kind
    let links: [(file: PackSample.File, url: URL)]

    var body: some View {
        HStack(spacing: 8) {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text(PackImportCopy.sampleTitle(kind))
                    Text(PackImportCopy.sampleDetail(kind))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "arrow.down.doc")
            }
            Spacer(minLength: 8)
            ForEach(links, id: \.file) { link in
                ShareLink(item: link.url) {
                    Text(PackImportCopy.sampleFormatLabel(link.file.format))
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
                // 줄 전체가 아니라 알약만 눌린다(형식이 둘인 판에서 알약마다 따로)
                .buttonStyle(.borderless)
                .accessibilityLabel(PackImportCopy.sampleShareLabel(link.file))
            }
        }
    }
}

// MARK: - 3-B 만드는 법

/// 팩 만드는 법 — 글 중심 한 화면(시안 3-B). 시트 그림은 샘플과 같은 가짜 내용(U6). 제목·3절·4절 저장 방법은 판이 바꾼다 —
/// CSV 전용판의 3절은 PDR 6-7 안내(R20 — 바뀐 값은 파서가 모르므로 안내만). 칸의 글은 **문장마다 한 줄, 앞에 「·」**(R30 — 문구 표가 문장 배열)
struct PackImportGuideView: View {
    /// 문단 안 줄 간격 — 글 중심 화면인데 기본 행간이 좁아 보였다(사장님 실기 2026-10-07). 본문 크기에 맞춰 늘어 큰 글자에서도 비율이 같다
    @ScaledMetric(relativeTo: .body) private var lineGap: CGFloat = 4
    /// 항목(행) 위아래 여백 — 같은 이유. 3절처럼 한 절에 줄이 여럿이면 줄 사이가 이만큼씩 더 벌어진다
    @ScaledMetric(relativeTo: .body) private var rowGap: CGFloat = 4
    /// 문장(「·」 줄) 사이 — 한 문장이 줄바꿈된 행간(`lineGap`)보다 조금 넓게 둬 문장 경계가 보이게
    @ScaledMetric(relativeTo: .body) private var sentenceGap: CGFloat = 6

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    sheetGrid
                    GuideSentences(sentences: PackImportCopy.guideColumns, spacing: sentenceGap)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, rowGap)
            } header: {
                Text(numbered(1, PackImportCopy.guideHeaderSection))
            }

            Section {
                GuideSentences(sentences: PackImportCopy.guideMeta, spacing: sentenceGap)
                    .padding(.vertical, rowGap)
            } header: {
                Text(numbered(2, PackImportCopy.guideMetaSection))
            }

            Section {
                ForEach(PackImportCopy.guideCells, id: \.self) { cell in
                    GuideSentences(sentences: cell, spacing: sentenceGap)
                        .padding(.vertical, rowGap)
                }
            } header: {
                Text(numbered(3, PackImportCopy.guideCellsSection))
            } footer: {
                Text(PackImportCopy.guideCellsFooter)
            }

            Section {
                GuideSentences(sentences: PackImportCopy.guideSave, spacing: sentenceGap)
                    .padding(.vertical, rowGap)
            } header: {
                Text(numbered(4, PackImportCopy.guideSaveSection))
            }
        }
        // 화면 전체(행·머리·풋터)의 여러 줄 글에 — 한 줄짜리(시트 그림 칸)에는 영향이 없다
        .lineSpacing(lineGap)
        .settingsFormWidth()
        .navigationTitle(PackImportCopy.guideTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numbered(_ index: Int, _ title: String) -> String { "\(index). \(title)" }

    /// 스프레드시트 모양 — 열 머리(A·B·C)와 행 번호, 정보 줄(#…)은 파랑, 머리글 행은 굵게
    private var sheetGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                Text(verbatim: "")
                ForEach(["A", "B", "C"], id: \.self) { column in
                    Text(verbatim: column).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(PackImportCopy.guideSheet.enumerated()), id: \.offset) { index, row in
                GridRow {
                    Text(verbatim: "\(index + 1)").foregroundStyle(.secondary)
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell)
                            .fontWeight(index == PackImportCopy.guideSheetHeaderRow ? .semibold : .regular)
                            .foregroundStyle(cell.hasPrefix("#") ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }
}

/// 만드는 법 한 칸 — 문장마다 한 줄, 앞에 「·」(R30). 머리점과 글을 **따로 놓아**(HStack) 문장이 줄바꿈돼도 둘째 줄이 글 첫 글자에 맞춰
/// 들어간다 — 「·」를 글자에 붙이면 큰 글자에서 둘째 줄이 머리점 밑으로 파고든다. 머리점은 VoiceOver가 읽지 않고, 칸 전체를 한 번에 읽는다
private struct GuideSentences: View {
    let sentences: [String]
    let spacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(Array(sentences.enumerated()), id: \.offset) { _, sentence in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    Text(sentence)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 3-E 붙여넣기

/// 붙여넣기로 가져오기 — 큰 입력칸 + 「붙여넣기」(누를 때만 클립보드를 읽는다) + 「읽기」. 붙여 넣은 글은 이미 글자라 인코딩 확인이 없다.
/// 글은 **이 화면 메모리에만** 있다 — 화면을 떠나면 비운다. 직접 쳐서 고칠 수도 있다
struct PackPasteView: View {
    /// 가져오기를 마쳤다 — 채움글 화면으로(`PackImportStartView.onFinished`와 같다)
    let onFinished: @MainActor (_ packID: String) -> Void

    @State private var text = ""
    @State private var overview: PackPasteOverview?
    @State private var request: PackImportRequest?
    @State private var completedPackID: String?

    var body: some View {
        Form {
            Section {
                // 높이 상한 — 넘는 글은 칸 안에서 스크롤한다. 상한이 없으면 칸이 글 길이만큼 늘어 3MB 글이면 화면이 516쪽이 되고
                // 아래 개요 줄·「모두 지우기」·「붙여넣기」·「읽기」에 닿으려면 끝까지 내려야 했다(화면 확인 N-5)
                TextEditor(text: $text)
                    .font(.callout.monospaced())
                    .frame(minHeight: 250, maxHeight: 360)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !text.isEmpty {
                    HStack {
                        if let overview {
                            Text(PackImportCopy.pasteSummary(lines: overview.lines, delimiter: overview.delimiter))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(PackImportCopy.clearButton) { text = "" }
                            .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
            } header: {
                Text(PackImportCopy.pasteHeader)
            } footer: {
                Text(PackImportCopy.pasteFooter)
            }

            Section {
                // 시스템 붙여넣기 — 사용자가 누를 때만 클립보드를 읽는다(확인 창 없음)
                PasteButton(payloadType: String.self) { strings in
                    text = strings.joined(separator: "\n")
                }
                .frame(maxWidth: .infinity)
                Button(action: read) {
                    Text(PackImportCopy.readButton)
                        .frame(maxWidth: .infinity)
                }
                .disabled(text.isEmpty)
            } footer: {
                Text(PackImportCopy.pastePrivacy)
            }
        }
        .settingsFormWidth()
        .navigationTitle(PackImportCopy.pasteTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(PackImportCopy.readButton, action: read)
                    .disabled(text.isEmpty)
            }
        }
        // 줄 수·칸 나누기 — 앞부분만 보는 후보 시험이라 가볍지만 큰 글은 메인 밖에서. 그 사이 글이 또 바뀌면 이 작업은 취소되고
        // 늦은 결과는 버린다(nil — 검증 F-8 ③)
        .task(id: text) {
            guard !text.isEmpty else {
                overview = nil
                return
            }
            if let measured = await PackPasteOverview.perform(text) { overview = measured }
        }
        .sheet(item: $request, onDismiss: {
            guard let packID = completedPackID else { return }
            completedPackID = nil
            onFinished(packID)
        }) { request in
            PackImportFlowView(request: request) { exit in
                guard case .completed(let packID) = exit else { return }
                // 가져왔으면 붙여 넣은 글(클립보드에서 온 내용)을 바로 비운다 — 메모리에만, 완료 때 비움
                text = ""
                overview = nil
                completedPackID = packID
            }
        }
        // 화면을 떠나면 붙인 글을 비운다(메모리에만, 취소·완료 때 비움)
        .onDisappear {
            text = ""
            overview = nil
        }
    }

    private func read() {
        guard !text.isEmpty else { return }
        request = PackImportRequest(origin: .paste(text))
    }
}

