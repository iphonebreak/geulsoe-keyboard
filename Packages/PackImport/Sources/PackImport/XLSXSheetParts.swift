import Foundation

// 외부 채움글 1-e ② — 공유 문자열·스타일·시트 XML 처리기(PDR 6-4·6-5·6-5b). 모르는 요소는 `false`로 하위 트리째 건너뛴다.

/// SpreadsheetML 본문 네임스페이스 요소인가
private func isMain(_ element: XLSXXML.Element) -> Bool {
    element.namespace.map(XLSXXML.spreadsheetNamespaces.contains) == true
}

private func checkMainRoot(_ element: XLSXXML.Element, _ name: String) throws(XLSXWorkbookFailure) {
    guard element.name == name, isMain(element) else { throw .unexpectedPart }
}

/// ASCII 숫자만(부호·공백 없음), 자릿수 상한 안 — 넘치면 nil
private func digits(_ text: String, maxLength: Int = 9) -> Int? {
    guard !text.isEmpty, text.utf8.count <= maxLength, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
    return Int(text)
}

/// XML Schema boolean
private func boolean(_ text: String?) throws(XLSXWorkbookFailure) -> Bool {
    switch text {
    case nil, "0", "false": false
    case "1", "true": true
    default: throw .malformedPart
    }
}

// MARK: - 공유 문자열

/// `<sst><si>` — `<t>` 또는 `<r><t>` 조각을 이어 붙이고 `<rPh>`(발음 힌트)·`<rPr>`는 건너뛴다. 조각마다 `_xHHHH_`를 풀고
/// 항목이 끝나면 CRLF·CR → LF(6-4 순서 계약). 색인 = 문서 순서. `count`·`uniqueCount`는 보지 않는다
final class SharedStringsHandler: XLSXXMLHandler {
    private let limits: XLSXWorkbookLimits
    private var path: [String] = []
    private var item: String?
    private var piece: String?
    private(set) var strings: [String] = []

    init(limits: XLSXWorkbookLimits) {
        self.limits = limits
    }

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if path.isEmpty {
            try checkMainRoot(element, "sst")
        } else {
            guard isMain(element) else { return false }
            switch (path.last, element.name) {
            case ("sst", "si"):
                guard strings.count < limits.sharedStrings else { throw .tooManySharedStrings }
                item = ""
            case ("si", "t"), ("r", "t"):
                piece = ""
            case ("si", "r"):
                break
            default:
                return false
            }
        }
        path.append(element.name)
        return true
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) {
        switch path.removeLast() {
        case "t":
            item?.append(XLSXText.decodeEscapes(piece ?? ""))
            piece = nil
        case "si":
            let text = XLSXText.normalizeNewlines(item ?? "")
            guard text.utf8.count <= limits.textBytes else { throw .textTooLong }
            strings.append(text)
            item = nil
        default:
            break
        }
    }

    func characters(_ string: String) throws(XLSXWorkbookFailure) {
        piece?.append(string)
    }
}

// MARK: - 스타일·날짜 서식

/// `cellXfs` 색인 → 날짜 서식인가
struct XLSXCellStyles: Sendable {
    /// cellXfs 순서. 비면 스타일 파트가 없다 — 색인 0(기본)만 받는다
    let dateFlags: [Bool]

    /// 셀 `s` 속성 → 날짜 서식인가. 범위 밖이면 거부
    func isDate(styleIndex text: String?) throws(XLSXWorkbookFailure) -> Bool {
        guard let text else { return dateFlags.first ?? false }
        guard let index = digits(text) else { throw .invalidStyleIndex }
        if dateFlags.isEmpty {
            guard index == 0 else { throw .invalidStyleIndex }
            return false
        }
        guard index < dateFlags.count else { throw .invalidStyleIndex }
        return dateFlags[index]
    }
}

/// `<styleSheet>` — `<numFmts><numFmt numFmtId formatCode>`와 `<cellXfs><xf numFmtId>`만 본다(`cellStyleXfs`의 `xf`는 다른 표다).
/// `applyNumberFormat`은 보지 않는다(엑셀·구글 모두 셀 xf의 번호를 그대로 쓴다 — 날짜를 놓치지 않는 쪽)
final class StylesHandler: XLSXXMLHandler {
    private var path: [String] = []
    private var formats: [Int: String] = [:]
    private var formatIDs: [Int] = []
    private var sawCellFormats = false

