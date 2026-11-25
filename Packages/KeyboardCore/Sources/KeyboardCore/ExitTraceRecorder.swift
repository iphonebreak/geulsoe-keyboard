import Foundation
import TadakDomain

// 백로그 14 (가) 키보드 비정상 종료 흔적 — 판정기·표시 수명·카운터·발신함 이동.
// PDR `docs/design-reviews/keyboard-crashlytics.md` 2-3(언제 세우고 지우나)·2-5(판정표)·2-6(FA 없을 때)·2-8(통계), 보안 규칙 N21.
//
// VC는 생명주기 지점에서 **부르기만** 한다(`Keyboard/ExitTraceHooks.swift`·`KeyboardViewController`). 시계·pid·소유 토큰·
// 빌드/OS·메모리 표본기·저장소는 주입한다. 시계는 `Date`(시 단위)뿐 — `systemUptime`·`mach_absolute_time`은 「부팅 시간」
// 필수 사유 범주라 쓰지 않는다(TN3183). 로그·파일·네트워크로 내보내지 않는다.
//
// ★ 스레드 안전: `deinit`은 Swift 6에서 비격리라 `deinitialized()`가 메인이 아닌 곳에서 불릴 수 있다 — 모든 진입점이 락 안에서 돈다.

/// 판정 결과(2-5) — 시험·보고용
public enum ExitTraceJudgement: Equatable, Sendable {
    case none, update, stale
    case recorded(ExitTraceClass)
}

/// 조립 지점이 주는 프로세스 환경 — idiom은 UIKit(메인)이 필요해 `didLoad`에서 받는다
public struct ExitTraceEnvironment: Sendable {
    public let pid: Int32
    public let buildNumber: Int
    public let os: ExitTraceOSVersion

    public init(pid: Int32, buildNumber: Int, os: ExitTraceOSVersion) {
        self.pid = pid
        self.buildNumber = buildNumber
        self.os = os
    }
}

/// VC 소유 토큰 — 프로세스 안 증가 정수(문자열 아님)
public enum ExitTraceOwnerToken {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last: UInt32 = 0

    public static func next() -> UInt32 {
        lock.withLock {
            last &+= 1
            return last
        }
    }
}

public final class ExitTraceRecorder: @unchecked Sendable {

    /// 표시를 쓴 지 이만큼 지나 발견하면 판정하지 않고 `stale`로 센다(시계 변경·장기 방치)
    static let staleAfterHours = 12

    private let store: any ExitTraceStore
    private let outbox: any ExitTraceOutboxWriting
    private let environment: ExitTraceEnvironment
    private let ownerToken: UInt32
    private let clock: @Sendable () -> Date
    private let availableMemory: @Sendable () -> UInt64?

    private let lock = NSLock()
    /// 설정·끈 표지가 허락하는가 — 끈 사용자는 아무것도 만들지 않는다(2-8 ①)
    private var enabled = true
    private var optedOut = false
    private var idiom: ExitTraceIdiom = .phone
    private var lastHeight: Double?
    /// 마지막으로 본 자판·패널·폭 버킷 — 레이아웃마다 불려도 바뀌지 않았으면 저장소를 건드리지 않는다
    private var lastObserved: (mode: ExitTraceMode, panel: ExitTracePanel)?
    private var lastWidthBuckets: (width: Int, screen: Int)?

    public init(store: any ExitTraceStore, outbox: any ExitTraceOutboxWriting, environment: ExitTraceEnvironment,
                ownerToken: UInt32 = ExitTraceOwnerToken.next(), clock: @escaping @Sendable () -> Date = { Date() },
                availableMemory: @escaping @Sendable () -> UInt64? = { nil }) {
        self.store = store
        self.outbox = outbox
        self.environment = environment
        self.ownerToken = ownerToken
        self.clock = clock
        self.availableMemory = availableMemory
    }

    // MARK: 생명주기

