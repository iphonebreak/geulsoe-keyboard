import Foundation

// 백로그 14 (가) 키보드 비정상 종료 흔적 — 기록 타입(PDR `docs/design-reviews/keyboard-crashlytics.md` 2-7, 보안 규칙 N21).
//
// ★ 모든 필드는 열거형·정수·불리언이다. **`String` 저장 프로퍼티를 두지 않는다** — 자유 문자열 칸이 생기면
//   언젠가 입력·문맥이 들어간다. 입력란 종류(`keyboardType`·`isSecureTextEntry`)·문서 식별자·호스트 앱도 담지 않는다.
//   `ExitTracePrivacyTests`가 리플렉션·인코딩 키로 고정한다. 필드를 더하려면 PDR 개정과 시험 수정이 먼저다.

/// 자판 종류 — 글자가 아니라 어느 자판이었는지만
public enum ExitTraceMode: String, Codable, Sendable, CaseIterable {
    case unknown, dubeolsik, cheonjiin, danmoeum, english, symbols, numberPad, keypadNumber, keypadSymbols
}

/// 열린 패널 — 성경 검색·채움글 후보 등은 `other` 하나로 묶는다(특정 기능 이용을 드러내지 않게, K2-05)
public enum ExitTracePanel: String, Codable, Sendable, CaseIterable {
    case none, emoji, clipboard, other
}

/// 최근 전환(2-3) — 시각 없이 순서만
public enum ExitTraceTransition: String, Codable, Sendable, CaseIterable {
    case none, appear, toEnglish, toHangul, toSymbols, toNumberPad, panelOpen, heightApplied, settingsReload,
         memoryWarning, memoryPressure
}

public enum ExitTraceIdiom: String, Codable, Sendable, CaseIterable {
    case phone, pad
}

/// 전체 접근 — `viewWillAppear` 전에는 모른다(`unknown`)
public enum ExitTraceFullAccessState: String, Codable, Sendable, CaseIterable {
    case unknown, off, on
}

/// 기록이 되는 분류(2-5) — `update`·`stale`은 카운터로만 센다
public enum ExitTraceClass: String, Codable, Sendable, CaseIterable {
    case abnormal, orphan
}

/// 메모리 압박 — 표시 수명 동안 본 최고 단계
public enum ExitTracePressureLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case none = 0, warning = 1, critical = 2

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

public struct ExitTraceOSVersion: Codable, Equatable, Sendable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// `major×10000 + minor×100 + patch` — 이벤트 `osv`
    public var code: Int { major * 10_000 + minor * 100 + patch }
}

/// 「열린 표시」 — 키보드 자기 컨테이너에만 있고 **전송하지 않는다**. 다음 로드가 이것으로 판정한다
public struct ExitTraceMarker: Codable, Equatable, Sendable {
    public var pid: Int32
    /// 프로세스 안 증가값 — 어느 VC의 표시인지(겹침 방어)
    public var ownerToken: UInt32
    /// 쓴 시각(시 단위로 내림, 1970 기준 시)
    public var setAtHour: Int
    public var buildNumber: Int
    public var os: ExitTraceOSVersion
    public var idiom: ExitTraceIdiom
    /// 퇴장 콜백 없이 VC가 해제됐다(C3)
    public var orphaned: Bool
    public var fullAccess: ExitTraceFullAccessState
    public var mode: ExitTraceMode
    public var panel: ExitTracePanel
    /// 최근 전환 — 오래된 것부터, 최대 `ExitTraceRetention.transitionLimit`개
    public var transitions: [ExitTraceTransition]
    public var widthBucket: Int
    public var screenWidthBucket: Int
    /// 마지막 표본(5MB 단위, MB). 표본이 없으면 `ExitTraceBuckets.unknown`
    public var memoryBucket: Int
    public var memoryMinBucket: Int
    public var pressure: ExitTracePressureLevel

