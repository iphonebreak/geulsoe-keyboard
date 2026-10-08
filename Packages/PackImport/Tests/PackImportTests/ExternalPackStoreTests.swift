import Foundation
import Testing
import TadakDomain
@testable import PackImport
import TadakData

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
    /// 참이면 쓰기가 실패한다(저장하지 않고 false) — 실패 경로 시험(F5 ③)
    var failSaves = false
    init(_ entries: [SnippetEntry] = []) { stored = entries }
    func entries() -> [SnippetEntry] { lock.withLock { stored } }
    func save(_ entries: [SnippetEntry]) -> Bool {
        lock.withLock {
            guard !failSaves else { return false }
            stored = entries
            return true
        }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
}

/// 한 번이라도 켜졌나 — PackStore 일이 메인 스레드에서 돌았는지 본다(G8)
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    func raise() { lock.withLock { raised = true } }
    var isRaised: Bool { lock.withLock { raised } }
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
    /// 이 이름의 파일은 **첫 읽기만** 없는 것처럼(nil) — 세대는 그대로인 일시 소실(F5 ①)
    var vanishOnFirstRead: Set<String> = []

    func size(of url: URL) -> Int? { base.size(of: url) }
    func read(_ url: URL) -> Data? {
        beforeRead?(url)
        let name = url.lastPathComponent
        let vanish = lock.withLock { () -> Bool in
            reads.append(name)
            return vanishOnFirstRead.remove(name) != nil
        }
        return vanish ? nil : base.read(url)
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
    /// 판정 입력(내장 문구)을 메인 스레드에서 만든 적이 있으면 켜진다 — 큐 안의 일은 모두 이 갈고리를 지난다(G8 탐침)
    let workedOnMain = Flag()
    let store: PackStore

    init(user: [SnippetEntry] = [], builtIn: [SnippetEntry] = [], limits: PackBudgetLimits = small) {
        self.user = MemorySnippets(user)
        self.builtIn = builtIn
        self.limits = limits
        store = Self.makeStore(sandbox: sandbox, generations: generations, user: self.user, builtIn: builtIn, disabled: disabled,
                               notifications: notifications, ids: ids, workedOnMain: workedOnMain, limits: limits)
    }

    /// 같은 저장 위치·같은 주입으로 `PackStore`를 새로 연다 — 앱을 다시 실행한 것과 같다(메모리에 든 것이 없다)
    func reopenedStore() -> PackStore {
        Self.makeStore(sandbox: sandbox, generations: generations, user: user, builtIn: builtIn, disabled: disabled,
                       notifications: notifications, ids: ids, workedOnMain: workedOnMain, limits: limits)
    }

    private static func makeStore(sandbox: Sandbox, generations: MemoryGenerations, user: MemorySnippets, builtIn: [SnippetEntry],
                                  disabled: DisabledBox, notifications: Counter, ids: Counter, workedOnMain: Flag,
                                  limits: PackBudgetLimits) -> PackStore {
        PackStore(
            libraryRoot: sandbox.library, snapshotRoot: sandbox.snapshot, generations: generations, userSnippets: user,
            builtInEntries: { off in
                if Thread.isMainThread { workedOnMain.raise() }
                return off.contains("anthem") ? [] : builtIn
            }, disabledBuiltIns: { disabled.current },
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
               manifestSchema: Int = PackSnapshotManifest.schemaVersion, lieStoredStats: Set<String> = [],
               foreignPackIDs: Set<String> = []) throws {
        let directory = sandbox.snapshot.appendingPathComponent("g\(generation)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var items: [PackSnapshotManifest.Item] = []
        for (id, pack) in packs {
            var stored = StoredExternalPack(packID: id, source: .csv, pack: pack)
            stored.schema = packSchema
            if lieStoredStats.contains(id) { stored.stats = .zero }   // 변환본이 stats를 속인다(F5 ②)
            if foreignPackIDs.contains(id) { stored.packID = "다른팩" }   // 다른 팩의 변환본이 이 자리에(검증 V10)
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

    // MARK: F5 ③ — 실패 경로(쓰는 순서·롤백)

    @Test("★ 내 채움글 쓰기가 실패하면 그대로 — 세대 둘·새 세대 폴더·사용자 문구·revision 모두 원래대로 (S10·S11)")
    func failedUserSaveLeavesEverythingAsIs() throws {
        let h = Harness(user: [entry("원래")])
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("팩", chars: 10), source: .csv))
        let before = (user: h.generations.userSnippetsGeneration, packs: h.generations.packsGeneration,
                      folders: h.sandbox.generationNames(), revision: h.store.revision)
        h.user.failSaves = true
        #expect(h.store.saveUserSnippet(entry("새것"), editing: nil) == .rejected(.writeFailed, rechecked: false))
        #expect(h.generations.userSnippetsGeneration == before.user)
        #expect(h.generations.packsGeneration == before.packs, "커밋 지점(packsGeneration)은 내 채움글 저장 뒤다")
        #expect(h.sandbox.generationNames() == before.folders, "실패한 새 세대 폴더를 남기지 않는다")
        #expect(h.user.entries() == [entry("원래")])
        #expect(h.store.revision == before.revision)
    }

    @Test("★ snapshot 쓰기가 실패하면 새 변환본을 지우고 목록·세대 그대로 (S11 롤백)")
    func failedSnapshotRollsBack() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let packsDirectory = h.sandbox.library.appendingPathComponent("packs").path
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: packsDirectory)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.snapshot.path)
        #expect(h.store.importPack(pack("나", chars: 10), source: .csv) == .rejected(.writeFailed, rechecked: false))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.snapshot.path)
        #expect(try FileManager.default.contentsOfDirectory(atPath: packsDirectory) == filesBefore, "새 변환본을 지웠다")
        #expect(h.store.order == [.userSnippets, .pack(a)])
        #expect(h.generations.packsGeneration == 1)
        #expect(h.sandbox.generationNames() == ["g1"])
    }

    // MARK: F5 ④ — 결정적 직렬 시험

    @Test("★ 판정과 쓰기 사이에 다른 커밋이 끼어들지 못한다 — 끼어들기 갈고리로 결정적으로 (S09)")
    func commitsDoNotInterleave() {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let store = h.store
        let calls = Counter()
        let interleaved = InterleaveProbe()
        // 둘째 커밋이 끝나면 두 번 신호한다 — 갈고리 안의 관찰과 시험 끝의 대기가 각각 하나씩(둘 다 시간 제한, 무한 대기 없음)
        let secondFinished = DispatchSemaphore(value: 0)
        store.beforeWriteForTesting = {
            guard calls.next() == 1 else { return }
            DispatchQueue.global().async {
                _ = store.saveUserSnippet(entry("둘째"), editing: nil)
                secondFinished.signal()
                secondFinished.signal()
            }
            // 직렬이면 둘째는 큐에서 기다리므로 여기서 끝날 수 없다(시간 초과). 동시라면 이 사이에 끝난다
            interleaved.set(secondFinished.wait(timeout: .now() + 0.3) == .success)
        }
        _ = store.saveUserSnippet(entry("첫째"), editing: nil)
        _ = secondFinished.wait(timeout: .now() + 5)
        #expect(!interleaved.value)
        #expect(h.user.entries() == [entry("첫째"), entry("둘째")])
        #expect(store.revision == 2)
    }

    // MARK: F7 — 화면 dedup과 같은 기준으로 지운다

    @Test("★ 지우기는 정규화 단축어가 같은 저장분을 모두 지운다 — 화면에서 하나로 보이는 항목 하나 (F7)")
    func deleteRemovesNormalizedDuplicates() {
        let a = entry("우리집주소"), aSpaced = entry("우리집 주소"), other = entry("다른")
        let h = Harness(user: [a, other, aSpaced])
        defer { h.sandbox.cleanup() }
        #expect(h.store.deleteUserSnippet(a).isAccepted)
        #expect(h.user.entries() == [other], "띄어쓰기만 다른 옛 중복도 함께")
        #expect(h.generations.userSnippetsGeneration == 1, "커밋 한 번")
        #expect(h.store.deleteUserSnippet(a) == .rejected(.notFound, rechecked: false))
    }

    @Test("F7 — 한도를 넘은 옛 저장분에서도 중복 지우기는 막히지 않는다(줄이는 쪽)")
    func deleteDuplicatesWhileOverLimit() {
        let big = entry(String(repeating: "가", count: 150)), bigSpaced = entry(String(repeating: "가", count: 75) + " " + String(repeating: "가", count: 75))
        let h = Harness(user: [big, bigSpaced])                // 300 > 200
        defer { h.sandbox.cleanup() }
        #expect(!h.store.evaluation().baselineOverflow.isEmpty)
        #expect(h.store.deleteUserSnippet(bigSpaced).isAccepted)
        #expect(h.user.entries().isEmpty)
    }

    // MARK: F4 — 읽을 수 없는 변환본은 그 팩만 뺀다

    @Test("★ 목록이 가리키는 변환본이 없으면 판정에서 그 팩만 `.unavailable`로 빼고 커밋은 계속한다 — 판정 == snapshot·목록 그대로 (F4·C5)")
    func unreadablePackIsSkipped() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))
        let packsDirectory = h.sandbox.library.appendingPathComponent("packs")
        for name in try FileManager.default.contentsOfDirectory(atPath: packsDirectory.path) where name.hasPrefix(a) {
            try FileManager.default.removeItem(at: packsDirectory.appendingPathComponent(name))
        }
        #expect(h.store.unreadablePackIDs() == [a])
        guard case .accepted(let accepted) = h.store.saveUserSnippet(entry("내문구"), editing: nil) else {
            Issue.record("내 채움글 저장이 막히면 안 된다"); return
        }
        // C5 — snapshot에서 조용히 빼지 않고 **판정 단계에서 제외(.unavailable)** — 판정과 snapshot이 같다(AC-8)
        #expect(accepted.evaluation.included == [b])
        #expect(accepted.evaluation.excluded == [ActivePackBudget.Exclusion(id: a, reason: .unavailable)])
        #expect(h.store.evaluation().excluded.map(\.id) == [a])
        #expect(try h.manifest().packs.map(\.id) == [b])
        #expect(try h.manifest().order == [.userSnippets, .pack(b)])
        #expect(h.store.order == [.userSnippets, .pack(a), .pack(b)], "목록에서 지우지 않는다(9-3)")
        #expect(h.load().includedPackIDs == h.store.evaluation().included, "AC-8 — 앱 판정 == 키보드")
        guard case .accepted = h.store.setBuiltInPack("anthem", enabled: false, currentDisabled: []) else {
            Issue.record("내장 토글도 막히지 않는다"); return
        }
        #expect(h.store.setPackEnabled(a, enabled: false).isAccepted)
        #expect(h.store.setPackEnabled(a, enabled: true) == .rejected(.packUnavailable(a), rechecked: false),
                "못 읽는 팩은 켤 수 없다 — 다시 가져오기·삭제로 복구(1-c)")
    }

    @Test("C5 — 못 읽는 팩이 앞에서 예산을 차지하지 않는다: 뒤 팩이 그 몫으로 들어온다(예산 쉼과 같은 결과)")
    func unavailablePackFreesBudget() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 150), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("나", chars: 100), source: .csv, enabled: false))
        guard case .rejected(.gate(.packExcluded), _) = h.store.setPackEnabled(b, enabled: true) else {
            Issue.record("처음엔 a가 예산을 차지해 b를 켤 수 없다"); return
        }
        let packsDirectory = h.sandbox.library.appendingPathComponent("packs")
        for name in try FileManager.default.contentsOfDirectory(atPath: packsDirectory.path) where name.hasPrefix(a) {
            try FileManager.default.removeItem(at: packsDirectory.appendingPathComponent(name))
        }
        #expect(h.store.setPackEnabled(b, enabled: true).isAccepted, "a가 빠졌으니 b가 들어온다")
        #expect(h.store.evaluation().included == [b])
    }

    // MARK: C1 — 목록 손상은 아무것도 지우거나 덮어쓰지 않는다

    @Test("★ C1 — library.json이 손상·낯선 schema면 maintain은 변환본을 지우지 않고, 커밋은 거부하고 목록을 덮어쓰지 않는다",
          arguments: ["{ 망가짐", #"{"schema":99,"revision":3,"order":["user"],"packs":{}}"#])
    func damagedLibraryIsNeverOverwritten(_ damaged: String) throws {
        let h = Harness(user: [entry("원래")])
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let libraryURL = h.sandbox.library.appendingPathComponent("library.json")
        let packsDirectory = h.sandbox.library.appendingPathComponent("packs").path
        let files = try FileManager.default.contentsOfDirectory(atPath: packsDirectory)
        try Data(damaged.utf8).write(to: libraryURL)
        let userGeneration = h.generations.userSnippetsGeneration

        h.store.maintain()
        #expect(try FileManager.default.contentsOfDirectory(atPath: packsDirectory) == files, "변환본 보존")
        #expect(!h.store.isLibraryReadable)
        #expect(h.generations.userSnippetsGeneration == userGeneration + 1, "G9 — 목록을 못 읽어도 실행 때 한 번 올린다")
        let generations = (h.generations.userSnippetsGeneration, h.generations.packsGeneration)

        #expect(h.store.saveUserSnippet(entry("새것"), editing: nil) == .rejected(.libraryUnreadable, rechecked: false))
        #expect(h.store.importPack(pack("나", chars: 10), source: .csv) == .rejected(.libraryUnreadable, rechecked: false))
        #expect(try Data(contentsOf: libraryURL) == Data(damaged.utf8), "목록 원본 그대로")
        #expect(try FileManager.default.contentsOfDirectory(atPath: packsDirectory) == files)
        #expect(h.user.entries() == [entry("원래")])
        #expect((h.generations.userSnippetsGeneration, h.generations.packsGeneration) == generations)
    }

    @Test("C1 — library.json이 아예 없으면(처음) 빈 목록으로 시작한다")
    func missingLibraryIsFresh() {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        #expect(h.store.isLibraryReadable)
        #expect(h.store.saveUserSnippet(entry("처음"), editing: nil).isAccepted)
    }

    // MARK: C2 — 내 채움글을 되돌린 실패 경로도 세대를 올린다

    @Test("★ C2 — 내 채움글 저장 뒤 목록 쓰기가 실패해 되돌리면 사용자 세대를 올리고 알린다(그 사이 읽은 키보드가 같은 키로 캐시하지 않게)")
    func rolledBackUserSaveStillBumpsGeneration() throws {
        let h = Harness(user: [entry("원래")])
        defer { h.sandbox.cleanup() }
        #expect(h.store.saveUserSnippet(entry("첫"), editing: nil).isAccepted)     // library 폴더가 생긴다
        let before = (user: h.generations.userSnippetsGeneration, packs: h.generations.packsGeneration,
                      folders: h.sandbox.generationNames(), notified: h.notifications.next())
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.library.path)
        let result = h.store.saveUserSnippet(entry("둘째"), editing: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.library.path)
        #expect(result == .rejected(.writeFailed, rechecked: false))
        #expect(h.user.entries() == [entry("원래"), entry("첫")], "내 채움글은 되돌렸다")
        #expect(h.generations.userSnippetsGeneration == before.user + 1, "되돌렸어도 세대는 올린다")
        #expect(h.generations.packsGeneration == before.packs)
        #expect(h.sandbox.generationNames() == before.folders)
        #expect(h.notifications.next() == before.notified + 2, "알림 1회(이 호출이 +2번째)")
    }

    // MARK: C7 — 일괄 삭제는 snippetListID 완전 일치만

    @Test("★ C7 — 「집」을 지워도 「집, 회사」는 남는다(단축어 하나가 겹친다고 지우지 않는다 — 완전 일치만)")
    func deleteNeedsExactListID() {
        let home = entry("집"), homeOffice = SnippetEntry(triggers: ["집", "회사"], title: "집·회사", body: "본문")
        let h = Harness(user: [home, homeOffice])
        defer { h.sandbox.cleanup() }
        #expect(h.store.deleteUserSnippet(home).isAccepted)
        #expect(h.user.entries() == [homeOffice])
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

    // MARK: 1-d — 팩 지우기·바꾸기 뒤 옛 snapshot 즉시 정리

    @Test("★ 1-d — 팩을 지우면 옛 snapshot 세대를 모두 지운다(현재만) — 지운 팩의 내용·변환본·검사 기록이 어느 파일에도 남지 않는다",
          arguments: [true, false])
    func deletePurgesOldSnapshots(enabled: Bool) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let gone = try h.importedID(h.store.importPack(pack("DELMARK", chars: 10), source: .csv, enabled: enabled))   // g1
        let kept = try h.importedID(h.store.importPack(pack("KEEPMARK", chars: 10), source: .csv))                    // g2
        h.store.maintain()   // 검사 기록(pack-checks)에 두 변환본이 실린다 — 지운 뒤 빠지는지 본다
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)                                      // g3
        #expect(h.sandbox.generationNames() == ["g2", "g3"], "평소 커밋은 현재 − 2 이하만")
        #expect(try filesMentioning("DELMARK", in: h).count > 1, "지우기 전에는 변환본·snapshot에 있다")
        #expect(try checkedFiles(h).contains { $0.hasPrefix("\(gone)-r") })

        #expect(h.store.deletePack(gone).isAccepted)                                                                 // g4
        #expect(h.sandbox.generationNames() == ["g4"], "지우기는 현재 세대만 남긴다")
        #expect(try filesMentioning("DELMARK", in: h).isEmpty, "지운 팩의 내용이 남은 파일 0")
        #expect(try filesMentioning("\(gone)-r", in: h).isEmpty, "지운 팩의 변환본 이름(목록·검사 기록)도 남지 않는다")
        #expect(try filesMentioning("\(gone).json", in: h).isEmpty, "snapshot 사본 이름도")
        #expect(!packFileNames(h).contains { $0.hasPrefix("\(gone)-r") })
        #expect(try !checkedFiles(h).contains { $0.hasPrefix("\(gone)-r") }, "검사 기록에서도 빠진다")
        #expect(try checkedFiles(h).contains { $0.hasPrefix("\(kept)-r") }, "남은 팩의 검사 기록은 그대로")
        #expect(h.load().includedPackIDs == [kept])

        // 그 뒤 평소 커밋은 지금 규칙 그대로(현재 − 2 이하만)
        #expect(h.store.saveUserSnippet(entry("문구2"), editing: nil).isAccepted)                                     // g5
        #expect(h.sandbox.generationNames() == ["g4", "g5"])
    }

    @Test("★ 1-d — 팩을 바꾸면(켜진·꺼진 팩 모두) 옛 snapshot 세대를 모두 지운다 — 바꾸기 전 내용이 남은 파일 0", arguments: [true, false])
    func replacePurgesOldSnapshots(enabled: Bool) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("OLDMARK", chars: 10), source: .csv))                      // g1(켜짐)
        if !enabled { #expect(h.store.setPackEnabled(id, enabled: false).isAccepted) }                               // g2 — g1에는 켜진 채 남아 있다
        let oldFile = try packFileName(h, of: id)
        #expect(h.sandbox.generationNames().count == (enabled ? 1 : 2))
        #expect(try filesMentioning("OLDMARK", in: h).count > 1)

        #expect(h.store.replacePack(id, with: pack("NEWMARK", chars: 10), source: .csv).isAccepted)
        #expect(h.sandbox.generationNames() == ["g\(h.generations.packsGeneration)"], "현재 세대만")
        #expect(try filesMentioning("OLDMARK", in: h).isEmpty, "바꾸기 전 내용이 남은 파일 0")
        #expect(try filesMentioning(oldFile, in: h).isEmpty, "옛 변환본 이름도(목록·검사 기록) 남지 않는다")
        #expect(h.load().includedPackIDs == (enabled ? [id] : []))
    }

    @Test("1-d — 평소 커밋(가져오기·켬/끔·순서·내 채움글)은 지금 규칙 그대로: 바로 앞 세대를 남긴다")
    func ordinaryCommitsKeepPreviousGeneration() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))
        #expect(h.sandbox.generationNames() == ["g1", "g2"])
        #expect(h.store.setPackEnabled(a, enabled: false).isAccepted)
        #expect(h.sandbox.generationNames() == ["g2", "g3"])
        #expect(h.store.reorder([.pack(b), .userSnippets, .pack(a)]).isAccepted)
        #expect(h.sandbox.generationNames() == ["g3", "g4"])
    }
}

