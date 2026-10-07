import Foundation
import Testing
import TadakDomain
import UniformTypeIdentifiers
@testable import PackImport

// 외부 채움글 1-e ③ — xlsx `RawTable` → CSV와 **같은** 판정 경로(PDR `external-snippet-packs.md` 6-1·6-4, AC-32) ·
// 6-4 건너뜀 사유 5종과 우선순위(수식 → 날짜 서식 → 불리언·오류 → 숫자(번호 열 밖, R19) → 병합) · 병합 × 머리글/정보 줄 = 전체 거부 ·
// 원본 판별(ZIP·OLE2 매직 — 인코딩·구분자 단계를 건너뛴다) · 시트 고르기(AC-36) · 판이 xlsx를 받는지(AC-35) · 위치·실패에 내용 없음(AC-34).
// 합성 워크북은 ②의 `XLSXFixture`로 짓는다(외부 도구 0).

private typealias F = XLSXFixture

// MARK: - 시험 표

/// 시험 칸 — xlsx 셀 종류 그대로(6-1). 빈 글은 셀을 두지 않는다
enum WorkbookCell: Sendable {
    case text(String)
    /// `<v>` 글자 그대로(`323`·`323.0`)
    case number(String)
    /// `<f>` + 캐시 값
    case formula
    /// 날짜 서식(내장 14)의 숫자
    case date
    case boolean
    case error
}

struct WorkbookRow: Sendable {
    var cells: [WorkbookCell?]
    var hidden = false

    init(_ cells: [WorkbookCell?], hidden: Bool = false) {
        self.cells = cells
        self.hidden = hidden
    }

    /// 글 칸만(빈 글 = 빈 칸)
    static func text(_ texts: [String], hidden: Bool = false) -> WorkbookRow {
        WorkbookRow(texts.map { .text($0) }, hidden: hidden)
    }
}

enum WorkbookBuilder {

    /// 열 번호(0부터) → `A`·`B`·…·`Z`·`AA`
    static func columnName(_ index: Int) -> String {
        var remaining = index + 1
        var name = ""
        while remaining > 0 {
            let offset = (remaining - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + offset))) + name
            remaining = (remaining - 1) / 26
        }
        return name
    }

    static func cellXML(_ cell: WorkbookCell, reference: String) -> String? {
        switch cell {
        case .text(let text):
            guard !text.isEmpty else { return nil }
            return #"<c r="\#(reference)" t="inlineStr"><is><t xml:space="preserve">\#(F.escape(text))</t></is></c>"#
        case .number(let literal): return #"<c r="\#(reference)"><v>\#(literal)</v></c>"#
        case .formula: return #"<c r="\#(reference)"><f>1+2</f><v>3</v></c>"#
        case .date: return #"<c r="\#(reference)" s="1"><v>46302</v></c>"#
        case .boolean: return #"<c r="\#(reference)" t="b"><v>1</v></c>"#
        case .error: return #"<c r="\#(reference)" t="e"><v>#N/A</v></c>"#
        }
    }

    /// `<sheetData>` 안쪽 — 행 번호는 표의 자리(1부터). 칸이 하나도 없는 행은 쓰지 않는다(엑셀처럼 빈 행이 없다)
    static func rowsXML(_ rows: [WorkbookRow]) -> String {
        rows.enumerated().map { index, row in
            let number = index + 1
            let cells = row.cells.enumerated().compactMap { column, cell in
                cell.flatMap { cellXML($0, reference: "\(columnName(column))\(number)") }
            }
            guard !cells.isEmpty else { return "" }
            return #"<row r="\#(number)"\#(row.hidden ? #" hidden="1""# : "")>"# + cells.joined() + "</row>"
        }.joined()
    }

    static func sheet(_ name: String, _ rows: [WorkbookRow], merges: [String] = [], hiddenColumns: [Int] = [],
                      state: String? = nil, index: Int = 1) -> XLSXFixture.Sheet {
        let columns = hiddenColumns.isEmpty ? "" : "<cols>" + hiddenColumns.map { #"<col min="\#($0 + 1)" max="\#($0 + 1)" hidden="1"/>"# }.joined() + "</cols>"
        let mergeCells = merges.isEmpty ? "" : #"<mergeCells count="\#(merges.count)">"# + merges.map { #"<mergeCell ref="\#($0)"/>"# }.joined() + "</mergeCells>"
        return F.sheet(name, rows: rowsXML(rows), state: state, index: index, before: columns, after: mergeCells)
    }

    /// 시트 여럿 — 날짜 서식(내장 14)을 스타일 색인 1에 둔다
    static func workbook(_ sheets: [XLSXFixture.Sheet]) -> Data {
        var fixture = XLSXFixture(sheets: sheets)
        fixture.styles = F.stylesXML(xfs: [0, 14])
        return fixture.build()
    }

    static func workbook(_ rows: [WorkbookRow], merges: [String] = [], hiddenColumns: [Int] = [], name: String = "문구") -> Data {
        workbook([sheet(name, rows, merges: merges, hiddenColumns: hiddenColumns)])
    }

    /// 글 칸 표 → 시트 하나짜리 xlsx
    static func workbook(grid: [[String]], name: String = "문구") -> Data {
        workbook(grid.map { WorkbookRow.text($0) }, name: name)
    }

    /// 같은 표를 **스프레드시트가 CSV로 저장한 꼴** — 모든 행을 표 폭까지 빈 칸으로 채우고(엑셀·구글 실측, 5-3), 쉼표·따옴표·줄바꿈이 든 칸만 따옴표.
    /// 빈 행은 `,,,`(5-4 명확화 ②)
    static func csv(_ grid: [[String]]) -> String {
        let width = grid.map(\.count).max() ?? 0
        return grid.map { row in
            (row + Array(repeating: "", count: width - row.count)).map { cell in
                // 스칼라로 본다 — `"\r\n"`은 글자(Character) 하나라 `Character` 비교로는 홀로 선 LF를 놓친다
                cell.unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) })
                    ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
            }.joined(separator: ",")
        }.joined(separator: "\r\n")
    }
}

enum WorkbookHelper {
    static func draft(_ data: Data, sheet: Int? = nil) throws -> PackDraft {
        switch try PackImporter.readWorkbook(data, sheet: sheet) {
        case .draft(let draft): return draft
        case .chooseSheet(let sheets):
            Issue.record("시트 고르기가 나왔다: \(sheets.count)개")
            throw PackImportFailure.headerNotRecognized
        }
    }

    static func sheets(_ data: Data) throws -> [PackSheetSummary] {
        switch try PackImporter.readWorkbook(data, sheet: nil) {
        case .chooseSheet(let sheets): return sheets
        case .draft:
            Issue.record("시트 고르기 없이 바로 초안이 나왔다")
            return []
        }
    }

    static func failure(_ data: Data, sheet: Int? = nil) -> PackImportFailure? {
        do throws(PackImportFailure) {
            _ = try PackImporter.readWorkbook(data, sheet: sheet)
            return nil
        } catch {
            return error
        }
    }

    static func reasons(_ draft: PackDraft) -> [SkipReason] { draft.skipped.map(\.reason) }
}

// MARK: - AC-32 비교 값

