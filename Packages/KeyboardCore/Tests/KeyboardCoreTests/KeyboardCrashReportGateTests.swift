import Testing
@testable import KeyboardCore

// 백로그 14 (나) 키보드 Crashlytics 시작 판정 — SDK 없이 상태 전이만 고정한다(보안 규칙 N4′ ②).
// PDR `docs/design-reviews/keyboard-crashlytics.md` 4-2(FA 없으면 시작 안 함)·5-2(한 번만)·5-5 T7·T11·6-8 (나) 행 #7~#10.
// R1(2026-10-26) — 남은 보고서 삭제안은 SDK 순서상 효과가 없어 철회하고 공개 고지로 대체했다(시작 = configure → 수집 켬, N4′ ③). 검증 #5 — 설정 파일은 opt-in ∧ FA일 때만 읽는다.

/// 한 번의 등장(같은 프로세스의 VC 하나)에서 조립 지점이 넘기는 값
private struct Appearance {
    var optedIn = true
    var fullAccess = true
    var configuration = true
}

/// 설정 파일 읽기 횟수를 센다 — `hasConfiguration`은 판정이 필요할 때만 평가돼야 한다(검증 #5)
private final class ConfigurationProbe {
    private(set) var reads = 0
    let available: Bool
    init(available: Bool) { self.available = available }
    func read() -> Bool {
        reads += 1
        return available
    }
}

private func step(_ phase: KeyboardCrashReportPhase, _ input: Appearance) -> KeyboardCrashReportStep {
    KeyboardCrashReportGate.step(
        from: phase,
        KeyboardCrashReportConditions(optedIn: input.optedIn, hasFullAccess: input.fullAccess),
        hasConfiguration: input.configuration)
}

/// 여러 등장을 차례로 흘려 넣고 나온 동작을 모은다
private func run(_ inputs: [Appearance], from phase: KeyboardCrashReportPhase = .notStarted)
    -> (phase: KeyboardCrashReportPhase, actions: [KeyboardCrashReportAction]) {
    var current = phase
    var actions: [KeyboardCrashReportAction] = []
    for input in inputs {
        let next = step(current, input)
        current = next.phase
        actions.append(next.action)
    }
    return (current, actions)
}

@Suite("키보드 크래시 보고 — 시작 판정")
struct KeyboardCrashReportGateTests {

