import SwiftUI
import TadakDomain
import TadakData

/// 툴바 탭 — 도구 on/off, 클립보드 기록, 추천단어·학습 초기화, 채움글, 인증번호 제안.
struct ToolbarTab: View {

    @Binding var settings: KeyboardSettings

    @State private var showsLearningResetDialog = false
    @State private var showsClipboardClearDialog = false
    /// 도구 순서 편집 모드 — 시스템 EditButton("편집") 대신 "순서 편집"으로 이름을 붙인다 (사용자 요청 2026-09-08)
    @State private var isEditingOrder = false

    private let clipboardHistoryRepository: ClipboardHistoryRepository = AppGroupClipboardHistoryRepository()

    var body: some View {
        NavigationStack {
            Form {
                toolsSection
                suggestionSection   // 추천단어·채움글이 클립보드보다 자주 손대는 설정 (사용자 요청 2026-09-08)
                clipboardSection
                fullAccessSection   // 전체 접근이 필요한 기능들의 안내 (사용자 버그 보고 2026-09-11)
            }
            .settingsFormWidth()
            .navigationTitle("툴바")
            .environment(\.editMode, Binding(
                get: { isEditingOrder ? .active : .inactive },
                set: { isEditingOrder = $0 == .active }
            ))
            .toolbar {
                // 순서 편집 — 편집 모드에서 드래그 핸들로 도구 순서를 바꾼다
                Button(isEditingOrder ? "완료" : "순서 편집") {
                    withAnimation { isEditingOrder.toggle() }
                }
            }
        }
    }

    private var toolsSection: some View {
        Section {
            ForEach(settings.orderedTools, id: \.self) { tool in
                // 키보드 툴바와 같은 아이콘을 왼쪽에 (사용자 요청 2026-09-08)
                Toggle(isOn: toolBinding(tool)) {
                    Label(tool.displayName, systemImage: tool.symbolName)
                }
            }
            .onMove(perform: moveTools)
        } header: {
            Text("도구")
        } footer: {
            Text("클립보드 도구는 전체 접근이 있을 때만 보여요.")
        }
    }

    private func moveTools(from source: IndexSet, to destination: Int) {
        var order = settings.orderedTools
        order.move(fromOffsets: source, toOffset: destination)
        settings.toolOrder = order
    }

