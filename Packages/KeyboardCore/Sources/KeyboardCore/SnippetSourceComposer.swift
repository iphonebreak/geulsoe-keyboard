import TadakDomain

/// 채움글 매처의 입력을 **U1 순서 목록대로** 합친다(PDR `external-snippet-packs.md` 10-3·10-4, E표 U1).
///
/// - 문구(`entries`): 순서 목록의 각 줄 — 「내 채움글」 줄은 사용자 문구, 팩 줄은 문구형 팩의 항목 — 을 **위에서부터** 잇고,
///   그 뒤에 내장 팩. `SnippetMatcher`는 「정규화 길이가 긴 단축어 → 같으면 앞선 항목」이라 **같은 단축어는 위의 줄이 이긴다**.
/// - 템플릿: 번호형 팩을 같은 순서로 — `PackTemplateMatcher`가 목록 순서로 소유권을 정한다(10-4).
///
/// 순서에 있지만 실리지 않은 팩(예산 밖·꺼짐 — 키보드 로더가 이미 뺐다)은 건너뛴다. 「내 채움글」 줄이 순서에 없으면 맨 위에
/// 둔다 — 순서 데이터가 비거나 손상돼도 사용자 문구를 잃지 않는다. 외부 팩이 없으면 결과는 지금과 같다(내 채움글 → 내장).
///
/// U7(길게 눌러 후보 고르기)은 같은 `entries`·템플릿 순서를 그대로 쓰면 된다 — 순서 정보는 배열 순서에 남아 있다.
public enum SnippetSourceComposer {

    public struct Sources: Sendable {
        public var entries: [SnippetEntry]
        /// 번호형 팩이 없으면 nil
        public var templates: PackTemplateMatcher?
    }

    public static func compose(
        order: [SnippetSourceSlot], userEntries: [SnippetEntry], packs: [String: ExternalPack], builtIn: [SnippetEntry]
    ) -> Sources {
        let slots = order.contains(.userSnippets) ? order : [.userSnippets] + order
        var entries: [SnippetEntry] = []
        var templateSources: [PackTemplateMatcher.Source] = []
        var seenPacks = Set<String>()
        for slot in slots {
            switch slot {
            case .userSnippets:
                entries += userEntries
            case .pack(let id):
                guard seenPacks.insert(id).inserted, let pack = packs[id] else { continue }
                entries += pack.entries
                if let template = pack.template {
                    templateSources.append(PackTemplateMatcher.Source(id: id, template: template))
                }
            }
        }
        entries += builtIn
        return Sources(entries: entries, templates: templateSources.isEmpty ? nil : PackTemplateMatcher(sources: templateSources))
    }
}
