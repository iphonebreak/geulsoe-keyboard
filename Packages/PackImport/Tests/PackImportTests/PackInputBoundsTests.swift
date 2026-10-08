import Foundation
import Testing
import TadakDomain
@testable import PackImport

// codex 반론 v1.3.0 앱(`docs/release/counter-v130-codex-app.md`) — 가져오기 입력의 상한이 **계산 앞**에 있는가.
// A3 붙여넣기: 3MB 상한을 합치기·자동 개요 앞에 · CSV 스캐너의 열 수 상한(xlsx와 같은 접기, AC-32) · 계산 중 취소.
// A4 xlsx: 실패한 해제(CRC·손상·크기)도 해제 총량 장부에 들어간다 — 시트 목록이 모든 시트를 풀어도 총량 안.

private typealias F = XLSXFixture

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
    var count: Int { lock.withLock { value } }
}

// MARK: - A3 붙여넣기

/// AC-32 — 13칸(메타 12 + 넘침 1)을 넘는 행. 넘친 칸은 xlsx처럼 마지막 칸 하나로 접혀(먼저 온 비지 않은 칸) 같은 판정이 나야 한다
let wideRowCases: [EquivalenceCase] = [
    EquivalenceCase(id: "머리글 — 알아보는 이름이 접힌 칸(14번째 뒤)에만 있다",
                    grid: [(1...12).map { "열\($0)" } + ["", "x", "", "본문", "번호"], ["1", "가", "나"]]),
    EquivalenceCase(id: "머리글 — 넘친 칸의 첫 글이 알아보는 이름",
                    grid: [["번호", "제목", "본문"] + Array(repeating: "", count: 12) + ["본문"], ["1", "가", "나"]]),
    EquivalenceCase(id: "데이터 — 20번째 칸에 글이 있는 행은 열 수로 건너뛴다",
                    grid: [["번호", "제목", "본문"], ["1", "가", "나"], ["2", "다", "라"] + Array(repeating: "", count: 16) + ["넘침"],
                           ["3", "마", "바"]]),
    EquivalenceCase(id: "메타 — 20번째 칸에 글이 있으면 칸 상한",
                    grid: [["#이름", "팩"] + Array(repeating: "", count: 17) + ["넘침"], ["번호", "제목", "본문"], ["1", "가", "나"]]),
]

@Suite("codex 반론 v1.3.0 앱 A3 — 붙여넣기: 상한을 계산 앞에 · 열 수 상한 · 계산 중 취소")
struct PasteBoundsTests {

