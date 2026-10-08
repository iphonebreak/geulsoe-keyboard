import Foundation
import Testing
import KeyboardCore
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 4단계 — 미리보기의 단축어 확인(4-I) `PackImpact.overlap(ofDraft:in:)`(계획서 5절 4행 ③ — 3단계 G3 재사용).
// 새 팩은 **켠 채 목록 맨 아래**(U2)로 놓고 3단계 `PackImpact.standing`이 쓰는 키보드 합성 순서로 「지금 누가 뜨나」를 정한다.
// 정규화는 `SnippetEntry.normalizedTrigger` 한 함수(CLAUDE.md). ★ 대조 시험이 실제 `SnippetMatcher`로 같은 답인지 본다(AC-8 취지).

private func phrasesPack(_ name: String, _ triggers: [String]) -> ExternalPack {
    ExternalPack(name: name, license: "자체 작성", mode: .phrases,
                 entries: triggers.map { SnippetEntry(trigger: $0, title: "\(name) \($0)", body: "\(name) 본문 \($0)") })
}

private struct OverlapFixture {
    var order: [SnippetSourceSlot]
    var packs: [(id: String, pack: ExternalPack, status: PackSummary.Status)]
    var user: [SnippetEntry] = []
    var builtIn: [SnippetEntry] = []
    var limits: PackBudgetLimits = .candidate

    var library: PackImpact.Library {
        PackImpact.Library(
            revision: 3, order: order,
            packs: packs.map { item in
                PackImpact.Pack(
                    summary: PackSummary(id: item.id, name: item.pack.name, mode: .phrases, itemCount: item.pack.entries.count,
                                         titleFormat: nil, isEnabled: item.status != .off, status: item.status),
                    stats: PackStats.of(pack: item.pack), content: item.status == .unavailable ? nil : item.pack)
            },
            userEntries: user, builtInEntries: builtIn, limits: limits)
    }
}

private let draft = [
    SnippetEntry(triggers: ["주소", "본사 주소"], title: "회사 주소", body: "예시 주소 한 줄"),
    SnippetEntry(trigger: "새해 인사", title: "새해 인사", body: "예시 인사"),
    SnippetEntry(trigger: "추석인사", title: "추석 인사", body: "예시 인사 둘"),
    SnippetEntry(trigger: "회의실", title: "회의실 안내", body: "예시 안내")
]
private let userEntries = [SnippetEntry(trigger: "주소", title: "우리집 주소", body: "내 주소"),
                           SnippetEntry(trigger: "새해인사", title: "새해 인사", body: "내 인사")]
private let builtInEntries = [SnippetEntry(trigger: "회의 실", title: "내장", body: "내장 안내")]

@Suite("외부 채움글 1-c 4단계 — 단축어 확인 (4-I, G3 재사용)")
struct PackDraftOverlapTests {

    @Test("겹치는 단축어가 없으면 빈 결과")
    func noOverlap() {
        let f = OverlapFixture(order: [.userSnippets], packs: [])
        let result = PackImpact.overlap(ofDraft: [SnippetEntry(trigger: "새 단축어", title: "t", body: "b")], in: f.library)
        #expect(result.isEmpty)
    }

    @Test("★ 내 채움글과 같은 단축어 — 띄어쓰기만 달라도 같다, 새 팩은 맨 아래라 지금은 「내 채움글」이 뜬다")
    func userSnippetsWin() throws {
        let f = OverlapFixture(order: [.userSnippets], packs: [], user: userEntries)
        let group = try #require(PackImpact.overlap(ofDraft: draft, in: f.library).userSnippets)
        #expect(group.source == .userSnippets)
        #expect(group.triggers == ["주소", "새해 인사"])          // 새 팩의 원문, 파일 순서
        #expect(group.showsBeforeDraft)
    }

    @Test("★ 「내 채움글」을 팩 아래로 내렸어도 새 팩보다는 위다(새 팩이 맨 아래)")
    func userSnippetsStillAboveNewPack() throws {
        let f = OverlapFixture(order: [.pack("a"), .userSnippets], packs: [("a", phrasesPack("상용 영어", ["인사"]), .on)],
                               user: userEntries)
        #expect(try #require(PackImpact.overlap(ofDraft: draft, in: f.library).userSnippets).showsBeforeDraft)
    }

