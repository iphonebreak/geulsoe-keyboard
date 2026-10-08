import Foundation
import TadakData
import TadakDomain

/// 외부 채움글·내 채움글·내장 팩 켬/끔의 **유일한 쓰기 진입점**(PDR `external-snippet-packs.md` 9-1·9-2, AC-2·3).
///
/// **컨테이너 앱 전용이다** — 앱 전용 모듈 `PackImport`에 있어 키보드 바이너리에 **링크되지 않는다**(키보드에서 부르면 빌드가 안 된다 —
/// 보안 규칙 「키보드는 외부 채움글 저장소에 쓰지 않는다」를 컴파일러가 지킨다, codex 반론 #11). 키보드는 TadakData의
/// `PackSnapshotLoader`로 읽기만 한다(App Group 쓰기는 전체 접근이 필요하다).
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
/// 오류가 아니라 **앱이 도중에 끝나면** 되돌릴 기회가 없다 — 목록에 이 커밋의 세대(`generation`)와 정리 몫(`purgeBelow`)을 함께 적어
/// 다음 실행(`maintain`)이 게시를 마무리하고 옛 내용을 지운다(codex 반론 #2·#6). 처음 커밋은 목록부터 만든다(반론 #1 — `.missing` 판정).
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
        /// 앱 전용 목록(`library.json`)이 있는데 읽을 수 없다·손상·낯선 schema(검증 C1) — **아무것도 지우거나 덮어쓰지 않는다**(9-3)
        case libraryUnreadable
        /// 변환본을 읽을 수 없는 팩은 켤 수 없다(검증 C5) — 다시 가져오기·삭제로 복구(1-c)
        case packUnavailable(String)
        // 화면 문구는 거부 사유만으로 정하지 않는다 — 무엇을 하다 막혔는지·저장 전 상태가 함께 정한다(`PackChangeNotice`, 1-c G7)
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
    /// 변환본 내용 검사 결과(파일 이름 → 크기·키보드가 받는 내용인가, 1-c G6) — `queue` 안에서만 읽고 쓴다. 처음 쓸 때 파일에서 읽는다
    private var contentChecks: [String: PackContentCheck]?
    /// 시험 전용 갈고리 — 큐 안에서 판정과 쓰기 사이에 부른다(직렬성 결정적 시험, 검증 F5 ④). 제품에서는 nil
    var beforeWriteForTesting: (@Sendable () -> Void)?

    /// 시험 전용 — 쓰는 도중 **앱이 끝난 것처럼** 이 지점에서 멈춘다(그 뒤는 아무것도 하지 않는다 — 되돌리기·정리·알림 없음).
    /// 시험은 이 저장소를 버리고 같은 위치로 다시 열어(`maintain`) 다음 실행을 흉내 낸다(codex 반론 #1·#2·#6). 제품에서는 nil
    enum CrashPoint: Sendable {
        /// ①②③ 뒤 · ④ 목록 앞
        case beforeLibrary
        /// ④ 목록 뒤 · ⑤ 커밋 지점(`packsGeneration`) 앞
        case beforePacksGeneration
        /// ⑤ 뒤 · ⑥ 정리 앞
        case beforeCleanup
        /// 복구 — 원래 목록을 보관한 뒤 · 새 목록을 쓰기 앞
        case recoveryBeforeWrite
    }
    var crashPointForTesting: CrashPoint?

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
            generations: AppGroupPackGenerationWriter(), userSnippets: AppGroupUserSnippetStore(),
            builtInEntries: { disabled in BuiltInSnippetEntries.enabled(disabled: disabled, anthem: anthem, greetings: greetings) },
            disabledBuiltIns: { AppGroupSettingsRepository().load().disabledSnippetPacks })
    }()

    // MARK: - 읽기

    public var revision: Int { queue.sync { (readLibrary() ?? PackLibrary()).revision } }

    /// 앱 전용 목록을 읽을 수 있는가 — 거짓이면 모든 변경·정리를 멈춘 상태다(검증 C1). 1-c가 복구 안내를 보일 자리
    public var isLibraryReadable: Bool { queue.sync { readLibrary() != nil } }

    /// 지금 저장본의 예산 판정 — 화면의 포함·제외(못 읽는 팩은 `.unavailable`)·「일부만 사용 중」 안내(9-3, 1-c)가 이 값을 쓴다
    public func evaluation() -> ActivePackBudget.Evaluation {
        queue.sync {
            let library = readLibrary() ?? PackLibrary()
            return currentEvaluation(library: library, unavailable: unavailablePackIDs(in: library))
        }
    }

    /// 팩 목록의 읽기 모델(1-c G1) — **목록 순서대로**, 이름·종류·항목 수·대표 틀·켬/끔·상태 5갈래. 판정은 `evaluation()`과 같다.
    /// 표시 칸은 목록(`library.json`)에서 읽어 **변환본을 못 읽는 팩도 이름이 보인다.** 표시 칸이 없는 옛 목록(1-b)이면 그 팩만 변환본을
    /// 열어 채운다(못 열면 이름 nil — 화면은 「이름 없는 팩」). 목록을 못 읽으면 빈 목록이다(`isLibraryReadable`로 가른다)
    public func summaries() -> [PackSummary] {
        queue.sync {
            let library = readLibrary() ?? PackLibrary()
            let unavailable = unavailablePackIDs(in: library)
            let evaluation = currentEvaluation(library: library, unavailable: unavailable)
            return library.order.compactMap(\.packID).compactMap { id in
                guard let entry = library.packs[id] else { return nil }
                let isUnavailable = unavailable.contains(id)
                let display = display(of: entry, isUnavailable: isUnavailable)
                return PackSummary(id: id, name: display.name, mode: display.mode, itemCount: entry.stats.items,
                                   titleFormat: display.titleFormat, isEnabled: entry.isEnabled,
                                   status: PackSummary.status(of: id, isEnabled: entry.isEnabled, isUnavailable: isUnavailable,
                                                              in: evaluation))
            }
        }
    }

    /// 팩 이름 하나 — 알림(`PackChangeNotice`)용. `summaries()`와 같은 표시 칸을 쓰되 판정은 하지 않는다. 모르면 nil
    func packName(_ id: String) -> String? {
        queue.sync {
            guard let library = readLibrary(), let entry = library.packs[id] else { return nil }
            return display(of: entry, isUnavailable: unavailablePackIDs(in: library).contains(id)).name
        }
    }

    /// 지금 순서 목록(U1 — 「내 채움글」 한 줄 포함)
    public var order: [SnippetSourceSlot] { queue.sync { (readLibrary() ?? PackLibrary()).order } }

    /// 목록에 있지만 변환본이 없거나 읽을 수 없는 팩(검증 F4·C5) — 판정에서 `.unavailable`로 빠지는 그 팩들. 1-c가 「이 팩을 읽을 수
    /// 없어요」를 보일 자리(꺼진 팩도 포함). 화면은 아직 없다
    public func unreadablePackIDs() -> [String] {
        queue.sync {
            let library = readLibrary() ?? PackLibrary()
            let unavailable = unavailablePackIDs(in: library)
            return library.order.compactMap(\.packID).filter(unavailable.contains)
        }
    }

    /// 목록 상태 — 읽히지 않으면 사유(1-c ㉡·G4). 화면의 손상 배너·복구 입구가 쓴다
    public func libraryStatus() -> PackLibraryStatus { queue.sync { loadLibrary().status } }

    /// 내 채움글 정리 모델(1-c ㉠·R25) — 경계는 키보드 로더와 **같은 함수·같은 입력**(내 채움글 + 켜진 내장, 9-3)
    public func userSnippetBudget() -> UserSnippetBudget {
        queue.sync {
            let user = userSnippets.entries()
            let builtIn = PackStats.of(entries: builtInEntries(Set(disabledBuiltIns())))
            let usage = ActivePackBudget.userSnippetUsage(user, builtIn: builtIn, limits: limits)
            let overflow = ActivePackBudget.evaluate(baseline: usage.stats + builtIn, packs: [], limits: limits).baselineOverflow
            return UserSnippetBudget(stored: user, loadableCount: usage.loadableCount, isOverLimit: !overflow.isEmpty)
        }
    }

    /// 순서·켬/끔 사전 영향(G3 `PackImpact`)과 팩 상세의 입력 — 목록·내 채움글·켜진 내장을 **한 번의 큐 작업**에서 읽는다. 읽을 수 있는 팩은
    /// 변환본을 열어 단축어·틀을 담는다(최대 16 × 3MB 디코드 — 메인에서 부르지 않는다, `PackStoreClient.impactLibrary`). 목록을 못 읽으면 nil
    public func impactLibrary() -> PackImpact.Library? {
        queue.sync { makeImpactLibrary(keeping: nil)?.library }
    }

    /// 팩 상세(2-E·U1) — 읽기 모델·권리·사용 예·자리(틀 소유·가림·뒤 순서). 같은 큐 작업 안에서 `impactLibrary`와 같은 입력으로 계산한다.
    /// 없는 팩·목록을 못 읽으면 nil. 읽을 수 없는 팩은 이름·상태만(권리·예·자리 없음)
    public func packDetail(_ id: String) -> PackDetail? {
        queue.sync {
            guard let made = makeImpactLibrary(keeping: id), let pack = made.library.pack(id) else { return nil }
            let standing = PackImpact.standing(of: id, in: made.library)
            // 사용법 예시는 지금 뜨는 단축어·이 팩이 쓰는 틀부터(O-1·N-2) — 「지금 안 뜨는 단축어」·「단축어 틀」 절과 같은 계산.
            // 가져오기 완료 화면(4-M)도 저장 뒤 이 값을 그대로 쓴다(`PackImportConfirmation.perform`)
            let hidden = Set(standing?.hiddenTriggers.map { SnippetEntry.normalizedTrigger($0.trigger) } ?? [])
            return PackDetail(summary: pack.summary, license: made.kept?.license,
                              examples: made.kept.map { PackDetail.examples(of: $0, hidden: hidden, patterns: standing?.patterns ?? []) } ?? [],
                              standing: standing,
                              names: Dictionary(made.library.packs.map { ($0.id, made.library.name(of: $0.id)) },
                                                uniquingKeysWith: { first, _ in first }))
        }
    }

    /// 팩 상세 「전체 보기」(R31) — 그 팩의 모든 항목. 켬/끔·쉬는 중과 무관하게 읽는다. 없는 팩·목록을 못 읽으면·**읽을 수 없는 팩**이면
    /// nil(상세가 「전체 보기」를 두지 않는 팩 — 코디네이터 결정 2026-10-07). 변환본 하나만 연다(최대 3MB 디코드 — 메인에서 부르지 않는다).
    /// 줄·검색 키 만들기(수천 개면 수백 ms)는 **큐 밖**에서 한다 — 그동안 켬/끔 같은 커밋이 이 읽기 뒤에 줄 서지 않게
    public func packEntries(_ id: String) -> PackEntryList? {
        let pack: ExternalPack? = queue.sync {
            guard let library = readLibrary(), let entry = library.packs[id], !unavailablePackIDs(in: library).contains(id) else { return nil }
            return autoreleasepool { readStoredPack(file: entry.file)?.pack }
        }
        return pack.map(PackEntryList.init)
    }

    // MARK: - 목록 복구 (R24)

    /// 복구하면 불러올 팩 수(읽을 수 없는 변환본 포함) — 확인 시트의 「가져온 팩 N개를 찾았어요」. 목록이 읽히면 nil(복구할 것이 없다)
    public func recoveryPreview() -> Int? {
        queue.sync { loadLibrary().status == .readable ? nil : recoveryFiles().count }
    }

    /// 목록 복구(R24) — **사용자가 확인한 뒤에만** 부른다. 변환본 폴더를 훑어 목록을 다시 만들고 **모두 꺼진 채** 불러온다(순서·켬/끔은
    /// 알 수 없다). 원래 목록은 지우지 않고 `library.damaged-<UTC 시각>.json` 보관본을 남긴다(같은 이름이 있으면 `-2`, `-3`…).
    /// ★ 원래 목록을 **옮기지 않는다**(codex 반론 #1) — 보관본은 하드 링크(안 되면 복사)로 만들고 원래 목록은 새 목록이 원자적으로 덮을 때까지
    /// 제자리에 둔다. 옮긴 뒤 새 목록을 쓰기 전에 앱이 끝나면 다음 실행이 「목록 없음」을 빈 목록으로 보고 팩 파일을 정리했다.
    /// 보관본을 못 만들면 아무것도 쓰지 않고, 새 목록·snapshot을 못 쓰면 보관본을 지운다 — **원래 목록을 덮어쓰지 않는다**(9-3).
    /// 목록 파일이 아예 없으면(`.missing`) 보관할 것이 없어 보관본 이름이 nil이다.
    ///
    /// 변환본을 읽어 키보드가 받는 내용이면 표시 칸(이름·종류·틀)과 stats(다시 센 값)를 채우고, 아니면 그 팩은 「읽을 수 없는 팩」(`.unavailable`)으로
    /// 목록에 남긴다(지우지 않는다 — 다시 가져오기·지우기는 사용자가 한다). 같은 팩의 변환본이 여럿이면(정리 전에 앱이 죽은 경우) revision이
    /// 가장 큰 것을 쓰고 나머지는 평소처럼 정리된다. 순서는 변환본 이름의 r 번호(쓴 차례 — 가져온 순서에 가깝다, 수정 시각은 읽지 않는다),
    /// 「내 채움글」은 맨 위(U1 기본).
    public func recoverLibrary(now: Date = Date()) -> PackLibraryRecovery {
        queue.sync {
            let status = loadLibrary().status
            guard status != .readable else { return .notNeeded }
            // 변환본을 하나씩 읽어 키보드가 받는 내용인지 본다(로더 ④⑤와 같은 함수) — 받지 않으면 stored nil. stats는 파일 값을 믿지 않고
            // **다시 센다**(검증 F-2 — 평소 커밋과 같은 `StoredExternalPack(packID:source:pack:)`. 옛 계산·모양을 지킨 손상이면 앱 판정이 키보드와 갈린다)
            let found = recoveryFiles().map { file in
                autoreleasepool { () -> (id: String, file: String, bytes: Int?, stored: StoredExternalPack?) in
                    let data = try? Data(contentsOf: packsDirectory.appendingPathComponent(file.file))
                    let stored = data.flatMap { try? StoredExternalPack.loadable(from: $0, packID: file.id).get() }
                    return (file.id, file.file, data?.count,
                            stored.map { StoredExternalPack(packID: $0.packID, source: $0.source, pack: $0.pack) })
                }
            }
            var library = PackLibrary()
            for candidate in found {
                library.order.append(.pack(candidate.id))
                library.packs[candidate.id] = candidate.stored.map { PackLibrary.Entry(file: candidate.file, isEnabled: false, stored: $0) }
                    ?? PackLibrary.Entry(file: candidate.file, isEnabled: false, stats: .zero)
            }
            // ① 원래 목록의 보관본 — 못 만들면 여기서 끝(아무것도 쓰지 않았다). 원래 목록은 제자리에 그대로다
            var backupName: String?
            if status != .missing {
                guard let name = preserveLibrary(now: now) else { return .failed }
                backupName = name
            }
            if crashPointForTesting == .recoveryBeforeWrite { return .failed }
            // 방금 디코드한 결과를 검사 결과로 남긴다 — 깨진 변환본은 바로 「읽을 수 없는 팩」(열지 못한 파일은 읽기 권한 검사가 뺀다)
            var checks = loadedChecks()
            for candidate in found {
                guard let bytes = candidate.bytes else { continue }
                checks[candidate.file] = PackContentCheck(bytes: bytes, isLoadable: candidate.stored != nil)
            }
            saveChecks(checks, keeping: library)
            // ② 새 목록·snapshot(켜진 팩 없음)·세대·알림 — 커밋과 같은 쓰기 순서(8-1).
            // ★ revision은 남은 변환본의 가장 큰 r 위로 잇는다(검증 F-6) — 1부터 다시 세면 복구 뒤 쓴 `<id>-r2`가 정리 전에 남은 옛
            //   `<id>-r57`보다 번호가 작아 다음 복구가 옛 내용을 고르고, 남아 있는 파일과 같은 이름을 다시 쓸 수도 있다
            var base = PackLibrary()
            base.revision = found.map { Self.packFileIdentity($0.file).revision }.max().map { max(0, $0) } ?? 0
            let state = State(library: base, user: userSnippets.entries(), disabled: disabledBuiltIns())
            var proposal = Proposal(change: .reorderPacks, state: state)
            proposal.library = library
            let unavailable = unavailablePackIDs(in: library)
            let input = budgetInput(library: library, user: state.user, disabled: state.disabled, unavailable: unavailable)
            let evaluation = withUnavailable(ActivePackBudget.evaluate(baseline: input.baseline, packs: input.packs, limits: limits),
                                             library: library, unavailable: unavailable)
            guard write(proposal, state: state, evaluation: evaluation) else {
                // 새 목록은 원자적으로 쓰므로 실패했다면 원래 목록이 그대로 있다 — 이번에 만든 보관본만 지운다
                if let backupName { try? FileManager.default.removeItem(at: libraryRoot.appendingPathComponent(backupName)) }
                return .failed
            }
            return .recovered(packs: found.count, unreadable: found.filter { $0.stored == nil }.count, backupFileName: backupName)
        }
    }

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

    /// 지우기 한 건 — **화면 목록과 같은 기준**(`snippetListID` = 정규화 단축어)으로 겹치는 저장분을 **모두** 지운다(검증 F7).
    /// 화면은 띄어쓰기만 다른 옛 중복을 하나로 보여 주므로, 하나만 지우면 지운 항목이 다시 보인다. 사용자에게 하나로 보이는
    /// 항목 하나라 「저장 1회 = 항목 1개」에 맞고, 줄이는 쪽이라 예산 판정에 막히지 않는다(`.deleteUserSnippets`는 거부 없음).
    @discardableResult
    public func deleteUserSnippet(_ entry: SnippetEntry, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            let target = entry.snippetListID
            guard state.user.contains(where: { $0.snippetListID == target }) else { return .failure(.notFound) }
            var proposal = Proposal(change: .deleteUserSnippets, state: state)
            proposal.user.removeAll { $0.snippetListID == target }
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
            proposal.library.packs[id] = PackLibrary.Entry(file: "", isEnabled: enabled, stored: stored)
            proposal.newPack = stored
            proposal.packID = id
            return .success(proposal)
        }
    }

    @discardableResult
    public func setPackEnabled(_ id: String, enabled: Bool, expectedRevision: Int? = nil) -> CommitResult {
        perform(expectedRevision: expectedRevision) { state in
            guard state.library.packs[id] != nil else { return .failure(.notFound) }
            if enabled, unavailablePackIDs(in: state.library).contains(id) { return .failure(.packUnavailable(id)) }
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
            proposal.library.packs[id] = PackLibrary.Entry(file: "", isEnabled: entry.isEnabled, stored: stored)
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
    ///
    /// 1-c 2단계: ① `userSnippetsGeneration`을 한 번 올리고 알린다(G9 — 내 채움글 저장 ③과 세대 올림 ⑤ 사이에 앱이 죽었으면 키보드가
    /// 옛 문구를 같은 세대 키로 계속 쓴다) ② 아직 검사하지 않은 변환본을 **한 번씩** 디코드해(G6, 결과는 파일 이름 + 크기로 남긴다) 키보드가
    /// 버릴 내용이면 그 팩만 `.unavailable`로 돌린다 ③ **지금 판정이 지금 snapshot과 다르면** snapshot을 다시 쓴다 — 깨진 팩 하나 때문에
    /// 키보드가 외부 팩 전부를 버리지 않게(판정 == snapshot, AC-8). 메인에서 부르지 않는다(`PackStoreClient.maintain`, 최대 16 × 3MB 디코드).
    public func maintain() {
        queue.sync {
            generations.setUserSnippetsGeneration(generations.userSnippetsGeneration + 1)
            defer { notify() }
            // ★ 목록을 못 읽으면 **아무것도 지우지 않는다**(검증 C1) — 빈 목록으로 보면 변환본이 전부 「안 쓰는 파일」이 된다
            guard let library = readLibrary() else { return }
            // 지난 실행이 못 지운 것(삭제 실패·정리 전 종료)도 여기서 다시 지운다 — 목록이 가리키지 않는 변환본, `purgeBelow` 아래 세대(codex 반론 #6)
            removeUnreferencedPackFiles(library: library)
            collectSnapshotGarbage(current: generations.packsGeneration, purgeBelow: library.purgeBelow)
            checkPackContents(library: library)
            let evaluation = currentEvaluation(library: library, unavailable: unavailablePackIDs(in: library))
            // ★ 다시 쓸지는 「지금 판정 ≠ 지금 snapshot」으로 정한다(검증 F-1). 「검사 전 ≠ 검사 후」로 정하면 검사 결과는 파일에 남았는데
            //   snapshot 쓰기가 실패한(또는 그 사이 앱이 죽은) 다음 실행에서 둘이 같아져 다시 쓰지 않고, 키보드는 다음 커밋까지 외부 팩 전부를 버린다.
            // ★ 순서만 보지 않는다(codex 반론 #2) — 목록에 적힌 게시 세대가 지금 세대와 다르면 커밋이 ④ 목록과 ⑤ 세대 사이에서 끝났다. 내용만
            //   바뀐 바꾸기는 순서가 같아 순서 비교로는 못 잡고, 앱은 새 내용·키보드는 옛 내용을 계속 쓴다. 다시 게시해 마무리한다(옛 목록은 nil — 순서만)
            let unfinished = library.generation.map { $0 != generations.packsGeneration } ?? false
            guard unfinished || publishedOrder() != Self.snapshotOrder(library: library, included: evaluation.included),
                  let state = loadState() else { return }
            _ = write(Proposal(change: .reorderPacks, state: state), state: state, evaluation: evaluation)
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
            // ★ 목록이 있는데 못 읽으면 커밋하지 않는다 — 빈 목록으로 판정해 덮어쓰면 팩 목록이 사라진다(검증 C1, 9-3)
            guard let state = loadState() else { return .rejected(.libraryUnreadable, rechecked: false) }
            let rechecked = expectedRevision.map { $0 != state.library.revision } ?? false
            var proposal: Proposal
            switch make(state) {
            case .failure(let rejection): return .rejected(rejection, rechecked: rechecked)
            case .success(let value): proposal = value
            }
            proposal.userChanged = proposal.user != state.user
            // ★ 저장 팩 수(9-4 ② — 꺼진 팩·읽을 수 없는 팩 포함)는 **목록**으로 센다(codex 반론 #5). 게이트의 수 검사는 판정 입력(`budgetInput`
            //   — 읽을 수 없는 팩을 뺀다)을 세므로 그것만으로는 16개를 넘겨 저장되고, 앱은 17개를 판정하는데 키보드는 앞 16개만 읽는다(AC-8).
            //   활성 예산과 따로 본다 — 수가 늘거나(가져오기) 그대로인(바꾸기) 경로 모두. 줄이는 쪽(지우기)은 막지 않는다
            if Self.storesPack(proposal.change), proposal.library.packs.count > PackLimits.externalPacks {
                return .rejected(.gate(.tooManyPacks), rechecked: rechecked)
            }
            let currentBase = proposal.currentOverride ?? (state.user, state.disabled)
            // C5 — 변환본을 읽을 수 없는 팩은 **판정 단계에서** 뺀다(예산 자리도 차지하지 않는다). 이번에 새로 쓰는 변환본은 읽을 수 있다
            var unavailable = unavailablePackIDs(in: proposal.library)
            if let newID = proposal.newPack?.packID { unavailable.remove(newID) }
            let current = budgetInput(library: state.library, user: currentBase.user, disabled: currentBase.disabled,
                                      unavailable: unavailablePackIDs(in: state.library))
            let proposed = budgetInput(library: proposal.library, user: proposal.user, disabled: proposal.disabled,
                                       unavailable: unavailable)
            switch PackCommitGate.judge(proposal.change, current: current, proposed: proposed, limits: limits) {
            case .reject(let rejection):
                return .rejected(.gate(rejection), rechecked: rechecked)
            case .accept(let judged, let newlyExcluded):
                let evaluation = withUnavailable(judged, library: proposal.library, unavailable: unavailable)
                beforeWriteForTesting?()
                guard ensureLibraryFile(state.library), write(proposal, state: state, evaluation: evaluation) else {
                    return .rejected(.writeFailed, rechecked: rechecked)
                }
                return .accepted(Accepted(revision: state.library.revision + 1, packID: proposal.packID,
                                          newlyExcluded: newlyExcluded, evaluation: evaluation, rechecked: rechecked))
            }
        }
    }

    /// 팩 파일을 하나 더 저장하거나 갈아 끼우는 변경 — 저장 팩 수를 목록으로 본다(codex 반론 #5)
    private static func storesPack(_ change: PackCommitGate.Change) -> Bool {
        switch change {
        case .importPack, .importDisabledPack, .replaceActivePack, .replaceInactivePack: true
        default: false
        }
    }

    /// 8-1 ③의 순서로 쓴다. 커밋 지점(`packsGeneration`) 전에 실패하면 새로 쓴 것을 지우고 false
    private func write(_ proposal: Proposal, state: State, evaluation: ActivePackBudget.Evaluation) -> Bool {
        let fileManager = FileManager.default
        var library = proposal.library
        library.revision = state.library.revision + 1
        var newFiles: [URL] = []
        func rollback() { newFiles.forEach { try? fileManager.removeItem(at: $0) } }
        let purges = Self.purgesOldSnapshots(proposal.change)

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
        if crashPointForTesting == .beforeLibrary { return false }
        // 목록에 이 커밋의 세대와 정리 몫을 함께 적는다 — ⑤·⑥ 전에 앱이 끝나도 다음 실행이 알아보고 마무리한다(codex 반론 #2·#6).
        // `purgeBelow`는 지우기·바꾸기 세대에서 오르고 뒤 커밋이 그대로 이어 간다(세대가 되돌아간 경우만 지금 세대로 낮춘다)
        library.generation = newPacksGeneration
        library.purgeBelow = purges ? newPacksGeneration : library.purgeBelow.map { min($0, newPacksGeneration) }
        guard (try? ensureDirectory(libraryRoot)) != nil, let data = try? JSONEncoder().encode(library),
              (try? data.write(to: libraryURL, options: .atomic)) != nil else {
            if proposal.userChanged {
                userSnippets.save(state.user)
                // ★ 되돌렸어도 세대는 올리고 알린다(검증 C2) — ③과 되돌리기 사이에 읽은 키보드가 **실패한 문구를 같은 세대 키로
                //   캐시**하지 않게. 내용은 원래대로, 세대만 하나 오른다(다음 읽기가 원래 문구를 다시 읽는다)
                generations.setUserSnippetsGeneration(newUserGeneration)
                notify()
            }
            rollback()
            return false
        }

        // ⑤ 세대 — packsGeneration이 커밋 지점
        if crashPointForTesting == .beforePacksGeneration { return true }
        if proposal.userChanged { generations.setUserSnippetsGeneration(newUserGeneration) }
        generations.setPacksGeneration(newPacksGeneration)
        if crashPointForTesting == .beforeCleanup { return true }

        // ⑥ 정리 — 앱의 변경 때만(키보드는 지우지 않는다) ⑦ 알림.
        // ★ 팩을 **지우거나 바꾸면** 옛 snapshot 세대를 모두 지운다(평소 커밋은 현재 − 2 이하만) — 지운 팩·바꾸기 전 내용이 키보드가 읽는
        //   App Group 공유 사본에 채움글을 두 번 더 바꿀 때까지 남지 않게(기획 1-d 「지우면 기기에서 지워져요」). 그 세대를 읽던 키보드는
        //   소실을 보고 현재 세대로 다시 읽는다(AC-26). 지운 파일의 검사 기록(pack-checks)도 함께 뺀다.
        // ★ 여기서 못 지운 것(삭제 실패·이 사이 종료)은 목록에 적힌 `purgeBelow`로 다음 커밋·다음 실행(`maintain`)이 다시 지운다(codex 반론 #6)
        removeUnreferencedPackFiles(library: library)
        pruneChecks(keeping: library)
        collectSnapshotGarbage(current: newPacksGeneration, purgeBelow: library.purgeBelow)
        notify()
        return true
    }

    /// 팩 내용이 기기에서 바로 사라져야 하는 커밋 — 지우기·바꾸기(켜진 팩·꺼진 팩 모두 — 꺼진 팩도 옛 세대에는 켜진 채 있을 수 있다)
    private static func purgesOldSnapshots(_ change: PackCommitGate.Change) -> Bool {
        switch change {
        case .deletePack, .replaceActivePack, .replaceInactivePack: true
        default: false
        }
    }

    /// snapshot 폴더 하나를 처음부터 쓴다 — 팩 파일을 다 쓴 **뒤** 마지막에 manifest(8절). `included`는 판정이 이미 못 읽는 팩을 뺀
    /// 목록이다(C5) — 여기서 팩을 **조용히 빼지 않는다**(판정 == snapshot, AC-8). 그 사이 파일이 사라지면(경쟁) 이 커밋은 실패하고
    /// 다음 커밋의 판정이 그 팩을 `.unavailable`로 뺀다.
    private func publishSnapshot(library: PackLibrary, included: [String], generation: Int, userRevision: Int) -> URL? {
        let fileManager = FileManager.default
        let directory = PackStorageLocations.generationDirectory(generation, in: snapshotRoot)
        try? fileManager.removeItem(at: directory)   // 이전 실패의 잔여
        do {
            try ensureDirectory(directory)
            var items: [PackSnapshotManifest.Item] = []
            let order = Self.snapshotOrder(library: library, included: included)
            for id in order.compactMap(\.packID) {
                guard let entry = library.packs[id] else { continue }
                let source = packsDirectory.appendingPathComponent(entry.file)
                let fileName = "\(id).json"
                let target = directory.appendingPathComponent(fileName)
                try fileManager.copyItem(at: source, to: target)
                let bytes = (try fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.intValue ?? 0
                items.append(.init(id: id, file: fileName, bytes: bytes, stats: entry.stats))
            }
            let manifest = PackSnapshotManifest(generation: generation, userSnippetsRevision: userRevision, order: order, packs: items)
            try JSONEncoder().encode(manifest).write(
                to: directory.appendingPathComponent(PackStorageLocations.manifestFileName), options: .atomic)
            return directory
        } catch {
            try? fileManager.removeItem(at: directory)
            return nil
        }
    }

    /// snapshot manifest에 싣는 순서 — 「내 채움글」 줄 + 판정이 포함한 켜진 팩(목록 순서). 발행과 `maintain`의 비교가 이 식 하나를 쓴다
    private static func snapshotOrder(library: PackLibrary, included: [String]) -> [SnippetSourceSlot] {
        let includedSet = Set(included)
        return library.order.filter { slot in slot.packID.map(includedSet.contains) ?? true }
    }

    /// 지금 snapshot의 순서 목록 — 세대 0(아직 쓴 적 없음)이면 키보드가 쓰는 기본 순서, manifest를 못 읽으면 nil(키보드가 외부 팩 전부를
    /// 버리는 상태 — 다시 쓸 대상)
    private func publishedOrder() -> [SnippetSourceSlot]? {
        let generation = generations.packsGeneration
        guard generation > 0 else { return SnippetSourceSlot.defaultOrder }
        let url = PackStorageLocations.generationDirectory(generation, in: snapshotRoot)
            .appendingPathComponent(PackStorageLocations.manifestFileName)
        guard let data = try? Data(contentsOf: url), let manifest = try? JSONDecoder().decode(PackSnapshotManifest.self, from: data),
              manifest.schema == PackSnapshotManifest.schemaVersion else { return nil }
        return manifest.order
    }

    /// 지금 세대와 바로 앞 세대만 남긴다 — 현재 − 2 이하(8-2, 읽고 있던 키보드는 현재 세대로 재시도한다)와 **현재보다 큰 세대**(커밋 지점
    /// 전에 끝난 커밋의 고아 — 키보드가 읽은 적이 없다, codex 반론 #2)를 지운다. `purgeBelow` 아래는 바로 앞 세대도 지운다 — 팩을 지우거나
    /// 바꾼 커밋 앞의 세대에는 옛 내용이 있다(1-d, 반론 #6). 지금 세대는 어느 경우에도 지우지 않는다
    private func collectSnapshotGarbage(current: Int, purgeBelow: Int?) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: snapshotRoot.path) else { return }
        for name in names where name.hasPrefix("g") {
            guard let generation = Int(name.dropFirst()), generation != current else { continue }
            guard generation > current || generation <= current - 2 || generation < (purgeBelow ?? .min) else { continue }
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

    /// 앱 전용 목록 — **파일이 없으면(처음) 빈 목록, 있는데 못 읽음·손상·낯선 schema면 nil**(검증 C1). 둘을 섞으면 손상된 목록을
    /// 빈 목록으로 보고 정리가 변환본을 전부 지우고 다음 커밋이 빈 목록으로 덮어쓴다. 파일이 없어도 팩 파일·복구 보관본이 남아 있으면
    /// 처음이 아니다 — nil(`.missing`, codex 반론 #1)
    private func readLibrary() -> PackLibrary? { loadLibrary().library }

    /// 목록과 그 상태(1-c G4 — 읽히지 않는 사유를 가른다). **schema를 먼저 본다** — 새 버전 목록은 모양이 달라 전체 디코드가 실패할 수
    /// 있는데, 그것을 「손상」으로 보면 「앱을 올리면 다시 읽힌다」는 안내를 못 한다
    private func loadLibrary() -> (library: PackLibrary?, status: PackLibraryStatus) {
        guard FileManager.default.fileExists(atPath: libraryURL.path) else {
            return hasLibraryTraces() ? (nil, .missing) : (PackLibrary(), .readable)
        }
        guard let data = try? Data(contentsOf: libraryURL) else { return (nil, .unreadable) }
        if let probe = try? JSONDecoder().decode(SchemaProbe.self, from: data), probe.schema != PackLibrary.schemaVersion {
            return (nil, .unknownSchema)
        }
        guard let library = try? JSONDecoder().decode(PackLibrary.self, from: data) else { return (nil, .corrupt) }
        return (library, .readable)
    }

    private struct SchemaProbe: Decodable {
        var schema: Int
    }

    /// 원래 목록의 보관본을 만든다 — `library.damaged-<UTC yyyyMMdd'T'HHmmss'Z'>.json`, 있으면 `-2`·`-3`…. **원래 목록은 옮기지 않는다**
    /// (codex 반론 #1). 하드 링크가 먼저다 — 읽을 수 없는 목록(권한)도 내용을 읽지 않고 남긴다. 링크가 안 되는 볼륨이면 복사. 만든 이름, 못 만들면 nil
    private func preserveLibrary(now: Date) -> String? {
        let fileManager = FileManager.default
        let stem = "\(Self.backupPrefix)\(Self.backupStamp(now))"
        var name = "\(stem).json"
        var suffix = 2
        while fileManager.fileExists(atPath: libraryRoot.appendingPathComponent(name).path) {
            name = "\(stem)-\(suffix).json"
            suffix += 1
        }
        let backup = libraryRoot.appendingPathComponent(name)
        guard (try? fileManager.linkItem(at: libraryURL, to: backup)) != nil
                || (try? fileManager.copyItem(at: libraryURL, to: backup)) != nil else { return nil }
        return name
    }

    private static let backupPrefix = "library.damaged-"

    /// 목록 파일이 없을 때 — 처음 상태인가, 목록만 사라진 상태인가(codex 반론 #1). 가져온 팩 파일이나 복구 보관본이 남아 있으면 처음이
    /// 아니다(복구 도중 종료·목록 소실). 처음 커밋은 목록부터 만들므로(`ensureLibraryFile`) 커밋 도중 종료로는 이 흔적이 생기지 않는다
    private func hasLibraryTraces() -> Bool {
        if !recoveryFiles().isEmpty { return true }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: libraryRoot.path)) ?? []
        return names.contains { $0.hasPrefix(Self.backupPrefix) }
    }

    /// 처음 커밋 — 목록 파일이 없으면 지금 상태(빈 목록)를 먼저 쓴다. 그래야 변환본을 쓴 뒤 목록을 쓰기 전에 앱이 끝나도 「목록 없음 + 팩 파일」
    /// (`.missing`)이 되지 않는다 — 남은 변환본은 커밋되지 않은 파일로 다음 실행이 정리한다. 이미 있으면 아무것도 하지 않는다
    private func ensureLibraryFile(_ library: PackLibrary) -> Bool {
        guard !FileManager.default.fileExists(atPath: libraryURL.path) else { return true }
        guard (try? ensureDirectory(libraryRoot)) != nil, let data = try? JSONEncoder().encode(library) else { return false }
        return (try? data.write(to: libraryURL, options: .atomic)) != nil
    }

    static func backupStamp(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
                      parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    /// 복구가 불러올 변환본 — 팩 id마다 하나(revision이 가장 큰 것), **이름의 r 번호 순**(그 팩을 마지막으로 쓴 커밋 차례 — 가져온 순서에
    /// 가깝다), 같으면 파일 이름 순. 내용은 읽지 않는다.
    /// ★ 파일 수정 시각을 읽지 않는다(검증 F-1) — 수정 시각은 애플 필수 사유 API(File timestamp)이고 PDR 1-d가 「파일 타임스탬프 미접근」을
    ///   심사 정합 조건으로 적었다. r 번호는 커밋마다 하나씩 오르므로 쓴 차례를 시각 없이 그대로 준다
    private func recoveryFiles() -> [(id: String, file: String)] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: packsDirectory.path) else { return [] }
        var newest: [String: (revision: Int, file: String)] = [:]
        for name in names where name.hasSuffix(".json") {
            let identity = Self.packFileIdentity(name)
            guard PackSnapshotLoader.isPlainFileName(identity.id) else { continue }
            if let current = newest[identity.id], current.revision >= identity.revision { continue }
            newest[identity.id] = (identity.revision, name)
        }
        return newest.map { (id: $0.key, revision: $0.value.revision, file: $0.value.file) }
            .sorted { ($0.revision, $0.file) < ($1.revision, $1.file) }
            .map { (id: $0.id, file: $0.file) }
    }

    /// 변환본 파일 이름 `<팩 id>-r<revision>.json`(커밋이 쓰는 모양) → id·revision. 모양이 다르면 이름 전체가 id, revision −1
    static func packFileIdentity(_ name: String) -> (id: String, revision: Int) {
        let stem = String(name.dropLast(".json".count))
        if let marker = stem.range(of: "-r", options: .backwards) {
            let digits = stem[marker.upperBound...]
            if !digits.isEmpty, digits.allSatisfy(\.isASCII), let revision = Int(digits), marker.lowerBound > stem.startIndex {
                return (String(stem[..<marker.lowerBound]), revision)
            }
        }
        return (stem, -1)
    }

    // MARK: 내용 검사 결과 (G6)
    //
    // 받는 조건은 키보드 로더와 **같은 함수** `StoredExternalPack.loadable(from:packID:)`(TadakDomain, 검증 F-4) — 어긋나면 키보드는 외부 팩
    // 전부를 버리므로(AC-8) 앱이 미리 그 팩만 뺀다. 여기에 조건을 따로 두지 않는다.

    private var checksURL: URL { libraryRoot.appendingPathComponent("pack-checks.json") }

    /// 옛 모양(1-c 2단계 `66518e2`의 이름 → Bool)은 디코드되지 않아 빈 결과로 본다 — 다음 실행 검사가 한 번 다시 본다
    private func loadedChecks() -> [String: PackContentCheck] {
        if let contentChecks { return contentChecks }
        let stored = (try? Data(contentsOf: checksURL))
            .flatMap { try? JSONDecoder().decode([String: PackContentCheck].self, from: $0) } ?? [:]
        contentChecks = stored
        return stored
    }

    /// 이 파일의 검사 결과 — 없거나 **크기가 검사 때와 다르면** nil(아직 안 본 파일로 — 다음 검사가 다시 본다, 검증 (e))
    private func checkedLoadable(_ file: String, in checks: [String: PackContentCheck]) -> Bool? {
        guard let check = checks[file],
              let size = (try? FileManager.default.attributesOfItem(
                atPath: packsDirectory.appendingPathComponent(file).path)[.size] as? NSNumber)?.intValue,
              size == check.bytes else { return nil }
        return check.isLoadable
    }

    /// 커밋 뒤 — 목록이 가리키지 않는 파일의 검사 결과가 있을 때만 다시 쓴다(지운 팩·바꾸기 전 변환본의 이름이 기록에 남지 않게, 1-d).
    /// 평소 커밋은 남길 것이 없어 쓰지 않는다
    private func pruneChecks(keeping library: PackLibrary) {
        let checks = loadedChecks()
        let referenced = Set(library.packs.values.map(\.file))
        guard checks.keys.contains(where: { !referenced.contains($0) }) else { return }
        saveChecks(checks, keeping: library)
    }

    /// 목록이 가리키는 파일 것만 남긴다(교체·삭제로 사라진 파일의 결과는 버린다). 쓰지 못하면 메모리에만 — 다음 실행이 다시 검사한다
    private func saveChecks(_ checks: [String: PackContentCheck], keeping library: PackLibrary) {
        let referenced = Set(library.packs.values.map(\.file))
        let kept = checks.filter { referenced.contains($0.key) }
        contentChecks = kept
        guard (try? ensureDirectory(libraryRoot)) != nil, let data = try? JSONEncoder().encode(kept) else { return }
        try? data.write(to: checksURL, options: .atomic)
    }

    /// 아직 검사하지 않은 변환본을 한 번씩 디코드한다 — 파일 이름에 revision이 붙어 교체하면 새 이름이 되므로 결과가 낡지 않는다.
    /// 같은 이름의 파일이 잘리거나 바뀌면(디스크 손상) 크기가 달라져 다시 본다(검증 (e) — 크기가 같은 손상은 못 잡는다).
    /// 열 수 없는 파일은 이미 `.unavailable`(읽기 권한 검사)이라 결과를 남기지 않는다(나중에 열리면 그때 본다)
    private func checkPackContents(library: PackLibrary) {
        var checks = loadedChecks()
        for (id, entry) in library.packs where !entry.file.isEmpty && checkedLoadable(entry.file, in: checks) == nil {
            guard let data = try? Data(contentsOf: packsDirectory.appendingPathComponent(entry.file)) else { continue }
            checks[entry.file] = autoreleasepool {
                PackContentCheck(bytes: data.count, isLoadable: (try? StoredExternalPack.loadable(from: data, packID: id).get()) != nil)
            }
        }
        saveChecks(checks, keeping: library)
    }

    /// 목록의 표시 칸 — 비었으면(1-b 목록) 변환본에서 채운다. 못 읽는 팩은 열지 않는다
    private func display(of entry: PackLibrary.Entry,
                         isUnavailable: Bool) -> (name: String?, mode: ExternalPack.Mode?, titleFormat: String?) {
        if entry.name == nil, !isUnavailable, let stored = readStoredPack(file: entry.file) {
            return (stored.pack.name, stored.pack.mode, stored.pack.template?.titleFormat)
        }
        return (entry.name, entry.mode, entry.titleFormat)
    }

    /// 변환본 하나 — 표시 칸이 없는 옛 목록의 이름 채우기에만 쓴다(최대 3MB 디코드라 커밋 경로에서는 부르지 않는다)
    private func readStoredPack(file: String) -> StoredExternalPack? {
        guard !file.isEmpty, let data = try? Data(contentsOf: packsDirectory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(StoredExternalPack.self, from: data)
    }

    /// `impactLibrary`·`packDetail`의 몸통 — 큐 안에서만. `keeping` 팩의 변환본 내용은 따로 돌려준다(두 번 디코드하지 않게)
    private func makeImpactLibrary(keeping keptID: String?) -> (library: PackImpact.Library, kept: ExternalPack?)? {
        guard let library = readLibrary() else { return nil }
        let unavailable = unavailablePackIDs(in: library)
        let user = userSnippets.entries()
        let disabled = disabledBuiltIns()
        let builtIn = builtInEntries(Set(disabled))
        let input = budgetInput(library: library, user: user, disabled: disabled, unavailable: unavailable)
        let evaluation = withUnavailable(ActivePackBudget.evaluate(baseline: input.baseline, packs: input.packs, limits: limits),
                                         library: library, unavailable: unavailable)
        var kept: ExternalPack?
        let packs = library.order.compactMap(\.packID).compactMap { id -> PackImpact.Pack? in
            guard let entry = library.packs[id] else { return nil }
            let isUnavailable = unavailable.contains(id)
            let content: ExternalPack? = isUnavailable ? nil : autoreleasepool { readStoredPack(file: entry.file)?.pack }
            if id == keptID { kept = content }
            // 표시 칸은 `display(of:isUnavailable:)`(`summaries()`)와 같은 규칙 — 목록 칸이 비었으면(1-b 목록) 방금 읽은 내용에서
            let display = entry.name == nil ? content.map { ($0.name, $0.mode, $0.template?.titleFormat) } : nil
            let summary = PackSummary(id: id, name: display?.0 ?? entry.name, mode: display?.1 ?? entry.mode,
                                      itemCount: entry.stats.items, titleFormat: display == nil ? entry.titleFormat : display?.2,
                                      isEnabled: entry.isEnabled,
                                      status: PackSummary.status(of: id, isEnabled: entry.isEnabled, isUnavailable: isUnavailable,
                                                                 in: evaluation))
            return PackImpact.Pack(summary: summary, stats: entry.stats, content: content)
        }
        let impactLibrary = PackImpact.Library(
            revision: library.revision, order: library.order, packs: packs, userSnippets: input.userSnippets, builtIn: input.builtIn,
            userTriggers: user.flatMap(\.triggers), builtInTriggers: builtIn.flatMap(\.triggers),
            userSnippetCount: UserSnippetBudget.displayEntries(user).count, limits: limits)
        return (impactLibrary, kept)
    }

    private func loadState() -> State? {
        readLibrary().map { State(library: $0, user: userSnippets.entries(), disabled: disabledBuiltIns()) }
    }

    /// 목록이 가리키는 변환본이 없거나 읽을 수 없거나(검증 F4·C5) **내용 검사에서 키보드가 버릴 것으로 나온**(1-c G6) 팩. 커밋마다
    /// 디코드하지는 않는다(최대 3MB) — 내용은 앱 실행 검사·복구가 남긴 결과(파일 이름 + 크기)를 본다
    private func unavailablePackIDs(in library: PackLibrary) -> Set<String> {
        let checks = loadedChecks()
        return Set(library.packs.compactMap { id, entry in
            entry.file.isEmpty || checkedLoadable(entry.file, in: checks) == false
                || !FileManager.default.isReadableFile(atPath: packsDirectory.appendingPathComponent(entry.file).path)
                ? id : nil
        })
    }

    /// 못 읽는 팩은 예산 후보에서 뺀다 — 앞에서 예산 자리를 차지하지 않는다(뒤 팩이 그 몫으로 들어올 수 있다 — 예산 쉼과 같은 결과)
    private func budgetInput(library: PackLibrary, user: [SnippetEntry], disabled: [String], unavailable: Set<String>) -> PackBudgetInput {
        let packs = library.order.compactMap(\.packID).filter { !unavailable.contains($0) }.compactMap { id in
            library.packs[id].map { ActivePackBudget.Candidate(id: id, isEnabled: $0.isEnabled, stats: $0.stats) }
        }
        let baseline = Self.baselineStats(user: user, builtInEntries: builtInEntries(Set(disabled)), limits: limits)
        return PackBudgetInput(userSnippets: baseline.user, builtIn: baseline.builtIn, packs: packs)
    }

    /// 내 채움글·켜진 내장의 예산 몫 — 커밋 판정과 사전 영향 계산(`PackImpact.Library`)이 이 하나를 쓴다. 내 채움글 stats는 키보드 로더와
    /// **같은 함수**로 센다(AC-8) — 항목마다 한 번 인코드, 배열 재인코드 없음(R23)
    static func baselineStats(user: [SnippetEntry], builtInEntries: [SnippetEntry],
                              limits: PackBudgetLimits) -> (user: PackStats, builtIn: PackStats) {
        let builtIn = PackStats.of(entries: builtInEntries)
        return (ActivePackBudget.userSnippetUsage(user, builtIn: builtIn, limits: limits).stats, builtIn)
    }

    /// 지금 저장본(내 채움글·끈 내장은 저장된 값)의 판정 — `evaluation()`·`summaries()`가 같은 계산을 쓴다
    private func currentEvaluation(library: PackLibrary, unavailable: Set<String>) -> ActivePackBudget.Evaluation {
        let input = budgetInput(library: library, user: userSnippets.entries(), disabled: disabledBuiltIns(), unavailable: unavailable)
        return withUnavailable(ActivePackBudget.evaluate(baseline: input.baseline, packs: input.packs, limits: limits),
                               library: library, unavailable: unavailable)
    }

    /// 판정 결과에 **켜진** 못 읽는 팩을 `.unavailable` 제외로 싣는다(목록 순서) — 1-c가 이유를 보일 수 있게(C5)
    private func withUnavailable(
        _ evaluation: ActivePackBudget.Evaluation, library: PackLibrary, unavailable: Set<String>
    ) -> ActivePackBudget.Evaluation {
        var evaluation = evaluation
        evaluation.excluded += library.order.compactMap(\.packID)
            .filter { unavailable.contains($0) && library.packs[$0]?.isEnabled == true }
            .map { ActivePackBudget.Exclusion(id: $0, reason: .unavailable) }
        return evaluation
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

/// 앱 전용 목록 — 순서(U1 「내 채움글」 줄 포함)·켬/끔·변환본 파일·stats(앱이 계산, 판정용)·표시 칸(1-c). 파일 하나, 원자적 쓰기.
struct PackLibrary: Codable, Equatable {
    static let schemaVersion = 1

    struct Entry: Codable, Equatable {
        var file: String
        var isEnabled: Bool
        var stats: PackStats
        // MARK: 표시 칸(1-c G1) — 커밋 때 변환본과 함께 채운다. 목록 행·알림의 팩 이름이 변환본을 열지 않고(못 읽는 팩도) 여기서 나온다.
        // **선택 칸이라 이행이 없다** — 1-b 목록에는 이 키가 없고 그대로 디코드된다(nil), schema 번호도 그대로다.
        // 항목 수는 `stats.items`를 쓴다(따로 두지 않는다). 팩 이름은 사용자 입력이다 — 로그·네트워크 0
        /// 팩 이름(40자 이하)
        var name: String?
        var mode: ExternalPack.Mode?
        /// 대표 틀 — 번호형의 첫 `#틀` 원문(`PackTemplate.titleFormat`), 문구형은 nil
        var titleFormat: String?

        init(file: String, isEnabled: Bool, stats: PackStats,
             name: String? = nil, mode: ExternalPack.Mode? = nil, titleFormat: String? = nil) {
            self.file = file
            self.isEnabled = isEnabled
            self.stats = stats
            self.name = name
            self.mode = mode
            self.titleFormat = titleFormat
        }

        /// 새 변환본으로 — stats·표시 칸을 그 값에서. stats는 `stored.stats` 그대로라 **다시 센 값을 넘긴다**(커밋·복구 모두
        /// `StoredExternalPack(packID:source:pack:)`로 만든 값 — 디코드한 파일의 stats를 그대로 넘기지 않는다, 검증 F-2)
        init(file: String, isEnabled: Bool, stored: StoredExternalPack) {
            self.init(file: file, isEnabled: isEnabled, stats: stored.stats, name: stored.pack.name, mode: stored.pack.mode,
                      titleFormat: stored.pack.template?.titleFormat)
        }
    }

    var schema = PackLibrary.schemaVersion
    var revision = 0
    var order: [SnippetSourceSlot] = SnippetSourceSlot.defaultOrder
    var packs: [String: Entry] = [:]
    // MARK: 커밋 마무리 칸(codex 반론 #2·#6) — **선택 칸이라 이행이 없다**(옛 목록은 nil로 디코드, schema 번호 그대로).
    /// 이 목록을 게시한 snapshot 세대 — 커밋 ④에서 ⑤(`packsGeneration`)에 쓸 값을 미리 적는다. 실행 때 지금 세대와 다르면 커밋이 그 사이에서
    /// 끝난 것이라 다시 게시한다(`maintain`). nil이면(옛 목록) 순서 비교만 한다
    var generation: Int?
    /// 이 세대 **아래**의 snapshot은 지운다 — 팩을 지우거나 바꾼 커밋의 세대(그 앞 세대에 옛 내용이 있다, 1-d). 뒤 커밋이 그대로 이어 가므로
    /// 정리가 실패했거나 정리 전에 앱이 끝났어도 다음 커밋·다음 실행이 다시 지운다. 세대는 오르기만 하니 한 번 지운 뒤에는 할 일이 없다
    var purgeBelow: Int?
}

/// 변환본 내용 검사 결과 하나(1-c G6, `pack-checks.json`의 값) — **파일 이름 + 크기**로 맞춘다(검증 (e)). 이름은 revision마다 새로 짓지만,
/// 같은 이름의 파일이 잘리거나 바뀌면 크기가 달라져 다시 검사한다. 사용자 텍스트는 담지 않는다(이름은 무작위 팩 id + revision)
struct PackContentCheck: Codable, Equatable {
    var bytes: Int
    var isLoadable: Bool
}
