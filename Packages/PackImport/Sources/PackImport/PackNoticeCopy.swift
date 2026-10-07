/// 외부 채움글 변경 알림의 **문구 표 — 한 곳**(1-c 계획서 `external-snippet-packs-1c-plan.md` 4-2절 A~G를 글자 그대로).
/// 화면은 이 표를 그대로 보인다. 패키지에 두는 이유는 문구 검사를 `swift test`로 돌리기 위해서다(5절 1단계 ④ —
/// U6 교회·성경 소재 0 · 금칙어 · 한도 숫자 0, `PackNoticeCopyLintTests`).
///
/// 규칙: 해요체 · 용어는 「단축어」「채움글」 · **한도 숫자를 쓰지 않는다**(8절 #3 — 후보값을 사용자 약속으로 굳히지 않는다) ·
/// 문구마다 **무엇을 하면 풀리는지**를 말한다(「잠시 뒤 다시」는 쓰기 실패에만 맞는 말이라 쓰지 않는다) ·
/// 「○○」에는 사용자가 정한 팩 이름(40자 이하)이 들어간다 — **표시만** 하고 로그·분석 이벤트에 싣지 않는다(보안 규칙).
public enum PackNoticeCopy {

    /// 거부를 다시 판정했을 때 문구 앞 한 줄(AC-3 `rechecked`)
    public static let recheckedLine = "그 사이 채움글이 바뀌어서 다시 확인했어요."
    /// 이름을 모르는 팩(표시 칸도 변환본도 없는 옛 목록·그 사이 지워진 팩)
    public static let unnamedPack = "이름 없는 팩"

    static func title(_ reason: PackChangeNotice.Reason) -> String {
        switch reason {
        case .userSaveTooMany, .userSaveTooLong, .userSaveWhileOverLimit, .writeFailed, .internalError: "저장하지 못했어요"
        case .builtInOverLimit, .builtInWhileUserOverLimit, .builtInDisplacesPacks, .enableDisplacesPacks, .enableExceedsLimit,
             .enableWhileUserOverLimit, .packUnavailable: "켤 수 없어요"
        case .replaceExceedsLimit, .replaceWhileUserOverLimit: "바꿀 수 없어요"
        case .importExceedsLimit, .importWhileUserOverLimit: "가져올 수 없어요"
        case .importTooManyPacks: "더 가져올 수 없어요"
        case .libraryUnreadable: "채움글을 바꿀 수 없어요"
        case .changedMeanwhile: "목록이 바뀌었어요"
        case .packRested, .packsRested: "저장했어요"
        }
    }

