import Foundation

/// 비밀번호 → KDF 입력 바이트(PDR `external-snippet-packs.md` 12-4).
///
/// - **NFC**(NFKC 아님 — 전각 `ＡＢＣ`와 `ABC`는 다른 비밀번호다). 제작기(JS `normalize('NFC')`)·파이썬 도구와 같은 규칙
/// - **자르지 않는다**(앞뒤 공백도 비밀번호다 — 바이트 정확). 수신 측 최소 길이는 없다 — 단 빈 값은 KDF를 시도하지 않는다
/// - 상한 NFC UTF-8 `GSPackLimits.passwordMaxBytes`(M6 — 파일 오류가 아니라 입력 오류)
/// - NUL도 그대로 담는다 — KDF에는 길이와 함께 넘긴다(C 문자열이 아니다)
public enum GSPackPassword {

    /// 돌려받은 배열은 쓰고 나서 `GSPackSecureBytes.zero`로 지운다(최선 노력 — 아래 한계 참조).
    ///
    /// ★ 한계: 입력 `String`과 NFC 사본은 Swift가 영점화를 보장하지 않는 불변 저장소라 지울 수 없다.
    /// 지우는 것은 이 함수가 돌려준 바이트 사본뿐이다.
    public static func keyMaterial(_ password: String) throws(GSPackFailure) -> [UInt8] {
        guard !password.isEmpty else { throw .passwordEmpty }
        let normalized = password.precomposedStringWithCanonicalMapping
        guard normalized.utf8.count <= GSPackLimits.passwordMaxBytes else { throw .passwordTooLong }
        return Array(normalized.utf8)
    }
}

/// 비밀번호·키·복호화본 바이트 사본의 영점화 — **최선 노력**.
///
/// `memset_s`는 최적화로 지워지지 않는다. 그러나 Swift 배열·`Data`는 값 복사(copy-on-write)라 이미 다른 곳에 생긴 사본,
/// CryptoKit·CommonCrypto 내부 버퍼, 그 배열이 재할당되기 전 옛 버퍼까지는 지울 수 없다.
enum GSPackSecureBytes {

    static func zero(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            _ = memset_s(base, raw.count, 0, raw.count)
        }
    }

    static func zero(_ data: inout Data) {
        data.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return }
            _ = memset_s(base, raw.count, 0, raw.count)
        }
    }
}
