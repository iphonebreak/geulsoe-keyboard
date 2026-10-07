import Foundation
import TadakDomain

/// xlsx를 `RawTable`로 읽는다 — 외부 채움글 1-e ②(PDR `external-snippet-packs.md` 6-1·6-4·6-5·6-5b, AC-30·31·34·36).
///
/// - 컨테이너는 ①(`XLSXArchive`)이 메모리에서 연다. 여기서는 **관계(rels)를 따라** 파트 이름을 정하고 ①에 **이름 완전 일치**로 읽게 한다
///   — 관계 id·엔트리 순서를 가정하지 않는다(구글 `rId5`, `[Content_Types].xml`이 맨 끝).
///   `[Content_Types].xml` → `_rels/.rels`(officeDocument) → 워크북(본문 콘텐츠 타입 확인 — **매크로 포함이면 거부**) → 워크북 관계 →
///   시트·공유 문자열·스타일. 대상 경로는 상대 경로를 풀고 `..`·외부·스킴·역슬래시를 거부한다. 고정된 깊이만 따라가므로 순환 관계가 루프를
///   만들지 않고, 엉뚱한 파트를 가리키면 루트 요소가 달라 거부된다.
/// - **숨김 시트**(`hidden`·`veryHidden`)·차트 시트는 `sheets`에 없다(6-4·AC-36 — `state` 생략 = 표시).
/// - XML은 `XLSXXML`(사전 스캔·SAX·깊이)로 읽고, 모르는 요소는 하위 트리째 건너뛴다(엑셀 `mc:AlternateContent`의 저장 경로 등 — 읽지도 두지도 않는다).
/// - 실패는 **내용 없는 코드**다(`XLSXWorkbookFailure`) — 파일 바이트·셀 글·시트 이름·파트 이름을 담지 않는다(AC-34). 로그도 쓰지 않는다.
///
/// 결과 표는 CSV와 같은 판정 경로(헤더·메타 → 행별 검증 → 예산)에 들어간다 — 그 연결은 1-e ③이다.
public struct XLSXWorkbookReader: Sendable {

    /// 표시 시트 하나 — 이름은 사용자가 지은 글이라 팩 이름 기본값에만 쓰고 로그·분석에는 쓰지 않는다(6-4)
    public struct Sheet: Equatable, Sendable {
        /// `_xHHHH_`를 푼 시트 이름
        public let name: String
        /// 아카이브 안 시트 파트 이름(관계로 푼 것)
        let part: String

        /// 팩 이름 칸의 기본값 — 엑셀 `Sheet1`, 구글 `시트1`처럼 앱이 붙인 이름이면 비워 둔다(6-4 P-10 보강 `[판단]`)
        public var suggestedPackName: String? { Self.suggestedPackName(forSheetName: name) }