    /// - Parameters:
    ///   - firstName: 이름이 들어가는 사유(B2·C1·G1·G2)의 첫 팩 이름 — 그 밖에는 쓰지 않는다
    ///   - count: 그 팩 수 — 둘 이상이면 「「A」 외 n개」
    static func message(_ reason: PackChangeNotice.Reason, firstName: String, count: Int) -> String {
        switch reason {
        case .userSaveTooMany:          // A1
            "채움글이 너무 많아요. 안 쓰는 채움글을 지우거나 내장 팩을 끈 뒤 다시 해 주세요."
        case .userSaveTooLong:          // A2
            "채움글이 너무 길어요. 문구를 줄이거나 안 쓰는 채움글을 지운 뒤 다시 해 주세요."
        case .userSaveWhileOverLimit:   // A3
            "지금은 채움글이 한도를 넘은 상태라 문구를 늘릴 수 없어요. 줄이는 수정이나 지우기만 돼요."
        case .builtInOverLimit:         // B1
            "켜면 채움글이 한도를 넘어요. 안 쓰는 채움글을 지우거나 다른 내장 팩을 끈 뒤 켜 주세요."
        case .builtInWhileUserOverLimit:   // B1b (2단계 추가)
            "내 채움글이 한도를 넘어서 지금은 내장 팩을 켤 수 없어요. 먼저 내 채움글을 정리해 주세요."
        case .builtInDisplacesPacks:    // B2
            "켜면 \(subject(firstName, count: count)) 한도 밖으로 밀려요. 외부 채움글 팩을 먼저 끄거나 지운 뒤 켜 주세요."
        case .enableDisplacesPacks:     // C1 — 「팩 우선순위 바꾸기」 버튼 대신 끄는 길을 문장으로(R30)
            "켜면 이 팩보다 아래에 있는 \(subject(firstName, count: count)) 한도 밖으로 밀려요. "
                + "먼저 다른 팩을 끄거나, 「외부 채움글」 목록에서 팩을 길게 눌러 순서를 바꿔 주세요."
        case .enableExceedsLimit:       // C2
            "켜면 한도를 넘어요. 다른 팩을 먼저 꺼 주세요."
        case .enableWhileUserOverLimit:    // C2b (2단계 추가)
            "내 채움글이 한도를 넘어서 외부 팩을 켤 수 없어요. 먼저 내 채움글을 정리해 주세요."
        case .replaceExceedsLimit:      // C3
            "새 파일로 바꾸면 한도를 넘어요. 다른 팩을 먼저 끄거나 지운 뒤 다시 가져와 주세요."
        case .replaceWhileUserOverLimit:   // C3b (2단계 추가)
            "내 채움글이 한도를 넘어서 지금은 팩을 바꿀 수 없어요. 먼저 내 채움글을 정리해 주세요."
        case .importExceedsLimit:       // D1
            "켜진 채움글을 모두 합치면 한도를 넘어요. 다른 외부 팩을 끄거나 지운 뒤 다시 가져와 주세요."
        case .importWhileUserOverLimit: // D2
            "내 채움글이 한도를 넘어서 외부 팩을 쓸 수 없어요. 먼저 내 채움글을 정리해 주세요. 꺼 둔 채로는 가져올 수 있어요."
        case .importTooManyPacks:       // D3
            "외부 채움글 팩이 너무 많아요. 안 쓰는 팩을 지운 뒤 다시 가져와 주세요."
        case .libraryUnreadable:        // E1
            "외부 채움글 목록을 읽을 수 없어서 지금은 채움글을 저장하거나 지울 수 없어요. 가져온 팩 파일은 지우지 않았어요. "
                + "키보드에서는 지금 쓰던 채움글이 그대로 떠요. 목록을 복구하면 다시 바꿀 수 있어요."
        case .packUnavailable:          // E2
            "이 팩의 파일을 읽을 수 없어요. 같은 이름으로 파일을 다시 가져와 바꾸거나 팩을 지워 주세요."
        case .writeFailed:              // F1
            "기기에 쓰지 못했어요. 저장 공간을 확인한 뒤 다시 해 주세요. 원래 있던 채움글은 그대로예요."
        case .changedMeanwhile:         // F2
            "그 사이 채움글이 바뀌었어요. 화면을 다시 열어 확인해 주세요."
        case .internalError:            // F3 — 내용·이름을 담지 않는다
            "문제가 생겨서 저장하지 못했어요. 앱을 다시 열어 주세요."
        case .packRested:               // G1 (AC-4)
            "대신 \(subject(firstName, count: 1)) 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요."
        case .packsRested:              // G2
            "대신 「\(firstName)」 외 \(number(count - 1))개 팩이 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 팩 목록에서 확인해 주세요."
        }
    }

    // MARK: - 상태 표시 (4-3절) — 2단계

    /// 목록 행 보조줄 — 켬·끔은 배지가 없다
    public static func statusLine(_ status: PackSummary.Status) -> String? {
        switch status {
        case .on, .off: nil
        case .restingOverLimit: "쉬는 중 · 한도를 넘어 지금은 안 떠요"
        case .restingForUserSnippets: "쉬는 중 · 내 채움글을 정리하면 다시 떠요"
        case .unavailable: "읽을 수 없어요 · 다시 가져오거나 지워 주세요"
        }
    }

    /// 팩 상세 상단 — 읽을 수 없는 팩(3단계 팩 상세가 쓴다)
    public static let unavailablePackDetail = "이 팩의 파일을 읽을 수 없어요. 같은 이름으로 파일을 다시 가져오면 바꿀 수 있어요. 지울 수도 있어요."

    /// 배너 ㉠ — 한도 넘은 옛 내 채움글. `loadableCount`는 키보드에 뜨는 **화면 행** 수(`UserSnippetBudget.loadableRowCount`)
    public static func overLimitBanner(loadableCount: Int) -> String {
        "내 채움글이 한도를 넘어서 앞의 \(number(loadableCount))개만 키보드에 떠요. 나머지와 외부 팩은 지금 안 떠요. 지운 것은 없어요."
    }

