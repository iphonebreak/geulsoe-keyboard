/// 채움글 단축어의 **단어 경계** (사장님 결정 2026-10-08, 1.3.0 — PDR `docs/design-reviews/snippet-shortcut-terms.md` 7절 ·
/// `external-snippet-packs.md` R48).
///
/// 맞은 구간 첫 글자의 **바로 앞 글자**가 문자도 숫자도 아닐 때만 맞은 것으로 친다 — 줄 처음·공백·개행·문장부호·기호(이모지 포함)는
/// 경계이고, 문자(한글 음절·자모·천지인 `ㆍ`·라틴…)나 숫자가 앞에 붙어 있으면 앞말의 일부라 맞지 않는다.
/// 실기에서 단축어 `주소`가 「서울주소」 끝에 떠서 탭하면 「서울서울주소」가 됐다(1.0부터의 끝 맞춤 동작).
///
/// 문구 needle(`SnippetMatcher`) · 번호형 틀(`PackTemplateMatcher`) · 날짜 팩(`DateSnippetParser`)이 이 함수 **하나**를 쓴다.
/// **성경 참조 파서는 쓰지 않는다**(제외 — 자기 규칙: 책 이름 앞은 꼬리 시작 또는 비한글).
///
/// ★ 「앞 글자」는 **공백을 건너뛰지 않은 원문**의 글자다. 단축어 안 띄어쓰기를 무시하는 훑기(비공백 역방향 풀이)의 인덱스로 보면
///   「서울 주소」가 「서울주소」로 오판된다 — 그래서 `start`는 원문 인덱스로 받는다.
/// ★ 이모지는 `isLetter`·`isNumber`가 모두 거짓이라 기호(경계)다. 키캡 숫자 `1️⃣`만 `isNumber`라 숫자로 본다.
enum SnippetWordBoundary {

    /// - Parameters:
    ///   - start: 맞은 구간 첫 글자의 **원문** 인덱스(`characters` 기준)
    ///   - characters: 꼬리 원문
    ///   - tailIsTruncated: 꼬리 앞이 잘렸는가(`InputController.textTailIsTruncated` — 48자 상한). 잘렸으면 꼬리 맨 앞 글자의
    ///     앞을 모르므로 경계로 치지 않는다. 잘리지 않았으면 꼬리 맨 앞은 줄 처음이다
    @inline(__always)
    static func allows(start: Int, in characters: [Character], tailIsTruncated: Bool) -> Bool {
        guard start > 0 else { return !tailIsTruncated }
        let previous = characters[start - 1]
        return !previous.isLetter && !previous.isNumber
    }
}
