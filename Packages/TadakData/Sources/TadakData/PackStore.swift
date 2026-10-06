import Foundation
import TadakDomain

/// 외부 채움글·내 채움글·내장 팩 켬/끔의 **유일한 쓰기 진입점**(PDR `external-snippet-packs.md` 9-1·9-2, AC-2·3).
///
/// **컨테이너 앱 전용이다** — 키보드는 `PackSnapshotLoader`로 읽기만 한다(App Group 쓰기는 전체 접근이 필요하다).
///
/// ## 하나의 직렬 경로 (9-1·9-2)
///
/// 모든 변경은 `queue` 하나를 지난다. 큐 안에서 ① 현재 저장본을 읽고 ② **최종 후보**(폼이 확정한 팩 — 부르는 쪽이 컴파일한 DTO의
/// stats를 여기서 다시 센다)로 제안 상태를 만들고 ③ `PackCommitGate.judge` ④ 거부면 끝 ⑤ 받으면 쓴다. 판정과 쓰기 사이에 다른
/// 변경이 끼어들 수 없다. 부르는 쪽이 미리보기에서 본 `revision`을 넘기면, 그사이 저장본이 바뀌었는지(`rechecked`)를 알려 주고
/// 판정은 **항상 지금 저장본으로 다시** 한다(AC-3).
///
/// ## 「저장 1회 = 항목 1개」 (1-b 계약, 9-1 메모)
///
/// 게이트는 저장 전후 **합계**만 본다 — 「삭제 + 새 추가」를 한 저장에 묶으면 순감소일 때 새 추가가 통과한다. 그래서 내 채움글은
/// 한 번에 **한 항목**만 추가·수정·삭제한다. 단축어가 겹쳐 함께 지워지는 다른 항목은 **먼저 뺀 상태를 기준으로** 판정한다(그 몫으로
/// 새 추가가 한도를 넘지 못한다). 꺼 둔 채로 가져오기는 게이트가 `proposed.dropLast == current`를 본다(N2).
///
/// ## 쓰는 순서 (8-1 ③ — 키보드가 일관되게 읽도록)
///
/// 새 변환본 파일 → 새 snapshot `g<N+1>`(팩 파일 → manifest) → 내 채움글 → 목록(`library.json`) → `userSnippetsGeneration`
/// → **`packsGeneration = N+1`(커밋 지점)** → 안 쓰는 변환본·옛 세대 정리(현재 − 2 이하, 9절·8-2) → 알림(신호일 뿐).
/// 커밋 지점 전에 실패하면 새로 쓴 것을 지우고 이전 상태를 그대로 둔다(9-2 ⑥).
///
/// 팩 본문·단축어·이름·권리는 사용자 입력이다 — 로그·네트워크 0. 저장은 앱 전용 폴더와 App Group 공유 폴더뿐이다.
public final class PackStore: @unchecked Sendable {

    public enum Rejection: Error, Equatable, Sendable {
        /// 예산 게이트 거부 — 화면이 이유를 보인다(9-1)
        case gate(PackCommitGate.Rejection)
        /// 「저장 1회 = 항목 1개」를 어긴 요청 — 부르는 쪽 버그(화면 문구 대상 아님)
        case moreThanOneItem
        /// 없는 팩·없는 문구
        case notFound
        /// 순서 바꾸기가 지금 목록의 재배열이 아니다
        case invalidOrder
        case writeFailed
    }

    public struct Accepted: Equatable, Sendable {
        public var revision: Int
        /// 가져오기로 새로 만든 팩 id
        public var packID: String?
        /// 이번 변경으로 snapshot에서 쉬게 된 팩(경고용, R14)
        public var newlyExcluded: [String]
        public var evaluation: ActivePackBudget.Evaluation
        /// 부르는 쪽이 본 revision과 저장본이 달라 다시 판정했다(AC-3)
        public var rechecked: Bool
    }

    public enum CommitResult: Equatable, Sendable {
        case accepted(Accepted)
        case rejected(Rejection, rechecked: Bool)

