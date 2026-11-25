import Foundation
import TadakDomain

/// 키보드가 싣는 내 채움글 — 실을 항목(앞부분)과 **멈춘 자리의 예산 판정**을 함께 든다.
///
/// ★ `load`를 앞부분 `entries`로 다시 계산하지 않는다 — 넘어서 멈춘 경우 앞부분만 다시 세면 「맞음」이 되어 9-3(baseline 초과 →
/// 외부 팩 읽지 않음)이 깨진다(PDR `keyboard-user-snippet-prefix-decode.md` 불변식 I1).
struct UserSnippetSupply: Equatable, Sendable {
    /// 실을 항목 — `load.loadableCount`개, 저장 순서
    var entries: [SnippetEntry]
    var load: ActivePackBudget.UserSnippetLoad

    /// 배열을 이미 다 가진 경우 — 기존 경로(`userSnippetLoad` 한 번)와 같다
    static func full(_ all: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits) -> UserSnippetSupply {
        let load = ActivePackBudget.userSnippetLoad(all, builtIn: builtIn, limits: limits)
        return UserSnippetSupply(entries: Array(all.prefix(load.loadableCount)), load: load)
    }
}

/// B1 가′ — 저장된 내 채움글 JSON 배열을 통째로 디코드하지 않고 **원소 하나씩** 디코드해 예산에 넣다가, 넘는 것이 확정되면 멈춘다.
///
/// 1. `JSONElementScanner`가 바이트를 한 번 훑어 **문법을 끝까지 검사**하고(깨지면 0개 — 지금과 같다) 최상위 원소의 바이트 범위와
///    원시 바이트 하한을 낸다. 문자열을 만들지 않는다.
/// 2. 원소마다 하한으로 먼저 판정 — 넘으면 **디코드하지 않고** 멈춘다(10MB 한 항목, codex M-2).
/// 3. 들어갈 수 있으면 그 원소 범위만 디코드해 `UserSnippetLoadAccumulator.add` — 넘으면 멈춘다. 디코드는 많아야 실을 개수 + 1번.
///
/// 쓰는 원소의 디코드가 실패하면 0개(지금과 같다). 멈춘 자리 **뒤** 원소는 문법만 보고 필드 타입은 보지 않는다 — 앱은 그런 저장분을
/// 0개로 보지만 정상 경로(`JSONEncoder`)로는 생기지 않는다(PDR 엣지케이스 — 받아들인 차이).
///
/// 내 채움글은 사용자 입력이다 — 로그·파일·네트워크 0.
enum UserSnippetPrefixDecoder {

    static func supply(
        from data: Data, builtIn: PackStats, limits: PackBudgetLimits,
        decodeElement: (Data) -> SnippetEntry? = { try? JSONDecoder().decode(SnippetEntry.self, from: $0) }
    ) -> UserSnippetSupply {
        guard let elements = JSONElementScanner.topLevelElements(of: data) else {
            return .full([], builtIn: builtIn, limits: limits)
        }
        var accumulator = ActivePackBudget.UserSnippetLoadAccumulator(builtIn: builtIn, limits: limits)
        var entries: [SnippetEntry] = []
        for element in elements {
            if let stopped = accumulator.overflowBeforeDecode(rawUTF8LowerBound: element.rawUTF8LowerBound) {
                return UserSnippetSupply(entries: entries, load: stopped)
            }
            let range = (data.startIndex + element.range.lowerBound)..<(data.startIndex + element.range.upperBound)
            let decoded: SnippetEntry? = autoreleasepool { decodeElement(data.subdata(in: range)) }
            guard let entry = decoded else {
                return .full([], builtIn: builtIn, limits: limits)   // 쓰는 원소가 깨졌다 — 전체 디코드 실패와 같게 0개
            }
            if let stopped = accumulator.add(entry) {
                return UserSnippetSupply(entries: entries, load: stopped)
            }
            entries.append(entry)
        }
        return UserSnippetSupply(entries: entries, load: accumulator.finish())
    }
}

