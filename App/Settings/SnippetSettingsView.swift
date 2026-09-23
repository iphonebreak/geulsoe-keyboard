import SwiftUI
import TadakDomain
import TadakData

/// 채움글 설정 — 전체 on/off, 내장 팩 on/off, 내 채움글 관리(추가·고치기·삭제).
///
/// 내 채움글은 App Group에 앱이 쓰고 키보드가 읽는다 (단방향 — 권한 불필요).
/// 키보드는 표시될 때마다 매처를 다시 만들므로 다음 키보드 표시부터 반영된다.
struct SnippetSettingsView: View {

    @Binding var settings: KeyboardSettings

    @State private var userSnippets: [SnippetEntry] = []
    @State private var showsEditor = false
    /// 고치는 중인 항목. nil이면 **추가**다 — 시트 하나가 두 모드를 다 맡는다.
    @State private var editingEntry: EditingSnippet?

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
                Text("단축어를 치면 전문이 툴바 후보로 떠요. 예) \"창세기 1장 1절\", \"창 1:1\", \"애국가 1절\", \"새해인사\", \"헌법 전문\"")
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
                // **id 는 정규화 단축어를 이어 붙인 것**이다. `\.trigger` 는 더 이상 없고,
                // 단축어가 여럿이라 하나만 쓰면 서로 다른 항목이 같은 id 를 가질 수 있다.
                ForEach(userSnippets, id: \.snippetListID) { entry in
                    // ★ **행을 눌러 고친다** (사장님 결정 2026-09-23).
                    //
                    // 전에는 추가와 삭제만 됐다 — 단축어 하나를 더하려면 **지우고 본문까지
                    // 다시 쳐야** 했고, 단축어를 여럿 둘 수 있게 되면서 더 아쉬워졌다.
                    //
                    // ★ `Button`이라 **스와이프 삭제와 부딪히지 않는다** — `.onDelete`는 행의
                    //   스와이프 제스처에 붙고 탭은 버튼이 먹는다. `.contentShape`로 빈 자리까지
                    //   누를 수 있게 한다(제목이 짧을 때 오른쪽 여백이 죽은 자리가 되지 않게).
                    Button {
                        editingEntry = EditingSnippet(entry: entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
                                Text("단축어: \(entry.triggers.joined(separator: ", "))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("고치기")
                }
                .onDelete(perform: deleteSnippets)

                Button("채움글 추가") { showsEditor = true }
            } header: {
                Text("내 채움글")
            } footer: {
                Text("단축어를 치면 본문 전문이 후보로 떠요. 띄어쓰기는 달라도 돼요.\n겹치는 단축어가 있으면 그 문구를 바꿔요.")
            }
            .disabled(!settings.snippetsEnabled)
        }
        .settingsFormWidth()
        .navigationTitle("채움글")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 저장분에 중복 단축어가 있으면(외부 쓰기·스키마 진화) ForEach id가 겹친다 — 방어 dedup.
            // 기준은 **정규화 단축어**다 — "우리집주소"와 "우리집 주소"는 같은 것으로 본다.
            var seen = Set<String>()
            userSnippets = repository.entries().filter { seen.insert($0.snippetListID).inserted }
        }
        .sheet(isPresented: $showsEditor) {
            SnippetEditorView(editing: nil, onSave: save)
        }
        // ★ **같은 시트를 고치기에도 쓴다** — 새로 만들지 않는다.
        //   `item:` 형태라 고를 때마다 시트가 그 항목으로 새로 만들어진다
        //   (`isPresented:`를 쓰면 `@State` 초기값이 첫 항목에 굳는다).
        .sheet(item: $editingEntry) { editing in
            SnippetEditorView(editing: editing.entry, onSave: save)
        }
    }

    /// 추가·고치기가 **같은 경로로** 저장한다.
    ///
    /// ## ★ 덮어쓰기는 이미 여기 있었다
    ///
    /// *정규화 단축어가 하나라도 겹치는 기존 항목을 교체한다* — 한쪽만 겹쳐도 둘 다 남겨 두면
    /// 어느 쪽이 발동할지 사용자가 알 수 없기 때문이다. **고치기가 그 규칙을 그대로 탄다** —
    /// 단축어를 그대로 두고 본문만 바꾸면 자기 자신이 교체되고, 단축어를 전부 갈면
    /// 새 항목이 된다(옛 것은 아래 `editing` 제거가 치운다).
    ///
    /// ★ 단축어 파싱은 **`SnippetEntry.parseTriggers` 한 곳**이다 — 새 파서를 쓰면
    /// 중복 제거·정규화 규칙이 갈린다.
    private func save(_ entry: SnippetEntry, editing original: SnippetEntry?) {
        // ★ 규칙은 `SnippetEntry.applying(_:editing:to:)`에 있다 — **여기 두면 테스트가 못 닿는다.**
        //   그래서 「고치면 자리가 맨 뒤로 튄다」를 아무도 못 잡았다(검증자 2026-09-23).
        //   추가는 맨 뒤, 편집은 **제자리**다. 겹쳐 지워진 항목만큼의 인덱스 보정도 거기 있다.
        userSnippets = SnippetEntry.applying(entry, editing: original, to: userSnippets)
        repository.save(userSnippets)
        SettingsChangeNotifier.post()  // 떠 있는 키보드의 매처를 즉시 갱신
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

/// 새 문구 입력 시트. **단축어 하나 이상 + 본문**이 있어야 저장된다.
///
/// ## 순서는 제목 → 단축어 → 본문이다 (사장님 결정 2026-09-15)
///
/// 예전엔 단축어가 맨 위였는데, 사용자가 먼저 정하는 것은 "이게 무슨 문구인가"(제목)다.
///
/// ## 단축어를 여럿 등록한다 — 구분자는 쉼표
///
/// **그래서 단축어 안에 쉼표를 넣을 수 없다.** 쉼표를 이스케이프하는 문법을 만들면 그걸 다시
/// 설명해야 한다 — 채움글 단축어에 쉼표가 필요한 경우가 드물어 그 한계를 받아들였다.
/// `.sheet(item:)`에 실을 **식별 가능한 포장**.
///
/// ★ `SnippetEntry`에 `Identifiable`을 붙이지 않는다 — id의 기준(`snippetListID`,
/// 정규화 단축어를 이어 붙인 값)은 **이 화면의 목록 사정**이지 도메인 개념이 아니다.
/// 도메인에 붙이면 다른 곳에서 그 id를 의미 있는 것으로 오해한다.
private struct EditingSnippet: Identifiable {
    let entry: SnippetEntry
    var id: String { entry.snippetListID }
}

private struct SnippetEditorView: View {

    /// 고치는 중인 항목. nil이면 **추가**다.
    let editing: SnippetEntry?

    /// ★ **불러온 단축어에 쉼표가 있었는가** — 저장하면 **쪼개진다.**
    ///
    /// v1.0.1까지 편집기는 단축어 칸이 하나였고 쉼표를 막지 않았다
    /// (`git log` 확인 2026-09-23). 그 시절 저장분의 `"가,나"`는 디코더가 **한 단축어로** 싣는데,
    /// 지금 편집기는 쉼표를 구분자로 보므로 **열었다 저장만 해도 둘로 갈린다** —
    /// 게다가 발동 범위가 넓어진다(`"가,나"` 하나가 `"가"`·`"나"` 둘이 되어 아무 데서나 뜬다).
    ///
    /// ★ **마이그레이션으로 조용히 바꾸지 않는다.** 사용자가 등록한 값을 우리가 해석해
    /// 덮어쓰는 것이고 되돌릴 근거도 안 남는다. **알리고 사용자가 정한다** — 저장도 막지 않는다.
    private var loadedCommaTrigger: Bool { editing?.hasCommaInTrigger ?? false }
    let onSave: (SnippetEntry, SnippetEntry?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var triggerText: String
    @State private var title: String
    @State private var body_: String

    /// ★ 불러올 때 **쉼표로 합치고**, 저장할 때 `SnippetEntry.parseTriggers`가 **쉼표로 나눈다** —
    /// 왕복이 같은 규약을 탄다. 구분자를 여기서 새로 정하지 않는다.
    init(editing: SnippetEntry?, onSave: @escaping (SnippetEntry, SnippetEntry?) -> Void) {
        self.editing = editing
        self.onSave = onSave
        _triggerText = State(initialValue: editing?.triggers.joined(separator: ", ") ?? "")
        _title = State(initialValue: editing?.title ?? "")
        _body_ = State(initialValue: editing?.body ?? "")
    }

    /// 키보드의 입력 꼬리 상한(48자)보다 긴 단축어는 절대 발동하지 않는 죽은 항목이 된다 —
    /// 여유를 두고 40자로 막는다 (리뷰 반영). **정규화 전 원문 기준**이다.
    private static let triggerLimit = 40
    /// 한 문구에 등록할 수 있는 단축어 개수 상한.
    private static let triggerCountLimit = 10

    /// 입력 문자열을 단축어 목록으로 —
    /// 쉼표로 나누고 각각 trim, 빈 것 제거, **정규화 기준 중복 제거**("집주소"와 "집 주소"는 하나).
    ///
    /// 규칙 자체는 `SnippetEntry.parseTriggers` 에 있다 — 뷰 안의 `private var` 라
    /// 테스트가 닿지 않던 것을 도메인으로 옮겼다 (2026-09-15). **여기서 다시 구현하지 않는다.**
    private var parsedTriggers: [String] {
        SnippetEntry.parseTriggers(triggerText)
    }
    private var trimmedBody: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var tooLong: Bool {
        parsedTriggers.contains { $0.count > Self.triggerLimit }
            || parsedTriggers.count > Self.triggerCountLimit
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목 (후보에 표시)") {
                    TextField("비우면 단축어를 써요", text: $title)
                }
                Section {
                    TextField("예: 우리집주소, 집주소", text: $triggerText)
                } header: {
                    Text("단축어")
                } footer: {
                    if tooLong {
                        Text("단축어는 하나에 \(Self.triggerLimit)자 이하, \(Self.triggerCountLimit)개까지예요.")
                            .foregroundStyle(.red)
                    } else if loadedCommaTrigger {
                        // 문구를 짧게 둔다 — 무슨 일이 일어나는지와 무엇을 하면 되는지만.
                        Text("이 단축어에 쉼표가 들어 있어요. 저장하면 쉼표를 기준으로 나뉘어요.\n"
                             + "하나로 두려면 쉼표를 지우세요.")
                            .foregroundStyle(.orange)
                    } else {
                        Text("쉼표(,)로 여러 개를 등록해요. 띄어쓰기는 달라도 돼요.")
                    }
                }
                Section("본문") {
                    TextField("삽입될 전문", text: $body_, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .settingsFormWidth()
            // ★ 추가와 고치기가 같은 시트를 쓰므로 **제목이 갈려야 한다.**
            //   항상 「채움글 추가」면 고칠 때 틀린 말이 된다.
            //   「고치기」는 이 화면의 다른 문구(「~어요」·「채움글 추가」)와 같은 결의 우리말이고,
            //   「편집」·「수정」보다 짧아 좁은 제목 자리에 맞다.
            .navigationTitle(editing == nil ? "채움글 추가" : "채움글 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let triggers = parsedTriggers
                        onSave(SnippetEntry(
                            triggers: triggers,
                            // 제목을 비우면 **첫 단축어**가 제목이 된다
                            title: heading.isEmpty ? (triggers.first ?? "") : heading,
                            body: trimmedBody
                        ), editing)
                        dismiss()
                    }
                    .disabled(parsedTriggers.isEmpty || trimmedBody.isEmpty || tooLong)
                }
            }
        }
    }
}

