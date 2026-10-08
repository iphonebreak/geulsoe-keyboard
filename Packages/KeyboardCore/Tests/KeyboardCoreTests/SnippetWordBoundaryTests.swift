import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// 채움글 단축어 **단어 경계** (사장님 결정 2026-10-08, 1.3.0 — PDR `snippet-shortcut-terms.md` 7절 · `external-snippet-packs.md` R48).
//
// 맞은 구간 첫 글자의 **바로 앞 글자**(공백을 건너뛰지 않은 원문)가 줄 처음·공백·개행·문장부호/기호일 때만 맞은 것으로 친다.
// 앞이 문자(한글·자모·라틴…)·숫자면 앞말에 붙은 것이라 칩이 없다 — 실기에서 단축어 `주소`(본문 「서울주소」)가 「서울주소」 끝에
// 떠서 탭하면 「서울서울주소」가 됐다. 문구 needle·번호형 틀·날짜 팩·U7 후보에 적용, **성경 참조 파서는 제외**.

private struct VerseBible: BibleVerseRepository {
    func text(book: Int, chapter: Int, verse: Int) -> String? { "성경 \(book):\(chapter):\(verse)" }
}

private enum Boundary {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        return calendar
    }()
    static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 10))!
    static let dates = DateSnippetParser(style: .formal, calendar: calendar, now: { now })

    static let address = SnippetEntry(trigger: "주소", title: "주소", body: "서울주소")
    static let home = SnippetEntry(trigger: "우리집주소", title: "우리집", body: "서울시 어딘가 1")
    static let homeShort = SnippetEntry(trigger: "집주소", title: "집", body: "집 주소 본문")
    static let newYear = SnippetEntry(trigger: "새해인사", title: "새해", body: "새해 복 많이 받으세요")
    static let greeting = SnippetEntry(trigger: "인사", title: "인사", body: "안녕하세요")

    static func idioms(_ id: String, _ prefix: String, items: [Int]) -> PackTemplateMatcher.Source {
        PackTemplateMatcher.Source(id: id, template: PackTemplate(
            patterns: [TemplatePattern(prefix: prefix, suffix: "번")], titleFormat: "\(prefix) {n}번",
            items: items.map { PackTemplateItem(n: $0, title: "", body: "\(id) 본문 \($0)") }))
    }
}

@Suite("채움글 단어 경계 — 문구 needle")
struct SnippetWordBoundaryPhraseTests {

    private let matcher = SnippetMatcher(bible: nil, entries: [Boundary.address])

    /// 꼬리 → 칩의 trigger(지울 원문). nil이면 칩 없음
    private static let table: [(tail: String, trigger: String?, why: String)] = [
        ("서울주소", nil, "앞이 한글 — 앞말에 붙었다(실기 버그)"),
        ("서울 주소", "주소", "앞이 공백"),
        ("주소", "주소", "줄 처음(꼬리 맨 앞, 잘리지 않음)"),
        ("(주소", "주소", "앞이 여는 괄호"),
        ("「주소", "주소", "앞이 낫표"),
        ("「주소」", nil, "끝이 단축어가 아니다 — 끝 맞춤 규칙은 그대로"),
        ("서울,주소", "주소", "앞이 쉼표"),
        ("서울.주소", "주소", "앞이 마침표"),
        ("서울2주소", nil, "앞이 숫자"),
        ("서울\n주소", "주소", "줄바꿈 뒤 — 새 줄의 처음"),
        ("서울\r\n주소", "주소", "CRLF 뒤"),
        ("서울\t주소", "주소", "앞이 탭(공백)"),
        ("서울\u{00A0}주소", "주소", "앞이 NBSP(공백)"),
        ("Seoul주소", nil, "앞이 라틴 문자"),
        ("서울ㄱ주소", nil, "앞이 자모(문자)"),
        ("서울ㆍ주소", nil, "앞이 천지인 미확정 점(ㆍ U+318D — 문자)"),
        ("서울😀주소", "주소", "앞이 이모지 — 기호로 본다"),
        ("서울👍🏻주소", "주소", "앞이 피부색 이모지 — 기호"),
        ("서울1️⃣주소", nil, "앞이 키캡 숫자 이모지 — isNumber라 숫자로 본다"),
        ("서울_주소", "주소", "앞이 밑줄 — 문장부호"),
        ("서울₩주소", "주소", "앞이 통화 기호"),
        ("서울 주 소", "주 소", "★ 단축어 안 띄어쓰기 무시는 그대로 — 앞은 공백"),
        ("서울주 소", nil, "★ 안 띄어쓰기가 있어도 첫 글자(주) 앞은 「울」")
    ]

