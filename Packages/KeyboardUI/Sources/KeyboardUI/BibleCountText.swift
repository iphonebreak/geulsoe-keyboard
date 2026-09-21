import Foundation

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
}
