import TadakDomain

/// 미리보기의 「단축어 확인」(시안 4-I) — 가져오려는 문구형 팩과 **같은 단축어**를 가진 줄(계획서 5절 4행 ③, 3-3절 4-I).
///
/// 겹침은 거부가 아니라 안내다(단축어가 겹쳐도 가져올 수 있다). 줄마다 「누가 먼저 뜨나」를 함께 낸다 — 새 팩은 **켠 채 목록 맨 아래**에
/// 붙으므로(U2) 「내 채움글」과 켜져 포함된 팩은 언제나 새 팩보다 먼저이고(U1), 꺼진·쉬는 팩은 지금 뜨지 않으며, 내장 팩은 언제나 뒤다(10-3).
/// 포함 판정은 3단계 G3와 같은 입력(`PackImpact.Library.budgetInput` → `ActivePackBudget.evaluate`), 정규화는 `SnippetEntry.normalizedTrigger`
/// 한 함수다. 단축어는 사용자 입력이라 화면에 **표시**만 한다(보안 규칙).
public struct PackDraftOverlap: Equatable, Sendable {

    public struct Group: Equatable, Sendable {
        public var source: PackImpact.Source
        /// 새 팩의 원문 — 파일 순서, 정규화가 같은 것은 한 번
        public var triggers: [String]
        /// 이 줄이 새 팩보다 먼저 뜬다(그 단축어를 치면 이 줄의 문구가 칩에 뜬다)
        public var showsBeforeDraft: Bool

        public init(source: PackImpact.Source, triggers: [String], showsBeforeDraft: Bool) {
            self.source = source
            self.triggers = triggers
            self.showsBeforeDraft = showsBeforeDraft
        }
    }

    public var userSnippets: Group?
    /// 목록 순서 — 읽을 수 없는 팩은 단축어를 몰라 없다
    public var packs: [Group]
    public var builtIn: Group?

    public init(userSnippets: Group?, packs: [Group], builtIn: Group?) {
        self.userSnippets = userSnippets
        self.packs = packs
        self.builtIn = builtIn
    }

    public var isEmpty: Bool { userSnippets == nil && packs.isEmpty && builtIn == nil }
}

extension PackImpact {

    /// 새 팩(가져오기 초안)의 단축어가 지금 목록의 어느 줄과 겹치나(4-I)
    public static func overlap(ofDraft entries: [SnippetEntry], in library: Library) -> PackDraftOverlap {
        var seen = Set<String>()
        let draft: [(key: String, trigger: String)] = entries.flatMap(\.triggers).compactMap { trigger in
            let key = SnippetEntry.normalizedTrigger(trigger)
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return (key, trigger)
        }
        func shared(with triggers: [String]) -> [String] {
            let keys = Set(triggers.map(SnippetEntry.normalizedTrigger))
            return draft.filter { keys.contains($0.key) }.map(\.trigger)
        }
        func group(_ source: Source, _ triggers: [String], showsBeforeDraft: Bool) -> PackDraftOverlap.Group? {
            let common = shared(with: triggers)
            return common.isEmpty ? nil : PackDraftOverlap.Group(source: source, triggers: common, showsBeforeDraft: showsBeforeDraft)
        }

        // 지금 포함된 팩 — 커밋 게이트·순서 화면과 같은 판정(읽을 수 없는 팩은 후보에서 빠진다). 새 팩은 맨 아래라 이 판정을 바꾸지 않는다(prefix rule)
        let current = library.budgetInput(order: library.order, enabled: [:])
        let included = Set(ActivePackBudget.evaluate(baseline: current.baseline, packs: current.packs, limits: library.limits).included)
        let packs = library.order.compactMap(\.packID).compactMap(library.pack).filter { !$0.isUnavailable }.compactMap {
            group(.pack($0.id), $0.triggers, showsBeforeDraft: included.contains($0.id))
        }
        // 「내 채움글」 줄은 순서 목록에 늘 있고(없으면 합성 함수가 맨 앞에 둔다) 새 팩은 그 아래 — 언제나 먼저 뜬다
        return PackDraftOverlap(userSnippets: group(.userSnippets, library.userTriggers, showsBeforeDraft: true),
                                packs: packs,
                                builtIn: group(.builtIn, library.builtInTriggers, showsBeforeDraft: false))
    }
}
