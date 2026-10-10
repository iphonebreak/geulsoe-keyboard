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
/// U7(길게 눌러 후보 고르기)은 같은 `entries`·템플릿 순서를 그대로 쓴다 — 순서 정보는 배열 순서에 남아 있다. 목록 행의 **출처**만
/// 배열 순서로는 알 수 없어 같은 자리에서 `origins`(줄 구간 표)를 함께 만든다(`SnippetEntry` 저장 스키마는 건드리지 않는다).
public enum SnippetSourceComposer {

    public struct Sources: Sendable {
        public var entries: [SnippetEntry]
        /// 번호형 팩이 없으면 nil
        public var templates: PackTemplateMatcher?
        /// U7 — 각 항목·템플릿 팩이 어느 줄(내 채움글·팩 이름·내장 팩)의 것인지. 목록 행 표시 전용 — 로그·분석 금지
        public var origins: SnippetOrigins
    }

    /// 켜진 내장 문구 팩 하나 — 목록 행의 출처(「국가 상징문」·「인사·상용구」)를 알려고 팩 단위로 받는다
    public struct BuiltInGroup: Sendable {
        /// `SnippetPack.anthem`·`SnippetPack.greetings`
        public var packID: String
        public var entries: [SnippetEntry]

        public init(packID: String, entries: [SnippetEntry]) {
            self.packID = packID
            self.entries = entries
        }
    }

    /// 내장 문구를 한 덩어리로 받는 옛 경로 — 결과 `entries`·`templates`는 같고, 내장 항목의 출처만 id 없는 내장(`.builtIn(id: "")`)이다
    public static func compose(
        order: [SnippetSourceSlot], userEntries: [SnippetEntry], packs: [String: ExternalPack], builtIn: [SnippetEntry]
    ) -> Sources {
        compose(order: order, userEntries: userEntries, packs: packs, builtInGroups: [BuiltInGroup(packID: "", entries: builtIn)])
    }

    public static func compose(
        order: [SnippetSourceSlot], userEntries: [SnippetEntry], packs: [String: ExternalPack], builtInGroups: [BuiltInGroup]
    ) -> Sources {
        let slots = order.contains(.userSnippets) ? order : [.userSnippets] + order
        var entries: [SnippetEntry] = []
        var origins = SnippetOrigins()
        var templateSources: [PackTemplateMatcher.Source] = []
        var seenPacks = Set<String>()
        var userAdded = false
        for slot in slots {
            switch slot {
            case .userSnippets:
                // 겹친 「내 채움글」 줄은 한 번만 — 로더가 그런 manifest를 손상으로 거절하지만 여기서도 막는다(검증 C3)
                guard !userAdded else { continue }
                userAdded = true
                entries += userEntries
                origins.appendEntries(count: userEntries.count, origin: .user)
            case .pack(let id):
                guard seenPacks.insert(id).inserted, let pack = packs[id] else { continue }
                entries += pack.entries
                origins.appendEntries(count: pack.entries.count, origin: .pack(name: pack.name))
                if let template = pack.template {
                    templateSources.append(PackTemplateMatcher.Source(id: id, template: template))
                    origins.setTemplate(sourceID: id, origin: .pack(name: pack.name))
                }
            }
        }
        for group in builtInGroups {
            entries += group.entries
            origins.appendEntries(count: group.entries.count, origin: .builtIn(id: group.packID))
        }
        return Sources(entries: entries, templates: templateSources.isEmpty ? nil : PackTemplateMatcher(sources: templateSources),
                       origins: origins)
    }
}
