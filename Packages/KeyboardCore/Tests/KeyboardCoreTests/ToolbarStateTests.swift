import Testing
import TadakDomain
@testable import KeyboardCore

@Suite("툴바 상태 전환")
struct ToolbarStateTests {

    @Test("조합이 시작되면 추천 모드로 바뀐다")
    func autoSwitchToSuggestions() {
        var state = ToolbarState()
        #expect(state.mode == .tools)
        state.textDidChange(isComposing: true)
        #expect(state.mode == .suggestions)
    }

    @Test("조합이 끝나면 도구 모드로 돌아온다")
    func autoSwitchBackToTools() {
        var state = ToolbarState()
        state.textDidChange(isComposing: true)
        state.textDidChange(isComposing: false)
        #expect(state.mode == .tools)
    }

    @Test("사용자가 전환하면 자동 전환이 덮어쓰지 않는다")
    func userPinBlocksAutoSwitch() {
        var state = ToolbarState()
        state.toggleByUser()               // 사용자가 추천 모드로
        #expect(state.mode == .suggestions)

        state.textDidChange(isComposing: false)  // 자동으로는 도구 모드가 되어야 할 상황
        #expect(state.mode == .suggestions)      // 그러나 사용자 선택이 이긴다
    }

    @Test("입력 중에도 사용자가 도구를 열 수 있다")
    func userCanOpenToolsWhileComposing() {
        var state = ToolbarState()
        state.textDidChange(isComposing: true)
        #expect(state.mode == .suggestions)

        state.toggleByUser()
        #expect(state.mode == .tools)

        state.textDidChange(isComposing: true)   // 계속 입력해도
        #expect(state.mode == .tools)            // 도구가 닫히지 않는다
    }

    @Test("세션이 끝나면 고정이 풀리고 기본 모드로 돌아간다")
    func endSessionResetsPin() {
        var state = ToolbarState(defaultMode: .tools)
        state.toggleByUser()
        #expect(state.isPinnedByUser)

        state.endSession()
        #expect(state.mode == .tools)
        #expect(state.isPinnedByUser == false)

        state.textDidChange(isComposing: true)   // 자동 전환이 다시 살아난다
        #expect(state.mode == .suggestions)
    }

    @Test("기본 모드를 추천으로 두면 세션 시작이 추천 모드다")
    func customDefaultMode() {
        let state = ToolbarState(defaultMode: .suggestions)
        #expect(state.mode == .suggestions)
    }
}