    /// `viewDidLoad` 첫 줄 — 이전 표시를 판정한 뒤 새 표시를 쓴다(C5). 판정은 **여기 한 곳**에서만 한다
    @discardableResult
    public func didLoad(idiom: ExitTraceIdiom) -> ExitTraceJudgement {
        lock.withLock {
            self.idiom = idiom
            optedOut = store.loadOptedOut()
            guard !optedOut else { return .none }
            let nowHour = ExitTraceBuckets.hour(of: clock())
            let judgement = store.loadMarker().map { judge($0, nowHour: nowHour) } ?? .none
            store.saveMarker(freshMarker(nowHour: nowHour))
            return judgement
        }
    }

    /// 설정 로드 직후·재로드마다 — 꺼져 있으면 표시·대기·카운터를 지우고 끈 표지를 남긴다
    public func applySettings(exitTraceEnabled: Bool) {
        lock.withLock {
            if exitTraceEnabled {
                if optedOut { store.saveOptedOut(false) }
                optedOut = false
                enabled = true
                return
            }
            if enabled || !optedOut {
                store.clearAll()
                store.saveOptedOut(true)
            }
            optedOut = true
            enabled = false
        }
    }

    /// `viewWillAppear` — 판정하지 않고 표시를 갱신(없으면 다시 세움)하고 등장을 센다. 전체 접근이 있으면 발신함으로 옮긴다
    public func willAppear(fullAccess: Bool, mode: ExitTraceMode, panel: ExitTracePanel, width: Double, screenWidth: Double) {
        lock.withLock {
            guard isActive else { return }
            let nowHour = ExitTraceBuckets.hour(of: clock())
            var marker = store.loadMarker().flatMap { $0.ownerToken == ownerToken ? $0 : nil } ?? freshMarker(nowHour: nowHour)
            marker.fullAccess = fullAccess ? .on : .off
            marker.widthBucket = ExitTraceBuckets.width(width)
            marker.screenWidthBucket = ExitTraceBuckets.width(screenWidth)
            // 등장 자체가 전환이다 — 그때의 자판·패널은 전환을 따로 남기지 않고 그대로 적는다
            if mode != .unknown { marker.mode = mode }
            marker.panel = panel
            lastObserved = (mode, panel)
            lastWidthBuckets = (marker.widthBucket, marker.screenWidthBucket)
            push(.appear, to: &marker)
            sampleMemory(into: &marker)
            store.saveMarker(marker)
            // 대기 목록 30일·20건 정리는 전체 접근과 무관하게 등장마다 한다 — 새 기록이 없어도 만료분이 남지 않게(검증 F1)
            var counters = store.loadCounters().adding(store.prunePending(nowHour: nowHour))
            counters.appearances += 1
            store.saveCounters(counters)
            if fullAccess { relay(nowHour: nowHour) }
        }
    }

    /// `viewWillDisappear` 끝 — 내 표시일 때만 지운다(토큰)
    public func willDisappear() {
        lock.withLock {
            guard isActive, store.loadMarker()?.ownerToken == ownerToken else { return }
            store.saveMarker(nil)
        }
    }

    /// VC `deinit` — 퇴장 콜백을 못 받은 채 해제되면 내 표시에 `orphaned`를 붙인다(C3)
    public func deinitialized() {
        lock.withLock {
            guard isActive, var marker = store.loadMarker(), marker.ownerToken == ownerToken else { return }
            marker.orphaned = true
            store.saveMarker(marker)
        }
    }

    // MARK: 전환·메모리 (키 입력마다 부르지 않는다)

    /// 자판·패널 관찰 — 바뀐 경우에만 전환을 남긴다
    public func observe(mode: ExitTraceMode, panel: ExitTracePanel) {
        let unchanged = lock.withLock { lastObserved.map { $0.mode == mode && $0.panel == panel } ?? false }
        guard !unchanged else { return }
        updateMarker { marker in
            lastObserved = (mode, panel)
            let before = marker.transitions
            apply(mode: mode, panel: panel, to: &marker)
            if marker.transitions != before { sampleMemory(into: &marker) }
        }
    }

