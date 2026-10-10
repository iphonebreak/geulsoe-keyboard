import TadakDomain

/// 외부 채움글 팩 한 줄의 **읽기 모델**(1-c G1) — 목록 행(2-C)·같은 이름 확인(U3)·이름 있는 알림(AC-4)이 이것을 쓴다.
/// `PackStore.summaries()`가 목록 순서대로 돌려준다. 계획서 `external-snippet-packs-1c-plan.md` 2절 G1, 3-1절 2-C.
///
/// **이름은 사용자 입력이다** — 화면·알림에 **표시**는 하되 로그·분석 이벤트·네트워크로 내보내지 않는다(보안 규칙).
public struct PackSummary: Equatable, Sendable, Identifiable {

    /// 목록 행의 상태 — 시안의 켬·끔·쉬는 중에 **실제로 갈리는 둘**(쉬는 이유·읽을 수 없음)을 더한 다섯 갈래(3-1절 2-C)
    public enum Status: Equatable, Sendable {
        /// 켰고 한도 안 — 키보드에 뜬다
        case on
        case off
        /// 켰지만 한도를 넘어 쉰다(`overflow`·`afterEarlierOverflow`) — 앞 팩을 끄거나 순서를 바꾸면 다시 뜬다
        case restingOverLimit
        /// 켰지만 **내 채움글**이 한도를 넘어 외부 팩 전부가 쉰다(`baselineOverflow`) — 내 채움글을 정리하면 다시 뜬다(4-N)
        case restingForUserSnippets
        /// 변환본이 없거나 못 읽는다(`unavailable`) — **꺼 둔 팩도** 이 상태다(켜면 `packUnavailable`로 거부). 다시 가져오기·지우기로 푼다
        case unavailable
    }

    public var id: String
    /// 팩 이름 — 모르면 nil(표시 칸이 없는 옛 목록에서 변환본까지 못 읽을 때). 알림은 「이름 없는 팩」(`PackNoticeCopy.unnamedPack`)
    public var name: String?
    /// 번호형·문구형 — 모르면 nil(이름과 같은 경우)
    public var mode: ExternalPack.Mode?
    /// 항목 수 — 문구형은 항목, 번호형은 번호 항목(`PackStats.items`)
    public var itemCount: Int
    /// 대표 틀(번호형의 첫 `#틀` 원문) — 문구형이면 nil
    public var titleFormat: String?
    /// 사용자가 켰나 — 쉬는 중이어도 참이다(켬은 사용자 의도, 쉼은 판정 결과)
    public var isEnabled: Bool
    public var status: Status

    public init(id: String, name: String?, mode: ExternalPack.Mode?, itemCount: Int, titleFormat: String?, isEnabled: Bool,
                status: Status) {
        self.id = id
        self.name = name
        self.mode = mode
        self.itemCount = itemCount
        self.titleFormat = titleFormat
        self.isEnabled = isEnabled
        self.status = status
    }

    /// 상태 판정 — **읽을 수 없음이 끔보다 먼저**(꺼 둔 팩도 켜면 거부되니 미리 알린다), 「켬」은 판정에 **포함됐을 때만**
    /// (켰는데 포함도 제외도 아니면 키보드가 싣지 않으므로 「쉬는 중」으로 본다 — 켬이라고 말하지 않는다)
    public static func status(of id: String, isEnabled: Bool, isUnavailable: Bool,
                              in evaluation: ActivePackBudget.Evaluation) -> Status {
        if isUnavailable { return .unavailable }
        guard isEnabled else { return .off }
        if evaluation.isIncluded(id) { return .on }
        switch evaluation.excluded.first(where: { $0.id == id })?.reason {
        case .baselineOverflow: return .restingForUserSnippets
        case .unavailable: return .unavailable
        case .overflow, .afterEarlierOverflow, nil: return .restingOverLimit
        }
    }
}
