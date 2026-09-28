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

/// VoiceOver가 읽는 키 이름·힌트 — `KeyCapAccessibility.name(for:label:)`(키패드 개정 2026-09-28)
@Suite("키캡 — VoiceOver 이름과 힌트")
struct KeyCapAccessibilityNameTests {

    private func keys(_ layout: LayoutDefinition) -> [LayoutDefinition.Key] { layout.rows.flatMap { $0 } }

    /// 이름은 **애플 VoiceOver가 그 글자를 읽는 말** 그대로다 — macOS VoiceOver 음성 출력 표
    /// (`ScreenReader.framework/…/SCROutputSpeechComponent.loctable`, ko): `.` 마침표 · `,` 쉼표 · `*` 별표 · `/` 슬래시 ·
    /// `+` 더하기 · `-`(U+002D) **하이픈**(「빼기」는 U+2212 마이너스 기호의 이름이다 — 이 키는 U+002D를 넣는다).
    /// 키 이름을 입력 뒤 되읽는 말과 맞춰야 「더하기 빼기」를 눌렀는데 「하이픈」이 들어간 것처럼 들리지 않는다.
    @Test("연타 키 둘 — 애플 VoiceOver의 글자 이름으로 읽고, 힌트로 연타를 알린다", arguments: [
        ([".", ",", "*", "/"], "마침표 쉼표 별표 슬래시"),
        (["-", "+"], "하이픈 더하기")
    ])
    func multiTapKey(characters: [String], name: String) throws {
        let layout = LayoutDefinition.layout(for: .keypadPad(page: 0), hangulLayout: .dubeolsik)
        let key = try #require(keys(layout).first { $0.event == .multiTap(characters) })
        #expect(KeyCapAccessibility.name(for: key, label: key.label) == name)
        let hint = try #require(KeyCapAccessibility.hint(for: key))
        #expect(hint.contains("다음 기호"))
        #expect(!hint.contains("네 기호"), "-+는 두 글자다 — 개수를 말하지 않는다")
    }

    @Test("문자 복귀 키 — 「가」도 「ABC」도 「문자 자판」, 「123」은 「기호」", arguments: [
        (InputMode.keypadPad(page: 0), InputMode.hangul, "문자 자판"),
        (.keypadPad(page: 2), .english, "문자 자판"),
        (.symbols, .hangul, "문자 자판"),
        (.hangul, .hangul, "기호")
    ])
    func letterReturnKey(mode: InputMode, letterMode: InputMode, name: String) throws {
        let layout = LayoutDefinition.layout(for: mode, hangulLayout: .dubeolsik, letterMode: letterMode)
        let key = try #require(keys(layout).first { $0.event == .symbols })
        #expect(KeyCapAccessibility.name(for: key, label: key.label) == name)
    }

    @Test("다른 키는 힌트가 없다 — 숫자·페이지·⌫·⏎")
    func noHintElsewhere() {
        let layout = LayoutDefinition.layout(for: .keypadPad(page: 0), hangulLayout: .dubeolsik)
        let others = keys(layout).filter { if case .multiTap = $0.event { false } else { true } }
        #expect(others.allSatisfy { KeyCapAccessibility.hint(for: $0) == nil })
    }
}