    /// 높이 적용 — 높이가 **실제로 바뀐** 호출만 `heightApplied`로 남긴다(M2). 폭 버킷도 함께 갱신한다
    public func heightApplied(_ height: Double, width: Double, screenWidth: Double) {
        let buckets = (width: ExitTraceBuckets.width(width), screen: ExitTraceBuckets.width(screenWidth))
        let unchanged = lock.withLock {
            lastHeight == height && lastWidthBuckets.map { $0 == buckets } == true
        }
        guard !unchanged else { return }
        updateMarker { marker in
            let changed = lastHeight.map { $0 != height } ?? false
            lastHeight = height
            lastWidthBuckets = buckets
            marker.widthBucket = buckets.width
            marker.screenWidthBucket = buckets.screen
            if changed {
                push(.heightApplied, to: &marker)
                sampleMemory(into: &marker)
            }
        }
    }

    public func settingsReloaded() {
        updateMarker { marker in
            push(.settingsReload, to: &marker)
            sampleMemory(into: &marker)
        }
    }

    /// `didReceiveMemoryWarning` — 그 순간 표본(C1)
    public func memoryWarning() {
        updateMarker { marker in
            push(.memoryWarning, to: &marker)
            raise(.warning, in: &marker)
            sampleMemory(into: &marker)
        }
    }

    /// 메모리 압박 `DispatchSource` 이벤트 — 그 순간 표본, 단계는 내려가지 않는다(C1)
    public func memoryPressure(_ level: ExitTracePressureLevel) {
        updateMarker { marker in
            push(.memoryPressure, to: &marker)
            raise(level, in: &marker)
            sampleMemory(into: &marker)
        }
    }

    // MARK: 내부 (락 안에서만 부른다)

    private var isActive: Bool { enabled && !optedOut }

    private func updateMarker(_ change: (inout ExitTraceMarker) -> Void) {
        lock.withLock {
            guard isActive, var marker = store.loadMarker(), marker.ownerToken == ownerToken else { return }
            let before = marker
            change(&marker)
            if marker != before { store.saveMarker(marker) }
        }
    }

    private func freshMarker(nowHour: Int) -> ExitTraceMarker {
        ExitTraceMarker(pid: environment.pid, ownerToken: ownerToken, setAtHour: nowHour,
                        buildNumber: environment.buildNumber, os: environment.os, idiom: idiom)
    }

    /// 판정표 2-5 — 위에서부터 첫 일치
    private func judge(_ old: ExitTraceMarker, nowHour: Int) -> ExitTraceJudgement {
        var counters = store.loadCounters()
        defer { store.saveCounters(counters) }
        if old.buildNumber != environment.buildNumber || old.os != environment.os {
            counters.update += 1
            return .update
        }
        if old.setAtHour > nowHour || nowHour - old.setAtHour > Self.staleAfterHours {
            counters.stale += 1
            return .stale
        }
        let cls: ExitTraceClass = (old.pid == environment.pid || old.orphaned) ? .orphan : .abnormal
        if cls == .orphan { counters.orphan += 1 } else { counters.abnormal += 1 }
        counters = counters.adding(store.appendPending(record(from: old, cls: cls, nowHour: nowHour), nowHour: nowHour))
        return .recorded(cls)
    }

    private func record(from old: ExitTraceMarker, cls: ExitTraceClass, nowHour: Int) -> ExitTraceRecord {
        ExitTraceRecord(cls: cls, mode: old.mode, panel: old.panel,
                        transitions: Array(old.transitions.suffix(ExitTraceRetention.transitionLimit)), idiom: old.idiom,
                        widthBucket: old.widthBucket, screenWidthBucket: old.screenWidthBucket,
                        memoryBucket: old.memoryBucket, memoryMinBucket: old.memoryMinBucket, pressure: old.pressure,
                        residueHours: ExitTraceBuckets.residueHours(setAtHour: old.setAtHour, nowHour: nowHour),
                        // 사건 세션의 전체 접근 — 등장 전에 죽어 모르면(unknown) 꺼진 것으로 본다
                        fullAccessAtCreation: old.fullAccess == .on,
                        buildNumber: old.buildNumber, osCode: old.os.code, createdAtHour: nowHour)
    }

