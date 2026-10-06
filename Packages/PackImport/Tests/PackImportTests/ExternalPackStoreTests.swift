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
        let ids = self.ids, notifications = self.notifications, disabled = self.disabled, builtIn = builtIn
        let workedOnMain = self.workedOnMain
        store = PackStore(
            libraryRoot: sandbox.library, snapshotRoot: sandbox.snapshot, generations: generations, userSnippets: self.user,
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
               manifestSchema: Int = PackSnapshotManifest.schemaVersion, lieStoredStats: Set<String> = []) throws {
        let directory = sandbox.snapshot.appendingPathComponent("g\(generation)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var items: [PackSnapshotManifest.Item] = []
        for (id, pack) in packs {
            var stored = StoredExternalPack(packID: id, source: .csv, pack: pack)
            stored.schema = packSchema
            if lieStoredStats.contains(id) { stored.stats = .zero }   // 변환본이 stats를 속인다(F5 ②)
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
        let generations = (h.generations.userSnippetsGeneration, h.generations.packsGeneration)

        h.store.maintain()
        #expect(try FileManager.default.contentsOfDirectory(atPath: packsDirectory) == files, "변환본 보존")
        #expect(!h.store.isLibraryReadable)

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
