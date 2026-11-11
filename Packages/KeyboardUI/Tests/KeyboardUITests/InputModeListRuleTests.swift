import Foundation
import Testing
import KeyboardCore
@testable import KeyboardUI

/// 한영 키에 지구본 합치기(1.4.0, PDR `language-globe-key.md`) — 키캡이 터치를 시스템 키보드 목록으로 넘기는지.
///
/// 넘기는 누름은 짧은 탭인지 길게 누르기인지를 **시스템이** 정한다(짧은 탭이면 `advanceToNextInputMode`를 부르고, VC가 그것을 한영 전환으로 바꾼다).
/// 그러니 넘긴 누름의 손 뗌에 키캡이 `.toggleLanguage`를 또 내면 **한영이 두 번 바뀐다** — 키캡은 터치 층이 알려 주는
/// 「시스템이 판정함」(`KeyTouchHandlers.ended`)을 보고 침묵한다.
@Suite("키캡 — 한영 키의 키보드 목록 통로")
struct InputModeListRuleTests {

    private let mergedLanguage = LayoutDefinition.Key(id: "language", label: "ABC", event: .toggleLanguage,
                                                      width: 1.2, isFunctionKey: true, opensInputModeList: true)
    private let plainLanguage = LayoutDefinition.Key(id: "language", label: "ABC", event: .toggleLanguage,
                                                     width: 1.2, isFunctionKey: true)

    @Test("목록을 여는 키 ∧ 통로가 있을 때만 넘긴다")
    func mergedKeyRoutes() {
        #expect(InputModeListRule.routes(mergedLanguage, handlerAvailable: true))
        #expect(!InputModeListRule.routes(mergedLanguage, handlerAvailable: false), "통로가 없으면(macOS) 평범한 한영 키")
    }

    @Test("목록을 열지 않는 키는 통로가 있어도 넘기지 않는다")
    func otherKeysNeverRoute() {
        for key in [plainLanguage,
                    LayoutDefinition.Key(id: "space", label: " ", event: .space, width: 4.4),
                    LayoutDefinition.Key(id: "q", label: "q", event: .character("q"))] {
            #expect(!InputModeListRule.routes(key, handlerAvailable: true), "\(key.id)")
        }
    }
}

/// 빠른 두 번 탭(리뷰 HIGH, 2026-11-11) — 시스템은 넘긴 누름마다 began에서 약 200ms 타이머를 걸고, 타이머는 「아직 판정 안 됨」이면 목록을 연다.
/// 둘째 탭의 began이 판정 상태를 되돌리면 **첫 탭의 타이머가** 둘째 누름 도중 목록을 열고 둘째 전환은 사라진다.
/// 그래서 직전에 넘긴 누름에서 `reentryWindow` 안에 닿은 누름은 넘기지 않는다 — 그 누름은 키캡이 손 뗌에 한영을 낸다.
@Suite("키캡 — 키보드 목록 통로의 누름 단위 판정")
struct InputModeListGateTests {

    private let window = InputModeListGate.reentryWindow

    /// 같은 판정기로 시각마다 누름을 넣고 넘겼는지를 모은다
    private func claims(_ times: [TimeInterval]) -> [Bool] {
        var gate = InputModeListGate()
        return times.map { gate.claim(at: $0) }
    }

    @Test("첫 누름은 넘긴다")
    func firstPressIsForwarded() {
        #expect(claims([100]) == [true])
    }

    @Test("직전에 넘긴 누름에서 창 안에 닿은 누름은 넘기지 않는다 — 첫 탭의 시스템 타이머가 둘째 누름을 가로채지 않게")
    func pressInsideWindowIsNotForwarded() {
        #expect(claims([100, 100.18]) == [true, false])
        #expect(claims([100, 100 + window - 0.001]) == [true, false])
    }

    @Test("창은 시스템 타이머(약 200ms)보다 길다 — 타이머가 늦게 돌아도 여유가 있다")
    func windowCoversSystemTimer() {
        #expect(window > 0.2)
        #expect(window <= 0.4, "길면 연타 뒤 길게 누르기(목록)가 늦게 살아난다")
    }

    @Test("창은 **넘긴** 누름에서 잰다 — 넘기지 않은 누름은 창을 늘리지 않는다(연타가 길어져도 목록 길이 계속 막히지 않게)")
    func windowIsMeasuredFromLastForwardedPress() {
        #expect(claims([100, 100.15, 100 + window + 0.001, 100 + window + 0.1]) == [true, false, true, false])
    }

    @Test("창이 지난 뒤의 누름은 다시 넘긴다 — 보통 속도의 한영 연속 전환")
    func pressAfterWindowIsForwarded() {
        #expect(claims([100, 100.5, 101]) == [true, true, true])
    }

    @Test("시계가 거꾸로 가면(있을 수 없지만) 넘긴다 — 목록 길을 잃지 않는 쪽")
    func clockGoingBackwardsForwards() {
        #expect(claims([100, 50]) == [true, true])
    }
}
