import Foundation

/// 키캡 한 번의 누름 — `onEnded`에서만 정리되던 상태를 한 값에 모았다(1.3.1 시스템 터치 취소 정리, 사장님 결정 2026-10-15).
///
/// **왜:** 시스템이 터치를 취소하면(제어 센터·알림 센터 당기기·전화 배너 — `touchesCancelled`) SwiftUI `DragGesture`는
/// `onEnded`를 부르지 않는다. 키캡은 눌림·⌫ 반복·대체 입력 무장·트랙패드를 전부 `onEnded`에서만 정리했으므로,
/// ⌫를 길게 누른 채 취소되면 **반복 Task가 80ms마다 글을 계속 지웠다**(같은 ⌫를 다시 눌렀다 떼야 멈추고, 뷰가 사라지면 멈출 길이 없다).
/// 뷰는 누름 여부를 `@GestureState`로 하나 더 쥐고, 그것이 거짓이 되면 `touchLost()`로 남은 누름을 버린다(칩 `ChipPressState` 선례).
///
/// **판정만 여기, 일은 뷰가 한다** — 클릭음·`onEvent`·Task는 `KeyCapView`가 결과대로 부른다(`swift test`는 제스처를 누를 수 없다).
/// 모든 「늦게 깬」 경로는 `isPressed`를 본다 — 취소·손 뗌 뒤에 깬 타이머·반복은 아무것도 하지 않는다. 기록 `docs/release/impl-v131-key-touch-cancel.md`
struct KeyCapPressState: Equatable {

    /// 손을 뗄 때 넣을 것
    enum Release: Equatable {
        /// 아무것도 — ⌫(누를 때 이미 지웠다)·트랙패드였을 때(공백을 넣지 않는다)
        case none
        /// 키의 본래 이벤트
        case primary
        /// 길게 눌러 무장된 대체 입력(`key.alternate`)
        case alternate
    }

    /// 눌림 — 배경 60%·확대 미리보기
    private(set) var isPressed = false
    /// 길게 누르기 대체 입력 무장(450ms) — 표면 라벨이 대체 글자로 바뀐다
    private(set) var alternateArmed = false
    /// 스페이스 트랙패드(400ms) — 표면이 ↔로 바뀌고 드래그가 커서를 옮긴다
    private(set) var cursorMode = false
    /// ⌫ 반복(500ms 뒤 80ms마다) 진행 중
    private(set) var isRepeating = false
    /// ⌫ 누름 세대 H — 이 터치의 반복 박자에 붙는다. 손 뗌·터치 잃음·사라짐에서 뷰가 **이 값으로** 누름을 끝내고(동기),
    /// 상태가 처음으로 돌아가며 지워진다(PDR `backspace-word-acceleration.md` 3-4)
    private(set) var backspaceHold: UInt64?

    /// 손이 닿았다(`onChanged`) — **지금 막 눌렸으면 true**: 뷰가 터치다운 일(클릭음·⌫ 1회·타이머)을 한다. 누른 채 움직이면 false
    mutating func touchDown() -> Bool {
        guard !isPressed else { return false }
        isPressed = true
        return true
    }

    /// ⌫ 반복을 시작한다 — 누르고 있을 때만. `hold`는 이 터치의 누름 세대
    mutating func startRepeating(hold: UInt64? = nil) {
        guard isPressed else { return }
        isRepeating = true
        backspaceHold = hold
    }

    /// 반복 한 번을 해도 되나 — **아직 누르고 있고 반복 중일 때만**. 반복 Task의 루프 조건이다:
    /// Task를 끊는 데 실패해도(취소 신호가 늦어도) 이 값이 거짓이면 더 지우지 않는다
    var repeatTickAllowed: Bool {
        isPressed && isRepeating
    }

    /// 450ms 대체 입력 타이머가 깼다 — 누르고 있을 때만 무장. **지금 막 무장했으면 true**(뷰가 피드백 1회)
    mutating func armAlternate() -> Bool {
        guard isPressed, !alternateArmed else { return false }
        alternateArmed = true
        return true
    }

    /// 400ms 트랙패드 타이머가 깼다 — 누르고 있을 때만 진입. **지금 막 진입했으면 true**(뷰가 이동 기준을 잡고 피드백 1회)
    mutating func enterCursorMode() -> Bool {
        guard isPressed, !cursorMode else { return false }
        cursorMode = true
        return true
    }

    /// 손을 뗐다(`onEnded`) — 넣을 것을 정하고 **언제나 처음으로** 돌아간다. 트랙패드였으면 아무것도 넣지 않고,
    /// ⌫는 누를 때 이미 지웠으므로 아무것도 넣지 않는다 — **옛 `onEnded`와 같은 식**(눌림 여부는 보지 않는다:
    /// `onEnded`는 손가락이 실제로 떨어졌다는 뜻이라 탭으로 넣는다. 시스템 취소에는 `onEnded`가 오지 않는다)
    mutating func release(isBackspace: Bool) -> Release {
        let result: Release
        if cursorMode || isBackspace {
            result = .none
        } else {
            result = alternateArmed ? .alternate : .primary
        }
        self = KeyCapPressState()
        return result
    }

    /// 터치를 잃었다(제스처 끝 또는 **시스템 취소**) — 손 뗌이 처리하지 않은 누름을 **아무 입력 없이** 버린다:
    /// ⌫ 반복 정지·무장된 대체 입력 버림(넣지 않는다)·트랙패드 해제·눌림 해제. **지금 막 버렸으면 true**(뷰가 남은 Task를 끊는다).
    /// 정상 손 뗌 뒤에는 이미 처음 상태라 false — 이중 정리 무해
    mutating func touchLost() -> Bool {
        guard self != KeyCapPressState() else { return false }
        self = KeyCapPressState()
        return true
    }

    /// 뷰가 사라짐(`onDisappear` — 자판 전환·키보드 내림) — 진행 중이던 누름을 버린다(무입력)
    mutating func reset() {
        self = KeyCapPressState()
    }
}