    /// 배너 ㉡ — 목록 손상. 낯선 버전이면 「앱을 올리면 다시 읽힐 수 있어요」를 한 줄 더한다. 읽히면 nil
    public static func libraryBanner(_ status: PackLibraryStatus) -> String? {
        let damaged = "외부 채움글 목록을 읽을 수 없어요. 가져온 팩 파일은 지우지 않았어요. 복구하기 전에는 채움글을 저장하거나 지울 수 없어요."
        switch status {
        case .readable: return nil
        case .unreadable, .corrupt: return damaged
        case .unknownSchema:
            return damaged + "\n새 버전의 글쇠에서 만든 목록 같아요. 앱을 최신 버전으로 올리면 다시 읽힐 수 있어요. 복구하면 이 기기의 팩 목록을 다시 만들어요."
        }
    }

    /// 배너 ㉢ — 읽을 수 없는 팩(계획서 4-3절에 배너 문구가 없어 팩 상세 문구로 지었다). 이름 뒤는 「의」라 받침과 무관하다
    public static func unavailablePacksBanner(names: [String]) -> String {
        let first = names.first ?? unnamedPack
        let subject = names.count > 1 ? "「\(first)」 외 \(number(names.count - 1))개 팩의 파일을 읽을 수 없어서 지금 안 떠요."
            : "「\(first)」의 파일을 읽을 수 없어서 이 팩은 지금 안 떠요."
        return subject + " 같은 이름으로 파일을 다시 가져오면 바꿀 수 있어요. 지울 수도 있어요."
    }

    // MARK: 정리 화면 (㉠ · R25)

    public static let cleanupTitle = "내 채움글 정리"
    public static let cleanupBoundary = "여기부터는 지금 안 떠요"
    public static let cleanupFooter = "지우면 되돌릴 수 없어요. 한도 안으로 들어오면 쉬던 팩이 다시 떠요."
    /// 끝 알림 제목 — 계획서 표에 제목이 없어 지었다
    public static let cleanupDoneTitle = "정리했어요"
    public static let cleanupDoneMessage = "이제 모두 쓸 수 있어요. 쉬던 팩이 한도 안이면 다시 떠요."

    // MARK: 목록 복구 (㉡ · R24)

    public static let recoveryTitle = "목록을 복구할까요?"
    public static let recoveryConfirm = "복구"
    public static let recoveryCancel = "취소"

    /// 복구 확인 시트 — 4-3절 문구 + R24 「틀·단축어 주인이 바뀔 수 있어요」 한 줄(4-5절 기획 서명 2026-10-06). 찾은 팩이 없으면 「0개를 찾았어요」 대신 빈 목록 안내
    public static func recoveryMessage(packCount: Int) -> String {
        guard packCount > 0 else {
            return "가져온 팩 파일을 찾지 못했어요. 복구하면 빈 목록으로 다시 시작해요. 원래 목록 파일은 따로 보관해요."
        }
        return "가져온 팩 \(number(packCount))개를 찾았어요. 순서와 켬/끔은 알 수 없어서 모두 꺼진 채로 불러와요. 쓸 팩은 직접 켜 주세요. "
            + "원래 목록 파일은 따로 보관해요.\n팩 순서가 예전과 달라질 수 있어서, 같은 틀이나 단축어를 다른 팩이 쓰게 될 수 있어요."
    }

    /// 끝 알림 제목 — 계획서 표에 제목이 없어 지었다
    public static let recoveredTitle = "목록을 복구했어요"

    public static func recoveredMessage(packCount: Int) -> String {
        packCount > 0 ? "팩 \(number(packCount))개를 불러왔어요. 모두 꺼져 있어요." : "빈 목록으로 다시 만들었어요."
    }

    public static let recoveryFailedTitle = "복구하지 못했어요"
    public static let recoveryFailedMessage = "기기에 쓰지 못했어요. 저장 공간을 확인한 뒤 다시 해 주세요. 원래 목록 파일은 그대로예요."

    // MARK: - 외부 채움글 절 (2-B·2-C) — 3단계. 글자는 시안 `docs/design/external-snippet-packs/index.html` 2절 그대로