        public var isAccepted: Bool {
            if case .accepted = self { return true }
            return false
        }
    }

    private let libraryRoot: URL
    private let snapshotRoot: URL
    private let generations: any PackGenerationWriting
    private let userSnippets: any UserSnippetStoring
    private let builtInEntries: @Sendable (_ disabledPacks: Set<String>) -> [SnippetEntry]
    private let disabledBuiltIns: @Sendable () -> [String]
    private let notify: @Sendable () -> Void
    private let makeID: @Sendable () -> String
    private let limits: PackBudgetLimits
    private let queue = DispatchQueue(label: "com.charging.tadak.PackStore")

    /// - Parameters:
    ///   - libraryRoot: **앱 전용** 폴더 — 변환본(꺼진 팩 포함)과 목록
    ///   - snapshotRoot: App Group 공유 폴더 — 활성 snapshot `g<N>/`
    ///   - builtInEntries: 끈 팩 목록 → 켜진 내장 팩의 문구(baseline, 키보드와 같은 모양)
    ///   - disabledBuiltIns: 지금 저장된 끈 팩 목록(설정) — 내장 켜기·끄기 판정은 부르는 쪽이 넘긴 값을 쓴다
    public init(
        libraryRoot: URL, snapshotRoot: URL, generations: any PackGenerationWriting, userSnippets: any UserSnippetStoring,
        builtInEntries: @escaping @Sendable (Set<String>) -> [SnippetEntry],
        disabledBuiltIns: @escaping @Sendable () -> [String],
        notify: @escaping @Sendable () -> Void = { SettingsChangeNotifier.post() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString },
        limits: PackBudgetLimits = .candidate
    ) {
        self.libraryRoot = libraryRoot
        self.snapshotRoot = snapshotRoot
        self.generations = generations
        self.userSnippets = userSnippets
        self.builtInEntries = builtInEntries
        self.disabledBuiltIns = disabledBuiltIns
        self.notify = notify
        self.makeID = makeID
        self.limits = limits
    }

    /// 제품 — 앱 전용 Application Support + App Group 공유 폴더 + App Group `UserDefaults`
    public static let live: PackStore = {
        let group = PackStorageLocations.groupContainer
        let anthem = BundledSnippetRepository()
        let greetings = BundledSnippetRepository(resourceName: "Greetings")
        return PackStore(
            libraryRoot: PackStorageLocations.appLibraryRoot(),
            // App Group이 없으면(있을 수 없는 구성) 앱 폴더에 쓴다 — 키보드는 못 보지만 앱은 죽지 않는다
            snapshotRoot: group.map(PackStorageLocations.snapshotRoot(groupContainer:))
                ?? PackStorageLocations.appLibraryRoot().appendingPathComponent("snapshot-fallback", isDirectory: true),
            generations: AppGroupPackGenerations(), userSnippets: AppGroupSnippetRepository(),
            builtInEntries: { disabled in BuiltInSnippetEntries.enabled(disabled: disabled, anthem: anthem, greetings: greetings) },
            disabledBuiltIns: { AppGroupSettingsRepository().load().disabledSnippetPacks })
    }()

    // MARK: - 읽기

    public var revision: Int { queue.sync { loadLibrary().revision } }

    /// 지금 저장본의 예산 판정 — 화면의 포함·제외·「일부만 사용 중」 안내(9-3, 1-c)가 이 값을 쓴다
    public func evaluation() -> ActivePackBudget.Evaluation {
        queue.sync {
            let state = loadState()
            let input = budgetInput(library: state.library, user: state.user, disabled: state.disabled)
            return ActivePackBudget.evaluate(baseline: input.baseline, packs: input.packs, limits: limits)
        }
    }

    /// 지금 순서 목록(U1 — 「내 채움글」 한 줄 포함)
    public var order: [SnippetSourceSlot] { queue.sync { loadLibrary().order } }

    // MARK: - 내 채움글

