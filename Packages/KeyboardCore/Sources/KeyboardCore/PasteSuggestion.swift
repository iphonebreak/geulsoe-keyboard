/// 툴바 **붙여넣기 칩**에 실을 값 — 복사한 내용을 한 줄로 보여 주고, 탭하면 넣는다.
///
/// ## 왜 있나 (2026-09-15)
///
/// v1.0.0 부터 툴바 칩이 될 수 있는 것은 **인증번호뿐**이었다. 클립보드 원문이 칩으로 가는 경로가
/// `VerificationCodeDetector.extractCode` 하나뿐이라, 평문을 복사하면 아무 일도 일어나지 않았다.
/// 사용자가 2026-09-11 에 "일반 텍스트도 칩이 나와야 한다"고 요구했고 설계
/// (`docs/design-reviews/paste-chip-plan.md` C절)까지 끝냈는데 두 번 미뤄져 구현된 적이 없다.
/// 2026-09-15 에 사용자가 다시 보고하며 형식까지 정했다:
///
/// > "네이버키보드와 동일하게 1줄로 보여준다 '복사했어요 맘에 드십니...' 이런식으로 보여주고
/// >  누르면 붙여넣기가 됨 / 비밀번호 관련 없이 모두 보여준다 복사했으면"
///
/// ## 두 종류가 한 칩 자리를 나눠 쓴다
///
/// **인증번호가 뽑히면 그쪽이 이긴다** — 번호만 보여 주고 번호만 넣는다. 일반 칩은
/// `extractCode == nil` 일 때만 만들어지므로 **두 칩이 동시에 뜨는 일은 없다**(설계 C-4).
///
/// ## 보안 (`.claude/rules/security.md`)
///
/// 여기서 만드는 문자열은 **화면 표시용 메모리 값**이다. 로그·파일·네트워크 어디로도 나가지
/// 않는다. 이 타입은 저장소를 건드리지 않고, 클립보드 읽기 지점을 새로 만들지도 않는다
/// (읽기는 여전히 키보드 등장 시 1회 — 주기 폴링 금지).
///
/// **비밀번호처럼 보인다고 거르지 않는다.** 사용자 명시 결정이다 — 복사한 것은 사용자가
/// 복사한 것이고 클립보드는 원래 붙여넣으라고 있는 것이다. 붙여넣을 **입력란**이
/// `isSecureTextEntry` 인 경우는 성격이 다른 별개 규칙이고, 호출자(조립 지점)가 막는다.
public struct PasteSuggestion: Equatable, Sendable {

    public enum Kind: Equatable, Sendable {
        /// 문자로 온 인증번호에서 **번호만** 뽑은 것
        case verificationCode
        /// 복사한 일반 텍스트
        case text
    }

    public let kind: Kind
    /// 칩에 보일 한 줄. 잘렸으면 끝에 말줄임표가 붙는다.
    public let preview: String
    /// 탭했을 때 실제로 넣을 문자열. **미리보기가 아니라 원문 전체**다
    /// (인증번호일 때는 뽑아낸 번호).
    public let insertText: String

    /// 미리보기 상한 — **40자**.
    ///
    /// 화면에서 실제로 자르는 것은 SwiftUI 다(`lineLimit(1)` + `.truncationMode(.tail)`).
    /// 칩 폭이 기기·글자 크기마다 다르므로 **고정 글자 수로 자르면 기기에 따라 어색해진다** —
    /// 좁은 기기에서는 어차피 더 잘리고, 넓은 기기에서는 남는 자리를 못 쓴다.
    /// 그래서 이 상한은 "화면에 맞추는 값"이 아니라 **우리가 만드는 문자열의 크기를 묶는 값**이다.
    ///
    /// 40 인 이유: 14pt 한글 기준 아이폰에서 칩에 들어가는 글자는 가장 넓은 기기에서도 30자 남짓이고
    /// (SE 계열은 15자 안팎), 접근성 큰 글자에서는 더 줄어든다. 40 이면 **아이폰에서는 항상
    /// SwiftUI 쪽 말줄임이 먼저 걸리므로** 기기별로 보이는 양이 자연스럽게 달라진다.
    /// 아이패드처럼 넓은 화면에서는 40자를 다 보여 주고 그 뒤를 말줄임표로 알린다.
    /// 상한 자체가 필요한 이유는, 사용자가 수십 KB 문단을 복사했을 때 그 전부를 뷰로 넘기지
    /// 않기 위해서다 (익스텐션 메모리 예산 60MB).
    public static let previewLimit = 40

    /// 클립보드 원문에서 칩을 만든다. 비었거나 공백뿐이거나 두 스위치가 다 꺼져 있으면 `nil`.
    ///
    /// **설정 두 개를 여기서 함께 본다** — 조립 지점에 흩어 두면 "인증번호는 끄고 일반만 켠"
    /// 조합에서 무엇이 떠야 하는지가 코드 두 곳에 나뉜다. 여기 한 곳에서 정하고 테스트로 고정한다.
    ///
    /// - Parameters:
    ///   - allowsCode: 인증번호 제안 스위치 (`verificationCodeSuggestionsEnabled`)
    ///   - allowsText: 일반 붙여넣기 제안 스위치 (`pasteSuggestionEnabled`)
    public static func make(
        from clipboard: String,
        allowsCode: Bool = true,
        allowsText: Bool = true
    ) -> PasteSuggestion? {
        if allowsCode, let code = VerificationCodeDetector.extractCode(from: clipboard) {
            return PasteSuggestion(kind: .verificationCode, preview: code, insertText: code)
        }
        guard allowsText else { return nil }
        let line = previewLine(from: clipboard)
        guard !line.isEmpty else { return nil }
        return PasteSuggestion(kind: .text, preview: line, insertText: clipboard)
    }

    /// 원문을 **한 줄로 접고** 상한까지 자른다.
    ///
    /// 줄바꿈·탭·연속 공백을 공백 하나로 접는다 — 칩은 한 줄이라 줄바꿈이 그대로 오면
    /// 뒷부분이 통째로 안 보이거나 레이아웃이 튄다.
    /// **접은 뒤의 길이로 센다** — 줄바꿈이 잔뜩 든 짧은 글이 공백 때문에 잘리면 안 된다.
    /// 길이는 **글자(grapheme cluster) 단위**다. 이모지가 중간에서 쪼개지지 않는다.
    public static func previewLine(from text: String) -> String {
        let folded = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard folded.count > previewLimit else { return folded }
        return String(folded.prefix(previewLimit)) + "…"
    }
}
