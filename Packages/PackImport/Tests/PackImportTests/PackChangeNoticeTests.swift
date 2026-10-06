import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 1단계 — 사유별 알림(`PackChangeNotice`)과 문구 표(`PackNoticeCopy`).
// 기준: `docs/design-reviews/external-snippet-packs-1c-plan.md` 4-2절 A~G 표(문구는 그 표를 **글자 그대로** 옮겼다 — 고치면 이 표가 깨진다),
// 2절 G2·G7, 5절 1단계 행, 8절 #3(한도 숫자 0), PDR E표 U6(교회·성경 소재 0).

// MARK: - 시험 도구

/// 알림에 들어가는 팩 이름 — **교회·성경 소재를 쓰지 않는다(U6)**
private let names = ["p1": "사자성어 예시 팩", "p2": "회사 상용구", "p3": "상용 영어"]

private let anyEvaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [])

private func accepted(_ newlyExcluded: [String], rechecked: Bool = false) -> PackStore.CommitResult {
    .accepted(PackStore.Accepted(revision: 1, packID: nil, newlyExcluded: newlyExcluded, evaluation: anyEvaluation,
                                 rechecked: rechecked))
}

private func rejected(_ rejection: PackStore.Rejection, rechecked: Bool = false) -> PackStore.CommitResult {
    .rejected(rejection, rechecked: rechecked)
}

private func notice(_ operation: PackChangeNotice.Operation, _ result: PackStore.CommitResult,
                    overLimit: Bool = false) -> PackChangeNotice? {
    PackChangeNotice(operation, result: result, userSnippetsOverLimit: { overLimit }, packName: { names[$0] })
}

/// 4-2절 표의 한 줄
struct NoticeTableRow: CustomTestStringConvertible, Sendable {
    let id: String
    let operation: PackChangeNotice.Operation
    let result: PackStore.CommitResult
    /// 저장 전(= 거부된 지금) 내 채움글이 한도를 넘었나 — A3·D2
    var overLimit = false
    let reason: PackChangeNotice.Reason
    let title: String
    let message: String
    /// 버튼 — 화면 순서(마지막이 닫는 버튼)
    let buttons: [String]
    var testDescription: String { id }
}

