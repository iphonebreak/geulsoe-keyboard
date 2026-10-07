import Foundation

/// xlsx 파트 XML을 **안전하게** 훑는다 — 외부 채움글 1-e ②(PDR 6-5 「XML」 표, AC-30).
///
/// - **사전 바이트 스캔**(`prescan`): `<!DOCTYPE`·`<!ENTITY`가 있으면 파서에 넘기기 전에 거부한다(XXE·엔티티 폭탄).
///   바이트 스캔이 비켜 가지 않게 **UTF-8만** 받는다 — UTF-16·NUL 바이트·다른 선언 인코딩·첫 글자가 ASCII `<`가 아닌 문서는 거부.
/// - **파서**: Foundation `XMLParser`(SAX). 외부 엔티티 해석은 끈다(`shouldResolveExternalEntities = false`,
///   `externalEntityResolvingPolicy = .never` — 애플 문서 「The parser should never resolve external entities」). 선언 콜백이 오면
///   대리자가 멈춘다(이중 방어). **실측**(1-e ②): 이 설정에서 외부 엔티티 선언은 보고되지 않고 참조는 빈 글로 사라진다 — 내용은 새지 않는다.
/// - **깊이** ≤ 상한(32): 건너뛰는 모르는 요소 안의 깊이도 센다.
/// - **시작 태그당 속성 수** ≤ 상한(64, xmlns 포함): 사전 스캔이 센다 — libxml2 2.9의 속성 중복 검사가 제곱 시간이고, 한 시작 태그 안의 일이라
///   대리자가 끊을 수 없다(보안 검토 S2, 모르는 요소도 파서는 끝까지 읽는다).
/// - **모르는 요소는 하위 트리째 건너뛴다**(6-5b) — 처리기가 `false`를 돌려주면 그 요소가 닫힐 때까지 아무것도 넘기지 않는다.
/// - 네임스페이스를 처리한다: 요소는 (네임스페이스, 로컬 이름), 접두 붙은 속성은 접두 대응표로 네임스페이스를 푼다(`r:id`의 `r`을 글자로 믿지 않는다).
enum XLSXXML {

    /// SpreadsheetML 본문 — 과도기(Transitional)·엄격(Strict) 둘 다
    static let spreadsheetNamespaces: Set<String> = [
        "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
        "http://purl.oclc.org/ooxml/spreadsheetml/main",
    ]
    /// `r:id`의 관계 네임스페이스 — 과도기·엄격
    static let officeRelationshipNamespaces: Set<String> = [
        "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
        "http://purl.oclc.org/ooxml/officeDocument/relationships",
    ]
    static let packageRelationshipsNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
    static let contentTypesNamespace = "http://schemas.openxmlformats.org/package/2006/content-types"

    struct Element: Equatable {
        /// 네임스페이스 URI — 없으면 nil
        let namespace: String?
        /// 로컬 이름(접두 없이)
        let name: String
    }

    /// 요소의 속성 — 접두 없는 속성은 네임스페이스가 없다(XML Namespaces 1.0)
    struct Attributes {
        fileprivate var entries: [(namespace: String?, name: String, value: String)] = []

        /// 접두 없는 속성
        subscript(_ name: String) -> String? {
            entries.first { $0.namespace == nil && $0.name == name }?.value
        }

        /// 이 네임스페이스들 중 하나에 든 그 이름의 속성 값 전부 — 하나가 아니면 부르는 쪽이 모호성으로 다룬다
        func values(_ name: String, in namespaces: Set<String>) -> [String] {
            entries.filter { $0.name == name && $0.namespace.map(namespaces.contains) == true }.map(\.value)
        }
    }

    static func parse(_ data: Data, maxDepth: Int, maxAttributes: Int, handler: some XLSXXMLHandler) throws(XLSXWorkbookFailure) {
        try prescan(data, maxAttributes: maxAttributes)
        try runParser(data, maxDepth: maxDepth, handler: handler)
    }

