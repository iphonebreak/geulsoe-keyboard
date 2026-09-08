/// 자모 스트림을 한글 음절로 조합하는 상태 기계.
///
/// **자판 3종이 이것을 완전히 공유한다.** 두벌식·천지인·단모음의 차이는 전부
/// `JamoSource`에서 흡수되고, 여기까지 오면 자판이 무엇이었는지 알 수 없다.
/// 자판을 추가한다고 이 타입에 분기를 넣기 시작하면 설계가 무너진다.
///
/// 값 타입인 이유: 상태를 통째로 복사·비교할 수 있어 테스트가 단순해지고,
/// 조합 상태를 스냅샷으로 보관했다 되돌리기도 쉽다.
public struct HangulAutomaton: Equatable, Sendable {

    private var choseong: Int?
    private var jungseong: Int?
    /// 0은 종성 없음
    private var jongseong: Int = 0

    public init() {}

    // MARK: - 조회

    /// 지금 조합 중인 글자. 조합이 없으면 빈 문자열.
    public var composingText: String {
        switch (choseong, jungseong) {
        case let (cho?, jung?):
            HangulSyllable.compose(choseong: cho, jungseong: jung, jongseong: jongseong)
                .map(String.init) ?? ""
        case let (cho?, nil):
            String(HangulSyllable.choseongTable[cho])
        case let (nil, jung?):
            String(HangulSyllable.jungseongTable[jung])
        case (nil, nil):
            ""
        }
    }

    public var isComposing: Bool {
        choseong != nil || jungseong != nil
    }

    // MARK: - 입력

    public mutating func input(_ jamo: Jamo) -> AutomatonOutput {
        switch jamo {
        case .consonant(let character): inputConsonant(character)
        case .vowel(let character): inputVowel(character)
        }
    }

    private mutating func inputConsonant(_ character: Character) -> AutomatonOutput {
        // 초성이 될 수 없는 자모(겹받침 문자 등)는 조합에 넣지 않고 그대로 흘려보낸다.
        guard let newChoseong = HangulSyllable.choseongIndex(of: character) else {
            return flushAndCommit(String(character))
        }

        switch (choseong, jungseong) {
        case (nil, nil):
            choseong = newChoseong
            return .composing(composingText)

        case (_?, nil), (nil, _?):
            // 단독 자음/모음이 떠 있는 상태 — 그것을 확정하고 새 초성을 시작한다
            let settled = composingText
            clear()
            choseong = newChoseong
            return AutomatonOutput(committed: settled, composing: composingText)

        case (_?, _?):
            return placeAsJongseong(character, fallbackChoseong: newChoseong)
        }
    }

    /// 초성+중성이 있는 상태에서 자음이 들어왔을 때 — 종성으로 붙일지, 다음 글자로 넘길지.
    private mutating func placeAsJongseong(
        _ character: Character,
        fallbackChoseong: Int
    ) -> AutomatonOutput {
        guard let newJongseong = HangulSyllable.jongseongIndex(of: character) else {
            // ㄸ·ㅃ·ㅉ은 받침이 될 수 없다 — 현재 글자를 끝내고 다음 글자의 초성으로
            return commitAndStart(choseong: fallbackChoseong)
        }

        if jongseong == 0 {
            jongseong = newJongseong
            return .composing(composingText)
        }

        // 이미 받침이 있다 — 겹받침이 되면 합치고, 안 되면 다음 글자로 넘긴다
        if let combined = HangulSyllable.combineJongseong(jongseong, newJongseong) {
            jongseong = combined
            return .composing(composingText)
        }
        return commitAndStart(choseong: fallbackChoseong)
    }

    private mutating func inputVowel(_ character: Character) -> AutomatonOutput {
        guard let newJungseong = HangulSyllable.jungseongIndex(of: character) else {
            return flushAndCommit(String(character))
        }

        // 받침이 있는데 모음이 오면 받침이 다음 글자의 초성으로 넘어간다 (도깨비불)
        if jongseong != 0 {
            return moveJongseongToNextSyllable(newJungseong: newJungseong)
        }

        switch (choseong, jungseong) {
        case (nil, nil):
            jungseong = newJungseong
            return .composing(composingText)

        case (_?, nil):
            jungseong = newJungseong
            return .composing(composingText)

        case (_, let current?):
            // 복모음이 되면 합치고, 안 되면 지금 글자를 끝낸다
            if let combined = HangulSyllable.combineJungseong(current, newJungseong) {
                jungseong = combined
                return .composing(composingText)
            }
            let settled = composingText
            clear()
            jungseong = newJungseong
            return AutomatonOutput(committed: settled, composing: composingText)
        }
    }

    /// 도깨비불 — `간` + `ㅏ` → `가` + `나`.
    ///
    /// 겹받침이면 뒤쪽 하나만 넘어간다: `갃` + `ㅏ` → `각` + `사`.
    private mutating func moveJongseongToNextSyllable(newJungseong: Int) -> AutomatonOutput {
        let movingJamo: Character
        if let parts = HangulSyllable.splitJongseong(jongseong) {
            jongseong = parts.first
            movingJamo = HangulSyllable.jongseongTable[parts.second] ?? " "
        } else {
            movingJamo = HangulSyllable.jongseongTable[jongseong] ?? " "
            jongseong = 0
        }

        let settled = composingText
        clear()
        choseong = HangulSyllable.choseongIndex(of: movingJamo)
        jungseong = newJungseong
        return AutomatonOutput(committed: settled, composing: composingText)
    }

    // MARK: - 교체

