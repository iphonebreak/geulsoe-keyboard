import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// 외부 채움글 1-b — 매처 배선(PDR `external-snippet-packs.md` 10-3 분기 순서 · 10-4/U1 순서 · D19).
// 분기: 사용자 문구/팩 entries → 내장 → 날짜·시간 → **템플릿** → 성경. 같은 단축어는 U1 목록에서 위에 있는 쪽.

private struct GenesisBible: BibleVerseRepository {
    func text(book: Int, chapter: Int, verse: Int) -> String? { "성경 \(book):\(chapter):\(verse)" }
}

@Suite("외부 채움글 — 매처 배선 (10-3·U1, 1-b)")
struct ExternalSnippetWiringTests {

    private static let userThanks = SnippetEntry(trigger: "감사인사", title: "내 감사", body: "내가 쓴 감사")
    private static let packThanks = SnippetEntry(trigger: "감사인사", title: "팩 감사", body: "팩의 감사")
    private static let phrasePack = ExternalPack(name: "상용구", license: "자체", mode: .phrases,
                                                 entries: [packThanks, SnippetEntry(trigger: "회의끝", title: "회의", body: "회의를 마칩니다")])
    private static let numberedPack = ExternalPack(
        name: "사자성어", license: "자체", mode: .numbered,
        template: PackTemplate(patterns: [TemplatePattern(prefix: "사자성어", suffix: "번")], titleFormat: "사자성어 {n}번",
                               items: [PackTemplateItem(n: 12, title: "", body: "온고지신"), PackTemplateItem(n: 3, title: "삼", body: "삼고초려")]))
    private static let builtIn = [SnippetEntry(trigger: "새해인사", title: "새해", body: "새해 복 많이 받으세요")]

    private func matcher(
        order: [SnippetSourceSlot], user: [SnippetEntry] = [userThanks],
        packs: [String: ExternalPack] = ["phr": phrasePack, "num": numberedPack],
        dates: DateSnippetParser? = nil, bible: (any BibleVerseRepository)? = nil
    ) -> SnippetMatcher {
        let sources = SnippetSourceComposer.compose(order: order, userEntries: user, packs: packs, builtIn: Self.builtIn)
        return SnippetMatcher(bible: bible, entries: sources.entries, dates: dates, templates: sources.templates)
    }

    // MARK: U1 — 순서 목록의 위가 이긴다

    @Test("★ U1 — 「내 채움글」이 위면 내 문구, 팩이 위면 팩 문구 (같은 단축어 동점)")
    func orderDecidesTie() {
        #expect(matcher(order: [.userSnippets, .pack("phr")]).suggestion(forTail: "감사인사")?.body == "내가 쓴 감사")
        #expect(matcher(order: [.pack("phr"), .userSnippets]).suggestion(forTail: "감사인사")?.body == "팩의 감사")
    }

    @Test("U1 기본 순서 — 「내 채움글」 맨 위")
    func defaultOrderUserFirst() {
        #expect(SnippetSourceSlot.defaultOrder == [.userSnippets])
        let sources = SnippetSourceComposer.compose(order: [], userEntries: [Self.userThanks], packs: [:], builtIn: Self.builtIn)
        #expect(sources.entries == [Self.userThanks] + Self.builtIn, "순서가 비면 내 채움글 → 내장(지금과 같다)")
        #expect(sources.templates == nil)
    }

    @Test("순서에 없는 팩·순서에만 있고 실린 팩이 없는 줄은 건너뛴다(쉬는 팩)")
    func missingPacksSkipped() {
        let sources = SnippetSourceComposer.compose(
            order: [.pack("gone"), .userSnippets, .pack("phr")], userEntries: [Self.userThanks],
            packs: ["phr": Self.phrasePack, "notInOrder": Self.phrasePack], builtIn: Self.builtIn)
        #expect(sources.entries == [Self.userThanks] + Self.phrasePack.entries + Self.builtIn)
    }

    @Test("「내 채움글」 줄이 순서에 없으면 맨 위에 둔다 — 사용자 문구를 잃지 않는다")
    func userRowAlwaysPresent() {
        let sources = SnippetSourceComposer.compose(order: [.pack("phr")], userEntries: [Self.userThanks],
                                                    packs: ["phr": Self.phrasePack], builtIn: [])
        #expect(sources.entries.first == Self.userThanks)
    }

