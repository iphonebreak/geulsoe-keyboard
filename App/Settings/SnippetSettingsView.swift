import SwiftUI
import PackImport
import TadakDomain

/// 채움글 설정 — 전체 on/off, 내장 팩 on/off, 내 채움글 관리(추가·고치기·삭제).
///
/// 내 채움글은 App Group에 앱이 쓰고 키보드가 읽는다 (단방향 — 권한 불필요).
/// **쓰기는 전부 `PackStore` 하나를 거친다**(외부 채움글 1-b, PDR `external-snippet-packs.md` 9-1·AC-2) — 예산 판정·snapshot·
/// 세대·알림이 그 안에 있고, 키보드는 세대가 바뀔 때만 매처를 다시 만든다(AC-9). 화면은 **메인 밖 래퍼** `PackStoreClient`로 부르고
/// (1-c G8 — `PackStore`는 `queue.sync`라 메인에서 부르면 저장 동안 화면이 멈춘다), 결과는 사유별 알림 `PackChangeNotice`로 보인다(1-c G7).
struct SnippetSettingsView: View {

    @Binding var settings: KeyboardSettings

    @State private var userSnippets: [SnippetEntry] = []
    @State private var showsEditor = false
    /// 고치는 중인 항목. nil이면 **추가**다 — 시트 하나가 두 모드를 다 맡는다.
    @State private var editingEntry: EditingSnippet?
    /// 알림 — 반영하지 못한 이유(사유별) 또는 저장은 됐지만 팩이 쉬게 됐다(이름 있는 G1·G2, AC-4). 문구는 `PackNoticeCopy`
    @State private var notice: PackChangeNotice?
    /// 편집 시트가 닫힌 뒤 띄울 알림 — 시트가 닫히는 중에 부모가 알림을 띄우지 않게 미뤄 둔다
    @State private var pendingNotice: PackChangeNotice?

    // 1-c 2단계 안전망 — 배너 셋(㉠ 한도 초과 · ㉡ 목록 손상 · ㉢ 읽을 수 없는 팩)의 상태. 화면에 올 때마다 메인 밖에서 다시 읽는다
    @State private var libraryStatus: PackLibraryStatus = .readable
    @State private var budget: UserSnippetBudget?
    @State private var unavailablePackNames: [String] = []
    @State private var showsCleanup = false
    @State private var showsRecovery = false

    // 1-c 3단계 — 「외부 채움글」 절(2-B·2-C)의 목록. 순서는 그 자리에서 길게 눌러 끌어 바꾼다(R30 — 순서 시트 2-D·2-G 없음)
    @State private var packSummaries: [PackSummary] = []
    @State private var packOrder: [SnippetSourceSlot] = SnippetSourceSlot.defaultOrder
    /// 목록을 읽을 때의 revision — 끌어 놓은 순서를 저장할 때 넘겨 그 사이 바뀌었는지 안다(AC-3)
    @State private var packRevision: Int?
    /// 끌어 놓은 순서를 저장하는 동안 — 또 끌지 못하게(저장은 한 번에 하나, 결과로 되돌릴 기준이 흔들리지 않게)
    @State private var isReorderingPacks = false

    // 1-c 5단계 — 가져오기 첫 화면(3-A)과 완료 뒤 새 팩 행 강조(U5)
    @State private var showsImport = false
    @State private var highlightedPackID: String?

