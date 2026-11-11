#if os(iOS)
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// 키캡 터치 알림 — `KeyCapView`가 자기 누름 처리(`KeyCapPressState`)로 잇는다
struct KeyTouchHandlers {
    var began: @MainActor () -> Void = {}
    /// 닿은 자리부터의 가로 이동량(pt)
    var moved: @MainActor (CGFloat) -> Void = { _ in }
    var ended: @MainActor () -> Void = {}
    /// 시스템 취소·다른 인식기에 밀림 — 입력 없이 버린다
    var lost: @MainActor () -> Void = {}
}

/// 키캡 위의 **투명 UIKit 터치 층** — iOS에서 키 누름을 SwiftUI `DragGesture` 대신 받는다.
///
/// **왜 (실측 2026-11-11, 15 Pro iOS 27.2.1 · PDR `key-touch-uikit.md`):** 터치는 모든 행에서 22~29ms에 도착하는데
/// SwiftUI 키 제스처는 시스템 제스처 판정기(`UISystemGestureGate`)가 실패하기를 기다렸다가 반응한다. 그 기다림이 화면 아래쪽일수록 길어
/// 단모음 3행(ㅋ)은 눌림 표시 777ms·길게 누르기 무장 1,250ms였다(2행 ㄴ 113ms·585ms). Face ID 기기에서만, SE2는 정상.
/// UIKit 인식기는 판정기와 **같은 때** 터치를 받으므로, 인식(recognize)하지 않고 `touchesBegan`에서 곧바로 알리면 기다림이 없다.
///
/// - 인식기는 **끝까지 인식하지 않는다**(`.possible` → 끝나면 `.failed`) — 다른 인식기·시스템 제스처를 막지도 늦추지도 않는다.
///   **전제: 키의 조상에 다른 제스처가 없다**(2026-11-11 기준). 누름 내내 `.possible`이므로, 이 인식기의 실패를 기다리는 인식기
///   (예: 자판 전체에 쓸기 제스처)를 나중에 붙이면 그것은 손을 뗄 때까지 늦춰진다
/// - iOS 경로는 `swift test`(macOS)가 **컴파일하지 않는다** — 이 파일을 고치면 `/keyboard-check`의 `xcodebuild build`까지 돌린다
/// - 시스템 취소(`touchesCancelled`)와 다른 인식기에 밀린 초기화(`reset`)는 **터치 잃음**이다 — 1.3.1 `isTouching` 정리와 같은 뜻
/// - 판정(어느 터치·무엇을 알릴지)은 `KeyTouchTracker`(시험 고정), 이 파일은 UIKit 배선만
/// - **항상 붙어 있는 overlay 하나**다 — 누르는 도중 뷰 구조가 바뀌지 않는다(키캡 원칙). 알림 클로저만 갱신마다 바꿔 끼운다
struct KeyTouchSurface: UIViewRepresentable {

    let handlers: KeyTouchHandlers

    func makeUIView(context: Context) -> KeyTouchView {
        let view = KeyTouchView()
        view.recognizer.handlers = handlers
        return view
    }

    func updateUIView(_ view: KeyTouchView, context: Context) {
        // 키캡 값(라벨·이벤트)이 바뀌면 클로저도 새 값을 본다 — 진행 중인 추적 상태는 인식기에 남는다
        view.recognizer.handlers = handlers
    }

    /// 키캡이 사라졌다(자판 전환 등) — 알림을 비운다. UITouch가 떨어져 나간 뷰의 인식기에 손 뗌을 계속 보내도
    /// 사라진 키의 입력이 나가지 않는다(리뷰 M1 — `KeyCapPressState.releaseIfPressed`와 이중 방어)
    static func dismantleUIView(_ view: KeyTouchView, coordinator: ()) {
        view.recognizer.handlers = KeyTouchHandlers()
    }
}

/// 키 크기의 투명 뷰 — 히트 테스트만 받고 그리지 않는다
final class KeyTouchView: UIView {

    let recognizer = KeyTouchRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        addGestureRecognizer(recognizer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// 터치를 받는 즉시 알리고 **인식하지 않는** 인식기
final class KeyTouchRecognizer: UIGestureRecognizer {

    var handlers = KeyTouchHandlers()
    private var tracker = KeyTouchTracker<ObjectIdentifier>()

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let note = tracker.began(ObjectIdentifier(touch), x: touch.location(in: nil).x) {
                deliver(note)
            } else {
                ignore(touch, for: event)   // 같은 키의 둘째 손가락 — 첫 누름을 건드리지 않는다
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let note = tracker.moved(ObjectIdentifier(touch), x: touch.location(in: nil).x) { deliver(note) }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let note = tracker.ended(ObjectIdentifier(touch)) { finish(with: note) }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            if let note = tracker.cancelled(ObjectIdentifier(touch)) { finish(with: note) }
        }
    }

    /// 손 뗌·취소 뒤(이미 추적 끝 — 알림 없음) 또는 **다른 인식기에 밀려** 초기화될 때(추적 중 — 터치 잃음)
    override func reset() {
        super.reset()
        if let note = tracker.reset() { deliver(note) }
    }

    /// 끝 알림 뒤 실패로 돌려 UIKit이 이 인식기를 초기화하게 한다(인식한 적이 없으니 다른 인식기에 아무 영향 없다)
    private func finish(with note: KeyTouchTracker<ObjectIdentifier>.Event) {
        deliver(note)
        state = .failed
    }

    private func deliver(_ note: KeyTouchTracker<ObjectIdentifier>.Event) {
        switch note {
        case .began: handlers.began()
        case .moved(let translation): handlers.moved(translation)
        case .ended: handlers.ended()
        case .lost: handlers.lost()
        }
    }
}
#endif
