import SwiftUI
import TadakDomain
import TadakData

/// 채움글 설정 — 전체 on/off, 내장 팩 on/off, 내 문구 관리.
///
/// 내 문구는 App Group에 앱이 쓰고 키보드가 읽는다 (단방향 — 권한 불필요).
/// 키보드는 표시될 때마다 매처를 다시 만들므로 다음 키보드 표시부터 반영된다.
struct SnippetSettingsView: View {

    @Binding var settings: KeyboardSettings

    @State private var userSnippets: [SnippetEntry] = []
    @State private var showsEditor = false

    private let repository = AppGroupSnippetRepository()

    var body: some View {
        Form {
            // 안내 애니메이션 — 타이핑 → 칩 → 치환을 반복 재생 (PDR snippet-intro-animation).
            // 인셋 0·행 배경 투명: 확대된 캔버스가 행 가장자리까지 닿으므로 카드가 스스로 모서리를 그리고 클립한다
            Section {
                SnippetIntroAnimationView(
                    themeID: settings.selectedThemeID,
                    appearance: settings.appearance,
                    showsKeyPreview: settings.showsKeyPreview,
                    showsLongPressHints: settings.longPressSymbolsEnabled
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("채움글 사용", isOn: $settings.snippetsEnabled)
            } footer: {
                Text("트리거 문구를 치면 전문이 툴바 후보로 떠요. 예) \"창세기 1장 1절\", \"창 1:1\", \"애국가 1절\", \"새해인사\", \"헌법 전문\"")
            }

            Section {
                ForEach(SnippetPackInfo.all, id: \.id) { pack in
                    NavigationLink {
                        SnippetPackDetailView(pack: pack, settings: $settings)
                    } label: {
                        LabeledContent(pack.name, value: packBinding(pack.id).wrappedValue ? "켬" : "끔")
                    }
                }
            } header: {
                Text("내장 팩")
            } footer: {
                Text("팩을 누르면 설명과 사용법, 켜기/끄기가 나와요.")
            }
            .disabled(!settings.snippetsEnabled)

            Section {
                ForEach(userSnippets, id: \.trigger) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                        Text("트리거: \(entry.trigger)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteSnippets)

                Button("문구 추가") { showsEditor = true }
            } header: {
                Text("내 문구")
            } footer: {
                Text("트리거와 같은 문구를 치면 본문 전문이 후보로 떠요. 같은 트리거로 저장하면 기존 문구를 바꿔요.")
            }
            .disabled(!settings.snippetsEnabled)
        }
        .settingsFormWidth()
        .navigationTitle("채움글")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 저장분에 중복 트리거가 있으면(외부 쓰기·스키마 진화) ForEach id가 겹친다 — 방어 dedup
            var seen = Set<String>()
            userSnippets = repository.entries().filter { seen.insert($0.trigger).inserted }
        }
        .sheet(isPresented: $showsEditor) {
            SnippetEditorView { entry in
                userSnippets.removeAll { $0.trigger == entry.trigger }
                userSnippets.append(entry)
                repository.save(userSnippets)
                SettingsChangeNotifier.post()  // 떠 있는 키보드의 매처를 즉시 갱신
            }
        }
    }

    private func packBinding(_ packID: String) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledSnippetPacks.contains(packID) },
            set: { enabled in
                if enabled {
                    settings.disabledSnippetPacks.removeAll { $0 == packID }
                } else if !settings.disabledSnippetPacks.contains(packID) {
                    settings.disabledSnippetPacks.append(packID)
                }
            }
        )
    }

    private func deleteSnippets(at offsets: IndexSet) {
        userSnippets.remove(atOffsets: offsets)
        repository.save(userSnippets)
        SettingsChangeNotifier.post()
    }
}

/// 새 문구 입력 시트. 트리거·본문이 비면 저장할 수 없다.
private struct SnippetEditorView: View {

    let onSave: (SnippetEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var trigger = ""
    @State private var title = ""
    @State private var body_ = ""

    /// 키보드의 입력 꼬리 상한(48자)보다 긴 트리거는 절대 발동하지 않는 죽은 항목이 된다 —
    /// 여유를 두고 40자로 막는다 (리뷰 반영).
    private static let triggerLimit = 40

    private var trimmedTrigger: String {
        trigger.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedBody: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var triggerTooLong: Bool {
        trimmedTrigger.count > Self.triggerLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("예: 우리집 주소", text: $trigger)
                } header: {
                    Text("트리거")
                } footer: {
                    if triggerTooLong {
                        Text("트리거는 \(Self.triggerLimit)자 이하여야 해요.")
                            .foregroundStyle(.red)
                    }
                }
                Section("제목 (후보에 표시)") {
                    TextField("비우면 트리거를 써요", text: $title)
                }
                Section("본문") {
                    TextField("삽입될 전문", text: $body_, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .settingsFormWidth()
            .navigationTitle("문구 추가")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(SnippetEntry(
                            trigger: trimmedTrigger,
                            title: heading.isEmpty ? trimmedTrigger : heading,
                            body: trimmedBody
                        ))
                        dismiss()
                    }
                    .disabled(trimmedTrigger.isEmpty || trimmedBody.isEmpty || triggerTooLong)
                }
            }
        }
    }
}