/// 두 경로가 내는 판정 — 위치는 **번호만**(CSV 논리 레코드 번호 = 시트 행 번호인 표만 쓴다), 원본 쪽 정보(인코딩·구분자·시트)는 뺀다
struct PackVerdict: Equatable {
    var mode: ExternalPack.Mode
    var meta: PackMetaPrefill
    var entries: [SnippetEntry]
    var items: [PackTemplateItem]
    var skipped: [String]
    var dataRecordCount: Int
    var acceptedRecordCount: Int
    var duplicateCount: Int
    var ignoredColumnCount: Int
    var sanitizedCharacterCount: Int

    init(_ draft: PackDraft) {
        mode = draft.mode
        meta = draft.meta
        entries = draft.entries
        items = draft.items
        skipped = draft.skipped.map { "\($0.record):\($0.reason)" }
        dataRecordCount = draft.dataRecordCount
        acceptedRecordCount = draft.acceptedRecordCount
        duplicateCount = draft.duplicateCount
        ignoredColumnCount = draft.ignoredColumnCount
        sanitizedCharacterCount = draft.sanitizedCharacterCount
    }
}

enum PackVerdictResult: Equatable {
    case verdict(PackVerdict)
    case failure(PackImportFailure)
    case chooser

    static func csv(_ grid: [[String]]) -> PackVerdictResult {
        do throws(PackImportFailure) {
            switch try PackImporter.read(text: WorkbookBuilder.csv(grid)) {
            case .draft(let draft): return .verdict(PackVerdict(draft))
            case .chooseDelimiter: return .chooser
            }
        } catch {
            return .failure(error)
        }
    }

    static func xlsx(_ data: Data) -> PackVerdictResult {
        do throws(PackImportFailure) {
            switch try PackImporter.readWorkbook(data, sheet: nil) {
            case .draft(let draft): return .verdict(PackVerdict(draft))
            case .chooseSheet: return .chooser
            }
        } catch {
            return .failure(error)
        }
    }
}

/// AC-32 — 글 칸만 든 같은 표. CSV는 스프레드시트가 저장한 꼴(행을 표 폭까지 채움)이다
struct EquivalenceCase: Sendable, CustomTestStringConvertible {
    let id: String
    let grid: [[String]]
    var testDescription: String { id }
}

private let longTitle = String(repeating: "가", count: PackLimits.title.characters + 1)
private let longTrigger = String(repeating: "말", count: PackLimits.trigger.characters + 1)
private let longBody = String(repeating: "본", count: PackLimits.body.characters + 1)
private let manyTriggers = (1...(PackLimits.triggersPerEntry + 1)).map { "단축\($0)" }.joined(separator: ",")

