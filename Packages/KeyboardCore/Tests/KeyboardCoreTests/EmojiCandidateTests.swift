import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 실제 번들 역색인(CLDR 48.2, `emoji.tde`)의 값을 그대로 옮긴 fake. 실데이터 묶음은 TadakData 테스트
/// (`BundledEmojiCandidateTests`)가 실제 `emoji.tde`·`EmojiCuration.json`으로 본다.
private final class FakeEmojiIndex: EmojiAnnotationIndex, @unchecked Sendable {
    static let cldr: [String: EmojiAnnotation] = [
        "자동차": EmojiAnnotation(emojis: ["🚕", "🚗", "🚘", "🛻", "🛞"], nameMatch: "🚗"),
        "고양이": EmojiAnnotation(emojis: ["😺", "😸", "😹", "😻", "😼", "😽", "🙀", "😿", "😾", "🐱", "🐈"],
                               nameMatch: "🐈"),
        "선물": EmojiAnnotation(emojis: ["🧧", "🎁"], nameMatch: "🎁"),
        "사람": EmojiAnnotation(emojis: ["🥸", "🧑", "👱", "🧔", "🙍", "🥷", "👷", "👰", "🦹", "🤹", "👤"],
                              nameMatch: "🧑"),
        "사과": EmojiAnnotation(emojis: ["🙇", "🍎", "🍏"], nameMatch: nil),
        "맥주": EmojiAnnotation(emojis: ["🫚", "🍺", "🍻"], nameMatch: "🍻"),
        "가지": EmojiAnnotation(emojis: ["🍆"], nameMatch: "🍆")
    ]

    private(set) var lookups: [String] = []

    func annotation(for word: String) -> EmojiAnnotation? {
        lookups.append(word)
        return Self.cldr[word]
    }
}

/// 결정적 난수원(SplitMix64) — 뽑기 테스트가 시드로 재현되고, 난수를 몇 번 썼는지로 「다시 뽑았나」를 본다.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    private(set) var draws = 0

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        draws += 1
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("이모지 후보 묶음 — CLDR 후보 ∪ 손질 목록, 막기 (D9·D10)")
struct EmojiCandidateTests {

    /// D9로 「자동차→🚗(🚕 아님)」 대표 고정은 무효다 — 둘 다 묶음에 있고 그중에서 뽑는다.
    @Test("「자동차」 묶음은 CLDR 후보 5개 전부다 — 🚗도 🚕도 있다")
    func carBundleHoldsAllCandidates() {
        let bundle = EmojiCandidateResolver(index: FakeEmojiIndex()).candidates(for: "자동차")
        #expect(bundle == ["🚕", "🚗", "🚘", "🛻", "🛞"])
        #expect(bundle.contains("🚗") && bundle.contains("🚕"))
    }

    @Test("이름 일치 이모지와 파일 첫 값이 함께 묶음에 있다", arguments: [
        ("고양이", "🐈", "😺"), ("선물", "🎁", "🧧"), ("사람", "🧑", "🥸")
    ])
    func nameMatchAndFirstBothIn(testCase: (word: String, named: String, first: String)) {
        let bundle = EmojiCandidateResolver(index: FakeEmojiIndex()).candidates(for: testCase.word)
        #expect(bundle.contains(testCase.named) && bundle.contains(testCase.first))
    }

    @Test("손질 목록 값은 묶음에 더해진다 — 이미 있으면 겹치지 않는다")
    func curationValuesJoin() {
        let resolver = CandidateFixtures.resolver(
            overrides: ["맥주": "🍺", "자동차": "🚙"], fallbacks: ["사과": "🍎", "선물": "🎀"])
        #expect(resolver.candidates(for: "맥주") == ["🫚", "🍺", "🍻"])
        #expect(resolver.candidates(for: "자동차") == ["🚕", "🚗", "🚘", "🛻", "🛞", "🚙"])
        #expect(resolver.candidates(for: "사과") == ["🙇", "🍎", "🍏"])
        #expect(resolver.candidates(for: "선물") == ["🧧", "🎁", "🎀"])
    }

    @Test("막기(override 빈 문자열)는 CLDR 후보가 있어도 빈 묶음이다")
    func blockedWordIsEmpty() {
        let resolver = CandidateFixtures.resolver(overrides: ["가지": ""])
        #expect(resolver.candidates(for: "가지").isEmpty)
        #expect(resolver.candidates(for: "자동차").count == 5, "막기는 그 단어에만")
    }

