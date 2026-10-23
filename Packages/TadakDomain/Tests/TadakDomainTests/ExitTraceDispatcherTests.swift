import Foundation
import Testing
@testable import TadakDomain

// 백로그 14 (가) 키보드 비정상 종료 흔적 — 순수 분배기와 기록 타입의 프라이버시 고정
// (PDR `docs/design-reviews/keyboard-crashlytics.md` 2-7·2-8·8-2-3, 보안 규칙 N21).

private func record(cls: ExitTraceClass = .abnormal, createdAtHour: Int = 500_000) -> ExitTraceRecord {
    ExitTraceRecord(cls: cls, mode: .english, panel: .none, transitions: [.appear, .toEnglish, .heightApplied],
                    idiom: .pad, widthBucket: 320, screenWidthBucket: 1020, memoryBucket: 25, memoryMinBucket: 15,
                    pressure: .warning, residueHours: 3, fullAccessAtCreation: true, buildNumber: 42,
                    osCode: 260_100, createdAtHour: createdAtHour)
}

private func entry(_ seq: Int, record: ExitTraceRecord? = nil, stats: ExitTraceCounters? = nil, createdAtHour: Int = 500_000) -> ExitTraceOutboxEntry {
    ExitTraceOutboxEntry(seq: seq, createdAtHour: createdAtHour, record: record, stats: stats)
}

private let today = Date(timeIntervalSince1970: 500_010 * 3600)

@Suite("종료 흔적 — 분배기(순수)")
struct ExitTraceDispatcherTests {

