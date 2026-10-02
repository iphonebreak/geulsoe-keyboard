import Foundation
import Testing
import TadakDomain
@testable import KeyboardUI

/// ★ 배지 낭독 라벨과 **UITests 술어**가 갈리지 않게 잠근다 (2026-09-22).
///
/// ## 왜 이 테스트가 생겼나 — 검증을 막은 고장이 여기서 났다
///
/// `UITests/SnippetShortcutTypingTests`는 배지를 **접근성 라벨 앞부분**으로 찾는다
/// (`label BEGINSWITH ...`). 그 문자열이 세 자리에 **박혀** 있었는데, 도구 이름이
/// 「성경 구절」 → 「구절 찾기」 → **「단어로 구절 찾기」**로 두 번 바뀌는 동안
/// **UITests만 안 따라왔다.** 결과:
///
/// - **형광펜 8조합을 아예 못 쟀다** — 패널을 열려면 배지를 탭해야 하는데 못 찾았다
/// - **`XCTAssertFalse` 한 자리의 검사력이 0이 됐다** — *못 찾은 것*이 *안 뜬 것*으로 읽혔다
///
/// ## ★ 왜 `swift test`에 있나 — UITests로는 이것을 지킬 수 없다
///
/// UITests는 **앱을 실제로 실행**해야 하고 그때 `FirebaseApp.configure()`가 불린다
/// (v1.0.1이 실사용자에게 나가 있어 실 통계가 오염된다). 즉 **아무 때나 못 돌린다.**
/// 그래서 라벨 규약은 여기서, 몇 초 만에 도는 쪽에서 지킨다.
@Suite("성경 배지 낭독 라벨")
struct BibleBadgeLabelTests {

    /// ★ **UITests가 쓰는 바로 그 값**이다 — 식을 다시 적지 않는다 (2026-09-22 정정).
    ///
    /// 전에는 여기서 `"\(displayName), "`를 **세 번째로 다시 적고** 있었다.
    /// 그래서 UITests 상수만 혼자 고치면 **어떤 테스트도 울지 않았다**(검증자 지적).
    /// 지금은 셋(`BibleCountText` · 이 테스트 · UITests)이
    /// `ToolbarTool.bibleBadgeLabelPrefix` 하나를 본다.
    private let uiTestPrefix = ToolbarTool.bibleBadgeLabelPrefix

    @Test("★ UITests 술어가 프로덕션 라벨을 실제로 잡는다")
    func predicateMatchesProductionLabel() {
        for count in [1, 9, 517, 999, 1_000] {
            let label = BibleCountText.badgeAccessibilityLabel(count: count)
            #expect(label.hasPrefix(uiTestPrefix), "\(count)건 라벨 \(q(label))을 술어가 놓친다")
        }
    }

    /// ★ **검사력 증명.** 이름을 틀리면 술어가 **반드시** 빗나가야 한다.
    ///
    /// 이 단언이 없으면 위 테스트는 「무엇이든 통과」가 될 수 있다.
    /// 실제로 옛 술어(`"성경 구절 "`)가 지금 라벨을 못 잡는다는 것을 여기서 고정한다 —
    /// 그것이 UITests를 막았던 바로 그 값이다.
    @Test("★ 이름이 틀린 술어는 라벨을 놓친다 — 옛 값 「성경 구절 」 포함")
    func wrongPrefixDoesNotMatch() {
        let label = BibleCountText.badgeAccessibilityLabel(count: 517)
        // UITests를 막았던 옛 값
        #expect(!label.hasPrefix("성경 구절 "))
        // 그 사이에 있었던 이름
        #expect(!label.hasPrefix("구절 찾기, "))
        // 쉼표·공백 규약이 깨진 경우
        #expect(!label.hasPrefix("\(ToolbarTool.bibleSearch.displayName) "))
        // ★ 프로덕션이 실제로 이 접두를 쓰는지 — 셋이 한 출처라는 것의 확인이다
        #expect(BibleCountText.badgeAccessibilityLabelPrefix == ToolbarTool.bibleBadgeLabelPrefix)
        #expect(!label.hasPrefix("\(ToolbarTool.bibleSearch.displayName),  "))
    }

    @Test("라벨은 무엇 / 얼마나 / 누르면 무엇 세 토막이다")
    func labelHasThreeParts() {
        let label = BibleCountText.badgeAccessibilityLabel(count: 517)
        #expect(label == "단어로 구절 찾기, 517건, 목록 열기")
        #expect(label.split(separator: ",").count == 3)
        // 상한에 걸리면 개수 표기가 바뀐다 — 배지·패널과 같은 규칙이다
        #expect(BibleCountText.badgeAccessibilityLabel(count: 1_000)
                == "단어로 구절 찾기, 999건 이상, 목록 열기")
    }

    /// 붙여 쓰면 *「단어로 구절 찾기」가 517건*으로 들려 뜻이 뒤집힌다 — 쉼표가 그것을 끊는다.
    @Test("이름과 건수 사이에 쉼표가 있다")
    func commaSeparatesNameFromCount() {
        #expect(uiTestPrefix.hasSuffix(", "))
    }

    private func q(_ s: String) -> String { "「\(s)」" }
}