/// 4-2절 표 — 문구는 계획서에서 **복사**했다. 「○○」 자리에만 이름이 들어가고 조사는 받침에 맞춘다(아래 `particle` 시험)
private let table: [NoticeTableRow] = [
    NoticeTableRow(id: "A1 내 채움글 저장 — 한도(개수 쪽)", operation: .saveUserSnippet,
        result: rejected(.gate(.baselineOverLimit([.items]))), reason: .userSaveTooMany,
        title: "저장하지 못했어요",
        message: "채움글이 너무 많아요. 안 쓰는 채움글을 지우거나 내장 팩을 끈 뒤 다시 해 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "A2 같은 건 — 길이·크기 쪽", operation: .saveUserSnippet,
        result: rejected(.gate(.baselineOverLimit([.needleChars]))), reason: .userSaveTooLong,
        title: "저장하지 못했어요",
        message: "채움글이 너무 길어요. 문구를 줄이거나 안 쓰는 채움글을 지운 뒤 다시 해 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "A3 같은 건 — 옛 초과본 상태(R21)", operation: .saveUserSnippet,
        result: rejected(.gate(.baselineOverLimit([.needleChars]))), overLimit: true, reason: .userSaveWhileOverLimit,
        title: "저장하지 못했어요",
        message: "지금은 채움글이 한도를 넘은 상태라 문구를 늘릴 수 없어요. 줄이는 수정이나 지우기만 돼요.",
        buttons: ["정리하기", "확인"]),
    NoticeTableRow(id: "B1 내장 팩 켜기 — 한도", operation: .enableBuiltIn,
        result: rejected(.gate(.baselineOverLimit([.items]))), reason: .builtInOverLimit,
        title: "켤 수 없어요",
        message: "켜면 채움글이 한도를 넘어요. 안 쓰는 채움글을 지우거나 다른 내장 팩을 끈 뒤 켜 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "B1b 내장 팩 켜기 — 내 채움글이 이미 한도 초과(2단계 추가)", operation: .enableBuiltIn,
        result: rejected(.gate(.baselineOverLimit([.items]))), overLimit: true, reason: .builtInWhileUserOverLimit,
        title: "켤 수 없어요",
        message: "내 채움글이 한도를 넘어서 지금은 내장 팩을 켤 수 없어요. 먼저 내 채움글을 정리해 주세요.",
        buttons: ["정리하기", "확인"]),
    NoticeTableRow(id: "B2 내장 팩 켜기 — 외부 팩이 밀림", operation: .enableBuiltIn,
        result: rejected(.gate(.displacesPacks(["p2"]))), reason: .builtInDisplacesPacks,
        title: "켤 수 없어요",
        message: "켜면 「회사 상용구」가 한도 밖으로 밀려요. 외부 채움글 팩을 먼저 끄거나 지운 뒤 켜 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "C1 외부 팩 켜기 — 다른 팩이 밀림", operation: .enablePack,
        result: rejected(.gate(.displacesPacks(["p2"]))), reason: .enableDisplacesPacks,
        title: "켤 수 없어요",
        message: "켜면 이 팩보다 아래에 있는 「회사 상용구」가 한도 밖으로 밀려요. 먼저 다른 팩을 끄거나 순서를 바꿔 주세요.",
        buttons: ["팩 순서 바꾸기", "확인"]),
    NoticeTableRow(id: "C2 외부 팩 켜기 — 자기 자신이 한도 밖", operation: .enablePack,
        result: rejected(.gate(.packExcluded(id: "p1", dimensions: [.needleChars]))), reason: .enableExceedsLimit,
        title: "켤 수 없어요",
        message: "켜면 한도를 넘어요. 다른 팩을 먼저 꺼 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "C2b 외부 팩 켜기 — 내 채움글이 이미 한도 초과(2단계 추가)", operation: .enablePack,
        result: rejected(.gate(.packExcluded(id: "p1", dimensions: [.needleChars]))), overLimit: true,
        reason: .enableWhileUserOverLimit,
        title: "켤 수 없어요",
        message: "내 채움글이 한도를 넘어서 외부 팩을 켤 수 없어요. 먼저 내 채움글을 정리해 주세요.",
        buttons: ["정리하기", "확인"]),
    NoticeTableRow(id: "C3 팩 교체(켜진 팩) — 한도", operation: .replacePack,
        result: rejected(.gate(.packExcluded(id: "p1", dimensions: [.bytes]))), reason: .replaceExceedsLimit,
        title: "바꿀 수 없어요",
        message: "새 파일로 바꾸면 한도를 넘어요. 다른 팩을 먼저 끄거나 지운 뒤 다시 가져와 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "C3b 팩 교체 — 내 채움글이 이미 한도 초과(2단계 추가)", operation: .replacePack,
        result: rejected(.gate(.displacesPacks(["p2"]))), overLimit: true, reason: .replaceWhileUserOverLimit,
        title: "바꿀 수 없어요",
        message: "내 채움글이 한도를 넘어서 지금은 팩을 바꿀 수 없어요. 먼저 내 채움글을 정리해 주세요.",
        buttons: ["정리하기", "확인"]),
    NoticeTableRow(id: "D1 가져오기 — 한도", operation: .importPack,
        result: rejected(.gate(.packExcluded(id: "p1", dimensions: [.needleChars]))), reason: .importExceedsLimit,
        title: "가져올 수 없어요",
        message: "켜진 채움글을 모두 합치면 한도를 넘어요. 다른 외부 팩을 끄거나 지운 뒤 다시 가져와 주세요.",
        buttons: ["꺼 둔 채로 가져오기", "닫기"]),
    NoticeTableRow(id: "D2 가져오기 — 내 채움글이 이미 한도 초과", operation: .importPack,
        result: rejected(.gate(.packExcluded(id: "p1", dimensions: [.needleChars]))), overLimit: true,
        reason: .importWhileUserOverLimit,
        title: "가져올 수 없어요",
        message: "내 채움글이 한도를 넘어서 외부 팩을 쓸 수 없어요. 먼저 내 채움글을 정리해 주세요. 꺼 둔 채로는 가져올 수 있어요.",
        buttons: ["정리하기", "꺼 둔 채로 가져오기", "닫기"]),
    NoticeTableRow(id: "D3 가져오기 — 팩이 너무 많아요(「꺼 둔 채로」 없음)", operation: .importPack,
        result: rejected(.gate(.tooManyPacks)), reason: .importTooManyPacks,
        title: "더 가져올 수 없어요",
        message: "외부 채움글 팩이 너무 많아요. 안 쓰는 팩을 지운 뒤 다시 가져와 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "E1 목록 손상", operation: .saveUserSnippet,
        result: rejected(.libraryUnreadable), reason: .libraryUnreadable,
        title: "채움글을 바꿀 수 없어요",
        message: "외부 채움글 목록을 읽을 수 없어서 지금은 채움글을 저장하거나 지울 수 없어요. 가져온 팩 파일은 지우지 않았어요. "
            + "키보드에서는 지금 쓰던 채움글이 그대로 떠요. 목록을 복구하면 다시 바꿀 수 있어요.",
        buttons: ["목록 복구", "확인"]),
    NoticeTableRow(id: "E2 읽을 수 없는 팩 켜기", operation: .enablePack,
        result: rejected(.packUnavailable("p1")), reason: .packUnavailable,
        title: "켤 수 없어요",
        message: "이 팩의 파일을 읽을 수 없어요. 같은 이름으로 파일을 다시 가져와 바꾸거나 팩을 지워 주세요.",
        buttons: ["지우기", "확인"]),
    NoticeTableRow(id: "F1 저장 실패", operation: .saveUserSnippet,
        result: rejected(.writeFailed), reason: .writeFailed,
        title: "저장하지 못했어요",
        message: "기기에 쓰지 못했어요. 저장 공간을 확인한 뒤 다시 해 주세요. 원래 있던 채움글은 그대로예요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "F2 그 사이 바뀜 — notFound", operation: .deleteUserSnippet,
        result: rejected(.notFound), reason: .changedMeanwhile,
        title: "목록이 바뀌었어요",
        message: "그 사이 채움글이 바뀌었어요. 화면을 다시 열어 확인해 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "F2 그 사이 바뀜 — invalidOrder", operation: .reorderPacks,
        result: rejected(.invalidOrder), reason: .changedMeanwhile,
        title: "목록이 바뀌었어요",
        message: "그 사이 채움글이 바뀌었어요. 화면을 다시 열어 확인해 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "F3 앱 내부 오류 — moreThanOneItem", operation: .saveUserSnippet,
        result: rejected(.moreThanOneItem), reason: .internalError,
        title: "저장하지 못했어요",
        message: "문제가 생겨서 저장하지 못했어요. 앱을 다시 열어 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "F3 앱 내부 오류 — invalidDisabledImport", operation: .importDisabledPack,
        result: rejected(.gate(.invalidDisabledImport(id: "p1"))), reason: .internalError,
        title: "저장하지 못했어요",
        message: "문제가 생겨서 저장하지 못했어요. 앱을 다시 열어 주세요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "G1 받았지만 팩이 쉬게 됨(1개, AC-4)", operation: .saveUserSnippet,
        result: accepted(["p2"]), reason: .packRested,
        title: "저장했어요",
        message: "대신 「회사 상용구」가 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요.",
        buttons: ["확인"]),
    NoticeTableRow(id: "G2 같은 — 2개 이상", operation: .saveUserSnippet,
        result: accepted(["p1", "p2", "p3"]), reason: .packsRested,
        title: "저장했어요",
        message: "대신 「사자성어 예시 팩」 외 2개 팩이 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 팩 목록에서 확인해 주세요.",
        buttons: ["확인"])
]

