import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// U7 ① — 칩 길게 눌러 고르는 **겹치는 후보** (PDR `external-snippet-packs.md` 10-6 · AC-37~46,
// 지시서 `external-snippet-packs-u7-plan.md` 2절 ①). 이 파일은 KeyboardCore 몫만 시험한다 —
// 칩 제스처·패널 그림(②)과 조립 지점 배선(③)은 다른 커밋이다.
//
// 예시는 중립 소재(사자성어·상용구)를 쓴다(PDR U6). 성경·날짜는 분기 순서 시험에 필요한 만큼만.

private struct VerseBible: BibleVerseRepository {
    func text(book: Int, chapter: Int, verse: Int) -> String? { "성경 \(book):\(chapter):\(verse)" }
}

private enum Fixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10))!
    static let dates = DateSnippetParser(style: .formal, calendar: calendar, now: { now })

    static func numbered(_ name: String, _ prefix: String, _ suffix: String, items: [Int]) -> ExternalPack {
        ExternalPack(name: name, license: "자체", mode: .numbered, template: PackTemplate(
            patterns: [TemplatePattern(prefix: prefix, suffix: suffix)], titleFormat: "\(prefix) {n}\(suffix)",
            items: items.map { PackTemplateItem(n: $0, title: "", body: "\(name) 본문 \($0)") }))
    }

    static func phrases(_ name: String, _ entries: [SnippetEntry]) -> ExternalPack {
        ExternalPack(name: name, license: "자체", mode: .phrases, entries: entries)
    }

    static let myNewYear = SnippetEntry(trigger: "새해인사", title: "내 새해", body: "내가 쓴 새해 인사")
    static let myIdiom38 = SnippetEntry(trigger: "사자성어38번", title: "내 38번", body: "내가 쓴 38번")
    static let packNewYear = SnippetEntry(trigger: "새해 인사", title: "팩 새해", body: "팩의 새해 인사")
    static let builtInNewYear = SnippetEntry(trigger: "새해인사", title: "새해 인사", body: "새해 복 많이 받으세요")

    static let packs: [String: ExternalPack] = [
        "phr": phrases("회사 상용구", [packNewYear]),
        "idiomA": numbered("사자성어 팩 A", "사자성어", "번", items: [12, 38]),
        "idiomB": numbered("사자성어 팩 B", "사자성어", "번", items: [12])
    ]
    static let defaultOrder: [SnippetSourceSlot] = [.userSnippets, .pack("phr"), .pack("idiomA"), .pack("idiomB")]
    static let builtIn = [SnippetSourceComposer.BuiltInGroup(packID: SnippetPack.greetings, entries: [builtInNewYear])]

    static func sources(
        order: [SnippetSourceSlot] = defaultOrder, user: [SnippetEntry] = [myNewYear, myIdiom38],
        packs: [String: ExternalPack] = packs, builtIn: [SnippetSourceComposer.BuiltInGroup] = builtIn
    ) -> SnippetSourceComposer.Sources {
        SnippetSourceComposer.compose(order: order, userEntries: user, packs: packs, builtInGroups: builtIn)
    }

    static func matcher(
        _ sources: SnippetSourceComposer.Sources = sources(), dates: DateSnippetParser? = dates,
        bible: (any BibleVerseRepository)? = VerseBible()
    ) -> SnippetMatcher {
        SnippetMatcher(bible: bible, entries: sources.entries, dates: dates, templates: sources.templates,
                       origins: sources.origins)
    }
}

@Suite("U7 ① — 겹치는 후보 집합 (10-6 ①②, AC-37~39)")
struct SnippetCandidatesTests {

    /// 꼬리 → (후보 수, 출처 순서). 0이면 칩도 목록도 없다
    private static let table: [(tail: String, origins: [SnippetOrigin])] = [
        ("팀장님 새해인사", [.user, .pack(name: "회사 상용구"), .builtIn(id: SnippetPack.greetings)]),
        ("오늘은 사자성어 12번", [.pack(name: "사자성어 팩 A"), .pack(name: "사자성어 팩 B")]),
        ("사자성어 38번", [.user, .pack(name: "사자성어 팩 A")]),          // 문구 + 템플릿, 팩 B엔 38이 없다
        ("오늘 날짜", [.date]),
        ("창세기 1장 1절", [.bible]),
        ("그냥 쓰는 글", []),
        ("사자성어 99번", [])                                               // 소유 팩(A)에 99가 없다 — 칩도 목록도 없다
    ]

    @Test("★ AC-37 — 목록 첫 원소는 칩과 **같은 값**(alternativeCount 포함)이고 개수는 후보 수 − 1",
          arguments: table.indices)
    func firstEqualsChip(row: Int) {
        let (tail, origins) = Self.table[row]
        let matcher = Fixture.matcher()
        let chip = matcher.suggestion(forTail: tail)
        let candidates = matcher.candidates(forTail: tail, isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == origins, "\(tail)")
        #expect(candidates.first?.suggestion == chip, "\(tail)")
        #expect(chip?.alternativeCount == (origins.isEmpty ? nil : origins.count - 1), "\(tail)")
    }

    @Test("AC-37 — 칩 짧은 탭이 넣는 값은 U7 전과 같다(첫 후보 본문·trigger 불변)")
    func chipUnchanged() throws {
        let matcher = Fixture.matcher()
        let newYear = try #require(matcher.suggestion(forTail: "팀장님 새해인사"))
        #expect(newYear.body == "내가 쓴 새해 인사" && newYear.trigger == "새해인사")
        let idiom = try #require(matcher.suggestion(forTail: "오늘은 사자성어 12번"))
        #expect(idiom.body == "사자성어 팩 A 본문 12" && idiom.trigger == "사자성어 12번")
    }

    @Test("모든 후보는 같은 trigger(꼬리 원문 구간)를 든다 — 지울 길이가 같다")
    func sameTrigger() {
        let matcher = Fixture.matcher()
        for (tail, _) in Self.table {
            let triggers = Set(matcher.candidates(forTail: tail, isSecureTextEntry: false).map(\.suggestion.trigger))
            #expect(triggers.count <= 1, "\(tail)")
        }
    }

    @Test("목록의 둘째 이후 행은 칩이 아니다 — alternativeCount 0")
    func restHaveNoCount() {
        let candidates = Fixture.matcher().candidates(forTail: "팀장님 새해인사", isSecureTextEntry: false)
        #expect(candidates.dropFirst().allSatisfy { $0.suggestion.alternativeCount == 0 })
        #expect(candidates.map(\.suggestion.body) == ["내가 쓴 새해 인사", "팩의 새해 인사", "새해 복 많이 받으세요"])
    }

    // MARK: AC-38 — 같은 꼬리 구간만