    @Test("표 — 앞 글자가 줄 처음·공백·문장부호/기호일 때만 칩", arguments: table)
    func phraseTable(row: (tail: String, trigger: String?, why: String)) {
        #expect(matcher.suggestion(forTail: row.tail)?.trigger == row.trigger, "\(row.why)")
    }

    @Test("★ 앞 글자는 공백을 건너뛰지 않은 원문 기준 — 정규화 인덱스로 보면 「서울 주소」가 「서울주소」로 오판된다")
    func previousCharacterIsRaw() {
        let matcher = SnippetMatcher(bible: nil, entries: [Boundary.home])
        #expect(matcher.suggestion(forTail: "우 리 집 주 소")?.trigger == "우 리 집 주 소", "안 띄어쓰기 무시 — 그대로")
        #expect(matcher.suggestion(forTail: "보내줄게 우리집 주소")?.trigger == "우리집 주소", "앞 공백은 지울 구간에 안 든다")
        #expect(matcher.suggestion(forTail: "보내줄게우리집주소") == nil, "앞이 「게」")
        #expect(matcher.suggestion(forTail: "보내줄게우리 집주소") == nil, "첫 글자(우) 앞은 「게」 — 안 공백은 경계가 아니다")
    }

    @Test("★ 지울 길이 불변 — 꼬리 원문에서 맞은 구간(공백 포함)이고 경계 앞 공백은 들지 않는다")
    func deleteLengthUnchanged() throws {
        let chip = try #require(matcher.suggestion(forTail: "서울 주 소"))
        #expect(chip.trigger == "주 소")
        #expect(chip.triggerLength == 3, "정규화 길이 2가 아니라 원문 3")
        let atStart = try #require(matcher.suggestion(forTail: "주소"))
        #expect(atStart.triggerLength == 2)
    }

    @Test("한 줄 위의 글자는 보지 않는다 — 줄바꿈 뒤 첫 글자는 줄 처음")
    func newlineIsLineStart() {
        #expect(matcher.suggestion(forTail: "가나다라마바사서울\n주소")?.trigger == "주소")
        #expect(matcher.suggestion(forTail: "가나다라\n서울주소") == nil)
    }
}

@Suite("채움글 단어 경계 — 긴 needle이 경계에 걸리면 짧은 needle")
struct SnippetWordBoundaryFallbackTests {

    private let matcher = SnippetMatcher(bible: nil, entries: [Boundary.newYear, Boundary.greeting])

    @Test("표 — 각 후보를 따로 판정한다(첫 매치 = 경계를 통과한 가장 긴 needle)", arguments: [
        ("새해인사", "새해인사", "새해"),
        ("새해 인사", "새해 인사", "새해"),            // ★ 짧은 「인사」도 경계를 통과하지만 길이 내림차순 첫 매치가 이긴다(불변식)
        ("덕담 새해 인사", "새해 인사", "새해"),
        ("그새해 인사", "인사", "인사"),              // 긴 needle(앞 「그」) 실패 → 짧은 needle(앞 공백) 통과
        ("(새해인사", "새해인사", "새해")
    ] as [(String, String, String)])
    func fallback(row: (tail: String, trigger: String, title: String)) throws {
        let chip = try #require(matcher.suggestion(forTail: row.tail))
        #expect(chip.trigger == row.trigger)
        #expect(chip.title == row.title)
    }

