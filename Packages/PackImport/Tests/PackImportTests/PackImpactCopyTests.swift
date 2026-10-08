import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 3단계 문구 — 외부 채움글 절(2-B·2-C)·팩 상세(2-E·U1)·삭제 확인(2-F). 순서 화면(2-D·2-G)과 사전 안내(G3)는
// R30에서 없앴다 — 순서는 목록에서 길게 눌러 끌어 바꾼다(`PackListReorderTests`).
// 기준: 시안 `docs/design/external-snippet-packs/index.html` 2절·U1 컷의 화면 글자(**글자 그대로** 옮겼다), 계획서 4-2·4-3절.
// 이름은 사용자가 정한다 — 조사는 받침을 따른다. 한도 숫자 검사는 `PackChangeNoticeTests`의 `stage1To3Copy`가, U6·금칙어·xlsx 검사는
// `PackCopyLintTests`(6단계 — 한 곳)가 이 목록(`stage3Copy`)까지 돈다.

// MARK: - 시험 도구

private func summary(_ id: String, _ name: String?, mode: ExternalPack.Mode?, count: Int, titleFormat: String? = nil,
                     enabled: Bool = true, status: PackSummary.Status = .on) -> PackSummary {
    PackSummary(id: id, name: name, mode: mode, itemCount: count, titleFormat: titleFormat, isEnabled: enabled, status: status)
}

private let sajaseongeo = summary("a", "사자성어 예시 팩", mode: .numbered, count: 37, titleFormat: "사자성어 {n}번")
private let examplePack = summary("b", "예시 번호 팩", mode: .numbered, count: 41, titleFormat: "성어 {n}번")
private let company = summary("c", "우리 회사 상용구", mode: .phrases, count: 41)
private let names = ["a": "사자성어 예시 팩", "b": "예시 번호 팩", "c": "우리 회사 상용구"]
private func name(_ id: String) -> String { names[id] ?? PackNoticeCopy.unnamedPack }

@Suite("외부 채움글 1-c 3단계 — 문구 (2-B·2-C · 2-E·2-F · U1)")
struct PackImpactCopyTests {

