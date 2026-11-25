import Foundation
import Testing
import TadakDomain
@testable import PackImport

/// 잠금 팩 봉투 — 상한 숫자·AAD 바이트·검사 순서 ⓐ~ⓕ·엄격 JSON·엄격 base64 (PDR `external-snippet-packs.md` 12-2·12-3·12-6).
/// 고정 파일로 덮은 경우(V16~V26)는 `GSPackVectorTests`가 보고, 여기는 파일 없이 규칙 하나씩을 본다.
@Suite("잠금 팩 — 봉투 검사 (12-2 · 12-3 · 12-6)")
struct GSPackEnvelopeTests {

    // MARK: 상한(12-3)

    @Test("상한 숫자 — 4,100,000 · 4,000,024 · 3,000,016 · 3,000,000, 그리고 ②가 4×ceil(③/3)")
    func limits() {
        #expect(GSPackLimits.envelopeBytes == 4_100_000)
        #expect(GSPackLimits.ciphertextBase64Characters == 4_000_024)
        #expect(GSPackLimits.ciphertextBytes == 3_000_016)
        #expect(GSPackLimits.plaintextBytes == 3_000_000)
        #expect(GSPackLimits.plaintextBytes == PackLimits.fileBytes)
        #expect(GSPackLimits.ciphertextBytes == GSPackLimits.plaintextBytes + GSPackLimits.tagBytes)
        let ceilThirds = (GSPackLimits.ciphertextBytes + 2) / 3
        #expect(4 * ceilThirds == GSPackLimits.ciphertextBase64Characters)
        #expect(GSPackLimits.envelopeBytes - GSPackLimits.ciphertextBase64Characters == 99_976)
        #expect(GSPackLimits.iterations == 300_000...2_000_000)
        #expect(GSPackLimits.iterations.contains(GSPackLimits.makerIterations))
        #expect((GSPackLimits.saltBytes, GSPackLimits.nonceBytes, GSPackLimits.tagBytes) == (16, 12, 16))
        #expect(GSPackLimits.passwordMaxBytes == 256)
        #expect(GSPackLimits.fileExtension == "gspack" && GSPackLimits.typeIdentifier == "com.charging.tadak.pack")
    }

    // MARK: AAD(12-6)

    @Test("12-6 바이트 예시 — 87바이트가 문서의 16진과 같다")
    func aadExample() throws {
        let envelope = try GSPackEnvelope.parse(Data(GSPackSpec.fileText.utf8))
        let aad = envelope.additionalData
        #expect(aad.count == 87)
        #expect(aad.hexString == GSPackSpec.aadHex)
        // 오프셋 표 몇 곳 — 길이 접두·big-endian
        #expect(Array(aad[16..<18]) == [0x00, 0x01])
        #expect(Array(aad[59..<63]) == [0x00, 0x09, 0x27, 0xC0])
        #expect(Array(aad[83..<87]) == [0x00, 0x00, 0x00, 0x00])
    }

    @Test("12-2 예시 파일을 읽으면 메타·반복 수·salt·nonce·암호문 길이가 문서와 같다")
    func specExampleParses() throws {
        let envelope = try GSPackEnvelope.parse(Data(GSPackSpec.fileText.utf8))
        #expect(envelope.meta == GSPackMeta(name: "찬송가 샘플", rights: ""))
        #expect(envelope.iterations == 600_000)
        #expect(envelope.salt.hexString == "101112131415161718191a1b1c1d1e1f")
        #expect(envelope.nonce.hexString == "a0a1a2a3a4a5a6a7a8a9aaab")
        #expect(envelope.sealed.count == 67)
    }

    @Test("AAD는 정규화하지 않는다 — NFC·NFD 이름은 다른 AAD")
    func aadIsNotNormalized() throws {
        let nfc = GSPackEnvelope(meta: GSPackMeta(name: "\u{00E9}", rights: ""), iterations: 600_000,
                                 salt: Data(count: 16), nonce: Data(count: 12), sealed: Data(count: 16))
        let nfd = GSPackEnvelope(meta: GSPackMeta(name: "e\u{0301}", rights: ""), iterations: 600_000,
                                 salt: Data(count: 16), nonce: Data(count: 12), sealed: Data(count: 16))
        #expect(nfc.additionalData != nfd.additionalData)
        #expect(nfc.additionalData.count == 87 - 16 + 2 && nfd.additionalData.count == 87 - 16 + 3)
    }

    // MARK: 검사 순서(12-2 규칙 6)

    @Test("ⓐ가 ⓑ보다 먼저 — 4,100,001바이트 쓰레기는 형식 오류가 아니라 크기 초과")
    func sizeBeforeSyntax() {
        #expect(throws: GSPackFailure.tooLarge) { try GSPackEnvelope.parse(Data(repeating: 0x78, count: 4_100_001)) }
        #expect(throws: GSPackFailure.malformed) { try GSPackEnvelope.parse(Data(repeating: 0x78, count: 4_100_000)) }
    }

