import Foundation
import Testing
import KeyboardCore
import TadakDomain
@testable import PackImport

// 검증 F-8 — 화면이 메인 밖으로 넘기는 계산 둘(순서 화면 G3 안내 · 붙여넣기 개요)은 **부른 작업이 취소됐으면 결과를 버린다**(nil).
// 화면은 `.task(id:)`로 부르므로 값이 바뀌면 앞 작업이 취소된다 — 늦게 온 앞 결과가 새 값의 표시를 덮지 않는다.
// 멈춘 큐(`suspend`)로 결과가 오기 전에 취소를 확정해 순서를 고정한다.

private func pausedQueue() -> DispatchQueue {
    let queue = DispatchQueue(label: "pack-background-test")
    queue.suspend()
    return queue
}

@Suite("검증 F-8 — 메인 밖 계산의 늦은 결과")
struct PackBackgroundWorkTests {

    @Test("붙여넣기 개요 — 줄 수(끝 줄바꿈은 세지 않는다)·칸 나누기(하나로 정해질 때만)")
    func pasteOverview() {
        #expect(PackPasteOverview.of("번호\t제목\t본문\n1\t가\t나") == PackPasteOverview(lines: 2, delimiter: .tab))
        #expect(PackPasteOverview.of("번호\t제목\t본문\n1\t가\t나\n").lines == 2)
        #expect(PackPasteOverview.of("한 줄").lines == 1)
    }

    @Test("★ 붙여넣기 개요 — 취소되지 않았으면 그 글의 값, 기다리는 사이 취소됐으면 nil(늦은 「n줄」이 새 글을 덮지 않는다)")
    func pasteOverviewDropsLateResult() async {
        let text = "번호\t제목\t본문\n1\t가\t나\n2\t다\t라\n"
        #expect(await PackPasteOverview.perform(text) == PackPasteOverview.of(text))

        let queue = pausedQueue()
        let task = Task { await PackPasteOverview.perform(text, queue: queue) }
        task.cancel()
        queue.resume()
        #expect(await task.value == nil)
    }

    @Test("★ 순서 화면 G3 안내 — 메인 밖 결과는 `of`와 같고, 기다리는 사이 취소됐으면 nil(늦은 안내가 새 순서를 덮지 않는다)")
    func impactDropsLateResult() async {
        let pack = ExternalPack(name: "회사 상용구", license: "자체 작성", mode: .phrases,
                                entries: [SnippetEntry(trigger: "주소", title: "회사 주소", body: "예시 주소")])
        let library = PackImpact.Library(
            revision: 1, order: [.userSnippets, .pack("a")],
            packs: [PackImpact.Pack(summary: PackSummary(id: "a", name: pack.name, mode: .phrases, itemCount: 1, titleFormat: nil,
                                                         isEnabled: true, status: .on),
                                    stats: PackStats.of(pack: pack), content: pack)],
            userEntries: [SnippetEntry(trigger: "주소", title: "내 주소", body: "내 예시 주소")], builtInEntries: [], limits: .candidate)
        let proposal = PackImpact.Proposal(order: [.pack("a"), .userSnippets])
        let direct = PackImpact.of(proposal, in: library)
        #expect(!direct.triggerOwnerChanges.isEmpty, "「주소」 주인이 바뀌는 순서 — 비어 있지 않은 안내로 본다")
        #expect(await PackImpact.perform(proposal, in: library) == direct)

        let queue = pausedQueue()
        let task = Task { await PackImpact.perform(proposal, in: library, queue: queue) }
        task.cancel()
        queue.resume()
        #expect(await task.value == nil)
    }
}
