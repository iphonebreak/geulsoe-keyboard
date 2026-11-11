import Testing
import KeyboardCore
@testable import KeyboardUI

/// 한영 키에 지구본 합치기(1.4.0, PDR `language-globe-key.md`) — 키캡이 터치를 시스템 키보드 목록으로 넘기는지, 손 뗌에 자기 이벤트를 내는지.
///
/// 넘기는 키는 짧은 탭인지 길게 누르기인지를 **시스템이** 정한다(짧은 탭이면 `advanceToNextInputMode`를 부르고, VC가 그것을 한영 전환으로 바꾼다).
/// 그러니 키캡이 손 뗌에 `.toggleLanguage`를 또 내면 **한영이 두 번 바뀐다** — 여기서 막는다.
@Suite("키캡 — 한영 키의 키보드 목록 통로")
struct InputModeListRuleTests {

    private let mergedLanguage = LayoutDefinition.Key(id: "language", label: "ABC", event: .toggleLanguage,
                                                      width: 1.2, isFunctionKey: true, opensInputModeList: true)
    private let plainLanguage = LayoutDefinition.Key(id: "language", label: "ABC", event: .toggleLanguage,
                                                     width: 1.2, isFunctionKey: true)

    @Test("목록을 여는 키 ∧ 통로가 있으면 넘기고, 손 뗌에 자기 이벤트를 내지 않는다(이중 전환 방지)")
    func mergedKeyRoutesAndStaysSilentOnRelease() {
        #expect(InputModeListRule.routes(mergedLanguage, handlerAvailable: true))
        #expect(!InputModeListRule.emitsReleaseEvent(mergedLanguage, handlerAvailable: true))
    }

    @Test("통로가 없으면(macOS·조립 지점이 안 넘김) 평범한 한영 키다")
    func withoutHandlerItIsAPlainKey() {
        #expect(!InputModeListRule.routes(mergedLanguage, handlerAvailable: false))
        #expect(InputModeListRule.emitsReleaseEvent(mergedLanguage, handlerAvailable: false))
    }

    @Test("목록을 열지 않는 키는 통로가 있어도 넘기지 않는다")
    func otherKeysNeverRoute() {
        for key in [plainLanguage,
                    LayoutDefinition.Key(id: "space", label: " ", event: .space, width: 4.4),
                    LayoutDefinition.Key(id: "q", label: "q", event: .character("q"))] {
            #expect(!InputModeListRule.routes(key, handlerAvailable: true), "\(key.id)")
            #expect(InputModeListRule.emitsReleaseEvent(key, handlerAvailable: true), "\(key.id)")
        }
    }
}
