#if os(iOS)
import UIKit
#endif
import Foundation
import KeyboardCore

/// 시스템 **키보드 목록**(지구본 길게 누르기와 같은 팝업)으로 가는 통로 — 조립 지점(키보드 VC)이 만들어 넘긴다.
///
/// 한영 키에 지구본을 합친 배열(`LayoutDefinition.mergingGlobeIntoLanguageKey`, `needsInputModeSwitchKey == true` 기기)에서
/// 한영 키의 터치를 **첫 이벤트부터 끝까지** `UIInputViewController.handleInputModeList(from:with:)`에 넘긴다. 짧은 탭인지
/// 길게 누르기인지는 **시스템이** 정한다(길게 = 목록, 짧게 = `advanceToNextInputMode` — VC가 이 키에서 온 호출만 한영 전환으로 바꾼다).
/// 늦게(길게 누른 뒤에) 넘기면 시스템이 목록을 열지 않는다(PDR `language-globe-key.md` — 공개 구현 조사).
///
/// 넘길지는 **누름마다 닿을 때 한 번** 정한다(`claimPress` → `InputModeListGate`) — 빠른 두 번 탭에서 첫 탭의 시스템 타이머가
/// 둘째 누름을 가로채지 않게(리뷰 HIGH). 그 판정 상태를 통로가 들고 있어, 한영 전환 뒤 키캡이 다시 그려져도 이어진다.
///
/// KeyboardUI는 `UIInputViewController`를 모르므로(의존성 규칙) 일은 클로저로 받는다. macOS(시험)에는 만들 수 없다 — 늘 nil이다
public struct InputModeListHandler {
    #if os(iOS)
    /// 한영 키 터치의 시작·움직임·끝·취소를 그대로 넘긴다 — `from:`은 그 터치가 속한 뷰
    let forward: @MainActor (UIView, UIEvent) -> Void
    /// VoiceOver 로터 「다음 키보드」 — 길게 누르기를 못 쓰는 사용자가 다른 키보드로 가는 길(`advanceToNextInputMode`)
    let advance: @MainActor () -> Void
    private let session = InputModeListSession()

    public init(forward: @escaping @MainActor (UIView, UIEvent) -> Void, advance: @escaping @MainActor () -> Void) {
        self.forward = forward
        self.advance = advance
    }

    /// 닿을 때 한 번 — 이 누름을 시스템에 넘길지. 거짓이면 그 누름은 평범한 한영 키다(손 뗌에 키캡이 한영을 낸다)
    @MainActor func claimPress() -> Bool {
        session.gate.claim(at: ProcessInfo.processInfo.systemUptime)
    }
    #endif

    /// VoiceOver 로터 동작 — macOS에서는 아무 일 없다
    @MainActor func advanceToNextKeyboard() {
        #if os(iOS)
        advance()
        #endif
    }
}

#if os(iOS)
/// 통로가 들고 다니는 판정 상태 — 메인 스레드(터치 처리)에서만 읽고 쓴다
private final class InputModeListSession {
    var gate = InputModeListGate()
}
#endif

/// 한 누름을 시스템 키보드 목록으로 넘길지 — **닿을 때 한 번** 정한다(`InputModeListGateTests`).
///
/// 시스템은 넘긴 누름마다 began에서 약 200ms 타이머를 걸고, 타이머가 돌 때 그 키가 「아직 판정 안 됨」이면 목록을 연다.
/// 빠른 두 번 탭에서 둘째 began이 판정 상태를 되돌리면 **첫 탭의 타이머가** 둘째 누름 도중 목록을 열고, 둘째 전환은 사라진다
/// (리뷰 HIGH 2026-11-11 — macOS Catalyst UIKitCore 디스어셈블 재구성). 그래서 직전에 넘긴 누름에서 `reentryWindow` 안에 닿은
/// 누름은 넘기지 않는다 — 첫 탭이 남긴 「판정함」이 그대로라 첫 타이머는 아무것도 하지 않는다
struct InputModeListGate {

    /// 시스템 타이머(약 200ms)에 메인 스레드 지연 여유를 더한 값. 이 안의 누름은 길게 눌러도 목록이 아니라 한영이다
    static let reentryWindow: TimeInterval = 0.3

    private var lastForwardedBegan: TimeInterval?

    /// `now`(단조 시계, 초)에 닿은 누름을 넘길지 — 넘기면 그 시각을 기억한다
    mutating func claim(at now: TimeInterval) -> Bool {
        if let last = lastForwardedBegan, now >= last, now - last < Self.reentryWindow { return false }
        lastForwardedBegan = now
        return true
    }
}

/// 키캡이 터치를 시스템 키보드 목록으로 넘기는 키인지 — 판정 한 곳(`InputModeListRuleTests`)
enum InputModeListRule {

    /// 넘기는 키인가 — 목록을 여는 키(`opensInputModeList`) ∧ 통로가 있을 때(iOS 조립 지점).
    /// 누름마다 실제로 넘길지는 `InputModeListGate`가 닿을 때 정한다
    static func routes(_ key: LayoutDefinition.Key, handlerAvailable: Bool) -> Bool {
        key.opensInputModeList && handlerAvailable
    }
}