    /// 마지막으로 들어온 자모를 다른 자모로 교체한다 (`JamoEvent.replaceLast`의 구현).
    ///
    /// `backspace()` + `input()`으로는 안 되는 이유: backspace는 복모음을 **분해**한다
    /// (ㅚ → ㅗ). 천지인 `ㅚ + ㆍ → ㅘ` 전이에서 분해 후 ㅘ를 넣으면 ㅗ와 결합하지 못해
    /// 조합이 깨진다. 여기는 자판을 모른다 — 표준 결합 표만 참조하는 공용 연산이다.
    ///
    /// - 모음: **중성 전체 교체.** 천지인 소스가 완성된 모음을 통째로 보낸다는 계약
    ///   (ㅚ→ㅘ, ㅠ→ㅝ). 종성이 있으면 마지막 자모가 모음이 아니므로 입력 폴백.
    /// - 자음: 종성이 있으면 마지막 종성 성분 교체 (겹받침은 뒤 성분만: 닭+ㅋ → 달+ㅋ),
    ///   초성만 있으면 초성 교체 (순환: ㄱ → ㅋ).
    public mutating func replaceLast(_ jamo: Jamo) -> AutomatonOutput {
        switch jamo {
        case .vowel(let character):
            guard jungseong != nil, jongseong == 0,
                  let newJungseong = HangulSyllable.jungseongIndex(of: character)
            else { return input(jamo) }
            jungseong = newJungseong
            return .composing(composingText)

        case .consonant(let character):
            if jongseong != 0 {
                return replaceLastJongseong(with: character)
            }
            if choseong != nil, jungseong == nil,
               let newChoseong = HangulSyllable.choseongIndex(of: character) {
                choseong = newChoseong
                return .composing(composingText)
            }
            return input(jamo)
        }
    }

    private mutating func replaceLastJongseong(with character: Character) -> AutomatonOutput {
        let newIndex = HangulSyllable.jongseongIndex(of: character)

        if let parts = HangulSyllable.splitJongseong(jongseong) {
            // 겹받침 — 뒤 성분만 교체. 결합이 안 되면 앞 성분을 남기고 다음 글자로
            if let newIndex, let combined = HangulSyllable.combineJongseong(parts.first, newIndex) {
                jongseong = combined
                return .composing(composingText)
            }
            jongseong = parts.first
        } else if let newIndex {
            // 홑받침 — 통째 교체 (각+ㅋ → 갘, 앙+ㅁ → 암)
            jongseong = newIndex
            return .composing(composingText)
        } else {
            // 새 자음이 받침 불가(ㄸ·ㅃ·ㅉ) — 기존 받침을 빼고 다음 글자 초성으로
            jongseong = 0
        }

        guard let newChoseong = HangulSyllable.choseongIndex(of: character) else {
            return flushAndCommit(String(character))
        }
        return commitAndStart(choseong: newChoseong)
    }

    // MARK: - 삭제 / 확정

    /// 조합 중이면 자모 하나를 되돌리고, 조합이 없으면 문서에서 한 글자를 지우라고 알린다.
    public mutating func backspace() -> AutomatonOutput {
        if jongseong != 0 {
            jongseong = HangulSyllable.splitJongseong(jongseong)?.first ?? 0
            return .composing(composingText)
        }
        if let current = jungseong {
            jungseong = HangulSyllable.splitJungseong(current)?.first
            return .composing(composingText)
        }
        if choseong != nil {
            choseong = nil
            return .composing(composingText)
        }
        return AutomatonOutput(committed: "", composing: "", deletesBackward: true)
    }

    /// 조합을 강제로 끝낸다.
    ///
    /// **커서 이동·자판 전환·앱 전환 직전에 반드시 호출한다.** 조합 상태를 들고
    /// 커서만 옮기면 다음 입력이 엉뚱한 위치에 붙는다.
    public mutating func commit() -> AutomatonOutput {
        guard isComposing else { return .empty }
        let settled = composingText
        clear()
        return AutomatonOutput(committed: settled, composing: "")
    }

    /// 조합 상태를 버린다. 확정하지 않으므로 문서에 아무것도 남기지 않는다.
    public mutating func reset() {
        clear()
    }

    // MARK: - 내부

    private mutating func clear() {
        choseong = nil
        jungseong = nil
        jongseong = 0
    }

    /// 조합에 넣을 수 없는 문자가 왔을 때 — 조합을 끝내고 그 문자를 뒤에 붙인다.
    private mutating func flushAndCommit(_ text: String) -> AutomatonOutput {
        let settled = composingText
        clear()
        return AutomatonOutput(committed: settled + text, composing: "")
    }

    private mutating func commitAndStart(choseong newChoseong: Int) -> AutomatonOutput {
        let settled = composingText
        clear()
        choseong = newChoseong
        return AutomatonOutput(committed: settled, composing: composingText)
    }
}

/// 입력 한 번의 결과.
///
/// 호출자는 이전 `composing`을 문서에서 지운 뒤 `committed + composing`을 넣는다.
/// `UITextDocumentProxy`에 marked text API가 없어서 이 방식으로 조합을 표현한다.
public struct AutomatonOutput: Equatable, Sendable {

    /// 문서에 확정 입력할 문자열
    public var committed: String
    /// 아직 조합 중인 글자 (없으면 빈 문자열)
    public var composing: String
    /// 문서에서 한 글자를 지워야 하는가 (조합이 없을 때의 백스페이스)
    public var deletesBackward: Bool

    public init(committed: String, composing: String, deletesBackward: Bool = false) {
        self.committed = committed
        self.composing = composing
        self.deletesBackward = deletesBackward
    }

    static func composing(_ text: String) -> AutomatonOutput {
        AutomatonOutput(committed: "", composing: text)
    }

    static let empty = AutomatonOutput(committed: "", composing: "")
}
