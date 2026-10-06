import Foundation
import TadakDomain

/// 키보드의 외부 채움글 읽기 — **「읽은 뒤 제외」가 아니라 「읽기 전에 제한」**(PDR `external-snippet-packs.md` 9-4, AC-7·8·26).
///
/// ```
/// generation 읽기 ─▶ ① manifest 크기 cap ─▶ ② 팩 수 cap ─▶ ③ 파일 실제 바이트 cap(남은 예산 기준)
///   ─▶ ④ 팩 하나씩 읽기 ─▶ ⑤ 디코드·필드 상한 재검사 ─▶ ⑥ stats 다시 세고 같은 예산 함수(prefix rule)
///   ─▶ ⑦ 허용 팩만 결과에 — 넘는 첫 팩에서 멈추고 그 뒤는 읽지 않는다
/// ```
///
/// - **stats를 믿지 않는다** — manifest·변환본의 stats는 빠른 거절 힌트일 뿐, 허용은 다시 센 값으로 `ActivePackBudget.evaluate`
///   (앱과 같은 함수, AC-8).
/// - **일관 읽기(8-1)** — `(u1,p1)` 읽기 → 사용자 문구·snapshot 읽기 → `(u2,p2)`. 다르면 처음부터(최대 3회), 끝내 어긋나면 외부 팩을
///   빼고 사용자 문구·내장만. 읽는 중 파일이 사라지면(앱 GC) 현재 generation으로 다시(8-2).
/// - 손상 manifest·낯선 `schema`·크기 불일치·필드 상한 위반 → **외부 팩 전부 제외**, 사용자 문구·내장은 싣는다(AC-8).
/// - baseline(내 채움글 + 켜진 내장)이 한도를 넘으면 사용자 문구를 **저장 순서대로 한도까지만** 싣고 외부 팩은 읽지 않는다(9-3, AC-5).
/// - **쓰지 않는다** — 읽기만이라 전체 접근과 무관하다(App Group 읽기는 권한 없이 된다, P-1).
///
/// 팩 본문·단축어는 사용자 입력이다 — 로그·파일·네트워크 0.
public struct PackSnapshotLoader: Sendable {

    public enum DropReason: Equatable, Sendable {
        case corruptManifest
        case unknownSchema
        case sizeMismatch
        case invalidPack
        /// 세대가 계속 바뀌었다(3회)
        case inconsistentGenerations
        /// 파일이 계속 사라졌다(3회)
        case vanished
    }

    public struct Result: Sendable {
        /// U1 순서 — snapshot이 없으면 기본(내 채움글 맨 위)
        public var order: [SnippetSourceSlot]
        /// 9-3 — baseline이 넘으면 저장 순서대로 한도까지만
        public var userEntries: [SnippetEntry]
        /// 실린 팩(예산 안) — 순서는 `order`
        public var packs: [String: ExternalPack]
        public var includedPackIDs: [String]
        public var excluded: [ActivePackBudget.Exclusion]
        public var baselineOverflow: [PackBudgetDimension]
        /// 외부 팩을 통째로 뺀 이유(정상이면 nil)
        public var dropped: DropReason?
        public var userSnippetsGeneration: Int
        public var packsGeneration: Int
        /// 시도 횟수(1~3) — 진단·시험용
        public var attempts: Int
        /// 실제로 내용을 읽은 팩 파일 수 — 「넘는 첫 팩 뒤는 읽지 않는다」 시험용
        public var packFilesRead: Int
    }

    static let maxAttempts = 3

    private let root: URL
    private let generations: any PackGenerationReading
    private let userSnippets: @Sendable () -> [SnippetEntry]
    private let reader: any PackFileReading
    private let limits: PackBudgetLimits

    public init(
        snapshotRoot: URL, generations: any PackGenerationReading, userSnippets: @escaping @Sendable () -> [SnippetEntry],
        reader: any PackFileReading = SystemPackFileReader(), limits: PackBudgetLimits = .candidate
    ) {
        self.root = snapshotRoot
        self.generations = generations
        self.userSnippets = userSnippets
        self.reader = reader
        self.limits = limits
    }