        /// 앞뒤 공백을 뗀 이름. 비었거나 `Sheet1`·`Sheet N`·`시트1`·`시트 N` 꼴(대소문자 무시, 숫자 앞 공백 하나까지)이면 nil
        public static func suggestedPackName(forSheetName name: String) -> String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lowered = trimmed.lowercased()
            for prefix in ["sheet", "시트"] where lowered.hasPrefix(prefix) {
                var rest = lowered.dropFirst(prefix.count)
                if rest.first == " " { rest = rest.dropFirst() }
                if !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isNumber }) { return nil }
            }
            return trimmed
        }
    }

    /// 표시 워크시트 — 워크북에 적힌 순서. 기본 = 첫 시트(AC-36)
    public let sheets: [Sheet]
    public let limits: XLSXWorkbookLimits
    private var archive: XLSXArchive
    private let sharedStrings: [String]
    private let styles: XLSXCellStyles

    /// 컨테이너를 열고 워크북·관계·공유 문자열·스타일을 읽는다 — 시트 본문은 `table(for:)`가 읽는다
    public static func open(_ data: Data, limits: XLSXWorkbookLimits = .product) throws(XLSXWorkbookFailure) -> XLSXWorkbookReader {
        var archive: XLSXArchive
        do {
            archive = try XLSXArchive.open(data, limits: limits.archive)
        } catch {
            throw .archive(error)
        }

        let types = ContentTypesHandler()
        try parse(&archive, "[Content_Types].xml", as: .contentTypes, missing: .notSpreadsheet, limits: limits, handler: types)

        let rootRelationships = RelationshipsHandler()
        try parse(&archive, "_rels/.rels", as: .relationships, missing: .notSpreadsheet, limits: limits, handler: rootRelationships)
        let documents = rootRelationships.relationships.filter { $0.kind == "officeDocument" }
        guard let document = documents.first else { throw .notSpreadsheet }
        guard documents.count == 1 else { throw .brokenRelationship }
        let workbookPart = try resolve(document, from: "")

        // 본문 콘텐츠 타입(6-4 「매크로」) — OPC 파트 이름은 대소문자를 가리지 않는다
        guard let contentType = types.contentType(of: workbookPart)?.lowercased() else { throw .notSpreadsheet }
        if contentType.contains("macroenabled") { throw .macroEnabled }
        guard workbookContentTypes.contains(contentType) else { throw .notSpreadsheet }

        let workbook = WorkbookHandler(limits: limits)
        try parse(&archive, workbookPart, as: .workbook, missing: .brokenRelationship, limits: limits, handler: workbook)
        let directory = (workbookPart as NSString).deletingLastPathComponent
        let file = (workbookPart as NSString).lastPathComponent
        let relationshipsPart = (directory.isEmpty ? "" : directory + "/") + "_rels/\(file).rels"
        let workbookRelationships = RelationshipsHandler()
        try parse(&archive, relationshipsPart, as: .relationships, missing: .brokenRelationship, limits: limits, handler: workbookRelationships)
        let byID = Dictionary(workbookRelationships.relationships.map { ($0.id, $0) }) { first, _ in first }

        var sheets: [Sheet] = []
        var usedParts = Set<String>()
        for entry in workbook.sheets {
            guard let relationship = byID[entry.relationshipID] else { throw .brokenRelationship }
            switch relationship.kind {
            case "worksheet", "chartsheet", "dialogsheet": break
            case "xlMacrosheet", "xlIntlMacrosheet": throw .macroEnabled
            default: throw .brokenRelationship
            }
            let part = try resolve(relationship, from: directory)
            guard archive.contains(part), usedParts.insert(part).inserted else { throw .brokenRelationship }
            if relationship.kind == "worksheet", entry.isVisible { sheets.append(Sheet(name: entry.name, part: part)) }
        }
        guard !sheets.isEmpty else { throw .noVisibleSheet }

        let strings = SharedStringsHandler(limits: limits)
        if let part = try optionalPart("sharedStrings", in: workbookRelationships, from: directory) {
            try parse(&archive, part, as: .sharedStrings, missing: .brokenRelationship, limits: limits, handler: strings)
        }
        let styles = StylesHandler()
        if let part = try optionalPart("styles", in: workbookRelationships, from: directory) {
            try parse(&archive, part, as: .styles, missing: .brokenRelationship, limits: limits, handler: styles)
        }
        return XLSXWorkbookReader(sheets: sheets, limits: limits, archive: archive, sharedStrings: strings.strings, styles: styles.result())
    }

    /// 시트 하나를 표로 읽는다 — 같은 시트를 다시 읽으면 컨테이너 해제 총량(①)에 다시 더해진다
    public mutating func table(for sheet: Sheet) throws(XLSXWorkbookFailure) -> RawTable {
        guard sheets.contains(sheet) else { throw .sheetNotFound }
        let handler = WorksheetHandler(limits: limits, sharedStrings: sharedStrings, styles: styles)
        try Self.parse(&archive, sheet.part, as: .worksheet, missing: .brokenRelationship, limits: limits, handler: handler)
        return handler.result()
    }

    // MARK: 관계·파트

    /// 워크북 본문 콘텐츠 타입 — 통합 문서(.xlsx)·서식 파일(.xltx)
    private static let workbookContentTypes: Set<String> = [
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.template.main+xml",
    ]

    private static func parse(_ archive: inout XLSXArchive, _ part: String, as kind: XLSXArchive.PartKind, missing: XLSXWorkbookFailure,
                              limits: XLSXWorkbookLimits, handler: some XLSXXMLHandler) throws(XLSXWorkbookFailure) {
        guard archive.contains(part) else { throw missing }
        let data: Data
        do {
            data = try archive.read(part, as: kind)
        } catch {
            throw .archive(error)
        }
        try XLSXXML.parse(data, maxDepth: limits.depth, maxAttributes: limits.attributesPerElement, handler: handler)
    }

    /// 그 종류 관계가 없으면 nil, 둘 이상이면 모호성 거부
    private static func optionalPart(_ kind: String, in relationships: RelationshipsHandler,
                                     from directory: String) throws(XLSXWorkbookFailure) -> String? {
        let matching = relationships.relationships.filter { $0.kind == kind }
        guard let relationship = matching.first else { return nil }
        guard matching.count == 1 else { throw .brokenRelationship }
        return try resolve(relationship, from: directory)
    }

    /// 관계 대상 → 아카이브 파트 이름. 절대(`/xl/…`)·상대(`worksheets/…`·`./…`)를 풀고, 외부·스킴(`:`)·`\`·`?`·`#`·`..`·빈 조각은 거부.
    /// **`%`도 거부한다**(보안 검토 S5) — 퍼센트 인코딩을 풀어 찾는 독자와 글자 그대로 찾는 우리가 다른 파트를 읽을 수 있다(정상 생성기 표본 0건, P-10)
    static func resolve(_ relationship: Relationship, from directory: String) throws(XLSXWorkbookFailure) -> String {
        guard relationship.targetMode.map({ $0.caseInsensitiveCompare("Internal") == .orderedSame }) ?? true else {
            throw .unsafeRelationshipTarget
        }
        let target = relationship.target
        guard !target.isEmpty, !target.contains(where: { "\\:?#%".contains($0) }) else { throw .unsafeRelationshipTarget }
        var segments = target.hasPrefix("/") ? [] : directory.split(separator: "/").map(String.init)
        for segment in (target.hasPrefix("/") ? target.dropFirst() : Substring(target)).split(separator: "/", omittingEmptySubsequences: false) {
            switch segment {
            case ".": continue
            case "", "..": throw .unsafeRelationshipTarget
            default: segments.append(String(segment))
            }
        }
        guard !segments.isEmpty else { throw .unsafeRelationshipTarget }
        return segments.joined(separator: "/")
    }
}

