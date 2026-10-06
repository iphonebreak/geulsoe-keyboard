/// 외부 채움글·내 채움글·내장 팩 변경의 **사유별 알림 모델**(1-c 계획서 `external-snippet-packs-1c-plan.md` 4-2절 A~G, 2절 G2·G7).
///
/// 같은 거부 사유라도 **무엇을 하다 막혔는지**(내장 켜기 / 외부 팩 켜기 / 교체 / 가져오기)와 **저장 전 상태**(내 채움글이 이미 한도를
/// 넘었나 — A3·D2)에 따라 문구·버튼이 갈린다. 그래서 `PackStore.Rejection` 하나로 문구를 정하지 않는다(G7 — 예전
/// `isBudgetLimit`는 팩 수 초과·부르는 쪽 버그까지 「한도」로 묶었고, 목록 손상에 「잠시 뒤 다시」를 안내했다).
///
/// 받은 결과의 `newlyExcluded`(쉬게 된 팩)와 거부의 `rechecked`(다시 판정함)를 **버리지 않는다**(codex #8) — 이름 있는 G1·G2와
/// 「그 사이 … 다시 확인했어요」 한 줄이 된다. 문구는 `PackNoticeCopy` 한 곳.
public struct PackChangeNotice: Equatable, Sendable {

    /// 무엇을 하다 나온 결과인가 — `PackStore`의 쓰기 메서드 하나에 하나(켜기·끄기는 둘로 나눈다)
    public enum Operation: CaseIterable, Sendable {
        case saveUserSnippet, deleteUserSnippet
        case enableBuiltIn, disableBuiltIn
        case importPack, importDisabledPack
        case enablePack, disablePack, replacePack, deletePack, reorderPacks
    }

    /// 4-2절 표의 줄 — G3(순서 변경 전 사전 안내)는 알림이 아니라 화면 줄이라 `PackNoticeCopy.reorderWarning`
    public enum Reason: CaseIterable, Sendable {
        /// A1 내 채움글 저장 — 한도(개수 쪽: 항목·단축어 수)
        case userSaveTooMany
        /// A2 같은 건 — 길이·크기 쪽(글자 수·바이트)
        case userSaveTooLong
        /// A3 같은 건 — 저장 전부터 한도를 넘은 옛 초과본(R21: 줄이는 수정·지우기만 된다)
        case userSaveWhileOverLimit
        /// B1 내장 팩 켜기 — 한도
        case builtInOverLimit
        /// B2 내장 팩 켜기 — 외부 팩이 밀림(순서 바꾸기로는 안 풀린다 — 내장이 먼저다)
        case builtInDisplacesPacks
        /// C1 외부 팩 켜기 — 다른 팩이 밀림(R15)
        case enableDisplacesPacks
        /// C2 외부 팩 켜기 — 자기 자신이 한도 밖
        case enableExceedsLimit
        /// C3 켜진 팩 교체 — 한도
        case replaceExceedsLimit
        /// D1 가져오기 — 한도(「꺼 둔 채로 가져오기」를 준다, U2)
        case importExceedsLimit
        /// D2 가져오기 — 내 채움글이 이미 한도 초과(「다른 외부 팩을 끄라」는 틀린 안내라 갈랐다)
        case importWhileUserOverLimit
        /// D3 가져오기 — 팩이 너무 많다(꺼 둔 팩도 센다 — 「꺼 둔 채로」 없음, 8절 #5)
        case importTooManyPacks
        /// E1 목록 손상(`libraryUnreadable`) — 다시 해도 안 풀린다. 복구해야 한다(2단계)
        case libraryUnreadable
        /// E2 읽을 수 없는 팩 켜기(`packUnavailable`) — 다시 가져오기·지우기
        case packUnavailable
        /// F1 쓰기 실패 — 다시 하면 풀릴 수 있는 유일한 사유
        case writeFailed
        /// F2 그 사이 바뀜(`notFound`·`invalidOrder`)
        case changedMeanwhile
        /// F3 앱 내부 오류(`moreThanOneItem`·`invalidDisabledImport` — 부르는 쪽 버그). 문구에 내용·이름을 담지 않는다
        case internalError
        /// G1 받았지만 팩 하나가 쉬게 됨(AC-4)
        case packRested
        /// G2 같은 — 둘 이상
        case packsRested

        /// 거부인가 — 받았는데 팩이 쉬게 된 알림(G1·G2)만 거짓
        public var isRejection: Bool { self != .packRested && self != .packsRested }

        /// 이름(「○○」)이 문구에 들어가는가 — 이 넷만 저장본에서 이름을 찾는다
        var namesPacks: Bool {
            switch self {
            case .builtInDisplacesPacks, .enableDisplacesPacks, .packRested, .packsRested: true
            default: false
            }
        }
    }

    /// 알림 버튼 — 닫는 버튼(`confirm`·`close`)과 그 밖의 동작. 동작이 가는 화면(정리·복구·순서·가져오기)은 다음 단계들이 붙인다
    public enum Action: CaseIterable, Sendable {
        case confirm, close
        /// 내 채움글 정리 — 2단계(옛 초과본 정리 화면)
        case organize
        /// 꺼 둔 채로 가져오기(U2) — 4·5단계
        case importDisabled
        /// 팩 순서 바꾸기(U4) — 3단계
        case reorderPacks
        /// 목록 복구(R24) — 2단계
        case recoverLibrary
        /// 팩 지우기 — 3단계
        case deletePack

