import Testing
@testable import KeyboardUI

/// 키캡 누름 상태기계 — 시스템 터치 취소 정리(1.3.1, 사장님 결정 2026-10-15 · 기록 `docs/release/impl-v131-key-touch-cancel.md`).
///
/// 키캡은 누름 상태(눌림·⌫ 반복·대체 입력 무장·트랙패드)를 전부 `onEnded`에서만 정리했다. 시스템이 터치를 취소하면
/// (제어 센터·알림 당기기·전화 배너 — `touchesCancelled`) `onEnded`가 오지 않아 **⌫ 반복이 계속 글을 지웠다**.
/// 뷰(`KeyCapView`)는 `swift test`가 누를 수 없어, 뷰가 상태기계를 부르는 방식을 여기서 그대로 흉내 낸다(`ChipPressStateTests` 선례).
@Suite("키캡 — 누름 상태기계 · 시스템 터치 취소")
struct KeyCapPressStateTests {

    enum Kind {
        case letter
        case backspace
        /// 스페이스(트랙패드가 배선된 경우)
        case space
        /// 길게 누르기 대체 입력이 있는 키(문장부호 `.` → `,` 등)
        case alternate
    }

    enum Step {
        /// 손가락이 닿음 / 누른 채 움직임 — `onChanged`
        case down
        /// ⌫ 반복 한 번(500ms 뒤 80ms마다) — 반복 Task의 루프 조건
        case repeatTick
        /// 450ms 대체 입력 타이머
        case alternateTimer
        /// 400ms 트랙패드 타이머
        case cursorTimer
        /// 손 뗌 — `onEnded`
        case release
        /// 터치를 잃음(제스처 끝 또는 시스템 취소 — `@GestureState` 복귀 뒤 미룬 정리)
        case touchLost
        /// 뷰가 사라짐 — `onDisappear`
        case disappear
    }

    struct Run {
        var deletes = 0
        var primary = 0
        var alternate = 0
        /// 클릭음·진동(`onPress`) 횟수
        var feedback = 0
        var final = KeyCapPressState()
    }

    /// `KeyCapView.pressGesture`·타이머 Task·`onDisappear`가 상태기계를 부르는 방식 그대로
    private func run(_ kind: Kind, _ steps: [Step]) -> Run {
        var state = KeyCapPressState()
        var result = Run()
        for step in steps {
            switch step {
            case .down:
                if state.touchDown() {
                    result.feedback += 1
                    if kind == .backspace {
                        result.deletes += 1
                        state.startRepeating()
                    }
                }
            case .repeatTick:
                if kind == .backspace, state.repeatTickAllowed {
                    result.feedback += 1
                    result.deletes += 1
                }
            case .alternateTimer:
                if kind == .alternate, state.armAlternate() { result.feedback += 1 }
            case .cursorTimer:
                if kind == .space, state.enterCursorMode() { result.feedback += 1 }
            case .release:
                switch state.release(isBackspace: kind == .backspace) {
                case .primary: result.primary += 1
                case .alternate: result.alternate += 1
                case .none: break
                }
            case .touchLost:
                _ = state.touchLost()
            case .disappear:
                state.reset()
            }
        }
        result.final = state
        return result
    }

    // MARK: - 정상 경로(회귀 없음)

    @Test("정상 — 탭·⌫ 반복·대체 입력·트랙패드 그대로")
    func normalPaths() {
        let letter = run(.letter, [.down, .down, .release])
        #expect(letter.primary == 1 && letter.feedback == 1, "누른 채 움직여도 터치다운은 한 번")

        let backspace = run(.backspace, [.down, .repeatTick, .repeatTick, .release, .repeatTick])
        #expect(backspace.deletes == 3, "누를 때 1 + 반복 2, 뗀 뒤 반복 없음")
        #expect(backspace.primary == 0, "⌫는 떼는 순간 아무것도 넣지 않는다(누를 때 이미 지웠다)")

        #expect(run(.alternate, [.down, .release]).primary == 1)
        let armed = run(.alternate, [.down, .alternateTimer, .release])
        #expect(armed.alternate == 1 && armed.primary == 0 && armed.feedback == 2)

        #expect(run(.space, [.down, .release]).primary == 1)
        let trackpad = run(.space, [.down, .cursorTimer, .release])
        #expect(trackpad.primary == 0 && trackpad.feedback == 2, "트랙패드였으면 공백을 넣지 않는다")

        for result in [letter, backspace, armed, trackpad] {
            #expect(result.final == KeyCapPressState(), "손을 떼면 언제나 처음으로")
        }
    }

    // MARK: - 시스템 터치 취소

