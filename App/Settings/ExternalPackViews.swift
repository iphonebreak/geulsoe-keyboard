import SwiftUI
import PackImport
import TadakDomain

// 외부 채움글 1-c 3단계 — 채움글 화면 「외부 채움글」 절·팩 상세·삭제 확인
// (계획서 `external-snippet-packs-1c-plan.md` 3-1절·5절 3행, 시안 `docs/design/external-snippet-packs/index.html` 2-B·2-C·2-E·2-F·U1,
// PDR `external-snippet-packs.md` E표 U1·U4·U5, R30, 9-1, 10-3·10-4, AC-6·AC-24).
//
// 순서(우선순위)는 **목록 그 자리에서 길게 눌러 끌어** 바꾼다(R30) — 순서 시트(2-D·2-G)와 사전 안내(G3)는 없앴다. 끄는 규칙·저장은
// `PackListReorder`(패키지 — 시험이 닿는다), 놓은 순서를 보이고 저장하는 것은 채움글 화면(`SnippetSettingsView.reorderPacks`)이다.
//
// 쓰기·판정은 전부 `PackStoreClient`(메인 밖, 1-c G8) → `PackStore` 한 길이다 — 켬/끔 스위치도 내장 팩 스위치와 같은 커밋 게이트를 탄다(AC-6).
// 문구는 전부 `PackNoticeCopy`(U6·금칙어·한도 숫자 검사가 `swift test`로 돈다). 팩 이름·단축어·권리 표기는 사용자 입력이다 —
// **화면에 표시만** 하고 로그·분석 이벤트로 내보내지 않는다(보안 규칙). 「외부 채움글 추가」 줄은 가져오기 입구(4단계, `PackImportViews.swift`)로 간다.

// MARK: - 채움글 화면의 절 (2-B · 2-C)

/// 「외부 채움글」 절 — 내장 팩 바로 아래(U5). 팩이 없으면 추가 줄과 설명만(2-B), 있으면 순서 목록(「내 채움글 (우선순위)」 줄 포함, U1) ·
/// 추가 줄(2-C). 목록 순서가 곧 우선순위이고, **줄을 길게 눌러 끌어** 바꾼다(R30 — `onMove`는 편집 모드 밖에서 길게 눌러 끌기를 켠다).
/// 팩 줄을 짧게 누르면 상세로 간다(끌기는 길게 누를 때만이라 겹치지 않는다)
struct ExternalSnippetSection: View {
    let summaries: [PackSummary]
    let order: [SnippetSourceSlot]
    /// 목록 상태 — 읽히지 않으면 빈 상태 대신 손상 한 줄(O-2)
    var libraryStatus: PackLibraryStatus = .readable
    /// 방금 가져온·바꾼 팩 — 잠깐 주황 바탕(U5·U2, 시안 U2 컷 「방금 가져옴」 강조). 채움글 화면이 잠시 뒤 nil로 돌린다
    var highlightedPackID: String?
    /// 끌어 놓았다 — (끌기 전 순서, 놓은 순서). 채움글 화면이 놓은 순서를 바로 보이고 저장한다(R30). nil이면 끌 수 없다(앞 저장을 기다리는 중)
    let onReorder: (@MainActor (_ original: [SnippetSourceSlot], _ proposed: [SnippetSourceSlot]) -> Void)?
    /// 「외부 채움글 추가」 — 채움글 화면이 가져오기 첫 화면(3-A)을 밀어 넣는다(완료하면 같은 화면이 걷어 목록으로 돌아온다)
    let onAdd: () -> Void
    /// 팩 상세에서 켬/끔·삭제를 했다 — 채움글 화면이 저장본을 다시 읽는다
    let onChange: @MainActor () -> Void