    @Test("긴 needle도 짧은 needle도 경계에 걸리면 칩 없음", arguments: ["그새해인사", "새해 그인사", "x새해인사"])
    func bothFail(tail: String) {
        #expect(matcher.suggestion(forTail: tail) == nil)
    }

    @Test("PDR 7절 예 — 「우리집주소」 실패 뒤 「집주소」도 앞이 「리」라 실패")
    func designExample() {
        let matcher = SnippetMatcher(bible: nil, entries: [Boundary.home, Boundary.homeShort])
        #expect(matcher.suggestion(forTail: "너우리집주소") == nil)
        #expect(matcher.suggestion(forTail: "너우리 집주소")?.title == "집", "짧은 needle 앞이 공백이면 그쪽이 뜬다")
        #expect(matcher.suggestion(forTail: "너 우리집주소")?.title == "우리집")
    }
}

@Suite("채움글 단어 경계 — 번호형 틀")
struct SnippetWordBoundaryTemplateTests {

    private static func matcher(_ sources: [PackTemplateMatcher.Source], entries: [SnippetEntry] = []) -> SnippetMatcher {
        SnippetMatcher(bible: nil, entries: entries, templates: PackTemplateMatcher(sources: sources))
    }

    @Test("표 — 틀의 첫 글자(접두 첫 글자) 앞이 경계", arguments: [
        ("고사성어12번", "고사성어12번"),
        ("고사성어 12번", "고사성어 12번"),
        ("옛 고사성어12번", "고사성어12번"),
        ("(고사성어12번", "고사성어12번"),
        ("옛고사성어12번", nil),
        ("2고사성어12번", nil)
    ] as [(String, String?)])
    func table(row: (tail: String, trigger: String?)) {
        let matcher = Self.matcher([Boundary.idioms("A", "고사성어", items: [12])])
        #expect(matcher.suggestion(forTail: row.tail)?.trigger == row.trigger)
        #expect(PackTemplateMatcher(sources: [Boundary.idioms("A", "고사성어", items: [12])]).match(tail: row.tail)?.trigger
                    == row.trigger, "단독 API도 같은 규칙")
    }

    @Test("긴 틀이 경계에 걸리면 짧은 틀 — 문구와 같은 규칙(후퇴 금지는 「맞은」 틀에 대한 것)")
    func shorterPattern() {
        let sources = [Boundary.idioms("long", "고사성어", items: [12]), Boundary.idioms("short", "성어", items: [12])]
        let matcher = Self.matcher(sources)
        #expect(matcher.suggestion(forTail: "고사성어12번")?.body == "long 본문 12")
        #expect(matcher.suggestion(forTail: "옛고사성어12번") == nil, "짧은 틀(성어) 앞도 「사」")
        #expect(matcher.suggestion(forTail: "옛고사 성어12번")?.body == "short 본문 12", "짧은 틀 앞이 공백")
        #expect(matcher.suggestion(forTail: "옛고사 성어12번")?.trigger == "성어12번")
    }

    @Test("★ 정적 단축어의 가림이 입력에 따라 갈린다 — 「12번」 앞이 「어」면 틀, 공백이면 정적 단축어")
    func shadowingDependsOnSeparator() {
        let staticTwelve = SnippetEntry(trigger: "12번", title: "정적 12번", body: "정적 본문")
        let matcher = Self.matcher([Boundary.idioms("A", "사자성어", items: [12])], entries: [staticTwelve])
        #expect(matcher.suggestion(forTail: "사자성어12번")?.body == "A 본문 12", "정적 「12번」은 앞 「어」에 걸려 빠진다")
        #expect(matcher.suggestion(forTail: "사자성어 12번")?.body == "정적 본문", "띄어 쓰면 정적 단축어가 먼저(10-3 분기 순서)")
    }
}

@Suite("채움글 단어 경계 — 날짜 팩")
struct SnippetWordBoundaryDateTests {

    private let matcher = SnippetMatcher(bible: nil, entries: [], dates: Boundary.dates)

