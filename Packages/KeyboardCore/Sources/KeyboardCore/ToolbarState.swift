import TadakDomain

/// 툴바가 도구를 보여줄지 추천단어를 보여줄지 결정한다.
///
/// 조합이 시작되면 추천 모드로, 확정되거나 비면 도구 모드로 자동 전환한다.
/// 다만 **사용자가 직접 전환한 상태는 자동 전환이 덮어쓰지 않는다.** 입력 중에도
/// 이모지를 넣고 싶은 경우가 있는데, 자동 전환만 두면 그게 불가능해진다.
public struct ToolbarState: Equatable, Sendable {

    public private(set) var mode: ToolbarMode
    /// 사용자가 직접 전환했는가. 참이면 자동 전환이 무시된다.
    public private(set) var isPinnedByUser: Bool

    private let defaultMode: ToolbarMode

    public init(defaultMode: ToolbarMode = .tools) {
        self.mode = defaultMode
        self.defaultMode = defaultMode
        self.isPinnedByUser = false
    }

    /// 조합 상태가 바뀌었을 때 호출한다.
    /// - Parameter isComposing: 지금 조합 중이거나 추천할 문맥이 있는가
    public mutating func textDidChange(isComposing: Bool) {
        guard !isPinnedByUser else { return }
        mode = isComposing ? .suggestions : .tools
    }

    /// 사용자가 툴바를 직접 전환했다. 이후 자동 전환은 멈춘다.
    public mutating func toggleByUser() {
        mode = (mode == .tools) ? .suggestions : .tools
        isPinnedByUser = true
    }

    /// 입력 세션이 끝났다 (다른 앱/필드로 이동). 고정을 풀고 기본 모드로 돌아간다.
    public mutating func endSession() {
        mode = defaultMode
        isPinnedByUser = false
    }
}