/// 이 상자(목록·변환본·검사 기록·snapshot) 안에서 `marker`(UTF-8 바이트)를 품은 파일 — 이름에 들었거나 내용에 들었거나
private func filesMentioning(_ marker: String, in h: Harness) throws -> [String] {
    let needle = Data(marker.utf8)
    guard let enumerator = FileManager.default.enumerator(at: h.sandbox.root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
    var found: [String] = []
    for case let url as URL in enumerator {
        guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
        let contents = try Data(contentsOf: url)
        if url.lastPathComponent.contains(marker) || contents.range(of: needle) != nil {
            found.append(url.path.replacingOccurrences(of: h.sandbox.root.path, with: ""))
        }
    }
    return found
}

/// 검사 기록(`pack-checks.json`)이 든 변환본 이름 — 파일이 없으면 빈 목록
private func checkedFiles(_ h: Harness) throws -> [String] {
    let url = h.sandbox.library.appendingPathComponent("pack-checks.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
    return ((object as? [String: Any]) ?? [:]).keys.sorted()
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

    @Test("★ AC-8 — 손상·낯선 schema·크기 불일치·필드 상한 위반·다른 팩 id → 외부 팩 전부 제외, 내 채움글·내장은 싣는다",
          arguments: 0..<7)
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
        case 5:
            try h.craft(generation: 1, packs: good, foreignPackIDs: ["b"])
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

    @Test("★ C3 — manifest 순서에 「내 채움글」 줄이 정확히 하나가 아니거나 줄이 겹치면 손상으로 보고 외부 팩 제외",
          arguments: [[SnippetSourceSlot.userSnippets, .userSnippets, .pack("a")], [.pack("a")], [.userSnippets, .pack("a"), .pack("a")]])
    func manifestOrderSlots(_ order: [SnippetSourceSlot]) throws {
        let h = Harness(user: [entry("내문구")])
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, order: order, packs: [("a", pack("가", chars: 10))])
        let loaded = h.load()
        #expect(loaded.dropped == .corruptManifest)
        #expect(loaded.userEntries == [entry("내문구")] && loaded.packs.isEmpty)
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
        #expect(!loaded.isCacheable, "F1 — 일시적 실패는 캐시하지 않는다(다음 재구성이 다시 읽는다)")
    }

    /// R23 — 내 채움글 몫은 두 경로(읽은 경로·3회 포기 경로) 모두 `ActivePackBudget.userSnippetUsage` 하나로 센다
    @Test("★ R23 — 3회 포기 경로도 같은 함수: 옛 초과본은 앞 20개만, 넘은 항목은 읽은 경로와 같다")
    func givesUpWithLegacyOverflow() throws {
        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }  // 300 > 200자
        let h = Harness(user: legacy)
        defer { h.sandbox.cleanup() }
        let normal = h.load()
        let generations = h.generations
        let flips = Counter()
        h.generations.onRead = { generations.setUserSnippetsGeneration(flips.next()) }
        let gaveUp = h.load()
        #expect(gaveUp.dropped == .inconsistentGenerations && gaveUp.attempts == 3)
        #expect(gaveUp.userEntries == Array(legacy.prefix(20)) && normal.userEntries == gaveUp.userEntries)
        #expect(!normal.baselineOverflow.isEmpty && gaveUp.baselineOverflow == normal.baselineOverflow)
    }

    /// 범위: 읽는 사이 앱이 **새 세대를 만들고 옛 세대를 지운** 경우 — 세대 불일치·소실이 함께 일어난다(실제 GC 경로)
    @Test("★ AC-26 — 읽는 중 앱이 새 세대를 만들고 옛 세대를 지우면 새 세대로 다시")
    func retriesWhenGenerationReplacedDuringRead() throws {
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

    /// 1-d — 팩 지우기는 옛 세대를 **바로** 지운다(평소 GC는 현재 − 2 이하). 키보드가 그 세대를 읽던 중이면 소실 → 새 세대로 다시
    @Test("★ AC-26·1-d — 읽는 중 앱이 팩을 지우면 그 커밋이 읽던 세대를 바로 지운다 — 키보드는 새 세대로 다시 읽어 지운 팩 없이 싣는다")
    func retriesWhenDeleteRemovesReadingGeneration() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))                 // g1
        let b = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))                 // g2
        let reader = CountingReader()
        let store = h.store
        let once = Counter()
        reader.beforeRead = { url in
            guard url.lastPathComponent == "\(a).json", once.next() == 1 else { return }
            _ = store.deletePack(b)                                                                       // g3 — g2(읽는 중)를 바로 지운다
        }
        let loaded = h.load(reader: reader)
        #expect(h.sandbox.generationNames() == ["g3"], "테스트가 아니라 저장소가 지웠다")
        #expect(loaded.attempts == 2)
        #expect(loaded.dropped == nil)
        #expect(loaded.packsGeneration == 3)
        #expect(loaded.includedPackIDs == [a], "지운 팩은 싣지 않는다")
    }

    @Test("★ AC-26 — 세대는 그대로인데 파일이 한 번 안 보이면 같은 세대로 다시 읽는다 (L08 · 소실 재시도 단독)")
    func transientVanishRetriesSameGeneration() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        let reader = CountingReader()
        reader.vanishOnFirstRead = ["\(a).json"]
        let loaded = h.load(reader: reader)
        #expect(loaded.attempts == 2)
        #expect(loaded.dropped == nil)
        #expect(loaded.includedPackIDs == [a])
        #expect(loaded.packsGeneration == 1)
    }

    @Test("★ AC-26·F1 — 파일이 계속 없으면 3회 뒤 외부 팩 제외(.vanished), 그 결과는 캐시하지 않는다")
    func persistentVanishGivesUpUncacheable() throws {
        let h = Harness(user: [entry("내문구")])
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))
        try FileManager.default.removeItem(at: h.sandbox.snapshot.appendingPathComponent("g1/\(a).json"))
        let loaded = h.load()
        #expect(loaded.attempts == 3)
        #expect(loaded.dropped == .vanished)
        #expect(loaded.userEntries == [entry("내문구")] && loaded.packs.isEmpty)
        #expect(!loaded.isCacheable)
    }

    @Test("★ 9-4·AC-8 — 변환본이 stats를 작게 속여도 키보드는 다시 세어 넘는 팩을 뺀다 (L09b)")
    func storedStatsAreRecounted() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 150)), ("liar", pack("나", chars: 100))],
                    lieStoredStats: ["a", "liar"])
        let loaded = h.load()
        #expect(loaded.includedPackIDs == ["a"])
        #expect(loaded.excluded.map(\.id) == ["liar"])
    }

    @Test("F1 — 캐시해도 되는 결과: 정상·snapshot 없음·영구 손상(다음 저장이 세대를 바꾼다) / 안 되는 결과: 세대 불일치·소실")
    func cacheability() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        #expect(h.load().isCacheable, "snapshot 없음")
        try h.craft(generation: 1, packs: [("a", pack("가", chars: 10))])
        #expect(h.load().isCacheable, "정상")
        try h.craft(generation: 2, packs: [("a", pack("가", chars: 10))], manifestSchema: 9)
        let unknown = h.load()
        #expect(unknown.dropped == .unknownSchema && unknown.isCacheable)
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

