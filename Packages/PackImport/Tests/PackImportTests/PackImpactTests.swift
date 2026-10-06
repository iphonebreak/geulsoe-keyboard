import Foundation
import Testing
import KeyboardCore
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 3단계 — G3 사전 영향 계산 `PackImpact`(계획서 `external-snippet-packs-1c-plan.md` 2절 G3·4-1 ㉤·5절 3행).
// PDR `external-snippet-packs.md` E표 U1(「내 채움글」도 순서 목록의 한 줄)·U4(완료 전 알림)·9-1(순서 변경: 포함 목록·소유 팩·가림을
// 다시 계산해 보인다)·10-3(가림)·10-4(소유권·동점), AC-24. 저장하지 않는 순수 함수라 저장소 없이 표로 돈다.
// 「키보드와 같은 답인가」는 아래 ★ 대조 시험이 실제 `SnippetMatcher`·`PackTemplateMatcher`로 본다(AC-8 취지).

// MARK: - 시험 도구

/// needleChars 200 — 문구형 팩 40자 하나가 needle 40자
private let small = PackBudgetLimits(needleCount: 100, needleChars: 200, bytes: 2_000_000, items: 1_000)

private func phrases(_ name: String, _ triggers: [String]) -> ExternalPack {
    ExternalPack(name: name, license: "자체 작성", mode: .phrases,
                 entries: triggers.map { SnippetEntry(trigger: $0, title: "\(name) \($0)", body: "\(name) 본문 \($0)") })
}

/// 정규화 단축어 글자 수가 `chars`가 되도록 채운 문구형 팩 — 예산 시험용(단축어는 서로 겹치지 않는다)
private func filler(_ name: String, chars: Int) -> ExternalPack {
    var triggers: [String] = []
    var remaining = chars
    var index = 0
    while remaining > 0 {
        let length = min(40, remaining)
        triggers.append(String(("\(name)\(index)" + String(repeating: "채", count: 40)).prefix(length)))
        remaining -= length
        index += 1
    }
    return phrases(name, triggers)
}

/// 번호형 — `patterns`는 `#틀` 원문(`성어 {n}번`), 첫 틀이 `titleFormat`
private func numbered(_ name: String, _ patterns: [String], items: ClosedRange<Int> = 1...20) -> ExternalPack {
    let parsed = patterns.compactMap { try? TemplatePatternSpec.parse($0).get() }
    return ExternalPack(name: name, license: "자체 작성", mode: .numbered, template: PackTemplate(
        patterns: parsed, titleFormat: patterns[0],
        items: items.map { PackTemplateItem(n: $0, title: "", body: "\(name) \($0)번 본문") }))
}

private struct Fixture {
    var order: [SnippetSourceSlot]
    var packs: [(id: String, pack: ExternalPack, enabled: Bool, unavailable: Bool)]
    var user: [SnippetEntry]
    var builtIn: [SnippetEntry]
    var limits: PackBudgetLimits

    init(order: [SnippetSourceSlot]? = nil, packs: [(String, ExternalPack)], off: Set<String> = [], unavailable: Set<String> = [],
         user: [SnippetEntry] = [], builtIn: [SnippetEntry] = [], limits: PackBudgetLimits = .candidate) {
        self.order = order ?? ([.userSnippets] + packs.map { .pack($0.0) })
        self.packs = packs.map { ($0.0, $0.1, !off.contains($0.0), unavailable.contains($0.0)) }
        self.user = user
        self.builtIn = builtIn
        self.limits = limits
    }

    /// 화면 상태 판정은 이 시험의 대상이 아니다 — 켬/끔·읽을 수 없음만 싣는다(판정은 `PackImpact`가 다시 한다)
    var library: PackImpact.Library {
        PackImpact.Library(
            revision: 7, order: order,
            packs: packs.map { item in
                PackImpact.Pack(
                    summary: PackSummary(id: item.id, name: item.pack.name, mode: item.pack.mode,
                                         itemCount: item.pack.entries.count + (item.pack.template?.items.count ?? 0),
                                         titleFormat: item.pack.template?.titleFormat, isEnabled: item.enabled,
                                         status: item.unavailable ? .unavailable : (item.enabled ? .on : .off)),
                    stats: PackStats.of(pack: item.pack), content: item.unavailable ? nil : item.pack)
            },
            userEntries: user, builtInEntries: builtIn, limits: limits)
    }
}

