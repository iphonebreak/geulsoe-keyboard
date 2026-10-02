import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 실제 번들 역색인(CLDR 48.2, `emoji.tde`)의 값을 그대로 옮긴 fake — 파일 첫 값과 이름 일치가 갈리는
/// 모양까지 같다. 실데이터 조회 자체는 TadakData 테스트(`BundledEmojiAnnotationIndexTests`)가 맡는다.
private final class FakeEmojiIndex: EmojiAnnotationIndex, @unchecked Sendable {
    static let cldr: [String: EmojiAnnotation] = [
        "자동차": EmojiAnnotation(emojis: ["🚕", "🚗", "🚘", "🛻", "🛞"], nameMatch: "🚗"),
        "고양이": EmojiAnnotation(emojis: ["😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾", "🐱", "🐈"],
                               nameMatch: "🐈"),
        "선물": EmojiAnnotation(emojis: ["🧧", "🎁"], nameMatch: "🎁"),
        "사람": EmojiAnnotation(emojis: ["🥸", "🧑", "👱", "🧔", "🙍", "🥷", "👷", "👰", "🦹", "🤹", "👤"],
                              nameMatch: "🧑"),
        "사과": EmojiAnnotation(emojis: ["🙇", "🍎", "🍏"], nameMatch: nil)
    ]

    private(set) var lookups: [String] = []

    func annotation(for word: String) -> EmojiAnnotation? {
        lookups.append(word)
        return Self.cldr[word]
    }
}

@Suite("대표 이모지 — 손질 목록 > 이름 일치 > 검토한 대체 (Q7)")
struct RepresentativeEmojiTests {

    @Test("「자동차」는 🚗다 — CLDR 파일 첫 값 🚕가 아니다 (PDR 2-3절, 수용 기준 10)")
    func carIsNotTaxi() {
        let resolver = RepresentativeEmojiResolver(index: FakeEmojiIndex())
        #expect(resolver.emoji(for: "자동차") == "🚗")
        #expect(resolver.emoji(for: "자동차") != FakeEmojiIndex.cldr["자동차"]?.emojis.first)
    }

    @Test("이름(tts)이 단어와 같은 이모지를 고른다", arguments: [
        ("고양이", "🐈"),  // 첫 값 😺
        ("선물", "🎁"),    // 첫 값 🧧
        ("사람", "🧑")     // 첫 값 🥸
    ])
    func nameMatchWins(testCase: (word: String, emoji: String)) {
        let resolver = RepresentativeEmojiResolver(index: FakeEmojiIndex())
        #expect(resolver.emoji(for: testCase.word) == testCase.emoji)
    }

    @Test("손질 목록(override)이 이름 일치보다 먼저다")
    func overrideBeatsNameMatch() {
        let resolver = RepresentativeEmojiResolver(
            index: FakeEmojiIndex(), curation: EmojiCuration(overrides: ["자동차": "🚙"]))
        #expect(resolver.emoji(for: "자동차") == "🚙")
        #expect(resolver.emoji(for: "고양이") == "🐈", "목록에 없는 단어는 그대로 이름 일치")
    }

    @Test("override 값이 빈 문자열이면 이름 일치가 있어도 띄우지 않는다")
    func emptyOverrideSuppresses() {
        let resolver = RepresentativeEmojiResolver(
            index: FakeEmojiIndex(), curation: EmojiCuration(overrides: ["사람": ""]))
        #expect(resolver.emoji(for: "사람") == nil)
    }

    @Test("이름 일치가 없으면 검토한 대체(fallback)를 쓴다")
    func fallbackWhenNoNameMatch() {
        let resolver = RepresentativeEmojiResolver(
            index: FakeEmojiIndex(), curation: EmojiCuration(fallbacks: ["사과": "🍎"]))
        #expect(resolver.emoji(for: "사과") == "🍎")
    }

    @Test("검토한 대체는 이름 일치를 이기지 못한다")
    func fallbackLosesToNameMatch() {
        let resolver = RepresentativeEmojiResolver(
            index: FakeEmojiIndex(), curation: EmojiCuration(fallbacks: ["자동차": "🚙"]))
        #expect(resolver.emoji(for: "자동차") == "🚗")
    }

    @Test("이름 일치도 손질 목록도 없으면 nil이다 — 파일 첫 값(🙇)으로 메우지 않는다")
    func noCurationNoNameMatchIsNil() {
        let resolver = RepresentativeEmojiResolver(index: FakeEmojiIndex())
        #expect(resolver.emoji(for: "사과") == nil)
    }

    @Test("역색인에 없는 단어는 nil이고, 손질 목록에 있으면 그 값이다")
    func wordOutsideIndex() {
        let resolver = RepresentativeEmojiResolver(
            index: FakeEmojiIndex(), curation: EmojiCuration(overrides: ["치킨": "🍗"]))
        #expect(resolver.emoji(for: "비행기") == nil)
        #expect(resolver.emoji(for: "치킨") == "🍗")
    }

    @Test("조사 붙은 꼴(「자동차는」)은 nil이다 — 어간을 떼어 다시 찾지 않는다 (Q5)")
    func particleFormIsNil() {
        let index = FakeEmojiIndex()
        let resolver = RepresentativeEmojiResolver(
            index: index, curation: EmojiCuration(overrides: ["자동차": "🚙"]))
        #expect(resolver.emoji(for: "자동차는") == nil)
        #expect(resolver.emoji(for: "자동차를") == nil)
        #expect(!index.lookups.contains("자동차"), "어간 재조회 없음")
    }

    @Test("완성된 한글 2~12음절이 아니면 역색인을 보지도 않고 nil이다",
          arguments: ["", "자", "자동ㅊ", "ㅊ", "car", "자동 차", "자동차1", "🚗",
                      String(repeating: "가", count: 13)])
    func rejectsNonWords(text: String) {
        let index = FakeEmojiIndex()
        let resolver = RepresentativeEmojiResolver(
            index: index, curation: EmojiCuration(overrides: [text: "🚙"]))
        #expect(resolver.emoji(for: text) == nil)
        #expect(index.lookups.isEmpty)
    }

    @Test("12음절까지는 조회한다")
    func twelveSyllablesLookedUp() {
        let index = FakeEmojiIndex()
        let resolver = RepresentativeEmojiResolver(index: index)
        _ = resolver.emoji(for: String(repeating: "가", count: 12))
        #expect(index.lookups.count == 1)
    }

    @Test("역색인이 없어도(리소스 누락) 손질 목록은 동작한다")
    func curationWithoutIndex() {
        let resolver = RepresentativeEmojiResolver(
            index: nil, curation: EmojiCuration(overrides: ["맥주": "🍺"], fallbacks: ["사과": "🍎"]))
        #expect(resolver.emoji(for: "맥주") == "🍺")
        #expect(resolver.emoji(for: "사과") == "🍎")
        #expect(resolver.emoji(for: "자동차") == nil)
    }
}