let equivalenceCases: [EquivalenceCase] = [
    EquivalenceCase(id: "번호형 — 정보 줄 셋·모르는 열·같은 번호(뒤가 이김)·앞자리 0·번호 형식·범위·빈 본문·긴 제목·긴 본문", grid: [
        ["#이름", "사자성어 예시 팩"], ["#틀", "사자성어 {n}번", "성어 {n}번"], ["#출처", "자체 작성"],
        ["번호", "제목", "본문", "비고"],
        ["1", "일석이조", "한 가지 일로\n두 가지 이익", "메모"],
        ["007", "칠", "앞자리 0은 값으로", ""],
        ["3.0", "삼", "점 영", ""],
        ["1", "덮어씀", "뒤가 이긴다", ""],
        ["12a", "형식", "번호 형식 아님", ""],
        ["0", "범위", "번호 범위 밖", ""],
        ["", "번호 없음", "본문", ""],
        ["5", "빈 본문", " ", ""],
        ["6", longTitle, "제목이 길다", ""],
        ["8", "긴 본문", longBody, ""],
    ]),
    EquivalenceCase(id: "문구형 — 여러 단축어(쉼표·줄바꿈)·같은 단축어 뒤가 이김·빈 단축어·단축어 11개·긴 단축어·제목 없음", grid: [
        ["#이름", "업무 상용구"],
        ["단축어", "제목", "본문"],
        ["회의시작,회의 시작", "회의 시작 인사", "안녕하세요, 회의를 시작하겠습니다."],
        ["일정\n조율", "", "일정 조율 문의"],
        ["회의시작", "다시", "뒤가 가져간다"],
        ["", "빈 단축어", "본문"],
        [manyTriggers, "많음", "본문"],
        [longTrigger, "긺", "본문"],
    ]),
    EquivalenceCase(id: "빈 행(헤더 앞·사이)·머리글보다 넓은 행·눈에 안 보이는 글자 정리", grid: [
        [], ["번호", "본문"], ["1", "가\u{200B}나"], [], ["2", "다", "넘침"], ["3", "라"],
    ]),
    EquivalenceCase(id: "정보 줄이 머리글 뒤 — 위치 오류", grid: [["번호", "본문"], ["1", "가"], ["#이름", "뒤"]]),
    EquivalenceCase(id: "같은 정보 줄 두 번", grid: [["#이름", "가"], ["#이름", "나"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "#출처와 옛 #권리", grid: [["#출처", "가"], ["#권리", "나"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "모르는 정보 줄", grid: [["#메모", "가"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "#escape", grid: [["#escape", "가"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "정보 줄 값 개수", grid: [["#이름", "가", "나"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "정보 줄 칸 상한(13칸 넘침도 같은 결과)", grid: [["#틀"] + (1...14).map { "틀\($0) {n}" }, ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "머리글을 찾지 못함(제목 줄)", grid: [["예시 모음"], ["번호", "본문"], ["1", "가"]]),
    EquivalenceCase(id: "번호+단축어", grid: [["번호", "단축어", "본문"], ["1", "a", "가"]]),
    EquivalenceCase(id: "같은 열 이름 두 번", grid: [["번호", "본문", "본문"], ["1", "가", "나"]]),
    EquivalenceCase(id: "같은 뜻의 열 둘", grid: [["번호", "본문", "body"], ["1", "가", "나"]]),
    EquivalenceCase(id: "필수 열 없음", grid: [["번호", "제목"], ["1", "가"]]),
    EquivalenceCase(id: "칸이 너무 많음", grid: [["번호", "제목", "본문", "a", "b", "c", "d", "e", "f"], ["1", "가", "나"]]),
    EquivalenceCase(id: "문구형에 #틀", grid: [["#틀", "예 {n}"], ["단축어", "본문"], ["a", "가"]]),
    EquivalenceCase(id: "유효 0", grid: [["번호", "본문"], ["0", "가"], ["", "나"]]),
]

// MARK: - AC-32

@Suite("외부 채움글 1-e ③ — AC-32 xlsx와 CSV는 같은 판정 경로")
struct PackWorkbookEquivalenceTests {

    @Test("★ 같은 표 — xlsx로 읽은 것과 스프레드시트가 저장한 CSV로 읽은 것이 같은 판정(항목·건너뜀 번호와 사유·정보 줄·중복·모르는 열·정리 건수·구조 오류)",
          arguments: equivalenceCases)
    func sameVerdict(_ testCase: EquivalenceCase) {
        let csv = PackVerdictResult.csv(testCase.grid)
        let xlsx = PackVerdictResult.xlsx(WorkbookBuilder.workbook(grid: testCase.grid))
        #expect(csv != .chooser)
        #expect(xlsx == csv)
    }

    @Test("시험 표가 뜻대로다 — 판정이 실제로 갈린다(건너뜀·중복·실패가 다 나온다)")
    func casesExercisePaths() throws {
        guard case .verdict(let numbered) = PackVerdictResult.csv(equivalenceCases[0].grid) else { Issue.record("번호형 초안 없음"); return }
        #expect(Set(numbered.skipped.map { $0.split(separator: ":")[1] }) == ["invalidNumber", "numberOutOfRange", "missingNumber", "emptyBody",
                                                                              "titleTooLong", "bodyTooLong"])
        #expect(numbered.duplicateCount == 1 && numbered.ignoredColumnCount == 1 && numbered.items.map(\.n) == [1, 3, 7])
        #expect(numbered.meta.templateSpecs == ["사자성어 {n}번", "성어 {n}번"])
        guard case .verdict(let phrases) = PackVerdictResult.csv(equivalenceCases[1].grid) else { Issue.record("문구형 초안 없음"); return }
        // 「회의시작,회의 시작」은 정규화하면 같은 단축어 하나 — 뒤 행 「회의시작」이 가져가 앞 항목은 없어진다(5-4 ⑦)
        #expect(phrases.entries.map(\.triggers) == [["일정", "조율"], ["회의시작"]] && phrases.duplicateCount == 1)
        guard case .verdict(let blanks) = PackVerdictResult.csv(equivalenceCases[2].grid) else { Issue.record("빈 행 초안 없음"); return }
        #expect(blanks.skipped == ["5:columnCount"] && blanks.sanitizedCharacterCount == 1 && blanks.dataRecordCount == 3)
        let failures = equivalenceCases.dropFirst(3).map { PackVerdictResult.csv($0.grid) }
        #expect(failures.dropLast().allSatisfy { if case .failure = $0 { true } else { false } })
        #expect(failures.last.map { if case .verdict(let verdict) = $0 { verdict.acceptedRecordCount == 0 } else { false } } == true)
    }

    @Test("★ 샘플 2종 — 같은 내용의 xlsx(옛 `#권리`판)와 원본 CSV(`#출처`, UTF-8 BOM·CRLF·여러 줄 본문)가 같은 초안", arguments: ["sample-numbered", "sample-phrases"])
    func samplesMatchOriginalCSV(_ name: String) throws {
        let xlsx = try #require(Bundle.module.url(forResource: name, withExtension: "xlsx", subdirectory: "Fixtures"))
        let csv = try #require(Bundle.module.url(forResource: "\(name).original", withExtension: "csv", subdirectory: "Fixtures"))
        let fromXLSX = try WorkbookHelper.draft(Data(contentsOf: xlsx))
        let fromCSV = try ImportHelper.draft(data: Data(contentsOf: csv))
        #expect(PackVerdict(fromXLSX) == PackVerdict(fromCSV))
        #expect(fromXLSX.isImportable && fromXLSX.skipped.isEmpty)
        // 원본 쪽 정보만 다르다 — xlsx는 인코딩·칸 나누기가 없고 시트 이름이 있다
        #expect(fromXLSX.delimiter == nil && fromXLSX.delimiterCandidates.isEmpty && fromXLSX.encoding == nil && !fromXLSX.needsEncodingConfirmation)
        #expect(fromXLSX.sheetName == name && fromCSV.sheetName == nil && fromCSV.delimiter == .comma)
    }

    @Test("CSV만의 단계는 xlsx에 없다 — 구분자 시험(5-2)의 「열 수 과반 불일치」는 CSV 전체 거부, xlsx는 그 행만 건너뜀(5-4)")
    func delimiterTrialIsCSVOnly() throws {
        let grid = [["번호", "본문"], ["1", "가", "넘"], ["2", "나", "넘"], ["3", "다"]]
        #expect(PackVerdictResult.csv(grid) == .failure(.columnCountMismatch(record: 2, line: 2)))
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook(grid: grid))
        #expect(WorkbookHelper.reasons(draft) == [.columnCount, .columnCount] && draft.items.map(\.n) == [3])
    }
}

// MARK: - 6-4 사유·우선순위

private let numberedHeader = WorkbookRow.text(["번호", "제목", "본문", "비고"])

struct PriorityCase: Sendable, CustomTestStringConvertible {
    let id: String
    let row: WorkbookRow
    var merged = false
    let expected: SkipReason?
    var testDescription: String { id }
}

let priorityCases: [PriorityCase] = [
    PriorityCase(id: "수식이 날짜·불리언보다 먼저", row: WorkbookRow([.number("1"), .formula, .date, .boolean]), expected: .formula),
    PriorityCase(id: "수식이 숫자·병합보다 먼저", row: WorkbookRow([.number("1"), .text("가"), .formula, .number("9")]), merged: true, expected: .formula),
    PriorityCase(id: "날짜가 불리언·숫자보다 먼저", row: WorkbookRow([.number("1"), .number("5"), .date, .boolean]), expected: .dateFormat),
    PriorityCase(id: "불리언", row: WorkbookRow([.number("1"), .text("가"), .text("나"), .boolean]), expected: .booleanOrError),
    PriorityCase(id: "오류", row: WorkbookRow([.number("1"), .error, .text("나")]), expected: .booleanOrError),
    PriorityCase(id: "불리언·오류가 숫자보다 먼저", row: WorkbookRow([.number("1"), .number("5"), .error]), expected: .booleanOrError),
    PriorityCase(id: "숫자 — 제목", row: WorkbookRow([.number("1"), .number("2026"), .text("나")]), expected: .numberCell),
    PriorityCase(id: "숫자 — 본문", row: WorkbookRow([.number("1"), .text("가"), .number("5")]), expected: .numberCell),
    PriorityCase(id: "숫자 — 모르는 열(R19)", row: WorkbookRow([.number("1"), .text("가"), .text("나"), .number("3")]), expected: .numberCell),
    PriorityCase(id: "숫자가 병합보다 먼저", row: WorkbookRow([.number("1"), .number("5"), .text("나")]), merged: true, expected: .numberCell),
    PriorityCase(id: "병합", row: WorkbookRow([.number("1"), .text("가"), .text("나")]), merged: true, expected: .merged),
    PriorityCase(id: "6-4 사유가 열 수보다 먼저(머리글 밖 수식)", row: WorkbookRow([.number("1"), .text("가"), .text("나"), nil, .formula]), expected: .formula),
    PriorityCase(id: "6-4 사유가 번호 형식보다 먼저", row: WorkbookRow([.text("12a"), .date, .text("나")]), expected: .dateFormat),
    PriorityCase(id: "6-4 사유가 빈 본문보다 먼저", row: WorkbookRow([.number("1"), .formula]), expected: .formula),
    PriorityCase(id: "번호 열의 날짜는 날짜 서식", row: WorkbookRow([.date, .text("가"), .text("나")]), expected: .dateFormat),
    PriorityCase(id: "머리글보다 넓은 글 칸 = 열 수(xlsx)", row: WorkbookRow([.number("1"), .text("가"), .text("나"), nil, .text("넘침")]), expected: .columnCount),
    PriorityCase(id: "번호 열 숫자 323 = 받음", row: WorkbookRow([.number("323"), .text("가"), .text("나")]), expected: nil),
    PriorityCase(id: "번호 열 숫자 323.0(구글) = 받음", row: WorkbookRow([.number("323.0"), .text("가"), .text("나")]), expected: nil),
    PriorityCase(id: "번호 열 1.5 = 번호 형식", row: WorkbookRow([.number("1.5"), .text("가"), .text("나")]), expected: .invalidNumber),
    PriorityCase(id: "번호 열 -3 = 번호 형식", row: WorkbookRow([.number("-3"), .text("가"), .text("나")]), expected: .invalidNumber),
    PriorityCase(id: "번호 열 지수 = 번호 형식", row: WorkbookRow([.number("1.23456789012345E+19"), .text("가"), .text("나")]), expected: .invalidNumber),
    PriorityCase(id: "번호 열 0 = 범위", row: WorkbookRow([.number("0"), .text("가"), .text("나")]), expected: .numberOutOfRange),
    PriorityCase(id: "끝 빈 칸은 채운다 — 본문이 빈 칸이면 빈 본문(열 수 아님)", row: WorkbookRow([.number("1"), .text("가")]), expected: .emptyBody),
    PriorityCase(id: "가운데 빈 제목 = 받음", row: WorkbookRow([.number("1"), nil, .text("나")]), expected: nil),
]

@Suite("외부 채움글 1-e ③ — 6-4 건너뜀 사유·우선순위 (AC-31·AC-36)")
struct PackWorkbookSkipTests {

    @Test("★ 한 행에 여럿이면 첫 사유 — 수식 → 날짜 서식 → 불리언·오류 → 숫자(번호 열 밖) → 병합, 그다음 CSV와 같은 검사", arguments: priorityCases)
    func priority(_ testCase: PriorityCase) throws {
        let data = WorkbookBuilder.workbook([numberedHeader, testCase.row], merges: testCase.merged ? ["B2:C2"] : [])
        let draft = try WorkbookHelper.draft(data)
        #expect(WorkbookHelper.reasons(draft) == (testCase.expected.map { [$0] } ?? []))
        #expect(draft.dataRecordCount == 1)
    }

    @Test("★ 받은 값 — 번호 열 323·323.0·앞자리 0(글 007)은 같은 번호, 빈 칸은 빈 글")
    func acceptedValues() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([
            numberedHeader,
            WorkbookRow([.number("323"), .text("가"), .text("하나")]),
            WorkbookRow([.number("324.0"), nil, .text("둘")]),
            WorkbookRow([.text("007"), .text("칠"), .text("셋")]),
        ]))
        #expect(draft.items == [PackTemplateItem(n: 7, title: "칠", body: "셋"), PackTemplateItem(n: 323, title: "가", body: "하나"),
                                PackTemplateItem(n: 324, title: "", body: "둘")])
    }

    @Test("★ 문구형 — 단축어·제목 열의 숫자는 R19 건너뜀(번호 열이 없다)")
    func phrasesNumberCells() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([
            WorkbookRow.text(["단축어", "제목", "본문"]),
            WorkbookRow([.number("2026"), .text("가"), .text("나")]),
            WorkbookRow([.text("인사"), .number("1"), .text("나")]),
            WorkbookRow([.text("주소"), .text("회사"), .text("한 줄")]),
        ]))
        #expect(WorkbookHelper.reasons(draft) == [.numberCell, .numberCell])
        #expect(draft.entries.map(\.triggers) == [["주소"]])
    }

    @Test("★ 건너뛴 위치는 **시트 행 번호**(빈 행 자리 포함) — CSV는 그대로 「항목·줄」")
    func rowPositions() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([
            numberedHeader,
            WorkbookRow([.number("1"), .formula, .text("가")]),
            WorkbookRow([]),
            WorkbookRow([.number("2"), .text("가"), .date]),
        ]))
        #expect(draft.skipped == [SkippedRecord(row: 2, reason: .formula), SkippedRecord(row: 4, reason: .dateFormat)])
        #expect(draft.skipped.map(\.position) == [.row(2), .row(4)])
        let csv = try ImportHelper.draft("번호,본문\n1,\"가\n나\"\n0,다")
        #expect(csv.skipped == [SkippedRecord(record: 3, line: 4, reason: .numberOutOfRange)])
        #expect(csv.skipped[0].position == .record(3, line: 4))
    }

    @Test("★ 유효 0인 xlsx — 받을 행 없음(5-5), 건너뛴 위치는 행 번호뿐")
    func noValidRows() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([numberedHeader, WorkbookRow([.number("1"), .formula, .text("가")])]))
        #expect(!draft.isImportable && draft.skipped == [SkippedRecord(row: 2, reason: .formula)])
    }
}

