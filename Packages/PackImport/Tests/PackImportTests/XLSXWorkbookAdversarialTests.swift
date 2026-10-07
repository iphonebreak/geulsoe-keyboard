import Foundation
import Testing
@testable import PackImport

// 외부 채움글 1-e ② — **적대 XML fixture 표**(PDR AC-30 XML 층, 6-5 「XML」 표·6-5b). ①의 컨테이너 표(`ArchiveCase`, 83건)와
// 합쳐 AC-30 한 표가 된다. 전부 테스트 안에서 짓는다(`XLSXFixture` → ①의 `ZipSpec`).
// 기대값은 「열기에서 거부」 / 「표 읽기에서 거부」 / 「제한된 채로 읽힘(행 번호)」 셋 중 하나다.

struct WorkbookCase: Sendable, CustomTestStringConvertible {

    enum Expectation: Sendable {
        /// `XLSXWorkbookReader.open`이 이 이유로 거부한다
        case openFails(XLSXWorkbookFailure)
        /// 열기는 되고, 첫 표시 시트의 표 읽기가 이 이유로 거부된다
        case tableFails(XLSXWorkbookFailure)
        /// 열기·표 읽기가 되고 비지 않은 행 번호가 이것이다(거짓 선언·모르는 요소에 휘둘리지 않음)
        case tableRows([Int])
    }

    let id: String
    let title: String
    var limits: XLSXWorkbookLimits = .product
    let build: @Sendable () -> Data
    let expect: Expectation

    var testDescription: String { "\(id) \(title)" }
}

// MARK: - 표

extension WorkbookCase {

    typealias F = XLSXFixture

    /// 글 한 칸짜리 기본 워크북을 고쳐 짓는다
    static func fixture(_ adjust: @escaping @Sendable (inout XLSXFixture) -> Void) -> @Sendable () -> Data {
        {
            var fixture = XLSXFixture.singleText()
            adjust(&fixture)
            return fixture.build()
        }
    }

    /// 시트 글만 바꾼다(공유 문자열 `회의시작` 하나는 그대로)
    static func sheet(_ rows: String, before: String = "", after: String = "", stored: Bool = false) -> @Sendable () -> Data {
        fixture { fixture in
            fixture.sheets[0].xml = F.worksheet(rows: rows, before: before, after: after)
            if stored { fixture.method = 0 }
        }
    }

    /// 다 지은 엔트리 하나의 바이트를 통째로 바꾼다(인코딩 시험)
    static func rawPart(_ name: String, _ bytes: [UInt8]) -> @Sendable () -> Data {
        {
            var entries = XLSXFixture.singleText().entries()
            entries[ZipFixture.index(of: name, in: entries)].content = bytes
            return ZipSpec(entries).build()
        }
    }

    static func nested(_ depth: Int, element: String = "x") -> String {
        String(repeating: "<\(element)>", count: depth) + String(repeating: "</\(element)>", count: depth)
    }

    static let a1 = #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#
    static let billionLaughs = #"<!DOCTYPE sst [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;"><!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]>"#

    static let all: [WorkbookCase] = declarations + structure + contentTypes + relationships + sheetList + strings + styleCases + grid