    func result() -> XLSXCellStyles {
        // 재정의가 우선 — 엑셀은 내장 6을 ₩ 통화 서식으로 다시 적어 저장한다(P-10)
        XLSXCellStyles(dateFlags: formatIDs.map { id in
            formats[id].map(XLSXNumberFormat.isDateFormat) ?? XLSXNumberFormat.isBuiltInDate(id)
        })
    }

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if path.isEmpty {
            try checkMainRoot(element, "styleSheet")
        } else {
            guard isMain(element) else { return false }
            switch (path.last, element.name) {
            case ("styleSheet", "numFmts"):
                break
            case ("numFmts", "numFmt"):
                guard let id = attributes["numFmtId"].flatMap({ digits($0) }), let code = attributes["formatCode"] else { throw .malformedPart }
                guard formats.updateValue(code, forKey: id) == nil else { throw .malformedPart }
            case ("styleSheet", "cellXfs"):
                guard !sawCellFormats else { throw .malformedPart }
                sawCellFormats = true
            case ("cellXfs", "xf"):
                guard let id = attributes["numFmtId"].map({ digits($0) }) ?? 0 else { throw .malformedPart }
                formatIDs.append(id)
            default:
                return false
            }
        }
        path.append(element.name)
        return true
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) { path.removeLast() }
    func characters(_ string: String) throws(XLSXWorkbookFailure) {}
}

/// 숫자 서식이 날짜·시간인가(6-4)
enum XLSXNumberFormat {

    /// 내장 번호(정의 없이 번호만 쓰는 서식) — PDR 14~22·45~47 + **한국어·동아시아 로캘 내장 날짜 27~36·50~58**과 태국어 71~81 `[판단]`
    /// (한국어 엑셀은 `yyyy"년" m"월" d"일"` 등을 이 번호로 정의 없이 쓴다 — 놓치면 날짜 일련번호가 숫자로 들어온다)
    static func isBuiltInDate(_ id: Int) -> Bool {
        switch id {
        case 14...22, 27...36, 45...47, 50...58, 71...81: true
        default: false
        }
    }

    /// 서식 문자열 판정 — `"…"` 따옴표 구간·`\x` 이스케이프·`_x`(폭 채움)·`*x`(반복)·`[…]`(색·조건·로캘)를 **먼저 뺀 뒤**
    /// `y m d h s e g`·`AM/PM`·`A/P` 토큰을 본다(대소문자 무시). `General`과 지수 표기 `E+`·`E-`는 토큰이 아니다.
    /// `[h]`·`[mm]`·`[ss]` 경과 시간은 날짜다. 따옴표 리터럴 `m"월" d"일"`(Mac)·`mm"월"\ dd"일"`(윈도우)와
    /// **따옴표 없는 한글 리터럴** `m월 d일`(구글)이 모두 날짜로 판정된다(P-10)
    static func isDateFormat(_ code: String) -> Bool {
        let scalars = Array(code.unicodeScalars)
        var kept: [UInt8] = []
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            switch scalar {
            case "\"":
                index += 1
                while index < scalars.count, scalars[index] != "\"" { index += 1 }
                index += 1
            case "\\", "_", "*":
                index += 2
            case "[":
                var close = index + 1
                while close < scalars.count, scalars[close] != "]" { close += 1 }
                let content = scalars[(index + 1)..<min(close, scalars.count)]
                if !content.isEmpty, content.allSatisfy({ "hHmMsS".unicodeScalars.contains($0) }) { return true }
                index = close + 1
            default:
                // 한글 등 ASCII 밖 글자는 리터럴이다(토큰이 아니다)
                if scalar.isASCII { kept.append(UInt8(ascii: scalar.properties.lowercaseMapping.unicodeScalars.first ?? scalar)) }
                index += 1
            }
        }
        var text = String(decoding: kept, as: UTF8.self).replacingOccurrences(of: "general", with: "")
        if text.contains("a/p") { return true }
        text = text.replacingOccurrences(of: "e+", with: "").replacingOccurrences(of: "e-", with: "")
        return text.contains { "ymdhseg".contains($0) }
    }
}

// MARK: - 시트

/// `<worksheet>` → `RawTable`. 읽는 것: `<sheetData><row r hidden><c r t s><f>/<v>/<is>`, `<mergeCells><mergeCell ref>`,
/// `<cols><col min max hidden>`. `<dimension>`은 믿지 않고(읽지도 않는다) 실제 `<row>`·`<c>`를 센다(6-5).
/// `r`이 없으면 직전 다음 자리, 있으면 오름차순이어야 하고 셀의 행은 그 행과 같아야 한다(거꾸로·중복은 어느 값이 이길지 모호 — 거부)
final class WorksheetHandler: XLSXXMLHandler {

