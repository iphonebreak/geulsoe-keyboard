import Foundation

/// base64 엄격 규칙(PDR 12-2) — 표준 알파벳 `A-Za-z0-9+/`, 패딩 `=` 필수(길이 4의 배수), 공백·줄바꿈·URL-safe 거부,
/// **정규형만**(디코드 → 다시 인코드한 글자가 입력과 같아야 한다 — 남는 비트가 0이 아닌 변형 거부).
///
/// `Data(base64Encoded:)`는 관대하므로(남는 비트 무시) 재인코딩 비교가 필수다.
enum GSPackBase64 {

    /// 알파벳 검사만 — 디코드하지 않는다. 이것이 참이면 글자 수 = 바이트 수라 ② 글자 상한을 언어마다 같은 값으로 잰다
    static func usesAlphabet(_ text: [UInt8]) -> Bool {
        text.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="):
                true
            default:
                false
            }
        }
    }

    /// 정규형 base64면 디코드한 바이트, 아니면 nil
    static func decodeCanonical(_ text: [UInt8]) -> Data? {
        guard usesAlphabet(text), text.count % 4 == 0 else { return nil }
        // `=`는 끝 두 자리에만, 그리고 `x=`이 아니라 `==` 또는 `=` 꼴로만
        let padding = text.reversed().prefix { $0 == UInt8(ascii: "=") }.count
        guard padding <= 2, !text.dropLast(padding).contains(UInt8(ascii: "=")) else { return nil }
        let encoded = Data(text)
        guard let decoded = Data(base64Encoded: encoded), decoded.base64EncodedData() == encoded else { return nil }
        return decoded
    }
}
