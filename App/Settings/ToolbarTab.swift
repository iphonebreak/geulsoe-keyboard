import SwiftUI
import TadakDomain
import TadakData

/// 툴바 탭 — 도구 on/off, 클립보드 기록, 추천단어·학습 초기화, 채움글, 인증번호 제안.
struct ToolbarTab: View {

    @Binding var settings: KeyboardSettings

    @State private var showsLearningResetDialog = false
    @State private var showsClipboardClearDialog = false
    /// 클립보드 기록을 **끔 → 켬**으로 바꾼 그 순간에만 뜨는 권한 안내.
    /// 이미 켜 둔 사용자를 다시 괴롭히지 않으려고 전환 방향을 본다.
    @State private var showsClipboardPermissionSheet = false
    /// 도구 순서 편집 모드 — 시스템 EditButton("편집") 대신 "순서 편집"으로 이름을 붙인다 (사용자 요청 2026-09-08)
    @State private var isEditingOrder = false

    private let clipboardHistoryRepository: ClipboardHistoryRepository = AppGroupClipboardHistoryRepository()

    var body: some View {
        NavigationStack {
            Form {
                toolsSection
                suggestionSection   // 추천단어·채움글이 클립보드보다 자주 손대는 설정 (사용자 요청 2026-09-08)
                clipboardSection    // 전체 접근 안내를 이 절로 **합쳤다** (사용자 요청 2026-09-15)
            }
            .settingsFormWidth()
            .navigationTitle("툴바")
            .sheet(isPresented: $showsClipboardPermissionSheet) {
                ClipboardPermissionSheet()
            }
            // `.environment(\.editMode, ...)`를 걸지 않는다 — 그건 `.onMove`(세로 List 재배열) 전용이었고,
            // 켜 두면 이 Form의 **다른 행들까지** 편집 모드 모양이 된다. 가로 미리보기는 자체 제스처를 쓴다.
            .toolbar {
                // 순서 편집 — 이 모드에서만 미리보기 셀에 드래그가 붙는다
                Button(isEditingOrder ? "완료" : "순서 편집") {
                    withAnimation { isEditingOrder.toggle() }
                }
            }
        }
    }

