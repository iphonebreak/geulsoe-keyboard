import Foundation

/// 잠금 팩 실패 — **값 없는 열거형**(PDR `external-snippet-packs.md` 12-7, 12-4 「로그」).
///
/// ★ 비밀번호·복호화본·봉투 값·파일 이름을 담지 않는다. 화면 문구는 UI가 이 코드에서 만든다.
/// 틀린 비밀번호와 변조는 GCM이 구분하지 못하므로 **한 코드**(`wrongPasswordOrDamaged`)다.
public enum GSPackFailure: Error, Equatable, Sendable {
    /// M1 — JSON 아님·`format` 다름·중복/모르는/누락 키·타입·정수 리터럴·base64·salt/nonce 길이·메타 규칙·
    /// `scheme`/`inner` 모르는 값·`iterations` 범위 밖·BOM·`hint` 키·암호문 16B 미만
    case malformed
    /// M2 — `format` 일치 + `version` 정수 ≥ 2(나머지 구조는 보지 않는다)
    case newerVersion
    /// M3 — 4계층(봉투·base64 글자·디코드 암호문·복호화본) 어느 것이든 초과. 계층을 알리지 않는다
    case tooLarge
    /// M4 — GCM tag 검증 실패(틀린 비밀번호 · 암호문/메타/`iterations`/`salt`/`nonce` 변조)
    case wrongPasswordOrDamaged
    /// M5 — 복호는 성공했는데 안쪽이 엄격 UTF-8이 아니다
    case unreadableContent
    /// M6 — 입력 오류(파일 오류 아님): 비밀번호가 NFC UTF-8 256바이트 초과
    case passwordTooLong
    /// 빈 비밀번호 — KDF를 시도하지 않는다(열기 버튼 비활성의 코드 쪽 방어)
    case passwordEmpty
}

/// 봉투 `meta` — 복호화 **전에는 미인증 표시 사본**이다(12-2·12-8). 복호에 성공하면 같은 값이 AAD로 인증된 것이다.
public struct GSPackMeta: Equatable, Sendable {
    public let name: String
    /// 화면에는 「출처」로 보인다(R27). 키 이름 `rights`는 형식 식별자라 바꾸지 않는다
    public let rights: String

    public init(name: String, rights: String) {
        self.name = name
        self.rights = rights
    }
}