// MARK: - 머리글·정보 줄

@Suite("외부 채움글 1-e ③ — 병합·글 아닌 칸 × 머리글/정보 줄 = 전체 거부 (6-4)")
struct PackWorkbookHeaderTests {

    @Test("★ 병합이 머리글·정보 줄과 겹치면 전체 거부 — 머리글 행·정보 줄·머리글과 데이터에 걸친 병합", arguments: [
        ("A2:B2", 2), ("A1:B1", 1), ("C2:C3", 2), ("B1:B2", 1),
    ])
    func mergedHeaderOrMeta(_ range: String, row: Int) {
        let data = WorkbookBuilder.workbook([WorkbookRow.text(["#이름", "예시"]), WorkbookRow.text(["번호", "제목", "본문"]),
                                             WorkbookRow.text(["1", "가", "나"])], merges: [range])
        #expect(WorkbookHelper.failure(data) == .mergedHeaderOrMeta(record: row, line: row))
    }

    @Test("머리글 위 병합 제목 줄 — 머리글이 아니라서 CSV와 같은 「머리글을 찾지 못했어요」(병합보다 먼저)")
    func mergedTitleAboveHeader() {
        let data = WorkbookBuilder.workbook([WorkbookRow.text(["예시 모음"]), WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])],
                                            merges: ["A1:B1"])
        #expect(WorkbookHelper.failure(data) == .headerNotRecognized)
    }

    @Test("데이터만 걸친 병합은 그 행들만 건너뜀 — 선두·비선두 모두")
    func mergedDataRows() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([
            WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"]), WorkbookRow.text(["2", "나"]), WorkbookRow.text(["3", "다"]),
        ], merges: ["B3:B4"]))
        #expect(draft.skipped == [SkippedRecord(row: 3, reason: .merged), SkippedRecord(row: 4, reason: .merged)])
        #expect(draft.items.map(\.n) == [1])
    }

    @Test("★ 머리글·정보 줄의 수식·날짜·불리언·오류 칸 — 원문을 알 수 없어 전체 거부 [판단]", arguments: [
        WorkbookRow([.text("#이름"), .formula]),
        WorkbookRow([.text("#틀"), .text("예 {n}"), .date]),
        WorkbookRow([.text("#출처"), .boolean]),
        WorkbookRow([.text("#이름"), .text("가"), nil, .error]),
    ])
    func nonTextMeta(_ meta: WorkbookRow) {
        let data = WorkbookBuilder.workbook([meta, WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])])
        #expect(WorkbookHelper.failure(data) == .nonTextHeaderCell(record: 1, line: 1))
    }

    @Test("★ 머리글 행의 글 아닌 칸 — 전체 거부(머리글 밖 칸이어도)", arguments: [
        WorkbookRow([.text("번호"), .formula, .text("본문")]),
        WorkbookRow([.text("번호"), .text("본문"), nil, .date]),
        WorkbookRow([.boolean, .text("번호"), .text("본문")]),
    ])
    func nonTextHeader(_ header: WorkbookRow) {
        let data = WorkbookBuilder.workbook([header, WorkbookRow.text(["1", "가"])])
        #expect(WorkbookHelper.failure(data) == .nonTextHeaderCell(record: 1, line: 1))
    }

    @Test("★ 머리글·정보 줄의 **숫자** 칸은 CSV처럼 글자 그대로 — `#이름 2026`·모르는 열 이름 `2026`")
    func numberCellsInHeaderAndMeta() throws {
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([
            WorkbookRow([.text("#이름"), .number("2026")]),
            WorkbookRow([.text("번호"), .text("본문"), .number("2026")]),
            WorkbookRow([.number("1"), .text("가")]),
        ]))
        #expect(draft.meta.name == "2026" && draft.ignoredColumnCount == 1 && draft.items.map(\.n) == [1])
        #expect(PackVerdict(draft) == PackVerdict(try ImportHelper.draft("#이름,2026\n번호,본문,2026\n1,가,")))
    }
}