    var body: some View {
        Form {
            safetyNetBanners

            // 안내 애니메이션 — 타이핑 → 칩 → 치환을 반복 재생 (PDR snippet-intro-animation).
            // 인셋 0·행 배경 투명: 확대된 캔버스가 행 가장자리까지 닿으므로 카드가 스스로 모서리를 그리고 클립한다
            Section {
                SnippetIntroAnimationView(
                    themeID: settings.selectedThemeID,
                    appearance: settings.appearance,
                    showsKeyPreview: settings.showsKeyPreview,
                    showsLongPressHints: settings.longPressSymbolsEnabled
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                Toggle("채움글 사용", isOn: $settings.snippetsEnabled)
            } footer: {
                Text("단축어를 치면 전문이 툴바 후보로 떠요. 예) \"창세기 1장 1절\", \"창 1:1\", \"애국가 1절\", \"새해인사\", \"헌법 전문\", \"오늘 날짜\"")
            }

            Section {
                ForEach(SnippetPackInfo.all, id: \.id) { pack in
                    NavigationLink {
                        SnippetPackDetailView(pack: pack, settings: $settings)
                    } label: {
                        LabeledContent(pack.name, value: settings.disabledSnippetPacks.contains(pack.id) ? "끔" : "켬")
                    }
                }
            } header: {
                Text("내장 팩")
            } footer: {
                Text("팩을 누르면 설명과 사용법, 켜기/끄기가 나와요.")
            }
            .disabled(!settings.snippetsEnabled)

            // 외부 채움글 — 내장 팩 바로 아래(U5). 순서 목록(길게 눌러 끌기, R30)·팩 상세는 `ExternalPackViews.swift`
            ExternalSnippetSection(summaries: packSummaries, order: packOrder, libraryStatus: libraryStatus,
                                   highlightedPackID: highlightedPackID,
                                   onReorder: packReorderAction, onAdd: { showsImport = true },
                                   onChange: { Task { await reloadSafetyNet() } })
                .disabled(!settings.snippetsEnabled)

            Section {
                // **id 는 정규화 단축어를 이어 붙인 것**이다. `\.trigger` 는 더 이상 없고,
                // 단축어가 여럿이라 하나만 쓰면 서로 다른 항목이 같은 id 를 가질 수 있다.
                ForEach(userSnippets, id: \.snippetListID) { entry in
                    // ★ **행을 눌러 고친다** (사장님 결정 2026-09-23).
                    //
                    // 전에는 추가와 삭제만 됐다 — 단축어 하나를 더하려면 **지우고 본문까지
                    // 다시 쳐야** 했고, 단축어를 여럿 둘 수 있게 되면서 더 아쉬워졌다.
                    //
                    // ★ `Button`이라 **스와이프 삭제와 부딪히지 않는다** — `.onDelete`는 행의
                    //   스와이프 제스처에 붙고 탭은 버튼이 먹는다. `.contentShape`로 빈 자리까지
                    //   누를 수 있게 한다(제목이 짧을 때 오른쪽 여백이 죽은 자리가 되지 않게).
                    Button {
                        editingEntry = EditingSnippet(entry: entry)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.title)
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
                .onDelete(perform: deleteSnippets)

                Button("채움글 추가") { showsEditor = true }
            } header: {
                Text("내 채움글")
            } footer: {
                Text("단축어를 치면 본문 전문이 후보로 떠요. 띄어쓰기는 달라도 돼요.\n겹치는 단축어가 있으면 그 문구를 바꿔요.")
            }
            .disabled(!settings.snippetsEnabled)
        }
        .settingsFormWidth()
        .navigationTitle("채움글")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await reloadSafetyNet() }
        }
        .packChangeNoticeAlert($notice, onAction: perform)
        .navigationDestination(isPresented: $showsCleanup) { SnippetCleanupView() }
        // 가져오기 — 3-A 위로 붙여넣기(3-E)를 밀어 넣었어도 이 값을 끄면 이 화면까지 함께 걷힌다
        .navigationDestination(isPresented: $showsImport) { PackImportStartView(onFinished: finishImport) }
        .packLibraryRecovery(isPresented: $showsRecovery) {
            Task { await reloadSafetyNet() }
        }
        .sheet(isPresented: $showsEditor, onDismiss: showPendingNotice) {
            SnippetEditorView(editing: nil, onSave: save)
        }
        // ★ **같은 시트를 고치기에도 쓴다** — 새로 만들지 않는다.
        //   `item:` 형태라 고를 때마다 시트가 그 항목으로 새로 만들어진다
        //   (`isPresented:`를 쓰면 `@State` 초기값이 첫 항목에 굳는다).
        .sheet(item: $editingEntry, onDismiss: showPendingNotice) { editing in
            SnippetEditorView(editing: editing.entry, onSave: save)
        }
    }

    /// 채움글 화면 맨 위 배너(1-c 4-1 ㉠㉡㉢, 문구 4-3절) — 문제가 없으면 아무것도 그리지 않는다
    @ViewBuilder private var safetyNetBanners: some View {
        if let banner = PackNoticeCopy.libraryBanner(libraryStatus) {
            Section {
                SnippetNoticeBanner(message: banner, actionTitle: PackChangeNotice.Action.recoverLibrary.label) { showsRecovery = true }
            }
        }
        if let budget, budget.isOverLimit {
            Section {
                SnippetNoticeBanner(message: PackNoticeCopy.overLimitBanner(loadableCount: budget.loadableRowCount),
                                    actionTitle: PackChangeNotice.Action.organize.label) { showsCleanup = true }
            }
        }
        if !unavailablePackNames.isEmpty {
            Section {
                SnippetNoticeBanner(message: PackNoticeCopy.unavailablePacksBanner(names: unavailablePackNames))
            }
        }
    }

    /// 화면 상태를 저장본에서 다시 읽는다 — 내 채움글 목록도 여기서(검증 F-5). 목록은 정리 모델의 화면 목록을 그대로 쓴다: 저장분
    /// UserDefaults 디코드가 **메인 밖** 한 번이고(한도를 넘은 큰 옛 저장분에서 가장 무겁다), 중복 제거 규칙도 정리 화면과 한 곳이다
    /// (`UserSnippetBudget.displayEntries` — 정규화 단축어가 같은 저장분은 첫 것만. 그래야 ForEach id가 겹치지 않는다)
    private func reloadSafetyNet() async {
        let client = PackStoreClient.live
        libraryStatus = await client.libraryStatus()
        let fresh = await client.userSnippetBudget()
        budget = fresh
        userSnippets = fresh.entries
        let summaries = await client.summaries()
        packSummaries = summaries
        packOrder = await client.order()
        packRevision = await client.revision()
        unavailablePackNames = summaries.filter { $0.status == .unavailable }.map { $0.name ?? PackNoticeCopy.unnamedPack }
    }