    @Test("★ 개요는 3MB(파일과 같은 바이트 상한)를 넘는 글을 세지 않는다 — 줄 수·칸 나누기 계산 없이 「너무 길어요」")
    func overviewOverLimit() {
        let limit = PackLimits.fileBytes
        let over = String(repeating: "가,", count: limit / 4 + 1)   // 4B × 750,001 = 3,000,004B
        let overview = PackPasteOverview.of(over)
        #expect(overview.isTooLarge)
        #expect(overview.lines == 0 && overview.delimiter == nil, "세지 않았다")
        #expect(PackImportCopy.pasteSummary(overview) == PackImportCopy.failureMessage(.structural(.fileTooLarge), source: .paste),
                "「읽기」를 눌렀을 때와 같은 문구")
        let atLimit = PackPasteOverview.of(String(repeating: "a", count: limit))
        #expect(!atLimit.isTooLarge && atLimit.lines == 1, "딱 상한은 받는다(제한 읽기와 같은 경계)")
        #expect(PackImportCopy.pasteSummary(PackPasteOverview(lines: 42, delimiter: .tab)) == PackImportCopy.pasteSummary(lines: 42, delimiter: .tab))
    }

    @Test("★ 「붙여넣기」 버튼의 여러 글 합치기도 상한 앞에서 — 구분자 줄바꿈까지 세어 넘으면 합치지 않는다(nil)")
    func joinedPasteLimit() {
        #expect(PackPasteOverview.joinedPaste(["가", "나"]) == "가\n나")
        #expect(PackPasteOverview.joinedPaste([]) == "")
        let half = String(repeating: "a", count: PackLimits.fileBytes / 2)
        #expect(PackPasteOverview.joinedPaste([half, String(half.dropLast())])?.utf8.count == PackLimits.fileBytes)
        #expect(PackPasteOverview.joinedPaste([half, half]) == nil, "1,500,000 + 줄바꿈 1 + 1,500,000 = 3,000,001B")
        #expect(PackPasteOverview.joinedPaste([String(repeating: "가", count: PackLimits.fileBytes / 3 + 1)]) == nil, "한 글도 바이트로")
    }

    @Test("★ CSV 스캐너는 한 레코드에 13칸까지만 배열을 늘린다 — 넘친 칸은 마지막 칸 하나로(먼저 온 비지 않은 칸)")
    func scannerCapsColumns() throws {
        let wide = try CSVRecordParser.parse("x" + String(repeating: ",", count: 100_000) + "끝", delimiter: .comma)
        #expect(wide.records.count == 1)
        #expect(wide.records[0].cells.count == RawTable.columnLimit)
        #expect(wide.records[0].cells.first == "x" && wide.records[0].cells.last == "끝")

        let first = try CSVRecordParser.parse((1...12).map { "\($0)" }.joined(separator: ",") + ",,첫,둘\n다음", delimiter: .comma)
        #expect(first.records.map(\.cells.count) == [RawTable.columnLimit, 1])
        #expect(first.records[0].cells[12] == "첫", "xlsx 접기와 같이 먼저 온 것")
        let blank = try CSVRecordParser.parse(String(repeating: ",", count: 50), delimiter: .comma)
        #expect(blank.records[0].isBlank && blank.records[0].cells.count == RawTable.columnLimit)
        // 따옴표 칸도 같은 규칙
        let quoted = try CSVRecordParser.parse(Array(repeating: "\"q\"", count: 20).joined(separator: ","), delimiter: .comma)
        #expect(quoted.records[0].cells.count == RawTable.columnLimit && quoted.records[0].cells[12] == "q")
    }

    @Test("★ AC-32 — 넓은 행도 CSV와 xlsx가 같은 판정(같은 접기)", arguments: wideRowCases)
    func wideRowsSameVerdict(_ testCase: EquivalenceCase) {
        #expect(PackVerdictResult.csv(testCase.grid) == PackVerdictResult.xlsx(WorkbookBuilder.workbook(grid: testCase.grid)))
    }

    @Test("넓은 행의 판정 — 데이터는 그 행만 열 수로, 메타는 칸 상한으로 전체 거부(지금 규칙 그대로)")
    func wideRowVerdicts() throws {
        guard case .verdict(let data) = PackVerdictResult.csv(wideRowCases[2].grid) else { Issue.record("초안이어야 한다"); return }
        #expect(data.skipped == ["3:columnCount"])
        #expect(PackVerdictResult.csv(wideRowCases[3].grid) == .failure(.metaTooManyCells(record: 1, line: 1)))
    }

    @Test("★ 계산 중에도 취소를 본다 — 취소를 보면 남은 계산 없이 nil(늦은 「n줄」도 없다)")
    func cancellationDuringMeasure() {
        let text = "x" + String(repeating: ",", count: 2_000_000)
        let calls = CallCounter()
        #expect(PackPasteOverview.measure(text) { calls.next() >= 3 } == nil)
        #expect(calls.count == 3, "취소를 본 뒤에는 더 계산하지 않는다")
        #expect(PackPasteOverview.measure("번호\t제목\t본문\n1\t가\t나") { false } == PackPasteOverview(lines: 2, delimiter: .tab))

        // 칸 나누기 시험(한 레코드가 2MB — 후보마다 약 488번 묻는다)의 둘째 후보 중간에 취소돼도 거기서 멈춘다 — 셋째 후보는 하지 않는다
        let trialCalls = CallCounter()
        #expect(PackImporter.likelyDelimiter(text) { trialCalls.next() >= 3 } == nil)
        #expect(trialCalls.count == 3)
        let lateCalls = CallCounter()
        #expect(PackPasteOverview.measure(text) { lateCalls.next() >= 500 } == nil, "둘째 후보 시험 중의 취소")
        #expect(lateCalls.count == 500)
    }
}

// MARK: - A4 xlsx 해제 총량

@Suite("codex 반론 v1.3.0 앱 A4 — 실패한 해제도 해제 총량 장부에")
struct FailedInflationLedgerTests {

    private static func badCRC(_ entry: ZipEntrySpec) -> ZipEntrySpec {
        var entry = entry
        entry.centralCRC = 0x1234_5678
        entry.localCRC = 0x1234_5678
        return entry
    }