    /// 제품 — App Group의 snapshot·세대·내 채움글
    public static func live() -> PackSnapshotLoader? {
        guard let group = PackStorageLocations.groupContainer else { return nil }
        let snippets = AppGroupSnippetRepository()
        return PackSnapshotLoader(snapshotRoot: PackStorageLocations.snapshotRoot(groupContainer: group),
                                  generations: AppGroupPackGenerations(), userSnippets: { snippets.entries() })
    }

    /// - Parameter builtIn: 켜진 내장 팩 문구(baseline에 먼저 든다)
    public func load(builtIn: [SnippetEntry]) -> Result {
        var lastUser: [SnippetEntry] = []
        var lastGenerations = (user: 0, packs: 0)
        var lastFailure = DropReason.inconsistentGenerations
        for attempt in 1...Self.maxAttempts {
            let before = (user: generations.userSnippetsGeneration, packs: generations.packsGeneration)
            let user = userSnippets()
            let outcome = readSnapshot(generation: before.packs, user: user, builtIn: builtIn)
            let after = (user: generations.userSnippetsGeneration, packs: generations.packsGeneration)
            lastUser = user
            lastGenerations = after
            guard before == after else {
                lastFailure = .inconsistentGenerations
                continue
            }
            switch outcome {
            case .vanished:
                lastFailure = .vanished
                continue
            case .loaded(var result):
                result.userSnippetsGeneration = before.user
                result.packsGeneration = before.packs
                result.attempts = attempt
                return result
            case .dropped(let reason, let filesRead):
                var result = baselineOnly(user: user, builtIn: builtIn, dropped: reason)
                result.userSnippetsGeneration = before.user
                result.packsGeneration = before.packs
                result.attempts = attempt
                result.packFilesRead = filesRead
                return result
            }
        }
        var result = baselineOnly(user: lastUser, builtIn: builtIn, dropped: lastFailure)
        result.userSnippetsGeneration = lastGenerations.user
        result.packsGeneration = lastGenerations.packs
        result.attempts = Self.maxAttempts
        return result
    }

    // MARK: - 한 번 읽기

    private enum Outcome {
        case loaded(Result)
        case dropped(DropReason, filesRead: Int)
        case vanished
    }

