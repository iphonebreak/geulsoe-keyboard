import Testing
import KeyboardCore
@testable import KeyboardUI

// ⌫ 길게 누르기 단어 단계 — 박자 시간표·반복 루프·누름 세대(PDR `docs/design-reviews/backspace-word-acceleration.md` 1-1·3-4).
//
// 시간표: 터치다운 → 0.5초부터 80ms 글자 박자(마지막 ≤ 2.25초 → 2.18초) → 2.30초 읽기 전용 닻 → 2.6초부터 0.35초마다 단어 박자.
// 다음 박자는 **직전 박자를 실제로 낸 시각**에서 잰다 — 늦게 깨도 밀린 박자를 몰아 내지 않는다.

@Suite("⌫ 단어 단계 — 박자 시간표")
struct BackspaceRepeatScheduleTests {

    private func next(_ last: BackspaceRepeatPhase?, at milliseconds: Int, allowed: Bool = true)
        -> (phase: BackspaceRepeatPhase, at: Duration) {
        let next = BackspaceRepeatSchedule.next(after: last, at: .milliseconds(milliseconds), wordPhaseAllowed: allowed)
        return (next.phase, next.at)
    }

    /// 시간표를 처음부터 `count`박자 펼친다(박자를 제시각에 냈다고 본다)
    private func unrolled(_ count: Int, allowed: Bool = true) -> [(BackspaceRepeatPhase, Duration)] {
        var last: BackspaceRepeatPhase?
        var at: Duration = .zero
        var result: [(BackspaceRepeatPhase, Duration)] = []
        for _ in 0..<count {
            let next = BackspaceRepeatSchedule.next(after: last, at: at, wordPhaseAllowed: allowed)
            result.append((next.phase, next.at))
            last = next.phase
            at = next.at
        }
        return result
    }

    @Test("첫 반복은 500ms")
    func firstRepeatAt500ms() {
        #expect(next(nil, at: 0) == (.character, .milliseconds(500)))
    }

    @Test("글자 박자는 80ms마다")
    func characterTicksEvery80ms() {
        #expect(next(.character, at: 500) == (.character, .milliseconds(580)))
        #expect(next(.character, at: 1_300) == (.character, .milliseconds(1_380)))
    }

    @Test("2.25초 뒤에는 글자 박자가 없다 — 마지막은 2.18초, 쉼 구간에 문맥 읽기 없음")
    func noCharacterTickAfter2250ms() {
        let ticks = unrolled(30)
        let characters = ticks.filter { $0.0 == .character }
        #expect(characters.count == 22)
        #expect(characters.last?.1 == .milliseconds(2_180))
        #expect(!ticks.contains { $0.0 == .character && $0.1 > .milliseconds(2_250) })
    }

    @Test("닻은 2.30초에 한 번")
    func anchorAt2300ms() {
        let ticks = unrolled(30)
        #expect(ticks.filter { $0.0 == .anchor }.map(\.1) == [.milliseconds(2_300)])
    }

    @Test("단어 단계는 2.6초에 시작")
    func wordPhaseStartsAt2600ms() {
        #expect(unrolled(30).first { $0.0 == .word }?.1 == .milliseconds(2_600))
    }

    @Test("단어 박자는 0.35초마다")
    func wordTicksEvery350ms() {
        let words = unrolled(30).filter { $0.0 == .word }.prefix(3).map(\.1)
        #expect(words == [.milliseconds(2_600), .milliseconds(2_950), .milliseconds(3_300)])
    }

    @Test("단어 단계 비허용(secure·VoiceOver·스위치 제어)이면 80ms 글자 박자만 — 닻·단어 없음")
    func wordPhaseNeverStartsWhenNotAllowed() {
        let ticks = unrolled(60, allowed: false)
        #expect(ticks.allSatisfy { $0.0 == .character })
        #expect(ticks.last?.1 == .milliseconds(500 + 59 * 80))
    }

    @Test("늦게 깨면 그 시각에서 다시 잰다 — 밀린 박자를 몰아 내지 않는다")
    func noCatchUpAfterLateWake() {
        #expect(next(.word, at: 3_500) == (.word, .milliseconds(3_850)))
        #expect(next(.character, at: 2_400) == (.anchor, .milliseconds(2_480)))
        #expect(next(.anchor, at: 2_900) == (.word, .milliseconds(3_200)))
    }
}