    public static let externalSectionTitle = "외부 채움글"
    /// 가져오기 입구 — 4단계가 3-A 첫 화면(`PackImportStartView`)으로 연결했다. 그 화면의 제목이기도 하다
    public static let addPack = "외부 채움글 추가"
    /// 2-B 빈 상태 — 첫 문장은 판이 바꾼다(`PackCopySet`: CSV 전용판 「CSV 파일로…」 / xlsx 중심판 「엑셀 파일로…」, AC-35·R12)
    public static var emptyListFooter: String {
        PackCopySet.current.lines.listIntro + " 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요."
    }
    /// 목록이 손상된 동안 — 빈 상태(2-B) 문구는 「팩이 없다」로 읽혀 헷갈린다(화면 확인 O-2). 위 배너(㉡)가 복구 길을 준다
    public static let unreadableListFooter = "외부 채움글 목록을 읽을 수 없어요. 위에서 목록을 복구해 주세요."

    /// 「외부 채움글」 절 풋터 — 목록을 못 읽으면 손상 한 줄, 팩이 없으면 2-B 빈 상태, 있으면 **없다**(nil). 2-C 「위에 있는 줄이 먼저 떠요 …」
    /// 풋터는 뺐다(사장님 실기 2026-10-07) — 순서가 곧 우선순위라는 것은 「내 채움글 (우선순위)」 줄이 말한다
    public static func externalSectionFooter(isEmpty: Bool, libraryStatus: PackLibraryStatus) -> String? {
        if libraryStatus.needsRecovery { return unreadableListFooter }
        return isEmpty ? emptyListFooter : nil
    }
    /// 순서 목록의 「내 채움글」 줄(U1) — 아래 「내 채움글」 절과 헷갈리지 않게 「(우선순위)」(2026-10-07 「순서」 → 「우선순위」 용어 통일)
    public static let userSlotTitle = "내 채움글 (우선순위)"
    /// 머리글 버튼·풋터가 없어 「길게 눌러 끈다」를 이 줄이 알린다(R30, 코디네이터 결정 2026-10-07)
    public static let userSlotDetail = "길게 눌러 끌면 우선순위가 바뀌어요 · 문구는 아래 「내 채움글」 절에서"
    /// 목록 줄의 VoiceOver 동작 — 길게 눌러 끌기 대신 한 칸씩 옮긴다(R30, 놓는 것과 같은 길로 저장)
    public static let moveUpAction = "위로 옮기기"
    public static let moveDownAction = "아래로 옮기기"
    /// 행 값 — 사용자가 켰나(쉬는 중이어도 켬, 쉬는 이유는 `statusLine`)
    public static let enabledValue = "켬"
    public static let disabledValue = "끔"

    /// 종류 · 항목 수 — 종류를 모르면 nil(읽을 수 없는 옛 팩)
    public static func packKind(_ summary: PackSummary) -> String? {
        guard let mode = summary.mode else { return nil }
        return "\(mode == .numbered ? "번호형" : "문구형") · \(number(summary.itemCount))개"
    }

    /// 2-C 행 보조줄 — 종류 · 항목 수 · 대표 틀(번호형만)
    public static func packRowDetail(_ summary: PackSummary) -> String? {
        guard let kind = packKind(summary) else { return nil }
        guard summary.mode == .numbered, let format = summary.titleFormat else { return kind }
        return kind + " · " + format
    }

    /// 안내 둘째 줄에 이름을 다 보일 단축어 수 — 넘으면 「외 n개」(가져오기 겹침 안내 4-I)
    static let shownTriggerCount = 5

    // MARK: 팩 상세 (2-E·U1)

    public static let useToggle = "이 팩 사용"
    public static let infoHeader = "정보"
    public static let kindLabel = "종류"
    public static let licenseLabel = "출처"
    public static let infoFooter = "출처는 가져올 때 확인한 문구 그대로예요."
    public static let templatesHeader = "단축어 틀"
    public static let templatesFooter = "같은 틀을 두 팩이 쓰면 위에 있는 팩이 가져요. 고유한 앞 글자(예: 고사성어 {n}번)를 쓰면 겹치지 않아요."

    /// 틀 상태 배지(10-4 ③) — 사용 중 · 뒤 순서 · 가려짐
    public static func patternBadge(_ status: PackStanding.PatternStatus) -> String {
        switch status {
        case .owned: "사용 중"
        case .outranked: "뒤 순서"
        case .shadowed: "가려짐"
        }
    }

    /// 팩 상세의 틀·단축어 자리가 **가정**인 까닭 — 지금 키보드에 뜨지 않는 팩은 「켜면(다시 뜨면) 어떻게 되나」로 계산한다
    /// (`PackImpact.standing` — 그 팩만 포함된 것으로 놓는다). 그 전제를 절 머리·배지에 드러낸다(검증 F-5)
    public enum StandingPremise: Equatable, Sendable {
        /// 꺼진 팩 — 켜면
        case ifEnabled
        /// 켜져 있지만 쉬는 팩 — 다시 뜨면
        case ifResumed
    }