    @Test("★ AC-38 — 같은 틀 두 팩: 소유 팩이 첫째, 다른 팩의 **같은 n**이 뒤(n이 없으면 제외)")
    func sameTemplateOtherPack() {
        let matcher = Fixture.matcher()
        #expect(matcher.candidates(forTail: "사자성어 12번", isSecureTextEntry: false).map(\.suggestion.body)
                == ["사자성어 팩 A 본문 12", "사자성어 팩 B 본문 12"])
        #expect(matcher.candidates(forTail: "사자성어12번", isSecureTextEntry: false).count == 2, "띄어쓰기 무관")
    }

    @Test("★ AC-38 · 10-4 5번 — 소유 팩에 n이 없으면 다른 팩에 있어도 칩·목록 모두 없다(후퇴 금지)")
    func ownerMissingNumberMeansNothing() {
        let packs = ["A": Fixture.numbered("A", "사자성어", "번", items: [1]),
                     "B": Fixture.numbered("B", "사자성어", "번", items: [1, 2])]
        let matcher = Fixture.matcher(Fixture.sources(order: [.pack("A"), .pack("B")], user: [], packs: packs, builtIn: []))
        #expect(matcher.suggestion(forTail: "사자성어 2번") == nil)
        #expect(matcher.candidates(forTail: "사자성어 2번", isSecureTextEntry: false).isEmpty)
    }

    @Test("★ AC-38 — 더 짧게 맞은 후보는 넣지 않는다(문구·템플릿 각각)")
    func shorterMatchesExcluded() {
        // 문구: 「새해인사말」을 치면 「인사말」도 접미로 맞지만 시작 위치가 다르다
        let long = SnippetEntry(trigger: "새해인사말", title: "긴", body: "긴 본문")
        let short = SnippetEntry(trigger: "인사말", title: "짧은", body: "짧은 본문")
        let phraseMatcher = Fixture.matcher(Fixture.sources(user: [short, long], packs: [:], builtIn: []))
        #expect(phraseMatcher.candidates(forTail: "새해인사말", isSecureTextEntry: false).map(\.suggestion.body) == ["긴 본문"])

        // 템플릿: 「새사자성어 38번」에서 접미로도 맞는 「사자성어 38번」(다른 팩)은 제외
        let packs = ["L": Fixture.numbered("L", "새사자성어", "번", items: [38]),
                     "S": Fixture.numbered("S", "사자성어", "번", items: [38])]
        let templateMatcher = Fixture.matcher(Fixture.sources(order: [.pack("S"), .pack("L")], user: [], packs: packs, builtIn: []))
        #expect(templateMatcher.candidates(forTail: "새사자성어 38번", isSecureTextEntry: false).map(\.suggestion.body) == ["L 본문 38"])

        // 문구 칩 + 시작 위치가 다른 템플릿: 문구가 칩이고 템플릿(더 긴 구간)은 같은 구간이 아니다.
        // 문구 앞을 띄운다 — 단어 경계(2026-10-08) 뒤로 「새사자성어 38번」의 문구 「사자성어38번」은 앞 「새」에 걸려 맞지 않는다
        let withPhrase = Fixture.matcher(Fixture.sources(order: [.userSnippets, .pack("L")], user: [Fixture.myIdiom38],
                                                         packs: packs, builtIn: []))
        #expect(withPhrase.candidates(forTail: "새 사자성어 38번", isSecureTextEntry: false).map(\.suggestion.body) == ["내가 쓴 38번"])
        #expect(withPhrase.candidates(forTail: "새사자성어 38번", isSecureTextEntry: false).map(\.suggestion.body) == ["L 본문 38"],
                "붙여 쓰면 문구가 경계에 걸려 빠지고 템플릿(줄 처음)이 칩 — 목록도 그 구간만")
    }

    @Test("★ AC-38 — 시작 위치가 다른 날짜·템플릿 겹침(「기한 3일 후 날짜」)은 같은 구간이 아니다")
    func differentStartAcrossBranches() throws {
        let clash = ["clash": ExternalPack(name: "기한", license: "자체", mode: .numbered, template: PackTemplate(
            patterns: [TemplatePattern(prefix: "기한", suffix: "일후날짜")], titleFormat: "기한 {n}일 후 날짜",
            items: [PackTemplateItem(n: 3, title: "", body: "템플릿 본문")]))]
        let matcher = Fixture.matcher(Fixture.sources(order: [.pack("clash")], user: [], packs: clash, builtIn: []))
        let candidates = matcher.candidates(forTail: "기한 3일 후 날짜", isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == [.date])
        #expect(candidates.first?.suggestion.trigger == "3일 후 날짜")
    }

    /// 문구 칩이 **짧은** 구간을 잡으면 뒤 분기(날짜·템플릿·성경)가 더 긴 구간에 맞아도 같은 구간이 아니다 — 분기 순서가 길이보다 먼저다
    @Test("★ AC-38 — 칩보다 긴 구간에 맞은 뒤 분기는 제외(날짜·템플릿·성경 각각)", arguments: [
        ("날짜", "오늘 날짜"),            // 날짜 파서는 「오늘 날짜」 전체
        ("12번", "사자성어 12번"),        // 템플릿은 「사자성어 12번」 전체
        ("1장1절", "창세기 1장 1절")      // 성경은 「창세기 1장 1절」 전체
    ])
    func laterBranchLongerSpanExcluded(trigger: String, tail: String) throws {
        let short = SnippetEntry(trigger: trigger, title: "짧은", body: "짧은 본문")
        let matcher = Fixture.matcher(Fixture.sources(user: [short], packs: Fixture.packs, builtIn: []))
        #expect(Fixture.matcher().suggestion(forTail: tail) != nil, "전제 — 문구가 없으면 뒤 분기가 이 꼬리에 맞는다")
        let candidates = matcher.candidates(forTail: tail, isSecureTextEntry: false)
        #expect(candidates.map(\.suggestion.body) == ["짧은 본문"], "\(tail)")
        #expect(matcher.suggestion(forTail: tail)?.alternativeCount == 0, "\(tail)")
    }

    @Test("AC-38 — 한 항목의 별칭 여럿이 같은 정규화로 겹쳐도 후보는 한 번")
    func aliasDeduplicated() {
        let aliased = SnippetEntry(triggers: ["새해인사", "새해 인사", "새 해 인 사"], title: "별칭", body: "별칭 본문")
        let matcher = Fixture.matcher(Fixture.sources(user: [aliased], packs: [:], builtIn: []))
        let candidates = matcher.candidates(forTail: "새해 인사", isSecureTextEntry: false)
        #expect(candidates.map(\.suggestion.body) == ["별칭 본문"])
        #expect(matcher.suggestion(forTail: "새해 인사")?.alternativeCount == 0)
    }

    @Test("★ 같은 출처의 같은 내용(제목·본문)은 한 번 — 출처가 다르면 둘 다(행으로 구별된다)")
    func identicalRowsDeduplicated() {
        let a = SnippetEntry(trigger: "새해인사", title: "새해 인사", body: "같은 본문")
        let b = SnippetEntry(trigger: "새해 인사", title: "새해 인사", body: "같은 본문")
        let sameOrigin = Fixture.matcher(Fixture.sources(user: [], packs: [:],
                                                         builtIn: [.init(packID: SnippetPack.greetings, entries: [a, b])]))
        #expect(sameOrigin.candidates(forTail: "새해인사", isSecureTextEntry: false).count == 1)
        #expect(sameOrigin.suggestion(forTail: "새해인사")?.alternativeCount == 0, "「+1」이 뜨지 않는다")

        let crossOrigin = Fixture.matcher(Fixture.sources(user: [a], packs: [:],
                                                          builtIn: [.init(packID: SnippetPack.greetings, entries: [b])]))
        #expect(crossOrigin.candidates(forTail: "새해인사", isSecureTextEntry: false).map(\.origin)
                == [.user, .builtIn(id: SnippetPack.greetings)])

        let differentBody = SnippetEntry(trigger: "새해 인사", title: "새해 인사", body: "다른 본문")
        let sameOriginDifferent = Fixture.matcher(Fixture.sources(user: [a, differentBody], packs: [:], builtIn: []))
        #expect(sameOriginDifferent.candidates(forTail: "새해인사", isSecureTextEntry: false).count == 2)
    }

    /// 실데이터 회귀 — `Greetings.json`·`Snippets.json`에는 띄어쓰기만 다른 옛 중복 항목이 23쌍 있다(제목·본문 동일, 정규화 전 시절의
    /// 별칭 표기). 걸러내지 않으면 **내장 인사말 칩마다 「+1」**이 붙고 패널에 똑같은 행이 두 줄 뜬다(U7 ① 구현 중 발견, 2026-10-07)
    @Test("★ 실데이터 — 내장 팩만으로는 어떤 단축어에도 「+n」이 뜨지 않는다")
    func bundledPacksHaveNoAlternatives() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TadakData/Sources/TadakData/Resources")
        func load(_ name: String) throws -> [SnippetEntry] {
            try JSONDecoder().decode([SnippetEntry].self, from: Data(contentsOf: resources.appendingPathComponent("\(name).json")))
        }
        let groups = [SnippetSourceComposer.BuiltInGroup(packID: SnippetPack.anthem, entries: try load("Snippets")),
                      SnippetSourceComposer.BuiltInGroup(packID: SnippetPack.greetings, entries: try load("Greetings"))]
        let sources = SnippetSourceComposer.compose(order: [], userEntries: [], packs: [:], builtInGroups: groups)
        let matcher = SnippetMatcher(bible: nil, entries: sources.entries, origins: sources.origins)
        var checked = 0
        for entry in sources.entries {
            for trigger in entry.triggers {
                let chip = try #require(matcher.suggestion(forTail: trigger), "\(trigger)")
                #expect(chip.alternativeCount == 0, "\(trigger)")
                checked += 1
            }
        }
        #expect(checked > 300)
    }

    @Test("★ 분기 순서 — 문구 → 템플릿 → 성경이 같은 구간 「창세기 1장 1절」에 함께 걸리면 셋 다, 그 순서로")
    func branchOrderSameSpan() {
        let mine = SnippetEntry(trigger: "창세기1장1절", title: "내 구절", body: "내가 쓴 구절")
        let packs = ["gen": ExternalPack(name: "구절 팩", license: "자체", mode: .numbered, template: PackTemplate(
            patterns: [TemplatePattern(prefix: "창세기", suffix: "장1절")], titleFormat: "창세기 {n}장 1절",
            items: [PackTemplateItem(n: 1, title: "", body: "템플릿 구절")]))]
        let matcher = Fixture.matcher(Fixture.sources(order: [.userSnippets, .pack("gen")], user: [mine], packs: packs, builtIn: []))
        let candidates = matcher.candidates(forTail: "창세기 1장 1절", isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == [.user, .pack(name: "구절 팩"), .bible])
        #expect(candidates.last?.suggestion.prefix == "[창세기 1장 1절] ", "성경 후보는 머리말 그대로")
    }

    @Test("분기 순서 — 문구 → 날짜(같은 구간 「오늘 날짜」)")
    func phraseThenDate() {
        let mine = SnippetEntry(trigger: "오늘날짜", title: "내 날짜", body: "내 날짜 문구")
        let matcher = Fixture.matcher(Fixture.sources(user: [mine], packs: [:], builtIn: []))
        let candidates = matcher.candidates(forTail: "오늘 날짜", isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == [.user, .date])
        #expect(candidates.last?.suggestion.body == "2026. 10. 7.")
    }

    @Test("성경 본문이 빈 절은 칩도 후보도 아니다 — 개수와 목록이 같은 판정을 쓴다")
    func emptyBibleVerseNotCounted() {
        struct HoleBible: BibleVerseRepository {
            func text(book: Int, chapter: Int, verse: Int) -> String? { verse == 2 ? "  " : "본문" }
        }
        let mine = SnippetEntry(trigger: "창세기1장2절", title: "내 구절", body: "내가 쓴 구절")
        let matcher = Fixture.matcher(Fixture.sources(user: [mine], packs: [:], builtIn: []), bible: HoleBible())
        #expect(matcher.suggestion(forTail: "창세기 1장 2절")?.alternativeCount == 0)
        #expect(matcher.candidates(forTail: "창세기 1장 2절", isSecureTextEntry: false).count == 1)
    }

    // MARK: AC-39 — 순서 = 분기 → U1 → 팩 내 패턴

    @Test("★ AC-39 — 팩 순서를 바꾸면 칩의 첫 후보와 목록 순서가 **함께** 바뀐다")
    func reorderMovesChipAndList() {
        let userFirst = Fixture.matcher(Fixture.sources(order: [.userSnippets, .pack("phr")]))
        let packFirst = Fixture.matcher(Fixture.sources(order: [.pack("phr"), .userSnippets]))
        let tail = "팀장님 새해인사"
        #expect(userFirst.candidates(forTail: tail, isSecureTextEntry: false).map(\.origin)
                == [.user, .pack(name: "회사 상용구"), .builtIn(id: SnippetPack.greetings)])
        #expect(packFirst.candidates(forTail: tail, isSecureTextEntry: false).map(\.origin)
                == [.pack(name: "회사 상용구"), .user, .builtIn(id: SnippetPack.greetings)], "내장 팩은 언제나 뒤")
        #expect(userFirst.suggestion(forTail: tail)?.body == "내가 쓴 새해 인사")
        #expect(packFirst.suggestion(forTail: tail)?.body == "팩의 새해 인사")

        let bFirst = Fixture.matcher(Fixture.sources(order: [.pack("idiomB"), .pack("idiomA")]))
        #expect(bFirst.candidates(forTail: "사자성어 12번", isSecureTextEntry: false).map(\.suggestion.body)
                == ["사자성어 팩 B 본문 12", "사자성어 팩 A 본문 12"])
        #expect(bFirst.suggestion(forTail: "사자성어 38번")?.body == "내가 쓴 38번", "문구가 템플릿보다 먼저(분기)")
        #expect(bFirst.candidates(forTail: "사자성어 38번", isSecureTextEntry: false).count == 1,
                "B가 소유하면 B에 38이 없어 템플릿 후보 없음(후퇴 금지)")
    }

    // MARK: AC-45 · AC-46 — secure·상한

    @Test("★ AC-45 — secure 입력란이면 빈 배열(칩과 같은 게이트)")
    func secureEmpty() {
        let matcher = Fixture.matcher()
        for (tail, _) in Self.table {
            #expect(matcher.candidates(forTail: tail, isSecureTextEntry: true).isEmpty, "\(tail)")
            #expect(matcher.suggestion(forTail: tail, isSecureTextEntry: true) == nil, "\(tail)")
        }
    }

    @Test("★ AC-46 · AC-42 — 상한 8: 10개가 겹치면 위 8개만, 칩 「+7」")
    func capAtEight() {
        let ten = (0..<10).map { SnippetEntry(trigger: "새해인사", title: "새해 \($0)", body: "본문 \($0)") }
        let matcher = Fixture.matcher(Fixture.sources(user: ten, packs: [:], builtIn: []))
        let candidates = matcher.candidates(forTail: "새해인사", isSecureTextEntry: false)
        #expect(candidates.map(\.suggestion.body) == (0..<8).map { "본문 \($0)" })
        #expect(matcher.suggestion(forTail: "새해인사")?.alternativeCount == 7)
        #expect(SnippetCandidateGate.limit == 8)
    }

    @Test("템플릿 상한 — 같은 틀 팩 16개가 모두 같은 n을 가져도 위 8개")
    func templateCap() {
        var packs: [String: ExternalPack] = [:]
        var order: [SnippetSourceSlot] = []
        for index in 0..<16 {
            packs["p\(index)"] = Fixture.numbered("팩\(index)", "사자성어", "번", items: [5])
            order.append(.pack("p\(index)"))
        }
        let matcher = Fixture.matcher(Fixture.sources(order: order, user: [], packs: packs, builtIn: []))
        #expect(matcher.candidates(forTail: "사자성어 5번", isSecureTextEntry: false).map(\.origin)
                == (0..<8).map { .pack(name: "팩\($0)") })
        #expect(matcher.suggestion(forTail: "사자성어 5번")?.alternativeCount == 7)
    }

    /// 분기 사이 상한(검증 `verify-u7.md` L-1) — `walk`의 **날짜 분기 앞·성경 분기 앞** `count < limit`를 잠근다.
    /// 그 줄이 빠지면 문구로 이미 8을 채운 같은 구간에 날짜·성경이 9번째로 붙어 목록 9행·칩 「+8」(AC-42 「최대 +7」 위반)이 된다
    @Test("★ AC-46 · AC-42 — 문구 8개로 상한을 채운 같은 구간의 날짜·성경 후보는 들어가지 않는다(8행, 「+7」)", arguments: [
        ("오늘날짜", "오늘 날짜", SnippetOrigin.date),
        ("창세기1장1절", "창세기 1장 1절", SnippetOrigin.bible)
    ])
    func laterBranchStopsAtCap(trigger: String, tail: String, later: SnippetOrigin) {
        func phrases(_ count: Int) -> [SnippetEntry] {
            (0..<count).map { SnippetEntry(trigger: trigger, title: "문구 \($0)", body: "본문 \($0)") }
        }
        // 전제 — 문구가 7개면 뒤 분기 후보가 같은 구간의 8번째로 들어온다
        let seven = Fixture.matcher(Fixture.sources(user: phrases(7), packs: [:], builtIn: []))
        #expect(seven.candidates(forTail: tail, isSecureTextEntry: false).map(\.origin)
                == Array(repeating: .user, count: 7) + [later], "\(tail)")

        let eight = Fixture.matcher(Fixture.sources(user: phrases(8), packs: [:], builtIn: []))
        #expect(eight.candidates(forTail: tail, isSecureTextEntry: false).map(\.suggestion.body)
                == (0..<8).map { "본문 \($0)" }, "\(tail)")
        #expect(eight.suggestion(forTail: tail)?.alternativeCount == 7, "\(tail)")
    }

    @Test("limit 인자 — 더 적게 달라면 그만큼(0 이하면 빈 배열)")
    func explicitLimit() {
        let matcher = Fixture.matcher()
        #expect(matcher.candidates(forTail: "팀장님 새해인사", isSecureTextEntry: false, limit: 2).count == 2)
        #expect(matcher.candidates(forTail: "팀장님 새해인사", isSecureTextEntry: false, limit: 0).isEmpty)
    }

    @Test("hasSameContent는 개수를 본다 — 「+n」이 바뀌면 칩을 다시 싣는다(F8)")
    func sameContentIncludesCount() {
        let one = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b")
        let two = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b", alternativeCount: 2)
        #expect(!one.hasSameContent(as: two))
        #expect(two.hasSameContent(as: two))
        #expect(one.alternativeCount == 0, "기본값 0 — 기존 호출부 그대로")
    }
}

