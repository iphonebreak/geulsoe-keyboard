import Foundation
import TadakDomain

/// 구분자 후보(5-2) — 순서가 곧 「모든 후보가 quote 오류로 탈락」일 때 보고할 오류의 우선순위다
public enum CSVDelimiter: Character, CaseIterable, Sendable {
    case comma = ","
    case semicolon = ";"
    case tab = "\t"
}

/// quote-aware **논리 레코드** 하나(5-4) — 물리 줄을 먼저 나누거나 거르지 않는다
public struct CSVRecord: Equatable, Sendable {
    /// 셀 값 — **trim하지 않는다**(본문 보존). 헤더·번호·단축어·메타 키는 읽는 쪽이 trim한다
    public var cells: [String]
    /// 이 레코드가 시작한 물리 줄(1부터) — 「논리 레코드 N (줄 M)」 보고용
    public var line: Int

    public init(cells: [String], line: Int) {
        self.cells = cells
        self.line = line
    }

    /// 빈 레코드 = **모든 셀이 빈 문자열**(`,,,`·빈 줄) — 공백 글자만 든 셀은 빈 셀이 아니다(5-4 명확화 ②)
    public var isBlank: Bool { cells.allSatisfy(\.isEmpty) }
}

public struct CSVParseResult: Equatable, Sendable {
    public var records: [CSVRecord]
    public var physicalLines: Int
    /// 따옴표 없는 셀 중간의 `"` — 리터럴로 받고 건수만 표시한다(5-4)
    public var strayQuoteCount: Int
}

public enum CSVParseError: Error, Equatable, Sendable {
    case quote(CSVQuoteError)
    case tooManyLines
}

/// RFC 4180 + 현실의 관대함(PDR 5-4).
///
/// - `""` → `"`. **닫는 따옴표 뒤에는 구분자 또는 레코드 끝만** — 그 밖의 문자·닫히지 않은 따옴표는 quote 오류.
///   이 오류를 전체 거부로 올릴지(본 파싱) 그 후보만 탈락시킬지(후보 시험)는 부르는 쪽이 정한다(5-2 명확화 ①).
/// - 레코드 끝은 CRLF·LF·CR 모두, **마지막 레코드 뒤 줄바꿈이 없어도** 받는다(엑셀·구글 실측).
/// - 셀 안 줄바꿈은 원문 그대로 둔다 — LF 통일은 문자 정리(11절)가 한다.
public enum CSVRecordParser {

    /// - Parameter maxNonBlankRecords: **비지 않은** 레코드가 이만큼 모이면 멈춘다(구분자 후보 시험용 — 「첫 논리 레코드들」만 본다).
    ///   빈 레코드는 결과에 남기지만(번호를 본 파싱과 맞춘다) 세지 않는다 — 머리글 앞 빈 줄이 시험 창을 다 쓰지 않게(검증 F3). nil이면 끝까지
    public static func parse(
        _ text: String, delimiter: CSVDelimiter, maxNonBlankRecords: Int? = nil
    ) throws(CSVParseError) -> CSVParseResult {
        var records: [CSVRecord] = []
        var nonBlankCount = 0
        var cells: [String] = []
        var cell = ""
        var line = 1
        var recordLine = 1
        var strayQuotes = 0
        var hasContent = false        // 지금 레코드에 글자(또는 구분자)가 하나라도 있었나

        enum State { case cellStart, unquoted, quoted, afterClosingQuote }
        var state = State.cellStart
        let separator = delimiter.rawValue

        func endRecord() {
            cells.append(cell)
            let record = CSVRecord(cells: cells, line: recordLine)
            if !record.isBlank { nonBlankCount += 1 }
            records.append(record)
            cells = []
            cell = ""
            hasContent = false
            state = .cellStart
        }

        for character in text {
            if let maxNonBlankRecords, nonBlankCount >= maxNonBlankRecords { break }
            // 글자가 있는 줄만 센다 — 마지막 줄바꿈 뒤의 빈 자리는 줄이 아니다
            if line > PackLimits.physicalLines { throw .tooManyLines }
            let isNewline = character == "\n" || character == "\r" || character == "\r\n"
            switch state {
            case .quoted:
                if character == "\"" {
                    state = .afterClosingQuote
                } else {
                    if isNewline { line += 1 }
                    cell.append(character)
                }
            case .afterClosingQuote:
                if character == "\"" {
                    cell.append("\"")           // `""` → `"`
                    state = .quoted
                } else if character == separator {
                    cells.append(cell)
                    cell = ""
                    state = .cellStart
                } else if isNewline {
                    endRecord()
                    line += 1
                    recordLine = line
                } else {
                    throw .quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: records.count + 1, line: recordLine))
                }
            case .cellStart, .unquoted:
                if character == "\"" && state == .cellStart {
                    state = .quoted
                    hasContent = true
                } else if character == separator {
                    cells.append(cell)
                    cell = ""
                    state = .cellStart
                    hasContent = true
                } else if isNewline {
                    if hasContent || !cell.isEmpty || !cells.isEmpty {
                        endRecord()
                    } else {
                        // 빈 물리 줄 — 셀 하나짜리 빈 레코드로 둔다(읽는 쪽이 빈 레코드로 무시)
                        records.append(CSVRecord(cells: [""], line: recordLine))
                    }
                    line += 1
                    recordLine = line
                } else {
                    if character == "\"" { strayQuotes += 1 }
                    cell.append(character)
                    state = .unquoted
                    hasContent = true
                }
            }
        }

        let stopped = maxNonBlankRecords.map { nonBlankCount >= $0 } ?? false
        if !stopped {
            switch state {
            case .quoted:
                throw .quote(CSVQuoteError(kind: .unterminated, record: records.count + 1, line: recordLine))
            case .afterClosingQuote:
                endRecord()
            case .cellStart, .unquoted:
                if hasContent || !cell.isEmpty || !cells.isEmpty { endRecord() }
            }
        }
        return CSVParseResult(records: records, physicalLines: records.isEmpty && text.isEmpty ? 0 : line - (text.last.map(isLineEnd) == true ? 1 : 0),
                              strayQuoteCount: strayQuotes)
    }

    private static func isLineEnd(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }
}