private func buttons(_ notice: PackChangeNotice) -> [String] {
    (notice.actions + [notice.dismiss]).map(\.label)
}

// MARK: - 4-2절 표

@Suite("외부 채움글 1-c 1단계 — 사유별 알림 (4-2절 A~G 표 · G2·G7)")
struct PackChangeNoticeTableTests {

    @Test("★ 4-2절 표 — 사유·제목·문구·버튼이 계획서 표와 글자까지 같다", arguments: table)
    func row(_ row: NoticeTableRow) throws {
        let made = try #require(notice(row.operation, row.result, overLimit: row.overLimit))
        #expect(made.reason == row.reason)
        #expect(made.title == row.title)
        #expect(made.message == row.message)
        #expect(buttons(made) == row.buttons)
        #expect(made.isRejection == !row.result.isAccepted)
    }

    @Test("표가 사유 21종을 모두 덮는다(1단계 18 + 2단계 B1b·C2b·C3b, G3는 화면 줄이라 따로)")
    func tableCoversEveryReason() {
        #expect(Set(table.map(\.reason)) == Set(PackChangeNotice.Reason.allCases))
        #expect(PackChangeNotice.Reason.allCases.count == 21)
    }

    @Test("★ G7 — 같은 게이트 거부도 무엇을 하다 막혔는지로 갈린다(「한도」 한 갈래로 묶지 않는다)")
    func sameRejectionDifferentOperation() {
        let displaced = rejected(.gate(.displacesPacks(["p2"])))
        #expect(notice(.enableBuiltIn, displaced)?.reason == .builtInDisplacesPacks)
        #expect(notice(.enablePack, displaced)?.reason == .enableDisplacesPacks)
        #expect(notice(.replacePack, displaced)?.reason == .replaceExceedsLimit)
        let excluded = rejected(.gate(.packExcluded(id: "p1", dimensions: [.items])))
        #expect(notice(.enablePack, excluded)?.reason == .enableExceedsLimit)
        #expect(notice(.replacePack, excluded)?.reason == .replaceExceedsLimit)
        #expect(notice(.importPack, excluded)?.reason == .importExceedsLimit)
        let baseline = rejected(.gate(.baselineOverLimit([.items])))
        #expect(notice(.enableBuiltIn, baseline)?.reason == .builtInOverLimit)
        #expect(notice(.enableBuiltIn, baseline, overLimit: true)?.reason == .builtInWhileUserOverLimit, "B1b — 꺼도 안 풀린다")
        #expect(notice(.saveUserSnippet, baseline, overLimit: true)?.reason == .userSaveWhileOverLimit)
        // 2단계 — 내 채움글이 이미 넘었으면 「다른 팩을 끄라」는 틀린 안내다(B1b·C2b·C3b, 1단계 보고 5번)
        #expect(notice(.enablePack, excluded, overLimit: true)?.reason == .enableWhileUserOverLimit)
        #expect(notice(.replacePack, excluded, overLimit: true)?.reason == .replaceWhileUserOverLimit)
        #expect(notice(.replacePack, displaced, overLimit: true)?.reason == .replaceWhileUserOverLimit)
        #expect(notice(.enablePack, displaced, overLimit: true)?.reason == .enableDisplacesPacks, "밀림(C1)은 한도 상태를 보지 않는다")
        // 꺼 둔 채로 가져오기도 팩 수에서는 막힌다 — D3, 「꺼 둔 채로」 버튼 없음(8절 #5)
        let tooMany = notice(.importDisabledPack, rejected(.gate(.tooManyPacks)))
        #expect(tooMany?.reason == .importTooManyPacks)
        #expect(tooMany?.actions.contains(.importDisabled) == false)
    }

