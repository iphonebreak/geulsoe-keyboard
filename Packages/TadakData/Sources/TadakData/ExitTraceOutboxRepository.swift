import Foundation
import TadakDomain

/// 종료 흔적 발신함 — App Group, **키보드 쪽**(추가·정리). 백로그 14 (가), 보안 규칙 N21.
///
/// 단일 작성자 규칙(PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8): 키보드는 `exitTrace.outbox`·`exitTrace.lastSeq`만 쓰고,
/// 앱은 `exitTrace.ack`(마지막으로 처리한 `seq`)만 쓴다. **ack 쓰기는 여기 두지 않는다** — 키보드가 이 패키지를 링크한다.
/// 쓰기는 전체 접근이 있을 때만 된다 — 부르는 쪽(`ExitTraceRecorder`)이 그때만 부른다.
/// 칸마다 따로 인코딩해 둔다 — 한 칸이 깨져도(다음 버전이 열거 값을 더한 저장분 등) 그 칸만 버린다.
public struct ExitTraceOutboxRepository: ExitTraceOutboxWriting, ExitTraceOutboxReading {

    static let outboxKey = "exitTrace.outbox"
    static let ackKey = "exitTrace.ack"
    static let lastSeqKey = "exitTrace.lastSeq"

    let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    public func entries() -> [ExitTraceOutboxEntry] {
        ExitTraceDispatcher.decode(defaults?.array(forKey: Self.outboxKey) as? [Data] ?? [])
    }

    public func ack() -> Int { defaults?.integer(forKey: Self.ackKey) ?? 0 }

    @discardableResult
    public func append(_ items: [ExitTraceOutboxItem], nowHour: Int) -> ExitTraceDropCount {
        guard let defaults else { return ExitTraceDropCount() }
        let ack = ack()
        let stored = defaults.array(forKey: Self.outboxKey) as? [Data] ?? []
        let kept = ExitTraceDispatcher.decode(stored).filter { $0.seq > ack }
        // 넣을 것도 지울 것도 없으면 쓰지 않는다 — 등장마다 App Group을 다시 쓰지 않게
        let nothingExpired = kept.allSatisfy { !ExitTraceRetention.isExpired(createdAtHour: $0.createdAtHour, nowHour: nowHour) }
        if items.isEmpty, kept.count == stored.count, nothingExpired { return ExitTraceDropCount() }
        // ack가 발신함 밖(이미 지운 번호보다 큼)을 가리켜도 새 칸은 그보다 큰 번호를 받는다 — 앱이 건너뛰지 않게
        var seq = max(defaults.integer(forKey: Self.lastSeqKey), ack, kept.map(\.seq).max() ?? 0)
        let added = items.map { item -> ExitTraceOutboxEntry in
            seq += 1
            switch item {
            case .record(let record): return ExitTraceOutboxEntry(seq: seq, createdAtHour: record.createdAtHour, record: record, stats: nil)
            case .stats(let stats): return ExitTraceOutboxEntry(seq: seq, createdAtHour: nowHour, record: nil, stats: stats)
            }
        }
        let result = ExitTraceRetention.retained(kept + added, nowHour: nowHour, limit: ExitTraceRetention.outboxLimit,
                                                 createdAtHour: \.createdAtHour)
        let encoder = JSONEncoder()
        defaults.set(result.kept.compactMap { try? encoder.encode($0) }, forKey: Self.outboxKey)
        defaults.set(seq, forKey: Self.lastSeqKey)
        return result.dropped
    }
}
