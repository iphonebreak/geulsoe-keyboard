import Foundation
import TadakDomain

/// 종료 흔적 발신함 — App Group. 백로그 14 (가), 보안 규칙 N21.
///
/// 단일 작성자 규칙(PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8·6-9 덧붙임): 칸은 **칸마다 고유 키**
/// `exitTrace.outbox.<seq>`에 있고 번호는 다시 쓰지 않는다. **칸을 만드는 것은 키보드뿐**이고(`append`, `exitTrace.lastSeq`도 키보드만),
/// 앱은 `exitTrace.ack`(마지막으로 처리한 `seq`)만 쓴다. **지우기는 같은 규칙(ack 이하·생성 후 30일 초과·읽을 수 없는 칸)으로
/// 양쪽이 한다** — 키를 지우는 것뿐이라 몇 번 겹쳐도 같고, 공유 배열을 읽고-고쳐-쓰지 않으므로 한쪽이 막 넣은 칸을 다른 쪽이
/// 덮어써 잃는 일이 없다. 앱이 지우는 이유: 전체 접근을 끄면 키보드는 App Group에 못 써 30일 지난 칸이 남는다(검증 때 발견).
/// **ack 쓰기는 여기 두지 않는다** — 키보드가 이 패키지를 링크한다(앱 쪽 `App/Diagnostics/ExitTraceAppInbox.swift`).
/// 키보드의 쓰기는 전체 접근이 있을 때만 된다 — 부르는 쪽(`ExitTraceRecorder`)이 그때만 부른다.
/// 살아 있는 칸은 늘 최근 번호 50개 `(lastSeq-50, lastSeq]` 안이다 — 새 칸을 만들 때 창 밖으로 밀린 번호를 지운다.
public struct ExitTraceOutboxRepository: ExitTraceOutboxWriting, ExitTraceOutboxReading {

    public static let entryKeyPrefix = "exitTrace.outbox."
    /// 배포 전 개발 빌드(`12cea89`)의 배열 발신함 — 읽지 않고 지운다
    public static let legacyOutboxKey = "exitTrace.outbox"
    public static let ackKey = "exitTrace.ack"
    public static let lastSeqKey = "exitTrace.lastSeq"

    public static func entryKey(_ seq: Int) -> String { entryKeyPrefix + String(seq) }

    let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// 창 안의 읽을 수 있는 칸, `seq` 오름차순. 알려진 열거 값으로 디코드되지 않거나 키와 번호가 다른 칸은 뺀다
    public func entries() -> [ExitTraceOutboxEntry] {
        guard let defaults else { return [] }
        return slots(in: defaults).compactMap(\.entry)
    }

    public func ack() -> Int { defaults?.integer(forKey: Self.ackKey) ?? 0 }

    /// ack 이하·생성 후 30일 초과·읽을 수 없는 칸을 지운다(넣지 않는다, 남은 칸·번호·ack는 다시 쓰지 않는다).
    /// 앱이 활성화될 때 전체 접근과 무관하게 부른다 — 30일 만료로 지운 수를 돌려준다(ack로 지운 칸은 버린 수가 아니다)
    @discardableResult
    public func removeHandled(nowHour: Int) -> ExitTraceDropCount {
        guard let defaults else { return ExitTraceDropCount() }
        return removeHandled(in: defaults, ack: ack(), nowHour: nowHour)
    }