    public init(pid: Int32, ownerToken: UInt32, setAtHour: Int, buildNumber: Int, os: ExitTraceOSVersion, idiom: ExitTraceIdiom,
                orphaned: Bool = false, fullAccess: ExitTraceFullAccessState = .unknown, mode: ExitTraceMode = .unknown,
                panel: ExitTracePanel = .none, transitions: [ExitTraceTransition] = [], widthBucket: Int = 0,
                screenWidthBucket: Int = 0, memoryBucket: Int = ExitTraceBuckets.unknown,
                memoryMinBucket: Int = ExitTraceBuckets.unknown, pressure: ExitTracePressureLevel = .none) {
        self.pid = pid
        self.ownerToken = ownerToken
        self.setAtHour = setAtHour
        self.buildNumber = buildNumber
        self.os = os
        self.idiom = idiom
        self.orphaned = orphaned
        self.fullAccess = fullAccess
        self.mode = mode
        self.panel = panel
        self.transitions = transitions
        self.widthBucket = widthBucket
        self.screenWidthBucket = screenWidthBucket
        self.memoryBucket = memoryBucket
        self.memoryMinBucket = memoryMinBucket
        self.pressure = pressure
    }
}

/// 종료 의심 기록 — 이벤트 `kb_exit_suspect` 한 건. pid·소유 토큰은 싣지 않는다
public struct ExitTraceRecord: Codable, Equatable, Sendable {
    public var cls: ExitTraceClass
    public var mode: ExitTraceMode
    public var panel: ExitTracePanel
    public var transitions: [ExitTraceTransition]
    public var idiom: ExitTraceIdiom
    public var widthBucket: Int
    public var screenWidthBucket: Int
    public var memoryBucket: Int
    public var memoryMinBucket: Int
    public var pressure: ExitTracePressureLevel
    /// 표시를 쓴 뒤 발견까지(시, 48 상한)
    public var residueHours: Int
    /// 사건 세션의 전체 접근 — 꺼진 동안 쌓였다가 소급 전송되는 기록을 가른다(`fa_rec`, K2-02)
    public var fullAccessAtCreation: Bool
    /// 사건 당시 빌드·OS(전송 시점 값과 다를 수 있다)
    public var buildNumber: Int
    public var osCode: Int
    /// 만든 시각(시) — 30일 만료의 기준(옮긴 날이 아니다, K2-09)
    public var createdAtHour: Int

    public init(cls: ExitTraceClass, mode: ExitTraceMode, panel: ExitTracePanel, transitions: [ExitTraceTransition],
                idiom: ExitTraceIdiom, widthBucket: Int, screenWidthBucket: Int, memoryBucket: Int, memoryMinBucket: Int,
                pressure: ExitTracePressureLevel, residueHours: Int, fullAccessAtCreation: Bool, buildNumber: Int,
                osCode: Int, createdAtHour: Int) {
        self.cls = cls
        self.mode = mode
        self.panel = panel
        self.transitions = transitions
        self.idiom = idiom
        self.widthBucket = widthBucket
        self.screenWidthBucket = screenWidthBucket
        self.memoryBucket = memoryBucket
        self.memoryMinBucket = memoryMinBucket
        self.pressure = pressure
        self.residueHours = residueHours
        self.fullAccessAtCreation = fullAccessAtCreation
        self.buildNumber = buildNumber
        self.osCode = osCode
        self.createdAtHour = createdAtHour
    }
}

/// 통계 — 이벤트 `kb_exit_stats`. `appearances`가 분모다
public struct ExitTraceCounters: Codable, Equatable, Sendable {
    public var appearances: Int
    public var abnormal: Int
    public var orphan: Int
    public var update: Int
    public var stale: Int
    /// 상한(대기 20·발신함 50)을 넘쳐서 버린 수(`dropped_n`)
    public var dropped: Int
    /// 생성 후 30일이 지나 버린 수(`expired_n`) — 넘침과 섞지 않는다(검증 F3)
    public var expired: Int

    public init(appearances: Int = 0, abnormal: Int = 0, orphan: Int = 0, update: Int = 0, stale: Int = 0, dropped: Int = 0,
                expired: Int = 0) {
        self.appearances = appearances
        self.abnormal = abnormal
        self.orphan = orphan
        self.update = update
        self.stale = stale
        self.dropped = dropped
        self.expired = expired
    }

