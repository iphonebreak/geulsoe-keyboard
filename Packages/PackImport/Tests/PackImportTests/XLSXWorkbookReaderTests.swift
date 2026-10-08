import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-e ② — xlsx XML → `RawTable` **정상 경로·셀 정책**(PDR 6-4·6-5b, AC-31·36). 합성 워크북은 `XLSXFixture`로 짓는다.
// 이 층은 셀의 **종류**만 정한다 — 건너뜀 사유·우선순위(수식 → 날짜 → 불리언·오류 → 숫자(번호 열 밖) → 병합)와
// 병합 × 헤더/메타 전체 거부는 CSV와 같은 판정 경로(1-e ③, AC-32)가 이 표를 받아 한다.

private typealias F = XLSXFixture

private func table(_ fixture: XLSXFixture, sheet index: Int = 0) throws -> RawTable {
    var reader = try XLSXWorkbookReader.open(fixture.build())
    return try reader.table(for: reader.sheets[index])
}

/// 시트 한 장 + 공유 문자열 + 스타일
private func workbook(_ rows: String, strings: [String] = ["글"], styles: String? = nil, before: String = "", after: String = "") -> XLSXFixture {
    var fixture = XLSXFixture(sheets: [F.sheet(rows: rows, before: before, after: after)], sharedStrings: F.plainSST(strings))
    fixture.styles = styles
    return fixture
}

@Suite("외부 채움글 1-e ② — 셀 종류 (6-4 셀 정책)")
struct XLSXCellKindTests {

    @Test("★ 수식(<f>)은 타입·캐시 값과 상관없이 수식 — t 없음(숫자 결과)·t=\"s\"·t=\"str\"·공유 수식·값 없는 수식")
    func formulaCells() throws {
        let rows = #"<row r="1"><c r="A1"><f>1+2</f><v>3</v></c><c r="B1" t="s"><f>A1</f><v>0</v></c><c r="C1" t="str"><f>"a"</f><v>a</v></c>"#
            + #"<c r="D1"><f t="shared" si="0"/><v>4</v></c><c r="E1"><f>NOW()</f></c><c r="F1" t="b"><f>TRUE()</f><v>1</v></c></row>"#
        let row = try #require(try table(workbook(rows)).row(1))
        #expect(row.cells == Array(repeating: .unsupported(.formula), count: 6))
    }

    @Test("t=\"str\"는 <f>가 없어도 수식이다(ECMA 「수식 문자열」 — PDR 6-4 「t=\"str\" 포함」)")
    func stringTypeWithoutFormula() throws {
        let row = try #require(try table(workbook(#"<row r="1"><c r="A1" t="str"><v>값</v></c></row>"#)).row(1))
        #expect(row.cells == [.unsupported(.formula)])
    }

