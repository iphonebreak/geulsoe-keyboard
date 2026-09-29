/// 키보드 등장 시 클립보드 프로브 — **내용(`string`)을 읽을지** (PDR verification-code-paste · clipboard-history).
///
/// 조립 지점(`KeyboardViewController.probePasteboard`)에 판정이 있으면 `swift test`가 닿지 않아 여기로 뺐다.
/// 조립 지점은 전체 접근·secure 입력란을 먼저 거른 뒤 `plan`을 만들고, **읽기는 `read`에 클로저로 넘긴다** —
/// 게이트를 지나야만 그 클로저가 불린다. 스파이 테스트가 「안 불렸다」를 센다(`PasteboardProbeTests`).
///
/// ★ 2026-09-29 수정(검증자 발견, 출시 차단): 조립 지점이 `pasteboard.string`을 스위치 게이트보다 **먼저** 불러,
/// 전체 접근 ON이면 「복사한 인증번호 제안」·「복사한 텍스트 제안」·「클립보드 기록」을 **셋 다 꺼도**, 이미 소비·기록한
/// 클립보드여도 키보드가 뜰 때마다 내용을 읽었다(`4e4fe5a`, v1.1.0부터). `.claude/rules/security.md`
/// 「두 기능이 모두 꺼져 있으면 읽지 않는다」·최소 접근 위반이고, `string`은 iOS 붙여넣기 알림을 띄울 수도 있다.
public enum PasteboardProbe {

    /// 이번 등장에서 무엇이 필요한가. 둘 다 거짓이면 **클립보드를 건드리지 않는다**(재시도도 없다).
    public struct Plan: Equatable, Sendable {
        /// 칩 후보를 만들 차례 — 인증번호·텍스트 제안 중 하나라도 켬 + 이 `changeCount`를 아직 칩으로 소비하지 않음
        public let needsSuggestion: Bool
        /// 기록할 차례 — 클립보드 기록 켬 + 이 `changeCount`를 아직 기록하지 않음
        public let needsHistory: Bool

        public var wantsContent: Bool { needsSuggestion || needsHistory }

        /// 빈손(내용이 아직 안 옴)이면 짧게 다시 시도할지 — 원하는 게 있을 때만(2026-09-15 재시도 규칙 그대로)
        public func retries(afterReading content: String?) -> Bool { wantsContent && content == nil }
    }

    /// - Parameters:
    ///   - consumedChangeCount: 칩을 탭해 이미 쓴 클립보드의 `changeCount`
    ///   - recordedChangeCount: 이미 기록에 넣은 클립보드의 `changeCount`
    public static func plan(
        codeSuggestionsEnabled: Bool,
        pasteSuggestionsEnabled: Bool,
        historyEnabled: Bool,
        changeCount: Int,
        consumedChangeCount: Int?,
        recordedChangeCount: Int?
    ) -> Plan {
        Plan(
            needsSuggestion: (codeSuggestionsEnabled || pasteSuggestionsEnabled) && changeCount != consumedChangeCount,
            needsHistory: historyEnabled && changeCount != recordedChangeCount)
    }

    /// **게이트 → `hasStrings` → `string`** 순서로만 읽는다.
    ///
    /// - 게이트(`plan.wantsContent`)가 닫히면 두 클로저 모두 부르지 않는다 — 클립보드를 아예 건드리지 않는다.
    /// - `hasStrings`는 내용을 가져오지 않아 붙여넣기 확인 창을 띄우지 않는다. 참일 때만 `string`을 **한 번** 부른다.
    public static func read(_ plan: Plan, hasStrings: () -> Bool, readString: () -> String?) -> String? {
        guard plan.wantsContent else { return nil }
        guard hasStrings() else { return nil }
        return readString()
    }
}