    @Test("A1·A2 — 넘은 항목에 개수 쪽(items·needleCount)이 있으면 A1(지워야 풀린다), 길이·크기 쪽만이면 A2",
          arguments: [
            ([PackBudgetDimension.items], PackChangeNotice.Reason.userSaveTooMany),
            ([.needleCount], .userSaveTooMany),
            ([.needleChars, .items], .userSaveTooMany),
            ([.bytes, .needleCount], .userSaveTooMany),
            ([.needleChars], .userSaveTooLong),
            ([.bytes], .userSaveTooLong),
            ([.needleChars, .bytes], .userSaveTooLong),
            ([.peak], .userSaveTooLong)
          ])
    func countOrLength(_ dimensions: [PackBudgetDimension], _ reason: PackChangeNotice.Reason) {
        #expect(notice(.saveUserSnippet, rejected(.gate(.baselineOverLimit(dimensions))))?.reason == reason)
    }

    @Test("★ 모든 거부는 알림이 있다 — 사유가 하나라도 빠지면 화면이 조용해진다", arguments: PackChangeNotice.Operation.allCases)
    func everyRejectionHasNotice(_ operation: PackChangeNotice.Operation) {
        for rejection in allRejections {
            let made = notice(operation, rejected(rejection))
            #expect(made != nil, "\(rejection)")
            #expect(made?.isRejection == true)
            #expect(made?.dismiss == .confirm || made?.dismiss == .close)
        }
    }

    @Test("★ codex #8 — 받은 결과의 newlyExcluded를 버리지 않는다: 1개면 G1, 여럿이면 G2, 없으면 알림 없음")
    func acceptedKeepsNewlyExcluded() {
        #expect(notice(.saveUserSnippet, accepted([])) == nil)
        #expect(notice(.reorderPacks, accepted(["p3"]))?.reason == .packRested, "어느 변경이든 쉬게 된 팩은 알린다")
        #expect(notice(.saveUserSnippet, accepted(["p3"]))?.packIDs == ["p3"])
        #expect(notice(.saveUserSnippet, accepted(["p1", "p3"]))?.packIDs == ["p1", "p3"])
        #expect(notice(.saveUserSnippet, accepted(["p1", "p3"]))?.message.hasPrefix("대신 「사자성어 예시 팩」 외 1개 팩이") == true)
    }

