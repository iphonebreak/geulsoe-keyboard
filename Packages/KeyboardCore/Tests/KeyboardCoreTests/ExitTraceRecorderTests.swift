import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// 백로그 14 (가) 종료 흔적 판정기 — 시계·pid·토큰·저장소를 주입해 표시 수명(2-3)·판정표(2-5)·FA 없는 경로(2-6)·
// 발신함 이동(2-8)을 고정한다. PDR `docs/design-reviews/keyboard-crashlytics.md` 8-2-3.

private final class FakeStore: ExitTraceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var marker: ExitTraceMarker?
    private var pending: [ExitTraceRecord] = []
    private var counters = ExitTraceCounters()
    private var statsDay: Int?
    private var optedOut = false

    func loadMarker() -> ExitTraceMarker? { lock.withLock { marker } }
    func saveMarker(_ marker: ExitTraceMarker?) { lock.withLock { self.marker = marker } }
    func loadPending() -> [ExitTraceRecord] { lock.withLock { pending } }
    func savePending(_ records: [ExitTraceRecord]) { lock.withLock { pending = records } }
    func appendPending(_ record: ExitTraceRecord, nowHour: Int) -> ExitTraceDropCount {
        retain(pending + [record], nowHour: nowHour)
    }
    func prunePending(nowHour: Int) -> ExitTraceDropCount {
        retain(pending, nowHour: nowHour)
    }
    private func retain(_ records: [ExitTraceRecord], nowHour: Int) -> ExitTraceDropCount {
        lock.withLock {
            let result = ExitTraceRetention.retained(records, nowHour: nowHour, limit: ExitTraceRetention.pendingLimit,
                                                     createdAtHour: \.createdAtHour)
            pending = result.kept
            return result.dropped
        }
    }
    func loadCounters() -> ExitTraceCounters { lock.withLock { counters } }
    func saveCounters(_ counters: ExitTraceCounters) { lock.withLock { self.counters = counters } }
    func loadLastStatsDay() -> Int? { lock.withLock { statsDay } }
    func saveLastStatsDay(_ day: Int?) { lock.withLock { statsDay = day } }
    func loadOptedOut() -> Bool { lock.withLock { optedOut } }
    func saveOptedOut(_ value: Bool) { lock.withLock { optedOut = value } }
    func clearAll() { lock.withLock { marker = nil; pending = []; counters = ExitTraceCounters(); statsDay = nil } }
}

private final class FakeOutbox: ExitTraceOutboxWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [ExitTraceOutboxItem] = []
    private(set) var appendCalls = 0
    func append(_ items: [ExitTraceOutboxItem], nowHour: Int) -> ExitTraceDropCount {
        lock.withLock { appendCalls += 1; self.items += items }
        return ExitTraceDropCount()
    }
    var records: [ExitTraceRecord] { items.compactMap { if case .record(let r) = $0 { r } else { nil } } }
    var stats: [ExitTraceCounters] { items.compactMap { if case .stats(let s) = $0 { s } else { nil } } }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 500_000 * 3600 + 120)
    var now: Date { lock.withLock { current } }
    func advance(hours: Double) { lock.withLock { current = current.addingTimeInterval(hours * 3600) } }
}

private final class TestMemory: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: UInt64? = 40 << 20
    var value: UInt64? { lock.withLock { bytes } }
    func set(megabytes: Double) { lock.withLock { bytes = UInt64(megabytes * 1_048_576) } }
}

private let os26 = ExitTraceOSVersion(major: 26, minor: 1, patch: 0)

/// 한 기기(저장소·발신함·시계)를 두고 프로세스·VC를 바꿔 가며 띄운다
private final class Device {
    let store = FakeStore()
    let outbox = FakeOutbox()
    let clock = TestClock()
    let memory = TestMemory()

    func recorder(pid: Int32 = 100, token: UInt32 = 1, build: Int = 42, os: ExitTraceOSVersion = os26) -> ExitTraceRecorder {
        let clock = clock, memory = memory
        return ExitTraceRecorder(store: store, outbox: outbox,
                                 environment: ExitTraceEnvironment(pid: pid, buildNumber: build, os: os),
                                 ownerToken: token, clock: { clock.now }, availableMemory: { memory.value })
    }

