import Foundation
@testable import PackImport

// 외부 채움글 1-e ② — 시험용 xlsx를 **테스트 안에서** 짓는다(AC-30: 외부 도구 0). 컨테이너는 ①의 `ZipSpec`을 그대로 쓰고,
// 여기서는 OOXML 파트(콘텐츠 타입·관계·워크북·시트·공유 문자열·스타일) 글만 정한다. 기본값은 엑셀 모양(네임스페이스·`rId1`·`state` 생략)이다.

struct XLSXFixture: Sendable {

    static let mainNS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let strictMainNS = "http://purl.oclc.org/ooxml/spreadsheetml/main"
    static let officeRelNS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let packageRelNS = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let contentTypesNS = "http://schemas.openxmlformats.org/package/2006/content-types"
    static let relType = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static let mainContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"
    static let declaration = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#

    struct Sheet: Sendable {
        var name: String
        var state: String?
        var relID: String
        var target: String
        /// 아카이브 안 파트 이름(관계 대상과 다르게 둘 수 있다 — 깨진 관계 시험)
        var part: String
        var xml: String
        var relType = XLSXFixture.relType + "worksheet"
    }

    var sheets: [Sheet]
    var sharedStrings: String?
    var styles: String?
    /// nil이면 `sheets`·`sharedStrings`·`styles`로 짓는다
    var contentTypes: String?
    var rootRels: String?
    var workbook: String?
    var workbookRels: String?
    var workbookPath = "xl/workbook.xml"
    var workbookContentType = XLSXFixture.mainContentType
    var extraEntries: [ZipEntrySpec] = []
    /// 0 = stored — 큰 합성 파트가 압축비 상한(①)에 먼저 걸리지 않게
    var method: UInt16 = 8

    init(sheets: [Sheet] = [XLSXFixture.sheet()], sharedStrings: String? = nil, styles: String? = nil) {
        self.sheets = sheets
        self.sharedStrings = sharedStrings
        self.styles = styles
    }

    /// 시트 하나 — `rows`는 `<sheetData>` 안쪽 글
    static func sheet(_ name: String = "문구", rows: String = "", state: String? = nil, index: Int = 1,
                      before: String = "", after: String = "") -> Sheet {
        Sheet(name: name, state: state, relID: "rId\(index)", target: "worksheets/sheet\(index).xml",
              part: "xl/worksheets/sheet\(index).xml", xml: worksheet(rows: rows, before: before, after: after))
    }

    static func worksheet(rows: String, before: String = "", after: String = "", namespace: String = mainNS) -> String {
        declaration + #"<worksheet xmlns="\#(namespace)" xmlns:r="\#(officeRelNS)">\#(before)<sheetData>\#(rows)</sheetData>\#(after)</worksheet>"#
    }

    /// `<sst>` — 항목 글은 이미 XML 이스케이프된 것으로 받는다(`<r>` 조각 시험을 위해)
    static func sst(_ items: [String]) -> String {
        declaration + #"<sst xmlns="\#(mainNS)" count="\#(items.count)" uniqueCount="\#(items.count)">"#
            + items.map { "<si>\($0)</si>" }.joined() + "</sst>"
    }