    @Test("★ codex #8 — rechecked로 거부됐으면 문구 앞에 한 줄(AC-3). 받은 결과·F2에는 붙이지 않는다")
    func recheckedLine() {
        let made = notice(.saveUserSnippet, rejected(.gate(.baselineOverLimit([.items])), rechecked: true))
        #expect(made?.message == "그 사이 채움글이 바뀌어서 다시 확인했어요.\n"
                + "채움글이 너무 많아요. 안 쓰는 채움글을 지우거나 내장 팩을 끈 뒤 다시 해 주세요.")
        #expect(made?.rechecked == true)
        #expect(notice(.importPack, rejected(.gate(.tooManyPacks), rechecked: true))?.message
                .hasPrefix("그 사이 채움글이 바뀌어서 다시 확인했어요.\n외부 채움글 팩이") == true)
        // F2는 이미 「그 사이 … 바뀌었어요」라 같은 말을 두 번 하지 않는다
        #expect(notice(.deleteUserSnippet, rejected(.notFound, rechecked: true))?.message
                == "그 사이 채움글이 바뀌었어요. 화면을 다시 열어 확인해 주세요.")
        #expect(notice(.saveUserSnippet, accepted([], rechecked: true)) == nil, "받았으면 알릴 것이 없다")
        #expect(notice(.saveUserSnippet, accepted(["p2"], rechecked: true))?.message.hasPrefix("대신") == true)
    }

    @Test("이름이 여럿이면 「A」 외 n개 — 밀린 팩이 둘 이상인 켜기 거부")
    func severalNames() {
        #expect(notice(.enableBuiltIn, rejected(.gate(.displacesPacks(["p1", "p2", "p3"]))))?.message
                == "켜면 「사자성어 예시 팩」 외 2개가 한도 밖으로 밀려요. 외부 채움글 팩을 먼저 끄거나 지운 뒤 켜 주세요.")
        #expect(notice(.enablePack, rejected(.gate(.displacesPacks(["p1", "p2"]))))?.packIDs == ["p1", "p2"])
    }

    @Test("★ 조사는 이름의 받침을 따른다 — 「팩」이·「상용구」가, 숫자는 읽는 소리, 모르면 이(가)",
          arguments: [
            ("사자성어 예시 팩", "이"), ("회사 상용구", "가"), ("상용 영어", "가"), ("인사말!", "이"),
            ("주소 2", "가"), ("주소 3", "이"), ("주소 10", "이"), ("주소 4)", "가"),
            ("Office", "이(가)"), ("😀", "이(가)")
          ])
    func particle(_ name: String, _ expected: String) {
        #expect(PackNoticeCopy.subjectParticle(after: name) == expected)
    }

    @Test("이름을 모르는 팩(지워졌거나 표시 칸·변환본이 없음)은 「이름 없는 팩」")
    func unknownName() {
        let made = PackChangeNotice(.saveUserSnippet, result: accepted(["없음"]), userSnippetsOverLimit: { false },
                                    packName: { _ in nil })
        #expect(made?.message == "대신 「이름 없는 팩」이 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요.")
    }

    @Test("저장본 조회는 필요할 때만 — 한도 상태는 A·B1·C2·C3·D에서만, 이름은 이름이 들어가는 알림에서만")
    func lazyLookups() {
        var overLimitReads = 0
        var nameReads = 0
        func make(_ operation: PackChangeNotice.Operation, _ result: PackStore.CommitResult) {
            _ = PackChangeNotice(operation, result: result,
                                 userSnippetsOverLimit: { overLimitReads += 1; return false },
                                 packName: { nameReads += 1; return names[$0] })
        }
        make(.saveUserSnippet, rejected(.writeFailed))
        make(.saveUserSnippet, accepted([]))
        make(.enablePack, rejected(.packUnavailable("p1")))
        make(.importPack, rejected(.gate(.tooManyPacks)))
        #expect(overLimitReads == 0 && nameReads == 0)
        make(.saveUserSnippet, rejected(.gate(.baselineOverLimit([.items]))))
        make(.importPack, rejected(.gate(.packExcluded(id: "p1", dimensions: []))))
        make(.enableBuiltIn, rejected(.gate(.baselineOverLimit([.items]))))
        make(.enablePack, rejected(.gate(.packExcluded(id: "p1", dimensions: []))))
        make(.replacePack, rejected(.gate(.packExcluded(id: "p1", dimensions: []))))
        #expect(overLimitReads == 5 && nameReads == 0)
        make(.enableBuiltIn, rejected(.gate(.displacesPacks(["p1"]))))
        #expect(overLimitReads == 5 && nameReads == 1, "B2는 이름만, 한도 상태는 보지 않는다")
        make(.saveUserSnippet, accepted(["p1", "p2", "p3"]))
        #expect(nameReads == 2, "G2는 첫 이름만 쓴다")
    }

    @Test("G3 — 순서 변경 전 사전 안내 줄(트리거는 3단계 PackImpact)")
    func reorderWarning() {
        #expect(PackNoticeCopy.reorderWarning(names: ["회사 상용구"])
                == "이렇게 바꾸면 「회사 상용구」가 한도 밖으로 밀려서 쉬어요.")
        #expect(PackNoticeCopy.reorderWarning(names: ["사자성어 예시 팩", "상용 영어"])
                == "이렇게 바꾸면 「사자성어 예시 팩」 외 1개가 한도 밖으로 밀려서 쉬어요.")
    }
}