// MARK: - 숨김 · 시트 이름

@Suite("외부 채움글 1-e ③ — 숨김 행·열(「숨김 N」) · 시트 이름은 팩 이름 기본값에만")
struct PackWorkbookSheetInfoTests {

    @Test("★ 숨긴 행 — 받은 것만 센다(건너뛴 숨김 행·머리글 위 숨김은 세지 않는다) · 숨긴 열 — 가져오는 열만 센다")
    func hiddenCounts() throws {
        let data = WorkbookBuilder.workbook([
            WorkbookRow.text(["#이름", "예시"], hidden: true),
            WorkbookRow.text(["번호", "제목", "본문", "비고"]),
            WorkbookRow.text(["1", "가", "나", "메모"], hidden: true),
            WorkbookRow([.number("2"), .formula, .text("다")], hidden: true),
            WorkbookRow.text(["3", "라", "마"], hidden: true),
            WorkbookRow.text(["4", "바", "사"]),
            WorkbookRow.text(["5", "빈 본문"], hidden: true),
            WorkbookRow.text(["0", "범위", "밖"], hidden: true),
        ], hiddenColumns: [1, 3, 6])
        let draft = try WorkbookHelper.draft(data)
        #expect(WorkbookHelper.reasons(draft) == [.formula, .emptyBody, .numberOutOfRange])
        #expect(draft.hiddenRowCount == 2, "본문·번호 검사로 건너뛴 숨김 행도 세지 않는다")
        #expect(draft.hiddenColumnCount == 1, "제목(B)만 — 비고(D)는 모르는 열, G는 머리글 밖")
        let csv = try ImportHelper.draft("번호,본문\n1,가")
        #expect(csv.hiddenRowCount == 0 && csv.hiddenColumnCount == 0)
    }

    @Test("★ 팩 이름 기본값 — 시트 이름(앞뒤 공백 뗌·문자 정리), `#이름`이 있으면 그것, `Sheet1`·`시트1`·이름 상한 초과면 빈칸", arguments: [
        ("사자성어", nil as String?, "사자성어"),
        ("  업무 상용구 ", nil, "업무 상용구"),
        ("인사\u{200B}말", nil, "인사말"),
        ("Sheet1", nil, ""),
        ("시트 2", nil, ""),
        ("사자성어", "파일 이름", "파일 이름"),
        (String(repeating: "가", count: PackLimits.name.characters + 1), nil, ""),
    ])
    func packNameDefault(_ sheetName: String, metaName: String?, expected: String) throws {
        var rows = [WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])]
        if let metaName { rows.insert(WorkbookRow.text(["#이름", metaName]), at: 0) }
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook(rows, name: sheetName))
        #expect(draft.sheetName == PackTextSanitizer.sanitize(sheetName).text, "화면에 그릴 이름은 문자 정리 뒤(S7)")
        #expect(PackImportForm(draft: draft).name == expected)
        #expect(draft.meta.name == metaName, "시트 이름은 정보 줄 값이 아니다 — 폼의 「파일에서」 표시를 받지 않는다")
    }

    @Test("CSV 초안은 시트 이름이 없다 — 이름 칸은 지금처럼 `#이름`만")
    func csvHasNoSheetName() throws {
        let draft = try ImportHelper.draft("번호,본문\n1,가")
        #expect(draft.sheetName == nil && PackImportForm(draft: draft).name == "")
    }
}

// MARK: - 원본 판별 · 실패 코드

@Suite("외부 채움글 1-e ③ — 원본 판별(ZIP·OLE2 매직)과 실패 코드")
struct PackWorkbookSourceTests {

    @Test("★ xlsx 원본 = ZIP 로컬 헤더·빈 ZIP·OLE2(비밀번호 엑셀·.xls) — 그 밖은 글(CSV)", arguments: [
        (Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00]), true),
        (Data([0x50, 0x4B, 0x05, 0x06] + Array(repeating: 0, count: 18)), true),
        (Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0x00]), true),
        (Data("PK,본문\n1,가".utf8), false),
        (Data("번호,본문\n1,가".utf8), false),
        (Data([0xEF, 0xBB, 0xBF, 0x50, 0x4B, 0x03, 0x04]), false),
        (Data([0xFF, 0xFE, 0x50, 0x00]), false),
        (Data([0x50, 0x4B, 0x03]), false),
        (Data(), false),
    ])
    func detection(_ data: Data, isWorkbook: Bool) {
        #expect(PackImporter.isWorkbook(data) == isWorkbook)
    }

    @Test("★ xlsx 실패는 내용 없는 코드 하나로 싼다 — 비밀번호(OLE2)·매크로·보이는 시트 없음·없는 시트·깨진 ZIP")
    func wrappedFailures() {
        #expect(WorkbookHelper.failure(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + Array(repeating: 0, count: 504)))
                == .workbook(.archive(.legacyOrProtectedWorkbook)))
        var macro = XLSXFixture.singleText()
        macro.workbookContentType = "application/vnd.ms-excel.sheet.macroEnabled.main+xml"
        #expect(WorkbookHelper.failure(macro.build()) == .workbook(.macroEnabled))
        let hidden = WorkbookBuilder.workbook([WorkbookBuilder.sheet("숨김", [WorkbookRow.text(["번호", "본문"])], state: "hidden")])
        #expect(WorkbookHelper.failure(hidden) == .workbook(.noVisibleSheet))
        #expect(WorkbookHelper.failure(WorkbookBuilder.workbook(grid: [["번호", "본문"], ["1", "가"]]), sheet: 1) == .workbook(.sheetNotFound))
        #expect(WorkbookHelper.failure(Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x41, count: 40)) == .workbook(.archive(.missingEndRecord)))
    }

    @Test("★ AC-34 — 거부·건너뜀 값에 시트 이름·셀 글이 없다(번호만)")
    func failuresCarryNoContent() throws {
        let marker = "표식ZQX"
        let sheets = [
            WorkbookBuilder.sheet("\(marker)시트", [WorkbookRow.text(["\(marker)제목"]), WorkbookRow.text(["번호", "본문"])], index: 1),
            WorkbookBuilder.sheet("둘째\(marker)", [WorkbookRow.text(["번호", "본문"]), WorkbookRow([.number("1"), .formula]),
                                                   WorkbookRow([.text("\(marker)번호"), .text("\(marker)본문")])], index: 2),
            WorkbookBuilder.sheet("셋째", [WorkbookRow.text(["#\(marker)", "값"]), WorkbookRow.text(["번호", "본문"])], merges: ["A1:B1"], index: 3),
        ]
        let data = WorkbookBuilder.workbook(sheets)
        var shown: [String] = []
        for index in 0..<3 {
            do throws(PackImportFailure) {
                if case .draft(let draft) = try PackImporter.readWorkbook(data, sheet: index) {
                    shown.append(String(describing: draft.skipped))
                    shown.append(String(describing: PackImportProblem.noValidRecords(draft.skipped)))
                }
            } catch {
                shown.append(String(describing: error))
                shown.append(PackImportCopy.failureMessage(.structural(error), source: .file))
            }
        }
        #expect(shown.count == 6)
        for text in shown { #expect(!text.contains(marker), "\(text)") }
    }
}