    // MARK: 사전 바이트 스캔

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    static func prescan(_ data: Data, maxAttributes: Int = XLSXWorkbookLimits.product.attributesPerElement) throws(XLSXWorkbookFailure) {
        let bytes = [UInt8](data)
        let start = bytes.starts(with: utf8BOM) ? utf8BOM.count : 0
        // UTF-16·UTF-32는 ASCII 표기에 0 바이트가 낀다 — 바이트 스캔이 `<\0!\0D…`를 못 보므로 받지 않는다
        if bytes.contains(0) { throw .unsupportedTextEncoding }
        var first = start
        while first < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[first]) { first += 1 }
        guard first < bytes.count else { throw .malformedXML }
        // EBCDIC 등 — 첫 글자가 ASCII `<`(0x3C)가 아니면 ASCII 바이트 스캔이 의미 없다
        guard bytes[first] == 0x3C else { throw .unsupportedTextEncoding }
        try checkDeclaredEncoding(bytes, from: first)
        // `<!` 뒤 DOCTYPE·ENTITY(대소문자 무시). CDATA·주석 안의 같은 글자도 거부한다(보수 — 정상 파트에는 없다, P-10 실측 0건)
        var index = first
        while index + 1 < bytes.count {
            if bytes[index] == 0x3C, bytes[index + 1] == 0x21,
               matches(bytes, at: index + 2, "doctype") || matches(bytes, at: index + 2, "entity") {
                throw .doctypeOrEntity
            }
            index += 1
        }
        try countAttributes(bytes, from: first, limit: maxAttributes)
    }

    /// 시작 태그마다 **따옴표 밖의 `=`**를 센다(속성·xmlns 선언 하나에 하나) — 상한을 넘으면 거부(S2). 따옴표를 아는 작은 상태 기계다:
    /// 속성 값 안의 `>`(XML이 허용)로 태그를 쪼개 우회할 수 없고, 태그 밖 본문의 `=`(「======」 구분선)는 세지 않는다.
    /// 주석·CDATA·처리 명령·`<!…>`·끝 태그는 건너뛴다(본문에는 날 `<`가 올 수 없으니 `<`가 곧 표지의 시작이다). 형식 오류는 파서 몫이다
    private static func countAttributes(_ bytes: [UInt8], from start: Int, limit: Int) throws(XLSXWorkbookFailure) {
        let lessThan: UInt8 = 0x3C, greaterThan: UInt8 = 0x3E, equals: UInt8 = 0x3D
        let doubleQuote: UInt8 = 0x22, singleQuote: UInt8 = 0x27, bang: UInt8 = 0x21, question: UInt8 = 0x3F, slash: UInt8 = 0x2F
        var index = start
        while index < bytes.count {
            guard bytes[index] == lessThan, index + 1 < bytes.count else { index += 1; continue }
            switch bytes[index + 1] {
            case bang:
                if matches(bytes, at: index, "<!--") {
                    index = skip(past: Array("-->".utf8), in: bytes, from: index + 4)
                } else if matches(bytes, at: index, "<![cdata[") {
                    index = skip(past: Array("]]>".utf8), in: bytes, from: index + 9)
                } else {
                    index = skip(past: [greaterThan], in: bytes, from: index + 2)
                }
            case question:
                index = skip(past: Array("?>".utf8), in: bytes, from: index + 2)
            case slash:
                index = skip(past: [greaterThan], in: bytes, from: index + 2)
            default:
                // 시작 태그 — 따옴표 밖 `>`에서 끝난다
                var count = 0
                var quote: UInt8?
                index += 1
                while index < bytes.count {
                    let byte = bytes[index]
                    index += 1
                    if let open = quote {
                        if byte == open { quote = nil }
                    } else if byte == doubleQuote || byte == singleQuote {
                        quote = byte
                    } else if byte == equals {
                        count += 1
                        if count > limit { throw .tooManyAttributes }
                    } else if byte == greaterThan {
                        break
                    }
                }
            }
        }
    }

    /// `needle` 바로 뒤 자리 — 없으면 끝
    private static func skip(past needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int {
        firstIndex(of: needle, in: bytes, from: start).map { $0 + needle.count } ?? bytes.count
    }

    /// `<?xml … encoding="…"?>`가 있으면 UTF-8이어야 한다
    private static func checkDeclaredEncoding(_ bytes: [UInt8], from start: Int) throws(XLSXWorkbookFailure) {
        guard matches(bytes, at: start, "<?xml"), let close = firstIndex(of: [0x3F, 0x3E], in: bytes, from: start) else { return }
        let declaration = String(decoding: bytes[start..<close], as: UTF8.self)
        guard let range = declaration.range(of: "encoding") else { return }
        var rest = declaration[range.upperBound...].drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard rest.first == "=" else { throw .malformedXML }
        rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        guard let quote = rest.first, quote == "\"" || quote == "'" else { throw .malformedXML }
        let value = rest.dropFirst().prefix { $0 != quote }.lowercased()
        guard value == "utf-8" || value == "utf8" else { throw .unsupportedTextEncoding }
    }

    /// ASCII 대소문자 무시 비교(`word`는 소문자)
    private static func matches(_ bytes: [UInt8], at index: Int, _ word: String) -> Bool {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count else { return false }
        for offset in expected.indices {
            let byte = bytes[index + offset]
            let lowered = (0x41...0x5A).contains(byte) ? byte | 0x20 : byte
            if lowered != expected[offset] { return false }
        }
        return true
    }

    private static func firstIndex(of needle: [UInt8], in bytes: [UInt8], from start: Int) -> Int? {
        var index = start
        while index + needle.count <= bytes.count {
            if bytes[index] == needle[0], bytes[index..<(index + needle.count)].elementsEqual(needle) { return index }
            index += 1
        }
        return nil
    }

    // MARK: 파서

    /// 사전 스캔 없이 파서만 돌린다 — 제품 경로는 `parse`, 시험은 이중 방어(파서 설정·대리자)를 따로 확인하려고 이것을 부른다
    static func runParser(_ data: Data, maxDepth: Int, handler: some XLSXXMLHandler) throws(XLSXWorkbookFailure) {
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        let driver = Driver(handler: handler, maxDepth: maxDepth)
        parser.delegate = driver
        let completed = parser.parse()
        if let failure = driver.failure { throw failure }
        guard completed else { throw .malformedXML }
    }

    /// `XMLParser` 대리자 — 처리기의 오류는 첫 것만 남기고 파싱을 멈춘다
    private final class Driver: NSObject, XMLParserDelegate {
        private let handler: any XLSXXMLHandler
        private let maxDepth: Int
        private var depth = 0
        /// 건너뛰는 하위 트리의 뿌리 깊이
        private var skippingFrom: Int?
        /// 접두 → 네임스페이스(겹쳐 선언되면 안쪽이 이긴다)
        private var prefixes: [String: [String]] = ["xml": ["http://www.w3.org/XML/1998/namespace"]]
        private(set) var failure: XLSXWorkbookFailure?

        init(handler: any XLSXXMLHandler, maxDepth: Int) {
            self.handler = handler
            self.maxDepth = maxDepth
        }

        private func fail(_ parser: XMLParser, _ reason: XLSXWorkbookFailure) {
            guard failure == nil else { return }
            failure = reason
            parser.abortParsing()
        }

        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            prefixes[prefix, default: []].append(namespaceURI)
        }

        func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) {
            prefixes[prefix]?.removeLast()
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            guard failure == nil else { return }
            depth += 1
            guard depth <= maxDepth else { return fail(parser, .nestingTooDeep) }
            guard skippingFrom == nil else { return }
            var attributes = Attributes()
            for (key, value) in attributeDict {
                if let colon = key.firstIndex(of: ":") {
                    let prefix = String(key[..<colon])
                    // 대응이 없는 접두는 어떤 네임스페이스와도 맞지 않게 둔다
                    attributes.entries.append((prefixes[prefix]?.last ?? "", String(key[key.index(after: colon)...]), value))
                } else {
                    attributes.entries.append((nil, key, value))
                }
            }
            let element = Element(namespace: namespaceURI.flatMap { $0.isEmpty ? nil : $0 }, name: elementName)
            do {
                if try !handler.start(element, attributes: attributes) { skippingFrom = depth }
            } catch {
                fail(parser, error)
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard failure == nil else { return }
            defer { depth -= 1 }
            if let root = skippingFrom {
                if root == depth { skippingFrom = nil }
                return
            }
            do {
                try handler.end(Element(namespace: namespaceURI.flatMap { $0.isEmpty ? nil : $0 }, name: elementName))
            } catch {
                fail(parser, error)
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            deliver(parser, string)
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            deliver(parser, String(decoding: CDATABlock, as: UTF8.self))
        }

        private func deliver(_ parser: XMLParser, _ string: String) {
            guard failure == nil, skippingFrom == nil else { return }
            do {
                try handler.characters(string)
            } catch {
                fail(parser, error)
            }
        }

        // 선언 콜백 — 사전 스캔이 이미 거부하지만 여기 오면 멈춘다(이중 방어)
        func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, foundUnparsedEntityDeclarationWithName name: String, publicID: String?,
                    systemID: String?, notationName: String?) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, foundElementDeclarationWithName elementName: String, model: String) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, foundAttributeDeclarationWithName attributeName: String, forElement elementName: String,
                    type: String?, defaultValue: String?) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, foundNotationDeclarationWithName name: String, publicID: String?, systemID: String?) {
            fail(parser, .doctypeOrEntity)
        }

        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? {
            fail(parser, .doctypeOrEntity)
            return nil
        }
    }
}

