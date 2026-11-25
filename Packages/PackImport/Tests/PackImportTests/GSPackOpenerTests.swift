import CryptoKit
import Foundation
import Testing
@testable import PackImport

/// 잠금 팩 열기 — KDF·AES-GCM·비밀번호 규칙·안쪽 UTF-8·크기 경계(PDR `external-snippet-packs.md` 12-3·12-4·12-5·12-6·12-8).
///
/// V27(③ 경계)·V28(① 경계)은 수 MB라 커밋하지 않고 여기서 만든다. 복호가 되는 3,000,000B 경우는 CryptoKit으로 고정 키 봉인 +
/// 그 키를 돌려주는 KDF 주입으로 만든다(크기 계층 시험이지 상호운용 시험이 아니다 — 상호운용은 `GSPackVectorTests`).
@Suite("잠금 팩 — 열기 (12-4 · 12-5 · 12-8)")
struct GSPackOpenerTests {

    // MARK: 12-6 작동 예시

    @Test("12-6 작동 예시 — 파생 키·평문이 문서와 같다(AC-G4 Swift 쪽 첫 확인)")
    func workedExample() throws {
        let envelope = try GSPackEnvelope.parse(Data(GSPackSpec.fileText.utf8))
        let spy = GSPackKDFSpy()
        let text = try GSPackOpener.open(envelope, password: GSPackSpec.password, deriveKey: spy.derive)
        #expect(spy.callCount == 1)
        #expect(spy.derivedKey?.hexString == GSPackSpec.keyHex)
        #expect(text == GSPackSpec.plaintext)
        #expect(text.utf8.elementsEqual(GSPackSpec.plaintext.utf8))
    }

    @Test("PBKDF2 — 12-6 비밀번호 바이트·salt·600,000 → 문서의 키")
    func pbkdf2KnownAnswer() throws {
        let password = try GSPackPassword.keyMaterial(GSPackSpec.password)
        #expect(password.hexString == "ec8398ed948cebb984ebb080ebb288ed98b82d32303236")
        let key = try #require(GSPackOpener.pbkdf2(password, Data(gspackHex: "101112131415161718191a1b1c1d1e1f")!, 600_000))
        #expect(key.hexString == GSPackSpec.keyHex)
    }

    @Test("PBKDF2 — 비밀번호는 길이와 함께 넘긴다(NUL에서 잘리지 않는다)·반복 수 0은 실패")
    func pbkdf2IsNulSafe() throws {
        let salt = Data(count: 16)
        let withNul = try #require(GSPackOpener.pbkdf2(Array("ab\u{0}cd".utf8), salt, 1_000))
        let truncated = try #require(GSPackOpener.pbkdf2(Array("ab".utf8), salt, 1_000))
        #expect(withNul.count == 32)
        #expect(withNul != truncated)
        #expect(GSPackOpener.pbkdf2(Array("ab".utf8), salt, 0) == nil)
    }

    // MARK: 비밀번호(12-4)

    @Test("비밀번호 — NFC로 바꾸고, 자르지 않고, NFKC가 아니다")
    func passwordNormalization() throws {
        let nfc = "한글비번"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        #expect(Array(nfd.utf8) != Array(nfc.utf8))
        #expect(try GSPackPassword.keyMaterial(nfd) == Array(nfc.utf8))
        #expect(try GSPackPassword.keyMaterial("e\u{0301}") == [0xC3, 0xA9])
        #expect(try GSPackPassword.keyMaterial("\u{212B}") == Array("\u{00C5}".utf8))
        #expect(try GSPackPassword.keyMaterial("\u{0958}") == Array("\u{0915}\u{093C}".utf8), "NFC 구성 제외 문자")
        #expect(try GSPackPassword.keyMaterial(" pw ") == Array(" pw ".utf8), "앞뒤 공백도 비밀번호")
        #expect(try GSPackPassword.keyMaterial("a\u{0}b") == [0x61, 0x00, 0x62])
        #expect(try GSPackPassword.keyMaterial("ＡＢＣ") != Array("ABC".utf8), "전각은 다른 비밀번호")
    }

