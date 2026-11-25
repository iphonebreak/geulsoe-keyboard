import Foundation

/// ✕·탭으로 소비한 클립보드 글의 **지문** — 원문 대신 저장해 같은 글이 다시 왔는지 알아본다(2026-11-25).
///
/// 유니버설 클립보드는 같은 글을 새 `changeCount`로 다시 보낸다(`PasteboardConsumption` 참조) — 번호로는 못 알아본다.
/// 원문을 저장하지 않으려고 글의 UTF-8 바이트에 **기기 열쇠**(기기마다 무작위 32바이트, 키보드 전용 컨테이너 —
/// `PasteboardConsumptionStore.fingerprintKey`)를 섞어 16바이트 지문을 만든다. 같은 글도 기기마다 지문이 다르다.
///
/// ## 암호 라이브러리를 쓰지 않는다
///
/// 키보드에는 CryptoKit·CommonCrypto 암호 호출을 싣지 않는다 — 잠금 팩 복호화는 앱 전용이고(`external-snippet-packs.md`
/// 12-10 ⑥-3), 출시 점검(`tools/archive-compliance-check.sh` `keyboard_crypto_check`)이 키보드의 CryptoKit 심볼을 실패로 본다.
/// 지문은 **같은 글인지 가리기**만 하면 되므로 비암호 해시 FNV-1a 64비트를 열쇠의 두 반쪽으로 두 번 돌려 붙인다.
/// 다른 글이 같은 지문을 낼 확률은 무시할 만하고, 잘못 맞으면 새 칩 하나가 안 뜰 뿐이다.
///
/// 한계(사장님 결정 2026-11-25에 함께 적었다): 열쇠와 지문은 같은 컨테이너에 있으므로, 인증번호처럼 짧은 글은
/// 둘을 함께 가진 사람이 경우의 수를 다 넣어 맞힐 수 있다 — **기기 밖으로 나가지 않는 것**이 보호의 전부다.
public enum PasteboardFingerprint {

    /// 열쇠 길이(바이트) — 저장소가 만드는 열쇠와 같다
    public static let keyByteCount = 32
    /// 지문 길이(바이트) — 64비트 두 갈래
    public static let byteCount = 16

    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// 글 바이트는 `text.utf8`을 그대로 훑는다 — 배열로 복사하지 않는다(긴 클립보드가 키보드 메모리 한도를 두 배로 쓰지 않게)
    public static func make(_ text: String, key: Data) -> Data {
        let keyBytes = Array(key)
        let half = keyBytes.count / 2
        let first = fnv1a(keyBytes[..<half], then: text.utf8)
        let second = fnv1a(keyBytes[half...], then: text.utf8)
        return bigEndianBytes(first) + bigEndianBytes(second)
    }

    private static func fnv1a(_ salt: ArraySlice<UInt8>, then bytes: String.UTF8View) -> UInt64 {
        var hash = offsetBasis
        for byte in salt { hash = (hash ^ UInt64(byte)) &* prime }
        for byte in bytes { hash = (hash ^ UInt64(byte)) &* prime }
        return hash
    }

    private static func bigEndianBytes(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
