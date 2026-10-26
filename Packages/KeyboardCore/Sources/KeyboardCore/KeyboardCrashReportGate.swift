// 백로그 14 (나) 키보드 Crashlytics — **시작 판정만** 하는 순수 상태 전이(SDK를 모른다, 보안 규칙 N4′ ②·⑤).
// SDK 호출은 `Keyboard/KeyboardDiagnostics.swift` 한 파일이 이 판정의 `action.sdkCalls`대로만 한다.
// PDR `docs/design-reviews/keyboard-crashlytics.md` 4-2(FA 없으면 시작 안 함)·5-2(한 번만)·6-8 (나) 행 #7~#10.
//
// - 시작은 opt-in ∧ 전체 접근 ∧ 번들 설정 파일이 **모두** 참일 때, 프로세스에 **한 번**. 설정 파일은 앞의 둘이 참일 때만 읽는다(검증 #5).
//   시작 전에는 `configure`가 없으므로 Crashlytics의 크래시 처리기가 설치되지 않는다 — 꺼진 동안의 크래시는 기록·전송되지 않는다(소급 없음, #10).
//   ★ 단 「SDK 코드가 하나도 안 돈다」는 아니다(검증 #1): 링크된 전송 라이브러리 GoogleDataTransport의 `+load`가 모든 키보드 프로세스에서
//   빈 업로드 타이머(30초)를 켜고 `Library/Caches/google-sdks-events` 빈 디렉터리를 만든다. 저장된 이벤트가 없어 보낼 것은 없다.
// - 시작 = `configure` → `setCrashlyticsCollectionEnabled(true)`(N4′ ③). 이전 프로세스가 수집을 끈 채 남긴 보고서(켜서 시작한 뒤 끄고
//   같은 프로세스에서 난 크래시)는 다시 켜면 전송될 수 있다 — 처리방침에 그대로 밝힌다(R1 공개 고지, 사장님 결정 2026-10-26).
//   시작 때 남은 보고서를 SDK 삭제 호출로 지우는 안(R1 삭제안)은 같은 차례의 수집 켬과 SDK 안에서 경쟁해 지는 것으로 읽혀(최종 검증 #1) 철회했다.
// - 시작한 뒤 opt-in이나 전체 접근이 꺼지면 수집을 끈다(`setCrashlyticsCollectionEnabled(false)`). 공식 문서상 끄기는
//   **다음 실행부터** 확실히 적용된다(#8). 다시 켜지면 configure 없이 수집만 켠다.

/// 이 프로세스에서 SDK가 어디까지 왔나
public enum KeyboardCrashReportPhase: Sendable, Equatable {
    /// `configure`를 부르지 않았다 — 크래시 처리기 미설치
    case notStarted
    /// 시작했고 수집이 켜져 있다
    case collecting
    /// 시작했지만 opt-in·전체 접근이 꺼져 수집을 껐다
    case paused
}

/// 조립 지점이 부를 수 있는 SDK 호출 — N4′ ③의 허용 목록 그대로다(이 밖의 호출은 표현할 수 없다)
public enum KeyboardCrashReportSDKCall: Sendable, Equatable {
    /// `FirebaseApp.configure(options:)`
    case configure
    /// `Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(_:)`
    case setCollectionEnabled(Bool)
}

/// 판정 결과로 조립 지점이 할 일 — 하나뿐이다
public enum KeyboardCrashReportAction: Sendable, Equatable {
    case none
    case start
    case pauseCollection
    case resumeCollection

    /// 이 동작이 부를 SDK 호출, 부를 순서대로
    public var sdkCalls: [KeyboardCrashReportSDKCall] {
        switch self {
        case .none:
            return []
        case .start:
            return [.configure, .setCollectionEnabled(true)]
        case .pauseCollection:
            return [.setCollectionEnabled(false)]
        case .resumeCollection:
            return [.setCollectionEnabled(true)]
        }
    }
}

/// 판정 입력 — 둘 다 등장 때 조립 지점이 읽는다(전체 접근은 `viewWillAppear` 이후 값). 설정 파일은 `step`이 필요할 때만 묻는다
public struct KeyboardCrashReportConditions: Sendable, Equatable {
    public let optedIn: Bool
    public let hasFullAccess: Bool

    public init(optedIn: Bool, hasFullAccess: Bool) {
        self.optedIn = optedIn
        self.hasFullAccess = hasFullAccess
    }

    /// 수집해도 되는가
    var allowsCollection: Bool { optedIn && hasFullAccess }
}

public struct KeyboardCrashReportStep: Sendable, Equatable {
    public let phase: KeyboardCrashReportPhase
    public let action: KeyboardCrashReportAction

    public init(phase: KeyboardCrashReportPhase, action: KeyboardCrashReportAction) {
        self.phase = phase
        self.action = action
    }
}

public enum KeyboardCrashReportGate {

    /// 지금 단계와 조건에서 다음 단계와 할 일. 같은 조건을 거듭 넣으면 두 번째부터는 `.none`이다(VC가 여러 번 생겨도 한 번 — T7)
    /// - Parameter hasConfiguration: 번들 설정 파일이 쓸 만한가. **시작 전 ∧ opt-in ∧ 전체 접근일 때만 평가한다**(검증 #5 —
    ///   꺼진 프로세스는 `FirebaseOptions`도 만들지 않는다). 시작한 뒤에는 이미 읽었으므로 보지 않는다.
    public static func step(from phase: KeyboardCrashReportPhase,
                            _ conditions: KeyboardCrashReportConditions,
                            hasConfiguration: @autoclosure () -> Bool) -> KeyboardCrashReportStep {
        switch phase {
        case .notStarted:
            guard conditions.allowsCollection, hasConfiguration() else {
                return KeyboardCrashReportStep(phase: .notStarted, action: .none)
            }
            return KeyboardCrashReportStep(phase: .collecting, action: .start)
        case .collecting:
            return conditions.allowsCollection
                ? KeyboardCrashReportStep(phase: .collecting, action: .none)
                : KeyboardCrashReportStep(phase: .paused, action: .pauseCollection)
        case .paused:
            return conditions.allowsCollection
                ? KeyboardCrashReportStep(phase: .collecting, action: .resumeCollection)
                : KeyboardCrashReportStep(phase: .paused, action: .none)
        }
    }
}
