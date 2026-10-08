import Foundation
import TadakDomain

/// 틀 칸 검사(시안 5-C, PDR 10-1·10-2·10-3·10-4, AC-21~24) — 칸마다 빨강(거부)·주황(알림)·통과.
///
/// - **빨강 = 가져올 수 없다:** 10-1 스키마(`TemplatePatternSpec.parse` — 접두 2자 이상·숫자 끝/숫자뿐·`{n}` 한 번·접미·예약 접미·literal 40자·
///   개행)와 10-2 성경 전체 n(`TemplatePatternSpec.firstBibleCollision` — 1~9,999 전부). 최종 컴파일(`PackCompiler`)이 **같은 두 함수**로 다시 막는다.
/// - **주황 = 알림(거부 아님):** 위 팩이 같은 틀을 가짐(10-4) · 정적 단축어가 가림(10-3). 팩 상세(2-E)와 **같은 계산**(`PackImpact.standing`)을
///   「새 팩을 목록 맨 아래에 켠 채로 넣은」(U2) 가상 목록에 돌린다. 같은 이름 팩을 바꾸는 자리면(U3) 그 팩 자리에 넣는다.
///
/// 성경 검사가 틀 하나에 9,999 × 표기 3가지라 **메인에서 부르지 않는다**(`perform`). 입력하는 동안 화면이 기다렸다가(디바운스) 부른다.
public enum PackTemplateReview {

    public enum Status: Equatable, Sendable {
        /// 빈 칸 — 건너뛴다
        case empty
        /// 빨강 — 가져올 수 없다
        case invalid(TemplatePatternSpec.Failure)
        case ok
        /// 주황 — 위에 있는 팩(id)이 같은 틀을 가진다(10-4)
        case outranked(by: String)
        /// 주황 — 정적 단축어(원문)가 이 틀이 만드는 입력의 끝과 같아 먼저 뜬다(10-3). 주인은 첫 단축어의 주인(모르면 nil)
        case shadowed(triggers: [String], owner: PackImpact.Source?)

        /// 「가져오기」를 막는가 — 빨강만
        public var blocksImport: Bool {
            if case .invalid = self { return true }
            return false
        }
    }

    /// 가상 목록에 넣는 새 팩의 자리 id — 실제 팩 id(무작위 UUID)와 겹치지 않는다
    static let draftID = "import-draft"

    /// - Parameters:
    ///   - library: 지금 목록(`PackStore.impactLibrary`) — nil이면 주황 알림 없이 빨강·통과만
    ///   - replacing: 같은 이름 팩(U3 「바꾸기」 대상) — 그 자리에서 계산한다. nil이면 목록 맨 아래(U2)
    public static func review(_ templates: [String], library: PackImpact.Library?, replacing: String?) -> [Status] {
        var statuses: [Status] = []
        var patterns: [TemplatePattern] = []
        for raw in templates {
            let cleaned = PackCompiler.cleanedTemplate(raw)
            guard !cleaned.isEmpty else {
                statuses.append(.empty)
                continue
            }
            switch TemplatePatternSpec.parse(cleaned) {
            case .failure(let failure):
                statuses.append(.invalid(failure))
            case .success(let pattern):
                if let n = TemplatePatternSpec.firstBibleCollision(pattern, raw: cleaned) {
                    statuses.append(.invalid(.collidesWithBible(n: n)))
                } else {
                    statuses.append(.ok)
                    if !patterns.contains(pattern) { patterns.append(pattern) }
                }
            }
        }
        guard let library, !patterns.isEmpty else { return statuses }

        let placed = placing(patterns, in: library, replacing: replacing)
        guard let standing = PackImpact.standing(of: draftID, in: placed) else { return statuses }
        let owners = triggerOwners(in: placed)
        var byPattern: [TemplatePattern: Status] = [:]
        for item in standing.patterns {
            switch item.status {
            case .owned: byPattern[item.pattern] = .ok
            case .outranked(let owner): byPattern[item.pattern] = .outranked(by: owner)
            case .shadowed(let triggers):
                byPattern[item.pattern] = .shadowed(triggers: triggers,
                                                    owner: triggers.first.flatMap { owners[SnippetEntry.normalizedTrigger($0)] })
            }
        }
        return zip(templates, statuses).map { raw, status in
            guard status == .ok, case .success(let pattern) = TemplatePatternSpec.parse(PackCompiler.cleanedTemplate(raw)) else { return status }
            return byPattern[pattern] ?? .ok
        }
    }

    /// `review`를 전역 큐에서 — 화면(메인)은 `await` 동안 멈추지 않는다(`PackImportSession.perform`과 같은 이유)
    public static func perform(_ templates: [String], library: PackImpact.Library?, replacing: String?,
                               queue: DispatchQueue = .global(qos: .userInitiated)) async -> [Status] {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: review(templates, library: library, replacing: replacing)) }
        }
    }

    // MARK: - 안

    /// 새 팩(틀만 — 소유·가림 계산은 단축어·틀만 본다)을 켠 채로 맨 아래 또는 바꿀 팩 자리에
    private static func placing(_ patterns: [TemplatePattern], in library: PackImpact.Library, replacing: String?) -> PackImpact.Library {
        let summary = PackSummary(id: draftID, name: nil, mode: .numbered, itemCount: 0, titleFormat: nil, isEnabled: true, status: .on)
        let content = ExternalPack(name: "", license: "", mode: .numbered,
                                   template: PackTemplate(patterns: patterns, titleFormat: "", items: []))
        let pack = PackImpact.Pack(summary: summary, stats: .zero, content: content)
        var placed = library
        if let replacing, let packIndex = placed.packs.firstIndex(where: { $0.id == replacing }),
           let slotIndex = placed.order.firstIndex(of: .pack(replacing)) {
            placed.packs[packIndex] = pack
            placed.order[slotIndex] = .pack(draftID)
        } else {
            placed.packs.append(pack)
            placed.order.append(.pack(draftID))
        }
        return placed
    }

    /// 가림 단축어의 주인 — `standing`과 같은 포함 판정(지금 예산 + 새 팩은 켠 것으로)으로 키보드 매칭 순서의 첫 주인
    private static func triggerOwners(in library: PackImpact.Library) -> [String: PackImpact.Source] {
        let input = library.budgetInput(order: library.order, enabled: [:])
        var included = Set(ActivePackBudget.evaluate(baseline: input.baseline, packs: input.packs, limits: library.limits).included)
        included.insert(draftID)
        let owners = PackImpact.triggerOwners(of: library, order: library.order,
                                              included: library.order.compactMap(\.packID).filter(included.contains))
        return Dictionary(owners.map { ($0.0, $0.1.source) }, uniquingKeysWith: { first, _ in first })
    }
}
