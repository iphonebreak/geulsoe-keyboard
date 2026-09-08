import Foundation

/// 두벌식 자판.
///
/// 키 하나가 자모 하나로 바로 매핑되므로 **상태가 없다.** `reset()`이 할 일도 없다.
/// 천지인·단모음처럼 이전 입력에 따라 결과가 달라지는 자판과 대비된다.
///
/// 키 식별자는 QWERTY 문자를 그대로 쓴다. 시프트가 눌린 키는 대문자로 전달한다
/// (`R` → `ㄲ`, `O` → `ㅒ`).
public final class DubeolsikSource: JamoSource {

    public let identifier = "dubeolsik"

    public init() {}

    /// 매핑에 없는 키(숫자·기호·공백)는 **빈 배열**을 낸다.
    /// 호출자는 이를 "자모가 아님"으로 보고 오토마타를 거치지 않고 그대로 입력한다.
    public func accept(key: String, at timestamp: TimeInterval) -> [JamoEvent] {
        guard let character = key.first, key.count == 1,
              let jamo = Self.keyMap[character] else { return [] }
        return [.emit(jamo)]
    }

    /// 두벌식은 상태가 없어 되돌릴 것이 없다.
    public func reset() {}

    // MARK: - 자판 배열

    private static let keyMap: [Character: Jamo] = {
        var map: [Character: Jamo] = [:]

        let consonants: [Character: Character] = [
            "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ",
            "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ",
            "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ"
        ]
        let vowels: [Character: Character] = [
            "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
            "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
            "b": "ㅠ", "n": "ㅜ", "m": "ㅡ"
        ]
        /// 시프트로만 나오는 자모
        let shifted: [Character: Jamo] = [
            "Q": .consonant("ㅃ"), "W": .consonant("ㅉ"), "E": .consonant("ㄸ"),
            "R": .consonant("ㄲ"), "T": .consonant("ㅆ"),
            "O": .vowel("ㅒ"), "P": .vowel("ㅖ")
        ]

        for (key, jamo) in consonants {
            map[key] = .consonant(jamo)
            // 시프트 전용 자모가 없는 키는 대문자도 같은 자모를 낸다
            map[Character(key.uppercased())] = .consonant(jamo)
        }
        for (key, jamo) in vowels {
            map[key] = .vowel(jamo)
            map[Character(key.uppercased())] = .vowel(jamo)
        }
        for (key, jamo) in shifted {
            map[key] = jamo
        }
        return map
    }()
}
