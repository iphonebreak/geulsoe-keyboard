import SwiftUI
import KeyboardCore
import TadakDomain

/// 키보드 익스텐션의 SwiftUI 루트. 툴바 + 자판.
///
/// 조립 지점(KeyboardViewController)이 상태와 이벤트 핸들러를 주입한다 —
/// 이 뷰는 TadakData를 모른다 (의존성 규칙).
public struct KeyboardRootView: View {

    /// 툴바 높이. 조립 지점의 총 높이 계산과 공유한다.
    /// 44 → 52(도구 버튼이 좁고 낮다, 2026-09-02) → 46(52는 너무 높다, 2026-09-03) — 사용자 피드백 순.
    public static let toolbarHeight: CGFloat = 46

    private let state: KeyboardViewState
    private let onEvent: (KeyEvent) -> Void
    private let onSnippetTap: ((SnippetSuggestion) -> Void)?
    private let onWordTap: ((String) -> Void)?
    private let onPasteboardCodeTap: (() -> Void)?
    private let onToolTap: ((ToolbarTool) -> Void)?
    private let onCursorMove: ((Int) -> Void)?
    private let onEmojiTap: ((String) -> Void)?
    private let onKeyPress: (() -> Void)?
    private let onClipboardEntryTap: ((String) -> Void)?
    private let onClipboardEntryDelete: ((String) -> Void)?
    private let onClipboardClear: (() -> Void)?
    private let onCursorDrag: ((Int) -> Void)?
    private let onDismissSuggestions: (() -> Void)?
    private let inputModeSwitchButton: AnyView?

    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - inputModeSwitchButton: `needsInputModeSwitchKey`가 참일 때
    ///     지구본 자리에 들어갈 UIKit 버튼 래퍼. 조립 지점이 만들어 준다.
    ///   - onSnippetTap: 툴바 채움글 칩을 탭했을 때. nil이면 칩을 그리지 않는다.
    ///   - onWordTap: 추천단어 후보를 탭했을 때. nil이면 후보를 그리지 않는다.
    ///   - onPasteboardCodeTap: 인증번호 붙여넣기 칩을 탭했을 때. nil이면 칩을 그리지 않는다.
    ///   - onToolTap: 툴바 도구(내리기·클립보드·이모지)를 탭했을 때. nil이면 도구 행을 그리지 않는다.
    ///   - onClipboardEntryTap/Delete/Clear: 클립보드 기록 패널 항목 삽입·삭제·모두 지우기.
    ///   - onCursorDrag: 스페이스 트랙패드 모드의 문자 단위 커서 이동 (진동 없이 연속 호출된다).
    ///   - onDismissSuggestions: 후보 행 맨 오른쪽 ✕ — 후보를 내리고 도구 행으로 돌아간다.
    ///   - onCursorMove: 커서 이동 도구(◀ -1 / ▶ +1).
    ///   - onEmojiTap: 이모지 그리드에서 이모지를 골랐을 때.
    ///   - onKeyPress: 자판 키 터치다운(백스페이스 반복 포함) — 클릭음·진동 재생 시점.
    public init(
        state: KeyboardViewState,
        inputModeSwitchButton: AnyView? = nil,
        onEvent: @escaping (KeyEvent) -> Void,
        onSnippetTap: ((SnippetSuggestion) -> Void)? = nil,
        onWordTap: ((String) -> Void)? = nil,
        onPasteboardCodeTap: (() -> Void)? = nil,
        onToolTap: ((ToolbarTool) -> Void)? = nil,
        onCursorMove: ((Int) -> Void)? = nil,
        onEmojiTap: ((String) -> Void)? = nil,
        onKeyPress: (() -> Void)? = nil,
        onClipboardEntryTap: ((String) -> Void)? = nil,
        onClipboardEntryDelete: ((String) -> Void)? = nil,
        onClipboardClear: (() -> Void)? = nil,
        onCursorDrag: ((Int) -> Void)? = nil,
        onDismissSuggestions: (() -> Void)? = nil
    ) {
        self.state = state
        self.inputModeSwitchButton = inputModeSwitchButton
        self.onEvent = onEvent
        self.onSnippetTap = onSnippetTap
        self.onWordTap = onWordTap
        self.onPasteboardCodeTap = onPasteboardCodeTap
        self.onToolTap = onToolTap
        self.onCursorMove = onCursorMove
        self.onEmojiTap = onEmojiTap
        self.onKeyPress = onKeyPress
        self.onClipboardEntryTap = onClipboardEntryTap
        self.onClipboardEntryDelete = onClipboardEntryDelete
        self.onClipboardClear = onClipboardClear
        self.onCursorDrag = onCursorDrag
        self.onDismissSuggestions = onDismissSuggestions
    }

    private var theme: ResolvedTheme {
        ResolvedTheme(spec: state.themeSpec, appearance: state.appearance, systemColorScheme: colorScheme)
    }