    /// 프로세스 하나가 떠서 키보드가 한 번 보인 상태 — 퇴장 콜백 없이 끝나면 다음 로드가 판정한다
    @discardableResult
    func appeared(pid: Int32 = 100, token: UInt32 = 1, build: Int = 42, os: ExitTraceOSVersion = os26, fullAccess: Bool = false) -> ExitTraceRecorder {
        let r = recorder(pid: pid, token: token, build: build, os: os)
        r.didLoad(idiom: .phone)
        r.applySettings(exitTraceEnabled: true)
        r.willAppear(fullAccess: fullAccess, mode: .english, panel: .none, width: 393, screenWidth: 393)
        return r
    }
}

@Suite("종료 흔적 — 판정기", .serialized)
struct ExitTraceRecorderTests {

    // MARK: 표시 수명

    @Test("이전 표시가 없으면 기록 없이 표시만 세운다")
    func didLoadWithoutOldMarkerYieldsNoRecordAndSetsMarker() {
        let device = Device()
        let judgement = device.recorder().didLoad(idiom: .pad)
        #expect(judgement == .none)
        #expect(device.store.loadPending().isEmpty)
        let marker = device.store.loadMarker()
        #expect(marker?.pid == 100 && marker?.ownerToken == 1 && marker?.idiom == .pad)
        #expect(marker?.setAtHour == 500_000 && marker?.orphaned == false)
    }

    @Test("설정을 읽기 전에 표시를 쓴다 — 자판·전체 접근은 unknown(C5)")
    func didLoadSetsMarkerBeforeSettingsAreKnown() {
        let device = Device()
        device.recorder().didLoad(idiom: .phone)
        let marker = device.store.loadMarker()
        #expect(marker?.mode == .unknown && marker?.fullAccess == .unknown)
        #expect(marker?.transitions.isEmpty == true)
    }

    @Test("등장은 표시를 갱신하고 등장 수를 한 번 센다")
    func willAppearRefreshesMarkerFieldsAndCountsAppearanceOnce() {
        let device = Device()
        let r = device.recorder()
        r.didLoad(idiom: .phone)
        r.applySettings(exitTraceEnabled: true)
        device.memory.set(megabytes: 27.9)
        r.willAppear(fullAccess: false, mode: .cheonjiin, panel: .emoji, width: 393, screenWidth: 393)
        let marker = device.store.loadMarker()
        #expect(marker?.fullAccess == .off && marker?.mode == .cheonjiin && marker?.panel == .emoji)
        #expect(marker?.widthBucket == 380 && marker?.screenWidthBucket == 380)
        #expect(marker?.memoryBucket == 25 && marker?.memoryMinBucket == 25)
        #expect(marker?.transitions == [.appear])
        #expect(device.store.loadCounters().appearances == 1)
    }

    @Test("퇴장 끝에서 내 표시를 지운다")
    func disappearAtEndClearsOwnMarker() {
        let device = Device()
        device.appeared().willDisappear()
        #expect(device.store.loadMarker() == nil)
    }

    @Test("깨끗하게 내려간 같은 VC가 다시 뜨면 표시를 다시 세운다")
    func willAppearAfterCleanDisappearRestoresMarkerForSameViewController() {
        let device = Device()
        let r = device.appeared()
        r.willDisappear()
        r.willAppear(fullAccess: false, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.store.loadMarker()?.ownerToken == 1)
        #expect(device.store.loadCounters().appearances == 2)
        #expect(device.store.loadPending().isEmpty)
    }

    // MARK: 판정표(2-5)

    @Test("pid가 다른 표시는 abnormal 기록 — 사건 당시 맥락을 싣는다")
    func markerWithOtherPidIsAbnormalRecord() {
        let device = Device()
        let first = device.appeared(pid: 100, fullAccess: true)
        first.observe(mode: .dubeolsik, panel: .none)
        device.clock.advance(hours: 2)
        let judgement = device.recorder(pid: 200, token: 2).didLoad(idiom: .phone)
        #expect(judgement == .recorded(.abnormal))
        let record = device.store.loadPending().first
        #expect(record?.cls == .abnormal && record?.mode == .dubeolsik)
        #expect(record?.transitions == [.appear, .toHangul])
        #expect(record?.residueHours == 2 && record?.buildNumber == 42 && record?.osCode == 260_100)
        #expect(record?.fullAccessAtCreation == true)
        #expect(device.store.loadCounters().abnormal == 1)
        #expect(device.store.loadMarker()?.pid == 200)
    }

