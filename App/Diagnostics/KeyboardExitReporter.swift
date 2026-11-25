import Foundation
import FirebaseAnalytics
import TadakDomain

/// 키보드 종료 흔적 전송 — **종료 흔적에서 Firebase를 만지는 유일한 파일**(보안 규칙 N21, PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8).
///
/// 하는 일은 하나다: 순수 계획(`ExitTraceDispatcher`)이 만든 이벤트를 `Analytics.logEvent`로 옮긴다.
/// 이벤트 이름·파라미터 키는 `ExitTraceDispatcher`의 상수(`kb_exit_suspect`·`kb_exit_stats`), 값은 열거 `rawValue`·정수뿐이다 —
/// **여기서 값을 만들거나 더하지 않는다.** 입력·문맥·클립보드·학습 단어·채움글은 기록 타입에 칸 자체가 없다(`recordHasNoStringFields`).
/// App Group 저장소를 참조하지 않는다(`telemetry-gate.sh` 검사 B) — 발신함 읽기·ack·지우기는 `ExitTraceAppInbox`.
/// `logEvent`는 게이트 ALLOWLIST에 이 파일 하나만 올라 있다.
/// **이 파일 안에서도 `Analytics.logEvent` 호출은 아래 한 곳뿐이어야 한다** — ALLOWLIST가 파일 단위라 두 번째 호출은 게이트가 못 잡고, 사람 검토로 막는다.
enum KeyboardExitReporter {

    /// 설정 앱이 활성화될 때(`RootView`) — 칸마다 `logEvent` 직후 그 칸을 ack한다(SDK가 로컬 큐에 받은 시점이 「보냄」, M4)
    static func report(analyticsEnabled: Bool, now: Date = Date()) {
        ExitTraceAppInbox().deliver(analyticsEnabled: analyticsEnabled, now: now) { event in
            Analytics.logEvent(event.name, parameters: event.parameters.mapValues(\.analyticsValue))
        }
    }
}

private extension ExitTraceEvent.Value {
    var analyticsValue: Any {
        switch self {
        case .text(let text): text
        case .number(let number): number
        }
    }
}