/// 파트 하나를 읽는 처리기 — 오류를 던지면 파싱이 멈춘다
protocol XLSXXMLHandler: AnyObject {
    /// `false`면 이 요소의 하위 트리를 건너뛴다(모르는 요소 — 6-5b). 그 요소의 `end`도 오지 않는다
    func start(_ element: XLSXXML.Element, attributes: XLSXXML.Attributes) throws(XLSXWorkbookFailure) -> Bool
    func end(_ element: XLSXXML.Element) throws(XLSXWorkbookFailure)
    func characters(_ string: String) throws(XLSXWorkbookFailure)
}

// MARK: - 글

/// 셀 글의 6-4 줄바꿈 순서 계약 — ① XML 파서가 줄끝을 정규화(생 CRLF → LF, `XMLParser`가 한다)
/// ② `_xHHHH_`를 왼쪽부터 **한 번만** 푼다(`decodeEscapes`) ③ 남은 CRLF·CR → LF(`normalizeNewlines`).
/// 윈도우 엑셀 `_x000D_` + 생 CRLF, Mac 엑셀 생 CRLF, 구글 LF가 모두 LF 하나가 된다(P-10 실측). 순서가 바뀌면 CR이 남는다
enum XLSXText {

    /// ECMA-376 ST_Xstring의 `_xHHHH_`(UTF-16 코드 단위) — 풀린 결과를 다시 풀지 않는다(`_x005F_x000D_` → `_x000D_`).
    /// 서로게이트 쌍은 한 글자로 합치고, 홀로 선 서로게이트는 이스케이프 글자 그대로 둔다(버리지 않는다)
    static func decodeEscapes(_ text: String) -> String {
        guard text.contains("_x") else { return text }
        let scalars = Array(text.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard let value = escape(scalars, at: index) else {
                output.append(scalars[index])
                index += 1
                continue
            }
            if (0xD800...0xDBFF).contains(value), let low = escape(scalars, at: index + 7), (0xDC00...0xDFFF).contains(low),
               let scalar = Unicode.Scalar(0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)) {
                output.append(scalar)
                index += 14
            } else if let scalar = Unicode.Scalar(value) {
                output.append(scalar)
                index += 7
            } else {
                output.append(contentsOf: scalars[index..<(index + 7)])
                index += 7
            }
        }
        return String(output)
    }

    /// `_x` + 16진 4자리 + `_` 이면 그 값
    private static func escape(_ scalars: [Unicode.Scalar], at index: Int) -> UInt32? {
        guard index + 7 <= scalars.count, scalars[index] == "_", scalars[index + 1] == "x", scalars[index + 6] == "_" else { return nil }
        var value: UInt32 = 0
        for scalar in scalars[(index + 2)..<(index + 6)] {
            guard let digit = scalar.properties.isASCIIHexDigit ? UInt32(String(scalar), radix: 16) : nil else { return nil }
            value = value << 4 | digit
        }
        return value
    }

    /// CRLF·CR → LF
    static func normalizeNewlines(_ text: String) -> String {
        guard text.unicodeScalars.contains("\r") else { return text }
        var output = String.UnicodeScalarView()
        var afterCR = false
        for scalar in text.unicodeScalars {
            if scalar == "\r" {
                output.append("\n")
                afterCR = true
            } else {
                if !(scalar == "\n" && afterCR) { output.append(scalar) }
                afterCR = false
            }
        }
        return String(output)
    }
}
