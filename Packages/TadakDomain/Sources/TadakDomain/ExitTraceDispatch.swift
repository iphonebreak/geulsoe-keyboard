import Foundation

// 백로그 14 (가) — 발신함 → 이벤트 계획(순수)과 저장소 프로토콜. PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8·8-2.
//
// 앱 리포터(`App/Diagnostics/KeyboardExitReporter.swift`, 다음 과제)는 이 계획을 그대로 Analytics 이벤트로 옮기기만 한다 —
// 이벤트 이름·파라미터 키는 여기 상수뿐이고, 값은 열거형 `rawValue`·정수뿐이다.

/// 이벤트 하나 — 이름은 상수, 값은 열거 문자열 또는 정수
public struct ExitTraceEvent: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case text(String)
        case number(Int)
    }

    public let name: String
    public let parameters: [String: Value]
}

/// 발신함 한 칸의 처리 — 보낼 이벤트(없으면 보내지 않고 ack만)와 그 뒤에 쓸 ack
public struct ExitTraceDispatchStep: Equatable, Sendable {
    public let event: ExitTraceEvent?
    public let ackSeq: Int
}

public struct ExitTraceDispatchPlan: Equatable, Sendable {
    /// `seq` 오름차순. 앱은 이벤트를 보낸 **직후** 그 칸의 `ackSeq`를 쓴다(M4)
    public let steps: [ExitTraceDispatchStep]
    /// 보내지 않고 ack만 한 수(30일 초과·이용 분석 끔·빈 칸)
    public let discarded: Int
}

public enum ExitTraceDispatcher {
    public static let suspectEventName = "kb_exit_suspect"
    public static let statsEventName = "kb_exit_stats"
    public static let defaultMaxPerActivation = 20

    public static let suspectParameterKeys = [
        "seq", "cls", "mode", "panel", "tr1", "tr2", "tr3", "tr4", "idiom", "w_b", "sw_b", "mem_b", "mem_min_b",
        "pressure", "res_h", "age_d", "fa_rec", "bld", "osv",
    ]
    public static let statsParameterKeys = ["seq", "appear_n", "abn_n", "orph_n", "upd_n", "stale_n", "dropped_n", "expired_n"]

    static let ageCapDays = 30

    /// 발신함 원자료 → 칸. 알려진 열거 값으로 디코드되지 않는 칸은 버린다(그대로 흘려보내지 않는다)
    public static func decode(_ blobs: [Data]) -> [ExitTraceOutboxEntry] {
        let decoder = JSONDecoder()
        return blobs.compactMap { try? decoder.decode(ExitTraceOutboxEntry.self, from: $0) }
    }

    public static func plan(entries: [ExitTraceOutboxEntry], ack: Int, today: Date, analyticsEnabled: Bool,
                            maxPerActivation: Int = defaultMaxPerActivation) -> ExitTraceDispatchPlan {
        let nowHour = ExitTraceBuckets.hour(of: today)
        let due = entries.filter { $0.seq > ack }.sorted { $0.seq < $1.seq }.prefix(max(0, maxPerActivation))
        let steps = due.map { entry in
            ExitTraceDispatchStep(event: analyticsEnabled ? event(for: entry, nowHour: nowHour) : nil, ackSeq: entry.seq)
        }
        return ExitTraceDispatchPlan(steps: steps, discarded: steps.filter { $0.event == nil }.count)
    }

    /// 계획을 실행한다 — 칸마다 (이벤트가 있으면) 보낸 **직후** 그 칸의 ack를 쓴다(M4: 중복 창을 호출~ack 사이로 줄인다).
    /// 이벤트가 없는 칸(30일 초과·이용 분석 끔·빈 칸)도 ack한다. 보낸 이벤트 수를 돌려준다
    @discardableResult
    public static func deliver(_ plan: ExitTraceDispatchPlan, send: (ExitTraceEvent) -> Void, ack: any ExitTraceAckWriting) -> Int {
        var sent = 0
        for step in plan.steps {
            if let event = step.event {
                send(event)
                sent += 1
            }
            ack.writeAck(step.ackSeq)
        }
        return sent
    }

    private static func event(for entry: ExitTraceOutboxEntry, nowHour: Int) -> ExitTraceEvent? {
        guard !ExitTraceRetention.isExpired(createdAtHour: entry.createdAtHour, nowHour: nowHour) else { return nil }
        switch (entry.record, entry.stats) {
        case let (record?, nil): return suspectEvent(record, seq: entry.seq, nowHour: nowHour)
        case let (nil, stats?): return statsEvent(stats, seq: entry.seq)
        default: return nil
        }
    }

