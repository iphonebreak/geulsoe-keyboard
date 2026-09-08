import Foundation
import TadakDomain

/// App Group을 통한 설정 저장소.
///
/// 키보드 익스텐션은 `load()`만 쓴다. `save()`는 컨테이너 앱 전용이다 —
/// 익스텐션에서 호출하면 Full Access 없이는 조용히 실패한다.
///
/// `UserDefaults` 인스턴스를 들고 있지 않고 접근할 때마다 연다. `UserDefaults`가
/// `Sendable`이 아니기도 하고, 익스텐션이 떠 있는 동안 설정 앱에서 값이 바뀔 수 있어
/// 매번 새로 읽는 편이 맞다.
public struct AppGroupSettingsRepository: SettingsRepository, Sendable {

    public static let appGroupIdentifier = "group.com.charging.tadak"
    private static let key = "keyboard.settings"

    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    /// 설정을 읽는다. App Group에 접근할 수 없거나 값이 없으면 기본값을 낸다.
    ///
    /// 이 메서드는 실패하지 않는다. 키보드가 설정을 못 읽었다고 동작을 멈추면 안 되기 때문이다.
    public func load() -> KeyboardSettings {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.key),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else {
            return .default
        }
        return settings
    }

    /// 설정을 쓴다. **컨테이너 앱에서만 호출한다.**
    /// - Returns: 저장에 성공했는지. 익스텐션에서 Full Access 없이 호출하면 `false`.
    @discardableResult
    public func save(_ settings: KeyboardSettings) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(settings) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