    /// 4-M 「채움글로 돌아가기」 뒤 — 가져오기 화면을 걷고 목록을 다시 읽어 새 팩 행을 잠깐 강조한다(U5 — 새 팩은 맨 아래, U2)
    private func finishImport(_ packID: String) {
        showsImport = false
        highlightedPackID = packID
        Task {
            await reloadSafetyNet()
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.6)) {
                if highlightedPackID == packID { highlightedPackID = nil }
            }
        }
    }

    /// 알림 버튼 — 정리하기는 정리 화면, 목록 복구는 확인 시트(2단계)
    private func perform(_ action: PackChangeNotice.Action) {
        switch action {
        case .organize: showsCleanup = true
        case .recoverLibrary: showsRecovery = true
        default: break
        }
    }

    /// 끌어 놓을 때 부를 것 — 앞 저장을 기다리는 동안은 nil(끌리지 않는다)
    private var packReorderAction: (@MainActor (_ original: [SnippetSourceSlot], _ proposed: [SnippetSourceSlot]) -> Void)? {
        guard !isReorderingPacks else { return nil }
        return { original, proposed in reorderPacks(from: original, to: proposed) }
    }

    /// 「외부 채움글」 목록에서 끌어 놓았다(R30) — 놓은 자리에 바로 보이고 **놓는 순간 저장**한다(`PackListReorder` → `PackStoreClient.reorder`,
    /// 메인 밖 직렬 경로·커밋 게이트 그대로). 거부되면 끌기 전 자리로 되돌리고 사유별로 알린다. 받았는데 팩이 쉬게 되면 G1·G2로 알린다 —
    /// 미리 알려 주는 단계(G3)는 없앴다. 되돌리려면 다시 끌면 된다
    private func reorderPacks(from original: [SnippetSourceSlot], to proposed: [SnippetSourceSlot]) {
        guard !isReorderingPacks, proposed != original else { return }
        packOrder = proposed
        isReorderingPacks = true
        Task {
            let settled = await PackListReorder.commit(proposed, from: original, expectedRevision: packRevision, client: .live)
            if settled.order != packOrder {
                withAnimation { packOrder = settled.order }
            }
            if settled.committed { await reloadSafetyNet() }   // 쉬는 중 표시·revision을 저장본에서 다시
            isReorderingPacks = false
            if let shown = settled.notice { notice = shown }
        }
    }

    /// 추가·고치기가 **같은 경로로** 저장한다.
    ///
    /// ## ★ 덮어쓰기는 이미 여기 있었다
    ///
    /// *정규화 단축어가 하나라도 겹치는 기존 항목을 교체한다* — 한쪽만 겹쳐도 둘 다 남겨 두면
    /// 어느 쪽이 발동할지 사용자가 알 수 없기 때문이다. **고치기가 그 규칙을 그대로 탄다** —
    /// 단축어를 그대로 두고 본문만 바꾸면 자기 자신이 교체되고, 단축어를 전부 갈면
    /// 새 항목이 된다(옛 것은 아래 `editing` 제거가 치운다).
    ///
    /// ★ 단축어 파싱은 **`SnippetEntry.parseTriggers` 한 곳**이다 — 새 파서를 쓰면
    /// 중복 제거·정규화 규칙이 갈린다.
    /// - Returns: 거부 알림 — **nil이 아니면 시트가 닫히지 않고 입력이 남는다**(검증 C6). 받았는데 쉬게 된 팩이 있으면
    ///   시트가 닫힌 뒤 팩 이름과 함께 알린다(AC-4, G1·G2)
    private func save(_ entry: SnippetEntry, editing original: SnippetEntry?) async -> PackChangeNotice? {
        // ★ 규칙은 `SnippetEntry.applying(_:editing:to:)`에 있다 — **여기 두면 테스트가 못 닿는다.**
        //   그래서 「고치면 자리가 맨 뒤로 튄다」를 아무도 못 잡았다(검증자 2026-09-23).
        //   추가는 맨 뒤, 편집은 **제자리**다. 겹쳐 지워진 항목만큼의 인덱스 보정도 거기 있다.
        // ★ 저장은 `PackStore` 한 길 — 한 번에 **한 항목**(1-b 계약). 판정·snapshot·키보드 알림이 그 안에 있다.
        let outcome = await PackStoreClient.live.saveUserSnippet(entry, editing: original)
        // 거부면 언제나 알림이 있다(`PackChangeNoticeTableTests`) — 시트가 그것을 띄우고 닫히지 않는다. 거부는 저장본을 바꾸지 않아 다시 읽지 않는다
        guard outcome.isAccepted else { return outcome.notice }
        pendingNotice = outcome.notice
        await reloadSafetyNet()
        return nil
    }

    private func showPendingNotice() {
        guard let pending = pendingNotice else { return }
        pendingNotice = nil
        notice = pending
    }

    /// 지울 때도 한 항목씩 — 여러 개를 고르면 하나씩 커밋한다(1-b 「저장 1회 = 항목 1개」)
    private func deleteSnippets(at offsets: IndexSet) {
        let targets = offsets.map { userSnippets[$0] }
        // 화면에서 먼저 뺀다 — 저장은 메인 밖이라 기다리는 동안 지운 행이 되살아나 보이지 않게. 거부되면(드묾) 아래 다시 읽기가 되돌린다
        userSnippets.remove(atOffsets: offsets)
        Task {
            // 지우기는 화면과 같은 기준(정규화 단축어)으로 겹치는 저장분까지 지운다(`PackStore.deleteUserSnippet`, 검증 F7)
            for entry in targets {
                if let shown = await PackStoreClient.live.deleteUserSnippet(entry).notice { notice = shown }
            }
            await reloadSafetyNet()
        }
    }
}