/// JSON 최상위 배열의 원소 경계 스캐너(RFC 8259 문법). 값을 만들지 않고 바이트만 훑는다.
///
/// 원소가 객체면 `SnippetEntry`의 디코드 규칙대로 문자열 필드의 **이스케이프를 푼 UTF-8 바이트**를 센다 — `triggers`(배열 안 문자열)가
/// 있으면 그것, 없거나 `null`이면 `trigger`, 그리고 `title`·`body`. 이 값은 디코드한 항목의 `PackStats.rawUTF8Bytes` **이하**여야 한다
/// (하한). 그래서 확신할 수 없는 경우는 0으로 센다 — 중복 키(어느 값이 이길지 디코더 몫), 문자열이 아닌 값, 짝 없는 서로게이트.
struct JSONElementScanner {

    struct Element: Equatable {
        /// 원소의 바이트 범위(데이터 시작 기준 0부터)
        var range: Range<Int>
        var rawUTF8LowerBound: Int
    }

    /// 중첩 상한 — 넘으면 손상으로 본다(스택 보호)
    static let maxDepth = 512

    /// 최상위가 배열이고 문법이 끝까지 맞으면 원소 목록, 아니면 nil
    static func topLevelElements(of data: Data) -> [Element]? {
        data.withUnsafeBytes { buffer in
            var scanner = JSONElementScanner(bytes: buffer)
            return scanner.scanTopLevelArray()
        }
    }

    private let bytes: UnsafeRawBufferPointer
    private var index = 0

    private init(bytes: UnsafeRawBufferPointer) {
        self.bytes = bytes
    }

    // MARK: - 최상위

    private mutating func scanTopLevelArray() -> [Element]? {
        skipWhitespace()
        guard consume(.openBracket) else { return nil }
        var elements: [Element] = []
        skipWhitespace()
        if !consume(.closeBracket) {
            while true {
                skipWhitespace()
                let start = index
                guard let bound = scanElement() else { return nil }
                elements.append(Element(range: start..<index, rawUTF8LowerBound: bound))
                skipWhitespace()
                if consume(.comma) { continue }
                guard consume(.closeBracket) else { return nil }
                break
            }
        }
        skipWhitespace()
        return index == bytes.count ? elements : nil
    }

    /// 항목 필드 — 디코더(`SnippetEntry.init(from:)`)가 읽는 네 키
    private enum Field: CaseIterable {
        case triggers, trigger, title, body

        init?(key: [UInt8]) {
            switch key {
            case Array("triggers".utf8): self = .triggers
            case Array("trigger".utf8): self = .trigger
            case Array("title".utf8): self = .title
            case Array("body".utf8): self = .body
            default: return nil
            }
        }
    }

    private struct Measured {
        var occurrences = 0
        var bytes = 0
        var isNull = false
    }

    /// 최상위 원소 하나 — 하한 바이트를 돌려준다(객체가 아니면 0)
    private mutating func scanElement() -> Int? {
        guard peek == .openBrace else { return skipValue(depth: 1) ? 0 : nil }
        index += 1
        var measured: [Field: Measured] = [:]
        skipWhitespace()
        if !consume(.closeBrace) {
            while true {
                skipWhitespace()
                var key: [UInt8] = []
                guard peek == .quote, scanString(capturingUpTo: 8, into: &key) != nil else { return nil }
                let field = Field(key: key)
                skipWhitespace()
                guard consume(.colon) else { return nil }
                skipWhitespace()
                var value = Measured(occurrences: 1)
                switch field {
                case .title?, .body?, .trigger?:
                    if peek == .quote {
                        guard let length = scanString() else { return nil }
                        value.bytes = length
                    } else {
                        value.isNull = peek == UInt8(ascii: "n")
                        guard skipValue(depth: 2) else { return nil }
                    }
                case .triggers?:
                    if peek == .openBracket {
                        guard let length = scanStringArray() else { return nil }
                        value.bytes = length
                    } else {
                        value.isNull = peek == UInt8(ascii: "n")
                        guard skipValue(depth: 2) else { return nil }
                    }
                case nil:
                    guard skipValue(depth: 2) else { return nil }
                }
                if let field {
                    var current = measured[field, default: Measured()]
                    current.occurrences += 1
                    current.bytes = value.bytes
                    current.isNull = value.isNull
                    measured[field] = current
                }
                skipWhitespace()
                if consume(.comma) { continue }
                guard consume(.closeBrace) else { return nil }
                break
            }
        }
        return Self.lowerBound(measured)
    }