// MARK: - 상한

/// xlsx XML 상한 — PDR 6-5 「XML」 표(후보값). 컨테이너 상한은 ①의 `XLSXArchiveLimits`
public struct XLSXWorkbookLimits: Equatable, Sendable {
    public var archive: XLSXArchiveLimits
    /// 요소 깊이 ≤ 32
    public var depth: Int
    /// 스캔 행(`<row>` 요소) ≤ 20,000 — 빈 행도 센다
    public var scannedRows: Int
    /// 셀(`<c>` 요소) ≤ 100,000 — 서식만 있는 빈 셀도 센다
    public var cells: Int
    /// 공유 문자열 항목 ≤ 50,000
    public var sharedStrings: Int
    /// 글 하나(공유·인라인 문자열, 숫자 `<v>`)의 UTF-8 바이트 — **엑셀 셀 최대(32,767자) 쪽 131,072B**(1-e ③ 승인 메모 ③). 넘으면 엑셀이
    /// 만들 수 없는 파일이라 거부한다. 그 아래는 본문 상한(12,000B)을 넘어도 표에 싣고 **CSV와 같은 판정**이 자리별로 정한다(본문·제목은 그 행
    /// 건너뜀, 모르는 열은 받음, 정보 줄은 미리 채우지 않음 — AC-32). 공유 문자열 증폭은 표 글 합 상한(`tableTextBytes`, S3)이 묶는다
    public var textBytes: Int
    /// 시트 이름 UTF-8 바이트 — 엑셀은 31자, 넉넉히 255B(①의 엔트리 이름 상한과 같다) `[판단]`
    public var sheetNameBytes: Int
    /// 시작 태그 하나의 속성 수(xmlns 선언 포함) — 64 `[판단]`(보안 검토 S2: libxml2 2.9의 속성 중복 검사가 속성 수의 제곱 시간이라
    /// 1MB 파트 약 2초·8MB 파트 수 분. 번들 샘플 최댓값 9). 사전 스캔이 파서보다 먼저 센다
    public var attributesPerElement: Int
    /// 한 시트 표(`RawTable`)에 실린 글·숫자 칸의 UTF-8 합 — 파일 상한 × 2 = 6MB `[판단]`(보안 검토 S3: 공유 문자열 하나를 여러 칸이 가리키면
    /// 파일보다 훨씬 큰 글이 판정 경로로 들어간다. CSV는 파일 3MB가 곧 글 합의 상한이다 — 정상 팩은 예산 3MB를 넘을 수 없어 오거부가 없다)
    public var tableTextBytes: Int

