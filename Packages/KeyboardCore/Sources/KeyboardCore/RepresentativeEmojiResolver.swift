import TadakDomain

/// 단어 하나의 대표 이모지 — 추천단어 줄 이모지 칩(`[🚗 자동차]`·`[🚗]`)에 실을 값
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 2-3절, 확정 결정 Q7).
///
/// 순서는 **손질 목록(override) > 이름(tts) 완전 일치 > 검토한 대체(fallback)**이고, 셋 다 없으면 nil이다.
/// CLDR 파일 첫 값은 쓰지 않는다 — 코드포인트 순이라 「자동차」에 🚕, 「사람」에 🥸를 낸다(2-3절).
///
/// 조회는 **지금 치는 단어 자신의 정확 일치 1회**다(Q1) — 조사 붙은 꼴(「자동차는」)에서 어간을 떼어
/// 다시 찾지 않는다(Q5, 1자 어간 오분석 8.85% 실측). 완성된 한글 2~12음절이 아니면(조합 중 자모·
/// 영문·공백) 역색인을 보지도 않는다 — 역색인 키가 그 꼴뿐이고 키 입력마다 불리는 자리다.
public struct RepresentativeEmojiResolver: Sendable {

    /// 역색인 키와 같은 꼴 — `tools/convert_emoji.py`의 `^[가-힣]{2,12}$`
    static let wordLengths = 2...12

    private let index: (any EmojiAnnotationIndex)?
    private let curation: EmojiCuration

    /// - Parameters:
    ///   - index: nil이면(리소스 누락) 이름 일치 단계를 건너뛰고 손질 목록만 본다
    ///   - curation: 사람이 고른 목록 — 빈 문자열 값은 「이 단어엔 띄우지 않음」
    public init(index: (any EmojiAnnotationIndex)?, curation: EmojiCuration = .empty) {
        self.index = index
        self.curation = curation
    }

    public func emoji(for word: String) -> String? {
        guard Self.isCompleteWord(word) else { return nil }
        if let curated = curation.overrides[word] {
            return curated.isEmpty ? nil : curated
        }
        if let named = index?.annotation(for: word)?.nameMatch {
            return named
        }
        if let fallback = curation.fallbacks[word], !fallback.isEmpty {
            return fallback
        }
        return nil
    }

    static func isCompleteWord(_ word: String) -> Bool {
        var count = 0
        for scalar in word.unicodeScalars {
            guard (0xAC00...0xD7A3).contains(scalar.value) else { return false }
            count += 1
        }
        return wordLengths.contains(count)
    }
}