// MARK: - 시트 고르기 (AC-36)

@Suite("외부 채움글 1-e ③ — 시트 고르기 (AC-36)")
struct PackWorkbookSheetChoiceTests {

    private static let numbered = [WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"]), WorkbookRow.text(["2", "나"])]
    private static let phrases = [WorkbookRow.text(["#이름", "인사"]), WorkbookRow.text(["단축어", "본문"]), WorkbookRow.text(["주소", "한 줄"])]

    @Test("★ 보이는 시트가 둘 이상이면 고르기 — 숨김·매우 숨김 제외, `state` 생략·`visible` 명시는 표시, 워크북 순서, 대략의 행 수")
    func listsVisibleSheets() throws {
        let data = WorkbookBuilder.workbook([
            WorkbookBuilder.sheet("숨김", Self.numbered, state: "hidden", index: 1),
            WorkbookBuilder.sheet("번호", Self.numbered, index: 2),
            WorkbookBuilder.sheet("매우 숨김", Self.numbered, state: "veryHidden", index: 3),
            WorkbookBuilder.sheet("인사", Self.phrases, state: "visible", index: 4),
            WorkbookBuilder.sheet("빈 시트", [], index: 5),
        ])
        let sheets = try WorkbookHelper.sheets(data)
        #expect(sheets == [PackSheetSummary(name: "번호", rowCount: 3), PackSheetSummary(name: "인사", rowCount: 3),
                           PackSheetSummary(name: "빈 시트", rowCount: 0)])
        let second = try WorkbookHelper.draft(data, sheet: 1)
        #expect(second.mode == .phrases && second.sheetName == "인사" && second.meta.name == "인사")
        let first = try WorkbookHelper.draft(data, sheet: 0)
        #expect(first.mode == .numbered && first.sheetName == "번호" && first.items.map(\.n) == [1, 2])
    }

    @Test("★ 보이는 시트가 하나면 고르기 없이 그 시트 — 앞에 숨긴 시트가 있어도(기본 = 첫 표시 시트)")
    func singleVisibleSheet() throws {
        let data = WorkbookBuilder.workbook([
            WorkbookBuilder.sheet("숨김", Self.phrases, state: "hidden", index: 1),
            WorkbookBuilder.sheet("번호", Self.numbered, index: 2),
        ])
        let draft = try WorkbookHelper.draft(data)
        #expect(draft.sheetName == "번호" && draft.mode == .numbered)
    }

    @Test("읽지 못하는 시트도 목록에 남는다(행 수 없음) — 고르면 그때 거부. 다른 시트는 읽힌다")
    func brokenSheetInList() throws {
        var broken = WorkbookBuilder.sheet("깨짐", [], index: 2)
        broken.xml = F.worksheet(rows: #"<row r="1"><c r="a1" t="inlineStr"><is><t>x</t></is></c></row>"#)
        let data = WorkbookBuilder.workbook([WorkbookBuilder.sheet("번호", Self.numbered, index: 1), broken])
        #expect(try WorkbookHelper.sheets(data) == [PackSheetSummary(name: "번호", rowCount: 3), PackSheetSummary(name: "깨짐", rowCount: nil)])
        #expect(WorkbookHelper.failure(data, sheet: 1) == .workbook(.invalidCellReference))
        #expect(try WorkbookHelper.draft(data, sheet: 0).items.count == 2)
    }
}

// MARK: - 상태기계

private extension PackImportSession {
    var preview: PackImportPreview? {
        if case .preview(let preview) = phase { return preview }
        return nil
    }
    var choice: PackSheetChoice? {
        if case .sheet(let choice) = phase { return choice }
        return nil
    }
    var problem: PackImportProblem? {
        if case .failed(let problem) = phase { return problem }
        return nil
    }
}

@discardableResult
private func drive(_ session: inout PackImportSession, _ run: PackImportSession.Run?) -> Bool {
    guard let run else { return false }
    return session.receive(PackImportSession.compute(run, library: nil))
}

private func startedWorkbook(_ data: Data, accepts: Bool = true) -> PackImportSession {
    var session = PackImportSession(acceptsWorkbookFiles: accepts)
    drive(&session, session.start(.file(data)))
    return session
}

private let twoSheets = WorkbookBuilder.workbook([
    WorkbookBuilder.sheet("번호", [WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])], index: 1),
    WorkbookBuilder.sheet("메모", [WorkbookRow.text(["오늘 할 일"]), WorkbookRow.text(["장보기"])], index: 2),
    WorkbookBuilder.sheet("문구", [WorkbookRow.text(["단축어", "본문"]), WorkbookRow.text(["주소", "한 줄"])], index: 3),
])

@Suite("외부 채움글 1-e ③ — 가져오기 상태기계: xlsx 입력 · 시트 고르기 (AC-36)")
struct PackWorkbookSessionTests {

    @Test("★ 판이 xlsx를 받는지 — CSV 전용판은 받지 않는다(AC-35), 지금 판은 CSV 전용판 그대로")
    func acceptanceFollowsCopySet() {
        #expect(PackCopySet.selected == .csv && !PackCopySet.selected.acceptsWorkbookFiles && PackCopySet.xlsx.acceptsWorkbookFiles)
        #expect(!PackImportSession().acceptsWorkbookFiles)
        #expect(PackCopySet.$previewing.withValue(.xlsx) { PackImportSession().acceptsWorkbookFiles })
    }

    @Test("★ 파일 고르기 형식 — CSV 전용판은 CSV·TSV·글만, xlsx 중심판은 xlsx(org.openxmlformats.spreadsheetml.sheet)를 앞에 더한다")
    func pickerTypes() throws {
        let csv = PackImportFileTypes.allowed(for: .csv)
        #expect(csv == [.commaSeparatedText, .tabSeparatedText, .plainText])
        let xlsx = PackImportFileTypes.allowed(for: .xlsx)
        #expect(Array(xlsx.dropFirst()) == csv)
        let workbook = try #require(xlsx.first)
        #expect(workbook.identifier == "org.openxmlformats.spreadsheetml.sheet")
        #expect(workbook.preferredFilenameExtension == "xlsx")
        #expect(PackImportFileTypes.allowed(for: .selected) == csv)
    }

    @Test("★ 시트 하나 — 글자 확인·시트 고르기 없이 바로 미리보기, 칸 나누기 고르기 없음")
    func singleSheetGoesToPreview() throws {
        var session = startedWorkbook(WorkbookBuilder.workbook(grid: [["번호", "본문"], ["1", "가"]], name: "사자성어"))
        let preview = try #require(session.preview)
        #expect(preview.draft.sheetName == "사자성어" && !preview.offersDelimiterChoice)
        #expect(session.lastReview == nil && session.sheetChoice == nil && !session.canReviewSheet)
        // 칸 나누기는 xlsx에 없다 — 바꾸기 시도는 아무 일도 하지 않는다
        #expect(session.chooseDelimiter(.semicolon) == nil)
        session.reviewEncodingAgain()
        #expect(session.preview == preview)
    }