private func impact(_ fixture: Fixture, order: [SnippetSourceSlot], enabled: [String: Bool] = [:]) -> PackImpact {
    PackImpact.of(PackImpact.Proposal(order: order, enabled: enabled), in: fixture.library)
}

private let userAddress = SnippetEntry(triggers: ["주소", "우리집주소"], title: "우리집 주소", body: "예시 주소 한 줄")
private let userGreeting = SnippetEntry(trigger: "새해인사", title: "새해 인사", body: "내 새해 인사")
private let company = phrases("우리 회사 상용구", ["주소", "새해 인사", "회의실"])

// MARK: - G3 표

@Suite("외부 채움글 1-c 3단계 — G3 사전 영향 PackImpact")
struct PackImpactTests {

    @Test("순서를 그대로 두면 영향이 없다")
    func unchangedOrderHasNoImpact() {
        let f = Fixture(packs: [("a", company), ("b", numbered("사자성어 예시 팩", ["사자성어 {n}번"]))], user: [userAddress])
        #expect(impact(f, order: f.order).isEmpty)
    }

    @Test("★ 2-G — 「내 채움글」을 팩 아래로 내리면 같은 단축어의 주인이 팩으로 바뀐다(정규화 같은 것도, 원문은 새 주인 것)")
    func movingUserSnippetsDown() {
        let f = Fixture(packs: [("a", company)], user: [userAddress, userGreeting])
        let result = impact(f, order: [.pack("a"), .userSnippets])
        #expect(result.restingPacks.isEmpty)
        #expect(result.templateOwnerChanges.isEmpty)
        // 「새해인사」(내 채움글)와 「새해 인사」(팩)는 띄어쓰기만 달라 같은 단축어다 — 정규화는 `normalizedTrigger` 하나
        #expect(result.triggerOwnerChanges == [
            .init(trigger: "주소", from: .userSnippets, to: .pack("a")),
            .init(trigger: "새해 인사", from: .userSnippets, to: .pack("a"))
        ])
        // 되돌리면 반대 방향
        let back = Fixture(order: [.pack("a"), .userSnippets], packs: [("a", company)], user: [userAddress, userGreeting])
        #expect(impact(back, order: [.userSnippets, .pack("a")]).triggerOwnerChanges == [
            .init(trigger: "주소", from: .pack("a"), to: .userSnippets),
            .init(trigger: "새해인사", from: .pack("a"), to: .userSnippets)
        ])
    }

    @Test("★ 2-D — 같은 틀을 가진 두 번호형 팩의 순서를 바꾸면 틀 주인이 바뀐다(소유권은 PackTemplateMatcher.ownership)")
    func swappingTemplateOwners() {
        let first = numbered("사자성어 예시 팩", ["사자성어 {n}번", "성어 {n}번"])
        let second = numbered("예시 번호 팩", ["성어 {n}번"])
        let f = Fixture(packs: [("a", first), ("b", second)])
        let result = impact(f, order: [.userSnippets, .pack("b"), .pack("a")])
        #expect(result.templateOwnerChanges == [
            .init(pattern: TemplatePattern(prefix: "성어", suffix: "번"), from: "a", to: "b")
        ])
        #expect(result.triggerOwnerChanges.isEmpty && result.restingPacks.isEmpty)
        // 띄어쓰기만 다른 틀(`성어{n}번`)은 같은 쌍이다(10-4 2번)
        let spaced = Fixture(packs: [("a", first), ("b", numbered("예시 번호 팩", ["성어{n} 번"]))])
        #expect(impact(spaced, order: [.userSnippets, .pack("b"), .pack("a")]).templateOwnerChanges.count == 1)
    }

    @Test("★ ㉤ — 큰 팩을 위로 올리면 아래 팩이 한도 밖으로 밀려 쉰다(완료는 막지 않는다 — 거부가 아니라 안내)")
    func reorderRestsPacks() {
        // 한도 needleChars 200: 내장 0 + a(80) + b(80) = 160 → 둘 다 포함. c(150)는 맨 아래에서 쉬는 중
        let f = Fixture(packs: [("a", filler("가팩", chars: 80)), ("b", filler("나팩", chars: 80)), ("c", filler("다팩", chars: 150))],
                        limits: small)
        let result = impact(f, order: [.userSnippets, .pack("c"), .pack("a"), .pack("b")])
        // c(150)가 먼저 들어가면 a(80)에서 넘는다 — a와 그 뒤 b가 쉰다. 원래 쉬던 c는 「새로 쉬는」 팩이 아니다
        #expect(result.restingPacks == ["a", "b"])
        // 아래로 내리기만 하면(한도 안 그대로) 쉬는 팩이 없다
        #expect(impact(f, order: [.userSnippets, .pack("b"), .pack("a"), .pack("c")]).restingPacks.isEmpty)
    }

    @Test("「내 채움글」 줄의 자리는 한도와 무관 — 내 채움글은 늘 먼저 예산을 차지한다(R14)")
    func userSlotDoesNotAffectBudget() {
        let f = Fixture(packs: [("a", filler("가팩", chars: 100)), ("b", filler("나팩", chars: 90))],
                        user: [SnippetEntry(trigger: "가나다", title: "t", body: "b")], limits: small)
        #expect(impact(f, order: [.pack("a"), .pack("b"), .userSnippets]).restingPacks.isEmpty)
    }

    @Test("★ 읽을 수 없는 팩은 예산 자리도 단축어·틀 주인도 갖지 않는다(PackStore 판정과 같다 — C5)")
    func unavailablePacksAreIgnored() {
        let broken = phrases("깨진 팩", ["주소"])
        let f = Fixture(packs: [("x", broken), ("a", company)], unavailable: ["x"], user: [userAddress])
        let result = impact(f, order: [.pack("x"), .pack("a"), .userSnippets])
        #expect(result.triggerOwnerChanges == [.init(trigger: "주소", from: .userSnippets, to: .pack("a"))],
                "읽을 수 없는 x가 맨 위여도 주인이 되지 않는다")
        // 읽을 수 없는 큰 팩이 앞에 있어도 뒤 팩을 밀어내지 않는다
        let budget = Fixture(order: [.userSnippets, .pack("a"), .pack("x")],
                             packs: [("x", filler("못읽음", chars: 190)), ("a", filler("가팩", chars: 100))], unavailable: ["x"],
                             limits: small)
        #expect(impact(budget, order: [.userSnippets, .pack("x"), .pack("a")]).restingPacks.isEmpty)
    }

    @Test("쉬게 되는 팩의 단축어는 다음 주인에게 — 내장 팩은 언제나 맨 뒤라 순서로는 못 이기고, 팩이 쉬면 그때 주인이 된다")
    func builtInTakesOverFromRestingPack() {
        let builtIn = [SnippetEntry(trigger: "새해인사", title: "내장 새해", body: "내장 본문")]
        let greeting = phrases("인사말 예시", ["새해인사"])
        let f = Fixture(packs: [("g", greeting), ("big", filler("큰팩", chars: 195))], off: ["big"], builtIn: builtIn,
                        limits: small)
        // 순서만 바꿔서는 내장의 차례가 오지 않는다
        #expect(impact(f, order: [.pack("g"), .userSnippets, .pack("big")]).triggerOwnerChanges.isEmpty)
        // 큰 팩을 켜고 위로 — g가 쉬면 「새해인사」는 내장 팩이 가진다
        let result = impact(f, order: [.userSnippets, .pack("big"), .pack("g")], enabled: ["big": true])
        #expect(result.restingPacks == ["g"])
        #expect(result.triggerOwnerChanges == [.init(trigger: "새해인사", from: .pack("g"), to: .builtIn)])
    }

    @Test("꺼진 팩은 순서를 바꿔도 주인이 되지 않는다 — 켜기를 함께 제안하면 그때 계산한다")
    func disabledPacksDoNotCompete() {
        let f = Fixture(packs: [("a", company)], off: ["a"], user: [userAddress])
        #expect(impact(f, order: [.pack("a"), .userSnippets]).isEmpty)
        #expect(impact(f, order: [.pack("a"), .userSnippets], enabled: ["a": true]).triggerOwnerChanges
                == [.init(trigger: "주소", from: .userSnippets, to: .pack("a"))])
    }

    @Test("묶음 — 같은 (전 주인, 새 주인)끼리 한 줄, 처음 나온 순서")
    func groups() {
        let other = phrases("상용 영어", ["회의실", "인사"])
        let f = Fixture(packs: [("a", company), ("b", other)], user: [userAddress, userGreeting])
        let result = impact(f, order: [.pack("b"), .pack("a"), .userSnippets])
        #expect(result.triggerOwnerGroups == [
            .init(from: .pack("a"), to: .pack("b"), triggers: ["회의실"]),
            .init(from: .userSnippets, to: .pack("a"), triggers: ["주소", "새해 인사"])
        ])
        let templates = Fixture(packs: [("a", numbered("가 예시", ["사자성어 {n}번", "성어 {n}번"])),
                                        ("b", numbered("나 예시", ["성어 {n}번", "사자성어 {n}번"]))])
        #expect(impact(templates, order: [.userSnippets, .pack("b"), .pack("a")]).templateOwnerGroups == [
            .init(from: "a", to: "b", patterns: [TemplatePattern(prefix: "성어", suffix: "번"),
                                                 TemplatePattern(prefix: "사자성어", suffix: "번")])
        ])
    }

    // MARK: ★ 키보드와 같은 답인가 (AC-8 취지)

    @Test("★ 단축어 주인 == 키보드 SnippetMatcher가 그 단축어를 쳤을 때 고르는 항목(순서마다)",
          arguments: [
            [SnippetSourceSlot.userSnippets, .pack("a"), .pack("b")],
            [.pack("a"), .userSnippets, .pack("b")],
            [.pack("b"), .pack("a"), .userSnippets],
            [.pack("a"), .pack("b"), .userSnippets]
          ])
    func triggerOwnersMatchKeyboard(_ order: [SnippetSourceSlot]) {
        let builtIn = [SnippetEntry(trigger: "회의 실", title: "내장", body: "내장")]
        let packs = ["a": company, "b": phrases("상용 영어", ["회의실", "주 소", "인사"])]
        let user = [userAddress, userGreeting]
        let f = Fixture(order: order, packs: [("a", packs["a"]!), ("b", packs["b"]!)], user: user, builtIn: builtIn)
        let owners = PackImpact.triggerOwners(of: f.library, order: order, included: ["a", "b"])
        // 키보드: 같은 합성 함수 + 같은 매처. 제목으로 출처를 가린다
        func tagged(_ entries: [SnippetEntry], _ tag: String) -> [SnippetEntry] {
            entries.map { SnippetEntry(triggers: $0.triggers, title: tag, body: $0.body) }
        }
        let sources = SnippetSourceComposer.compose(
            order: order, userEntries: tagged(user, "user"),
            packs: packs.mapValues { var pack = $0; pack.entries = tagged(pack.entries, "pack"); return pack }
                .reduce(into: [:]) { $0[$1.key] = $1.value },
            builtIn: tagged(builtIn, "builtIn"))
        let matcher = SnippetMatcher(bible: nil, entries: sources.entries)
        for (normalized, owner) in owners {
            let chosen = matcher.suggestion(forTail: normalized)
            let expected: String = switch owner.source {
            case .userSnippets: "user"
            case .pack: "pack"
            case .builtIn: "builtIn"
            }
            #expect(chosen?.title == expected, "\(normalized)")
            if case .pack(let id) = owner.source {
                #expect(packs[id]!.entries.contains { $0.body == chosen?.body }, "\(normalized) — 팩 \(id)의 항목")
            }
        }
    }

    @Test("★ 틀 주인 == 키보드 PackTemplateMatcher가 고르는 팩(순서마다)",
          arguments: [["a", "b", "c"], ["b", "a", "c"], ["c", "b", "a"], ["b", "c", "a"]])
    func templateOwnersMatchKeyboard(_ ids: [String]) {
        let packs = ["a": numbered("가 예시", ["사자성어 {n}번", "성어 {n}번"]),
                     "b": numbered("나 예시", ["성어 {n}번"]),
                     "c": numbered("다 예시", ["사자성어{n}번", "고사 {n}번"])]
        let order: [SnippetSourceSlot] = [.userSnippets] + ids.map { .pack($0) }
        let f = Fixture(order: order, packs: ids.sorted().map { ($0, packs[$0]!) })
        let owners = PackImpact.templateOwners(of: f.library, order: order, included: ids)
        let matcher = PackTemplateMatcher(sources: ids.map { PackTemplateMatcher.Source(id: $0, template: packs[$0]!.template!) })
        for (pattern, owner) in owners {
            #expect(matcher.match(tail: "\(pattern.prefix)3\(pattern.suffix)")?.sourceID == owner, "\(pattern)")
        }
        #expect(owners.count == 3)
    }

    // MARK: ★ 팩 상세의 자리(2-E·U1, 10-3·10-4 ③)

    @Test("★ 2-E — 틀마다 사용 중·뒤 순서·가려짐. 사용 중이면 같은 틀을 가진 아래 팩도 알린다")
    func templateStanding() throws {
        let a = numbered("사자성어 예시 팩", ["사자성어 {n}번", "성어 {n}번"])
        let b = numbered("예시 번호 팩", ["성어 {n}번", "고사 {n}장"])
        let user = [SnippetEntry(trigger: "장", title: "장", body: "정적 단축어")]
        let f = Fixture(packs: [("a", a), ("b", b)], user: user)
        let standingA = try #require(PackImpact.standing(of: "a", in: f.library))
        #expect(standingA.patterns.map(\.status) == [.owned(sharedWith: []), .owned(sharedWith: ["b"])])
        #expect(standingA.patterns.map(\.display) == ["사자성어 {n}번", "성어 {n}번"],
                "대표 틀은 원문 — 별칭도 다른 팩의 대표 틀과 같은 쌍이면 그 원문(같은 틀이다)")
        let alone = Fixture(packs: [("a", a)])
        #expect(try #require(PackImpact.standing(of: "a", in: alone.library)).patterns.map(\.display) == ["사자성어 {n}번", "성어{n}번"],
                "원문을 모르는 별칭은 정규화 모양")
        let standingB = try #require(PackImpact.standing(of: "b", in: f.library))
        #expect(standingB.patterns.map(\.status) == [.outranked(by: "a"), .shadowed(by: ["장"])],
                "「고사 {n}장」은 정적 단축어 「장」이 먼저 뜬다(10-3 — 순서와 무관)")
        #expect(standingB.hiddenTriggers.isEmpty)
    }

    @Test("★ 검증 F-3 V14 — 「가려짐」(10-3)은 내 채움글만이 아니라 포함된 문구형 팩·내장 팩의 정적 단축어도 본다(순서와 무관), 꺼진 팩은 가리지 않는다")
    func shadowedByPackAndBuiltIn() throws {
        let b = numbered("예시 번호 팩", ["고사 {n}장"])
        let byPack = Fixture(packs: [("b", b), ("c", phrases("상용 문구", ["장"]))])
        #expect(try #require(PackImpact.standing(of: "b", in: byPack.library)).patterns.map(\.status) == [.shadowed(by: ["장"])],
                "아래에 있는 문구형 팩의 단축어도 가린다 — 정적 단축어가 틀보다 먼저다")
        let byBuiltIn = Fixture(packs: [("b", b)], builtIn: [SnippetEntry(trigger: "장", title: "내장", body: "내장 본문")])
        #expect(try #require(PackImpact.standing(of: "b", in: byBuiltIn.library)).patterns.map(\.status) == [.shadowed(by: ["장"])])
        let offPack = Fixture(packs: [("b", b), ("c", phrases("상용 문구", ["장"]))], off: ["c"])
        #expect(try #require(PackImpact.standing(of: "b", in: offPack.library)).patterns.map(\.status) == [.owned(sharedWith: [])],
                "꺼진 팩의 단축어는 키보드에 없다")
    }

    @Test("★ U1 — 문구형 팩의 「지금 안 뜨는 단축어」: 위 줄이 같은 단축어를 가지면 뒤 순서. 팩을 올리면 사라진다")
    func hiddenTriggers() throws {
        let other = phrases("상용 영어", ["회의 실"])
        let f = Fixture(packs: [("b", other), ("a", company)], user: [userAddress, userGreeting])
        let standing = try #require(PackImpact.standing(of: "a", in: f.library))
        #expect(standing.hiddenTriggers == [
            .init(trigger: "주소", owner: .userSnippets),
            .init(trigger: "새해 인사", owner: .userSnippets),
            .init(trigger: "회의실", owner: .pack("b"))
        ])
        #expect(standing.patterns.isEmpty)
        let raised = Fixture(order: [.pack("a"), .userSnippets, .pack("b")], packs: [("b", other), ("a", company)],
                             user: [userAddress, userGreeting])
        #expect(try #require(PackImpact.standing(of: "a", in: raised.library)).hiddenTriggers.isEmpty)
        // 내장 팩은 언제나 뒤라 팩 문구를 가리지 못한다
        let builtIn = Fixture(packs: [("a", company)], builtIn: [SnippetEntry(trigger: "회의실", title: "내장", body: "내장")])
        #expect(try #require(PackImpact.standing(of: "a", in: builtIn.library)).hiddenTriggers.isEmpty)
    }

    @Test("꺼진·쉬는 팩도 「켜면 어떻게 되나」로 본다 — 그 팩만 포함된 것으로 놓고 계산")
    func standingOfDisabledPack() throws {
        let f = Fixture(packs: [("a", company)], off: ["a"], user: [userAddress])
        #expect(try #require(PackImpact.standing(of: "a", in: f.library)).hiddenTriggers == [.init(trigger: "주소", owner: .userSnippets)])
        let templates = Fixture(packs: [("a", numbered("가 예시", ["성어 {n}번"])), ("b", numbered("나 예시", ["성어 {n}번"]))],
                                off: ["a"])
        #expect(try #require(PackImpact.standing(of: "b", in: templates.library)).patterns.map(\.status) == [.owned(sharedWith: [])],
                "꺼진 a는 b의 틀을 빼앗지 않는다")
        #expect(try #require(PackImpact.standing(of: "a", in: templates.library)).patterns.map(\.status) == [.owned(sharedWith: ["b"])],
                "a를 켜면 위에 있으니 a가 가진다")
    }

    @Test("읽을 수 없는 팩·없는 팩은 자리를 계산하지 않는다(nil)")
    func standingOfUnavailablePack() {
        let f = Fixture(packs: [("a", company)], unavailable: ["a"])
        #expect(PackImpact.standing(of: "a", in: f.library) == nil)
        #expect(PackImpact.standing(of: "없음", in: f.library) == nil)
    }
}

