import Testing
@testable import HangulEngine

/// `HangulAutomaton.replaceLast` — 마지막 자모 교체 연산.
///
/// backspace+input으로 대체할 수 없는 이유(복모음 분해)와 의미 규칙은
/// `docs/design-reviews/cheonjiin-danmoeum-layouts.md` 참조.
@Suite("오토마타 replaceLast")
struct ReplaceLastTests {

    private func composed(_ jamos: [Jamo]) -> HangulAutomaton {
        var automaton = HangulAutomaton()
        for jamo in jamos { _ = automaton.input(jamo) }
        return automaton
    }

    @Test("모음은 중성 전체를 교체한다")
    func replacesWholeJungseong() {
        var automaton = composed([.consonant("ㄱ"), .vowel("ㅣ")])
        let output = automaton.replaceLast(.vowel("ㅏ"))
        #expect(output.composing == "가")
        #expect(output.committed.isEmpty)
    }

    @Test("복모음도 통째로 교체한다 — 분해하지 않는다 (ㅚ → ㅘ)")
    func replacesCompoundJungseongWholly() {
        var automaton = composed([.consonant("ㄱ"), .vowel("ㅚ")])
        let output = automaton.replaceLast(.vowel("ㅘ"))
        #expect(output.composing == "과")
        #expect(output.committed.isEmpty)
    }

    @Test("홑받침은 통째로 교체한다 (각 → 갘)")
    func replacesSimpleJongseong() {
        var automaton = composed([.consonant("ㄱ"), .vowel("ㅏ"), .consonant("ㄱ")])
        let output = automaton.replaceLast(.consonant("ㅋ"))
        #expect(output.composing == "갘")
    }

    @Test("겹받침은 뒤 성분만 교체한다 — 결합 불가면 다음 글자로 (닭 + ㅋ)")
    func replacesLastComponentOfCompoundJongseong() {
        var automaton = composed([.consonant("ㄷ"), .vowel("ㅏ"), .consonant("ㄹ"), .consonant("ㄱ")])
        let output = automaton.replaceLast(.consonant("ㅋ"))
        #expect(output.committed == "달")
        #expect(output.composing == "ㅋ")
    }

    @Test("받침 불가 자모로 교체하면 받침을 빼고 다음 글자 초성으로 (간 + ㄸ)")
    func nonJongseongReplacementStartsNewSyllable() {
        var automaton = composed([.consonant("ㄱ"), .vowel("ㅏ"), .consonant("ㄴ")])
        let output = automaton.replaceLast(.consonant("ㄸ"))
        #expect(output.committed == "가")
        #expect(output.composing == "ㄸ")
    }

    @Test("초성만 있으면 초성을 교체한다 (순환)")
    func replacesChoseong() {
        var automaton = composed([.consonant("ㄱ")])
        let output = automaton.replaceLast(.consonant("ㅋ"))
        #expect(output.composing == "ㅋ")
    }

    @Test("교체할 것이 없으면 입력과 같다")
    func fallsBackToInput() {
        var automaton = HangulAutomaton()
        let output = automaton.replaceLast(.consonant("ㄱ"))
        #expect(output.composing == "ㄱ")
        #expect(output.committed.isEmpty)
    }

    /// 소스 2종은 이 상태를 만들지 않지만(자음 뒤엔 모음 replaceLast를 내보내지 않음),
    /// 공용 정식 연산이므로 폴백 계약을 고정해 둔다 — 향후 자판이 밟으면 도깨비불이다.
    @Test("종성이 있는데 모음 교체가 오면 입력 폴백 — 도깨비불")
    func vowelReplacementWithJongseongFallsBackToInput() {
        var automaton = composed([.consonant("ㄱ"), .vowel("ㅏ"), .consonant("ㄴ")])
        let output = automaton.replaceLast(.vowel("ㅑ"))
        #expect(output.committed == "가")
        #expect(output.composing == "냐")
    }
}