    @Test("opt-in ∧ 전체 접근 ∧ 설정 파일이 모두 참일 때만 시작한다 — 8조합 중 1개(4-2)")
    func startsOnlyWhenOptedInWithFullAccessAndConfiguration() {
        for optedIn in [false, true] {
            for fullAccess in [false, true] {
                for configuration in [false, true] {
                    let result = step(.notStarted,
                                      Appearance(optedIn: optedIn, fullAccess: fullAccess, configuration: configuration))
                    if optedIn, fullAccess, configuration {
                        #expect(result == KeyboardCrashReportStep(phase: .collecting, action: .start))
                    } else {
                        #expect(result == KeyboardCrashReportStep(phase: .notStarted, action: .none),
                                "optIn \(optedIn) · FA \(fullAccess) · 설정 \(configuration)")
                    }
                }
            }
        }
    }

    @Test("설정 파일은 opt-in ∧ 전체 접근일 때만 읽는다 — 꺼진 프로세스는 plist도 열지 않는다(검증 #5)")
    func readsConfigurationOnlyWhenCollectionAllowed() {
        for optedIn in [false, true] {
            for fullAccess in [false, true] {
                let probe = ConfigurationProbe(available: true)
                _ = KeyboardCrashReportGate.step(
                    from: .notStarted,
                    KeyboardCrashReportConditions(optedIn: optedIn, hasFullAccess: fullAccess),
                    hasConfiguration: probe.read())
                #expect(probe.reads == (optedIn && fullAccess ? 1 : 0), "optIn \(optedIn) · FA \(fullAccess)")
            }
        }
    }

    @Test("시작한 뒤에는 설정 파일을 다시 보지 않는다 — 수집 중·정지 중 어느 조건에서도")
    func neverReadsConfigurationAfterStart() {
        for phase in [KeyboardCrashReportPhase.collecting, .paused] {
            for allowed in [false, true] {
                let probe = ConfigurationProbe(available: false)
                _ = KeyboardCrashReportGate.step(
                    from: phase,
                    KeyboardCrashReportConditions(optedIn: allowed, hasFullAccess: allowed),
                    hasConfiguration: probe.read())
                #expect(probe.reads == 0, "\(phase) · 허용 \(allowed)")
            }
        }
    }

    @Test("같은 프로세스에서 VC가 여러 번 생겨도 시작은 한 번뿐이다(T7)")
    func repeatedAppearancesStartOnce() {
        let result = run(Array(repeating: Appearance(), count: 5))
        #expect(result.actions == [.start, .none, .none, .none, .none])
        #expect(result.phase == .collecting)
    }

    @Test("설정 파일이 없으면 끝까지 시작하지 않는다 — 조용히(예외 없음)")
    func missingConfigurationNeverStarts() {
        let result = run(Array(repeating: Appearance(configuration: false), count: 3))
        #expect(result.actions == [.none, .none, .none])
        #expect(result.phase == .notStarted)
    }

    @Test("꺼진 동안은 아무것도 하지 않고, 켠 뒤에도 그 기간을 소급하지 않는다 — 켠 순간이 첫 시작(6-8 #10)")
    func optedOutPeriodNeverStartsAndOptInStartsFresh() {
        let result = run([Appearance(optedIn: false), Appearance(optedIn: false), Appearance()])
        #expect(result.actions == [.none, .none, .start])
    }

    @Test("같은 프로세스 안에서 OFF → ON이면 다음 판정에서 시작한다(6-8 #7)")
    func optInInSameProcessStartsAtNextEvaluation() {
        let result = run([Appearance(optedIn: false), Appearance(optedIn: true)])
        #expect(result.actions == [.none, .start])
        #expect(result.phase == .collecting)
    }

    @Test("시작한 뒤 opt-in을 끄면 수집을 한 번 끈다 — 다시 시작하지 않는다(6-8 #8, T11)")
    func optOutAfterStartPausesCollectionOnce() {
        let result = run([Appearance(), Appearance(optedIn: false), Appearance(optedIn: false)])
        #expect(result.actions == [.start, .pauseCollection, .none])
        #expect(result.phase == .paused)
    }

    @Test("시작한 뒤 전체 접근이 꺼져도 수집을 끈다(6-8 #9, T11)")
    func fullAccessLossAfterStartPausesCollection() {
        let result = run([Appearance(), Appearance(fullAccess: false)])
        #expect(result.actions == [.start, .pauseCollection])
        #expect(result.phase == .paused)
    }

    @Test("끈 뒤 다시 켜면 configure를 다시 부르지 않고 수집만 켠다(이중 configure 방지)")
    func reOptInAfterPauseResumesWithoutReconfiguring() {
        let result = run([Appearance(), Appearance(optedIn: false), Appearance(), Appearance()])
        #expect(result.actions == [.start, .pauseCollection, .resumeCollection, .none])
        #expect(result.actions.filter { $0 == .start }.count == 1)
        #expect(result.phase == .collecting)
    }

    @Test("끈 상태에서 전체 접근만 돌아와도 opt-in이 꺼져 있으면 수집을 켜지 않는다")
    func pausedStaysPausedWithoutOptIn() {
        let result = run([Appearance(optedIn: false, fullAccess: true)], from: .paused)
        #expect(result.actions == [.none])
        #expect(result.phase == .paused)
    }
}

@Suite("키보드 크래시 보고 — SDK 호출 순서(N4′ ③)")
struct KeyboardCrashReportSDKCallTests {

    @Test("시작 = configure → 수집 켬. 남은 보고서 삭제는 부르지 않는다(R1 공개 고지로 대체, 2026-10-26)")
    func startConfiguresThenEnablesCollection() {
        // 삭제안은 SDK 안에서 수집 켬과 경쟁해 지는 것으로 읽혀(최종 검증 #1) 철회했다 — 끈 뒤 남은 보고서는 다시 켜면 전송될 수 있다고 처리방침에 밝힌다
        #expect(KeyboardCrashReportAction.start.sdkCalls == [.configure, .setCollectionEnabled(true)])
    }

    @Test("정지·재개는 수집 값만 바꾼다 — configure를 다시 부르지 않는다")
    func pauseAndResumeOnlyToggleCollection() {
        #expect(KeyboardCrashReportAction.pauseCollection.sdkCalls == [.setCollectionEnabled(false)])
        #expect(KeyboardCrashReportAction.resumeCollection.sdkCalls == [.setCollectionEnabled(true)])
        #expect(KeyboardCrashReportAction.none.sdkCalls.isEmpty)
    }

    @Test("configure는 시작에서만, 한 프로세스의 어떤 전이에서도 한 번이다")
    func configureHappensOncePerProcess() {
        let inputs = [Appearance(), Appearance(optedIn: false), Appearance(), Appearance(fullAccess: false), Appearance()]
        let calls = run(inputs).actions.flatMap(\.sdkCalls)
        #expect(calls.filter { $0 == .configure }.count == 1)
        #expect(calls.last == .setCollectionEnabled(true))
    }
}