/// 끼어들기 갈고리의 관찰 값
private final class InterleaveProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var observed = false
    func set(_ value: Bool) { lock.withLock { observed = value } }
    var value: Bool { lock.withLock { observed } }
}

// MARK: - 1-c 1단계 — 읽기 모델 (G1)

/// 번호형 팩 — 틀 하나, 항목 `count`개
private func numbered(_ name: String, count: Int) -> ExternalPack {
    ExternalPack(name: name, license: "자체 작성", mode: .numbered, template: PackTemplate(
        patterns: [TemplatePattern(prefix: "사자성어", suffix: "번")], titleFormat: "사자성어 {n}번",
        items: (1...count).map { PackTemplateItem(n: $0, title: "", body: "예시 본문 \($0)") }))
}

private func removePackFiles(_ h: Harness, of id: String) throws {
    let packsDirectory = h.sandbox.library.appendingPathComponent("packs")
    for name in try FileManager.default.contentsOfDirectory(atPath: packsDirectory.path) where name.hasPrefix(id) {
        try FileManager.default.removeItem(at: packsDirectory.appendingPathComponent(name))
    }
}

@Suite("외부 채움글 1-c 1단계 — 읽기 모델 PackSummary (G1·상태 5갈래)")
struct PackSummaryTests {

    @Test("★ G1 — 목록 순서대로 이름·종류·항목 수·대표 틀·켬/끔. 변환본이 없어도 이름은 목록에 있다")
    func summariesComeFromLibrary() throws {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 50), source: .csv))
        let b = try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 12), source: .csv, enabled: false))
        #expect(h.store.summaries() == [
            PackSummary(id: a, name: "회사 상용구", mode: .phrases, itemCount: 2, titleFormat: nil, isEnabled: true, status: .on),
            PackSummary(id: b, name: "사자성어 예시 팩", mode: .numbered, itemCount: 12, titleFormat: "사자성어 {n}번",
                        isEnabled: false, status: .off)
        ])
        // ★ 「읽을 수 없는 팩」도 이름이 보인다 — 이름이 변환본 안에만 있으면 이름 없는 행이 된다(G1)
        try removePackFiles(h, of: b)
        let unreadable = try #require(h.store.summaries().last)
        #expect(unreadable.name == "사자성어 예시 팩")
        #expect(unreadable.titleFormat == "사자성어 {n}번")
        #expect(unreadable.status == .unavailable, "꺼진 팩도 읽을 수 없으면 「읽을 수 없어요」(켜면 거부된다)")
    }

    @Test("★ 상태 5갈래 — 켬 · 끔 · 쉬는 중(한도) · 쉬는 중(내 채움글) · 읽을 수 없어요")
    func fiveStatuses() throws {
        let h = Harness(user: [entry(String(repeating: "가", count: 100))])
        defer { h.sandbox.cleanup() }
        let on = try h.importedID(h.store.importPack(pack("켬", chars: 40), source: .csv))
        let off = try h.importedID(h.store.importPack(pack("끔", chars: 10), source: .csv, enabled: false))
        let unreadable = try h.importedID(h.store.importPack(pack("못읽음", chars: 10), source: .csv))
        let resting = try h.importedID(h.store.importPack(pack("쉼", chars: 40), source: .csv))
        try removePackFiles(h, of: unreadable)
        // 내 채움글을 늘려 마지막 팩만 한도 밖으로(overflow)
        #expect(h.store.saveUserSnippet(entry(String(repeating: "나", count: 30)), editing: nil).isAccepted)
        #expect(h.store.summaries().map(\.status) == [.on, .off, .unavailable, .restingOverLimit])
        #expect(h.store.summaries().map(\.id) == [on, off, unreadable, resting])

        // 내 채움글만으로 한도를 넘은 저장본(옛 버전에서 써 온 것 — PackStore를 거치지 않았다): 켠 외부 팩은 전부
        // 「내 채움글을 정리하면 다시 떠요」 쪽(4-N). 읽을 수 없는 팩은 그대로 「읽을 수 없어요」, 끈 팩은 「끔」
        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }
        #expect(h.user.save(legacy))
        #expect(h.store.summaries().map(\.status) == [.restingForUserSnippets, .off, .unavailable, .restingForUserSnippets])
    }

    @Test("상태 판정 표 — 읽을 수 없음이 끔보다 먼저, 켬은 포함일 때만",
          arguments: [
            (true, false, nil as ActivePackBudget.ExclusionReason?, true, PackSummary.Status.on),
            (false, false, nil, false, .off),
            (false, true, nil, false, .unavailable),
            (true, true, .unavailable, false, .unavailable),
            (true, false, .overflow([.bytes]), false, .restingOverLimit),
            (true, false, .afterEarlierOverflow, false, .restingOverLimit),
            (true, false, .baselineOverflow, false, .restingForUserSnippets),
            (true, false, nil, false, .restingOverLimit)
          ])
    func statusTable(_ isEnabled: Bool, _ isUnavailable: Bool, _ reason: ActivePackBudget.ExclusionReason?,
                     _ included: Bool, _ expected: PackSummary.Status) {
        let packs = [ActivePackBudget.Candidate(id: "x", isEnabled: true, stats: .zero)]
        var evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: included ? packs : [])
        if let reason { evaluation.excluded = [ActivePackBudget.Exclusion(id: "x", reason: reason)] }
        #expect(PackSummary.status(of: "x", isEnabled: isEnabled, isUnavailable: isUnavailable, in: evaluation) == expected)
    }

    @Test("★ 이행 없음 — 표시 칸이 없는 1-b 목록(schema 1)도 그대로 읽히고, 이름은 변환본에서 채운다")
    func legacyLibraryWithoutDisplayFields() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 3), source: .csv))
        // 1-b가 쓰던 모양으로 되돌린다 — 팩 항목에 file·isEnabled·stats만
        let libraryURL = h.sandbox.library.appendingPathComponent("library.json")
        var json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: libraryURL)) as? [String: Any])
        var packs = try #require(json["packs"] as? [String: [String: Any]])
        for (id, var item) in packs {
            #expect(item["name"] != nil, "새 목록은 이름을 담는다")
            item = item.filter { ["file", "isEnabled", "stats"].contains($0.key) }
            packs[id] = item
        }
        json["packs"] = packs
        #expect(json["schema"] as? Int == 1, "schema 번호는 그대로")
        try JSONSerialization.data(withJSONObject: json).write(to: libraryURL)

        #expect(h.store.isLibraryReadable)
        #expect(h.store.summaries().map(\.name) == ["회사 상용구", "사자성어 예시 팩"])
        #expect(h.store.summaries().map(\.mode) == [.phrases, .numbered])
        #expect(h.store.summaries().map(\.titleFormat) == [nil, "사자성어 {n}번"])
        // 표시 칸도 변환본도 없으면 이름을 모른다(nil) — 알림은 「이름 없는 팩」(문구 표)
        try removePackFiles(h, of: a)
        #expect(h.store.summaries().first?.name == nil)
        #expect(h.store.summaries().first?.itemCount == 1, "항목 수는 목록의 stats에서 — 변환본 없이도")
        // 옛 목록 위에서도 커밋은 그대로 된다
        #expect(h.store.setPackEnabled(b, enabled: false).isAccepted)
    }

    @Test("교체하면 표시 칸도 새 파일 것으로 — 위치·켬/끔은 그대로(9-1)")
    func replaceUpdatesDisplay() throws {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        #expect(h.store.replacePack(a, with: numbered("사자성어 예시 팩", count: 5), source: .csv).isAccepted)
        #expect(h.store.summaries() == [PackSummary(id: a, name: "사자성어 예시 팩", mode: .numbered, itemCount: 5,
                                                    titleFormat: "사자성어 {n}번", isEnabled: true, status: .on)])
    }
}

// MARK: - 1-c 1단계 — 메인 밖 래퍼 (G8)

private func onMainThread() -> Bool { Thread.isMainThread }