        public var label: String { PackNoticeCopy.label(self) }
    }

    public let reason: Reason
    public let title: String
    public let message: String
    /// 닫는 버튼 앞에 놓는 동작(화면 순서대로) — 없으면 빈 배열
    public let actions: [Action]
    /// 닫는 버튼 — 가져오기 거부(D1·D2)는 「닫기」, 나머지는 「확인」
    public let dismiss: Action
    /// 알림이 가리키는 팩 — 밀리거나 쉬게 된 팩(B2·C1·C3·G1·G2), 켜려던 팩(C2·E2). 가져오기(D)는 저장되지 않은 새 id라 비운다
    public let packIDs: [String]
    /// 거부를 지금 저장본으로 다시 판정했다(AC-3) — 문구 첫 줄에 이미 들어가 있다
    public let rechecked: Bool

    public var isRejection: Bool { reason.isRejection }

    /// - Parameters:
    ///   - userSnippetsOverLimit: **저장 전** 내 채움글 + 켜진 내장이 이미 한도를 넘었나(`evaluation().baselineOverflow`가 비어 있지 않음).
    ///     거부는 저장본을 바꾸지 않으므로 거부 뒤에 읽어도 같은 값이다. A·D 거부에서만 부른다
    ///   - packName: 팩 id → 이름(`PackStore.summaries()`). 이름이 들어가는 알림(B2·C1·G1·G2)에서 **첫 팩만** 부른다. 모르면 「이름 없는 팩」
    /// - Returns: 받았고 쉬게 된 팩이 없으면 nil — **거부는 언제나 알림이 있다**
    public init?(_ operation: Operation, result: PackStore.CommitResult,
                 userSnippetsOverLimit: () -> Bool, packName: (String) -> String?) {
        switch result {
        case .accepted(let accepted):
            guard !accepted.newlyExcluded.isEmpty else { return nil }
            reason = accepted.newlyExcluded.count == 1 ? .packRested : .packsRested
            packIDs = accepted.newlyExcluded
            rechecked = accepted.rechecked
        case .rejected(let rejection, let wasRechecked):
            (reason, packIDs) = Self.classify(rejection, operation: operation, userSnippetsOverLimit: userSnippetsOverLimit)
            rechecked = wasRechecked
        }
        let firstName = reason.namesPacks ? packIDs.first.flatMap(packName) ?? PackNoticeCopy.unnamedPack : ""
        let body = PackNoticeCopy.message(reason, firstName: firstName, count: packIDs.count)
        // F2는 이미 「그 사이 … 바뀌었어요」라 같은 말을 두 번 하지 않는다
        let prefixed = rechecked && reason.isRejection && reason != .changedMeanwhile
        title = PackNoticeCopy.title(reason)
        message = prefixed ? PackNoticeCopy.recheckedLine + "\n" + body : body
        (actions, dismiss) = Self.buttons(reason)
    }

    private static func classify(_ rejection: PackStore.Rejection, operation: Operation,
                                 userSnippetsOverLimit: () -> Bool) -> (Reason, [String]) {
        switch rejection {
        case .gate(let gate):
            switch gate {
            case .baselineOverLimit(let dimensions):
                if operation == .enableBuiltIn { return (.builtInOverLimit, []) }
                if userSnippetsOverLimit() { return (.userSaveWhileOverLimit, []) }
                // 개수 쪽이 넘었으면 문구를 줄여도 안 풀린다 — 지우기를 먼저 말하는 A1
                let countSide = dimensions.contains(.items) || dimensions.contains(.needleCount)
                return (countSide ? .userSaveTooMany : .userSaveTooLong, [])
            case .displacesPacks(let ids):
                switch operation {
                case .enableBuiltIn: return (.builtInDisplacesPacks, ids)
                case .replacePack: return (.replaceExceedsLimit, ids)
                case .importPack, .importDisabledPack: return (importLimit(userSnippetsOverLimit), [])
                default: return (.enableDisplacesPacks, ids)
                }
            case .packExcluded(let id, _):
                switch operation {
                case .importPack, .importDisabledPack: return (importLimit(userSnippetsOverLimit), [])
                case .replacePack: return (.replaceExceedsLimit, [id])
                default: return (.enableExceedsLimit, [id])
                }
            case .tooManyPacks: return (.importTooManyPacks, [])
            case .invalidDisabledImport: return (.internalError, [])
            }
        case .libraryUnreadable: return (.libraryUnreadable, [])
        case .packUnavailable(let id): return (.packUnavailable, [id])
        case .writeFailed: return (.writeFailed, [])
        case .notFound, .invalidOrder: return (.changedMeanwhile, [])
        case .moreThanOneItem: return (.internalError, [])
        }
    }

    private static func importLimit(_ userSnippetsOverLimit: () -> Bool) -> Reason {
        userSnippetsOverLimit() ? .importWhileUserOverLimit : .importExceedsLimit
    }

    private static func buttons(_ reason: Reason) -> ([Action], Action) {
        switch reason {
        case .userSaveWhileOverLimit: ([.organize], .confirm)
        case .enableDisplacesPacks: ([.reorderPacks], .confirm)
        case .importExceedsLimit: ([.importDisabled], .close)
        case .importWhileUserOverLimit: ([.organize, .importDisabled], .close)
        case .libraryUnreadable: ([.recoverLibrary], .confirm)
        case .packUnavailable: ([.deletePack], .confirm)
        default: ([], .confirm)
        }
    }
}