    /// 추가·고치기 한 건. 규칙(겹치는 단축어 교체·제자리 고치기)은 `SnippetEntry.applying` 그대로다.
    @discardableResult
    public func saveUserSnippet(_ entry: SnippetEntry, editing original: SnippetEntry?, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            let proposedUser = SnippetEntry.applying(entry, editing: original, to: state.user)
            // 겹쳐 함께 지워지는 **다른** 항목을 먼저 뺀 상태가 판정 기준이다 — 그 몫으로 새 추가가 통과하지 않게
            let originalID = original?.snippetListID
            let incoming = Set(entry.triggers.map(SnippetEntry.normalizedTrigger))
            let base = state.user.filter { existing in
                existing.snippetListID == originalID
                    || !existing.triggers.contains { incoming.contains(SnippetEntry.normalizedTrigger($0)) }
            }
            guard Self.isSingleItemChange(from: base, to: proposedUser) else { return .failure(.moreThanOneItem) }
            var proposal = Proposal(change: .saveUserSnippets, state: state)
            proposal.user = proposedUser
            proposal.currentOverride = (base, state.disabled)
            return .success(proposal)
        }
    }

    @discardableResult
    public func deleteUserSnippet(_ entry: SnippetEntry, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard let index = state.user.firstIndex(of: entry) else { return .failure(.notFound) }
            var proposal = Proposal(change: .deleteUserSnippets, state: state)
            proposal.user.remove(at: index)
            return .success(proposal)
        }
    }

    // MARK: - 내장 팩

    /// 내장 팩 켜기·끄기 — 설정의 두 토글 경로(목록·팩 상세)가 **이 하나**를 쓴다(AC-6). 받으면 부르는 쪽이 설정에
    /// `proposedDisabled`를 저장한다(설정 저장 지점은 `RootView` 하나 — 여기서 쓰지 않는다).
    @discardableResult
    public func setBuiltInPack(_ id: String, enabled: Bool, currentDisabled: [String], expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            var proposal = Proposal(change: enabled ? .enableBuiltIn : .disableBuiltIn, state: state)
            var disabled = currentDisabled.filter { $0 != id }
            if !enabled { disabled.append(id) }
            proposal.disabled = disabled
            proposal.currentOverride = (state.user, currentDisabled)
            return .success(proposal)
        }
    }

    // MARK: - 외부 팩

    /// 가져오기 최종 확정 — 새 팩은 **목록 맨 아래**(U2). `enabled == false`면 「꺼 둔 채로 가져오기」.
    /// `pack`은 폼이 확정한 최종 DTO다 — stats는 여기서 다시 센다(AC-3).
    @discardableResult
    public func importPack(_ pack: ExternalPack, source: StoredExternalPack.Source, enabled: Bool = true,
                           expectedRevision: Int? = nil) -> CommitResult {
        let id = makeID()
        return perform(expectedRevision: expectedRevision) { state in
            guard SnippetSourceSlot.pack(id).packID.map(PackSnapshotLoader.isPlainFileName) == true,
                  state.library.packs[id] == nil else { return .failure(.writeFailed) }
            let stored = StoredExternalPack(packID: id, source: source, pack: pack)
            var proposal = Proposal(change: enabled ? .importPack(id: id) : .importDisabledPack(id: id), state: state)
            proposal.library.order.append(.pack(id))
            proposal.library.packs[id] = PackLibrary.Entry(file: "", isEnabled: enabled, stats: stored.stats)
            proposal.newPack = stored
            proposal.packID = id
            return .success(proposal)
        }
    }

    @discardableResult
    public func setPackEnabled(_ id: String, enabled: Bool, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard state.library.packs[id] != nil else { return .failure(.notFound) }
            var proposal = Proposal(change: enabled ? .enablePack(id: id) : .disablePack(id: id), state: state)
            proposal.library.packs[id]?.isEnabled = enabled
            return .success(proposal)
        }
    }

    /// 같은 이름 팩 교체 — **위치·켬/끔 유지**(9-1). 켜진 팩이면 활성 예산, 꺼진 팩이면 예산을 보지 않는다
    @discardableResult
    public func replacePack(_ id: String, with pack: ExternalPack, source: StoredExternalPack.Source,
                            expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard let entry = state.library.packs[id] else { return .failure(.notFound) }
            let stored = StoredExternalPack(packID: id, source: source, pack: pack)
            var proposal = Proposal(change: entry.isEnabled ? .replaceActivePack(id: id) : .replaceInactivePack(id: id), state: state)
            proposal.library.packs[id] = PackLibrary.Entry(file: "", isEnabled: entry.isEnabled, stats: stored.stats)
            proposal.newPack = stored
            return .success(proposal)
        }
    }

    @discardableResult
    public func deletePack(_ id: String, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard state.library.packs[id] != nil else { return .failure(.notFound) }
            var proposal = Proposal(change: .deletePack(id: id), state: state)
            proposal.library.packs[id] = nil
            proposal.library.order.removeAll { $0 == .pack(id) }
            return .success(proposal)
        }
    }

    /// 팩 순서 바꾸기(U4) — 「내 채움글」 줄도 옮길 수 있다(U1). 지금 목록의 **재배열**이어야 한다
    @discardableResult
    public func reorder(_ order: [SnippetSourceSlot], expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard order.count == state.library.order.count, Set(order) == Set(state.library.order),
                  Set(order).count == order.count else { return .failure(.invalidOrder) }
            var proposal = Proposal(change: .reorderPacks, state: state)
            proposal.library.order = order
            return .success(proposal)
        }
    }

    // MARK: - 앱 실행 시

    /// 앱 실행 때 한 번 — 옛 세대(현재 − 2 이하)와 목록이 가리키지 않는 변환본을 지운다. **사용자 데이터(목록에 있는 팩·내 채움글)는
    /// 한도를 넘어도 지우지 않는다**(9-3).
    public func maintain() {
        queue.sync {
            let library = loadLibrary()
            removeUnreferencedPackFiles(library: library)
            collectSnapshotGarbage(current: generations.packsGeneration)
        }
    }

    // MARK: - 커밋

    private struct State {
        var library: PackLibrary
        var user: [SnippetEntry]
        var disabled: [String]
    }

    private struct Proposal {
        var change: PackCommitGate.Change
        var library: PackLibrary
        var user: [SnippetEntry]
        var disabled: [String]
        /// 판정 기준(current)을 저장본 대신 이것으로 — 겹침 교체 저장·내장 토글
        var currentOverride: (user: [SnippetEntry], disabled: [String])?
        var newPack: StoredExternalPack?
        var packID: String?
        var userChanged = false

        init(change: PackCommitGate.Change, state: State) {
            self.change = change
            self.library = state.library
            self.user = state.user
            self.disabled = state.disabled
        }
    }

    private func perform(expectedRevision: Int?, _ make: (State) -> Swift.Result<Proposal, Rejection>) -> CommitResult {
        queue.sync {
            let state = loadState()
            let rechecked = expectedRevision.map { $0 != state.library.revision } ?? false
            var proposal: Proposal
            switch make(state) {
            case .failure(let rejection): return .rejected(rejection, rechecked: rechecked)
            case .success(let value): proposal = value
            }
            proposal.userChanged = proposal.user != state.user
            let currentBase = proposal.currentOverride ?? (state.user, state.disabled)
            let current = budgetInput(library: state.library, user: currentBase.user, disabled: currentBase.disabled)
            let proposed = budgetInput(library: proposal.library, user: proposal.user, disabled: proposal.disabled)
            switch PackCommitGate.judge(proposal.change, current: current, proposed: proposed, limits: limits) {
            case .reject(let rejection):
                return .rejected(.gate(rejection), rechecked: rechecked)
            case .accept(let evaluation, let newlyExcluded):
                guard write(proposal, state: state, evaluation: evaluation) else {
                    return .rejected(.writeFailed, rechecked: rechecked)
                }
                return .accepted(Accepted(revision: state.library.revision + 1, packID: proposal.packID,
                                          newlyExcluded: newlyExcluded, evaluation: evaluation, rechecked: rechecked))
            }
        }
    }

    /// 8-1 ③의 순서로 쓴다. 커밋 지점(`packsGeneration`) 전에 실패하면 새로 쓴 것을 지우고 false
    private func write(_ proposal: Proposal, state: State, evaluation: ActivePackBudget.Evaluation) -> Bool {
        let fileManager = FileManager.default
        var library = proposal.library
        library.revision = state.library.revision + 1
        var newFiles: [URL] = []
        func rollback() { newFiles.forEach { try? fileManager.removeItem(at: $0) } }

        // ① 새 변환본 — 이름에 revision을 붙여 옛 파일을 덮지 않는다(실패해도 이전 상태가 남는다)
        if let stored = proposal.newPack {
            let name = "\(stored.packID)-r\(library.revision).json"
            let url = packsDirectory.appendingPathComponent(name)
            guard let data = try? JSONEncoder().encode(stored), (try? ensureDirectory(packsDirectory)) != nil,
                  (try? data.write(to: url, options: .atomic)) != nil else { return false }
            newFiles.append(url)
            library.packs[stored.packID]?.file = name
        }

        // ② 새 snapshot g<N+1> — 예산 안의 켜진 팩만(쉬는 팩은 싣지 않는다, R14)
        let newUserGeneration = generations.userSnippetsGeneration + (proposal.userChanged ? 1 : 0)
        let newPacksGeneration = generations.packsGeneration + 1
        guard let snapshotDirectory = publishSnapshot(library: library, included: evaluation.included,
                                                      generation: newPacksGeneration, userRevision: newUserGeneration) else {
            rollback()
            return false
        }
        newFiles.append(snapshotDirectory)

        // ③ 내 채움글 ④ 목록
        if proposal.userChanged, !userSnippets.save(proposal.user) {
            rollback()
            return false
        }
        guard (try? ensureDirectory(libraryRoot)) != nil, let data = try? JSONEncoder().encode(library),
              (try? data.write(to: libraryURL, options: .atomic)) != nil else {
            if proposal.userChanged { userSnippets.save(state.user) }
            rollback()
            return false
        }

        // ⑤ 세대 — packsGeneration이 커밋 지점
        if proposal.userChanged { generations.setUserSnippetsGeneration(newUserGeneration) }
        generations.setPacksGeneration(newPacksGeneration)

        // ⑥ 정리 — 앱의 변경 때만(키보드는 지우지 않는다) ⑦ 알림
        removeUnreferencedPackFiles(library: library)
        collectSnapshotGarbage(current: newPacksGeneration)
        notify()
        return true
    }

    /// snapshot 폴더 하나를 처음부터 쓴다 — 팩 파일을 다 쓴 **뒤** 마지막에 manifest(8절)
    private func publishSnapshot(library: PackLibrary, included: [String], generation: Int, userRevision: Int) -> URL? {
        let fileManager = FileManager.default
        let directory = PackStorageLocations.generationDirectory(generation, in: snapshotRoot)
        try? fileManager.removeItem(at: directory)   // 이전 실패의 잔여
        do {
            try ensureDirectory(directory)
            var items: [PackSnapshotManifest.Item] = []
            let includedSet = Set(included)
            let packOrder = library.order.compactMap(\.packID).filter(includedSet.contains)
            for id in packOrder {
                guard let entry = library.packs[id] else { continue }
                let source = packsDirectory.appendingPathComponent(entry.file)
                let fileName = "\(id).json"
                let target = directory.appendingPathComponent(fileName)
                try fileManager.copyItem(at: source, to: target)
                let bytes = (try fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0
                items.append(.init(id: id, file: fileName, bytes: bytes, stats: entry.stats))
            }
            let order = library.order.filter { slot in slot.packID.map(includedSet.contains) ?? true }
            let manifest = PackSnapshotManifest(generation: generation, userSnippetsRevision: userRevision, order: order, packs: items)
            try JSONEncoder().encode(manifest).write(
                to: directory.appendingPathComponent(PackStorageLocations.manifestFileName), options: .atomic)
            return directory
        } catch {
            try? fileManager.removeItem(at: directory)
            return nil
        }
    }

    /// 현재 − 2 세대 이하만 지운다(8-2) — 읽고 있던 키보드는 현재 세대로 재시도한다
    private func collectSnapshotGarbage(current: Int) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: snapshotRoot.path) else { return }
        for name in names where name.hasPrefix("g") {
            guard let generation = Int(name.dropFirst()), generation <= current - 2 else { continue }
            try? fileManager.removeItem(at: snapshotRoot.appendingPathComponent(name, isDirectory: true))
        }
    }

    /// 목록이 가리키지 않는 변환본(교체·삭제로 남은 옛 파일)을 지운다
    private func removeUnreferencedPackFiles(library: PackLibrary) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: packsDirectory.path) else { return }
        let referenced = Set(library.packs.values.map(\.file))
        for name in names where !referenced.contains(name) {
            try? fileManager.removeItem(at: packsDirectory.appendingPathComponent(name))
        }
    }

    // MARK: - 저장본 읽기

    private var libraryURL: URL { libraryRoot.appendingPathComponent("library.json") }
    private var packsDirectory: URL { libraryRoot.appendingPathComponent("packs", isDirectory: true) }

    private func loadLibrary() -> PackLibrary {
        guard let data = try? Data(contentsOf: libraryURL),
              let library = try? JSONDecoder().decode(PackLibrary.self, from: data),
              library.schema == PackLibrary.schemaVersion else { return PackLibrary() }
        return library
    }

    private func loadState() -> State {
        State(library: loadLibrary(), user: userSnippets.entries(), disabled: disabledBuiltIns())
    }

    private func budgetInput(library: PackLibrary, user: [SnippetEntry], disabled: [String]) -> PackBudgetInput {
        let packs = library.order.compactMap(\.packID).compactMap { id in
            library.packs[id].map { ActivePackBudget.Candidate(id: id, isEnabled: $0.isEnabled, stats: $0.stats) }
        }
        return PackBudgetInput(userSnippets: PackStats.of(entries: user),
                               builtIn: PackStats.of(entries: builtInEntries(Set(disabled))), packs: packs)
    }

    private func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// 한 항목의 추가·수정·삭제인가 — 빠진 것 ≤ 1, 들어온 것 ≤ 1
    static func isSingleItemChange(from base: [SnippetEntry], to proposed: [SnippetEntry]) -> Bool {
        var remaining = proposed
        var removed = 0
        for entry in base {
            if let index = remaining.firstIndex(of: entry) {
                remaining.remove(at: index)
            } else {
                removed += 1
            }
        }
        return removed <= 1 && remaining.count <= 1
    }
}