    /// 디코더 규칙 그대로, 확신할 수 없으면 0 — 하한은 작게 잡아도 안전하다(디코드 뒤 정확히 다시 본다)
    private static func lowerBound(_ measured: [Field: Measured]) -> Int {
        func single(_ field: Field) -> Measured? {
            guard let value = measured[field], value.occurrences == 1 else { return nil }
            return value
        }
        let triggers = measured[.triggers]
        var total = 0
        if let triggers, triggers.occurrences > 1 {
            // 어느 `triggers`가 이길지 모른다 — `trigger`로 넘어갈지도 모르므로 둘 다 0
        } else if let triggers, !triggers.isNull {
            total += triggers.bytes
        } else if let trigger = single(.trigger), !trigger.isNull {
            total += trigger.bytes
        }
        for field in [Field.title, .body] {
            if let value = single(field), !value.isNull { total += value.bytes }
        }
        return total
    }

    /// `[ "…", … ]` — 문자열 원소의 바이트 합. 문자열이 아닌 원소는 0으로 세고 문법만 본다(디코드에서 실패한다)
    private mutating func scanStringArray() -> Int? {
        index += 1   // [
        var total = 0
        skipWhitespace()
        if consume(.closeBracket) { return 0 }
        while true {
            skipWhitespace()
            if peek == .quote {
                guard let length = scanString() else { return nil }
                total += length
            } else {
                guard skipValue(depth: 3) else { return nil }
            }
            skipWhitespace()
            if consume(.comma) { continue }
            guard consume(.closeBracket) else { return nil }
            return total
        }
    }

    // MARK: - 값

