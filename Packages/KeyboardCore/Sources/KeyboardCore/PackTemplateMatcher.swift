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
///
/// ## U7 — 소유하지 못한 팩의 같은 번호 (10-6 ①)
///
/// 칩은 위 규칙 그대로 소유 팩의 항목이다(`match(tail:)`). 길게 누르기 목록(`matches(tail:limit:)`)만 같은 쌍을 **후순위로 가진 팩**의
/// 같은 `n` 항목을 소유 팩 뒤에(목록 순서대로) 더한다 — 소유 팩에 n이 없으면 여전히 아무것도 없다(후퇴 금지).
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

    /// 같은 쌍을 후순위로 가진 팩(U7) — 번호 사전을 **만들지 않는다**. 팩마다 항목 최대 5,000개의 사전을 상시 들면 키보드 피크
    /// (9-5, legacy10 35.6MB 주의대)에 더해진다. `template`은 키보드가 이미 읽어 둔 팩 값을 공유한다(배열 CoW — 복사 없음).
    /// 조회는 칩이 맞았을 때만, 번호 오름차순이면 이진 탐색이다.
    private struct Alternate: Sendable {
        let sourceID: String
        let template: PackTemplate
        /// 번호가 엄격히 오름차순인가 — 가져오기(`PackImporter`)가 그렇게 쓰지만 키보드는 저장본을 믿지 않는다(9-4)
        let itemsAreSorted: Bool

        func item(_ n: Int) -> PackTemplateItem? {
            let items = template.items
            guard itemsAreSorted else { return items.last { $0.n == n } }   // 같은 번호는 뒤가 이긴다(소유 팩 사전과 같은 규칙)
            var low = 0, high = items.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if items[mid].n == n { return items[mid] }
                if items[mid].n < n { low = mid + 1 } else { high = mid - 1 }
            }
            return nil
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
        /// 이 쌍을 후순위로 가진 팩 — 목록 순서(U7)
        var alternates: [Alternate] = []
    }

    /// 목록 순서 → 팩 내부 패턴 순서(10-4 동점 기준)
    public let ownership: [PatternOwnership]
    /// literal 길이 내림차순(같으면 목록·패턴 순서) — 첫 매치가 곧 최선
    private let owned: [OwnedPattern]

    public init(sources: [Source]) {
        var owners: [TemplatePattern: (sourceID: String, index: Int)] = [:]
        var ownership: [PatternOwnership] = []
        var owned: [OwnedPattern] = []
        for source in sources {
            var seenInSource = Set<TemplatePattern>()
            let items = Dictionary(source.template.items.map { ($0.n, $0) }, uniquingKeysWith: { _, later in later })
            var sorted: Bool?   // 후순위 쌍이 있을 때만 한 번 잰다
            for pattern in source.template.patterns where seenInSource.insert(pattern).inserted {
                if let owner = owners[pattern] {
                    ownership.append(PatternOwnership(sourceID: source.id, pattern: pattern, status: .outranked(by: owner.sourceID)))
                    let itemsAreSorted = sorted ?? zip(source.template.items, source.template.items.dropFirst()).allSatisfy { $0.n < $1.n }
                    sorted = itemsAreSorted
                    owned[owner.index].alternates.append(
                        Alternate(sourceID: source.id, template: source.template, itemsAreSorted: itemsAreSorted))
                    continue
                }
                owners[pattern] = (source.id, owned.count)
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

    /// 칩 — 이긴 쌍의 소유 팩 항목. `matches(tail:limit:)`의 첫째와 같다.
    public func match(tail: String) -> Match? {
        matches(tail: tail, limit: 1).first
    }

    /// U7 — 같은 꼬리 구간에 맞은 항목 전부(최대 `limit`개). **첫째 = `match(tail:)`**(칩), 그 뒤는:
    ///
    /// 1. 이긴 쌍을 **후순위로 가진 팩**의 같은 `n` 항목 — 목록 순서(10-6 ①). 그 팩에 n이 없으면 건너뛴다
    /// 2. 다른 소유 쌍이 **같은 구간**(같은 시작 위치)에 맞으면 그 소유 팩 → 그 쌍의 후순위 팩 — 쌍 우선순위(literal 길이 → 목록 → 패턴) 순
    ///
    /// 이긴 쌍의 소유 팩에 n이 없으면 **빈 배열**이다 — 칩이 없으면 목록도 없다(10-4 5번, 후퇴 금지). 같은 (팩, 번호)는 한 번만.
    public func matches(tail: String, limit: Int = .max) -> [Match] {
        guard !owned.isEmpty, !tail.isEmpty, limit > 0 else { return [] }
        let characters = Array(tail)
        var reversed: [(character: Character, index: Int)] = []
        reversed.reserveCapacity(characters.count)
        for index in stride(from: characters.count - 1, through: 0, by: -1) {
            let character = characters[index]
            if character.isNewline { break }
            if character.isWhitespace { continue }
            reversed.append((character, index))
        }
        var result: [Match] = []
        forEachMatch(characters: characters, reversed: reversed) { raw in
            result.append(raw.match)
            return result.count < limit
        }
        return result
    }

    /// 같은 구간 적중 하나 — **제목·`Match`를 아직 만들지 않은** 재료. 칩의 「+n」은 이것을 세기만 한다(핫패스, 10-6 ① (b))
    struct RawMatch {
        let sourceID: String
        let n: Int
        let item: PackTemplateItem
        let template: PackTemplate
        /// 꼬리에서 잘라낸 원문 — 같은 호출의 적중은 모두 같다
        let trigger: String

        var match: Match {
            Match(sourceID: sourceID, n: n, trigger: trigger, title: template.title(for: item), body: item.body)
        }
    }

    /// `matches`의 판정 본체 — 꼬리를 이미 풀어 둔 호출자(`SnippetMatcher`)가 그대로 넘긴다(같은 규칙: 줄바꿈에서 멈추고 공백은 건너뛴다).
    /// 적중을 순서대로 `visit`에 넘기고 `visit`이 false를 내면 멈춘다. 이긴 쌍의 소유 팩에 n이 없으면 아무것도 넘기지 않는다.
    func forEachMatch(
        characters: [Character], reversed: [(character: Character, index: Int)], _ visit: (RawMatch) -> Bool
    ) {
        var span: (start: Int, trigger: String)?
        var seen: [(sourceID: String, n: Int)] = []   // 같은 (팩, 번호)는 한 번만 — 한 팩이 같은 구간에 맞는 쌍을 둘 가질 수 있다
        func offer(_ sourceID: String, _ n: Int, _ item: PackTemplateItem, _ template: PackTemplate, _ trigger: String) -> Bool {
            guard !seen.contains(where: { $0.sourceID == sourceID && $0.n == n }) else { return true }
            seen.append((sourceID, n))
            return visit(RawMatch(sourceID: sourceID, n: n, item: item, template: template, trigger: trigger))
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
            let start = reversed[cursor + pattern.prefixReversed.count - 1].index
            let trigger: String
            if let span {
                // 칩은 이미 정해졌다 — 같은 구간에 맞은 다른 쌍만 더한다
                guard span.start == start else { continue }
                trigger = span.trigger
            } else {
                // 이 쌍이 이겼다 — 소유 팩에 n이 없으면 아무것도 없다(더 짧은 쌍·다른 판본으로도 후퇴하지 않는다)
                guard pattern.items[n] != nil else { return }
                trigger = String(characters[start...])
                span = (start, trigger)
            }
            if let item = pattern.items[n], !offer(pattern.sourceID, n, item, pattern.template, trigger) { return }
            for alternate in pattern.alternates {
                guard let item = alternate.item(n) else { continue }
                guard offer(alternate.sourceID, n, item, alternate.template, trigger) else { return }
            }
        }
    }

    private static func hasPrefix(
        _ reversed: [(character: Character, index: Int)], from start: Int, _ needle: [Character]
    ) -> Bool {
        guard start + needle.count <= reversed.count else { return false }
        for offset in 0..<needle.count where reversed[start + offset].character != needle[offset] { return false }
        return true
    }
}
