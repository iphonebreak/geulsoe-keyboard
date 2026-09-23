import Foundation
import Testing
@testable import TadakDomain

/// ★ 「내 채움글」 목록의 **자리**가 편집으로 흐트러지지 않는가 (검증자 2026-09-23).
///
/// ## 왜 이 스위트가 생겼나
///
/// 편집 진입점이 생기자마자 **고치면 항목이 맨 뒤로 튀는 것**이 드러났다.
/// 목록이 길수록 나쁘다 — 고친 항목을 다시 찾아야 한다.
///
/// 규칙이 설정 화면(`App/`)에 있어 **`swift test`가 닿지 않았고**, 그래서 아무도 못 잡았다.
/// 규칙을 `SnippetEntry.applying(_:editing:to:)`로 내리고 여기서 잠근다.
@Suite("내 채움글 — 목록 자리")
struct SnippetListOrderTests {

    private func entry(_ trigger: String, _ body: String = "본문") -> SnippetEntry {
        SnippetEntry(triggers: [trigger], title: trigger, body: body)
    }

    private var three: [SnippetEntry] { [entry("하나"), entry("둘"), entry("셋")] }

    // MARK: - 편집은 제자리

    /// ★ **이 스위트의 핵심.** 3개 목록의 **가운데**를 고쳐도 가운데에 남아야 한다.
    ///
    /// 깨지려면: `applying`이 편집에서도 `append`로 끝난다 — 사용자가 고칠 때마다
    /// 그 항목이 목록 맨 뒤로 간다.
    @Test("★ 가운데를 고쳐도 가운데에 그대로 있다")
    func editKeepsMiddleIndex() {
        let list = three
        let edited = SnippetEntry(triggers: ["둘"], title: "둘", body: "고친 본문")
        let result = SnippetEntry.applying(edited, editing: list[1], to: list)

        #expect(result.map(\.title) == ["하나", "둘", "셋"], "자리가 바뀌었다")
        #expect(result[1].body == "고친 본문", "고친 내용이 안 실렸다")
        #expect(result.count == 3)
    }

    @Test("맨 앞·맨 뒤를 고쳐도 자리가 그대로다", arguments: [0, 1, 2])
    func editKeepsAnyIndex(index: Int) {
        let list = three
        let original = list[index]
        let edited = SnippetEntry(
            triggers: original.triggers, title: original.title, body: "새 본문")
        let result = SnippetEntry.applying(edited, editing: original, to: list)
        #expect(result.map(\.title) == ["하나", "둘", "셋"])
        #expect(result[index].body == "새 본문")
    }

    /// 단축어를 **통째로 바꿔도** 자리는 그대로다 — 옛 항목이 남지도 않는다.
    @Test("단축어를 전부 갈아도 자리는 유지되고 옛 항목은 사라진다")
    func replacingAllTriggersKeepsIndex() {
        let list = three
        let edited = SnippetEntry(triggers: ["새단축어"], title: "새 제목", body: "본문")
        let result = SnippetEntry.applying(edited, editing: list[1], to: list)
        #expect(result.map(\.title) == ["하나", "새 제목", "셋"])
        #expect(!result.contains { $0.triggers.contains("둘") })
    }

    // MARK: - ★ 두 번 지우는 구조와 인덱스가 부딪히는 자리