@Suite("U7 ① — 출처(10-6 ⑥) · 조립")
struct SnippetOriginTests {

    @Test("★ 조립 — 항목별 출처: 내 채움글 / 팩 이름 / 내장 팩 id, 템플릿은 팩 이름")
    func composedOrigins() {
        let sources = Fixture.sources()
        #expect(sources.entries.count == 4)
        #expect((0..<4).map(sources.origins.entryOrigin(at:))
                == [.user, .user, .pack(name: "회사 상용구"), .builtIn(id: SnippetPack.greetings)])
        #expect(sources.origins.templateOrigin(sourceID: "idiomA") == .pack(name: "사자성어 팩 A"))
        #expect(sources.origins.templateOrigin(sourceID: "idiomB") == .pack(name: "사자성어 팩 B"))
    }

    @Test("내장 팩 둘(국가 상징문 → 인사·상용구)은 각자 id로 — 순서는 넘긴 그대로")
    func twoBuiltInGroups() {
        let anthem = SnippetEntry(trigger: "애국가1절", title: "애국가", body: "동해물과")
        let groups = [SnippetSourceComposer.BuiltInGroup(packID: SnippetPack.anthem, entries: [anthem]),
                      SnippetSourceComposer.BuiltInGroup(packID: SnippetPack.greetings, entries: [Fixture.builtInNewYear])]
        let sources = SnippetSourceComposer.compose(order: [], userEntries: [], packs: [:], builtInGroups: groups)
        #expect(sources.entries == [anthem, Fixture.builtInNewYear])
        #expect(sources.origins.entryOrigin(at: 0) == .builtIn(id: SnippetPack.anthem))
        #expect(sources.origins.entryOrigin(at: 1) == .builtIn(id: SnippetPack.greetings))
    }

    @Test("기존 compose(builtIn:)는 결과 entries·templates가 그대로 — 내장은 id 없는 내장 출처")
    func legacyComposeUnchanged() {
        let legacy = SnippetSourceComposer.compose(order: Fixture.defaultOrder, userEntries: [Fixture.myNewYear],
                                                   packs: Fixture.packs, builtIn: [Fixture.builtInNewYear])
        let grouped = SnippetSourceComposer.compose(order: Fixture.defaultOrder, userEntries: [Fixture.myNewYear],
                                                    packs: Fixture.packs, builtInGroups: Fixture.builtIn)
        #expect(legacy.entries == grouped.entries)
        #expect(legacy.templates?.ownership == grouped.templates?.ownership)
        #expect(legacy.origins.entryOrigin(at: legacy.entries.count - 1) == .builtIn(id: ""))
    }

    @Test("출처 없이 만든 매처(기존 호출부)는 문구를 「내 채움글」로 본다 — 깨지지 않는다")
    func missingOriginsFallBack() {
        let matcher = SnippetMatcher(bible: nil, entries: [Fixture.myNewYear, Fixture.builtInNewYear])
        #expect(matcher.candidates(forTail: "새해인사", isSecureTextEntry: false).map(\.origin) == [.user, .user])
        #expect(SnippetOrigins().templateOrigin(sourceID: "없음") == .pack(name: ""))
    }

    @Test("출처 표 — 구간만 든다(항목 수와 무관한 크기)")
    func originsAreSpans() {
        var origins = SnippetOrigins()
        origins.appendEntries(count: 80_000, origin: .pack(name: "큰 팩"))
        origins.appendEntries(count: 0, origin: .user)
        origins.appendEntries(count: 2, origin: .builtIn(id: SnippetPack.anthem))
        #expect(origins.spanCount == 2)
        #expect(origins.entryOrigin(at: 79_999) == .pack(name: "큰 팩"))
        #expect(origins.entryOrigin(at: 80_000) == .builtIn(id: SnippetPack.anthem))
        #expect(origins.entryOrigin(at: 80_002) == .user, "범위 밖은 기본값")
    }
}

