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
        let scanned = scan(text, delimiter: delimiter, maxNonBlankRecords: maxNonBlankRecords)
        if let failure = scanned.failure { throw failure }
        return scanned.result
    }

    /// `parse`와 같되 오류가 나도 **그 앞까지 모은 레코드**를 함께 돌려준다 — 후보 시험이 quote 오류 전에 머리글을
    /// 인정했는지 보려고 쓴다(재검증 N1). 오류가 났을 때의 `physicalLines`는 그 지점까지의 줄이다.
    /// `cancellation`이 있으면 몇 천 글자마다 취소를 본다 — 취소되면 그 자리에서 멈추고 그 앞까지를 돌려준다(부르는 쪽이 버린다, codex 반론 #3)
    static func scan(
        _ text: String, delimiter: CSVDelimiter, maxNonBlankRecords: Int? = nil, cancellation: PackCancellation? = nil
    ) -> (result: CSVParseResult, failure: CSVParseError?) {
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

        /// 칸 하나를 레코드에 — **13칸(`RawTable.columnLimit` = 메타 12 + 넘침 1)까지만 배열을 늘린다**(codex 반론 #3). 넘친 칸은 마지막 칸
        /// 하나로 접고 먼저 온 비지 않은 칸이 남는다 — xlsx 표와 같은 접기라 메타(> 12칸)·머리글(> 8열)·데이터(머리글보다 넓음) 판정이
        /// 두 형식에서 같다(AC-32). 쉼표만 수백만 개인 줄이 셀 배열을 수백만 칸으로 늘리지 않는다
        func appendCell(_ value: String) {
            if cells.count < RawTable.columnLimit {
                cells.append(value)
            } else if cells[RawTable.columnLimit - 1].isEmpty, !value.isEmpty {
                cells[RawTable.columnLimit - 1] = value
            }
        }

        func endRecord() {
            appendCell(cell)
            let record = CSVRecord(cells: cells, line: recordLine)
            if !record.isBlank { nonBlankCount += 1 }
            records.append(record)
            cells = []
            cell = ""
            hasContent = false
            state = .cellStart
        }

        func failed(_ failure: CSVParseError) -> (result: CSVParseResult, failure: CSVParseError?) {
            (CSVParseResult(records: records, physicalLines: line, strayQuoteCount: strayQuotes), failure)
        }

        var steps = 0
        var cancelled = false
        for character in text {
            if let maxNonBlankRecords, nonBlankCount >= maxNonBlankRecords { break }
            if let cancellation {
                steps &+= 1
                if steps & 0xFFF == 0, cancellation.poll() {
                    cancelled = true
                    break
                }
            }
            // 글자가 있는 줄만 센다 — 마지막 줄바꿈 뒤의 빈 자리는 줄이 아니다
            if line > PackLimits.physicalLines { return failed(.tooManyLines) }
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
                    appendCell(cell)
                    cell = ""
                    state = .cellStart
                } else if isNewline {
                    endRecord()
                    line += 1
                    recordLine = line
                } else {
                    return failed(.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: records.count + 1, line: recordLine)))
                }
            case .cellStart, .unquoted:
                if character == "\"" && state == .cellStart {
                    state = .quoted
                    hasContent = true
                } else if character == separator {
                    appendCell(cell)
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

        let stopped = cancelled || (maxNonBlankRecords.map { nonBlankCount >= $0 } ?? false)
        if !stopped {
            switch state {
            case .quoted:
                return failed(.quote(CSVQuoteError(kind: .unterminated, record: records.count + 1, line: recordLine)))
            case .afterClosingQuote:
                endRecord()
            case .cellStart, .unquoted:
                if hasContent || !cell.isEmpty || !cells.isEmpty { endRecord() }
            }
        }
        let result = CSVParseResult(records: records, physicalLines: records.isEmpty && text.isEmpty ? 0 : line - (text.last.map(isLineEnd) == true ? 1 : 0),
                                    strayQuoteCount: strayQuotes)
        return (result, nil)
    }

    private static func isLineEnd(_ character: Character) -> Bool {
        character == "\n" || character == "\r" || character == "\r\n"
    }
}

/// 계산 중 취소 확인(codex 반론 #3) — 부르는 쪽 확인은 몇 천 글자마다 한 번만 부르고, **한 번 참을 보면** 그 뒤로는 묻지 않고 참이다
/// (취소를 본 뒤 남은 단계가 다시 계산하거나 다시 묻지 않게). 한 계산 안에서만 쓴다 — 스레드를 넘기지 않는다
final class PackCancellation {
    private let check: () -> Bool
    private(set) var isCancelled = false

    init(_ check: @escaping () -> Bool) {
        self.check = check
    }

    func poll() -> Bool {
        if !isCancelled, check() { isCancelled = true }
        return isCancelled
    }
}
