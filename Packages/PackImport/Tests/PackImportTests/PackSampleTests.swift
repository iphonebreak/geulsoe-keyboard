import CryptoKit
import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 6단계 ④⑤ — 고정 샘플 CSV 2종(번호형·문구형)을 번들에 넣고 3-C 공유 시트로 내보낸다
// (PDR `external-snippet-packs.md` 6-6 ③ 「번들 CSV는 `*.original.csv`」·13-1(R5) · AC-29, 시안 3-A 「처음이라면」·3-C).
// 번들 파일은 기획자 원본을 **바이트 그대로** 복사한 것이다 — 해시는 제작 기록 `docs/design/external-snippet-packs/sample-build-record.md`와 같아야 한다.
// `/docs/`는 저장소에 올리지 않는다(.gitignore) — 그래서 기록의 해시를 아래 표에 옮겨 두고 **늘** 대조하며, 문서가 있는 기기에서는 표가 기록과 같은지도 본다.

/// 제작 기록 표의 SHA-256 — 샘플을 다시 만들면 기록과 이 표를 함께 고친다(기록의 「다시 만들 때」).
/// 2026-10-07 개정(R27) — 정보 줄 키 `#권리` → `#출처` 한 곳만 바꿨다(기록의 「변경 이력」)
/// 2026-10-08 실기 피드백 2 — 정보 줄 묶음과 머리글 사이에 빈 줄(CRLF) 하나만 넣었다(xlsx 샘플과 같은 자리)
private let recordedSHA256: [PackSample.Kind: String] = [
    .numbered: "d6ef527f901f44a619d77b2add03e263abba3e0d930ea9a8889ba513a9b01424",
    .phrases: "e856978949137ff598c96e070b60bfb5279e1310ef85fcbfb698e14b3ec7776a"
]

/// 빈 줄을 넣기 전(R27 판)의 SHA-256 — 새 판에서 그 빈 줄 하나를 빼면 이 바이트로 돌아가야 한다(BOM·줄 끝·열 순서·나머지 바이트 그대로)
private let sha256BeforeBlankLine: [PackSample.Kind: String] = [
    .numbered: "425eb2c44b904b5779a64e01be07c5d2ef73effa140d7873d1bfba71187549f1",
    .phrases: "e97413f0853cca93b6ef6043fd8d8be0b9f15a0fc0dffb41cd69d04a2ba1ef9d"
]

/// 제작 기록 표의 xlsx SHA-256 — 1-e ④-가 `tools/generate_sample_xlsx.py` 산출물(`#출처`판·열 너비·본문 줄바꿈). 다시 만들면 기록과 함께 고친다.
/// 2026-10-08 실기 피드백판 — 정보 줄 키·머리글 칸 굵게 · 정보 줄 묶음과 머리글 사이 빈 행 하나(셀 값은 그대로)
/// 2026-10-08 실기 피드백 3 — 표 영역 칸 네 변 테두리 · 머리글 칸 연한 회색 채우기(셀 값·열 너비·숫자 서식은 그대로)
private let recordedXLSXSHA256: [PackSample.Kind: String] = [
    .numbered: "b1f9a27ec7347eba44d22a856c2c85bb72d51068ac46229b215e02dd4e4c9377",
    .phrases: "fb88e798a2c1d02d0debdebf853ddaa669d6d347b209ff7e51f123e0fe82457e"
]

/// 기획자 원본 이름 — 시험 픽스처(`Fixtures/`, 4단계에 원본을 그대로 복사)와 문서 폴더에 같은 이름으로 있다
private func originalName(_ kind: PackSample.Kind) -> String { kind == .numbered ? "sample-numbered.original" : "sample-phrases.original" }

/// 저장소의 샘플 원본 폴더 — 이 시험 파일에서 거슬러 올라간다(`Packages/PackImport/Tests/PackImportTests/`). 로컬 전용이라 없을 수 있다
private let sampleDocsDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // PackImportTests · Tests · PackImport
    .deletingLastPathComponent().deletingLastPathComponent()                               // Packages · 저장소
    .appendingPathComponent("docs/design/external-snippet-packs")

private let hasSampleDocs = FileManager.default.fileExists(atPath: sampleDocsDirectory.appendingPathComponent("sample-build-record.md").path)

private func csvFile(_ kind: PackSample.Kind) -> PackSample.File { PackSample.File(kind: kind, format: .csv) }

private func xlsxFile(_ kind: PackSample.Kind) -> PackSample.File { PackSample.File(kind: kind, format: .xlsx) }

private func resourceName(_ kind: PackSample.Kind) -> String { kind == .numbered ? "sample-numbered" : "sample-phrases" }

/// 번들 샘플 폴더의 xlsx — **판을 거치지 않고** 폴더에서 바로(번들에 무엇이 실렸는지 보는 시험용). 앱은 `PackSample.File.bundledURL`만 쓴다
private func bundledXLSXData(_ kind: PackSample.Kind) throws -> Data {
    let directory = try #require(PackSample.bundledDirectory)
    return try Data(contentsOf: directory.appendingPathComponent("\(resourceName(kind)).xlsx"))
}

private func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

/// 샘플의 엑셀 행 자리(사장님 실기 피드백 2026-10-08) — 정보 줄 묶음(1행부터) · **빈 행 하나** · 머리글 · 데이터.
/// 번호형은 정보 줄 3 · 데이터 20(머리글 5행), 문구형은 2 · 15(머리글 4행). CSV 샘플도 같은 자리에 빈 줄 하나(실기 피드백 2) —
/// 그래서 CSV 레코드 번호와 xlsx 행 번호가 같다
private func sampleLayout(_ kind: PackSample.Kind) -> (meta: Int, header: Int, rows: [Int]) {
    let meta = kind == .numbered ? 3 : 2
    let header = meta + 2
    let data = kind == .numbered ? 20 : 15
    return (meta, header, Array(1...meta) + Array(header...(header + data)))
}

