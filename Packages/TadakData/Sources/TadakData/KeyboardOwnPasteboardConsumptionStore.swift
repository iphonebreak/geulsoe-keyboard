import Foundation
import TadakDomain

/// 소비한 클립보드의 번호·지문과 지문 열쇠 — **키보드 자기 컨테이너**(`UserDefaults.standard`, App Group 아님).
///
/// 사장님 보고(2026-11-25): 복사됨 칩을 ✕로 내렸는데 나중에 키보드를 다시 열면 같은 칩이 또 떴다. 기록이
/// 메모리(`static`)에만 있어 키보드 프로세스가 내려가면 사라졌고, 저장한 뒤에도 유니버설 클립보드가 같은 글을
/// 새 번호로 다시 보내 번호만으로는 막지 못했다(`PasteboardConsumption` 참조). `KeyboardOwnEmojiHistoryRepository`·
/// `KeyboardOwnExitTraceStore`와 같은 자리·같은 패턴이라 전체 접근과 무관하게 쓰이고 매니페스트 사유도 같다(`CA92.1`).
///
/// 담는 것은 **정수(번호)와 바이트(지문·열쇠)뿐**이다 — 클립보드 원문·길이는 담지 않는다. 기록은 마지막 하나만 덮어쓴다.
public struct KeyboardOwnPasteboardConsumptionStore: PasteboardConsumptionStore {

    /// `218c612`(번호만 저장하던 빌드)와 같은 키 — 그 기록을 그대로 읽는다
    static let changeCountKey = "keyboard.pasteboard.consumedChangeCount"
    static let fingerprintStorageKey = "keyboard.pasteboard.consumedFingerprint"
    static let secretStorageKey = "keyboard.pasteboard.fingerprintKey"
    /// 지문 길이 — KeyboardCore `PasteboardFingerprint.byteCount`와 같다(FNV-1a 64비트 두 갈래)
    static let fingerprintByteCount = 16
    /// 열쇠 길이 — KeyboardCore `PasteboardFingerprint.keyByteCount`와 같다
    static let keyByteCount = 32

    let suiteName: String?

    /// `suiteName`은 시험용 — 키보드는 늘 `nil`(= `.standard`)이다
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func load() -> PasteboardConsumption? {
        let changeCount = defaults?.object(forKey: Self.changeCountKey) as? Int
        let fingerprint = defaults?.data(forKey: Self.fingerprintStorageKey).flatMap { $0.count == Self.fingerprintByteCount ? $0 : nil }
        guard changeCount != nil || fingerprint != nil else { return nil }
        return PasteboardConsumption(changeCount: changeCount, fingerprint: fingerprint)
    }

    public func save(_ consumption: PasteboardConsumption?) {
        set(consumption?.changeCount, forKey: Self.changeCountKey)
        set(consumption?.fingerprint, forKey: Self.fingerprintStorageKey)
    }

    public func fingerprintKey() -> Data {
        if let stored = defaults?.data(forKey: Self.secretStorageKey), stored.count == Self.keyByteCount {
            return stored
        }
        // `SystemRandomNumberGenerator`는 애플 플랫폼에서 암호학적으로 안전한 난수다(`arc4random_buf`)
        var generator = SystemRandomNumberGenerator()
        let key = Data((0..<Self.keyByteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        defaults?.set(key, forKey: Self.secretStorageKey)
        return key
    }

    private func set(_ value: Any?, forKey key: String) {
        guard let value else {
            defaults?.removeObject(forKey: key)
            return
        }
        defaults?.set(value, forKey: key)
    }
}
