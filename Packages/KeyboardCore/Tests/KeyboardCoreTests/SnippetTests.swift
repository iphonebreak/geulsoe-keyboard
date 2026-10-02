import Foundation
import Testing
import HangulEngine
import TadakDomain
@testable import KeyboardCore

/// 존재하는 절만 아는 fake — 창세기 1장(실제 데이터와 같은 31절)만 안다.
/// 1절만 실제 본문이고 나머지는 합성 문자열이다 — 범위 조립 형식을 검증하기 위한 것.
private struct FakeBible: BibleVerseRepository {
    static let genesis11 = "태초에 하나님이 천지를 창조하시니라"
    /// 창세기 1장은 31절까지 (bible.tdb 실측)
    static let genesisChapter1VerseCount = 31

    func text(book: Int, chapter: Int, verse: Int) -> String? {
        guard book == 1, chapter == 1,
              (1...Self.genesisChapter1VerseCount).contains(verse) else { return nil }
        return verse == 1 ? Self.genesis11 : "창세기 1장 \(verse)절 본문"
    }
}

/// 66권 어느 절이든 아는 fake — 트리거 원문 되비추기 검증용(별칭·띄어쓴 이름 포함).
private struct AnyVerseBible: BibleVerseRepository {
    func text(book: Int, chapter: Int, verse: Int) -> String? { "본문 \(book)/\(chapter)/\(verse)" }
}

/// **절은 있는데 본문이 비어 있는** fake — 조회 실패(nil)와는 다른 상태다.
///
/// 2026-09-15 에 실제로 이 상태가 있었다: 정본이 "1-2" 로 묶어 인쇄한 합병절의 **뒷절**이
/// 원본 데이터에서 빈 문자열로 남아 있어(사 30:2 · 사 48:2 · 렘 21:2 · 겔 24:5 · 행 15:26 · 롬 9:2)
/// 「로마서 9장 2절」을 치면 **빈 내용이 삽입됐다.** 데이터는 고쳤지만(뒷절에 앞절을 가리키는
/// 표기를 넣었다) 데이터만 믿지 않는다 — 매처가 스스로 막는다.
private struct EmptyBodyBible: BibleVerseRepository {
    /// 공백만 있는 경우도 같이 본다 — 눈에는 비어 보이는 것이 사용자에게는 같은 버그다.
    var body = ""
    func text(book: Int, chapter: Int, verse: Int) -> String? { body }
}

@Suite("성경 참조 파서")
struct BibleReferenceParserTests {

    @Test("정식 명칭 — 창세기 1장 1절")
    func fullForm() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "창세기 1장 1절"))
        #expect(match.book == 1 && match.chapter == 1 && match.verse == 1)
        #expect(match.matchedLength == 9)
        #expect(match.display == "창세기 1:1")
    }

    @Test("약칭 콜론형 — 앞의 다른 텍스트는 매칭 길이에서 빠진다")
    func abbreviatedColonForm() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "말씀은 창 1:1"))
        #expect(match.book == 1 && match.chapter == 1 && match.verse == 1)
        #expect(match.matchedLength == 5, "'창 1:1'만 트리거다")
    }

    @Test("공백 없는 변형도 받는다", arguments: [
        ("창1:1", 1, 1, 1, 4),
        ("창세기1장1절", 1, 1, 1, 7),
        ("요 3:16", 43, 3, 16, 6)
    ])
    func spacingVariants(testCase: (String, Int, Int, Int, Int)) throws {
        let (tail, book, chapter, verse, length) = testCase
        let match = try #require(BibleReferenceParser.matchSuffix(of: tail))
        #expect(match.book == book && match.chapter == chapter && match.verse == verse)
        #expect(match.matchedLength == length)
    }

    @Test("통용 별칭 — 계시록")
    func alias() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "계시록 22장 21절"))
        #expect(match.book == 66 && match.chapter == 22 && match.verse == 21)
    }

    @Test("두 단어 별칭 '요한 계시록'은 앞말까지 트리거에 포함한다")
    func twoWordAliasIncludesLeadingWord() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "요한 계시록 1장 1절"))
        #expect(match.book == 66)
        #expect(match.matchedLength == 12, "'요한 '까지 지워야 잔여물이 없다")

        // 앞말 run이 "요한"이 아니면 확장하지 않는다
        let noExtend = try #require(BibleReferenceParser.matchSuffix(of: "안녕요한 계시록 1장 1절"))
        #expect(noExtend.matchedLength == 9, "'계시록 1장 1절'만 트리거다")
    }

    // MARK: - 절 범위 (2026-09-08)

    /// 콜론형 범위 — `창세기 1:1~13`. 마지막 값은 트리거 길이(삽입 시 지울 문자 수)다.
    @Test("콜론형 범위 구문", arguments: [
        ("창세기 1:1~13", 1, 1, 1, 13, 10),
        ("창세기 1:1-13", 1, 1, 1, 13, 10),
        ("창 1:1-13", 1, 1, 1, 13, 8),
        ("창1:1~13", 1, 1, 1, 13, 7),
        ("요 3:16~18", 43, 3, 16, 18, 9),
        ("말씀은 창 1:1~3", 1, 1, 1, 3, 7),
        // 이 키보드로 칠 수 없지만 붙여넣기·타 키보드로 들어올 수 있는 구분자
        ("창 1:1～3", 1, 1, 1, 3, 7),   // 전각 물결 U+FF5E
        ("창 1:1〜3", 1, 1, 1, 3, 7),   // 물결 대시 U+301C
        ("창 1:1–3", 1, 1, 1, 3, 7),   // en dash U+2013
        // 구분자 양옆 공백 한 칸까지 받는다
        ("창 1:1 ~ 3", 1, 1, 1, 3, 9),
        ("창 1:1~ 3", 1, 1, 1, 3, 8)
    ])
    func colonRange(testCase: (String, Int, Int, Int, Int, Int)) throws {
        let (tail, book, chapter, start, end, length) = testCase
        let match = try #require(BibleReferenceParser.matchSuffix(of: tail))
        #expect(match.book == book && match.chapter == chapter)
        #expect(match.verse == start && match.endVerse == end)
        #expect(match.isRange)
        #expect(match.matchedLength == length)
    }

    /// 형태 A(장·절)의 범위형 — `1~13절`과 `1절~13절` 모두 받는다.
    @Test("장·절형 범위 구문", arguments: [
        ("창세기 1장 1~13절", 1, 1, 1, 13, 12),
        ("창세기 1장 1절~13절", 1, 1, 1, 13, 13),
        ("창세기1장1~13절", 1, 1, 1, 13, 10),
        ("창세기 1장 1-13절", 1, 1, 1, 13, 12)
    ])
    func chapterVerseRange(testCase: (String, Int, Int, Int, Int, Int)) throws {
        let (tail, book, chapter, start, end, length) = testCase
        let match = try #require(BibleReferenceParser.matchSuffix(of: tail))
        #expect(match.book == book && match.chapter == chapter)
        #expect(match.verse == start && match.endVerse == end)
        #expect(match.matchedLength == length)
    }

    @Test("범위 display는 '책 장:시작-끝'이다")
    func rangeDisplay() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "창세기 1:1~13"))
        #expect(match.display == "창세기 1:1-13")
    }

    /// 같은 값 범위는 범위가 아니라 단일 절로 본다 — 절 번호·머리말이 단일 절과 같아야 한다.
    @Test("같은 값 범위는 단일 절로 접힌다")
    func degenerateRangeCollapses() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "창 1:1~1"))
        #expect(match.verse == 1 && match.endVerse == 1)
        #expect(!match.isRange)
        #expect(match.display == "창세기 1:1", "'1:1-1'이 아니다")
        #expect(match.matchedLength == 7)
    }

    /// 두 단어 별칭 확장은 범위형에서도 살아 있어야 한다 (잔여물 "요한 " 방지).
    @Test("'요한 계시록' 범위형도 앞말까지 트리거에 포함한다")
    func twoWordAliasRange() throws {
        let match = try #require(BibleReferenceParser.matchSuffix(of: "요한 계시록 1장 1~3절"))
        #expect(match.book == 66 && match.verse == 1 && match.endVerse == 3)
        #expect(match.matchedLength == 14, "'요한 '까지 지워야 잔여물이 없다")

        let colon = try #require(BibleReferenceParser.matchSuffix(of: "요한 계시록 1:1~3"))
        #expect(colon.book == 66 && colon.matchedLength == 12)
    }

    @Test("절 수 상한 경계 — 상한까지만 참조로 본다")
    func rangeLimitBoundary() throws {
        let limit = BibleReferenceParser.maxRangeVerses
        let atLimit = try #require(BibleReferenceParser.matchSuffix(of: "시 119:1~\(limit)"))
        #expect(atLimit.endVerse == limit)
        // 한 절 더 넘으면 참조로 보지 않는다 (칩 없음)
        #expect(BibleReferenceParser.matchSuffix(of: "시 119:1~\(limit + 1)") == nil)
        // 시작점이 달라도 절 수가 기준이다
        #expect(BibleReferenceParser.matchSuffix(of: "시 119:100~\(99 + limit)") != nil)
        #expect(BibleReferenceParser.matchSuffix(of: "시 119:100~\(100 + limit)") == nil)
    }

    @Test("범위 구문 거절", arguments: [
        "창 1:13~1",        // 역순 — 의도가 모호하다
        "창세기 1장 13~1절",
        "창 1:1~",          // 아직 치는 중
        "창 1:~3",
        "창 1:0~3",         // 0절은 없다
        "창 1:1~0",
        "창 1:1~1234",      // 절은 최대 3자리
        "창 1234:1~3",
        "그러나 1:1~3",      // "나"가 나훔으로 오인되면 안 된다
        "안녕창 1:1~3",      // 붙여 쓴 run은 책이 아니다
        "창 1:1~3에",        // 조사가 붙으면 삽입 의도가 아니다
        "무언가 1:1~3",
        "창세기 1:1~13절",   // 혼합형(콜론 + 절)은 받지 않는다
        "창 1:1~~3",
        "창 1:1  ~  3",     // 공백은 한 칸까지
        "1:1~3"
    ])
    func rejectsRangeNonReferences(tail: String) {
        #expect(BibleReferenceParser.matchSuffix(of: tail) == nil)
    }

    @Test("책 이름은 한글 run 전체가 정확히 일치해야 한다", arguments: [
        "그러나 1:1",     // "나"가 나훔으로 오인되면 안 된다
        "안녕창 1:1",     // 붙여 쓴 run "안녕창"은 책이 아니다
        "창세기 1장 1절에",  // 조사가 붙으면 삽입 의도가 아니다
        "창세기 0장 1절",   // 0장은 없다
        "창 1:0",
        "창 1234:5",      // 장·절은 최대 3자리
        "무언가 1장 1절",
        ""
    ])
    func rejectsNonReferences(tail: String) {
        #expect(BibleReferenceParser.matchSuffix(of: tail) == nil)
    }
}

