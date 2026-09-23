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
    private let onBibleBadgeTap: (() -> Void)?
    private let onBibleRowTap: ((BibleSearchRow) -> Void)?
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
    ///   - onBibleBadgeTap: 툴바 성경 배지 — 검색 패널(화면 2)을 연다.
    ///   - onBibleRowTap: 검색 패널의 구절 행 — 기존 채움글 삽입 경로로 넣는다.
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
        onBibleBadgeTap: (() -> Void)? = nil,
        onBibleRowTap: ((BibleSearchRow) -> Void)? = nil,
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
        self.onBibleBadgeTap = onBibleBadgeTap
        self.onBibleRowTap = onBibleRowTap
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
                onDismissSuggestions: onDismissSuggestions,
                onBibleBadgeTap: onBibleBadgeTap
            )
            // 툴바도 자판과 같은 폭 안에 둔다. 자판만 좁히면 도구 아이콘 4개가 여전히 전폭에
            // 균등 분배돼 **자판 밖으로 삐져나온다.** 가로 아이패드에서는 커서 ◀▶ 사이가
            // 306pt(약 8cm)까지 벌어져 한 글자 고치는 데 손이 화면을 가로질렀다
            // (검증자 실측 REQ-4).
            .frame(maxWidth: areaMaxWidth)
            if state.showsBibleSearchPanel, let onBibleRowTap, let onBibleBadgeTap {
                BibleSearchPanelView(
                    query: state.bibleSearchQuery,
                    rows: state.bibleSearchRows,
                    theme: theme,
                    onRowTap: onBibleRowTap,
                    onClose: onBibleBadgeTap   // 토글 — 조립 지점이 패널을 닫는다
                )
                .frame(height: state.keyboardHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, 4)
                .frame(maxWidth: areaMaxWidth)
            } else if state.showsClipboardPanel, let onClipboardEntryTap, let onToolTap {
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
    let onBibleBadgeTap: (() -> Void)?

    var body: some View {
        let snippet = state.snippetSuggestion
        let words = state.wordSuggestions
        // ★ **배지는 여기 안 넣는다** — 배지만 떠 있을 때는 ✕가 없어야 한다 (사용자 결정 2026-09-21).
        //
        // 예전 주석은 *"배지만 떠 있을 때 내릴 방법이 없으면 안 된다"* 고 적었다. **전제가 틀렸다.**
        // 도구 행을 그리는 조건(아래 `:300` 부근)은 `snippet == nil && words.isEmpty &&
        // pasteSuggestion == nil` 뿐이고 **배지를 보지 않는다.** 그래서 배지 단독 상태에서는
        // 한 줄에 `[도구 4개] [📖 N]`이 **함께** 그려진다 — 커서·클립보드·이모지가 이미 화면에 있다.
        // 갇히지 않으므로 ✕가 필요 없고, 새 제스처도 필요 없다.
        //
        // 추천단어·채움글 칩·붙여넣기 칩의 ✕는 **그대로 남는다**(2026-09-03 사용자 요청) —
        // 그때는 후보가 도구 행 자리를 차지하므로 내릴 길이 ✕뿐이다.
        let hasCandidates = KeyboardMetrics.showsDismissButton(
            hasSnippet: snippet != nil,
            hasWords: !words.isEmpty,
            hasPaste: state.pasteSuggestion != nil
        )
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
        let centersChipOnly = (snippet != nil || state.pasteSuggestion != nil) && words.isEmpty
        return HStack(spacing: 10) {
            if centersChipOnly { Spacer(minLength: 0) }
            if let paste = state.pasteSuggestion, let onPasteboardCodeTap {
                PasteChip(suggestion: paste, theme: theme, action: onPasteboardCodeTap)
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
                        // 배지가 오른쪽 폭을 가져가므로 긴 후보는 줄여 넣는다 (계획서 2-1).
                        // 자르는 대신 줄이는 이유: 「창조하시니라」가 「창조하…」가 되면
                        // 무엇을 넣을지 알 수 없다.
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                }
            }
            if !hasCandidates {
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
            // ★ **후보가 있을 때만** 여기서 그린다 (v1.1.0 — 사용자 지시 2026-09-21).
            //
            // 후보가 없을 때(= 도구 행이 뜰 때)의 배지는 **도구 행 안**에 있다(`toolButtons`).
            // 이 조건을 빼면 같은 배지가 **두 번** 그려진다.
            if hasCandidates, let count = state.bibleMatchCount, let onBibleBadgeTap {
                bibleBadge(count: count, action: onBibleBadgeTap)
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

    /// 성경 검색 배지 — 건수가 있을 때만 그린다. **자리는 두 가지다** (v1.1.0).
    ///
    /// | 상태 | 자리 |
    /// |---|---|
    /// | 추천단어·칩이 있다 | **오른쪽 끝 고정**(✕ 왼쪽). 도구 행이 없으니 순서 개념도 없다 |
    /// | 배지만 뜬다(도구 행) | **도구 순서의 한 자리.** 사용자가 툴바 탭에서 끌어 옮긴다 |
    ///
    /// 기본 자리는 **이모지와 키보드 내리기 사이**다(`ToolbarTool.bibleSearch` 선언 자리).
    /// 두 자리가 **같은 뷰**(이 함수)를 쓰므로 999+ 표기도 접근성 라벨도 갈릴 수 없다.
    ///
    /// ## 왜 오른쪽인가 (계획서 2-1, 양보 불가)
    ///
    /// 왼쪽에 두면 배지가 떴다 사라질 때마다 **추천단어 전체가 매 타 54~78pt씩 옆으로 뛴다**
    /// (배지 폭 44.5~68.1pt + 간격 10pt). 오른쪽 끝이면 **1번 버튼의 왼쪽 모서리만** 그대로다 —
    /// *"추천단어의 시작 자리가 그대로다"* 는 그 한 점에 대해서만 참이다.
    ///
    /// ## ★ 자리 예약은 되돌렸다 (2026-09-21 저녁 → 밤)
    ///
    /// 낮에 **배지 자리를 항상 비워 두는** 안을 넣었다. **사용자가 실기에서 보고 판정했다:**
    ///
    /// > 「호산ㄴ 까지 타이핑 하면 맨 오른쪽이 빈 여백으로 나오는데 … **맨 오른쪽이 비어보여서
    /// >  이상하다** … 없을때에는 전에 처럼 여백을 없애라」
    ///
    /// 그래서 **배지가 없으면 아무것도 차지하지 않는다.** 추천단어는 배지가 뜰 때만 2개다.
    ///
    /// ## ★ 되살아난 위험 — 표는 남겨 둔다
    ///
    /// 배지가 뜨는 순간 추천단어 분배가 다시 계산된다.
    ///
    /// **★ 2026-09-21 정정 — 예전 표의 화면 폭이 틀렸다.** 「379pt(15 Pro)」로 적혀 있었는데
    /// 379는 **패널 폭**(padding 뺀 값)이고 **화면 폭은 393pt**다. 그 값을 툴바 계산에 쓰고
    /// padding을 **또** 뺐다(반론자1 A-4가 자기 값이었다고 정정). SE도 361이 아니라 **375pt**다.
    /// 배지 폭은 텍스트 계측이라 그대로 맞다.
    ///
    /// **계산 과정 — 숫자만 적으면 다음 사람이 또 틀린다:**
    ///
    /// ```
    /// 안쪽 폭  = 화면 폭 - padding(.horizontal, 10) × 2
    /// 나눌 폭  = 안쪽 폭 - 요소 사이 spacing(10) 합 - ✕(30) - 배지 폭
    /// 한 칸    = 나눌 폭 / 후보 수            (.frame(maxWidth: .infinity) 균등 분배)
    /// ```
    ///
    /// **iPhone 15 Pro — 화면 393pt, 안쪽 373pt. 배지 없을 때 한 칸 104.3pt:**
    ///
    /// | 배지 | 폭 | 1번 중심 이동 | 2번 중심 이동 | 3번 자리 겹침 |
    /// |---|---|---|---|---|
    /// | `[📖 9]` | 44.5pt | +15.0pt | **+44.9pt** | 44.5pt = **43%** |
    /// | `[📖 137]` | 60.1pt | +11.1 | +33.2 | 60.1pt = **58%** |
    /// | `[📖 999+]` | 68.1pt | +9.1 | +27.2 | 68.1pt = **65%** |
    ///
    /// **iPhone SE — 화면 375pt, 안쪽 355pt. 한 칸 98.3pt:** 겹침 45% / 61% / **69%**.
    ///
    /// ★ **배지 최소 폭을 44.0 → 44.5pt로 고쳤다** (2026-09-22, 검증자 실측).
    /// 두 파일이 44.0과 44.5로 갈려 있었다. 검증자가 실기에서 **두 번 독립 실행해 61.0pt**를
    /// 얻었고 같은 CoreText 계산이 **61.36pt**(517건)를 냈다 — 오차 0.36pt다.
    /// 그 모형이 한 자리 라벨에 주는 값이 **44.45pt**이므로 44.5 쪽이 맞다.
    /// 44.0은 출처가 적혀 있지 않은 값이었고, 같은 표를 만든 계산이 **배지를 균등 분배로**
    /// 보는 오류를 이미 한 번 냈다(검증자 0-1절).
    /// **결론은 안 바뀐다** — 위 세 칸이 +15.1 → +15.0 · +45.2 → +44.9 · 42% → 43%로 움직였을 뿐이다.
    ///
    /// **3번 추천단어를 누르려는 사이 배지가 그 자리에 와서 성경 패널이 열릴 수 있다.**
    ///
    /// ## ★★ 도구 행 겹침 — **구조가 바뀌어 표를 다시 냈다** (2026-09-21 밤)
    ///
    /// 반론자1 A-5가 잰 「배지가 마지막 도구를 79~100% 덮는다」는 **배지가 도구 행 *바깥*에
    /// 붙어 있던 때의 값**이다. 사용자가 실기에서 그것을 「답답함」으로 겪고 순서 편입을
    /// 요청하면서 구조가 바뀌었다 — 이제 배지는 도구 행 **안의 한 칸**이다.
    ///
    /// **그래도 자리는 여전히 움직인다.** 0건이면 칸을 없애기로 했기 때문이다(아래).
    /// 아래는 **기본 순서**(`◀ ▶ 클립 이모지 📖 내리기`)·15 Pro(393pt)·배지 `999+`에서
    /// 다시 계산한 값이다.
    ///
    /// **전체 접근 ON — 도구 칸 66.6 → 51.0pt:**
    ///
    /// | 도구 | 중심 이동 | 옛 자리를 배지가 덮는 양 |
    /// |---|---|---|
    /// | ◀ | -7.8pt | 0% |
    /// | ▶ | -23.4pt | 0% |
    /// | 클립보드 | -39.1pt | 0% |
    /// | **이모지** | **-54.7pt** | **79%** |
    /// | 키보드 내리기 | +7.8pt | **8%** |
    ///
    /// **전체 접근 OFF — 66.2pt:** 이모지 -48.8pt·**57%**, 내리기 +9.8pt·11%.
    ///
    /// ## 무엇이 나아졌고 무엇이 남았나
    ///
    /// - **나아짐:** 맨 오른쪽 도구가 **100% → 8%**다. 예전에는 「키보드 내리기」를 누르려다
    ///   성경 패널이 열렸다. 더 중요한 것은 **사용자가 자리를 옮길 수 있다**는 점이다 —
    ///   위험한 이웃이 싫으면 📖를 다른 데로 끌면 된다. 오른쪽 고정에는 그 길이 없었다
    /// - **남음:** 배지 **바로 앞** 도구가 79%(FA ON) 덮인다. 자리만 옮겨 갔지 사라지지 않았다.
    ///   근본 원인은 **0건이면 칸을 없애는 것**이고, 그것은 사용자가 같은 날 추천단어 줄에서
    ///   빈 칸을 직접 물린 결과다(`bible-badge-slot-revert.md`). **대가를 알고 고른 것이다**
    ///
    /// ★ **화면에서 확인하지 않았다 — 기하 계산뿐이다.** 되돌아갈 후보(0건에도 빈 칸 유지)는
    /// `docs/design-reviews/bible-badge-tool-order.md`에 남겨 두었다.
    ///
    /// ## 추천단어 쪽(오른쪽 끝 고정)은 위 표가 그대로다
    ///
    /// 후보가 있을 때는 도구 행이 없으므로 배지가 여전히 오른쪽 끝이고,
    /// 3번 추천단어 겹침 42~69%도 그대로다.
    private func bibleBadge(count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            badgeCapsule(label: BibleCountText.label(count))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // ## ★ 낭독 문장은 **도구 이름에서 시작한다** (검증자 #12, 2026-09-22)
        //
        // 전에는 「성경 구절 9건, 검색 열기」였다. 그런데 설정에서 켜는 기능의 이름은
        // **「단어로 구절 찾기」**다 — VoiceOver 사용자가 *자기가 켠 그것*과 화면의 이것을
        // **같은 것으로 못 알아본다.** 그래서 이름을 **문자열로 박지 않고** 도구 정의에서 가져온다.
        // 이름이 또 바뀌면 여기도 따라 바뀐다(이번에 이름이 두 번 바뀐 것이 그 근거다).
        //
        // ## 세 토막으로 끊은 이유
        //
        // 「단어로 구절 찾기, 9건, 목록 열기」 — **무엇 / 얼마나 / 누르면 무엇**이다.
        // 「단어로 구절 찾기 9건」처럼 붙이면 *「단어로 구절 찾기」가 9건*으로 들려 뜻이 뒤집힌다.
        // 쉼표가 그 오해를 끊는다.
        //
        // 「검색 열기」를 **「목록 열기」**로 바꿨다 — 이름에서 「검색」이 사라졌는데 동작 설명에만
        // 남기면 **세 번째 용어**가 된다. 실제로 열리는 것도 구절 **목록**이다.
        // 개수 표기(`spokenCount`)는 배지·패널 칩과 같은 규칙 그대로다.
        //
        // ★ 문장 조립은 `BibleCountText`에 있다 — **UITests가 같은 앞부분을 술어로 쓴다.**
        //   여기서 문자열을 직접 만들면 그 둘이 또 갈린다(그것이 이번 고장의 원인이었다).
        .accessibilityLabel(BibleCountText.badgeAccessibilityLabel(count: count))
    }

    private func badgeCapsule(label: String) -> some View {
        // 표기 규칙은 `BibleCountText` 한 곳에 있다 — 패널의 「전체」 칩과 **같은 규칙**을 써야
        // 둘이 다른 말을 하지 않는다(2026-09-21: 배지 999+ / 패널 전체(1000) 불일치를 닫았다).
        HStack(spacing: 3) {
            Image(systemName: "book")
                .font(.system(size: 12, weight: .semibold))
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                // 숫자가 바뀔 때 폭이 흔들리지 않게 — 옆의 추천단어가 따라 흔들린다
                .monospacedDigit()
        }
        .foregroundStyle(theme.keyText)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(theme.functionKey, in: Capsule())
    }

    /// 도구 행 — 후보가 없을 때의 기본 툴바 내용 (PDR toolbar-tools). 아이콘·라벨은 `ToolbarTool`이 정한다
    /// (설정 앱 도구 행과 같은 아이콘·문구).
    @ViewBuilder
    private var toolButtons: some View {
        ForEach(state.visibleTools, id: \.self) { tool in
            if tool == .bibleSearch {
                bibleBadgeCell
            } else {
                toolButton(tool.symbolName, label: tool.displayName) {
                    switch tool {
                    case .cursorLeft: onCursorMove?(-1)
                    case .cursorRight: onCursorMove?(+1)
                    case .dismiss, .clipboard, .emoji: onToolTap?(tool)
                    case .bibleSearch: break   // 위 분기가 잡는다
                    }
                }
            }
        }
    }

    /// 도구 행 **안**의 성경 배지 (v1.1.0).
    ///
    /// ## ★ 같은 뷰를 쓴다
    ///
    /// 오른쪽 끝 고정일 때와 **완전히 같은 `bibleBadge(count:action:)`** 이다.
    /// 999+ 표기(`BibleCountText`)도 접근성 라벨도 한 곳에서 나오므로 두 자리가 다른 말을 할 수 없다.
    ///
    /// ## ★ 왜 다른 도구처럼 `maxWidth: .infinity` 칸을 안 쓰나
    ///
    /// 아이콘 도구는 20pt 글리프라 칸이 좁아져도 멀쩡하지만, 배지는 캡슐이라 **글자가 들어가야 한다**
    /// (`999+`가 68.1pt). 6칸 균등 분배면 SE(375pt)에서 한 칸이 약 51pt라 캡슐이 잘린다.
    /// 그래서 배지는 **제 크기를 먼저 가져가고**(`layoutPriority`) 남은 폭을 아이콘 다섯이 나눈다 —
    /// 아이콘 쪽은 그래도 40pt대라 넉넉하다.
    ///
    /// ★ **SE에서 실제로 어떻게 보이는지는 확인하지 못했다**(실기·시뮬레이터 금지).
    @ViewBuilder
    private var bibleBadgeCell: some View {
        if let count = state.bibleMatchCount, let onBibleBadgeTap {
            bibleBadge(count: count, action: onBibleBadgeTap)
                .frame(minHeight: 38)
                .layoutPriority(1)
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

/// 붙여넣기 칩 — 복사한 내용을 **한 줄**로 보여 주고, 탭하면 넣는다.
///
/// ## 두 모양이 한 칩을 쓴다
///
/// - **인증번호**: 번호만. 예전 모양 그대로다(고정폭 숫자, accent 색) — 회귀를 만들지 않는다.
/// - **일반 텍스트**: `복사됨` 라벨 + 내용 미리보기.
///   사용자가 준 예시는 `'복사했어요 맘에 드십니...'` 였고, **문구는 2026-09-15 사용자 지시로 `복사됨`으로 바꿨다.**
///
/// ## 왜 라벨을 붙이나
///
/// 사용자 예시를 **앞부분이 라벨이고 뒤가 내용**으로 읽었다(2026-09-15 구현자 판단).
/// 그 읽기는 사용자가 확인했다 — 문구만 `복사됨`으로 바꾸라고 했다.
/// 근거 둘 — (1) 라벨이 있으면 이 칩이 **왜 갑자기 떴는지**를 사용자가 안다.
/// (2) 바로 옆 `SnippetChip`이 이미 `[제목] 본문 미리보기` 구조라 시각적으로 일관된다.
/// 다만 **대괄호는 쓰지 않는다** — 사용자 예시에 없었다.
/// 틀렸으면 이 뷰 한 곳만 고치면 된다.
///
/// **보이는 것과 넣는 것이 다르다** — 미리보기는 잘리고 넣는 것은 원문 전체다.
/// 그래서 잘렸다는 사실을 말줄임표로 반드시 알린다(`PasteSuggestion.previewLine`).
private struct PasteChip: View {

    let suggestion: PasteSuggestion
    let theme: ResolvedTheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                if suggestion.kind == .text {
                    Text("복사됨")
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(suggestion.preview)
                    .font(suggestion.kind == .verificationCode
                          ? .system(size: 14, weight: .semibold).monospacedDigit()
                          : .system(size: 14))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // ★ 글자색은 `keyText`다 — `accent`가 아니다 (2026-09-15 사용자 보고).
            //
            // **같은 실수가 두 번째다.** 바로 위 `SnippetChip`이 2026-09-03에 똑같은 피드백으로
            // 이미 고쳤는데("accent(파랑)는 배경과 대비가 약해 안 보인다"), 이 칩은 2026-09-15에
            // 새로 만들면서 그 교훈을 못 받고 `accent`로 갔다. 다크 테마에서 파란 글자가
            // `characterKey` 배경에 묻혀 안 보인다는 보고가 그대로 다시 왔다.
            //
            // **배경이 `characterKey`면 글자는 `keyText`다.** 팔레트가 배경 < 기능 키 < 문자 키
            // 3단계 대비를 보장하는 짝이 그 둘이고(CLAUDE.md), `accent`는 그 대비 보장 밖이다 —
            // 테마마다 값이 달라 어떤 테마에서는 우연히 보이고 어떤 테마에서는 묻힌다.
            // 칩을 구분하는 일은 색이 아니라 클립보드 아이콘과 「복사됨」 라벨이 한다.
            .foregroundStyle(theme.keyText)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.characterKey, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// 화면에 잘려 보이더라도 **읽어 줄 때는 미리보기 전체**를 읽는다 — 잘린 곳에서 끊기면
    /// 무엇을 붙여넣는지 알 수 없다. (원문 전체가 아니라 미리보기다 — 문단을 다 읽지 않는다.)
    private var accessibilityLabel: String {
        switch suggestion.kind {
        case .verificationCode: "복사한 인증번호 \(suggestion.preview) 붙여넣기"
        case .text: "복사한 내용 \(suggestion.preview) 붙여넣기"
        }
    }
}

/// 채움글 후보 칩 — 제목 + 본문 첫 줄 미리보기. 탭하면 단축어가 전문으로 바뀐다.
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
