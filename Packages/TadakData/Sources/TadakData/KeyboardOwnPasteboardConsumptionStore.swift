import Foundation
import TadakDomain

/// 소비한 클립보드의 `changeCount` — **키보드 자기 컨테이너**(`UserDefaults.standard`, App Group 아님).
///
/// 사장님 보고(2026-11-25): 복사됨 칩을 ✕로 내렸는데 나중에 키보드를 다시 열면 같은 칩이 또 떴다. 기록이
/// 메모리(`static`)에만 있어 키보드 프로세스가 내려가면 사라졌다. `KeyboardOwnEmojiHistoryRepository`·
/// `KeyboardOwnExitTraceStore`와 같은 자리·같은 패턴이라 전체 접근과 무관하게 쓰이고 매니페스트 사유도 같다(`CA92.1`).
///
/// 담는 것은 **정수 하나**다 — 시스템이 세는 클립보드 변경 번호이고, 클립보드 내용·해시·길이는 담지 않는다.
/// 지금 클립보드와 다른 기록은 조립 지점이 `PasteboardProbe.retainedConsumption`으로 버린다.
public struct KeyboardOwnPasteboardConsumptionStore: PasteboardConsumptionStore {

    static let key = "keyboard.pasteboard.consumedChangeCount"

    let suiteName: String?

    /// `suiteName`은 시험용 — 키보드는 늘 `nil`(= `.standard`)이다
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load() -> Int? {
        defaults?.object(forKey: Self.key) as? Int
    }

    public func save(_ changeCount: Int?) {
        guard let changeCount else {
            defaults?.removeObject(forKey: Self.key)
            return
        }
        defaults?.set(changeCount, forKey: Self.key)
    }
}
