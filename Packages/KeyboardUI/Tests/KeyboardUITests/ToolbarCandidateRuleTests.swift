import CoreGraphics
import Foundation
import Testing
import KeyboardCore
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

    // MARK: - 이모지 칩 (v1.3.0 ⑤, PDR `emoji-word-suggestion.md` Q2·D3·D6, 수용 기준 6·7)

    private static let mixed = WordSuggestionCandidate.emojiWithWord("🚕", word: "자동차")
    private static let only = WordSuggestionCandidate.emojiOnly("🚕", word: "자동차")

    @Test("이모지 칩이 뜨면 단어 후보가 한 칸 준다 — 배지 없음 2·배지 있음 1, 숨김 동안은 원래대로 3·2 (Q2·D3)")
    func wordLimitWithEmojiChips() {
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: false, hasEmojiChips: true) == 2)
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: true, hasEmojiChips: true) == 1)
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: false, hasEmojiChips: false) == 3)
        #expect(KeyboardMetrics.wordSuggestionLimit(hasBadge: true, hasEmojiChips: false) == 2)
    }

    @Test("배지 없음 — 칸 4개 `[단어][단어][🚕 자동차][🚕]` (수용 기준 7)")
    func fourSlotsWithoutBadge() {
        let row = [WordSuggestionCandidate.word("자동차를"), .word("자동차가"), Self.mixed, Self.only]
        let slots = KeyboardMetrics.wordChipSlots(row, hasBadge: false)
        #expect(slots == [[.word("자동차를")], [.word("자동차가")], [Self.mixed], [Self.only]])
        #expect(slots.count <= 4)
    }

    @Test("배지 있음 — 칸 2개, 둘째 칸을 혼합·전용이 반씩 나눈다 · 단어 후보는 0개로 떨어지지 않는다 (수용 기준 6·7)")
    func twoSlotsWithBadge() {
        let row = [WordSuggestionCandidate.word("자동차를"), Self.mixed, Self.only]
        let slots = KeyboardMetrics.wordChipSlots(row, hasBadge: true)
        #expect(slots == [[.word("자동차를")], [Self.mixed, Self.only]])
        #expect(slots.first?.first?.emoji == nil, "첫 칸은 단어 후보")
    }

    @Test("이모지가 없으면 칸 나누기가 지금과 같다 — 후보 하나에 칸 하나 (수용 기준 2)", arguments: [false, true])
    func slotsWithoutEmoji(hasBadge: Bool) {
        let row = [WordSuggestionCandidate.word("안녕하세요"), .word("안녕히")]
        #expect(KeyboardMetrics.wordChipSlots(row, hasBadge: hasBadge) == [[.word("안녕하세요")], [.word("안녕히")]])
    }

    @Test("배지 있음 + 단어 후보 0개 — 이모지 칸 하나")
    func badgeWithoutWords() {
        #expect(KeyboardMetrics.wordChipSlots([Self.mixed, Self.only], hasBadge: true) == [[Self.mixed, Self.only]])
    }

    // MARK: - D18 붙여넣기 칩이 있으면 [칩][✕]만 (PDR `emoji-word-suggestion.md` D18, 실기 세션 1 K7)

    private static let carRow = [WordSuggestionCandidate.word("자동차를"), .word("자동차가"), mixed, only]

    @Test("★ D18 — 붙여넣기 칩이 있으면 추천단어·이모지 칩을 그리지 않는다 · ✕는 남는다 ([복사됨][✕])")
    func pasteChipStandsAlone() {
        let visible = KeyboardMetrics.candidateRowWords(Self.carRow, hasPaste: true)
        #expect(visible.isEmpty, "[복사됨][추천]×4[✕]가 아니다")
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: !visible.isEmpty, hasPaste: true))
    }

    @Test("★ D18 — 붙여넣기 칩이 있으면 성경 배지도 후보 줄에 그리지 않는다")
    func pasteChipHidesBadge() {
        #expect(!KeyboardMetrics.candidateRowShowsBadge(hasPaste: true))
        #expect(KeyboardMetrics.candidateRowShowsBadge(hasPaste: false))
    }

    @Test("D18 — ✕로 붙여넣기 칩이 물러나면 후보가 그대로 그려진다(✕ 유지)")
    func afterPasteDismissWordsReturn() {
        let visible = KeyboardMetrics.candidateRowWords(Self.carRow, hasPaste: false)
        #expect(visible == Self.carRow)
        #expect(KeyboardMetrics.wordChipSlots(visible, hasBadge: false).count == 4)
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: true, hasPaste: false))
    }

    // MARK: - D19 붙여넣기 칩이 채움글 칩보다 먼저 (PDR `emoji-word-suggestion.md` D19)

    private static let greeting = SnippetSuggestion(trigger: "새해인사", title: "새해 인사", body: "새해 복 많이 받으세요")
    private static let today = SnippetSuggestion(
        trigger: "오늘 날짜", title: "오늘 날짜", body: "2026. 9. 27.", computedAt: Date(timeIntervalSince1970: 0), kind: .dateOnly)

    @Test("★ D19 — 붙여넣기 칩이 있으면 채움글 칩(날짜 포함)을 그리지 않는다 · ✕ 하나 ([붙여넣기][✕])",
          arguments: [greeting, today])
    func pasteChipHidesSnippet(_ snippet: SnippetSuggestion) {
        let visible = KeyboardMetrics.candidateRowSnippet(snippet, hasPaste: true)
        #expect(visible == nil, "[붙여넣기][채움글][✕]가 아니다")
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: visible != nil, hasWords: false, hasPaste: true))
    }

    @Test("D19 — ✕로 붙여넣기 칩이 물러나면 채움글 칩이 그려진다(✕ 유지) · 붙여넣기 칩이 없으면 지금과 같다",
          arguments: [greeting, today])
    func afterPasteDismissSnippetReturns(_ snippet: SnippetSuggestion) {
        #expect(KeyboardMetrics.candidateRowSnippet(snippet, hasPaste: false) == snippet)
        #expect(KeyboardMetrics.candidateRowSnippet(nil, hasPaste: false) == nil)
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: true, hasWords: false, hasPaste: false))
    }

    // MARK: - 사진 칩도 붙여넣기 칩이다 (v1.3.0 ④ B, PDR `clipboard-image-history.md` 1-2 · D18·D19)

    private static var photoChip: CopiedPhotoChip {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return CopiedPhotoChip(stage: .copyable, thumbnail: CopiedPhotoThumbnail(image: context.makeImage()!))
    }

    @Test("★ 사진 칩이 있으면 [사진][✕]만 — 채움글 칩·추천단어·배지를 그리지 않는다")
    func photoChipStandsAlone() {
        let hasPaste = PasteChipGate.hasPasteChip(text: nil, photo: Self.photoChip)
        #expect(hasPaste)
        #expect(KeyboardMetrics.candidateRowWords(Self.carRow, hasPaste: hasPaste).isEmpty)
        #expect(KeyboardMetrics.candidateRowSnippet(Self.greeting, hasPaste: hasPaste) == nil)
        #expect(!KeyboardMetrics.candidateRowShowsBadge(hasPaste: hasPaste))
        #expect(KeyboardMetrics.showsDismissButton(hasSnippet: false, hasWords: false, hasPaste: hasPaste))
    }

    @Test("사진 칩이 물러나면(✕·만료) 후보 줄은 지금과 같다")
    func noPhotoChipUnchanged() {
        let hasPaste = PasteChipGate.hasPasteChip(text: nil, photo: nil)
        #expect(!hasPaste)
        #expect(KeyboardMetrics.candidateRowWords(Self.carRow, hasPaste: hasPaste) == Self.carRow)
        #expect(KeyboardMetrics.candidateRowSnippet(Self.greeting, hasPaste: hasPaste) == Self.greeting)
    }

    @Test("D6 여백C — 이모지 칩이 뜬 줄은 칩 안쪽 좌우 여백 0, 아니면 지금 그대로 6")
    func chipPadding() {
        #expect(KeyboardMetrics.wordChipHorizontalPadding(hasEmojiChips: true) == 0)
        #expect(KeyboardMetrics.wordChipHorizontalPadding(hasEmojiChips: false) == 6)
    }
}
