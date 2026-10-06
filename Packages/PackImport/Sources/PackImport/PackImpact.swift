import Foundation
import KeyboardCore
import TadakDomain

/// 순서·켬/끔을 **바꾸기 전에** 무엇이 달라지는지 — 1-c G3 사전 영향 계산(계획서 `external-snippet-packs-1c-plan.md` 2절 G3·4-1 ㉤).
///
/// `PackStore.reorder`는 거부가 없고(한도 감소 방향) 쉬게 된 팩을 **커밋 뒤에야** 돌려준다. 순서 화면(2-D·2-G)은 「완료」 전에
/// 「이렇게 바꾸면 ○○가 쉬어요 · 틀 주인이 바뀌어요 · 단축어 주인이 바뀌어요」를 보여야 한다(PDR 9-1 순서 변경 행, 10-4 ③, U4, AC-24).
/// 이 타입은 **저장하지 않는 순수 함수**다 — 입력은 `PackStore.impactLibrary()`가 한 번에 읽어 준 `Library`.
///
/// ## 키보드와 같은 답 (AC-8 취지 — 따로 규칙을 두지 않는다)
///
/// - **쉬게 될 팩**: 커밋 게이트 `PackCommitGate.judge`의 `newlyExcluded` 그 식 — 커밋이 돌려줄 값과 같다(읽을 수 없는 팩은
///   `PackStore`처럼 예산 후보에서 뺀다)
/// - **틀 주인**: 키보드의 `SnippetSourceComposer.compose` → `PackTemplateMatcher.ownership`(10-4 — 목록 순서 → 팩 안 패턴 순서)
/// - **단축어 주인**: 같은 `compose`가 낸 문구 순서에서 정규화 단축어마다 **처음 나온 줄** — `SnippetMatcher`의 동점 규칙(길이가 같으면
///   앞선 항목)과 같다. 정규화는 `SnippetEntry.normalizedTrigger` 한 함수뿐이다
///
/// 합성 함수에 넘기는 문구는 **단축어만 담은 가짜 항목**이고, 어느 줄의 것인지는 제목 칸에 표시해 둔다(매처는 제목으로 고르지 않는다 —
/// `PackImpactTests`의 키보드 대조 시험이 실제 `SnippetMatcher`로 같은 답을 확인한다). 팩 본문·단축어·이름은 사용자 입력이다 —
/// 화면에 **표시**만 하고 로그·분석 이벤트로 내보내지 않는다(보안 규칙).
public struct PackImpact: Equatable, Sendable {

    /// 단축어의 주인 — 키보드 매칭 순서: 순서 목록(「내 채움글」·문구형 팩, U1) → 내장 팩(10-3, 언제나 맨 뒤)
    public enum Source: Hashable, Sendable {
        case userSnippets
        case pack(String)
        case builtIn
    }

    /// 같은 틀(정규화 쌍)의 주인이 바뀐다(10-4)
    public struct TemplateOwnerChange: Equatable, Sendable {
        public var pattern: TemplatePattern
        public var from: String
        public var to: String

        public init(pattern: TemplatePattern, from: String, to: String) {
            self.pattern = pattern
            self.from = from
            self.to = to
        }
    }

    /// 같은 단축어(정규화)의 주인이 바뀐다(U1)
    public struct TriggerOwnerChange: Equatable, Sendable {
        /// **바뀐 뒤 주인**이 쓴 원문 — 화면에 보이는 모양
        public var trigger: String
        public var from: Source
        public var to: Source

        public init(trigger: String, from: Source, to: Source) {
            self.trigger = trigger
            self.from = from
            self.to = to
        }
    }

    /// 같은 (전 주인, 새 주인)끼리 묶은 한 줄 — 화면 문구 단위
    public struct TriggerOwnerGroup: Equatable, Sendable {
        public var from: Source
        public var to: Source
        public var triggers: [String]
    }

    public struct TemplateOwnerGroup: Equatable, Sendable {
        public var from: String
        public var to: String
        public var patterns: [TemplatePattern]
    }