    /// 지금 뜨는 팩·읽을 수 없는 팩(자리를 계산하지 않는다)은 nil
    public static func standingPremise(_ status: PackSummary.Status) -> StandingPremise? {
        switch status {
        case .on, .unavailable: nil
        case .off: .ifEnabled
        case .restingOverLimit, .restingForUserSnippets: .ifResumed
        }
    }

    /// 「단축어 틀」 절 머리 — 가정이면 「— 켜면 이렇게 떠요」
    public static func templatesHeader(_ premise: StandingPremise?) -> String {
        switch premise {
        case nil: templatesHeader
        case .ifEnabled?: "\(templatesHeader) — 켜면 이렇게 떠요"
        case .ifResumed?: "\(templatesHeader) — 다시 뜨면 이렇게 떠요"
        }
    }

    /// 틀 배지 — 가정이면 「사용 중」이 아니라 「켜면 사용」·「뜨면 사용」(지금 쓰는 것처럼 보이지 않게). 뒤 순서·가려짐은 그대로
    public static func patternBadge(_ status: PackStanding.PatternStatus, premise: StandingPremise?) -> String {
        switch (status, premise) {
        case (.owned, .ifEnabled?): "켜면 사용"
        case (.owned, .ifResumed?): "뜨면 사용"
        default: patternBadge(status)
        }
    }

    /// 틀 행 설명 줄 — 이름은 다른 팩 이름(`PackDetail.name(of:)`). 주어는 **뜨는 문구**다 — 「이 팩이 써요」는 「이 팩을 써요」로
    /// 읽혔다(사장님 실기 2026-10-07). 이 틀을 치면 어느 문구가 뜨는지로 말하고, 가정(꺼진·쉬는 팩)이면 「켜면(다시 뜨면)」을 붙인다(검증 F-5)
    public static func patternLine(_ status: PackStanding.PatternStatus, premise: StandingPremise? = nil,
                                   name: (String) -> String) -> String {
        let condition = switch premise {
        case nil: ""
        case .ifEnabled?: "켜면 "
        case .ifResumed?: "다시 뜨면 "
        }
        switch status {
        case .owned(let shared):
            guard let first = shared.first else { return "\(condition)이 팩 문구가 떠요" }
            let others = shared.count > 1 ? "「\(name(first))」 외 \(number(shared.count - 1))개 팩도" : "「\(name(first))」도"
            return "아래 \(others) 같은 틀이지만 \(condition)위에 있는 이 팩 문구가 떠요"
        case .outranked(let owner):
            return "같은 틀이라 위에 있는 「\(name(owner))」 문구가 먼저 떠요"
        case .shadowed(let triggers):
            // 가림은 **그 끝말로 끝나는 입력에서만**이다 — 「이 틀은 안 떠요」는 범위를 과장했다(화면 확인 S-3, 시안 4-I·5-C 꼴)
            let first = triggers.first ?? ""
            let many = triggers.count > 1
            let subject = many ? "「\(first)」 외 \(number(triggers.count - 1))개" : "「\(first)」"
            return "「…\(first)」\(many ? " 등" : "")\(directionParticle(after: many ? "등" : first)) 끝나는 입력에서는 단축어 \(subject) 문구가 먼저 떠요"
        }
    }

    /// U1 — 문구형 팩에서 위 줄에 밀린 단축어 절
    public static func hiddenTriggersHeader(count: Int) -> String { "지금 안 뜨는 단축어 \(number(count))개" }

    /// U1 절 머리 — 가정이면 「지금」이 아니라 「켜도」·「다시 떠도」(검증 F-5)
    public static func hiddenTriggersHeader(count: Int, premise: StandingPremise?) -> String {
        switch premise {
        case nil: hiddenTriggersHeader(count: count)
        case .ifEnabled?: "켜도 안 뜨는 단축어 \(number(count))개"
        case .ifResumed?: "다시 떠도 안 뜨는 단축어 \(number(count))개"
        }
    }
    public static let hiddenTriggerBadge = "뒤 순서"

    public static func hiddenTriggerLine(owner: PackImpact.Source, name: (String) -> String) -> String {
        let shown = rowName(owner, name: name)
        return "위에 있는 \(shown)\(subjectParticle(after: shown)) 먼저 떠요"
    }

