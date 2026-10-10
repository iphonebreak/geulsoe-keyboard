import Foundation
import KeyboardCore
import TadakDomain

/// `#틀` 값 하나(`사자성어 {n}번`)를 템플릿 패턴으로 — 스키마(10-1, R3)·성경 충돌(10-2)·가림(10-3).
///
/// 정규화는 `SnippetEntry.normalizedTrigger` **한 함수**만 쓴다 — 설정의 중복 판정·키보드 발동과 같은 규칙(CLAUDE.md).
public enum TemplatePatternSpec {

    public enum Failure: Error, Equatable, Sendable {
        /// `{n}`이 정확히 1개가 아니다
        case placeholderCount
        /// 접두가 정규화 뒤 `minimumPrefixCharacters`(2자) 미만(접두 없음 포함 — Q6 「접두 없는 `323장`」 끔)
        case prefixTooShort
        /// 접두 끝이 ASCII 숫자 — `회차2{n}번`은 `회차23번`의 숫자열 전체를 23으로 읽어 접두를 못 찾는다(후퇴 금지와 충돌)
        case prefixEndsWithDigit
        /// 접두가 숫자뿐(숫자 단독 금지, R3)
        case prefixAllDigits
        /// 접미가 정규화 뒤 비었다
        case suffixEmpty
        /// literal 안에 개행
        case literalContainsNewline
        /// 접미가 `날짜`·`시간`·`시각`으로 끝난다 — 날짜·시간 팩 끝말(전체 일치가 아니라 endsWith, 10-1)
        case reservedDateSuffix
        /// 접두+접미 정규화 합이 `PackLimits.templateLiteral`(40자·160B·120 scalar)을 넘는다
        case literalTooLong
        /// 이 번호에서 현재 성경 파서가 구절로 읽는다(10-2) — 번호는 내용이 아니다
        case collidesWithBible(n: Int)
    }

    static let placeholder = "{n}"
    static let reservedDateSuffixes = ["날짜", "시간", "시각"]

    /// 접두(정규화 뒤) 최소 글자 수 — 틀 검사(`prefixTooShort`)와 폼 문구(「앞 글자는 2자 이상」)가 이 값 하나를 본다(검증 F-6)
    public static let minimumPrefixCharacters = 2
    /// 폼 문구 「틀+번호는 띄어쓰기 포함 48자 이내」의 숫자 — 키보드가 채움글 매칭에 보는 꼬리(`InputController.committedTail`) 길이다.
    /// 키보드 쪽 값은 private이라 **거울 값**이고, 시험이 `InputController`로 꼬리 길이를 재 대조한다. 실제로 막는 것은
    /// `PackLimits.templateLiteral`(40자)이고, 최대 확장(40 + 번호 4자리 + 띄어쓰기 2 = 46)이 이 안에 든다(10-1)
    public static let expandedTriggerCharacters = 48

    /// 스키마 검사만(10-1). 성경 충돌은 `firstBibleCollision` — 1~9,999 전체를 돌아 비싸서 따로 둔다
    public static func parse(_ raw: String) -> Result<TemplatePattern, Failure> {
        let parts = raw.components(separatedBy: placeholder)
        guard parts.count == 2 else { return .failure(.placeholderCount) }
        guard !raw.contains(where: \.isNewline) else { return .failure(.literalContainsNewline) }
        let prefix = SnippetEntry.normalizedTrigger(parts[0])
        let suffix = SnippetEntry.normalizedTrigger(parts[1])
        guard prefix.count >= minimumPrefixCharacters else { return .failure(.prefixTooShort) }
        if prefix.allSatisfy(isASCIIDigit) { return .failure(.prefixAllDigits) }
        if let last = prefix.last, isASCIIDigit(last) { return .failure(.prefixEndsWithDigit) }
        guard !suffix.isEmpty else { return .failure(.suffixEmpty) }
        if reservedDateSuffixes.contains(where: suffix.hasSuffix) { return .failure(.reservedDateSuffix) }
        guard PackLimits.templateLiteral.admits(prefix + suffix) else { return .failure(.literalTooLong) }
        return .success(TemplatePattern(prefix: prefix, suffix: suffix))
    }

    /// 10-2 — 허용 숫자 영역 **1~9,999 전체**(팩의 모든 `items.n`을 포함한다)를 현재 `BibleReferenceParser.matchSuffix`에
    /// 넣어 하나라도 구절로 읽히면 그 첫 번호. 공백 제거한 패턴과 성경의 정상 공백 표기 변형(작성 원문의 띄어쓰기,
    /// 번호 앞뒤 한 칸)을 함께 넣는다. 가져오기·교체·순서 변경에서만 부른다(키 입력 경로 아님).
    public static func firstBibleCollision(_ pattern: TemplatePattern, raw: String) -> Int? {
        let parts = raw.components(separatedBy: placeholder)
        let rawPrefix = parts.first ?? pattern.prefix
        let rawSuffix = parts.count == 2 ? parts[1] : pattern.suffix
        for n in PackLimits.numberRange {
            let number = String(n)
            let variants = [
                pattern.prefix + number + pattern.suffix,
                rawPrefix + number + rawSuffix,
                pattern.prefix + " " + number + " " + pattern.suffix
            ]
            if variants.contains(where: { BibleReferenceParser.matchSuffix(of: $0) != nil }) { return n }
        }
        return nil
    }

    /// 10-3 — 활성 정적 단축어 중 **이 템플릿이 만들 수 있는 입력의 접미사**인 것(예: `번`·`3번`·`어12번`).
    /// 분기 순서상 문구가 먼저 발동하므로 그 패턴은 가려진다 — 거부하지 않고 미리보기·팩 정보에 표시한다.
    /// 돌려주는 것은 넘겨받은 원문 단축어다.
    public static func shadowingTriggers(of pattern: TemplatePattern, among staticTriggers: [String]) -> [String] {
        staticTriggers.filter { shadows(SnippetEntry.normalizedTrigger($0), pattern) }
    }

    /// 가능한 입력 = 접두 + D + 접미, D는 1~4자리 선행 0 없는 숫자열
    private static func shadows(_ trigger: String, _ pattern: TemplatePattern) -> Bool {
        guard !trigger.isEmpty else { return false }
        if trigger.count <= pattern.suffix.count { return pattern.suffix.hasSuffix(trigger) }
        guard trigger.hasSuffix(pattern.suffix) else { return false }
        let rest = trigger.dropLast(pattern.suffix.count)                 // 접두 꼬리 + 숫자 꼬리
        let digits = rest.reversed().prefix(while: isASCIIDigit)
        guard !digits.isEmpty, digits.count <= 4 else { return false }
        let beforeDigits = rest.dropLast(digits.count)
        let digitString = String(digits.reversed())
        if beforeDigits.isEmpty {
            // 숫자 꼬리만 — 어떤 유효한 D의 접미사면 된다(4자리면 D 자체라 선행 0이면 안 된다)
            return digitString.count < 4 || digitString.first != "0"
        }
        // 접두 꼬리가 있으면 숫자열은 D 전체여야 한다
        return digitString.first != "0" && pattern.prefix.hasSuffix(beforeDigits)
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        character.asciiValue.map { (48...57).contains($0) } ?? false
    }
}