    /// 지금 포함됐는데 바꾸면 한도 밖으로 밀리는 팩(목록 순서) — 커밋의 `Accepted.newlyExcluded`와 같은 값
    public var restingPacks: [String]
    /// 바뀐 뒤 소유 순서
    public var templateOwnerChanges: [TemplateOwnerChange]
    /// 바뀐 뒤 매칭 순서 — 주인이 생기거나(새로 포함) 사라지는(쉬게 됨) 단축어는 넣지 않는다(쉬는 팩은 `restingPacks`가 알린다)
    public var triggerOwnerChanges: [TriggerOwnerChange]

    public var isEmpty: Bool { restingPacks.isEmpty && templateOwnerChanges.isEmpty && triggerOwnerChanges.isEmpty }

    public var triggerOwnerGroups: [TriggerOwnerGroup] {
        var groups: [TriggerOwnerGroup] = []
        for change in triggerOwnerChanges {
            if let index = groups.firstIndex(where: { $0.from == change.from && $0.to == change.to }) {
                groups[index].triggers.append(change.trigger)
            } else {
                groups.append(TriggerOwnerGroup(from: change.from, to: change.to, triggers: [change.trigger]))
            }
        }
        return groups
    }

    public var templateOwnerGroups: [TemplateOwnerGroup] {
        var groups: [TemplateOwnerGroup] = []
        for change in templateOwnerChanges {
            if let index = groups.firstIndex(where: { $0.from == change.from && $0.to == change.to }) {
                groups[index].patterns.append(change.pattern)
            } else {
                groups.append(TemplateOwnerGroup(from: change.from, to: change.to, patterns: [change.pattern]))
            }
        }
        return groups
    }

    /// 제안 — 순서(지금 목록의 재배열)와 켬/끔 바꾸기(없으면 지금 값)
    public struct Proposal: Equatable, Sendable {
        public var order: [SnippetSourceSlot]
        public var enabled: [String: Bool]

        public init(order: [SnippetSourceSlot], enabled: [String: Bool] = [:]) {
            self.order = order
            self.enabled = enabled
        }
    }

    // MARK: - 계산

    public static func of(_ proposal: Proposal, in library: Library) -> PackImpact {
        let current = library.budgetInput(order: library.order, enabled: [:])
        let proposed = library.budgetInput(order: proposal.order, enabled: proposal.enabled)
        let before = ActivePackBudget.evaluate(baseline: current.baseline, packs: current.packs, limits: library.limits)
        // 쉬게 될 팩 — 커밋 게이트와 같은 식. 순서 바꾸기 판정은 거부가 없어 언제나 받는다(켬 제안이 섞여도 「거부 없는 판정」으로 본다)
        guard case .accept(let after, let newlyExcluded) = PackCommitGate.judge(
            .reorderPacks, current: current, proposed: proposed, limits: library.limits) else {
            return PackImpact(restingPacks: [], templateOwnerChanges: [], triggerOwnerChanges: [])
        }

        let triggersBefore = Dictionary(triggerOwners(of: library, order: library.order, included: before.included),
                                        uniquingKeysWith: { first, _ in first })
        let triggerChanges = triggerOwners(of: library, order: proposal.order, included: after.included)
            .compactMap { key, owner -> TriggerOwnerChange? in
                guard let old = triggersBefore[key], old.source != owner.source else { return nil }
                return TriggerOwnerChange(trigger: owner.trigger, from: old.source, to: owner.source)
            }
        let templatesBefore = Dictionary(templateOwners(of: library, order: library.order, included: before.included),
                                         uniquingKeysWith: { first, _ in first })
        let templateChanges = templateOwners(of: library, order: proposal.order, included: after.included)
            .compactMap { pattern, owner -> TemplateOwnerChange? in
                guard let old = templatesBefore[pattern], old != owner else { return nil }
                return TemplateOwnerChange(pattern: pattern, from: old, to: owner)
            }
        return PackImpact(restingPacks: newlyExcluded, templateOwnerChanges: templateChanges, triggerOwnerChanges: triggerChanges)
    }