@Suite("U7 ① — 판정 게이트 · 라벨 표 (AC-41~43·46)")
struct SnippetCandidateGateTests {

    @Test("★ AC-42 — 후보 1개면 열지 않는다, 2개 이상만", arguments: [(0, false), (1, false), (2, true), (8, true)])
    func canOpen(count: Int, expected: Bool) {
        #expect(SnippetCandidateGate.canOpen(candidateCount: count) == expected)
    }

    /// (trigger, 꼬리) → 꼬리가 아직 그 trigger로 끝나는가 — 무장·패널 유지·행 탭 직전이 **같은 식**을 쓴다
    @Test("★ AC-41·43 — isStillValid 표", arguments: [
        ("새해인사", "팀장님 새해인사", true),
        ("새해인사", "팀장님 새해인사 ", false),          // 꼬리가 바뀌었다
        ("새해인사", "", false),                         // 빈 꼬리(다른 앱·커서 이동 뒤)
        ("새해인사", "새해인사\n", false),               // 줄바꿈
        ("", "팀장님 새해인사", false),                   // 빈 trigger는 언제나 무효
        ("사자성어 12번", "오늘은 사자성어 12번", true),
        ("사자성어 12번", "오늘은 사자성어 1", false)
    ])
    func stillValid(trigger: String, tail: String, expected: Bool) {
        #expect(SnippetCandidateGate.isStillValid(trigger: trigger, tail: tail) == expected)
    }