    /// 위 줄이 하나면 그 이름 위로, 여럿이면 「더 위로」. 올리는 곳은 「외부 채움글」 목록 — 길게 눌러 끈다(R30, 「팩 우선순위 바꾸기」 버튼은 없앴다)
    public static func hiddenTriggersFooter(owners: [PackImpact.Source], name: (String) -> String) -> String {
        let distinct = owners.reduce(into: [PackImpact.Source]()) { if !$0.contains($1) { $0.append($1) } }
        let target = distinct.count == 1 ? "\(rowName(distinct[0], name: name)) 위로" : "더 위로"
        return "목록에서 위에 있는 쪽이 먼저 떠요. 이 팩 문구를 쓰려면 「외부 채움글」 목록에서 이 팩을 길게 눌러 \(target) 올려 주세요."
    }

    /// 목록 줄 이름 — 「내 채움글」·「팩 이름」(U1 컷은 내 채움글에도 괄호를 쓴다)
    private static func rowName(_ source: PackImpact.Source, name: (String) -> String) -> String {
        switch source {
        case .userSnippets: "「내 채움글」"
        case .pack(let id): "「\(name(id))」"
        case .builtIn: "내장 팩"
        }
    }

    public static let usageHeader = "사용법"
    /// 내장 팩 상세와 같은 문구
    public static let usageFooter = "단축어를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 단축어가 전문으로 바뀌어요."

    /// 5-A 「이렇게 칩이 떠요」 — 칩 제목
    public static func usageResult(_ title: String) -> String { "→ \(title)" }

