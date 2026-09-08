import Foundation
import TadakDomain

/// App Group을 통한 클립보드 기록 저장소.
///
/// **키보드가 쓰는 App Group 데이터** — Full Access가 있어야 지속된다 (클립보드 읽기 자체가
/// FA 필수라 새 의존은 아니다). 내용은 이 컨테이너 밖으로 나가지 않는다 (보안 규칙).
/// 설정 앱은 끄기·지우기 경로에서 `clear()`만 호출한다.
public struct AppGroupClipboardHistoryRepository: ClipboardHistoryRepository {

    private static let key = "keyboard.clipboardHistory"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    public func load() -> ClipboardHistory {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.key),
              let history = try? JSONDecoder().decode(ClipboardHistory.self, from: data)
        else {
            return ClipboardHistory()
        }
        return history
    }

    /// 쓰기 실패(Full Access 없음)는 감지되지 않을 수 있다 — 반환값이 지속을 보장하지 않는다.
    @discardableResult
    public func save(_ history: ClipboardHistory) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(history) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: Self.key)
    }
}