    @Test("손질 목록에만 있는 단어도 묶음이 생긴다 (치킨 → 🍗)")
    func curationOnlyWord() {
        let resolver = CandidateFixtures.resolver(fallbacks: ["치킨": "🍗"])
        #expect(resolver.candidates(for: "치킨") == ["🍗"])
    }

    @Test("역색인에도 손질 목록에도 없는 단어는 빈 묶음이다")
    func unknownWordIsEmpty() {
        #expect(EmojiCandidateResolver(index: FakeEmojiIndex()).candidates(for: "비행기").isEmpty)
    }

    @Test("조사 붙은 꼴(「자동차는」)은 빈 묶음이다 — 어간을 떼어 다시 찾지 않는다 (Q5)")
    func particleFormIsEmpty() {
        let index = FakeEmojiIndex()
        let resolver = EmojiCandidateResolver(index: index, curation: EmojiCuration(overrides: ["자동차": "🚙"]))
        #expect(resolver.candidates(for: "자동차는").isEmpty)
        #expect(resolver.candidates(for: "자동차를").isEmpty)
        #expect(!index.lookups.contains("자동차"), "어간 재조회 없음")
    }

    @Test("완성된 한글 2~12음절이 아니면 역색인을 보지도 않고 빈 묶음이다",
          arguments: ["", "자", "자동ㅊ", "ㅊ", "car", "자동 차", "자동차1", "🚗", "사과\n",
                      String(repeating: "가", count: 13)])
    func rejectsNonWords(text: String) {
        let index = FakeEmojiIndex()
        let resolver = EmojiCandidateResolver(index: index, curation: EmojiCuration(overrides: [text: "🚙"]))
        #expect(resolver.candidates(for: text).isEmpty)
        #expect(index.lookups.isEmpty)
    }

    @Test("12음절까지는 조회한다")
    func twelveSyllablesLookedUp() {
        let index = FakeEmojiIndex()
        _ = EmojiCandidateResolver(index: index).candidates(for: String(repeating: "가", count: 12))
        #expect(index.lookups.count == 1)
    }

    @Test("역색인이 없어도(리소스 누락) 손질 목록은 동작한다")
    func curationWithoutIndex() {
        let resolver = EmojiCandidateResolver(
            index: nil, curation: EmojiCuration(overrides: ["맥주": "🍺"], fallbacks: ["치킨": "🍗"]))
        #expect(resolver.candidates(for: "맥주") == ["🍺"])
        #expect(resolver.candidates(for: "치킨") == ["🍗"])
        #expect(resolver.candidates(for: "자동차").isEmpty)
    }
}

private enum CandidateFixtures {
    static func resolver(overrides: [String: String] = [:], fallbacks: [String: String] = [:]) -> EmojiCandidateResolver {
        EmojiCandidateResolver(index: FakeEmojiIndex(),
                               curation: EmojiCuration(overrides: overrides, fallbacks: fallbacks))
    }
}

@Suite("이모지 뽑기 — 다 친 순간 한 번 뽑고 고정, 다시 치면 새로 (D9)")
struct EmojiDrawTests {

    private let car = ["🚕", "🚗", "🚘", "🛻", "🛞"]
    private let beer = ["🫚", "🍺", "🍻"]

    @Test("같은 단어를 연속 조회하는 동안(메아리 sync·재계산) 같은 값이고 난수를 더 쓰지 않는다")
    func sticksWhileSameWord() {
        var generator = SeededGenerator(seed: 7)
        var draw = EmojiDraw()
        let first = draw.emoji(for: "자동차", from: car, using: &generator)
        let used = generator.draws
        #expect(first.map(car.contains) == true)
        for _ in 0..<20 {
            #expect(draw.emoji(for: "자동차", from: car, using: &generator) == first)
        }
        #expect(generator.draws == used)
    }

    @Test("단어가 비었다가(공백·조사 등) 다시 그 단어가 되면 새로 뽑는다", arguments: [
        ("", [String]()), ("자동차는", [String]()), ("맥주", ["🫚", "🍺", "🍻"])
    ])
    func redrawsAfterOtherWord(between: (word: String, candidates: [String])) {
        var generator = SeededGenerator(seed: 7)
        var draw = EmojiDraw()
        _ = draw.emoji(for: "자동차", from: car, using: &generator)
        _ = draw.emoji(for: between.word, from: between.candidates, using: &generator)
        let before = generator.draws
        let again = draw.emoji(for: "자동차", from: car, using: &generator)
        #expect(generator.draws > before, "다시 친 것 — 새로 뽑는다")
        #expect(again.map(car.contains) == true)
    }