// MARK: - 내장 팩 상세 (설명 · 사용법 · 켜기/끄기, 성경은 머리말 스위치)

/// 내장 팩의 설명·사용법 — 데이터(Snippets.json 등)와 짝을 이루는 안내. 트리거는 팩 JSON과 같게 유지한다.
struct SnippetPackInfo {
    let id: String
    let name: String
    let summary: String
    let usage: [(trigger: String, result: String)]
    let note: String?

    static let all: [SnippetPackInfo] = [
        SnippetPackInfo(
            id: SnippetPack.bible, name: "성경 (개역한글)",
            summary: "개역한글판(1961) 성경 66권 전체가 들어 있어요. 책 이름과 장·절을 치면 그 절의 본문이 후보로 떠요. 저작권 보호 기간이 만료된 본문이라 자유롭게 쓸 수 있어요.",
            usage: [
                ("창세기 1장 1절", "정식 이름 + 장·절"),
                ("창 1:1", "약칭 + 콜론"),
                ("요한복음3장16절", "띄어쓰기 없이도 돼요"),
                ("계시록 21:4", "통용 별칭도 받아요")
            ],
            note: "머리말을 켜면 본문 앞에 [창세기 1:1] 처럼 출처가 함께 들어가요."),
        SnippetPackInfo(
            id: SnippetPack.anthem, name: "국가 상징문",
            summary: "애국가 1~4절, 국기에 대한 맹세, 대한민국 헌법 전문과 제1조부터 제130조까지 전 조문, 기미독립선언서 서두를 담았어요. 공유 저작물과 저작권 보호를 받지 않는 공공 저작물이에요.",
            usage: [
                ("애국가 1절", "1절부터 4절까지"),
                ("국기에 대한 맹세", "또는 \"국기맹세\""),
                ("헌법 전문", "또는 \"헌법전문\""),
                ("헌법 10조", "또는 \"헌법 제10조\" — 1조부터 130조까지 전부"),
                ("독립선언서", "또는 \"기미독립선언서\" — 서두 두 문장")
            ],
            note: nil),
        SnippetPackInfo(
            id: SnippetPack.greetings, name: "인사·상용구",
            summary: "인사, 축하, 위로·기원, 감사·사과처럼 자주 보내는 문구 25종이에요. 글쇠가 직접 쓴 일반형 문구라 붙여 넣은 뒤 이름이나 상황에 맞게 고쳐 쓰세요.",
            usage: [
                ("인사", "새해인사 · 설날인사 · 추석인사 · 명절인사 · 연말인사 · 크리스마스인사 · 첫인사 · 안부인사 · 입사인사 · 퇴사인사 · 어버이날인사 · 스승의날인사"),
                ("축하 문구", "생일축하 · 결혼축하 · 출산축하 · 합격축하 · 입학축하 · 졸업축하 · 승진축하 · 개업축하"),
                ("위로·기원", "쾌유기원 · 조의문 · 조문답례"),
                ("감사·사과", "감사인사 · 사과문")
            ],
            note: "\"새해인사\"처럼 붙여 쓰거나 \"새해 인사\"처럼 띄어 써도 돼요.")
    ]
}

struct SnippetPackDetailView: View {

    let pack: SnippetPackInfo
    @Binding var settings: KeyboardSettings

    var body: some View {
        Form {
            Section {
                Toggle("이 팩 사용", isOn: enabledBinding)
                if pack.id == SnippetPack.bible {
                    // 삽입 텍스트 앞의 출처 머리말 — 키보드 매처가 설정을 읽어 붙인다 (SnippetMatcher biblePrefix)
                    Toggle("출처 머리말 넣기", isOn: $settings.bibleSnippetPrefixEnabled)
                        .disabled(!enabledBinding.wrappedValue)
                }
            } footer: {
                if let note = pack.note { Text(note) }
            }

            Section("설명") {
                Text(pack.summary)
                    .font(.callout)
            }

            Section {
                ForEach(Array(pack.usage.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.trigger)
                            .font(.body.monospacedDigit())
                        Text(item.result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("사용법")
            } footer: {
                Text("트리거를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 트리거가 전문으로 바뀌어요.")
            }
        }
        .settingsFormWidth()
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { !settings.disabledSnippetPacks.contains(pack.id) },
            set: { enabled in
                if enabled {
                    settings.disabledSnippetPacks.removeAll { $0 == pack.id }
                } else if !settings.disabledSnippetPacks.contains(pack.id) {
                    settings.disabledSnippetPacks.append(pack.id)
                }
            }
        )
    }
}