@Suite("외부 채움글 1-c 1단계 — PackStoreClient (G8 메인 밖 · 사유별 알림)")
struct PackStoreClientTests {

    @MainActor
    @Test("★ G8 — 메인에서 불러도 PackStore 일(판정·파일 IO)은 메인 밖에서 돌고, 결과는 메인에서 받는다")
    func runsOffMain() async throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let client = PackStoreClient(store: h.store)
        let saved = await client.saveUserSnippet(entry("문구"), editing: nil)
        #expect(onMainThread(), "await 뒤는 메인(화면이 그대로 상태를 바꾼다)")
        #expect(saved.isAccepted)
        _ = await client.deleteUserSnippet(entry("문구"))
        _ = await client.setBuiltInPack("anthem", enabled: false, currentDisabled: [])
        _ = await client.summaries()
        _ = await client.evaluation()
        _ = await client.isLibraryReadable()
        _ = await client.libraryStatus()
        _ = await client.userSnippetBudget()
        _ = await client.recoveryPreview()
        #expect(await client.recoverLibrary() == .notNeeded)
        await client.maintain()
        #expect(onMainThread())
        #expect(!h.workedOnMain.isRaised, "PackStore 일은 한 번도 메인에서 돌지 않았다")
        // 탐침이 살아 있는지 — 메인에서 직접 부르면 켜진다(이 시험이 헛돌지 않게)
        _ = h.store.evaluation()
        #expect(h.workedOnMain.isRaised)
    }

    @Test("★ G8 — 일은 주입한 GCD 큐에서 돈다(협력 스레드 풀·부른 액터를 queue.sync로 막지 않는다)")
    func runsOnInjectedQueue() async {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let key = DispatchSpecificKey<String>()
        let queue = DispatchQueue(label: "client-test")
        queue.setSpecific(key: key, value: "client-test")
        let client = PackStoreClient(store: h.store, queue: queue)
        #expect(await client.run { _ in DispatchQueue.getSpecific(key: key) } == "client-test")
        #expect(await client.saveUserSnippet(entry("문구"), editing: nil).isAccepted, "쓰기도 같은 길")
    }

    @MainActor
    @Test("★ F-5 — 채움글 화면의 내 채움글 목록도 래퍼로 메인 밖에서 읽는다 — 정리 모델의 화면 목록(정규화 단축어 중복 제거) 그대로")
    func userSnippetListOffMain() async {
        let stored = [entry("우리집주소"), entry("우리집 주소", body: "옛 중복"), entry("회사")]
        let h = Harness(user: stored)
        defer { h.sandbox.cleanup() }
        let list = await PackStoreClient(store: h.store).userSnippetBudget().entries
        #expect(list == UserSnippetBudget.displayEntries(stored))
        #expect(list.map(\.title) == ["우리집주소", "회사"])
        #expect(!h.workedOnMain.isRaised, "저장분 디코드와 판정이 같은 메인 밖 작업 안에서 돈다")
    }

    @Test("★ AC-4·G2 — 받았지만 팩이 쉬게 되면 이름 있는 알림(G1)")
    func restedPackIsNamed() async throws {
        let h = Harness(user: [entry(String(repeating: "가", count: 100))])
        defer { h.sandbox.cleanup() }
        let client = PackStoreClient(store: h.store)
        #expect(await client.importPack(pack("회사 상용구", chars: 90), source: .csv).isAccepted)
        let outcome = await client.saveUserSnippet(entry(String(repeating: "나", count: 50)), editing: nil)
        #expect(outcome.isAccepted)
        #expect(outcome.notice?.reason == .packRested)
        #expect(outcome.notice?.message == "대신 「회사 상용구」가 한도를 넘어 쉬고 있어요. 지운 것은 없어요. 채움글을 줄이면 다시 떠요.")
    }

    @Test("★ A2·A3 — 같은 baseline 거부도 저장 전 상태로 갈린다(옛 초과본이면 A3)")
    func userSaveRejections() async {
        let h = Harness(user: [entry(String(repeating: "가", count: 190))])
        defer { h.sandbox.cleanup() }
        let fresh = await PackStoreClient(store: h.store).saveUserSnippet(entry(String(repeating: "나", count: 20)), editing: nil)
        #expect(!fresh.isAccepted)
        #expect(fresh.notice?.reason == .userSaveTooLong)

        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }
        let h2 = Harness(user: legacy)
        defer { h2.sandbox.cleanup() }
        let over = await PackStoreClient(store: h2.store).saveUserSnippet(entry("새것"), editing: nil)
        #expect(over.notice?.reason == .userSaveWhileOverLimit)
        #expect(over.notice?.actions == [.organize])
    }

    @Test("★ D2·E1·E2 — 가져오기(내 채움글 초과)·목록 손상·읽을 수 없는 팩 켜기")
    func otherRejections() async throws {
        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }
        let h = Harness(user: legacy)
        defer { h.sandbox.cleanup() }
        let client = PackStoreClient(store: h.store)
        let imported = await client.importPack(pack("회사 상용구", chars: 10), source: .csv)
        #expect(imported.notice?.reason == .importWhileUserOverLimit)
        #expect(imported.notice?.actions == [.organize, .importDisabled])
        let disabled = await client.importPack(pack("회사 상용구", chars: 10), source: .csv, enabled: false)
        #expect(disabled.isAccepted && disabled.notice == nil)
        let id = try h.importedID(disabled.result)
        try removePackFiles(h, of: id)
        let enable = await client.setPackEnabled(id, enabled: true)
        #expect(enable.notice?.reason == .packUnavailable)
        #expect(enable.notice?.packIDs == [id])

        try Data("{ 망가짐".utf8).write(to: h.sandbox.library.appendingPathComponent("library.json"))
        let delete = await client.deleteUserSnippet(legacy[0])
        #expect(delete.notice?.reason == .libraryUnreadable)
        #expect(await client.isLibraryReadable() == false)
    }
}

// MARK: - 1-c 2단계 — 목록 상태·복구 (㉡, R24)

/// 목록 손상 세 갈래
enum LibraryDamage: String, CaseIterable, Sendable {
    /// 파일은 있는데 열 수 없다(권한)
    case unreadable
    /// 열리는데 JSON이 망가졌다
    case corrupt
    /// 새 버전이 쓴 목록(schema 99, 이 앱이 모르는 칸 포함)
    case unknownSchema

    var status: PackLibraryStatus {
        switch self {
        case .unreadable: .unreadable
        case .corrupt: .corrupt
        case .unknownSchema: .unknownSchema
        }
    }
}

/// 복구할 때 변환본 폴더의 모양
enum RecoveryPackFiles: String, CaseIterable, Sendable {
    case allGood, someBroken, none
}

private func libraryURL(_ h: Harness) -> URL { h.sandbox.library.appendingPathComponent("library.json") }

