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
        #expect(hit?.prefix == "[창세기 1:1] ")
        #expect(hit?.insertedText == "[창세기 1:1] " + FakeBible.genesis11)
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
        #expect(hit.prefix == "[창세기 1:1-3] ")
        #expect(hit.body == """
            1 \(FakeBible.genesis11)
            2 창세기 1장 2절 본문
            3 창세기 1장 3절 본문
            """)
        #expect(hit.triggerLength == 9, "'창세기 1:1~3' 9자만 지운다")
        #expect(hit.insertedText == "[창세기 1:1-3] " + hit.body)
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
        #expect(hit.prefix == "[창세기 1:1] ")
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
        let inserted = "[창세기 1:1] " + FakeBible.genesis11
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
            .delete(7), .insert("[창세기 1:1-3] " + body)
        ])
        #expect(output.text == "1[창세기 1:1-3] " + body)
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

        let inserted = "[창세기 1:1] " + FakeBible.genesis11
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