    @Test("기록 한 건마다 의심 이벤트 하나, 이름은 상수")
    func dispatcherEmitsOneSuspectEventPerRecordWithConstantNames() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record()), entry(2, record: record(cls: .orphan))],
                                            ack: 0, today: today, analyticsEnabled: true)
        #expect(plan.steps.compactMap(\.event).map(\.name) == ["kb_exit_suspect", "kb_exit_suspect"])
        #expect(plan.steps[1].event?.parameters["cls"] == .text("orphan"))
        #expect(plan.steps[0].event?.parameters["tr3"] == .text("heightApplied"))
        #expect(plan.steps[0].event?.parameters["tr4"] == .text("none"))
        #expect(plan.steps[0].event?.parameters["age_d"] == .number(0))
    }

    @Test("통계 항목마다 통계 이벤트 하나")
    func dispatcherEmitsStatsEventPerStatsEntry() {
        let stats = ExitTraceCounters(appearances: 12, abnormal: 1, orphan: 0, update: 2, stale: 0, dropped: 3, expired: 4)
        let plan = ExitTraceDispatcher.plan(entries: [entry(5, stats: stats)], ack: 0, today: today, analyticsEnabled: true)
        let event = plan.steps.first?.event
        #expect(event?.name == "kb_exit_stats")
        #expect(event?.parameters["appear_n"] == .number(12))
        #expect(event?.parameters["upd_n"] == .number(2))
        // 넘쳐서 버린 수와 30일 만료로 버린 수는 따로 간다(검증 F3)
        #expect(event?.parameters["dropped_n"] == .number(3))
        #expect(event?.parameters["expired_n"] == .number(4))
    }

    @Test("이용 분석을 끈 사용자는 보내지 않고 ack만")
    func dispatcherSkipsEventsAndAcksWhenAnalyticsDisabled() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record()), entry(2, stats: ExitTraceCounters(appearances: 1))],
                                            ack: 0, today: today, analyticsEnabled: false)
        #expect(plan.steps.allSatisfy { $0.event == nil })
        #expect(plan.steps.map(\.ackSeq) == [1, 2])
    }

    @Test("생성 후 30일이 지난 항목은 보내지 않고 ack")
    func dispatcherDiscardsEntriesOlderThanThirtyDaysAndAcks() {
        let old = 500_010 - 30 * 24 - 1
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record(createdAtHour: old), createdAtHour: old), entry(2, record: record())],
                                            ack: 0, today: today, analyticsEnabled: true)
        #expect(plan.steps.map(\.ackSeq) == [1, 2])
        #expect(plan.steps[0].event == nil)
        #expect(plan.steps[1].event != nil)
        #expect(plan.discarded == 1)
    }

    // 「30일 초과」의 경계를 고정한다 — 정확히 720시간은 남고 721시간부터 만료(구현 검증 F3, 변이 `>`→`>=`)
    @Test("만료 경계 — 생성 후 정확히 720시간은 남고 721시간이면 만료")
    func retentionKeepsExactlyThirtyDaysAndExpiresTheHourAfter() {
        #expect(ExitTraceRetention.maxAgeHours == 720)
        #expect(!ExitTraceRetention.isExpired(createdAtHour: 1_000, nowHour: 1_000 + 720))
        #expect(ExitTraceRetention.isExpired(createdAtHour: 1_000, nowHour: 1_000 + 721))
        let kept = ExitTraceRetention.retained([1_000 - 720, 1_000 - 721], nowHour: 1_000, limit: 20, createdAtHour: { $0 })
        #expect(kept.kept == [1_000 - 720])
        #expect(kept.dropped == ExitTraceDropCount(overflow: 0, expired: 1))
    }

    @Test("만료 경계 — 생성 후 정확히 720시간 된 칸은 보내고, 721시간 된 칸은 보내지 않고 ack")
    func dispatcherSendsAtExactlyThirtyDaysAndDiscardsTheHourAfter() {
        let at720 = 500_010 - 720
        let at721 = 500_010 - 721
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record(createdAtHour: at720), createdAtHour: at720),
                                                      entry(2, record: record(createdAtHour: at721), createdAtHour: at721)],
                                            ack: 0, today: today, analyticsEnabled: true)
        #expect(plan.steps.map(\.ackSeq) == [1, 2])
        #expect(plan.steps[0].event != nil)
        #expect(plan.steps[1].event == nil)
        #expect(plan.discarded == 1)
    }

    @Test("모르는 열거 값이 든 발신함 항목은 디코드에서 버린다")
    func dispatcherIgnoresEntriesWithUnknownEnumValues() throws {
        let good = try JSONEncoder().encode(entry(1, record: record()))
        var json = try #require(String(data: good, encoding: .utf8))
        json = json.replacingOccurrences(of: "\"english\"", with: "\"klingon\"")
        let decoded = ExitTraceDispatcher.decode([good, Data(json.utf8), Data("garbage".utf8)])
        #expect(decoded.map(\.seq) == [1])
    }

    @Test("이벤트 키는 허용 목록 안")
    func dispatcherEventKeysAreWhitelisted() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record()), entry(2, stats: ExitTraceCounters(appearances: 3))],
                                            ack: 0, today: today, analyticsEnabled: true)
        let suspect = Set(ExitTraceDispatcher.suspectParameterKeys)
        let stats = Set(ExitTraceDispatcher.statsParameterKeys)
        #expect(Set(plan.steps[0].event!.parameters.keys) == suspect)
        #expect(Set(plan.steps[1].event!.parameters.keys) == stats)
    }

    @Test("의심 이벤트 파라미터는 25개 이하")
    func dispatcherSuspectEventHasAtMostTwentyFiveParameters() {
        #expect(ExitTraceDispatcher.suspectParameterKeys.count == 19)
        #expect(ExitTraceDispatcher.suspectParameterKeys.count <= 25)
        #expect(ExitTraceDispatcher.statsParameterKeys.count <= 25)
    }

    @Test("이벤트 이름은 40자 이하")
    func dispatcherEventNamesAreAtMostFortyCharacters() {
        #expect(ExitTraceDispatcher.suspectEventName.count <= 40)
        #expect(ExitTraceDispatcher.statsEventName.count <= 40)
    }

    @Test("활성화 한 번에 20건까지")
    func dispatcherCapsEventsPerActivationAtTwenty() {
        let entries = (1...25).map { entry($0, record: record()) }
        let plan = ExitTraceDispatcher.plan(entries: entries, ack: 0, today: today, analyticsEnabled: true)
        #expect(plan.steps.count == 20)
        #expect(plan.steps.last?.ackSeq == 20)
    }

    @Test("항목마다 ack — 이미 ack한 것은 건너뛴다")
    func dispatcherPlansAckAfterEachEntry() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(3, record: record()), entry(1, record: record()), entry(2, record: record())],
                                            ack: 1, today: today, analyticsEnabled: true)
        #expect(plan.steps.map(\.ackSeq) == [2, 3])
    }

    @Test("중복 제거용 seq를 싣는다")
    func dispatcherIncludesSequenceForDedup() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(7, record: record())], ack: 0, today: today, analyticsEnabled: true)
        #expect(plan.steps.first?.event?.parameters["seq"] == .number(7))
    }
}

@Suite("종료 흔적 — 기록 타입의 프라이버시 고정(N21)")
struct ExitTracePrivacyTests {

