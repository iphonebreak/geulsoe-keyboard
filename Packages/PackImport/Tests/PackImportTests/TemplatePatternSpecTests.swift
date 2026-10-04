import Foundation
import Testing
import KeyboardCore
import TadakDomain
@testable import PackImport

/// 템플릿 단축어 스키마 (10-1·10-2·10-3, R3, AC-21 · AC-22 · AC-23 · AC-24 일부).
@Suite("템플릿 스키마 (10-1, AC-21 · AC-23)")
struct TemplatePatternSpecTests {

    @Test("정규화(공백 제거) 뒤 접두·접미 — `SnippetEntry.normalizedTrigger` 같은 함수", arguments: [
        ("사자성어 {n}번", "사자성어", "번"),
        ("사자 성어 {n} 번", "사자성어", "번"),
        ("상용 영어{n}번 문장", "상용영어", "번문장"),
        ("회차{n}장", "회차", "장")
    ])
    func valid(testCase: (raw: String, prefix: String, suffix: String)) throws {
        #expect(try TemplatePatternSpec.parse(testCase.raw).get() == TemplatePattern(prefix: testCase.prefix, suffix: testCase.suffix))
    }

    @Test("거부 표 — `{n}` 개수·접두 2자 미만·접두 없음·접두 끝 숫자·숫자 단독·접미 없음·literal 개행·날짜 예약 끝말·40자 초과 (AC-21·AC-23)",
          arguments: [
            ("사자성어", TemplatePatternSpec.Failure.placeholderCount),
            ("{n}사자{n}번", .placeholderCount),
            ("찬{n}장", .prefixTooShort),
            ("{n}번", .prefixTooShort),
            (" 가 {n}번", .prefixTooShort),
            ("회차2{n}번", .prefixEndsWithDigit),
            ("12{n}번", .prefixAllDigits),
            ("사자성어{n}", .suffixEmpty),
            ("사자성어{n}  ", .suffixEmpty),
            ("사자\n성어{n}번", .literalContainsNewline),
            ("사자성어{n}번\n", .literalContainsNewline),
            ("회차{n}시간", .reservedDateSuffix),
            ("회차{n}일후날짜", .reservedDateSuffix),
            ("회차{n}시각", .reservedDateSuffix),
            (String(repeating: "가", count: 40) + "{n}번", .literalTooLong)
          ])
    func rejected(testCase: (raw: String, failure: TemplatePatternSpec.Failure)) {
        #expect(TemplatePatternSpec.parse(testCase.raw) == .failure(testCase.failure))
    }

    @Test("literal 40자는 받는다 — 최대 확장 40+4자리 = 44")
    func literalBoundary() throws {
        let pattern = try TemplatePatternSpec.parse(String(repeating: "가", count: 39) + "{n}번").get()
        #expect(pattern.literalLength == 40)
    }

    @Test("끝말이 날짜·시간·시각으로 끝나지 않으면 받는다(전체 일치가 아니라 endsWith)")
    func dateSuffixOnlyAtEnd() throws {
        #expect((try? TemplatePatternSpec.parse("회차{n}날짜표").get()) != nil)
    }
}

@Suite("성경 충돌 — 탐침 2개가 아니라 전체 n (10-2, AC-22)")
struct TemplateBibleCollisionTests {

    /// 반례(반론자2): n=1·10은 역순 범위라 성경 파서가 거부하지만 n=50~51에서 정상 구절이 된다
    @Test("`창세기1장50~{n}절` — 탐침 1·10은 통과하지만 전체 n 검사가 잡는다")
    func rangeCounterexample() throws {
        let raw = "창세기1장50~{n}절"
        let pattern = try TemplatePatternSpec.parse(raw).get()
        #expect(BibleReferenceParser.matchSuffix(of: "창세기1장50~1절") == nil)
        #expect(BibleReferenceParser.matchSuffix(of: "창세기1장50~10절") == nil)
        #expect(BibleReferenceParser.matchSuffix(of: "창세기1장50~51절") != nil)
        let first = try #require(TemplatePatternSpec.firstBibleCollision(pattern, raw: raw))
        #expect((50...51).contains(first))
    }

    @Test("`창세기{n}장1절` — n=1부터 충돌, 공백 표기 변형(`창세기 {n}장 1절`)도 같은 패턴")
    func chapterVerse() throws {
        for raw in ["창세기{n}장1절", "창세기 {n}장 1절"] {
            let pattern = try TemplatePatternSpec.parse(raw).get()
            #expect(TemplatePatternSpec.firstBibleCollision(pattern, raw: raw) == 1)
        }
    }

    @Test("성경과 무관한 틀은 1~9,999 어디서도 충돌하지 않는다")
    func noCollision() throws {
        for raw in ["사자성어 {n}번", "상용 영어 {n}번", "회차{n}장"] {
            let pattern = try TemplatePatternSpec.parse(raw).get()
            #expect(TemplatePatternSpec.firstBibleCollision(pattern, raw: raw) == nil)
        }
    }
}

@Suite("정적 단축어가 가림 (10-3, AC-24 일부)")
struct TemplateShadowingTests {

    private let pattern = TemplatePattern(prefix: "사자성어", suffix: "번")

    @Test("템플릿이 만들 수 있는 입력의 접미사인 단축어는 그 패턴을 가린다 — 거부가 아니라 표시", arguments: [
        ("번", true), ("3번", true), ("3 번", true), ("어3번", true), ("성어12번", true), ("0번", true),
        ("사자성어9999번", true), ("0123번", false), ("가번", false), ("장", false), ("사자성어", false),
        ("어번", false), ("12345번", false), ("x사자성어1번", false)
    ])
    func shadowing(testCase: (trigger: String, shadows: Bool)) {
        let shadowing = TemplatePatternSpec.shadowingTriggers(of: pattern, among: [testCase.trigger])
        #expect(shadowing == (testCase.shadows ? [testCase.trigger] : []))
    }
}