/// 내장 팩 켜기·끄기 — 목록과 팩 상세가 **이 하나**를 쓴다(외부 채움글 AC-6). 판정·snapshot은 `PackStore`가 메인 밖에서 하고
/// (`PackStoreClient`, 1-c G8), 받으면 설정에 반영한다(설정 저장 지점은 `RootView` 하나 — 여기서 저장하지 않는다. **판정 뒤에** 바꾼다 —
/// 먼저 바꾸면 키보드가 판정 전 설정을 읽는다). 거부되면 스위치는 제자리로 돌아가고 알린다(B1·B2).
///
/// `pending`은 저장하는 동안 스위치가 보일 값이다 — 기다리는 동안 스위치가 옛 값으로 튀었다 다시 넘어가지 않게. 그 사이 다시 누르면 무시한다
@MainActor
private func builtInPackBinding(
    _ packID: String, settings: Binding<KeyboardSettings>, pending: Binding<Bool?>,
    onNotice: @escaping @MainActor (PackChangeNotice) -> Void
) -> Binding<Bool> {
    Binding(
        get: { pending.wrappedValue ?? !settings.wrappedValue.disabledSnippetPacks.contains(packID) },
        set: { enabled in
            guard pending.wrappedValue == nil else { return }
            pending.wrappedValue = enabled
            let current = settings.wrappedValue.disabledSnippetPacks
            Task {
                let outcome = await PackStoreClient.live.setBuiltInPack(packID, enabled: enabled, currentDisabled: current)
                if outcome.isAccepted {
                    if enabled {
                        settings.wrappedValue.disabledSnippetPacks.removeAll { $0 == packID }
                    } else if !current.contains(packID) {
                        settings.wrappedValue.disabledSnippetPacks.append(packID)
                    }
                }
                pending.wrappedValue = nil
                if let notice = outcome.notice { onNotice(notice) }
            }
        }
    )
}

/// 새 문구 입력 시트. **단축어 하나 이상 + 본문**이 있어야 저장된다.
///
/// ## 순서는 제목 → 단축어 → 본문이다 (사장님 결정 2026-09-15)
///
/// 예전엔 단축어가 맨 위였는데, 사용자가 먼저 정하는 것은 "이게 무슨 문구인가"(제목)다.
///
/// ## 단축어를 여럿 등록한다 — 구분자는 쉼표
///
/// **그래서 단축어 안에 쉼표를 넣을 수 없다.** 쉼표를 이스케이프하는 문법을 만들면 그걸 다시
/// 설명해야 한다 — 채움글 단축어에 쉼표가 필요한 경우가 드물어 그 한계를 받아들였다.
/// `.sheet(item:)`에 실을 **식별 가능한 포장**.
///
/// ★ `SnippetEntry`에 `Identifiable`을 붙이지 않는다 — id의 기준(`snippetListID`,
/// 정규화 단축어를 이어 붙인 값)은 **이 화면의 목록 사정**이지 도메인 개념이 아니다.
/// 도메인에 붙이면 다른 곳에서 그 id를 의미 있는 것으로 오해한다.
struct EditingSnippet: Identifiable {
    let entry: SnippetEntry
    var id: String { entry.snippetListID }
}

struct SnippetEditorView: View {

    /// 고치는 중인 항목. nil이면 **추가**다.
    let editing: SnippetEntry?

    /// ★ **불러온 단축어에 쉼표가 있었는가** — 저장하면 **쪼개진다.**
    ///
    /// v1.0.1까지 편집기는 단축어 칸이 하나였고 쉼표를 막지 않았다
    /// (`git log` 확인 2026-09-23). 그 시절 저장분의 `"가,나"`는 디코더가 **한 단축어로** 싣는데,
    /// 지금 편집기는 쉼표를 구분자로 보므로 **열었다 저장만 해도 둘로 갈린다** —
    /// 게다가 발동 범위가 넓어진다(`"가,나"` 하나가 `"가"`·`"나"` 둘이 되어 아무 데서나 뜬다).
    ///
    /// ★ **마이그레이션으로 조용히 바꾸지 않는다.** 사용자가 등록한 값을 우리가 해석해
    /// 덮어쓰는 것이고 되돌릴 근거도 안 남는다. **알리고 사용자가 정한다** — 저장도 막지 않는다.
    private var loadedCommaTrigger: Bool { editing?.hasCommaInTrigger ?? false }
    /// 거부 알림을 돌려준다 — nil이면 저장됨(시트를 닫는다), 아니면 **시트·입력을 그대로 두고** 알린다(검증 C6)
    let onSave: @MainActor (SnippetEntry, SnippetEntry?) async -> PackChangeNotice?

    @Environment(\.dismiss) private var dismiss
    @State private var notice: PackChangeNotice?
    /// 저장 중 — 메인 밖에서 판정·쓰기를 기다리는 동안 「저장」을 다시 누르지 못하게
    @State private var isSaving = false
    @State private var triggerText: String
    @State private var title: String
    @State private var body_: String

    /// ★ 불러올 때 **쉼표로 합치고**, 저장할 때 `SnippetEntry.parseTriggers`가 **쉼표로 나눈다** —
    /// 왕복이 같은 규약을 탄다. 구분자를 여기서 새로 정하지 않는다.
    init(editing: SnippetEntry?, onSave: @escaping @MainActor (SnippetEntry, SnippetEntry?) async -> PackChangeNotice?) {
        self.editing = editing
        self.onSave = onSave
        _triggerText = State(initialValue: editing?.triggers.joined(separator: ", ") ?? "")
        _title = State(initialValue: editing?.title ?? "")
        _body_ = State(initialValue: editing?.body ?? "")
    }

    /// 키보드의 입력 꼬리 상한(48자)보다 긴 단축어는 절대 발동하지 않는 죽은 항목이 된다 —
    /// 여유를 두고 40자로 막는다 (리뷰 반영). **정규화 전 원문 기준**이다.
    private static let triggerLimit = 40
    /// 한 문구에 등록할 수 있는 단축어 개수 상한.
    private static let triggerCountLimit = 10

