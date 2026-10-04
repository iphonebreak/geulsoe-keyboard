import Foundation
import TadakDomain

public enum PackTextEncoding: Equatable, Sendable {
    case utf8, utf16LittleEndian, utf16BigEndian, cp949
}

/// 사용자가 확인 화면에서 고르는 인코딩(5-3b #5) — 고르면 **원본 바이트에서 전부 다시**(5-1·AC-18)
public enum PackEncodingChoice: Equatable, Sendable {
    case automatic, utf8, cp949
}

public struct DecodedPackText: Equatable, Sendable {
    public let text: String
    public let encoding: PackTextEncoding
    public let hadBOM: Bool
    /// R18 — **BOM 없는 비ASCII 파일이면 항상** 확인 화면(UTF-8 ↔ 한국어(CP949) 수동 전환). ASCII만이면 해석 차이가 없어 생략
    public let needsConfirmation: Bool

    public init(text: String, encoding: PackTextEncoding, hadBOM: Bool, needsConfirmation: Bool) {
        self.text = text
        self.encoding = encoding
        self.hadBOM = hadBOM
        self.needsConfirmation = needsConfirmation
    }
}

/// 인코딩 판정(PDR `external-snippet-packs.md` 5-3b, R4·R18).
///
/// - BOM이 인코딩을 말하면 그 인코딩을 **엄격히** 검증한다 — UTF-8 BOM인데 본문이 어긋나면 CP949로 폴백하지 않고 거부(손상).
///   BOM을 뗀 뒤 남은 첫 `U+FEFF` **하나**는 더 뗀다(BOM이 두 번 붙은 파일, 검증 F8). 본문 가운데의 것은 문자 정리 몫이다.
/// - BOM이 없으면 엄격 UTF-8, 실패하면 엄격 CP949. **replacement character로 복구하지 않는다** — 엄격성은
///   디코드한 문자열을 같은 인코딩으로 되돌려 원본 바이트와 같은지로 확인한다(왕복 검사).
/// - **자동 판정은 추정이다**(`C3 A9` = UTF-8 `é` = CP949 `챕`) — 그래서 BOM 없는 비ASCII는 확인 화면이 항상 뜬다.
///
/// 결과 문자열은 메모리에만 있다 — 로그·파일·네트워크로 내보내지 않는다(보안 규칙). 오류는 내용 없는 코드다.
public enum PackTextDecoder {

    static let cp949 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))

    public static func decode(_ data: Data, choice: PackEncodingChoice = .automatic) throws(PackImportFailure) -> DecodedPackText {
        guard data.count <= PackLimits.fileBytes else { throw .fileTooLarge }
        let bytes = [UInt8](data)

        // 1. UTF-32 BOM — UTF-16LE로 오인하지 않는다(FF FE 00 00은 UTF-16LE BOM으로도 읽힌다)
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            throw .unsupportedEncoding
        }
        // 2. UTF-8 BOM
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard choice != .cp949 else { throw .encodingDoesNotMatchBOM }
            guard let text = strictUTF8(bytes.dropFirst(3)) else { throw .invalidUTF8AfterBOM }
            return DecodedPackText(text: droppingRepeatedBOM(text), encoding: .utf8, hadBOM: true, needsConfirmation: false)
        }
        // 3. UTF-16 BOM — 짝수 바이트·서로게이트 쌍 엄격
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            guard choice == .automatic else { throw .encodingDoesNotMatchBOM }
            let little = bytes[0] == 0xFF
            guard let text = strictUTF16(bytes.dropFirst(2), littleEndian: little) else { throw .invalidUTF16 }
            return DecodedPackText(text: droppingRepeatedBOM(text), encoding: little ? .utf16LittleEndian : .utf16BigEndian,
                                   hadBOM: true, needsConfirmation: false)
        }
        // 4. BOM 없음
        let nonASCII = bytes.contains { $0 >= 0x80 }
        switch choice {
        case .utf8:
            guard let text = strictUTF8(bytes[...]) else { throw .undecodable(.utf8) }
            return DecodedPackText(text: text, encoding: .utf8, hadBOM: false, needsConfirmation: nonASCII)
        case .cp949:
            guard let text = strictCP949(bytes) else { throw .undecodable(.cp949) }
            return DecodedPackText(text: text, encoding: .cp949, hadBOM: false, needsConfirmation: nonASCII)
        case .automatic:
            // NUL이 든 텍스트는 BOM 없는 UTF-16 등 — 억지로 받지 않는다(5-3b #4)
            guard !bytes.contains(0x00) else { throw .unsupportedEncoding }
            if let text = strictUTF8(bytes[...]) {
                return DecodedPackText(text: text, encoding: .utf8, hadBOM: false, needsConfirmation: nonASCII)
            }
            if let text = strictCP949(bytes) {
                return DecodedPackText(text: text, encoding: .cp949, hadBOM: false, needsConfirmation: true)
            }
            throw .unsupportedEncoding
        }
    }

    /// 표준 라이브러리 디코드(잘못된 바이트 → U+FFFD) 뒤 왕복 비교 — U+FFFD가 생겼으면 원본과 달라진다.
    /// Foundation `String(data:encoding: .utf8)`은 앞의 `U+FEFF`를 말없이 떼어 BOM 두 번을 「손상」으로 오진했다(F8)
    private static func strictUTF8(_ bytes: ArraySlice<UInt8>) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard text.utf8.elementsEqual(bytes) else { return nil }
        return text
    }

    private static func droppingRepeatedBOM(_ text: String) -> String {
        text.unicodeScalars.first == "\u{FEFF}" ? String(text.unicodeScalars.dropFirst()) : text
    }

    private static func strictCP949(_ bytes: [UInt8]) -> String? {
        let data = Data(bytes)
        guard let text = String(data: data, encoding: cp949), text.data(using: cp949) == data else { return nil }
        return text
    }

    private static func strictUTF16(_ bytes: ArraySlice<UInt8>, littleEndian: Bool) -> String? {
        guard bytes.count % 2 == 0 else { return nil }
        var units: [UInt16] = []
        units.reserveCapacity(bytes.count / 2)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let first = UInt16(bytes[index])
            let second = UInt16(bytes[index + 1])
            units.append(littleEndian ? (second << 8 | first) : (first << 8 | second))
            index += 2
        }
        var text = ""
        text.unicodeScalars.reserveCapacity(units.count)
        var iterator = units.makeIterator()
        var codec = UTF16()
        while true {
            switch codec.decode(&iterator) {
            case .scalarValue(let scalar): text.unicodeScalars.append(scalar)
            case .emptyInput: return text
            case .error: return nil
            }
        }
    }
}
