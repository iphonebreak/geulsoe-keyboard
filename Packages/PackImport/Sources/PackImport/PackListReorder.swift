import Foundation
import TadakDomain

/// 「외부 채움글」 목록 **그 자리에서** 길게 눌러 끌어 우선순위를 바꾼다(PDR `external-snippet-packs.md` R30 — 순서 시트 2-D·2-G와
/// 사전 안내 G3를 대신한다. U4 끌기 원칙은 그대로, 자리만 목록으로). 「내 채움글 (우선순위)」 줄도 끌린다(U1).
///
/// **놓는 순간 저장한다** — 직렬 경로 `PackStoreClient.reorder` → `PackStore` 커밋 게이트 그대로다. 거부되면 **끌기 전 자리로 되돌리고**
/// 사유별로 알린다. 받았는데 팩이 쉬게 되면 G1·G2로 알린다 — 미리 알려 주는 단계가 없으니 되돌리려면 다시 끌면 된다.
/// 화면(`onMove`)은 여기서 돌려준 순서·알림을 그대로 보인다 — 규칙을 화면에 두면 `swift test`가 닿지 않는다.
public enum PackListReorder {

    /// 끌어 놓은 뒤의 순서 — `onMove(perform:)`가 주는 (옮긴 줄들의 자리, 놓은 자리)를 그대로 받는다. 놓은 자리는 **옮기기 전** 목록 기준
    /// 오프셋이다(SwiftUI `move(fromOffsets:toOffset:)`와 같은 뜻 — 패키지는 SwiftUI를 링크하지 않아 같은 규칙을 여기 둔다)
    public static func moving<Element>(_ items: [Element], from source: IndexSet, to destination: Int) -> [Element] {
        let offsets = source.filter { items.indices.contains($0) }
        guard !offsets.isEmpty else { return items }
        let target = min(max(destination, 0), items.count)
        var rest = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: offsets.map { items[$0] }, at: target - offsets.filter { $0 < target }.count)
        return rest
    }

    /// 놓은 결과 — 화면이 보일 순서와 알림
    public struct Settlement: Equatable, Sendable {
        /// 받았으면 놓은 순서, 거부면 **끌기 전 순서**(원래 자리로 되돌린다)
        public let order: [SnippetSourceSlot]
        /// 거부면 언제나 있다(사유별). 받았으면 팩이 쉬게 됐을 때만(G1·G2)
        public let notice: PackChangeNotice?
        /// 저장소에 물었나 — 제자리에 놓았으면 거짓(저장하지 않았다). 참이면 화면은 목록(쉬는 중 표시)을 다시 읽는다
        public let committed: Bool
    }

    /// 놓은 순서를 저장한다. 끌기 전과 같으면(제자리에 놓음) 저장하지 않는다
    /// - Parameters:
    ///   - proposed: 놓은 뒤 순서(`moving`)
    ///   - original: 끌기 전 순서 — 거부되면 이 순서로 돌아간다
    ///   - expectedRevision: 목록을 읽을 때의 revision — 그 사이 바뀌었으면 다시 판정했다고 알린다(AC-3)
    public static func commit(_ proposed: [SnippetSourceSlot], from original: [SnippetSourceSlot],
                              expectedRevision: Int?, client: PackStoreClient) async -> Settlement {
        guard proposed != original else { return Settlement(order: original, notice: nil, committed: false) }
        let outcome = await client.reorder(proposed, expectedRevision: expectedRevision)
        return Settlement(order: outcome.isAccepted ? proposed : original, notice: outcome.notice, committed: true)
    }
}
