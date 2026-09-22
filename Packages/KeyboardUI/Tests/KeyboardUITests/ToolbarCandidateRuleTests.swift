import Testing
@testable import KeyboardUI

/// 툴바 후보 행의 두 규칙 — 추천단어 개수와 ✕ 표시.
///
/// 하루 동안 툴바 레이아웃 값 타입이 이 둘을 들고 있었는데, **배지 자리 예약을 되돌리면서**
/// 그 타입을 통째로 지우고 규칙만 `KeyboardMetrics`로 옮겼다(2026-09-21 밤).
@Suite("툴바 후보 행 규칙")
struct ToolbarCandidateRuleTests {

    // MARK: - ★ 추천단어 개수 — 사용자가 되돌린 바로 그 규칙

    /// > 「성경 키워드 개수가 0개일떄 추천단어가 2개로 나오는데 **기본적으로 3개가 나오도록** 하자」
    @Test("★ 배지가 없으면 추천단어 3개")
    func threeWordsWithoutBadge() {
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: false) == 3)
    }

    /// > 「성경 키워드 갯수가 1개 이상일떄에는 **추천단어 2개** 나오도록 하자」
    @Test("★ 배지가 있으면 추천단어 2개")
    func twoWordsWithBadge() {
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: true) == 2)
    }

    /// ★ **이것이 사용자가 고친 바로 그 지점이다.**
    ///
    /// 낮에는 게이트가 켜져 있기만 하면(결과가 0건이어도) 자리를 비워 두고 2개로 고정했다.
    /// 그래서 「호산ㄴ」처럼 조합 중이라 0건인 순간 **오른쪽이 비어 보였다.**
    /// 이제 규칙이 **게이트가 아니라 배지 유무**를 보므로 0건이면 3개이고 여백도 없다.
    @Test("★ 검색이 켜져 있어도 결과가 0건이면 3개다 — 게이트가 아니라 배지가 정한다")
    func enabledButNoResultsStillThree() {
        // 게이트는 이 함수에 아예 들어오지 않는다 — 들어올 자리가 없다는 것이 규칙이다
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: false) == 3)
    }

    // MARK: - ✕ 표시 (2026-09-21 낮 결정 — 그대로 유지)

    /// 배지만 있을 때는 ✕가 없다. 도구 행 조건이 배지를 보지 않으므로
    /// `[도구 4개] [📖 N]`이 한 줄에 함께 그려져 갇히지 않는다.
    @Test("★ 배지만 있을 때 ✕가 없다 — 도구 행이 함께 보인다")
    func noDismissWithBadgeAlone() {
        // 배지는 이 함수의 입력에 없다 — 그것이 규칙이다
        #expect(!KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: false, hasPaste: false))
    }

    @Test("추천단어가 있으면 ✕가 있다")
    func wordsKeepDismiss() {
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: true, hasPaste: false))
    }

    @Test("채움글 칩의 ✕는 그대로")
    func snippetKeepsDismiss() {
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: true, hasWords: false, hasPaste: false))
    }

    @Test("붙여넣기 칩의 ✕는 그대로")
    func pasteKeepsDismiss() {
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: false, hasPaste: true))
    }

    @Test("후보 조합 8가지 — ✕와 도구 행은 정확히 반대다")
    func dismissAndToolRowAreComplementary() {
        for snippet in [false, true] {
            for words in [false, true] {
                for paste in [false, true] {
                    let dismiss = KeyboardMetrics.showsDismissButton(
                        hasSnippet: snippet, hasWords: words, hasPaste: paste
                    )
                    #expect(dismiss == (snippet || words || paste))
                }
            }
        }
    }
}
