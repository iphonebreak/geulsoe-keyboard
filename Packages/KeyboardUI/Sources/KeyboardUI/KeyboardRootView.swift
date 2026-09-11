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

    /// 이 자판 배열에서 자판 영역(자판·이모지·클립보드·툴바)이 가질 수 있는 최대 폭.
    /// 넘으면 가운데 정렬하고 좌우는 배경색으로 둔다. 규칙과 근거는 `KeyboardMetrics`에 있다.
    ///
    /// **idiom이 아니라 폭 규칙이다** — KeyboardUI는 아이패드를 모른다(의존성 규칙).
    /// 아이폰 폭(320~440pt)은 모든 자판의 상한 아래라 아이폰에는 아무 영향이 없다.
    /// **조립 지점의 높이 계산이 같은 값을 되짚으므로 둘이 갈라지면 종횡비가 어긋난다.**
    private var areaMaxWidth: CGFloat {
        KeyboardMetrics.contentMaxWidth(for: state.layout)
    }

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

    /// **상자를 전부 채우고 내용은 하단 정렬한다** (14차 H1, 기본 `false` = 기존 동작).
    ///
    /// 조립 지점이 SwiftUI 호스트를 입력 뷰 **전체**에 붙일 때 켠다. 시스템이 등장 직전 입력 뷰를
    /// 과대한 높이(실기 852pt)로 잡는 구간에, 기존의 "하단 고정 높이" 방식은 **위쪽이 빈 채**로 남아
    /// 그 자리에 시스템 반투명 백드롭이 비친다 — 그것이 사용자가 보는 판이라는 것이 H1이다.
    ///
    /// 켜면 루트가 상자 높이를 전부 차지하고 **내용(툴바+자판)은 `Spacer`로 아래에 붙는다.**
    /// 과거 실패 기록("위아래로 늘려 붙이면 자판이 가운데 정렬돼 화면 절반을 덮었다 튀어 내려온다")은
    /// **가운데 정렬** 때문이었다 — 여기서는 정렬을 `.bottom`으로 못박아 그 실패를 피한다.
    /// 자판 자체의 크기는 `state.keyboardHeight` 고정이라 **키 크기·배열은 바뀌지 않는다.**
    private let fillsContainer: Bool

    /// **상자 위쪽을 칠하지 않는다** (16차, 기본 `false` = 기존 동작).
    ///
    /// `fillsContainer`는 상자 **전체**를 테마 색으로 칠했다. 그런데 시스템이 입력 뷰를 과대하게
    /// 잡는 구간에는 그 칠이 곧 **화면을 덮는 단색 판**이 된다(검증자 실측: 852pt 중 555pt가 단색).
    /// 켜면 배경을 **내용(툴바+자판) 뒤에만** 칠하고 그 위는 **투명하게** 둔다 —
    /// 그 자리에는 시스템 키보드 백드롭이 그려진다(그것이 정상 등장의 모습이다).
    private let transparentAbove: Bool

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
    ///   - fillsContainer: 상자를 전부 채우고 내용을 **하단 정렬**한다 (14차 H1). 기본 `false` = 기존 동작.
    ///   - transparentAbove: 배경을 **내용 뒤에만** 칠하고 그 위는 투명하게 둔다 (16차). 기본 `false` = 기존 동작.
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
        onDismissSuggestions: (() -> Void)? = nil,
        fillsContainer: Bool = false,
        transparentAbove: Bool = false
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
        self.fillsContainer = fillsContainer
        self.transparentAbove = transparentAbove
    }

    private var theme: ResolvedTheme {
        ResolvedTheme(spec: state.themeSpec, appearance: state.appearance, systemColorScheme: colorScheme)
    }

    public var body: some View {
        let theme = self.theme
        if fillsContainer {
            // **H1 — 상자를 전부 채우고 내용은 아래로.**
            // `Spacer`가 남는 높이를 전부 먹고, 내용은 제 높이 그대로 하단에 붙는다.
            // `alignment: .bottom`까지 못박아 과대 상자에서도 가운데로 뜨지 않게 한다.
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                // **16차** — 칠은 여기(내용 뒤)까지다. 위쪽은 아래 `.background`가 정한다.
                content(theme: theme)
                    .background(theme.keyboardBackground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // `transparentAbove`면 상자 위쪽은 **투명** — 그 자리에 시스템 백드롭이 그려진다.
            // 아니면 14차처럼 상자 전체를 테마 색으로 칠한다.
            .background(transparentAbove ? Color.clear : theme.keyboardBackground)
        } else {
            content(theme: theme)
                .background(theme.keyboardBackground)
        }
    }

    /// 툴바 + 자판/패널. 자기 높이는 내용이 정한다(`toolbarHeight` + `state.keyboardHeight` + 여백).
    @ViewBuilder
    private func content(theme: ResolvedTheme) -> some View {
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
            // 툴바도 자판과 같은 폭 안에 둔다. 자판만 좁히면 도구 아이콘 4개가 여전히 전폭에
            // 균등 분배돼 **자판 밖으로 삐져나온다.** 가로 아이패드에서는 커서 ◀▶ 사이가
            // 306pt(약 8cm)까지 벌어져 한 글자 고치는 데 손이 화면을 가로질렀다
            // (검증자 실측 REQ-4).
            .frame(maxWidth: areaMaxWidth)
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
                .frame(maxWidth: areaMaxWidth)
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
                .frame(maxWidth: areaMaxWidth)
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
                .frame(maxWidth: areaMaxWidth)
            }
        }
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
        // **칩만 있을 때는 가운데 정렬한다** (사용자 요청 2026-09-11, 사장님 결정 5).
        //
        // 기준은 **닫기(✕)를 제외한 콘텐츠 영역의 가운데**다 — ✕는 오른쪽 끝에 그대로 두고
        // 그 왼쪽 영역에서 칩을 가운데로 모은다. 화면 전체의 정확한 중앙이 아니라는 것을
        // 명시해 둔다(반론자 E가 지적한 구분).
        //
        // **추천단어가 함께 있거나 추천단어만 있을 때는 건드리지 않는다** — 그 경우 후보가
        // `maxWidth: .infinity`로 남은 폭을 균등 분배한다(Apple QuickType 방식). 여기에
        // 선행 `Spacer`를 넣으면 그 분배가 깨진다. 도구 행도 지금 그대로다.
        //
        // **칩이 실제로 있을 때만** 켠다. 후보가 하나도 없는 경우(도구 행·"글쇠" 자리 표시)도
        // `words.isEmpty`라서, 그 조건만 보면 도구 행이 선행 `Spacer`에 눌려 회귀한다.
        let centersChipOnly = (snippet != nil || state.pasteboardCode != nil) && words.isEmpty
        return HStack(spacing: 10) {
            if centersChipOnly { Spacer(minLength: 0) }
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
                    // 도구 행은 남은 폭을 균등 분배하되, 버튼 하나가 아이폰에서보다 넓어지지는
                    // 않게 묶고 가운데로 모은다 (REQ-4). 아이폰은 상한에 걸리지 않아 그대로다.
                    // 추천단어 후보의 균등 분배는 손대지 않는다 — 규칙이 다른 두 콘텐츠다.
                    HStack(spacing: KeyboardMetrics.toolButtonSpacing) {
                        toolButtons
                    }
                    .frame(maxWidth: KeyboardMetrics.toolRowMaxWidth(count: state.visibleTools.count))
                    .frame(maxWidth: .infinity)
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
        let spacing = KeyboardMetrics.keySpacing
        // **음수 방어.** 등장 첫 레이아웃 패스에서는 `geometry.size.width`가 0으로 온다.
        // 그때 `0 − 5 × 9 = −45`가 키 폭으로 들어가 SwiftUI가
        // `Invalid frame dimension (negative or non-finite)`를 수십 줄 뱉고 자판이 빈 회색으로 떴다
        // (전체 접근을 켠 직후 등장에서 재현, 2026-09-09 — 검증자가 두 번 목격한 증상).
        // 폭이 확정되면 다음 패스에서 제대로 그려지므로, 여기서는 0으로 눌러 두기만 하면 된다.
        let available = max(0, totalWidth - spacing * CGFloat(max(0, row.count - 1)))
        return HStack(spacing: spacing) {
            ForEach(row) { key in
                keyView(key)
                    .frame(width: totalUnits > 0 ? available * CGFloat(key.width) / CGFloat(totalUnits) : 0)
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
