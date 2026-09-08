import Foundation

/// 천지인 자판.
///
/// 모음은 `ㅣ ㆍ ㅡ` 세 키의 조합으로 만들고, 자음은 같은 키 연타로 순환한다
/// (ㄱ → ㅋ → ㄲ). 동작 스펙과 실측 근거는
/// `docs/design-reviews/cheonjiin-danmoeum-layouts.md` 참조.
///
/// 상태 규칙:
/// - **자음 순환은 타임아웃이 있다.** `timeout` 안에 같은 자음 키가 다시 오면 순환,
///   지나면 별개 자모다. 사이에 다른 키가 오면 순환이 끊긴다.
/// - **모음 조합은 타임아웃이 없다** (실측 — 몇 초가 지나도 결합한다).
/// - 아직 모음이 되지 못한 `ㆍ`(1개)/`ᆢ`(2개)는 `pendingText`로 노출한다.
///   자음이 오면 리터럴로 확정하고(보이던 글자를 지우지 않는다), 세 번째 ㆍ는
///   단일 점으로 순환한다.
/// - 백스페이스는 키 입력 단위 취소다 — 호출자가 키 로그를 재생한다
///   (`prefersKeystrokeReplayBackspace`).
public final class CheonjiinSource: JamoSource {

    public let identifier = "cheonjiin"

    /// 자음 순환을 인정하는 같은 키 재입력 간격(초)
    private let timeout: TimeInterval

    // MARK: 상태

    /// 오토마타에 이미 내보낸, 지금 조합 중인 모음 (전이 표의 기준점)
    private var currentVowel: Character?
    /// 아직 모음이 되지 못한 ㆍ 개수 (0·1·2)
    private var dots = 0
    /// 순환 중인 자음 키와 위치
    private var cycleKey: String?
    private var cycleIndex = 0
    private var lastConsonantTime: TimeInterval = -.infinity

    public init(timeout: TimeInterval = 0.8) {
        self.timeout = timeout
    }

    public var pendingText: String {
        switch dots {
        case 1: "ㆍ"
        case 2: "ㆍㆍ"
        default: ""
        }
    }
    // 이중 점을 Apple처럼 ᆢ(U+11A2)로 쓰지 않는 이유: U+11A2는 **결합형 중성**이라
    // 직전 완성 음절과 한 그래핌으로 병합된다 ("가"+"ᆢ" = 1글자). 조합 교체가
    // 글자 수로 지우는 우리 방식에서는 확정된 글자까지 함께 지워진다.
    // ㆍ(U+318D)는 호환 자모라 병합되지 않는다.

    public var prefersKeystrokeReplayBackspace: Bool { true }
    /// 조합 중 스페이스 = 이동 (배열에서 → 키를 뺀 대신, Apple 10키와 같다 — 2026-09-07)
    public var spaceAdvancesWhileComposing: Bool { true }

    public func accept(key: String, at timestamp: TimeInterval) -> [JamoEvent] {
        switch key {
        case "ㆍ":
            return acceptDot()
        case "ㅣ", "ㅡ":
            return acceptVowelKey(key)
        default:
            guard let cycle = Self.consonantCycles[key] else { return [] }
            return acceptConsonant(key: key, cycle: cycle, at: timestamp)
        }
    }

    public func reset() {
        currentVowel = nil
        dots = 0
        cycleKey = nil
        cycleIndex = 0
        lastConsonantTime = -.infinity
    }

    // MARK: - 모음

    private func acceptDot() -> [JamoEvent] {
        cycleKey = nil

        if dots > 0 {
            // 실측: ㆍ → ᆢ → ㆍ 2상태 순환
            dots = (dots == 1) ? 2 : 1
            return [.pendingChanged]
        }
        if let vowel = currentVowel, let next = Self.vowelTransitions[vowel]?["ㆍ"] {
            currentVowel = next
            return [.replaceLast(.vowel(next))]
        }
        dots = 1
        return [.pendingChanged]
    }

    private func acceptVowelKey(_ key: String) -> [JamoEvent] {
        cycleKey = nil

        if dots > 0 {
            let resolved: Character = (dots == 1)
                ? (key == "ㅣ" ? "ㅓ" : "ㅗ")
                : (key == "ㅣ" ? "ㅕ" : "ㅛ")
            dots = 0
            currentVowel = resolved
            return [.emit(.vowel(resolved))]
        }
        if let vowel = currentVowel, let next = Self.vowelTransitions[vowel]?[key] {
            currentVowel = next
            return [.replaceLast(.vowel(next))]
        }
        let vowel = Character(key)
        currentVowel = vowel
        return [.emit(.vowel(vowel))]
    }

    // MARK: - 자음

    private func acceptConsonant(key: String, cycle: [Character],
                                 at timestamp: TimeInterval) -> [JamoEvent] {
        var events: [JamoEvent] = []

        // 보류 중인 점은 리터럴로 확정한다 — 화면에 보이던 글자를 지우지 않는다.
        // ㆍ는 중성이 될 수 없어 오토마타가 조합을 끝내고 그대로 흘려보낸다.
        for _ in 0..<dots {
            events.append(.emit(.vowel("ㆍ")))
        }
        dots = 0
        currentVowel = nil // 자음이 오면 모음 빌드가 끝난다

        if cycleKey == key, timestamp - lastConsonantTime <= timeout {
            cycleIndex = (cycleIndex + 1) % cycle.count
            lastConsonantTime = timestamp
            events.append(.replaceLast(.consonant(cycle[cycleIndex])))
            return events
        }
        cycleKey = key
        cycleIndex = 0
        lastConsonantTime = timestamp
        events.append(.emit(.consonant(cycle[0])))
        return events
    }

    // MARK: - 표

    /// 자음 키 → 연타 순환 순서. 키 id는 순환의 첫 자모다.
    private static let consonantCycles: [String: [Character]] = [
        "ㄱ": ["ㄱ", "ㅋ", "ㄲ"],
        "ㄴ": ["ㄴ", "ㄹ"],
        "ㄷ": ["ㄷ", "ㅌ", "ㄸ"],
        "ㅂ": ["ㅂ", "ㅍ", "ㅃ"],
        "ㅅ": ["ㅅ", "ㅎ", "ㅆ"],
        "ㅈ": ["ㅈ", "ㅊ", "ㅉ"],
        "ㅇ": ["ㅇ", "ㅁ"]
    ]

    /// 조합 중 모음 + 키 → 다음 모음. 표에 없으면 새 모음/새 점으로 시작한다.
    /// ㅚ+ㆍ=ㅘ, ㅠ+ㅣ=ㅝ 같은 비직관 전이는 iOS 내장 천지인 실측과 일치한다.
    private static let vowelTransitions: [Character: [String: Character]] = [
        "ㅣ": ["ㆍ": "ㅏ"],
        "ㅏ": ["ㆍ": "ㅑ", "ㅣ": "ㅐ"],
        "ㅑ": ["ㅣ": "ㅒ"],
        "ㅓ": ["ㅣ": "ㅔ"],
        "ㅕ": ["ㅣ": "ㅖ"],
        "ㅗ": ["ㅣ": "ㅚ"],
        "ㅚ": ["ㆍ": "ㅘ"],
        "ㅘ": ["ㅣ": "ㅙ"],
        "ㅡ": ["ㆍ": "ㅜ", "ㅣ": "ㅢ"],
        "ㅜ": ["ㆍ": "ㅠ", "ㅣ": "ㅟ"],
        "ㅠ": ["ㅣ": "ㅝ"],
        "ㅝ": ["ㅣ": "ㅞ"]
    ]
}