    @Test("★ AC-43 — 무장: 후보 2개 이상 + 꼬리 정합일 때만(퇴장 중 칩·1개 칩은 무시)")
    func canArm() {
        let chip = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b", alternativeCount: 2)
        let single = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b")
        #expect(SnippetCandidateGate.canArm(chip: chip, tail: "팀장님 새해인사"))
        #expect(!SnippetCandidateGate.canArm(chip: chip, tail: "팀장님 새해인사 드려요"), "칩이 사라진 뒤(꼬리 바뀜)")
        #expect(!SnippetCandidateGate.canArm(chip: single, tail: "팀장님 새해인사"), "1개면 무장하지 않는다(진동 없음)")
        #expect(!SnippetCandidateGate.canArm(chip: nil, tail: "팀장님 새해인사"))
    }

    @Test("★ AC-41 — 패널 유지: 칩이 그대로이고 꼬리가 패널 trigger로 끝날 때만")
    func panelStaysOpen() {
        let chip = SnippetSuggestion(trigger: "새해인사", title: "t", body: "b", alternativeCount: 2)
        #expect(SnippetCandidateGate.keepsPanelOpen(panelTrigger: "새해인사", chip: chip, tail: "팀장님 새해인사"))
        #expect(!SnippetCandidateGate.keepsPanelOpen(panelTrigger: "새해인사", chip: nil, tail: "팀장님 새해인사"), "칩이 사라짐")
        #expect(!SnippetCandidateGate.keepsPanelOpen(panelTrigger: "새해인사", chip: chip, tail: "팀장님"), "꼬리 변경")
        let other = SnippetSuggestion(trigger: "팀장님새해인사", title: "t", body: "b")
        #expect(!SnippetCandidateGate.keepsPanelOpen(panelTrigger: "새해인사", chip: other, tail: "팀장님새해인사"),
                "칩의 구간이 바뀌면(매처 재구성 등) 목록이 낡았다")
    }

    /// (누른 칩, 지금 칩, 꼬리) → 무장·열기 허락. 구간은 누른 칩, 개수는 지금 칩(③ 배선 — 조립 지점은 이 식만 부른다)
    @Test("★ AC-43 — 누른 칩으로 무장·열기: 구간은 누른 칩, 개수는 지금 칩", arguments: [
        // 누른 칩 = 지금 칩, 후보 3개, 꼬리 정합
        ("새해인사", 2, "새해인사", 2, "팀장님 새해인사", true),
        // 누르는 사이 「+n」이 바뀜(2 → 1) — 지금 칩 기준이라 무장한다
        ("새해인사", 2, "새해인사", 1, "팀장님 새해인사", true),
        // 누르는 사이 다른 후보가 사라짐(2 → 0) — 지금 칩 기준으로 무장하지 않는다
        ("새해인사", 2, "새해인사", 0, "팀장님 새해인사", false),
        // 누른 때엔 1개였지만 지금 칩은 2개 이상 — 지금 칩 기준이라 무장한다
        ("새해인사", 0, "새해인사", 1, "팀장님 새해인사", true),
        // 퇴장 중 옛 칩 — 지금 칩이 다른 구간(이어 친 글자로 더 긴 단축어가 맞음)
        ("새해인사", 2, "팀장님새해인사", 2, "팀장님새해인사", false),
        // 퇴장 중 옛 칩 — 지금 칩이 없음
        ("새해인사", 2, nil, 0, "팀장님 새해인사 드려요", false),
        // 칩은 같은데 꼬리가 어긋남(호스트가 문서를 바꿈)
        ("새해인사", 2, "새해인사", 2, "팀장님", false)
    ] as [(String, Int, String?, Int, String, Bool)])
    func canArmPressed(pressedTrigger: String, pressedCount: Int, currentTrigger: String?, currentCount: Int,
                       tail: String, expected: Bool) {
        let pressed = SnippetSuggestion(trigger: pressedTrigger, title: "t", body: "b", alternativeCount: pressedCount)
        let current = currentTrigger.map {
            SnippetSuggestion(trigger: $0, title: "t", body: "b", alternativeCount: currentCount)
        }
        #expect(SnippetCandidateGate.canArm(pressed: pressed, current: current, tail: tail) == expected)
    }

    /// 행 탭 — 패널 열림(패널 trigger 있음) ∧ 지금 목록의 행 ∧ 꼬리 정합. 더블탭 둘째 탭은 패널이 닫혀 걸린다
    @Test("★ AC-41 — 후보 행 탭 받기 표")
    func acceptsRowTap() {
        let first = SnippetCandidate(suggestion: SnippetSuggestion(trigger: "새해인사", title: "a", body: "A", alternativeCount: 1),
                                     origin: .user)
        let second = SnippetCandidate(suggestion: SnippetSuggestion(trigger: "새해인사", title: "b", body: "B"),
                                      origin: .builtIn(id: SnippetPack.greetings))
        let stranger = SnippetCandidate(suggestion: SnippetSuggestion(trigger: "새해인사", title: "c", body: "C"), origin: .user)
        let panel = [first, second]
        let tail = "팀장님 새해인사"
        #expect(SnippetCandidateGate.acceptsRowTap(second, panelTrigger: "새해인사", panelCandidates: panel, tail: tail))
        #expect(SnippetCandidateGate.acceptsRowTap(first, panelTrigger: "새해인사", panelCandidates: panel, tail: tail))
        #expect(!SnippetCandidateGate.acceptsRowTap(second, panelTrigger: nil, panelCandidates: [], tail: tail),
                "더블탭 둘째 탭 — 첫 탭이 패널을 닫았다")
        #expect(!SnippetCandidateGate.acceptsRowTap(second, panelTrigger: nil, panelCandidates: panel, tail: tail),
                "패널 trigger가 없으면(닫힘) 목록이 남아 있어도 받지 않는다")
        #expect(!SnippetCandidateGate.acceptsRowTap(stranger, panelTrigger: "새해인사", panelCandidates: panel, tail: tail),
                "지금 목록에 없는 행(다시 연 패널의 옛 행)")
        #expect(!SnippetCandidateGate.acceptsRowTap(second, panelTrigger: "새해인사", panelCandidates: panel, tail: "팀장님"),
                "꼬리가 바뀌었다")
        #expect(!SnippetCandidateGate.acceptsRowTap(second, panelTrigger: "인사", panelCandidates: panel, tail: tail),
                "패널 trigger와 행 trigger가 다르다")
    }

    /// ✕ — 패널이 열려 있으면 **패널만** 닫는다(10-6 ⑤ · AC-43). 닫혀 있으면 지금 규칙 그대로(D18·D19 포함)
    @Test("★ AC-43 — ✕ 효과 표", arguments: [
        (true, false, true, SnippetDismissEffect.closeCandidatesPanel),
        (true, true, true, SnippetDismissEffect.closeCandidatesPanel),
        (false, false, true, SnippetDismissEffect.dismissSuggestions(hideSnippetTail: "팀장님 새해인사")),
        (false, true, true, SnippetDismissEffect.dismissSuggestions(hideSnippetTail: nil)),    // D19 — 붙여넣기 칩만 물린다
        (false, false, false, SnippetDismissEffect.dismissSuggestions(hideSnippetTail: nil))
    ])
    func dismissEffect(panelOpen: Bool, pasteChip: Bool, snippetChip: Bool, expected: SnippetDismissEffect) {
        #expect(SnippetCandidateGate.dismissEffect(
            isCandidatesPanelOpen: panelOpen, hasPasteChip: pasteChip, hasSnippetChip: snippetChip,
            tail: "팀장님 새해인사") == expected)
    }

    @Test("★ AC-46 · AC-42 — 칩 힌트·동작·「+n」 문자열: 0개면 없음(자리 0), n개면 n", arguments: [0, 1, 2, 7])
    func chipTexts(alternatives: Int) {
        #expect(SnippetCandidateText.chipHint(alternativeCount: alternatives) == (alternatives == 0 ? nil : "다른 후보 \(alternatives)개"))
        #expect(SnippetCandidateText.alternativeBadge(alternativeCount: alternatives) == (alternatives == 0 ? "" : "+\(alternatives)"))
        #expect(SnippetCandidateText.chipActionName == "다른 후보 보기")
    }

    @Test("★ AC-46 — 행 라벨 「채움글 <제목>, <출처>, 붙여넣기」 · 출처 이름 표")
    func rowLabels() {
        func row(_ origin: SnippetOrigin, title: String = "새해 인사") -> String {
            SnippetCandidateText.rowLabel(SnippetCandidate(
                suggestion: SnippetSuggestion(trigger: "새해인사", title: title, body: "b"), origin: origin))
        }
        #expect(row(.user) == "채움글 새해 인사, 내 채움글, 붙여넣기")
        #expect(row(.pack(name: "회사 상용구")) == "채움글 새해 인사, 회사 상용구, 붙여넣기")
        #expect(row(.builtIn(id: SnippetPack.greetings)) == "채움글 새해 인사, 인사·상용구, 붙여넣기")
        #expect(row(.builtIn(id: SnippetPack.anthem)) == "채움글 새해 인사, 국가 상징문, 붙여넣기")
        #expect(row(.bible, title: "창 1:1") == "채움글 창 1:1, 성경, 붙여넣기")
        #expect(SnippetCandidateText.originName(.date) == "날짜·시간")
        #expect(SnippetCandidateText.originName(.builtIn(id: "")) == "기본 채움글")
        #expect(SnippetCandidateText.originName(.pack(name: "")) == "외부 팩")
    }

    @Test("날짜 후보 행은 값을 읽는다(기존 칩 라벨의 spokenValue 규칙)")
    func dateRowReadsValue() throws {
        let date = try #require(Fixture.dates.suggestion(forTail: "오늘 날짜"))
        let label = SnippetCandidateText.rowLabel(SnippetCandidate(suggestion: date, origin: .date))
        #expect(label == "채움글 오늘 날짜, 2026년 10월 7일, 날짜·시간, 붙여넣기")
    }

    @Test("패널 머리줄(R32 (다)) — 「「trigger」 후보 n개」")
    func panelHeader() {
        #expect(SnippetCandidateText.panelHeader(trigger: "새해인사", count: 3) == "「새해인사」 후보 3개")
    }
}

