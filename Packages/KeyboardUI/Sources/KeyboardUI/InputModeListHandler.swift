#if os(iOS)
import UIKit
#endif
import KeyboardCore

/// 시스템 **키보드 목록**(지구본 길게 누르기와 같은 팝업)으로 가는 통로 — 조립 지점(키보드 VC)이 만들어 넘긴다.
///
/// 한영 키에 지구본을 합친 배열(`LayoutDefinition.mergingGlobeIntoLanguageKey`, 홈 버튼 아이폰·아이패드)에서 한영 키의 터치를
/// **첫 이벤트부터 끝까지** `UIInputViewController.handleInputModeList(from:with:)`에 넘긴다. 짧은 탭인지 길게 누르기인지는
/// **시스템이** 정한다(길게 = 목록, 짧게 = `advanceToNextInputMode` — VC가 이 키에서 온 호출만 한영 전환으로 바꾼다).
/// 늦게(길게 누른 뒤에) 넘기면 시스템이 목록을 열지 않는다(PDR `language-globe-key.md` — 공개 구현 조사).
///
/// KeyboardUI는 `UIInputViewController`를 모르므로(의존성 규칙) 일은 클로저로 받는다. macOS(시험)에는 만들 수 없다 — 늘 nil이다
public struct InputModeListHandler {
    #if os(iOS)
    /// 한영 키 터치의 시작·움직임·끝·취소를 그대로 넘긴다 — `from:`은 그 터치가 속한 뷰
    let forward: @MainActor (UIView, UIEvent) -> Void
    /// VoiceOver 로터 「다음 키보드」 — 길게 누르기를 못 쓰는 사용자가 다른 키보드로 가는 길(`advanceToNextInputMode`)
    let advance: @MainActor () -> Void

    public init(forward: @escaping @MainActor (UIView, UIEvent) -> Void, advance: @escaping @MainActor () -> Void) {
        self.forward = forward
        self.advance = advance
    }
    #endif

    /// VoiceOver 로터 동작 — macOS에서는 아무 일 없다
    @MainActor func advanceToNextKeyboard() {
        #if os(iOS)
        advance()
        #endif
    }
}

/// 키캡이 터치를 시스템 키보드 목록으로 넘기는지 — 판정 한 곳(`InputModeListRuleTests`)
enum InputModeListRule {

    /// 넘기나 — 목록을 여는 키(`opensInputModeList`) ∧ 통로가 있을 때(iOS 조립 지점)
    static func routes(_ key: LayoutDefinition.Key, handlerAvailable: Bool) -> Bool {
        key.opensInputModeList && handlerAvailable
    }

    /// 손 뗌에 키 자신의 이벤트를 내나 — **넘기는 키는 내지 않는다.** 짧은 탭의 한영 전환은 시스템 판정 뒤 VC가 낸다(이중 전환 방지)
    static func emitsReleaseEvent(_ key: LayoutDefinition.Key, handlerAvailable: Bool) -> Bool {
        !routes(key, handlerAvailable: handlerAvailable)
    }
}