/// 목록을 망가뜨리고, 망가진 뒤의 원래 바이트를 돌려준다(보관본과 비교)
private func damage(_ h: Harness, _ kind: LibraryDamage) throws -> Data {
    let url = libraryURL(h)
    switch kind {
    case .unreadable:
        let data = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        return data
    case .corrupt:
        let data = Data("{ 망가짐".utf8)
        try data.write(to: url)
        return data
    case .unknownSchema:
        let data = Data(#"{"schema":99,"revision":3,"order":["user"],"packs":{},"future":{"x":1}}"#.utf8)
        try data.write(to: url)
        return data
    }
}

private func packFileName(_ h: Harness, of id: String) throws -> String {
    let names = try FileManager.default.contentsOfDirectory(atPath: h.sandbox.library.appendingPathComponent("packs").path)
    return try #require(names.first { $0.hasPrefix(id + "-r") })
}

private func overwritePackFile(_ h: Harness, of id: String, with data: Data) throws {
    let name = try packFileName(h, of: id)
    try data.write(to: h.sandbox.library.appendingPathComponent("packs").appendingPathComponent(name))
}

/// 변환본 폴더의 파일 이름들 — 폴더가 없으면(팩을 가져온 적이 없다) 빈 집합
private func packFileNames(_ h: Harness) -> Set<String> {
    Set((try? FileManager.default.contentsOfDirectory(atPath: h.sandbox.library.appendingPathComponent("packs").path)) ?? [])
}

/// 2026-10-06 07:42:22 UTC — 보관본 이름이 이 시각으로 정해진다
private let recoveryTime = Date(timeIntervalSince1970: 1_791_272_542)

@Suite("외부 채움글 1-c 2단계 — 목록 상태·복구 (㉡ · R24)")
struct LibraryRecoveryTests {

    @Test("★ ㉡ — 목록 상태는 사유를 가른다(지금까지는 셋 다 nil이었다)", arguments: LibraryDamage.allCases)
    func statusKinds(_ kind: LibraryDamage) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        #expect(h.store.libraryStatus() == .readable, "파일이 없으면 처음 상태 — 읽힘")
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        #expect(h.store.libraryStatus() == .readable)
        _ = try damage(h, kind)
        #expect(h.store.libraryStatus() == kind.status)
        #expect(!h.store.isLibraryReadable)
        #expect(h.store.recoveryPreview() == 1)
    }

    @Test("★ R24 — 복구: 손상 3종 × 변환본(정상·일부 깨짐·0개) — 원래 목록 보관·모두 꺼짐·표시 칸 채움·깨진 팩은 읽을 수 없음",
          arguments: LibraryDamage.allCases, RecoveryPackFiles.allCases)
    func recover(_ kind: LibraryDamage, _ files: RecoveryPackFiles) throws {
        let h = Harness(user: [entry("원래")])
        defer { h.sandbox.cleanup() }
        var ids: [String] = []
        if files == .none {
            #expect(h.store.saveUserSnippet(entry("둘째"), editing: nil).isAccepted)   // 목록 파일이 생긴다
        } else {
            ids.append(try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv)))
            ids.append(try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 3), source: .csv)))
            ids.append(try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv, enabled: false)))
        }
        if files == .someBroken { try overwritePackFile(h, of: ids[1], with: Data("{ 깨짐".utf8)) }
        let packFilesBefore = packFileNames(h)
        let original = try damage(h, kind)
        let userBefore = h.user.entries()
        let packsGeneration = h.generations.packsGeneration
        let notified = h.notifications.next()

        #expect(h.store.recoveryPreview() == ids.count)
        guard case .recovered(let count, let unreadable, let backupName) = h.store.recoverLibrary(now: recoveryTime) else {
            Issue.record("복구돼야 한다"); return
        }
        #expect(count == ids.count)
        #expect(unreadable == (files == .someBroken ? 1 : 0))

        // 원래 목록은 지우지 않고 옆에 보관한다 — 이름 규칙 library.damaged-<UTC>.json
        #expect(backupName == "library.damaged-20261006T074222Z.json")
        let backupURL = h.sandbox.library.appendingPathComponent(try #require(backupName))
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: backupURL.path)
        #expect(try Data(contentsOf: backupURL) == original)

        // 새 목록 — 읽힌다·「내 채움글」이 맨 위·모두 꺼짐
        #expect(h.store.libraryStatus() == .readable)
        #expect(h.store.order.first == .userSnippets)
        let summaries = h.store.summaries()
        #expect(Set(summaries.map(\.id)) == Set(ids))
        #expect(summaries.allSatisfy { !$0.isEnabled })
        for summary in summaries {
            if files == .someBroken, summary.id == ids[1] {
                #expect(summary.status == .unavailable, "깨진 변환본은 읽을 수 없는 팩으로")
                #expect(summary.name == nil)
            } else {
                #expect(summary.status == .off)
                #expect(summary.name != nil, "표시 칸은 변환본에서 채운다")
            }
        }
        if files == .allGood {
            #expect(summaries.map(\.id) == ids, "가져온 순서(r 번호)대로")
            #expect(summaries.map(\.name) == ["회사 상용구", "사자성어 예시 팩", "상용 영어"])
            #expect(summaries[1].titleFormat == "사자성어 {n}번" && summaries[1].mode == .numbered && summaries[1].itemCount == 3)
        }

        // snapshot·세대·알림 — 키보드는 외부 팩 0, 내 채움글 그대로
        #expect(h.generations.packsGeneration == packsGeneration + 1)
        #expect(h.notifications.next() == notified + 2, "알림 1회")
        #expect(try h.manifest().packs.isEmpty)
        #expect(h.user.entries() == userBefore)
        #expect(h.load().userEntries == userBefore && h.load().dropped == nil)
        // 변환본은 하나도 지우지 않았다
        #expect(packFileNames(h) == packFilesBefore)

        // 복구 뒤에는 커밋이 다시 된다 — 멀쩡한 팩은 켜지고, 깨진 팩은 켤 수 없다
        #expect(h.store.saveUserSnippet(entry("새것"), editing: nil).isAccepted)
        if files != .none { #expect(h.store.setPackEnabled(ids[0], enabled: true).isAccepted) }
        if files == .someBroken {
            #expect(h.store.setPackEnabled(ids[1], enabled: true) == .rejected(.packUnavailable(ids[1]), rechecked: false))
        }
        #expect(h.store.recoverLibrary(now: recoveryTime) == .notNeeded, "멀쩡한 목록은 건드리지 않는다")
    }

    @Test("목록이 멀쩡하면 복구하지 않는다 — 미리보기 nil, 아무것도 바꾸지 않음")
    func notNeeded() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let before = (h.store.revision, h.generations.packsGeneration, try Data(contentsOf: libraryURL(h)))
        #expect(h.store.recoveryPreview() == nil)
        #expect(h.store.recoverLibrary() == .notNeeded)
        #expect((h.store.revision, h.generations.packsGeneration, try Data(contentsOf: libraryURL(h))) == before)
    }

    @Test("★ 실패해도 원래 목록은 그대로 — 옆으로 옮기지 못하면 아무것도 쓰지 않고, 새 snapshot을 못 쓰면 원래 자리로 되돌린다")
    func failureKeepsOriginal() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let original = try damage(h, .corrupt)
        let packsGeneration = h.generations.packsGeneration

        // ① 목록 폴더에 쓸 수 없다 — 옮기지 못한다
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.library.path)
        #expect(h.store.recoverLibrary(now: recoveryTime) == .failed)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.library.path)
        #expect(try Data(contentsOf: libraryURL(h)) == original)

        // ② snapshot을 쓸 수 없다 — 옮겼던 목록을 제자리로
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.snapshot.path)
        #expect(h.store.recoverLibrary(now: recoveryTime) == .failed)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.snapshot.path)
        #expect(try Data(contentsOf: libraryURL(h)) == original)
        let names = try FileManager.default.contentsOfDirectory(atPath: h.sandbox.library.path)
        #expect(!names.contains { $0.hasPrefix("library.damaged") }, "보관본이 남지 않는다(제자리로 돌아갔다)")
        #expect(h.generations.packsGeneration == packsGeneration)
        #expect(h.store.libraryStatus() == .corrupt)
    }

    @Test("같은 팩의 옛 변환본이 남아 있으면 가장 최근 것(r 번호가 큰 것)으로 — 같은 시각의 보관본 이름은 겹치지 않는다")
    func newestRevisionAndUniqueBackup() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("옛 이름", chars: 10), source: .csv))
        #expect(h.store.replacePack(a, with: pack("새 이름", chars: 10), source: .csv).isAccepted)
        // 정리되기 전에 앱이 죽어 옛 변환본이 남은 것처럼
        let old = try JSONEncoder().encode(StoredExternalPack(packID: a, source: .csv, pack: pack("옛 이름", chars: 10)))
        try old.write(to: h.sandbox.library.appendingPathComponent("packs").appendingPathComponent("\(a)-r1.json"))
        _ = try damage(h, .corrupt)
        try Data("다른 보관본".utf8).write(to: h.sandbox.library.appendingPathComponent("library.damaged-20261006T074222Z.json"))
        guard case .recovered(1, 0, let backupName) = h.store.recoverLibrary(now: recoveryTime) else {
            Issue.record("복구돼야 한다"); return
        }
        #expect(backupName == "library.damaged-20261006T074222Z-2.json")
        #expect(h.store.summaries().map(\.name) == ["새 이름"])
    }

    @Test("★ 검증 F-1 — 복구 순서는 변환본 이름의 r 번호(쓴 차례)다 — 파일 수정 시각·이름 순과 무관(수정 시각을 읽지 않는다, PDR 1-d)")
    func recoveryOrderFollowsRevision() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("가 팩", chars: 10), source: .csv))   // r1
        let b = try h.importedID(h.store.importPack(pack("나 팩", chars: 10), source: .csv))   // r2
        let c = try h.importedID(h.store.importPack(pack("다 팩", chars: 10), source: .csv))   // r3
        #expect(h.store.replacePack(a, with: pack("가 새 팩", chars: 10), source: .csv).isAccepted)   // a → r4
        let packs = h.sandbox.library.appendingPathComponent("packs")
        let files = try [a, b, c].map { try packFileName(h, of: $0) }
        #expect(files.sorted() == files, "이름 순은 a·b·c — r 번호 순(b·c·a)과 다르다")
        // 수정 시각은 a·c·b 순으로 — 시각으로 정렬하면 이 순서가 나온다(시험만 시각을 만진다)
        for (file, seconds) in zip(files, [1_000.0, 3_000, 2_000]) {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: seconds)],
                                                  ofItemAtPath: packs.appendingPathComponent(file).path)
        }
        _ = try damage(h, .corrupt)
        guard case .recovered(3, 0, _) = h.store.recoverLibrary(now: recoveryTime) else {
            Issue.record("복구돼야 한다"); return
        }
        #expect(h.store.summaries().map(\.id) == [b, c, a], "r2 · r3 · r4")
        #expect(h.store.summaries().map(\.name) == ["나 팩", "다 팩", "가 새 팩"])
    }

    @Test("★ F-2 — 복구는 변환본 파일의 stats를 믿지 않고 다시 센다 — 앱 판정 == 키보드(AC-8, 검증 탐침 P2)")
    func recoveryRecountsStats() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 150), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("상용 영어", chars: 150), source: .csv, enabled: false))
        // B 변환본의 stats만 작게 — 내용(키보드가 다시 세는 값)은 그대로(옛 버전의 계산·JSON 모양을 지킨 손상과 같다)
        let url = h.sandbox.library.appendingPathComponent("packs").appendingPathComponent(try packFileName(h, of: b))
        var stored = try JSONDecoder().decode(StoredExternalPack.self, from: Data(contentsOf: url))
        stored.stats.needleChars = 1
        try JSONEncoder().encode(stored).write(to: url)
        _ = try damage(h, .corrupt)
        guard case .recovered(2, 0, _) = h.store.recoverLibrary(now: recoveryTime) else {
            Issue.record("복구돼야 한다"); return
        }
        #expect(h.store.setPackEnabled(a, enabled: true).isAccepted)
        #expect(!h.store.setPackEnabled(b, enabled: true).isAccepted, "다시 세면 150 + 150 > 200 — 켤 수 없다")
        #expect(h.load().includedPackIDs == [a])
        #expect(h.load().includedPackIDs == h.store.evaluation().included, "AC-8 — 앱 판정 == 키보드")
    }

    @Test("★ F-6 — 복구 뒤 revision은 남은 변환본의 가장 큰 r 위로 잇는다 — 정리 전에 남은 옛 변환본이 다음 복구에서 「최신」으로 뽑히지 않게")
    func recoveryContinuesRevision() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let packs = h.sandbox.library.appendingPathComponent("packs")
        let a = try h.importedID(h.store.importPack(pack("옛 이름", chars: 10), source: .csv))                 // r1
        for index in 0..<4 { #expect(h.store.saveUserSnippet(entry("문구\(index)"), editing: nil).isAccepted) }  // r2~r5
        #expect(h.store.replacePack(a, with: pack("중간 이름", chars: 10), source: .csv).isAccepted)             // r6
        let middle = try packFileName(h, of: a)
        let middleData = try Data(contentsOf: packs.appendingPathComponent(middle))
        _ = try damage(h, .corrupt)
        guard case .recovered = h.store.recoverLibrary(now: recoveryTime) else { Issue.record("복구돼야 한다"); return }
        #expect(h.store.revision > PackStore.packFileIdentity(middle).revision, "남은 변환본 번호 위로 — 1부터 다시 시작하지 않는다")

        // 복구 뒤 교체 — 정리(옛 파일 지우기) 전에 앱이 죽어 옛 변환본이 남은 것처럼 되살리고, 목록이 또 망가진다
        #expect(h.store.replacePack(a, with: pack("새 이름", chars: 10), source: .csv).isAccepted)
        try middleData.write(to: packs.appendingPathComponent(middle))
        _ = try damage(h, .corrupt)
        guard case .recovered(1, 0, _) = h.store.recoverLibrary(now: recoveryTime) else { Issue.record("복구돼야 한다"); return }
        #expect(h.store.summaries().map(\.name) == ["새 이름"], "복구 뒤 쓴 변환본이 옛 것보다 번호가 커야 한다")
    }
}

// MARK: - 1-c 2단계 — 앱 실행 검사 (G6 · G9)

enum BrokenContent: String, CaseIterable, Sendable {
    /// JSON이 아니다
    case garbage
    /// 이 앱이 모르는 변환본 schema
    case unknownSchema
    /// 다른 팩의 id
    case wrongPackID
    /// 디코드는 되는데 필드 상한을 넘는다(이름 41자)
    case overFieldLimit

    func data(id: String) throws -> Data {
        switch self {
        case .garbage: return Data("{ 깨짐".utf8)
        case .unknownSchema:
            var stored = StoredExternalPack(packID: id, source: .csv, pack: pack("회사 상용구", chars: 10))
            stored.schema = 2
            return try JSONEncoder().encode(stored)
        case .wrongPackID:
            return try JSONEncoder().encode(StoredExternalPack(packID: "다른팩", source: .csv, pack: pack("회사 상용구", chars: 10)))
        case .overFieldLimit:
            return try JSONEncoder().encode(StoredExternalPack(
                packID: id, source: .csv, pack: pack(String(repeating: "가", count: 41), chars: 10)))
        }
    }
}

@Suite("외부 채움글 1-c 2단계 — 앱 실행 검사 (G6 내용 깨진 팩 · G9 세대)")
struct PackContentCheckTests {