@Suite("U7 ① — 후보 삽입은 insertSnippet 그대로 (AC-40·41·44)")
struct SnippetCandidateInsertTests {

    @MainActor
    @Test("★ AC-40 — 둘째·셋째 후보를 넣으면 trigger만큼 지운 자리에 그 본문", arguments: [1, 2])
    func insertsOtherCandidate(index: Int) throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("팀장님 새해인사")
        let candidates = Fixture.matcher().candidates(forTail: controller.textTail, isSecureTextEntry: false)
        #expect(controller.insertSnippet(candidates[index].suggestion))
        #expect(output.text == "팀장님 " + candidates[index].suggestion.body)
    }

    @MainActor
    @Test("AC-40 — 성경 후보는 머리말(친 원문)까지 들어간다")
    func bibleCandidateWithPrefix() throws {
        let mine = SnippetEntry(trigger: "창세기1장1절", title: "내 구절", body: "내가 쓴 구절")
        let matcher = Fixture.matcher(Fixture.sources(user: [mine], packs: [:], builtIn: []))
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("오늘 묵상 창세기 1장 1절")
        let candidates = matcher.candidates(forTail: controller.textTail, isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == [.user, .bible])
        #expect(controller.insertSnippet(candidates[1].suggestion))
        #expect(output.text == "오늘 묵상 [창세기 1장 1절] 성경 1:1:1")
    }

    @MainActor
    @Test("★ AC-41 — 꼬리가 바뀐 뒤 후보 탭은 문서를 건드리지 않는다 · 같은 후보 둘째 탭도 무동작")
    func staleTapDoesNothing() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("팀장님 새해인사")
        let candidates = Fixture.matcher().candidates(forTail: controller.textTail, isSecureTextEntry: false)
        controller.insertProvidedText(" 드려요")
        let before = output.text
        #expect(!controller.insertSnippet(candidates[1].suggestion))
        #expect(output.text == before)

        let fresh = RecordingOutput()
        let again = InputController(output: fresh)
        again.insertProvidedText("팀장님 새해인사")
        let rows = Fixture.matcher().candidates(forTail: again.textTail, isSecureTextEntry: false)
        #expect(again.insertSnippet(rows[2].suggestion))
        let inserted = fresh.text
        #expect(!again.insertSnippet(rows[2].suggestion), "더블탭 둘째 — 꼬리가 본문으로 바뀌었다")
        #expect(fresh.text == inserted)
    }

    /// 기존 「채움글 본문에 한 글자 이어 쳐도 학습하지 않는다」(SuggestionTests)를 **둘째 후보** 경로로
    @MainActor
    @Test("★ AC-44 — 둘째 후보를 넣은 뒤 한 글자 이어 쳐도 그 run은 학습하지 않는다")
    func candidateBodyNotLearned() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }
        let mine = SnippetEntry(trigger: "애국가1절", title: "내 애국가", body: "내가 쓴 애국가")
        let anthem = SnippetEntry(trigger: "애국가 1절", title: "애국가 1절", body: "동해물과 백두산이")
        let matcher = Fixture.matcher(Fixture.sources(user: [mine], packs: [:],
                                                      builtIn: [.init(packID: SnippetPack.anthem, entries: [anthem])]))

        for key in ["d", "o", "r", "n", "r", "r", "k"] { controller.handle(.character(key)) }
        controller.handle(.space)
        controller.handle(.character("1"))
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }  // 절
        let candidates = matcher.candidates(forTail: controller.textTail, isSecureTextEntry: false)
        #expect(candidates.map(\.origin) == [.user, .builtIn(id: SnippetPack.anthem)])
        #expect(controller.insertSnippet(candidates[1].suggestion))
        #expect(output.text.hasSuffix("동해물과 백두산이"))

        for key in ["d", "y"] { controller.handle(.character(key)) }  // 요
        controller.handle(.space)
        #expect(committed == ["애국가"], "본문 조각이 섞인 '백두산이요'는 학습되지 않는다")
    }
}