/// 샘플의 표 영역 칸(실기 피드백 3, 2026-10-08) — 머리글 행부터 마지막 데이터 행까지 × 머리글 열(A·B·C). 정보 줄·빈 행은 들지 않는다
private func sampleTableCells(_ kind: PackSample.Kind) -> Set<String> {
    let layout = sampleLayout(kind)
    return Set((layout.header...(layout.rows.last ?? layout.header)).flatMap { row in ["A", "B", "C"].map { "\($0)\(row)" } })
}

/// 샘플 xlsx의 굵은 칸·테두리 칸·채우기 칸과 칸 스타일의 숫자 서식 — `xl/styles.xml`의 `fonts`(`<b/>`)·`fills`·`borders`·
/// `cellXfs`(fontId·fillId·borderId·numFmtId)와 시트 칸의 `s`·열의 `style`만 본다. 생성기·파이썬 검사기(L2~L4)와 따로 읽는다
struct SampleCellStyles {
    private(set) var boldCells: Set<String> = []
    /// 네 변 모두 가는 실선(`thin`)·자동/검정 색인 칸 — 실기 피드백 3(2026-10-08)
    private(set) var thinBoxCells: Set<String> = []
    /// 어느 변이든 선이 하나라도 있는 칸
    private(set) var anyBorderCells: Set<String> = []
    /// 단색(`solid`) 연한 회색 `FFD9D9D9` 채우기 칸(엑셀 「흰색, 배경 1, 15% 더 어둡게」)
    private(set) var grayFillCells: Set<String> = []
    /// 채우기가 있는 칸(무늬 `none`이 아닌 것 전부)
    private(set) var anyFillCells: Set<String> = []
    /// 테두리·채우기가 있는 열 기본 스타일(`<col style>`) — 있으면 새로 친 칸까지 번진다
    private(set) var decoratedColumns: [String] = []
    /// `cellXfs` 순서의 numFmtId
    private(set) var numberFormats: [Int] = []

    init(_ data: Data) throws {
        var archive = try XLSXArchive.open(data)
        let styles = try ElementList(try archive.read("xl/styles.xml", as: .styles))
        let sheet = try ElementList(try archive.read("xl/worksheets/sheet1.xml", as: .worksheet))
        var boldFonts: Set<Int> = []
        var fontCount = 0
        // fills — 무늬와 앞 색(rgb), borders — 변마다 (선 모양, 색 속성)
        var fills: [(pattern: String, foreground: String?)] = []
        var borders: [[String: (style: String?, color: [String: String])]] = []
        let sides: Set<String> = ["left", "right", "top", "bottom", "diagonal"]
        var xfs: [(font: Int, fill: Int, border: Int)] = []
        for element in styles.elements {
            switch (element.parent, element.name) {
            case ("fonts", "font"): fontCount += 1
            case ("font", "b") where [nil, "1", "true"].contains(element.attributes["val"]): boldFonts.insert(fontCount - 1)
            case ("fills", "fill"): fills.append(("none", nil))
            case ("fill", "patternFill"): fills[fills.count - 1].pattern = element.attributes["patternType"] ?? "none"
            case ("patternFill", "fgColor"): fills[fills.count - 1].foreground = element.attributes["rgb"]
            case ("borders", "border"): borders.append([:])
            case ("border", let side) where sides.contains(side): borders[borders.count - 1][side] = (element.attributes["style"], [:])
            case (let side?, "color") where sides.contains(side): borders[borders.count - 1][side]?.color = element.attributes
            case ("cellXfs", "xf"):
                func id(_ name: String) -> Int { Int(element.attributes[name] ?? "0") ?? 0 }
                xfs.append((id("fontId"), id("fillId"), id("borderId")))
                numberFormats.append(id("numFmtId"))
            default: break
            }
        }
        // 자동(`auto`)·색인 64(엑셀이 「자동」으로 쓰는 값)·검정 rgb만 받는다
        func isThinAuto(_ side: (style: String?, color: [String: String])?) -> Bool {
            guard let side, side.style == "thin" else { return false }
            let color = side.color
            return color.isEmpty || ["1", "true"].contains(color["auto"]) || color["indexed"] == "64" || color["rgb"] == "FF000000"
        }
        for element in sheet.elements {
            guard let xf = Int(element.attributes[element.name == "col" ? "style" : "s"] ?? "0").flatMap({ xfs.indices.contains($0) ? xfs[$0] : nil })
            else { continue }
            let border = borders.indices.contains(xf.border) ? borders[xf.border] : [:]
            let fill: (pattern: String, foreground: String?) = fills.indices.contains(xf.fill) ? fills[xf.fill] : ("none", nil)
            let hasBorder = border.values.contains { $0.style != nil && $0.style != "none" }
            let hasFill = fill.pattern != "none"
            if element.name == "col" {
                if hasBorder || hasFill { decoratedColumns.append("\(element.attributes["min"] ?? "?")~\(element.attributes["max"] ?? "?")") }
                continue
            }
            guard element.name == "c", let reference = element.attributes["r"] else { continue }
            if boldFonts.contains(xf.font) { boldCells.insert(reference) }
            if hasBorder { anyBorderCells.insert(reference) }
            if ["left", "right", "top", "bottom"].allSatisfy({ isThinAuto(border[$0]) }) { thinBoxCells.insert(reference) }
            if hasFill { anyFillCells.insert(reference) }
            if fill.pattern == "solid" && fill.foreground?.uppercased() == "FFD9D9D9" { grayFillCells.insert(reference) }
        }
    }

    /// 요소마다 (부모 로컬 이름, 로컬 이름, 속성) — 시작 순서
    private final class ElementList: NSObject, XMLParserDelegate {
        struct Element { let parent: String?; let name: String; let attributes: [String: String] }
        private var stack: [String] = []
        private(set) var elements: [Element] = []

