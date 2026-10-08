import TadakDomain

/// 지금 치는 단어의 이모지 **후보 묶음** — 추천단어 줄 이모지 칩(`[🚗 자동차]`·`[🚗]`)은 이 묶음에서
/// `EmojiDraw`가 하나를 뽑아 싣는다 (PDR `docs/design-reviews/emoji-word-suggestion.md` 확정 결정 D9·D10).
///
/// 묶음 = **CLDR 후보 전부 ∪ 손질 목록 값**, `override ""`(막기)면 빈 묶음 — 규칙 자체는
/// `EmojiCuration.candidates(for:annotation:)`(TadakDomain)에 있다. 그래야 TadakData 테스트가 실제
/// `emoji.tde`·`EmojiCuration.json`으로 같은 규칙을 돌려 볼 수 있다(KeyboardCore는 TadakData를 모른다).
/// 이 타입은 단어 꼴 검사와 역색인 조회만 더한다.
///
/// 조회는 **지금 치는 단어 자신의 정확 일치 1회**다(Q1) — 조사 붙은 꼴(「자동차는」)에서 어간을 떼어
/// 다시 찾지 않는다(Q5, 1자 어간 오분석 8.85% 실측). 완성된 한글 2~12음절이 아니면(조합 중 자모·
/// 영문·공백) 역색인을 보지도 않는다 — 역색인 키가 그 꼴뿐이고 키 입력마다 불리는 자리다.
///
/// ⑤-1의 `RepresentativeEmojiResolver`(대표 하나 — Q7)를 D9가 「랜덤」으로 바꿔 이름을 갈았다.
/// 아직 조립 지점에 배선되기 전이라 이름을 바꾸는 비용이 0일 때 바꿨다.
public struct EmojiCandidateResolver: Sendable {

    /// 역색인 키와 같은 꼴 — `tools/convert_emoji.py`의 `^[가-힣]{2,12}$`
    static let wordLengths = 2...12

    private let index: (any EmojiAnnotationIndex)?
    private let curation: EmojiCuration

    /// - Parameters:
    ///   - index: nil이면(리소스 누락) 손질 목록 값만으로 묶음을 만든다
    ///   - curation: 사람이 고른 목록 — 값은 묶음에 더하고, `override ""`는 막기
    public init(index: (any EmojiAnnotationIndex)?, curation: EmojiCuration = .empty) {
        self.index = index
        self.curation = curation
    }

    /// 빈 배열이면 이 단어엔 이모지 칩이 없다.
    public func candidates(for word: String) -> [String] {
        guard Self.isCompleteWord(word) else { return [] }
        return curation.candidates(for: word, annotation: index?.annotation(for: word))
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