    public var body: some View {
        let theme = self.theme
        VStack(spacing: 0) {
            SuggestionToolbar(
                state: state,
                theme: theme,
                onSnippetTap: onSnippetTap,
                onWordTap: onWordTap,
                onPasteboardCodeTap: onPasteboardCodeTap,
                onToolTap: onToolTap,
                onCursorMove: onCursorMove,
                onDismissSuggestions: onDismissSuggestions
            )
            if state.showsClipboardPanel, let onClipboardEntryTap, let onToolTap {
                ClipboardPanelView(
                    entries: state.clipboardEntries,
                    historyEnabled: state.clipboardHistoryEnabled,
                    theme: theme,
                    onEntryTap: onClipboardEntryTap,
                    onEntryDelete: { onClipboardEntryDelete?($0) },
                    onClearAll: { onClipboardClear?() },
                    onClose: { onToolTap(.clipboard) }  // 토글 — 조립 지점이 패널을 닫는다
                )
                .frame(height: state.keyboardHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            } else if state.showsEmojiPanel, let onEmojiTap, let onToolTap {
                EmojiGridView(
                    recentEmojis: state.recentEmojis,
                    theme: theme,
                    onEmojiTap: onEmojiTap,
                    onBackspace: { onEvent(.backspace) },
                    onClose: { onToolTap(.emoji) }  // 토글 — 조립 지점이 패널을 닫는다
                )
                .frame(height: state.keyboardHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            } else {
                KeyboardLayoutView(
                    state: state,
                    theme: theme,
                    inputModeSwitchButton: inputModeSwitchButton,
                    onEvent: onEvent,
                    onKeyPress: onKeyPress,
                    onCursorDrag: onCursorDrag  // 스페이스 길게 누른 뒤 드래그 — 트랙패드 커서 이동
                )
                .frame(height: state.keyboardHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
            }
        }
        .background(theme.keyboardBackground)
    }

    // 툴바 구현은 SuggestionToolbar (별도 View) — 후보 프로퍼티 읽기 격리
}

/// 채움글 칩(항상 앞) + 추천단어 후보. 둘 다 없으면 자리 표시.
/// 도구 내용물(커서·클립보드·이모지)은 Phase 4에서 들어온다.
///
/// **별도 View인 이유:** 후보는 거의 매 키 입력마다 바뀐다. 루트 body에서 읽으면
/// @Observable 추적이 루트에 걸려 자판 전체가 키마다 재평가된다 — 여기(자식 body)로
/// 격리해 무효화 범위를 툴바로 좁힌다 (성능 규율).
private struct SuggestionToolbar: View {

    let state: KeyboardViewState
    let theme: ResolvedTheme
    let onSnippetTap: ((SnippetSuggestion) -> Void)?
    let onWordTap: ((String) -> Void)?
    let onPasteboardCodeTap: (() -> Void)?
    let onToolTap: ((ToolbarTool) -> Void)?
    let onCursorMove: ((Int) -> Void)?
    let onDismissSuggestions: (() -> Void)?

    var body: some View {
        let snippet = state.snippetSuggestion
        let words = state.wordSuggestions
        let hasCandidates = snippet != nil || !words.isEmpty || state.pasteboardCode != nil
        return HStack(spacing: 10) {
            if let code = state.pasteboardCode, let onPasteboardCodeTap {
                Button(action: onPasteboardCodeTap) {
                    Label(code, systemImage: "doc.on.clipboard")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(theme.characterKey, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("복사한 인증번호 \(code) 붙여넣기")
            }
            if let snippet, let onSnippetTap {
                SnippetChip(suggestion: snippet, theme: theme) {
                    onSnippetTap(snippet)
                }
                // 붙여넣기 가능 상태로의 전환을 눈에 띄게 — 칩이 아래에서 떠오르며 커진다
                .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                .id(snippet.title)  // 다른 절로 바뀌면 새 칩으로 다시 애니메이션
            }
            if let onWordTap, !words.isEmpty {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    if index > 0 || snippet != nil {
                        Rectangle()
                            .fill(theme.keyText.opacity(0.2))
                            .frame(width: 1, height: 18)
                    }
                    // 후보는 남은 폭을 균등 분배 — Apple QuickType처럼 좌우가 꽉 찬다
                    Button(word) { onWordTap(word) }
                        .font(.system(size: 17))
                        .foregroundStyle(theme.keyText)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
            }
            if snippet == nil && words.isEmpty && state.pasteboardCode == nil {
                if state.visibleTools.isEmpty {
                    Text("글쇠")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.keyText.opacity(0.5))
                    Spacer()
                } else {
                    toolButtons  // 도구 행은 폭을 균등 분배해 우측 틈이 없다
                        .transition(.opacity)
                }
            } else if words.isEmpty {
                Spacer()  // 칩만 있을 때는 내용 크기 유지
            }
            if hasCandidates, let onDismissSuggestions {
                // 후보 내리기 — 도구 행으로 돌아간다 (사용자 요청 2026-09-03). 맨 오른쪽 고정.
                Button(action: onDismissSuggestions) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.keyText.opacity(0.6))
                        .frame(width: 30, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("후보 닫기")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: KeyboardRootView.toolbarHeight)
        // 칩 등장/퇴장에만 애니메이션 — 추천단어 후보는 키마다 바뀌므로 애니메이션을 걸지 않는다
        // (매 키 입력마다 툴바가 꿈틀거리면 산만하고 비용도 든다)
        .animation(.spring(duration: 0.28, bounce: 0.25), value: snippet?.title)
    }

    /// 도구 행 — 후보가 없을 때의 기본 툴바 내용 (PDR toolbar-tools). 아이콘·라벨은 `ToolbarTool`이 정한다
    /// (설정 앱 도구 행과 같은 아이콘·문구).
    @ViewBuilder
    private var toolButtons: some View {
        ForEach(state.visibleTools, id: \.self) { tool in
            toolButton(tool.symbolName, label: tool.displayName) {
                switch tool {
                case .cursorLeft: onCursorMove?(-1)
                case .cursorRight: onCursorMove?(+1)
                case .dismiss, .clipboard, .emoji: onToolTap?(tool)
                }
            }
        }
    }

    private func toolButton(
        _ symbol: String, label: String, action: @escaping () -> Void
    ) -> some View {
        // 배경 없이 아이콘만 (애플 툴바와 같은 감각 — 2026-09-02 사용자 요청). 터치 영역은
        // contentShape로 셀 전체를 잡는다 (.plain은 라벨의 불투명 픽셀만 히트 테스트한다).
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.keyText.opacity(0.85))
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// 채움글 후보 칩 — 제목 + 본문 첫 줄 미리보기. 탭하면 트리거가 전문으로 바뀐다.
private struct SnippetChip: View {

    let suggestion: SnippetSuggestion
    let theme: ResolvedTheme
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // 제목은 "[고린도전서 12:3]" 꼴, 본문 글자색 굵게 — accent(파랑)는 배경과
                // 대비가 약해 안 보인다는 피드백 (2026-09-03)
                Text("[\(suggestion.title)]")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.keyText)
                    .lineLimit(1)
                    .fixedSize()
                Text(previewLine)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.keyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.characterKey, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("채움글 \(suggestion.title) 붙여넣기")
    }

    private var previewLine: String {
        suggestion.body.split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? ""
    }
}

/// 자판 그리드. LayoutDefinition을 그리기만 한다.
struct KeyboardLayoutView: View {

    let state: KeyboardViewState
    let theme: ResolvedTheme
    let inputModeSwitchButton: AnyView?
    let onEvent: (KeyEvent) -> Void
    var onKeyPress: (() -> Void)? = nil
    /// 스페이스 트랙패드 모드의 문자 단위 커서 이동 (nil이면 기능 없음)
    var onCursorDrag: ((Int) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 7) {
                ForEach(Array(state.layout.rows.enumerated()), id: \.offset) { _, row in
                    rowView(row, totalWidth: geometry.size.width)
                }
            }
        }
    }

    private func rowView(_ row: [LayoutDefinition.Key], totalWidth: CGFloat) -> some View {
        let totalUnits = row.reduce(0) { $0 + $1.width }
        let spacing: CGFloat = 5
        let available = totalWidth - spacing * CGFloat(row.count - 1)
        return HStack(spacing: spacing) {
            ForEach(row) { key in
                keyView(key)
                    .frame(width: available * CGFloat(key.width) / CGFloat(totalUnits))
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func keyView(_ key: LayoutDefinition.Key) -> some View {
        if key.id == "globe" {
            // 시스템이 지구본을 요구하면 UIKit 버튼(다음 키보드 전환). 요구하지 않는 환경에서는
            // 조립 지점이 `layout(inputModeSwitchKey: false)`로 지구본 없는 하단 행을 넣으므로
            // 여기 오지 않는다 — 아래 빈 칸은 상태 갱신 사이의 과도기 방어용
            if state.needsInputModeSwitchKey, let button = inputModeSwitchButton {
                button
                    .modifier(KeyCapSurface(background: theme.functionKey, cornerRadius: theme.keyCornerRadius))
            } else {
                Color.clear.frame(width: 0)
            }
        } else if key.event == .spacer {
            // 스페이서 — 자리만 차지하고 표면·터치 없음 (단모음 3행 가운데 정렬)
            Color.clear.accessibilityHidden(true)
        } else {
            KeyCapView(
                // 리턴 키는 입력란 returnKeyType 표시로 덮어쓴다 (배열 데이터는 그대로)
                key: (key.event == .return && state.returnKey != nil)
                    ? key.relabeled(label: state.returnKey?.label, symbol: state.returnKey?.symbol)
                    : key,
                isShifted: state.isShifted,
                isCapsLocked: state.isCapsLocked,
                theme: theme,
                showsPreview: state.showsKeyPreview,
                onEvent: onEvent,
                onPress: onKeyPress,
                onCursorDrag: key.event == .space ? onCursorDrag : nil
            )
        }
    }
}