    @Test("pid가 같은 표시는 무시하지 않고 orphan 기록(C2)")
    func markerWithSamePidIsOrphanRecordNotIgnored() {
        let device = Device()
        device.appeared(pid: 100, token: 1)
        let judgement = device.recorder(pid: 100, token: 2).didLoad(idiom: .phone)
        #expect(judgement == .recorded(.orphan))
        #expect(device.store.loadPending().map(\.cls) == [.orphan])
        #expect(device.store.loadCounters().orphan == 1)
    }

    @Test("orphaned 표지가 붙은 표시를 다른 pid가 보면 orphan이다(C3)")
    func orphanedMarkerSeenByOtherPidIsOrphanNotAbnormal() {
        let device = Device()
        device.appeared(pid: 100).deinitialized()
        #expect(device.recorder(pid: 300, token: 9).didLoad(idiom: .phone) == .recorded(.orphan))
    }

    @Test("퇴장 없이 해제되면 내 표시에 orphaned 표지(C3)")
    func ownerDeinitWithoutDisappearMarksOrphaned() {
        let device = Device()
        device.appeared().deinitialized()
        #expect(device.store.loadMarker()?.orphaned == true)
    }

    @Test("퇴장 뒤 해제되면 표시가 남지 않는다")
    func ownerDeinitAfterDisappearLeavesNoMarker() {
        let device = Device()
        let r = device.appeared()
        r.willDisappear()
        r.deinitialized()
        #expect(device.store.loadMarker() == nil)
    }

    @Test("옛 VC의 퇴장은 새 VC의 표시를 지우지 않는다(토큰)")
    func staleOwnerDisappearDoesNotClearNewerMarker() {
        let device = Device()
        let old = device.appeared(token: 1)
        let newer = device.appeared(token: 2)
        old.willDisappear()
        #expect(device.store.loadMarker()?.ownerToken == 2)
        newer.willDisappear()
        #expect(device.store.loadMarker() == nil)
    }

    @Test("옛 VC의 해제는 새 VC의 표시에 orphaned를 붙이지 않는다(토큰)")
    func staleOwnerDeinitDoesNotMarkNewerMarkerOrphaned() {
        let device = Device()
        let old = device.appeared(token: 1)
        device.appeared(token: 2)
        old.deinitialized()
        #expect(device.store.loadMarker()?.ownerToken == 2)
        #expect(device.store.loadMarker()?.orphaned == false)
    }

    @Test("빌드가 다르면 update — 숫자로만 센다")
    func differentBuildIsUpdateResidueCountedNotRecorded() {
        let device = Device()
        device.appeared(build: 41)
        #expect(device.recorder(pid: 200, build: 42).didLoad(idiom: .phone) == .update)
        #expect(device.store.loadPending().isEmpty)
        #expect(device.store.loadCounters().update == 1)
        #expect(device.store.loadMarker()?.buildNumber == 42)
    }

    @Test("OS 패치만 달라도 update(M3)")
    func differentOSPatchIsUpdateResidue() {
        let device = Device()
        device.appeared(os: ExitTraceOSVersion(major: 26, minor: 1, patch: 0))
        let judgement = device.recorder(pid: 200, os: ExitTraceOSVersion(major: 26, minor: 1, patch: 1)).didLoad(idiom: .phone)
        #expect(judgement == .update)
        #expect(device.store.loadPending().isEmpty)
    }

    @Test("12시간 넘게 남은 표시는 stale — 기록 없음")
    func markerOlderThanTwelveHoursIsStaleNotRecorded() {
        let device = Device()
        device.appeared()
        device.clock.advance(hours: 13)
        #expect(device.recorder(pid: 200).didLoad(idiom: .phone) == .stale)
        #expect(device.store.loadPending().isEmpty)
        #expect(device.store.loadCounters().stale == 1)
    }