    @Test("표 — 파서가 잡은 구문 첫 글자의 앞", arguments: [
        ("오늘 날짜", "오늘 날짜"),
        ("오늘날짜", "오늘날짜"),
        ("그 오늘 날짜", "오늘 날짜"),
        ("(오늘 날짜", "오늘 날짜"),
        ("그오늘 날짜", nil),
        ("3일 후 날짜", "3일 후 날짜"),
        ("x3일 후 날짜", nil),
        ("지금 시간", "지금 시간"),
        ("그지금 시간", nil),
        ("다음주 금요일 날짜", "다음주 금요일 날짜"),
        ("저다음주 금요일 날짜", nil)
    ] as [(String, String?)])
    func table(row: (tail: String, trigger: String?)) {
        #expect(matcher.suggestion(forTail: row.tail)?.trigger == row.trigger)
        #expect(Boundary.dates.suggestion(forTail: row.tail)?.trigger == row.trigger, "단독 API도 같은 규칙")
    }

    @Test("긴 어휘가 경계에 걸리면 짧은 어휘 — 「그올해 광복절 날짜」는 「광복절 날짜」(앞 공백)")
    func shorterWord() throws {
        let chip = try #require(matcher.suggestion(forTail: "그올해 광복절 날짜"))
        #expect(chip.trigger == "광복절 날짜")
        #expect(matcher.suggestion(forTail: "그올해광복절 날짜") == nil, "짧은 어휘 앞도 「해」")
        #expect(matcher.suggestion(forTail: "올해 광복절 날짜")?.trigger == "올해 광복절 날짜", "긴 어휘가 통과하면 긴 어휘")
    }

    @Test("「날짜」로 끝나는 사용자 단축어 — 앞에 붙은 꼴에서는 날짜 팩이 뜬다")
    func userDateSuffixTrigger() {
        let matcher = SnippetMatcher(
            bible: nil, entries: [SnippetEntry(trigger: "날짜", title: "내 날짜", body: "내 본문")], dates: Boundary.dates)
        #expect(matcher.suggestion(forTail: "오늘 날짜")?.title == "내 날짜", "띄어 쓰면 사용자 문구가 먼저(분기 순서 불변)")
        #expect(matcher.suggestion(forTail: "오늘날짜")?.trigger == "오늘날짜", "붙여 쓰면 「날짜」는 앞 「늘」에 걸려 빠지고 날짜 팩")
    }
}

@Suite("채움글 단어 경계 — U7 후보 · 성경 제외 · 꼬리 잘림")
struct SnippetWordBoundaryCandidatesTests {

    private static let twoAddresses = SnippetMatcher(bible: nil, entries: [
        Boundary.address, SnippetEntry(trigger: "주 소", title: "주소 2", body: "부산주소")
    ])

    @Test("★ 칩과 목록이 같은 규칙 — 칩이 없으면 목록도 없다", arguments: [
        ("서울주소", 0), ("서울 주소", 2), ("주소", 2), ("서울2주소", 0), ("(주소", 2)
    ] as [(String, Int)])
    func candidatesFollowChip(row: (tail: String, count: Int)) {
        let chip = Self.twoAddresses.suggestion(forTail: row.tail)
        let list = Self.twoAddresses.candidates(forTail: row.tail, isSecureTextEntry: false)
        #expect(list.count == row.count)
        #expect(list.first?.suggestion == chip, "첫 행 = 칩(alternativeCount 포함)")
        #expect((chip?.alternativeCount ?? -1) == row.count - 1)
    }

    @Test("짧은 needle로 넘어간 칩의 목록은 그 구간만 — 경계에 걸린 긴 needle은 목록에도 없다")
    func fallbackCandidates() {
        let matcher = SnippetMatcher(bible: nil, entries: [
            Boundary.newYear, Boundary.greeting, SnippetEntry(trigger: "인 사", title: "인사 2", body: "반가워요")
        ])
        let list = matcher.candidates(forTail: "그새해 인사", isSecureTextEntry: false)
        #expect(list.map(\.suggestion.title) == ["인사", "인사 2"])
        #expect(list.allSatisfy { $0.suggestion.trigger == "인사" })
    }

