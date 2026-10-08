import SwiftUI
import PackImport
import TadakDomain

/// 내 채움글 정리 — 한도를 넘은 옛 저장분(1-c 계획서 4-1 ㉠, PDR R25 「최소」, AC-5).
///
/// 키보드는 내 채움글을 **저장 순서대로 한도까지만** 싣고 외부 팩을 모두 쉬게 한다(9-3). 이 화면은 그 경계를 **「여기부터는 지금 안
/// 떠요」 머리줄**로 보이고, 기존과 같은 **한 항목씩** 지우기(밀어서)·고치기(눌러서)로 줄이게 한다 — 일괄 삭제는 두지 않는다(R25,
/// 「저장 1회 = 항목 1개」). 경계는 키보드와 같은 함수(`UserSnippetBudget` ← `ActivePackBudget.userSnippetUsage`)이고, 바꿀 때마다
/// 저장본에서 다시 판정한다. 한도 안으로 들어오는 순간 한 번 알린다(쉬던 팩은 판정 결과로 다시 포함된다 — 9-1).
struct SnippetCleanupView: View {

    @State private var budget: UserSnippetBudget?
    @State private var editingEntry: EditingSnippet?
    @State private var notice: PackChangeNotice?
    @State private var pendingNotice: PackChangeNotice?
    @State private var showsDone = false
    @State private var showsRecovery = false

    var body: some View {
        Form {
            if let budget {
                if budget.isOverLimit {
                    Section {
                        SnippetNoticeBanner(message: PackNoticeCopy.overLimitBanner(loadableCount: budget.loadableRowCount))
                    }
                }
                let loaded = Array(budget.entries.prefix(budget.loadableRowCount))
                let resting = Array(budget.entries.dropFirst(budget.loadableRowCount))
                Section {
                    rows(loaded, dimmed: false)
                        .onDelete { delete(loaded, at: $0) }
                } footer: {
                    if resting.isEmpty, budget.isOverLimit { Text(PackNoticeCopy.cleanupFooter) }
                }
                if !resting.isEmpty {
                    Section {
                        rows(resting, dimmed: true)
                            .onDelete { delete(resting, at: $0) }
                    } header: {
                        // ★ 경계 줄 — 이 머리줄 아래는 키보드에 지금 안 뜬다(키보드 로더와 같은 개수)
                        Text(PackNoticeCopy.cleanupBoundary)
                    } footer: {
                        Text(PackNoticeCopy.cleanupFooter)
                    }
                }
            }
        }
        .settingsFormWidth()
        .navigationTitle(PackNoticeCopy.cleanupTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload(announcingDone: false) }
        .packChangeNoticeAlert($notice, onAction: perform)
        .packLibraryRecovery(isPresented: $showsRecovery) { Task { await reload(announcingDone: false) } }
        .sheet(item: $editingEntry, onDismiss: showPending) { editing in
            SnippetEditorView(editing: editing.entry, onSave: save)
        }
        .alert(PackNoticeCopy.cleanupDoneTitle, isPresented: $showsDone) {
            Button(PackChangeNotice.Action.confirm.label, role: .cancel) {}
        } message: {
            Text(PackNoticeCopy.cleanupDoneMessage)
        }
    }

    /// 행 모양은 채움글 화면의 내 채움글 목록과 같다 — 눌러서 고치고 밀어서 지운다. 안 뜨는 쪽은 흐리게
    private func rows(_ entries: [SnippetEntry], dimmed: Bool) -> some DynamicViewContent {
        ForEach(entries, id: \.snippetListID) { entry in
            Button {
                editingEntry = EditingSnippet(entry: entry)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.title)
                            .foregroundStyle(dimmed ? .secondary : .primary)
                        Text("단축어: \(entry.triggers.joined(separator: ", "))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("고치기")
        }
    }

    /// 한도 안으로 들어온 순간을 알리려고 바꾸기 전 상태를 들고 다시 읽는다
    private func reload(announcingDone: Bool) async {
        let wasOver = budget?.isOverLimit ?? false
        let fresh = await PackStoreClient.live.userSnippetBudget()
        budget = fresh
        if announcingDone, wasOver, !fresh.isOverLimit { showsDone = true }
    }

    /// 한 항목씩 — 화면에서 먼저 빼고(기다리는 동안 행이 되살아나 보이지 않게) 메인 밖에서 지운 뒤 다시 판정한다
    private func delete(_ section: [SnippetEntry], at offsets: IndexSet) {
        let targets = offsets.map { section[$0] }
        let removed = Set(targets.map(\.snippetListID))
        if var current = budget {
            // 경계 위에서 지운 만큼 경계도 당긴다 — 다시 판정하기 전까지 아래 행이 위로 넘어가 보이지 않게
            let loaded = Set(current.entries.prefix(current.loadableRowCount).map(\.snippetListID))
            current.loadableRowCount -= removed.intersection(loaded).count
            current.entries.removeAll { removed.contains($0.snippetListID) }
            budget = current
        }
        Task {
            for entry in targets {
                if let shown = await PackStoreClient.live.deleteUserSnippet(entry).notice { notice = shown }
            }
            await reload(announcingDone: true)
        }
    }

    private func save(_ entry: SnippetEntry, editing original: SnippetEntry?) async -> PackChangeNotice? {
        let outcome = await PackStoreClient.live.saveUserSnippet(entry, editing: original)
        guard outcome.isAccepted else { return outcome.notice }
        pendingNotice = outcome.notice
        await reload(announcingDone: true)
        return nil
    }

    private func showPending() {
        guard let pending = pendingNotice else { return }
        pendingNotice = nil
        notice = pending
    }

    /// 알림 버튼 — 이미 정리 화면이라 「정리하기」는 할 일이 없다
    private func perform(_ action: PackChangeNotice.Action) {
        if action == .recoverLibrary { showsRecovery = true }
    }
}