    @Test("비밀번호 — 빈 값은 KDF 전 거부, 256B까지 받고 257B는 M6(NFC 뒤 바이트로 잰다)")
    func passwordLength() throws {
        #expect(throws: GSPackFailure.passwordEmpty) { try GSPackPassword.keyMaterial("") }
        let exact = String(repeating: "가", count: 85) + "a"
        #expect(try GSPackPassword.keyMaterial(exact).count == 256)
        #expect(throws: GSPackFailure.passwordTooLong) { try GSPackPassword.keyMaterial(exact + "a") }
        #expect(throws: GSPackFailure.passwordTooLong) { try GSPackPassword.keyMaterial(String(repeating: "가", count: 86)) }
        // NFD 입력은 765B지만 NFC로 255B — NFC 뒤에 잰다
        let nfd = String(repeating: "한", count: 85).decomposedStringWithCanonicalMapping
        #expect(nfd.utf8.count == 765)
        #expect(try GSPackPassword.keyMaterial(nfd).count == 255)
    }

    @Test("빈 비밀번호·257B 비밀번호로 열면 KDF를 부르지 않는다")
    func passwordErrorsSkipKDF() throws {
        let envelope = try GSPackEnvelope.parse(Data(GSPackSpec.fileText.utf8))
        let spy = GSPackKDFSpy()
        #expect(throws: GSPackFailure.passwordEmpty) { try GSPackOpener.open(envelope, password: "", deriveKey: spy.derive) }
        #expect(throws: GSPackFailure.passwordTooLong) {
            try GSPackOpener.open(envelope, password: String(repeating: "a", count: 257), deriveKey: spy.derive)
        }
        #expect(spy.callCount == 0)
    }

    // MARK: KDF 결과 방어

    @Test("KDF 실패(nil)·32바이트가 아닌 키는 M4 — 16바이트 키로 AES-128이 되지 않는다")
    func badDerivedKey() throws {
        let short = SymmetricKey(data: [UInt8](repeating: 0x11, count: 16))
        let envelope = try Self.sealedEnvelope(plaintext: Data("a,b\n".utf8), key: short)
        #expect(throws: GSPackFailure.wrongPasswordOrDamaged) {
            try GSPackOpener.open(envelope, password: "pw", deriveKey: { _, _, _ in [UInt8](repeating: 0x11, count: 16) })
        }
        #expect(throws: GSPackFailure.wrongPasswordOrDamaged) {
            try GSPackOpener.open(envelope, password: "pw", deriveKey: { _, _, _ in nil })
        }
    }

    @Test("KDF에는 NFC 비밀번호 바이트·봉투의 salt·반복 수가 그대로 간다")
    func kdfInputs() throws {
        let envelope = try GSPackEnvelope.parse(Data(GSPackSpec.fileText.utf8))
        let seen = GSPackKDFInputs()
        _ = try? GSPackOpener.open(envelope, password: GSPackSpec.password.decomposedStringWithCanonicalMapping,
                                   deriveKey: { password, salt, iterations in seen.record(password, salt, iterations); return nil })
        #expect(seen.password == Array(GSPackSpec.password.utf8))
        #expect(seen.salt == envelope.salt && seen.iterations == 600_000)
    }

    // MARK: 안쪽 UTF-8(12-8)

    @Test("안쪽 — BOM(겹 BOM은 하나 더)을 벗기고 엄격 UTF-8, 아니면 M5. CP949·UTF-16을 자동 판정하지 않는다")
    func innerText() throws {
        #expect(try GSPackOpener.innerText(Data()) == "")
        #expect(try GSPackOpener.innerText(Data([0xEF, 0xBB, 0xBF])) == "")
        #expect(try GSPackOpener.innerText(Data([0xEF, 0xBB, 0xBF]) + Data("가".utf8)) == "가")
        #expect(try GSPackOpener.innerText(Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF])) == "")
        #expect(try GSPackOpener.innerText(Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF])) == "\u{FEFF}")
        #expect(try GSPackOpener.innerText(Data([0x61, 0x00, 0x62])) == "a\u{0}b", "NUL은 UTF-8이다 — 거부는 CSV 단계 몫")
        for bytes: [UInt8] in [[0xB0, 0xA1], [0xFF, 0xFE, 0x00, 0xAC], [0xFE, 0xFF, 0xAC, 0x00], [0xFF, 0xFE, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00],
                               [0xEF, 0xBB, 0xBF, 0xB0, 0xA1], [0xED, 0xA0, 0x80], [0xC0, 0xAF], [0x61, 0xE0, 0xA4]] {
            #expect(throws: GSPackFailure.unreadableContent) { try GSPackOpener.innerText(Data(bytes)) }
        }
    }

    // MARK: V27 — ③ 경계 (시험 안에서 생성)

    @Test("V27 — 평문 3,000,000B는 복호된다(봉투 ① 안)")
    func v27LargestPlaintextOpens() throws {
        let key = SymmetricKey(data: [UInt8](repeating: 0x42, count: 32))
        let plaintext = Data(repeating: UInt8(ascii: "a"), count: GSPackLimits.plaintextBytes)
        let draft = try Self.sealedEnvelope(plaintext: plaintext, key: key)
        let file = Data(Self.envelopeText(draft).utf8)
        #expect(file.count <= GSPackLimits.envelopeBytes)
        #expect(draft.sealed.base64EncodedString().count == GSPackLimits.ciphertextBase64Characters)

        let spy = GSPackKDFSpy { _, _, _ in key.withUnsafeBytes { Array($0) } }
        let text = try GSPackOpener.open(GSPackEnvelope.parse(file), password: "pw", deriveKey: spy.derive)
        #expect(text.utf8.count == GSPackLimits.plaintextBytes)
        #expect(spy.callCount == 1)
    }

    @Test("V27 — 암호문 3,000,017B(base64 4,000,024자, ② 통과·③ 초과)와 3,000,019B(4,000,028자, ② 초과)는 M3, KDF 0회",
          arguments: [(3_000_017, 4_000_024), (3_000_018, 4_000_024), (3_000_019, 4_000_028)])
    func v27CiphertextTooLarge(bytes: Int, characters: Int) throws {
        let sealed = Data(repeating: 0xAB, count: bytes)
        let base64 = sealed.base64EncodedString()
        #expect(base64.count == characters)
        let text = GSPackSpec.text(iterations: "300000", ciphertext: base64)
        #expect(text.utf8.count <= GSPackLimits.envelopeBytes)
        let spy = GSPackKDFSpy()
        #expect(gspackOutcome(Data(text.utf8), password: "pw", spy: spy) == .failed(.tooLarge))
        #expect(spy.callCount == 0)
    }

    @Test("③ 상한 정확히 3,000,016B는 봉투 검사를 통과한다(틀린 tag라 열면 M4)")
    func v27UpperBoundParses() throws {
        let text = GSPackSpec.text(iterations: "300000", ciphertext: Data(repeating: 0xAB, count: 3_000_016).base64EncodedString())
        let envelope = try GSPackEnvelope.parse(Data(text.utf8))
        #expect(envelope.sealed.count == GSPackLimits.ciphertextBytes)
        let key = [UInt8](repeating: 0x42, count: 32)
        #expect(throws: GSPackFailure.wrongPasswordOrDamaged) {
            try GSPackOpener.open(envelope, password: "pw", deriveKey: { _, _, _ in key })
        }
    }

    @Test("④ 심층 방어 — 봉투 검사를 거치지 않은 3,000,001B 평문도 복호 뒤 M3")
    func plaintextCapAfterOpen() throws {
        let key = SymmetricKey(data: [UInt8](repeating: 0x42, count: 32))
        let envelope = try Self.sealedEnvelope(plaintext: Data(repeating: 0x61, count: GSPackLimits.plaintextBytes + 1), key: key)
        let spy = GSPackKDFSpy { _, _, _ in key.withUnsafeBytes { Array($0) } }
        #expect(throws: GSPackFailure.tooLarge) { try GSPackOpener.open(envelope, password: "pw", deriveKey: spy.derive) }
        #expect(spy.callCount == 1)
    }

    // MARK: V28 — ① 경계 (시험 안에서 생성)

    @Test("V28 — 공백으로 부풀린 정상 파일: 4,100,000B는 열리고 4,100,001B는 M3(KDF 0회)")
    func v28EnvelopeBoundary() throws {
        let base = try GSPackFixtures.data("v20-iterations-300000.gspack")
        let open = Self.padded(base, to: GSPackLimits.envelopeBytes)
        #expect(open.count == 4_100_000)
        let spy = GSPackKDFSpy()
        guard case .opened = gspackOutcome(open, password: "iter-pass-1", spy: spy) else {
            Issue.record("4,100,000B 봉투가 열리지 않았다")
            return
        }
        let tooLarge = Self.padded(base, to: GSPackLimits.envelopeBytes + 1)
        let rejectSpy = GSPackKDFSpy()
        #expect(gspackOutcome(tooLarge, password: "iter-pass-1", spy: rejectSpy) == .failed(.tooLarge))
        #expect(rejectSpy.callCount == 0)
    }

    // MARK: 도우미

    /// CryptoKit으로 봉인한 봉투 값(파일을 거치지 않는다) — AAD는 봉투가 만드는 그대로
    static func sealedEnvelope(plaintext: Data, key: SymmetricKey, name: String = "Big",
                               iterations: Int = 300_000) throws -> GSPackEnvelope {
        let nonceBytes = Data((0..<12).map { UInt8($0) })
        let draft = GSPackEnvelope(meta: GSPackMeta(name: name, rights: ""), iterations: iterations,
                                   salt: Data(repeating: 0x07, count: 16), nonce: nonceBytes, sealed: Data())
        let box = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: nonceBytes),
                                   authenticating: draft.additionalData)
        return GSPackEnvelope(meta: draft.meta, iterations: iterations, salt: draft.salt, nonce: nonceBytes,
                              sealed: box.ciphertext + box.tag)
    }

    static func envelopeText(_ envelope: GSPackEnvelope) -> String {
        GSPackSpec.text(name: envelope.meta.name, rights: envelope.meta.rights, iterations: String(envelope.iterations),
                        salt: envelope.salt.base64EncodedString(), nonce: envelope.nonce.base64EncodedString(),
                        ciphertext: envelope.sealed.base64EncodedString())
    }

    /// 첫 `{` 바로 뒤(토큰 사이)에 공백을 채워 정확히 `size`바이트로
    static func padded(_ data: Data, to size: Int) -> Data {
        var bytes = [UInt8](data)
        let brace = bytes.firstIndex(of: UInt8(ascii: "{"))!
        bytes.insert(contentsOf: repeatElement(0x20, count: size - bytes.count), at: brace + 1)
        return Data(bytes)
    }
}

/// KDF가 받은 입력 기록 — 값 비교용(시험 안에서만)
final class GSPackKDFInputs: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: (password: [UInt8], salt: Data, iterations: Int)?

    func record(_ password: [UInt8], _ salt: Data, _ iterations: Int) {
        lock.withLock { recorded = (password, salt, iterations) }
    }

    var password: [UInt8]? { lock.withLock { recorded?.password } }
    var salt: Data? { lock.withLock { recorded?.salt } }
    var iterations: Int? { lock.withLock { recorded?.iterations } }
}
