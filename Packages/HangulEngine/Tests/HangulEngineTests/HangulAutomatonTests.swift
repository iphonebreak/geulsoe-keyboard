import Testing
@testable import HangulEngine

@Suite("오토마타 백스페이스")
struct AutomatonBackspaceTests {

    @Test("받침만 지운다", arguments: [
        ("rks", "가", "홑받침 제거"),
        ("rkrt", "각", "겹받침은 뒤쪽만 제거"),
        ("rk", "ㄱ", "중성 제거 후 초성만 남음"),
        ("rhk", "고", "복모음은 앞 모음만 남는다"),
        ("rhl", "고", "ㅚ도 ㅗ로 되돌아간다"),
        ("dml", "으", "ㅢ → ㅡ")
    ])
    func backspaceUndoesOneJamo(keys: String, expected: String, note: String) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(keys)
        harness.backspace()
        #expect(harness.finish() == expected, "\(note)")
    }

    @Test("조합을 다 지우면 빈 문서가 된다")
    func backspaceClearsComposition() {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type("rk")           // 가
        harness.backspace()          // ㄱ
        harness.backspace()          // (빔)
        #expect(harness.finish() == "")
    }

    @Test("조합이 없으면 문서에서 한 글자를 지운다")
    func backspaceDeletesDocumentCharacter() {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type("rk1")          // "가1" — 1은 조합 밖
        harness.backspace()          // 조합이 없으므로 문서에서 삭제
        #expect(harness.finish() == "가")
    }

    @Test("확정된 글자는 자모 단위로 되돌아가지 않는다")
    func backspaceDoesNotReopenCommittedSyllable() {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type("rksk")         // 가나 — "가"는 이미 확정
        harness.backspace()          // 조합 중인 "나"의 ㅏ만 지워진다
        #expect(harness.finish() == "가ㄴ")
    }
}

@Suite("오토마타 확정과 리셋")
struct AutomatonCommitTests {

    @Test("commit은 조합을 확정해 내보낸다")
    func commitFlushesComposition() {
        var automaton = HangulAutomaton()
        _ = automaton.input(.consonant("ㄱ"))
        _ = automaton.input(.vowel("ㅏ"))
        #expect(automaton.isComposing)

        let output = automaton.commit()
        #expect(output.committed == "가")
        #expect(output.composing == "")
        #expect(automaton.isComposing == false)
    }

    @Test("조합이 없으면 commit이 아무것도 내보내지 않는다")
    func commitOnEmptyIsNoop() {
        var automaton = HangulAutomaton()
        let output = automaton.commit()
        #expect(output.committed == "")
        #expect(output.composing == "")
    }

    @Test("reset은 조합을 확정하지 않고 버린다")
    func resetDiscardsComposition() {
        var automaton = HangulAutomaton()
        _ = automaton.input(.consonant("ㄱ"))
        _ = automaton.input(.vowel("ㅏ"))
        automaton.reset()
        #expect(automaton.isComposing == false)
        #expect(automaton.composingText == "")
    }

    /// 커서 이동 시 이 순서를 지키지 않으면 다음 입력이 엉뚱한 위치에 붙는다.
    @Test("커서 이동 전 확정하면 다음 입력이 새 글자로 시작한다")
    func commitBeforeCursorMove() {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type("rk")           // 가 (조합 중)
        harness.commitAndReset()     // 커서 이동 직전에 하는 일
        harness.type("s")            // ㄴ — 앞 글자의 받침이 되면 안 된다
        #expect(harness.finish() == "가ㄴ")
    }

    @Test("확정하지 않고 이어 치면 받침으로 붙는다")
    func withoutCommitConsonantBecomesJongseong() {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type("rk")
        harness.type("s")            // 확정 없이 이어 침
        #expect(harness.finish() == "간")
    }
}

@Suite("두벌식 자판 매핑")
struct DubeolsikSourceTests {

    @Test("상태가 없어 reset이 결과를 바꾸지 않는다")
    func statelessAcrossReset() {
        let source = DubeolsikSource()
        let before = source.accept(key: "r", at: 0)
        source.reset()
        let after = source.accept(key: "r", at: 999)
        #expect(before == after)
        #expect(before == [.emit(.consonant("ㄱ"))])
    }

    @Test("시프트 키는 다른 자모를 낸다")
    func shiftedKeys() {
        let source = DubeolsikSource()
        #expect(source.accept(key: "r", at: 0) == [.emit(.consonant("ㄱ"))])
        #expect(source.accept(key: "R", at: 0) == [.emit(.consonant("ㄲ"))])
        #expect(source.accept(key: "o", at: 0) == [.emit(.vowel("ㅐ"))])
        #expect(source.accept(key: "O", at: 0) == [.emit(.vowel("ㅒ"))])
    }

    @Test("시프트 전용 자모가 없는 키는 대소문자가 같은 결과를 낸다")
    func unshiftedUppercaseFallsBack() {
        let source = DubeolsikSource()
        #expect(source.accept(key: "k", at: 0) == source.accept(key: "K", at: 0))
        #expect(source.accept(key: "a", at: 0) == source.accept(key: "A", at: 0))
    }

    @Test("자모가 아닌 키는 빈 배열을 낸다", arguments: ["1", "!", " ", "가", ""])
    func nonJamoKeys(key: String) {
        #expect(DubeolsikSource().accept(key: key, at: 0).isEmpty)
    }
}
