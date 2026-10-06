import SwiftUI
import PackImport
import TadakDomain

// 외부 채움글 1-c 3단계 — 채움글 화면 「외부 채움글」 절·팩 상세·삭제 확인·순서 화면
// (계획서 `external-snippet-packs-1c-plan.md` 3-1절·5절 3행, 시안 `docs/design/external-snippet-packs/index.html` 2-B~2-G·U1,
// PDR `external-snippet-packs.md` E표 U1·U4·U5, 9-1, 10-3·10-4, AC-6·AC-24).
//
// 쓰기·판정은 전부 `PackStoreClient`(메인 밖, 1-c G8) → `PackStore` 한 길이다 — 켬/끔 스위치도 내장 팩 스위치와 같은 커밋 게이트를 탄다(AC-6).
// 문구는 전부 `PackNoticeCopy`(U6·금칙어·한도 숫자 검사가 `swift test`로 돈다). 팩 이름·단축어·권리 표기는 사용자 입력이다 —
// **화면에 표시만** 하고 로그·분석 이벤트로 내보내지 않는다(보안 규칙). 「외부 채움글 추가」 줄은 가져오기 입구(4단계, `PackImportViews.swift`)로 간다.

// MARK: - 채움글 화면의 절 (2-B · 2-C)

/// 「외부 채움글」 절 — 내장 팩 바로 아래(U5). 팩이 없으면 추가 줄과 설명만(2-B), 있으면 순서 목록(「내 채움글 (순서)」 줄 포함, U1) ·
/// 팩 순서 바꾸기 · 추가 줄(2-C). 목록 순서가 곧 우선순위다
struct ExternalSnippetSection: View {
    let summaries: [PackSummary]
    let order: [SnippetSourceSlot]
    /// 목록 상태 — 읽히지 않으면 빈 상태 대신 손상 한 줄(O-2)
    var libraryStatus: PackLibraryStatus = .readable
    /// 방금 가져온·바꾼 팩 — 잠깐 주황 바탕(U5·U2, 시안 U2 컷 「방금 가져옴」 강조). 채움글 화면이 잠시 뒤 nil로 돌린다
    var highlightedPackID: String?
    let onReorder: () -> Void
    /// 「외부 채움글 추가」 — 채움글 화면이 가져오기 첫 화면(3-A)을 밀어 넣는다(완료하면 같은 화면이 걷어 목록으로 돌아온다)
    let onAdd: () -> Void
    /// 팩 상세에서 켬/끔·삭제를 했다 — 채움글 화면이 저장본을 다시 읽는다
    let onChange: @MainActor () -> Void