    @Test("C3 — 「내 채움글」 줄이 순서에 두 번 있어도 사용자 문구는 한 번만 싣는다(방어 — 로더는 그런 manifest를 손상으로 거절)")
    func duplicateUserSlotOnce() {
        let sources = SnippetSourceComposer.compose(order: [.userSnippets, .pack("phr"), .userSnippets],
                                                    userEntries: [Self.userThanks], packs: ["phr": Self.phrasePack], builtIn: [])
        #expect(sources.entries == [Self.userThanks] + Self.phrasePack.entries)
    }

    @Test("긴 단축어가 이기는 규칙은 그대로 — 순서는 같은 길이일 때만")
    func longestStillWins() {
        let long = SnippetEntry(trigger: "회의끝인사", title: "긴", body: "긴 본문")
        let m = matcher(order: [.pack("phr"), .userSnippets], user: [long])
        #expect(m.suggestion(forTail: "회의끝인사")?.body == "긴 본문")
    }

    // MARK: 10-3 분기 순서 — entries → 내장 → 날짜 → 템플릿 → 성경

    @Test("★ 템플릿 — 「사자성어 12번」에 칩, 지울 구간은 꼬리 원문")
    func templateBranch() throws {
        let hit = try #require(matcher(order: [.userSnippets, .pack("num")]).suggestion(forTail: "오늘은 사자성어 12번"))
        #expect(hit.body == "온고지신")
        #expect(hit.title == "사자성어 12번")
        #expect(hit.trigger == "사자성어 12번")
    }

    @Test("템플릿 소유 팩에 번호가 없으면 칩 없음 — 다른 판본·성경으로 후퇴하지 않는다")
    func templateNoFallback() {
        #expect(matcher(order: [.pack("num")]).suggestion(forTail: "사자성어 99번") == nil)
    }

    @Test("★ 정적 단축어(문구)가 템플릿보다 먼저다 — 같은 꼬리면 문구가 이긴다(10-3 가림)")
    func entriesBeforeTemplate() {
        let shadow = SnippetEntry(trigger: "12번", title: "문구", body: "문구가 이김")
        let shadowed = matcher(order: [.userSnippets, .pack("num")], user: [shadow])
        #expect(shadowed.suggestion(forTail: "사자성어 12번")?.body == "문구가 이김")
        // 단어 경계(2026-10-08) — 붙여 쓰면 정적 「12번」은 앞 「어」에 걸려 맞지 않아 템플릿이 뜬다(가림은 띄어 쓴 입력에서만)
        #expect(shadowed.suggestion(forTail: "사자성어12번")?.body == "온고지신")
    }

    @Test("내장 팩 문구는 외부 팩 문구 뒤 — 같은 길이면 순서 목록 쪽이 이긴다")
    func builtInAfterExternal() {
        let packNewYear = SnippetEntry(trigger: "새해인사", title: "팩 새해", body: "팩 새해")
        let pack = ExternalPack(name: "팩", license: "자체", mode: .phrases, entries: [packNewYear])
        let sources = SnippetSourceComposer.compose(order: [.userSnippets, .pack("p")], userEntries: [],
                                                    packs: ["p": pack], builtIn: Self.builtIn)
        #expect(SnippetMatcher(bible: nil, entries: sources.entries).suggestion(forTail: "새해인사")?.body == "팩 새해")
    }

