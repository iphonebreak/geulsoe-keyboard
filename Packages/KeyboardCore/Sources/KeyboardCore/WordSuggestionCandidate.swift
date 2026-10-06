/// 추천단어 줄의 후보 하나 — 단어 칩 또는 이모지 칩(`[🚗 자동차]`·`[🚗]`)
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 6-2절, 확정 결정 Q8).
///
/// 버튼 뷰는 그대로 두고 **받는 타입만** `String`에서 이 값으로 바꿨다 — 이모지 칩은 VoiceOver 라벨이
/// 따로 있어야 하고(6-1절: 🚕는 애플 이름표로 「택시」라 단어 칩과 구별이 안 된다), 탭 처리가
/// 원본 단어를 알아야 꼬리 정합을 검사할 수 있어서다.
public struct WordSuggestionCandidate: Equatable, Sendable {
    /// 원본 단어 — 단어 칩은 후보 그 자체, 이모지 칩은 **지금 치던 단어**(「자동차」). 탭할 때 꼬리가
    /// 이 단어로 끝나야만 바꾼다(`InputController.replaceCurrentWord`).
    public let sourceWord: String
    /// 실제로 넣을 문자열 — 단어 칩은 단어, 혼합 칩은 `🚗 자동차`(Q3), 전용 칩은 `🚗`(Q4)
    public let insertionText: String
    /// 칩에 실린 이모지 — nil이면 순수 단어 칩(v1.2.0과 같다)
    public let emoji: String?
    /// 단어 칩은 단어 그대로, 이모지 칩은 **원본 단어**로 읽는다(이모지 이름이 아니다 — D9로 값이 랜덤이라
    /// 이름표를 읽으면 칩마다 다른 말이 된다).
    public let accessibilityLabel: String

    public static func word(_ word: String) -> WordSuggestionCandidate {
        WordSuggestionCandidate(sourceWord: word, insertionText: word, emoji: nil, accessibilityLabel: word)
    }

    /// `[🚗 자동차]` — 치던 단어를 지우고 이모지·공백·단어(후행 공백 없음, Q3)
    public static func emojiWithWord(_ emoji: String, word: String) -> WordSuggestionCandidate {
        WordSuggestionCandidate(sourceWord: word, insertionText: "\(emoji) \(word)", emoji: emoji,
                                accessibilityLabel: "\(word) 이모지 붙여넣기")
    }

    /// `[🚗]` — 치던 단어를 이모지로 바꾼다(교체, Q4)
    public static func emojiOnly(_ emoji: String, word: String) -> WordSuggestionCandidate {
        WordSuggestionCandidate(sourceWord: word, insertionText: emoji, emoji: emoji,
                                accessibilityLabel: "\(word) 이모지로 바꾸기")
    }

    public var isEmojiOnly: Bool { emoji != nil && insertionText == emoji }

    /// 후보 줄 — 단어 후보 뒤에 혼합·전용 칩을 붙인다(Q2). 두 칩은 **같은 뽑은 값**이다(수용 기준 15).
    /// 단어 후보 개수 상한(이모지가 있으면 한 칸 적게)은 `KeyboardMetrics.wordSuggestionLimit(hasBadge:hasEmojiChips:)`.
    public static func row(words: [String], emoji: String?, sourceWord: String) -> [WordSuggestionCandidate] {
        let wordChips = words.map(word)
        guard let emoji else { return wordChips }
        return wordChips + [emojiWithWord(emoji, word: sourceWord), emojiOnly(emoji, word: sourceWord)]
    }
}

/// 추천단어(이모지 칩 포함)를 지금 계산해도 되는가 — 툴바 우선순위의 앞쪽 규칙
/// (채움글·날짜 칩 > … , PDR `emoji-word-suggestion.md` 4-4절 「바뀌는 것 없음」).
///
/// 조립 지점에 있던 조건식을 그대로 옮겼다 — 익스텐션 타깃은 `swift test`가 닿지 않아서다.
/// 추천단어가 꺼져 있으면 엔진이 없으므로 그 조건은 조립 지점이 따로 본다.
public enum WordSuggestionGate {
    /// - Parameters:
    ///   - isSecureTextEntry: 비밀번호 칸 — 추천·학습·이모지 모두 하지 않는다(보안 규칙)
    ///   - hasSnippet: 채움글·날짜 칩이 떠 있다 — 칩만 보인다(2026-09-03 결정)
    ///   - hasPasteChip: 붙여넣기 칩(일반 텍스트·인증번호)이 떠 있다 — `[칩][✕]`만 보인다(D18, 2026-10-06).
    ///     ✕로 칩을 물리면 이 값이 거짓이 되어 지금 단어의 후보가 나온다. v1.2.0부터 둘이 한 줄에 함께 떠
    ///     말줄임으로 안 보였다(실기 세션 1 K7). 칩이 가린 동안은 sync뿐이라 이모지 기억은 버려지지 않는다(D16)
    ///   - isDismissed: ✕로 내린 단어를 이어 치는 중
    ///   - isSuppressedAfterCursorMove: 커서 이동 뒤 다음 키 입력 전
    public static func allowsWords(
        isSecureTextEntry: Bool, hasSnippet: Bool, hasPasteChip: Bool,
        isDismissed: Bool, isSuppressedAfterCursorMove: Bool
    ) -> Bool {
        !isSecureTextEntry && !hasSnippet && !hasPasteChip && !isDismissed && !isSuppressedAfterCursorMove
    }
}
