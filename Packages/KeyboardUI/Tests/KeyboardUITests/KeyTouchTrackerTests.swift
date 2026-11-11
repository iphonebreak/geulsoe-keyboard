import CoreGraphics
import Testing
@testable import KeyboardUI

/// 키캡 터치 추적기 — iOS에서 키캡 누름을 SwiftUI `DragGesture` 대신 UIKit 인식기로 받는다(3행 지연, PDR `key-touch-uikit.md`).
///
/// 인식기(`KeyTouchRecognizer`)는 `swift test`가 누를 수 없어(UITouch를 만들 수 없다) **어느 터치를 따라가고 무엇을 알릴지**만
/// 이 값 타입에 두고 여기서 고정한다. 알림 뒤의 일(클릭음·⌫ 반복·무장·트랙패드)은 그대로 `KeyCapPressState`다.
@Suite("키캡 — UIKit 터치 추적기")
struct KeyTouchTrackerTests {

    typealias Tracker = KeyTouchTracker<Int>

    @Test("닿으면 바로 알린다 — 첫 손가락만 따라간다")
    func beganTracksFirstTouch() {
        var tracker = Tracker()

        #expect(tracker.began(1, x: 100) == .began)
        #expect(tracker.isTracking)
    }

    @Test("같은 키에 둘째 손가락 — 무시한다(첫 누름을 건드리지 않는다)")
    func secondTouchIsIgnored() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.began(2, x: 140) == nil)
        #expect(tracker.moved(2, x: 180) == nil)
        #expect(tracker.ended(2) == nil)
        #expect(tracker.isTracking)
        #expect(tracker.ended(1) == .ended)
    }

    @Test("움직임은 닿은 자리부터의 가로 이동량 — 트랙패드가 쓴다(DragGesture translation.width와 같은 뜻)")
    func movedReportsHorizontalTranslation() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.moved(1, x: 112) == .moved(12))
        #expect(tracker.moved(1, x: 90) == .moved(-10))
    }

    @Test("손 뗌 — 한 번만 알리고 추적을 끝낸다")
    func endedOnce() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.ended(1) == .ended)
        #expect(!tracker.isTracking)
        #expect(tracker.ended(1) == nil)
        #expect(tracker.moved(1, x: 120) == nil)
    }

    @Test("시스템 취소 — 터치 잃음(입력 없이 버림)")
    func cancelledIsLost() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.cancelled(1) == .lost)
        #expect(!tracker.isTracking)
    }

    @Test("다른 인식기에 밀려 초기화됨(reset) — 따라가던 터치가 있으면 터치 잃음")
    func resetWhileTrackingIsLost() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.reset() == .lost)
        #expect(!tracker.isTracking)
    }

    @Test("손 뗌 뒤 UIKit이 부르는 reset — 아무것도 알리지 않는다(이중 정리 없음)")
    func resetAfterEndIsSilent() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)
        _ = tracker.ended(1)

        #expect(tracker.reset() == nil)
        var fresh = Tracker()
        #expect(fresh.reset() == nil)
    }

    @Test("끝난 뒤 새 누름 — 새 시작점에서 다시 잰다")
    func nextPressStartsFresh() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)
        _ = tracker.ended(1)

        #expect(tracker.began(2, x: 300) == .began)
        #expect(tracker.moved(2, x: 308) == .moved(8))
    }

    @Test("따라가지 않는 터치의 취소 — 무시한다")
    func cancelOfOtherTouchIsIgnored() {
        var tracker = Tracker()
        _ = tracker.began(1, x: 100)

        #expect(tracker.cancelled(2) == nil)
        #expect(tracker.isTracking)
    }
}