    /// 팩 상세 「사용법」·완료 화면 「이렇게 써 보세요」 — 그 단축어를 쳐서 칩을 누르면 **들어가는 문구**(본문, 사장님 실기 2026-10-07).
    /// 여러 줄이면 **줄을 빈칸 하나로 이어** 한 줄로, 길면 자르고 끝에 「…」 — 한 줄을 넘지 않게(화면도 한 줄로 자른다).
    /// 첫 줄만 보이면 「안녕하세요.」처럼 어느 문구인지 모를 때가 많아 잇는다(코디네이터, 사장님 실기 2026-10-07 뒤)
    public static func usageResult(body: String) -> String {
        let lines = body.split(whereSeparator: \.isNewline).map(trimmedSpaces).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "→" }
        let joined = lines.joined(separator: " ")
        if joined.count > usageResultLength { return "→ \(trimmedSpaces(joined.prefix(usageResultLength)))…" }
        return "→ \(joined)"
    }

    /// 앞뒤 공백을 뗀다(Foundation 없이)
    private static func trimmedSpaces(_ text: Substring) -> Substring {
        guard let start = text.firstIndex(where: { !$0.isWhitespace }), let end = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return text[start...end]
    }

    /// 사용법 결과 줄에 보일 본문 글자 수 — 넘으면 자르고 「…」
    static let usageResultLength = 30

    // MARK: 전체 보기 (R31)

    /// 「사용법」 예시 아래 줄 — 개수는 팩 항목 수(`PackSummary.itemCount`, 화면 확인 S-4처럼 쉼표)
    public static func allEntriesRow(count: Int) -> String { "전체 보기 (\(number(count))개)" }
    /// 전체 보기 화면 머리 — 꺼진 팩. 목록 행 보조줄(`statusLine`)은 끔에 배지가 없어 따로 둔다
    public static let allEntriesOffLine = "꺼져 있어서 지금은 안 떠요"

    /// 전체 보기 화면 머리 한 줄 — 꺼짐은 위 문구, 쉬는 중은 목록 행 보조줄 그대로(`statusLine`), 켬은 없다(nil)
    public static func allEntriesStatusLine(_ status: PackSummary.Status) -> String? {
        status == .off ? allEntriesOffLine : statusLine(status)
    }

    /// 목록 절 머리 — 찾는 중이면 찾은 수
    public static func allEntriesHeader(count: Int, isSearching: Bool) -> String {
        isSearching ? "찾은 채움글 \(number(count))개" : "채움글 \(number(count))개"
    }
    public static let allEntriesSearchPrompt = "단축어나 문구로 찾기"
    /// 찾은 것이 없을 때 한 줄
    public static let allEntriesNoMatch = "맞는 채움글이 없어요. 다른 말로 찾아 보세요."

    public static let deletePackButton = "팩 삭제"

    // MARK: 삭제 확인 (2-F)

    public static let cancel = "취소"

    public static func deleteTitle(name: String) -> String { "「\(name)」\(objectParticle(after: name)) 지울까요?" }

    /// 항목 수를 모르면(읽을 수 없는 팩을 복구해 stats가 0) 숫자 없이
    public static func deleteMessage(itemCount: Int) -> String {
        let subject = itemCount > 0 ? "이 팩의 채움글 \(number(itemCount))개가" : "이 팩이"
        return subject + " 이 기기에서 지워져요. 다시 쓰려면 파일을 다시 가져와야 해요."
    }

    static func label(_ action: PackChangeNotice.Action) -> String {
        switch action {
        case .confirm: "확인"
        case .close: "닫기"
        case .organize: "정리하기"
        case .importDisabled: "꺼 둔 채로 가져오기"
        case .recoverLibrary: "목록 복구"
        case .deletePack: "지우기"
        }
    }

    /// 주어 — 하나면 「이름」 + 받침에 맞는 이/가, 여럿이면 「「A」 외 n개가」(계획서 4-2절 「이름이 여럿이면」)
    static func subject(_ firstName: String, count: Int) -> String {
        count > 1 ? "「\(firstName)」 외 \(number(count - 1))개가" : "「\(firstName)」\(subjectParticle(after: firstName))"
    }

    /// 이름 뒤 주격 조사 — 마지막 글자(문장부호·이모지는 건너뛴다)가 한글이면 받침으로, 아라비아 숫자면 읽는 소리로
    /// (2·4·5·9 = 이·사·오·구 → 「가」), 그 밖(로마자 등 읽는 법을 모르는 글자)이면 「이(가)」.
    /// 계획서 표는 「○○」가로 적었지만 이름은 사용자가 정한다 — 「…팩」가처럼 틀린 조사를 보이지 않는다
    public static func subjectParticle(after name: String) -> String {
        particle(after: name, consonant: "이", vowel: "가")
    }

    /// 이름 뒤 목적격 조사 — 규칙은 주격과 같다(받침 → 「을」, 없으면 「를」, 모르면 「을(를)」). 삭제 확인(2-F)·틀 주인 안내(2-D)
    public static func objectParticle(after name: String) -> String {
        particle(after: name, consonant: "을", vowel: "를")
    }

    /// 끝말 뒤 「으로/로」 — 받침이 없거나 ㄹ 받침이면 「로」, 그 밖 받침이면 「으로」, 아라비아 숫자는 읽는 소리로(1·2·4·5·7·8·9 → 「로」),
    /// 모르면 「(으)로」. 가림 안내(「「…장」으로 끝나는 입력」, 5-C·2-E)
    public static func directionParticle(after text: String) -> String {
        guard let last = text.last(where: { $0.isLetter || $0.isNumber }),
              let scalar = last.unicodeScalars.first, last.unicodeScalars.count == 1 else { return "(으)로" }
        if (0xAC00...0xD7A3).contains(scalar.value) {
            let final = (scalar.value - 0xAC00) % 28
            return final == 0 || final == 8 ? "로" : "으로"
        }
        if last.isASCII, let digit = last.wholeNumberValue {
            return [1, 2, 4, 5, 7, 8, 9].contains(digit) ? "로" : "으로"
        }
        return "(으)로"
    }

    /// 표시 숫자 — 천 단위 쉼표(「1,300」). 화면 문구의 개수·건수는 **전부 이 함수 하나**를 지난다(화면 확인 S-4). 지역 설정과 무관하게 쉼표다
    public static func number(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var grouped = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
            grouped.append(digit)
        }
        return value < 0 ? "-" + grouped : grouped
    }

    private static func particle(after name: String, consonant: String, vowel: String) -> String {
        guard let last = name.last(where: { $0.isLetter || $0.isNumber }),
              let scalar = last.unicodeScalars.first, last.unicodeScalars.count == 1 else { return "\(consonant)(\(vowel))" }
        if (0xAC00...0xD7A3).contains(scalar.value) {
            return (scalar.value - 0xAC00) % 28 == 0 ? vowel : consonant
        }
        if last.isASCII, let digit = last.wholeNumberValue {
            return [2, 4, 5, 9].contains(digit) ? vowel : consonant
        }
        return "\(consonant)(\(vowel))"
    }
}