        init(_ data: Data) throws {
            super.init()
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = true
            parser.delegate = self
            guard parser.parse() else { throw CocoaError(.fileReadCorruptFile) }
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            elements.append(Element(parent: stack.last, name: elementName, attributes: attributes))
            stack.append(elementName)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            _ = stack.popLast()
        }
    }
}

/// 제작 기록 표에서 그 원본 파일 줄의 SHA-256
private func recordedHash(_ original: String) throws -> String {
    let record = try String(contentsOf: sampleDocsDirectory.appendingPathComponent("sample-build-record.md"), encoding: .utf8)
    let row = try #require(record.split(separator: "\n").first { $0.contains("`\(original)`") })
    let hash = try #require(row.range(of: "[0-9a-f]{64}", options: .regularExpression))
    return String(row[hash])
}

/// PDR 13-1(R5)·13-2(R6) — 스프레드시트가 수식·명령으로 읽을 수 있는 시작 글자: `= + - @`(전각 포함) · 탭 · CR · LF
private let dangerousLeadingCharacters: Set<Character> = ["=", "+", "-", "@", "＝", "＋", "－", "＠", "\t", "\r", "\n", "\r\n"]

private func startsDangerously(_ cell: String) -> Bool { cell.first.map(dangerousLeadingCharacters.contains) ?? false }

// MARK: - xlsx 샘플 검사 — `tools/check_sample_xlsx.py`의 A29·A47과 같은 규칙(독립 오라클은 파이썬, 이쪽은 번들에 실린 바이트를 매 빌드 본다)

/// AC-29 대상 글 — 표의 글·숫자 칸 전부 + 공유 문자열 항목 전부(칸이 가리키지 않는 항목도 — 파이썬 A29와 같다). 6-4 정리(`_xHHHH_`·CRLF) 뒤
func workbookSampleTexts(_ data: Data) throws -> (cells: [String], sharedStrings: [String]) {
    var reader = try XLSXWorkbookReader.open(data)
    let table = try reader.table(for: try #require(reader.sheets.first))
    let cells = table.rows.flatMap(\.cells).compactMap { cell -> String? in
        switch cell {
        case .text(let text), .number(let text): text
        case .blank: nil
        case .unsupported(let kind): "<\(kind)>"
        }
    }
    var archive = try XLSXArchive.open(data)
    let handler = SharedStringsHandler(limits: .product)
    try XLSXXML.parse(try archive.read("xl/sharedStrings.xml", as: .sharedStrings), maxDepth: 32, maxAttributes: 64, handler: handler)
    return (cells, handler.strings)
}

/// AC-47(값 기준) — 파이썬 A47과 같은 규칙: 금지 파트(custom·customXml·persons·댓글) · 모든 엔트리의 `absPath`·사용자 경로·이메일 꼴
/// (XML·rels가 아니면 UTF-16LE로도 읽는다) · 콘텐츠 타입·관계의 `persons`·`customXml` 참조 · 작성자·수정자(빈 값·「글쇠」만)·Company·Manager 값 ·
/// `author` 요소·속성. 걸린 것의 **자리만**(파트 이름·규칙) 돌려준다 — 값은 담지 않는다
enum SamplePrivacyLint {
    static let forbiddenParts = #"(?i)^(docProps/custom\.xml|customXml/|xl/persons/|xl/comments|xl/threadedComments/)"#
    static let userPath = #"(?i)/Users/|/home/|[A-Za-z]:\\|\\Users\\|file:"#
    static let email = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"#
    static let neutralAuthors: Set<String> = ["", "글쇠"]

    static func findings(_ data: Data) throws -> [String] {
        var archive = try XLSXArchive.open(data)
        var found: [String] = []
        for name in archive.entryNames.sorted() {
            if name.range(of: forbiddenParts, options: .regularExpression) != nil { found.append("\(name): 금지 파트") }
            let bytes = [UInt8](try archive.read(name, as: .worksheet))
            let isXML = name.hasSuffix(".xml") || name.hasSuffix(".rels")
            var texts = [String(decoding: bytes, as: UTF8.self)]
            if !isXML {
                let units = stride(from: 0, to: bytes.count - 1, by: 2).map { UInt16(bytes[$0]) | UInt16(bytes[$0 + 1]) << 8 }
                texts.append(String(decoding: units, as: UTF16.self))
            }
            for text in texts {
                if text.lowercased().contains("abspath") { found.append("\(name): absPath") }
                if text.range(of: userPath, options: .regularExpression) != nil { found.append("\(name): 사용자 경로") }
                if text.range(of: email, options: .regularExpression) != nil { found.append("\(name): 이메일") }
            }
            if name == "[Content_Types].xml" || name.hasSuffix(".rels") {
                let lowered = texts[0].lowercased()
                if lowered.contains("persons") || lowered.contains("customxml") { found.append("\(name): persons·customXml 참조") }
            }
            guard isXML else { continue }
            let walker = ElementWalker()
            let parser = XMLParser(data: Data(bytes))
            parser.shouldProcessNamespaces = true
            parser.delegate = walker
            guard parser.parse() else { found.append("\(name): XML 아님"); continue }
            for element in walker.elements {
                if element.name == "creator" || element.name == "lastModifiedBy" {
                    if !neutralAuthors.contains(element.text) { found.append("\(name): \(element.name)") }
                } else if element.name == "Company" || element.name == "Manager" {
                    if !element.text.isEmpty { found.append("\(name): \(element.name)") }
                } else if element.name == "author" || element.hasAuthorAttribute {
                    found.append("\(name): author")
                }
            }
        }
        return found
    }

    /// 요소마다 (로컬 이름, 앞뒤 공백 뗀 글, `author` 속성 여부)
    private final class ElementWalker: NSObject, XMLParserDelegate {
        struct Element { let name: String; var text: String; let hasAuthorAttribute: Bool }
        private var stack: [Element] = []
        private(set) var elements: [Element] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String]) {
            stack.append(Element(name: elementName, text: "", hasAuthorAttribute: attributes["author"] != nil))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !stack.isEmpty { stack[stack.count - 1].text += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            guard var element = stack.popLast() else { return }
            element.text = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            elements.append(element)
        }
    }
}