    @Test("U7 — 같은 틀 두 팩: 경계에 걸리면 목록도 비고, 통과하면 두 팩")
    func templateCandidates() {
        let sources = [Boundary.idioms("A", "사자성어", items: [12]), Boundary.idioms("B", "사자성어", items: [12])]
        let matcher = SnippetMatcher(bible: nil, entries: [], templates: PackTemplateMatcher(sources: sources))
        #expect(matcher.candidates(forTail: "옛사자성어12번", isSecureTextEntry: false).isEmpty)
        #expect(matcher.candidates(forTail: "옛 사자성어12번", isSecureTextEntry: false).count == 2)
    }

    @Test("U7 — 문구 + 날짜가 같은 구간이면 함께, 경계에 걸리면 둘 다 없음")
    func phraseAndDateCandidates() {
        let matcher = SnippetMatcher(
            bible: nil, entries: [SnippetEntry(trigger: "오늘날짜", title: "내 오늘", body: "내 본문")], dates: Boundary.dates)
        #expect(matcher.candidates(forTail: "오늘 날짜", isSecureTextEntry: false).map(\.origin) == [.user, .date])
        #expect(matcher.candidates(forTail: "그오늘 날짜", isSecureTextEntry: false).isEmpty)
    }

    @Test("★ 성경 참조 파서는 제외 — 앞이 라틴·숫자여도 자기 규칙대로 뜨고, 꼬리 잘림도 보지 않는다", arguments: [
        "a창 1:1", "1창 1:1", "창 1:1"
    ])
    func bibleExcluded(tail: String) throws {
        let matcher = SnippetMatcher(bible: VerseBible(), entries: [])
        let chip = try #require(matcher.suggestion(forTail: tail))
        #expect(chip.trigger == "창 1:1")
        #expect(matcher.suggestion(forTail: tail, isSecureTextEntry: false, tailIsTruncated: true)?.trigger == "창 1:1")
    }

    @Test("★ 꼬리가 잘렸으면(48자 상한) 꼬리 맨 앞에서 시작한 구간은 앞 글자를 모른다 — 경계가 아니다")
    func truncatedTailStart() {
        let matcher = SnippetMatcher(bible: nil, entries: [Boundary.address], dates: Boundary.dates,
                                     templates: PackTemplateMatcher(sources: [Boundary.idioms("A", "고사성어", items: [12])]))
        for tail in ["주소", "오늘 날짜", "고사성어12번"] {
            #expect(matcher.suggestion(forTail: tail, isSecureTextEntry: false, tailIsTruncated: false) != nil, "\(tail) 잘리지 않음")
            #expect(matcher.suggestion(forTail: tail, isSecureTextEntry: false, tailIsTruncated: true) == nil, "\(tail) 잘림")
            #expect(matcher.candidates(forTail: tail, isSecureTextEntry: false, tailIsTruncated: true).isEmpty, "\(tail) 목록")
        }
        // 잘렸어도 꼬리 안에서 시작한 구간은 실제 앞 글자로 판정한다
        #expect(matcher.suggestion(forTail: "가나 주소", isSecureTextEntry: false, tailIsTruncated: true)?.trigger == "주소")
        #expect(matcher.suggestion(forTail: "가나주소", isSecureTextEntry: false, tailIsTruncated: true) == nil)
    }
}

@MainActor
@Suite("채움글 단어 경계 — InputController 꼬리 잘림 추적")
struct SnippetWordBoundaryInputControllerTests {

    private func makeController() -> (RecordingOutput, InputController) {
        let output = RecordingOutput()
        return (output, InputController(output: output))
    }

    @Test("타이핑으로 48자를 넘기면 잘림, 리턴하면 새 줄이라 풀린다")
    func typingTruncates() {
        let (_, controller) = makeController()
        controller.handle(.symbols)
        #expect(controller.textTailIsTruncated == false, "처음")
        for _ in 0..<48 { controller.handle(.character("1")) }
        #expect(controller.textTailIsTruncated == false, "정확히 48자 — 앞을 버리지 않았다")
        controller.handle(.character("1"))
        #expect(controller.textTailIsTruncated == true, "49자째 — 맨 앞을 버렸다")
        controller.handle(.backspace)
        #expect(controller.textTailIsTruncated == true, "뒤를 지워도 앞은 여전히 줄 중간")
        controller.handle(.return)
        #expect(controller.textTailIsTruncated == false, "새 줄의 처음")
    }