    @Test("미래 시각의 표시는 stale(시계 변경)")
    func markerFromFutureHourIsStale() {
        let device = Device()
        device.clock.advance(hours: 5)
        device.appeared()
        device.clock.advance(hours: -5)
        #expect(device.recorder(pid: 200).didLoad(idiom: .phone) == .stale)
    }

    @Test("시계가 뒤로 가도 경과는 음수가 아니라 0")
    func clockMovedBackwardYieldsZeroAgeNotNegative() throws {
        let device = Device()
        device.appeared()
        device.recorder(pid: 200, token: 2).didLoad(idiom: .phone)
        let created = try #require(device.store.loadPending().first)
        #expect(created.residueHours == 0)
        #expect(ExitTraceBuckets.residueHours(setAtHour: 10, nowHour: 7) == 0)
        let entry = ExitTraceOutboxEntry(seq: 1, createdAtHour: created.createdAtHour, record: created, stats: nil)
        let earlier = Date(timeIntervalSince1970: TimeInterval(created.createdAtHour - 50) * 3600)
        let plan = ExitTraceDispatcher.plan(entries: [entry], ack: 0, today: earlier, analyticsEnabled: true)
        #expect(plan.steps.first?.event?.parameters["age_d"] == .number(0))
    }

    // MARK: 전환·메모리

    @Test("최근 전환은 마지막 4개를 순서대로")
    func recentTransitionsKeepLastFourInOrder() {
        let device = Device()
        let r = device.appeared()
        r.observe(mode: .dubeolsik, panel: .none)
        r.observe(mode: .symbols, panel: .none)
        r.observe(mode: .symbols, panel: .clipboard)
        r.settingsReloaded()
        #expect(device.store.loadMarker()?.transitions == [.toHangul, .toSymbols, .panelOpen, .settingsReload])
        r.observe(mode: .numberPad, panel: .clipboard)
        #expect(device.store.loadMarker()?.transitions == [.toSymbols, .panelOpen, .settingsReload, .toNumberPad])
    }

    @Test("높이는 실제로 바뀐 경우에만 전환으로 남긴다(M2)")
    func heightAppliedRecordedOnlyWhenHeightChanged() {
        let device = Device()
        let r = device.appeared()
        r.heightApplied(262, width: 393, screenWidth: 393)
        r.heightApplied(262, width: 393, screenWidth: 393)
        #expect(device.store.loadMarker()?.transitions == [.appear])
        r.heightApplied(300, width: 300, screenWidth: 1024)
        #expect(device.store.loadMarker()?.transitions == [.appear, .heightApplied])
        #expect(device.store.loadMarker()?.widthBucket == 300 && device.store.loadMarker()?.screenWidthBucket == 1020)
    }

    @Test("전환 때 메모리를 뜨고 최솟값을 지킨다")
    func transitionSamplesMemoryAndKeepsMinimum() {
        let device = Device()
        let r = device.appeared()
        device.memory.set(megabytes: 12)
        r.observe(mode: .dubeolsik, panel: .none)
        device.memory.set(megabytes: 33)
        r.observe(mode: .english, panel: .none)
        let marker = device.store.loadMarker()
        #expect(marker?.memoryBucket == 30 && marker?.memoryMinBucket == 10)
    }

    @Test("압박 이벤트는 그 순간 메모리를 뜨고 단계를 올린다(C1)")
    func memoryPressureEventSamplesMemoryAndRaisesPressure() {
        let device = Device()
        let r = device.appeared()
        device.memory.set(megabytes: 4)
        r.memoryPressure(.critical)
        let marker = device.store.loadMarker()
        #expect(marker?.pressure == .critical && marker?.memoryMinBucket == 0)
        #expect(marker?.transitions.last == .memoryPressure)
        r.memoryWarning()
        #expect(device.store.loadMarker()?.transitions.last == .memoryWarning)
    }

    @Test("압박 단계는 내려가지 않는다")
    func memoryPressureNeverLowersRecordedLevel() {
        let device = Device()
        let r = device.appeared()
        r.memoryPressure(.critical)
        r.memoryPressure(.warning)
        r.memoryWarning()
        #expect(device.store.loadMarker()?.pressure == .critical)
    }

