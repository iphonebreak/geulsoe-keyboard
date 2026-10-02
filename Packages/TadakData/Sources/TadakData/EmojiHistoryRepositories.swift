import Foundation
import TadakDomain

/// 이모지 「최근 사용」 저장소 — **키보드 익스텐션 자신의 `UserDefaults`**(App Group 아님, v1.2.0 ⑤).
///
/// 익스텐션에서 `UserDefaults.standard`는 **익스텐션 번들의 전용 도메인**이다 — 앱의 standard와도,
/// App Group 스위트와도 다른 저장 공간이다. Apple 「Configuring open access for a custom keyboard」:
/// 전체 접근이 없을 때 막히는 것은 *"writing to the containing app's shared group containers"* 뿐이다.
/// 그래서 **전체 접근과 무관하게** 저장되고, 키보드의 App Group 쓰기(학습 단어·클립보드 기록)는 늘지 않는다.
///
/// ★ **이 저장소는 키보드 익스텐션에서만 쓴다.** 설정 앱에서 만들면 **앱 자신의** standard를 읽고 쓴다 —
///   키보드의 기록에는 닿지 않는다. 앱은 `KeyboardSettings.emojiHistoryResetToken`으로만 「지워라」를 전한다.
///
/// ★ `UserDefaults.standard` 사용은 프라이버시 매니페스트 사유 `CA92.1`(앱 전용 데이터)이 필요하다 —
///   `Keyboard/PrivacyInfo.xcprivacy`에 선언한다(이 저장소 전까지 키보드는 standard를 쓴 적이 없어 `1C8F.1`만 있었다).
///
/// 실기에서 프로세스 재시작 뒤 값이 남는지는 **미확인**이다 — `docs/release/v1.2.0-emoji-recent-device-check.md`.
/// 실패하면 `InMemoryEmojiHistoryRepository`로 바꿔 끼운다(PDR 6-3절).
public struct KeyboardOwnEmojiHistoryRepository: EmojiHistoryRepository {

    static let key = "keyboard.emojiHistory"
    /// nil = 익스텐션 자신의 도메인(`UserDefaults.standard`). 테스트만 따로 스위트를 준다.
    let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load() -> EmojiHistory {
        guard let data = defaults?.data(forKey: Self.key),
              let history = try? JSONDecoder().decode(EmojiHistory.self, from: data)
        else { return EmojiHistory() }
        return history
    }

    @discardableResult
    public func save(_ history: EmojiHistory) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(history) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func clear() {
        defaults?.removeObject(forKey: Self.key)
    }
}

/// **후퇴안** — 프로세스가 살아 있는 동안만 기억한다(PDR 6-3절). 실기에서 전용 컨테이너가 재시작 뒤
/// 비는 것으로 밝혀졌을 때 조립 지점의 저장소 한 줄을 이것으로 바꾼다. 지금은 제품에서 쓰지 않는다.
///
/// 키보드 VC는 등장마다 새로 만들어질 수 있어 **프로세스 전역 하나**를 공유한다(`shared`).
public final class InMemoryEmojiHistoryRepository: EmojiHistoryRepository, @unchecked Sendable {

    public static let shared = InMemoryEmojiHistoryRepository()

    private let lock = NSLock()
    private var history = EmojiHistory()

    public init() {}

    public func load() -> EmojiHistory {
        lock.lock(); defer { lock.unlock() }
        return history
    }

    @discardableResult
    public func save(_ history: EmojiHistory) -> Bool {
        lock.lock(); defer { lock.unlock() }
        self.history = history
        return true
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        history = EmojiHistory()
    }
}
