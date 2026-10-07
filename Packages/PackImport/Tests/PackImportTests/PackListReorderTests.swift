import Foundation
import Testing
import TadakDomain
@testable import PackImport

// R30 — 우선순위는 「외부 채움글」 목록 그 자리에서 길게 눌러 끌어 바꾼다(PDR `external-snippet-packs.md` R30, 순서 시트 2-D·2-G와 사전 안내 G3를 대신).
// 놓는 순간 저장(`PackStoreClient.reorder` → `PackStore` 커밋 게이트), 거부되면 끌기 전 자리로 되돌리고 알림, 받았는데 팩이 쉬게 되면 G1·G2.
// 저장은 실제 `PackStore`(임시 폴더)로 돈다 — 화면이 쓰는 `PackStoreClient`(메인 밖)로 부른다.

// MARK: - 시험 도구

private final class ReorderGenerations: PackGenerationWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var user = 0
    private var packs = 0
    var userSnippetsGeneration: Int { lock.withLock { user } }
    var packsGeneration: Int { lock.withLock { packs } }
    func setUserSnippetsGeneration(_ value: Int) { lock.withLock { user = value } }
    func setPacksGeneration(_ value: Int) { lock.withLock { packs = value } }
}

private final class ReorderSnippets: UserSnippetStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SnippetEntry] = []
    func entries() -> [SnippetEntry] { lock.withLock { stored } }
    func save(_ entries: [SnippetEntry]) -> Bool { lock.withLock { stored = entries; return true } }
}

private final class ReorderIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> String { lock.withLock { value += 1; return "pack\(value)" } }
}

/// 임시 폴더의 실제 저장소 — 작은 예산(needleChars 200)
private struct Store {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("packreorder-\(UUID().uuidString)", isDirectory: true)
    let store: PackStore
    var client: PackStoreClient { PackStoreClient(store: store) }

    init() {
        let ids = ReorderIDs()
        store = PackStore(libraryRoot: root.appendingPathComponent("library", isDirectory: true),
                          snapshotRoot: root.appendingPathComponent("snapshot", isDirectory: true),
                          generations: ReorderGenerations(), userSnippets: ReorderSnippets(),
                          builtInEntries: { _ in [] }, disabledBuiltIns: { [] }, notify: {}, makeID: { ids.next() },
                          limits: PackBudgetLimits(needleCount: 100, needleChars: 200, bytes: 2_000_000, items: 1_000))
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func imported(_ pack: ExternalPack) throws -> String {
        guard case .accepted(let accepted) = store.importPack(pack, source: .csv), let id = accepted.packID else {
            throw ImportFailed()
        }
        return id
    }

    private struct ImportFailed: Error {}
}

/// needleChars가 정확히 `chars`인 문구형 팩 — 단축어는 40자 이하로 나눈다
private func pack(_ name: String, chars: Int) -> ExternalPack {
    var entries: [SnippetEntry] = []
    var remaining = chars
    var index = 0
    while remaining > 0 {
        let length = min(40, remaining)
        let trigger = String(("\(name)\(index)" + String(repeating: "가", count: 40)).prefix(length))
        entries.append(SnippetEntry(trigger: trigger, title: name, body: "\(name) 본문 \(index)"))
        remaining -= length
        index += 1
    }
    return ExternalPack(name: name, license: "자체 작성", mode: .phrases, entries: entries)
}

// MARK: - 시험

@Suite("R30 — 목록에서 길게 눌러 끌어 우선순위 바꾸기")
struct PackListReorderTests {

    @Test("onMove의 (옮긴 자리, 놓은 자리) → 새 순서 — SwiftUI `move(fromOffsets:toOffset:)`와 같은 뜻(놓은 자리는 옮기기 전 기준)",
          arguments: [
            (IndexSet([0]), 3, ["B", "C", "A", "D"]), (IndexSet([3]), 0, ["D", "A", "B", "C"]),
            (IndexSet([1]), 4, ["A", "C", "D", "B"]), (IndexSet([1]), 1, ["A", "B", "C", "D"]),
            (IndexSet([1]), 2, ["A", "B", "C", "D"]), (IndexSet([0, 2]), 4, ["B", "D", "A", "C"]),
            (IndexSet([9]), 0, ["A", "B", "C", "D"]), (IndexSet([2]), 99, ["A", "B", "D", "C"])
          ])
    func moving(_ source: IndexSet, _ destination: Int, _ expected: [String]) {
        #expect(PackListReorder.moving(["A", "B", "C", "D"], from: source, to: destination) == expected)
    }

    @Test("★ 놓으면 바로 저장 — 「내 채움글」 줄도 끌린다(U1), 저장소 순서가 놓은 순서가 되고 알림은 없다")
    func dropSaves() async throws {
        let s = Store()
        defer { s.cleanup() }
        let a = try s.imported(pack("가", chars: 40))
        let b = try s.imported(pack("나", chars: 40))
        let original = s.store.order
        #expect(original == [.userSnippets, .pack(a), .pack(b)])
        // 「내 채움글」 줄을 맨 아래로 끌어 놓는다
        let proposed = PackListReorder.moving(original, from: IndexSet([0]), to: 3)
        #expect(proposed == [.pack(a), .pack(b), .userSnippets])

        let settled = await PackListReorder.commit(proposed, from: original, expectedRevision: s.store.revision, client: s.client)
        #expect(settled.committed)
        #expect(settled.order == proposed)
        #expect(settled.notice == nil, "쉬게 된 팩이 없으면 알릴 것이 없다")
        #expect(s.store.order == proposed, "저장소에 바로 들어갔다")
    }