// MARK: - 내장 팩 상세 (설명 · 사용법 · 켜기/끄기, 성경은 머리말 스위치)

/// 내장 팩의 설명·사용법 — 데이터(Snippets.json 등)와 짝을 이루는 안내. 단축어는 팩 JSON과 같게 유지한다.
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
            note: "머리말을 켜면 본문 앞에 출처가 함께 들어가요. \"창세기 1장 1절\"이라고 치면 [창세기 1장 1절] 처럼 친 그대로 들어가요."),
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
                    // ★ 설명을 **스위치마다** 붙인다 (사용자 지시 2026-09-21).
                    //
                    // 예전에는 설명 셋이 Section 바닥 footer에 뭉쳐 있어 **어느 설명이 어느
                    // 스위치 것인지** 알기 어려웠다. 제목 + 설명 두 줄로 각 행 안에 넣는다.
                    // 스타일은 이 저장소의 보조 문구 관례를 그대로 쓴다
                    // (`.font(.footnote)` + `.foregroundStyle(.secondary)`).

                    // 삽입 텍스트 앞의 출처 머리말 — 키보드 매처가 설정을 읽어 붙인다 (SnippetMatcher biblePrefix)
                    Toggle(isOn: $settings.bibleSnippetPrefixEnabled) {
                        switchLabel(
                            "출처 머리말 넣기",
                            // 문구는 옮기기만 한다 — `pack.note`에 있던 그대로다
                            pack.note ?? ""
                        )
                    }
                    .disabled(!enabledBinding.wrappedValue)

                    // 성경 키워드 검색 — 자리를 툴바 탭에서 여기로 옮겼다 (사용자 지시 2026-09-21).
                    //
                    // 화면 제목이 이미 「성경 (개역한글)」이라 「성경」을 다시 붙이지 않는다.
                    //
                    // **「이 팩 사용」이 꺼지면 함께 흐려진다** — 합성 게이트
                    // (`KeyboardViewController.canSearchBible`)가 `disabledSnippetPacks`를 보므로
                    // 팩이 꺼진 채로는 켜도 동작하지 않는다. **켤 수 있는데 안 도는 스위치는 거짓말이다.**
                    //
                    // 값 자체는 독립 `Bool`이라 팩을 껐다 켜도 **보존된다**(`bibleSearchEnabled`).
                    //
                    // ★ **설명을 한 줄로 줄였다** (사용자 지시 2026-09-22: "여기까지만 써라").
                    //
                    // 지운 두 문장이 담고 있던 것:
                    // (가) 「주소를 치는 단축어와는 다른 기능이에요」 — 이름이 「구절 찾기」에서
                    //      **「단어로 구절 찾기」**가 되면서 **이름 자체가 그 구분을 한다.**
                    // (나) 「네 글자 이상 붙여 쓰면 띄어쓰기가 달라도」 — 전날 「거짓 약속」이라고
                    //      좁힌 바로 그 문장이다. 지금 문구는 **띄어쓰기를 아예 언급하지 않는다** →
                    //      약속하지 않으므로 거짓이 아니다. 대신 사용자가 「왜 내것은 안 되나」를
                    //      물을 수 있고, 그 답은 `bible-space-insensitive-search.md`에 있다.
                    //
                    // 사용자 원문의 「단어을」은 **「단어를」로 바로잡아 썼다** — UI 문구다.
                    //
                    // ★ **제목을 박지 않는다** (2026-09-22). 툴바 도구 목록의 이름과
                    //   **같은 문자열이어야 한다** — 설정에서 켠 것과 툴바에 보이는 것이
                    //   같은 기능임을 알아볼 수 있어야 하기 때문이다. 이름이 이미 두 번
                    //   바뀌었고 그때마다 두 곳을 따로 고쳤다.
                    Toggle(isOn: $settings.bibleSearchEnabled) {
                        switchLabel(
                            ToolbarTool.bibleSearch.displayName,
                            "「사랑」처럼 단어를 치면 그 단어가 든 구절을 툴바에서 찾아 줘요."
                        )
                    }
                    .disabled(!enabledBinding.wrappedValue)
                }
            } footer: {
                // 스위치 하나의 설명이 아니라 **Section 전체의 상태 안내**다 — 그래서 여기 남는다.
                if pack.id == SnippetPack.bible {
                    if !enabledBinding.wrappedValue {
                        // ★ 여기는 **문장 안**이라 상수로 빼지 않았다 (2026-09-22 판단).
                        //   `"이 팩을 켜야 머리말 넣기와 \(ToolbarTool.bibleSearch.displayName)도…"`로
                        //   쓰면 **조사가 이름을 따라가지 못한다** — 지금은 받침 없는 「기」로
                        //   끝나 「도」가 맞지만, 이름이 받침으로 끝나면 문장이 깨진다.
                        //   이름이 바뀌면 이 줄은 **사람이 읽고 고쳐야 한다.**
                        //   대신 위 스위치 제목이 이름을 참조하므로 **둘이 어긋나면 화면에서 바로 보인다.**
                        Text("이 팩을 켜야 머리말 넣기와 단어로 구절 찾기도 쓸 수 있어요.")
                    }
                } else if let note = pack.note {
                    // 성경이 아닌 팩은 스위치가 「이 팩 사용」 하나뿐이라 설명이 Section 것이다
                    Text(note)
                }
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
                Text("단축어를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 단축어가 전문으로 바뀌어요.")
            }
        }
        .settingsFormWidth()
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 스위치 한 행의 **제목 + 설명** — 설명이 어느 스위치 것인지 붙어 있어야 한다.
    private func switchLabel(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
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