    private var clipboardSection: some View {
        Section {
            Toggle(isOn: clipboardHistoryBinding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("클립보드 기록")
                    Text("전체 접근 필요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button("클립보드 기록 지우기", role: .destructive) {
                showsClipboardClearDialog = true
            }
            .confirmationDialog(
                "저장된 클립보드 기록을 모두 지울까요?",
                isPresented: $showsClipboardClearDialog,
                titleVisibility: .visible
            ) {
                Button("지우기", role: .destructive) { clipboardHistoryRepository.clear() }
            }
        } header: {
            Text("클립보드")
        } footer: {
            Text("전체 접근이 필요해요 — 아래 「전체 접근」 안내를 보세요. 기록을 끄면 저장분이 바로 삭제돼요.")
        }
    }

    /// 끄면 저장분을 즉시 비운다 — 보안 규칙 "끄면 기존 기록도 삭제" (PDR clipboard-history).
    private var clipboardHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.clipboardHistoryEnabled },
            set: { enabled in
                settings.clipboardHistoryEnabled = enabled
                if !enabled { clipboardHistoryRepository.clear() }
            }
        )
    }

    /// **전체 접근 안내 — 항상 보인다.**
    ///
    /// 설계 결정(사장님, 2026-09-11): **상태를 추정하지 않는다.** 컨테이너 앱은
    /// `hasFullAccess`를 읽을 수 없고, App Group 쓰기 흔적으로 추정하면 오탐(신규 설치 직후
    /// 허용 상태인데 "꺼짐"으로 보임)과 미탐(허용 뒤 철회를 모름)을 구분할 수 없다(반론자 B).
    /// 그래서 "지금 켜졌는지"를 말하지 않고 **"이 기능에는 전체 접근이 필요하다"는 요건만**
    /// 조건 없이 설명한다. App Group에 새 키를 만들지 않는다.
    ///
    /// **"다른 앱에서 붙여넣기"를 반드시 함께 안내한다.** 전체 접근만 켜면 iOS가 붙여넣기 확인
    /// 창을 띄워 "여전히 안 된다"가 되기 때문이다 — 시뮬레이터에서 실측한 지점이다
    /// (`paste-chip-plan.md` A-2).
    private var fullAccessSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("인증번호 제안·클립보드 도구와 기록·키 입력 진동은 전체 접근이 있어야 동작해요.",
                      systemImage: "lock.open")
                    .font(.subheadline)
                Text("켜는 곳: 설정 > 일반 > 키보드 > 키보드 > 글쇠 > 전체 접근 허용")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Divider()
                Text("인증번호가 칩에 보이려면 키보드가 복사한 내용을 읽어야 해요. 그래서 iOS가 "
                     + "\"붙여넣으려고 함\" 확인 창을 띄워요. 매번 누르기 번거로우면 아래에서 "
                     + "「다른 앱에서 붙여넣기」를 \"허용\"으로 바꾸세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("바꾸는 곳: 설정 > 글쇠 > 다른 앱에서 붙여넣기 > 허용")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)

            Button {
                // 컨테이너 앱이라 자기 설정 페이지를 열 수 있다 (온보딩이 이미 쓰는 경로).
                // 키보드 설정 화면까지 바로 가는 공개 URL은 없어 경로를 글로 적었다.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("글쇠 설정 열기", systemImage: "arrow.up.forward.app")
            }
        } header: {
            Text("전체 접근")
        } footer: {
            Text("전체 접근 없이도 한글 입력·채움글·추천단어 등 핵심 기능은 전부 동작해요.")
        }
    }

    private var suggestionSection: some View {
        Section {
            Toggle("추천단어", isOn: $settings.suggestionsEnabled)
            // 추천단어를 꺼도 초기화는 가능해야 한다 — 기능을 끄는 사용자일수록
            // 남은 학습 데이터를 지우고 싶어 한다
            Button("학습 단어 초기화", role: .destructive) {
                showsLearningResetDialog = true
            }
            .confirmationDialog(
                "키보드가 학습한 단어를 모두 지울까요?",
                isPresented: $showsLearningResetDialog,
                titleVisibility: .visible
            ) {
                Button("초기화", role: .destructive) { resetLearnedWords() }
            }

            NavigationLink {
                SnippetSettingsView(settings: $settings)
            } label: {
                LabeledContent("채움글", value: settings.snippetsEnabled ? "켬" : "끔")
            }

            // **토글 옆에 요건을 적는다.** 권한이 없어도 토글은 켜진 채로 보이므로,
            // 사용자는 "켰는데 왜 안 되지"가 된다 — 이번 버그 보고가 정확히 그 결과다
            // (2026-09-11). 상태를 추정하지 않고 **요건만** 조건 없이 말한다.
            Toggle(isOn: $settings.verificationCodeSuggestionsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("복사한 인증번호 제안")
                    Text("전체 접근 필요")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("추천과 채움글")
        } footer: {
            Text("학습은 기기 안에서만 해요. 인증번호 제안은 전체 접근이 필요해요 — 아래 「전체 접근」 안내를 보세요.")
        }
    }

    private func toolBinding(_ tool: ToolbarTool) -> Binding<Bool> {
        Binding(
            get: { !settings.disabledTools.contains(tool) },
            set: { enabled in
                if enabled {
                    settings.disabledTools.removeAll { $0 == tool }
                } else if !settings.disabledTools.contains(tool) {
                    settings.disabledTools.append(tool)
                }
            }
        )
    }

    /// 저장소를 비우는 것만으로는 부족하다 — 살아 있는 익스텐션이 세션 메모리로 옛 단어를
    /// 되살린다. 토큰을 올려 키보드가 엔진을 재생성하게 한다 (PDR settings-app 결정 4).
    private func resetLearnedWords() {
        AppGroupUserWordRepository().save([:])
        settings.learningResetToken += 1
    }
}
