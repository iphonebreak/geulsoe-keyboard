import Foundation
import TadakDomain

/// 잠금 팩 봉투(파일 형식 v1, PDR `external-snippet-packs.md` 12-2) — 검증을 **모두 통과한** 값만 만들어진다.
///
/// `parse`는 KDF 호출 **전**의 검사 ⓐ~ⓕ를 고정 순서로 끝낸다. 비밀번호 입력(ⓖ)과 복호는 `GSPackOpener`가 한다.
/// `meta`는 복호 전에는 **미인증 표시 사본**이다 — 복호에 성공하면 같은 문자열이 AAD로 인증된 것이다(AC-G4).
public struct GSPackEnvelope: Equatable, Sendable {
    public let meta: GSPackMeta
    public let iterations: Int
    /// PBKDF2 salt — 정확히 `GSPackLimits.saltBytes`
    let salt: Data
    /// GCM IV — 정확히 `GSPackLimits.nonceBytes`
    let nonce: Data
    /// 암호문 ‖ GCM tag(16B, **뒤**) — `tagBytes`…`ciphertextBytes`
    let sealed: Data

    /// AAD(12-6) — `F(format) ‖ U16(version) ‖ F(inner) ‖ F(scheme) ‖ U32(iterations) ‖ F(name) ‖ F(rights)`.
    /// 문자열은 JSON 해석 뒤 **그대로**의 UTF-8(정규화 없음), `F(s)` = U32 길이 접두. 정수는 big-endian.
    /// `salt`·`nonce`·`ciphertext`는 넣지 않는다(키 파생·IV로 이미 묶인다)
    var additionalData: Data {
        var aad = Data()
        Self.appendField(GSPackLimits.format, to: &aad)
        Self.appendBigEndian(UInt16(GSPackLimits.version), to: &aad)
        Self.appendField(GSPackLimits.inner, to: &aad)
        Self.appendField(GSPackLimits.scheme, to: &aad)
        Self.appendBigEndian(UInt32(truncatingIfNeeded: iterations), to: &aad)
        Self.appendField(meta.name, to: &aad)
        Self.appendField(meta.rights, to: &aad)
        return aad
    }

    private static func appendField(_ text: String, to aad: inout Data) {
        let bytes = Array(text.utf8)
        appendBigEndian(UInt32(truncatingIfNeeded: bytes.count), to: &aad)
        aad.append(contentsOf: bytes)
    }

    private static func appendBigEndian<T: FixedWidthInteger>(_ value: T, to aad: inout Data) {
        withUnsafeBytes(of: value.bigEndian) { aad.append(contentsOf: $0) }
    }
}

// MARK: - 검사 ⓐ~ⓕ (KDF 전)

extension GSPackEnvelope {

    /// 봉투 바이트를 검사해 값으로 만든다. 순서(12-2 규칙 6)는 고정이다 —
    /// ⓐ 크기 ① → ⓑ JSON 구문·중복 키·깊이 → ⓒ `format` → ⓓ `version`(정수 ≥ 2면 여기서 M2) →
    /// ⓔ 나머지 구조·타입·모르는/누락 키·고정값·`iterations` 범위·메타 규칙 → ⓕ base64 엄격·길이(② ③).
    public static func parse(_ data: Data) throws(GSPackFailure) -> GSPackEnvelope {
        // ⓐ 크기 ① — 파일 읽기 단계의 cap+1과 같은 값(심층 방어)
        guard data.count <= GSPackLimits.envelopeBytes else { throw .tooLarge }
        // ⓑ
        guard case .object(let top) = try GSPackJSONParser.parse([UInt8](data)) else { throw .malformed }
        // ⓒ
        guard case .string(let format)? = top.value(for: "format"), format.elementsEqual(GSPackLimits.format.utf8) else {
            throw .malformed
        }
        // ⓓ
        try checkVersion(top.value(for: "version"))
        // ⓔ
        try top.requireKeys(["format", "version", "inner", "meta", "encryption", "ciphertext"])
        guard case .string(let inner)? = top.value(for: "inner"), inner.elementsEqual(GSPackLimits.inner.utf8) else {
            throw .malformed
        }
        let meta = try parseMeta(top.value(for: "meta"))
        guard case .object(let encryption)? = top.value(for: "encryption") else { throw .malformed }
        try encryption.requireKeys(["scheme", "iterations", "salt", "nonce"])
        guard case .string(let scheme)? = encryption.value(for: "scheme"), scheme.elementsEqual(GSPackLimits.scheme.utf8) else {
            throw .malformed
        }
        let iterations = try parseIterations(encryption.value(for: "iterations"))
        guard case .string(let saltText)? = encryption.value(for: "salt"),
              case .string(let nonceText)? = encryption.value(for: "nonce"),
              case .string(let ciphertextText)? = top.value(for: "ciphertext") else { throw .malformed }
        // ⓕ
        guard let salt = GSPackBase64.decodeCanonical(saltText), salt.count == GSPackLimits.saltBytes,
              let nonce = GSPackBase64.decodeCanonical(nonceText), nonce.count == GSPackLimits.nonceBytes else {
            throw .malformed
        }
        let sealed = try decodeCiphertext(ciphertextText)
        return GSPackEnvelope(meta: meta, iterations: iterations, salt: salt, nonce: nonce, sealed: sealed)
    }