    @discardableResult
    public func append(_ items: [ExitTraceOutboxItem], nowHour: Int) -> ExitTraceDropCount {
        guard let defaults else { return ExitTraceDropCount() }
        let ack = ack()
        // 넣을 것도 지울 것도 없으면 쓰지 않는다 — 등장마다 App Group을 다시 쓰지 않게
        let removed = removeHandled(in: defaults, ack: ack, nowHour: nowHour)
        let fresh = items.filter { !ExitTraceRetention.isExpired(createdAtHour: createdAtHour(of: $0, nowHour: nowHour), nowHour: nowHour) }
        let expiredOnArrival = ExitTraceDropCount(expired: items.count - fresh.count)
        guard !fresh.isEmpty else { return removed + expiredOnArrival }
        let last = defaults.integer(forKey: Self.lastSeqKey)
        // ack가 발신함 밖(이미 지운 번호보다 큼)을 가리켜도 새 칸은 그보다 큰 번호를 받는다 — 앱이 건너뛰지 않게
        var seq = max(last, ack)
        let encoder = JSONEncoder()
        for item in fresh {
            seq += 1
            let entry = ExitTraceOutboxEntry(seq: seq, createdAtHour: createdAtHour(of: item, nowHour: nowHour),
                                             record: item.record, stats: item.stats)
            defaults.set(try? encoder.encode(entry), forKey: Self.entryKey(seq))
        }
        defaults.set(seq, forKey: Self.lastSeqKey)
        return removed + expiredOnArrival + ExitTraceDropCount(overflow: removeOutsideWindow(in: defaults, previousLast: last, newLast: seq))
    }

    // MARK: - 내부

    private func createdAtHour(of item: ExitTraceOutboxItem, nowHour: Int) -> Int {
        item.record?.createdAtHour ?? nowHour
    }

    private static func window(endingAt last: Int) -> ClosedRange<Int>? {
        let lower = max(1, last - ExitTraceRetention.outboxLimit + 1)
        return lower <= last ? lower...last : nil
    }

    /// 창 `(lastSeq-50, lastSeq]` 안의 저장된 키 — 읽을 수 없으면 `entry == nil`
    private func slots(in defaults: UserDefaults) -> [(seq: Int, entry: ExitTraceOutboxEntry?)] {
        guard let window = Self.window(endingAt: defaults.integer(forKey: Self.lastSeqKey)) else { return [] }
        return window.compactMap { seq in
            guard let data = defaults.data(forKey: Self.entryKey(seq)) else { return nil }
            let entry = ExitTraceDispatcher.decode([data]).first
            return (seq, entry?.seq == seq ? entry : nil)
        }
    }

    private func removeHandled(in defaults: UserDefaults, ack: Int, nowHour: Int) -> ExitTraceDropCount {
        if defaults.object(forKey: Self.legacyOutboxKey) != nil { defaults.removeObject(forKey: Self.legacyOutboxKey) }
        var expired = 0
        for slot in slots(in: defaults) {
            guard let entry = slot.entry else {
                defaults.removeObject(forKey: Self.entryKey(slot.seq))
                continue
            }
            if entry.seq <= ack {
                defaults.removeObject(forKey: Self.entryKey(slot.seq))
            } else if ExitTraceRetention.isExpired(createdAtHour: entry.createdAtHour, nowHour: nowHour) {
                defaults.removeObject(forKey: Self.entryKey(slot.seq))
                expired += 1
            }
        }
        return ExitTraceDropCount(expired: expired)
    }

    /// 새 번호로 창이 밀려 밖으로 나간 칸(최근 50개 밖 = 상한 초과)을 지우고 그 수를 돌려준다
    private func removeOutsideWindow(in defaults: UserDefaults, previousLast: Int, newLast: Int) -> Int {
        let lower = max(1, previousLast - ExitTraceRetention.outboxLimit + 1)
        let upper = newLast - ExitTraceRetention.outboxLimit
        guard lower <= upper else { return 0 }
        var overflow = 0
        for seq in lower...upper where defaults.object(forKey: Self.entryKey(seq)) != nil {
            defaults.removeObject(forKey: Self.entryKey(seq))
            overflow += 1
        }
        return overflow
    }
}

private extension ExitTraceOutboxItem {
    var record: ExitTraceRecord? {
        if case .record(let record) = self { return record }
        return nil
    }

    var stats: ExitTraceCounters? {
        if case .stats(let stats) = self { return stats }
        return nil
    }
}