    /// `of`를 전역 큐에서 — 순서 화면이 끌어 놓을 때마다 부른다(합성 2회·정규화 전부가 메인을 막지 않게, 검증 F-8 ①).
    /// 기다리는 사이 부른 작업이 취소됐으면(그 사이 또 옮겼다) nil — 늦은 결과가 새 순서의 안내를 덮지 않게.
    /// Swift 협력 스레드 풀이 아니라 GCD 큐로 넘긴다(`PackImportSession.perform`과 같은 이유)
    public static func perform(_ proposal: Proposal, in library: Library,
                               queue: DispatchQueue = .global(qos: .userInitiated)) async -> PackImpact? {
        let impact = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: of(proposal, in: library)) }
        }
        return Task.isCancelled ? nil : impact
    }

    /// 팩 상세(2-E·U1)의 자리 — 틀마다 사용 중·뒤 순서·가려짐(10-3·10-4 ③), 문구형은 「지금 안 뜨는 단축어」.
    /// **이 팩은 포함된 것으로 놓고** 계산한다(꺼졌거나 쉬는 팩이면 「켜면 어떻게 되나」) — 다른 팩은 지금 판정 그대로.
    /// 읽을 수 없는 팩·없는 팩은 nil(내용을 모른다)
    public static func standing(of packID: String, in library: Library) -> PackStanding? {
        guard let pack = library.pack(packID), !pack.isUnavailable else { return nil }
        let current = library.budgetInput(order: library.order, enabled: [:])
        var included = Set(ActivePackBudget.evaluate(baseline: current.baseline, packs: current.packs, limits: library.limits).included)
        included.insert(packID)
        let sources = compose(library, order: library.order, included: library.order.compactMap(\.packID).filter(included.contains))

        // 틀 — 소유는 키보드의 ownership 그대로. 소유한 틀도 정적 단축어가 먼저 가져가면 「가려짐」(10-3 — 순서와 무관)
        let ownership = sources.templates?.ownership ?? []
        var seenStatic = Set<String>()
        let staticTriggers = sources.entries.flatMap(\.triggers)
            .filter { seenStatic.insert(SnippetEntry.normalizedTrigger($0)).inserted }
        let patterns = ownership.filter { $0.sourceID == packID }.map { item -> PackStanding.Pattern in
            let status: PackStanding.PatternStatus
            switch item.status {
            case .outranked(let owner):
                status = .outranked(by: owner)
            case .owned:
                let shadowing = TemplatePatternSpec.shadowingTriggers(of: item.pattern, among: staticTriggers)
                status = shadowing.isEmpty
                    ? .owned(sharedWith: ownership.filter { $0.pattern == item.pattern && $0.status == .outranked(by: packID) }
                        .map(\.sourceID))
                    : .shadowed(by: shadowing)
            }
            return PackStanding.Pattern(pattern: item.pattern, display: library.display(item.pattern, preferring: packID),
                                        status: status)
        }

        // 단축어 — 위 줄(「내 채움글」·위 팩)이 같은 단축어를 가지면 이 팩 것은 안 뜬다(U1 「뒤 순서」). 내장 팩은 언제나 뒤라 해당 없음
        let owners = Dictionary(triggerOwners(in: sources), uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        let hidden = pack.triggers.compactMap { trigger -> PackStanding.HiddenTrigger? in
            let key = SnippetEntry.normalizedTrigger(trigger)
            guard !key.isEmpty, seen.insert(key).inserted, let owner = owners[key], owner.source != .pack(packID) else { return nil }
            return PackStanding.HiddenTrigger(trigger: trigger, owner: owner.source)
        }
        return PackStanding(patterns: patterns, hiddenTriggers: hidden)
    }

    // MARK: - 키보드 함수로 주인 정하기

    struct TriggerOwner: Equatable {
        var source: Source
        /// 그 주인이 쓴 원문
        var trigger: String
    }

    /// 정규화 단축어 → 주인(키보드 매칭 순서에서 처음 나온 줄). 순서는 그 매칭 순서
    static func triggerOwners(of library: Library, order: [SnippetSourceSlot], included: [String]) -> [(String, TriggerOwner)] {
        triggerOwners(in: compose(library, order: order, included: included))
    }

    /// 틀(정규화 쌍) → 소유 팩. 순서는 `ownership` 순서(목록 → 팩 안 패턴)
    static func templateOwners(of library: Library, order: [SnippetSourceSlot], included: [String]) -> [(TemplatePattern, String)] {
        (compose(library, order: order, included: included).templates?.ownership ?? [])
            .filter { $0.status == .owned }
            .map { ($0.pattern, $0.sourceID) }
    }

    private static func triggerOwners(in sources: SnippetSourceComposer.Sources) -> [(String, TriggerOwner)] {
        var seen = Set<String>()
        var owners: [(String, TriggerOwner)] = []
        for entry in sources.entries {
            guard let source = Source(tag: entry.title) else { continue }
            for trigger in entry.triggers {
                let key = SnippetEntry.normalizedTrigger(trigger)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                owners.append((key, TriggerOwner(source: source, trigger: trigger)))
            }
        }
        return owners
    }

    /// 키보드의 합성 함수에 **포함된 팩만** 넣는다(키보드 로더가 snapshot에 실린 팩만 넘기는 것과 같다). 줄마다 단축어를 한 항목에 모으고
    /// 제목 칸에 출처를 적는다 — 같은 줄 안의 순서는 주인을 바꾸지 않는다
    private static func compose(_ library: Library, order: [SnippetSourceSlot], included: [String]) -> SnippetSourceComposer.Sources {
        let includedSet = Set(included)
        var packs: [String: ExternalPack] = [:]
        for pack in library.packs where includedSet.contains(pack.id) && !pack.isUnavailable {
            packs[pack.id] = ExternalPack(
                name: "", license: "", mode: pack.patterns.isEmpty ? .phrases : .numbered,
                entries: pack.triggers.isEmpty ? [] : [tagged(.pack(pack.id), pack.triggers)],
                template: pack.patterns.isEmpty ? nil : PackTemplate(patterns: pack.patterns, titleFormat: "", items: []))
        }
        return SnippetSourceComposer.compose(order: order, userEntries: [tagged(.userSnippets, library.userTriggers)], packs: packs,
                                             builtIn: [tagged(.builtIn, library.builtInTriggers)])
    }

    private static func tagged(_ source: Source, _ triggers: [String]) -> SnippetEntry {
        SnippetEntry(triggers: triggers, title: source.tag, body: "")
    }
}