    /// 「채움글 사용」을 끄면 채움글 화면이 이 절에 `.disabled`를 건다
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Section {
            if !summaries.isEmpty {
                let slots = rows
                ForEach(Array(slots.enumerated()), id: \.element) { index, slot in
                    row(slot)
                        // VoiceOver — 길게 눌러 끌기 대신 한 칸씩 옮기는 동작(놓는 것과 같은 길로 저장한다)
                        .accessibilityActions { moveActions(at: index, in: slots) }
                }
                .onMove(perform: moveAction(slots))
            }
            // 가져오기(4·5단계) — 3-A 첫 화면. 끝나면 새 팩이 목록 맨 아래에 강조된다.
            // 색을 직접 준다 — `Label` 버튼은 꺼져도 글자가 검정·아이콘이 파랑으로 남아 켜진 줄처럼 보였다(화면 확인 N-4, S-2 잔여).
            // 「채움글 추가」 등 옆 줄처럼 꺼지면 흐리게
            Button(action: onAdd) {
                Label(PackNoticeCopy.addPack, systemImage: "plus")
                    .foregroundStyle(isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
        } header: {
            Text(PackNoticeCopy.externalSectionTitle)
        } footer: {
            // 팩이 있으면 풋터가 없다(2-C 「위에 있는 줄이 먼저 떠요 …」를 뺐다, 사장님 실기 2026-10-07)
            if let footer = PackNoticeCopy.externalSectionFooter(isEmpty: summaries.isEmpty, libraryStatus: libraryStatus) {
                Text(footer)
            }
        }
    }

    /// 순서 목록 그대로 — 목록에 없는 팩이 있으면(있을 수 없지만) 끝에 붙여 사라지지 않게. 요약이 없는 팩 줄(목록과 요약을 읽는 사이에
    /// 지워짐)은 그리지 않는다 — 그린 줄과 끌기 자리가 어긋나지 않게. 그 상태로 끌면 저장소가 「그 사이 바뀜」으로 거부하고 다시 읽는다
    private var rows: [SnippetSourceSlot] {
        let known = Set(summaries.map(\.id))
        let listed = Set(order.compactMap(\.packID))
        return order.filter { $0.packID.map(known.contains) ?? true } + summaries.filter { !listed.contains($0.id) }.map { .pack($0.id) }
    }

    @ViewBuilder
    private func row(_ slot: SnippetSourceSlot) -> some View {
        switch slot {
        case .userSnippets:
            userSlotRow
        case .pack(let id):
            if let summary = summaries.first(where: { $0.id == id }) {
                NavigationLink {
                    ExternalPackDetailView(packID: id, onChange: onChange)
                } label: {
                    packRow(summary)
                }
                .listRowBackground(summary.id == highlightedPackID ? Color.orange.opacity(0.18) : nil)
            }
        }
    }

    /// 끌어 놓기 — 놓은 순서를 `PackListReorder.moving`(SwiftUI `move(fromOffsets:toOffset:)`와 같은 뜻)으로 만들어 채움글 화면에 넘긴다.
    /// 「채움글 사용」을 껐거나(절이 흐림) 앞 저장을 기다리는 중이면 nil — 끌리지 않는다
    private func moveAction(_ slots: [SnippetSourceSlot]) -> ((IndexSet, Int) -> Void)? {
        guard isEnabled, let onReorder else { return nil }
        return { source, destination in
            onReorder(slots, PackListReorder.moving(slots, from: source, to: destination))
        }
    }

    /// VoiceOver 동작 — 한 칸 위·아래(놓은 자리는 옮기기 전 기준이라 아래는 +2). 끝 줄에는 그쪽 동작이 없다
    @ViewBuilder
    private func moveActions(at index: Int, in slots: [SnippetSourceSlot]) -> some View {
        if let move = moveAction(slots) {
            if index > 0 {
                Button(PackNoticeCopy.moveUpAction) { move(IndexSet(integer: index), index - 1) }
            }
            if index < slots.count - 1 {
                Button(PackNoticeCopy.moveDownAction) { move(IndexSet(integer: index), index + 2) }
            }
        }
    }

    /// 「내 채움글 (우선순위)」 — 눌리지 않는 줄(chevron 없음), 길게 눌러 끌면 다른 줄처럼 옮겨진다(R30). 문구는 아래 「내 채움글」 절에서 고친다.
    /// 끌기 손잡이 모양(`line.3.horizontal`)은 두지 않는다 — 다른 줄도 손잡이 없이 길게 눌러 끈다
    private var userSlotRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(PackNoticeCopy.userSlotTitle)
                Text(PackNoticeCopy.userSlotDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
        }
        .accessibilityElement(children: .combine)
    }

