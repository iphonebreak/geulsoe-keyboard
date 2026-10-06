import Foundation
import TadakDomain

/// 4-M 완료 화면 모델
public struct PackImportCompletion: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 켠 채로 목록 맨 아래(U2)
        case imported
        /// 「꺼 둔 채로 가져오기」(D1·D2) — 꺼진 채 맨 아래
        case importedDisabled
        /// 같은 이름 팩 바꾸기(U3) — 자리·켬/끔 유지
        case replaced
    }

    public var kind: Kind
    /// 목록에서 잠깐 강조할 행(U5)
    public var packID: String
    public var name: String
    public var itemCount: Int
    public var skippedCount: Int
    /// 키보드에 뜰 수 있는 상태인가 — 꺼진 채면 「켜면 써요」
    public var isEnabled: Bool
    /// 「이렇게 써 보세요」 — 팩 상세(2-E)와 같은 함수(`PackDetail.examples`), 폼에서 확정한 틀로 만든다
    public var examples: [PackDetail.Example]
    /// 받았지만 다른 팩이 쉬게 됐다(G1·G2) — 없으면 nil
    public var notice: PackChangeNotice?
}

/// 가져오기 확정 흐름(계획서 5절 5행 ③, PDR 9-1·9-2, AC-3, E표 U2·U3, 계획서 4-2절 D1~D3·G1·G2·8절 #5).
///
/// ```
/// editing ─confirm─┬─(같은 이름)─▶ askingSameName ─chooseReplace─▶ working(바꾸기)
///                  │                              ├─chooseSeparate─▶ editing(이름 칸으로)
///                  │                              └─cancelSameName─▶ editing
///                  └─▶ working(켠 채 가져오기)
/// working ─receive─┬─▶ completed(4-M)                     ─ 원본(초안)을 비운다
///                  ├─▶ rejected(알림 — D1·D2면 「꺼 둔 채로」) ─importDisabled─▶ working(꺼진 채 가져오기)
///                  │                                        └─dismissNotice─▶ editing
///                  └─▶ editing(최종 검사 실패 — 그 칸)
/// ```
///
/// - **미리보기 때 읽은 `revision`을 넘긴다** — 그 사이 저장본이 바뀌었으면 `PackStore`가 지금 저장본으로 다시 판정하고(`rechecked`)
///   거부 알림 첫 줄에 「그 사이 … 다시 확인했어요」가 붙는다(AC-3, `PackChangeNotice`).
/// - **최종 DTO는 폼 값**이다 — 확정할 때 `PackCompiler.compile`로 다시 만든다(9-2 ②). 성경 전체 n 검사도 여기서 다시 돈다.
/// - **「꺼 둔 채로 가져오기」는 그 버튼을 단 거부에서만**(D1·D2 — 예산) — 팩 수 초과(D3)에서는 꺼 둔 팩도 세므로 없다(8절 #5).
///   저장은 `importPack(enabled: false)` = 1-b 게이트 `importDisabledPack`(예산 대신 팩 수·`dropLast == current` 검사) 그대로다.
///
/// 초안·폼 값은 사용자 데이터다 — 메모리에만 있고 완료하면 비운다. 로그·분석 이벤트로 내보내지 않는다(보안 규칙).
public struct PackImportConfirmation: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case editing
        /// U3 — 「같은 이름의 팩이 있어요: 바꾸기 / 따로 추가 / 취소」
        case askingSameName(PackSummary)
        /// 메인 밖에서 컴파일·커밋 중
        case working
        /// 거부 알림(D1·D2·D3·C3·E1·F…)
        case rejected(PackChangeNotice)
        case completed(PackImportCompletion)
    }

    public enum Action: Equatable, Sendable {
        /// 새 팩 — 목록 맨 아래(U2). `enabled == false`면 꺼 둔 채로
        case importNew(enabled: Bool)
        /// 같은 이름 팩 교체(U3) — 자리·켬/끔 유지(9-1). `isEnabled`는 그 팩의 지금 켬/끔(완료 화면 문구용)
        case replace(packID: String, isEnabled: Bool)
    }

    /// 메인 밖에서 할 일 한 번 — `perform`에 넘긴다
    public struct Work: Equatable, Sendable {
        public let draft: PackDraft
        public let form: PackForm
        public let action: Action
        /// 미리보기 때 읽은 목록 revision(AC-3) — 목록을 못 읽었으면 nil
        public let expectedRevision: Int?
    }

    /// `perform` 결과 — `receive`로 돌려준다
    public enum Result: Equatable, Sendable {
        /// 최종 컴파일이 거부했다 — 저장하지 않았다
        case compileFailed(PackCompileFailure)
        /// 커밋했다(받았거나 거부됐다). `compiled`는 저장소에 넘긴 최종 DTO
        case committed(PackChangeOutcome, compiled: ExternalPack?)
    }

    public private(set) var phase: Phase = .editing
    /// 최종 검사에서 거부된 칸 — 폼이 그 칸에 보인다. 다시 확정하면 지운다
    public private(set) var formFailure: PackCompileFailure?
    /// 「따로 추가」 — 화면이 이름 칸에 커서를 둔 뒤 `nameFocused()`로 지운다
    public private(set) var focusesName = false

    private var draft: PackDraft?
    private var revision: Int?
    private var packs: [PackSummary]
    /// 지금(또는 마지막) 일 — 거부 뒤 「꺼 둔 채로」가 같은 폼 값을 쓴다
    private var lastWork: Work?
    /// 마지막 거부 알림이 「꺼 둔 채로 가져오기」를 줬다 — 알림이 닫힌 **뒤에** 그 버튼 동작이 와도 받는다(알림 버튼은 닫힘과 동작의 순서를
    /// 보장하지 않는다). 다시 확정하면 지운다
    private var offersDisabledImport = false

    /// - Parameter library: 미리보기 때 읽은 목록(`PackStore.impactLibrary`) — 같은 이름 판정과 `expectedRevision`이 이것을 쓴다
    public init(draft: PackDraft, library: PackImpact.Library?) {
        self.draft = draft
        revision = library?.revision
        packs = library?.packs.map(\.summary) ?? []
    }

    /// 초안을 들고 있나 — 완료하면 비운다(메모리에만, 끝나면 비움)
    public var hasDraft: Bool { draft != nil }

    /// 목록을 다시 읽었다(정리 화면에서 돌아옴 등) — 같은 이름·revision이 새 목록을 따른다
    public mutating func refresh(library: PackImpact.Library?) {
        revision = library?.revision
        packs = library?.packs.map(\.summary) ?? []
    }

    // MARK: - 확정

    /// 「가져오기」 — 폼이 완성됐을 때만. 같은 이름 팩이 있으면 먼저 묻는다(U3)
    public mutating func confirm(_ form: PackImportForm) -> Work? {
        guard phase == .editing, form.isComplete, let draft else { return nil }
        formFailure = nil
        focusesName = false
        offersDisabledImport = false
        if let existing = form.sameNamePack(in: packs) {
            lastWork = work(draft, form.packForm, .replace(packID: existing.id, isEnabled: existing.isEnabled))
            phase = .askingSameName(existing)
            return nil
        }
        return start(work(draft, form.packForm, .importNew(enabled: true)))
    }

    /// U3 「바꾸기」 — 그 팩 자리·켬/끔 그대로 내용만
    public mutating func chooseReplace() -> Work? {
        guard case .askingSameName = phase, let lastWork else { return nil }
        return start(lastWork)
    }

    /// U3 「따로 추가」 — 이름 칸으로 돌아가 다른 이름을 쓰게 한다(같은 이름 팩이 둘 생기지 않는다)
    public mutating func chooseSeparate() {
        guard case .askingSameName = phase else { return }
        phase = .editing
        focusesName = true
    }

    public mutating func cancelSameName() {
        guard case .askingSameName = phase else { return }
        phase = .editing
    }

    public mutating func nameFocused() { focusesName = false }

    /// 거부 알림의 「꺼 둔 채로 가져오기」(D1·D2) — 그 버튼이 있는 알림에서만. 알림이 막 닫혀 폼으로 돌아간 순간에도 받는다
    public mutating func importDisabled() -> Work? {
        switch phase {
        case .rejected, .editing: break
        default: return nil
        }
        guard offersDisabledImport, let lastWork, case .importNew = lastWork.action else { return nil }
        return start(work(lastWork.draft, lastWork.form, .importNew(enabled: false)))
    }

    /// 거부 알림을 닫았다 — 폼으로(같은 값으로 다시 확정할 수 있다)
    public mutating func dismissNotice() {
        guard case .rejected = phase else { return }
        phase = .editing
    }

    // MARK: - 결과 받기

    /// 메인 밖 결과 — 일하는 중이 아니면(늦게 온 결과) 버리고 거짓
    @discardableResult
    public mutating func receive(_ result: Result) -> Bool {
        guard phase == .working, let work = lastWork else { return false }
        switch result {
        case .compileFailed(let failure):
            formFailure = failure
            phase = .editing
        case .committed(let outcome, let compiled):
            switch outcome.result {
            case .accepted(let accepted):
                phase = .completed(completion(work: work, accepted: accepted, compiled: compiled, notice: outcome.notice))
                draft = nil
                self.lastWork = nil
            case .rejected:
                // 거부는 언제나 알림이 있다(`PackChangeNotice`) — 없으면 폼으로
                phase = outcome.notice.map(Phase.rejected) ?? .editing
                offersDisabledImport = outcome.notice?.actions.contains(.importDisabled) ?? false
            }
        }
        return true
    }

    // MARK: - 메인 밖에서 할 일

    /// 최종 컴파일(전역 큐 — 성경 전체 n) → `PackStoreClient`로 가져오기·바꾸기(메인 밖 직렬 큐). 소스는 CSV(붙여넣기도 같은 파서)
    public static func perform(_ work: Work, client: PackStoreClient,
                               queue: DispatchQueue = .global(qos: .userInitiated)) async -> Result {
        let compiled: Swift.Result<ExternalPack, PackCompileFailure> = await withCheckedContinuation { continuation in
            queue.async {
                do throws(PackCompileFailure) {
                    continuation.resume(returning: .success(try PackCompiler.compile(work.draft, form: work.form)))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
        let pack: ExternalPack
        switch compiled {
        case .failure(let failure): return .compileFailed(failure)
        case .success(let value): pack = value
        }
        let outcome = switch work.action {
        case .importNew(let enabled):
            await client.importPack(pack, source: .csv, enabled: enabled, expectedRevision: work.expectedRevision)
        case .replace(let id, _):
            await client.replacePack(id, with: pack, source: .csv, expectedRevision: work.expectedRevision)
        }
        return .committed(outcome, compiled: pack)
    }

    // MARK: - 안

    private func work(_ draft: PackDraft, _ form: PackForm, _ action: Action) -> Work {
        Work(draft: draft, form: form, action: action, expectedRevision: revision)
    }

    private mutating func start(_ work: Work) -> Work {
        lastWork = work
        offersDisabledImport = false
        phase = .working
        return work
    }

    private func completion(work: Work, accepted: PackStore.Accepted, compiled: ExternalPack?,
                            notice: PackChangeNotice?) -> PackImportCompletion {
        let kind: PackImportCompletion.Kind
        let packID: String
        let isEnabled: Bool
        switch work.action {
        case .importNew(let enabled):
            kind = enabled ? .imported : .importedDisabled
            packID = accepted.packID ?? ""
            isEnabled = enabled
        case .replace(let id, let enabled):
            kind = .replaced
            packID = id
            isEnabled = enabled
        }
        let itemCount = compiled.map { $0.template?.items.count ?? $0.entries.count }
            ?? (work.draft.mode == .numbered ? work.draft.items.count : work.draft.entries.count)
        return PackImportCompletion(kind: kind, packID: packID, name: compiled?.name ?? work.form.name, itemCount: itemCount,
                                    skippedCount: work.draft.skipped.count, isEnabled: isEnabled,
                                    examples: compiled.map { PackDetail.examples(of: $0) } ?? [], notice: notice)
    }
}