    private func labels(_ value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label)
    }

    @Test("기록에 String 저장 프로퍼티가 없다(리플렉션)")
    func recordHasNoStringFields() {
        // 함께 저장되는 표시·OS 버전까지 본다(검증 F6)
        let stored: [Any] = [record(), ExitTraceCounters(appearances: 1), entry(1, record: record()),
                             ExitTraceMarker.sample, ExitTraceOSVersion(major: 26, minor: 1, patch: 0)]
        for value in stored {
            for child in Mirror(reflecting: value).children {
                // `is String?`는 다른 형의 nil에도 참이라 동적 형으로 비교한다
                let fieldType = type(of: child.value)
                #expect(fieldType != String.self && fieldType != String?.self && fieldType != [String].self,
                        "\(child.label ?? "?")")
            }
        }
    }

    @Test("기록 인코딩 키는 허용 목록 그대로")
    func recordEncodingKeysAreWhitelisted() throws {
        let data = try JSONEncoder().encode(record())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == [
            "cls", "mode", "panel", "transitions", "idiom", "widthBucket", "screenWidthBucket", "memoryBucket", "memoryMinBucket",
            "pressure", "residueHours", "fullAccessAtCreation", "buildNumber", "osCode", "createdAtHour",
        ])
    }

    @Test("입력란 종류·secure 표지가 없다")
    func recordHasNoFieldTraitOrSecureFlag() {
        let names = (labels(record()) + labels(ExitTraceMarker.sample)).map { $0.lowercased() }
        for forbidden in ["keyboardtype", "secure", "trait", "returnkey", "autocap", "textcontent"] {
            #expect(!names.contains { $0.contains(forbidden) }, "\(forbidden)")
        }
    }

    @Test("문서 식별자를 싣지 않는다")
    func recordDoesNotCarryDocumentIdentifier() {
        let names = labels(record()).map { $0.lowercased() }
        #expect(!names.contains { $0.contains("document") || $0.contains("host") || $0.contains("bundle") })
        #expect(!Mirror(reflecting: record()).children.contains { $0.value is UUID || $0.value is UUID? })
    }

    @Test("패널 열거에 기능별 칸(성경 검색 등)이 없다(K2-05)")
    func panelEnumHasNoFeatureSpecificCases() {
        #expect(ExitTracePanel.allCases == [.none, .emoji, .clipboard, .other])
    }

    @Test("표시의 pid·소유 토큰은 기록 인코딩에 들어가지 않는다")
    func markerPidAndTokenAreNeverEncodedIntoRecord() throws {
        let json = try #require(String(data: try JSONEncoder().encode(record()), encoding: .utf8))
        #expect(!json.contains("pid") && !json.contains("ownerToken") && !json.contains("orphaned"))
    }
}

extension ExitTraceMarker {
    static let sample = ExitTraceMarker(pid: 1, ownerToken: 1, setAtHour: 500_000, buildNumber: 1,
                                        os: ExitTraceOSVersion(major: 26, minor: 1, patch: 0), idiom: .phone)
}

// MARK: - 계획 실행(앱 리포터가 그대로 쓴다) — 보낸 **직후** 그 칸의 ack(M4), 보내지 않는 칸도 ack

private final class AckSpy: ExitTraceAckWriting, @unchecked Sendable {
    var log: [String] = []
    func writeAck(_ seq: Int) { log.append("ack \(seq)") }
}

@Suite("종료 흔적 — 계획 실행")
struct ExitTraceDeliveryTests {

    @Test("이벤트를 보낸 직후 그 칸을 ack한다 — 순서가 칸마다 보냄→ack")
    func deliverSendsThenAcksEachStepInOrder() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(3, record: record()), entry(4, stats: ExitTraceCounters(appearances: 1))],
                                            ack: 2, today: today, analyticsEnabled: true)
        let spy = AckSpy()
        let sent = ExitTraceDispatcher.deliver(plan, send: { spy.log.append("send \($0.name)") }, ack: spy)
        #expect(spy.log == ["send kb_exit_suspect", "ack 3", "send kb_exit_stats", "ack 4"])
        #expect(sent == 2)
    }

    @Test("이용 분석을 끈 사용자 — 아무것도 보내지 않고 ack만")
    func deliverAcksWithoutSendingWhenAnalyticsDisabled() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record()), entry(2, record: record())],
                                            ack: 0, today: today, analyticsEnabled: false)
        let spy = AckSpy()
        let sent = ExitTraceDispatcher.deliver(plan, send: { spy.log.append("send \($0.name)") }, ack: spy)
        #expect(spy.log == ["ack 1", "ack 2"])
        #expect(sent == 0)
    }

    @Test("30일 지난 칸은 보내지 않고 ack만 — 다른 칸은 그대로 보낸다")
    func deliverSkipsExpiredButAcksIt() {
        let old = 500_010 - 31 * 24
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record(createdAtHour: old), createdAtHour: old),
                                                      entry(2, record: record())],
                                            ack: 0, today: today, analyticsEnabled: true)
        let spy = AckSpy()
        _ = ExitTraceDispatcher.deliver(plan, send: { spy.log.append("send \($0.name)") }, ack: spy)
        #expect(spy.log == ["ack 1", "send kb_exit_suspect", "ack 2"])
    }

    @Test("보낼 칸이 없으면 보내지도 ack하지도 않는다")
    func deliverWithNothingDueTouchesNothing() {
        let plan = ExitTraceDispatcher.plan(entries: [entry(1, record: record())], ack: 1, today: today, analyticsEnabled: true)
        let spy = AckSpy()
        #expect(ExitTraceDispatcher.deliver(plan, send: { spy.log.append("send \($0.name)") }, ack: spy) == 0)
        #expect(spy.log.isEmpty)
    }
}
