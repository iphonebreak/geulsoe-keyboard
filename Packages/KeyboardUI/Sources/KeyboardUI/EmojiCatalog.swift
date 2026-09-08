import Foundation

/// 이모지 카탈로그 — 유니코드 블록을 순회하며 **이모지 표현이 기본인 단일 코드포인트**만 모은다
/// (`isEmojiPresentation`: VS16 없이도 컬러 이모지로 그려지는 것). 텍스트 기본 기호(☺ 등)와
/// 피부색·머리색 구성요소, 지역 표시자(국기 조합 재료), ZWJ 시퀀스는 뺀다 — 렌더 실패(□)를
/// 피하고 목록을 단순하게 유지.
///
/// 하드코딩 목록이 아니라 시스템 유니코드 속성이라 OS가 지원하는 이모지가 곧 목록이다.
/// 카테고리는 유니코드 블록 단위라 경계가 거칠지만 탐색용으로 충분. 어느 블록에도 안 든
/// 잔여는 마지막 "기타"가 스윕하므로 새 유니코드 버전의 이모지도 빠지지 않는다
/// (커버리지는 `EmojiCatalogTests`가 고정).
public enum EmojiCatalog {

    public struct Category: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let symbol: String
        public let emojis: [String]
    }

    /// 자주 쓰는 이모지 — 목록 맨 앞 큐레이션
    public static let frequent: [String] = [
        "😀", "😂", "🤣", "😊", "😍", "🥰", "😘", "😎",
        "🙂", "🙃", "😉", "😌", "🤗", "🤔", "😅", "😳",
        "🥺", "😢", "😭", "😤", "😡", "😱", "😴", "🤒",
        "👍", "👎", "👌", "✌️", "🤞", "👏", "🙏", "💪",
        "🤝", "👋", "🙇", "🫶", "❤️", "🧡", "💛", "💚",
        "💙", "💜", "🖤", "🤍", "💕", "💖", "💯", "🔥",
        "✨", "⭐", "🎉", "🎊", "🎂", "🎁", "🌸", "🌺",
        "☀️", "🌙", "⚡", "❄️", "💧", "😇", "🍀", "💤"
    ]

    /// 스윕 대상 전 범위 — 이모지가 존재하는 BMP 기호 구간부터 SMP 이모지 확장 블록 끝까지
    static let sweepRange: ClosedRange<UInt32> = 0x2000...0x1FAFF

    /// 카탈로그에서 의도적으로 빼는 스칼라 — 단독으로는 견본(색·머리)이나 글자 상자로 그려진다
    static func isExcluded(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return scalar.properties.isEmojiModifier      // 피부색 1F3FB~1F3FF
            || (0x1F9B0...0x1F9B3).contains(v)         // 머리색 구성요소
            || (0x1F1E6...0x1F1FF).contains(v)         // 지역 표시자 (국기 조합 재료)
    }

    /// 카탈로그 포함 조건
    static func isCatalogued(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmojiPresentation && !isExcluded(scalar)
    }

    public static let categories: [Category] = {
        var seen = Set<UInt32>()
        var result: [Category] = []
        for block in blocks {
            let emojis = block.ranges.flatMap { range in
                range.compactMap { value -> String? in
                    guard let scalar = Unicode.Scalar(value), isCatalogued(scalar),
                          !seen.contains(value) else { return nil }
                    seen.insert(value)
                    return String(Character(scalar))
                }
            }
            if !emojis.isEmpty {
                result.append(Category(id: block.id, name: block.name, symbol: block.symbol, emojis: emojis))
            }
        }
        // 잔여 스윕 — 블록 범위가 놓친 이모지(새 유니코드 버전 포함)
        let rest = sweepRange.compactMap { value -> String? in
            guard let scalar = Unicode.Scalar(value), isCatalogued(scalar),
                  !seen.contains(value) else { return nil }
            return String(Character(scalar))
        }
        if !rest.isEmpty {
            result.append(Category(id: "other", name: "기타", symbol: "ellipsis.circle", emojis: rest))
        }
        return result
    }()

    private struct Block {
        let id: String
        let name: String
        let symbol: String
        let ranges: [ClosedRange<UInt32>]
    }

    private static let blocks: [Block] = [
        Block(id: "smileys", name: "표정", symbol: "face.smiling",
              ranges: [0x1F600...0x1F64A, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1F9D0...0x1F9D0,
                       0x1FAE0...0x1FAE9]),
        Block(id: "people", name: "사람·손", symbol: "hand.raised",
              ranges: [0x1F440...0x1F487, 0x1F64B...0x1F64F, 0x1F90C...0x1F90F, 0x1F930...0x1F93E,
                       0x1F9B4...0x1F9B9, 0x1F9BB...0x1F9BB, 0x1F9CC...0x1F9CF, 0x1F9D1...0x1F9DF,
                       0x1FAC0...0x1FAC5, 0x1FAF0...0x1FAF8]),
        Block(id: "nature", name: "동물·자연", symbol: "leaf",
              ranges: [0x1F300...0x1F32C, 0x1F330...0x1F344, 0x1F400...0x1F43F, 0x1F980...0x1F9AE,
                       0x1FAB0...0x1FABF, 0x1FACE...0x1FACF]),
        Block(id: "food", name: "음식", symbol: "fork.knife",
              ranges: [0x1F32D...0x1F32F, 0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB,
                       0x1FAD0...0x1FADB]),
        Block(id: "activity", name: "활동·기념", symbol: "figure.run",
              ranges: [0x1F380...0x1F3D3, 0x1F3F8...0x1F3FA, 0x1F93F...0x1F94F, 0x26BD...0x26BE,
                       0x1F9E9...0x1F9E9, 0x1FA80...0x1FA88, 0x1F004...0x1F004, 0x1F0CF...0x1F0CF]),
        Block(id: "travel", name: "교통·장소", symbol: "car",
              ranges: [0x1F3D4...0x1F3F7, 0x1F680...0x1F6FF]),
        Block(id: "objects", name: "사물", symbol: "lightbulb",
              ranges: [0x1F488...0x1F4AE, 0x1F4B0...0x1F4FF, 0x1F500...0x1F53D, 0x1F550...0x1F567,
                       0x1F5FA...0x1F5FF, 0x1F97B...0x1F97F, 0x1F9AF...0x1F9AF, 0x1F9BA...0x1F9BA,
                       0x1F9BC...0x1F9BF, 0x1F9E0...0x1F9E8, 0x1F9EA...0x1F9FF, 0x1FA70...0x1FA74,
                       0x1FA78...0x1FA7C, 0x1FA90...0x1FAAF, 0x1FAC6...0x1FACD]),
        Block(id: "symbols", name: "기호", symbol: "heart",
              ranges: [0x2600...0x26BC, 0x26BF...0x27BF, 0x2B50...0x2B55, 0x2B1B...0x2B1C,
                       0x25FD...0x25FE, 0x231A...0x23FF, 0x1F4AF...0x1F4AF, 0x1F53E...0x1F54F,
                       0x1F568...0x1F5F9, 0x1FA75...0x1FA77, 0x1F7E0...0x1F7FF,
                       0x1F170...0x1F19A, 0x1F200...0x1F251])
    ]
}