@Suite("U7 ① — 템플릿 같은 구간 후보 (10-6 ① · 10-4 불변)")
struct PackTemplateCandidatesTests {

    private static func source(_ id: String, _ patterns: [(String, String)], items: [Int]) -> PackTemplateMatcher.Source {
        .init(id: id, template: PackTemplate(
            patterns: patterns.map { TemplatePattern(prefix: $0.0, suffix: $0.1) }, titleFormat: "\(id) {n}",
            items: items.map { PackTemplateItem(n: $0, title: "", body: "\(id) \($0)") }))
    }

    private static let matcher = PackTemplateMatcher(sources: [
        source("A", [("사자성어", "번"), ("성어", "번")], items: [1, 7, 12]),
        source("B", [("사자성어", "번")], items: [1, 12, 99]),
        source("C", [("성어", "번")], items: [12]),
        source("D", [("고사성어", "번")], items: [12])
    ])

    @Test("★ 첫째 == match(tail:) — 칩 판정 불변(여러 꼬리)", arguments: [
        "사자성어 12번", "성어12번", "고사성어 12번", "사자성어 99번", "사자성어 1번", "사자성어 7번", "그냥", "사자성어 012번", ""
    ])
    func firstIsMatch(tail: String) {
        #expect(Self.matcher.matches(tail: tail).first == Self.matcher.match(tail: tail))
    }

    @Test("소유 팩 → 같은 쌍의 후순위 팩(목록 순서), n이 없는 팩은 건너뛴다")
    func ownerThenAlternates() {
        #expect(Self.matcher.matches(tail: "사자성어 12번").map(\.sourceID) == ["A", "B"])
        #expect(Self.matcher.matches(tail: "오늘의 성어 12번").map(\.sourceID) == ["A", "C"])
        #expect(Self.matcher.matches(tail: "사자성어 7번").map(\.sourceID) == ["A"], "B에 7이 없다")
        #expect(Self.matcher.matches(tail: "사자성어 99번").isEmpty, "소유 팩 A에 99가 없다 — B에 있어도 후퇴 금지")
        #expect(Self.matcher.matches(tail: "고사성어 12번").map(\.sourceID) == ["D"], "다른 쌍이 이긴 더 긴 구간 — 「성어 12번」 후보는 시작 위치가 달라 제외")
    }