/// 모든 거부 사유 — `PackStore.Rejection`에 사유가 늘면 아래 `switch`가 컴파일되지 않아 이 목록과 4-2절 표를 함께 고치게 된다
private let allRejections: [PackStore.Rejection] = {
    let all: [PackStore.Rejection] = [
        .gate(.packExcluded(id: "p1", dimensions: [.items])), .gate(.displacesPacks(["p2"])),
        .gate(.baselineOverLimit([.needleChars])), .gate(.tooManyPacks), .gate(.invalidDisabledImport(id: "p1")),
        .moreThanOneItem, .notFound, .invalidOrder, .writeFailed, .libraryUnreadable, .packUnavailable("p1")
    ]
    for rejection in all {
        switch rejection {
        case .gate(let gate):
            switch gate {
            case .packExcluded, .displacesPacks, .baselineOverLimit, .tooManyPacks, .invalidDisabledImport: break
            }
        case .moreThanOneItem, .notFound, .invalidOrder, .writeFailed, .libraryUnreadable, .packUnavailable: break
        }
    }
    return all
}()

// MARK: - 문구 검사 (④ — U6·금칙어·한도 숫자 0)

/// 교회·성경 소재(U6) — 화면 문구·예시에 쓰지 않는다
private let churchWords = [
    "성경", "찬송", "찬양", "성가", "예배", "교회", "기도", "설교", "목사", "장로", "주일", "복음", "하나님", "하느님",
    "예수", "그리스도", "말씀", "구절", "창세기", "시편", "요한", "개역", "아멘", "할렐루야", "성도", "선교", "십자가", "성탄"
]
/// 금칙어 — 「트리거」(용어는 「단축어」, CLAUDE.md) · 「잠시 뒤」(틀린 안내, 4-2절) · xlsx·엑셀(1.3.0은 CSV판, AC-35)
private let bannedWords = ["트리거", "잠시 뒤", "xlsx", "XLSX", "엑셀"]

