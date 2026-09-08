import Foundation

/// 단모음 자판.
///
/// 두벌식에서 이중모음 키(ㅑㅕㅛㅠㅒㅖ)와 시프트를 없앤 배열. 쌍자음과 이중모음은
/// 같은 키 연타로 승격한다 (ㄱㄱ → ㄲ, ㅏㅏ → ㅑ). 배열 근거는
/// `docs/design-reviews/cheonjiin-danmoeum-layouts.md` (삼성 키보드·Gboard 공통).
///
/// 승격은 2상태 토글이다: 세 번째 연타는 원래 자모로 돌아온다 (ㄱㄱㄱ → ㄱ).
/// `timeout`을 넘긴 재입력은 승격이 아니라 별개 자모다.
/// 키 id는 자모 문자 자체를 쓴다 (두벌식과 달리 QWERTY 대응이 없다).
public final class DanmoeumSource: JamoSource {

    public let identifier = "danmoeum"

    /// 연타 승격을 인정하는 같은 키 재입력 간격(초)
    private let timeout: TimeInterval

    private var lastKey: String?
    private var lastTime: TimeInterval = -.infinity
    /// 직전 입력이 승격 상태인가 (ㄲ·ㅑ 등) — 토글 복귀 판정
    private var promoted = false

    public init(timeout: TimeInterval = 0.3) {
        self.timeout = timeout
    }

    public func accept(key: String, at timestamp: TimeInterval) -> [JamoEvent] {
        guard let jamo = Self.keyMap[key] else {
            // 자모가 아닌 키 — 연타 상태도 끊는다 ("ㄱ1ㄱ"이 ㄲ이 되면 안 된다)
            reset()
            return []
        }

        if key == lastKey, timestamp - lastTime <= timeout,
           let base = key.first, let promotion = Self.promotions[base] {
            lastTime = timestamp
            if promoted {
                promoted = false
                return [.replaceLast(jamo)] // 토글 복귀 (ㄲ → ㄱ)
            }
            promoted = true
            return [.replaceLast(Self.jamo(like: jamo, character: promotion))]
        }

        lastKey = key
        lastTime = timestamp
        promoted = false
        return [.emit(jamo)]
    }

    public func reset() {
        lastKey = nil
        lastTime = -.infinity
        promoted = false
    }

    // MARK: - 표

    private static func jamo(like original: Jamo, character: Character) -> Jamo {
        switch original {
        case .consonant: .consonant(character)
        case .vowel: .vowel(character)
        }
    }

    /// 배열에 있는 자모 22개. 시프트가 없으므로 이것이 전부다.
    private static let keyMap: [String: Jamo] = {
        var map: [String: Jamo] = [:]
        for character in "ㅂㅈㄷㄱㅅㅁㄴㅇㄹㅎㅋㅌㅊㅍ" {
            map[String(character)] = .consonant(character)
        }
        for character in "ㅗㅐㅔㅓㅏㅣㅜㅡ" {
            map[String(character)] = .vowel(character)
        }
        return map
    }()

    /// 연타 승격: 기본 자모 → 승격 자모. 여기 없는 키는 연타해도 각각 입력된다.
    private static let promotions: [Character: Character] = [
        "ㄱ": "ㄲ", "ㄷ": "ㄸ", "ㅂ": "ㅃ", "ㅅ": "ㅆ", "ㅈ": "ㅉ",
        "ㅏ": "ㅑ", "ㅓ": "ㅕ", "ㅗ": "ㅛ", "ㅜ": "ㅠ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"
    ]
}
