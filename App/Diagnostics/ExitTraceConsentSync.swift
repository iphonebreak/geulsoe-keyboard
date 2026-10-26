import Foundation

/// 이용 분석 저장값을 키보드 종료 흔적 쪽에 건네는 **얇은 접근자** — 백로그 14 (가), PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8·8-2-1.
///
/// `RootView`는 App Group 저장소를 만지는 파일이라 Firebase를 import하는 `AnalyticsConsent`를 직접 부르지 않는다
/// (`telemetry-gate.sh` 검사 B의 취약점 회피). 이 파일에도 Firebase 심볼이 없다.
/// 기본값(켬)·저장 키는 `AnalyticsConsent`가 쥔다 — 여기서 바꾸지 않는다(N20: 이전 버전에서 끈 선택을 지키는 값이다).
enum ExitTraceConsentSync {
    static var analyticsEnabled: Bool { AnalyticsConsent.analyticsEnabled }
}