    @Test("★ 2-B·2-C — 절 제목·추가 줄·빈 상태 풋터(두 판)·「내 채움글 (우선순위)」 줄(목록 풋터·머리글 버튼은 없다 — R30)")
    func sectionCopy() {
        #expect(PackNoticeCopy.externalSectionTitle == "외부 채움글")
        #expect(PackNoticeCopy.addPack == "외부 채움글 추가")
        #expect(PackCopySet.$previewing.withValue(.csv) { PackNoticeCopy.emptyListFooter }
                == "CSV 파일로 만든 채움글 묶음(팩)을 가져와요. 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요.")
        // 지금 판(1.3.0 — xlsx 중심판, R38)
        #expect(PackNoticeCopy.emptyListFooter
                == "엑셀 파일로 만든 채움글 묶음(팩)을 가져와요. 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요.")
        // 2-C 목록 풋터(「위에 있는 줄이 먼저 떠요 …」)는 뺐다 — 팩이 있으면 풋터가 없다(사장님 실기 2026-10-07, `ExternalSectionFooterTests`)
        #expect(PackNoticeCopy.userSlotTitle == "내 채움글 (우선순위)")
        #expect(PackNoticeCopy.userSlotDetail == "길게 눌러 끌면 우선순위가 바뀌어요 · 문구는 아래 「내 채움글」 절에서")
        #expect(PackNoticeCopy.enabledValue == "켬" && PackNoticeCopy.disabledValue == "끔")
        // R30 — 목록 줄을 VoiceOver로 옮기는 동작(길게 눌러 끌기 대신)
        #expect(PackNoticeCopy.moveUpAction == "위로 옮기기" && PackNoticeCopy.moveDownAction == "아래로 옮기기")
    }

    @Test("★ 2-C 행 — 종류 · 항목 수 · 대표 틀(번호형만). 종류를 모르면 줄이 없다")
    func rowDetail() {
        #expect(PackNoticeCopy.packRowDetail(sajaseongeo) == "번호형 · 37개 · 사자성어 {n}번")
        #expect(PackNoticeCopy.packRowDetail(company) == "문구형 · 41개")
        #expect(PackNoticeCopy.packKind(sajaseongeo) == "번호형 · 37개")
        #expect(PackNoticeCopy.packRowDetail(summary("x", nil, mode: nil, count: 0, status: .unavailable)) == nil)
    }

    @Test("★ 2-E — 팩 상세: 스위치·정보·틀 상태 배지와 설명 줄·풋터·사용법(결과는 본문 첫 줄)·삭제")
    func detailCopy() {
        #expect(PackNoticeCopy.useToggle == "이 팩 사용")
        #expect(PackNoticeCopy.infoHeader == "정보" && PackNoticeCopy.kindLabel == "종류" && PackNoticeCopy.licenseLabel == "출처")
        #expect(PackNoticeCopy.infoFooter == "출처는 가져올 때 확인한 문구 그대로예요.")   // R27
        #expect(PackNoticeCopy.templatesHeader == "단축어 틀")
        #expect(PackNoticeCopy.templatesFooter
                == "같은 틀을 두 팩이 쓰면 위에 있는 팩이 가져요. 고유한 앞 글자(예: 고사성어 {n}번)를 쓰면 겹치지 않아요.")
        #expect(PackNoticeCopy.templatesEditHint   // 틀 편집은 다시 가져오기 한 길(U3) — 그 길을 알려 준다(사장님 2026-10-08)
                == "틀을 고치거나 더하려면 파일을 다시 가져와요. 가져오기 화면에서 틀을 고치고 「바꾸기」를 고르면 목록 자리와 켬/끔은 그대로예요.")
        #expect(PackNoticeCopy.patternBadge(.owned(sharedWith: [])) == "사용 중")
        #expect(PackNoticeCopy.patternBadge(.outranked(by: "a")) == "뒤 순서")
        #expect(PackNoticeCopy.patternBadge(.shadowed(by: ["장"])) == "가려짐")
        // 주어는 뜨는 문구 — 「이 팩이 써요」는 「이 팩을 써요」로 읽혔다(사장님 실기 2026-10-07)
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: []), name: name) == "이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b"]), name: name) == "아래 「예시 번호 팩」도 같은 틀이지만 위에 있는 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b", "c"]), name: name)
                == "아래 「예시 번호 팩」 외 1개 팩도 같은 틀이지만 위에 있는 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.outranked(by: "a"), name: name) == "같은 틀이라 위에 있는 「사자성어 예시 팩」 문구가 먼저 떠요")
        // 화면 확인 S-3 — 가림은 그 끝말로 끝나는 입력에서만(「이 틀은 안 떠요」는 범위 과장)
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["장"]), name: name) == "「…장」으로 끝나는 입력에서는 단축어 「장」 문구가 먼저 떠요")
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["번호3번", "번"]), name: name)
                    == "「…번호3번」 등으로 끝나는 입력에서는 단축어 「번호3번」 외 1개 문구가 먼저 떠요")
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["자"]), name: name) == "「…자」로 끝나는 입력에서는 단축어 「자」 문구가 먼저 떠요")
        for status: PackStanding.PatternStatus in [.owned(sharedWith: []), .owned(sharedWith: ["b"]), .outranked(by: "a"), .shadowed(by: ["장"])] {
            let line = PackNoticeCopy.patternLine(status, name: name)
            #expect(!line.contains("써요") && line.contains("문구가"), "\(line)")
        }
        #expect(PackNoticeCopy.usageHeader == "사용법")
        #expect(PackNoticeCopy.usageFooter == "단축어를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 단축어가 전문으로 바뀌어요.")
        #expect(PackNoticeCopy.usageResult("예시 제목 둘") == "→ 예시 제목 둘")   // 5-A 「이렇게 칩이 떠요」 — 칩 제목
        // 사용법·「이렇게 써 보세요」 결과는 칩 제목이 아니라 들어가는 문구(본문) — 여러 줄이면 첫 줄 + 「…」, 길면 자르고 「…」(사장님 실기 2026-10-07)
        #expect(PackNoticeCopy.usageResult(body: "예시 본문 한 줄") == "→ 예시 본문 한 줄")
        #expect(PackNoticeCopy.usageResult(body: "안녕하세요.\n오늘 회의를 시작하겠습니다.") == "→ 안녕하세요. 오늘 회의를 시작하겠습니다.", "여러 줄은 빈칸으로 잇는다")
        #expect(PackNoticeCopy.usageResult(body: "안녕하세요.\n오늘 회의를 시작하겠습니다.\n자료는 메일로 보내 드렸습니다.") == "→ 안녕하세요. 오늘 회의를 시작하겠습니다. 자료는 메일로…", "이은 뒤 길면 30자에서 자른다")
        #expect(PackNoticeCopy.usageResult(body: "\n  첫 줄 \r\n\n") == "→ 첫 줄", "빈 줄·앞뒤 공백은 줄로 치지 않는다")
        let thirty = String(repeating: "가", count: PackNoticeCopy.usageResultLength)
        #expect(PackNoticeCopy.usageResult(body: thirty) == "→ " + thirty, "딱 맞으면 자르지 않는다")
        #expect(PackNoticeCopy.usageResult(body: thirty + "나") == "→ " + thirty + "…")
        #expect(PackNoticeCopy.usageResult(body: String(thirty.dropLast()) + " 나다") == "→ " + String(thirty.dropLast()) + "…", "자른 끝의 공백은 뗀다")
        // 경계는 상수가 아니라 글자로 고정한다 — 위 줄들은 길이를 상수에서 내 상수를 바꾸면 함께 따라간다(검증 N03). 30·31번째 모두 공백이 아니다
        #expect(PackNoticeCopy.usageResult(body: "123456789가123456789나123456789다") == "→ 123456789가123456789나123456789다", "30자는 자르지 않는다")
        #expect(PackNoticeCopy.usageResult(body: "123456789가123456789나123456789다라마") == "→ 123456789가123456789나123456789다…", "31자부터 30자로 자른다")
        #expect(PackNoticeCopy.deletePackButton == "팩 삭제")
    }

    @Test("★ U1 — 지금 안 뜨는 단축어: 머리줄·행 설명·배지·풋터(위 줄이 하나면 그 이름, 여럿이면 「더 위로」 — 올리는 길은 목록 길게 눌러 끌기, R30)")
    func hiddenTriggerCopy() {
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 37) == "지금 안 뜨는 단축어 37개")
        #expect(PackNoticeCopy.hiddenTriggerLine(owner: .userSnippets, name: name) == "위에 있는 「내 채움글」이 먼저 떠요")
        #expect(PackNoticeCopy.hiddenTriggerLine(owner: .pack("c"), name: name) == "위에 있는 「우리 회사 상용구」가 먼저 떠요")
        #expect(PackNoticeCopy.hiddenTriggerBadge == "뒤 순서")
        #expect(PackNoticeCopy.hiddenTriggersFooter(owners: [.userSnippets, .userSnippets], name: name)
                == "목록에서 위에 있는 쪽이 먼저 떠요. 이 팩 문구를 쓰려면 「외부 채움글」 목록에서 이 팩을 길게 눌러 「내 채움글」 위로 올려 주세요.")
        #expect(PackNoticeCopy.hiddenTriggersFooter(owners: [.userSnippets, .pack("c")], name: name)
                == "목록에서 위에 있는 쪽이 먼저 떠요. 이 팩 문구를 쓰려면 「외부 채움글」 목록에서 이 팩을 길게 눌러 더 위로 올려 주세요.")
    }

    @Test("★ 검증 F-5 — 꺼진·쉬는 팩 상세는 「켜면(다시 뜨면)」 전제를 머리·배지·설명 줄에 보인다 — 지금 뜨는 팩은 그대로")
    func standingPremiseCopy() {
        #expect(PackNoticeCopy.standingPremise(.on) == nil && PackNoticeCopy.standingPremise(.unavailable) == nil)
        #expect(PackNoticeCopy.standingPremise(.off) == .ifEnabled)
        #expect(PackNoticeCopy.standingPremise(.restingOverLimit) == .ifResumed && PackNoticeCopy.standingPremise(.restingForUserSnippets) == .ifResumed)

        #expect(PackNoticeCopy.templatesHeader(nil) == "단축어 틀")
        #expect(PackNoticeCopy.templatesHeader(.ifEnabled) == "단축어 틀 — 켜면 이렇게 떠요")
        #expect(PackNoticeCopy.templatesHeader(.ifResumed) == "단축어 틀 — 다시 뜨면 이렇게 떠요")
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 37, premise: nil) == "지금 안 뜨는 단축어 37개")
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 37, premise: .ifEnabled) == "켜도 안 뜨는 단축어 37개")
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 1_500, premise: .ifResumed) == "다시 떠도 안 뜨는 단축어 1,500개")
        #expect(PackNoticeCopy.patternBadge(.owned(sharedWith: []), premise: nil) == "사용 중")
        #expect(PackNoticeCopy.patternBadge(.owned(sharedWith: ["b"]), premise: .ifEnabled) == "켜면 사용")
        #expect(PackNoticeCopy.patternBadge(.owned(sharedWith: []), premise: .ifResumed) == "뜨면 사용")
        #expect(PackNoticeCopy.patternBadge(.outranked(by: "a"), premise: .ifEnabled) == "뒤 순서")
        #expect(PackNoticeCopy.patternBadge(.shadowed(by: ["장"]), premise: .ifEnabled) == "가려짐")
        // 설명 줄도 같은 전제 — 이 팩 문구가 뜨는 것은 켜면(다시 뜨면). 뒤 순서·가려짐은 다른 문구가 먼저 뜨는 것이라 그대로
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: []), premise: nil, name: name) == "이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: []), premise: .ifEnabled, name: name) == "켜면 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: []), premise: .ifResumed, name: name) == "다시 뜨면 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b"]), premise: .ifEnabled, name: name)
                == "아래 「예시 번호 팩」도 같은 틀이지만 켜면 위에 있는 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b", "c"]), premise: .ifResumed, name: name)
                == "아래 「예시 번호 팩」 외 1개 팩도 같은 틀이지만 다시 뜨면 위에 있는 이 팩 문구가 떠요")
        #expect(PackNoticeCopy.patternLine(.outranked(by: "a"), premise: .ifEnabled, name: name)
                == PackNoticeCopy.patternLine(.outranked(by: "a"), name: name))
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["장"]), premise: .ifResumed, name: name)
                == PackNoticeCopy.patternLine(.shadowed(by: ["장"]), name: name))
        // 가정 문구에는 「지금」·「사용 중」이 없다 — 꺼진 팩이 지금 쓰이는 것처럼 보이지 않게
        let premised = [PackNoticeCopy.StandingPremise.ifEnabled, .ifResumed].flatMap {
            [PackNoticeCopy.templatesHeader($0), PackNoticeCopy.hiddenTriggersHeader(count: 37, premise: $0),
             PackNoticeCopy.patternBadge(.owned(sharedWith: []), premise: $0),
             PackNoticeCopy.patternLine(.owned(sharedWith: []), premise: $0, name: name),
             PackNoticeCopy.patternLine(.owned(sharedWith: ["b"]), premise: $0, name: name)]
        }
        for text in premised { #expect(!text.contains("지금") && !text.contains("사용 중"), "\(text)") }
    }

    @Test("★ 2-F — 삭제 확인: 「이름」을/를 지울까요? · 항목 수 · 다시 가져와야 한다. 항목 수를 모르면 숫자 없이")
    func deleteCopy() {
        #expect(PackNoticeCopy.deleteTitle(name: "사자성어 예시 팩") == "「사자성어 예시 팩」을 지울까요?")
        #expect(PackNoticeCopy.deleteTitle(name: "회사 상용구") == "「회사 상용구」를 지울까요?")
        #expect(PackNoticeCopy.deleteMessage(itemCount: 37) == "이 팩의 채움글 37개가 이 기기에서 지워져요. 다시 쓰려면 파일을 다시 가져와야 해요.")
        #expect(PackNoticeCopy.deleteMessage(itemCount: 0) == "이 팩이 이 기기에서 지워져요. 다시 쓰려면 파일을 다시 가져와야 해요.")
        #expect(PackNoticeCopy.cancel == "취소")
    }

    @Test("목적격 조사 — 받침이면 을, 아니면 를. 숫자는 읽는 소리(2·4·5·9 = 를), 모르면 을(를)",
          arguments: [("팩", "을"), ("상용구", "를"), ("예시 팩 2", "를"), ("예시 팩 3", "을"), ("Pack", "을(를)"), ("성어 {n}번", "을")])
    func objectParticle(_ name: String, _ expected: String) {
        #expect(PackNoticeCopy.objectParticle(after: name) == expected)
    }
}