    private mutating func skipValue(depth: Int) -> Bool {
        guard depth <= Self.maxDepth, let byte = peek else { return false }
        switch byte {
        case .quote:
            return scanString() != nil
        case .openBrace:
            index += 1
            skipWhitespace()
            if consume(.closeBrace) { return true }
            while true {
                skipWhitespace()
                guard peek == .quote, scanString() != nil else { return false }
                skipWhitespace()
                guard consume(.colon) else { return false }
                skipWhitespace()
                guard skipValue(depth: depth + 1) else { return false }
                skipWhitespace()
                if consume(.comma) { continue }
                return consume(.closeBrace)
            }
        case .openBracket:
            index += 1
            skipWhitespace()
            if consume(.closeBracket) { return true }
            while true {
                skipWhitespace()
                guard skipValue(depth: depth + 1) else { return false }
                skipWhitespace()
                if consume(.comma) { continue }
                return consume(.closeBracket)
            }
        case UInt8(ascii: "t"): return consumeLiteral("true")
        case UInt8(ascii: "f"): return consumeLiteral("false")
        case UInt8(ascii: "n"): return consumeLiteral("null")
        default:
            return skipNumber()
        }
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`
    private mutating func skipNumber() -> Bool {
        _ = consume(UInt8(ascii: "-"))
        if consume(UInt8(ascii: "0")) {
        } else {
            guard let first = peek, (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(first) else { return false }
            skipDigits()
        }
        if consume(UInt8(ascii: ".")) {
            guard skipDigits() > 0 else { return false }
        }
        if consume(UInt8(ascii: "e")) || consume(UInt8(ascii: "E")) {
            if !consume(UInt8(ascii: "+")) { _ = consume(UInt8(ascii: "-")) }
            guard skipDigits() > 0 else { return false }
        }
        return true
    }

    @discardableResult
    private mutating func skipDigits() -> Int {
        let start = index
        while let byte = peek, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) { index += 1 }
        return index - start
    }

    private mutating func scanString() -> Int? {
        var unused: [UInt8] = []
        return scanString(capturingUpTo: 0, into: &unused)
    }

    /// 따옴표 문자열 하나 — 이스케이프를 푼 UTF-8 바이트 수. `capturingUpTo`가 0보다 크면 푼 바이트를 그 길이까지 담는다(키 비교용,
    /// 넘으면 한 바이트 더 담아 어떤 키와도 같지 않게 한다). 짝 없는 서로게이트는 문법상 맞으므로 받되 0바이트로 센다(하한)
    private mutating func scanString(capturingUpTo limit: Int, into captured: inout [UInt8]) -> Int? {
        index += 1   // "
        var length = 0
        func capture(_ byte: UInt8) {
            if captured.count <= limit, limit > 0 { captured.append(byte) }
        }
        while let byte = peek {
            index += 1
            switch byte {
            case .quote:
                return length
            case .backslash:
                guard let escaped = peek else { return nil }
                index += 1
                switch escaped {
                case .quote, .backslash, UInt8(ascii: "/"):
                    length += 1; capture(escaped)
                case UInt8(ascii: "b"), UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                    // 푼 값(제어 문자)을 담는다 — 글자(b·f·n·r·t)를 담으면 `"\title"`(탭+itle)이 `title` 필드가 된다(검증 F1)
                    length += 1; capture(Self.unescapedControl[escaped] ?? 0x00)
                case UInt8(ascii: "u"):
                    guard let unit = readHex4() else { return nil }
                    if (0xD800...0xDBFF).contains(unit), peek == .backslash, index + 1 < bytes.count,
                       bytes[index + 1] == UInt8(ascii: "u") {
                        let save = index
                        index += 2
                        guard let low = readHex4() else { return nil }
                        if (0xDC00...0xDFFF).contains(low) {
                            length += 4; capture(0xF0)
                        } else {
                            index = save   // 다음 \u는 따로 센다
                        }
                    } else if (0xD800...0xDFFF).contains(unit) {
                        // 짝 없는 서로게이트 — 0바이트(하한)
                    } else {
                        length += unit < 0x80 ? 1 : (unit < 0x800 ? 2 : 3)
                        capture(unit < 0x80 ? UInt8(unit) : 0xC0)
                    }
                default:
                    return nil
                }
            default:
                guard byte >= 0x20 else { return nil }   // 제어 문자는 이스케이프해야 한다
                length += 1; capture(byte)
            }
        }
        return nil   // 닫는 따옴표 없음
    }

    /// `\b \f \n \r \t`의 푼 값
    private static let unescapedControl: [UInt8: UInt8] = [
        UInt8(ascii: "b"): 0x08, UInt8(ascii: "f"): 0x0C, UInt8(ascii: "n"): 0x0A, UInt8(ascii: "r"): 0x0D, UInt8(ascii: "t"): 0x09,
    ]

    private mutating func readHex4() -> UInt32? {
        guard index + 4 <= bytes.count else { return nil }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt8
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = byte - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = byte - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = byte - UInt8(ascii: "A") + 10
            default: return nil
            }
            value = value << 4 | UInt32(digit)
            index += 1
        }
        return value
    }

    // MARK: - 바이트

    private var peek: UInt8? { index < bytes.count ? bytes[index] : nil }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard peek == byte else { return false }
        index += 1
        return true
    }

    private mutating func consumeLiteral(_ literal: StaticString) -> Bool {
        let count = literal.utf8CodeUnitCount
        guard index + count <= bytes.count else { return false }
        for offset in 0..<count where bytes[index + offset] != literal.utf8Start[offset] { return false }
        index += count
        return true
    }

    private mutating func skipWhitespace() {
        while let byte = peek, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
    }
}

private extension UInt8 {
    static let quote = UInt8(ascii: "\"")
    static let backslash = UInt8(ascii: "\\")
    static let openBracket = UInt8(ascii: "[")
    static let closeBracket = UInt8(ascii: "]")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let comma = UInt8(ascii: ",")
    static let colon = UInt8(ascii: ":")
}
