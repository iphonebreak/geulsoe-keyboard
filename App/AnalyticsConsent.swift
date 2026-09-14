import Foundation
import FirebaseAnalytics
import FirebaseCrashlytics

/// 이용 분석(Analytics)·오류 진단(Crashlytics) 수집 동의 상태.
///
/// **왜 있나 — App Store 심사 가이드라인 5.1.1(ii).** "앱이 수집하는 데이터에 대해 사용자가 동의를
/// 철회할 수 있는 **접근 가능하고 이해하기 쉬운** 수단을 제공해야 한다." v1.0.0에는 이 수단이 없었고
/// 처리방침 3장이 스스로 "현재 버전에는 앱 내 끄기 스위치가 없습니다"라고 적어 두는 상태였다.
/// v1.0.1에서 그 문장을 지우고 실제 스위치를 넣는다 (사용자 결정 2026-09-14).
///
/// **기본값은 켬이다** (사용자 결정). `Info.plist`에 `FIREBASE_ANALYTICS_COLLECTION_ENABLED`·
/// `FirebaseCrashlyticsCollectionEnabled` 게이트를 넣지 않는 이유가 이것이다 — 두 키는 **초기 상태를
/// 끔으로 만드는** 키라서, 넣는 순간 기본값 결정이 뒤집힌다. 넣지 않는 것이 결정 사항이다.
///
/// **왜 App Group이 아니라 앱 전용 `UserDefaults`인가.** 키보드 익스텐션에는 Firebase가 아예 없고
/// (심볼 0건, `docs/release/firebase-on-hardening.md`) 이 값을 읽을 이유가 없다. `KeyboardSettings`에
/// 넣으면 (1) 익스텐션이 알 필요 없는 필드를 디코드하게 되고 (2) 토글을 만질 때마다 Darwin 알림이
/// 떠 있는 키보드를 무의미하게 재로드시킨다. `RootView`의 `hasSeenOnboarding`과 같은 판단이다 —
/// **키보드가 읽을 일이 없는 값은 App Group에 두지 않는다.**
///
/// **Analytics와 Crashlytics를 따로 끈다.** 성격이 다르고(사용 통계 ↔ 크래시 진단), 프라이버시
/// 매니페스트·ASC 설문에서도 목적이 갈린다(Analytics ↔ App Functionality). 하나로 묶으면 "크래시는
/// 고쳐 달라, 사용 통계는 싫다"는 선택을 표현할 방법이 없어진다. 판단 근거: `docs/release/analytics-optout.md`
///
/// **적용 시점이 둘이 다르다 (공식 문서 확인 2026-09-14).**
/// - Analytics: `setAnalyticsCollectionEnabled`의 값은 "persists across app executions"이고
///   끄면 "collection is suspended until you re-enable it" — **즉시** 멈춘다.
/// - Crashlytics: 끄기는 "will apply the next time the user launches the app" — **다음 실행부터**다.
///   꺼 둔 동안의 크래시는 기기에 로컬 저장되는데, **우리는 그것을 다음 실행에서 지운다**
///   (`deleteUnsentReports`, 아래 참조). 그래서 "다시 켜면 그때 전송된다"는 SDK 기본 동작은
///   이 앱에서는 일어나지 않는다. UI 안내 문구와 처리방침이 이 사실과 어긋나지 않아야 한다.
enum AnalyticsConsent {

    /// 앱 전용 `UserDefaults` 키. App Group suite가 아니라 `.standard`다 (위 주석 참조).
    enum Key {
        static let analytics = "analyticsCollectionEnabled"
        static let crashlytics = "crashlyticsCollectionEnabled"
    }

    /// 키가 없을 때의 값 = 기본 켬.
    static let defaultValue = true

    static var analyticsEnabled: Bool { stored(Key.analytics) }
    static var crashlyticsEnabled: Bool { stored(Key.crashlytics) }

    /// 저장된 선택을 Firebase에 반영한다. `FirebaseApp.configure()` **이후에** 부른다.
    ///
    /// Firebase SDK 자체도 두 값을 영구 저장하므로 매 실행 재적용은 원칙적으로 중복이다.
    /// 그래도 부르는 이유: 우리 `UserDefaults` 값이 **단일 진실 원천**이 되어 UI 스위치 위치와
    /// 실제 수집 상태가 갈라질 여지를 없앤다.
    static func applyStoredChoices() {
        Analytics.setAnalyticsCollectionEnabled(analyticsEnabled)

        let crashlytics = Crashlytics.crashlytics()
        crashlytics.setCrashlyticsCollectionEnabled(crashlyticsEnabled)

        // 끈 상태면 기기에 남아 있는 미전송 크래시 보고를 지운다.
        //
        // **왜 필요한가** — `setCrashlyticsCollectionEnabled(false)`만 부르면 철회 이후의 크래시가
        // 디스크에 계속 쌓이고, 사용자가 나중에 다시 켜는 순간 **철회 기간에 모인 것까지 전부 올라간다.**
        // 처리방침에 적어 두면 거짓말은 아니지만 철회의 질이 낮다. 지우는 쪽이 맞다.
        //
        // **왜 여기(= 매 실행 적용 지점)인가 — SDK 소스를 직접 읽고 정한 위치다** (firebase-ios-sdk 12.19.1).
        // `FIRCrashlytics.h`: *"Deletes any unsent reports on the device. **This method only applies
        // if automatic data collection is disabled.**"* 그리고 `setCrashlyticsCollectionEnabled`는
        // *"The value does not apply until the next run of the app."*
        // `FIRCLSReportManager.m`의 기동 경로를 보면 이유가 분명하다 — SDK는 **기동 시 한 번**
        // `isCrashlyticsCollectionEnabled`로 분기하고, 켜져 있던 분기에서는
        // *"the SDK will not notify the user when unsent reports are available, or respect
        // Send / DeleteUnsentReports"* 라고 주석까지 달아 두고 액션을 기다리지 않는다.
        // 즉 **사용자가 스위치를 끄는 그 실행에서 부르는 삭제는 무시된다**(이번 실행은 켜진 채 기동했으므로).
        // 실제로 지워지는 시점은 **꺼진 채 기동한 다음 실행**이고, 그 지점이 바로 여기다.
        // 그래서 호출을 UI 쪽이 아니라 이 함수에 둔다 — 스위치를 끌 때도, 앱을 다시 켤 때도 같은
        // 경로를 지나므로 한 곳으로 충분하다.
        //
        // **실패 처리는 없다** — 공개 API가 `-> Void`이고 completion도 에러도 주지 않는다.
        // 내부적으로 삭제를 operation queue에 넣는 fire-and-forget이다(`FIRCLSExistingReportManager`).
        if !crashlyticsEnabled {
            crashlytics.deleteUnsentReports()
        }
    }

    private static func stored(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