    /// 행 = 이름 + (종류 · 항목 수 · 대표 틀) + 켬/끔, 쉬는 중·읽을 수 없음이면 그 이유 한 줄(4-3절)
    private func packRow(_ summary: PackSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.name ?? PackNoticeCopy.unnamedPack)
                if let detail = PackNoticeCopy.packRowDetail(summary) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let status = PackNoticeCopy.statusLine(summary.status) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(summary.isEnabled ? PackNoticeCopy.enabledValue : PackNoticeCopy.disabledValue)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 팩 상세 (2-E · U1) + 삭제 확인 (2-F)

/// 외부 팩 상세 — 내장 팩 상세와 같은 뼈대(사용 스위치 · 정보 · 사용법)에 권리 표기·틀 상태(사용 중/뒤 순서/가려짐, 10-4 ③)·
/// 「지금 안 뜨는 단축어」(U1)·삭제를 더했다. 「새 파일로 바꾸기」는 없다(U3 — 교체는 가져오기 한 길)
struct ExternalPackDetailView: View {
    let packID: String
    let onChange: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var detail: PackDetail?
    /// 켜기·끄기를 저장하는 동안 스위치가 보일 값 — 내장 팩 스위치(`builtInPackBinding`)와 같은 모양
    @State private var pendingEnabled: Bool?
    @State private var notice: PackChangeNotice?
    @State private var showsDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var showsCleanup = false
    @State private var showsRecovery = false

    var body: some View {
        Form {
            if let detail {
                content(detail)
            }
        }
        .settingsFormWidth()
        .navigationTitle(detail.map(name) ?? "")
        .navigationBarTitleDisplayMode(.inline)
        // 정리 화면 등에서 돌아올 때도 다시 읽는다(채움글 화면과 같은 방식) — 내 채움글을 줄이면 쉬던 팩이 다시 포함될 수 있다
        .onAppear { Task { await reload() } }
        .packChangeNoticeAlert($notice, onAction: perform)
        .alert(PackNoticeCopy.deleteTitle(name: detail.map(name) ?? PackNoticeCopy.unnamedPack),
               isPresented: $showsDeleteConfirmation) {
            Button(PackNoticeCopy.cancel, role: .cancel) {}
            Button(PackChangeNotice.Action.deletePack.label, role: .destructive, action: delete)
        } message: {
            Text(PackNoticeCopy.deleteMessage(itemCount: detail?.summary.itemCount ?? 0))
        }
        .navigationDestination(isPresented: $showsCleanup) { SnippetCleanupView() }
        .packLibraryRecovery(isPresented: $showsRecovery) {
            Task { await reload() }
        }
    }

