/// 한글 자모. 오토마타와 자판(`JamoSource`) 사이의 유일한 공통 언어다.
///
/// 자판별 차이는 전부 `JamoSource` 안에서 흡수되고, 여기부터 아래로는 자판을 구분하지 않는다.
public enum Jamo: Equatable, Sendable {
    /// 초성 또는 종성이 될 수 있는 자음 (호환 자모 기준)
    case consonant(Character)
    /// 중성이 되는 모음
    case vowel(Character)
}

/// 현대 한글 음절의 유니코드 조합/분해.
///
/// `음절 = 0xAC00 + (초성 × 588) + (중성 × 28) + 종성`
public enum HangulSyllable {

    public static let choseongTable: [Character] = [
        "ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    public static let jungseongTable: [Character] = [
        "ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
        "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"
    ]

    /// 첫 원소는 "종성 없음"을 뜻한다.
    public static let jongseongTable: [Character?] = [
        nil, "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ",
        "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ",
        "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"
    ]

    private static let base: UInt32 = 0xAC00
    private static let jungseongCount: UInt32 = 21
    private static let jongseongCount: UInt32 = 28

    /// 초성·중성·(종성)을 하나의 음절로 합친다. 인덱스가 표 범위를 벗어나면 `nil`.
    public static func compose(choseong: Int, jungseong: Int, jongseong: Int = 0) -> Character? {
        guard choseongTable.indices.contains(choseong),
              jungseongTable.indices.contains(jungseong),
              jongseongTable.indices.contains(jongseong) else { return nil }

        let code = base
            + UInt32(choseong) * jungseongCount * jongseongCount
            + UInt32(jungseong) * jongseongCount
            + UInt32(jongseong)
        guard let scalar = Unicode.Scalar(code) else { return nil }
        return Character(scalar)
    }

    /// 완성형 음절을 초성·중성·종성 인덱스로 분해한다. 완성형이 아니면 `nil`.
    public static func decompose(_ character: Character) -> (choseong: Int, jungseong: Int, jongseong: Int)? {
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1,
              (base ..< base + 11172).contains(scalar.value) else { return nil }

        let offset = scalar.value - base
        return (
            choseong: Int(offset / (jungseongCount * jongseongCount)),
            jungseong: Int((offset % (jungseongCount * jongseongCount)) / jongseongCount),
            jongseong: Int(offset % jongseongCount)
        )
    }

    /// 겹받침을 두 자모로 분해한다. 홑받침이거나 종성이 없으면 `nil`.
    ///
    /// 백스페이스로 겹받침을 되돌릴 때 쓴다 (`ㄳ` → `ㄱ` + `ㅅ`).
    public static func splitJongseong(_ index: Int) -> (first: Int, second: Int)? {
        compoundJongseong[index]
    }

    /// 두 종성 자모를 겹받침으로 합친다. 합쳐질 수 없으면 `nil`.
    public static func combineJongseong(_ first: Int, _ second: Int) -> Int? {
        compoundJongseong.first { $0.value == (first, second) }?.key
    }

    /// 겹받침 인덱스 → 구성 홑받침 인덱스 쌍
    private static let compoundJongseong: [Int: (first: Int, second: Int)] = [
        3: (1, 19),    // ㄳ = ㄱ + ㅅ
        5: (4, 22),    // ㄵ = ㄴ + ㅈ
        6: (4, 27),    // ㄶ = ㄴ + ㅎ
        9: (8, 1),     // ㄺ = ㄹ + ㄱ
        10: (8, 16),   // ㄻ = ㄹ + ㅁ
        11: (8, 17),   // ㄼ = ㄹ + ㅂ
        12: (8, 19),   // ㄽ = ㄹ + ㅅ
        13: (8, 25),   // ㄾ = ㄹ + ㅌ
        14: (8, 26),   // ㄿ = ㄹ + ㅍ
        15: (8, 27),   // ㅀ = ㄹ + ㅎ
        18: (17, 19)   // ㅄ = ㅂ + ㅅ
    ]

    // MARK: - 복모음

    /// 복모음을 두 모음으로 분해한다. 단모음이면 `nil`.
    ///
    /// 백스페이스로 복모음을 되돌릴 때 쓴다 (`ㅘ` → `ㅗ` + `ㅏ`).
    public static func splitJungseong(_ index: Int) -> (first: Int, second: Int)? {
        compoundJungseong[index]
    }

    /// 두 모음을 복모음으로 합친다. 합쳐질 수 없으면 `nil`.
    public static func combineJungseong(_ first: Int, _ second: Int) -> Int? {
        compoundJungseong.first { $0.value == (first, second) }?.key
    }

    /// 복모음 인덱스 → 구성 단모음 인덱스 쌍
    ///
    /// `ㅑㅒㅕㅖㅛㅠ`는 여기 없다. 두벌식에서 키 하나로 입력되고 조합으로 만들지 않기 때문이다.
    /// (천지인·단모음은 자기 `JamoSource` 안에서 이 모음들을 만들어 넘긴다)
    private static let compoundJungseong: [Int: (first: Int, second: Int)] = [
        9: (8, 0),     // ㅘ = ㅗ + ㅏ
        10: (8, 1),    // ㅙ = ㅗ + ㅐ
        11: (8, 20),   // ㅚ = ㅗ + ㅣ
        14: (13, 4),   // ㅝ = ㅜ + ㅓ
        15: (13, 5),   // ㅞ = ㅜ + ㅔ
        16: (13, 20),  // ㅟ = ㅜ + ㅣ
        19: (18, 20)   // ㅢ = ㅡ + ㅣ
    ]

    // MARK: - 자모 → 인덱스

    /// 자음의 초성 인덱스. 초성이 될 수 없으면 `nil` (겹받침 등).
    public static func choseongIndex(of jamo: Character) -> Int? {
        choseongLookup[jamo]
    }

    /// 모음의 중성 인덱스.
    public static func jungseongIndex(of jamo: Character) -> Int? {
        jungseongLookup[jamo]
    }

    /// 자음의 종성 인덱스. 종성이 될 수 없으면 `nil` (`ㄸ`, `ㅃ`, `ㅉ`).
    public static func jongseongIndex(of jamo: Character) -> Int? {
        jongseongLookup[jamo]
    }

    private static let choseongLookup: [Character: Int] =
        Dictionary(uniqueKeysWithValues: choseongTable.enumerated().map { ($1, $0) })

    private static let jungseongLookup: [Character: Int] =
        Dictionary(uniqueKeysWithValues: jungseongTable.enumerated().map { ($1, $0) })

    private static let jongseongLookup: [Character: Int] =
        Dictionary(uniqueKeysWithValues: jongseongTable.enumerated().compactMap { index, jamo in
            jamo.map { ($0, index) }
        })
}
