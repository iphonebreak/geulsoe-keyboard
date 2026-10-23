import KeyboardCore

/// ⌫ 길게 누르기 박자 시간표(PDR `docs/design-reviews/backspace-word-acceleration.md` 1-1).
///
/// 터치다운(누를 때 1회는 키캡이 따로 낸다) → 0.5초부터 80ms 글자 박자 → **2.25초 뒤로는 글자 박자 없음**(마지막 2.18초)
/// → 2.30초 읽기 전용 닻 → 2.6초부터 0.35초마다 단어 박자. 단어 단계 비허용(secure·VoiceOver·스위치 제어)이면 글자 박자만 이어 간다.
/// 다음 박자는 **직전 박자를 실제로 낸 시각**에서 잰다 — 늦게 깨도 밀린 박자를 몰아 내지 않는다.
enum BackspaceRepeatSchedule {

    static let firstRepeat: Duration = .milliseconds(500)
    static let characterInterval: Duration = .milliseconds(80)
    /// 이 시각을 넘는 글자 박자는 내지 않는다 — 닻 전에 직전 삭제가 호스트에 반영될 쉼(D3)
    static let lastCharacterTick: Duration = .milliseconds(2_250)
    static let anchor: Duration = .milliseconds(2_300)
    /// 단어 단계 진입 — 누른 지 2.6초(결정 3)
    static let wordPhase: Duration = .milliseconds(2_600)
    static let wordInterval: Duration = .milliseconds(350)

    /// - Parameters:
    ///   - last: 직전에 낸 박자(nil = 터치다운)
    ///   - elapsed: 직전 박자를 실제로 낸 시각(터치다운 기준)
    static func next(after last: BackspaceRepeatPhase?, at elapsed: Duration,
                     wordPhaseAllowed: Bool) -> (phase: BackspaceRepeatPhase, at: Duration) {
        switch last {
        case nil:
            return (.character, firstRepeat)
        case .character:
            let next = elapsed + characterInterval
            guard wordPhaseAllowed, next > lastCharacterTick else { return (.character, next) }
            return (.anchor, max(anchor, next))
        case .anchor:
            return (.word, max(wordPhase, elapsed + (wordPhase - anchor)))
        case .word:
            return (.word, elapsed + wordInterval)
        }
    }
}

/// ⌫ 반복 루프 — 시간표대로 깨어 **아직 누르고 있을 때만**(`tickAllowed` = `KeyCapPressState.repeatTickAllowed`) 박자를 낸다.
/// 시계를 주입받는다(`swift test`는 가상 시계로 단계 전이·손 뗀 뒤 박자 0을 고정한다).
enum BackspaceRepeatDriver {

    @MainActor
    static func run<C: Clock>(clock: C, wordPhaseAllowed: Bool, tickAllowed: () -> Bool,
                              emit: (BackspaceRepeatPhase) -> Void) async where C.Duration == Duration {
        let start = clock.now
        var last: BackspaceRepeatPhase?
        var lastAt: Duration = .zero
        while true {
            let next = BackspaceRepeatSchedule.next(after: last, at: lastAt, wordPhaseAllowed: wordPhaseAllowed)
            do {
                try await clock.sleep(until: start.advanced(by: next.at), tolerance: nil)
            } catch {
                return
            }
            // 루프 조건에 누름 상태도 본다 — Task 취소가 늦어도 손가락이 떠났으면(취소 포함) 더 내지 않는다
            guard !Task.isCancelled, tickAllowed() else { return }
            emit(next.phase)
            last = next.phase
            lastAt = start.duration(to: clock.now)
        }
    }
}