private extension PackImpact.Source {
    /// 합성 함수에 넘기는 가짜 항목의 제목 — 「u」·「b」·「p:<팩 id>」
    var tag: String {
        switch self {
        case .userSnippets: "u"
        case .builtIn: "b"
        case .pack(let id): "p:" + id
        }
    }

    init?(tag: String) {
        switch tag {
        case "u": self = .userSnippets
        case "b": self = .builtIn
        default:
            guard tag.hasPrefix("p:") else { return nil }
            self = .pack(String(tag.dropFirst(2)))
        }
    }
}

// MARK: - 입력

extension PackImpact {

    /// 목록 한 줄 — 읽기 모델 + 판정용 stats + 매칭에 쓰는 단축어·틀(읽을 수 없는 팩은 비었다)
    public struct Pack: Equatable, Sendable, Identifiable {
        public var summary: PackSummary
        /// 목록의 stats(커밋 때 다시 센 값) — `PackStore` 판정과 같은 입력
        public var stats: PackStats
        /// 문구형 단축어 원문 — 항목 순서대로
        public var triggers: [String]
        /// 번호형 틀(정규화 쌍) — 별칭 순서대로
        public var patterns: [TemplatePattern]

        public var id: String { summary.id }
        var isUnavailable: Bool { summary.status == .unavailable }

        /// - Parameter content: 변환본 내용 — 읽을 수 없는 팩은 nil
        public init(summary: PackSummary, stats: PackStats, content: ExternalPack?) {
            self.summary = summary
            self.stats = stats
            triggers = content?.entries.flatMap(\.triggers) ?? []
            patterns = content?.template?.patterns ?? []
        }
    }