    @Test("★ 시트 둘 이상 — 고르기(기본 첫 표시 시트) → 고른 시트로 원본에서 다시 → 미리보기")
    func chooseSheet() throws {
        var session = startedWorkbook(twoSheets)
        let choice = try #require(session.choice)
        #expect(choice.sheets.map(\.name) == ["번호", "메모", "문구"] && choice.selected == 0)
        #expect(session.hasSource && !session.isWorking)
        session.selectSheet(2)
        #expect(session.choice?.selected == 2)
        session.selectSheet(7)
        #expect(session.choice?.selected == 2, "없는 자리는 무시")
        let run = try required(session.confirmSheet())
        #expect(run.options.sheet == 2 && run.source == .file(twoSheets) && session.isWorking)
        drive(&session, run)
        #expect(session.preview?.draft.sheetName == "문구" && session.preview?.draft.mode == .phrases)
        #expect(session.canProceed && session.canReviewSheet)
    }

    @Test("★ 미리보기에서 「시트 다시 고르기」 — 다시 읽지 않고 고르기 화면(지금 시트가 골라져 있다), 다른 시트로 바꾸면 원본에서 다시")
    func reviewSheetAgain() throws {
        var session = startedWorkbook(twoSheets)
        session.selectSheet(2)
        drive(&session, session.confirmSheet())
        session.reviewSheetAgain()
        #expect(session.choice?.selected == 2 && !session.isWorking)
        session.selectSheet(0)
        drive(&session, session.confirmSheet())
        #expect(session.preview?.draft.sheetName == "번호")
    }

    @Test("★ 고른 시트를 읽지 못하면 거부 화면이지만 원본을 지닌다 — 「다른 시트 고르기」로 돌아가 다른 시트를 고르면 미리보기")
    func failedSheetFallsBack() throws {
        var session = startedWorkbook(twoSheets)
        session.selectSheet(1)
        drive(&session, session.confirmSheet())
        #expect(session.problem == .structural(.headerNotRecognized))
        #expect(session.hasSource && session.canReviewSheet && session.delimiterFallback == nil)
        session.reviewSheetAgain()
        #expect(session.choice?.selected == 1)
        session.selectSheet(0)
        drive(&session, session.confirmSheet())
        #expect(session.preview?.draft.sheetName == "번호")
    }

    @Test("유효 0인 시트도 같은 자리에서 돌아갈 수 있다 · 시트가 하나뿐인 파일의 거부는 끝(원본을 비운다)")
    func noValidSheetFallback() throws {
        let data = WorkbookBuilder.workbook([
            WorkbookBuilder.sheet("빈 값", [WorkbookRow.text(["번호", "본문"]), WorkbookRow([.number("1"), .formula])], index: 1),
            WorkbookBuilder.sheet("번호", [WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])], index: 2),
        ])
        var session = startedWorkbook(data)
        drive(&session, session.confirmSheet())
        #expect(session.problem == .noValidRecords([SkippedRecord(row: 2, reason: .formula)]) && session.canReviewSheet)

        let single = startedWorkbook(WorkbookBuilder.workbook(grid: [["예시 모음"], ["번호", "본문"]]))
        #expect(single.problem == .structural(.headerNotRecognized))
        #expect(!single.hasSource && !single.canReviewSheet)
    }

    @Test("★ 컨테이너·XML 거부는 끝 — 원본을 비운다(비밀번호 엑셀)")
    func workbookFailureFinishes() {
        let session = startedWorkbook(Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + Array(repeating: 0, count: 504)))
        #expect(session.problem == .structural(.workbook(.archive(.legacyOrProtectedWorkbook))))
        #expect(!session.hasSource && session.lastReview == nil)
    }

    @Test("★ CSV 전용판 세션은 xlsx 바이트를 xlsx로 읽지 않는다 — 시트 고르기·엑셀 사유가 나오지 않는다(없는 기능, AC-35)")
    func csvEditionIgnoresWorkbooks() {
        for data in [twoSheets, WorkbookBuilder.workbook(grid: [["번호", "본문"], ["1", "가"]]),
                     Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + Array(repeating: 0, count: 504))] {
            let session = startedWorkbook(data, accepts: false)
            #expect(session.choice == nil && session.preview == nil)
            if case .structural(.workbook)? = session.problem { Issue.record("CSV 전용판이 엑셀 사유를 냈다") }
            if case .encoding = session.phase {} else if session.problem == nil { Issue.record("글자 확인도 거부도 아니다: \(session.phase)") }
        }
    }

    @Test("단계에 맞지 않는 시트 동작은 아무 일도 없다 · 취소하면 시트 목록도 비운다 · 일하는 중에는 받지 않는다")
    func guards() throws {
        var idle = PackImportSession(acceptsWorkbookFiles: true)
        idle.selectSheet(1)
        idle.reviewSheetAgain()
        #expect(idle.confirmSheet() == nil && idle.phase == .idle)

        var session = startedWorkbook(twoSheets)
        let run = try required(session.confirmSheet())
        #expect(session.confirmSheet() == nil, "일하는 중")
        session.selectSheet(2)
        session.reviewSheetAgain()
        drive(&session, run)
        #expect(session.preview?.draft.sheetName == "번호")
        #expect(session.confirmSheet() == nil, "미리보기에서는 고르기 화면을 거쳐야 한다")
        session.cancel()
        #expect(session.sheetChoice == nil && !session.canReviewSheet && !session.hasSource && session.options == PackImportOptions())
    }

    @Test("같은 Run이면 같은 결과(순수) — 시트 목록도")
    func computeIsPure() throws {
        var session = PackImportSession(acceptsWorkbookFiles: true)
        let run = try required(session.start(.file(twoSheets)))
        #expect(PackImportSession.compute(run, library: nil) == PackImportSession.compute(run, library: nil))
    }
}

// MARK: - 문구

@Suite("외부 채움글 1-e ③ — 문구: 6-4 사유 · 엑셀 거부(4-G) · 시트 고르기(4-D) · 「n번째 행」")
struct PackWorkbookCopyTests {

    @Test("★ 6-4 사유 5종 — 사유 + 고치는 법 한 줄(시안 4-F·PDR 6-4 R19 문구)", arguments: [
        (SkipReason.formula, "수식이에요", "「값만 붙여넣기」로 바꿔 주세요"),
        (.dateFormat, "날짜 서식이에요", "그 열 서식을 「텍스트」로 바꿔 주세요"),
        (.booleanOrError, "TRUE·FALSE나 오류 값이에요", "그 열 서식을 「텍스트」로 바꿔 주세요"),
        (.numberCell, "숫자로 저장된 칸이에요", "그 열 서식을 「텍스트」로 바꿔 주세요"),
        (.merged, "병합한 칸이 있어요", "병합을 풀어 주세요"),
    ])
    func skipReasons(_ reason: SkipReason, label: String, fix: String) {
        #expect(PackImportCopy.skipReason(reason) == label)
        #expect(PackImportCopy.skipFix(reason) == fix)
        #expect(PackImportCopy.skipFix(SkippedRecord(row: 12, reason: reason)) == fix)
    }