    private func readSnapshot(generation: Int, user: [SnippetEntry], builtIn: [SnippetEntry]) -> Outcome {
        let builtInStats = PackStats.of(entries: builtIn)
        let baseline = PackStats.of(entries: user) + builtInStats
        let baselineCheck = ActivePackBudget.evaluate(baseline: baseline, packs: [], limits: limits)
        // 9-3 — baseline이 넘으면 외부 팩은 읽지도 않는다. 사용자 문구는 저장 순서대로 한도까지
        guard baselineCheck.baselineOverflow.isEmpty else {
            let count = ActivePackBudget.loadableUserEntryCount(user, builtIn: builtInStats, limits: limits)
            return .loaded(makeResult(order: SnippetSourceSlot.defaultOrder, user: Array(user.prefix(count)), packs: [:],
                                      included: [], excluded: [], baselineOverflow: baselineCheck.baselineOverflow))
        }
        guard generation > 0 else {   // 아직 snapshot이 없다 — 내 채움글·내장만(지금과 같다)
            return .loaded(makeResult(order: SnippetSourceSlot.defaultOrder, user: user, packs: [:],
                                      included: [], excluded: [], baselineOverflow: []))
        }

        let directory = PackStorageLocations.generationDirectory(generation, in: root)
        let manifestURL = directory.appendingPathComponent(PackStorageLocations.manifestFileName)
        // ① manifest 크기 cap — 읽기 전에
        guard let manifestSize = reader.size(of: manifestURL) else { return .vanished }
        guard manifestSize <= PackLimits.snapshotManifestBytes else { return .dropped(.corruptManifest, filesRead: 0) }
        guard let manifestData = reader.read(manifestURL) else { return .vanished }
        guard manifestData.count == manifestSize,
              let manifest = try? JSONDecoder().decode(PackSnapshotManifest.self, from: manifestData) else {
            return .dropped(.corruptManifest, filesRead: 0)
        }
        guard manifest.schema == PackSnapshotManifest.schemaVersion else { return .dropped(.unknownSchema, filesRead: 0) }
        let ids = manifest.packs.map(\.id)
        // 순서 목록: 「내 채움글」 줄 **정확히 하나**·줄 겹침 없음(검증 C3 — 겹치면 사용자 문구가 슬롯마다 붙어 예산보다 큰 매처가 된다)
        guard manifest.generation == generation, Set(ids).count == ids.count,
              manifest.order.compactMap(\.packID) == ids,
              manifest.order.filter({ $0 == .userSnippets }).count == 1,
              Set(manifest.order).count == manifest.order.count,
              manifest.packs.allSatisfy({ Self.isPlainFileName($0.file) }) else {
            return .dropped(.corruptManifest, filesRead: 0)
        }

        // ② 팩 수 cap — 읽기 전에 자른다(뒤는 보지 않는다)
        let items = Array(manifest.packs.prefix(PackLimits.externalPacks))
        var loaded: [(id: String, pack: ExternalPack, stats: PackStats)] = []
        var excluded: [ActivePackBudget.Exclusion] = []
        var filesRead = 0
        packLoop: for (index, item) in items.enumerated() {
            let rest = items[(index + 1)...].map { ActivePackBudget.Exclusion(id: $0.id, reason: .afterEarlierOverflow) }
            let url = directory.appendingPathComponent(item.file)
            // ③ 실제 바이트 — manifest와 같아야 하고, 남은 예산 바이트 + 감싸기 여유를 넘으면 읽지 않고 여기서 멈춘다
            guard let size = reader.size(of: url) else { return .vanished }
            guard size == item.bytes else { return .dropped(.sizeMismatch, filesRead: filesRead) }
            let usedBytes = baseline.bytes + loaded.reduce(0) { $0 + $1.stats.bytes }
            let fileCap = max(0, limits.bytes - usedBytes) + PackLimits.storedPackOverheadBytes
            guard size <= fileCap else {
                excluded.append(ActivePackBudget.Exclusion(id: item.id, reason: .overflow([.bytes])))
                excluded += rest
                break packLoop
            }
            // ④⑤ 한 팩씩 읽고 디코드 — 임시 바이트는 이 블록을 나가면 놓는다(다음 팩 전에 해제)
            let decoded: DecodedPack = autoreleasepool {
                guard let data = reader.read(url) else { return .missing }
                guard data.count == size else { return .failed(.sizeMismatch) }
                guard let stored = try? JSONDecoder().decode(StoredExternalPack.self, from: data) else { return .failed(.invalidPack) }
                guard stored.schema == StoredExternalPack.schemaVersion else { return .failed(.unknownSchema) }
                guard stored.packID == item.id, stored.pack.isWithinStoredLimits else { return .failed(.invalidPack) }
                return .pack(stored.pack)
            }
            filesRead += 1
            let pack: ExternalPack
            switch decoded {
            case .missing: return .vanished
            case .failed(let reason): return .dropped(reason, filesRead: filesRead)
            case .pack(let value): pack = value
            }
            // ⑥ stats는 다시 센다 → 앱과 같은 예산 함수(prefix rule)
            let stats = PackStats.of(pack: pack)
            let candidates = (loaded.map { ($0.id, $0.stats) } + [(item.id, stats)])
                .map { ActivePackBudget.Candidate(id: $0.0, isEnabled: true, stats: $0.1) }
            let evaluation = ActivePackBudget.evaluate(baseline: baseline, packs: candidates, limits: limits)
            guard evaluation.isIncluded(item.id) else {
                excluded += evaluation.excluded.filter { $0.id == item.id }
                excluded += rest
                break packLoop
            }
            loaded.append((item.id, pack, stats))
        }
        // ② 에서 잘린 팩도 제외 목록에 남긴다
        excluded += manifest.packs.dropFirst(PackLimits.externalPacks).map {
            ActivePackBudget.Exclusion(id: $0.id, reason: .afterEarlierOverflow)
        }
        let includedIDs = loaded.map(\.id)
        let order = manifest.order.filter { slot in slot.packID.map(includedIDs.contains) ?? true }
        var result = makeResult(order: order, user: user, packs: Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0.pack) }),
                                included: includedIDs, excluded: excluded, baselineOverflow: [])
        result.packFilesRead = filesRead
        return .loaded(result)
    }

    private func baselineOnly(user: [SnippetEntry], builtIn: [SnippetEntry], dropped: DropReason) -> Result {
        let builtInStats = PackStats.of(entries: builtIn)
        let check = ActivePackBudget.evaluate(baseline: PackStats.of(entries: user) + builtInStats, packs: [], limits: limits)
        let count = check.baselineOverflow.isEmpty
            ? user.count : ActivePackBudget.loadableUserEntryCount(user, builtIn: builtInStats, limits: limits)
        var result = makeResult(order: SnippetSourceSlot.defaultOrder, user: Array(user.prefix(count)), packs: [:],
                                included: [], excluded: [], baselineOverflow: check.baselineOverflow)
        result.dropped = dropped
        return result
    }

    private func makeResult(
        order: [SnippetSourceSlot], user: [SnippetEntry], packs: [String: ExternalPack], included: [String],
        excluded: [ActivePackBudget.Exclusion], baselineOverflow: [PackBudgetDimension]
    ) -> Result {
        Result(order: order, userEntries: user, packs: packs, includedPackIDs: included, excluded: excluded,
               baselineOverflow: baselineOverflow, dropped: nil, userSnippetsGeneration: 0, packsGeneration: 0,
               attempts: 1, packFilesRead: 0)
    }

    /// manifest의 파일 이름은 snapshot 폴더 안의 이름 하나뿐이다 — 경로 이동(`..`·`/`)을 받지 않는다
    public static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && name != "." && name != ".." && !name.hasPrefix(".")
    }
}