    public init(archive: XLSXArchiveLimits, depth: Int, scannedRows: Int, cells: Int, sharedStrings: Int, textBytes: Int, sheetNameBytes: Int,
                attributesPerElement: Int = 64, tableTextBytes: Int = PackLimits.fileBytes * 2) {
        self.archive = archive
        self.depth = depth
        self.scannedRows = scannedRows
        self.cells = cells
        self.sharedStrings = sharedStrings
        self.textBytes = textBytes
        self.sheetNameBytes = sheetNameBytes
        self.attributesPerElement = attributesPerElement
        self.tableTextBytes = tableTextBytes
    }

    public static let product = XLSXWorkbookLimits(
        archive: .product, depth: 32, scannedRows: 20_000, cells: 100_000, sharedStrings: 50_000,
        textBytes: 131_072, sheetNameBytes: 255, attributesPerElement: 64, tableTextBytes: PackLimits.fileBytes * 2
    )
}

// MARK: - 실패

/// xlsx 읽기 거부 사유 — **내용 없는 열거형**(AC-34): 파일 바이트·셀 글·시트 이름·파트 이름·위치를 담지 않는다.
/// 사용자 문구는 가져오기 화면(1-e ③)이 이 코드에서 만든다
public enum XLSXWorkbookFailure: Error, Equatable, Sendable {
    /// 컨테이너(ZIP) 층 거부(①)
    case archive(XLSXArchiveFailure)
    /// `<!DOCTYPE`·`<!ENTITY`(사전 스캔) 또는 파서가 보고한 선언
    case doctypeOrEntity
    /// UTF-8이 아닌 XML(선언 인코딩·UTF-16·NUL 바이트·첫 글자가 ASCII `<`가 아님)
    case unsupportedTextEncoding
    /// XML 형식 오류(파서가 멈춤)
    case malformedXML
    /// 요소 깊이 상한 초과
    case nestingTooDeep
    /// 시작 태그 하나의 속성(xmlns 포함)이 상한을 넘는다(사전 스캔 — 보안 검토 S2)
    case tooManyAttributes
    /// 엑셀 통합 문서가 아니다(콘텐츠 타입·officeDocument 관계가 없거나 다른 문서 종류)
    case notSpreadsheet
    /// 매크로 포함 통합 문서(`…macroEnabled…` 콘텐츠 타입·XLM 매크로 시트)
    case macroEnabled
    /// 관계 대상이 외부·스킴·`..`·역슬래시·빈 경로
    case unsafeRelationshipTarget
    /// 관계가 없거나·겹치거나·모호하거나 가리키는 파트가 없다
    case brokenRelationship
    /// 파트의 루트 요소가 기대와 다르다(엉뚱한 파트를 가리킨 관계 포함)
    case unexpectedPart
    /// 파트 안 값이 형식에 맞지 않는다(속성 값·중복 정의·중복 요소)
    case malformedPart
    /// 표시 워크시트가 없다
    case noVisibleSheet
    /// 이 워크북의 시트가 아니다
    case sheetNotFound
    /// 스캔 행 상한 초과
    case tooManyRows
    /// 셀 상한 초과
    case tooManyCells
    /// 공유 문자열 항목 상한 초과
    case tooManySharedStrings
    /// 글 하나가 상한을 넘는다
    case textTooLong
    /// 한 시트 표에 실린 글의 합이 상한을 넘는다(공유 문자열 증폭 — 보안 검토 S3)
    case tooMuchText
    /// 공유 문자열 색인이 범위 밖·숫자 아님
    case invalidSharedStringIndex
    /// 스타일 색인이 범위 밖·숫자 아님
    case invalidStyleIndex
    /// 셀·행 참조가 형식·범위·순서에 맞지 않는다(거꾸로·중복·행 불일치)
    case invalidCellReference
    /// 모르는 셀 타입(`t`)
    case unknownCellType
    /// 병합 참조가 형식에 맞지 않는다
    case invalidMergeRange
}

// MARK: - 패키지 파트 처리기

/// 관계 하나 — `kind`는 Type URI의 마지막 조각(과도기·엄격 공통: `officeDocument`·`worksheet`·`sharedStrings`·`styles`…)
struct Relationship {
    let id: String
    let kind: String
    let target: String
    let targetMode: String?
}

/// 루트 요소 이름·네임스페이스가 기대와 같은가 — 아니면 엉뚱한 파트
private func checkRoot(_ element: XLSXXML.Element, _ name: String, in namespaces: Set<String>) throws(XLSXWorkbookFailure) {
    guard element.name == name, element.namespace.map(namespaces.contains) == true else { throw .unexpectedPart }
}

