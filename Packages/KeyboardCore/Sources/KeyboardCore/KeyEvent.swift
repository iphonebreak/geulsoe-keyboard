/// 키캡 하나가 발생시키는 이벤트.
///
/// UI는 이 이벤트만 만들고, 해석(자모 변환·시프트 상태·조합)은 전부
/// `InputController`가 한다. 키캡 뷰에 입력 로직을 넣지 않는다.
public enum KeyEvent: Equatable, Sendable {
    /// 문자 키. 한글 모드에서는 두벌식 키 id(예: "r"), 영어/기호 모드에서는 그 문자 자체.
    case character(String)
    case backspace
    case space
    case `return`
    case shift
    /// 한/영 전환
    case toggleLanguage
    /// 문자 ↔ 기호 자판 전환. 기호 자판(1·2페이지 모두)에서 누르면 **들어오기 전 문자 모드**로
    /// 돌아간다 (영어에서 들어갔으면 영어로 — 항상 한글로 되돌리던 버그 수정, 2026-09-02)
    case symbols
    /// 기호 1페이지(123) ↔ 2페이지(#+=) 전환
    case symbolsAlternate
    /// 천지인 이동(→) 키 — 공백 없이 조합만 확정한다.
    /// 같은 자음을 순환 없이 이어 칠 때 쓴다 (학 + → + ㄱ = "학ㄱ")
    case advance
    /// 빈 자리(스페이서) — 아무 동작 없음. 행 폭을 맞춰 글자 열을 가운데 정렬할 때 쓴다
    /// (단모음 3행). UI는 키 표면을 그리지 않는다.
    case spacer
}

/// 숫자 패드 종류 — 입력란 `keyboardType`에서 온다 (PDR field-traits-and-live-settings)
public enum NumberPadKind: Equatable, Sendable {
    /// 보조 키 없음 (`.numberPad`)
    case plain
    /// 소수점 `.` (`.decimalPad`)
    case decimal
    /// 국제전화 `+` (`.phonePad`)
    case phone
}

/// 현재 자판 모드
public enum InputMode: Equatable, Sendable {
    case hangul
    case english
    /// 기호 1페이지 — 숫자·기본 문장부호
    case symbols
    /// 기호 2페이지(#+=) — 괄호·특수문자
    case symbolsAlternate
    /// 숫자 패드 — 입력란이 숫자 전용일 때 (`keyboardType`). 문자가 바로 커밋된다
    case numberPad(NumberPadKind)

    /// 기호 자판인가 (두 페이지 공통 처리용)
    public var isSymbols: Bool {
        self == .symbols || self == .symbolsAlternate
    }

    public var isNumberPad: Bool {
        if case .numberPad = self { return true }
        return false
    }

    /// 문자 자판(한글·영어)인가 — 기호·숫자 패드에서 돌아갈 곳을 기억할 때 쓴다
    public var isLetter: Bool {
        self == .hangul || self == .english
    }
}

/// 시프트 상태. capsLock은 영어에서만 의미가 있다.
public enum ShiftState: Equatable, Sendable {
    case off
    /// 다음 입력 1개에만 적용 후 자동 해제
    case once
    case capsLock
}

/// 자동 대문자 규칙 — 입력란 `autocapitalizationType`과 설정 `autoCapitalization`을 조립 지점이
/// 합쳐 `InputController.autoCapitalization`에 넣는다 (PDR auto-capitalization). 영어 모드에서만
/// 의미가 있다 — 한글 자판의 시프트(쌍자음)는 건드리지 않는다.
public enum AutoCapitalization: Equatable, Sendable {
    /// 끔 — 설정이 꺼져 있거나 입력란이 거부한다 (이메일·URL·비밀번호 = `.none`)
    case none
    /// 단어마다 — 공백 뒤
    case words
    /// 문장 시작 — 문서·줄 시작, 마침표·물음표·느낌표 + 공백 뒤 (입력란 기본값)
    case sentences
    /// 전부 대문자
    case allCharacters
}

/// 스페이스 오른쪽 문장부호 키의 내용 — 입력란 `keyboardType`에 따라 조립 지점이 고른다
/// (PDR punctuation-key). `primary`는 탭, `secondary`는 길게 누르기.
public struct PunctuationKeySpec: Equatable, Sendable {
    public let primary: String
    public let secondary: String

    public init(primary: String, secondary: String) {
        self.primary = primary
        self.secondary = secondary
    }

    /// 기본 — `.` 탭 / `,` 길게
    public static let standard = PunctuationKeySpec(primary: ".", secondary: ",")
    /// 이메일 입력란 — `@` 탭 / `.` 길게
    public static let email = PunctuationKeySpec(primary: "@", secondary: ".")
    /// 주소창·URL 입력란 — `.` 탭 / `.com` 길게
    public static let url = PunctuationKeySpec(primary: ".", secondary: ".com")
    /// 트위터형(@·#) 입력란 — `@` 탭 / `#` 길게
    public static let twitter = PunctuationKeySpec(primary: "@", secondary: "#")
}
