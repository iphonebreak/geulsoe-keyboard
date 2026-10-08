import Foundation
import Testing
@testable import TadakDomain

/// 손질 목록 JSON 형식 — `{"override": {단어: 이모지}, "fallback": {단어: 이모지}}`
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` Q7, 반입 기록 `emoji-data-import.md`).
@Suite("손질 목록 — 형식")
struct EmojiCurationTests {

    @Test("override·fallback 두 절을 읽는다")
    func decodesBothSections() throws {
        let json = #"{"override":{"맥주":"🍺","다리":""},"fallback":{"사과":"🍎"}}"#
        let curation = try JSONDecoder().decode(EmojiCuration.self, from: Data(json.utf8))
        #expect(curation.overrides == ["맥주": "🍺", "다리": ""])
        #expect(curation.fallbacks == ["사과": "🍎"])
    }

    @Test("빠진 절은 빈 목록이다", arguments: [
        #"{}"#, #"{"override":{"맥주":"🍺"}}"#, #"{"fallback":{"사과":"🍎"}}"#
    ])
    func missingSectionIsEmpty(json: String) throws {
        let curation = try JSONDecoder().decode(EmojiCuration.self, from: Data(json.utf8))
        let expected = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: String]]
        #expect(curation.overrides == expected?["override"] ?? [:])
        #expect(curation.fallbacks == expected?["fallback"] ?? [:])
    }

    @Test("인코딩하면 같은 키 이름으로 돌아온다")
    func roundTrip() throws {
        let curation = EmojiCuration(overrides: ["맥주": "🍺"], fallbacks: ["사과": "🍎"])
        let data = try JSONEncoder().encode(curation)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        #expect(object == ["override": ["맥주": "🍺"], "fallback": ["사과": "🍎"]])
        #expect(try JSONDecoder().decode(EmojiCuration.self, from: data) == curation)
    }
}

/// 후보 묶음 — **CLDR 후보 전부 ∪ 손질 목록 값**, `override ""`는 막기 (확정 결정 D9·D10).
@Suite("손질 목록 — 후보 묶음 (D9·D10)")
struct EmojiCurationCandidatesTests {

    private let car = EmojiAnnotation(emojis: ["🚕", "🚗", "🚘", "🛻", "🛞"], nameMatch: "🚗")
    private let beer = EmojiAnnotation(emojis: ["🫚", "🍺", "🍻"], nameMatch: "🍻")

    @Test("손질 목록이 없으면 CLDR 후보 전부다 — 이름 일치(🚗)도 첫 값(🚕)도 함께 있다")
    func cldrOnly() {
        let bundle = EmojiCuration.empty.candidates(for: "자동차", annotation: car)
        #expect(bundle == ["🚕", "🚗", "🚘", "🛻", "🛞"])
    }

    @Test("override 값은 묶음에 더해지고, 이미 있으면 겹치지 않는다 (D7 맥주→🍺는 묶음 안에서 흡수)")
    func overrideJoinsBundle() {
        #expect(EmojiCuration(overrides: ["맥주": "🍺"]).candidates(for: "맥주", annotation: beer)
                == ["🫚", "🍺", "🍻"])
        #expect(EmojiCuration(overrides: ["맥주": "🍷"]).candidates(for: "맥주", annotation: beer)
                == ["🫚", "🍺", "🍻", "🍷"])
    }

    @Test("fallback 값도 묶음에 더해진다 — 이름 일치가 있어도 마찬가지")
    func fallbackJoinsBundle() {
        let curation = EmojiCuration(fallbacks: ["자동차": "🚙"])
        #expect(curation.candidates(for: "자동차", annotation: car) == ["🚕", "🚗", "🚘", "🛻", "🛞", "🚙"])
    }

    @Test("override와 fallback이 둘 다 있으면 둘 다 더한다")
    func bothSections() {
        let curation = EmojiCuration(overrides: ["맥주": "🍷"], fallbacks: ["맥주": "🥂"])
        #expect(curation.candidates(for: "맥주", annotation: beer) == ["🫚", "🍺", "🍻", "🍷", "🥂"])
    }

    @Test("override 빈 문자열은 막기 — CLDR 후보가 있어도 빈 묶음 (가지·가면·파리·뒤로)")
    func emptyOverrideBlocks() {
        let curation = EmojiCuration(overrides: ["가지": ""], fallbacks: ["가지": "🍆"])
        #expect(curation.candidates(for: "가지", annotation: EmojiAnnotation(emojis: ["🍆"], nameMatch: "🍆")).isEmpty)
    }

    @Test("fallback 빈 문자열은 뜻이 없다 — 무시하고 CLDR 후보는 그대로")
    func emptyFallbackIgnored() {
        #expect(EmojiCuration(fallbacks: ["자동차": ""]).candidates(for: "자동차", annotation: car) == car.emojis)
    }

    @Test("역색인에 없는 단어도 손질 목록에 있으면 그 값 하나다 (콜라)")
    func curationOnlyWord() {
        #expect(EmojiCuration(fallbacks: ["콜라": "🥤"]).candidates(for: "콜라", annotation: nil) == ["🥤"])
    }

    @Test("역색인에도 손질 목록에도 없으면 빈 묶음이다")
    func nothing() {
        #expect(EmojiCuration(fallbacks: ["콜라": "🥤"]).candidates(for: "비행기", annotation: nil).isEmpty)
    }
}
