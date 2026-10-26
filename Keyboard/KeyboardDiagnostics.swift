import Foundation
import FirebaseCore
import FirebaseCrashlytics
import KeyboardCore

// 백로그 14 (나) 키보드 Crashlytics(스위치·기본 켜짐) — **키보드에서 `import Firebase*`가 있는 유일한 파일**(보안 규칙 N4′ ③).
// 여기서 부르는 SDK 기능은 `FirebaseApp.configure(options:)`·`setCrashlyticsCollectionEnabled` 둘뿐이다.
// 로그·사용자 키·사용자 ID·non-fatal 기록 API는 쓰지 않는다 — `.claude/hooks/telemetry-gate.sh` 검사 C가 이 파일의 SDK 토큰을
// 허용된 모양(아래 `perform`의 세 줄 + `FirebaseOptions` 읽기)만 남기고 막는다. SDK 인스턴스를 변수에 담지 않는다.
// 언제 무엇을 부르는지는 KeyboardCore `KeyboardCrashReportGate`가 정하고(`action.sdkCalls` — 순서까지 시험으로 고정), 이 파일은 옮길 뿐이다.
// PDR `docs/design-reviews/keyboard-crashlytics.md` 4-2·5-2·6-8, 구현 보고 `docs/release/impl-v132b-keyboard-crashlytics.md`.
//
// 설정 파일은 **설정 앱과 같은 `GoogleService-Info.plist`**다(사장님 결정 2026-10-26 — 키보드용 Firebase 앱을 따로 두지 않는다).
// `project.yml`이 같은 파일을 키보드 번들 리소스로도 넣는다. SDK는 익스텐션이 앱의 옵션을 쓰는 경우를 번들 ID 접두로 맞춰 보고,
// 안 맞아도 로그만 남긴다(FirebaseCore `FIRBundleUtil`·`checkExpectedBundleID`). 파일은 opt-in ∧ 전체 접근일 때만 읽고(검증 #5),
// 없거나 필수 값이 비어 있으면 **조용히 시작하지 않는다**(`configure`가 예외를 던지는 경로를 밟지 않는다).

@MainActor
enum KeyboardDiagnostics {

    /// 프로세스 전체에서 하나 — 호스트가 VC를 여러 번 만들어도 `configure`는 한 번이다(T7)
    private static var phase: KeyboardCrashReportPhase = .notStarted

    /// 번들의 설정 — 판정이 처음 물을 때 한 번 읽는다(`lazy` 정적). 없으면 nil
    private static let options: FirebaseOptions? = loadOptions()

    /// 등장(`viewWillAppear`)과 설정 즉시 반영 때 부른다. 전체 접근은 등장 이후 값이다(PDR 4-2 [미확인] — 보고서 3절)
    static func update(optedIn: Bool, hasFullAccess: Bool) {
        let conditions = KeyboardCrashReportConditions(optedIn: optedIn, hasFullAccess: hasFullAccess)
        // `hasConfiguration`은 자동 클로저 — opt-in ∧ 전체 접근인 시작 전에만 평가되어 그때 처음 plist를 읽는다
        let step = KeyboardCrashReportGate.step(from: phase, conditions, hasConfiguration: options != nil)
        let calls = step.action.sdkCalls
        if calls.contains(.configure), options == nil { return }   // 판정이 설정 파일을 요구하므로 오지 않는다 — 단계도 바꾸지 않는다
        for call in calls {
            perform(call)
        }
        phase = step.phase
    }

    /// 판정이 정한 순서 그대로. 시작은 `configure` → 켬. 이전 프로세스가 끈 채 남긴 보고서는 다시 켜면 전송될 수 있다 —
    /// 지우지 않고 처리방침에 밝힌다(R1 공개 고지, 2026-10-26. 삭제안은 SDK 안에서 켬과 경쟁해 져 철회 — 최종 검증 #1)
    private static func perform(_ call: KeyboardCrashReportSDKCall) {
        switch call {
        case .configure:
            guard let options else { return }
            FirebaseApp.configure(options: options)
        case .setCollectionEnabled(true):
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        case .setCollectionEnabled(false):
            Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(false)
        }
    }

    private static func loadOptions() -> FirebaseOptions? {
        guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") else { return nil }
        guard let options = FirebaseOptions(contentsOfFile: path) else { return nil }
        guard !options.googleAppID.isEmpty, !options.gcmSenderID.isEmpty else { return nil }
        return options
    }
}
