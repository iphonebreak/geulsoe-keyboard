/// 클립보드 기록 패널을 열 때 **무엇을 읽고 무엇을 보여 줄지** (PDR clipboard-history).
///
/// 판정이 익스텐션 타깃(`KeyboardViewController.openClipboardPanel`)에 있으면 `swift test`가
/// 닿지 않아 여기로 뺐다. 조립 지점은 이 두 함수의 답대로 `UIPasteboard`를 읽고 목록을 싣기만 한다.
/// Full Access가 없으면 패널 자체가 열리지 않으므로(도구 버튼이 숨는다) 여기서 권한은 보지 않는다.
///
/// ★ **기록이 꺼져 있으면 읽지도 보여 주지도 않는다** (2026-09-27 사장님 지적 —
/// 「OFF 했는데 클립보드 아이콘을 누르면 기록 1개가 뜬다」). 옛 설계는 OFF일 때 현재 클립보드를
/// 세션 목록 1개로 보여 줬다(저장은 안 함) — 사용자 눈에는 기록과 똑같이 보여 오해를 샀다.
/// 그 대가로 「OFF에서 클립보드 도구로 현재 클립보드 붙여넣기」 길은 버렸다(붙여넣기 칩이 대신한다).
public enum ClipboardPanelContent {

    /// 패널을 열 때 현재 클립보드를 읽어야 하는가.
    ///
    /// - Parameter alreadyRecorded: 지금 `changeCount`를 이미 기록했는가 — 사용자가 ✕로 지운
    ///   현재 클립보드가 재오픈마다 되살아나지 않게 다시 읽지 않는다.
    public static func readsPasteboard(
        historyEnabled: Bool,
        isSecureTextEntry: Bool,
        alreadyRecorded: Bool
    ) -> Bool {
        historyEnabled && !isSecureTextEntry && !alreadyRecorded
    }

    /// 패널에 실을 목록.
    ///
    /// 현재 클립보드는 받지 않는다 — 켜져 있으면 이미 `stored`에 기록돼 있고, 꺼져 있으면
    /// 보여 주지 않는 것이 2026-09-27 결정이다(되살리면 「OFF인데 1개 뜬다」가 돌아온다).
    ///
    /// - Parameter stored: App Group 저장분(최근순) — 현재 클립보드를 **기록한 뒤** 읽은 값.
    ///   secure 필드에서도 저장분은 그대로 보인다(읽기·기록만 막는다 — `readsPasteboard`).
    public static func entries(historyEnabled: Bool, stored: [String]) -> [String] {
        historyEnabled ? stored : []
    }
}
