import Foundation

/// ⌫ 길게 누르기 반복 박자의 종류 — 시간표는 KeyboardUI `BackspaceRepeatSchedule`, 처리는 `InputController.handleBackspaceRepeat`
/// (PDR `docs/design-reviews/backspace-word-acceleration.md` 1-1).
public enum BackspaceRepeatPhase: Sendable, Equatable {
    /// 0.5초부터 80ms — 현행 ⌫ 1회(문맥을 읽지 않는다)
    case character
    /// 2.30초 한 번 — **읽기 전용**: 문맥을 읽어 사슬만 둔다
    case anchor
    /// 2.6초부터 0.35초 — 두 단위 또는 폴백 4자
    case word
}

/// 반복 박자 하나를 처리한 결과 — VC가 피드백·화면 갱신 여부를 정한다
public enum BackspaceRepeatOutcome: Equatable, Sendable {
    /// 받지 않음(끝난 누름) 또는 하는 일 없음(닻을 놓지 못함)
    case ignored
    /// 닻 — 문맥을 읽어 사슬만 두었다(지우지 않음)
    case anchored
    /// 단어 단계 — 프록시 `deleteBackward()` n회
    case deletedWords(count: Int)
    /// 현행 ⌫(`handle(.backspace)`)를 n회 — 글자 박자·선택·조합·폴백
    case backspaces(count: Int)
}

/// 「두 어절」 계획 — 커서 앞 문맥에서 이번 단계에 지울 `Character` 수를 낸다(PDR 1-2).
///
/// 한 단위 = 끝에서부터 ① 공백 줄 ② (그 앞이 개행이면 그 개행 하나로 끝 — D1) ③ 문장부호 줄 ④ 단어 줄 ⑤ 앞 공백 하나.
/// 한 단계 = 두 단위. **보이는 문맥 안에서만 센다** — 맨 앞에 닿으면 보이는 만큼만(과소 삭제), 길이로 잘림을 추정하지 않는다.
/// 지울 길이는 `Character`(그래핌) 수다 — UTF-16·스칼라 수를 쓰지 않는다(3-6).
enum BackspaceWordPlan {

    /// 한 단위 단어 줄의 상한 — 넘으면 「긴 단위」(결정 기본: 20자 초과 붙임 토큰은 글자 단위)
    static let maximumWordLength = 20
    /// 한 단계 합계 상한 — 프록시 호출 수 상한(R2-BA-05)
    static let maximumStepLength = 48
    /// 한 단계의 단위 수(결정 2 — 두 어절)
    static let unitsPerStep = 2

    enum FallbackReason: Equatable, Sendable {
        case emptyContext
        case wordTooLong
        /// 스칼라가 둘 이상인 글자(개행 제외) — 프록시의 지움 단위를 실기로 확인하기 전까지(R5)
        case multiScalarCharacter
        case stepTooLong
    }

    enum Result: Equatable, Sendable {
        case delete(count: Int)
        case fallback(FallbackReason)
    }

    static func plan(context: String) -> Result {
        let characters = Array(context)
        guard !characters.isEmpty else { return .fallback(.emptyContext) }
        var end = characters.count
        var total = 0
        for index in 0..<unitsPerStep {
            guard end > 0 else { break }
            let unit = Unit(characters, end: end)
            let longReason = unit.longReason(totalSoFar: total)
            if let longReason {
                // 첫 단위가 길면 이 단계는 폴백, 둘째만 길면 첫 단위만 지운다(CW-08)
                return index == 0 ? .fallback(longReason) : .delete(count: total)
            }
            total += unit.length
            end -= unit.length
        }
        return .delete(count: total)
    }

    /// 끝(`end` 앞)에서 잡은 한 단위
    private struct Unit {
        let length: Int
        let wordLength: Int
        let hasMultiScalarCharacter: Bool

        init(_ characters: [Character], end: Int) {
            var start = end
            func kind(_ index: Int) -> Kind { Kind(characters, index, end: end) }
            while start > 0, kind(start - 1) == .space { start -= 1 }
            if start > 0, kind(start - 1) == .newline {
                // 개행 하나(와 그 뒤 공백)가 한 단위다 — D1
                start -= 1
                self.init(characters, start: start, end: end, wordLength: 0)
                return
            }
            while start > 0, kind(start - 1) == .other { start -= 1 }
            let wordEnd = start
            while start > 0, kind(start - 1) == .word { start -= 1 }
            let wordLength = wordEnd - start
            if start > 0, kind(start - 1) == .space { start -= 1 }
            self.init(characters, start: start, end: end, wordLength: wordLength)
        }

        private init(_ characters: [Character], start: Int, end: Int, wordLength: Int) {
            length = end - start
            self.wordLength = wordLength
            hasMultiScalarCharacter = characters[start..<end].contains { !$0.isNewline && $0.unicodeScalars.count > 1 }
        }

        func longReason(totalSoFar: Int) -> FallbackReason? {
            if wordLength > BackspaceWordPlan.maximumWordLength { return .wordTooLong }
            if hasMultiScalarCharacter { return .multiScalarCharacter }
            if totalSoFar + length > BackspaceWordPlan.maximumStepLength { return .stepTooLong }
            return nil
        }
    }

    /// 글자 분류(PDR 1-2 표)
    private enum Kind: Equatable {
        case newline, space, word, other

        init(_ characters: [Character], _ index: Int, end: Int) {
            let character = characters[index]
            if character.isNewline {
                self = .newline
            } else if character.isWhitespace {
                self = .space
            } else if character.isLetter || character.isNumber {
                self = .word
            } else if Kind.joins(characters, index, end: end) {
                self = .word
            } else {
                self = .other
            }
        }

        /// 단어 안에 붙는 글자 — 양옆이 글자인 아포스트로피, 양옆이 숫자인 `,`·`.`
        private static func joins(_ characters: [Character], _ index: Int, end: Int) -> Bool {
            guard index > 0, index + 1 < end else { return false }
            let before = characters[index - 1]
            let after = characters[index + 1]
            switch characters[index] {
            case "'", "’": return before.isLetter && after.isLetter
            case ",", ".": return before.isNumber && after.isNumber
            default: return false
            }
        }
    }
}

/// 이 누름에서 ⌫ 단어 단계를 써도 되나 — 터치다운 때 VC가 값을 모아 부른다(PDR 4절·반론2 C2W-04).
public enum BackspaceWordPhasePolicy {

    /// **출시용 정적 상수** — 끄면 모든 누름이 80ms 글자 반복만 한다(쉼·닻·단어 없음, 손 뗌 세대 검사는 그대로).
    /// 원격 플래그·설정·저장 키가 아니다. 실기 확인이 남은 채 출시해야 할 때 이 기능만 빼는 출구이고, 끈 채 출시하는 것은 사장님 판정이다
    public static let shipEnabled = true

    /// secure면 문맥을 읽지 않으므로 글자 반복만, VoiceOver·스위치 제어 사용 중에는 단어 단계를 끈다(D2)
    public static func allows(isSecureTextEntry: Bool, isVoiceOverRunning: Bool, isSwitchControlRunning: Bool,
                              shipEnabled: Bool = shipEnabled) -> Bool {
        shipEnabled && !isSecureTextEntry && !isVoiceOverRunning && !isSwitchControlRunning
    }
}