/// 앱 전용 목록 — 순서(U1 「내 채움글」 줄 포함)·켬/끔·변환본 파일·stats(앱이 계산, 판정용). 파일 하나, 원자적 쓰기.
struct PackLibrary: Codable, Equatable {
    static let schemaVersion = 1

    struct Entry: Codable, Equatable {
        var file: String
        var isEnabled: Bool
        var stats: PackStats
    }

    var schema = PackLibrary.schemaVersion
    var revision = 0
    var order: [SnippetSourceSlot] = SnippetSourceSlot.defaultOrder
    var packs: [String: Entry] = [:]
}

/// 켜진 내장 문구 팩 — 키보드(`KeyboardViewController.rebuildSnippetMatcher`)와 앱(`PackStore` baseline)이 같은 순서·같은 모양을 쓴다
/// (국가 상징문 → 인사·상용구). 날짜·성경은 문구가 없는 계산 팩이라 baseline에 들지 않는다.
public enum BuiltInSnippetEntries {
    public static func enabled(
        disabled: Set<String>, anthem: any SnippetRepository, greetings: any SnippetRepository
    ) -> [SnippetEntry] {
        var entries: [SnippetEntry] = []
        if !disabled.contains(SnippetPack.anthem) { entries += anthem.entries() }
        if !disabled.contains(SnippetPack.greetings) { entries += greetings.entries() }
        return entries
    }
}