// MARK: - 순서 변경 뒤 알림 (코디네이터 결정 ⓑ — rechecked일 때만)

@Suite("외부 채움글 1-c 3단계 — 순서 변경 뒤 알림")
struct ReorderNoticeTests {

    private func accepted(_ excluded: [String], rechecked: Bool) -> PackChangeOutcome {
        let result = PackStore.CommitResult.accepted(.init(
            revision: 2, packID: nil, newlyExcluded: excluded,
            evaluation: ActivePackBudget.evaluate(baseline: .zero, packs: []), rechecked: rechecked))
        return PackChangeOutcome(result: result, notice: PackChangeNotice(.reorderPacks, result: result,
                                                                          userSnippetsOverLimit: { false }, packName: { _ in "회사 상용구" }))
    }

    @Test("★ ⓑ — 사전 안내와 같은 결과면 알리지 않는다(같은 말을 두 번 하지 않는다)")
    func sameAsPreviewIsSilent() {
        #expect(accepted(["a"], rechecked: false).noticeAfterReorder(previewed: ["a"]) == nil)
        #expect(accepted([], rechecked: false).noticeAfterReorder(previewed: []) == nil)
    }

    @Test("★ ⓑ — 그 사이 저장본이 바뀌어 다시 판정했으면(rechecked) 쉬게 된 팩을 알린다")
    func recheckedShowsRested() {
        #expect(accepted(["a"], rechecked: true).noticeAfterReorder(previewed: [])?.reason == .packRested)
        #expect(accepted(["a"], rechecked: true).noticeAfterReorder(previewed: ["a"])?.reason == .packRested,
                "다시 판정했으면 결과가 우연히 같아도 알린다 — 안내는 옛 저장본을 본 것이다")
        #expect(accepted([], rechecked: true).noticeAfterReorder(previewed: ["a"]) == nil, "쉬게 된 팩이 없으면 알릴 것이 없다")
        // 다시 판정하지 않았는데 결과가 안내와 다르면(있어선 안 되는 일) 숨기지 않는다
        #expect(accepted(["a", "b"], rechecked: false).noticeAfterReorder(previewed: ["a"])?.reason == .packsRested)
    }

    @Test("거부는 언제나 알린다 — 목록 손상·그 사이 바뀜·쓰기 실패")
    func rejectionsAlwaysShow() {
        for rejection: PackStore.Rejection in [.libraryUnreadable, .invalidOrder, .writeFailed] {
            let result = PackStore.CommitResult.rejected(rejection, rechecked: false)
            let outcome = PackChangeOutcome(result: result, notice: PackChangeNotice(
                .reorderPacks, result: result, userSnippetsOverLimit: { false }, packName: { _ in nil }))
            #expect(outcome.noticeAfterReorder(previewed: []) != nil, "\(rejection)")
        }
    }
}