/// 1단계가 내는 모든 문구 — 표의 알림 전부(rechecked 줄 포함)·G3 줄·버튼·이름 대체어
private let everyCopy: [String] = {
    var texts = table.flatMap { row -> [String] in
        let plain = notice(row.operation, row.result, overLimit: row.overLimit)
        let recheckedResult: PackStore.CommitResult
        switch row.result {
        case .rejected(let rejection, _): recheckedResult = .rejected(rejection, rechecked: true)
        case .accepted: recheckedResult = row.result
        }
        let again = notice(row.operation, recheckedResult, overLimit: row.overLimit)
        return [plain, again].compactMap { $0 }.flatMap { [$0.title, $0.message] + buttons($0) }
    }
    texts += PackChangeNotice.Action.allCases.map(\.label)
    texts += [PackNoticeCopy.reorderWarning(names: ["회사 상용구"]), PackNoticeCopy.reorderWarning(names: ["회사 상용구", "상용 영어"]),
              PackNoticeCopy.recheckedLine, PackNoticeCopy.unnamedPack]
    // 2단계 — 상태 표시(4-3절)·배너 셋·정리 화면·복구 시트. 개수는 표시 값이라 `countSentinels`로 넣는다
    texts += [PackSummary.Status.on, .off, .restingOverLimit, .restingForUserSnippets, .unavailable]
        .compactMap(PackNoticeCopy.statusLine)
    texts += [PackNoticeCopy.unavailablePackDetail, PackNoticeCopy.overLimitBanner(loadableCount: 37),
              PackNoticeCopy.unavailablePacksBanner(names: ["회사 상용구"]),
              PackNoticeCopy.unavailablePacksBanner(names: ["사자성어 예시 팩", "회사 상용구", "상용 영어"]),
              PackNoticeCopy.cleanupTitle, PackNoticeCopy.cleanupBoundary, PackNoticeCopy.cleanupFooter, PackNoticeCopy.cleanupDoneTitle, PackNoticeCopy.cleanupDoneMessage,
              PackNoticeCopy.recoveryTitle, PackNoticeCopy.recoveryMessage(packCount: 41), PackNoticeCopy.recoveryMessage(packCount: 0),
              PackNoticeCopy.recoveryConfirm, PackNoticeCopy.recoveryCancel,
              PackNoticeCopy.recoveredTitle, PackNoticeCopy.recoveredMessage(packCount: 41), PackNoticeCopy.recoveredMessage(packCount: 0),
              PackNoticeCopy.recoveryFailedTitle, PackNoticeCopy.recoveryFailedMessage]
    texts += [PackLibraryStatus.unreadable, .corrupt, .unknownSchema].compactMap(PackNoticeCopy.libraryBanner)
    return texts
}()

/// 문구에 들어가는 **표시 개수**(한도 숫자가 아니다) — 숫자 검사에서 이것만 지운다
private let countSentinels = ["37개", "41개"]

@Suite("외부 채움글 1-c 1단계 — 문구 표 검사 (U6·금칙어·한도 숫자 0)")
struct PackNoticeCopyLintTests {

    @Test("★ U6 — 교회·성경 소재 0")
    func noChurchWords() {
        for text in everyCopy {
            for word in churchWords { #expect(!text.contains(word), "「\(word)」: \(text)") }
        }
    }

    @Test("★ 금칙어 0 — 트리거·잠시 뒤·xlsx·엑셀")
    func noBannedWords() {
        for text in everyCopy {
            for word in bannedWords { #expect(!text.contains(word), "「\(word)」: \(text)") }
        }
    }

    @Test("★ 8절 #3 — 한도 숫자를 쓰지 않는다: 숫자는 「외 n개」의 개수뿐")
    func noLimitNumbers() {
        for text in everyCopy {
            var withoutCount = text.replacingOccurrences(of: #"외 \d+개"#, with: "", options: .regularExpression)
            for sentinel in countSentinels { withoutCount = withoutCount.replacingOccurrences(of: sentinel, with: "") }
            #expect(!withoutCount.contains { $0.isNumber }, "\(text)")
        }
    }

    @Test("해요체 — 문장은 「요.」로 끝난다(제목·버튼 제외)")
    func politeEnding() {
        for row in table {
            guard let made = notice(row.operation, row.result, overLimit: row.overLimit) else { continue }
            #expect(made.message.hasSuffix("요."), "\(row.id)")
            #expect(made.title.hasSuffix("요"), "\(row.id)")
        }
    }
}

// MARK: - 2단계 문구 (4-3절 상태 표시 · 배너 · 정리 · 복구)

@Suite("외부 채움글 1-c 2단계 — 상태 표시·배너·정리·복구 문구 (4-3절)")
struct PackNoticeCopyStage2Tests {

    @Test("★ 4-3절 — 목록 행 보조줄: 켬·끔은 배지 없음, 나머지 셋은 표 그대로")
    func statusLines() {
        #expect(PackNoticeCopy.statusLine(.on) == nil)
        #expect(PackNoticeCopy.statusLine(.off) == nil)
        #expect(PackNoticeCopy.statusLine(.restingOverLimit) == "쉬는 중 · 한도를 넘어 지금은 안 떠요")
        #expect(PackNoticeCopy.statusLine(.restingForUserSnippets) == "쉬는 중 · 내 채움글을 정리하면 다시 떠요")
        #expect(PackNoticeCopy.statusLine(.unavailable) == "읽을 수 없어요 · 다시 가져오거나 지워 주세요")
        #expect(PackNoticeCopy.unavailablePackDetail
                == "이 팩의 파일을 읽을 수 없어요. 같은 이름으로 파일을 다시 가져오면 바꿀 수 있어요. 지울 수도 있어요.")
    }

    @Test("★ 4-3절 — 배너 ㉠(한도 초과)·㉡(목록 손상 — 낯선 버전은 한 줄 더)")
    func banners() {
        #expect(PackNoticeCopy.overLimitBanner(loadableCount: 12)
                == "내 채움글이 한도를 넘어서 앞의 12개만 키보드에 떠요. 나머지와 외부 팩은 지금 안 떠요. 지운 것은 없어요.")
        let damaged = "외부 채움글 목록을 읽을 수 없어요. 가져온 팩 파일은 지우지 않았어요. 복구하기 전에는 채움글을 저장하거나 지울 수 없어요."
        #expect(PackNoticeCopy.libraryBanner(.unreadable) == damaged)
        #expect(PackNoticeCopy.libraryBanner(.corrupt) == damaged)
        #expect(PackNoticeCopy.libraryBanner(.unknownSchema) == damaged + "\n"
                + "새 버전의 글쇠에서 만든 목록 같아요. 앱을 최신 버전으로 올리면 다시 읽힐 수 있어요. 복구하면 이 기기의 팩 목록을 다시 만들어요.")
        #expect(PackNoticeCopy.libraryBanner(.readable) == nil)
    }