    @ViewBuilder
    private func content(_ detail: PackDetail) -> some View {
        if detail.summary.status == .unavailable {
            Section {
                SnippetNoticeBanner(message: PackNoticeCopy.unavailablePackDetail)
            }
        }

        Section {
            Toggle(PackNoticeCopy.useToggle, isOn: enabledBinding(detail))
        } footer: {
            // 쉬는 이유(4-3절) — 읽을 수 없는 팩은 위 안내가 말한다
            if detail.summary.status != .unavailable, let status = PackNoticeCopy.statusLine(detail.summary.status) {
                Text(status)
            }
        }

        if PackNoticeCopy.packKind(detail.summary) != nil || detail.license != nil {
            Section {
                if let kind = PackNoticeCopy.packKind(detail.summary) {
                    LabeledContent(PackNoticeCopy.kindLabel, value: kind)
                }
                if let license = detail.license {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PackNoticeCopy.licenseLabel)
                        Text(license)
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text(PackNoticeCopy.infoHeader)
            } footer: {
                if detail.license != nil { Text(PackNoticeCopy.infoFooter) }
            }
        }

        if let standing = detail.standing {
            // 꺼진·쉬는 팩은 「켜면(다시 뜨면)」으로 계산한 자리다 — 그 전제를 머리·배지에 보인다(검증 F-5)
            let premise = PackNoticeCopy.standingPremise(detail.summary.status)
            if !standing.patterns.isEmpty {
                Section {
                    ForEach(standing.patterns, id: \.pattern) { item in
                        standingRow(title: item.display, monospaced: true,
                                    line: PackNoticeCopy.patternLine(item.status, premise: premise, name: detail.name(of:)),
                                    badge: PackNoticeCopy.patternBadge(item.status, premise: premise), tint: tint(item.status))
                    }
                } header: {
                    Text(PackNoticeCopy.templatesHeader(premise))
                } footer: {
                    Text(PackNoticeCopy.templatesFooter + "\n" + PackNoticeCopy.templatesEditHint)
                }
            }
            if !standing.hiddenTriggers.isEmpty {
                Section {
                    ForEach(standing.hiddenTriggers, id: \.trigger) { item in
                        standingRow(title: item.trigger, monospaced: false,
                                    line: PackNoticeCopy.hiddenTriggerLine(owner: item.owner, name: detail.name(of:)),
                                    badge: PackNoticeCopy.hiddenTriggerBadge, tint: .gray)
                    }
                } header: {
                    Text(PackNoticeCopy.hiddenTriggersHeader(count: standing.hiddenTriggers.count, premise: premise))
                } footer: {
                    Text(PackNoticeCopy.hiddenTriggersFooter(owners: standing.hiddenTriggers.map(\.owner), name: detail.name(of:)))
                }
            }
        }

        if !detail.examples.isEmpty {
            Section {
                ForEach(Array(detail.examples.enumerated()), id: \.offset) { _, example in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(example.trigger)
                            .font(.body.monospacedDigit())
                        Text(PackNoticeCopy.usageResult(body: example.body))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityElement(children: .combine)
                }
                // R31 — 예시 아래 「전체 보기 (n개)」 → 그 팩의 모든 항목·검색. 읽을 수 없는 팩은 예시가 없어 이 절이 없다(전체 보기도 없다)
                NavigationLink {
                    PackEntryListView(packID: packID, name: name(detail), status: detail.summary.status)
                } label: {
                    Text(PackNoticeCopy.allEntriesRow(count: detail.summary.itemCount))
                }
            } header: {
                Text(PackNoticeCopy.usageHeader)
            } footer: {
                Text(PackNoticeCopy.usageFooter)
            }
        }

        Section {
            Button(PackNoticeCopy.deletePackButton, role: .destructive) { showsDeleteConfirmation = true }
                .disabled(isDeleting)
        }
    }

    /// 틀·단축어 한 행 — 제목 + 설명 줄 + 오른쪽 배지(사용 중 파랑 · 뒤 순서 회색 · 가려짐 주황)
    private func standingRow(title: String, monospaced: Bool, line: String, badge: String, tint: Color) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(monospaced ? .body.monospaced() : .body)
                Text(line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(badge)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.14), in: Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    private func tint(_ status: PackStanding.PatternStatus) -> Color {
        switch status {
        case .owned: .blue
        case .outranked: .gray
        case .shadowed: .orange
        }
    }

    private func name(_ detail: PackDetail) -> String { detail.summary.name ?? PackNoticeCopy.unnamedPack }

    /// 켬/끔 — 내장 팩 스위치와 같은 길(`PackStoreClient` → `PackStore` 커밋 게이트, AC-6). 받으면 다시 읽고, 거부되면 스위치는 제자리로
    /// 돌아가고 사유별로 알린다(C1 · C2 · C2b 「정리하기」 · E2 「지우기」 — C1의 순서 바꾸기는 목록 끌기라 버튼이 없다, R30). 저장하는 동안 다시 누르면 무시한다
    private func enabledBinding(_ detail: PackDetail) -> Binding<Bool> {
        Binding(
            get: { pendingEnabled ?? detail.summary.isEnabled },
            set: { enabled in
                guard pendingEnabled == nil else { return }
                pendingEnabled = enabled
                Task {
                    let outcome = await PackStoreClient.live.setPackEnabled(packID, enabled: enabled)
                    if outcome.isAccepted {
                        await reload()
                        onChange()
                    }
                    pendingEnabled = nil
                    if let shown = outcome.notice { notice = shown }
                }
            }
        )
    }

