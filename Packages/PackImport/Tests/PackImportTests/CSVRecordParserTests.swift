import Foundation
import Testing
@testable import PackImport

/// 논리 레코드 파서 (PDR 5-4, AC-13 · AC-16 · AC-49(e)).
@Suite("CSV 논리 레코드 (5-4)")
struct CSVRecordParserTests {

    private func cells(_ text: String, _ delimiter: CSVDelimiter = .comma) throws -> [[String]] {
        try CSVRecordParser.parse(text, delimiter: delimiter).records.map(\.cells)
    }

    @Test("레코드 끝은 CRLF·LF·CR 모두, 마지막 레코드 뒤 줄바꿈이 없어도 받는다 (AC-49 e)", arguments: [
        "a,b\r\nc,d", "a,b\nc,d", "a,b\rc,d", "a,b\r\nc,d\r\n", "a,b\nc,d\n"
    ])
    func lineEndings(text: String) throws {
        #expect(try cells(text) == [["a", "b"], ["c", "d"]])
    }

    @Test("따옴표 셀 — 구분자·`\"\"`·셀 안 줄바꿈은 내용, 레코드 시작 줄 번호가 맞다")
    func quotedCells() throws {
        let result = try CSVRecordParser.parse("1,\"가, 나\",\"그는 \"\"네\"\"\"\r\n2,\"첫 줄\n둘째 줄\",x\r\n3,c,d",
                                               delimiter: .comma)
        #expect(result.records.map(\.cells) == [["1", "가, 나", "그는 \"네\""], ["2", "첫 줄\n둘째 줄", "x"], ["3", "c", "d"]])
        #expect(result.records.map(\.line) == [1, 2, 4])
        #expect(result.physicalLines == 4)
    }

    @Test("셀 값은 trim하지 않는다 — 본문 보존")
    func noTrim() throws {
        #expect(try cells(" a , b ") == [[" a ", " b "]])
    }

    @Test("빈 칸만 있는 레코드(`,,,`)는 빈 레코드다")
    func blankRecord() throws {
        let records = try CSVRecordParser.parse(",,,\r\n\r\na,,b", delimiter: .comma).records
        #expect(records.map(\.isBlank) == [true, true, false])
        #expect(records[0].cells == ["", "", "", ""])
    }

    @Test("닫히지 않은 따옴표 → quote 오류(레코드·줄 번호만) (AC-13)")
    func unterminated() {
        #expect(throws: CSVParseError.quote(CSVQuoteError(kind: .unterminated, record: 2, line: 2))) {
            try CSVRecordParser.parse("a,b\r\n1,\"끝나지 않음\r\n2,x", delimiter: .comma)
        }
    }

    @Test("닫는 따옴표 뒤에 구분자·레코드 끝이 아닌 문자 → quote 오류 (AC-13)")
    func characterAfterClosingQuote() {
        #expect(throws: CSVParseError.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 1, line: 1))) {
            try CSVRecordParser.parse("\"가\"나,다", delimiter: .comma)
        }
    }

    @Test("따옴표 없는 셀 중간의 `\"`는 리터럴로 받고 건수만 센다")
    func strayQuote() throws {
        let result = try CSVRecordParser.parse("a\"b,c\"\r\nd,e", delimiter: .comma)
        #expect(result.records.map(\.cells) == [["a\"b", "c\""], ["d", "e"]])
        #expect(result.strayQuoteCount == 2)
    }

    @Test("구분자 후보 — 탭·세미콜론")
    func otherDelimiters() throws {
        #expect(try cells("a\tb;c\r\nd\te", .tab) == [["a", "b;c"], ["d", "e"]])
        #expect(try cells("a;b,c\r\nd;e", .semicolon) == [["a", "b,c"], ["d", "e"]])
    }

    @Test("물리 줄이 상한(50,000)을 넘으면 거부 — 논리 레코드와 따로 센다 (AC-16)")
    func physicalLineCap() throws {
        let ok = Array(repeating: "a", count: 50_000).joined(separator: "\n")
        #expect(try CSVRecordParser.parse(ok, delimiter: .comma).physicalLines == 50_000)
        #expect(throws: CSVParseError.tooManyLines) {
            try CSVRecordParser.parse(ok + "\na", delimiter: .comma)
        }
    }

    @Test("빈 문자열은 레코드 0")
    func empty() throws {
        #expect(try CSVRecordParser.parse("", delimiter: .comma).records.isEmpty)
    }
}