    @Test("★ G6·AC-8 — 내용이 깨진 변환본은 그 팩만 「읽을 수 없어요」로, snapshot을 다시 써 키보드가 나머지 팩을 싣는다",
          arguments: BrokenContent.allCases)
    func brokenPackOnly(_ kind: BrokenContent) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv))
        try overwritePackFile(h, of: a, with: kind.data(id: a))
        // 다음 커밋이 깨진 변환본을 snapshot에 복사한다 — 키보드는 외부 팩 전부를 뺀다(AC-8), 앱은 아직 모른다
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)
        #expect(h.load().dropped != nil)
        #expect(h.store.summaries().map(\.status) == [.on, .on], "검사 전")

        let packsGeneration = h.generations.packsGeneration
        h.store.maintain()
        #expect(h.store.summaries().map(\.status) == [.unavailable, .on])
        #expect(h.generations.packsGeneration == packsGeneration + 1, "포함 목록이 바뀌어 snapshot을 다시 썼다")
        let loaded = h.load()
        #expect(loaded.dropped == nil)
        #expect(loaded.includedPackIDs == [b])
        #expect(loaded.includedPackIDs == h.store.evaluation().included, "AC-8 — 앱 판정 == 키보드")
        #expect(h.store.setPackEnabled(a, enabled: false).isAccepted)
        #expect(h.store.setPackEnabled(a, enabled: true) == .rejected(.packUnavailable(a), rechecked: false))
    }

    @Test("★ 검사 결과는 파일 이름 기준으로 남는다 — 다시 실행해도(새 PackStore) 검사 전부터 그 팩을 빼고, 바꿔 넣으면(새 파일) 풀린다")
    func persistedByFileName() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        try overwritePackFile(h, of: a, with: BrokenContent.garbage.data(id: a))
        h.store.maintain()
        let reopened = h.reopenedStore()
        #expect(reopened.summaries().first?.status == .unavailable, "다시 실행 — 검사 전부터")
        #expect(reopened.replacePack(a, with: pack("회사 상용구", chars: 12), source: .csv).isAccepted)
        #expect(reopened.summaries().first?.status == .on, "새 변환본은 새 이름 — 검사 결과가 따라가지 않는다")
        reopened.maintain()
        #expect(reopened.summaries().first?.status == .on)
    }

    @Test("★ F-1 — snapshot 다시 쓰기가 한 번 실패해도 다음 실행이 다시 쓴다(판정 ≠ 지금 snapshot이면 쓴다 — 검증 탐침 P1)")
    func republishRetriesAfterFailedWrite() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv))
        try overwritePackFile(h, of: a, with: BrokenContent.garbage.data(id: a))
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)
        #expect(h.load().dropped != nil, "준비 — 깨진 변환본이 snapshot에 실려 키보드가 외부 팩 전부를 버린다")

        // 검사는 했는데 snapshot을 못 쓴다(저장 공간 부족·쓰는 사이 앱 종료와 같다) — 검사 결과는 이미 파일에 남았다
        let packsGeneration = h.generations.packsGeneration
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.snapshot.path)
        h.store.maintain()
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.snapshot.path)
        #expect(h.generations.packsGeneration == packsGeneration, "쓰지 못했다")
        #expect(h.load().dropped != nil)

        // 다음 실행 — 「검사 전 == 검사 후」(이미 A를 뺀 판정)여도 지금 snapshot이 판정과 다르므로 다시 쓴다
        h.reopenedStore().maintain()
        #expect(h.generations.packsGeneration == packsGeneration + 1)
        let loaded = h.load()
        #expect(loaded.dropped == nil)
        #expect(loaded.includedPackIDs == [b])
        #expect(loaded.includedPackIDs == h.store.evaluation().included, "AC-8 — 앱 판정 == 키보드")
    }

    @Test("★ (e) — 검사 결과는 파일 이름 + 크기로 맞춘다: 검사 뒤 같은 이름의 파일이 바뀌면(크기 다름) 다음 실행이 다시 검사한다")
    func recheckWhenFileChangesInPlace() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv))
        h.store.maintain()   // 둘 다 멀쩡 — 「받음」 결과가 남는다
        #expect(h.store.summaries().map(\.status) == [.on, .on])
        // 같은 이름 그대로 내용이 바뀐다(디스크 손상·잘림과 같다) — 이름만 보면 옛 「받음」을 그대로 믿는다
        try overwritePackFile(h, of: a, with: BrokenContent.garbage.data(id: a))
        let reopened = h.reopenedStore()
        reopened.maintain()
        #expect(reopened.summaries().map(\.status) == [.unavailable, .on])
        #expect(h.load().includedPackIDs == [b])
        #expect(h.load().includedPackIDs == reopened.evaluation().included, "AC-8")
    }

    @Test("멀쩡한 팩만 있으면 검사가 snapshot을 다시 쓰지 않는다 · 꺼진 팩이 깨져도 포함 목록이 같으면 다시 쓰지 않는다")
    func noRepublishWhenNothingChanges() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let packsGeneration = h.generations.packsGeneration
        h.store.maintain()
        #expect(h.generations.packsGeneration == packsGeneration)

        let h2 = Harness()
        defer { h2.sandbox.cleanup() }
        _ = try h2.importedID(h2.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let off = try h2.importedID(h2.store.importPack(pack("상용 영어", chars: 10), source: .csv, enabled: false))
        try overwritePackFile(h2, of: off, with: BrokenContent.garbage.data(id: off))
        let packsGeneration2 = h2.generations.packsGeneration
        h2.store.maintain()
        #expect(h2.generations.packsGeneration == packsGeneration2)
        #expect(h2.store.summaries().map(\.status) == [.on, .unavailable])
    }

    @Test("★ G9 — maintain은 실행 때마다 userSnippetsGeneration을 한 번 올리고 알린다")
    func bumpsUserGeneration() {
        let h = Harness(user: [entry("문구")])
        defer { h.sandbox.cleanup() }
        let before = h.generations.userSnippetsGeneration
        let notified = h.notifications.next()
        h.store.maintain()
        #expect(h.generations.userSnippetsGeneration == before + 1)
        #expect(h.notifications.next() == notified + 2, "알림 1회")
        #expect(h.load().userSnippetsGeneration == before + 1)
    }
}

// MARK: - 1-c 2단계 — 정리 모델 (㉠ · R25)

@Suite("외부 채움글 1-c 2단계 — 한도 넘은 내 채움글 정리 (㉠ · R25)")
struct UserSnippetBudgetTests {

    @Test("★ R25 — 경계는 키보드 로더와 같은 개수(같은 함수 userSnippetUsage), 지우면 다시 판정해 한도 안이면 경계가 없다")
    func boundaryMatchesKeyboard() throws {
        let legacy = (0..<30).map { entry(String(repeating: "다", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }   // 300 > 200
        let h = Harness(user: legacy)
        defer { h.sandbox.cleanup() }
        let budget = h.store.userSnippetBudget()
        #expect(budget.isOverLimit)
        #expect(budget.loadableCount == h.load().userEntries.count)
        #expect(budget.loadableCount == 20)
        #expect(budget.loadableRowCount == 20 && budget.entries.count == 30 && budget.hasBoundary)
        // 한 항목씩 지운다(R25 — 일괄 삭제 없음) — 지울 때마다 다시 판정
        for (index, item) in legacy.suffix(10).enumerated() {
            #expect(h.store.deleteUserSnippet(item).isAccepted)
            let again = h.store.userSnippetBudget()
            #expect(again.loadableCount == h.load().userEntries.count, "\(index)")
            #expect(again.isOverLimit == (index < 9))
        }
        let done = h.store.userSnippetBudget()
        #expect(!done.hasBoundary && done.loadableRowCount == 20 && done.entries.count == 20)
    }

    @Test("내장 팩 몫까지 같이 본다 — 켜진 내장이 크면 경계가 앞당겨지고, 끄면 없어진다(키보드와 같은 입력)")
    func builtInCounts() {
        let user = (0..<6).map { entry(String(repeating: "라", count: 9) + String(UnicodeScalar(0xAC00 + $0)!)) }   // 60자
        let h = Harness(user: user, builtIn: [entry(String(repeating: "애", count: 150))])
        defer { h.sandbox.cleanup() }
        #expect(h.store.userSnippetBudget().isOverLimit, "내 채움글만으로는 60자지만 켜진 내장 몫까지 넘는다 — 배너 ㉠ 대상(V12)")
        #expect(h.store.userSnippetBudget().loadableCount == 5)
        #expect(h.store.userSnippetBudget().loadableCount == h.load().userEntries.count)
        h.disabled.current = ["anthem"]
        #expect(!h.store.userSnippetBudget().isOverLimit)
        #expect(h.store.userSnippetBudget().loadableCount == 6)
    }

    @Test("★ 경계는 화면 행으로 옮긴다 — 화면은 정규화 단축어가 같은 옛 중복을 한 행(첫 자리)으로 보이므로 경계도 행 수로")
    func boundaryInDisplayRows() {
        let a = entry("우리집주소"), a2 = entry("우리집 주소", body: "옛 중복"), b = entry("회사"), c = entry("인사"), d = entry("주소")
        let budget = UserSnippetBudget(stored: [a, a2, b, c, d], loadableCount: 3, isOverLimit: true)
        #expect(budget.entries == [a, b, c, d])
        #expect(budget.loadableRowCount == 2, "앞 3개(a, a2, b)는 화면에서 두 행")
        let late = UserSnippetBudget(stored: [a, b, c, a2], loadableCount: 2, isOverLimit: true)
        #expect(late.entries == [a, b, c] && late.loadableRowCount == 2)
        let fine = UserSnippetBudget(stored: [a, b], loadableCount: 2, isOverLimit: false)
        #expect(!fine.hasBoundary && fine.loadableRowCount == 2)
        #expect(UserSnippetBudget.displayEntries([a, a2, b]) == [a, b], "설정 화면 목록과 같은 중복 제거")
    }
}

// MARK: - 1-c 3단계 — 영향 계산 읽기·팩 상세 (G3 · 2-E · U1)

@Suite("외부 채움글 1-c 3단계 — 영향 계산 읽기·팩 상세 (G3 · 2-E · U1)")
struct PackImpactStoreTests {

    @Test("★ impactLibrary — 목록 순서·읽기 모델·문구형 단축어·번호형 틀·revision을 한 번에. 읽을 수 없는 팩은 내용 없이")
    func impactLibraryReadsEverything() throws {
        let user = [entry("주소")]
        let h = Harness(user: user, builtIn: [entry("새해인사")], limits: .candidate)
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 50), source: .csv))
        let b = try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 12), source: .csv, enabled: false))
        let c = try h.importedID(h.store.importPack(pack("못읽음", chars: 10), source: .csv))
        try removePackFiles(h, of: c)
        let library = try #require(h.store.impactLibrary())
        #expect(library.revision == h.store.revision)
        #expect(library.order == h.store.order)
        #expect(library.packs.map(\.summary) == h.store.summaries(), "목록 행과 같은 읽기 모델")
        #expect(library.packs[0].triggers == pack("회사 상용구", chars: 50).entries.flatMap(\.triggers))
        #expect(library.packs[1].patterns == [TemplatePattern(prefix: "사자성어", suffix: "번")])
        #expect(library.packs[2].triggers.isEmpty && library.packs[2].patterns.isEmpty, "읽을 수 없는 팩은 열지 않는다")
        #expect(library.userTriggers == ["주소"] && library.builtInTriggers == ["새해인사"])
        #expect(library.userSnippetCount == 1)
        #expect([a, b, c] == library.packs.map(\.id))
    }

    @Test("목록을 읽을 수 없으면 nil — 순서 화면을 열지 않는다(E1)")
    func impactLibraryNilWhenUnreadable() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        try Data("{ 망가짐".utf8).write(to: h.sandbox.library.appendingPathComponent("library.json"))
        #expect(h.store.impactLibrary() == nil)
        #expect(h.store.packDetail("pack1") == nil)
    }

    /// 순서 — 0·1·2는 팩 a·b·c, -1은 「내 채움글」 줄. 시작 상태: a(70)·b(50) 포함, c(60)는 켠 채 쉬는 중(내 채움글 30 때문에)
    static let reorderCases: [[Int]] = [
        [-1, 2, 0, 1], [-1, 1, 2, 0], [-1, 0, 1, 2], [-1, 2, 1, 0], [-1, 1, 0, 2], [-1, 0, 2, 1],
        [2, -1, 0, 1], [0, 1, 2, -1], [1, 2, -1, 0]
    ]

    @Test("★ G3 == 커밋 — 사전 안내의 「쉬게 될 팩」이 실제 reorder가 돌려준 newlyExcluded와 같다(같은 판정 함수)",
          arguments: reorderCases)
    func restingMatchesCommit(_ permutation: [Int]) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        // 한도 needleChars 200 — 셋 다 켜도 180이라 들어간다
        let ids = [try h.importedID(h.store.importPack(pack("가", chars: 70), source: .csv)),
                   try h.importedID(h.store.importPack(pack("나", chars: 50), source: .csv)),
                   try h.importedID(h.store.importPack(pack("다", chars: 60), source: .csv))]
        // 내 채움글 30자를 저장하면 맨 아래 c가 한도 밖으로 — 받고 쉬게 한다(R14)
        guard case .accepted(let saved) = h.store.saveUserSnippet(entry(String(repeating: "내", count: 30)), editing: nil) else {
            Issue.record("내 채움글 저장은 외부 팩 때문에 막히지 않는다")
            return
        }
        #expect(saved.newlyExcluded == [ids[2]])
        let library = try #require(h.store.impactLibrary())
        let order: [SnippetSourceSlot] = permutation.map { $0 < 0 ? .userSnippets : .pack(ids[$0]) }
        let preview = PackImpact.of(PackImpact.Proposal(order: order), in: library)
        guard case .accepted(let accepted) = h.store.reorder(order, expectedRevision: library.revision) else {
            Issue.record("순서 바꾸기는 거부가 없다")
            return
        }
        #expect(preview.restingPacks == accepted.newlyExcluded)
        #expect(!accepted.rechecked)
        // 표가 실제로 쉬는 경우를 덮는지 — c를 a·b 사이나 앞에 두면 뒤 팩이 밀린다
        let cIndex = permutation.filter { $0 >= 0 }.firstIndex(of: 2)
        #expect(accepted.newlyExcluded.isEmpty == (cIndex == 2))
    }

    @Test("★ packDetail — 권리·사용 예·자리. 번호형 예시는 첫 항목을 첫 틀 원문으로, 문구형은 처음 셋")
    func packDetailNumbered() throws {
        let h = Harness(user: [entry("장")], limits: .candidate)
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 12), source: .csv))
        let detail = try #require(h.store.packDetail(a))
        #expect(detail.summary.name == "사자성어 예시 팩")
        #expect(detail.license == "자체 작성")
        #expect(detail.examples == [.init(trigger: "사자성어 1번", title: "사자성어 1번", body: "예시 본문 1")], "제목이 빈 항목은 틀로 채운 제목(칩과 같다)")
        #expect(detail.standing?.patterns.map(\.status) == [.owned(sharedWith: [])])
        #expect(detail.name(of: a) == "사자성어 예시 팩")
        #expect(h.store.packDetail("없는 팩") == nil)

        let phrasesID = try h.importedID(h.store.importPack(ExternalPack(name: "회사 상용구", license: "총무팀", mode: .phrases, entries: [
            SnippetEntry(triggers: ["장", "회사장"], title: "장 제목", body: "본문"), SnippetEntry(trigger: "인사", title: "인사 제목", body: "본문"),
            SnippetEntry(trigger: "회의", title: "회의 제목", body: "본문"), SnippetEntry(trigger: "넷째", title: "넷째 제목", body: "본문")
        ]), source: .csv))
        let phrasesDetail = try #require(h.store.packDetail(phrasesID))
        // 화면 확인 O-1 — 내 채움글에 밀린 「장」 대신 같은 항목의 안 밀린 단축어 「회사장」을 보인다
        #expect(phrasesDetail.examples == [.init(trigger: "회사장", title: "장 제목", body: "본문"), .init(trigger: "인사", title: "인사 제목", body: "본문"),
                                           .init(trigger: "회의", title: "회의 제목", body: "본문")])
        #expect(phrasesDetail.standing?.hiddenTriggers == [.init(trigger: "장", owner: .userSnippets)], "내 채움글이 위라 「장」은 뒤 순서")
    }

    @Test("읽을 수 없는 팩의 상세 — 이름·상태는 목록에서, 권리·예시·자리는 없다(열지 않는다)")
    func packDetailUnavailable() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        try removePackFiles(h, of: a)
        let detail = try #require(h.store.packDetail(a))
        #expect(detail.summary.status == .unavailable && detail.summary.name == "회사 상용구")
        #expect(detail.license == nil && detail.examples.isEmpty && detail.standing == nil)
    }

    @Test("★ R31 packEntries — 꺼진 팩도 모든 항목(상세의 항목 수와 같다), 읽을 수 없는 팩·없는 팩은 nil(전체 보기가 없다)")
    func packEntries() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let off = try h.importedID(h.store.importPack(numbered("사자성어 예시 팩", count: 12), source: .csv, enabled: false))
        let list = try #require(h.store.packEntries(off))
        #expect(list.rows.map(\.trigger) == (1...12).map { "사자성어 \($0)번" })
        #expect(list.rows.map(\.result) == (1...12).map { "→ 예시 본문 \($0)" })
        #expect(list.rows.count == h.store.packDetail(off)?.summary.itemCount, "「전체 보기 (n개)」의 n과 줄 수가 같다")
        #expect(h.store.packDetail(off)?.summary.status == .off)

        let unreadable = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        try removePackFiles(h, of: unreadable)
        #expect(h.store.packEntries(unreadable) == nil)
        #expect(h.store.packEntries("없는 팩") == nil)

        // 파일은 디코드되지만 내용 검사(G6)에 걸린 변환본 — 변환본을 여는 것만으로는 nil이 되지 않아 「읽을 수 없는 팩」 검사가 따로 막는다(검증 M21)
        let broken = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv))
        try overwritePackFile(h, of: broken, with: BrokenContent.overFieldLimit.data(id: broken))
        h.store.maintain()
        #expect(h.store.packDetail(broken)?.summary.status == .unavailable, "준비 — 앱 실행 검사가 읽을 수 없는 팩으로 남겼다")
        #expect(h.store.packEntries(broken) == nil)
    }
}