    /// 입력 문자열을 단축어 목록으로 —
    /// 쉼표로 나누고 각각 trim, 빈 것 제거, **정규화 기준 중복 제거**("집주소"와 "집 주소"는 하나).
    ///
    /// 규칙 자체는 `SnippetEntry.parseTriggers` 에 있다 — 뷰 안의 `private var` 라
    /// 테스트가 닿지 않던 것을 도메인으로 옮겼다 (2026-09-15). **여기서 다시 구현하지 않는다.**
    private var parsedTriggers: [String] {
        SnippetEntry.parseTriggers(triggerText)
    }
    private var trimmedBody: String {
        body_.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var tooLong: Bool {
        parsedTriggers.contains { $0.count > Self.triggerLimit }
            || parsedTriggers.count > Self.triggerCountLimit
    }
    /// ★ 내장 날짜·시간 팩과 겹칠 수 있는 단축어인가 — **지금 입력 중인** 단축어로 본다
    /// (PDR `date-snippet-pack.md` 3-5절). 사용자 문구가 날짜 계산보다 먼저라 그 칩을 가린다 —
    /// 버그가 아니라 확정 동작이고, 쉼표 경고와 같은 자리·같은 톤으로 **알리기만** 한다(저장은 막지 않는다).
    /// 판정 규칙은 도메인(`SnippetEntry.mayOverlapDateSnippets`)에 있다 — 여기 두면 테스트가 못 닿는다.
    private var overlapsDateSnippets: Bool {
        SnippetEntry.mayOverlapDateSnippets(parsedTriggers)
    }

    /// 쉼표 경고 문구 — 날짜 겹침 경고와 **함께** 뜰 수 있어 따로 뺐다(문구·근거는 그대로).
    private var commaWarning: some View {
        // 문구를 짧게 둔다 — 무슨 일이 일어나는지와 무엇을 하면 되는지만.
        //
        // ★ **「지우면 이 안내가 사라진다」를 약속하지 않는다** (v1.2.0 ⑩-3, 사장님 결정).
        // 판정이 **불러온 원본** 기준이라(`loadedCommaTrigger`) 입력칸에서 쉼표를 지워도
        // 이 안내는 그대로 남는다. 옛 문구 「하나로 두려면 쉼표를 지우세요」는 지운 뒤에도
        // 안내가 남아 「안 먹혔나」로 읽혔다(`docs/release/verify-v110-8combo-final.md` G).
        // 판정은 현재 입력 기준으로 바꾸지 않는다 — 그러면 정상적인 여러 단축어 입력
        // (`우리집주소, 집주소`)에 **항상** 떠서 더 나쁘다. 그래서 문구를 **저장 결과** 중심으로 쓴다.
        Text("이 단축어에 쉼표가 들어 있어요. 저장하면 쉼표를 기준으로 나뉘어요.\n"
             + "쉼표를 지우고 저장하면 하나로 남아요.")
            .foregroundStyle(.orange)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("제목 (후보에 표시)") {
                    TextField("비우면 단축어를 써요", text: $title)
                }
                Section {
                    TextField("예: 우리집주소, 집주소", text: $triggerText)
                } header: {
                    Text("단축어")
                } footer: {
                    if tooLong {
                        Text("단축어는 하나에 \(Self.triggerLimit)자 이하, \(Self.triggerCountLimit)개까지예요.")
                            .foregroundStyle(.red)
                    } else if loadedCommaTrigger || overlapsDateSnippets {
                        VStack(alignment: .leading, spacing: 6) {
                            if loadedCommaTrigger { commaWarning }
                            if overlapsDateSnippets {
                                // 결과 중심으로 쓴다 — 무엇이 겹치고, 저장하면 어떻게 되는지
                                Text("이 단축어는 내장 날짜·시간 기능과 겹칠 수 있어요. 저장하면 이 문구가 먼저 떠요.")
                                    .foregroundStyle(.orange)
                            }
                        }
                    } else {
                        Text("쉼표(,)로 여러 개를 등록해요. 띄어쓰기는 달라도 돼요.")
                    }
                }
                Section("본문") {
                    TextField("삽입될 전문", text: $body_, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .settingsFormWidth()
            // ★ 추가와 고치기가 같은 시트를 쓰므로 **제목이 갈려야 한다.**
            //   항상 「채움글 추가」면 고칠 때 틀린 말이 된다.
            //   「고치기」는 이 화면의 다른 문구(「~어요」·「채움글 추가」)와 같은 결의 우리말이고,
            //   「편집」·「수정」보다 짧아 좁은 제목 자리에 맞다.
            .navigationTitle(editing == nil ? "채움글 추가" : "채움글 고치기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let triggers = parsedTriggers
                        let entry = SnippetEntry(
                            triggers: triggers,
                            // 제목을 비우면 **첫 단축어**가 제목이 된다
                            title: heading.isEmpty ? (triggers.first ?? "") : heading,
                            body: trimmedBody
                        )
                        isSaving = true
                        Task {
                            // 거부면 닫지 않는다 — 친 내용을 잃지 않게(검증 C6)
                            if let rejected = await onSave(entry, editing) { notice = rejected } else { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(parsedTriggers.isEmpty || trimmedBody.isEmpty || tooLong || isSaving)
                }
            }
            // ★ 편집 시트 안에서는 「확인」만(A3 정리하기·E1 목록 복구 없음) — 그 버튼은 시트를 닫아 **친 내용을 지웠다**(화면 확인 O-4).
            //   정리·복구 길은 채움글 화면 맨 위 배너(㉠·㉡)가 같은 것을 준다. 자리별 버튼은 `PackChangeNotice.Presenter`가 정하고 시험이 고정한다
            .packChangeNoticeAlert($notice, in: .editorSheet) { _ in }
        }
    }
}

// MARK: - 내장 팩 상세 (설명 · 사용법 · 켜기/끄기, 성경은 머리말 스위치)

/// 내장 팩의 설명·사용법 — 데이터(Snippets.json 등)와 짝을 이루는 안내. 단축어는 팩 JSON과 같게 유지한다.
/// 이름은 키보드 후보 패널의 출처 이름표와 같은 상수(`SnippetPackName`, TadakDomain)를 쓴다(U7).
struct SnippetPackInfo {
    let id: String
    let name: String
    let summary: String
    let usage: [(trigger: String, result: String)]
    let note: String?

    static let all: [SnippetPackInfo] = [
        SnippetPackInfo(
            id: SnippetPack.bible, name: SnippetPackName.bible,
            summary: "개역한글판(1961) 성경 66권 전체가 들어 있어요. 책 이름과 장·절을 치면 그 절의 본문이 후보로 떠요. 저작권 보호 기간이 만료된 본문이라 자유롭게 쓸 수 있어요.",
            usage: [
                ("창세기 1장 1절", "정식 이름 + 장·절"),
                ("창 1:1", "약칭 + 콜론"),
                ("요한복음3장16절", "띄어쓰기 없이도 돼요"),
                ("계시록 21:4", "통용 별칭도 받아요")
            ],
            note: "머리말을 켜면 본문 앞에 출처가 함께 들어가요. \"창세기 1장 1절\"이라고 치면 [창세기 1장 1절] 처럼 친 그대로 들어가요."),
        SnippetPackInfo(
            id: SnippetPack.anthem, name: SnippetPackName.anthem,
            summary: "애국가 1~4절, 국기에 대한 맹세, 대한민국 헌법 전문과 제1조부터 제130조까지 전 조문, 기미독립선언서 서두를 담았어요. 공유 저작물과 저작권 보호를 받지 않는 공공 저작물이에요.",
            usage: [
                ("애국가 1절", "1절부터 4절까지"),
                ("국기에 대한 맹세", "또는 \"국기맹세\""),
                ("헌법 전문", "또는 \"헌법전문\""),
                ("헌법 10조", "또는 \"헌법 제10조\" — 1조부터 130조까지 전부"),
                ("독립선언서", "또는 \"기미독립선언서\" — 서두 두 문장")
            ],
            note: nil),
        SnippetPackInfo(
            id: SnippetPack.greetings, name: SnippetPackName.greetings,
            summary: "인사, 축하, 위로·기원, 감사·사과처럼 자주 보내는 문구 25종이에요. 글쇠가 직접 쓴 일반형 문구라 붙여 넣은 뒤 이름이나 상황에 맞게 고쳐 쓰세요.",
            usage: [
                ("인사", "새해인사 · 설날인사 · 추석인사 · 명절인사 · 연말인사 · 크리스마스인사 · 첫인사 · 안부인사 · 입사인사 · 퇴사인사 · 어버이날인사 · 스승의날인사"),
                ("축하 문구", "생일축하 · 결혼축하 · 출산축하 · 합격축하 · 입학축하 · 졸업축하 · 승진축하 · 개업축하"),
                ("위로·기원", "쾌유기원 · 조의문 · 조문답례"),
                ("감사·사과", "감사인사 · 사과문")
            ],
            note: "\"새해인사\"처럼 붙여 쓰거나 \"새해 인사\"처럼 띄어 써도 돼요."),
        // ★ 날짜·시간 팩(v1.2.0, PDR `date-snippet-pack.md` 8절) — 문구 JSON이 없는 계산 팩이다.
        //   **예시는 전부 끝말까지 친 완성형이다**(8-1절) — 「오늘」·「3일 후」처럼 끝말을 뺀 예시는
        //   따라 쳐도 칩이 안 뜬다(반론자2). 전체 목록은 상세 화면의 펼침 목록(`DateSnippetCatalog`)에 있다.
        SnippetPackInfo(
            id: SnippetPack.date, name: SnippetPackName.date,
            summary: "\"오늘 날짜\", \"3일 후 날짜\", \"지금 시간\"처럼 끝에 \"날짜\"나 \"시간\"을 붙여 치면, 치는 그 순간의 날짜·시각을 계산해 후보로 띄워요. 양력 기준이고, 음력 명절은 설날·추석만 찾아 줘요.",
            usage: [
                ("오늘 날짜", "어제 날짜 · 내일 날짜 · 모레 날짜 · 그저께 날짜 · 글피 날짜도 돼요"),
                ("3일 후 날짜", "숫자 + 일·주·개월·년 + 후·뒤·전 — 2주 뒤 날짜, 10개월 전 날짜"),
                ("다음주 금요일 날짜", "이번주 · 다음주 · 지난주 + 요일 — 한 주는 월요일부터"),
                ("광복절 날짜", "양력 공휴일 8종 — 내년 광복절 날짜도 돼요"),
                ("추석 날짜", "설날 날짜 · 구정 날짜도 돼요 — 음력 명절은 이 둘만"),
                ("지금 시간", "지금 날짜 시간 · 오늘 날짜 시간이면 날짜와 시각을 함께 넣어요")
            ],
            note: nil)
    ]
}

struct SnippetPackDetailView: View {

    let pack: SnippetPackInfo
    @Binding var settings: KeyboardSettings
    @State private var notice: PackChangeNotice?
    /// 켜기·끄기를 저장하는 동안 스위치가 보일 값(`builtInPackBinding`)
    @State private var pendingEnabled: Bool?
    /// 켜기 거부 알림의 동작(B1b 정리하기 · E1 목록 복구)
    @State private var showsCleanup = false
    @State private var showsRecovery = false

    var body: some View {
        Form {
            Section {
                Toggle("이 팩 사용", isOn: enabledBinding)
                if pack.id == SnippetPack.bible {
                    // ★ 설명을 **스위치마다** 붙인다 (사용자 지시 2026-09-21).
                    //
                    // 예전에는 설명 셋이 Section 바닥 footer에 뭉쳐 있어 **어느 설명이 어느
                    // 스위치 것인지** 알기 어려웠다. 제목 + 설명 두 줄로 각 행 안에 넣는다.
                    // 스타일은 이 저장소의 보조 문구 관례를 그대로 쓴다
                    // (`.font(.footnote)` + `.foregroundStyle(.secondary)`).

                    // 삽입 텍스트 앞의 출처 머리말 — 키보드 매처가 설정을 읽어 붙인다 (SnippetMatcher biblePrefix)
                    Toggle(isOn: $settings.bibleSnippetPrefixEnabled) {
                        switchLabel(
                            "출처 머리말 넣기",
                            // 문구는 옮기기만 한다 — `pack.note`에 있던 그대로다
                            pack.note ?? ""
                        )
                    }
                    .disabled(!enabledBinding.wrappedValue)

                    // 성경 키워드 검색 — 자리를 툴바 탭에서 여기로 옮겼다 (사용자 지시 2026-09-21).
                    //
                    // 화면 제목이 이미 「성경 (개역한글)」이라 「성경」을 다시 붙이지 않는다.
                    //
                    // **「이 팩 사용」이 꺼지면 함께 흐려진다** — 합성 게이트
                    // (`KeyboardViewController.canSearchBible`)가 `disabledSnippetPacks`를 보므로
                    // 팩이 꺼진 채로는 켜도 동작하지 않는다. **켤 수 있는데 안 도는 스위치는 거짓말이다.**
                    //
                    // 값 자체는 독립 `Bool`이라 팩을 껐다 켜도 **보존된다**(`bibleSearchEnabled`).
                    //
                    // ★ **설명을 한 줄로 줄였다** (사용자 지시 2026-09-22: "여기까지만 써라").
                    //
                    // 지운 두 문장이 담고 있던 것:
                    // (가) 「주소를 치는 단축어와는 다른 기능이에요」 — 이름이 「구절 찾기」에서
                    //      **「단어로 구절 찾기」**가 되면서 **이름 자체가 그 구분을 한다.**
                    // (나) 「네 글자 이상 붙여 쓰면 띄어쓰기가 달라도」 — 전날 「거짓 약속」이라고
                    //      좁힌 바로 그 문장이다. 지금 문구는 **띄어쓰기를 아예 언급하지 않는다** →
                    //      약속하지 않으므로 거짓이 아니다. 대신 사용자가 「왜 내것은 안 되나」를
                    //      물을 수 있고, 그 답은 `bible-space-insensitive-search.md`에 있다.
                    //
                    // 사용자 원문의 「단어을」은 **「단어를」로 바로잡아 썼다** — UI 문구다.
                    //
                    // ★ **제목을 박지 않는다** (2026-09-22). 툴바 도구 목록의 이름과
                    //   **같은 문자열이어야 한다** — 설정에서 켠 것과 툴바에 보이는 것이
                    //   같은 기능임을 알아볼 수 있어야 하기 때문이다. 이름이 이미 두 번
                    //   바뀌었고 그때마다 두 곳을 따로 고쳤다.
                    Toggle(isOn: $settings.bibleSearchEnabled) {
                        switchLabel(
                            ToolbarTool.bibleSearch.displayName,
                            "「사랑」처럼 단어를 치면 그 단어가 든 구절을 툴바에서 찾아 줘요."
                        )
                    }
                    .disabled(!enabledBinding.wrappedValue)
                }
            } footer: {
                // 스위치 하나의 설명이 아니라 **Section 전체의 상태 안내**다 — 그래서 여기 남는다.
                if pack.id == SnippetPack.bible {
                    if !enabledBinding.wrappedValue {
                        // ★ 여기는 **문장 안**이라 상수로 빼지 않았다 (2026-09-22 판단).
                        //   `"이 팩을 켜야 머리말 넣기와 \(ToolbarTool.bibleSearch.displayName)도…"`로
                        //   쓰면 **조사가 이름을 따라가지 못한다** — 지금은 받침 없는 「기」로
                        //   끝나 「도」가 맞지만, 이름이 받침으로 끝나면 문장이 깨진다.
                        //   이름이 바뀌면 이 줄은 **사람이 읽고 고쳐야 한다.**
                        //   대신 위 스위치 제목이 이름을 참조하므로 **둘이 어긋나면 화면에서 바로 보인다.**
                        Text("이 팩을 켜야 머리말 넣기와 단어로 구절 찾기도 쓸 수 있어요.")
                    }
                } else if let note = pack.note {
                    // 성경이 아닌 팩은 스위치가 「이 팩 사용」 하나뿐이라 설명이 Section 것이다
                    Text(note)
                }
            }

            if pack.id == SnippetPack.date {
                DateSnippetStylePicker(style: $settings.dateSnippetStyle)
                    .disabled(!enabledBinding.wrappedValue)
            }

            Section("설명") {
                Text(pack.summary)
                    .font(.callout)
            }

            Section {
                ForEach(Array(pack.usage.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.trigger)
                            .font(.body.monospacedDigit())
                        Text(item.result)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("사용법")
            } footer: {
                Text("단축어를 커서 끝까지 치면 툴바에 칩이 떠요. 칩을 누르면 단축어가 전문으로 바뀌어요.")
            }

            if pack.id == SnippetPack.date {
                DateSnippetCatalog()
            }
        }
        .settingsFormWidth()
        .navigationTitle(pack.name)
        .navigationBarTitleDisplayMode(.inline)
        .packChangeNoticeAlert($notice) { action in
            switch action {
            case .organize: showsCleanup = true
            case .recoverLibrary: showsRecovery = true
            default: break
            }
        }
        .navigationDestination(isPresented: $showsCleanup) { SnippetCleanupView() }
        .packLibraryRecovery(isPresented: $showsRecovery) {}
    }

    /// 스위치 한 행의 **제목 + 설명** — 설명이 어느 스위치 것인지 붙어 있어야 한다.
    private func switchLabel(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var enabledBinding: Binding<Bool> {
        builtInPackBinding(pack.id, settings: $settings, pending: $pendingEnabled) { notice = $0 }
    }
}


// MARK: - 날짜·시간 팩 (v1.2.0, PDR `date-snippet-pack.md` 4·8절)

/// 출력 형식 고르기 — 세 형식을 **실제 모양**으로 보여 준다.
///
/// ★ 예시 문자열은 키보드의 출력 지점(`KeyboardCore.DateSnippetFormatter`)과 **같은 모양이어야 한다.**
/// 앱 타깃은 KeyboardCore를 링크하지 않아(의존성 추가는 이번 범위 밖) 여기 문자열로 적었다 —
/// 형식을 바꾸면 이 예시도 함께 고친다. 기준 시각은 2026-09-27 21:54(PDR 4-1절 표와 같다).
private struct DateSnippetStylePicker: View {

    @Binding var style: DateSnippetStyle

    var body: some View {
        Section {
            Picker("출력 형식", selection: $style) {
                ForEach(DateSnippetStyle.allCases, id: \.self) { option in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(option.displayName)
                        Text(Self.example(option))
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("출력 형식")
        } footer: {
            Text("규범형·관행형은 24시간, 한글형은 오전·오후로 써요. 초는 넣지 않아요.")
        }
    }

    private static func example(_ style: DateSnippetStyle) -> String {
        switch style {
        case .formal: "2026. 9. 27. · 21:54"
        case .common: "2026.09.27 · 21:54"
        case .korean: "2026년 9월 27일 · 오후 9시 54분"
        }
    }
}

/// 날짜 팩 단축어 전체 — 접었다 펴는 4묶음(PDR 8-3절). **모든 예시는 끝말까지 친 완성형이다**(8-1절).
///
/// 키보드가 받는 어휘는 `KeyboardCore.DateSnippetParser`의 표가 SSOT다 — 거기에 더하면 여기도 더한다.
private struct DateSnippetCatalog: View {

    var body: some View {
        Section {
            DisclosureGroup("숫자 계산") {
                row("5일 후 날짜 · 2주 뒤 날짜 · 10개월 전 날짜", "숫자 + 단위 + 방향 + 날짜")
                row("숫자", "1~999, 또는 한·두·세·네·다섯·여섯·일곱·여덟·아홉·열 — 두 달 후 날짜")
                row("날 수로", "하루 · 이틀 · 사흘 · 나흘 · 닷새 · 엿새 · 이레 · 여드레 · 아흐레 · 열흘 · 보름 · 일주일 — 사흘 뒤 날짜")
                row("단위", "일 · 주(주일) · 개월(달) · 년(해)")
                row("방향", "후 · 뒤 · 전 · 이전")
                row("말일에서 달을 더하면", "그 달의 말일로 맞춰요 — 1월 31일에 1개월 후 날짜는 2월 28일")
            }
            DisclosureGroup("요일·월말") {
                row("그저께 · 어제 · 오늘 · 내일 · 모레 · 글피 날짜", "글피는 모레의 다음 날")
                row("이번주 · 다음주 · 지난주 + 월요일~일요일 날짜", "한 주는 월요일부터 일요일까지 — 다음주 금요일 날짜")
                row("이번달 첫날 날짜 · 이번달 말일 날짜", "")
                row("올해 마지막날 날짜", "연말 날짜라고 쳐도 같아요")
                row("분기말 날짜", "지금이 속한 분기의 마지막 날")
            }
            DisclosureGroup("공휴일·기념일") {
                row("신정 · 삼일절 · 어린이날 · 현충일 · 광복절 · 개천절 · 한글날 · 성탄절 날짜",
                    "앞에 올해·이번·이번년도·내년을 붙일 수 있어요 — 내년 성탄절 날짜")
                row("설날 · 구정 · 추석 날짜", "한국 음력 기준, 2050년까지 — 이번년도 추석 날짜 · 내년 설날 날짜")
                row("올해 날짜를 보여 줍니다", "올해 공휴일이 지난 뒤 다음 공휴일을 찾으려면 『내년 … 날짜』를 입력하세요")
                row("후보 이름 옆 표시", "· 올해(아직 안 옴) · 지남(지났음) · 오늘 — 넣는 값에는 붙지 않아요")
                row("음력 명절은 설날·추석뿐이에요", "정월대보름·부처님오신날·단오·칠석과 대체·임시공휴일은 없어요")
            }
            DisclosureGroup("시간") {
                row("현재 시간 · 지금 시간 · 현재 시각 · 지금 시각", "시각만")
                row("지금 · 현재 · 오늘 + 날짜 시간 · 날짜 시각", "날짜와 시각을 함께 — 오늘 날짜 시간")
                row("후보를 띄운 뒤 분이 바뀌면", "누를 때 새 시각으로 다시 떠요 — 한 번 더 누르세요")
            }
        } header: {
            Text("단축어 전체")
        }
    }

    private func row(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
            if !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