    @Test("★ 불리언·오류·ISO 날짜(t=\"d\")·인라인 문자열·숫자 글자 그대로")
    func otherTypes() throws {
        let rows = #"<row r="1"><c r="A1" t="b"><v>1</v></c><c r="B1" t="e"><v>#DIV/0!</v></c><c r="C1" t="d"><v>2026-10-07</v></c>"#
            + #"<c r="D1" t="inlineStr"><is><t>인라인</t></is></c><c r="E1" t="inlineStr"><is><r><t>서식 </t></r><r><rPr><b/></rPr><t>조각</t></r><rPh sb="0" eb="1"><t>ルビ</t></rPh></is></c>"#
            + #"<c r="F1"><v>323</v></c><c r="G1" t="n"><v>323.0</v></c><c r="H1"><v>1.23456789012345E+19</v></c><c r="I1"><v> 7 </v></c></row>"#
        let row = try #require(try table(workbook(rows)).row(1))
        #expect(row.cells == [.unsupported(.boolean), .unsupported(.error), .unsupported(.date), .text("인라인"), .text("서식 조각"),
                              .number("323"), .number("323.0"), .number("1.23456789012345E+19"), .number("7")])
    }

    @Test("★ 빈 셀 — 서식만 있는 <c>(Mac 빈 행)·값 없는 숫자·빈 공유 문자열·빈 인라인은 빈 칸, 끝 빈 칸은 잘라 내고 빈 행은 버린다")
    func blankCells() throws {
        let rows = #"<row r="1"><c r="A1" s="0"/><c r="B1" t="s"><v>0</v></c><c r="C1"><v></v></c><c r="D1" t="s"><v>1</v></c><c r="E1" t="inlineStr"><is><t></t></is></c></row>"#
            + #"<row r="2"><c r="A2" s="0"/><c r="B2" s="0"/><c r="C2" t="s"><v>1</v></c></row><row r="3"/>"#
        let result = try table(workbook(rows, strings: ["글", ""]))
        #expect(result.rows.map(\.number) == [1])
        #expect(result.rows[0].cells == [.blank, .text("글")])
    }

    @Test("★ 날짜 서식 — 내장 14·20, 사용자 서식(Mac·윈도우 따옴표 리터럴, 구글 따옴표 없는 한글), 통화·백분율·지수는 숫자")
    func dateStyles() throws {
        let styles = F.stylesXML(
            numFmts: [(180, #"m"월"\ d"일""#), (176, #"mm"월"\ dd"일""#), (166, "m월 d일"), (167, "yyyy-mm-dd"), (168, ##""₩"#,##0"##)],
            xfs: [0, 14, 20, 180, 176, 166, 167, 168, 9, 11, 6, 49])
        let cells = (1...11).map { #"<c r="\#(columnName($0 - 1))1" s="\#($0)"><v>46024</v></c>"# }.joined()
        let row = try #require(try table(workbook("<row r=\"1\">" + cells + "</row>", styles: styles)).row(1))
        #expect(row.cells == Array(repeating: RawCell.unsupported(.date), count: 6) + [.number("46024"), .number("46024"), .number("46024"),
                                                                                      .number("46024"), .number("46024")])
    }

    @Test("★ 내장 번호 재정의가 우선 — 엑셀의 내장 6(₩ 통화) 재정의는 숫자, 내장 14를 숫자 서식으로 재정의하면 숫자, 내장 6을 날짜로 재정의하면 날짜")
    func builtInOverride() throws {
        let currency = F.stylesXML(numFmts: [(6, ##""₩"#,##0_);[Red]\("₩"#,##0\)"##)], xfs: [0, 6])
        let notDate = F.stylesXML(numFmts: [(14, "0.00")], xfs: [0, 14])
        let date = F.stylesXML(numFmts: [(6, "yyyy-mm-dd")], xfs: [0, 6])
        let rows = #"<row r="1"><c r="A1" s="1"><v>1000</v></c></row>"#
        #expect(try table(workbook(rows, styles: currency)).row(1)?.cells == [.number("1000")])
        #expect(try table(workbook(rows, styles: notDate)).row(1)?.cells == [.number("1000")])
        #expect(try table(workbook(rows, styles: date)).row(1)?.cells == [.unsupported(.date)])
    }

    @Test("날짜 서식이 걸린 **글** 셀은 글이다(구글 「3월 4일」이 문자열로 남은 셀) — 숫자일 때만 날짜")
    func textWithDateStyle() throws {
        let styles = F.stylesXML(xfs: [0, 14])
        let row = try #require(try table(workbook(#"<row r="1"><c r="A1" s="1" t="s"><v>0</v></c></row>"#, strings: ["3월 4일"], styles: styles)).row(1))
        #expect(row.cells == [.text("3월 4일")])
    }

    @Test("한국어 엑셀 내장 날짜 번호(27~36·50~58)는 정의가 없어도 날짜, 정의 없는 사용자 번호는 일반")
    func localeBuiltInDates() throws {
        let styles = F.stylesXML(xfs: [0, 31, 32, 55, 200])
        let cells = (1...4).map { #"<c r="\#(columnName($0 - 1))1" s="\#($0)"><v>45000</v></c>"# }.joined()
        let row = try #require(try table(workbook("<row r=\"1\">" + cells + "</row>", styles: styles)).row(1))
        #expect(row.cells == [.unsupported(.date), .unsupported(.date), .unsupported(.date), .number("45000")])
    }

    @Test("★ 서식 문자열 판정 — 따옴표·\\x·[…]·_x·*x를 뺀 뒤 y m d h s e g·AM/PM·경과 시간 [h]", arguments: [
        // (서식, 날짜인가)
        (#"m"월"\ d"일""#, true), (#"mm"월"\ dd"일""#, true), ("m월 d일", true), ("m-d", true), ("m/d", true), ("yyyy-mm-dd", true),
        ("h:mm AM/PM", true), ("[h]:mm:ss", true), ("[ss]", true), ("[$-412]yyyy\"년\" m\"월\"", true), ("ggge\"年\"", true),
        ("mm:ss.0", true), ("[Red][<=100]d", true), ("dddd", true),
        (##""₩"#,##0_);[Red]\("₩"#,##0\)"##, false), ("0.00E+00", false), ("##0.0e-0", false), ("General", false), ("@", false),
        (#"0"일""#, false), (#"#,##0 "개월""#, false), (#""yyyy"0"#, false), (#"\d0"#, false), ("[Red]0", false), ("[DBNum1]0", false),
        ("_d0", false), ("*m0", false), ("0%", false), ("# ?/?", false), ("0;-0;;@", false), ("", false), (#""unterminated"#, false),
    ])
    func formatCodes(_ code: String, isDate: Bool) {
        #expect(XLSXNumberFormat.isDateFormat(code) == isDate, "\(code)")
    }

    @Test("내장 번호 표 — 14~22·45~47 날짜(PDR), 0~13·37~40·48·49 숫자")
    func builtInTable() {
        for id in [14, 15, 16, 17, 18, 19, 20, 21, 22, 45, 46, 47] { #expect(XLSXNumberFormat.isBuiltInDate(id), "\(id)") }
        for id in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 37, 38, 39, 40, 48, 49] { #expect(!XLSXNumberFormat.isBuiltInDate(id), "\(id)") }
    }
}

@Suite("외부 채움글 1-e ② — 공유 문자열 (6-4 셀 안 줄바꿈·서식 있는 문자열)")
struct XLSXSharedStringTests {

    private func strings(_ items: [String]) throws -> [String] {
        let rows = "<row r=\"1\">" + items.indices.map { #"<c r="\#(columnName($0))1" t="s"><v>\#($0)</v></c>"# }.joined() + "</row>"
        var fixture = XLSXFixture(sheets: [F.sheet(rows: rows)], sharedStrings: F.sst(items))
        fixture.method = 0
        let row = try #require(try table(fixture).row(1))
        return row.cells.map { if case .text(let text) = $0 { text } else { "<\($0)>" } }
    }

    @Test("★ 줄바꿈 순서 계약 — 윈도우(_x000D_ + 생 CRLF)·Mac(생 CRLF)·구글(LF)·CR만·&#13;&#10; 모두 LF 하나")
    func newlineContract() throws {
        let result = try strings([
            "<t>첫째 줄_x000D_\r\n둘째 줄</t>", "<t>첫째 줄\r\n둘째 줄</t>", "<t>첫째 줄\n둘째 줄</t>", "<t>첫째 줄\r둘째 줄</t>",
            "<t>첫째 줄&#13;&#10;둘째 줄</t>", "<t>첫째 줄_x000D_둘째 줄</t>", "<t>첫째 줄_x000D__x000A_둘째 줄</t>",
        ])
        #expect(result == Array(repeating: "첫째 줄\n둘째 줄", count: 7))
    }

    @Test("★ _xHHHH_는 왼쪽부터 한 번만 — _x005F_x000D_는 글자 그대로 「_x000D_」, 서로게이트 쌍은 한 글자, 홀로 선 서로게이트·자리 수 틀림은 그대로")
    func escapeDecoding() throws {
        let result = try strings([
            "<t>_x005F_x000D_</t>", "<t>_xD83D__xDE00_</t>", "<t>_xD83D_끝</t>", "<t>_x00e9_</t>", "<t>_x41_ _X0041_ _x0041</t>",
            "<t>a_x0041_b_x0042_</t>",
        ])
        #expect(result == ["_x000D_", "😀", "_xD83D_끝", "é", "_x41_ _X0041_ _x0041", "aAbB"])
    }

    @Test("★ <r> 조각을 이어 붙이고 <rPh>(발음 힌트)는 무시 — 조각 경계에 걸친 _xHHHH_는 이스케이프가 아니다")
    func richText() throws {
        let result = try strings([
            #"<r><t>#</t></r><r><rPr><b/></rPr><t>이름</t></r>"#,
            #"<r><t>漢</t></r><rPh sb="0" eb="1"><t>かん</t></rPh><phoneticPr fontId="1"/>"#,
            #"<r><t>a_x00</t></r><r><t>41_</t></r>"#,
            #"<t xml:space="preserve">  앞뒤 공백  </t>"#, "<t>  앞뒤 공백  </t>", "<t><![CDATA[<b>&amp;</b>]]></t>",
        ])
        #expect(result == ["#이름", "漢", "a_x0041_", "  앞뒤 공백  ", "  앞뒤 공백  ", "<b>&amp;</b>"])
    }

    @Test("NFD 한글·ZWJ 이모지·NBSP는 정규화하지 않는다(문자 정리는 뒤 단계 몫)")
    func noNormalization() throws {
        let nfd = "\u{1107}\u{116E}\u{11AB}"
        let result = try strings(["<t>\(nfd)</t>", "<t>👨\u{200D}👩\u{200D}👧</t>", "<t>\u{A0}공백\u{A0}</t>"])
        #expect(result.map { Array($0.unicodeScalars) } == [Array(nfd.unicodeScalars), Array("👨\u{200D}👩\u{200D}👧".unicodeScalars),
                                                           Array("\u{A0}공백\u{A0}".unicodeScalars)])
    }

    @Test("★ 경계 — 항목 50,000개·글 12,000바이트는 받는다(50,001·12,001은 적대 표 T01·T02)")
    func boundaries() throws {
        var fixture = XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" t="s"><v>49999</v></c><c r="B1" t="s"><v>0</v></c></row>"#)],
                                  sharedStrings: F.sst([#"<t>\#(String(repeating: "가", count: 4_000))</t>"#] + (1..<50_000).map { "<t>\($0)</t>" }))
        fixture.method = 0
        let row = try #require(try table(fixture).row(1))
        #expect(row.cells == [.text("49999"), .text(String(repeating: "가", count: 4_000))])
    }
}

@Suite("외부 채움글 1-e ② — 행·열·병합·숨김 (6-4·6-5b)")
struct XLSXGridTests {

    @Test("★ 병합 — 범위와 겹치는 행은 선두·비선두 모두 표시, 범위 밖 행은 아니다. 값은 그대로 둔다(우선순위는 판정 경로 몫)")
    func mergedRows() throws {
        let rows = (1...6).map { #"<row r="\#($0)"><c r="A\#($0)"><v>\#($0)</v></c><c r="C\#($0)" t="s"><v>0</v></c></row>"# }.joined()
        let result = try table(workbook(rows, after: #"<mergeCells count="2"><mergeCell ref="A2:B3"/><mergeCell ref="Z5"/></mergeCells>"#))
        #expect(result.rows.map(\.isMerged) == [false, true, true, false, true, false])
        #expect(result.rows[1].cells == [.number("2"), .blank, .text("글")])
    }

    @Test("병합 참조가 거꾸로(B3:A2) 적혀도 같은 범위")
    func reversedMerge() throws {
        let rows = (1...3).map { #"<row r="\#($0)"><c r="A\#($0)"><v>\#($0)</v></c></row>"# }.joined()
        let result = try table(workbook(rows, after: #"<mergeCells><mergeCell ref="B3:A2"/></mergeCells>"#))
        #expect(result.rows.map(\.isMerged) == [false, true, true])
    }

    @Test("★ 숨김 행(1·true)·숨김 열(<cols> — 상한 칸까지만)은 읽되 표시만 한다(「숨김 N」)")
    func hiddenRowsAndColumns() throws {
        let rows = #"<row r="1" hidden="1"><c r="A1" t="s"><v>0</v></c></row><row r="2" hidden="true"><c r="A2" t="s"><v>0</v></c></row>"#
            + #"<row r="3" hidden="0"><c r="A3" t="s"><v>0</v></c></row><row r="4" hidden="1"/>"#
        let cols = #"<cols><col min="2" max="2" width="20" customWidth="1" hidden="1"/><col min="4" max="16384" hidden="true"/><col min="3" max="3" width="9"/></cols>"#
        let result = try table(workbook(rows, before: cols))
        #expect(result.rows.map(\.isHidden) == [true, true, false])
        #expect(result.rows.map(\.number) == [1, 2, 3])
        #expect(result.hiddenColumns == [1] + Array(3..<RawTable.columnLimit))
    }

    @Test("열 너비 자동 맞춤(<col width customWidth>)은 결과에 영향이 없다(④ 샘플 재제작 대비)")
    func columnWidthsIgnored() throws {
        let rows = #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#
        let plain = try table(workbook(rows))
        let widths = try table(workbook(rows, before: #"<cols><col min="1" max="3" width="41.5" bestFit="1" customWidth="1"/></cols>"#))
        #expect(plain == widths)
    }

    @Test("★ 열 상한 — 13번째 칸(메타 12칸 + 1) 밖의 비지 않은 셀은 그 칸 하나로 접는다(먼저 온 것), 빈 셀은 무시")
    func columnFolding() throws {
        let rows = #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="Z1" s="0"/><c r="AA1"><v>5</v></c><c r="XFD1" t="b"><v>1</v></c></row>"#
            + #"<row r="2"><c r="M2"><v>1</v></c><c r="N2"><v>2</v></c></row><row r="3"><c r="A3" t="s"><v>0</v></c><c r="XFD3" s="0"/></row>"#
        let result = try table(workbook(rows))
        #expect(RawTable.columnLimit == 13)
        #expect(result.rows[0].cells == [.text("글")] + Array(repeating: .blank, count: 11) + [.number("5")])
        #expect(result.rows[1].cells == Array(repeating: .blank, count: 12) + [.number("1")])
        #expect(result.rows[2].cells == [.text("글")])
    }

    @Test("★ r 속성이 없으면 직전 다음 자리(행·셀 모두), 있는 것과 섞여도 된다")
    func implicitReferences() throws {
        let rows = #"<row><c t="s"><v>0</v></c><c><v>2</v></c></row><row r="3"><c r="B3"><v>3</v></c><c><v>4</v></c></row><row><c><v>5</v></c></row>"#
        let result = try table(workbook(rows))
        #expect(result.rows.map(\.number) == [1, 3, 4])
        #expect(result.rows.map(\.cells) == [[.text("글"), .number("2")], [.blank, .number("3"), .number("4")], [.number("5")]])
    }

    @Test("★ 경계 — 스캔 행 20,000·셀 100,000·깊이 32는 받는다(넘침은 적대 표 G01·G02·N01)")
    func limitsBoundary() throws {
        let rowsOnly = String(repeating: "<row/>", count: 19_999) + #"<row><c t="s"><v>0</v></c></row>"#
        var fixture = workbook(rowsOnly)
        fixture.method = 0
        #expect(try table(fixture).rows.map(\.number) == [20_000])

        let cells = String(repeating: "<row>" + String(repeating: "<c/>", count: 10) + "</row>", count: 9_999)
            + "<row>" + String(repeating: "<c/>", count: 9) + #"<c t="s"><v>0</v></c></row>"#
        fixture = workbook(cells)
        fixture.method = 0
        #expect(try table(fixture).rows.map(\.number) == [10_000])

        let deep = "<extLst>" + String(repeating: "<x>", count: 30) + String(repeating: "</x>", count: 30) + "</extLst>"
        #expect(try table(workbook(#"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#, after: deep)).rows.count == 1)
    }

    @Test("모르는 요소는 하위 트리째 건너뛴다 — mc:AlternateContent·extLst·sheetPr·dimension·drawing")
    func unknownElementsSkipped() throws {
        let before = #"<sheetPr><outlinePr summaryBelow="0"/></sheetPr><dimension ref="A1:C3"/>"#
            + #"<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:Choice Requires="x14"><sheetData><row r="5"><c r="A5"><v>9</v></c></row></sheetData></mc:Choice></mc:AlternateContent>"#
        let result = try table(workbook(#"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><extLst><ext/></extLst><v>1</v></c></row>"#,
                                        before: before, after: #"<drawing r:id="rId1"/><extLst><ext uri="x"/></extLst>"#))
        #expect(result.rows.map(\.number) == [1])
        #expect(result.rows[0].cells == [.text("글"), .number("1")])
    }

    @Test("요소 접두가 달라도 네임스페이스가 본문이면 읽는다(x:row) · 엄격(Strict) OOXML 네임스페이스도 받는다")
    func prefixedAndStrict() throws {
        var fixture = workbook("")
        fixture.sheets[0].xml = F.declaration + #"<x:worksheet xmlns:x="\#(F.mainNS)"><x:sheetData><x:row r="1"><x:c r="A1" t="s"><x:v>0</x:v></x:c></x:row></x:sheetData></x:worksheet>"#
        #expect(try table(fixture).rows.map(\.cells) == [[.text("글")]])

        fixture = workbook("")
        fixture.sheets[0].xml = F.worksheet(rows: #"<row r="2"><c r="A2" t="s"><v>0</v></c></row>"#, namespace: F.strictMainNS)
        fixture.sharedStrings = F.plainSST(["글"]).replacingOccurrences(of: F.mainNS, with: F.strictMainNS)
        #expect(try table(fixture).rows.map(\.cells) == [[.text("글")]])
    }
}

@Suite("외부 채움글 1-e ② — 워크북·시트 목록 (6-4 「여러 시트」·AC-36·6-5b)")
struct XLSXWorkbookListTests {

    @Test("★ 숨김 시트 제외 — state 생략·visible은 표시, hidden·veryHidden은 목록에 없다, 차트 시트도 없다. 순서는 워크북 순서")
    func visibleSheets() throws {
        var chart = F.sheet("차트", index: 5)
        chart.relType = F.relType + "chartsheet"
        let fixture = XLSXFixture(sheets: [
            F.sheet("셋", rows: #"<row r="1"><c r="A1"><v>3</v></c></row>"#, index: 3),
            F.sheet("숨김", state: "hidden", index: 1),
            F.sheet("하나", rows: #"<row r="2"><c r="A2"><v>1</v></c></row>"#, state: "visible", index: 2),
            F.sheet("아주 숨김", state: "veryHidden", index: 4),
            chart,
        ])
        var reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(reader.sheets.map(\.name) == ["셋", "하나"])
        #expect(try reader.table(for: reader.sheets[1]).rows.map(\.number) == [2])
        #expect(try reader.table(for: reader.sheets[0]).rows.map(\.number) == [1])
    }

    @Test("★ 관계 id를 가정하지 않는다(구글 rId5) · 절대 경로·./ 대상 · 루트에 있는 워크북")
    func relationshipVariants() throws {
        var fixture = XLSXFixture.singleText()
        fixture.sheets[0].relID = "rId5"
        #expect(try table(fixture).rows.count == 1)

        fixture = XLSXFixture.singleText()
        fixture.sheets[0].target = "/xl/worksheets/sheet1.xml"
        #expect(try table(fixture).rows.count == 1)

        fixture = XLSXFixture.singleText()
        fixture.sheets[0].target = "./worksheets/sheet1.xml"
        #expect(try table(fixture).rows.count == 1)

        fixture = XLSXFixture.singleText()
        fixture.workbookPath = "workbook.xml"
        fixture.sheets[0].target = "xl/worksheets/sheet1.xml"
        fixture.workbookRels = fixture.defaultWorkbookRels.replacingOccurrences(of: #"Target="sharedStrings.xml""#, with: #"Target="xl/sharedStrings.xml""#)
        #expect(try table(fixture).rows.count == 1)
    }

    @Test("엑셀 워크북의 mc:AlternateContent(x15ac:absPath — 저장 경로)는 읽지 않고 건너뛴다")
    func absPathSkipped() throws {
        var fixture = XLSXFixture.singleText()
        fixture.workbook = fixture.defaultWorkbook.replacingOccurrences(of: "<sheets>", with:
            #"<mc:AlternateContent xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"><mc:Choice Requires="x15"><x15ac:absPath url="/Users/someone/" xmlns:x15ac="http://schemas.microsoft.com/office/spreadsheetml/2010/11/ac"/></mc:Choice></mc:AlternateContent><sheets>"#)
        let reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(reader.sheets.map(\.name) == ["문구"])
        #expect(!String(reflecting: reader.sheets).contains("someone"))
    }

    @Test("서식 파일(.xltx) 본문 타입·Default 확장자로만 정한 본문 타입도 받는다")
    func contentTypeVariants() throws {
        var fixture = XLSXFixture.singleText()
        fixture.workbookContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml"
        #expect(try table(fixture).rows.count == 1)

        fixture = XLSXFixture.singleText()
        fixture.contentTypes = F.declaration + #"<Types xmlns="\#(F.contentTypesNS)"><Default Extension="xml" ContentType="\#(F.mainContentType)"/></Types>"#
        #expect(try table(fixture).rows.count == 1)
    }

    @Test("★ 시트 이름 → 팩 이름 기본값 — Sheet1·Sheet N·시트1·시트 N 꼴과 빈 이름은 비워 둔다(6-4). 목록 이름과 같은 정리(게이트 준비 ⓐⓒ)를 거친다", arguments: [
        ("Sheet1", nil), ("Sheet 2", nil), ("sheet12", nil), ("SHEET3", nil), ("시트1", nil), ("시트 2", nil), ("  Sheet1  ", nil), ("   ", nil),
        ("사자성어", "사자성어"), ("Sheet1 복사본", "Sheet1 복사본"), ("시트", "시트"), ("Sheet", "Sheet"), ("  업무 상용구 ", "업무 상용구"),
        ("Sheet_1", "Sheet_1"), ("Sheet1a", "Sheet1a"),
        // 게이트 준비 — 문자 정리 뒤 빈 이름·보이는 글자 없음은 비움(ⓐ), 줄바꿈·탭·공백 묶음은 공백 하나(ⓒ — 그 뒤에 기본 이름 꼴을 본다)
        ("\u{200B}", nil), ("\u{3164}", nil), ("Sheet\u{200B}1", nil), ("시트\n2", nil), ("Sheet\t\t3", nil),
        ("가\n나", "가 나"), ("업무\r\n\n상용구", "업무 상용구"), ("인사\u{200B}말", "인사말"),
        // 사용자가 직접 쓴 「(2)」는 이름이다 — 목록의 구별 표시 「 (k)」는 이 함수를 지나지 않는다
        ("가 (2)", "가 (2)"),
        // 이름 상한(`PackLimits.name`)은 정리 **뒤** 길이로 — 줄바꿈 묶음이 공백 하나가 되어 상한 안이면 받는다
        (String(repeating: "가", count: PackLimits.name.characters + 1), nil),
        (String(repeating: "가", count: PackLimits.name.characters - 2) + "\n\n\n가", String(repeating: "가", count: PackLimits.name.characters - 2) + " 가"),
    ] as [(String, String?)])
    func packNameSuggestion(_ name: String, expected: String?) {
        #expect(XLSXWorkbookReader.Sheet.suggestedPackName(forSheetName: name) == expected)
    }

    @Test("시트 이름의 _xHHHH_도 푼다(ST_Xstring)")
    func sheetNameEscapes() throws {
        var fixture = XLSXFixture.singleText()
        fixture.sheets[0].name = "업무_x005F_목록"
        let reader = try XLSXWorkbookReader.open(fixture.build())
        #expect(reader.sheets.map(\.name) == ["업무_목록"])
    }

    @Test("XML 선언·BOM 없는 파트도 UTF-8로 읽는다")
    func noDeclaration() throws {
        var fixture = XLSXFixture.singleText()
        fixture.sheets[0].xml = #"<worksheet xmlns="\#(F.mainNS)"><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData></worksheet>"#
        #expect(try table(fixture).rows.map(\.cells) == [[.text("회의시작")]])
    }

    @Test("공유 문자열·스타일 파트가 없어도(글 셀 없음) 읽는다")
    func optionalParts() throws {
        let fixture = XLSXFixture(sheets: [F.sheet(rows: #"<row r="1"><c r="A1" s="0"><v>1</v></c><c r="B1" t="inlineStr"><is><t>인라인</t></is></c></row>"#)])
        #expect(try table(fixture).rows.map(\.cells) == [[.number("1"), .text("인라인")]])
    }
}

/// 0부터 센 열 → 열 문자(A, B, … Z, AA)
func columnName(_ index: Int) -> String {
    var number = index + 1
    var name = ""
    while number > 0 {
        let remainder = (number - 1) % 26
        name = String(UnicodeScalar(UInt8(65 + remainder))) + name
        number = (number - 1) / 26
    }
    return name
}
