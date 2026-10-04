import TadakDomain

/// 외부 팩 번호형 템플릿(`사자성어{n}번`)의 매칭과 소유권
/// (PDR `docs/design-reviews/external-snippet-packs.md` 10-4·10-5, AC-24 · AC-25).
///
/// `SnippetMatcher`의 분기 순서(문구 → 내장 → 날짜·시간 → **템플릿** → 성경)에 끼우는 배선은 저장 단계(1-b)다 —
/// 이 타입은 **꼬리 문자열만 보는 순수 값**이라 키보드와 앱(팩 정보 화면의 소유·후순위 표시)이 같이 쓴다.
///
/// ## 소유권 (10-4)
///
/// 같은 (접두, 접미) 정규화 쌍은 **목록 순서의 첫 팩**이 소유한다 — U1에 따라 「내 채움글」도 그 목록의 한 줄이지만
/// 템플릿이 없어 쌍을 갖지 않는다. 띄어쓰기만 다른 별칭은 정규화 뒤 같은 쌍이다. 소유 팩에 그 번호가 없으면
/// **nil** — 다른 팩·다른 판본으로 후퇴하지 않는다.
///
/// ## 매칭 (10-5)
///
/// 꼬리를 뒤에서 앞으로(같은 줄의 공백은 건너뛰고 **줄바꿈에서 멈춘다** — `SnippetMatcher`와 같다) → 접미 일치 →
/// 그 앞의 **ASCII 숫자열 전체**(1~4자리, 선행 0 금지, **후퇴 금지** — `3232`를 `232`로 줄이지 않는다) → 접두 일치 →
/// literal이 긴 쌍이 이긴다 → 소유 팩의 `n`. 지울 구간은 **꼬리에서 잘라낸 원문**(`insertSnippet`의 꼬리 정합 불변식).
public struct PackTemplateMatcher: Sendable {

    public struct Source: Equatable, Sendable {
        public var id: String
        public var template: PackTemplate

        public init(id: String, template: PackTemplate) {
            self.id = id
            self.template = template
        }
    }

    public struct Match: Equatable, Sendable {
        public var sourceID: String
        public var n: Int
        /// 꼬리에서 잘라낸 원문(공백 포함) — 지울 길이
        public var trigger: String
        public var title: String
        public var body: String

        public init(sourceID: String, n: Int, trigger: String, title: String, body: String) {
            self.sourceID = sourceID
            self.n = n
            self.trigger = trigger
            self.title = title
            self.body = body
        }

        public var suggestion: SnippetSuggestion {
            SnippetSuggestion(trigger: trigger, title: title, body: body)
        }
    }

    public enum PatternStatus: Equatable, Sendable {
        case owned
        /// 앞 순서 팩이 같은 쌍을 가져 이 팩의 패턴은 쓰이지 않는다 — 팩 정보에 「후순위」
        case outranked(by: String)
    }

    public struct PatternOwnership: Equatable, Sendable {
        public var sourceID: String
        public var pattern: TemplatePattern
        public var status: PatternStatus

        public init(sourceID: String, pattern: TemplatePattern, status: PatternStatus) {
            self.sourceID = sourceID
            self.pattern = pattern
            self.status = status
        }
    }

    /// 소유된 쌍 하나 — 매칭에 쓰는 미리 뒤집은 글자와 소유 팩의 항목
    private struct OwnedPattern: Sendable {
        let suffixReversed: [Character]
        let prefixReversed: [Character]
        let literalLength: Int
        let sourceID: String
        let template: PackTemplate
        let items: [Int: PackTemplateItem]
    }

    /// 목록 순서 → 팩 내부 패턴 순서(10-4 동점 기준)
    public let ownership: [PatternOwnership]
    /// literal 길이 내림차순(같으면 목록·패턴 순서) — 첫 매치가 곧 최선
    private let owned: [OwnedPattern]

    public init(sources: [Source]) {
        var owners: [TemplatePattern: String] = [:]
        var ownership: [PatternOwnership] = []
        var owned: [OwnedPattern] = []
        for source in sources {
            var seenInSource = Set<TemplatePattern>()
            let items = Dictionary(source.template.items.map { ($0.n, $0) }, uniquingKeysWith: { _, later in later })
            for pattern in source.template.patterns where seenInSource.insert(pattern).inserted {
                if let owner = owners[pattern] {
                    ownership.append(PatternOwnership(sourceID: source.id, pattern: pattern, status: .outranked(by: owner)))
                    continue
                }
                owners[pattern] = source.id
                ownership.append(PatternOwnership(sourceID: source.id, pattern: pattern, status: .owned))
                owned.append(OwnedPattern(suffixReversed: Array(pattern.suffix.reversed()),
                                          prefixReversed: Array(pattern.prefix.reversed()),
                                          literalLength: pattern.literalLength, sourceID: source.id,
                                          template: source.template, items: items))
            }
        }
        // 안정 정렬 — 같은 길이면 넣은 순서(목록 → 패턴)
        self.owned = owned.enumerated()
            .sorted { $0.element.literalLength != $1.element.literalLength
                ? $0.element.literalLength > $1.element.literalLength : $0.offset < $1.offset }
            .map(\.element)
        self.ownership = ownership
    }

    public func match(tail: String) -> Match? {
        guard !owned.isEmpty, !tail.isEmpty else { return nil }
        let characters = Array(tail)
        var reversed: [(character: Character, index: Int)] = []
        reversed.reserveCapacity(characters.count)
        for index in stride(from: characters.count - 1, through: 0, by: -1) {
            let character = characters[index]
            if character.isNewline { break }
            if character.isWhitespace { continue }
            reversed.append((character, index))
        }

        for pattern in owned {
            guard Self.hasPrefix(reversed, from: 0, pattern.suffixReversed) else { continue }
            // 숫자열 전체 — 후퇴 금지
            var cursor = pattern.suffixReversed.count
            var digits: [Character] = []
            while cursor < reversed.count, let ascii = reversed[cursor].character.asciiValue, (48...57).contains(ascii) {
                digits.append(reversed[cursor].character)
                cursor += 1
            }
            guard (1...4).contains(digits.count) else { continue }
            let number = String(digits.reversed())
            guard number.first != "0", let n = Int(number) else { continue }
            guard Self.hasPrefix(reversed, from: cursor, pattern.prefixReversed) else { continue }
            // 이 쌍이 이겼다 — 소유 팩에 n이 없으면 nil(더 짧은 쌍으로도 후퇴하지 않는다)
            guard let item = pattern.items[n] else { return nil }
            let start = reversed[cursor + pattern.prefixReversed.count - 1].index
            return Match(sourceID: pattern.sourceID, n: n, trigger: String(characters[start...]),
                         title: pattern.template.title(for: item), body: item.body)
        }
        return nil
    }

    private static func hasPrefix(
        _ reversed: [(character: Character, index: Int)], from start: Int, _ needle: [Character]
    ) -> Bool {
        guard start + needle.count <= reversed.count else { return false }
        for offset in 0..<needle.count where reversed[start + offset].character != needle[offset] { return false }
        return true
    }
}