    @Test("ⓒ가 ⓓ보다 먼저 — format이 다르면 version 2여도 형식 오류")
    func formatBeforeVersion() {
        #expect(throws: GSPackFailure.malformed) { try parse(#"{"format":"other","version":2}"#) }
        #expect(throws: GSPackFailure.malformed) { try parse(#"{"version":2,"format":"geulsoe-pack "}"#) }
        #expect(throws: GSPackFailure.malformed) { try parse(#"{"version":2}"#) }
        #expect(throws: GSPackFailure.malformed) { try parse(#"["geulsoe-pack",2]"#) }
        #expect(throws: GSPackFailure.newerVersion) { try parse(#"{"version":2,"format":"geulsoe-pack"}"#) }
    }

    @Test("ⓓ가 ⓔ보다 먼저 — version 2면 나머지(배열·null·모르는 키)는 보지 않고 새 버전")
    func versionBeforeStructure() {
        #expect(throws: GSPackFailure.newerVersion) {
            try parse(#"{"format":"geulsoe-pack","version":3,"items":[1,true,null,{"a":-1.5e3}]}"#)
        }
        #expect(throws: GSPackFailure.newerVersion) { try parse(#"{"format":"geulsoe-pack","version":99999999999999999999999}"#) }
        for literal in ["0", "-0", "-2", "1.0", "1e0", "\"1\"", "true", "null"] {
            #expect(throws: GSPackFailure.malformed, "version \(literal)") {
                try parse(#"{"format":"geulsoe-pack","version":\#(literal)}"#)
            }
        }
    }

    @Test("ⓔ가 ⓕ보다 먼저 — 구조 오류가 있으면 암호문이 ②를 넘어도 형식 오류")
    func structureBeforeBase64() {
        let huge = String(repeating: "A", count: 4_000_028)
        #expect(throws: GSPackFailure.tooLarge) { try parse(GSPackSpec.text(ciphertext: huge)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(iterations: "299999", ciphertext: huge)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(salt: "AAAA", ciphertext: huge)) }
    }