    @Test("문서 문맥으로 세운 꼬리 — 마지막 줄이 48자를 넘을 때만 잘림", arguments: [
        (String(repeating: "가", count: 48), false),
        (String(repeating: "가", count: 49), true),
        (String(repeating: "가", count: 60) + "\n주소", false),
        ("주소", false)
    ] as [(String, Bool)])
    func syncTruncation(row: (document: String, truncated: Bool)) {
        let (_, controller) = makeController()
        controller.syncWithDocument(documentTail: row.document)
        #expect(controller.textTailIsTruncated == row.truncated)
    }

    @Test("메아리 sync(문서가 우리 조합 글자로 끝남)도 확정 꼬리의 잘림을 문서 기준으로 다시 적는다")
    func echoSyncTracksTruncation() {
        let (_, controller) = makeController()
        for key in ["r", "k"] { controller.handle(.character(key)) }   // 가 (조합 중)
        controller.syncWithDocument(documentTail: String(repeating: "나", count: 60) + "가")
        #expect(controller.isComposing, "전제 — 메아리라 조합을 살린다")
        #expect(controller.textTailIsTruncated == true)
        controller.syncWithDocument(documentTail: "나 가")
        #expect(controller.isComposing)
        #expect(controller.textTailIsTruncated == false)
    }

    @Test("문맥을 모르는 sync(nil)는 잘림으로 보지 않는다 — 빈 입력란 첫 단축어가 막히면 안 된다")
    func nilSyncIsNotTruncated() {
        let (_, controller) = makeController()
        controller.syncWithDocument(documentTail: String(repeating: "가", count: 60))
        #expect(controller.textTailIsTruncated == true)
        controller.syncWithDocument()
        #expect(controller.textTailIsTruncated == false)
    }

    @Test("채움글 삽입 — 본문에 줄바꿈이 있으면 마지막 줄부터 새로 센다")
    func insertSnippetResetsOnNewline() throws {
        let (output, controller) = makeController()
        let document = String(repeating: "가", count: 50) + " 주소"
        output.insertText(document)
        controller.syncWithDocument(documentTail: document)
        #expect(controller.textTailIsTruncated == true)
        let matcher = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "주소", title: "주소", body: "첫 줄\n둘째 줄")])
        let chip = try #require(matcher.suggestion(
            forTail: controller.textTail, isSecureTextEntry: false, tailIsTruncated: controller.textTailIsTruncated))
        #expect(chip.trigger == "주소", "잘린 꼬리여도 꼬리 안에서 시작한 구간은 앞 글자(공백)로 판정")
        #expect(controller.insertSnippet(chip))
        #expect(output.text == String(repeating: "가", count: 50) + " 첫 줄\n둘째 줄")
        #expect(controller.textTailIsTruncated == false)
    }

    @Test("끝 맞춤 칩 → 삽입: 「서울 주소」는 「서울 」 + 본문, 「서울주소」는 칩 없음")
    func endToEnd() throws {
        let matcher = SnippetMatcher(bible: nil, entries: [Boundary.address])
        let (output, controller) = makeController()
        output.insertText("서울주소")
        controller.syncWithDocument(documentTail: "서울주소")
        #expect(matcher.suggestion(forTail: controller.textTail, isSecureTextEntry: false,
                                   tailIsTruncated: controller.textTailIsTruncated) == nil)

        let (spaced, spacedController) = makeController()
        spaced.insertText("서울 주소")
        spacedController.syncWithDocument(documentTail: "서울 주소")
        let chip = try #require(matcher.suggestion(
            forTail: spacedController.textTail, isSecureTextEntry: false, tailIsTruncated: spacedController.textTailIsTruncated))
        #expect(spacedController.insertSnippet(chip))
        #expect(spaced.text == "서울 서울주소")
    }
}
