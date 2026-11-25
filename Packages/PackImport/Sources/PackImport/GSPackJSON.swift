import Foundation

/// 봉투 JSON 값 — 문자열은 **이스케이프를 푼 UTF-8 바이트**로 든다(키 비교·AAD가 바이트 단위라서).
///
/// 구문 단계(12-2 검사 순서 ⓑ)는 RFC 8259 문법을 다 읽는다 — 배열·`null`·불리언·소수도 **구문으로는** 받고,
/// 스키마 밖이라는 거부는 ⓔ가 한다. 그래야 구조가 다른 새 버전 봉투(`version` ≥ 2)가 「손상」(M1)이 아니라
/// 「새 버전」(M2)으로 끝난다(벡터 V18 「나머지 구조 임의」). 중복 키·깊이·BOM·짝 없는 서로게이트·쓰레기는 ⓑ에서 거부한다.
indirect enum GSPackJSONValue: Equatable, Sendable {
    case object([GSPackJSONMember])
    case array([GSPackJSONValue])
    case string([UInt8])
    /// 리터럴 원문 그대로 — 변환은 쓰는 쪽이 자릿수를 본 뒤에 한다(오버플로 방지)
    case number(literal: [UInt8], isInteger: Bool)
    case bool(Bool)
    case null
}

struct GSPackJSONMember: Equatable, Sendable {
    let key: [UInt8]
    let value: GSPackJSONValue
}

/// 이 스키마만 읽는 엄격 JSON 파서(12-2 「구현 권고」 — `JSONDecoder` 대신). 실패는 전부 M1이다.
///
/// - 파일 전체가 엄격 UTF-8이어야 한다(대체 문자로 복구하지 않는다). UTF-8 BOM으로 시작하면 거부
/// - 토큰 사이 공백은 `0x20·0x09·0x0A·0x0D`만
/// - 중복 키는 **이스케이프를 푼 바이트**로 비교한다 — Swift `String ==`은 정준 동치(`é` = `e`+U+0301)라 쓰지 않는다
/// - 중첩 깊이 `GSPackLimits.jsonMaxDepth` 초과는 그 자리에서 멈춘다(깊은 중첩으로 재귀가 폭주하지 않는다)
/// - 숫자는 JSON 문법 그대로(`+`·앞자리 0·`.5`·`1.` 거부), 리터럴 원문을 남긴다
struct GSPackJSONParser {

    private let bytes: [UInt8]
    private var index = 0

    private init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    static func parse(_ bytes: [UInt8]) throws(GSPackFailure) -> GSPackJSONValue {
        guard !bytes.starts(with: [0xEF, 0xBB, 0xBF]) else { throw .malformed }
        guard String(decoding: bytes, as: UTF8.self).utf8.elementsEqual(bytes) else { throw .malformed }
        var parser = GSPackJSONParser(bytes: bytes)
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.index == bytes.count else { throw .malformed }
        return value
    }

    // MARK: 값

    private mutating func parseValue(depth: Int) throws(GSPackFailure) -> GSPackJSONValue {
        guard let byte = peek() else { throw .malformed }
        switch byte {
        case Byte.openBrace: return try parseObject(depth: depth + 1)
        case Byte.openBracket: return try parseArray(depth: depth + 1)
        case Byte.quote: return .string(try parseString())
        case Byte.minus, Byte.zero...Byte.nine: return try parseNumber()
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        default: throw .malformed
        }
    }

    private mutating func parseObject(depth: Int) throws(GSPackFailure) -> GSPackJSONValue {
        guard depth <= GSPackLimits.jsonMaxDepth else { throw .malformed }
        index += 1
        skipWhitespace()
        var members: [GSPackJSONMember] = []
        if peek() == Byte.closeBrace {
            index += 1
            return .object(members)
        }
        var seenKeys = Set<[UInt8]>()
        while true {
            guard peek() == Byte.quote else { throw .malformed }
            let key = try parseString()
            guard seenKeys.insert(key).inserted else { throw .malformed }
            skipWhitespace()
            guard peek() == Byte.colon else { throw .malformed }
            index += 1
            skipWhitespace()
            members.append(GSPackJSONMember(key: key, value: try parseValue(depth: depth)))
            skipWhitespace()
            switch peek() {
            case Byte.comma:
                index += 1
                skipWhitespace()
            case Byte.closeBrace:
                index += 1
                return .object(members)
            default:
                throw .malformed
            }
        }
    }

    private mutating func parseArray(depth: Int) throws(GSPackFailure) -> GSPackJSONValue {
        guard depth <= GSPackLimits.jsonMaxDepth else { throw .malformed }
        index += 1
        skipWhitespace()
        var elements: [GSPackJSONValue] = []
        if peek() == Byte.closeBracket {
            index += 1
            return .array(elements)
        }
        while true {
            elements.append(try parseValue(depth: depth))
            skipWhitespace()
            switch peek() {
            case Byte.comma:
                index += 1
                skipWhitespace()
            case Byte.closeBracket:
                index += 1
                return .array(elements)
            default:
                throw .malformed
            }
        }
    }

    // MARK: 문자열

