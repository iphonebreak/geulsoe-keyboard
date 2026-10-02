import Foundation
import TadakDomain

/// 성경 검색 **건수 표기** — 배지와 패널이 **같은 규칙**을 쓰게 하는 한 곳.
///
/// ## 왜 한 곳이어야 하나 (2026-09-21)
///
/// 예전에는 배지만 999+ 규칙을 갖고 있었고 패널은 받은 수를 그대로 그렸다. 그래서
/// 「사람」(실제 4,253건)에서 **배지는 `999+`, 패널은 `전체(1000)`** 이라고
/// **서로 다른 말을 했다.** 게다가 「전체」라고 하면서 3,253건을 조용히 빼고 있었다.
///
/// 규칙을 두 곳에 두면 반드시 갈라진다 — 그래서 여기 하나만 둔다.
///
/// ## 규칙
///
/// 검색은 절 주소를 **최대 1,000개**만 들고 온다(`BibleSearchCascade.defaultResultLimit` —
/// 메모리 때문에 정해진 값이다). 그래서 999를 넘는 수는 **정확한 전체 건수가 아니라
/// 「상한에 걸렸다」는 신호**다. 그 순간부터 정확한 수는 의미도 없다(어차피 책으로 접어 본다).
///
/// - 999 이하 → 그 수 그대로 (`517`)
/// - 999 초과 → `999+`
enum BibleCountText {

    /// 이 수를 넘으면 정확한 수를 말하지 않는다. 계획서 2-1이 승인한 규칙이다.
    static let displayCap = 999

    static func isCapped(_ count: Int) -> Bool { count > displayCap }

    /// 화면에 그리는 숫자. 배지와 패널의 「전체」 칩이 공유한다.
    static func label(_ count: Int) -> String {
        isCapped(count) ? "\(displayCap)+" : "\(count)"
    }

    /// 읽어 주는 말. `999+`를 그대로 읽으면 「구백구십구 더하기」로 들린다.
    static func spokenCount(_ count: Int) -> String {
        isCapped(count) ? "\(displayCap)건 이상" : "\(count)건"
    }

    // MARK: - ★ 배지 낭독 라벨 — **UITests가 이것을 술어로 찾는다** (2026-09-22)

    /// 배지 낭독 라벨의 **앞부분**. 건수 앞까지다.
    ///
    /// ## ★ 왜 이것이 따로 있나 — 이름이 두 번 바뀌는 동안 UITests만 안 따라왔다
    ///
    /// `UITests/SnippetShortcutTypingTests`가 배지를 **접근성 라벨로** 찾는다
    /// (`label BEGINSWITH ...`). 그런데 도구 이름이 「성경 구절」 → 「구절 찾기」 →
    /// **「단어로 구절 찾기」**로 바뀌는 동안 UITests의 술어는 **첫 이름 그대로**였다.
    ///
    /// 그래서 배지를 못 찾았고, 그 때문에 **형광펜 8조합을 아예 못 쟀다**(패널을 열려면
    /// 배지를 탭해야 한다). 더 나쁜 것은 `XCTAssertFalse`로 「안 떴다」를 보는 자리에서는
    /// **못 찾은 것이 통과로 읽혔다** — 검사력이 0이었다.
    ///
    /// **원인은 문자열을 세 번 박은 것이다.** 그래서 지금은 라벨이 이 한 곳에서 나오고,
    /// UITests는 `ToolbarTool.bibleSearch.displayName`에서 같은 앞부분을 **계산해서** 쓴다.
    /// 둘이 갈리면 `BibleBadgeLabelTests`가 **`swift test`에서** 먼저 운다 —
    /// UITests는 앱을 실제로 실행해야 해서(Firebase 수집) 아무 때나 못 돌린다.
    /// ★ 2026-09-22: 식을 **`TadakDomain`으로 내렸다.** 같은 식이 여기·UITests·계약 테스트
    /// 셋에 복제돼 있어서 **한 곳만 고치면 아무도 울지 않았다**(검증자 지적).
    /// 이제 셋 다 `ToolbarTool.bibleBadgeLabelPrefix` 하나를 본다.
    static var badgeAccessibilityLabelPrefix: String { ToolbarTool.bibleBadgeLabelPrefix }

    /// 배지 버튼이 읽어 주는 문장 전체 — 「단어로 구절 찾기, 517건, 목록 열기」.
    ///
    /// **무엇 / 얼마나 / 누르면 무엇** 세 토막이다. 붙여서 「단어로 구절 찾기 517건」으로 읽으면
    /// *「단어로 구절 찾기」가 517건*으로 들려 뜻이 뒤집히므로 쉼표로 끊는다.
    static func badgeAccessibilityLabel(count: Int) -> String {
        "\(badgeAccessibilityLabelPrefix)\(spokenCount(count)), 목록 열기"
    }
}
