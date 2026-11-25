import Foundation
import TadakDomain
import TadakData

/// 키보드 종료 흔적 발신함 — **앱 쪽**(읽기·ack 쓰기·처리한 칸 지우기). 백로그 14 (가), 보안 규칙 N21.
///
/// **Firebase를 import하지 않는다** — App Group 저장소를 만지는 파일이라 `telemetry-gate.sh` 검사 B가 Firebase 동거를 막는다.
/// 이벤트를 실제로 보내는 일은 `send`로 받은 리포터(`KeyboardExitReporter`, Firebase를 만지는 유일한 파일)만 한다.
///
/// 단일 작성자(PDR `docs/design-reviews/keyboard-crashlytics.md` 2-8·6-9 덧붙임): 앱이 **쓰는** 키는 `exitTrace.ack` 하나다.
/// 칸은 키보드만 만들고, 앱은 처리한 칸·30일 지난 칸의 키를 **지우기만** 한다(`ExitTraceOutboxRepository.removeHandled`) —
/// 전체 접근을 꺼서 키보드가 못 지우는 동안에도 기기 안 보관이 「만들어진 뒤 30일」을 넘지 않게.
struct ExitTraceAppInbox: ExitTraceAckWriting {

    private let outbox = ExitTraceOutboxRepository()

    func writeAck(_ seq: Int) {
        guard let defaults = UserDefaults(suiteName: AppGroupSettingsRepository.appGroupIdentifier) else { return }
        // 뒤로 가지 않는다 — 이미 처리한 칸을 다시 보내지 않게
        defaults.set(max(seq, outbox.ack()), forKey: ExitTraceOutboxRepository.ackKey)
    }

    /// 계획(활성화 1회당 최대 20칸) → 칸마다 보냄·ack → ack한 칸·30일 지난 칸 지움.
    /// 이용 분석을 끈 사용자면 계획에 이벤트가 없어 보내지 않고 ack·지우기만 한다(2-8 앱 쪽 방어)
    func deliver(analyticsEnabled: Bool, now: Date, send: (ExitTraceEvent) -> Void) {
        let plan = ExitTraceDispatcher.plan(entries: outbox.entries(), ack: outbox.ack(), today: now,
                                            analyticsEnabled: analyticsEnabled)
        ExitTraceDispatcher.deliver(plan, send: send, ack: self)
        outbox.removeHandled(nowHour: ExitTraceBuckets.hour(of: now))
    }
}
