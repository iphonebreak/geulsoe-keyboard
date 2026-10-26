import Foundation
import TadakDomain

/// 종료 흔적 — **키보드 자기 컨테이너**(`UserDefaults.standard`, App Group 아님). 백로그 14 (가), 보안 규칙 N21.
///
/// 전체 접근이 없을 때 막히는 것은 담는 앱과의 공유 컨테이너 쓰기뿐이라 이 저장소는 권한과 무관하게 쓰인다 —
/// `KeyboardOwnEmojiHistoryRepository`와 같은 자리·같은 패턴이다(매니페스트 `CA92.1`). 앱은 이 컨테이너를 못 읽는다.
/// 담는 것은 열거형·정수 상태뿐이다(입력·문맥·입력란 종류 없음 — `ExitTraceRecord` 머리 주석).
/// PDR `docs/design-reviews/keyboard-crashlytics.md` 2-2·2-6.
public struct KeyboardOwnExitTraceStore: ExitTraceStore {

    static let markerKey = "keyboard.exitTrace.marker"
    static let pendingKey = "keyboard.exitTrace.pending"
    static let countersKey = "keyboard.exitTrace.counters"
    static let statsDayKey = "keyboard.exitTrace.statsDay"
    static let optedOutKey = "keyboard.exitTrace.optedOut"
    static let keys = [markerKey, pendingKey, countersKey, statsDayKey, optedOutKey]

    let suiteName: String?

    /// `suiteName`은 시험용 — 키보드는 늘 `nil`(= `.standard`)이다
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? {
        suiteName.map { UserDefaults(suiteName: $0) } ?? .standard
    }

    public func loadMarker() -> ExitTraceMarker? { decode(ExitTraceMarker.self, Self.markerKey) }

    public func saveMarker(_ marker: ExitTraceMarker?) { encode(marker, Self.markerKey) }

    public func loadPending() -> [ExitTraceRecord] { decode([ExitTraceRecord].self, Self.pendingKey) ?? [] }

    public func savePending(_ records: [ExitTraceRecord]) { encode(records.isEmpty ? nil : records, Self.pendingKey) }

    public func appendPending(_ record: ExitTraceRecord, nowHour: Int) -> ExitTraceDropCount {
        retain(loadPending() + [record], nowHour: nowHour)
    }

    public func prunePending(nowHour: Int) -> ExitTraceDropCount {
        let pending = loadPending()
        guard !pending.isEmpty else { return ExitTraceDropCount() }
        let dropped = ExitTraceRetention.retained(pending, nowHour: nowHour, limit: ExitTraceRetention.pendingLimit,
                                                  createdAtHour: \.createdAtHour).dropped
        return dropped == ExitTraceDropCount() ? dropped : retain(pending, nowHour: nowHour)   // 버릴 것이 없으면 쓰지 않는다
    }

    private func retain(_ records: [ExitTraceRecord], nowHour: Int) -> ExitTraceDropCount {
        let result = ExitTraceRetention.retained(records, nowHour: nowHour, limit: ExitTraceRetention.pendingLimit,
                                                 createdAtHour: \.createdAtHour)
        savePending(result.kept)
        return result.dropped
    }

    public func loadCounters() -> ExitTraceCounters { decode(ExitTraceCounters.self, Self.countersKey) ?? ExitTraceCounters() }

    public func saveCounters(_ counters: ExitTraceCounters) {
        encode(counters == ExitTraceCounters() ? nil : counters, Self.countersKey)
    }

    public func loadLastStatsDay() -> Int? { defaults?.object(forKey: Self.statsDayKey) as? Int }

    public func saveLastStatsDay(_ day: Int?) {
        if let day { defaults?.set(day, forKey: Self.statsDayKey) } else { defaults?.removeObject(forKey: Self.statsDayKey) }
    }

    public func loadOptedOut() -> Bool { defaults?.bool(forKey: Self.optedOutKey) ?? false }

    public func saveOptedOut(_ value: Bool) {
        if value { defaults?.set(true, forKey: Self.optedOutKey) } else { defaults?.removeObject(forKey: Self.optedOutKey) }
    }

    public func clearAll() {
        for key in [Self.markerKey, Self.pendingKey, Self.countersKey, Self.statsDayKey] { defaults?.removeObject(forKey: key) }
    }

    private func decode<Value: Decodable>(_ type: Value.Type, _ key: String) -> Value? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<Value: Encodable>(_ value: Value?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults?.removeObject(forKey: key)
            return
        }
        defaults?.set(data, forKey: key)
    }
}
