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
            }
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
            Toggle("클립보드 기록", isOn: clipboardHistoryBinding)
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
            Text("전체 접근이 필요해요. 기록을 끄면 저장분이 바로 삭제돼요.")
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

            Toggle("복사한 인증번호 제안", isOn: $settings.verificationCodeSuggestionsEnabled)
        } header: {
            Text("추천과 채움글")
        } footer: {
            Text("학습은 기기 안에서만 해요. 인증번호 제안은 전체 접근이 필요해요.")
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