@Suite("외부 채움글 1-c 6단계 ④ — 고정 샘플 CSV (AC-29 · 제작 기록 해시)")
struct PackSampleBundleTests {

    @Test("위험 시작 글자 판정(AC-29) — `= + - @`·전각·탭·CR·LF로 시작하면 걸리고, 가운데에 있으면 괜찮다", arguments: [
        ("=1+2", true), ("+82", true), ("-목록", true), ("@이름", true), ("＝합계", true), ("＋", true), ("－", true), ("＠", true),
        ("\t탭", true), ("\r", true), ("\n줄", true), ("\r\n줄", true),
        ("일석이조 — 한 가지 일로", false), ("1", false), ("#이름", false), ("", false), ("회의 시작 = 인사", false)
    ])
    func dangerousStart(_ cell: String, dangerous: Bool) {
        #expect(startsDangerously(cell) == dangerous)
    }

    @Test("★ AC-29 — 번들 CSV의 모든 셀(정보 줄·머리글 포함)이 위험 시작 글자로 시작하지 않는다", arguments: PackSample.Kind.allCases)
    func noDangerousCells(_ kind: PackSample.Kind) throws {
        let url = try #require(csvFile(kind).bundledURL)
        let text = try PackTextDecoder.decode(Data(contentsOf: url)).text
        let records = try CSVRecordParser.parse(text, delimiter: .comma).records
        // 검사가 실제 셀을 돈다 — 정보 줄 + 빈 줄 + 머리글 + 데이터(번호형 3 + 1 + 1 + 20 · 문구형 2 + 1 + 1 + 15)
        #expect(records.count == (kind == .numbered ? 25 : 19))
        for cell in records.flatMap(\.cells) { #expect(!startsDangerously(cell), "\(kind): \(cell.debugDescription)") }
    }

    @Test("★ 번들 파일 SHA-256 == 제작 기록 — 그리고 기획자 원본(시험 픽스처)과 바이트가 같다(6-6 ③)", arguments: PackSample.Kind.allCases)
    func hashMatchesRecord(_ kind: PackSample.Kind) throws {
        let bundled = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        #expect(sha256(bundled) == recordedSHA256[kind])
        let fixture = try #require(Bundle.module.url(forResource: originalName(kind), withExtension: "csv", subdirectory: "Fixtures"))
        #expect(bundled == (try Data(contentsOf: fixture)))
        #expect(bundled.starts(with: [0xEF, 0xBB, 0xBF]))   // UTF-8 BOM — 엑셀이 글자를 바로 읽는다(6-6 ③)
    }

    @Test("제작 기록 문서와 대조 — 위 해시 표가 기록 표와 같고, 번들 파일이 문서 폴더의 원본과 같다(문서가 있는 기기에서만)",
          .enabled(if: hasSampleDocs), arguments: PackSample.Kind.allCases)
    func recordDocumentAgrees(_ kind: PackSample.Kind) throws {
        #expect(recordedSHA256[kind] == (try recordedHash("\(originalName(kind)).csv")))
        let bundled = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        #expect(bundled == (try Data(contentsOf: sampleDocsDirectory.appendingPathComponent("\(originalName(kind)).csv"))))
    }

    @Test("★ 번들 샘플은 그대로 팩이 된다 — 건너뜀 0 · 파일 정보 줄로 폼이 채워지고 파일 출처가 미리 골라져 가져오기가 켜져 있다(R28 · AC-27 준비)",
          arguments: PackSample.Kind.allCases)
    func importsCleanly(_ kind: PackSample.Kind) throws {
        let data = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        guard case .draft(let draft) = try PackImporter.read(data) else {
            Issue.record("구분자를 물었다")
            return
        }
        #expect(draft.skipped.isEmpty && !draft.needsEncodingConfirmation)
        #expect(draft.mode == (kind == .numbered ? .numbered : .phrases))
        #expect(kind == .numbered ? draft.items.count == 20 : draft.entries.count == 15)
        let form = PackImportForm(draft: draft)
        #expect(form.licenseChoice == .fromFile)     // R28 — 파일의 `#출처`를 미리 고른다(예전 시안 리뷰 수정 1을 바꿨다)
        #expect(form.isComplete)
        let pack = try PackCompiler.compile(draft, form: form.packForm)
        #expect(pack.name == (kind == .numbered ? "사자성어 예시 팩" : "업무 상용구 예시"))
        #expect(pack.license == "글쇠 고정 샘플 — 자체 작성 문구(가짜 내용)")
    }

    @Test("★ 실기 피드백 2(2026-10-08) — CSV 샘플도 정보 줄 묶음과 머리글 사이에 빈 줄 하나: 비지 않은 레코드 번호가 xlsx 샘플의 행 번호와 같다",
          arguments: PackSample.Kind.allCases)
    func blankLineBeforeHeader(_ kind: PackSample.Kind) throws {
        let data = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        let records = try CSVRecordParser.parse(try PackTextDecoder.decode(data).text, delimiter: .comma).records
        let layout = sampleLayout(kind)
        #expect(records.indices.filter { !records[$0].isBlank }.map { $0 + 1 } == layout.rows)
        // 빈 줄은 정말 빈 줄 하나(`,,`가 아니다) — 위는 마지막 정보 줄 `#출처`, 아래는 머리글. 물리 줄 번호도 xlsx 행 번호와 같다
        #expect(records.count == layout.rows.last && records[layout.meta].cells == [""])
        #expect(records[layout.meta - 1].cells.first == "#출처")
        let header = records[layout.header - 1]
        #expect(header.cells == (kind == .numbered ? ["번호", "제목", "본문"] : ["단축어", "제목", "본문"]) && header.line == layout.header)
    }

    @Test("★ 실기 피드백 2 — 바뀐 곳은 그 빈 줄(CRLF 두 바이트) 하나: 빼면 앞 판 바이트(BOM·CRLF·열 순서·나머지 그대로)", arguments: PackSample.Kind.allCases)
    func onlyBlankLineAdded(_ kind: PackSample.Kind) throws {
        let data = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        let blank = try #require(data.range(of: Data("\r\n\r\n".utf8)))
        // 처음 나오는 빈 줄이 곧 정보 줄 묶음 끝이다 — 그 앞은 정보 줄뿐
        let before = String(decoding: data[..<blank.lowerBound].dropFirst(3), as: UTF8.self)
        #expect(before.components(separatedBy: "\r\n").allSatisfy { $0.hasPrefix("#") })
        var previous = data
        previous.removeSubrange(blank.lowerBound..<(blank.lowerBound + 2))
        #expect(sha256(previous) == sha256BeforeBlankLine[kind])
    }

    @Test("★ R27 — 번들 샘플의 정보 줄은 `#출처` 한 줄이고 옛 `#권리`는 없다(바뀐 곳은 그 키 하나 — 값은 그대로)", arguments: PackSample.Kind.allCases)
    func sourceKeyInSample(_ kind: PackSample.Kind) throws {
        let data = try Data(contentsOf: try #require(csvFile(kind).bundledURL))
        let records = try CSVRecordParser.parse(try PackTextDecoder.decode(data).text, delimiter: .comma).records
        let source = records.filter { $0.cells.first == "#출처" }
        #expect(source.count == 1)
        #expect(source.first?.cells[1] == "글쇠 고정 샘플 — 자체 작성 문구(가짜 내용)")
        #expect(!records.contains { $0.cells.contains { $0.contains("권리") } })
    }
}

@Suite("외부 채움글 1-e ④ — 고정 샘플 xlsx (번들 = 제작 기록 = 픽스처 · AC-29 · AC-47)")
struct PackSampleWorkbookTests {

    @Test("★ 번들 xlsx SHA-256 == 제작 기록 — 시험 픽스처와 바이트가 같다(④-가 스크립트 산출물을 바이트 그대로)", arguments: PackSample.Kind.allCases)
    func hashMatchesRecord(_ kind: PackSample.Kind) throws {
        let bundled = try bundledXLSXData(kind)
        #expect(sha256(bundled) == recordedXLSXSHA256[kind])
        let fixture = try #require(Bundle.module.url(forResource: resourceName(kind), withExtension: "xlsx", subdirectory: "Fixtures"))
        #expect(bundled == (try Data(contentsOf: fixture)))
        #expect(bundled.starts(with: [0x50, 0x4B, 0x03, 0x04]))
    }

    @Test("제작 기록 문서와 대조 — xlsx 해시 표가 기록 표와 같고, 번들 파일이 문서 폴더의 정본과 같다(문서가 있는 기기에서만)",
          .enabled(if: hasSampleDocs), arguments: PackSample.Kind.allCases)
    func recordDocumentAgrees(_ kind: PackSample.Kind) throws {
        #expect(recordedXLSXSHA256[kind] == (try recordedHash("\(resourceName(kind)).xlsx")))
        #expect(try bundledXLSXData(kind) == (try Data(contentsOf: sampleDocsDirectory.appendingPathComponent("\(resourceName(kind)).xlsx"))))
    }

    @Test("★ AC-29 — 번들 xlsx의 모든 칸(정보 줄·머리글·번호 숫자 포함)과 공유 문자열 항목 전부가 위험 시작 글자로 시작하지 않는다",
          arguments: PackSample.Kind.allCases)
    func noDangerousCells(_ kind: PackSample.Kind) throws {
        let texts = try workbookSampleTexts(try bundledXLSXData(kind))
        // 검사가 실제 칸을 돈다 — 제작 기록 「행 24 · 셀 70 · 공유 문자열 50」 / 「행 18 · 셀 52 · 공유 문자열 52」
        #expect(texts.cells.count == (kind == .numbered ? 70 : 52) && texts.sharedStrings.count == (kind == .numbered ? 50 : 52))
        for text in texts.cells + texts.sharedStrings { #expect(!startsDangerously(text), "\(kind): \(text.debugDescription)") }
    }

    @Test("★ AC-47 — 번들 xlsx의 모든 엔트리에 개인 정보 0(작성자·수정자·회사·관리자 값·absPath·사용자 경로·이메일·persons·customXml·댓글)",
          arguments: PackSample.Kind.allCases)
    func noPrivateData(_ kind: PackSample.Kind) throws {
        #expect(try SamplePrivacyLint.findings(try bundledXLSXData(kind)) == [])
    }

    @Test("AC-47 규칙은 실제로 잡는다 — 작성자·absPath·사용자 경로·이메일·Company·author·persons 파트를 넣은 사본")
    func privacyRuleCatches() throws {
        var entries = XLSXFixture.singleText().entries()
        let core = #"<?xml version="1.0" encoding="UTF-8"?><cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" "#
            + #"xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:creator>작성자</dc:creator><cp:lastModifiedBy>글쇠</cp:lastModifiedBy></cp:coreProperties>"#
        let app = #"<?xml version="1.0" encoding="UTF-8"?><Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">"#
            + "<Company>회사</Company><Manager></Manager></Properties>"
        entries.append(ZipEntrySpec("docProps/core.xml", core, method: 0))
        entries.append(ZipEntrySpec("docProps/app.xml", app, method: 0))
        entries.append(ZipEntrySpec("xl/persons/person.xml", #"<?xml version="1.0"?><personList author="a"/>"#, method: 0))
        entries.append(ZipEntrySpec("xl/extra.bin", "C:\\Users\\name\\a.xlsx · name@example.com · absPath", method: 0))
        let found = try SamplePrivacyLint.findings(ZipSpec(entries).build())
        #expect(found.contains("docProps/core.xml: creator"))
        #expect(!found.contains("docProps/core.xml: lastModifiedBy"), "「글쇠」는 중립 값")
        #expect(found.contains("docProps/app.xml: Company") && !found.contains("docProps/app.xml: Manager"), "빈 Manager는 통과(값 기준)")
        #expect(found.contains("xl/persons/person.xml: 금지 파트") && found.contains("xl/persons/person.xml: author"))
        #expect(found.contains("xl/extra.bin: 사용자 경로") && found.contains("xl/extra.bin: 이메일") && found.contains("xl/extra.bin: absPath"))
        #expect(found.allSatisfy { !$0.contains("작성자") && !$0.contains("회사") }, "값은 담지 않는다")
    }

    @Test("★ 실기 피드백(2026-10-08) — 정보 줄 묶음과 머리글 사이에 빈 행 하나: 시트 행 번호가 엑셀 화면 그대로(번호형 머리글 5행 · 문구형 4행)",
          arguments: PackSample.Kind.allCases)
    func blankRowBeforeHeader(_ kind: PackSample.Kind) throws {
        var reader = try XLSXWorkbookReader.open(try bundledXLSXData(kind))
        let table = try reader.table(for: try #require(reader.sheets.first))
        let layout = sampleLayout(kind)
        #expect(table.rows.map(\.number) == layout.rows)
        // 빈 행 위는 마지막 정보 줄, 아래는 머리글
        let lastMeta = try #require(table.rows.first { $0.number == layout.meta }?.cells.first)
        #expect(lastMeta == .text("#출처"))
        let header = kind == .numbered ? ["번호", "제목", "본문"] : ["단축어", "제목", "본문"]
        #expect(table.rows.first { $0.number == layout.header }?.cells == header.map(RawCell.text))
    }

    @Test("★ 실기 피드백 — 빈 행이 있어도 건너뜀 문구의 「n번째 행」은 엑셀 화면의 행 번호다(같은 표를 CSV로 저장하면 빈 레코드를 세어 같은 번호)",
          arguments: PackSample.Kind.allCases)
    func skipPositionIsSheetRow(_ kind: PackSample.Kind) throws {
        var reader = try XLSXWorkbookReader.open(try bundledXLSXData(kind))
        let table = try reader.table(for: try #require(reader.sheets.first))
        // 샘플 표를 빈 행 자리까지 그대로 옮기고 데이터 셋째 행의 본문만 비운다
        let broken = sampleLayout(kind).header + 3
        let grid: [[String]] = (1...(table.rows.last?.number ?? 0)).map { number in
            let cells = table.rows.first { $0.number == number }?.cells ?? []
            return cells.enumerated().map { column, cell in
                switch cell {
                case .text(let text), .number(let text): number == broken && column == 2 ? "" : text
                case .blank, .unsupported: ""
                }
            }
        }
        let workbook = WorkbookBuilder.workbook(grid: grid)
        let draft = try WorkbookHelper.draft(workbook)
        #expect(draft.skipped == [SkippedRecord(row: broken, reason: .emptyBody)])
        #expect(draft.skipped.first.map(PackImportCopy.skipTitle)?.hasPrefix("\(broken)번째 행 — ") == true)
        // 같은 표의 CSV — 빈 줄이 레코드 하나라 「n번째 항목」의 n이 같다
        #expect(PackVerdictResult.xlsx(workbook) == PackVerdictResult.csv(grid))
    }

    @Test("★ 실기 피드백 — 굵은 칸은 정보 줄 키(#이름·#틀·#출처)와 머리글 칸뿐 · 칸 스타일의 숫자 서식은 모두 일반(날짜·숫자로 오인 0)",
          arguments: PackSample.Kind.allCases)
    func boldMetaKeysAndHeader(_ kind: PackSample.Kind) throws {
        let styles = try SampleCellStyles(try bundledXLSXData(kind))
        let layout = sampleLayout(kind)
        #expect(styles.boldCells == Set((1...layout.meta).map { "A\($0)" } + ["A", "B", "C"].map { "\($0)\(layout.header)" }))
        #expect(!styles.numberFormats.isEmpty && styles.numberFormats.allSatisfy { $0 == 0 })
    }

    @Test("★ 실기 피드백 2 — 3-B 시트 그림은 번호형 샘플과 같은 모양: 정보 줄 셋 · 빈 행 하나 · 머리글(5행) · 굵은 칸이 샘플 xlsx와 같다 · 그대로 붙여 넣으면 팩이 된다")
    func guideSheetMatchesSample() throws {
        let sheet = PackImportCopy.guideSheet
        let layout = sampleLayout(.numbered)
        let headerRow = PackImportCopy.guideSheetHeaderRow
        #expect(headerRow + 1 == layout.header)
        #expect(sheet.prefix(layout.meta).allSatisfy { $0.first?.hasPrefix("#") == true })
        #expect(sheet[layout.meta] == ["", "", ""])
        #expect(sheet[headerRow] == ["번호", "제목", "본문"])
        let columns = ["A", "B", "C"]
        let bold = sheet.indices.flatMap { row in
            sheet[row].indices.filter { PackImportCopy.guideSheetIsBold(row: row, column: $0) }.map { "\(columns[$0])\(row + 1)" }
        }
        #expect(Set(bold) == (try SampleCellStyles(try bundledXLSXData(.numbered)).boldCells))
        // 그림을 표로 옮겨 붙여 넣은 꼴 — 정보 줄·빈 줄·머리글이 판정 규칙대로 읽힌다(문구가 말하는 규칙과 같다)
        let draft = try ImportHelper.draft(sheet.map { $0.joined(separator: "\t") }.joined(separator: "\n"))
        #expect(draft.mode == .numbered && draft.items.map(\.n) == [1, 12] && draft.skipped.isEmpty)
        #expect(draft.meta.name == "사자성어 예시 팩" && draft.meta.license == "제작자 자체 작성")
    }

    @Test("★ 실기 피드백 3(2026-10-08) — 표 영역(머리글 행~마지막 데이터 행 × 머리글 열)의 모든 칸에 네 변 가는 실선(자동 색) · 정보 줄·빈 행·열 기본 스타일에는 테두리 0",
          arguments: PackSample.Kind.allCases)
    func tableBorders(_ kind: PackSample.Kind) throws {
        let styles = try SampleCellStyles(try bundledXLSXData(kind))
        let table = sampleTableCells(kind)
        #expect(table.count == (kind == .numbered ? 63 : 48))
        #expect(styles.thinBoxCells == table)
        #expect(styles.anyBorderCells == table, "표 밖 테두리 \(styles.anyBorderCells.subtracting(table).sorted())")
        #expect(styles.decoratedColumns.isEmpty)
    }

    @Test("★ 실기 피드백 3 — 머리글 칸만 단색 연한 회색(FFD9D9D9) 채우기 · 글자는 그대로 굵게 · 다른 칸·열 기본 스타일에는 채우기 0",
          arguments: PackSample.Kind.allCases)
    func headerFill(_ kind: PackSample.Kind) throws {
        let styles = try SampleCellStyles(try bundledXLSXData(kind))
        let header = Set(["A", "B", "C"].map { "\($0)\(sampleLayout(kind).header)" })
        #expect(styles.grayFillCells == header)
        #expect(styles.anyFillCells == header, "머리글 밖 채우기 \(styles.anyFillCells.subtracting(header).sorted())")
        #expect(header.isSubset(of: styles.boldCells))
    }

    @Test("★ 실기 피드백 3 — 테두리·채우기는 값·종류 판정에 영향 없음: 번호 열 데이터만 숫자 칸, 나머지는 글 칸 · 날짜(지원 안 함)·빈 칸 0",
          arguments: PackSample.Kind.allCases)
    func decorationKeepsCellKinds(_ kind: PackSample.Kind) throws {
        var reader = try XLSXWorkbookReader.open(try bundledXLSXData(kind))
        let table = try reader.table(for: try #require(reader.sheets.first))
        let header = sampleLayout(kind).header
        var numbers = 0
        for row in table.rows {
            for (column, cell) in row.cells.enumerated() {
                let numberColumn = kind == .numbered && column == 0 && row.number > header
                switch cell {
                case .number: numbers += 1; #expect(numberColumn, "\(row.number)행 \(column + 1)열")
                case .text: #expect(!numberColumn, "\(row.number)행 \(column + 1)열")
                case .blank, .unsupported: Issue.record("\(row.number)행 \(column + 1)열: \(cell)")
                }
            }
        }
        #expect(numbers == (kind == .numbered ? 20 : 0))
    }

    @Test("★ 실기 피드백 3 — 3-B 시트 그림의 테두리 칸·채우기 칸이 번호형 샘플 xlsx와 같다(그림이 보이는 행까지 — 표 영역 · 머리글 칸)")
    func guideSheetDecorationMatchesSample() throws {
        let sheet = PackImportCopy.guideSheet
        let styles = try SampleCellStyles(try bundledXLSXData(.numbered))
        let columns = ["A", "B", "C"]
        func cells(_ rule: (Int, Int) -> Bool) -> Set<String> {
            Set(sheet.indices.flatMap { row in sheet[row].indices.filter { rule(row, $0) }.map { "\(columns[$0])\(row + 1)" } })
        }
        let shown = { (reference: String) in (Int(reference.dropFirst()) ?? .max) <= sheet.count }
        #expect(cells(PackImportCopy.guideSheetHasBorder(row:column:)) == styles.thinBoxCells.filter(shown))
        #expect(cells(PackImportCopy.guideSheetIsFilled(row:column:)) == styles.grayFillCells.filter(shown))
        // 그림의 표 영역은 머리글과 항목 둘 — 3행 × 3칸
        #expect(cells(PackImportCopy.guideSheetHasBorder(row:column:)).count == 9)
    }

    @Test("★ 번들 xlsx 샘플은 그대로 팩이 된다 — 번들 CSV와 같은 판정 · 시트 이름이 팩 이름 기본값이지만 `#이름`이 이긴다 · 파일 출처가 미리 골라진다",
          arguments: PackSample.Kind.allCases)
    func importsCleanly(_ kind: PackSample.Kind) throws {
        guard case .draft(let draft) = try PackImporter.readWorkbook(try bundledXLSXData(kind), sheet: nil) else {
            Issue.record("시트를 물었다")
            return
        }
        let csv = try Data(contentsOf: try #require(PackCopySet.$previewing.withValue(.csv) { csvFile(kind).bundledURL }))
        guard case .draft(let fromCSV) = try PackImporter.read(csv) else {
            Issue.record("구분자를 물었다")
            return
        }
        #expect(PackVerdict(draft) == PackVerdict(fromCSV))
        #expect(draft.skipped.isEmpty && draft.sheetName == resourceName(kind) && draft.hiddenRowCount == 0 && draft.hiddenColumnCount == 0)
        let form = PackImportForm(draft: draft)
        #expect(form.licenseChoice == .fromFile && form.isComplete)
        let pack = try PackCompiler.compile(draft, form: form.packForm)
        #expect(pack.name == (kind == .numbered ? "사자성어 예시 팩" : "업무 상용구 예시"))
        #expect(pack.license == "글쇠 고정 샘플 — 자체 작성 문구(가짜 내용)")
    }
}

// 1-e ④ 판별 규칙 — 번들 샘플 폴더의 파일은 **확장자(형식)로 판에 속한다.** 판이 내보내는 형식(`PackCopySet.Lines.sampleFormats`)만
// `PackSample.File.bundledURL`로 꺼낼 수 있다 → CSV 전용판은 xlsx 샘플이 번들에 있어도 알약·공유 사본에 닿지 않는다(AC-35 — 문구 검사는 `PackCopyLintTests`)
@Suite("외부 채움글 1-e ④ — 샘플은 판이 내보내는 형식만 꺼낸다 (AC-35 판별 규칙)")
struct PackSampleEditionTests {

    @Test("★ CSV 전용판 — xlsx 샘플은 번들에 있어도 꺼내지 못한다(URL 없음·공유 사본 실패), 알약은 CSV뿐", arguments: PackSample.Kind.allCases)
    func csvEditionHidesWorkbookSamples(_ kind: PackSample.Kind) throws {
        #expect(try !bundledXLSXData(kind).isEmpty, "번들에는 있다")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleEditionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        PackCopySet.$previewing.withValue(.csv) {
            #expect(PackSample.files(kind).map(\.format) == [.csv])
            #expect(xlsxFile(kind).bundledURL == nil)
            #expect(csvFile(kind).bundledURL != nil)
            #expect(throws: CocoaError.self) { _ = try PackSample.exportCopy(xlsxFile(kind), into: directory) }
        }
    }

    @Test("★ xlsx 중심판 — 알약 [엑셀][CSV], xlsx 샘플을 꺼내고 공유 사본은 「번호형 샘플.xlsx」로 바이트 그대로", arguments: PackSample.Kind.allCases)
    func xlsxEditionSharesWorkbookSamples(_ kind: PackSample.Kind) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleEditionTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try PackCopySet.$previewing.withValue(.xlsx) {
            #expect(PackSample.files(kind) == [xlsxFile(kind), csvFile(kind)])
            let url = try #require(xlsxFile(kind).bundledURL)
            #expect(try Data(contentsOf: url) == (try bundledXLSXData(kind)))
            let copy = try PackSample.exportCopy(xlsxFile(kind), into: directory)
            #expect(copy.lastPathComponent == "\(PackImportCopy.sampleTitle(kind)).xlsx")
            #expect(try Data(contentsOf: copy) == (try bundledXLSXData(kind)))
        }
    }
}

@Suite("외부 채움글 1-c 6단계 ⑤ — 샘플 받기(3-C 공유 시트)")
struct PackSampleShareTests {

    @Test("★ 보이는 파일 이름은 시안 3-C 그대로 — 「번호형 샘플.csv」「문구형 샘플.csv」(번들 속 이름은 영어)")
    func displayNames() {
        #expect(csvFile(.numbered).displayName == "번호형 샘플.csv")
        #expect(csvFile(.phrases).displayName == "문구형 샘플.csv")
        #expect(csvFile(.numbered).bundledURL?.lastPathComponent == "sample-numbered.csv")
        #expect(PackImportCopy.sampleTitle(.numbered) == "번호형 샘플" && PackImportCopy.sampleTitle(.phrases) == "문구형 샘플")
        // 3-A 줄 제목만 「… 받기」(사장님 실기 2026-10-08) — 파일 이름·알약의 손쉬운 사용 이름은 `sampleTitle` 그대로
        #expect(PackImportCopy.sampleRowTitle(.numbered) == "번호형 샘플 받기" && PackImportCopy.sampleRowTitle(.phrases) == "문구형 샘플 받기")
        #expect(xlsxFile(.numbered).displayName == "번호형 샘플.xlsx" && xlsxFile(.phrases).displayName == "문구형 샘플.xlsx")
        #expect(PackImportCopy.sampleShareLabel(xlsxFile(.numbered)) == "번호형 샘플 엑셀 받기")
        #expect(PackImportCopy.sampleShareLabel(csvFile(.phrases)) == "문구형 샘플 CSV 받기")
        #expect(PackImportCopy.sampleDetail(.numbered) == "사자성어 + 번호로 치면 문구가 떠요")
        #expect(PackImportCopy.sampleDetail(.phrases) == "단축어를 치면 문구가 떠요")
        #expect(PackImportCopy.sampleFormatLabel(.csv) == "CSV" && PackImportCopy.sampleFormatLabel(.xlsx) == "엑셀")
        #expect(PackImportCopy.sampleShareLabel(csvFile(.numbered)) == "번호형 샘플 CSV 받기")
    }

    @Test("★ 공유 사본 — 보이는 이름으로 바이트 그대로 복사하고, 다시 만들어도(덮어써도) 같다")
    func exportCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleShareTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        for kind in PackSample.Kind.allCases {
            let file = csvFile(kind)
            let bundled = try Data(contentsOf: try #require(file.bundledURL))
            let first = try PackSample.exportCopy(file, into: directory)
            #expect(first.lastPathComponent == file.displayName)
            #expect(try Data(contentsOf: first) == bundled)
            let again = try PackSample.exportCopy(file, into: directory)
            #expect(again == first)
            #expect(try Data(contentsOf: again) == bundled)
        }
    }

    // 준비는 전역 큐에서 돌아 `$previewing`(작업 지역 값)이 닿지 않는다 — 늘 이 빌드의 판(`selected`)을 따른다. 그래서 CSV 전용판이 xlsx를
    // 꺼내지 않는 것은 준비가 부르는 `exportCopy` 층에서 본다(`PackSampleEditionTests.csvEditionHidesWorkbookSamples`)
    @Test("공유 준비(메인 밖) — 판이 꺼낼 수 있는 파일만 준비된다. 지금 판(1.3.0 — xlsx 중심판, R38)은 번들의 xlsx 샘플도 꺼낸다(1-e ④)")
    func prepareForSharing() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PackSampleShareTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let xlsx = PackSample.File(kind: .numbered, format: .xlsx)
        #expect(PackCopySet.selected == .xlsx && xlsx.bundledURL != nil)
        let prepared = await PackSample.prepareForSharing([csvFile(.numbered), csvFile(.phrases), xlsx], into: directory)
        #expect(Set(prepared.keys) == [csvFile(.numbered), csvFile(.phrases), xlsx])
        #expect(prepared[csvFile(.phrases)]?.lastPathComponent == "문구형 샘플.csv")
        #expect(prepared[xlsx]?.lastPathComponent == "번호형 샘플.xlsx")
    }
}