final class ContentTypesHandler: XLSXXMLHandler {
    private var depth = 0
    private var overrides: [String: String] = [:]
    private var defaults: [String: String] = [:]
    private let namespaces: Set<String> = [XLSXXML.contentTypesNamespace]

    /// 파트 이름의 콘텐츠 타입 — Override(대소문자 무시) → 확장자 Default
    func contentType(of part: String) -> String? {
        if let type = overrides[("/" + part).lowercased()] { return type }
        let name = (part as NSString).lastPathComponent
        guard let dot = name.lastIndex(of: ".") else { return nil }
        return defaults[String(name[name.index(after: dot)...]).lowercased()]
    }

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if depth == 0 { try checkRoot(element, "Types", in: namespaces) }
        if depth == 1, element.namespace.map(namespaces.contains) == true {
            switch element.name {
            case "Override":
                guard let part = attributes["PartName"], let type = attributes["ContentType"] else { throw .malformedPart }
                // 같은 파트에 타입이 둘이면 독자마다 다르게 읽는다(매크로 숨김)
                guard overrides.updateValue(type, forKey: part.lowercased()) == nil else { throw .malformedPart }
            case "Default":
                guard let fileExtension = attributes["Extension"], let type = attributes["ContentType"] else { throw .malformedPart }
                guard defaults.updateValue(type, forKey: fileExtension.lowercased()) == nil else { throw .malformedPart }
            default:
                return false
            }
        } else if depth >= 1 {
            return false
        }
        depth += 1
        return true
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) { depth -= 1 }
    func characters(_ string: String) throws(XLSXWorkbookFailure) {}
}

final class RelationshipsHandler: XLSXXMLHandler {
    private var depth = 0
    private var ids = Set<String>()
    private(set) var relationships: [Relationship] = []
    private let namespaces: Set<String> = [XLSXXML.packageRelationshipsNamespace]

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if depth == 0 { try checkRoot(element, "Relationships", in: namespaces) }
        if depth == 1 {
            guard element.name == "Relationship", element.namespace.map(namespaces.contains) == true else { return false }
            guard let id = attributes["Id"], let type = attributes["Type"], let target = attributes["Target"] else { throw .brokenRelationship }
            guard ids.insert(id).inserted else { throw .brokenRelationship }
            let kind = type.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            relationships.append(Relationship(id: id, kind: kind, target: target, targetMode: attributes["TargetMode"]))
        } else if depth > 1 {
            return false
        }
        depth += 1
        return true
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) { depth -= 1 }
    func characters(_ string: String) throws(XLSXWorkbookFailure) {}
}

final class WorkbookHandler: XLSXXMLHandler {
    struct Entry {
        let name: String
        let relationshipID: String
        let isVisible: Bool
    }

    private let limits: XLSXWorkbookLimits
    private var path: [String] = []
    private var sawSheets = false
    private(set) var sheets: [Entry] = []

    init(limits: XLSXWorkbookLimits) {
        self.limits = limits
    }

    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool {
        if path.isEmpty {
            try checkRoot(element, "workbook", in: XLSXXML.spreadsheetNamespaces)
        } else {
            guard element.namespace.map(XLSXXML.spreadsheetNamespaces.contains) == true else { return false }
            switch (path.last, element.name) {
            case ("workbook", "sheets"):
                guard !sawSheets else { throw .malformedPart }
                sawSheets = true
            case ("sheets", "sheet"):
                try readSheet(attributes)
            default:
                return false
            }
        }
        path.append(element.name)
        return true
    }

    private func readSheet(_ attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) {
        guard let raw = attributes["name"] else { throw .malformedPart }
        let name = XLSXText.decodeEscapes(raw)
        guard !name.isEmpty, name.utf8.count <= limits.sheetNameBytes else { throw .malformedPart }
        let visible: Bool
        switch attributes["state"] {
        case nil, "visible": visible = true
        case "hidden", "veryHidden": visible = false
        default: throw .malformedPart
        }
        let ids = attributes.values("id", in: XLSXXML.officeRelationshipNamespaces)
        guard ids.count == 1, let id = ids.first else { throw .brokenRelationship }
        sheets.append(Entry(name: name, relationshipID: id, isVisible: visible))
    }

    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure) { path.removeLast() }
    func characters(_ string: String) throws(XLSXWorkbookFailure) {}
}