    // DOCTYPE·ENTITY·인코딩 — 사전 바이트 스캔(6-5)
    static let declarations: [WorkbookCase] = [
        WorkbookCase(id: "D01", title: "시트에 <!DOCTYPE>", build: fixture {
            $0.sheets[0].xml = F.declaration + #"<!DOCTYPE worksheet><worksheet xmlns="\#(F.mainNS)"><sheetData>\#(a1)</sheetData></worksheet>"#
        }, expect: .tableFails(.doctypeOrEntity)),
        WorkbookCase(id: "D02", title: "공유 문자열에 엔티티 폭탄(billion laughs)", build: fixture {
            $0.sharedStrings = F.declaration + billionLaughs + #"<sst xmlns="\#(F.mainNS)"><si><t>&c;</t></si></sst>"#
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D03", title: "워크북에 외부 엔티티(SYSTEM file:)", build: fixture {
            $0.workbook = F.declaration + #"<!DOCTYPE workbook [<!ENTITY x SYSTEM "file:///etc/hosts">]><workbook xmlns="\#(F.mainNS)" xmlns:r="\#(F.officeRelNS)"><sheets><sheet name="&x;" sheetId="1" r:id="rId1"/></sheets></workbook>"#
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D04", title: "스타일에 <!DOCTYPE>", build: fixture {
            $0.styles = F.declaration + "<!DOCTYPE styleSheet>" + #"<styleSheet xmlns="\#(F.mainNS)"/>"#
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D05", title: "[Content_Types].xml에 <!DOCTYPE>", build: fixture {
            $0.contentTypes = $0.defaultContentTypes.replacingOccurrences(of: "<Types ", with: "<!DOCTYPE Types><Types ")
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D06", title: "_rels/.rels에 <!ENTITY>", build: fixture {
            $0.rootRels = $0.defaultRootRels.replacingOccurrences(of: "<Relationships ", with: #"<!DOCTYPE Relationships [<!ENTITY t "xl/workbook.xml">]><Relationships "#)
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D07", title: "워크북 관계에 <!DOCTYPE>", build: fixture {
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(of: "<Relationships ", with: "<!DOCTYPE Relationships><Relationships ")
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "D08", title: "소문자 <!doctype — 대소문자 무시 스캔", build: fixture {
            $0.sheets[0].xml = F.declaration + #"<!doctype worksheet><worksheet xmlns="\#(F.mainNS)"><sheetData/></worksheet>"#
        }, expect: .tableFails(.doctypeOrEntity)),
        WorkbookCase(id: "D09", title: "본문 사이에 홀로 선 <!ENTITY", build: sheet(a1, after: #"<!ENTITY x "y">"#),
                     expect: .tableFails(.doctypeOrEntity)),
        WorkbookCase(id: "D10", title: "선언 인코딩 UTF-16", build: fixture {
            $0.sheets[0].xml = $0.sheets[0].xml.replacingOccurrences(of: #"encoding="UTF-8""#, with: #"encoding="UTF-16""#)
        }, expect: .tableFails(.unsupportedTextEncoding)),
        WorkbookCase(id: "D11", title: "UTF-16LE(BOM) 바이트 시트 — 바이트 스캔을 비켜 가는 DOCTYPE", build: rawPart(
            "xl/worksheets/sheet1.xml",
            [0xFF, 0xFE] + Array(#"<!DOCTYPE worksheet><worksheet xmlns="\#(F.mainNS)"><sheetData/></worksheet>"#.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
        ), expect: .tableFails(.unsupportedTextEncoding)),
        WorkbookCase(id: "D12", title: "공유 문자열 안 NUL 바이트", build: rawPart(
            "xl/sharedStrings.xml", Array(F.plainSST(["회의"]).utf8) + [0x00]
        ), expect: .openFails(.unsupportedTextEncoding)),
        WorkbookCase(id: "D13", title: "선언 인코딩 ISO-8859-1(워크북)", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: #"encoding="UTF-8""#, with: #"encoding="ISO-8859-1""#)
        }, expect: .openFails(.unsupportedTextEncoding)),
        WorkbookCase(id: "D14", title: "UTF-8 BOM + 소문자 작은따옴표 선언은 받는다", build: rawPart(
            "xl/worksheets/sheet1.xml",
            [0xEF, 0xBB, 0xBF] + Array((#"<?xml version='1.0' encoding='utf-8'?>"# + #"<worksheet xmlns="\#(F.mainNS)"><sheetData>\#(a1)</sheetData></worksheet>"#).utf8)
        ), expect: .tableRows([1])),
        WorkbookCase(id: "D15", title: "EBCDIC 바이트(첫 글자가 ASCII <가 아님)", build: rawPart(
            "xl/worksheets/sheet1.xml", [0x4C, 0x6F, 0xA7, 0x94, 0x93, 0x40] + Array(#"<worksheet xmlns="\#(F.mainNS)"/>"#.utf8)
        ), expect: .tableFails(.unsupportedTextEncoding)),
        WorkbookCase(id: "D17", title: "UTF-8 선언인데 깨진 바이트(0xFF)", build: rawPart(
            "xl/sharedStrings.xml", Array(F.plainSST(["회의"]).utf8.prefix(120)) + [0xFF, 0xFE] + Array(F.plainSST(["회의"]).utf8.dropFirst(120))
        ), expect: .openFails(.malformedXML)),
        WorkbookCase(id: "D16", title: "선언 없는 문서 앞 공백은 받는다(XML 허용)", build: rawPart(
            "xl/worksheets/sheet1.xml", Array(("\n  " + #"<worksheet xmlns="\#(F.mainNS)"><sheetData>\#(a1)</sheetData></worksheet>"#).utf8)
        ), expect: .tableRows([1])),
    ]

    // 깊이·거대 속성·깨진 XML
    static let structure: [WorkbookCase] = [
        WorkbookCase(id: "N01", title: "시트 깊이 33(모르는 요소 안이라도 센다)", build: sheet(a1, after: "<extLst>" + nested(31) + "</extLst>"),
                     expect: .tableFails(.nestingTooDeep)),
        WorkbookCase(id: "N02", title: "공유 문자열 깊이 33", build: fixture {
            $0.sharedStrings = F.sst(["<t>회의시작</t>" + nested(31)])
        }, expect: .openFails(.nestingTooDeep)),
        WorkbookCase(id: "N03", title: "워크북 깊이 33(모르는 요소 안)", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: "<sheets>", with: "<extLst>" + nested(31) + "</extLst><sheets>")
        }, expect: .openFails(.nestingTooDeep)),
        WorkbookCase(id: "N04", title: "깊이 10,000(파서 자체 한도 전에 우리 상한)", build: sheet(a1, after: "<extLst>" + nested(10_000) + "</extLst>", stored: true),
                     expect: .tableFails(.nestingTooDeep)),
        WorkbookCase(id: "N05", title: "거대 속성 — 셀 참조 1MB", build: sheet(
            #"<row r="1"><c r="\#(String(repeating: "A", count: 1_000_000))1" t="s"><v>0</v></c></row>"#, stored: true
        ), expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "N06", title: "거대 속성 — 모르는 요소의 2MB 속성은 건너뛴다", build: sheet(
            a1, before: #"<sheetPr codeName="\#(String(repeating: "가", count: 700_000))"/>"#, stored: true
        ), expect: .tableRows([1])),
        WorkbookCase(id: "N07", title: "시트 이름 256바이트", build: fixture { $0.sheets[0].name = String(repeating: "a", count: 256) },
                     expect: .openFails(.malformedPart)),
        WorkbookCase(id: "N08", title: "닫히지 않은 태그", build: fixture {
            $0.sheets[0].xml = F.declaration + #"<worksheet xmlns="\#(F.mainNS)"><sheetData><row r="1">"#
        }, expect: .tableFails(.malformedXML)),
        WorkbookCase(id: "N09", title: "정의되지 않은 엔티티 &foo; — 파서가 해석을 물어 오면 대리자가 막는다", build: fixture {
            $0.sharedStrings = F.sst(["<t>&foo;</t>"])
        }, expect: .openFails(.doctypeOrEntity)),
        WorkbookCase(id: "N10", title: "루트 뒤 두 번째 루트", build: fixture {
            $0.sheets[0].xml = F.worksheet(rows: a1) + #"<worksheet xmlns="\#(F.mainNS)"/>"#
        }, expect: .tableFails(.malformedXML)),
        WorkbookCase(id: "N11", title: "시트 루트가 다른 네임스페이스", build: fixture {
            $0.sheets[0].xml = F.worksheet(rows: a1, namespace: "urn:evil")
        }, expect: .tableFails(.unexpectedPart)),
    ]

    // 콘텐츠 타입·매크로(6-4 「그림·차트·매크로」)
    static let contentTypes: [WorkbookCase] = [
        WorkbookCase(id: "C01", title: "매크로 포함 워크북(.xlsm)", build: fixture {
            $0.workbookContentType = "application/vnd.ms-excel.sheet.macroEnabled.main+xml"
        }, expect: .openFails(.macroEnabled)),
        WorkbookCase(id: "C02", title: "매크로 서식 파일(.xltm)", build: fixture {
            $0.workbookContentType = "application/vnd.ms-excel.template.macroEnabled.main+xml"
        }, expect: .openFails(.macroEnabled)),
        WorkbookCase(id: "C03", title: "워드 문서(.docx) 본문 타입", build: fixture {
            $0.workbookContentType = "application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "C04", title: "워크북 Override 없음(기본 xml 타입)", build: fixture {
            $0.contentTypes = F.declaration + #"<Types xmlns="\#(F.contentTypesNS)"><Default Extension="xml" ContentType="application/xml"/></Types>"#
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "C05", title: "[Content_Types].xml 없음", build: {
            var entries = XLSXFixture.singleText().entries()
            entries.removeFirst()
            return ZipSpec(entries).build()
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "C06", title: "XLM 매크로 시트 관계", build: fixture { $0.sheets[0].relType = F.relType + "xlMacrosheet" },
                     expect: .openFails(.macroEnabled)),
        WorkbookCase(id: "C07", title: "PartName 대소문자만 다른 매크로 Override(OPC는 대소문자 무시)", build: fixture {
            $0.contentTypes = F.declaration + #"<Types xmlns="\#(F.contentTypesNS)"><Default Extension="xml" ContentType="application/xml"/><Override PartName="/XL/Workbook.xml" ContentType="application/vnd.ms-excel.sheet.macroEnabled.main+xml"/></Types>"#
        }, expect: .openFails(.macroEnabled)),
        WorkbookCase(id: "C08", title: "바이너리 워크북(.xlsb) 타입", build: fixture {
            $0.workbookContentType = "application/vnd.ms-excel.sheet.binary.macroEnabled.main"
        }, expect: .openFails(.macroEnabled)),
        WorkbookCase(id: "C09", title: "같은 PartName Override 둘(대소문자만 다름) — 타입이 모호", build: fixture {
            $0.contentTypes = $0.defaultContentTypes.replacingOccurrences(
                of: "</Types>", with: #"<Override PartName="/xl/Workbook.XML" ContentType="application/vnd.ms-excel.sheet.macroEnabled.main+xml"/></Types>"#)
        }, expect: .openFails(.malformedPart)),
    ]

    // 관계(rels) — 경로·순환·모호성
    static let relationships: [WorkbookCase] = [
        WorkbookCase(id: "R01", title: "officeDocument 관계 없음", build: fixture {
            $0.rootRels = F.declaration + #"<Relationships xmlns="\#(F.packageRelNS)"/>"#
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "R02", title: "officeDocument 관계 둘", build: fixture {
            $0.rootRels = F.declaration + #"<Relationships xmlns="\#(F.packageRelNS)"><Relationship Id="rId1" Type="\#(F.relType)officeDocument" Target="xl/workbook.xml"/><Relationship Id="rId2" Type="\#(F.relType)officeDocument" Target="xl/workbook.xml"/></Relationships>"#
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R03", title: "_rels/.rels 없음", build: {
            var entries = XLSXFixture.singleText().entries()
            entries.remove(at: 1)
            return ZipSpec(entries).build()
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "R04", title: "워크북 대상 ../xl/workbook.xml", build: fixture {
            $0.rootRels = $0.defaultRootRels.replacingOccurrences(of: #"Target="xl/workbook.xml""#, with: #"Target="../xl/workbook.xml""#)
        }, expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R05", title: "시트 대상 ../worksheets/sheet1.xml", build: fixture { $0.sheets[0].target = "../worksheets/sheet1.xml" },
                     expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R06", title: "시트 대상 /xl/../xl/worksheets/sheet1.xml", build: fixture {
            $0.sheets[0].target = "/xl/../xl/worksheets/sheet1.xml"
        }, expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R07", title: "시트 관계 TargetMode=External", build: fixture {
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(of: #"Target="worksheets/sheet1.xml""#,
                                                                         with: #"Target="worksheets/sheet1.xml" TargetMode="External""#)
        }, expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R08", title: "시트 대상에 역슬래시", build: fixture { $0.sheets[0].target = #"worksheets\sheet1.xml"# },
                     expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R09", title: "시트 대상이 URL(스킴)", build: fixture { $0.sheets[0].target = "http://example.com/sheet1.xml" },
                     expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R10", title: "<sheet r:id>가 관계에 없음", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: #"r:id="rId1""#, with: #"r:id="rId9""#)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R11", title: "워크북 관계 Id 중복", build: fixture {
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(of: #"Id="rIdS""#, with: #"Id="rId1""#)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R12", title: "두 시트가 같은 파트", build: fixture {
            var second = F.sheet("둘", index: 2)
            second.target = "worksheets/sheet1.xml"
            second.part = "xl/worksheets/sheet1.xml"
            $0.sheets.append(second)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R13", title: "시트 대상 파트가 아카이브에 없음", build: fixture { $0.sheets[0].target = "worksheets/sheet9.xml" },
                     expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R14", title: "워크북 관계 파트 없음", build: {
            var entries = XLSXFixture.singleText().entries()
            entries.remove(at: 3)
            return ZipSpec(entries).build()
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R15", title: "<sheet>에 r:id 없음", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: #" r:id="rId1""#, with: "")
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R16", title: "순환 — officeDocument가 _rels/.rels 자신(콘텐츠 타입도 본문이라 속임)", build: fixture {
            $0.rootRels = $0.defaultRootRels.replacingOccurrences(of: #"Target="xl/workbook.xml""#, with: #"Target="_rels/.rels""#)
            $0.contentTypes = $0.defaultContentTypes.replacingOccurrences(of: #"PartName="/xl/workbook.xml""#, with: #"PartName="/_rels/.rels""#)
        }, expect: .openFails(.unexpectedPart)),
        WorkbookCase(id: "R25", title: "순환 — officeDocument가 _rels/.rels 자신(콘텐츠 타입은 관계)", build: fixture {
            $0.rootRels = $0.defaultRootRels.replacingOccurrences(of: #"Target="xl/workbook.xml""#, with: #"Target="_rels/.rels""#)
        }, expect: .openFails(.notSpreadsheet)),
        WorkbookCase(id: "R17", title: "순환 — 시트 대상이 workbook.xml", build: fixture { $0.sheets[0].target = "workbook.xml"; $0.sheets[0].part = "xl/workbook.xml" },
                     expect: .tableFails(.unexpectedPart)),
        WorkbookCase(id: "R18", title: "순환 — 시트 대상이 워크북 관계 파트", build: fixture {
            $0.sheets[0].target = "_rels/workbook.xml.rels"
            $0.sheets[0].part = "xl/_rels/workbook.xml.rels"
        }, expect: .tableFails(.unexpectedPart)),
        WorkbookCase(id: "R19", title: "순환 — 공유 문자열 대상이 시트", build: fixture {
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(of: #"Target="sharedStrings.xml""#, with: #"Target="worksheets/sheet1.xml""#)
        }, expect: .openFails(.unexpectedPart)),
        WorkbookCase(id: "R20", title: "순환 — 스타일 대상이 workbook.xml", build: fixture {
            $0.styles = F.stylesXML()
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(of: #"Target="styles.xml""#, with: #"Target="workbook.xml""#)
        }, expect: .openFails(.unexpectedPart)),
        WorkbookCase(id: "R21", title: "공유 문자열 관계 둘", build: fixture {
            $0.workbookRels = $0.defaultWorkbookRels.replacingOccurrences(
                of: "</Relationships>", with: #"<Relationship Id="rIdS2" Type="\#(F.relType)sharedStrings" Target="sharedStrings.xml"/></Relationships>"#)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R22", title: "빈 대상", build: fixture { $0.sheets[0].target = "" }, expect: .openFails(.unsafeRelationshipTarget)),
        WorkbookCase(id: "R23", title: "워크북 파트가 아카이브에 없음", build: fixture {
            $0.rootRels = $0.defaultRootRels.replacingOccurrences(of: #"Target="xl/workbook.xml""#, with: #"Target="xl/book.xml""#)
            $0.contentTypes = $0.defaultContentTypes.replacingOccurrences(of: "/xl/workbook.xml", with: "/xl/book.xml")
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R24", title: "r: 접두가 관계 네임스페이스가 아님 — 접두 글자가 아니라 네임스페이스로 찾는다", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: #"xmlns:r="\#(F.officeRelNS)""#, with: #"xmlns:r="urn:evil""#)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R27", title: "관계 id 속성 둘(과도기·엄격 관계 네임스페이스) — 어느 쪽인지 모호", build: fixture {
            $0.workbook = $0.defaultWorkbook
                .replacingOccurrences(of: "<workbook ", with: #"<workbook xmlns:s="http://purl.oclc.org/ooxml/officeDocument/relationships" "#)
                .replacingOccurrences(of: #"r:id="rId1""#, with: #"r:id="rId1" s:id="rIdS""#)
        }, expect: .openFails(.brokenRelationship)),
        WorkbookCase(id: "R26", title: "다른 접두(o:)라도 관계 네임스페이스면 받는다", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: #"xmlns:r="\#(F.officeRelNS)""#, with: #"xmlns:o="\#(F.officeRelNS)""#)
                .replacingOccurrences(of: #"r:id="rId1""#, with: #"o:id="rId1""#)
        }, expect: .tableRows([1])),
    ]

    // 시트 목록(6-4 「여러 시트」·AC-36)
    static let sheetList: [WorkbookCase] = [
        WorkbookCase(id: "S01", title: "모든 시트가 숨김(hidden·veryHidden)", build: fixture {
            $0.sheets[0].state = "hidden"
            $0.sheets.append(F.sheet("둘", rows: a1, state: "veryHidden", index: 2))
        }, expect: .openFails(.noVisibleSheet)),
        WorkbookCase(id: "S02", title: "모르는 state 값", build: fixture { $0.sheets[0].state = "secret" },
                     expect: .openFails(.malformedPart)),
        WorkbookCase(id: "S03", title: "차트 시트뿐", build: fixture { $0.sheets[0].relType = F.relType + "chartsheet" },
                     expect: .openFails(.noVisibleSheet)),
        WorkbookCase(id: "S04", title: "<sheets> 두 번", build: fixture {
            $0.workbook = $0.defaultWorkbook.replacingOccurrences(of: "</sheets>", with: "</sheets><sheets/>")
        }, expect: .openFails(.malformedPart)),
        WorkbookCase(id: "S05", title: "<sheets> 없음", build: fixture {
            $0.workbook = F.declaration + #"<workbook xmlns="\#(F.mainNS)"/>"#
        }, expect: .openFails(.noVisibleSheet)),
        WorkbookCase(id: "S06", title: "빈 시트 이름", build: fixture { $0.sheets[0].name = "" }, expect: .openFails(.malformedPart)),
    ]

    // 공유 문자열·글 상한(6-5 「sharedStrings」)
    static let strings: [WorkbookCase] = [
        WorkbookCase(id: "T01", title: "공유 문자열 항목 50,001개", build: fixture {
            $0.sharedStrings = F.sst((0...50_000).map { "<t>\($0)</t>" })
        }, expect: .openFails(.tooManySharedStrings)),
        WorkbookCase(id: "T02", title: "공유 문자열 하나 12,001바이트(본문 상한 초과)", build: fixture {
            $0.sharedStrings = F.plainSST([String(repeating: "a", count: 12_001)])
            $0.method = 0
        }, expect: .openFails(.textTooLong)),
        WorkbookCase(id: "T03", title: "인라인 문자열 12,001바이트", build: sheet(
            #"<row r="1"><c r="A1" t="inlineStr"><is><t>\#(String(repeating: "가", count: 4_000))</t><r><t>bb</t></r></is></c></row>"#, stored: true
        ), expect: .tableFails(.textTooLong)),
        WorkbookCase(id: "T04", title: "공유 문자열 색인 == 항목 수", build: sheet(#"<row r="1"><c r="A1" t="s"><v>1</v></c></row>"#),
                     expect: .tableFails(.invalidSharedStringIndex)),
        WorkbookCase(id: "T05", title: "공유 문자열 색인 -1", build: sheet(#"<row r="1"><c r="A1" t="s"><v>-1</v></c></row>"#),
                     expect: .tableFails(.invalidSharedStringIndex)),
        WorkbookCase(id: "T06", title: "공유 문자열 색인 1a", build: sheet(#"<row r="1"><c r="A1" t="s"><v>1a</v></c></row>"#),
                     expect: .tableFails(.invalidSharedStringIndex)),
        WorkbookCase(id: "T07", title: "공유 문자열 색인 넘침(20자리)", build: sheet(#"<row r="1"><c r="A1" t="s"><v>99999999999999999999</v></c></row>"#),
                     expect: .tableFails(.invalidSharedStringIndex)),
        WorkbookCase(id: "T08", title: "공유 문자열 파트 없이 t=\"s\"", build: fixture { $0.sharedStrings = nil },
                     expect: .tableFails(.invalidSharedStringIndex)),
        WorkbookCase(id: "T09", title: "숫자 <v> 12,001바이트", build: sheet(
            #"<row r="1"><c r="A1"><v>\#(String(repeating: "1", count: 12_001))</v></c></row>"#, stored: true
        ), expect: .tableFails(.textTooLong)),
    ]

    // 스타일 색인·서식 표
    static let styleCases: [WorkbookCase] = [
        WorkbookCase(id: "Y01", title: "스타일 색인 == cellXfs 수", build: fixture {
            $0.styles = F.stylesXML(xfs: [0, 14])
            $0.sheets[0].xml = F.worksheet(rows: #"<row r="1"><c r="A1" s="2"><v>1</v></c></row>"#)
        }, expect: .tableFails(.invalidStyleIndex)),
        WorkbookCase(id: "Y02", title: "스타일 색인 -1", build: fixture {
            $0.styles = F.stylesXML()
            $0.sheets[0].xml = F.worksheet(rows: #"<row r="1"><c r="A1" s="-1"><v>1</v></c></row>"#)
        }, expect: .tableFails(.invalidStyleIndex)),
        WorkbookCase(id: "Y03", title: "스타일 파트 없이 s=\"1\"", build: sheet(#"<row r="1"><c r="A1" s="1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidStyleIndex)),
        WorkbookCase(id: "Y04", title: "numFmt 번호 중복 정의", build: fixture {
            $0.styles = F.stylesXML(numFmts: [(180, "0"), (180, "yyyy")])
        }, expect: .openFails(.malformedPart)),
        WorkbookCase(id: "Y05", title: "xf numFmtId가 정수가 아님", build: fixture {
            $0.styles = F.stylesXML().replacingOccurrences(of: #"<cellXfs count="1"><xf numFmtId="0""#, with: #"<cellXfs count="1"><xf numFmtId="x""#)
        }, expect: .openFails(.malformedPart)),
    ]

    // 행·셀·참조·병합·dimension(6-5 「행·열·셀」, 6-5b)
    static let grid: [WorkbookCase] = [
        WorkbookCase(id: "G01", title: "스캔 행 20,001", build: sheet(String(repeating: "<row/>", count: 20_001), stored: true),
                     expect: .tableFails(.tooManyRows)),
        WorkbookCase(id: "G02", title: "셀 100,001", build: sheet(
            String(repeating: "<row>" + String(repeating: "<c/>", count: 10) + "</row>", count: 10_000) + "<row><c/></row>", stored: true
        ), expect: .tableFails(.tooManyCells)),
        WorkbookCase(id: "G03", title: "dimension 거짓(A1:XFD1048576) — 실제 행만", build: sheet(
            a1 + #"<row r="2"><c r="B2" t="s"><v>0</v></c></row>"#, before: #"<dimension ref="A1:XFD1048576"/>"#
        ), expect: .tableRows([1, 2])),
        WorkbookCase(id: "G04", title: "dimension 거짓(A1:A1)인데 C5에 값", build: sheet(
            #"<row r="5"><c r="C5" t="s"><v>0</v></c></row>"#, before: #"<dimension ref="A1:A1"/>"#
        ), expect: .tableRows([5])),
        WorkbookCase(id: "G05", title: "셀 참조 소문자 a1", build: sheet(#"<row r="1"><c r="a1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G06", title: "셀 참조 A0", build: sheet(#"<row r="1"><c r="A0" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G07", title: "열 XFE(16,385)", build: sheet(#"<row r="1"><c r="XFE1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G08", title: "행 1,048,577", build: sheet(#"<row r="1048577"><c t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G09", title: "행 번호와 셀 참조 행 불일치", build: sheet(#"<row r="2"><c r="A3" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G10", title: "열이 거꾸로(B1 다음 A1)", build: sheet(#"<row r="1"><c r="B1" t="s"><v>0</v></c><c r="A1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G11", title: "같은 셀 두 번(A1·A1) — 어느 값이 이길지 모호", build: sheet(
            #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="A1"><v>7</v></c></row>"#
        ), expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G12", title: "행이 거꾸로(2 다음 1)", build: sheet(#"<row r="2"><c r="A2" t="s"><v>0</v></c></row>"# + a1),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G13", title: "같은 행 두 번", build: sheet(a1 + a1), expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G14", title: "행 번호 0", build: sheet(#"<row r="0"><c t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G15", title: "행 번호 abc", build: sheet(#"<row r="abc"><c t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G16", title: "모르는 셀 타입 t=\"x\"", build: sheet(#"<row r="1"><c r="A1" t="x"><v>0</v></c></row>"#),
                     expect: .tableFails(.unknownCellType)),
        WorkbookCase(id: "G17", title: "<v> 두 번", build: sheet(#"<row r="1"><c r="A1"><v>1</v><v>2</v></c></row>"#),
                     expect: .tableFails(.malformedPart)),
        WorkbookCase(id: "G18", title: "hidden=\"maybe\"", build: sheet(#"<row r="1" hidden="maybe"><c r="A1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.malformedPart)),
        WorkbookCase(id: "G19", title: "<col min> > max", build: sheet(a1, before: #"<cols><col min="3" max="2" hidden="1"/></cols>"#),
                     expect: .tableFails(.malformedPart)),
        WorkbookCase(id: "G20", title: "<sheetData> 두 번", build: sheet(a1, after: "<sheetData/>"), expect: .tableFails(.malformedPart)),
        WorkbookCase(id: "G21", title: "병합 참조 A1:", build: sheet(a1, after: #"<mergeCells><mergeCell ref="A1:"/></mergeCells>"#),
                     expect: .tableFails(.invalidMergeRange)),
        WorkbookCase(id: "G22", title: "병합 참조 열 넘침 ZZZZ1:A1", build: sheet(a1, after: #"<mergeCells><mergeCell ref="ZZZZ1:A1"/></mergeCells>"#),
                     expect: .tableFails(.invalidMergeRange)),
        WorkbookCase(id: "G23", title: "병합 참조 빈 값", build: sheet(a1, after: #"<mergeCells><mergeCell ref=""/></mergeCells>"#),
                     expect: .tableFails(.invalidMergeRange)),
        WorkbookCase(id: "G24", title: "XFD1 셀 — 열 상한 칸으로 접혀 표 폭이 시트 폭을 따르지 않는다", build: sheet(
            #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="XFD1" t="s"><v>0</v></c></row>"#
        ), expect: .tableRows([1])),
        WorkbookCase(id: "G25", title: "병합 A1:XFD1048576 — 행을 펼치지 않는다", build: sheet(
            a1 + #"<row r="2"><c r="A2" t="s"><v>0</v></c></row>"#, after: #"<mergeCells><mergeCell ref="A1:XFD1048576"/></mergeCells>"#
        ), expect: .tableRows([1, 2])),
        WorkbookCase(id: "G26", title: "열 문자 4개(AAAA1)", build: sheet(#"<row r="1"><c r="AAAA1" t="s"><v>0</v></c></row>"#),
                     expect: .tableFails(.invalidCellReference)),
        WorkbookCase(id: "G27", title: "XML 안 모르는 요소에 든 가짜 sheetData는 읽지 않는다", build: sheet(
            a1, after: #"<extLst><ext><sheetData><row r="9"><c r="A9" t="s"><v>0</v></c></row></sheetData></ext></extLst>"#
        ), expect: .tableRows([1])),
        WorkbookCase(id: "G28", title: "다른 네임스페이스의 <row>는 읽지 않는다", build: sheet(
            a1 + #"<e:row xmlns:e="urn:evil" r="7"><e:c r="A7" t="s"><v>0</v></e:c></e:row>"#
        ), expect: .tableRows([1])),
    ]
}

// MARK: - 시험

@Suite("외부 채움글 1-e ② — 적대 XML fixture (AC-30 XML 층)")
struct XLSXWorkbookAdversarialTests {

    @Test("★ AC-30 표 — 컨테이너 층 + XML 층 합계 ≥ 40, id 중복 없음")
    func tableSize() {
        #expect(WorkbookCase.all.count + ArchiveCase.all.count >= 40)
        #expect(Set(WorkbookCase.all.map(\.id)).count == WorkbookCase.all.count)
    }

    @Test("★ 적대 XML은 전부 안전하게 거부되거나 제한된다", arguments: WorkbookCase.all)
    func adversarial(_ fixture: WorkbookCase) throws {
        let data = fixture.build()
        switch fixture.expect {
        case .openFails(let failure):
            #expect(throws: failure) { _ = try XLSXWorkbookReader.open(data, limits: fixture.limits) }
        case .tableFails(let failure):
            var reader = try XLSXWorkbookReader.open(data, limits: fixture.limits)
            let sheet = try #require(reader.sheets.first)
            #expect(throws: failure) { _ = try reader.table(for: sheet) }
        case .tableRows(let numbers):
            var reader = try XLSXWorkbookReader.open(data, limits: fixture.limits)
            let sheet = try #require(reader.sheets.first)
            let table = try reader.table(for: sheet)
            #expect(table.rows.map(\.number) == numbers)
            #expect(table.rows.allSatisfy { $0.cells.count <= RawTable.columnLimit })
        }
    }

    @Test("사전 스캔을 건너뛰어도 엔티티가 풀리지 않는다 — 외부 엔티티는 파서 설정이, 선언은 대리자가 막는다(이중 방어)")
    func parserGuardWithoutPrescan() throws {
        let documents = [
            #"<?xml version="1.0"?><!DOCTYPE t [<!ENTITY x SYSTEM "file:///etc/hosts">]><t>&x;</t>"#,
            #"<?xml version="1.0"?><!DOCTYPE t [<!ENTITY a "aaaa"><!ENTITY b "&a;&a;">]><t>&b;</t>"#,
            #"<?xml version="1.0"?><!DOCTYPE t [<!ELEMENT t (#PCDATA)>]><t>x</t>"#,
        ]
        final class Sink: XLSXXMLHandler {
            var text = ""
            func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool { true }
            func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) {}
            func characters(_ string: String) throws(XLSXWorkbookFailure) { text += string }
        }
        for (index, document) in documents.enumerated() {
            let sink = Sink()
            do {
                try XLSXXML.runParser(Data(document.utf8), maxDepth: 32, handler: sink)
                // 외부 엔티티: 해석을 끈 설정에서는 파서가 선언을 **보고하지도 않고** 참조는 빈 글로 사라진다(실측).
                // 해석을 켜면 선언이 보고돼 대리자가 멈추므로 이 기대가 깨진다 — 파서 설정 자체를 고정한다
                #expect(index == 0)
            } catch {
                // 내부 엔티티·요소 선언은 대리자가 막는다
                #expect(index != 0)
                #expect(error == .doctypeOrEntity)
            }
            #expect(!sink.text.contains("localhost"))
            #expect(!sink.text.contains("aaaa"))
        }
    }

    @Test("★ 거부 이유에 파일 내용·시트 이름이 실리지 않는다(AC-34)")
    func failuresCarryNoContent() throws {
        let marker = "비밀표식SECRET"
        let probes: [Data] = [
            WorkbookCase.fixture { $0.sheets[0].name = marker; $0.sheets[0].state = "hidden" }(),
            WorkbookCase.fixture { $0.sheets[0].name = marker; $0.sheets[0].target = "../\(marker).xml" }(),
            WorkbookCase.fixture { $0.sharedStrings = XLSXFixture.sst(["<t>\(marker)</t><t>&\(marker);</t>"]) }(),
            WorkbookCase.fixture { $0.sharedStrings = XLSXFixture.plainSST([marker + String(repeating: "가", count: 4_000)]); $0.method = 0 }(),
        ]
        for probe in probes {
            do {
                _ = try XLSXWorkbookReader.open(probe)
                Issue.record("거부돼야 한다")
            } catch {
                #expect(!String(reflecting: error).contains("SECRET"))
                #expect(!String(reflecting: error).contains("비밀"))
            }
        }
        var reader = try XLSXWorkbookReader.open(WorkbookCase.fixture {
            $0.sheets[0].name = marker
            $0.sheets[0].xml = XLSXFixture.worksheet(rows: #"<row r="1"><c r="\#(marker)" t="s"><v>0</v></c></row>"#)
        }())
        let sheet = try #require(reader.sheets.first)
        do {
            _ = try reader.table(for: sheet)
            Issue.record("거부돼야 한다")
        } catch {
            #expect(!String(reflecting: error).contains("SECRET"))
        }
    }
}
