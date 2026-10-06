import Foundation
import Testing
import TadakDomain
@testable import TadakData

// 외부 채움글 1-b — 앱 `PackStore`(직렬 큐·커밋 게이트·snapshot·GC)와 키보드 `PackSnapshotLoader`(9-4 순차 로드·8절 재시도).
// PDR `docs/design-reviews/external-snippet-packs.md` AC-2~9·AC-26. 파일 시스템은 임시 폴더를 주입한다.

// MARK: - 시험 도구

private final class MemoryGenerations: PackGenerationWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var user = 0
    private var packs = 0
    /// 읽을 때마다 부르는 갈고리 — 「읽는 도중 앱이 커밋」을 흉내 낸다
    var onRead: (@Sendable () -> Void)?

    var userSnippetsGeneration: Int { onRead?(); return lock.withLock { user } }
    var packsGeneration: Int { lock.withLock { packs } }
    func setUserSnippetsGeneration(_ value: Int) { lock.withLock { user = value } }
    func setPacksGeneration(_ value: Int) { lock.withLock { packs = value } }
}

private final class MemorySnippets: UserSnippetStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SnippetEntry]
    init(_ entries: [SnippetEntry] = []) { stored = entries }
    func entries() -> [SnippetEntry] { lock.withLock { stored } }
    func save(_ entries: [SnippetEntry]) -> Bool { lock.withLock { stored = entries }; return true }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

private final class DisabledBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [String] = []
    var current: [String] { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
}

/// 읽은 파일 수를 세고, 원하면 특정 읽기에서 갈고리를 부르는 리더
private final class CountingReader: PackFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private let base = SystemPackFileReader()
    private(set) var reads: [String] = []
    var beforeRead: (@Sendable (URL) -> Void)?

    func size(of url: URL) -> Int? { base.size(of: url) }
    func read(_ url: URL) -> Data? {
        beforeRead?(url)
        lock.withLock { reads.append(url.lastPathComponent) }
        return base.read(url)
    }
    var packReads: [String] { reads.filter { $0 != "manifest.json" } }
}

private struct Sandbox {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("packstore-\(UUID().uuidString)", isDirectory: true)
    var library: URL { root.appendingPathComponent("library", isDirectory: true) }
    var snapshot: URL { root.appendingPathComponent("snapshot", isDirectory: true) }

    func cleanup() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: snapshot.path)
        if let names = try? FileManager.default.contentsOfDirectory(atPath: snapshot.path) {
            for name in names {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: snapshot.appendingPathComponent(name).path)
            }
        }
        try? FileManager.default.removeItem(at: root)
    }

    func generationNames() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: snapshot.path)) ?? []).filter { $0.hasPrefix("g") }.sorted()
    }
}

/// 작은 예산 — needleChars 200, 바이트 넉넉
private let small = PackBudgetLimits(needleCount: 100, needleChars: 200, bytes: 2_000_000, items: 1_000)

private func entry(_ trigger: String, body: String = "본문") -> SnippetEntry {
    SnippetEntry(trigger: trigger, title: trigger, body: body)
}

/// needleChars가 정확히 `chars`인 문구형 팩 — 단축어는 40자 이하로 나눈다(필드 상한, 키보드가 다시 본다)
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
    return ExternalPack(name: name, license: "자체", mode: .phrases, entries: entries)
}

private struct Harness {
    let sandbox = Sandbox()
    let generations = MemoryGenerations()
    let user: MemorySnippets
    let disabled = DisabledBox()
    let builtIn: [SnippetEntry]
    let limits: PackBudgetLimits
    let ids = Counter()
    let notifications = Counter()
    let store: PackStore

    init(user: [SnippetEntry] = [], builtIn: [SnippetEntry] = [], limits: PackBudgetLimits = small) {
        self.user = MemorySnippets(user)
        self.builtIn = builtIn
        self.limits = limits
        let ids = self.ids, notifications = self.notifications, disabled = self.disabled, builtIn = builtIn
        store = PackStore(
            libraryRoot: sandbox.library, snapshotRoot: sandbox.snapshot, generations: generations, userSnippets: self.user,
            builtInEntries: { off in off.contains("anthem") ? [] : builtIn }, disabledBuiltIns: { disabled.current },
            notify: { _ = notifications.next() }, makeID: { "pack\(ids.next())" }, limits: limits)
    }