    private static func suspectEvent(_ record: ExitTraceRecord, seq: Int, nowHour: Int) -> ExitTraceEvent {
        let recent = Array(record.transitions.suffix(ExitTraceRetention.transitionLimit))
        let padded = recent + Array(repeating: ExitTraceTransition.none, count: ExitTraceRetention.transitionLimit - recent.count)
        let ageDays = min(ageCapDays, max(0, nowHour - record.createdAtHour) / 24)
        let parameters: [String: ExitTraceEvent.Value] = [
            "seq": .number(seq),
            "cls": .text(record.cls.rawValue),
            "mode": .text(record.mode.rawValue),
            "panel": .text(record.panel.rawValue),
            "tr1": .text(padded[0].rawValue),
            "tr2": .text(padded[1].rawValue),
            "tr3": .text(padded[2].rawValue),
            "tr4": .text(padded[3].rawValue),
            "idiom": .text(record.idiom.rawValue),
            "w_b": .number(record.widthBucket),
            "sw_b": .number(record.screenWidthBucket),
            "mem_b": .number(record.memoryBucket),
            "mem_min_b": .number(record.memoryMinBucket),
            "pressure": .number(record.pressure.rawValue),
            "res_h": .number(min(ExitTraceBuckets.residueCapHours, max(0, record.residueHours))),
            "age_d": .number(ageDays),
            "fa_rec": .number(record.fullAccessAtCreation ? 1 : 0),
            "bld": .number(record.buildNumber),
            "osv": .number(record.osCode),
        ]
        return ExitTraceEvent(name: suspectEventName, parameters: parameters)
    }

    private static func statsEvent(_ stats: ExitTraceCounters, seq: Int) -> ExitTraceEvent {
        ExitTraceEvent(name: statsEventName, parameters: [
            "seq": .number(seq),
            "appear_n": .number(stats.appearances),
            "abn_n": .number(stats.abnormal),
            "orph_n": .number(stats.orphan),
            "upd_n": .number(stats.update),
            "stale_n": .number(stats.stale),
            "dropped_n": .number(stats.dropped),
            "expired_n": .number(stats.expired),
        ])
    }
}

// MARK: - 저장소 프로토콜 (구현은 TadakData — KeyboardCore는 이 프로토콜만 안다)

/// 키보드 자기 컨테이너 — 표시·대기 기록·카운터. 전체 접근 없이 쓰인다
public protocol ExitTraceStore: Sendable {
    func loadMarker() -> ExitTraceMarker?
    func saveMarker(_ marker: ExitTraceMarker?)
    func loadPending() -> [ExitTraceRecord]
    func savePending(_ records: [ExitTraceRecord])
    /// 넣고 30일·20건 규칙으로 정리한다 — 버린 수(넘침·만료)를 돌려준다
    func appendPending(_ record: ExitTraceRecord, nowHour: Int) -> ExitTraceDropCount
    /// 넣지 않고 30일·20건 규칙으로만 정리한다 — 등장 때 전체 접근과 무관하게 부른다(검증 F1)
    func prunePending(nowHour: Int) -> ExitTraceDropCount
    func loadCounters() -> ExitTraceCounters
    func saveCounters(_ counters: ExitTraceCounters)
    /// 통계 항목을 마지막으로 발신함에 넣은 날(`ExitTraceBuckets.day`)
    func loadLastStatsDay() -> Int?
    func saveLastStatsDay(_ day: Int?)
    /// 이용 분석을 끈 사용자 — 다음 로드부터 설정을 읽기 전에도 아무것도 만들지 않는다
    func loadOptedOut() -> Bool
    func saveOptedOut(_ value: Bool)
    /// 표시·대기·카운터·통계일을 지운다(끈 표지는 남긴다)
    func clearAll()
}

/// App Group 발신함 — 키보드 쪽(추가·정리). 앱의 ack는 **읽기만** 한다
public protocol ExitTraceOutboxWriting: Sendable {
    /// ack 이하·30일 초과를 지우고 넣은 뒤 50건 상한으로 정리한다(빈 목록이면 정리만) — 버린 수(넘침·만료)를 돌려준다.
    /// ack로 지운 칸은 버린 수가 아니다(앱이 처리했다)
    @discardableResult
    func append(_ items: [ExitTraceOutboxItem], nowHour: Int) -> ExitTraceDropCount
}

/// 앱 쪽 발신함 읽기
public protocol ExitTraceOutboxReading: Sendable {
    func entries() -> [ExitTraceOutboxEntry]
    func ack() -> Int
}

/// 앱 쪽 ack 쓰기 — 키보드가 링크하는 코드에는 구현을 두지 않는다
public protocol ExitTraceAckWriting: Sendable {
    func writeAck(_ seq: Int)
}