    /// 여는 따옴표에서 시작해 닫는 따옴표 뒤에서 끝난다. 이스케이프 없는 구간은 원래 바이트를 통째로 옮긴다
    private mutating func parseString() throws(GSPackFailure) -> [UInt8] {
        index += 1
        var output: [UInt8] = []
        var runStart = index
        while index < bytes.count {
            let byte = bytes[index]
            if byte == Byte.quote {
                output.append(contentsOf: bytes[runStart..<index])
                index += 1
                return output
            }
            guard byte >= 0x20 else { throw .malformed }   // 원문 제어 문자는 JSON 문법 위반
            if byte == Byte.backslash {
                output.append(contentsOf: bytes[runStart..<index])
                index += 1
                try parseEscape(into: &output)
                runStart = index
            } else {
                index += 1
            }
        }
        throw .malformed
    }

    private mutating func parseEscape(into output: inout [UInt8]) throws(GSPackFailure) {
        guard let escape = peek() else { throw .malformed }
        index += 1
        switch escape {
        case Byte.quote, Byte.backslash, UInt8(ascii: "/"): output.append(escape)
        case UInt8(ascii: "b"): output.append(0x08)
        case UInt8(ascii: "f"): output.append(0x0C)
        case UInt8(ascii: "n"): output.append(0x0A)
        case UInt8(ascii: "r"): output.append(0x0D)
        case UInt8(ascii: "t"): output.append(0x09)
        case UInt8(ascii: "u"): try appendUnicodeEscape(into: &output)
        default: throw .malformed
        }
    }

    /// `\uXXXX` — 높은 서로게이트는 바로 뒤 `\u`낮은 서로게이트와 짝이어야 한다. 짝 없는 서로게이트는 M1(12-2)
    private mutating func appendUnicodeEscape(into output: inout [UInt8]) throws(GSPackFailure) {
        let unit = try parseHex4()
        let value: UInt32
        switch unit {
        case 0xD800...0xDBFF:
            guard peek() == Byte.backslash, peek(offset: 1) == UInt8(ascii: "u") else { throw .malformed }
            index += 2
            let low = try parseHex4()
            guard (0xDC00...0xDFFF).contains(low) else { throw .malformed }
            value = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
        case 0xDC00...0xDFFF:
            throw .malformed
        default:
            value = unit
        }
        guard let scalar = Unicode.Scalar(value) else { throw .malformed }
        UTF8.encode(scalar) { output.append($0) }
    }

    private mutating func parseHex4() throws(GSPackFailure) -> UInt32 {
        guard index + 4 <= bytes.count else { throw .malformed }
        var value: UInt32 = 0
        for byte in bytes[index..<(index + 4)] {
            guard let digit = Self.hexValue(byte) else { throw .malformed }
            value = value << 4 | digit
        }
        index += 4
        return value
    }

    private static func hexValue(_ byte: UInt8) -> UInt32? {
        switch byte {
        case Byte.zero...Byte.nine: UInt32(byte - Byte.zero)
        case UInt8(ascii: "a")...UInt8(ascii: "f"): UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F"): UInt32(byte - UInt8(ascii: "A") + 10)
        default: nil
        }
    }

    // MARK: 숫자·리터럴

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?` — `isInteger`는 소수부·지수부가 없을 때만 참
    private mutating func parseNumber() throws(GSPackFailure) -> GSPackJSONValue {
        let start = index
        if peek() == Byte.minus { index += 1 }
        guard let first = peek(), Self.isDigit(first) else { throw .malformed }
        if first == Byte.zero {
            index += 1
            if let next = peek(), Self.isDigit(next) { throw .malformed }   // 앞자리 0
        } else {
            skipDigits()
        }
        var isInteger = true
        if peek() == UInt8(ascii: ".") {
            index += 1
            guard let digit = peek(), Self.isDigit(digit) else { throw .malformed }
            skipDigits()
            isInteger = false
        }
        if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
            index += 1
            if peek() == UInt8(ascii: "+") || peek() == Byte.minus { index += 1 }
            guard let digit = peek(), Self.isDigit(digit) else { throw .malformed }
            skipDigits()
            isInteger = false
        }
        return .number(literal: Array(bytes[start..<index]), isInteger: isInteger)
    }

    private mutating func expectLiteral(_ word: String) throws(GSPackFailure) {
        guard bytes[index...].starts(with: word.utf8) else { throw .malformed }
        index += word.utf8.count
    }

    // MARK: 커서

    private func peek(offset: Int = 0) -> UInt8? {
        let position = index + offset
        return position < bytes.count ? bytes[position] : nil
    }

    private mutating func skipWhitespace() {
        while let byte = peek(), byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
            index += 1
        }
    }

    private mutating func skipDigits() {
        while let byte = peek(), Self.isDigit(byte) {
            index += 1
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (Byte.zero...Byte.nine).contains(byte)
    }

    private enum Byte {
        static let openBrace = UInt8(ascii: "{")
        static let closeBrace = UInt8(ascii: "}")
        static let openBracket = UInt8(ascii: "[")
        static let closeBracket = UInt8(ascii: "]")
        static let quote = UInt8(ascii: "\"")
        static let backslash = UInt8(ascii: "\\")
        static let colon = UInt8(ascii: ":")
        static let comma = UInt8(ascii: ",")
        static let minus = UInt8(ascii: "-")
        static let zero = UInt8(ascii: "0")
        static let nine = UInt8(ascii: "9")
    }
}