    @Test("메모리는 5MB 단위로 내림")
    func memoryBucketRoundsDownToFiveMegabytes() {
        #expect(ExitTraceBuckets.memory(bytes: 27 * 1_048_576 + 999) == 25)
        #expect(ExitTraceBuckets.memory(bytes: 30 * 1_048_576) == 30)
        #expect(ExitTraceBuckets.memory(bytes: 4 * 1_048_576) == 0)
        #expect(ExitTraceBuckets.memory(bytes: nil) == ExitTraceBuckets.unknown)
    }

    @Test("폭은 20pt 단위로 내림")
    func widthBucketRoundsDownToTwentyPoints() {
        #expect(ExitTraceBuckets.width(393) == 380)
        #expect(ExitTraceBuckets.width(320) == 320)
        #expect(ExitTraceBuckets.width(19.9) == 0)
        #expect(ExitTraceBuckets.width(-5) == 0)
        #expect(ExitTraceBuckets.width(.nan) == 0)
    }

    @Test("잔존 시간은 48시간 상한")
    func residueHoursIsCappedAtFortyEight() {
        #expect(ExitTraceBuckets.residueHours(setAtHour: 0, nowHour: 100) == 48)
        #expect(ExitTraceBuckets.residueHours(setAtHour: 10, nowHour: 13) == 3)
    }

    // MARK: 끈 사용자(2-8 ①)

    @Test("설정이 꺼져 있으면 표시·대기·카운터를 지우고 더 기록하지 않는다")
    func disabledSettingClearsMarkerPendingAndCountersAndStopsRecording() {
        let device = Device()
        device.appeared(pid: 100)
        let second = device.recorder(pid: 200, token: 2)
        second.didLoad(idiom: .phone)
        #expect(device.store.loadPending().count == 1)
        second.applySettings(exitTraceEnabled: false)
        #expect(device.store.loadMarker() == nil && device.store.loadPending().isEmpty)
        #expect(device.store.loadCounters() == ExitTraceCounters())
        second.willAppear(fullAccess: false, mode: .english, panel: .none, width: 393, screenWidth: 393)
        second.observe(mode: .dubeolsik, panel: .emoji)
        second.memoryPressure(.critical)
        second.deinitialized()
        #expect(device.store.loadMarker() == nil && device.store.loadCounters() == ExitTraceCounters())
        // 다음 프로세스는 설정을 읽기 전부터 아무것도 만들지 않는다 — 끈 표지가 남아 있다
        let third = device.recorder(pid: 300, token: 3)
        #expect(third.didLoad(idiom: .phone) == .none)
        #expect(device.store.loadMarker() == nil && device.store.loadPending().isEmpty)
        // 다시 켜면 다음 등장부터 기록한다
        third.applySettings(exitTraceEnabled: true)
        third.willAppear(fullAccess: false, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.store.loadMarker()?.ownerToken == 3)
    }

    @Test("설정이 꺼져 있으면 발신함에 옮기지도 정리하지도 않는다")
    func disabledSettingNeverRelays() {
        let device = Device()
        let r = device.recorder()
        r.didLoad(idiom: .phone)
        r.applySettings(exitTraceEnabled: false)
        r.willAppear(fullAccess: true, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.outbox.appendCalls == 0)
    }

    // MARK: 발신함 이동(2-6·2-8)

    @Test("전체 접근이 있을 때만 대기 기록을 발신함으로 옮긴다")
    func relayMovesPendingToOutboxOnlyWhenFullAccess() {
        let device = Device()
        device.appeared(pid: 100)
        let r = device.recorder(pid: 200, token: 2)
        r.didLoad(idiom: .phone)
        r.applySettings(exitTraceEnabled: true)
        r.willAppear(fullAccess: true, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.outbox.records.map(\.cls) == [.abnormal])
        #expect(device.store.loadPending().isEmpty)
    }

    @Test("전체 접근이 없으면 대기 기록은 자기 컨테이너에 남는다")
    func relayWithoutFullAccessKeepsPendingInOwnContainer() {
        let device = Device()
        device.appeared(pid: 100)
        device.appeared(pid: 200, token: 2, fullAccess: false)
        #expect(device.outbox.appendCalls == 0)
        #expect(device.store.loadPending().count == 1)
    }