    @Test("다시 칠 때마다 새로 뽑으므로 묶음의 값이 고르게 다 나온다")
    func redrawsCoverBundle() {
        var generator = SeededGenerator(seed: 2026)
        var draw = EmojiDraw()
        var seen: [String: Int] = [:]
        for _ in 0..<500 {
            if let emoji = draw.emoji(for: "자동차", from: car, using: &generator) { seen[emoji, default: 0] += 1 }
            _ = draw.emoji(for: "", from: [], using: &generator)
        }
        #expect(Set(seen.keys) == Set(car))
        #expect(seen.values.allSatisfy { $0 > 50 }, "균등 뽑기면 각 100회 안팎")
    }

    @Test("시드가 같으면 뽑기 결과가 같다 — 결정적")
    func deterministicWithSeed() {
        func run() -> [String?] {
            var generator = SeededGenerator(seed: 42)
            var draw = EmojiDraw()
            let script: [(String, [String])] = [
                ("자동차", car), ("자동차", car), ("", []), ("자동차", car), ("맥주", beer), ("맥주", beer),
                ("자동차는", []), ("자동차", car), ("맥주", beer)
            ]
            return script.map { draw.emoji(for: $0.0, from: $0.1, using: &generator) }
        }
        #expect(run() == run())
    }

    @Test("후보가 하나면 늘 그것이다")
    func singleCandidate() {
        var generator = SeededGenerator(seed: 1)
        var draw = EmojiDraw()
        for _ in 0..<10 {
            #expect(draw.emoji(for: "콜라", from: ["🥤"], using: &generator) == "🥤")
            _ = draw.emoji(for: "", from: [], using: &generator)
        }
    }

    @Test("묶음이 비면 nil이다 (막기·조사 꼴·비단어)")
    func emptyBundleIsNil() {
        var generator = SeededGenerator(seed: 1)
        var draw = EmojiDraw()
        #expect(draw.emoji(for: "가지", from: [], using: &generator) == nil)
    }

    @Test("고정된 값이 묶음에서 빠지면(손질 목록 갱신) 같은 단어라도 새로 뽑는다")
    func redrawsWhenPickLeavesBundle() throws {
        var generator = SeededGenerator(seed: 9)
        var draw = EmojiDraw()
        let first = try #require(draw.emoji(for: "자동차", from: car, using: &generator))
        let shrunk = car.filter { $0 != first }
        let next = draw.emoji(for: "자동차", from: shrunk, using: &generator)
        #expect(next.map(shrunk.contains) == true)
    }

    @Test("reset() 뒤에는 같은 단어도 새로 뽑는다")
    func resetForgets() {
        var generator = SeededGenerator(seed: 3)
        var draw = EmojiDraw()
        _ = draw.emoji(for: "자동차", from: car, using: &generator)
        draw.reset()
        let before = generator.draws
        _ = draw.emoji(for: "자동차", from: car, using: &generator)
        #expect(generator.draws > before)
    }

    /// 호스트 sync가 쓰는 엿보기 — 기억을 버리지도 새로 뽑지도 않는다(검증 ⑤-2a 참고 2, `EmojiChipState`).
    @Test("peek은 같은 단어일 때만 기억한 값을 주고, 다른 단어·빈 단어를 봐도 기억을 버리지 않는다")
    func peekNeverForgets() throws {
        var generator = SeededGenerator(seed: 5)
        var draw = EmojiDraw()
        let first = try #require(draw.emoji(for: "자동차", from: car, using: &generator))
        #expect(draw.peek(for: "자동차", in: car) == first)
        #expect(draw.peek(for: "", in: []) == nil)
        #expect(draw.peek(for: "맥주", in: beer) == nil)
        let used = generator.draws
        #expect(draw.emoji(for: "자동차", from: car, using: &generator) == first, "엿본 뒤에도 같은 값")
        #expect(generator.draws == used)
        #expect(draw.peek(for: "자동차", in: car.filter { $0 != first }) == nil, "고정 값이 묶음에서 빠지면 nil")
    }

    @Test("시스템 난수원을 쓰는 편의 함수도 묶음 안의 값을 고정한다")
    func systemGeneratorConvenience() {
        var draw = EmojiDraw()
        let first = draw.emoji(for: "자동차", from: car)
        #expect(first.map(car.contains) == true)
        #expect(draw.emoji(for: "자동차", from: car) == first)
    }
}