    @Test("★ 다른 팩 — 켜진 팩은 위라 그 팩이 뜨고, 꺼진·쉬는 팩은 지금 새 팩이 뜬다. 읽을 수 없는 팩은 단축어를 모른다")
    func otherPacks() {
        let f = OverlapFixture(
            order: [.userSnippets, .pack("on"), .pack("off"), .pack("rest"), .pack("bad")],
            packs: [("on", phrasesPack("인사말 예시", ["추석 인사"]), .on),
                    ("off", phrasesPack("상용 영어", ["회의실", "주소"]), .off),
                    ("rest", phrasesPack("쉬는 팩", ["회의실"]), .restingOverLimit),
                    ("bad", phrasesPack("깨진 팩", ["회의실"]), .unavailable)],
            // 정규화 단축어 글자 5자 — 「on」(추석인사 4자)은 들고 「rest」(회의실 3자)는 넘어 쉰다
            limits: PackBudgetLimits(needleCount: 100, needleChars: 5, bytes: 2_000_000, items: 1_000))
        let groups = PackImpact.overlap(ofDraft: draft, in: f.library).packs
        #expect(groups.map(\.source) == [.pack("on"), .pack("off"), .pack("rest")])
        #expect(groups.map(\.triggers) == [["추석인사"], ["주소", "회의실"], ["회의실"]])
        #expect(groups.map(\.showsBeforeDraft) == [true, false, false])
    }

    @Test("★ 내장 팩과 같은 단축어 — 이 팩이 먼저 뜬다(내장은 언제나 뒤, 10-3)")
    func builtInLoses() throws {
        let f = OverlapFixture(order: [.userSnippets], packs: [], builtIn: builtInEntries)
        let group = try #require(PackImpact.overlap(ofDraft: draft, in: f.library).builtIn)
        #expect(group.source == .builtIn)
        #expect(group.triggers == ["회의실"])
        #expect(!group.showsBeforeDraft)
    }

    @Test("새 팩 안에서 정규화가 같은 단축어는 한 번만 센다")
    func draftDuplicatesOnce() throws {
        let f = OverlapFixture(order: [.userSnippets], packs: [], user: userEntries)
        let dup = [SnippetEntry(trigger: "주소", title: "a", body: "a"), SnippetEntry(trigger: "주 소", title: "b", body: "b")]
        #expect(try #require(PackImpact.overlap(ofDraft: dup, in: f.library).userSnippets).triggers == ["주소"])
    }

    @Test("★ 「누가 먼저 뜨나」 == 키보드 SnippetMatcher — 그 줄과 새 팩(맨 아래)만 합성 함수에 넣어 같은 단축어를 쳤을 때",
          arguments: [
            [SnippetSourceSlot.userSnippets, .pack("on"), .pack("off")],
            [.pack("on"), .userSnippets, .pack("off")],
            [.pack("off"), .pack("on"), .userSnippets]
          ])
    func matchesKeyboard(_ order: [SnippetSourceSlot]) {
        let packs = ["on": phrasesPack("인사말 예시", ["추석 인사", "회 의 실"]), "off": phrasesPack("상용 영어", ["주소", "회의실"])]
        let f = OverlapFixture(order: order, packs: [("on", packs["on"]!, .on), ("off", packs["off"]!, .off)],
                               user: userEntries, builtIn: builtInEntries)
        let overlap = PackImpact.overlap(ofDraft: draft, in: f.library)

        // 키보드: 그 줄의 문구와 새 팩만 — 새 팩은 순서 맨 아래, 포함된(켠) 팩만 싣는다(키보드 로더가 snapshot에 실린 팩만 넘기듯)
        func tagged(_ entries: [SnippetEntry], _ tag: String) -> [SnippetEntry] {
            entries.map { SnippetEntry(triggers: $0.triggers, title: tag, body: $0.body) }
        }
        func chosen(_ trigger: String, source: PackImpact.Source) -> String? {
            var keyboardPacks = ["new": ExternalPack(name: "", license: "", mode: .phrases, entries: tagged(draft, "new"))]
            if case .pack(let id) = source, f.packs.first(where: { $0.id == id })?.status == .on {
                keyboardPacks[id] = ExternalPack(name: "", license: "", mode: .phrases, entries: tagged(packs[id]!.entries, id))
            }
            let sources = SnippetSourceComposer.compose(
                order: order + [.pack("new")], userEntries: source == .userSnippets ? tagged(userEntries, "user") : [],
                packs: keyboardPacks, builtIn: source == .builtIn ? tagged(builtInEntries, "builtIn") : [])
            return SnippetMatcher(bible: nil, entries: sources.entries)
                .suggestion(forTail: SnippetEntry.normalizedTrigger(trigger))?.title
        }
        let groups = [overlap.userSnippets, overlap.builtIn].compactMap { $0 } + overlap.packs
        #expect(groups.count == 4)                             // 내 채움글 · 내장 · on · off
        for group in groups {
            for trigger in group.triggers {
                #expect((chosen(trigger, source: group.source) != "new") == group.showsBeforeDraft, "\(trigger) — \(group.source)")
            }
        }
    }
}
