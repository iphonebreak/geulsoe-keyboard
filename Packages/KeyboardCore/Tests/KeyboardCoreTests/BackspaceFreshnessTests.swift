import Testing
@testable import KeyboardCore

/// ⌫ 단어 단계 — 문맥 신선성 판정(PDR `backspace-word-acceleration.md` 3-3)과 누름 세대 게이트(3-4).
///
/// `신선(C, S)` ⇔ ① C가 「직전 문맥에서 지운 만큼 뺀 것」으로 끝난다 ∧ ② 지웠는데(k > 0) 문맥이 그대로가 아니다.
/// 불일치 수는 **누름 단위로 누적**한다 — 성공해도 되돌리지 않는다(반론 CW-01).
@Suite("⌫ 단어 단계 — 문맥 신선성")
struct BackspaceFreshnessTests {

    @Test("지운 만큼 줄어든 문맥은 신선하다")
    func freshWhenContextEndsWithExpectation() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "one two three", deleted: 6)
        #expect(freshness.isFresh("one two"))
    }

    @Test("문맥 창이 왼쪽으로 늘어나도 신선하다")
    func freshWhenWindowGrowsLeft() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "two three four", deleted: 5)
        #expect(freshness.isFresh("zero one two three"))
    }

    @Test("지웠는데 문맥이 그대로면 낡은 값")
    func staleWhenContextUnchangedAfterDeletion() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "one two three", deleted: 6)
        #expect(!freshness.isFresh("one two three"))
    }

    @Test("ⓑ 지운 뒤 같은 값이 다시 와도 신선하지 않다 (같은 만큼 낡은 두 읽기)")
    func equallyStaleReadAfterDeletionIsNotFresh() {
        var freshness = BackspaceFreshness()
        let frozen = "alpha bravo charlie"
        freshness.record(context: frozen, deleted: 8)
        #expect(!freshness.isFresh(frozen))
    }

    @Test("호스트가 덜 지웠으면 불일치")
    func mismatchWhenHostDeletedFewer() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "one two three", deleted: 6)
        #expect(!freshness.isFresh("one two t"))
    }

    @Test("호스트가 더 지웠으면 불일치")
    func mismatchWhenHostDeletedMore() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "one two three", deleted: 6)
        #expect(!freshness.isFresh("one tw"))
    }

    @Test("커서가 옮겨 가면 불일치")
    func mismatchAfterCursorMove() {
        var freshness = BackspaceFreshness()
        freshness.record(context: "one two three", deleted: 6)
        #expect(!freshness.isFresh("hello world"))
    }

    @Test("주기적인 글 — 반영됐어도 창이 같아 보이면 낡은 쪽으로 본다(안전)")
    func periodicTextUnchangedWindowTreatedAsStale() {
        var freshness = BackspaceFreshness()
        let window = String(repeating: "ha ", count: 30)
        freshness.record(context: window, deleted: 6)
        #expect(!freshness.isFresh(window))
    }

    @Test("닻(k = 0) 뒤 같은 값은 신선하다")
    func anchorThenEqualReadIsFresh() {
        var freshness = BackspaceFreshness()
        freshness.anchor("one two three")
        #expect(freshness.isFresh("one two three"))
    }

    @Test("ⓐ 불일치 수는 누름 단위로 누적 — 불일치 · 성공 · 불일치면 꺼진다 (CW-01)")
    func mismatchCountAccumulatesPerHold() {
        var freshness = BackspaceFreshness()
        #expect(freshness.noteMismatch() == false)
        freshness.record(context: "one two three", deleted: 6)   // 성공한 단계 — 되돌리지 않는다
        #expect(freshness.mismatches == 1)
        #expect(freshness.noteMismatch() == true)
    }

    @Test("사슬이 없으면 판정하지 않는다(닻·다시 잡기가 먼저)")
    func noChainIsNeverFresh() {
        let freshness = BackspaceFreshness()
        #expect(!freshness.hasChain)
        #expect(!freshness.isFresh("anything"))
    }
}

@Suite("⌫ 단어 단계 — 누름 세대 게이트")
struct BackspaceHoldGateTests {

    @Test("끝낸 누름의 박자는 받지 않는다")
    func tickAfterEndIsDropped() {
        var gate = BackspaceHoldGate()
        gate.begin(1)
        gate.end(1)
        #expect(!gate.accepts(1))
    }

    @Test("ⓒ 시스템 취소 — 큐에 들어간 박자보다 동기 끝냄이 먼저면 박자는 0건")
    func systemCancelEndsHoldBeforeQueuedTick() {
        var gate = BackspaceHoldGate()
        var queue: [(inout BackspaceHoldGate) -> Bool] = []
        gate.begin(7)
        queue.append { $0.accepts(7) }   // 반복 Task가 `main.async`로 보낸 박자
        gate.end(7)                       // `onChange(of: isTouching)` 동기 부분
        let executed = queue.map { $0(&gate) }.filter { $0 }.count
        #expect(executed == 0)
    }

    @Test("ⓓ 옛 터치의 늦은 끝냄은 새 누름을 끝내지 않는다")
    func staleOnChangeDoesNotEndNewHold() {
        var gate = BackspaceHoldGate()
        gate.begin(1)
        gate.begin(2)
        gate.end(1)
        #expect(gate.accepts(2))
        #expect(!gate.accepts(1))
    }

    @Test("키보드가 내려가면 전부 끝낸다")
    func endAllOnDisappear() {
        var gate = BackspaceHoldGate()
        gate.begin(3)
        gate.endAll()
        #expect(!gate.accepts(3))
    }
}

@Suite("⌫ 단어 단계 — 허용 판정 (출시 상수·secure·접근성)")
struct BackspaceWordPhasePolicyTests {

    @Test("기본 — 출시 상수 켬, secure·VoiceOver·스위치 제어가 아니면 허용")
    func allowsByDefault() {
        #expect(BackspaceWordPhasePolicy.shipEnabled)
        #expect(BackspaceWordPhasePolicy.allows(isSecureTextEntry: false, isVoiceOverRunning: false, isSwitchControlRunning: false))
    }

    @Test("secure·VoiceOver·스위치 제어 중 하나라도면 비허용(D2)")
    func disallowsSecureAndAccessibility() {
        #expect(!BackspaceWordPhasePolicy.allows(isSecureTextEntry: true, isVoiceOverRunning: false, isSwitchControlRunning: false))
        #expect(!BackspaceWordPhasePolicy.allows(isSecureTextEntry: false, isVoiceOverRunning: true, isSwitchControlRunning: false))
        #expect(!BackspaceWordPhasePolicy.allows(isSecureTextEntry: false, isVoiceOverRunning: false, isSwitchControlRunning: true))
    }

    @Test("C2W-04 출시 상수를 끄면 언제나 비허용 — 80ms 글자 반복만(손 뗌 세대 검사는 그대로)")
    func shipSwitchOffDisallowsEverywhere() {
        for secure in [false, true] {
            for voiceOver in [false, true] {
                #expect(!BackspaceWordPhasePolicy.allows(isSecureTextEntry: secure, isVoiceOverRunning: voiceOver,
                                                         isSwitchControlRunning: false, shipEnabled: false))
            }
        }
    }
}
