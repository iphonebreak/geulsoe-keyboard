import Foundation
import Testing
import HangulEngine
import TadakDomain
@testable import KeyboardCore

/// 존재하는 절만 아는 fake — 창세기 1장 1절 하나.
private struct FakeBible: BibleVerseRepository {
    static let genesis11 = "태초에 하나님이 천지를 창조하시니라"

    func text(book: Int, chapter: Int, verse: Int) -> String? {
        (book == 1 && chapter == 1 && verse == 1) ? Self.genesis11 : nil
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