    @Test("★ CRC가 틀린 파트도 푼 만큼 장부에 — 셋째 파트는 CRC가 아니라 총량에서 멈춘다", arguments: [UInt16(0), 8])
    func crcFailuresAreCharged(method: UInt16) throws {
        let content = String(repeating: "x", count: 1_000)
        var spec = ZipSpec(["a.xml", "b.xml", "c.xml"].map { Self.badCRC(ZipEntrySpec($0, content, method: method)) })
        if method == 0 { for index in spec.entries.indices { spec.entries[index].flags = 0 } }
        var limits = XLSXArchiveLimits.product
        limits.totalOutputBytes = 2_500
        var archive = try XLSXArchive.open(spec.build(), limits: limits)
        #expect(throws: XLSXArchiveFailure.crcMismatch) { _ = try archive.read("a.xml", as: .worksheet) }
        #expect(archive.inflatedBytes == 1_000)
        #expect(throws: XLSXArchiveFailure.crcMismatch) { _ = try archive.read("b.xml", as: .worksheet) }
        #expect(archive.inflatedBytes == 2_000)
        #expect(throws: XLSXArchiveFailure.totalOutputExceeded) { _ = try archive.read("c.xml", as: .worksheet) }
    }

    @Test("손상된 압축·크기 불일치로 실패한 해제도 선언 크기만큼 장부에(멈추기 전까지 푼 양의 상한)")
    func corruptAndMismatchAreCharged() throws {
        let content = ZipFixture.moderatelyCompressible(count: 1_000)   // 압축비 상한(①)에 먼저 걸리지 않게
        var corrupt = ZipEntrySpec(name: Array("a.xml".utf8), content: content)
        corrupt.compressed = Array(ZipFixture.deflate(content).dropLast(2))
        var longer = ZipEntrySpec(name: Array("b.xml".utf8), content: content)
        longer.centralUncompressedSize = 1_005
        longer.localUncompressedSize = 1_005
        var archive = try XLSXArchive.open(ZipSpec([corrupt, longer]).build())
        #expect(throws: XLSXArchiveFailure.corruptCompressedData) { _ = try archive.read("a.xml", as: .worksheet) }
        #expect(archive.inflatedBytes == 1_000)
        #expect(throws: XLSXArchiveFailure.sizeMismatch) { _ = try archive.read("b.xml", as: .worksheet) }
        #expect(archive.inflatedBytes == 2_005)
    }

    @Test("★ 시트 목록(모든 시트의 행 수)도 같은 총량 — 깨진 시트를 푼 몫 때문에 뒤 시트는 행 수 없이 보인다")
    func sheetListingIsBounded() throws {
        let rows = #"<row r="1"><c r="A1" t="inlineStr"><is><t>번호</t></is></c></row>"#
        let fixture = XLSXFixture(sheets: [F.sheet("하나", rows: rows, index: 1), F.sheet("둘", rows: rows, index: 2),
                                           F.sheet("셋", rows: rows, index: 3)])
        let broken: Set<String> = ["xl/worksheets/sheet1.xml", "xl/worksheets/sheet2.xml"]
        let entries = fixture.entries().map { broken.contains(String(decoding: $0.name, as: UTF8.self)) ? Self.badCRC($0) : $0 }
        let data = ZipSpec(entries).build()
        let openParts = [fixture.defaultContentTypes, fixture.defaultRootRels, fixture.defaultWorkbook, fixture.defaultWorkbookRels]
            .map(\.utf8.count).reduce(0, +)
        let sheetBytes = fixture.sheets[0].xml.utf8.count

        var ample = XLSXWorkbookLimits.product
        ample.archive.totalOutputBytes = openParts + sheetBytes * 3
        var tight = XLSXWorkbookLimits.product
        tight.archive.totalOutputBytes = openParts + sheetBytes * 3 - 1
        for (limits, expected) in [(ample, [nil, nil, 1]), (tight, [Int?](repeating: nil, count: 3))] {
            guard case .chooseSheet(let sheets) = try PackImporter.readWorkbook(data, sheet: nil, limits: limits) else {
                Issue.record("시트 고르기여야 한다"); continue
            }
            #expect(sheets.map(\.rowCount) == expected)
        }
    }
}