    @Test("제자리에 놓으면 저장하지 않는다 — revision이 오르지 않는다")
    func dropInPlaceSkipsSave() async throws {
        let s = Store()
        defer { s.cleanup() }
        _ = try s.imported(pack("가", chars: 40))
        let original = s.store.order
        let revision = s.store.revision
        let settled = await PackListReorder.commit(PackListReorder.moving(original, from: IndexSet([1]), to: 1), from: original,
                                                   expectedRevision: revision, client: s.client)
        #expect(!settled.committed && settled.order == original && settled.notice == nil)
        #expect(s.store.revision == revision)
    }

    @Test("★ 거부되면 끌기 전 자리로 되돌리고 알린다 — 그 사이 팩이 지워져 순서가 맞지 않음(F2)")
    func rejectedRevertsAndNotifies() async throws {
        let s = Store()
        defer { s.cleanup() }
        let a = try s.imported(pack("가", chars: 40))
        let b = try s.imported(pack("나", chars: 40))
        let original = s.store.order
        let revision = s.store.revision
        let proposed = PackListReorder.moving(original, from: IndexSet([2]), to: 0)
        #expect(proposed == [.pack(b), .userSnippets, .pack(a)])
        // 끄는 동안 다른 곳(팩 상세)에서 b를 지웠다
        #expect(s.store.deletePack(b).isAccepted)
        let after = s.store.order

        let settled = await PackListReorder.commit(proposed, from: original, expectedRevision: revision, client: s.client)
        #expect(settled.committed)
        #expect(settled.order == original, "화면은 끌기 전 자리로 돌아간다")
        #expect(settled.notice?.reason == .changedMeanwhile)
        #expect(settled.notice?.isRejection == true)
        #expect(s.store.order == after, "거부는 저장본을 바꾸지 않는다")
    }

    @Test("★ 받았는데 팩이 쉬게 되면 G1(이름 있는 알림) — 쉬던 팩을 맨 위로 끌어 올리면 아래 팩이 한도 밖으로 밀린다")
    func restedPackIsNotified() async throws {
        let s = Store()
        defer { s.cleanup() }
        // 한도 needleChars 200 — 가(70)·나(50)·다(60) = 180은 들어간다
        let a = try s.imported(pack("가", chars: 70))
        let b = try s.imported(pack("나", chars: 50))
        let c = try s.imported(pack("다", chars: 60))
        // 내 채움글 30자를 저장하면 맨 아래 「다」가 한도 밖으로 — 받고 쉬게 한다(R14)
        guard case .accepted(let saved) = s.store.saveUserSnippet(
            SnippetEntry(trigger: String(repeating: "내", count: 30), title: "내 문구", body: "본문"), editing: nil) else {
            Issue.record("내 채움글 저장은 외부 팩 때문에 막히지 않는다")
            return
        }
        #expect(saved.newlyExcluded == [c])
        let original = s.store.order
        #expect(original == [.userSnippets, .pack(a), .pack(b), .pack(c)])

        // 「다」를 「가」 위로 — 다(60)·가(70) + 내 채움글 30 = 160, 「나」(50)가 밀린다
        let proposed = PackListReorder.moving(original, from: IndexSet([3]), to: 1)
        #expect(proposed == [.userSnippets, .pack(c), .pack(a), .pack(b)])
        let settled = await PackListReorder.commit(proposed, from: original, expectedRevision: s.store.revision, client: s.client)
        #expect(settled.committed && settled.order == proposed, "순서 바꾸기는 거부가 없다 — 놓은 자리에 남는다")
        let notice = try #require(settled.notice)
        #expect(notice.reason == .packRested)
        #expect(!notice.isRejection)
        #expect(notice.packIDs == [b])
        #expect(notice.message == "대신 「나」가 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요.")
        #expect(notice.actions.isEmpty, "갈 곳 없는 「팩 우선순위 바꾸기」 버튼은 없다 — 되돌리려면 다시 끈다")
        #expect(s.store.order == proposed)
    }

    @Test("둘 이상 쉬게 되면 G2 — 「첫 팩」 외 n개")
    func restedPacksAreNotified() async throws {
        let s = Store()
        defer { s.cleanup() }
        // 가(30)·나(30)·다(135) = 195는 들어간다. 내 채움글 40자를 저장하면 「다」가 쉬고, 「다」를 맨 위로 올리면 가·나가 둘 다 밀린다
        let a = try s.imported(pack("가", chars: 30))
        let b = try s.imported(pack("나", chars: 30))
        let c = try s.imported(pack("다", chars: 135))
        guard case .accepted(let saved) = s.store.saveUserSnippet(
            SnippetEntry(trigger: String(repeating: "내", count: 40), title: "내 문구", body: "본문"), editing: nil) else {
            Issue.record("내 채움글 저장은 외부 팩 때문에 막히지 않는다")
            return
        }
        #expect(saved.newlyExcluded == [c])
        let original = s.store.order
        let proposed = PackListReorder.moving(original, from: IndexSet([3]), to: 0)
        #expect(proposed == [.pack(c), .userSnippets, .pack(a), .pack(b)])

        let settled = await PackListReorder.commit(proposed, from: original, expectedRevision: s.store.revision, client: s.client)
        #expect(settled.order == proposed)
        let notice = try #require(settled.notice)
        #expect(notice.reason == .packsRested)
        #expect(notice.packIDs == [a, b])
        #expect(notice.message == "대신 「가」 외 1개 팩이 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 팩 목록에서 확인해 주세요.")
    }
}
