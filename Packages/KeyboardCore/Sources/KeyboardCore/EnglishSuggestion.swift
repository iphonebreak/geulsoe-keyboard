import Foundation
import TadakDomain

// B5 영어 추천단어 — run 규칙·조회 키·게이트·✕ 비교(PDR `english-word-suggestions.md`, 계획 §3-8 C3·C4·C13·E1·E2·E5·E10).
// 조립 지점(익스텐션 타깃)은 `swift test`가 닿지 않아 판정식을 여기 둔다.

/// 꼬리 끝의 영어 단어 run(E1 표).
///
/// - 영문자(ASCII)와 아포스트로피(`'`·`’`)가 이어진 꼬리 끝. 맨 앞 아포스트로피는 뗀다(`'tis` → `tis`).
/// - 앞 글자가 숫자·`@ . / : _ # \`이면 토큰의 일부라 없음(`a@exa`·`v1.2abc`). 하이픈·공백·괄호 뒤는 새 단어.
/// - **C3** — 앞 글자가 ASCII가 아닌 라틴 글자(`ï`·`é`·결합 부호)면 토큰 전체를 거절한다(`naïve`의 `ve`에 후보를 내지 않는다).
///   한글 뒤 라틴은 후보를 낸다(`아이폰iPh`).
/// - **E2** — run이 꼬리 전체이고 꼬리 앞이 잘렸으면(앞 글자를 모름) 없음.
/// 원본 run(대소문자·굽은 아포스트로피)을 그대로 돌려준다 — 지울 길이·탭 정합 검사가 원본 기준이다.
public enum LatinWordRun {

    public static func run(inTail tail: String, isTruncated: Bool) -> String? {
        var start = tail.endIndex
        while start > tail.startIndex, isRunCharacter(tail[tail.index(before: start)]) {
            start = tail.index(before: start)
        }
        guard start < tail.endIndex else { return nil }
        if start > tail.startIndex {
            let before = tail[tail.index(before: start)]
            if before.isNumber || tokenJoiners.contains(before) { return nil }
            if before.isLetter, !before.isASCII, !isHangul(before) { return nil }   // C3
        } else if isTruncated {
            return nil   // E2
        }
        var run = tail[start...]
        while let first = run.first, isApostrophe(first) { run = run.dropFirst() }
        guard run.contains(where: \.isLetter) else { return nil }
        return String(run)
    }

    /// 조회 키 — 소문자 + `’`(U+2019) → `'`. 사전 키·✕ 비교·자기 자신 제외가 모두 이 키를 쓴다
    public static func lookupKey(_ run: String) -> String {
        run.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }

    static func isRunCharacter(_ character: Character) -> Bool {
        (character.isASCII && character.isLetter) || isApostrophe(character)
    }

    static func isApostrophe(_ character: Character) -> Bool {
        character == "'" || character == "\u{2019}"
    }

    private static let tokenJoiners: Set<Character> = ["@", ".", "/", ":", "_", "#", "\\"]

    private static func isHangul(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0xAC00...0xD7A3).contains(scalar.value) || (0x3131...0x318E).contains(scalar.value)
    }
}

/// 입력란 특성 중 영어 후보 게이트가 보는 것 — 조립 지점이 UIKit traits에서 채운다(KeyboardCore는 UIKit을 모른다)
public struct EnglishFieldTraits: Equatable, Sendable {
    /// 이메일·URL 입력란(`.emailAddress`·`.URL`)
    public var isEmailOrURL: Bool
    /// `.asciiCapable`·`.asciiCapableNumberPad`
    public var isASCIICapable: Bool
    public var isSecure: Bool
    /// `autocorrectionType == .no`
    public var autocorrectionDisabled: Bool

    public init(isEmailOrURL: Bool, isASCIICapable: Bool, isSecure: Bool, autocorrectionDisabled: Bool) {
        self.isEmailOrURL = isEmailOrURL
        self.isASCIICapable = isASCIICapable
        self.isSecure = isSecure
        self.autocorrectionDisabled = autocorrectionDisabled
    }

    public static let `default` = EnglishFieldTraits(isEmailOrURL: false, isASCIICapable: false, isSecure: false,
                                                     autocorrectionDisabled: false)
}

/// 영어 후보를 띄워도 되는가(E5). 툴바 우선순위(채움글 칩·붙여넣기 칩·선택 영역·✕·커서 이동)는 `WordSuggestionGate`가 따로 본다.
///
/// **C13 — 입력란 끔은 제품 선택이다(N13).** `.asciiCapable`은 「ASCII 입력」이지 아이디·코드란이라는 뜻이 아니고,
/// `autocorrectionType == .no`는 자동 교정을 끄라는 뜻이지 수동 완성 후보가 불필요하다는 플랫폼 계약이 아니다.
/// 보수적으로 끄는 정책이며 기회 비용(영문 이름 칸·일반 영어 검색 칸)이 있다. **C14 — `textContentType`은 1.3.1에서 읽지
/// 않는다**(학습이 없어 소음뿐). 영어 학습(1.3.2 후보)을 넣기 전에는 username·password·oneTimeCode 차단이 필수다.
public enum EnglishSuggestionGate {
    /// - Parameters:
    ///   - isEnglishContext: `InputController.isEnglishSuggestionContext`(C4)
    ///   - settingEnabled: `KeyboardSettings.allowsEnglishSuggestions(isSecureTextEntry:)`
    public static func allows(isEnglishContext: Bool, field: EnglishFieldTraits, settingEnabled: Bool) -> Bool {
        isEnglishContext && settingEnabled && !field.isEmailOrURL && !field.isASCIICapable && !field.isSecure
            && !field.autocorrectionDisabled
    }
}

/// ✕로 내린 영어 후보 억제(E10) — **정규화 키**로 비교한다. `Hel`을 ✕한 뒤 `hell`·`don’`→`don't`로 이어 쳐도 유지되고,
/// 접두를 벗어나거나 run이 사라지면 풀린다. 모드 전환 때는 조립 지점이 비운다(C4)
public enum EnglishDismissal {
    public static func isStillDismissed(dismissedKey: String, currentRun: String?) -> Bool {
        guard let currentRun else { return false }
        return LatinWordRun.lookupKey(currentRun).hasPrefix(dismissedKey)
    }
}