/// 3단계 문구 전부 — `stage1To3Copy`(한도 숫자 검사)·`allScreenCopy`(U6·금칙어·xlsx)에 들어간다. 개수는 `37`·`41`만 쓴다(숫자 검사가 이것만 지운다).
/// 부를 때마다 지금 판으로 만든다(6단계 — 판을 바꿔 가며 읽는다)
var stage3Copy: [String] {
    var texts = [
        PackNoticeCopy.externalSectionTitle, PackNoticeCopy.addPack, PackNoticeCopy.emptyListFooter,
        PackNoticeCopy.userSlotTitle, PackNoticeCopy.userSlotDetail, PackNoticeCopy.enabledValue, PackNoticeCopy.disabledValue,
        PackNoticeCopy.cancel, PackNoticeCopy.moveUpAction, PackNoticeCopy.moveDownAction,
        PackNoticeCopy.useToggle, PackNoticeCopy.infoHeader, PackNoticeCopy.kindLabel, PackNoticeCopy.licenseLabel, PackNoticeCopy.infoFooter,
        PackNoticeCopy.templatesHeader, PackNoticeCopy.templatesFooter, PackNoticeCopy.templatesEditHint, PackNoticeCopy.hiddenTriggersHeader(count: 37),
        PackNoticeCopy.hiddenTriggerBadge, PackNoticeCopy.usageHeader, PackNoticeCopy.usageFooter, PackNoticeCopy.deletePackButton,
        PackNoticeCopy.usageResult("예시 제목 둘"), PackNoticeCopy.usageResult(body: "예시 본문 첫 줄\n둘째 줄"),
        PackNoticeCopy.deleteTitle(name: "회사 상용구"), PackNoticeCopy.deleteMessage(itemCount: 37), PackNoticeCopy.deleteMessage(itemCount: 0),
        // R31 전체 보기 — 줄·머리 한 줄(꺼짐·쉬는 중)·절 머리·검색 칸·빈 상태
        PackNoticeCopy.allEntriesRow(count: 37), PackNoticeCopy.allEntriesHeader(count: 37, isSearching: false),
        PackNoticeCopy.allEntriesHeader(count: 37, isSearching: true), PackNoticeCopy.allEntriesSearchPrompt, PackNoticeCopy.allEntriesNoMatch
    ]
    texts += [PackSummary.Status.off, .restingOverLimit, .restingForUserSnippets].compactMap(PackNoticeCopy.allEntriesStatusLine)
    texts += [sajaseongeo, examplePack, company].compactMap(PackNoticeCopy.packRowDetail)
    let statuses: [PackStanding.PatternStatus] = [.owned(sharedWith: []), .owned(sharedWith: ["b"]), .owned(sharedWith: ["b", "c"]),
                                                  .outranked(by: "a"), .shadowed(by: ["장"]), .shadowed(by: ["장", "번"])]
    texts += statuses.flatMap { [PackNoticeCopy.patternBadge($0), PackNoticeCopy.patternLine($0, name: name)] }
    // 검증 F-5 — 꺼진·쉬는 팩의 가정 머리·배지·설명 줄
    let premises: [PackNoticeCopy.StandingPremise] = [.ifEnabled, .ifResumed]
    texts += premises.flatMap { premise in
        [PackNoticeCopy.templatesHeader(premise), PackNoticeCopy.hiddenTriggersHeader(count: 37, premise: premise)]
            + statuses.flatMap { [PackNoticeCopy.patternBadge($0, premise: premise), PackNoticeCopy.patternLine($0, premise: premise, name: name)] }
    }
    texts += [PackImpact.Source.userSnippets, .pack("c")].map { PackNoticeCopy.hiddenTriggerLine(owner: $0, name: name) }
    texts += [[.userSnippets], [.userSnippets, .pack("c")]].map { PackNoticeCopy.hiddenTriggersFooter(owners: $0, name: name) }
    return texts
}
