/// 잠금 파일(`.gspack`) 받기 문구 — **한 곳**(PDR `external-snippet-packs.md` 12-7 실패 표·12-10 ④ 비밀번호 화면·12-8 한계 고지).
/// 두 판(CSV 전용판·xlsx 중심판)이 같다. 규칙은 `PackImportCopy`와 같다: 해요체 · 「단축어」 · 교회·성경 소재 0(U6) ·
/// **오류 문구에 파일 이름·봉투 값·메타를 넣지 않는다**(AC-34) · 「힌트」 없음(A4) · 「안전해요」·「보호돼요」 단정 없음.
/// 12-12 승인 전 후보 문안이다(사장님 Q6).
public enum PackLockedCopy {

    // MARK: 비밀번호 화면 (12-10 ④)

    public static let title = "잠긴 팩"
    public static let lead = "비밀번호로 잠긴 팩이에요. 비밀번호를 넣으면 풀어서 미리 보여 드려요."
    public static let metaHeader = "파일에 적힌 정보 (확인 전)"
    public static let nameLabel = "이름"
    public static let sourceLabel = "출처"
    public static let emptyValue = "없음"
    public static let metaFooter = "이 정보는 잠기지 않은 채 파일에 적혀 있어요. 비밀번호로 연 뒤에야 바뀌지 않았는지 확인돼요."
    public static let passwordLabel = "비밀번호"
    public static let open = "열기"
    public static let opening = "푸는 중…"
    /// 상시 도움말(12-7)
    public static let help = "비밀번호를 잊으면 열 수 없어요. 앞뒤 공백도 비밀번호에 포함돼요."

    // MARK: 미리보기 알림 줄 (12-8)

    /// 가져온 팩은 잠금이 풀린 채 저장된다(한계 고지)
    public static let storedUnlocked = "이 팩은 잠금이 풀린 채 이 기기에 저장돼요."
    /// 봉투 표시 메타와 안쪽 `#이름`·`#출처`가 다르다 — 안쪽 값을 쓴다
    public static let metaDiffers = "잠금 파일에 적힌 이름·출처가 안쪽 내용과 달라요. 안쪽 내용을 써요."

    // MARK: 실패 (12-7 M1~M6)

    /// M4·M6은 비밀번호 화면 안 한 줄, M1·M2·M3·M5는 거부 화면 문구
    public static func failure(_ failure: GSPackFailure) -> String {
        switch failure {
        case .malformed: "글쇠 잠금 파일이 아니거나 손상된 파일이에요."
        case .newerVersion: "더 새로운 글쇠에서 만든 파일이에요. 글쇠를 업데이트한 뒤 다시 열어 주세요."
        case .tooLarge: "파일이 너무 커요. 팩은 3MB까지 받을 수 있어요."
        case .wrongPasswordOrDamaged: "비밀번호가 맞지 않거나 파일이 손상됐어요."
        case .unreadableContent: "풀었지만 내용을 읽을 수 없어요. 파일을 만든 분께 UTF-8 CSV로 다시 만들어 달라고 해 주세요."
        case .passwordTooLong: "비밀번호는 256바이트(한글 약 85자)까지예요."
        case .passwordEmpty: "비밀번호를 넣어 주세요."
        }
    }

    /// 화면에 보이는 문구 전부 — 문구 검사(`PackCopyLintTests`)가 읽는다
    static var all: [String] {
        [title, lead, metaHeader, nameLabel, sourceLabel, emptyValue, metaFooter, passwordLabel, open, opening, help, storedUnlocked, metaDiffers]
            + [GSPackFailure.malformed, .newerVersion, .tooLarge, .wrongPasswordOrDamaged, .unreadableContent, .passwordTooLong, .passwordEmpty]
                .map(failure)
    }
}