    @Test("ⓕ 암호문 — 알파벳(M1) → ② 글자 수(M3) → 정규형(M1) → ③ 바이트(M3)·하한 16B(M1)")
    func ciphertextOrder() throws {
        // 알파벳 밖 글자가 있으면 ②를 넘어도 M1 — 그다음부터 글자 수 = 바이트 수라 언어마다 ②가 같다
        let overLongInvalid = String(repeating: "A", count: 4_000_027) + "-"
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(ciphertext: overLongInvalid)) }
        // ② 경계: 4,000,024자는 ②를 통과하지만 정규형이 아니면 M1
        let atLimitNonCanonical = String(repeating: "A", count: 4_000_022) + "B="
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(ciphertext: atLimitNonCanonical)) }
        // 하한: 15B → M1, 16B → 통과(빈 평문)
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(ciphertext: Data(count: 15).base64EncodedString())) }
        #expect(try parse(GSPackSpec.text(ciphertext: Data(count: 16).base64EncodedString())).sealed.count == 16)
    }

    @Test("ⓔ 메타 — 키가 있어야 하고 빈 값은 받으며 상한은 PackLimits 세 잣대")
    func metaRules() throws {
        #expect(try parse(GSPackSpec.text(name: "", rights: "")).meta == GSPackMeta(name: "", rights: ""))
        #expect(try parse(GSPackSpec.text(name: String(repeating: "가", count: 40))).meta.name.count == 40)
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(name: String(repeating: "가", count: 41))) }
        // 결합 문자: 글자 수는 안이어도 스칼라·바이트가 넘으면 거부(세 잣대)
        let combining = String(repeating: "e\u{0301}\u{0301}\u{0301}", count: 31)   // 31자 · 124 scalar · 217B
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(name: combining)) }
        #expect(try parse(GSPackSpec.text(rights: String(repeating: "r", count: 120))).meta.rights.count == 120)
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(rights: String(repeating: "r", count: 121))) }
    }

    @Test("메타 금지 문자 — C0·DEL·C1·U+2028·U+2029", arguments: [0x00, 0x09, 0x1F, 0x7F, 0x80, 0x85, 0x9F, 0x2028, 0x2029])
    func forbiddenMetaScalar(value: UInt32) throws {
        let scalar = try #require(Unicode.Scalar(value))
        #expect(GSPackEnvelope.isForbiddenInMeta(scalar))
        let escaped = String(format: "a\\u%04x", value)
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(nameLiteral: escaped)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(rightsLiteral: escaped)) }
    }

    @Test("메타 허용 문자 — 공백·U+00A0·U+FEFF·이모지는 받는다(정규화·trim 없음)")
    func allowedMetaScalars() throws {
        for name in [" 앞뒤 공백 ", "a\u{00A0}b", "\u{FEFF}x", "👍🏽", "e\u{0301}"] {
            #expect(try parse(GSPackSpec.text(name: name)).meta.name.unicodeScalars.elementsEqual(name.unicodeScalars))
        }
    }

    @Test("ⓔ iterations — 경계·정수 리터럴·자릿수(변환 전 거부)")
    func iterationsRules() throws {
        #expect(try parse(GSPackSpec.text(iterations: "300000")).iterations == 300_000)
        #expect(try parse(GSPackSpec.text(iterations: "2000000")).iterations == 2_000_000)
        for literal in ["299999", "2000001", "0", "-300000", "-0", "300000.0", "3e5", "3E5", "\"300000\"",
                        "0000300000", "10000000000", String(repeating: "9", count: 4_000)] {
            #expect(throws: GSPackFailure.malformed, "\(literal.prefix(12))") { try parse(GSPackSpec.text(iterations: literal)) }
        }
    }

    @Test("ⓔ 모르는·누락 키 — hint 포함, 어느 수준이든")
    func exactKeySets() {
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(extraEncryption: #","hint":"x""#)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(extraTop: #","hint":"x""#)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(extraMeta: #","hint":"x""#)) }
        #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(extraMeta: #","Name":"x""#)) }
    }

    // MARK: 엄격 JSON(ⓑ)

    @Test("JSON 문법 — 받는 것", arguments: [
        #"{}"#, #"[]"#, #" {"a" : "b" } "#, "\t{\r\n}\n", #"{"n":-1.5e+3}"#, #"{"n":0}"#, #"{"n":-0}"#, #"{"n":1E9}"#,
        #"{"a":[true,false,null]}"#, #"{"s":"\"\\\/\b\f\n\r\t"}"#, #"{"s":"😀"}"#, #"{"é":1,"é":2}"#,
        #"{"a":{"b":{}}}"#, #"[[[]]]"#
    ])
    func jsonAccepts(text: String) throws {
        _ = try GSPackJSONParser.parse(Array(text.utf8))
    }

    @Test("JSON 문법 — 거부하는 것", arguments: [
        "", " ", #"{"a":1,}"#, #"{'a':1}"#, #"{a:1}"#, #"{"a":01}"#, #"{"a":+1}"#, #"{"a":.5}"#, #"{"a":1.}"#, #"{"a":1e}"#,
        #"{"a":-}"#, #"{"a":NaN}"#, #"{"a":Infinity}"#, #"{"a":tru}"#, #"{"a":"\x"}"#, #"{"a":"\u12"}"#, #"{"a":"\u12G4"}"#,
        "{\"a\":\"\u{1}\"}", "{\"a\":\"\n\"}", #"{"a":"\ud800"}"#, #"{"a":"\udc00"}"#, #"{"a":"\ud800A"}"#,
        #"{"a":"\ud800x"}"#, #"{"a":1,"a":1}"#, #"{"a":1,"a":2}"#, #"{"a":{"b":{"c":{}}}}"#, #"[[[[]]]]"#,
        #"{}{}"#, #"{} x"#, "\u{FEFF}{}", "{\u{0C}}", #"{"a":1"#, #"{"a""#, #"["#
    ])
    func jsonRejects(text: String) {
        #expect(throws: GSPackFailure.malformed) { try GSPackJSONParser.parse(Array(text.utf8)) }
    }

    @Test("JSON — UTF-8 BOM·잘못된 UTF-8 바이트·인코딩된 서로게이트는 구문 오류")
    func jsonRejectsBadBytes() {
        for bytes: [UInt8] in [[0xEF, 0xBB, 0xBF, 0x7B, 0x7D], [0x7B, 0x22, 0xC0, 0xAF, 0x22, 0x3A, 0x31, 0x7D],
                               [0x22, 0xED, 0xA0, 0x80, 0x22], [0x22, 0xB0, 0xA1, 0x22]] {
            #expect(throws: GSPackFailure.malformed) { try GSPackJSONParser.parse(bytes) }
        }
    }

    @Test("JSON — 이스케이프를 풀어 바이트로 남기고, 키 비교는 바이트(정준 동치가 아니다)")
    func jsonDecodesEscapes() throws {
        let value = try GSPackJSONParser.parse(Array(#"{"s":"\"\\\/\b\f\n\r\té😀\u0000"}"#.utf8))
        let expected = Array("\"\\/\u{8}\u{C}\n\r\t\u{E9}\u{1F600}\u{0}".utf8)
        #expect(value == .object([GSPackJSONMember(key: Array("s".utf8), value: .string(expected))]))
        guard case .object(let members) = try GSPackJSONParser.parse(Array(#"{"é":1,"é":2}"#.utf8)) else {
            Issue.record("객체가 아니다")
            return
        }
        #expect(members.count == 2, "U+00E9와 e+U+0301은 다른 키다")
    }

    @Test("JSON — 깊은 중첩도 깊이 4에서 멈춘다(재귀 폭주 없음)")
    func jsonDeepNesting() {
        let deep = String(repeating: "[", count: 100_000) + String(repeating: "]", count: 100_000)
        #expect(throws: GSPackFailure.malformed) { try GSPackJSONParser.parse(Array(deep.utf8)) }
    }

    // MARK: 엄격 base64(ⓕ)

    @Test("base64 — 정규형만", arguments: [
        ("", true), ("AAAA", true), ("AA==", true), ("AAA=", true), ("EBESExQVFhcYGRobHB0eHw==", true),
        ("AA", false), ("AAA", false), ("AB==", false), ("AAB=", false), ("A===", false), ("=AAA", false), ("A=AA", false),
        ("AA-_", false), ("AA AA", false), ("AA\nA", false), ("AAAA====", false), ("EBESExQVFhcYGRobHB0eHx==", false)
    ])
    func base64Canonical(text: String, valid: Bool) {
        #expect((GSPackBase64.decodeCanonical(Array(text.utf8)) != nil) == valid)
    }

    @Test("salt 16·nonce 12바이트 정확히")
    func saltNonceSizes() {
        for salt in [Data(count: 15), Data(count: 17), Data()] {
            #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(salt: salt.base64EncodedString())) }
        }
        for nonce in [Data(count: 11), Data(count: 13)] {
            #expect(throws: GSPackFailure.malformed) { try parse(GSPackSpec.text(nonce: nonce.base64EncodedString())) }
        }
    }

    private func parse(_ text: String) throws(GSPackFailure) -> GSPackEnvelope {
        try GSPackEnvelope.parse(Data(text.utf8))
    }
}

// MARK: - 12-2 · 12-6 예시

enum GSPackSpec {
    static let password = "샘플비밀번호-2026"
    static let keyHex = "0d49353d3c8a5c5ada032ce31753dfe39df5177a25d3554ca0ae31015c984893"
    static let plaintext = "#이름,찬송가 샘플\n번호,본문\n1,가나다\n"
    static let aadHex = "0000000c6765756c736f652d7061636b0001000000086373762d757466380000001970626b6466322d7368613235362b"
        + "6165732d3235362d67636d000927c000000010ecb0acec86a1eab08020ec8398ed948c00000000"
    static let ciphertext = "GS8ROstM9CdUmOuCaB6mlUthEGIgXKgpbqAKqBe3uO3BTXLl6L7tLJLEPLYM1wzdQl9hBgUcp2ygHWcL0s1geK9lJA=="
    static let salt = "EBESExQVFhcYGRobHB0eHw=="
    static let nonce = "oKGio6Slpqeoqaqr"

    /// 문서 12-2의 예시 파일 그대로(제작기 출력 모양 — 2칸 들여쓰기 + 끝 줄바꿈)
    static let fileText = """
    {
      "format": "geulsoe-pack",
      "version": 1,
      "inner": "csv-utf8",
      "meta": {
        "name": "찬송가 샘플",
        "rights": ""
      },
      "encryption": {
        "scheme": "pbkdf2-sha256+aes-256-gcm",
        "iterations": 600000,
        "salt": "EBESExQVFhcYGRobHB0eHw==",
        "nonce": "oKGio6Slpqeoqaqr"
      },
      "ciphertext": "GS8ROstM9CdUmOuCaB6mlUthEGIgXKgpbqAKqBe3uO3BTXLl6L7tLJLEPLYM1wzdQl9hBgUcp2ygHWcL0s1geK9lJA=="
    }

    """

    /// 한 칸만 바꾼 봉투 글자 — 이름·출처는 JSON 이스케이프가 필요 없는 글자만(아니면 `…Literal`로 원문을 준다)
    static func text(name: String = "찬송가 샘플", rights: String = "", nameLiteral: String? = nil, rightsLiteral: String? = nil,
                     iterations: String = "600000", salt: String = Self.salt, nonce: String = Self.nonce,
                     ciphertext: String = Self.ciphertext,
                     extraTop: String = "", extraMeta: String = "", extraEncryption: String = "") -> String {
        """
        {"format":"geulsoe-pack","version":1,"inner":"csv-utf8",\
        "meta":{"name":"\(nameLiteral ?? name)","rights":"\(rightsLiteral ?? rights)"\(extraMeta)},\
        "encryption":{"scheme":"pbkdf2-sha256+aes-256-gcm","iterations":\(iterations),"salt":"\(salt)","nonce":"\(nonce)"\(extraEncryption)},\
        "ciphertext":"\(ciphertext)"\(extraTop)}
        """
    }
}