    func loader(reader: any PackFileReading = SystemPackFileReader()) -> PackSnapshotLoader {
        let user = self.user
        return PackSnapshotLoader(snapshotRoot: sandbox.snapshot, generations: generations,
                                  userSnippets: { user.entries() }, reader: reader, limits: limits)
    }

    func load(reader: any PackFileReading = SystemPackFileReader()) -> PackSnapshotLoader.Result {
        loader(reader: reader).load(builtIn: disabled.current.contains("anthem") ? [] : builtIn)
    }

    func manifest() throws -> PackSnapshotManifest {
        let url = sandbox.snapshot.appendingPathComponent("g\(generations.packsGeneration)/manifest.json")
        return try JSONDecoder().decode(PackSnapshotManifest.self, from: Data(contentsOf: url))
    }

    func importedID(_ result: PackStore.CommitResult) throws -> String {
        guard case .accepted(let accepted) = result, let id = accepted.packID else {
            Issue.record("가져오기가 받아져야 한다: \(result)")
            throw CancellationError()
        }
        return id
    }

    /// 앱을 거치지 않고 snapshot을 직접 만든다(옛 저장본·손상 흉내). bytes를 덮어쓰면 manifest가 거짓말을 한다
    func craft(generation: Int, order: [SnippetSourceSlot]? = nil, packs: [(String, ExternalPack)],
               lieBytes: [String: Int] = [:], packSchema: Int = StoredExternalPack.schemaVersion,
               manifestSchema: Int = PackSnapshotManifest.schemaVersion) throws {
        let directory = sandbox.snapshot.appendingPathComponent("g\(generation)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var items: [PackSnapshotManifest.Item] = []
        for (id, pack) in packs {
            var stored = StoredExternalPack(packID: id, source: .csv, pack: pack)
            stored.schema = packSchema
            let data = try JSONEncoder().encode(stored)
            try data.write(to: directory.appendingPathComponent("\(id).json"))
            items.append(.init(id: id, file: "\(id).json", bytes: lieBytes[id] ?? data.count, stats: .zero))
        }
        var manifest = PackSnapshotManifest(generation: generation, userSnippetsRevision: generations.userSnippetsGeneration,
                                            order: order ?? ([.userSnippets] + packs.map { .pack($0.0) }), packs: items)
        manifest.schema = manifestSchema
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        generations.setPacksGeneration(generation)
    }
}

// MARK: - 앱 PackStore

@Suite("외부 채움글 1-b — PackStore (AC-2~6)")
struct PackStoreTests {

