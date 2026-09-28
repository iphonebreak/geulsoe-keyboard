import Testing
import TadakDomain
import KeyboardCore
@testable import KeyboardUI

/// 길게 누르기의 VoiceOver 대체 동작 — 범위와 이름 (v1.2.0 출시 전 마무리 ②, `KeyCapAccessibility` 주석의 표).
@Suite("키캡 — 길게 누르기 VoiceOver 대체 동작")
struct KeyCapAccessibilityTests {

    private func keys(_ layout: LayoutDefinition) -> [LayoutDefinition.Key] { layout.rows.flatMap { $0 } }

    @Test("키패드 페이지 키 — 로터 「이전 페이지」", arguments: 0..<4)
    func pageKey(page: Int) throws {
        let layout = LayoutDefinition.layout(for: .keypadPad(page: page), hangulLayout: .dubeolsik)
        let key = try #require(keys(layout).first { $0.event == .keypadPageNext })
        #expect(KeyCapAccessibility.alternateAction(for: key)
                == .init(name: "이전 페이지", event: .keypadPagePrevious))
    }

    @Test("문장부호 키 — 입력란 종류대로", arguments: [
        (PunctuationKeySpec.standard, ", 입력"),
        (.email, ". 입력"),
        (.url, ".com 입력"),
        (.twitter, "# 입력")
    ])
    func punctuationKey(spec: PunctuationKeySpec, name: String) throws {
        let layout = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, punctuation: spec)
        let key = try #require(keys(layout).first { $0.id == "punct" })
        #expect(KeyCapAccessibility.alternateAction(for: key) == .init(name: name, event: .character(spec.secondary)))
    }

    @Test("문자 키의 길게 누르기 기호는 붙이지 않는다 — 글자마다 「동작 사용 가능」이 붙지 않게")
    func letterKeysExcluded() {
        let layout = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, longPressSymbols: true)
        let letters = keys(layout).filter { $0.alternate != nil && $0.id != "punct" }
        #expect(letters.count > 20, "전제 — 길게 누르기 기호가 붙은 문자 키가 실제로 있다")
        #expect(letters.allSatisfy { KeyCapAccessibility.alternateAction(for: $0) == nil })
    }

    @Test("길게 누르기가 없는 키는 동작도 없다")
    func noAlternateNoAction() {
        let layout = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik)
        #expect(keys(layout).filter { $0.alternate == nil }
            .allSatisfy { KeyCapAccessibility.alternateAction(for: $0) == nil })
    }
}
