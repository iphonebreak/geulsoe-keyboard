import Foundation
import TadakDomain

/// 잠금 팩(`.gspack`) 상한·고정값 — **한 곳**(PDR `external-snippet-packs.md` 12-3·12-4·12-5).
///
/// 앱 전용 `PackImport`에만 둔다 — `TadakDomain`·`TadakData`는 키보드가 링크하므로 암호 관련 상수를 두지 않는다(12-10 ⑤).
/// 복호화본 상한은 평문 CSV 파일 상한(`PackLimits.fileBytes`)과 **같은 값**을 그대로 쓴다(12-3 ④).
public enum GSPackLimits {

    // MARK: 크기 — 4계층(12-3)

    /// ① 봉투(파일 전체) 바이트. base64 4,000,024 + 여유 99,976(골격·들여쓰기·이스케이프한 메타 최악)
    public static let envelopeBytes = 4_100_000
    /// ② `ciphertext` base64 글자 수 — `4 × ceil(3,000,016 / 3)`. **디코드 전에** 본다
    public static let ciphertextBase64Characters = 4_000_024
    /// ③ 디코드한 암호문‖tag 바이트 상한. 하한은 `tagBytes`(빈 평문 = tag만)
    public static let ciphertextBytes = 3_000_016
    /// ④ 복호화본(안쪽 CSV) 바이트 — 평문 CSV 파일 상한과 같다
    public static let plaintextBytes = PackLimits.fileBytes

    // MARK: 암호(12-5)

    /// 수신 허용 반복 수 — KDF **전에** 검사(악의적 봉투의 계산 부하 방지)
    public static let iterations: ClosedRange<Int> = 300_000...2_000_000
    /// 제작기 반복 수(출발값 — P-5 게이트가 확정한다)
    public static let makerIterations = 600_000
    /// 비밀번호 상한 — NFC UTF-8 바이트(12-4, M6)
    public static let passwordMaxBytes = 256
    public static let saltBytes = 16
    public static let nonceBytes = 12
    public static let tagBytes = 16
    /// PBKDF2 출력 = AES-256 키 길이
    static let keyBytes = 32

    // MARK: 형식 식별자(12-2·12-10)

    public static let fileExtension = "gspack"
    public static let typeIdentifier = "com.charging.tadak.pack"

    /// 봉투 고정값 — AAD(12-6)에도 같은 바이트로 들어간다
    static let format = "geulsoe-pack"
    static let version = 1
    static let inner = "csv-utf8"
    static let scheme = "pbkdf2-sha256+aes-256-gcm"
    /// `iterations` 정수 리터럴의 최대 자릿수 — 넘으면 **변환 전에** 거부(정수 오버플로 방지, 12-2)
    static let iterationsMaxDigits = 10
    /// JSON 중첩 깊이 상한 — 최상위 객체 1 → `meta`·`encryption` 2(12-2 규칙 4)
    static let jsonMaxDepth = 3
}