@Suite("SnippetMatcher")
struct SnippetMatcherTests {

    private let anthem = SnippetEntry(
        trigger: "애국가 1절", title: "애국가 1절", body: "동해물과 백두산이…")

    @Test("성경 참조는 저장소에 존재할 때만 후보가 된다")
    func bibleMatchRequiresExistingVerse() {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = matcher.suggestion(forTail: "창세기 1장 1절")
        #expect(hit?.body == FakeBible.genesis11)
        #expect(hit?.triggerLength == 9)
        // 성경은 머리말이 붙어 들어간다 (사용자 결정 2026-09-03); 문구 팩은 붙지 않는다
        #expect(hit?.prefix == "[창세기 1장 1절] ", "머리말은 사용자가 친 트리거 원문 그대로")
        #expect(hit?.insertedText == "[창세기 1장 1절] " + FakeBible.genesis11)
        #expect(SnippetMatcher(bible: nil, entries: [anthem])
            .suggestion(forTail: "애국가 1절")?.insertedText == anthem.body)
        // 구문은 맞지만 존재하지 않는 절 — 후보 없음
        #expect(matcher.suggestion(forTail: "창세기 99장 1절") == nil)
    }

    /// 설정 `bibleSnippetPrefixEnabled` 끔 — 머리말 없이 본문만 (2026-09-07 성경 팩 상세 스위치)
    @Test("biblePrefix가 꺼지면 성경 후보에 머리말이 붙지 않는다")
    func biblePrefixCanBeDisabled() {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [], biblePrefix: false)
        let hit = matcher.suggestion(forTail: "창세기 1장 1절")
        #expect(hit?.prefix == nil)
        #expect(hit?.insertedText == FakeBible.genesis11)
        #expect(hit?.title == "창세기 1:1", "칩 제목은 그대로")
    }

    // MARK: - 머리말은 트리거 원문 (사용자 보고 2026-09-14)

    /// 사용자 결정: 머리말은 **사용자가 친 그대로**를 되비춘다. 파서 정규 표기(`display`)를
    /// 쓰면 "창세기 1장 1절"을 친 사람도 `[창세기 1:1] `을 받아 표기가 제멋대로 바뀐다.
    /// 칩 제목(`title`)은 정규 표기 그대로 둔다 — 바꾸라는 요청이 아니다.
    @Test("단일 절 머리말은 트리거 원문을 그대로 되비춘다", arguments: [
        "창세기 1장 1절",
        "창세기1:1",
        "창세기 1장1절",
        "창세기1장 1절",
        "창세기1장1절",
        "창세기 1:1",
        "창 1:1",
        "창1:1",
        "창 1장 1절",
        "창1장1절"
    ])
    func singleVersePrefixIsVerbatim(tail: String) throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: tail))
        #expect(hit.trigger == tail)
        #expect(hit.prefix == "[\(tail)] ")
        #expect(hit.insertedText == "[\(tail)] " + FakeBible.genesis11)
        #expect(hit.title == "창세기 1:1", "칩 제목은 정규 표기 그대로")
    }

    /// 앞에 다른 텍스트가 있어도 머리말은 트리거 구간만 — 앞말·공백이 새어 들어가면 안 된다.
    @Test("앞 텍스트는 머리말에 섞이지 않는다", arguments: [
        ("말씀은 창 1:1", "창 1:1"),
        ("오늘의 말씀 창세기 1장 1절", "창세기 1장 1절"),
        ("1창세기1:1", "창세기1:1"),
        ("어제 읽은 창세기 1:1~3", "창세기 1:1~3")
    ])
    func leadingTextIsNotInPrefix(testCase: (String, String)) throws {
        let (tail, trigger) = testCase
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: tail))
        #expect(hit.trigger == trigger)
        #expect(hit.prefix == "[\(trigger)] ")
        #expect(hit.prefix?.hasPrefix("[\(trigger.first!)") == true, "여는 대괄호 뒤 공백 없음")
        #expect(hit.prefix?.hasSuffix("] ") == true, "닫는 대괄호 뒤 공백 한 칸")
    }

    /// 범위 표기는 구분자 5종·`절` 붙임 여부가 제각각이다 — 전부 친 그대로 되비춘다.
    @Test("절 범위 머리말도 구분자·표기를 그대로 유지한다", arguments: [
        "창세기 1:1~3",
        "창세기 1:1-3",
        "창세기 1:1\u{FF5E}3",
        "창세기 1:1\u{301C}3",
        "창세기 1:1\u{2013}3",
        "창세기 1:1 ~ 3",
        "창세기 1:1~ 3",
        "창세기1:1~3",
        "창세기 1장 1~3절",
        "창세기 1장 1절~3절",
        "창세기1장1~3절",
        "창세기 1장 1-3절",
        "창 1:1~3"
    ])
    func verseRangePrefixIsVerbatim(tail: String) throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: tail))
        #expect(hit.trigger == tail)
        #expect(hit.prefix == "[\(tail)] ")
        #expect(hit.title == "창세기 1:1-3", "칩 제목은 정규 표기 그대로")
        #expect(hit.insertedText == "[\(tail)] " + hit.body)
    }

    /// 두 단어 별칭("요한 계시록")은 트리거가 앞말까지 확장된다 — 머리말도 그 구간 전체다.
    @Test("띄어 친 두 단어 별칭도 원문 그대로 머리말이 된다", arguments: [
        "요한 계시록 1장 1절",
        "요한 계시록 1:1",
        "계시록 1:1"
    ])
    func spacedAliasPrefixIsVerbatim(tail: String) throws {
        let matcher = SnippetMatcher(bible: AnyVerseBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: tail))
        #expect(hit.trigger == tail)
        #expect(hit.prefix == "[\(tail)] ")
        #expect(hit.title == "요한계시록 1:1", "칩 제목은 정식 명칭")
    }

    /// **본문이 비면 칩을 띄우지 않는다.** 조회가 성공했어도 마찬가지다.
    ///
    /// 빈 본문을 삽입하면 사용자에게는 "칩을 눌렀는데 아무 것도 안 들어갔다"가 된다.
    /// 범위 조회가 이미 쓰고 있는 fail-closed 규칙(한 절이라도 없으면 nil)과 같은 방향이다.
    @Test("본문이 비어 있으면 후보로 띄우지 않는다", arguments: ["", " ", "\n", "  \n "])
    func emptyBodyProducesNoSuggestion(body: String) {
        let matcher = SnippetMatcher(bible: EmptyBodyBible(body: body), entries: [])
        #expect(matcher.suggestion(forTail: "로마서 9장 2절") == nil)
        #expect(matcher.suggestion(forTail: "창 1:1") == nil)
    }

    /// 범위 안의 한 절만 비어도 전체를 띄우지 않는다 — 가운데가 빈 채로 삽입되면 안 된다.
    @Test("범위 안에 빈 절이 섞이면 범위 전체가 후보에서 빠진다")
    func emptyVerseInsideRangeSuppressesWholeRange() {
        /// 창세기 1:2 만 비어 있는 fake
        struct HoleBible: BibleVerseRepository {
            func text(book: Int, chapter: Int, verse: Int) -> String? {
                guard book == 1, chapter == 1, (1...31).contains(verse) else { return nil }
                return verse == 2 ? "" : "창세기 1장 \(verse)절 본문"
            }
        }
        let matcher = SnippetMatcher(bible: HoleBible(), entries: [])
        #expect(matcher.suggestion(forTail: "창 1:1~3") == nil)
        #expect(matcher.suggestion(forTail: "창 1:1") != nil, "빈 절을 비껴간 조회는 그대로 뜬다")
    }

    /// 머리말 스위치를 끄면 원문이든 정규 표기든 아무 것도 붙지 않는다.
    @Test("biblePrefix가 꺼지면 원문 머리말도 붙지 않는다")
    func verbatimPrefixRespectsToggle() throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [], biblePrefix: false)
        let hit = try #require(matcher.suggestion(forTail: "창세기 1장 1절"))
        #expect(hit.prefix == nil)
        #expect(hit.insertedText == FakeBible.genesis11)
    }

    /// 성경이 아닌 팩(인사·국가 상징문·사용자 문구)은 머리말이 없다 — 이번 변경과 무관하다.
    @Test("문구 팩 후보는 여전히 머리말이 없다")
    func entryPacksKeepNoPrefix() throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [anthem])
        let hit = try #require(matcher.suggestion(forTail: "애국가 1절"))
        #expect(hit.prefix == nil)
        #expect(hit.insertedText == anthem.body)
    }

    @Test("문구 트리거는 꼬리 접미사와 일치해야 한다")
    func entryMatchesSuffixOnly() {
        let matcher = SnippetMatcher(bible: nil, entries: [anthem])
        #expect(matcher.suggestion(forTail: "다같이 애국가 1절")?.body == anthem.body)
        #expect(matcher.suggestion(forTail: "애국가 1절을") == nil)
        #expect(matcher.suggestion(forTail: "") == nil)
    }

    @Test("트리거가 겹치면 긴 쪽이, 같으면 앞선 항목(사용자)이 이긴다")
    func longestTriggerWins() {
        let short = SnippetEntry(trigger: "국가 1절", title: "짧은", body: "짧은 본문")
        let user = SnippetEntry(trigger: "애국가 1절", title: "사용자", body: "사용자 본문")
        let matcher = SnippetMatcher(bible: nil, entries: [short, user, anthem])
        let hit = matcher.suggestion(forTail: "애국가 1절")
        #expect(hit?.title == "사용자")
    }

    @Test("사용자 문구가 성경 참조보다 우선한다")
    func entriesBeatBible() {
        let custom = SnippetEntry(trigger: "창 1:1", title: "내 문구", body: "내 본문")
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [custom])
        #expect(matcher.suggestion(forTail: "창 1:1")?.body == "내 본문")
    }

    // MARK: - 절 범위 (2026-09-08)

    /// 삽입 형식 결정 (PDR bible-verse-range): 절마다 "번호 본문", 줄바꿈으로 잇는다.
    @Test("범위 후보는 절 번호를 붙여 줄바꿈으로 잇는다")
    func bibleRangeBody() throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: "창세기 1:1~3"))
        #expect(hit.title == "창세기 1:1-3")
        #expect(hit.prefix == "[창세기 1:1~3] ", "구분자 `~`도 친 그대로")
        #expect(hit.body == """
            1 \(FakeBible.genesis11)
            2 창세기 1장 2절 본문
            3 창세기 1장 3절 본문
            """)
        #expect(hit.triggerLength == 9, "'창세기 1:1~3' 9자만 지운다")
        #expect(hit.insertedText == "[창세기 1:1~3] " + hit.body)
    }

    @Test("biblePrefix가 꺼지면 범위 후보도 머리말이 없다")
    func rangePrefixCanBeDisabled() throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [], biblePrefix: false)
        let hit = try #require(matcher.suggestion(forTail: "창세기 1:1~3"))
        #expect(hit.prefix == nil)
        #expect(hit.insertedText == hit.body)
        #expect(hit.title == "창세기 1:1-3", "칩 제목은 그대로")
    }

    /// 장 끝을 넘는 범위는 한 절이라도 없으면 후보를 내지 않는다 (단일 절과 같은 fail-closed).
    @Test("장 끝을 넘는 범위는 후보가 되지 않는다")
    func rangeBeyondChapterEndIsRejected() {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        #expect(matcher.suggestion(forTail: "창세기 1:29~33") == nil, "창세기 1장은 31절까지")
        #expect(matcher.suggestion(forTail: "창세기 1:1~31") != nil, "장 끝까지는 받는다")
        #expect(matcher.suggestion(forTail: "창세기 1:1~32") == nil)
        // 상한을 넘긴 범위는 구문 단계에서 걸러 조회조차 하지 않는다
        #expect(matcher.suggestion(forTail: "창세기 1:1~99") == nil)
    }

    @Test("같은 값 범위는 단일 절과 똑같이 삽입된다")
    func degenerateRangeInsertsSingleVerse() throws {
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])
        let hit = try #require(matcher.suggestion(forTail: "창 1:1~1"))
        #expect(hit.body == FakeBible.genesis11, "절 번호를 붙이지 않는다")
        #expect(hit.prefix == "[창 1:1~1] ", "접힌 범위도 친 그대로")
        #expect(hit.triggerLength == 7)
    }

    @Test("범위 조회는 절 수만큼만 저장소를 부른다")
    func rangeLookupCountIsBounded() {
        final class CountingBible: BibleVerseRepository, @unchecked Sendable {
            private(set) var calls = 0
            func text(book: Int, chapter: Int, verse: Int) -> String? {
                calls += 1
                return (1...31).contains(verse) ? "본문 \(verse)" : nil
            }
        }
        let bible = CountingBible()
        _ = SnippetMatcher(bible: bible, entries: []).suggestion(forTail: "창세기 1:1~5")
        #expect(bible.calls == 5)
    }
}

@MainActor
@Suite("InputController — 꼬리 추적과 채움글 삽입")
struct InputControllerSnippetTests {

    @Test("조합 중 글자까지 포함해 꼬리를 추적한다")
    func tailTracksCommittedAndComposing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["c", "k", "d"] { controller.handle(.character(key)) }  // 창 (조합 중)
        #expect(controller.textTail == "창")

        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1"] { controller.handle(.character(key)) }
        #expect(controller.textTail == "창 1:1")
        #expect(output.text == "창 1:1")
    }

    @Test("백스페이스·리턴·동기화가 꼬리를 정리한다")
    func tailFollowsEditing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["r", "k"] { controller.handle(.character(key)) }  // 가
        controller.handle(.space)
        #expect(controller.textTail == "가 ")

        controller.handle(.backspace)  // 공백 삭제 — 확정 텍스트 경로
        #expect(controller.textTail == "가")

        controller.handle(.return)
        #expect(controller.textTail == "", "트리거는 줄을 넘지 않는다")

        for key in ["r", "k"] { controller.handle(.character(key)) }
        controller.syncWithDocument()
        #expect(controller.textTail == "", "커서 이동 후 꼬리는 무효다")
    }

    /// 리뷰 HIGH 회귀 방어 — 트리거의 숫자·콜론은 기호 모드에서 지워진다.
    @Test("기호·영어 모드 백스페이스도 꼬리를 걷는다")
    func tailFollowsNonHangulBackspace() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["c", "k", "d"] { controller.handle(.character(key)) }  // 창
        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1", "2"] { controller.handle(.character(key)) }
        controller.handle(.backspace)  // 기호 모드에서 "2" 삭제
        #expect(output.text == "창 1:1")
        #expect(controller.textTail == "창 1:1", "문서에 없는 텍스트로 칩이 뜨면 안 된다")

        controller.handle(.symbols)  // 한글로 복귀
        controller.handle(.toggleLanguage)  // 영어 모드
        controller.handle(.character("a"))
        controller.handle(.backspace)
        #expect(output.text == "창 1:1")
        #expect(controller.textTail == "창 1:1")
    }

    @Test("천지인 키 재생 백스페이스 후에도 꼬리가 문서와 일치한다")
    func tailSurvivesKeystrokeReplay() {
        let output = RecordingOutput()
        let controller = InputController(
            output: output, hangulSource: CheonjiinSource(timeout: 10))

        // 가나: ㄱㅣㆍ → 가, ㄴ → 간, ㅣ → 가(확정)+니, ㆍ → 나
        for key in ["ㄱ", "ㅣ", "ㆍ", "ㄴ", "ㅣ", "ㆍ"] { controller.handle(.character(key)) }
        #expect(output.text == "가나")
        #expect(controller.textTail == "가나")

        controller.handle(.backspace)  // 마지막 키(ㆍ) 취소 → 가니
        #expect(output.text == "가니")
        #expect(controller.textTail == "가니")
    }

    @Test("채움글 삽입이 트리거만 지우고 전문을 넣는다")
    func insertReplacesTriggerWithBody() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d"] { controller.handle(.character(key)) }  // 창 (조합 중)
        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1"] { controller.handle(.character(key)) }

        let suggestion = matcher.suggestion(forTail: controller.textTail)
        #expect(suggestion?.triggerLength == 5)

        controller.insertSnippet(suggestion!)
        let inserted = "[창 1:1] " + FakeBible.genesis11
        #expect(output.operations.suffix(2) == [
            .delete(5), .insert(inserted)
        ])
        #expect(output.text == inserted)
        #expect(controller.textTail == inserted, "꼬리도 머리말 포함 본문으로 이어진다")
    }

    /// 범위 삽입 — triggerLength가 틀리면 앞 글자가 지워지거나 트리거 잔여물이 남는다.
    @Test("범위 채움글도 트리거만 지우고 여러 절을 넣는다")
    func insertVerseRange() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        controller.handle(.character("1"))                                 // 앞 텍스트 — 지워지면 안 된다
        for key in ["c", "k", "d"] { controller.handle(.character(key)) }  // 창 (조합 중)
        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1", "~", "3"] { controller.handle(.character(key)) }
        #expect(output.text == "1창 1:1~3")

        let suggestion = try #require(matcher.suggestion(forTail: controller.textTail))
        #expect(suggestion.triggerLength == 7, "'창 1:1~3'만 트리거다")

        controller.insertSnippet(suggestion)
        let body = """
            1 \(FakeBible.genesis11)
            2 창세기 1장 2절 본문
            3 창세기 1장 3절 본문
            """
        #expect(output.operations.suffix(2) == [
            .delete(7), .insert("[창 1:1~3] " + body)
        ])
        #expect(output.text == "1[창 1:1~3] " + body)
        #expect(controller.textTail == "3 창세기 1장 3절 본문", "꼬리는 본문 마지막 줄만")
    }

    /// QA BLOCK-2 회귀. 칩은 퇴장 트랜지션(0.28초) 동안에도 히트 테스트를 받으므로 같은 후보가
    /// 두 번 들어올 수 있다. 2회차는 꼬리가 이미 본문으로 바뀌어 트리거와 어긋나므로 **거부**해야
    /// 한다 — 검사가 없던 시절엔 `deleteBackward(triggerLength)`가 방금 넣은 본문 끝을 잘라냈다.
    @Test("같은 채움글 칩이 두 번 들어와도 2회차는 문서를 건드리지 않는다")
    func doubleTapDoesNotCorruptDocument() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d"] { controller.handle(.character(key)) }  // 창 (조합 중)
        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1"] { controller.handle(.character(key)) }

        let suggestion = try #require(matcher.suggestion(forTail: controller.textTail))
        #expect(controller.insertSnippet(suggestion), "1회차는 삽입된다")

        let inserted = "[창 1:1] " + FakeBible.genesis11
        #expect(output.text == inserted)
        let operationsAfterFirst = output.operations

        #expect(controller.insertSnippet(suggestion) == false, "2회차는 꼬리가 어긋나 거부된다")
        #expect(output.operations == operationsAfterFirst, "문서에 어떤 조작도 가지 않는다")
        #expect(output.text == inserted, "본문 끝이 잘리지 않는다")
        #expect(controller.textTail == inserted)
    }

    /// 범위 후보는 피해가 훨씬 크다 — 1회차 본문이 여러 줄이라 2회차가 잘라 내면 되돌리기 어렵다.
    @Test("범위 채움글 칩도 두 번째 탭을 거부한다")
    func doubleTapOnVerseRangeIsRejected() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d"] { controller.handle(.character(key)) }
        controller.handle(.space)
        controller.handle(.symbols)
        for key in ["1", ":", "1", "~", "3"] { controller.handle(.character(key)) }

        let suggestion = try #require(matcher.suggestion(forTail: controller.textTail))
        #expect(controller.insertSnippet(suggestion))
        let textAfterFirst = output.text
        let operationsAfterFirst = output.operations

        #expect(controller.insertSnippet(suggestion) == false)
        #expect(output.text == textAfterFirst)
        #expect(output.operations == operationsAfterFirst)
    }

    /// 빈 트리거는 어떤 꼬리로도 매칭되면 안 된다 (`hasSuffix("")`는 항상 참이다).
    @Test("트리거가 빈 후보는 삽입되지 않는다")
    func emptyTriggerIsRejected() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let suggestion = SnippetSuggestion(trigger: "", title: "빈 것", body: "본문")

        #expect(controller.insertSnippet(suggestion) == false)
        #expect(output.operations.isEmpty)
    }

    /// 사용자 보고(2026-09-03): "…3절"까지 치고 "절"을 지웠다 다시 쓰면 인식되지 않는다
    @Test("트리거 끝 글자를 지웠다 다시 쳐도 후보가 다시 뜬다 — 숫자는 기호 자판에서")
    func retypingLastSyllableRestoresSuggestion() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d", "t", "p", "r", "l"] { controller.handle(.character(key)) }  // 창세기
        controller.handle(.symbols)
        controller.handle(.character("1"))
        controller.handle(.symbols)                                   // 한글로
        for key in ["w", "k", "d"] { controller.handle(.character(key)) }  // 장
        controller.handle(.symbols)
        controller.handle(.character("1"))
        controller.handle(.symbols)
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }  // 절 (조합 중)
        #expect(output.text == "창세기1장1절")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil, "처음 입력에서 후보")

        // 절 → 저 → ㅈ → (없음) 그리고 다시 절
        for _ in 0..<3 { controller.handle(.backspace) }
        #expect(output.text == "창세기1장1")
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }
        #expect(output.text == "창세기1장1절")
        #expect(controller.textTail == "창세기1장1절")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil, "다시 쳐도 후보")

        // 한 글자 더 지워 숫자까지 걷어냈다가 복원해도 같다
        for _ in 0..<4 { controller.handle(.backspace) }
        #expect(output.text == "창세기1장")
        controller.handle(.symbols)
        controller.handle(.character("1"))
        controller.handle(.symbols)
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }
        #expect(output.text == "창세기1장1절")
        #expect(controller.textTail == "창세기1장1절")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil)
    }


    @Test("숫자 줄(한글 모드 숫자)로 친 트리거도 끝 글자를 지웠다 다시 치면 후보가 뜬다")
    func retypingWithNumberRowDigits() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d", "t", "p", "r", "l", "1", "w", "k", "d", "1", "w", "j", "f"] {
            controller.handle(.character(key))
        }
        #expect(output.text == "창세기1장1절")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil)
        for _ in 0..<3 { controller.handle(.backspace) }
        #expect(output.text == "창세기1장1")
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }
        #expect(output.text == "창세기1장1절")
        #expect(controller.textTail == "창세기1장1절")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil)
    }

    /// 실기 원인: 호스트가 우리 백스페이스에 반응해 textDidChange를 보내면 sync가 꼬리를 날렸다
    @Test("문서 꼬리를 주면 sync가 꼬리를 문서에서 다시 세운다 — 백스페이스 메아리 뒤에도 후보")
    func syncRebuildsTailFromDocument() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: FakeBible(), entries: [])

        for key in ["c", "k", "d", "t", "p", "r", "l", "1", "w", "k", "d", "1", "w", "j", "f"] {
            controller.handle(.character(key))
        }
        for _ in 0..<3 { controller.handle(.backspace) }       // 절 삭제
        controller.syncWithDocument(documentTail: output.text)  // 호스트의 textDidChange 메아리
        #expect(controller.textTail == "창세기1장1")
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }
        #expect(matcher.suggestion(forTail: controller.textTail) != nil)

        // 문서 꼬리 없이(nil) 부르면 이전처럼 버린다
        controller.syncWithDocument()
        #expect(controller.textTail == "")
    }

    @Test("문서가 우리 조합 글자로 끝나 있으면 sync가 조합을 유지한다")
    func syncKeepsCompositionWhenDocumentMatches() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["w", "j"] { controller.handle(.character(key)) }   // 저 (조합 중)
        controller.syncWithDocument(documentTail: "안녕 " + output.text)  // 메아리: "안녕 저"
        #expect(controller.isComposing, "문서와 일치 — 조합 유지")
        #expect(controller.textTail == "안녕 저")
        controller.handle(.character("f"))                           // ㄹ → 절
        #expect(output.text == "절")

        // 문서가 다른 곳(커서 이동)이면 이전처럼 조합을 버린다
        controller.syncWithDocument(documentTail: "다른 텍스트")
        #expect(!controller.isComposing)
        #expect(controller.textTail == "다른 텍스트")
    }

    @Test("문서 꼬리는 마지막 줄 48자로 자르고, 가져온 단어는 다음 구분자까지 학습하지 않는다")
    func syncTailLimitsAndLearningGuard() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }

        let long = String(repeating: "가", count: 60)
        controller.syncWithDocument(documentTail: "첫 줄\n" + long)
        #expect(controller.textTail.count == 48)
        #expect(!controller.textTail.contains("\n"))

        controller.handle(.space)   // 문서에서 온 단어 — 학습 제외
        #expect(learned.isEmpty)
        for key in ["r", "k", "s", "k"] { controller.handle(.character(key)) }  // 가나
        controller.handle(.space)   // 직접 친 단어 — 학습
        #expect(learned == ["가나"])
    }

    @Test("조합 중에 삽입해도 문서가 훼손되지 않는다")
    func insertWhileComposing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let anthem = SnippetEntry(trigger: "애국가 1절", title: "애국가 1절", body: "동해물과…")
        let matcher = SnippetMatcher(bible: nil, entries: [anthem])

        // 애국가 1절 — 마지막 "절"(w+j+f)이 조합 중인 상태
        for key in ["d", "o", "r", "n", "r", "r", "k"] { controller.handle(.character(key)) }  // 애국가
        controller.handle(.space)
        controller.handle(.character("1"))
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }  // 절 (조합 중)
        #expect(output.text == "애국가 1절")
        #expect(controller.isComposing)

        let suggestion = matcher.suggestion(forTail: controller.textTail)
        controller.insertSnippet(suggestion!)
        #expect(output.text == "동해물과…")
    }
}

// ─────────────────────────────────────────────────────────────────────────
// 단축어 여러 개 · 띄어쓰기 무시 (2026-09-15 사장님 지시)
// ─────────────────────────────────────────────────────────────────────────

/// 용어가 「트리거」에서 **「단축어」**로 바뀌었다 — iOS 설정의 「텍스트 대치」가 쓰는 애플 공식
/// 한국어 용어라 설명이 거의 필요 없다. **코드 식별자(`trigger`·`triggers`)는 영어 그대로** 둔다
/// (글쇠 개명 때와 같은 원칙 — 사용자에게 보이는 문자열만 바꾼다).
@Suite("단축어 — 저장 스키마 마이그레이션")
struct SnippetEntryMigrationTests {

    /// **옛 저장본은 `trigger` 단일 문자열**이다. 사용자 기기의 App Group 에 그대로 있다.
    @Test("옛 스키마(trigger 문자열)를 읽는다")
    func decodesLegacySingleTrigger() throws {
        let json = #"{"trigger":"우리집 주소","title":"집","body":"서울시 ..."}"#
        let entry = try JSONDecoder().decode(SnippetEntry.self, from: Data(json.utf8))
        #expect(entry.triggers == ["우리집 주소"])
        #expect(entry.title == "집")
    }

    @Test("새 스키마(triggers 배열)를 읽는다")
    func decodesNewTriggers() throws {
        let json = #"{"triggers":["우리집주소","집주소"],"title":"집","body":"서울시 ..."}"#
        let entry = try JSONDecoder().decode(SnippetEntry.self, from: Data(json.utf8))
        #expect(entry.triggers == ["우리집주소", "집주소"])
    }

    /// **새 스키마가 이긴다** — 둘 다 있으면 배열을 쓴다.
    @Test("triggers 와 trigger 가 둘 다 있으면 triggers 를 쓴다")
    func newSchemaWins() throws {
        let json = #"{"triggers":["a","b"],"trigger":"c","title":"t","body":"b"}"#
        let entry = try JSONDecoder().decode(SnippetEntry.self, from: Data(json.utf8))
        #expect(entry.triggers == ["a", "b"])
    }

    /// **둘 다 없어도 크래시하지 않는다** — 발동하지 않는 죽은 항목이 될 뿐이다.
    @Test("단축어 키가 아예 없으면 빈 배열이다 (크래시 없음)")
    func missingTriggersIsEmpty() throws {
        let json = #"{"title":"제목만","body":"본문만"}"#
        let entry = try JSONDecoder().decode(SnippetEntry.self, from: Data(json.utf8))
        #expect(entry.triggers.isEmpty)
    }

    @Test("왕복(encode → decode)이 같다")
    func roundTrips() throws {
        let original = SnippetEntry(triggers: ["우리집주소", "집주소"], title: "집", body: "서울시 ...")
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(SnippetEntry.self, from: data) == original)
        // 인코딩은 **새 키로만** 쓴다 — 옛 키를 남기면 무엇이 진짜인지 모호해진다
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("triggers"))
        #expect(!text.contains("\"trigger\""))
    }

    /// 내장 팩 JSON(`Snippets.json`·`Greetings.json`)도 **단일 `trigger`** 형태다.
    /// **그 JSON 을 고치지 않고 디코더가 흡수한다** — 번들 리소스를 건드리면 회귀 위험이 는다.
    @Test("내장 팩 JSON 형태(배열 안의 단일 trigger)가 그대로 읽힌다")
    func decodesBundledPackShape() throws {
        let json = """
        [{"trigger":"애국가 1절","title":"애국가 1절","body":"동해물과 …"},
         {"trigger":"새해인사","title":"새해 인사","body":"새해 복 …"}]
        """
        let entries = try JSONDecoder().decode([SnippetEntry].self, from: Data(json.utf8))
        #expect(entries.map(\.primaryTrigger) == ["애국가 1절", "새해인사"])
    }

    @Test("primaryTrigger 는 첫 단축어, 비었으면 빈 문자열")
    func primaryTrigger() {
        #expect(SnippetEntry(triggers: ["가", "나"], title: "", body: "b").primaryTrigger == "가")
        #expect(SnippetEntry(triggers: [], title: "", body: "b").primaryTrigger == "")
    }
}

/// ★ **편집 시트의 단축어 왕복** (사장님 결정 2026-09-23 — 「내 문구」 편집 진입점).
///
/// ## 왜 이 스위트가 지금 생겼나
///
/// 「저장하면 `triggers`로 인코딩되는가」가 **두 번 연속 미확인**으로 남아 있었다.
/// 원인은 단순했다 — **목록 행을 눌러도 시트가 안 열려서** 저장까지 끌고 갈 수가 없었다.
/// 편집 진입점이 생기며 그 경로가 열렸고, 여기서 **불러오기 → 고치기 → 저장**을 고정한다.
///
/// ## 무엇을 고정하나
///
/// 시트는 단축어를 **쉼표로 합쳐 보여 주고**(`triggers.joined(separator: ", ")`),
/// 저장할 때 **`SnippetEntry.parseTriggers`가 쉼표로 나눈다.**
/// 즉 왕복의 양끝이 **같은 규약**을 탄다 — 그 둘이 갈리면 사용자가 고친 것이 조용히 사라진다.
/// 시트 자체는 `App/` 타깃이라 `swift test`가 못 보므로, **그 둘이 쓰는 도메인 함수**를 검사한다.
@Suite("단축어 — 편집 시트 왕복")
struct SnippetEditorRoundTripTests {

    /// 시트가 불러올 때 쓰는 식 — `SnippetEditorView.init`과 **같은 표현**이다.
    private func load(_ entry: SnippetEntry) -> String {
        entry.triggers.joined(separator: ", ")
    }

    @Test("★ 단축어 3개를 불러 하나 지우고 하나 더해 저장하면 triggers가 기대대로다")
    func editThreeTriggers() throws {
        let original = SnippetEntry(
            triggers: ["우리집주소", "집주소", "우리집"], title: "집", body: "서울시 ...")

        // 1) 불러오기 — 쉼표로 합쳐 보인다
        let shown = load(original)
        #expect(shown == "우리집주소, 집주소, 우리집")

        // 2) 사용자가 고친다 — 「집주소」를 빼고 「우리집주소요」를 더한다
        let edited = "우리집주소, 우리집, 우리집주소요"

        // 3) 저장 — 시트가 쓰는 그 파서다
        let saved = SnippetEntry.parseTriggers(edited)
        #expect(saved == ["우리집주소", "우리집", "우리집주소요"])

        // 4) 저장된 항목이 실제로 그 셋을 들고, **새 키로** 인코딩된다
        let entry = SnippetEntry(triggers: saved, title: original.title, body: original.body)
        let data = try JSONEncoder().encode(entry)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("triggers"))
        #expect(!text.contains("\"trigger\""))
        #expect(try JSONDecoder().decode(SnippetEntry.self, from: data).triggers == saved)
    }

    /// 불러온 그대로 저장하면 **하나도 달라지지 않는다.** 왕복의 항등성이다 —
    /// 여기가 깨지면 사용자가 시트를 열었다 닫기만 해도 단축어가 바뀐다.
    @Test("★ 고치지 않고 저장하면 그대로다", arguments: [
        ["우리집주소"],
        ["우리집주소", "집주소"],
        ["우리집주소", "집주소", "우리집"]
    ])
    func identityRoundTrip(triggers: [String]) {
        let entry = SnippetEntry(triggers: triggers, title: "집", body: "본문")
        #expect(SnippetEntry.parseTriggers(load(entry)) == triggers)
    }

    /// 파서 규약이 왕복에 그대로 걸린다 — **정규화 기준 중복 제거**다.
    /// 사용자가 「집주소, 집 주소」로 고쳐도 **하나로 접힌다**(둘은 같은 단축어다).
    @Test("고칠 때 넣은 중복은 정규화 기준으로 접힌다")
    func duplicatesCollapseOnSave() {
        #expect(SnippetEntry.parseTriggers("집주소, 집 주소") == ["집주소"])
        #expect(SnippetEntry.parseTriggers("우리집주소,  , 집주소") == ["우리집주소", "집주소"])
    }

    /// 빈 시트(추가)에서 아무것도 안 치면 저장 버튼이 막히는 조건 — 파서가 빈 배열을 준다.
    @Test("빈 입력은 빈 배열이다 — 저장 버튼이 막히는 근거")
    func emptyInputGivesNothing() {
        #expect(SnippetEntry.parseTriggers("").isEmpty)
        #expect(SnippetEntry.parseTriggers("  ,  , ").isEmpty)
    }
}

@Suite("단축어 — 띄어쓰기 무시 매칭")
struct SnippetSpacingTests {

    private func matcher(_ entries: [SnippetEntry]) -> SnippetMatcher {
        SnippetMatcher(bible: nil, entries: entries)
    }

    /// 사장님 지시 4 — "우리집주소"로 등록해도 "우리집 주소"·"우 리 집 주 소"로 발동한다.
    @Test("띄어쓰기가 달라도 매칭된다", arguments: [
        "우리집주소", "우리집 주소", "우 리 집 주 소", "우리집  주소"
    ])
    func ignoresWhitespace(tail: String) throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "서울시 ...")
        let hit = try #require(matcher([entry]).suggestion(forTail: tail))
        #expect(hit.body == "서울시 ...")
    }

    /// ★ **이 작업에서 제일 틀리기 쉬운 곳** — 지울 길이는 **꼬리 원문 기준**이다.
    /// 5자짜리 단축어로 등록했어도 사용자가 6자를 쳤으면 6자를 지워야 한다.
    @Test("지울 길이는 꼬리 원문 기준이다", arguments: [
        ("우리집주소", 5), ("우리집 주소", 6), ("우 리 집 주 소", 9)
    ])
    func triggerLengthFollowsTail(testCase: (String, Int)) throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        let hit = try #require(matcher([entry]).suggestion(forTail: testCase.0))
        #expect(hit.trigger == testCase.0)
        #expect(hit.triggerLength == testCase.1)
    }

    /// 꼬리 앞에 다른 글자가 있어도 **접미사**로 맞으면 된다. 그리고 **맞은 구간 앞의 공백은
    /// 포함하지 않는다** — 마지막으로 맞은 글자에서 끊는다.
    @Test("앞에 글자가 있어도 접미사로 맞고, 앞 공백은 안 먹는다")
    func matchesSuffixWithoutLeadingSpace() throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        let hit = try #require(matcher([entry]).suggestion(forTail: "보내줄게 우리집 주소"))
        #expect(hit.trigger == "우리집 주소", "앞 공백을 먹지 않는다")
    }

    // MARK: - ★ 줄바꿈은 경계다 (사장님 결정 2026-09-23)

    /// ## 무엇이 문제였나
    ///
    /// 「우 리 집 주 소」가 먹는 것과 **같은 규칙으로 줄이 갈려도 붙었다.**
    /// 꼬리를 뒤에서 앞으로 풀 때 **비공백만 모았고**, 개행도 `isWhitespace`라 공백처럼
    /// 건너뛰었기 때문이다. 그래서 2~3자 짧은 단축어가 **엉뚱한 줄에서 발동**할 수 있었다.
    ///
    /// ## ★ 고친 자리 — `normalizedTrigger`가 **아니다**
    ///
    /// 그 함수는 설정의 **중복 판정**과 키보드의 **발동**이 공유하는 단일 출처다
    /// (`CLAUDE.md`: *"정규화는 이 한 함수뿐"*). 거기를 고치면 중복 판정까지 바뀌고,
    /// 애초에 **등록된 단축어에 개행이 들어갈 일이 없다.**
    /// 고친 곳은 **꼬리를 되짚는 쪽**(`SnippetMatcher.suggestion(forTail:)`)이다.
    @Test("★ 같은 줄의 공백은 그대로 건너뛴다 — 고친 뒤에도 안 깨진다", arguments: [
        "우리집주소", "우리집 주소", "우 리 집 주 소", "우리집  주소"
    ])
    func newlineFixKeepsSameLineSpacing(tail: String) throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        _ = try #require(matcher([entry]).suggestion(forTail: tail), "같은 줄 공백 무시가 깨졌다")
    }

    /// ★ 줄이 갈리면 **발동하지 않는다.** `\n`·`\r`·`\r\n` 전부.
    @Test("★ 줄바꿈을 건너뛰어 매칭하지 않는다", arguments: [
        "우리집\n주소", "우리집\r주소", "우리집\r\n주소", "우리집\n 주소", "우리집 \n 주소"
    ])
    func doesNotMatchAcrossNewline(tail: String) throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        #expect(matcher([entry]).suggestion(forTail: tail) == nil,
                "줄이 갈렸는데 붙었다: \(tail.debugDescription)")
    }

    /// 경계 **뒤**는 정상이다 — 개행 다음에 온전한 단축어가 오면 발동한다.
    @Test("개행 뒤에 온전히 있으면 발동한다")
    func matchesAfterNewline() throws {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        let hit = try #require(matcher([entry]).suggestion(forTail: "앞줄입니다\n우리집 주소"))
        #expect(hit.body == "본문")
        // ★ 지울 길이는 여전히 **꼬리 원문 기준**이고 개행을 먹지 않는다
        #expect(hit.trigger == "우리집 주소")
        #expect(hit.triggerLength == 6)
    }

    /// ★ 짧은 단축어가 **엉뚱한 줄에서** 발동하던 것이 이 결정의 이유다.
    @Test("★ 짧은 단축어가 줄을 넘어 발동하지 않는다")
    func shortTriggerDoesNotLeakAcrossLines() throws {
        let entry = SnippetEntry(triggers: ["ㄱㄴ"], title: "짧은", body: "본문")
        // 「ㄱ」으로 끝난 줄 + 「ㄴ」으로 시작한 줄 — 고치기 전에는 이것이 붙었다.
        // ★ 매칭은 **접미사**라 단축어가 꼬리 **끝**에 와야 판정이 성립한다
        //   (「ㄴ다음줄」처럼 뒤에 글자가 더 있으면 애초에 안 맞아서 시험이 무의미해진다).
        #expect(matcher([entry]).suggestion(forTail: "안녕ㄱ\nㄴ") == nil)
        // 같은 줄이면 그대로 발동한다
        _ = try #require(matcher([entry]).suggestion(forTail: "안녕 ㄱ ㄴ"))
    }

    @Test("단축어 여러 개 — 어느 쪽으로 쳐도 매칭된다", arguments: ["우리집주소", "집주소", "집 주소"])
    func anyOfMultipleTriggers(tail: String) throws {
        let entry = SnippetEntry(triggers: ["우리집주소", "집주소"], title: "집", body: "본문")
        _ = try #require(matcher([entry]).suggestion(forTail: tail))
    }

    /// 우선순위 — **정규화 길이가 긴 쪽이 이긴다.**
    @Test("정규화 길이가 긴 단축어가 이긴다")
    func longerNormalizedWins() throws {
        let short = SnippetEntry(triggers: ["집주소"], title: "짧은", body: "짧은 본문")
        let long = SnippetEntry(triggers: ["우리집주소"], title: "긴", body: "긴 본문")
        let hit = try #require(matcher([short, long]).suggestion(forTail: "우리집 주소"))
        #expect(hit.title == "긴")
    }

    /// 같으면 **앞선 엔트리**가 이긴다 — 사용자 문구를 내장 팩보다 앞에 넣으므로 사용자가 이긴다.
    @Test("길이가 같으면 앞선 엔트리(사용자)가 이긴다")
    func earlierEntryWinsOnTie() throws {
        let user = SnippetEntry(triggers: ["새해인사"], title: "사용자", body: "사용자 본문")
        let pack = SnippetEntry(triggers: ["새해 인사"], title: "내장", body: "내장 본문")
        let hit = try #require(matcher([user, pack]).suggestion(forTail: "새해인사"))
        #expect(hit.title == "사용자")
    }

    /// 한 엔트리 안에 여럿이면 **그중 가장 긴 매치**를 쓴다.
    @Test("한 엔트리 안에서는 가장 긴 매치를 쓴다")
    func longestWithinEntry() throws {
        let entry = SnippetEntry(triggers: ["집주소", "우리집주소"], title: "집", body: "본문")
        let hit = try #require(matcher([entry]).suggestion(forTail: "우리집 주소"))
        #expect(hit.trigger == "우리집 주소", "짧은 쪽(집 주소)이 아니라 긴 쪽이 맞아야 한다")
    }

    @Test("빈 triggers 엔트리는 절대 매칭되지 않는다 (크래시도 없다)", arguments: ["", "아무 글", "   "])
    func emptyTriggersNeverMatch(tail: String) {
        let dead = SnippetEntry(triggers: [], title: "죽은 항목", body: "본문")
        #expect(matcher([dead]).suggestion(forTail: tail) == nil)
    }

    @Test("공백만으로 이뤄진 단축어도 매칭되지 않는다")
    func whitespaceOnlyTriggerNeverMatches() {
        let blank = SnippetEntry(triggers: ["   "], title: "공백", body: "본문")
        #expect(matcher([blank]).suggestion(forTail: "아무 글") == nil)
        #expect(matcher([blank]).suggestion(forTail: "   ") == nil)
    }

    /// 기존 회귀 — 내장 팩 단축어가 **띄어쓰기 그대로도** 여전히 매칭된다.
    @Test("내장 팩 회귀 — 띄어쓰기 그대로 매칭된다", arguments: [
        "애국가 1절", "애국가1절", "새해인사", "새해 인사"
    ])
    func bundledPackStillMatches(tail: String) throws {
        let entries = [
            SnippetEntry(triggers: ["애국가 1절"], title: "애국가 1절", body: "동해물과 …"),
            SnippetEntry(triggers: ["새해인사"], title: "새해 인사", body: "새해 복 …")
        ]
        _ = try #require(matcher(entries).suggestion(forTail: tail))
    }

    /// **엉뚱한 글자는 공백을 건너뛰어도 안 맞는다** — 공백만 무시하지 글자는 안 건너뛴다.
    @Test("공백 외의 글자는 건너뛰지 않는다", arguments: ["우리집X주소", "우리 집이 주소"])
    func doesNotSkipNonWhitespace(tail: String) {
        let entry = SnippetEntry(triggers: ["우리집주소"], title: "집", body: "본문")
        #expect(matcher([entry]).suggestion(forTail: tail) == nil)
    }
}