    /// 대기 기록 → 발신함, 통계는 하루 한 번 또는 기록을 옮길 때(2-8). 옮긴 카운터는 0으로 되돌린다(M4)
    private func relay(nowHour: Int) {
        let pending = store.loadPending()
        let counters = store.loadCounters()
        let today = ExitTraceBuckets.day(ofHour: nowHour)
        let movesStats = counters.appearances >= 1 && (store.loadLastStatsDay() != today || !pending.isEmpty)
        let items = pending.map(ExitTraceOutboxItem.record) + (movesStats ? [.stats(counters)] : [])
        let dropped = outbox.append(items, nowHour: nowHour)
        if !pending.isEmpty { store.savePending([]) }
        if movesStats {
            store.saveCounters(ExitTraceCounters().adding(dropped))
            store.saveLastStatsDay(today)
        } else if dropped != ExitTraceDropCount() {
            store.saveCounters(counters.adding(dropped))
        }
    }

    private func apply(mode: ExitTraceMode, panel: ExitTracePanel, to marker: inout ExitTraceMarker) {
        if mode != .unknown, mode != marker.mode {
            if marker.mode != .unknown { push(mode.enteringTransition, to: &marker) }
            marker.mode = mode
        }
        if panel != marker.panel {
            if panel != .none { push(.panelOpen, to: &marker) }
            marker.panel = panel
        }
    }

    private func push(_ transition: ExitTraceTransition, to marker: inout ExitTraceMarker) {
        marker.transitions = Array((marker.transitions + [transition]).suffix(ExitTraceRetention.transitionLimit))
    }

    private func raise(_ level: ExitTracePressureLevel, in marker: inout ExitTraceMarker) {
        marker.pressure = max(marker.pressure, level)
    }

    private func sampleMemory(into marker: inout ExitTraceMarker) {
        let bucket = ExitTraceBuckets.memory(bytes: availableMemory())
        guard bucket != ExitTraceBuckets.unknown else { return }
        marker.memoryBucket = bucket
        marker.memoryMinBucket = marker.memoryMinBucket == ExitTraceBuckets.unknown ? bucket : min(marker.memoryMinBucket, bucket)
    }
}

// MARK: - 조립 지점용 매핑 (UIKit·뷰 상태 → 기록 열거)

extension ExitTraceMode {
    public init(inputMode: InputMode, hangulLayout: HangulLayout) {
        switch inputMode {
        case .hangul:
            switch hangulLayout {
            case .dubeolsik: self = .dubeolsik
            case .cheonjiin: self = .cheonjiin
            case .danmoeum: self = .danmoeum
            }
        case .english: self = .english
        case .symbols, .symbolsAlternate: self = .symbols
        case .numberPad: self = .numberPad
        case .keypadPad(let page): self = page == 0 ? .keypadNumber : .keypadSymbols
        }
    }

    /// 이 자판으로 들어올 때 남기는 전환
    var enteringTransition: ExitTraceTransition {
        switch self {
        case .english: .toEnglish
        case .dubeolsik, .cheonjiin, .danmoeum: .toHangul
        case .symbols, .keypadSymbols: .toSymbols
        case .numberPad, .keypadNumber: .toNumberPad
        case .unknown: .none
        }
    }
}

extension ExitTracePanel {
    /// 성경 검색·채움글 후보처럼 자판 자리를 덮는 그 밖의 패널은 `other` 하나로 묶는다(K2-05)
    public init(emoji: Bool, clipboard: Bool, other: Bool) {
        self = other ? .other : clipboard ? .clipboard : emoji ? .emoji : .none
    }
}