    /// 계산 입력 한 벌 — `PackStore.impactLibrary()`가 **한 번의 큐 작업**에서 읽는다(목록·내 채움글·켜진 내장이 서로 맞는 시점)
    public struct Library: Equatable, Sendable {
        /// 읽은 때의 목록 revision — 순서 화면이 커밋에 `expectedRevision`으로 넘긴다(그 사이 바뀌면 `rechecked`)
        public var revision: Int
        public var order: [SnippetSourceSlot]
        /// 목록 순서
        public var packs: [Pack]
        /// 내 채움글 전체 stats — 키보드 로더와 같은 함수(`ActivePackBudget.userSnippetUsage`)
        public var userSnippets: PackStats
        /// 켜진 내장 팩 stats
        public var builtIn: PackStats
        public var userTriggers: [String]
        public var builtInTriggers: [String]
        /// 화면의 내 채움글 행 수(정규화 단축어가 같은 옛 중복은 한 행 — `UserSnippetBudget.displayEntries`)
        public var userSnippetCount: Int
        public var limits: PackBudgetLimits

        /// 내 채움글·켜진 내장 문구에서 stats를 센다 — `PackStore`의 판정 입력과 같은 함수
        public init(revision: Int, order: [SnippetSourceSlot], packs: [Pack], userEntries: [SnippetEntry],
                    builtInEntries: [SnippetEntry], limits: PackBudgetLimits) {
            let baseline = PackStore.baselineStats(user: userEntries, builtInEntries: builtInEntries, limits: limits)
            self.init(revision: revision, order: order, packs: packs, userSnippets: baseline.user, builtIn: baseline.builtIn,
                      userTriggers: userEntries.flatMap(\.triggers), builtInTriggers: builtInEntries.flatMap(\.triggers),
                      userSnippetCount: UserSnippetBudget.displayEntries(userEntries).count, limits: limits)
        }

        init(revision: Int, order: [SnippetSourceSlot], packs: [Pack], userSnippets: PackStats, builtIn: PackStats,
             userTriggers: [String], builtInTriggers: [String], userSnippetCount: Int, limits: PackBudgetLimits) {
            self.revision = revision
            self.order = order
            self.packs = packs
            self.userSnippets = userSnippets
            self.builtIn = builtIn
            self.userTriggers = userTriggers
            self.builtInTriggers = builtInTriggers
            self.userSnippetCount = userSnippetCount
            self.limits = limits
        }

        public func pack(_ id: String) -> Pack? { packs.first { $0.id == id } }

        /// 팩 이름 — 모르면 「이름 없는 팩」
        public func name(of id: String) -> String { pack(id)?.summary.name ?? PackNoticeCopy.unnamedPack }

        /// 틀을 화면에 — 그 틀이 어느 팩의 대표 틀(첫 `#틀` 원문)과 같으면 원문(`사자성어 {n}번`), 아니면 정규화 모양(`성어{n}번`).
        /// `preferring` 팩의 대표 틀을 먼저 본다
        public func display(_ pattern: TemplatePattern, preferring id: String? = nil) -> String {
            let candidates = (id.flatMap(pack).map { [$0] } ?? []) + packs
            for candidate in candidates {
                guard let format = candidate.summary.titleFormat,
                      (try? TemplatePatternSpec.parse(format).get()) == pattern else { continue }
                return format
            }
            return pattern.prefix + TemplatePatternSpec.placeholder + pattern.suffix
        }

        /// `PackStore.budgetInput`과 같은 모양 — 순서대로, 읽을 수 없는 팩은 뺀다(C5)
        func budgetInput(order: [SnippetSourceSlot], enabled: [String: Bool]) -> PackBudgetInput {
            let candidates = order.compactMap(\.packID).compactMap(pack).filter { !$0.isUnavailable }.map {
                ActivePackBudget.Candidate(id: $0.id, isEnabled: enabled[$0.id] ?? $0.summary.isEnabled, stats: $0.stats)
            }
            return PackBudgetInput(userSnippets: userSnippets, builtIn: builtIn, packs: candidates)
        }
    }
}

/// 팩 상세(2-E·U1)의 자리 — `PackImpact.standing(of:in:)`
public struct PackStanding: Equatable, Sendable {

    public enum PatternStatus: Equatable, Sendable {
        /// 이 팩이 쓴다 — 같은 틀을 가진 **아래** 팩(뒤 순서)이 있으면 그 id(목록 순서)
        case owned(sharedWith: [String])
        /// 위 팩이 같은 틀을 가져 이 팩 것은 안 뜬다(10-4)
        case outranked(by: String)
        /// 정적 단축어(내 채움글·문구형 팩·내장)가 먼저 떠서 이 틀은 안 뜬다(10-3) — 그 단축어 원문
        case shadowed(by: [String])
    }