    /// 칸이 없는 저장분(만료 칸 이전)도 0으로 읽는다
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) throws -> Int { try container.decodeIfPresent(Int.self, forKey: key) ?? 0 }
        self.init(appearances: try count(.appearances), abnormal: try count(.abnormal), orphan: try count(.orphan),
                  update: try count(.update), stale: try count(.stale), dropped: try count(.dropped),
                  expired: try count(.expired))
    }

    /// 버린 수를 더한 복사본
    public func adding(_ drops: ExitTraceDropCount) -> ExitTraceCounters {
        var copy = self
        copy.dropped += drops.overflow
        copy.expired += drops.expired
        return copy
    }
}

/// 정리하며 버린 수 — 넘침과 만료를 따로 센다
public struct ExitTraceDropCount: Equatable, Sendable {
    public var overflow: Int
    public var expired: Int

    public init(overflow: Int = 0, expired: Int = 0) {
        self.overflow = overflow
        self.expired = expired
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(overflow: lhs.overflow + rhs.overflow, expired: lhs.expired + rhs.expired)
    }
}

/// 발신함 한 칸 — 기록 또는 통계 하나
public struct ExitTraceOutboxEntry: Codable, Equatable, Sendable {
    public var seq: Int
    public var createdAtHour: Int
    public var record: ExitTraceRecord?
    public var stats: ExitTraceCounters?

    public init(seq: Int, createdAtHour: Int, record: ExitTraceRecord?, stats: ExitTraceCounters?) {
        self.seq = seq
        self.createdAtHour = createdAtHour
        self.record = record
        self.stats = stats
    }
}

/// 발신함에 넣을 것
public enum ExitTraceOutboxItem: Equatable, Sendable {
    case record(ExitTraceRecord)
    case stats(ExitTraceCounters)
}

/// 버킷 — 원자료를 거칠게 내려 담는다
public enum ExitTraceBuckets {
    /// 메모리 표본이 없음
    public static let unknown = -1
    public static let memoryStepMegabytes = 5
    public static let widthStepPoints = 20
    public static let residueCapHours = 48

    /// 남은 메모리(바이트) → MB를 5 단위로 내림
    public static func memory(bytes: UInt64?) -> Int {
        guard let bytes else { return unknown }
        let megabytes = Int(bytes / 1_048_576)
        return megabytes / memoryStepMegabytes * memoryStepMegabytes
    }

    /// 폭(pt) → 20 단위로 내림. 음수·NaN은 0
    public static func width(_ points: Double) -> Int {
        guard points.isFinite, points > 0 else { return 0 }
        return Int(points) / widthStepPoints * widthStepPoints
    }

    /// 경과 시간 — 시계가 뒤로 가면 0, 48 상한
    public static func residueHours(setAtHour: Int, nowHour: Int) -> Int {
        min(residueCapHours, max(0, nowHour - setAtHour))
    }

    /// 1970 기준 시(내림)
    public static func hour(of date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 3600).rounded(.down))
    }

    /// 1970 기준 일(내림, UTC) — 통계 「하루 한 번」의 날짜
    public static func day(ofHour hour: Int) -> Int {
        Int((Double(hour) / 24).rounded(.down))
    }
}

/// 보관 규칙 — 대기 20건·발신함 50건·생성 후 30일(2-6·2-8·6-9)
public enum ExitTraceRetention {
    public static let pendingLimit = 20
    public static let outboxLimit = 50
    public static let maxAgeHours = 30 * 24
    public static let transitionLimit = 4

    public static func isExpired(createdAtHour: Int, nowHour: Int) -> Bool {
        nowHour - createdAtHour > maxAgeHours
    }

    /// 만료분을 빼고 상한을 넘으면 앞(오래된 것)부터 버린다 — 버린 수를 만료·넘침으로 나눠 돌려준다
    public static func retained<Item>(_ items: [Item], nowHour: Int, limit: Int,
                                      createdAtHour: (Item) -> Int) -> (kept: [Item], dropped: ExitTraceDropCount) {
        let fresh = items.filter { !isExpired(createdAtHour: createdAtHour($0), nowHour: nowHour) }
        let kept = Array(fresh.suffix(limit))
        return (kept, ExitTraceDropCount(overflow: fresh.count - kept.count, expired: items.count - fresh.count))
    }
}