    @Test("★ 엑셀은 「n번째 행」, CSV는 「n번째 항목(m번째 줄)」(시안 4-F) · 머리글보다 넓은 행의 고치는 법은 엑셀 말로")
    func positions() {
        #expect(PackImportCopy.skipTitle(SkippedRecord(row: 12, reason: .formula)) == "12번째 행 — 수식이에요")
        #expect(PackImportCopy.skipTitle(SkippedRecord(record: 12, line: 40, reason: .emptyBody)) == "12번째 항목(40번째 줄) — 본문이 비어 있어요")
        #expect(PackImportCopy.skipFix(SkippedRecord(record: 12, line: 40, reason: .columnCount)) == "쉼표가 빠졌거나 더 있어요")
        #expect(PackImportCopy.skipFix(SkippedRecord(row: 12, reason: .columnCount)) == "머리글이 없는 오른쪽 칸을 비워 주세요")
        #expect(PackImportCopy.skipFix(SkippedRecord(row: 12, reason: .emptyBody)) == PackImportCopy.skipFix(.emptyBody))
    }

    @Test("★ 4-G 엑셀 사유 — 비밀번호·옛 형식 / 매크로 / 너무 큼 / 항목 많음 / 보이는 시트 없음 / 긴 글 / 그 밖은 「읽을 수 없어요」 묶음")
    func workbookFailures() {
        func message(_ failure: XLSXWorkbookFailure) -> String {
            PackImportCopy.failureMessage(.structural(.workbook(failure)), source: .file)
        }
        #expect(message(.archive(.legacyOrProtectedWorkbook))
                == "비밀번호가 걸렸거나 옛 형식(.xls)인 엑셀이에요. 비밀번호를 풀고 「Excel 통합 문서(.xlsx)」로 저장해 주세요.")
        #expect(message(.macroEnabled) == "매크로가 든 파일은 받지 않아요. 「Excel 통합 문서(.xlsx)」로 다시 저장해 주세요.")
        let tooLarge = PackImportCopy.failureMessage(.structural(.fileTooLarge), source: .file)
        for failure: XLSXWorkbookFailure in [.archive(.fileTooLarge), .archive(.partTooLarge), .archive(.totalOutputExceeded),
                                             .archive(.compressionRatioExceeded)] {
            #expect(message(failure) == tooLarge, "\(failure)")
        }
        let tooMany = PackImportCopy.failureMessage(.structural(.tooManyRecords), source: .file)
        for failure: XLSXWorkbookFailure in [.tooManyRows, .tooManyCells, .tooManySharedStrings] { #expect(message(failure) == tooMany, "\(failure)") }
        #expect(message(.noVisibleSheet) == "보이는 시트가 없어요. 숨긴 시트는 가져오지 않으니 숨기기를 풀어 주세요.")
        #expect(message(.textTooLong) == "칸 하나의 글이 너무 길어요. 본문은 한 칸에 3,000자까지예요.")
        let unreadable = "이 엑셀 파일을 읽을 수 없어요. 엑셀에서 「Excel 통합 문서(.xlsx)」로 다시 저장해 주세요."
        for failure: XLSXWorkbookFailure in [.archive(.notZip), .archive(.encrypted), .archive(.crcMismatch), .archive(.zip64), .doctypeOrEntity,
                                             .malformedXML, .notSpreadsheet, .brokenRelationship, .invalidCellReference, .sheetNotFound] {
            #expect(message(failure) == unreadable, "\(failure)")
        }
        #expect(PackImportCopy.failureFooter(.structural(.workbook(.malformedXML)), source: .file) == "파일 내용은 보여 주지 않아요.")
        #expect(!PackImportCopy.showsHeaderExample(.structural(.workbook(.malformedXML))))
    }

    @Test("★ 4-G 머리글·정보 줄 — 병합(시안 표 그대로) · 글 아닌 칸 — 구조 오류 풋터")
    func headerFailures() {
        #expect(PackImportCopy.failureMessage(.structural(.mergedHeaderOrMeta(record: 1, line: 1)), source: .file)
                == "머리글이나 정보 줄에 병합한 칸이 있어요. 병합을 풀어 주세요.")
        #expect(PackImportCopy.failureMessage(.structural(.nonTextHeaderCell(record: 1, line: 1)), source: .file)
                == "머리글이나 정보 줄에 수식·날짜처럼 글이 아닌 칸이 있어요. 그 칸을 글로 바꿔 주세요.")
        for failure: PackImportFailure in [.mergedHeaderOrMeta(record: 1, line: 1), .nonTextHeaderCell(record: 1, line: 1)] {
            #expect(PackImportCopy.failureFooter(.structural(failure), source: .file)
                    == "파일 내용은 보여 주지 않아요. 한 행이라도 구조가 틀리면 다른 행도 믿을 수 없어 통째로 받지 않아요.")
        }
    }

    @Test("★ 4-D 시트 고르기 · 미리보기 숨김 줄")
    func sheetCopy() {
        #expect(PackImportCopy.sheetTitle == "시트 고르기")
        #expect(PackImportCopy.sheetHeader == "가져올 시트")
        #expect(PackImportCopy.sheetFooter == "숨긴 시트는 목록에 없어요. 한 번에 한 시트만 가져와요 — 다른 시트는 다시 가져오면 돼요.")
        #expect(PackImportCopy.sheetRowCount(645) == "약 645행")
        #expect(PackImportCopy.sheetRowCount(0) == "빈 시트")
        #expect(PackImportCopy.sheetRowCount(nil) == nil)
        #expect(PackImportCopy.reviewSheetAgain == "시트 다시 고르기")
        #expect(PackImportCopy.chooseAnotherSheet == "다른 시트 고르기")
        #expect(PackImportCopy.hiddenRows(3) == "숨긴 행 3개도 가져와요")
        #expect(PackImportCopy.hiddenColumns(1) == "숨긴 열 1개도 가져와요")
    }

    @Test("★ AC-35 — 엑셀 사유 문구는 xlsx 중심판 목록에만 있다(CSV 전용판 목록에는 없다 — 그 판은 xlsx를 받지 않는다)")
    func workbookCopyOnlyInXLSXEdition() {
        let csvTexts = Set(PackCopySet.$previewing.withValue(.csv) { allScreenCopy })
        let xlsxTexts = Set(PackCopySet.$previewing.withValue(.xlsx) { allScreenCopy })
        #expect(Set(workbookOnlyCopy).isSubset(of: xlsxTexts))
        // 공유 풋터(「파일 내용은 보여 주지 않아요.」)·같은 고치는 법은 두 판에 다 있다 — xlsx를 말하는 줄만 CSV 판에 없어야 한다
        let mentioning = workbookOnlyCopy.filter { !PackCopyLint.xlsxMentions(in: $0).isEmpty }
        #expect(mentioning.count >= 4, "엑셀 사유 문구가 실제로 xlsx를 말한다 — 판 구분이 필요한 이유")
        for text in mentioning { #expect(!csvTexts.contains(text), "\(text)") }
        #expect(!csvTexts.contains(PackImportCopy.sheetTitle) && !csvTexts.contains(PackImportCopy.skipTitle(SkippedRecord(row: 12, reason: .formula))),
                "시트 고르기·「n번째 행」도 CSV 판 목록에 없다")
    }
}
