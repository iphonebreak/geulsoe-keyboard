import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 3단계 문구 — 외부 채움글 절(2-B·2-C)·순서 화면(2-D·2-G)·팩 상세(2-E·U1)·삭제 확인(2-F).
// 기준: 시안 `docs/design/external-snippet-packs/index.html` 2절·U1 컷의 화면 글자(**글자 그대로** 옮겼다), 계획서 4-2·4-3절.
// 이름은 사용자가 정한다 — 조사는 받침을 따른다. 한도 숫자 검사는 `PackChangeNoticeTests`의 `stage1To3Copy`가, U6·금칙어·xlsx 검사는
// `PackCopyLintTests`(6단계 — 한 곳)가 이 목록(`stage3Copy`)까지 돈다.

// MARK: - 시험 도구

private func summary(_ id: String, _ name: String?, mode: ExternalPack.Mode?, count: Int, titleFormat: String? = nil,
                     enabled: Bool = true, status: PackSummary.Status = .on) -> PackSummary {
    PackSummary(id: id, name: name, mode: mode, itemCount: count, titleFormat: titleFormat, isEnabled: enabled, status: status)
}

private func library(_ summaries: [PackSummary]) -> PackImpact.Library {
    PackImpact.Library(revision: 1, order: [.userSnippets] + summaries.map { .pack($0.id) },
                       packs: summaries.map { PackImpact.Pack(summary: $0, stats: .zero, content: nil) },
                       userEntries: [], builtInEntries: [], limits: .candidate)
}

private let sajaseongeo = summary("a", "사자성어 예시 팩", mode: .numbered, count: 37, titleFormat: "사자성어 {n}번")
private let examplePack = summary("b", "예시 번호 팩", mode: .numbered, count: 41, titleFormat: "성어 {n}번")
private let company = summary("c", "우리 회사 상용구", mode: .phrases, count: 41)
private let names = ["a": "사자성어 예시 팩", "b": "예시 번호 팩", "c": "우리 회사 상용구"]
private func name(_ id: String) -> String { names[id] ?? PackNoticeCopy.unnamedPack }

/// 한도 숫자 검사가 「외 n개」와 `37개`·`41개`만 지우므로 개수는 그 값으로 만든다 — 37개짜리 단축어 주인 변화
private let manyTriggers = (0..<37).map { String(UnicodeScalar(0xAC00 + $0 * 28)!) + "말" }

@Suite("외부 채움글 1-c 3단계 — 문구 (2-B~2-G · U1)")
struct PackImpactCopyTests {