    @Test("★ 가져오기 → 맨 아래·켬, snapshot g1(manifest 마지막)·packsGeneration 1·알림 1 → 키보드가 그 팩을 싣는다")
    func importPublishesSnapshot() throws {
        let h = Harness(user: [entry("내문구")])
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("상용", chars: 20), source: .csv))
        #expect(h.store.order == [.userSnippets, .pack(id)])
        #expect(h.generations.packsGeneration == 1)
        #expect(h.notifications.next() == 2, "알림 1회(이 호출이 2번째)")
        let manifest = try h.manifest()
        #expect(manifest.order == [.userSnippets, .pack(id)])
        #expect(manifest.packs.map(\.id) == [id])
        let loaded = h.load()
        #expect(loaded.dropped == nil)
        #expect(loaded.includedPackIDs == [id])
        #expect(loaded.packs[id] == pack("상용", chars: 20))
        #expect(loaded.userEntries == [entry("내문구")])
    }

    @Test("★ AC-3 — 판정은 넘겨받은 최종 DTO로 한다(stats를 여기서 다시 센다)")
    func finalDTOIsJudged() {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        #expect(h.store.importPack(pack("작음", chars: 150), source: .csv).isAccepted)
        // 폼에서 단축어를 늘린 최종 DTO — 예산 밖이라 거부(자신 제외)
        guard case .rejected(.gate(.packExcluded), _) = h.store.importPack(pack("늘림", chars: 60), source: .csv) else {
            Issue.record("최종 DTO 기준으로 거부돼야 한다"); return
        }
    }

    @Test("★ AC-3 — 미리보기 뒤 큐에서 revision이 바뀌면 지금 저장본으로 다시 판정하고 rechecked를 알린다")
    func revisionChangeRejudges() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let seen = h.store.revision
        #expect(h.store.importPack(pack("먼저", chars: 150), source: .csv).isAccepted)     // 그사이 다른 변경
        let result = h.store.importPack(pack("나중", chars: 60), source: .csv, expectedRevision: seen)
        guard case .rejected(.gate(.packExcluded), let rechecked) = result else {
            Issue.record("지금 저장본(먼저 팩 포함)으로 판정해 거부해야 한다: \(result)"); return
        }
        #expect(rechecked)
        guard case .accepted(let accepted) = h.store.importPack(pack("작은", chars: 10), source: .csv,
                                                                 expectedRevision: h.store.revision) else {
            Issue.record("받아야 한다"); return
        }
        #expect(!accepted.rechecked)
    }

    @Test("★ AC-4 — 내 문구 저장이 baseline 초과면 거부, 외부 팩 때문에는 막히지 않는다")
    func userSaveBaseline() {
        let h = Harness(user: [entry(String(repeating: "가", count: 190))])
        defer { h.sandbox.cleanup() }
        guard case .rejected(.gate(.baselineOverLimit), _) = h.store.saveUserSnippet(
            entry(String(repeating: "나", count: 20)), editing: nil) else {
            Issue.record("baseline 초과 — 거부"); return
        }
        let h2 = Harness(user: [entry(String(repeating: "가", count: 100))])
        defer { h2.sandbox.cleanup() }
        #expect(h2.store.importPack(pack("팩", chars: 90), source: .csv).isAccepted)
        let result = h2.store.saveUserSnippet(entry(String(repeating: "나", count: 50)), editing: nil)
        guard case .accepted(let accepted) = result else { Issue.record("외부 팩 때문에 막지 않는다"); return }
        #expect(accepted.newlyExcluded == ["pack1"], "밀린 팩은 경고")
    }

    @Test("★ AC-4 — 저장 결과 예산 밖이 된 외부 팩은 snapshot에서 쉬고, 키보드도 싣지 않는다")
    func pushedOutPackRestsInSnapshot() throws {
        let h = Harness(user: [entry(String(repeating: "가", count: 100))])
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("팩", chars: 90), source: .csv))
        #expect(h.store.saveUserSnippet(entry(String(repeating: "나", count: 50)), editing: nil).isAccepted)
        #expect(try h.manifest().packs.isEmpty)
        #expect(try h.manifest().order == [.userSnippets])
        #expect(h.load().packs[id] == nil)
        // 내 문구를 지우면 켜져 있던 팩이 결정적으로 다시 들어온다(자동 재활성이 아니라 함수 결과)
        #expect(h.store.deleteUserSnippet(entry(String(repeating: "나", count: 50))).isAccepted)
        #expect(h.load().includedPackIDs == [id])
    }

    @Test("★ AC-5 — 옛 초과본은 지우지 않는다: 앱은 초과를 알고, 키보드는 저장 순서대로 한도까지만·외부 팩 0")
    func legacyOverflowKept() throws {
        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }  // 30 × 10자 = 300 > 200
        let h = Harness(user: legacy)
        defer { h.sandbox.cleanup() }
        #expect(!h.store.evaluation().baselineOverflow.isEmpty)
        h.store.maintain()
        #expect(h.user.entries() == legacy, "maintain은 사용자 데이터를 지우지 않는다")
        let loaded = h.load()
        #expect(loaded.userEntries == Array(legacy.prefix(20)), "200자까지 = 앞 20개")
        #expect(loaded.packs.isEmpty && loaded.packFilesRead == 0)
        #expect(h.store.deleteUserSnippet(legacy[0]).isAccepted, "줄이는 쪽은 받는다")
    }

    @Test("★ AC-6 — 켜기: 자신이 빠지거나 앞 순서로 켜서 기존 팩이 밀리면 거부(R15)")
    func enableRules() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("앞", chars: 150), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("큰", chars: 100), source: .csv, enabled: false))
        guard case .rejected(.gate(.packExcluded(let id, _)), _) = h.store.setPackEnabled(b, enabled: true) else {
            Issue.record("자신이 빠진다 — 거부"); return
        }
        #expect(id == b)
        #expect(h.store.reorder([.userSnippets, .pack(b), .pack(a)]).isAccepted)
        guard case .rejected(.gate(.displacesPacks([a])), _) = h.store.setPackEnabled(b, enabled: true) else {
            Issue.record("앞 순서 팩을 켜 기존 팩이 밀린다 — 거부"); return
        }
    }

    @Test("★ AC-6 — 내장 팩 켜기도 같은 함수 — 켜서 외부 팩이 밀리면 거부, 끄기는 늘 받는다")
    func builtInToggle() throws {
        let builtIn = [entry(String(repeating: "애", count: 80))]
        let h = Harness(builtIn: builtIn)
        defer { h.sandbox.cleanup() }
        h.disabled.current = ["anthem"]
        _ = try h.importedID(h.store.importPack(pack("팩", chars: 150), source: .csv))
        guard case .rejected(.gate(.displacesPacks), _) = h.store.setBuiltInPack("anthem", enabled: true, currentDisabled: ["anthem"]) else {
            Issue.record("내장을 켜 외부 팩이 밀린다 — 거부"); return
        }
        #expect(h.store.setBuiltInPack("greetings", enabled: false, currentDisabled: ["anthem"]).isAccepted)
    }

    @Test("U2 — 꺼 둔 채로 가져오기는 예산을 보지 않는다(큰 팩도 받고 snapshot에는 없다)")
    func importDisabledIgnoresBudget() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("큰", chars: 500), source: .csv, enabled: false))
        #expect(h.store.order == [.userSnippets, .pack(id)])
        #expect(try h.manifest().packs.isEmpty)
    }

    // MARK: 저장 1회 = 항목 1개

    @Test("★ 「저장 1회 = 항목 1개」 — 초과 상태에서 두 항목을 겹쳐 지우며 새로 넣는 저장은 지운 몫으로 통과하지 못한다")
    func mergeCannotUseRemovedBudget() {
        let a = entry(String(repeating: "아", count: 100)), b = entry(String(repeating: "비", count: 120))   // 220 > 200
        let h = Harness(user: [a, b])
        defer { h.sandbox.cleanup() }
        let merged = SnippetEntry(triggers: [a.triggers[0], b.triggers[0]], title: "합침", body: "합친 본문")      // 같은 220
        guard case .rejected(.gate(.baselineOverLimit), _) = h.store.saveUserSnippet(merged, editing: nil) else {
            Issue.record("합계는 같지만 「새 추가」다 — 거부"); return
        }
        var shrunk = b
        shrunk.triggers = [String(repeating: "비", count: 90)]
        #expect(h.store.saveUserSnippet(shrunk, editing: b).isAccepted, "넘은 상태에서 줄이는 고치기는 받는다(R21)")
    }

    @Test("한 항목 판정 — 빠진 것 ≤ 1·들어온 것 ≤ 1")
    func singleItemChange() {
        let a = entry("가"), b = entry("나"), c = entry("다")
        #expect(PackStore.isSingleItemChange(from: [a, b], to: [a, b, c]))
        #expect(PackStore.isSingleItemChange(from: [a, b], to: [a, c]))
        #expect(PackStore.isSingleItemChange(from: [a, b], to: [a]))
        #expect(!PackStore.isSingleItemChange(from: [a, b], to: [c]))
        #expect(!PackStore.isSingleItemChange(from: [a], to: [a, b, c]))
    }

    // MARK: 순서·교체·삭제

    @Test("U1 — 「내 채움글」 줄도 옮긴다, manifest·키보드가 같은 순서")
    func reorderUserRow() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("팩", chars: 10), source: .csv))
        #expect(h.store.reorder([.pack(id), .userSnippets]).isAccepted)
        #expect(try h.manifest().order == [.pack(id), .userSnippets])
        #expect(h.load().order == [.pack(id), .userSnippets])
        #expect(h.store.reorder([.userSnippets]) == .rejected(.invalidOrder, rechecked: false))
        #expect(h.store.reorder([.pack(id), .pack(id)]) == .rejected(.invalidOrder, rechecked: false))
    }

    @Test("교체 — 위치·켬/끔 유지, 옛 변환본은 지운다 · 삭제 — 목록·snapshot에서 빠진다")
    func replaceAndDelete() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))
        #expect(h.store.replacePack(a, with: pack("가2", chars: 12), source: .csv).isAccepted)
        #expect(h.store.order == [.userSnippets, .pack(a), .pack(b)])
        #expect(h.load().packs[a] == pack("가2", chars: 12))
        let packFiles = try FileManager.default.contentsOfDirectory(atPath: h.sandbox.library.appendingPathComponent("packs").path)
        #expect(packFiles.count == 2, "옛 변환본 정리")
        #expect(h.store.deletePack(b).isAccepted)
        #expect(h.store.order == [.userSnippets, .pack(a)])
        #expect(h.load().includedPackIDs == [a])
        #expect(h.store.deletePack("없음") == .rejected(.notFound, rechecked: false))
    }

    @Test("★ 직렬 경로 — 여러 스레드에서 동시에 저장해도 하나씩 커밋된다(revision·세대가 저장 수와 같다)")
    func serialQueue() {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let store = h.store
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            _ = store.saveUserSnippet(entry("문구\(index)"), editing: nil)
        }
        #expect(h.user.entries().count == 20)
        #expect(h.store.revision == 20)
        #expect(h.generations.userSnippetsGeneration == 20)
        #expect(h.generations.packsGeneration == 20)
    }

    // MARK: AC-26 — GC

    @Test("★ AC-26 — GC는 현재 − 2 이하만, 앱의 변경·실행 때만")
    func garbageCollection() {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        for index in 0..<4 { _ = h.store.saveUserSnippet(entry("문구\(index)"), editing: nil) }
        #expect(h.sandbox.generationNames() == ["g3", "g4"])
        h.store.maintain()
        #expect(h.sandbox.generationNames() == ["g3", "g4"])
        _ = h.load()
        #expect(h.sandbox.generationNames() == ["g3", "g4"], "키보드는 지우지 않는다")
    }
}

