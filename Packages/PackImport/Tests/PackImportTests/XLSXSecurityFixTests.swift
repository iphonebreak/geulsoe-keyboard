import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-e ③ — 보안 검토(`docs/release/review-ext-1e-security.md`) S1~S7 수정 고정 + 「③ 뒤 뮤테이션에서 꼭 볼 것」 미리 넣기.
// **시간 폭탄(S1·S2·S3)은 결과만 보면 작은 입력에서 고치기 전과 같다** — 큰 입력 + 경과 시간 상한으로 고정한다(검토 6절 1번).
// 시간 상한은 고치기 전 실측(검토 7절, `-O`)의 몇 분의 일이고, 고친 뒤 실측의 수십 배다(디버그 빌드 기준) — 흔들림에 넉넉하다.

private typealias F = XLSXFixture

/// 경과 시간(초)
private func seconds(_ work: () -> Void) -> Double {
    let duration = ContinuousClock().measure(work)
    return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

private func openFailure(_ data: Data) -> XLSXWorkbookFailure? {
    do {
        var reader = try XLSXWorkbookReader.open(data)
        for sheet in reader.sheets { _ = try reader.table(for: sheet) }
        return nil
    } catch {
        return error
    }
}

/// 스타일 파트만 바꾼 한 칸짜리 워크북 — 큰 파트가 압축비 상한(①)에 먼저 걸리지 않게 stored
private func workbook(styles: String) -> Data {
    var fixture = XLSXFixture.singleText()
    fixture.styles = styles
    fixture.method = 0
    return fixture.build()
}

/// 서식 하나 + 그것을 쓰는 xf 여럿
private func styles(code: String, xfCount: Int) -> String {
    F.declaration + #"<styleSheet xmlns="\#(F.mainNS)"><numFmts count="1"><numFmt numFmtId="164" formatCode="\#(F.escape(code))"/></numFmts>"#
        + #"<cellXfs count="\#(xfCount)">"# + String(repeating: #"<xf numFmtId="164"/>"#, count: xfCount) + "</cellXfs></styleSheet>"
}

/// 날짜 토큰이 없는 서식(숫자 기호만) — 끝까지 훑어야 「날짜 아님」을 안다
private func numberCode(length: Int) -> String {
    String(String(repeating: "#,##0.00;", count: length / 9 + 1).prefix(length))
}

/// 시트에 모르는 요소 하나 — 속성 `count`개(값 안에 `>`·`=`를 넣을 수 있다)
private func sheetWithAttributes(_ count: Int, value: String = "") -> Data {
    let attributes = (0..<count).map { #" a\#($0)="\#(value)""# }.joined()
    var fixture = XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#, before: "<x\(attributes)/>")],
                              sharedStrings: F.plainSST(["회의시작"]))
    fixture.method = 0
    return fixture.build()
}

// MARK: - S1

@Suite("보안 S1 — styles 서식 판정: 서식 번호마다 한 번 · formatCode 255자 상한")
struct XLSXStylesTimeBombTests {

    @Test("★ 시간 폭탄(검토 실측 약 19분) — 50만 자 서식 하나 + xf 2만 4천 개는 곧바로 거부(1초 안)")
    func hugeFormatCode() {
        let data = workbook(styles: styles(code: numberCode(length: 480_000), xfCount: 24_000))
        var failure: XLSXWorkbookFailure?
        let elapsed = seconds { failure = openFailure(data) }
        #expect(failure == .malformedPart)
        #expect(elapsed < 1, "\(elapsed)초")
    }

    @Test("★ 255자 서식은 받고 256자는 거부 — 엑셀 사용자 서식 상한", arguments: [(255, true), (256, false)])
    func codeLengthBoundary(_ length: Int, accepted: Bool) {
        #expect(openFailure(workbook(styles: styles(code: numberCode(length: length), xfCount: 1))) == (accepted ? nil : .malformedPart))
    }

    @Test("★ 메모 — 상한 안 서식(255자)을 xf 4만 개가 써도 서식 판정은 한 번(파트 1MB 안, 2초 안)")
    func memoizedPerFormat() {
        let text = styles(code: numberCode(length: 255), xfCount: 40_000)
        #expect(text.utf8.count < XLSXArchiveLimits.product.stylesBytes)
        let data = workbook(styles: text)
        var failure: XLSXWorkbookFailure?
        let elapsed = seconds { failure = openFailure(data) }
        #expect(failure == nil)
        #expect(elapsed < 2, "\(elapsed)초")
    }

    @Test("메모가 판정을 바꾸지 않는다 — 날짜 서식·숫자 서식·재정의가 섞인 xf 표")
    func memoKeepsVerdicts() throws {
        let text = F.declaration + #"<styleSheet xmlns="\#(F.mainNS)"><numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/>"#
            + #"<numFmt numFmtId="14" formatCode="0.00"/></numFmts><cellXfs count="5"><xf numFmtId="164"/><xf numFmtId="14"/><xf numFmtId="164"/>"#
            + #"<xf numFmtId="20"/><xf numFmtId="14"/></cellXfs></styleSheet>"#
        var fixture = XLSXFixture(sheets: [F.sheet(rows: (0..<5).map { #"<c r="\#(WorkbookBuilder.columnName($0))1" s="\#($0)"><v>5</v></c>"# }
            .joined().wrappedInRow())])
        fixture.styles = text
        var reader = try XLSXWorkbookReader.open(fixture.build())
        let row = try #require(try reader.table(for: reader.sheets[0]).row(1))
        #expect(row.cells == [.unsupported(.date), .number("5"), .unsupported(.date), .unsupported(.date), .number("5")])
    }
}

private extension String {
    func wrappedInRow() -> String { #"<row r="1">"# + self + "</row>" }
}

// MARK: - S2

@Suite("보안 S2 — 시작 태그당 속성 수 ≤ 64(사전 스캔, 따옴표를 아는 셈)")
struct XLSXAttributeCountTests {

    @Test("★ 64개는 받고 65개는 거부 — 값 안의 `>`·`=`로 태그를 쪼개 덜 세게 만들 수 없다", arguments: ["", "a>b=c", "=>='\u{0027}"])
    func boundary(_ value: String) {
        let escaped = value.replacingOccurrences(of: "'", with: "&apos;")
        #expect(openFailure(sheetWithAttributes(64, value: escaped)) == nil)
        #expect(openFailure(sheetWithAttributes(65, value: escaped)) == .tooManyAttributes)
    }

    @Test("작은따옴표 값 안의 큰따옴표·`>`도 값이다")
    func singleQuotedValues() {
        let attributes = (0..<65).map { #" a\#($0)='x">y=z'"# }.joined()
        var fixture = XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#, before: "<x\(attributes)/>")],
                                  sharedStrings: F.plainSST(["회의시작"]))
        fixture.method = 0
        #expect(openFailure(fixture.build()) == .tooManyAttributes)
    }

    @Test("★ 본문·주석·CDATA·처리 명령·끝 태그의 `=`는 세지 않는다(「======」 구분선 오거부 없음)")
    func textIsNotCounted() throws {
        let line = String(repeating: "=", count: 200)
        let rows = #"<row r="1"><c r="A1" t="inlineStr"><is><t>\#(line)</t></is></c><c r="B1" t="s"><v>0</v></c></row>"#
        let before = "<!-- \(line) --><?pi \(line)?>"
        var fixture = XLSXFixture(sheets: [F.sheet(rows: rows, before: before)], sharedStrings: F.sst([#"<t><![CDATA[\#(line)]]></t>"#]))
        fixture.method = 0
        var reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(try reader.table(for: reader.sheets[0]).row(1)?.cells == [.text(line), .text(line)])
    }

    @Test("★ 시간 폭탄(검토 실측 16만 개 6.5초) — 속성 16만 개 시트는 1.5초 안에 거부", .timeLimit(.minutes(1)))
    func hugeAttributeCount() {
        let data = sheetWithAttributes(160_000)
        var failure: XLSXWorkbookFailure?
        let elapsed = seconds { failure = openFailure(data) }
        #expect(failure == .tooManyAttributes)
        #expect(elapsed < 1.5, "\(elapsed)초")
    }

    @Test("★ 주석·CDATA·처리 명령 안의 **가짜 시작 태그**(속성 100개)는 태그가 아니다 — 건너뛰지 않으면 오거부한다")
    func fakeTagsInsideSkippedMarkup() throws {
        let fake = "<x" + (0..<100).map { #" a\#($0)="""# }.joined() + ">"
        let before = "<!-- \(fake) --><?pi \(fake)?>"
        let rows = #"<row r="1"><c r="A1" t="inlineStr"><is><t><![CDATA[\#(fake)]]></t></is></c></row>"#
        var fixture = XLSXFixture(sheets: [F.sheet(rows: rows, before: before)])
        fixture.method = 0
        var reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(try reader.table(for: reader.sheets[0]).row(1)?.cells == [.text(fake)])
    }

    @Test("xmlns 선언도 속성으로 센다 — 루트에 접두 선언 63개 + 기본 2개")
    func namespaceDeclarationsCount() {
        let declarations = (0..<63).map { #" xmlns:p\#($0)="urn:p\#($0)""# }.joined()
        var fixture = XLSXFixture.singleText()
        fixture.sheets[0].xml = F.declaration + #"<worksheet xmlns="\#(F.mainNS)" xmlns:r="\#(F.officeRelNS)"\#(declarations)><sheetData/></worksheet>"#
        fixture.method = 0
        #expect(openFailure(fixture.build()) == .tooManyAttributes)
    }
}

// MARK: - S3

@Suite("보안 S3 — 한 시트 표의 글 합 ≤ 6MB(공유 문자열 증폭)")
struct XLSXTableTextTests {

    /// 공유 문자열 하나(`bytes`B)를 `rows`행이 가리킨다
    private func amplified(bytes: Int, rows: Int) -> Data {
        let text = String(repeating: "가", count: bytes / 3)
        let sheetRows = (1...rows).map { #"<row r="\#($0)"><c r="A\#($0)" t="s"><v>0</v></c></row>"# }.joined()
        var fixture = XLSXFixture(sheets: [F.sheet(rows: sheetRows)], sharedStrings: F.plainSST([text]))
        fixture.method = 0
        return fixture.build()
    }

    @Test("★ 12,000B 글 하나 × 2만 행(논리 240MB) — 6MB에서 곧바로 거부(1초 안)")
    func amplificationRejected() {
        let data = amplified(bytes: 11_997, rows: 20_000)
        #expect(data.count < PackLimits.fileBytes)
        var failure: XLSXWorkbookFailure?
        let elapsed = seconds { failure = openFailure(data) }
        #expect(failure == .tooMuchText)
        #expect(elapsed < 1, "\(elapsed)초")
    }

    @Test("경계 — 합이 상한 안이면 받는다(1만 2천 B × 499행 ≈ 6MB 아래)")
    func underLimitAccepted() {
        #expect(openFailure(amplified(bytes: 12_000, rows: 499)) == nil)
        #expect(openFailure(amplified(bytes: 12_000, rows: 501)) == .tooMuchText)
    }

    @Test("★ ③까지 — 가져오기 파이프라인은 「파일이 너무 커요」로 끝난다(판정 경로에 6MB 넘는 글이 들어가지 않는다)")
    func pipelineStops() {
        let failure = WorkbookHelper.failure(amplified(bytes: 11_997, rows: 20_000))
        #expect(failure == .workbook(.tooMuchText))
        #expect(PackImportCopy.failureMessage(.structural(.workbook(.tooMuchText)), source: .file)
                == PackImportCopy.failureMessage(.structural(.fileTooLarge), source: .file))
    }
}

// MARK: - S4

@Suite("보안 S4 — 해제 총량은 사본이 함께 센다")
struct XLSXSharedLedgerTests {

    @Test("★ 아카이브 사본 둘에서 같은 파트를 읽어도 총량이 합산된다")
    func archiveCopiesShareLedger() throws {
        let content = String(repeating: "x", count: 1_000)
        let data = ZipSpec([ZipEntrySpec("a.xml", content, method: 0), ZipEntrySpec("b.xml", content, method: 0)]).build()
        var limits = XLSXArchiveLimits.product
        limits.totalOutputBytes = 1_500
        var archive = try XLSXArchive.open(data, limits: limits)
        var copy = archive
        _ = try archive.read("a.xml", as: .worksheet)
        #expect(copy.inflatedBytes == 1_000)
        #expect(throws: XLSXArchiveFailure.totalOutputExceeded) { _ = try copy.read("b.xml", as: .worksheet) }
    }

    @Test("★ 워크북 독자 사본에서 시트를 읽어도 총량이 합산된다(시트 목록의 행 수 읽기 등)")
    func readerCopiesShareLedger() throws {
        let fixture = XLSXFixture.singleText("회의시작")
        let openParts = [fixture.defaultContentTypes, fixture.defaultRootRels, fixture.defaultWorkbook, fixture.defaultWorkbookRels,
                         fixture.sharedStrings ?? ""].map(\.utf8.count).reduce(0, +)
        let sheetBytes = fixture.sheets[0].xml.utf8.count
        var limits = XLSXWorkbookLimits.product
        limits.archive.totalOutputBytes = openParts + sheetBytes * 2 - 1
        let reader = try XLSXWorkbookReader.open(fixture.build(), limits: limits)
        var first = reader
        var second = reader
        _ = try first.table(for: reader.sheets[0])
        #expect(throws: XLSXWorkbookFailure.archive(.totalOutputExceeded)) { _ = try second.table(for: reader.sheets[0]) }
    }
}

// MARK: - S5 · S6 · S7

@Suite("보안 S5·S6·S7 — 관계 대상 `%` · `<is>`·`<t>` 두 번 · 시트 이름 표시 정리")
struct XLSXAmbiguityTests {

    @Test("★ S5 — 관계 대상에 `%`가 있으면 거부(글자 그대로의 이름이 아카이브에 있어도)")
    func percentTarget() {
        var fixture = XLSXFixture.singleText()
        fixture.sheets[0].target = "worksheets/sheet%31.xml"
        fixture.sheets[0].part = "xl/worksheets/sheet%31.xml"
        #expect(openFailure(fixture.build()) == .unsafeRelationshipTarget)
    }

    @Test("★ S6 — 한 칸에 하나여야 할 것이 둘이면 거부: `<si>`의 `<t>` 둘·`<r>`의 `<t>` 둘·`<is>` 둘·`<is>`의 `<t>` 둘", arguments: [
        ("sst", "<t>가</t><t>나</t>"),
        ("sst", "<r><t>가</t><t>나</t></r>"),
        ("inline", "<is><t>가</t></is><is><t>나</t></is>"),
        ("inline", "<is><t>가</t><t>나</t></is>"),
        ("inline", "<is><r><t>가</t><t>나</t></r></is>"),
        // `<t>` 중복 검사에 가려지지 않게 — 조각(`<r>`)만 든 `<is>` 둘, 빈 `<is>` 뒤의 `<is>`
        ("inline", "<is><r><t>가</t></r></is><is><r><t>나</t></r></is>"),
        ("inline", "<is/><is><t>나</t></is>"),
    ])
    func duplicatedText(_ place: String, _ xml: String) {
        let fixture: XLSXFixture = place == "sst"
            ? XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#)], sharedStrings: F.sst([xml]))
            : XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="inlineStr">\#(xml)</c></row>"#)])
        #expect(openFailure(fixture.build()) == .malformedPart)
    }

    @Test("S6 — 스키마대로의 여러 조각은 그대로 이어 붙인다(`<t>` + `<r>`들, 인라인 `<r>`들)")
    func validPiecesStillJoin() throws {
        var fixture = XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="inlineStr"><is><r><t>다</t></r><r><t>라</t></r></is></c></row>"#)],
                                  sharedStrings: F.sst(["<t>가</t><r><t>나</t></r><r><t>다</t></r>"]))
        fixture.method = 0
        var reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(try reader.table(for: reader.sheets[0]).row(1)?.cells == [.text("가나다"), .text("다라")])
    }

    @Test("★ S7 — 시트 이름의 `_x202E_`(방향 재정의)·`_x0000_`·`_x200B_`는 화면 이름에서 빠진다(고르기 목록·초안)")
    func sheetNamesSanitizedForDisplay() throws {
        let rows = [WorkbookRow.text(["번호", "본문"]), WorkbookRow.text(["1", "가"])]
        let data = WorkbookBuilder.workbook([WorkbookBuilder.sheet("가_x202E_나", rows, index: 1),
                                             WorkbookBuilder.sheet("Sheet_x200B_1_x0000_", rows, index: 2)])
        let sheets = try WorkbookHelper.sheets(data)
        #expect(sheets.map(\.name) == ["가나", "Sheet1"])
        let second = try WorkbookHelper.draft(data, sheet: 1)
        #expect(second.sheetName == "Sheet1" && second.suggestedPackName == nil, "정리한 뒤의 이름으로 기본 이름(`Sheet N`)을 가린다")
        #expect(try WorkbookHelper.draft(data, sheet: 0).sheetName == "가나")
    }
}

// MARK: - ③ 뒤 뮤테이션에서 꼭 볼 것 (검토 6절) — 미리 넣는 시험

@Suite("보안 검토 6절 — 묶음 뮤테이션 대비 시험")
struct XLSXMutationGuardTests {

    @Test("★ 빈칸 5 — 정규화(NFC/NFD)만 다른 엔트리 이름 둘은 중복으로 거부")
    func normalizationDuplicate() {
        let composed = Array("xl/가.xml".precomposedStringWithCanonicalMapping.utf8)
        let decomposed = Array("xl/가.xml".decomposedStringWithCanonicalMapping.utf8)
        #expect(composed != decomposed)
        var first = ZipEntrySpec(name: composed, content: Array("a".utf8), method: 0)
        var second = ZipEntrySpec(name: decomposed, content: Array("b".utf8), method: 0)
        first.flags = 0x0800
        second.flags = 0x0800
        #expect(throws: XLSXArchiveFailure.duplicateEntryName) { _ = try XLSXArchive.open(ZipSpec([first, second]).build()) }
    }

    @Test("★ 빈칸 6 — 엔트리 정확히 200개는 받는다(201개는 E12가 거부)")
    func twoHundredEntries() throws {
        let entries = (0..<200).map { ZipEntrySpec("p\($0).xml", "x", method: 0) }
        let archive = try XLSXArchive.open(ZipSpec(entries).build())
        #expect(archive.contains("p199.xml"))
    }

    @Test("★ 빈칸 9 — xlsx 바이트도 같은 제한 읽기(cap+1)를 거친다: 상한 + 1바이트 xlsx 파일은 열기 전에 거부")
    func boundedReadForWorkbooks() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: url) }
        try (Data([0x50, 0x4B, 0x03, 0x04]) + Data(count: PackLimits.fileBytes - 3)).write(to: url)
        #expect(PackFileReader.read(url) == .failure(.structural(.fileTooLarge)))
        // 세션도 바이트 상한을 먼저 본다 — 계산 없이 거부하고 원본을 들지 않는다
        var session = PackImportSession(acceptsWorkbookFiles: true)
        #expect(session.start(.file(Data([0x50, 0x4B, 0x03, 0x04]) + Data(count: PackLimits.fileBytes - 3))) == nil)
        #expect(session.phase == .failed(.structural(.fileTooLarge)) && !session.hasSource)
    }

    @Test("★ 빈칸 8 — xlsx 경로도 데이터 행 5,000·머리글 8열·정보 줄 12칸·문자 정리를 CSV와 같이 본다")
    func pipelineCapsOnWorkbooks() throws {
        let header = WorkbookRow.text(["번호", "본문"])
        let many = [header] + (1...(PackLimits.dataRecords + 1)).map { WorkbookRow.text(["\($0 % 9_999 + 1)", "가"]) }
        #expect(WorkbookHelper.failure(WorkbookBuilder.workbook(many)) == .tooManyRecords)
        let wide = WorkbookRow.text(["번호", "본문"] + (1...7).map { "열\($0)" })
        #expect(WorkbookHelper.failure(WorkbookBuilder.workbook([wide, WorkbookRow.text(["1", "가"])])) == .tooManyColumns)
        let meta = WorkbookRow.text(["#틀"] + (1...12).map { "틀\($0) {n}" })
        #expect(WorkbookHelper.failure(WorkbookBuilder.workbook([meta, header, WorkbookRow.text(["1", "가"])])) == .metaTooManyCells(record: 1, line: 1))
        let draft = try WorkbookHelper.draft(WorkbookBuilder.workbook([header, WorkbookRow.text(["1", "가\u{202E}나\u{200B}"])]))
        #expect(draft.items.first?.body == "가나" && draft.sanitizedCharacterCount == 2)
    }

    @Test("★ 빈칸 AC-34 전 구간 — 표식을 넣은 시트 이름·셀 글·파트 이름이 세션의 거부 값·문구·건너뛴 행 문구 어디에도 없다")
    func sessionCarriesNoContent() throws {
        let marker = "ZQXMARK"
        var broken = WorkbookBuilder.sheet("\(marker)깨짐", [], index: 1)
        broken.part = "xl/worksheets/\(marker).xml"
        broken.target = "worksheets/\(marker).xml"
        broken.xml = F.worksheet(rows: #"<row r="1"><c r="a1" t="inlineStr"><is><t>\#(marker)</t></is></c></row>"#)
        let skipped = WorkbookBuilder.sheet("\(marker)건너뜀", [WorkbookRow.text(["번호", "본문"]), WorkbookRow([.text("\(marker)"), .text("\(marker)본문")]),
                                                              WorkbookRow([.number("1"), .formula])], index: 2)
        let data = WorkbookBuilder.workbook([broken, skipped])
        var shown: [String] = []
        for index in 0..<2 {
            var session = PackImportSession(acceptsWorkbookFiles: true)
            _ = session.start(.file(data)).map { session.receive(PackImportSession.compute($0, library: nil)) }
            session.selectSheet(index)
            _ = session.confirmSheet().map { session.receive(PackImportSession.compute($0, library: nil)) }
            guard case .failed(let problem) = session.phase else { Issue.record("거부가 아니다: \(index)"); continue }
            shown += [String(describing: problem), PackImportCopy.failureMessage(problem, source: .file), PackImportCopy.failureFooter(problem, source: .file)]
            if case .noValidRecords(let records) = problem {
                shown += records.flatMap { [PackImportCopy.skipTitle($0), PackImportCopy.skipFix($0)] }
            }
        }
        #expect(shown.count >= 6)
        for text in shown { #expect(!text.contains(marker), "\(text)") }
    }
}