    /// 도구 섹션 — **가로 미리보기 한 줄이 세로 `Toggle` 리스트를 대체한다** (사용자 요청 2026-09-14).
    /// 세로 리스트를 남겨 두면 같은 것을 두 군데서 조작하게 되고, 불편하다고 한 그 리스트가 그대로 남는다.
    private var toolsSection: some View {
        Section {
            ToolbarOrderPreview(settings: $settings, isEditing: isEditingOrder)
                .listRowInsets(EdgeInsets(top: 14, leading: 10, bottom: 14, trailing: 10))
                .listRowBackground(Color(.secondarySystemGroupedBackground))
            if isEditingOrder {
                Button("기본 순서로 되돌리기") {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        // **순서만** 되돌린다 — on/off는 건드리지 않는다. 그래서 "기본값"이 아니라 "기본 순서"다.
                        settings.toolOrder = ToolbarTool.allCases
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text("도구")
        } footer: {
            Text(toolsFooter)
        }
    }

    private var toolsFooter: String {
        if settings.disabledTools.count >= ToolbarTool.allCases.count {
            return "지금은 툴바에 도구가 하나도 보이지 않아요.\n아이콘을 눌러 다시 켤 수 있어요."
        }
        if isEditingOrder {
            return "아이콘을 끌어서 자리를 옮기세요.\n클립보드 도구는 전체 접근이 있을 때만 보여요."
        }
        return "아이콘을 눌러 도구를 켜고 끌 수 있어요.\n순서를 바꾸려면 오른쪽 위 ‘순서 편집’을 누르세요.\n클립보드 도구는 전체 접근이 있을 때만 보여요."
    }

    /// 클립보드 절 — **예전 「전체 접근」 절을 여기로 합쳤다** (사용자 요청 2026-09-15:
    /// "툴바 탭에 클립보드와 전체 접근 영역을 클립보드 영역과 합하자, 너무 복잡해 보인다",
    /// "설정 위치만 놔두고 전체 접근 글을 제거하자").
    ///
    /// **합치는 김에 「복사한 인증번호 제안」 토글도 여기로 옮겼다.** 옮기지 않으면
    /// `suggestionSection` 푸터가 **사라진 「전체 접근」 헤더를 계속 가리킨다** — 그 문장은
    /// 어차피 고쳐야 했고, 고칠 바엔 두 토글을 같은 절에 모으는 쪽이 더 간결하다
    /// (반론자 R-1·R-6, 사장님 채택). 두 토글은 **같은 권한 하나**에 묶여 있다.
    ///
    /// ## 안내가 왜 "1단계 / 2단계"인가 — 병렬이 아니라 순서다
    ///
    /// 예전 문구는 「전체 접근 허용」과 「다른 앱에서 붙여넣기」를 **두 줄로 나란히** 적었다.
    /// 검증자가 시뮬레이터에서 걸어 보니 그게 틀렸다(`docs/release/settings-path-truth.md`):
    ///
    /// - 「전체 접근 허용」 행은 **글쇠 스위치를 켜는 그 순간 같은 화면에 생긴다.** 화면 이동 없음.
    /// - 「다른 앱에서 붙여넣기」 행은 **처음에 아예 없다.** 설치로도, 키보드를 켜도, 전체 접근을
    ///   켜도 안 생긴다. **키보드가 클립보드를 처음 읽어 확인 창이 한 번 뜬 뒤에야** 생긴다.
    ///
    /// 즉 예전처럼 "설정에 가서 허용으로 바꾸세요"를 먼저 시키면 **사용자는 없는 행을 찾는다.**
    /// 그래서 안내 순서가 실제 순서를 따른다.
    ///
    /// ## 상태를 말하지 않는다
    ///
    /// 컨테이너 앱은 `hasFullAccess`를 읽을 수 없다. "지금 꺼져 있어요" 류의 상태 문구를
    /// 만들지 않는다 — 오탐(신규 설치 직후 허용 상태인데 "꺼짐")과 미탐(허용 뒤 철회를 모름)을
    /// 구분할 수 없어서다. **요건만** 조건 없이 말한다. 조건부 잠금은 v1.1.0으로 미뤘다
    /// (`docs/release/v1.1.0-backlog.md` 1절).
    private var clipboardSection: some View {
        Section {
            Toggle(isOn: clipboardHistoryBinding) {
                settingLabel("클립보드 기록")
            }
            // **토글 옆에 요건을 적는다.** 권한이 없어도 토글은 켜진 채로 보이므로 사용자는
            // "켰는데 왜 안 되지"가 된다 — 2026-09-11 버그 보고가 정확히 그 결과였다.
            //
            // **끔 → 켬 전환에서 권한 시트를 띄운다** (사장님 지시 2026-09-15). 시트를 만든 이유가
            // "안내가 토글을 켜는 그 순간에 없어서 안 읽혔다"인데, 정작 그 버그 보고는
            // **인증번호 쪽**이었다. 클립보드 기록 토글에만 붙어 있던 것을 두 토글에 마저 붙인다.
            Toggle(isOn: fullAccessBinding(\.verificationCodeSuggestionsEnabled)) {
                settingLabel("복사한 인증번호 제안")
            }
            // 복사한 **일반 텍스트**도 칩으로 — 사용자 요청 2026-09-15
            // ("네이버키보드와 동일하게 1줄로 보여준다 … 누르면 붙여넣기가 됨").
            // 인증번호 토글과 **따로 둔다**: 이쪽은 복사한 내용이 그대로 화면에 보인다
            // (설계 `docs/design-reviews/paste-chip-plan.md` C-5).
            Toggle(isOn: fullAccessBinding(\.pasteSuggestionEnabled)) {
                settingLabel("복사한 텍스트 제안")
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

            Button {
                // 컨테이너 앱은 **자기 설정 페이지만** 열 수 있고, 그마저도 어디에 떨어질지
                // 보장되지 않는다 — 설정 앱이 떠 있으면 마지막 본 화면, 종료돼 있으면 설정 루트다
                // (검증자 실측 2026-09-15). 그래서 라벨 아래에 완충 문구를 붙였다.
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("글쇠 설정 열기", systemImage: "arrow.up.forward.app")
                    Text("설정 앱을 열어요. 「글쇠」가 바로 안 보이면 「앱」에서 찾으세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // **설명 글을 지우면서 이 버튼이 유일한 상시 안내 경로가 됐다.**
            // 이름도 바꿨다 — 예전 「왜 두 가지가 필요한지 보기」의 "두 가지"는 iOS 설정 둘
            // (전체 접근 허용 · 다른 앱에서 붙여넣기)을 가리키는 말이었는데, 이 절에 토글이 셋이라
            // **우리 토글 두 개로 읽힐 여지**가 생겼다. 무엇이 나오는지를 이름이 말하게 한다.
            Button {
                showsClipboardPermissionSheet = true
            } label: {
                Label("전체 접근 켜는 방법 보기", systemImage: "questionmark.circle")
            }
        } header: {
            Text("클립보드")
        } footer: {
            // **둘 다 반드시 남긴다.** 앞 문장은 "권한을 안 켜면 앱을 못 쓴다"는 오해를 막는
            // 안심 문장이고, 뒷 문장은 **개인정보 처리방침이 이용자 권리로 명시한 것**이라
            // 안내 없이 지우면 방침과 화면이 어긋난다 (반론자 R-3).
            Text("전체 접근 없이도 한글 입력·채움글·추천단어는 그대로 동작해요.\n"
                 + "클립보드 기록을 끄면 저장분이 바로 삭제돼요.")
        }
    }

    /// 전체 접근이 필요한 토글의 공용 바인딩 — **끔 → 켬 전환에서만** 권한 시트를 띄운다.
    ///
    /// 이미 켜 둔 사용자를 다시 괴롭히지 않으려고 전환 방향을 본다
    /// (클립보드 기록 토글이 2026-09-11부터 쓰던 규칙과 같다).
    private func fullAccessBinding(_ keyPath: WritableKeyPath<KeyboardSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { enabled in
                let wasOff = !settings[keyPath: keyPath]
                settings[keyPath: keyPath] = enabled
                if enabled, wasOff { showsClipboardPermissionSheet = true }
            }
        )
    }

    /// 토글 라벨 — 제목 + "전체 접근 권한 필요" 한 줄. 세 토글이 같은 모양을 쓴다.
/// (문구는 사용자 지시 2026-09-15: "전체 접근 필요 → 전체 접근 권한 필요")
    private func settingLabel(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text("전체 접근 권한 필요")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// 끄면 저장분을 즉시 비운다 — 보안 규칙 "끄면 기존 기록도 삭제" (PDR clipboard-history).
    ///
    /// **끔 → 켬 전환에서만** 권한 안내를 띄운다. 이미 켜 둔 사용자는 이 경로를 타지 않는다.
    private var clipboardHistoryBinding: Binding<Bool> {
        Binding(
            get: { settings.clipboardHistoryEnabled },
            set: { enabled in
                let wasOff = !settings.clipboardHistoryEnabled
                settings.clipboardHistoryEnabled = enabled
                if !enabled {
                    clipboardHistoryRepository.clear()
                } else if wasOff {
                    showsClipboardPermissionSheet = true
                }
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
            // 「복사한 인증번호 제안」 토글은 **클립보드 절로 옮겼다** (2026-09-15).
            // 여기 있던 푸터가 **사라진 「전체 접근」 헤더를 가리키고 있었고**(반론자 R-1),
            // 그 토글은 클립보드 기록과 **같은 권한 하나**에 묶여 있어 같은 절이 맞다.
        } header: {
            Text("추천과 채움글")
        } footer: {
            Text("학습은 기기 안에서만 해요.")
        }
    }

    /// 저장소를 비우는 것만으로는 부족하다 — 살아 있는 익스텐션이 세션 메모리로 옛 단어를
    /// 되살린다. 토큰을 올려 키보드가 엔진을 재생성하게 한다 (PDR settings-app 결정 4).
    private func resetLearnedWords() {
        AppGroupUserWordRepository().save([:])
        settings.learningResetToken += 1
    }
}