    @Test("통계 항목은 하루 한 번, 또는 기록을 옮길 때 붙는다")
    func relayAddsStatsEntryOncePerDayOrWhenRecordsMoved() {
        let device = Device()
        let r = device.appeared(fullAccess: true)
        #expect(device.outbox.stats.count == 1)
        r.willDisappear()
        r.willAppear(fullAccess: true, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.outbox.stats.count == 1)
        device.appeared(pid: 200, token: 2, fullAccess: true)   // 표시가 남은 1번 VC — 다음 로드가 orphan이 아니라 abnormal
        #expect(device.outbox.records.count == 1)
        #expect(device.outbox.stats.count == 2)
        device.clock.advance(hours: 24)
        device.store.saveMarker(nil)
        device.appeared(pid: 300, token: 3, fullAccess: true)
        #expect(device.outbox.stats.count == 3)
    }

    @Test("새 기록·전체 접근이 없어도 등장 때 30일 지난 대기 기록을 버리고 만료로 센다(검증 F1·F3)")
    func pendingExpiresAtAppearanceEvenWithoutNewRecordsOrFullAccess() {
        let device = Device()
        device.appeared(pid: 100)
        device.recorder(pid: 200, token: 2).didLoad(idiom: .phone)
        #expect(device.store.loadPending().count == 1)
        device.clock.advance(hours: 31 * 24)
        let later = device.recorder(pid: 300, token: 3)
        #expect(later.didLoad(idiom: .phone) == .stale)          // 31일 묵은 표시 — 새 기록 없음
        later.applySettings(exitTraceEnabled: true)
        later.willAppear(fullAccess: false, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.store.loadPending().isEmpty)
        #expect(device.outbox.appendCalls == 0)
        let counters = device.store.loadCounters()
        #expect(counters.expired == 1 && counters.dropped == 0)
    }

    @Test("등장 수는 발신함에 한 번만 옮기고 0으로 되돌린다(M4)")
    func appearanceCountMovesToOutboxOnceAndResets() {
        let device = Device()
        let r = device.appeared(fullAccess: true)
        r.willDisappear()
        r.willAppear(fullAccess: true, mode: .english, panel: .none, width: 393, screenWidth: 393)
        r.willDisappear()
        #expect(device.store.loadCounters().appearances == 1)
        device.clock.advance(hours: 24)
        r.willAppear(fullAccess: true, mode: .english, panel: .none, width: 393, screenWidth: 393)
        #expect(device.outbox.stats.map(\.appearances) == [1, 2])
        #expect(device.store.loadCounters() == ExitTraceCounters())
    }

    @Test("전체 접근이 꺼진 동안 만든 기록은 fa_rec 0을 싣는다(K2-02)")
    func recordCreatedWhileFullAccessOffCarriesFaRecZero() {
        let device = Device()
        device.appeared(pid: 100, fullAccess: false)
        device.appeared(pid: 200, token: 2, fullAccess: true)
        #expect(device.outbox.records.first?.fullAccessAtCreation == false)
        let entry = ExitTraceOutboxEntry(seq: 1, createdAtHour: 500_000, record: device.outbox.records.first, stats: nil)
        let plan = ExitTraceDispatcher.plan(entries: [entry], ack: 0, today: device.clock.now, analyticsEnabled: true)
        #expect(plan.steps.first?.event?.parameters["fa_rec"] == .number(0))
    }

    // MARK: 자판·패널 매핑

    @Test("입력 모드를 기록용 자판 종류로 옮긴다")
    func modeMapping() {
        #expect(ExitTraceMode(inputMode: .hangul, hangulLayout: .danmoeum) == .danmoeum)
        #expect(ExitTraceMode(inputMode: .english, hangulLayout: .dubeolsik) == .english)
        #expect(ExitTraceMode(inputMode: .symbolsAlternate, hangulLayout: .dubeolsik) == .symbols)
        #expect(ExitTraceMode(inputMode: .keypadPad(page: 0), hangulLayout: .dubeolsik) == .keypadNumber)
        #expect(ExitTraceMode(inputMode: .keypadPad(page: 2), hangulLayout: .dubeolsik) == .keypadSymbols)
        #expect(ExitTracePanel(emoji: false, clipboard: false, other: true) == .other)
        #expect(ExitTracePanel(emoji: true, clipboard: false, other: false) == .emoji)
    }
}