// MARK: - codex 반론(v1.3.0 앱) A1·A2·A5·A6 — 도중 종료·정리 실패·저장 팩 수

/// 시험이 만든 snapshot 세대 폴더를 쓰기 금지로(안의 파일을 지울 수 없게) — 정리 실패를 흉내 낸다. 시험 끝 `cleanup`이 권한을 되돌린다
private func lockGenerations(_ h: Harness, _ names: [String], writable: Bool) throws {
    for name in names {
        try FileManager.default.setAttributes([.posixPermissions: writable ? 0o755 : 0o555],
                                              ofItemAtPath: h.sandbox.snapshot.appendingPathComponent(name).path)
    }
}

@Suite("codex 반론 v1.3.0 앱 A1 — 목록이 없는데 팩 파일·복구 기록이 있으면 빈 목록이 아니다")
struct MissingLibraryTests {

    @Test("★ A1 — 옛 복구가 목록을 옮긴 뒤 종료(보관본 있음)·목록만 사라짐(보관본 없음): 다음 실행이 팩 파일을 지우지 않고 복구 안내로",
          arguments: [true, false])
    func missingLibraryNeedsRecovery(withBackup: Bool) throws {
        let h = Harness(user: [entry("원래")])
        defer { h.sandbox.cleanup() }
        let a = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        let b = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv))
        let c = try h.importedID(h.store.importPack(pack("꺼 둔 팩", chars: 10), source: .csv, enabled: false))
        let files = packFileNames(h)
        if withBackup {
            try FileManager.default.moveItem(at: libraryURL(h),
                                             to: h.sandbox.library.appendingPathComponent("library.damaged-20261006T074222Z.json"))
        } else {
            try FileManager.default.removeItem(at: libraryURL(h))
        }

        let reopened = h.reopenedStore()
        reopened.maintain()
        #expect(packFileNames(h) == files, "변환본을 하나도 지우지 않는다 — 꺼진 팩은 공유 사본도 없다")
        #expect(reopened.libraryStatus() == .missing)
        #expect(!reopened.isLibraryReadable)
        #expect(PackNoticeCopy.libraryBanner(.missing) == PackNoticeCopy.libraryBanner(.corrupt), "1-c AC-5 — 같은 복구 안내")
        #expect(PackNoticeCopy.externalSectionFooter(isEmpty: true, libraryStatus: .missing) == PackNoticeCopy.unreadableListFooter)
        #expect(h.load().includedPackIDs == [a, b], "키보드는 마지막 snapshot 그대로 — 빈 snapshot으로 덮지 않는다")
        #expect(reopened.importPack(pack("새 팩", chars: 10), source: .csv) == .rejected(.libraryUnreadable, rechecked: false),
                "빈 목록으로 판정해 새 목록을 쓰지 않는다")
        #expect(!FileManager.default.fileExists(atPath: libraryURL(h).path))

        #expect(reopened.recoveryPreview() == 3)
        guard case .recovered(3, 0, _) = reopened.recoverLibrary(now: recoveryTime) else { Issue.record("복구돼야 한다"); return }
        #expect(reopened.summaries().map(\.id) == [a, b, c])
        #expect(reopened.libraryStatus() == .readable)
        #expect(packFileNames(h) == files)
    }

    @Test("A1 — 처음 가져오기가 목록 쓰기 전에 끝나도 「목록 없음」 오탐이 아니다(처음 커밋은 목록을 먼저 만든다) — 남은 변환본은 정리")
    func firstImportInterruptedIsNotMissing() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        h.store.crashPointForTesting = .beforeLibrary
        _ = h.store.importPack(pack("회사 상용구", chars: 10), source: .csv)
        #expect(!packFileNames(h).isEmpty, "준비 — 커밋 전 변환본이 남았다")
        let reopened = h.reopenedStore()
        #expect(reopened.libraryStatus() == .readable)
        reopened.maintain()
        #expect(packFileNames(h).isEmpty, "커밋되지 않은 가져오기의 변환본은 정리")
        #expect(reopened.recoveryPreview() == nil)
        #expect(reopened.importPack(pack("다시", chars: 10), source: .csv).isAccepted)
    }

    @Test("★ A1 — 새 복구는 원래 목록을 옮기지 않는다: 보관본을 만든 뒤 종료돼도 목록은 제자리, 다음 실행도 복구 안내",
          arguments: LibraryDamage.allCases)
    func recoveryKeepsOriginalUntilNewList(_ kind: LibraryDamage) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("회사 상용구", chars: 10), source: .csv))
        _ = try h.importedID(h.store.importPack(pack("상용 영어", chars: 10), source: .csv, enabled: false))
        let files = packFileNames(h)
        _ = try damage(h, kind)
        h.store.crashPointForTesting = .recoveryBeforeWrite
        _ = h.store.recoverLibrary(now: recoveryTime)
        #expect(FileManager.default.fileExists(atPath: libraryURL(h).path), "종료 지점 — 원래 목록이 제자리에 있다")

        let reopened = h.reopenedStore()
        reopened.maintain()
        #expect(reopened.libraryStatus() == kind.status)
        #expect(packFileNames(h) == files)
        guard case .recovered(2, 0, _) = reopened.recoverLibrary(now: recoveryTime) else { Issue.record("복구돼야 한다"); return }
        #expect(reopened.libraryStatus() == .readable)
        #expect(packFileNames(h) == files)
    }
}

@Suite("codex 반론 v1.3.0 앱 A2·A6 — 커밋 도중 종료·정리 실패 뒤 다음 실행이 마무리")
struct UnfinishedCommitTests {