    @Test("모든 후보의 trigger는 칩과 같은 원문 구간")
    func sameTrigger() {
        #expect(Set(Self.matcher.matches(tail: "앞말 사자성어 12번").map(\.trigger)) == ["사자성어 12번"])
    }

    @Test("limit — 소유 팩만 달라면 칩 하나")
    func limit() {
        #expect(Self.matcher.matches(tail: "사자성어 12번", limit: 1).map(\.sourceID) == ["A"])
        #expect(Self.matcher.matches(tail: "사자성어 12번", limit: 0).isEmpty)
    }

    @Test("소유권 표(앱 팩 정보 화면)는 U7 전과 같다")
    func ownershipUnchanged() {
        let pair = TemplatePattern(prefix: "사자성어", suffix: "번")
        let alias = TemplatePattern(prefix: "성어", suffix: "번")
        #expect(Self.matcher.ownership == [
            .init(sourceID: "A", pattern: pair, status: .owned),
            .init(sourceID: "A", pattern: alias, status: .owned),
            .init(sourceID: "B", pattern: pair, status: .outranked(by: "A")),
            .init(sourceID: "C", pattern: alias, status: .outranked(by: "A")),
            .init(sourceID: "D", pattern: TemplatePattern(prefix: "고사성어", suffix: "번"), status: .owned)
        ])
    }

    @Test("후순위 팩 저장본의 번호가 정렬돼 있지 않아도(손상) 찾는다 — 같은 번호는 뒤가 이긴다")
    func unsortedAlternateItems() {
        let unsorted = PackTemplateMatcher.Source(id: "U", template: PackTemplate(
            patterns: [TemplatePattern(prefix: "사자성어", suffix: "번")], titleFormat: "U {n}",
            items: [PackTemplateItem(n: 30, title: "", body: "U 30"), PackTemplateItem(n: 12, title: "", body: "앞 12"),
                    PackTemplateItem(n: 5, title: "", body: "U 5"), PackTemplateItem(n: 12, title: "", body: "뒤 12")]))
        let matcher = PackTemplateMatcher(sources: [Self.source("A", [("사자성어", "번")], items: [5, 12, 30]), unsorted])
        #expect(matcher.matches(tail: "사자성어 12번").map(\.body) == ["A 12", "뒤 12"])
        #expect(matcher.matches(tail: "사자성어 30번").map(\.body) == ["A 30", "U 30"])
        #expect(matcher.matches(tail: "사자성어 5번").map(\.body) == ["A 5", "U 5"])
    }

    @Test("정렬된 큰 팩 — 이진 탐색으로 처음·끝·없는 번호", arguments: [1, 2_500, 5_000, 5_001])
    func binarySearchEdges(n: Int) {
        let big = (1...5_000).map { $0 }
        let matcher = PackTemplateMatcher(sources: [Self.source("A", [("사자성어", "번")], items: big + [5_001]),
                                                    Self.source("B", [("사자성어", "번")], items: big)])
        #expect(matcher.matches(tail: "사자성어 \(n)번").map(\.sourceID) == (n <= 5_000 ? ["A", "B"] : ["A"]))
    }

    @Test("한 팩이 같은 구간에 맞는 쌍을 둘 가져도 같은 (팩, 번호)는 한 번 — 다른 소유 쌍의 같은 구간 후보는 더한다")
    func sameSpanOtherPairDeduplicated() {
        // (창세기, 장1절)과 (창세기1장, 절)은 「창세기 1장 1절」에서 같은 구간·같은 n=1
        let both = Self.source("A", [("창세기", "장1절"), ("창세기1장", "절")], items: [1])
        let other = Self.source("B", [("창세기1장", "절")], items: [1])
        let matcher = PackTemplateMatcher(sources: [both, other])
        #expect(matcher.matches(tail: "창세기 1장 1절").map(\.sourceID) == ["A", "B"])
    }

    /// 검증 `verify-u7.md` R-3 — 사장님 결정(2026-10-08): **지금 동작 유지.** 후퇴 금지(소유 팩에 n이 없으면 빈 배열)는 **이긴 쌍**에만
    /// 걸린다. 같은 구간을 덮는 다른 소유 쌍은 그 소유 팩에 n이 없으면 그 행만 빠지고, 그 쌍의 후순위 팩(n 있음) 행은 들어간다
    @Test("다른 소유 쌍의 소유 팩에 n이 없으면 그 행만 빠지고 그 쌍의 후순위 팩(n 있음) 행은 들어간다")
    func otherPairOwnerMissingNumberKeepsAlternate() {
        // 「창세기 1장 1절」에서 (창세기, 장1절)과 (창세기1장, 절)은 literal 길이 6으로 같고 같은 구간·같은 n=1 — 목록 순서 A → C → B
        let matcher = PackTemplateMatcher(sources: [
            Self.source("A", [("창세기", "장1절")], items: [1]),   // 이긴 쌍의 소유 팩
            Self.source("C", [("창세기1장", "절")], items: [2]),   // 다른 쌍의 소유 팩 — 1이 없다
            Self.source("B", [("창세기1장", "절")], items: [1])    // 그 쌍의 후순위 팩 — 1이 있다
        ])
        #expect(matcher.matches(tail: "창세기 1장 2절").map(\.sourceID) == ["C"], "전제 — (창세기1장, 절)은 C가 소유한다")
        #expect(matcher.match(tail: "창세기 1장 1절")?.sourceID == "A", "칩은 이긴 쌍의 소유 팩")
        #expect(matcher.matches(tail: "창세기 1장 1절").map(\.sourceID) == ["A", "B"], "C는 빠지고 B는 들어간다")

        // 칩 「+n」과 목록이 같은 판정을 쓴다(SnippetMatcher 경로 — 출처는 팩 이름)
        let packs = ["a": Fixture.numbered("A", "창세기", "장1절", items: [1]),
                     "c": Fixture.numbered("C", "창세기1장", "절", items: [2]),
                     "b": Fixture.numbered("B", "창세기1장", "절", items: [1])]
        let snippets = Fixture.matcher(Fixture.sources(order: [.pack("a"), .pack("c"), .pack("b")], user: [], packs: packs,
                                                       builtIn: []), dates: nil, bible: nil)
        #expect(snippets.candidates(forTail: "창세기 1장 1절", isSecureTextEntry: false).map(\.origin)
                == [.pack(name: "A"), .pack(name: "B")])
        #expect(snippets.suggestion(forTail: "창세기 1장 1절")?.alternativeCount == 1)
    }
}