    /// 평범한 글 항목들 — `<si><t xml:space="preserve">…</t></si>`
    static func plainSST(_ texts: [String]) -> String {
        sst(texts.map { #"<t xml:space="preserve">\#(escape($0))</t>"# })
    }

    static func stylesXML(numFmts: [(Int, String)] = [], xfs: [Int] = [0]) -> String {
        let formats = numFmts.isEmpty ? "" : #"<numFmts count="\#(numFmts.count)">"#
            + numFmts.map { #"<numFmt numFmtId="\#($0.0)" formatCode="\#(escape($0.1))"/>"# }.joined() + "</numFmts>"
        return declaration + #"<styleSheet xmlns="\#(mainNS)">\#(formats)<cellStyleXfs count="1"><xf numFmtId="0"/></cellStyleXfs>"#
            + #"<cellXfs count="\#(xfs.count)">"# + xfs.map { #"<xf numFmtId="\#($0)" fontId="0" fillId="0" borderId="0" xfId="0"/>"# }.joined()
            + "</cellXfs></styleSheet>"
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: 기본 파트

    var defaultContentTypes: String {
        var overrides = [#"<Override PartName="/\#(workbookPath)" ContentType="\#(workbookContentType)"/>"#]
        // 시트 파트가 다른 파트를 가리키는 시험(순환 관계)에서는 Override를 겹쳐 쓰지 않는다
        var listed: Set<String> = [workbookPath, workbookRelsPath]
        for sheet in sheets where listed.insert(sheet.part).inserted {
            overrides.append(#"<Override PartName="/\#(sheet.part)" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#)
        }
        if sharedStrings != nil {
            overrides.append(#"<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>"#)
        }
        if styles != nil {
            overrides.append(#"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#)
        }
        return Self.declaration + #"<Types xmlns="\#(Self.contentTypesNS)"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/>"#
            + overrides.joined() + "</Types>"
    }

    var defaultRootRels: String {
        Self.declaration + #"<Relationships xmlns="\#(Self.packageRelNS)"><Relationship Id="rId1" Type="\#(Self.relType)officeDocument" Target="\#(workbookPath)"/></Relationships>"#
    }

    var defaultWorkbook: String {
        let entries = sheets.enumerated().map { index, sheet in
            let state = sheet.state.map { #" state="\#($0)""# } ?? ""
            return #"<sheet name="\#(Self.escape(sheet.name))" sheetId="\#(index + 1)"\#(state) r:id="\#(sheet.relID)"/>"#
        }
        return Self.declaration + #"<workbook xmlns="\#(Self.mainNS)" xmlns:r="\#(Self.officeRelNS)"><sheets>"# + entries.joined()
            + "</sheets></workbook>"
    }

    var defaultWorkbookRels: String {
        var rels = sheets.map { #"<Relationship Id="\#($0.relID)" Type="\#($0.relType)" Target="\#($0.target)"/>"# }
        if sharedStrings != nil { rels.append(#"<Relationship Id="rIdS" Type="\#(Self.relType)sharedStrings" Target="sharedStrings.xml"/>"#) }
        if styles != nil { rels.append(#"<Relationship Id="rIdT" Type="\#(Self.relType)styles" Target="styles.xml"/>"#) }
        return Self.declaration + #"<Relationships xmlns="\#(Self.packageRelNS)">"# + rels.joined() + "</Relationships>"
    }

    var workbookRelsPath: String {
        let directory = (workbookPath as NSString).deletingLastPathComponent
        let file = (workbookPath as NSString).lastPathComponent
        return (directory.isEmpty ? "" : directory + "/") + "_rels/\(file).rels"
    }

    func entries() -> [ZipEntrySpec] {
        var entries = [
            ZipEntrySpec("[Content_Types].xml", contentTypes ?? defaultContentTypes, method: method),
            ZipEntrySpec("_rels/.rels", rootRels ?? defaultRootRels, method: method),
            ZipEntrySpec(workbookPath, workbook ?? defaultWorkbook, method: method),
            ZipEntrySpec(workbookRelsPath, workbookRels ?? defaultWorkbookRels, method: method),
        ]
        // 시트 파트 이름이 이미 있는 파트(순환 관계 시험)이거나 다른 시트와 같으면 다시 넣지 않는다
        var seen = Set(entries.map { String(decoding: $0.name, as: UTF8.self) })
        for sheet in sheets where seen.insert(sheet.part).inserted {
            entries.append(ZipEntrySpec(sheet.part, sheet.xml, method: method))
        }
        if let sharedStrings { entries.append(ZipEntrySpec("xl/sharedStrings.xml", sharedStrings, method: method)) }
        if let styles { entries.append(ZipEntrySpec("xl/styles.xml", styles, method: method)) }
        for extra in extraEntries { entries.append(extra) }
        for index in entries.indices where entries[index].method == 0 { entries[index].flags = 0 }
        return entries
    }

    func build() -> Data { ZipSpec(entries()).build() }

    /// 셀 하나짜리 시트(공유 문자열 하나) — 가장 흔한 바탕
    static func singleText(_ text: String = "회의시작") -> XLSXFixture {
        XLSXFixture(sheets: [sheet(rows: #"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#)], sharedStrings: plainSST([text]))
    }
}

extension RawTable {
    /// 행 번호 → 셀(시험 편의)
    func row(_ number: Int) -> RawRow? { rows.first { $0.number == number } }
}