extension PackSnapshotLoader.Result {
    /// 프로세스 캐시에 넣어도 되는가(검증 F1). **일시적 실패**(세대가 계속 바뀜·파일이 사라짐)로 외부 팩을 뺀 결과는 넣지 않는다 —
    /// 넣으면 그 세대가 그대로인 동안 다음 재구성도 캐시를 써서 외부 팩이 조용히 빠진 채 남는다. 정상·snapshot 없음과
    /// **영구 실패**(손상·낯선 schema·크기 불일치·필드 상한)는 넣어도 된다 — 같은 세대를 다시 읽어도 같고, 앱의 다음 저장이 세대를 바꾼다.
    public var isCacheable: Bool {
        switch dropped {
        case .inconsistentGenerations?, .vanished?: false
        default: true
        }
    }

    /// 외부 팩 없이 사용자 문구만 — App Group을 못 여는(있을 수 없는) 구성의 안전한 기본값
    public static func userOnly(_ entries: [SnippetEntry]) -> Self {
        Self(order: SnippetSourceSlot.defaultOrder, userEntries: entries, packs: [:], includedPackIDs: [], excluded: [],
             baselineOverflow: [], dropped: nil, userSnippetsGeneration: 0, packsGeneration: 0, attempts: 1, packFilesRead: 0)
    }
}

/// 팩 파일 하나를 읽은 결과 — 파일 안에서만 쓴다
private enum DecodedPack {
    case pack(ExternalPack)
    case failed(PackSnapshotLoader.DropReason)
    case missing
}