    @Test("★ A2 — 바꾸기가 목록 뒤·세대 앞에서 끝나면 다음 실행이 다시 게시한다(순서가 같아도) — 앱 == 키보드, 옛 내용 0")
    func unfinishedReplaceIsRepublished() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("OLDMARK", chars: 10), source: .csv))
        let other = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))
        h.store.crashPointForTesting = .beforePacksGeneration
        _ = h.store.replacePack(id, with: pack("NEWMARK", chars: 12), source: .csv)
        #expect(h.store.summaries().first?.name == "NEWMARK", "준비 — 앱 목록은 새 내용")
        #expect(h.load().packs[id] == pack("OLDMARK", chars: 10), "준비 — 키보드는 옛 내용(같은 순서)")

        let reopened = h.reopenedStore()
        reopened.maintain()
        let loaded = h.load()
        #expect(loaded.packs[id] == pack("NEWMARK", chars: 12))
        #expect(loaded.includedPackIDs == [id, other])
        #expect(loaded.includedPackIDs == reopened.evaluation().included, "AC-8")
        #expect(try filesMentioning("OLDMARK", in: h).isEmpty, "A6 — 바꾸기 전 내용이 남은 파일 0")
        #expect(h.sandbox.generationNames() == ["g\(h.generations.packsGeneration)"])

        // 한 번 마무리하면 다음 실행은 다시 쓰지 않는다
        let generation = h.generations.packsGeneration
        h.reopenedStore().maintain()
        #expect(h.generations.packsGeneration == generation)
    }

    @Test("★ A6 — 지우기·바꾸기가 커밋 뒤·정리 전에 끝나면 다음 실행이 옛 snapshot 세대·변환본을 지운다", arguments: [true, false])
    func cleanupInterruptedIsFinishedOnLaunch(deletes: Bool) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let id = try h.importedID(h.store.importPack(pack("OLDMARK", chars: 10), source: .csv))     // g1
        let kept = try h.importedID(h.store.importPack(pack("KEEPMARK", chars: 10), source: .csv))  // g2
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)                    // g3
        h.store.crashPointForTesting = .beforeCleanup
        if deletes {
            _ = h.store.deletePack(id)
        } else {
            _ = h.store.replacePack(id, with: pack("NEWMARK", chars: 10), source: .csv)
        }
        #expect(try !filesMentioning("OLDMARK", in: h).isEmpty, "준비 — 정리 전 종료라 옛 내용이 남았다")

        let reopened = h.reopenedStore()
        reopened.maintain()
        #expect(try filesMentioning("OLDMARK", in: h).isEmpty, "옛 내용이 남은 파일 0(변환본·snapshot·검사 기록)")
        #expect(h.sandbox.generationNames() == ["g\(h.generations.packsGeneration)"], "지우기·바꾸기 세대만 남는다")
        #expect(h.load().includedPackIDs == (deletes ? [kept] : [id, kept]))

        // 그 뒤 평소 커밋은 지금 규칙 그대로 — 바로 앞 세대를 남긴다
        #expect(reopened.saveUserSnippet(entry("문구2"), editing: nil).isAccepted)
        #expect(h.sandbox.generationNames().count == 2)
    }

    @Test("★ A6 — 지우기 뒤 정리가 실패하면(옛 세대·변환본을 못 지움) 다음 실행이 다시 지운다")
    func failedCleanupIsRetriedOnLaunch() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let gone = try h.importedID(h.store.importPack(pack("DELMARK", chars: 10), source: .csv))   // g1
        let kept = try h.importedID(h.store.importPack(pack("KEEPMARK", chars: 10), source: .csv)) // g2
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)                    // g3
        let old = h.sandbox.generationNames()
        let packs = h.sandbox.library.appendingPathComponent("packs")
        try lockGenerations(h, old, writable: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: packs.path)
        #expect(h.store.deletePack(gone).isAccepted, "정리 실패는 커밋 실패가 아니다")
        try lockGenerations(h, old, writable: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: packs.path)
        #expect(try !filesMentioning("DELMARK", in: h).isEmpty, "준비 — 지우지 못한 옛 내용이 남았다")

        let reopened = h.reopenedStore()
        reopened.maintain()
        #expect(try filesMentioning("DELMARK", in: h).isEmpty, "다음 실행이 다시 지운다")
        #expect(h.sandbox.generationNames() == ["g\(h.generations.packsGeneration)"])
        #expect(h.load().includedPackIDs == [kept])
    }

    @Test("A6 — 정리 실패 뒤 다음 커밋도 다시 지운다(실행을 기다리지 않는다)")
    func failedCleanupIsRetriedOnNextCommit() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        let gone = try h.importedID(h.store.importPack(pack("DELMARK", chars: 10), source: .csv))
        _ = try h.importedID(h.store.importPack(pack("KEEPMARK", chars: 10), source: .csv))
        let old = h.sandbox.generationNames()
        try lockGenerations(h, old, writable: false)
        #expect(h.store.deletePack(gone).isAccepted)
        try lockGenerations(h, old, writable: true)
        #expect(h.store.saveUserSnippet(entry("문구"), editing: nil).isAccepted)
        #expect(try filesMentioning("DELMARK", in: h).isEmpty)
    }

    /// 다음 실행의 재게시가 실패하는 두 갈래 — 목록 쓰기 실패(앱 전용 폴더 쓰기 금지)·재게시 도중 종료
    enum RepublishFailure: CaseIterable, Sendable { case listWriteDenied, terminated }

    /// 지금 세대를 지우는 경로는 `maintain`의 `purgeBelow = 현재 + 1`(④–⑤ 사이에 끝난 지우기·바꾸기)뿐이고 평소엔 같은 실행의 재게시가
    /// 곧 덮는다 — 재게시가 실패할 때만 「지금 세대는 지우지 않는다」 가드가 키보드의 snapshot을 지킨다(검증 L-3 · AM1)
    @Test("★ A6 — 지우기가 목록 뒤·세대 앞에서 끝나고 다음 실행의 재게시도 실패하면 지금 세대는 남는다 — 키보드가 snapshot을 잃지 않는다",
          arguments: RepublishFailure.allCases)
    func currentGenerationSurvivesFailedRepublish(_ failure: RepublishFailure) throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.library.path) }
        let a = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))   // g1
        let b = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))   // g2
        h.store.crashPointForTesting = .beforePacksGeneration
        _ = h.store.deletePack(b)                                                     // 목록은 세대 3·purgeBelow 3, 세대는 2
        #expect(h.generations.packsGeneration == 2, "준비 — 커밋 지점 전 종료")

        let reopened = h.reopenedStore()
        switch failure {
        case .listWriteDenied:
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: h.sandbox.library.path)
        case .terminated:
            reopened.crashPointForTesting = .beforeLibrary
        }
        reopened.maintain()
        #expect(h.generations.packsGeneration == 2, "전제 — 재게시가 마무리되지 않았다")
        #expect(h.sandbox.generationNames().contains("g2"), "지금 세대는 purgeBelow 아래여도 지우지 않는다")
        #expect(h.load().includedPackIDs == [a, b], "키보드는 지금 세대를 그대로 읽는다 — 마무리는 다음 실행")

        // 다음 실행이 성공하면 마무리한다 — 지우기 세대만 남는다
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: h.sandbox.library.path)
        h.reopenedStore().maintain()
        #expect(h.generations.packsGeneration == 3)
        #expect(h.sandbox.generationNames() == ["g3"])
        #expect(h.load().includedPackIDs == [a])
    }

    @Test("A2 — 세대 뒤에 남은 고아 세대(커밋 지점 전 종료)는 다음 실행이 지운다 — 지금 세대·바로 앞 세대만 남는다")
    func orphanGenerationAboveCurrentIsRemoved() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))   // g1
        _ = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))   // g2
        h.store.crashPointForTesting = .beforePacksGeneration
        _ = h.store.saveUserSnippet(entry("문구"), editing: nil)                        // g3 폴더만
        #expect(h.sandbox.generationNames() == ["g1", "g2", "g3"])
        h.reopenedStore().maintain()
        #expect(h.generations.packsGeneration == 3, "마무리 게시")
        #expect(h.sandbox.generationNames() == ["g2", "g3"])
    }

    @Test("★ A2 — 목록을 쓰기 전에 끝난 가져오기의 고아 세대는 다시 게시하지 않아도 지운다 — 커밋 안 된 팩 내용이 공유 폴더에 남지 않는다")
    func uncommittedImportSnapshotIsRemoved() throws {
        let h = Harness()
        defer { h.sandbox.cleanup() }
        _ = try h.importedID(h.store.importPack(pack("가", chars: 10), source: .csv))   // g1
        _ = try h.importedID(h.store.importPack(pack("나", chars: 10), source: .csv))   // g2
        h.store.crashPointForTesting = .beforeLibrary
        _ = h.store.importPack(pack("UNCOMMITTED", chars: 10), source: .csv)          // 변환본·g3 폴더만
        #expect(h.sandbox.generationNames() == ["g1", "g2", "g3"])
        #expect(try !filesMentioning("UNCOMMITTED", in: h).isEmpty)
        h.reopenedStore().maintain()
        #expect(h.generations.packsGeneration == 2, "커밋되지 않았다 — 다시 게시할 것이 없다")
        #expect(h.sandbox.generationNames() == ["g1", "g2"])
        #expect(try filesMentioning("UNCOMMITTED", in: h).isEmpty, "변환본·고아 세대 모두")
    }
}

@Suite("codex 반론 v1.3.0 앱 A5 — 저장 팩 수는 목록 전체(꺼진 팩·읽을 수 없는 팩 포함)로 센다")
struct StoredPackCountTests {

    private static func sixteen(_ h: Harness) throws -> [String] {
        try (0..<PackLimits.externalPacks).map { index in
            try h.importedID(h.store.importPack(pack("팩\(index)", chars: 5), source: .csv, enabled: index % 2 == 0))
        }
    }

    @Test("★ A5 — 16개 중 하나를 읽을 수 없어도 가져오기(켠 채·꺼 둔 채)는 「팩이 너무 많아요」", arguments: [true, false])
    func unreadablePackStillCounts(enabled: Bool) throws {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let ids = try Self.sixteen(h)
        try removePackFiles(h, of: ids[3])
        #expect(h.store.unreadablePackIDs() == [ids[3]])
        #expect(h.store.importPack(pack("열일곱", chars: 5), source: .csv, enabled: enabled)
                == .rejected(.gate(.tooManyPacks), rechecked: false))
        #expect(h.store.order.compactMap(\.packID).count == PackLimits.externalPacks)
    }

    @Test("★ A5 — 바꾸기도 목록 수로 본다: 16개면 받고, 이미 16개를 넘은 목록(옛 우회로 생긴)이면 거부")
    func replaceChecksStoredCount() throws {
        let h = Harness(limits: .candidate)
        defer { h.sandbox.cleanup() }
        let ids = try Self.sixteen(h)
        #expect(h.store.replacePack(ids[0], with: pack("팩0", chars: 6), source: .csv).isAccepted, "16개 — 수가 늘지 않는 바꾸기")

        // 옛 빌드의 우회로 생긴 17개 목록을 흉내 낸다 — 변환본 하나를 새 id로 복사해 목록에 더한다
        var library = try JSONDecoder().decode(PackLibrary.self, from: Data(contentsOf: libraryURL(h)))
        let packs = h.sandbox.library.appendingPathComponent("packs")
        let source = try #require(library.packs[ids[1]])
        var stored = try JSONDecoder().decode(StoredExternalPack.self, from: Data(contentsOf: packs.appendingPathComponent(source.file)))
        stored.packID = "extra"
        try JSONEncoder().encode(stored).write(to: packs.appendingPathComponent("extra-r1.json"))
        library.packs["extra"] = PackLibrary.Entry(file: "extra-r1.json", isEnabled: false, stored: stored)
        library.order.append(.pack("extra"))
        try JSONEncoder().encode(library).write(to: libraryURL(h))

        #expect(library.packs[ids[0]]?.isEnabled == true && library.packs[ids[1]]?.isEnabled == false, "전제 — 켜진 팩·꺼진 팩")
        #expect(h.store.replacePack(ids[1], with: pack("팩1", chars: 6), source: .csv) == .rejected(.gate(.tooManyPacks), rechecked: false))
        // 켜진 팩 바꾸기도 — 게이트(`judgeActivation`)는 수를 보지 않으므로 이 경로는 목록 수 검사만 막는다(검증 L-4 · AM9a)
        #expect(h.store.replacePack(ids[0], with: pack("팩0", chars: 7), source: .csv) == .rejected(.gate(.tooManyPacks), rechecked: false),
                "켜진 팩 바꾸기도 거부")
        #expect(h.store.deletePack("extra").isAccepted, "줄이는 쪽은 막지 않는다")
        #expect(h.store.replacePack(ids[1], with: pack("팩1", chars: 6), source: .csv).isAccepted)
    }
}
