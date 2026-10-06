import Foundation
import TadakDomain

/// 앱 화면용 `PackStore` 래퍼 — **메인 스레드에서 파일 IO·판정을 하지 않게**(1-c 계획서 2절 G8, 검증 6절).
///
/// `PackStore`의 공개 메서드는 모두 `queue.sync`라 부른 스레드가 그동안 멈춘다. 화면(@MainActor)이 그대로 부르면 snapshot 쓰기·
/// 내 채움글 인코딩 동안 화면이 멈춘다. 이 래퍼는 그 호출을 **전역 큐로 넘기고** `await`로 돌려받는다 — 화면은 `await` 뒤 자기 액터
/// (메인)로 돌아와 상태를 바꾼다. `PackStore`의 직렬성(큐 하나·판정과 쓰기 사이 끼어들기 없음)은 그대로다 — 줄 서는 자리만 옮긴다.
///
/// 쓰기 결과는 **사유별 알림**(`PackChangeNotice`)과 함께 돌려준다. 알림에 필요한 저장본 조회(저장 전 한도 상태·팩 이름)도 같은
/// 메인 밖 작업 안에서, **필요할 때만** 한다.
public struct PackStoreClient: Sendable {

    /// 제품 — `PackStore.live` 하나를 쓴다(쓰기 진입점은 여전히 하나)
    public static let live = PackStoreClient(store: .live)

    private let store: PackStore
    private let queue: DispatchQueue

    public init(store: PackStore, queue: DispatchQueue = .global(qos: .userInitiated)) {
        self.store = store
        self.queue = queue
    }

    // MARK: - 읽기

    public func summaries() async -> [PackSummary] { await run { $0.summaries() } }
    public func evaluation() async -> ActivePackBudget.Evaluation { await run { $0.evaluation() } }
    public func isLibraryReadable() async -> Bool { await run { $0.isLibraryReadable } }
    public func revision() async -> Int { await run { $0.revision } }
    public func order() async -> [SnippetSourceSlot] { await run { $0.order } }
    public func unreadablePackIDs() async -> [String] { await run { $0.unreadablePackIDs() } }
    public func libraryStatus() async -> PackLibraryStatus { await run { $0.libraryStatus() } }
    public func userSnippetBudget() async -> UserSnippetBudget { await run { $0.userSnippetBudget() } }
    public func recoveryPreview() async -> Int? { await run { $0.recoveryPreview() } }
    /// 앱 실행 때 한 번(옛 세대·안 쓰는 변환본 정리 · 내 채움글 세대 올림 · 변환본 내용 검사 — 1-c G6·G9)
    public func maintain() async { await run { $0.maintain() } }

    /// 목록 복구(R24) — 사용자가 확인 시트에서 「복구」를 누른 뒤에만
    public func recoverLibrary() async -> PackLibraryRecovery { await run { $0.recoverLibrary() } }

    // MARK: - 쓰기 — `PackStore`의 같은 이름 메서드 그대로, 결과에 알림을 붙인다

    public func saveUserSnippet(_ entry: SnippetEntry, editing original: SnippetEntry?,
                                expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(.saveUserSnippet) { $0.saveUserSnippet(entry, editing: original, expectedRevision: expectedRevision) }
    }

    public func deleteUserSnippet(_ entry: SnippetEntry, expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(.deleteUserSnippet) { $0.deleteUserSnippet(entry, expectedRevision: expectedRevision) }
    }

    public func setBuiltInPack(_ id: String, enabled: Bool, currentDisabled: [String],
                               expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(enabled ? .enableBuiltIn : .disableBuiltIn) {
            $0.setBuiltInPack(id, enabled: enabled, currentDisabled: currentDisabled, expectedRevision: expectedRevision)
        }
    }

    public func importPack(_ pack: ExternalPack, source: StoredExternalPack.Source, enabled: Bool = true,
                           expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(enabled ? .importPack : .importDisabledPack) {
            $0.importPack(pack, source: source, enabled: enabled, expectedRevision: expectedRevision)
        }
    }

    public func setPackEnabled(_ id: String, enabled: Bool, expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(enabled ? .enablePack : .disablePack) { $0.setPackEnabled(id, enabled: enabled, expectedRevision: expectedRevision) }
    }

    public func replacePack(_ id: String, with pack: ExternalPack, source: StoredExternalPack.Source,
                            expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(.replacePack) { $0.replacePack(id, with: pack, source: source, expectedRevision: expectedRevision) }
    }

    public func deletePack(_ id: String, expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(.deletePack) { $0.deletePack(id, expectedRevision: expectedRevision) }
    }

    public func reorder(_ order: [SnippetSourceSlot], expectedRevision: Int? = nil) async -> PackChangeOutcome {
        await commit(.reorderPacks) { $0.reorder(order, expectedRevision: expectedRevision) }
    }

    // MARK: - 메인 밖에서

    private func commit(_ operation: PackChangeNotice.Operation,
                        _ change: @escaping @Sendable (PackStore) -> PackStore.CommitResult) async -> PackChangeOutcome {
        await run { store in
            let result = change(store)
            // 거부는 저장본을 바꾸지 않는다 — 거부 뒤에 읽은 한도 상태가 곧 「저장 전」 상태다(A3·D2)
            let notice = PackChangeNotice(operation, result: result,
                                          userSnippetsOverLimit: { !store.evaluation().baselineOverflow.isEmpty },
                                          packName: { store.packName($0) })
            return PackChangeOutcome(result: result, notice: notice)
        }
    }

    /// 일을 GCD 큐에서 돌리고 결과를 돌려준다 — 부른 쪽(메인)은 기다리는 동안 멈추지 않는다. `PackStore`가 `queue.sync`로 막는 일을
    /// Swift 협력 스레드 풀에서 하지 않으려고 **큐로 넘긴다**(풀을 블로킹으로 묶지 않는다 — `nonisolated async`가 어느 실행기에서 도는지는
    /// 언어 모드(`NonisolatedNonsendingByDefault`)에 따라 갈리므로 그것에 기대지 않는다)
    func run<Value: Sendable>(_ work: @escaping @Sendable (PackStore) -> Value) async -> Value {
        let store = self.store
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work(store)) }
        }
    }
}

/// 쓰기 결과 + 보일 알림
public struct PackChangeOutcome: Equatable, Sendable {
    public var result: PackStore.CommitResult
    /// 거부면 **언제나** 있다. 받았으면 팩이 쉬게 됐을 때만(G1·G2)
    public var notice: PackChangeNotice?

    public init(result: PackStore.CommitResult, notice: PackChangeNotice?) {
        self.result = result
        self.notice = notice
    }

    public var isAccepted: Bool { result.isAccepted }
}
