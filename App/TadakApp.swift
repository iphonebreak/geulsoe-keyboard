import SwiftUI
import UIKit
import FirebaseCore

/// Firebase 초기화 전용 앱 델리게이트.
///
/// **여기는 컨테이너 앱이다. 키보드 익스텐션이 아니다.** Firebase는 `App/` 타깃에만 링크한다
/// (`project.yml`의 `Tadak` 타깃 dependencies). 익스텐션에 넣지 않는 이유는 두 가지다 —
/// 익스텐션은 60MB를 넘으면 경고 없이 강제 종료되고, 무엇보다 **사용자가 입력하는 모든 것을
/// 보는 자리**라 거기에 네트워크 SDK를 두는 것 자체가 신뢰 문제다.
///
/// **`.claude/rules/security.md` 1순위 규칙은 이 결정으로도 바뀌지 않는다** — 사용자가 입력한
/// 텍스트는 로그·파일·네트워크 어디로도 나가지 않는다. 이 파일은 **초기화만** 한다.
/// 이벤트 정의·로깅은 기획자 PDR이 끝난 뒤 별도 작업이며, 그때도 입력 텍스트는 대상이 아니다.
///
/// **수집 on/off는 `AnalyticsConsent`가 쥔다** (설정 > 정보 > 이용 분석·오류 진단).
/// 기본값은 켬이므로 `Info.plist`에 `FIREBASE_ANALYTICS_COLLECTION_ENABLED`·
/// `FirebaseCrashlyticsCollectionEnabled` 게이트를 넣지 않는다 — 넣으면 기본이 끔이 된다.
///
/// SwiftUI에 델리게이트가 필요한 이유: `FirebaseApp.configure()`는 앱 기동 시 한 번만 불려야 하고
/// UIKit 생명주기(`didFinishLaunchingWithOptions`)가 그 지점이다. SwiftUI에서 그 지점을 얻는
/// 공식 경로가 `@UIApplicationDelegateAdaptor`다 (Firebase 콘솔 표준 스니펫도 같은 방식).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        // 사용자가 끈 상태를 매 실행 재적용한다 — 심사 가이드라인 5.1.1(ii) 동의 철회 수단.
        // **반드시 configure() 뒤다** (두 API 모두 Firebase 초기화를 전제한다).
        // Firebase SDK 자체도 값을 영구 저장하지만, 우리 UserDefaults를 단일 진실 원천으로
        // 두어 UI 스위치와 실제 수집 상태가 갈라질 여지를 없앤다. 근거: AnalyticsConsent
        AnalyticsConsent.applyStoredChoices()
        return true
    }
}

@main
struct TadakApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
