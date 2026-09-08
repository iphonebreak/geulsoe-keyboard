import Foundation
import Testing
@testable import KeyboardCore

/// 주입 시계 — 더블스페이스 타임아웃(0.35초)을 결정적으로 검증한다.
private final class TestClock {
    var now: TimeInterval = 0
}

@MainActor
@Suite("더블스페이스 마침표")
struct DoubleSpacePeriodTests {

    private func makeController() -> (RecordingOutput, InputController, TestClock) {
        let output = RecordingOutput()
        let clock = TestClock()
        let controller = InputController(output: output, clock: { clock.now })
        return (output, controller, clock)
    }

    @Test("짧은 간격의 스페이스 두 번이 '. '가 된다")
    func substitutes() {
        let (output, controller, clock) = makeController()
        for key in ["d", "k", "s"] { controller.handle(.character(key)) }  // 안
        clock.now = 1.0
        controller.handle(.space)
        clock.now = 1.2
        controller.handle(.space)
        #expect(output.text == "안. ")
        #expect(output.operations.suffix(2) == [.delete(1), .insert(". ")])
        #expect(controller.textTail == "안. ", "꼬리도 문서와 같아야 한다")
    }

    @Test("타임아웃을 넘기면 그냥 공백 두 개다")
    func timeoutKeepsSpaces() {
        let (output, controller, clock) = makeController()
        for key in ["d", "k", "s"] { controller.handle(.character(key)) }
        clock.now = 1.0
        controller.handle(.space)
        clock.now = 1.5  // 0.35초 초과
        controller.handle(.space)
        #expect(output.text == "안  ")
    }

    @Test("사이에 다른 입력이 끼면 발동하지 않는다")
    func interveningInputBreaksChain() {
        let (output, controller, clock) = makeController()
        for key in ["d", "k", "s"] { controller.handle(.character(key)) }
        clock.now = 1.0
        controller.handle(.space)
        controller.handle(.character("1"))
        clock.now = 1.1
        controller.handle(.space)
        clock.now = 1.2
        controller.handle(.space)
        // "안 1" 뒤의 더블스페이스는 발동한다 (1은 문장 문자)
        #expect(output.text == "안 1. ")
    }

    @Test("공백·쉼표 뒤에서는 발동하지 않는다")
    func nonSentenceCharactersDoNotTrigger() {
        let (output, controller, clock) = makeController()
        for key in ["d", "k", "s"] { controller.handle(.character(key)) }
        clock.now = 1.0
        controller.handle(.space)
        clock.now = 1.1
        controller.handle(.space)  // → "안. "
        clock.now = 1.2
        controller.handle(.space)  // 치환 후 연쇄는 끊긴다 → "안.  "
        clock.now = 1.3
        controller.handle(.space)  // 공백 앞이 공백 — 비발동 → "안.   "
        #expect(output.text == "안.   ")

        controller.handle(.character(","))  // 한글 모드 비자모 — 그대로 삽입
        clock.now = 2.0
        controller.handle(.space)
        clock.now = 2.1
        controller.handle(.space)
        #expect(output.text == "안.   ,  ", "쉼표 뒤는 마침표로 바꾸지 않는다")
    }

    @Test("영어 모드에서도 동작하고, 설정을 끄면 멈춘다")
    func englishAndSettingToggle() {
        let (output, controller, clock) = makeController()
        controller.handle(.toggleLanguage)
        controller.handle(.character("a"))
        clock.now = 1.0
        controller.handle(.space)
        clock.now = 1.2
        controller.handle(.space)
        #expect(output.text == "a. ")

        controller.doubleSpacePeriod = false
        controller.handle(.character("b"))
        clock.now = 2.0
        controller.handle(.space)
        clock.now = 2.1
        controller.handle(.space)
        #expect(output.text == "a. b  ")
    }
}
