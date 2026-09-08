import Foundation

/// 앱 → 키보드 "설정이 바뀌었다" 신호 — Darwin 알림 (PDR field-traits-and-live-settings).
///
/// payload가 없다. 값은 수신 측이 App Group에서 다시 읽는다 — **앱이 쓰고 키보드가 읽는**
/// 방향성이 그대로라 Full Access가 필요 없다. notifyd 경유라 샌드박스 익스텐션에서도 쓰는
/// 통상 패턴(위젯 갱신 등). 폴링 없음: 알림이 없으면 아무 일도 하지 않는다.
public enum SettingsChangeNotifier {

    /// 알림 이름 — 번들 접두를 붙여 다른 앱과 충돌하지 않게
    public static let name = "com.charging.tadak.settingsChanged"

    /// 앱이 설정·내 문구를 저장한 직후 호출한다.
    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}

/// 키보드 쪽 수신기. 살아 있는 동안 등록되고, 해제되면 관찰을 끊는다.
/// Darwin 알림은 등록한 스레드의 런루프(여기선 메인)로 온다 — 핸들러는 메인에서 불린다고
/// 보되, 호출자가 다시 메인으로 홉하는 것을 막지 않는다.
public final class SettingsChangeObserver: @unchecked Sendable {

    private let handler: @Sendable () -> Void

    public init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<SettingsChangeObserver>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            SettingsChangeNotifier.name as CFString,
            nil,
            .deliverImmediately
        )
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque()
        )
    }
}