    @Test("배너 ㉢(읽을 수 없는 팩) — 이름 뒤는 「의」라 받침과 무관, 여럿이면 「A」 외 n개 팩의")
    func unavailableBanner() {
        #expect(PackNoticeCopy.unavailablePacksBanner(names: ["사자성어 예시 팩"])
                == "「사자성어 예시 팩」의 파일을 읽을 수 없어서 이 팩은 지금 안 떠요. 같은 이름으로 파일을 다시 가져오면 바꿀 수 있어요. 지울 수도 있어요.")
        #expect(PackNoticeCopy.unavailablePacksBanner(names: ["회사 상용구", "상용 영어"])
                == "「회사 상용구」 외 1개 팩의 파일을 읽을 수 없어서 지금 안 떠요. 같은 이름으로 파일을 다시 가져오면 바꿀 수 있어요. 지울 수도 있어요.")
    }

    @Test("★ 4-3절 — 정리 화면: 경계 줄·풋터·끝 알림")
    func cleanup() {
        #expect(PackNoticeCopy.cleanupBoundary == "여기부터는 지금 안 떠요")
        #expect(PackNoticeCopy.cleanupFooter == "지우면 되돌릴 수 없어요. 한도 안으로 들어오면 쉬던 팩이 다시 떠요.")
        #expect(PackNoticeCopy.cleanupDoneMessage == "이제 모두 쓸 수 있어요. 쉬던 팩이 한도 안이면 다시 떠요.")
    }

    @Test("★ R24 — 복구 확인 시트: 4-3절 문구 + 「틀·단축어 주인이 바뀔 수 있어요」 한 줄, 끝 알림")
    func recoverySheet() {
        #expect(PackNoticeCopy.recoveryTitle == "목록을 복구할까요?")
        #expect(PackNoticeCopy.recoveryMessage(packCount: 3)
                == "가져온 팩 3개를 찾았어요. 순서와 켬/끔은 알 수 없어서 모두 꺼진 채로 불러와요. 쓸 팩은 직접 켜 주세요. 원래 목록 파일은 따로 보관해요.\n"
                + "팩 순서가 예전과 달라질 수 있어서, 같은 틀이나 단축어를 다른 팩이 쓰게 될 수 있어요.")
        #expect(PackNoticeCopy.recoveryConfirm == "복구" && PackNoticeCopy.recoveryCancel == "취소")
        #expect(PackNoticeCopy.recoveredMessage(packCount: 3) == "팩 3개를 불러왔어요. 모두 꺼져 있어요.")
        // 팩 파일이 하나도 없을 때 — 「0개를 찾았어요」로 쓰지 않는다
        #expect(!PackNoticeCopy.recoveryMessage(packCount: 0).contains("0"))
        #expect(!PackNoticeCopy.recoveredMessage(packCount: 0).contains("0"))
    }
}