    static let maxRow = 1_048_576
    static let maxColumn = 16_384

    private struct CellBuilder {
        let column: Int
        let type: String?
        let isDate: Bool
        var hasFormula = false
        var value: String?
        var inline: String?
        var piece: String?
    }

    private let limits: XLSXWorkbookLimits
    private let sharedStrings: [String]
    private let styles: XLSXCellStyles
    private var path: [String] = []
    private var sawSheetData = false
    private var scannedRows = 0
    private var cellCount = 0
    private var rowNumber = 0
    private var rowHidden = false
    private var lastColumn = -1
    private var cells: [RawCell] = []
    private var cell: CellBuilder?
    private var rows: [RawRow] = []
    private var hiddenColumns = Set<Int>()
    /// 병합 범위의 행 구간
    private var merges: [ClosedRange<Int>] = []

    init(limits: XLSXWorkbookLimits, sharedStrings: [String], styles: XLSXCellStyles) {
        self.limits = limits
        self.sharedStrings = sharedStrings
        self.styles = styles
    }

    /// 병합 표시 — 시작 행으로 정렬한 구간을 행 순서대로 한 번 훑는다(겹친 큰 범위가 많아도 행 × 범위로 커지지 않는다)
    func result() -> RawTable {
        let sorted = merges.sorted { $0.lowerBound < $1.lowerBound }
        var next = 0
        var reach = 0
        for index in rows.indices {
            let number = rows[index].number
            while next < sorted.count, sorted[next].lowerBound <= number {
                reach = max(reach, sorted[next].upperBound)
                next += 1
            }
            rows[index].isMerged = reach >= number
        }
        return RawTable(rows: rows, hiddenColumns: hiddenColumns.sorted())
    }

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if path.isEmpty {
            try checkMainRoot(element, "worksheet")
        } else {
            guard isMain(element) else { return false }
            switch (path.last, element.name) {
            case ("worksheet", "sheetData"):
                guard !sawSheetData else { throw .malformedPart }
                sawSheetData = true
            case ("sheetData", "row"):
                try startRow(attributes)
            case ("row", "c"):
                try startCell(attributes)
            case ("c", "v"):
                guard cell?.value == nil else { throw .malformedPart }
                cell?.value = ""
            case ("c", "f"):
                // 수식 글은 읽지 않는다 — 있다는 사실만
                cell?.hasFormula = true
                return false
            case ("c", "is"):
                cell?.inline = ""
            case ("is", "t"), ("r", "t"):
                cell?.piece = ""
            case ("is", "r"):
                break
            case ("worksheet", "cols"), ("worksheet", "mergeCells"):
                break
            case ("cols", "col"):
                try readColumn(attributes)
            case ("mergeCells", "mergeCell"):
                try readMerge(attributes["ref"])
            default:
                return false
            }
        }
        path.append(element.name)
        return true
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) {
        switch path.removeLast() {
        case "v":
            guard (cell?.value?.utf8.count ?? 0) <= limits.textBytes else { throw .textTooLong }
        case "t":
            let piece = XLSXText.decodeEscapes(cell?.piece ?? "")
            cell?.inline?.append(piece)
            cell?.piece = nil
        case "c":
            if let built = cell { place(try finish(built), at: built.column) }
            cell = nil
        case "row":
            if !cells.isEmpty { rows.append(RawRow(number: rowNumber, cells: cells, isHidden: rowHidden)) }
        default:
            break
        }
    }

    func characters(_ string: String) throws(XLSXWorkbookFailure) {
        guard let last = path.last else { return }
        if last == "v" {
            cell?.value?.append(string)
        } else if last == "t" {
            cell?.piece?.append(string)
        }
    }

    private func startRow(_ attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) {
        scannedRows += 1
        guard scannedRows <= limits.scannedRows else { throw .tooManyRows }
        if let text = attributes["r"] {
            guard let number = digits(text, maxLength: 7), number > rowNumber, number <= Self.maxRow else { throw .invalidCellReference }
            rowNumber = number
        } else {
            rowNumber += 1
            guard rowNumber <= Self.maxRow else { throw .invalidCellReference }
        }
        rowHidden = try boolean(attributes["hidden"])
        lastColumn = -1
        cells = []
    }

    private func startCell(_ attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) {
        cellCount += 1
        guard cellCount <= limits.cells else { throw .tooManyCells }
        let column: Int
        if let reference = attributes["r"] {
            guard let parsed = Self.cellReference(reference), parsed.row == rowNumber, parsed.column > lastColumn else {
                throw .invalidCellReference
            }
            column = parsed.column
        } else {
            column = lastColumn + 1
            guard column < Self.maxColumn else { throw .invalidCellReference }
        }
        lastColumn = column
        let type = attributes["t"]
        guard [nil, "n", "s", "str", "inlineStr", "b", "e", "d"].contains(type) else { throw .unknownCellType }
        cell = CellBuilder(column: column, type: type, isDate: try styles.isDate(styleIndex: attributes["s"]))
    }

    /// 6-4 셀 종류 — 수식이 먼저(타입과 상관없이), `t="str"`(수식 문자열)도 수식
    private func finish(_ built: CellBuilder) throws(XLSXWorkbookFailure) -> RawCell {
        if built.hasFormula { return .unsupported(.formula) }
        let value = built.value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch built.type {
        case nil, "n":
            guard !value.isEmpty else { return .blank }
            return built.isDate ? .unsupported(.date) : .number(value)
        case "s":
            guard !value.isEmpty else { return .blank }
            guard let index = digits(value), index < sharedStrings.count else { throw .invalidSharedStringIndex }
            let text = sharedStrings[index]
            return text.isEmpty ? .blank : .text(text)
        case "inlineStr":
            let text = XLSXText.normalizeNewlines(built.inline ?? "")
            guard text.utf8.count <= limits.textBytes else { throw .textTooLong }
            return text.isEmpty ? .blank : .text(text)
        case "str":
            return built.value == nil ? .blank : .unsupported(.formula)
        case "b":
            return value.isEmpty ? .blank : .unsupported(.boolean)
        case "e":
            return value.isEmpty ? .blank : .unsupported(.error)
        default:
            return value.isEmpty ? .blank : .unsupported(.date)
        }
    }

    /// 빈 셀은 두지 않는다(끝 빈 칸이 생기지 않는다). 열 상한 밖은 마지막 칸으로 접고, 그 칸이 이미 차 있으면 먼저 온 것이 남는다
    private func place(_ value: RawCell, at column: Int) {
        guard value != .blank else { return }
        let slot = min(column, RawTable.columnLimit - 1)
        if slot >= cells.count {
            cells.append(contentsOf: repeatElement(.blank, count: slot - cells.count))
            cells.append(value)
        } else if cells[slot] == .blank {
            cells[slot] = value
        }
    }

    private func readColumn(_ attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) {
        guard let low = attributes["min"].flatMap({ digits($0) }), let high = attributes["max"].flatMap({ digits($0) }),
              1 <= low, low <= high, high <= Self.maxColumn else { throw .malformedPart }
        // 너비(`width`·`customWidth` — 열 너비 자동 맞춤)는 보지 않는다
        guard try boolean(attributes["hidden"]), low <= RawTable.columnLimit else { return }
        for column in low...min(high, RawTable.columnLimit) { hiddenColumns.insert(column - 1) }
    }

    private func readMerge(_ reference: String?) throws(XLSXWorkbookFailure) {
        let corners = (reference ?? "").split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(corners.count) else { throw .invalidMergeRange }
        var bounds: [Int] = []
        for corner in corners {
            guard let parsed = Self.cellReference(String(corner)) else { throw .invalidMergeRange }
            bounds.append(parsed.row)
        }
        merges.append(bounds.min()!...bounds.max()!)
    }

    /// `A1`~`XFD1048576` — 대문자 열 1~3자 + 앞자리 0 없는 행. 0부터 센 열과 1부터 센 행
    static func cellReference(_ text: String) -> (column: Int, row: Int)? {
        let bytes = Array(text.utf8)
        guard bytes.count <= 10 else { return nil }
        var index = 0
        var column = 0
        while index < bytes.count, (0x41...0x5A).contains(bytes[index]) {
            column = column * 26 + Int(bytes[index] - 0x40)
            index += 1
        }
        guard (1...3).contains(index), column <= maxColumn, index < bytes.count, bytes[index] != 0x30,
              let row = digits(String(decoding: bytes[index...], as: UTF8.self), maxLength: 7), row <= maxRow else { return nil }
        return (column - 1, row)
    }
}
