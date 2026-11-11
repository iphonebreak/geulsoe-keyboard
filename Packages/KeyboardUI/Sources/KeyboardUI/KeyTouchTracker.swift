import CoreGraphics

/// 키캡 하나가 **어느 터치를 따라가고 무엇을 알릴지** — iOS 터치 층(`KeyTouchSurface`)의 판정만 모은 값 타입.
///
/// **왜 따로 두나:** 인식기는 UITouch를 받아야 해서 `swift test`가 누를 수 없다. 판정을 여기 두면 macOS에서 시험으로 고정된다
/// (`KeyTouchTrackerTests`). 알림 뒤의 일(클릭음·⌫ 반복·무장·트랙패드)은 그대로 `KeyCapPressState`가 정한다.
///
/// - 첫 손가락만 따라간다 — 같은 키에 둘째 손가락이 닿아도 첫 누름을 건드리지 않는다(DragGesture도 한 손가락 제스처였다)
/// - 움직임은 **닿은 자리부터의 가로 이동량** — `DragGesture.Value.translation.width`와 같은 뜻(트랙패드가 쓴다)
/// - 끝은 한 번만 알린다 — 손 뗌(`ended`)·시스템 취소(`lost`)·다른 인식기에 밀린 초기화(`reset` → `lost`) 중 먼저 온 것
struct KeyTouchTracker<TouchID: Hashable> {

    enum Event: Equatable {
        /// 손가락이 닿았다 — 터치다운 일을 지금 한다
        case began
        /// 누른 채 움직였다 — 닿은 자리부터의 가로 이동량
        case moved(CGFloat)
        /// 손을 뗐다
        case ended
        /// 터치를 잃었다 — 입력 없이 버린다
        case lost
    }

    private var tracked: TouchID?
    private var startX: CGFloat = 0

    var isTracking: Bool { tracked != nil }

    mutating func began(_ touch: TouchID, x: CGFloat) -> Event? {
        guard tracked == nil else { return nil }
        tracked = touch
        startX = x
        return .began
    }

    mutating func moved(_ touch: TouchID, x: CGFloat) -> Event? {
        guard touch == tracked else { return nil }
        return .moved(x - startX)
    }

    mutating func ended(_ touch: TouchID) -> Event? {
        finish(touch, as: .ended)
    }

    mutating func cancelled(_ touch: TouchID) -> Event? {
        finish(touch, as: .lost)
    }

    /// 인식기가 초기화됐다(UIKit `reset`) — 따라가던 터치가 남아 있으면 그 터치를 잃은 것이다
    mutating func reset() -> Event? {
        guard let tracked else { return nil }
        return finish(tracked, as: .lost)
    }

    private mutating func finish(_ touch: TouchID, as event: Event) -> Event? {
        guard touch == tracked else { return nil }
        tracked = nil
        return event
    }
}