// MARK: - 키보드 PackSnapshotLoader

@Suite("외부 채움글 1-b — 키보드 순차 로드 (AC-7·8·26, 9-4)")
struct PackSnapshotLoaderTests {

    @Test("snapshot이 없으면(세대 0) 내 채움글·내장만 — 지금과 같다")
    func noSnapshot() {
        let h = Harness(user: [entry("내문구")], builtIn: [entry("내장")])
        defer { h.sandbox.cleanup() }
        let loaded = h.load()
        #expect(loaded.order == [.userSnippets] && loaded.userEntries == [entry("내문구")] && loaded.packs.isEmpty)
        #expect(loaded.dropped == nil && loaded.attempts == 1)
    }

    @Test("★ AC-7 — 넘는 첫 팩에서 멈추고 그 뒤 팩은 읽지도 않는다(예산 판정으로)")
    func stopsAtFirstOverflowDecoded() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 150)), ("b", pack("나", chars: 60)), ("c", pack("다", chars: 10))])
        let reader = CountingReader()
        let loaded = h.load(reader: reader)
        #expect(loaded.includedPackIDs == ["a"])
        #expect(loaded.excluded.map(\.id) == ["b", "c"])
        #expect(reader.packReads == ["a.json", "b.json"], "c는 읽지 않는다")
    }

    @Test("★ AC-7 — 파일 실제 바이트가 남은 예산을 넘으면 그 팩은 내용을 읽지 않고 멈춘다(읽기 전에 제한)")
    func stopsBeforeReadingOversizedFile() throws {
        let tight = PackBudgetLimits(needleCount: 100, needleChars: 10_000, bytes: 6_000, items: 1_000)
        let h = Harness(limits: tight)
        defer { h.sandbox.cleanup() }
        let big = ExternalPack(name: "큰", license: "자체", mode: .phrases,
                               entries: [SnippetEntry(trigger: "큰본문", title: "큰", body: String(repeating: "가", count: 2_900)),
                                         SnippetEntry(trigger: "큰본문2", title: "큰2", body: String(repeating: "나", count: 2_900))])
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 10)), ("big", big), ("c", pack("다", chars: 10))])
        let reader = CountingReader()
        let loaded = h.load(reader: reader)
        #expect(loaded.includedPackIDs == ["a"])
        #expect(reader.packReads == ["a.json"], "큰 파일은 크기만 보고 읽지 않는다")
        #expect(loaded.excluded.first == ActivePackBudget.Exclusion(id: "big", reason: .overflow([.bytes])))
    }

    @Test("★ 9-4 — 초과 snapshot은 일부만 싣고 파일은 지우지 않는다")
    func overflowSnapshotPartiallyLoadedNotDeleted() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 150)), ("b", pack("나", chars: 100))])
        #expect(h.load().includedPackIDs == ["a"])
        let files = try FileManager.default.contentsOfDirectory(atPath: h.sandbox.snapshot.appendingPathComponent("g1").path)
        #expect(Set(files) == ["manifest.json", "a.json", "b.json"])
    }

    @Test("9-4 ② — 팩 수 cap: 앞 16개만 본다(뒤는 읽지 않는다)")
    func packCountCap() throws {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, packs: (0..<18).map { ("p\($0)", pack("팩\($0)", chars: 5)) })
        let reader = CountingReader()
        let loaded = h.load(reader: reader)
        #expect(loaded.includedPackIDs.count == 16)
        #expect(reader.packReads.count == 16)
        #expect(Set(loaded.excluded.map(\.id)) == ["p16", "p17"])
    }

    @Test("★ AC-8 — 앱의 포함·제외 == 키보드의 포함·제외(같은 입력, 같은 함수)")
    func appAndKeyboardAgree() throws {
        let h = Harness(user: [entry(String(repeating: "내", count: 30))])
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 100), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("나", chars: 60), source: .csv, enabled: false))
        #expect(h.store.reorder([.userSnippets, .pack(b), .pack(a)]).isAccepted)
        let appView = h.store.evaluation()
        #expect(h.load().includedPackIDs == appView.included)
        // 같은 입력을 옛 snapshot처럼 전부 실어도(앱을 거치지 않음) 키보드의 제외가 앱과 같다
        let all = [("x", pack("가", chars: 100)), ("y", pack("나", chars: 60)), ("z", pack("다", chars: 30))]
        try h.craft(generation: 99, packs: all)
        let expected = ActivePackBudget.evaluate(
            baseline: PackStats.of(entries: h.user.entries()),
            packs: all.map { ActivePackBudget.Candidate(id: $0.0, isEnabled: true, stats: PackStats.of(pack: $0.1)) }, limits: small)
        let loaded = h.load()
        #expect(loaded.includedPackIDs == expected.included)
        #expect(loaded.excluded.map(\.id) == expected.excluded.map(\.id))
    }

    @Test("★ AC-8 — 손상·낯선 schema·크기 불일치·필드 상한 위반 → 외부 팩 전부 제외, 내 채움글·내장은 싣는다", arguments: 0..<6)
    func corruptionDropsAllExternal(_ index: Int) throws {
        let h = Harness(user: [entry("내문구")], builtIn: [entry("내장")])
        defer { h.sandbox.cleanup() }
        let good = [("a", pack("가", chars: 10)), ("b", pack("나", chars: 10))]
        var expected: PackSnapshotLoader.DropReason
        switch index {
        case 0:
            try h.craft(generation: 1, packs: good)
            try Data("{ 망가짐".utf8).write(to: h.sandbox.snapshot.appendingPathComponent("g1/manifest.json"))
            expected = .corruptManifest
        case 1:
            try h.craft(generation: 1, packs: good, manifestSchema: 2)
            expected = .unknownSchema
        case 2:
            try h.craft(generation: 1, packs: good, packSchema: 2)
            expected = .unknownSchema
        case 3:
            try h.craft(generation: 1, packs: good, lieBytes: ["b": 10])
            expected = .sizeMismatch
        case 4:
            var bad = pack("다", chars: 10)
            bad.name = String(repeating: "이", count: 41)
            try h.craft(generation: 1, packs: [("a", pack("가", chars: 10)), ("bad", bad)])
            expected = .invalidPack
        default:
            try h.craft(generation: 1, order: [.userSnippets, .pack("b"), .pack("a")], packs: good)   // 순서·목록 어긋남
            expected = .corruptManifest
        }
        let loaded = h.load()
        #expect(loaded.dropped == expected)
        #expect(loaded.packs.isEmpty && loaded.includedPackIDs.isEmpty)
        #expect(loaded.userEntries == [entry("내문구")])
        #expect(loaded.order == [.userSnippets])
    }

    @Test("manifest가 cap(64KB)을 넘으면 읽지 않고 외부 팩 제외")
    func manifestCap() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 10))])
        try Data(repeating: 0x20, count: PackLimits.snapshotManifestBytes + 1)
            .write(to: h.sandbox.snapshot.appendingPathComponent("g1/manifest.json"))
        let reader = CountingReader()
        #expect(h.load(reader: reader).dropped == .corruptManifest)
        #expect(reader.reads.isEmpty, "크기만 보고 읽지 않는다")
    }

    // MARK: AC-26 — 일관 읽기·재시도

    @Test("★ AC-26 — 읽는 도중 세대가 바뀌면 처음부터 다시 읽어 최신을 싣는다")
    func retriesOnGenerationChange() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let first = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let reads = Counter()
        let store = h.store
        h.generations.onRead = {
            if reads.next() == 2 { _ = store.importPack(pack("나", chars: 10), source: .csv) }   // 첫 시도의 두 번째 읽기 직전 커밋
        }
        let loaded = h.load()
        #expect(loaded.attempts == 2)
        #expect(loaded.includedPackIDs == [first, "pack2"])
        #expect(loaded.dropped == nil)
    }

    @Test("★ AC-26 — 세대가 계속 바뀌면 3회 뒤 외부 팩을 빼고 내 채움글·내장만")
    func givesUpAfterThreeAttempts() throws {
        let h = Harness(user: [entry("내문구")])
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let generations = h.generations
        let flips = Counter()
        h.generations.onRead = { generations.setUserSnippetsGeneration(flips.next()) }   // 읽을 때마다 바뀐다
        let loaded = h.load()
        #expect(loaded.attempts == 3)
        #expect(loaded.dropped == .inconsistentGenerations)
        #expect(loaded.packs.isEmpty && loaded.userEntries == [entry("내문구")])
    }

    @Test("★ AC-26 — 읽는 중 파일이 사라지면(앱이 새 세대를 만들고 지움) 현재 세대로 다시")
    func retriesWhenFileVanishes() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let first = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let reader = CountingReader()
        let store = h.store, sandbox = h.sandbox
        let once = Counter()
        reader.beforeRead = { url in
            guard url.lastPathComponent == "\(first).json", once.next() == 1 else { return }
            _ = store.importPack(pack("나", chars: 10), source: .csv)                      // g2
            try? FileManager.default.removeItem(at: sandbox.snapshot.appendingPathComponent("g1"))   // 옛 세대가 지워짐
        }
        let loaded = h.load(reader: reader)
        #expect(loaded.attempts == 2)
        #expect(loaded.packsGeneration == 2)
        #expect(loaded.includedPackIDs == [first, "pack2"])
    }

    @Test("★ 전체 접근 없음 — 키보드는 읽기만 한다: 쓰기 권한 없는 snapshot 폴더에서도 그대로 싣는다(별도 분기 없음)")
    func readOnlySnapshot() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        for path in [h.sandbox.snapshot.appendingPathComponent("g1").path, h.sandbox.snapshot.path] {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: path)
        }
        #expect(h.load().includedPackIDs == [id])
    }
}
