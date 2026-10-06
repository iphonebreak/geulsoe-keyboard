import SwiftUI
import UniformTypeIdentifiers
import PackImport
import TadakDomain

// 외부 채움글 1-c 4단계 — 가져오기 입구: 3-A 첫 화면 · 3-B 만드는 법 · 3-D 파일 고르기 · 3-E 붙여넣기
// (계획서 `external-snippet-packs-1c-plan.md` 3-2절·5절 4행, 시안 `docs/design/external-snippet-packs/index.html` 3-A·3-B·3-D·3-E — **CSV 전용판**).
// 고른 파일·붙인 글은 `PackImportFlowView`(4-A~4-I)가 읽는다. 문구는 전부 `PackImportCopy`(U6·금칙어·숫자 검사가 `swift test`로 돈다).
//
// 보안: 파일 내용·붙인 글은 **메모리에만** 있다 — 로그·파일·분석 이벤트로 내보내지 않는다. 클립보드는 「붙여넣기」를 눌렀을 때만 읽는다(시스템
// `PasteButton` — 누르기 전에는 읽지 않고 확인 창도 없다). 샘플 받기(3-C)는 6단계, xlsx는 1-e라 이 화면에 없다.

/// 3-D 파일 선택기가 받는 형식 — `.csv`·`.tsv`·`.txt`(계획서 3-2절). 나머지는 선택기에서 고를 수 없다
let packImportContentTypes: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText]

// MARK: - 3-A 첫 화면

/// 「외부 채움글 추가」 — 주 버튼 하나(CSV 파일 고르기) · 처음이라면(만드는 법) · 그 밖의 방법(붙여넣기) · 받지 않는 파일 안내
struct PackImportStartView: View {
    /// 가져오기를 마쳤다(4-M) — 채움글 화면으로 돌아가 그 팩 행을 강조한다(U5). 가져오기 시트가 **닫힌 뒤** 부른다
    let onFinished: @MainActor (_ packID: String) -> Void

    @State private var showsImporter = false
    @State private var request: PackImportRequest?
    /// 4-G 「다른 파일 고르기」 — 가져오기 시트가 닫힌 뒤 선택기를 다시 연다
    @State private var picksAgain = false
    /// 가져오기 시트가 완료를 알렸다 — 시트가 닫히면(버튼·끌어 내림) 목록으로
    @State private var completedPackID: String?

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
                    Button {
                        showsImporter = true
                    } label: {
                        Label(PackImportCopy.pickFile, systemImage: "folder")
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
            } header: {
                Text(PackImportCopy.firstTimeHeader)
            }

            Section {
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
                Text(PackImportCopy.startFooter)
            }
        }
        .settingsFormWidth()
        .navigationTitle(PackNoticeCopy.addPack)
        .navigationBarTitleDisplayMode(.inline)
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

// MARK: - 3-B 만드는 법

/// CSV로 팩 만드는 법 — 글 중심 한 화면(시안 3-B CSV판). 시트 그림은 샘플과 같은 가짜 내용(U6).
/// 「이런 칸」 절은 PDR 6-7의 CSV 전용판 안내(R20 — 바뀐 값은 파서가 모르므로 안내만)로 바꿨다
struct PackImportGuideView: View {
    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    sheetGrid
                    Text(PackImportCopy.guideColumns)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text(numbered(1, PackImportCopy.guideHeaderSection))
            }

            Section {
                Text(PackImportCopy.guideMeta)
            } header: {
                Text(numbered(2, PackImportCopy.guideMetaSection))
            }

            Section {
                ForEach(PackImportCopy.guideCells, id: \.self) { line in
                    Text(line)
                }
            } header: {
                Text(numbered(3, PackImportCopy.guideCellsSection))
            } footer: {
                Text(PackImportCopy.guideCellsFooter)
            }

            Section {
                Text(PackImportCopy.guideSave)
            } header: {
                Text(numbered(4, PackImportCopy.guideSaveSection))
            }
        }
        .settingsFormWidth()
        .navigationTitle(PackImportCopy.guideTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numbered(_ index: Int, _ title: String) -> String { "\(index). \(title)" }

    /// 스프레드시트 모양 — 열 머리(A·B·C)와 행 번호, 정보 줄(#…)은 파랑, 머리글 행은 굵게
    private var sheetGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
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

// MARK: - 3-E 붙여넣기

/// 붙여넣기로 가져오기 — 큰 입력칸 + 「붙여넣기」(누를 때만 클립보드를 읽는다) + 「읽기」. 붙여 넣은 글은 이미 글자라 인코딩 확인이 없다.
/// 글은 **이 화면 메모리에만** 있다 — 화면을 떠나면 비운다. 직접 쳐서 고칠 수도 있다
struct PackPasteView: View {
    /// 가져오기를 마쳤다 — 채움글 화면으로(`PackImportStartView.onFinished`와 같다)
    let onFinished: @MainActor (_ packID: String) -> Void

    @State private var text = ""
    @State private var overview: PasteOverview?
    @State private var request: PackImportRequest?
    @State private var completedPackID: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .font(.callout.monospaced())
                    .frame(minHeight: 250)
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
        // 줄 수·칸 나누기 — 앞부분만 보는 후보 시험이라 가볍지만 큰 글은 메인 밖에서
        .task(id: text) {
            overview = text.isEmpty ? nil : await PasteOverview.of(text)
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

/// 붙인 글의 줄 수와, 하나로 정해지면 칸 나누기(시안 3-E 「42줄 · 칸 나누기: 탭」)
private struct PasteOverview: Equatable, Sendable {
    let lines: Int
    let delimiter: CSVDelimiter?

    static func of(_ text: String) async -> PasteOverview {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let breaks = text.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
                let lines = breaks + (text.hasSuffix("\n") ? 0 : 1)
                continuation.resume(returning: PasteOverview(lines: lines, delimiter: PackImporter.likelyDelimiter(text)))
            }
        }
    }
}