    public struct Pattern: Equatable, Sendable {
        public var pattern: TemplatePattern
        /// 화면 모양 — 대표 틀이면 원문
        public var display: String
        public var status: PatternStatus
    }

    /// 위 줄이 같은 단축어를 가져 이 팩 것이 안 뜨는 단축어(U1 「뒤 순서」)
    public struct HiddenTrigger: Equatable, Sendable {
        /// 이 팩의 원문
        public var trigger: String
        public var owner: PackImpact.Source

        public init(trigger: String, owner: PackImpact.Source) {
            self.trigger = trigger
            self.owner = owner
        }
    }

    /// 번호형 — 틀 순서대로
    public var patterns: [Pattern]
    /// 문구형 — 이 팩의 단축어 순서대로
    public var hiddenTriggers: [HiddenTrigger]
}

/// 팩 상세 화면의 읽기 모델 — `PackStore.packDetail(_:)`
public struct PackDetail: Equatable, Sendable {

    /// 사용법 한 줄 — 친 단축어 → 칩 제목
    public struct Example: Equatable, Sendable {
        public var trigger: String
        public var title: String

        public init(trigger: String, title: String) {
            self.trigger = trigger
            self.title = title
        }
    }

    public var summary: PackSummary
    /// 권리 표기 — 읽을 수 없는 팩은 nil(변환본 안에만 있다)
    public var license: String?
    /// 번호형은 첫 항목 하나(대표 틀에 번호를 넣은 모양), 문구형은 처음 셋
    public var examples: [Example]
    /// 읽을 수 없는 팩은 nil
    public var standing: PackStanding?
    /// 이 화면에 이름이 나올 수 있는 팩들(목록 전체)
    var names: [String: String]

    public func name(of id: String) -> String { names[id] ?? PackNoticeCopy.unnamedPack }

    /// 팩 상세·완료 화면(4-M)이 함께 쓴다 — 둘 다 `PackStore.packDetail`이 `PackStanding`으로 부른다(화면 확인 N-2).
    /// - Parameters:
    ///   - hidden: 위 줄에 밀려 지금 안 뜨는 단축어(정규화) — 문구형은 **지금 뜨는 단축어부터** 고른다(화면 확인 O-1: 안 뜨는 단축어를
    ///     사용법으로 보이면 그대로 쳐도 이 팩 문구가 안 나온다). 항목 안에서도 안 밀린 단축어를 보이고, 다 밀린 항목은 뒤로 보낸다
    ///   - patterns: 번호형 틀의 자리(`PackStanding.patterns`) — **이 팩이 쓰는(`owned`) 틀부터** 고른다(N-2 — 위 팩이 같은 틀을 가졌거나
    ///     단축어가 가린 틀로 쳐도 이 팩 칩이 안 뜬다). 다 밀렸거나 자리를 모르면 대표 틀(첫 `#틀` 원문)
    static func examples(of pack: ExternalPack, hidden: Set<String> = [], patterns: [PackStanding.Pattern] = []) -> [Example] {
        if let template = pack.template {
            guard let first = template.items.first else { return [] }
            let owned = template.patterns.lazy.compactMap { pattern in patterns.first { $0.pattern == pattern } }
                .first { if case .owned = $0.status { true } else { false } }
            let format = owned?.display ?? template.titleFormat
            return [Example(trigger: format.replacingOccurrences(of: TemplatePatternSpec.placeholder, with: String(first.n)),
                            title: template.title(for: first))]
        }
        let ranked = pack.entries.map { entry -> (example: Example, isShown: Bool) in
            let shown = entry.triggers.first { !hidden.contains(SnippetEntry.normalizedTrigger($0)) }
            return (Example(trigger: shown ?? entry.primaryTrigger, title: entry.title), shown != nil)
        }
        return (ranked.filter(\.isShown) + ranked.filter { !$0.isShown }).prefix(3).map(\.example)
    }
}