/// 박자 시험용 가상 시계 — `sleep(until:)`이 곧바로 그 시각으로 건너뛴다
final class VirtualClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration
        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private var current = Instant(offset: .zero)
    private var sleeps = 0
    /// n번째 잠(1부터)을 이만큼 늦게 깨운다 — 따라잡기 금지 시험용
    var lateWakes: [Int: Duration] = [:]
    var now: Instant { current }
    var minimumResolution: Duration { .zero }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try Task.checkCancellation()
        sleeps += 1
        if current < deadline { current = deadline }
        if let late = lateWakes[sleeps] { current = current.advanced(by: late) }
    }
}

@MainActor
@Suite("⌫ 단어 단계 — 반복 루프(가상 시계)")
struct BackspaceRepeatDriverTests {

    /// `stopAfter`박자를 낸 뒤 손을 뗀다(`tickAllowed` 거짓)
    private func drive(wordPhaseAllowed: Bool, stopAfter: Int,
                       lateWakes: [Int: Duration] = [:]) async -> [(BackspaceRepeatPhase, Duration)] {
        let clock = VirtualClock()
        clock.lateWakes = lateWakes
        let start = clock.now
        var emitted: [(BackspaceRepeatPhase, Duration)] = []
        await BackspaceRepeatDriver.run(
            clock: clock,
            wordPhaseAllowed: wordPhaseAllowed,
            tickAllowed: { emitted.count < stopAfter },
            emit: { phase in emitted.append((phase, start.duration(to: clock.now))) }
        )
        return emitted
    }

    @Test("시간표대로 낸다 — 글자 22회, 2.30초 닻, 2.6·2.95초 단어")
    func driverEmitsScheduleInOrder() async throws {
        let emitted = await drive(wordPhaseAllowed: true, stopAfter: 25)
        try #require(emitted.count == 25)
        #expect(emitted.prefix(22).allSatisfy { $0.0 == .character })
        #expect(emitted.first?.1 == .milliseconds(500))
        #expect(emitted[21].1 == .milliseconds(2_180))
        #expect(emitted[22] == (.anchor, .milliseconds(2_300)))
        #expect(emitted[23] == (.word, .milliseconds(2_600)))
        #expect(emitted[24] == (.word, .milliseconds(2_950)))
    }

    @Test("검증 F2 — 늦게 깨면 그 시각에서 다시 잰다(밀린 박자를 몰아 내지 않는다)")
    func driverDoesNotCatchUpAfterLateWake() async {
        // 세 번째 잠을 380ms 늦게 깨운다 — 0.66초 박자가 1.04초에 나고, 다음은 1.12초(0.74·0.82·…를 몰아 내지 않는다)
        let emitted = await drive(wordPhaseAllowed: true, stopAfter: 5, lateWakes: [3: .milliseconds(380)])
        #expect(emitted.map(\.1) == [.milliseconds(500), .milliseconds(580), .milliseconds(1_040),
                                     .milliseconds(1_120), .milliseconds(1_200)])
    }

    @Test("손을 떼면(`tickAllowed` 거짓) 박자를 더 내지 않는다")
    func endedHoldEmitsNoFurtherTicks() async {
        let emitted = await drive(wordPhaseAllowed: true, stopAfter: 3)
        #expect(emitted.count == 3)
    }

    @Test("단어 단계 비허용이면 글자 박자만")
    func notAllowedEmitsOnlyCharacterTicks() async {
        let emitted = await drive(wordPhaseAllowed: false, stopAfter: 40)
        #expect(emitted.count == 40)
        #expect(emitted.allSatisfy { $0.0 == .character })
    }
}

@Suite("⌫ 단어 단계 — 누름 세대 H")
struct KeyCapBackspaceHoldTests {

    @Test("⌫ 반복은 그 터치의 H를 갖는다")
    func backspaceRepeatCarriesHold() {
        var state = KeyCapPressState()
        let pressed = state.touchDown()
        #expect(pressed)
        state.startRepeating(hold: 42)
        #expect(state.backspaceHold == 42)
        #expect(state.repeatTickAllowed)
    }

    @Test("손 뗌·터치 잃음·사라짐은 H를 지운다")
    func endingClearsHold() {
        for end in 0..<3 {
            var state = KeyCapPressState()
            _ = state.touchDown()
            state.startRepeating(hold: 7)
            switch end {
            case 0: _ = state.release(isBackspace: true)
            case 1: _ = state.touchLost()
            default: state.reset()
            }
            #expect(state.backspaceHold == nil)
            #expect(!state.repeatTickAllowed)
        }
    }

    @Test("누르고 있지 않으면 H를 두지 않는다")
    func holdIsNotSetWhenNotPressed() {
        var state = KeyCapPressState()
        state.startRepeating(hold: 9)
        #expect(state.backspaceHold == nil)
    }
}
