import TadakDomain

/// 내 채움글 정리 화면의 모델(1-c ㉠, R25) — 한도를 넘은 옛 저장분에서 **어디까지 키보드에 뜨는지**를 화면 행으로 보인다.
///
/// 경계는 **키보드와 같은 함수** `ActivePackBudget.userSnippetUsage(...).loadableCount`(저장 순서 앞에서부터 한도까지, 9-3)다 —
/// `PackStore.userSnippetBudget()`이 키보드 로더(`PackSnapshotLoader`)와 같은 입력(내 채움글 + 켜진 내장)으로 부른다.
/// 화면은 정규화 단축어(`snippetListID`)가 같은 옛 중복을 **한 행(첫 자리)**으로 보이므로(검증 F7), 저장 순서의 경계를 **행 수**로
/// 옮기는 일을 여기 한 곳에서 한다(계획서 6절 마지막 줄). 지운 뒤에는 저장본에서 다시 만든다(재판정).
public struct UserSnippetBudget: Equatable, Sendable {
    /// 화면 목록 — 저장 순서, 정규화 단축어 기준 중복 제거(`displayEntries`)
    public var entries: [SnippetEntry]
    /// 키보드가 싣는 저장분 수(저장 순서 앞에서부터) — 키보드 로더의 `userEntries.count`와 같다
    public var loadableCount: Int
    /// 키보드에 뜨는 **화면 행** 수 — 이 행 다음부터 「여기부터는 지금 안 떠요」
    public var loadableRowCount: Int
    /// 내 채움글 + 켜진 내장이 한도를 넘었나(9-3) — 넘었으면 외부 팩은 전부 쉰다
    public var isOverLimit: Bool

    /// 경계 줄을 그리나 — 뜨지 않는 행이 하나라도 있을 때
    public var hasBoundary: Bool { loadableRowCount < entries.count }

    /// - Parameters:
    ///   - stored: 내 채움글 저장분(저장 순서 그대로)
    ///   - loadableCount: `ActivePackBudget.userSnippetUsage(stored, ...).loadableCount`
    public init(stored: [SnippetEntry], loadableCount: Int, isOverLimit: Bool) {
        entries = Self.displayEntries(stored)
        self.loadableCount = loadableCount
        // 화면 행은 첫 자리 순서라, 앞 k개에 나온 행이 곧 앞 행들이다 — 앞 k개의 서로 다른 행 수가 경계다
        loadableRowCount = Set(stored.prefix(loadableCount).map(\.snippetListID)).count
        self.isOverLimit = isOverLimit
    }

    /// 화면 목록 규칙 — 정규화 단축어가 같은 저장분은 **첫 것만**("우리집주소"와 "우리집 주소"는 한 행). 설정 화면의 내 채움글 목록도 이것을 쓴다
    public static func displayEntries(_ stored: [SnippetEntry]) -> [SnippetEntry] {
        var seen = Set<String>()
        return stored.filter { seen.insert($0.snippetListID).inserted }
    }
}