    private func reload() async {
        detail = await PackStoreClient.live.packDetail(packID)
    }

    /// 2-F 「지우기」 — 받으면 목록으로 돌아간다. 거부(목록 손상·그 사이 지워짐·쓰기 실패)는 알린다
    private func delete() {
        isDeleting = true
        Task {
            let outcome = await PackStoreClient.live.deletePack(packID)
            isDeleting = false
            if outcome.isAccepted {
                onChange()
                dismiss()
            } else if let shown = outcome.notice {
                notice = shown
            }
        }
    }

    /// 알림 버튼 — 지우기(E2 — 2-F 확인을 한 번 더 받는다) · 정리하기(C2b) · 목록 복구(E1)
    private func perform(_ action: PackChangeNotice.Action) {
        switch action {
        case .deletePack: showsDeleteConfirmation = true
        case .organize: showsCleanup = true
        case .recoverLibrary: showsRecovery = true
        default: break
        }
    }
}

// MARK: - 전체 보기 (R31)

/// 팩 상세 「전체 보기」(PDR R31) — 그 팩의 **모든 항목**을 「단축어 → 들어가는 문구」로(사용법 줄과 같은 모양), 검색(띄어쓰기·대소문자 무시).
/// 수천 개여도 매끄럽게 — 줄은 `List`가 보이는 만큼만 그리고, 줄·검색 키 만들기(`PackStoreClient.packEntries`)와 거르기는 메인 밖에서 한다.
/// 꺼진·쉬는 팩도 볼 수 있다(머리에 그 상태 한 줄). 단축어·본문은 사용자 입력이다 — 화면에 표시만 하고 로그로 내보내지 않는다(보안 규칙)
struct PackEntryListView: View {
    let packID: String
    let name: String
    let status: PackSummary.Status

    /// nil = 아직 읽는 중 · `.some(nil)` = 그 사이 읽을 수 없게 됨(지워짐 등)
    @State private var list: PackEntryList??
    @State private var query = ""
    /// 지금 보이는 줄 — 찾는 말로 거른 결과(메인 밖에서 거른 뒤 받는다)
    @State private var shown: [PackEntryList.Row] = []

    var body: some View {
        List {
            if let line = PackNoticeCopy.allEntriesStatusLine(status) {
                Section {
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            switch list {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity)
            case .some(nil):
                Text(PackNoticeCopy.unavailablePackDetail)
                    .foregroundStyle(.secondary)
            case .some(.some):
                Section {
                    ForEach(shown) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.trigger)
                                .font(.body.monospacedDigit())
                            Text(row.result)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if shown.isEmpty, PackEntryList.isSearching(query) {
                        Text(PackNoticeCopy.allEntriesNoMatch)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(PackNoticeCopy.allEntriesHeader(count: shown.count, isSearching: PackEntryList.isSearching(query)))
                }
            }
        }
        .listStyle(.insetGrouped)
        .settingsFormWidth()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: PackNoticeCopy.allEntriesSearchPrompt)
        .task {
            list = .some(await PackStoreClient.live.packEntries(packID))
            await refilter()
        }
        .task(id: query) { await refilter() }
    }

    /// 찾는 말로 거른다(메인 밖). 거르는 사이 찾는 말이 또 바뀌었으면 버린다 — 늦게 끝난 옛 결과가 새 결과를 덮지 않게
    private func refilter() async {
        guard case .some(.some(let list)) = list else { return }
        let current = query
        let found = await Task.detached(priority: .userInitiated) { list.rows(matching: current) }.value
        if current == query { shown = found }
    }
}