    @Test("★ 2-B·2-C — 절 제목·추가 줄·빈 상태 풋터(CSV판)·목록 풋터·「내 채움글 (순서)」 줄")
    func sectionCopy() {
        #expect(PackNoticeCopy.externalSectionTitle == "외부 채움글")
        #expect(PackNoticeCopy.addPack == "외부 채움글 추가")
        #expect(PackNoticeCopy.emptyListFooter
                == "CSV 파일로 만든 채움글 묶음(팩)을 가져와요. 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요.")
        #expect(PackNoticeCopy.listFooter
                == "위에 있는 줄이 먼저 떠요 — 같은 문구 단축어는 위 줄이, 같은 단축어 틀은 위 팩이 가져요. 「내 채움글」도 이 순서에 들어가요.\n"
                + "한도는 외부 팩만 위에서부터 채워요(내 채움글은 늘 써요). 가져온 팩은 이 기기에만 저장돼요.")
        #expect(PackNoticeCopy.userSlotTitle == "내 채움글 (순서)")
        #expect(PackNoticeCopy.userSlotDetail == "순서 표시 전용 · 눌리지 않아요 · 문구는 아래 「내 채움글」 절에서")
        #expect(PackNoticeCopy.enabledValue == "켬" && PackNoticeCopy.disabledValue == "끔")
    }

    @Test("★ 2-C 행 — 종류 · 항목 수 · 대표 틀(번호형만). 종류를 모르면 줄이 없다")
    func rowDetail() {
        #expect(PackNoticeCopy.packRowDetail(sajaseongeo) == "번호형 · 37개 · 사자성어 {n}번")
        #expect(PackNoticeCopy.packRowDetail(company) == "문구형 · 41개")
        #expect(PackNoticeCopy.packKind(sajaseongeo) == "번호형 · 37개")
        #expect(PackNoticeCopy.packRowDetail(summary("x", nil, mode: nil, count: 0, status: .unavailable)) == nil)
    }

    @Test("★ 2-D·2-G — 순서 화면: 제목·버튼·「내 채움글」 줄·꺼진 팩·풋터")
    func orderCopy() {
        #expect(PackNoticeCopy.orderTitle == "팩 순서")
        #expect(PackNoticeCopy.orderDone == "완료" && PackNoticeCopy.cancel == "취소")
        #expect(PackNoticeCopy.orderUserTitle == "내 채움글")
        #expect(PackNoticeCopy.orderUserDetail(count: 37) == "내가 만든 문구 37개 · 지울 수 없어요")
        #expect(PackNoticeCopy.orderPackDetail(summary("c", "인사말 예시", mode: .phrases, count: 41, enabled: false, status: .off))
                == "문구형 · 41개 · 꺼짐")
        #expect(PackNoticeCopy.orderPackDetail(examplePack) == "번호형 · 41개 · 성어 {n}번")
        #expect(PackNoticeCopy.orderPackDetail(summary("x", "깨진 팩", mode: nil, count: 0, enabled: false, status: .unavailable))
                == "읽을 수 없어요")
        #expect(PackNoticeCopy.orderFooter
                == "끌어서 순서를 바꿔요. 위에 있는 줄이 먼저 떠요 — 「내 채움글」도 끌 수 있어요. 한도는 외부 팩만 위에서부터 채워요.")
    }

    @Test("★ 2-D — 틀 주인 변화(완료 전): 틀은 대표 틀 원문으로, 주인은 이름 + 받침에 맞는 조사")
    func templateOwnerLine() {
        let impact = PackImpact(restingPacks: [], templateOwnerChanges: [
            .init(pattern: TemplatePattern(prefix: "성어", suffix: "번"), from: "a", to: "b")
        ], triggerOwnerChanges: [])
        #expect(PackNoticeCopy.impactLines(impact, in: library([sajaseongeo, examplePack])) == [
            .init(message: "이렇게 바꾸면 「성어 {n}번」을 「사자성어 예시 팩」 대신 「예시 번호 팩」이 가져요.",
                  detail: "「성어 {n}번」을 치면 지금과 다른 팩의 글이 떠요.")
        ])
        // 같은 두 팩 사이에서 틀이 여럿 바뀌면 한 줄로 — 대표 틀이 아닌 별칭은 정규화 모양
        let two = PackImpact(restingPacks: [], templateOwnerChanges: [
            .init(pattern: TemplatePattern(prefix: "성어", suffix: "번"), from: "a", to: "b"),
            .init(pattern: TemplatePattern(prefix: "고사", suffix: "번"), from: "a", to: "b")
        ], triggerOwnerChanges: [])
        #expect(PackNoticeCopy.impactLines(two, in: library([sajaseongeo, examplePack])) == [
            .init(message: "이렇게 바꾸면 「성어 {n}번」·「고사{n}번」을 「사자성어 예시 팩」 대신 「예시 번호 팩」이 가져요.",
                  detail: "이 틀을 치면 지금과 다른 팩의 글이 떠요.")
        ])
    }

    @Test("★ 2-G — 단축어 주인 변화(완료 전): 「단축어 n개가 ○ 대신 ○의 문구로」, 다섯 개까지 보이고 「외 n개」")
    func triggerOwnerLine() {
        let impact = PackImpact(restingPacks: [], templateOwnerChanges: [], triggerOwnerChanges: [
            .init(trigger: "주소", from: .userSnippets, to: .pack("c")),
            .init(trigger: "새해인사", from: .userSnippets, to: .pack("c"))
        ])
        #expect(PackNoticeCopy.impactLines(impact, in: library([company])) == [
            .init(message: "이렇게 바꾸면 단축어 2개가 내 채움글 대신 「우리 회사 상용구」의 문구로 떠요.",
                  detail: "주소, 새해인사 — 내 채움글의 같은 단축어는 안 떠요.")
        ])
        let back = PackImpact(restingPacks: [], templateOwnerChanges: [], triggerOwnerChanges: [
            .init(trigger: "주소", from: .pack("c"), to: .userSnippets), .init(trigger: "회의실", from: .pack("c"), to: .builtIn)
        ])
        #expect(PackNoticeCopy.impactLines(back, in: library([company])) == [
            .init(message: "이렇게 바꾸면 단축어 1개가 「우리 회사 상용구」 대신 내 채움글의 문구로 떠요.",
                  detail: "주소 — 「우리 회사 상용구」의 같은 단축어는 안 떠요."),
            .init(message: "이렇게 바꾸면 단축어 1개가 「우리 회사 상용구」 대신 내장 팩의 문구로 떠요.",
                  detail: "회의실 — 「우리 회사 상용구」의 같은 단축어는 안 떠요.")
        ])
        let many = PackImpact(restingPacks: [], templateOwnerChanges: [],
                              triggerOwnerChanges: manyTriggers.map { .init(trigger: $0, from: .userSnippets, to: .pack("c")) })
        let line = PackNoticeCopy.impactLines(many, in: library([company]))[0]
        #expect(line.detail == manyTriggers.prefix(5).joined(separator: ", ") + " 외 32개 — 내 채움글의 같은 단축어는 안 떠요.")
    }

    @Test("★ ㉤ — 쉬게 될 팩이 맨 먼저(가장 큰 변화), 그다음 틀·단축어. 영향이 없으면 줄도 없다")
    func lineOrder() {
        let impact = PackImpact(restingPacks: ["a"], templateOwnerChanges: [
            .init(pattern: TemplatePattern(prefix: "성어", suffix: "번"), from: "a", to: "b")
        ], triggerOwnerChanges: [.init(trigger: "주소", from: .userSnippets, to: .pack("c"))])
        let lines = PackNoticeCopy.impactLines(impact, in: library([sajaseongeo, examplePack, company]))
        #expect(lines.map(\.message).first == "이렇게 바꾸면 「사자성어 예시 팩」이 한도 밖으로 밀려서 쉬어요.")
        #expect(lines.first?.detail == nil && lines.count == 3)
        #expect(PackNoticeCopy.impactLines(PackImpact(restingPacks: [], templateOwnerChanges: [], triggerOwnerChanges: []),
                                           in: library([])).isEmpty)
    }

    @Test("★ 2-E — 팩 상세: 스위치·정보·틀 상태 배지와 설명 줄·풋터·사용법·삭제")
    func detailCopy() {
        #expect(PackNoticeCopy.useToggle == "이 팩 사용")
        #expect(PackNoticeCopy.infoHeader == "정보" && PackNoticeCopy.kindLabel == "종류" && PackNoticeCopy.licenseLabel == "권리 표기")
        #expect(PackNoticeCopy.infoFooter == "권리 표기는 가져올 때 확인한 문구 그대로예요.")
        #expect(PackNoticeCopy.templatesHeader == "단축어 틀")
        #expect(PackNoticeCopy.templatesFooter
                == "같은 틀을 두 팩이 쓰면 위에 있는 팩이 가져요. 고유한 앞 글자(예: 고사성어 {n}번)를 쓰면 겹치지 않아요.")
        #expect(PackNoticeCopy.patternBadge(.owned(sharedWith: [])) == "사용 중")
        #expect(PackNoticeCopy.patternBadge(.outranked(by: "a")) == "뒤 순서")
        #expect(PackNoticeCopy.patternBadge(.shadowed(by: ["장"])) == "가려짐")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: []), name: name) == "이 팩이 써요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b"]), name: name) == "아래 「예시 번호 팩」도 같은 틀 — 위에 있는 이 팩이 써요")
        #expect(PackNoticeCopy.patternLine(.owned(sharedWith: ["b", "c"]), name: name)
                == "아래 「예시 번호 팩」 외 1개 팩도 같은 틀 — 위에 있는 이 팩이 써요")
        #expect(PackNoticeCopy.patternLine(.outranked(by: "a"), name: name) == "위에 있는 「사자성어 예시 팩」이 같은 틀을 써요")
        // 화면 확인 S-3 — 가림은 그 끝말로 끝나는 입력에서만(「이 틀은 안 떠요」는 범위 과장)
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["장"]), name: name) == "「…장」으로 끝나는 입력에서는 단축어 「장」이 먼저 떠요")
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["번호3번", "번"]), name: name)
                    == "「…번호3번」 등으로 끝나는 입력에서는 단축어 「번호3번」 외 1개가 먼저 떠요")
        #expect(PackNoticeCopy.patternLine(.shadowed(by: ["자"]), name: name) == "「…자」로 끝나는 입력에서는 단축어 「자」가 먼저 떠요")
        #expect(PackNoticeCopy.usageHeader == "사용법")
        #expect(PackNoticeCopy.usageFooter == "단축어를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 단축어가 전문으로 바뀌어요.")
        #expect(PackNoticeCopy.usageResult("예시 제목 둘") == "→ 예시 제목 둘")
        #expect(PackNoticeCopy.deletePackButton == "팩 삭제")
    }

    @Test("★ U1 — 지금 안 뜨는 단축어: 머리줄·행 설명·배지·풋터(위 줄이 하나면 그 이름, 여럿이면 「더 위로」)")
    func hiddenTriggerCopy() {
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 37) == "지금 안 뜨는 단축어 37개")
        #expect(PackNoticeCopy.hiddenTriggerLine(owner: .userSnippets, name: name) == "위에 있는 「내 채움글」이 먼저 떠요")
        #expect(PackNoticeCopy.hiddenTriggerLine(owner: .pack("c"), name: name) == "위에 있는 「우리 회사 상용구」가 먼저 떠요")
        #expect(PackNoticeCopy.hiddenTriggerBadge == "뒤 순서")
        #expect(PackNoticeCopy.hiddenTriggersFooter(owners: [.userSnippets, .userSnippets], name: name)
                == "목록에서 위에 있는 쪽이 먼저 떠요. 이 팩 문구를 쓰려면 이 팩을 「내 채움글」 위로 올려 주세요.")
        #expect(PackNoticeCopy.hiddenTriggersFooter(owners: [.userSnippets, .pack("c")], name: name)
                == "목록에서 위에 있는 쪽이 먼저 떠요. 이 팩 문구를 쓰려면 이 팩을 더 위로 올려 주세요.")
    }

    @Test("★ 2-F — 삭제 확인: 「이름」을/를 지울까요? · 항목 수 · 다시 가져와야 한다. 항목 수를 모르면 숫자 없이")
    func deleteCopy() {
        #expect(PackNoticeCopy.deleteTitle(name: "사자성어 예시 팩") == "「사자성어 예시 팩」을 지울까요?")
        #expect(PackNoticeCopy.deleteTitle(name: "회사 상용구") == "「회사 상용구」를 지울까요?")
        #expect(PackNoticeCopy.deleteMessage(itemCount: 37) == "이 팩의 채움글 37개가 이 기기에서 지워져요. 다시 쓰려면 파일을 다시 가져와야 해요.")
        #expect(PackNoticeCopy.deleteMessage(itemCount: 0) == "이 팩이 이 기기에서 지워져요. 다시 쓰려면 파일을 다시 가져와야 해요.")
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
    let lib = library([sajaseongeo, examplePack, company])
    var texts = [
        PackNoticeCopy.externalSectionTitle, PackNoticeCopy.addPack, PackNoticeCopy.emptyListFooter, PackNoticeCopy.listFooter,
        PackNoticeCopy.userSlotTitle, PackNoticeCopy.userSlotDetail, PackNoticeCopy.enabledValue, PackNoticeCopy.disabledValue,
        PackNoticeCopy.orderTitle, PackNoticeCopy.orderDone, PackNoticeCopy.cancel, PackNoticeCopy.orderUserTitle,
        PackNoticeCopy.orderUserDetail(count: 37), PackNoticeCopy.orderFooter,
        PackNoticeCopy.useToggle, PackNoticeCopy.infoHeader, PackNoticeCopy.kindLabel, PackNoticeCopy.licenseLabel, PackNoticeCopy.infoFooter,
        PackNoticeCopy.templatesHeader, PackNoticeCopy.templatesFooter, PackNoticeCopy.hiddenTriggersHeader(count: 37),
        PackNoticeCopy.hiddenTriggerBadge, PackNoticeCopy.usageHeader, PackNoticeCopy.usageFooter, PackNoticeCopy.deletePackButton,
        PackNoticeCopy.deleteTitle(name: "회사 상용구"), PackNoticeCopy.deleteMessage(itemCount: 37), PackNoticeCopy.deleteMessage(itemCount: 0)
    ]
    texts += [sajaseongeo, examplePack, company].compactMap(PackNoticeCopy.packRowDetail)
    texts += [sajaseongeo, company].compactMap(PackNoticeCopy.orderPackDetail)
    let statuses: [PackStanding.PatternStatus] = [.owned(sharedWith: []), .owned(sharedWith: ["b"]), .owned(sharedWith: ["b", "c"]),
                                                  .outranked(by: "a"), .shadowed(by: ["장"]), .shadowed(by: ["장", "번"])]
    texts += statuses.flatMap { [PackNoticeCopy.patternBadge($0), PackNoticeCopy.patternLine($0, name: name)] }
    texts += [PackImpact.Source.userSnippets, .pack("c")].map { PackNoticeCopy.hiddenTriggerLine(owner: $0, name: name) }
    texts += [[.userSnippets], [.userSnippets, .pack("c")]].map { PackNoticeCopy.hiddenTriggersFooter(owners: $0, name: name) }
    let impact = PackImpact(
        restingPacks: ["a"],
        templateOwnerChanges: [.init(pattern: TemplatePattern(prefix: "성어", suffix: "번"), from: "a", to: "b")],
        triggerOwnerChanges: manyTriggers.map { .init(trigger: $0, from: .userSnippets, to: .pack("c")) }
            + manyTriggers.map { .init(trigger: $0 + "글", from: .pack("c"), to: .builtIn) })
    texts += PackNoticeCopy.impactLines(impact, in: lib).flatMap { [$0.message] + ($0.detail.map { [$0] } ?? []) }
    return texts
}
