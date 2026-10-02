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