    /// ⓓ — 정수 리터럴 `1`만 통과. 음수·`0`은 M1, 그 밖의 정수(≥ 2 — JSON은 앞자리 0이 없다)는 M2.
    /// 변환하지 않고 리터럴로 판정하므로 자릿수가 아무리 커도 넘치지 않는다
    private static func checkVersion(_ value: GSPackJSONValue?) throws(GSPackFailure) {
        guard case .number(let literal, isInteger: true)? = value else { throw .malformed }
        if literal.elementsEqual(String(GSPackLimits.version).utf8) { return }
        if literal.first == UInt8(ascii: "-") || literal.elementsEqual("0".utf8) { throw .malformed }
        throw .newerVersion
    }

    private static func parseMeta(_ value: GSPackJSONValue?) throws(GSPackFailure) -> GSPackMeta {
        guard case .object(let members)? = value else { throw .malformed }
        try members.requireKeys(["name", "rights"])
        return GSPackMeta(name: try metaText(members.value(for: "name"), limit: PackLimits.name),
                          rights: try metaText(members.value(for: "rights"), limit: PackLimits.license))
    }

    /// 메타 규칙(12-2) — 빈 문자열 허용, 제어 문자 거부, 도메인 상한 세 잣대. **정규화하지 않는다**
    private static func metaText(_ value: GSPackJSONValue?, limit: PackLimits.FieldLimit) throws(GSPackFailure) -> String {
        guard case .string(let bytes)? = value else { throw .malformed }
        let text = String(decoding: bytes, as: UTF8.self)
        guard !text.unicodeScalars.contains(where: isForbiddenInMeta), limit.admits(text) else { throw .malformed }
        return text
    }

    /// U+0000~U+001F, U+007F, U+0080~U+009F, U+2028·U+2029
    static func isForbiddenInMeta(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029: true
        default: false
        }
    }

    /// 정수 리터럴만, 음수·자릿수 초과는 **변환 전에** 거부, 그다음 수신 허용 범위
    private static func parseIterations(_ value: GSPackJSONValue?) throws(GSPackFailure) -> Int {
        guard case .number(let literal, isInteger: true)? = value,
              literal.first != UInt8(ascii: "-"),
              literal.count <= GSPackLimits.iterationsMaxDigits,
              let iterations = Int(String(decoding: literal, as: UTF8.self)),
              GSPackLimits.iterations.contains(iterations) else { throw .malformed }
        return iterations
    }

    /// ⓕ 암호문 — 알파벳(M1) → ② 글자 수(M3, 디코드 전) → 정규형 디코드(M1) → ③ 바이트 상한(M3)·하한 tag(M1).
    /// 알파벳을 먼저 보는 이유: 그다음부터 글자 수 = 바이트 수라 웹·파이썬·Swift가 ②를 같은 값으로 잰다
    private static func decodeCiphertext(_ text: [UInt8]) throws(GSPackFailure) -> Data {
        guard GSPackBase64.usesAlphabet(text) else { throw .malformed }
        guard text.count <= GSPackLimits.ciphertextBase64Characters else { throw .tooLarge }
        guard let sealed = GSPackBase64.decodeCanonical(text) else { throw .malformed }
        guard sealed.count <= GSPackLimits.ciphertextBytes else { throw .tooLarge }
        guard sealed.count >= GSPackLimits.tagBytes else { throw .malformed }
        return sealed
    }
}

// MARK: - 객체 멤버 조회(바이트 비교)

private extension Array where Element == GSPackJSONMember {

    /// 키를 **바이트로** 비교한다 — `String ==`은 정준 동치라 U+212A(켈빈)를 `K`와 같다고 본다
    func value(for key: String) -> GSPackJSONValue? {
        first { $0.key.elementsEqual(key.utf8) }?.value
    }

    /// 키 집합이 정확히 `keys`인가 — 중복은 ⓑ가 이미 막았으므로 개수 + 포함으로 충분하다(모르는 키·누락 키 모두 M1, `hint` 포함)
    func requireKeys(_ keys: [String]) throws(GSPackFailure) {
        guard count == keys.count, keys.allSatisfy({ key in contains { $0.key.elementsEqual(key.utf8) } }) else {
            throw .malformed
        }
    }
}