    /// 두 분기가 **같은 꼬리**에 함께 맞는다 — 순서를 바꾸면 결과가 바뀐다(검증 F5 ⑤: 겹치지 않는 꼬리로는 순서를 못 잠근다).
    /// 실제 가져오기는 10-1 예약 접미(`날짜`로 끝나는 틀 거부)가 이 겹침을 막지만, 매처의 순서 자체를 여기서 고정한다
    @Test("★ 날짜가 템플릿보다 먼저 — 같은 꼬리 「기한 3일 후 날짜」에 둘 다 맞아도 날짜 칩")
    func datesBeforeTemplate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 10))!
        let dates = DateSnippetParser(style: .formal, calendar: calendar, now: { now })
        let clash = PackTemplateMatcher(sources: [.init(id: "clash", template: PackTemplate(
            patterns: [TemplatePattern(prefix: "기한", suffix: "일후날짜")], titleFormat: "기한 {n}일 후 날짜",
            items: [PackTemplateItem(n: 3, title: "", body: "템플릿 본문")]))])
        #expect(clash.match(tail: "기한 3일 후 날짜") != nil, "전제 — 템플릿도 이 꼬리에 맞는다")
        #expect(dates.suggestion(forTail: "기한 3일 후 날짜") != nil, "전제 — 날짜도 이 꼬리에 맞는다")
        let hit = try #require(SnippetMatcher(bible: nil, entries: [], dates: dates, templates: clash)
            .suggestion(forTail: "기한 3일 후 날짜"))
        #expect(hit.kind != nil && hit.body != "템플릿 본문")
    }

    @Test("★ 템플릿이 성경보다 먼저 — 같은 꼬리 「창세기 1장 1절」에 둘 다 맞으면 템플릿 칩")
    func templateBeforeBible() throws {
        let clash = PackTemplateMatcher(sources: [.init(id: "clash", template: PackTemplate(
            patterns: [TemplatePattern(prefix: "창세기", suffix: "장1절")], titleFormat: "창세기 {n}장 1절",
            items: [PackTemplateItem(n: 1, title: "", body: "템플릿 본문")]))])
        let bible = GenesisBible()
        #expect(SnippetMatcher(bible: bible, entries: []).suggestion(forTail: "창세기 1장 1절")?.body == "성경 1:1:1",
                "전제 — 성경도 이 꼬리에 맞는다")
        let hit = try #require(SnippetMatcher(bible: bible, entries: [], templates: clash).suggestion(forTail: "창세기 1장 1절"))
        #expect(hit.body == "템플릿 본문")
        #expect(SnippetMatcher(bible: bible, entries: [], templates: clash).suggestion(forTail: "창세기 1장 2절")?.body == "성경 1:1:2",
                "템플릿 소유 쌍이 아니면 성경은 지금처럼")
    }

    @Test("secure 입력란이면 템플릿도 아무것도 맞추지 않는다")
    func secureGate() {
        #expect(matcher(order: [.pack("num")]).suggestion(forTail: "사자성어 12번", isSecureTextEntry: true) == nil)
    }

    @Test("외부 팩이 없으면 매처는 지금과 같다 — entries·결과 동일")
    func noPacksUnchanged() {
        let sources = SnippetSourceComposer.compose(order: SnippetSourceSlot.defaultOrder, userEntries: [Self.userThanks],
                                                    packs: [:], builtIn: Self.builtIn)
        let wired = SnippetMatcher(bible: nil, entries: sources.entries, templates: sources.templates)
        let legacy = SnippetMatcher(bible: nil, entries: [Self.userThanks] + Self.builtIn)
        for tail in ["감사인사", "새해인사", "사자성어 12번", "없음"] {
            #expect(wired.suggestion(forTail: tail) == legacy.suggestion(forTail: tail))
        }
    }

    // MARK: D19 — 붙여넣기 칩이 채움글 칩(템플릿 포함)보다 먼저

    @Test("D19 회귀 — 붙여넣기 칩이 있으면 외부 팩 템플릿 칩도 같은 줄에 없다")
    func pasteChipStillWins() throws {
        let hit = try #require(matcher(order: [.pack("num")]).suggestion(forTail: "사자성어 12번"))
        #expect(SnippetChipGate.visibleSnippet(hit, isDismissed: false, hasPasteChip: true, allowsInsertion: true) == nil)
        #expect(SnippetChipGate.visibleSnippet(hit, isDismissed: false, hasPasteChip: false, allowsInsertion: true) == hit)
    }

    // MARK: 칩 탭 — 기존 insertSnippet(꼬리 정합·학습 제외) 그대로

    @MainActor
    @Test("외부 팩 칩 탭은 insertSnippet — 꼬리 원문만 지우고 본문을 넣는다")
    func tapInsertsThroughSnippetPath() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("오늘은 감사인사")
        let hit = try #require(matcher(order: [.pack("phr"), .userSnippets]).suggestion(forTail: controller.textTail))
        #expect(controller.insertSnippet(hit))
        #expect(output.text == "오늘은 팩의 감사")
    }
}