    @Test("★ ⌫ 길게 누르기 중 시스템 취소 — 반복이 멈춘다(글이 계속 지워지지 않는다)")
    func backspaceRepeatStopsOnTouchLost() {
        let result = run(.backspace, [.down, .repeatTick, .touchLost, .repeatTick, .repeatTick, .repeatTick])
        #expect(result.deletes == 2, "취소 전 1 + 1, 취소 뒤 0")
        #expect(result.final == KeyCapPressState())
    }

    @Test("★ ⌫ 반복 중 뷰가 사라짐(onDisappear) — 반복이 멈춘다")
    func backspaceRepeatStopsOnDisappear() {
        let result = run(.backspace, [.down, .repeatTick, .disappear, .repeatTick, .repeatTick])
        #expect(result.deletes == 2)
    }

    @Test("시스템 취소 — 아무 입력도 새로 일으키지 않고, 다음 탭은 정상", arguments: [
        // (키, 단계, 본래 입력 수, 대체 입력 수, 지운 수)
        (Kind.alternate, [Step.down, .touchLost, .alternateTimer, .down, .release], 1, 0, 0),   // 무장 전 취소 — 늦은 타이머가 무장하지 않는다
        (.alternate, [.down, .alternateTimer, .touchLost, .down, .release], 1, 0, 0),             // 무장 뒤 취소 — 다음 탭에 대체 입력이 새지 않는다
        (.alternate, [.down, .alternateTimer, .touchLost], 0, 0, 0),                              // 취소 자체는 무입력(무장된 대체 입력을 넣지 않는다)
        (.space, [.down, .touchLost, .cursorTimer, .down, .release], 1, 0, 0),                     // 트랙패드 진입 전 취소 — 다음 스페이스는 공백
        (.space, [.down, .cursorTimer, .touchLost, .down, .release], 1, 0, 0),                     // 트랙패드 중 취소 — 다음 스페이스는 공백
        (.letter, [.down, .touchLost, .down, .release], 1, 0, 0),                                  // 눌림만 남았던 키 — 다음 탭 정상
        (.backspace, [.down, .touchLost, .down, .release], 0, 0, 2)                                 // ⌫ 탭 — 다음 탭도 1회 지운다(삼켜지지 않는다)
    ] as [(Kind, [Step], Int, Int, Int)])
    func touchLostAddsNothing(row: (kind: Kind, steps: [Step], primary: Int, alternate: Int, deletes: Int)) {
        let result = run(row.kind, row.steps)
        #expect(result.primary == row.primary)
        #expect(result.alternate == row.alternate)
        #expect(result.deletes == row.deletes)
        #expect(result.final == KeyCapPressState())
    }

    @Test("시스템 취소 — 다음 터치의 클릭음·진동이 정상으로 난다(눌림이 남아 터치다운을 건너뛰지 않는다)")
    func nextTouchGivesFeedback() {
        let result = run(.letter, [.down, .touchLost, .down, .release])
        #expect(result.feedback == 2)
    }

    @Test("정상 손 뗌 뒤 터치 잃음이 또 와도 무해(이중 정리) — 결과·횟수 그대로", arguments: [
        Kind.letter, .backspace, .space, .alternate
    ])
    func touchLostAfterReleaseIsHarmless(kind: Kind) {
        var state = KeyCapPressState()
        _ = state.touchDown()
        _ = state.release(isBackspace: kind == .backspace)
        let first = state.touchLost()
        let second = state.touchLost()
        #expect(!first, "이미 처음 상태라 정리할 것이 없다")
        #expect(!second)
        #expect(state == KeyCapPressState())
    }

    /// 시스템 취소에는 `onEnded`가 오지 않는다 — `onEnded`가 왔다는 것은 손가락이 실제로 떨어졌다는 뜻이다. 정리가 손 뗌보다 먼저 도는
    /// 드문 순서(뷰는 정리를 한 박자 미뤄 막는다)에서도 그 손 뗌은 옛 `onEnded`처럼 **탭으로 넣는다**(키 입력을 잃지 않는다)
    @Test("손 뗌은 옛 onEnded와 같은 식 — 정리가 먼저 돌았어도 실제 손 뗌은 탭으로 넣는다")
    func releaseMatchesOldOnEnded() {
        #expect(run(.letter, [.down, .touchLost, .release]).primary == 1)
        #expect(run(.backspace, [.down, .touchLost, .release]).primary == 0, "⌫는 떼는 순간 아무것도 넣지 않는다")
    }

    @Test("터치 잃음 반환값 = 지금 막 정리했다(뷰가 남은 Task를 끊는다)")
    func touchLostReportsCleanup() {
        var state = KeyCapPressState()
        let idle = state.touchLost()
        #expect(!idle, "누르지 않은 키")
        _ = state.touchDown()
        state.startRepeating()
        #expect(state.isPressed && state.repeatTickAllowed)
        let cleaned = state.touchLost()
        #expect(cleaned)
        #expect(!state.isPressed && !state.repeatTickAllowed && !state.alternateArmed && !state.cursorMode)
    }
}
