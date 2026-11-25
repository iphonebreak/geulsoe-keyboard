import CommonCrypto
import CryptoKit
import Foundation

/// 비밀번호 바이트·salt·반복 수 → 32바이트 키. 실패하면 nil. 시험은 스파이·고정 키를 주입한다
public typealias GSPackKeyDerivation = @Sendable (_ password: [UInt8], _ salt: Data, _ iterations: Int) -> [UInt8]?

/// 잠금 팩 열기(PDR `external-snippet-packs.md` 12-5·12-8) — 복호화만 한다(앱은 암호화하지 않는다, A1).
///
/// 암호는 **OS 제공만**: PBKDF2는 CommonCrypto `CCKeyDerivationPBKDF`(CryptoKit에는 PBKDF2가 없다),
/// AEAD는 CryptoKit `AES.GCM`. 자체 구현·서드파티 0(12-12 ①).
///
/// ★ KDF는 수백 ms~수 초 걸리는 취소 불가 C 호출이다 — **메인 스레드에서 부르지 않는다**(12-5 「스레드」). 동시 1개·취소(결과 버림)는 세션 몫이다.
/// ★ 비밀번호·키·복호화본은 로그·파일·네트워크로 내보내지 않는다(security.md 1순위). 실패는 값 없는 `GSPackFailure`다.
public enum GSPackOpener {

    /// PBKDF2-HMAC-SHA256, 출력 32바이트. 비밀번호는 **포인터 + 길이**로 넘겨 NUL에서 잘리지 않는다
    public static let pbkdf2: GSPackKeyDerivation = { password, salt, iterations in
        guard let rounds = UInt32(exactly: iterations), rounds > 0 else { return nil }
        var key = [UInt8](repeating: 0, count: GSPackLimits.keyBytes)
        let status = key.withUnsafeMutableBytes { keyBuffer in
            password.withUnsafeBytes { passwordBuffer in
                salt.withUnsafeBytes { saltBuffer in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress?.assumingMemoryBound(to: CChar.self), passwordBuffer.count,
                        saltBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), saltBuffer.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), rounds,
                        keyBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self), keyBuffer.count)
                }
            }
        }
        guard status == kCCSuccess else {
            GSPackSecureBytes.zero(&key)
            return nil
        }
        return key
    }

    /// 비밀번호(ⓖ) → KDF → `AES.GCM.open`(AAD = 12-6) → ④ 복호화본 상한 → UTF-8 BOM 벗김 → 엄격 UTF-8 → 글자.
    ///
    /// - 빈 비밀번호·256B 초과는 KDF를 부르지 않는다(`passwordEmpty`·`passwordTooLong`)
    /// - tag 실패는 틀린 비밀번호와 변조를 구분하지 않는다(`wrongPasswordOrDamaged`, M4)
    /// - KDF가 실패하거나 32바이트가 아닌 키를 주면 `wrongPasswordOrDamaged` — 짧은 키로 AES-128이 되는 일을 막는다
    public static func open(_ envelope: GSPackEnvelope, password: String,
                            deriveKey: GSPackKeyDerivation = GSPackOpener.pbkdf2) throws(GSPackFailure) -> String {
        var material = try GSPackPassword.keyMaterial(password)
        defer { GSPackSecureBytes.zero(&material) }
        let box = try sealedBox(envelope)

        guard var key = deriveKey(material, envelope.salt, envelope.iterations) else { throw .wrongPasswordOrDamaged }
        defer { GSPackSecureBytes.zero(&key) }
        guard key.count == GSPackLimits.keyBytes else { throw .wrongPasswordOrDamaged }

        var plaintext: Data
        do {
            plaintext = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: envelope.additionalData)
        } catch {
            throw .wrongPasswordOrDamaged
        }
        defer { GSPackSecureBytes.zero(&plaintext) }
        // ④ — ③(암호문 ≤ 3,000,016B)에서 이미 보장되지만 심층 방어로 따로 본다(12-3)
        guard plaintext.count <= GSPackLimits.plaintextBytes else { throw .tooLarge }
        return try innerText(plaintext)
    }

    /// 암호문 ‖ tag(뒤 16B)를 나눈다 — `parse`를 거친 봉투면 실패하지 않는다(nonce 12B·암호문 ≥ 16B)
    private static func sealedBox(_ envelope: GSPackEnvelope) throws(GSPackFailure) -> AES.GCM.SealedBox {
        guard envelope.sealed.count >= GSPackLimits.tagBytes else { throw .malformed }
        do {
            return try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce),
                                         ciphertext: envelope.sealed.dropLast(GSPackLimits.tagBytes),
                                         tag: envelope.sealed.suffix(GSPackLimits.tagBytes))
        } catch {
            throw .malformed
        }
    }

    /// 안쪽 CSV(12-8) — **평문 CSV 파일과 같은 디코더**(`PackTextDecoder`)를 UTF-8 고정으로 쓴다: UTF-8 BOM(`EF BB BF`)을 벗기고
    /// 바로 뒤 `U+FEFF` 하나를 더 뗀다(BOM 두 번 붙은 파일, 검증 F8 — 평문 경로와 같은 결과), 나머지는 엄격 UTF-8(대체 문자 복구 없음).
    /// CP949·UTF-16 자동 판정·인코딩 확인 화면을 타지 않는다(`choice: .utf8`). 어떤 디코드 실패든 M5
    static func innerText(_ plaintext: Data) throws(GSPackFailure) -> String {
        do {
            return try PackTextDecoder.decode(plaintext, choice: .utf8).text
        } catch {
            throw .unreadableContent
        }
    }
}