    /// ★ 겹쳐서 지워지는 항목이 **원본보다 앞에** 있으면 자리가 당겨진다 —
    /// `removedBefore` 보정이 없으면 항목이 그만큼 뒤로 밀린다.
    ///
    /// 깨지려면: `applying`이 원본 인덱스를 **보정 없이** 그대로 쓴다.
    @Test("★ 앞쪽 항목이 단축어 충돌로 함께 지워져도 자리가 안 밀린다")
    func removedEarlierEntryDoesNotShiftIndex() {
        // [하나, 둘, 셋]에서 **둘**을 고치며 단축어에 「하나」를 더한다
        // → 맨 앞 「하나」가 충돌로 지워지고, 고친 항목은 **그 자리(0번)** 로 와야 한다
        let list = three
        let edited = SnippetEntry(triggers: ["둘", "하나"], title: "합친 것", body: "본문")
        let result = SnippetEntry.applying(edited, editing: list[1], to: list)
        #expect(result.map(\.title) == ["합친 것", "셋"],
                "앞에서 하나가 지워졌으니 1번이 아니라 0번이어야 한다")
        #expect(result.count == 2)
    }

    /// 뒤쪽이 지워지는 것은 자리에 영향이 없다.
    @Test("뒤쪽 항목이 충돌로 지워져도 자리는 그대로다")
    func removedLaterEntryKeepsIndex() {
        let list = three
        let edited = SnippetEntry(triggers: ["둘", "셋"], title: "합친 것", body: "본문")
        let result = SnippetEntry.applying(edited, editing: list[1], to: list)
        #expect(result.map(\.title) == ["하나", "합친 것"])
    }

    // MARK: - 추가는 맨 뒤

    @Test("새로 추가하면 맨 뒤다")
    func addGoesToEnd() {
        let result = SnippetEntry.applying(entry("넷"), editing: nil, to: three)
        #expect(result.map(\.title) == ["하나", "둘", "셋", "넷"])
    }

    /// 추가인데 단축어가 겹치면 **기존 것이 사라지고 새 것이 맨 뒤**다 — 예전 규칙 그대로다.
    @Test("추가에서 단축어가 겹치면 기존을 대체하고 맨 뒤로 간다")
    func addWithConflictReplacesAndGoesToEnd() {
        let result = SnippetEntry.applying(
            SnippetEntry(triggers: ["둘"], title: "새 둘", body: "본문"), editing: nil, to: three)
        #expect(result.map(\.title) == ["하나", "셋", "새 둘"])
    }

    /// 원본을 목록에서 못 찾으면(있을 수 없는 입력) 잃어버리지 않고 맨 뒤로 간다.
    @Test("원본이 목록에 없으면 맨 뒤에 붙는다 — 잃어버리지 않는다")
    func missingOriginalFallsBackToEnd() {
        let ghost = entry("없는것")
        let result = SnippetEntry.applying(entry("넷"), editing: ghost, to: three)
        #expect(result.map(\.title) == ["하나", "둘", "셋", "넷"])
    }

    // MARK: - D. 쉼표 든 단축어 판정

    /// ★ v1.0.1 편집기가 쉼표를 막지 않았으므로 **저장분에 있을 수 있다.**
    /// 고치지 않고 **알린다** — 자세한 근거는 `hasCommaInTrigger` 주석에 있다.
    @Test("★ 쉼표 든 단축어를 가려낸다 — 편집 왕복에서 쪼개지는 항목이다")
    func detectsCommaTrigger() {
        #expect(SnippetEntry(triggers: ["가,나"], title: "옛것", body: "b").hasCommaInTrigger)
        #expect(!SnippetEntry(triggers: ["가", "나"], title: "새것", body: "b").hasCommaInTrigger)
        #expect(!entry("우리집주소").hasCommaInTrigger)
    }

    /// 쉼표 든 단축어가 **실제로 쪼개진다**는 것을 고정한다 — 경고가 왜 필요한지의 근거다.
    /// (`parseTriggers`는 단일 출처라 건드리지 않는다. 여기서는 **현상만** 적는다.)
    @Test("★ 쉼표 든 단축어는 편집 왕복에서 둘로 갈린다 — 경고의 근거")
    func commaTriggerSplitsOnRoundTrip() {
        let old = SnippetEntry(triggers: ["가,나"], title: "옛것", body: "본문")
        let shown = old.triggers.joined(separator: ", ")   // 편집기가 싣는 모양
        #expect(shown == "가,나")
        #expect(SnippetEntry.parseTriggers(shown) == ["가", "나"], "하나가 둘이 된다")
    }
}