    var body: some View {
        Section {
            if !summaries.isEmpty {
                ForEach(rows, id: \.self) { slot in
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
                Button(PackChangeNotice.Action.reorderPacks.label, action: onReorder)
            }
            // 가져오기(4·5단계) — 3-A 첫 화면. 끝나면 새 팩이 목록 맨 아래에 강조된다
            Button(action: onAdd) {
                Label(PackNoticeCopy.addPack, systemImage: "plus")
            }
        } header: {
            Text(PackNoticeCopy.externalSectionTitle)
        } footer: {
            Text(PackNoticeCopy.externalSectionFooter(isEmpty: summaries.isEmpty, libraryStatus: libraryStatus))
        }
    }

    /// 순서 목록 그대로 — 목록에 없는 팩이 있으면(있을 수 없지만) 끝에 붙여 사라지지 않게
    private var rows: [SnippetSourceSlot] {
        let listed = Set(order.compactMap(\.packID))
        return order + summaries.filter { !listed.contains($0.id) }.map { .pack($0.id) }
    }

    /// 「내 채움글 (순서)」 — 눌리지 않는 줄(chevron 없음). 순서는 「팩 순서 바꾸기」에서만, 문구는 아래 「내 채움글」 절에서 고친다
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
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
    @State private var showsOrder = false
    /// 순서 화면이 닫힌 뒤 띄울 알림
    @State private var pendingNotice: PackChangeNotice?
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
        .sheet(isPresented: $showsOrder, onDismiss: afterOrder) {
            PackOrderView { pendingNotice = $0 }
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
            if !standing.patterns.isEmpty {
                Section {
                    ForEach(standing.patterns, id: \.pattern) { item in
                        standingRow(title: item.display, monospaced: true,
                                    line: PackNoticeCopy.patternLine(item.status, name: detail.name(of:)),
                                    badge: PackNoticeCopy.patternBadge(item.status), tint: tint(item.status))
                    }
                } header: {
                    Text(PackNoticeCopy.templatesHeader)
                } footer: {
                    Text(PackNoticeCopy.templatesFooter)
                }
            }
            if !standing.hiddenTriggers.isEmpty {
                Section {
                    ForEach(standing.hiddenTriggers, id: \.trigger) { item in
                        standingRow(title: item.trigger, monospaced: false,
                                    line: PackNoticeCopy.hiddenTriggerLine(owner: item.owner, name: detail.name(of:)),
                                    badge: PackNoticeCopy.hiddenTriggerBadge, tint: .gray)
                    }
                    Button(PackChangeNotice.Action.reorderPacks.label) { showsOrder = true }
                } header: {
                    Text(PackNoticeCopy.hiddenTriggersHeader(count: standing.hiddenTriggers.count))
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
                        Text(PackNoticeCopy.usageResult(example.title))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
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
    /// 돌아가고 사유별로 알린다(C1 「팩 순서 바꾸기」 · C2 · C2b 「정리하기」 · E2 「지우기」). 저장하는 동안 다시 누르면 무시한다
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

    /// 알림 버튼 — 팩 순서 바꾸기(C1) · 지우기(E2 — 2-F 확인을 한 번 더 받는다) · 정리하기(C2b) · 목록 복구(E1)
    private func perform(_ action: PackChangeNotice.Action) {
        switch action {
        case .reorderPacks: showsOrder = true
        case .deletePack: showsDeleteConfirmation = true
        case .organize: showsCleanup = true
        case .recoverLibrary: showsRecovery = true
        default: break
        }
    }

    private func afterOrder() {
        if let pending = pendingNotice {
            pendingNotice = nil
            notice = pending
        }
        Task {
            await reload()
            onChange()
        }
    }
}

// MARK: - 순서 화면 (2-D · 2-G)

/// 팩 순서 바꾸기(U4) — 끌어서 바꾸고, 「내 채움글」 줄도 끈다(U1). 완료 전에 바꾸면 무엇이 달라지는지(G3 `PackImpact`)를 주황 줄로 보인다 —
/// 쉬게 될 팩(㉤) · 틀 주인(10-4 ③) · 단축어 주인(2-G). **완료는 막지 않는다**(한도 감소 방향이라 거부가 없다, 9-1).
/// 삭제는 이 화면에 두지 않는다 — 팩 상세 한 길(2-F 확인)
struct PackOrderView: View {
    /// 닫힌 뒤 부모가 띄울 알림 — 거부, 또는 그 사이 저장본이 바뀌어 사전 안내와 결과가 다를 때만(코디네이터 결정 ⓑ)
    let onFinish: @MainActor (PackChangeNotice?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var library: PackImpact.Library?
    @State private var slots: [SnippetSourceSlot] = []
    @State private var lines: [PackNoticeCopy.ImpactLine] = []
    /// 지금 보이는 안내의 「쉬게 될 팩」 — 완료 뒤 결과와 견준다
    @State private var previewedResting: [String] = []
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            List {
                if let library {
                    Section {
                        ForEach(slots, id: \.self) { slot in
                            row(slot, in: library)
                        }
                        .onMove { source, destination in
                            slots.move(fromOffsets: source, toOffset: destination)
                            recompute()
                        }
                    } footer: {
                        Text(PackNoticeCopy.orderFooter)
                    }
                    if !lines.isEmpty {
                        Section {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                ImpactLineRow(line: line)
                            }
                        }
                        .listRowBackground(Color.orange.opacity(0.12))
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .overlay {
                // 변환본을 열어 단축어·틀을 읽는 동안(메인 밖)
                if library == nil { ProgressView() }
            }
            .settingsFormWidth()
            .navigationTitle(PackNoticeCopy.orderTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(PackNoticeCopy.cancel) { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(PackNoticeCopy.orderDone, action: finish)
                        .disabled(library == nil || isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { await load() }
        }
    }

    @ViewBuilder
    private func row(_ slot: SnippetSourceSlot, in library: PackImpact.Library) -> some View {
        switch slot {
        case .userSnippets:
            HStack(spacing: 12) {
                Image(systemName: "person.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(PackNoticeCopy.orderUserTitle)
                    Text(PackNoticeCopy.orderUserDetail(count: library.userSnippetCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        case .pack(let id):
            VStack(alignment: .leading, spacing: 3) {
                Text(library.name(of: id))
                if let summary = library.pack(id)?.summary, let detail = PackNoticeCopy.orderPackDetail(summary) {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func load() async {
        guard let loaded = await PackStoreClient.live.impactLibrary() else {
            // 목록을 읽을 수 없다(E1) — 닫고 부모가 「목록 복구」 알림을 띄운다
            onFinish(PackChangeNotice(.reorderPacks, result: .rejected(.libraryUnreadable, rechecked: false),
                                      userSnippetsOverLimit: { false }, packName: { _ in nil }))
            dismiss()
            return
        }
        library = loaded
        slots = loaded.order
        recompute()
    }

    /// 사전 영향(G3) — 순수 계산이라 끌 때마다 다시 한다(변환본은 열 때 한 번만 읽었다)
    private func recompute() {
        guard let library else { return }
        let impact = PackImpact.of(PackImpact.Proposal(order: slots), in: library)
        previewedResting = impact.restingPacks
        lines = PackNoticeCopy.impactLines(impact, in: library)
    }

    /// 바뀐 것이 없으면 저장하지 않는다. 저장은 메인 밖(`PackStoreClient`), 연 때의 revision을 넘겨 그 사이 바뀌었는지 안다(AC-3)
    private func finish() {
        guard let library, slots != library.order else {
            dismiss()
            return
        }
        isSaving = true
        let order = slots
        let previewed = previewedResting
        Task {
            let outcome = await PackStoreClient.live.reorder(order, expectedRevision: library.revision)
            onFinish(outcome.noticeAfterReorder(previewed: previewed))
            isSaving = false
            dismiss()
        }
    }
}

/// 완료 전 안내 한 줄 — 경고 아이콘 + 본문 + 작은 둘째 줄(시안 2-D·2-G 주황 칸)
private struct ImpactLineRow: View {
    let line: PackNoticeCopy.ImpactLine

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(line.message)
                    .font(.subheadline)
                if let detail = line.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
