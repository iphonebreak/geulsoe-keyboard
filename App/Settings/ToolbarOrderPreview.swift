import SwiftUI
import TadakDomain

/// 툴바 도구 미리보기 — **실물 툴바와 같은 가로 한 줄**에서 on/off와 순서를 함께 다룬다.
///
/// 사용자 요청(2026-09-14): *"툴바는 수평 배치인데 설정은 수직으로 배치하여 순서 변경하는게
/// 사용자 보기에는 불편함."* 세로 `Toggle` 리스트 + `.onMove`를 이 컴포넌트가 **대체한다** —
/// 남겨 두면 같은 것을 두 군데서 조작하게 되고, 불편하다고 한 세로 리스트가 그대로 남는다.
///
/// 설계: `docs/design-reviews/toolbar-order-ui.md`(★ 최종 결정 절) ·
/// `docs/design-reviews/toolbar-order-ui-design.md`(치수·색·상태·접근성) ·
/// 시안 `docs/design-reviews/evidence/toolbar-order-ui/*.png`
///
/// **KeyboardUI를 import하지 않는다.** 조립 지점(설정 앱)에서 스타일 상수를 미러링한다 —
/// `MockKeyboardView.swift`와 같은 규율이다.
/// mirror: 아이콘 20pt medium (`KeyboardUI.KeyboardRootView.toolButton`). **이 하나뿐이다** —
/// 나머지 치수(스트립 56·셀 44·간격 6·배지)는 이 화면 전용 신규 설계라 미러가 아니다.
///
/// **저장 스키마를 바꾸지 않는다** — `toolOrder`/`disabledTools`를 그대로 읽고 쓴다.
/// 디코더의 `toolOrderMigratedV101` 1회성 전환도 건드리지 않는다(이미 있다).
struct ToolbarOrderPreview: View {

    @Binding var settings: KeyboardSettings
    /// 오른쪽 위 "순서 편집" 버튼이 켜는 모드. 드래그는 **이 모드에서만** 붙는다.
    let isEditing: Bool
    /// ★ **여기서 못 끄는 도구를 눌렀다** — 조립 지점(`ToolbarTab`)이 토스트로 알린다.
    ///
    /// 전에는 그 탭이 **조용히 죽어 있었다.** `toggle()`이 `.bibleSearch`를 무시하므로
    /// 눌러도 아무 일이 없고, 섹션 푸터는 「아이콘을 눌러 도구를 ON/OFF」라고 말한다 —
    /// 그 도구에서만 **거짓**이다. 특히 평소 모드에서 헷갈린다(그때는 다른 도구가 실제로 켜지고 꺼진다).
    ///
    /// **토스트를 여기서 그리지 않는다.** 이 뷰는 스트립 하나만 그리는 부품이고,
    /// 토스트는 화면 전체에 얹히는 것이라 조립 지점의 몫이다.
    var onBlockedToggle: (ToolbarTool) -> Void = { _ in }

    /// 📖만 여기서 못 끄는 이유를 말하는 **한 문장**. 화면(토스트)과 낭독(접근성 값)이
    /// **같은 말**을 쓰게 한 곳에 둔다 — 둘이 갈리면 두 사용자가 다른 안내를 받는다.
    ///
    /// 두 값의 차이는 **구두점뿐**이다. VoiceOver는 `>`를 「보다 큼」으로 읽거나 건너뛰므로
    /// 낭독용은 쉼표로 끊는다.
    static let bibleSwitchHint = "채움글 > 성경에서 켜고 꺼요"
    static let bibleSwitchHintSpoken = "채움글, 성경에서 켜고 꺼요"

    /// 끌고 있는 도구와 그 순간의 x 이동량. 셀 하나를 지날 때마다 자리를 바꾸고 offset을 그만큼 뺀다.
    @State private var draggingTool: ToolbarTool?
    @State private var dragOffset: CGFloat = 0
    /// 지금 겨누고 있는 자리를 **시작 자리로부터 몇 칸**으로 들고 있다. 경계 이력(hysteresis)의
    /// 기준점이라 상태가 필요하다.
    ///
    /// **절대 인덱스가 아니라 상대 칸수인 이유.** 예전엔 `dragStartIndex`(시작 자리)와
    /// `dragTargetIndex`(목표 자리)를 절대값으로 들고 있었다. 그런데 드래그 도중
    /// 「기본 순서로 되돌리기」나 VoiceOver `move(_:by:)`가 순서를 바꾸면 두 값이 **stale**이 되어,
    /// 오른쪽으로 한 칸 끌었는데 엉뚱한 자리로 확정됐다(지적 1). 확정 시점에 시작 자리만 다시
    /// 읽어도 목표가 여전히 옛 시작 기준이라 고쳐지지 않는다 — 그래서 **목표를 상대값으로** 바꿨다.
    /// "한 칸 오른쪽"은 배열이 어떻게 바뀌어도 뜻이 변하지 않는다.
    @State private var dragStepDelta: Int = 0

    /// **제스처가 살아 있는 동안에만 참인 값. 취소돼도 반드시 거짓으로 돌아온다.**
    ///
    /// 위 네 개는 평범한 `@State`라 우리가 지워야 하는데, `onEnded`는
    /// *성공했을 때만* 온다 — 애플 원문: *"The onEnded action is only performed if the gesture
    /// ends successfully… To track state that must reset regardless of whether the gesture
    /// succeeds or is cancelled, use a **@GestureState** property."*
    ///
    /// 전화·알림·잠금·회전, 또는 다른 손가락이 「완료」를 눌러 `.gesture(isEditing ? … : nil)`이
    /// nil이 되면 제스처는 **취소**된다. 그때 `onEnded`는 오지 않으므로, 이것 없이는
    /// 끌던 셀이 1.12배 확대 + 그림자를 단 채 굳고 이웃은 offset −step으로 겹친 채 남는다
    /// (`RootView`가 TabView라 탭을 옮겨도 `@State`가 살아 있어 안 풀린다).
    ///
    /// **`onDisappear`나 `isEditing` 변화 감시로 때우지 않는다** — 인터럽트 종류마다 구멍이 남는다.
    /// SwiftUI 제스처 생명주기가 직접 주는 이 신호 하나가 **모든 취소 경로**를 덮는다.
    @GestureState private var isDragActive = false

    /// 스트립의 좌표계 이름. **셀이 아니라 스트립을 기준으로 드래그를 잰다** — 이유는 `reorderGesture` 주석.
    private static let stripSpace = "toolbar-order-strip"

    // MARK: 치수 (디자인 문서 2.1)

    private enum Metrics {
        static let stripHeight: CGFloat = 56
        static let stripCorner: CGFloat = 14
        static let stripInset: CGFloat = 8
        static let cellHeight: CGFloat = 44
        static let cellMaxWidth: CGFloat = 84
        static let cellCorner: CGFloat = 12
        static let cellSpacing: CGFloat = 6
        /// mirror: KeyboardRootView.toolButton — 실물 툴바와 같은 값
        static let iconSize: CGFloat = 20
        static let badgeDiameter: CGFloat = 16
        static let lockDiameter: CGFloat = 17
        static let labelTopSpacing: CGFloat = 6
    }

    /// 스트립에 **보이는** 도구들.
    ///
    /// ★ 꺼진 📖은 목록에 없다 (사용자 지시 2026-09-22 — 전날의 「흐리게 보여 준다」를 뒤집었다).
    /// **저장은 `persist(visibleOrder:)`를 거쳐야 한다** — 이 목록을 그대로 `toolOrder`에 쓰면
    /// 안 보이는 도구가 배열에서 사라진다.
    private var tools: [ToolbarTool] { settings.toolsShownInOrderEditor() }

    /// 이름표 두 줄이 들어갈 높이. `@ScaledMetric` 이 사용자 글자 크기에 맞춰 늘려 준다.
    /// 기준 30 은 기본 크기에서 `.caption2` 두 줄이 들어가던 값이라 **일반 크기 화면은 그대로다.**
    @ScaledMetric(relativeTo: .caption2) private var labelBoxHeight: CGFloat = 30

    var body: some View {
        GeometryReader { proxy in
            let width = cellWidth(forStripWidth: proxy.size.width)
            VStack(spacing: Metrics.labelTopSpacing) {
                strip(cellWidth: width)
                labels(cellWidth: width)
            }
        }
        // GeometryReader는 높이를 스스로 정하지 못하므로 바깥에서 고정한다.
        //
        // **이름표 칸은 Dynamic Type 을 따라 늘어난다.** 예전엔 상수 30 이라 글자를 키운 사용자에게
        // 이름표가 "왼… 오… 클… 이… 키…" 로 잘렸다 — **왼과 오가 서로 구분도 안 됐다**(반론자 O-2).
        // 디자이너가 "아이콘만 두면 무슨 도구인지 모른다"며 지켜낸 정보가 **글자를 키운 사용자에게서
        // 정확히 사라지는** 상태였다. VoiceOver 는 셀 라벨이 `displayName` 전체라 영향이 없었고,
        // 잃는 쪽은 시각 사용자였다.
        .frame(height: Metrics.stripHeight + Metrics.labelTopSpacing + labelBoxHeight)
        .animation(.easeInOut(duration: 0.25), value: isEditing)
        // **취소 경로의 리셋 지점.** `@GestureState`는 제스처가 성공하든 취소되든 초기값으로
        // 돌아오므로, false로 떨어지는 순간을 보고 평범한 `@State` 넷을 함께 지운다.
        // 성공했을 때는 `onEnded`가 먼저 확정한 뒤 여기로 오고, `resetDragState`는 멱등하다.
        .onChange(of: isDragActive) { _, active in
            if !active { resetDragState(animated: true) }
        }
    }

    // MARK: 스트립

    private func strip(cellWidth: CGFloat) -> some View {
        HStack(spacing: Metrics.cellSpacing) {
            ForEach(tools, id: \.self) { tool in
                cell(tool, width: cellWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.stripHeight)
        // 드래그를 재는 기준 좌표계. 스트립은 셀이 재배열돼도 움직이지 않는다 — 그것이 요점이다.
        .coordinateSpace(name: Self.stripSpace)
        .background(
            RoundedRectangle(cornerRadius: Metrics.stripCorner, style: .continuous)
                .fill(Color(.secondarySystemFill))
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.stripCorner, style: .continuous)
                        .fill(Color.accentColor.opacity(isEditing ? 0.10 : 0))
                }
        )
    }

    /// 셀 하나.
    ///
    /// ## ★ 📖 셀은 **끌 수는 있고 끌 수는 없다** (v1.1.0)
    ///
    /// 「끌어서 옮기기」는 되고 「탭해서 끄기」는 안 된다. 켜고 끄는 것은 채움글 > 성경이 정한다.
    ///
    /// **꺼져 있으면 스트립에 아예 안 보인다** (사용자 지시 2026-09-22).
    /// 전날에는 「흐리게 보여 준다」였다 — *켰을 때 어디 나타날지 미리 알 수 있다*가 근거였는데
    /// **사용자가 뒤집었다.** 그래서 켜야 보이고, 보일 때 자리는 `toolOrder`가 정한 자리다.
    ///
    /// ★ 안 보이는 동안에도 **저장에는 남아 있다** — `persist(visibleOrder:)` 참조.
    /// 그래서 껐다 다시 켜도 끌어 둔 자리가 그대로다.
    ///
    /// **누르는 도중 서브트리 구조를 바꾸지 않는다** (CLAUDE.md 2026-09-05 트랙패드 버그와 같은 이유).
    /// 켜짐/꺼짐·집힘·편집 모드를 전부 **배경·테두리·transform·투명도**로만 표현한다.
    /// `if`로 아이콘을 갈아끼우거나 오버레이를 넣고 빼면 진행 중인 터치가 제스처에서 떨어진다.
    private func cell(_ tool: ToolbarTool, width: CGFloat) -> some View {
        let enabled = isOn(tool)
        let dragging = draggingTool == tool

        return Image(systemName: tool.symbolName)
            .font(.system(size: Metrics.iconSize, weight: .medium))
            .foregroundStyle(enabled ? Color(.label) : Color(.label).opacity(0.28))
            .frame(width: width, height: Metrics.cellHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.cellCorner, style: .continuous)
                    .fill(enabled ? Color(.secondarySystemGroupedBackground) : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.cellCorner, style: .continuous)
                            .strokeBorder(Color(.separator), lineWidth: enabled ? 0 : 1)
                    }
            )
            .overlay(alignment: .topLeading) { orderBadge(tool, enabled: enabled) }
            .overlay(alignment: .bottomTrailing) { lockBadge(tool) }
            .scaleEffect(dragging ? 1.12 : 1)
            .shadow(color: .black.opacity(dragging ? 0.25 : 0), radius: dragging ? 10 : 0, y: dragging ? 4 : 0)
            // 끌리는 셀은 손가락을, 나머지는 비켜 준 자리를 **offset으로만** 표현한다.
            // 드래그 중에 `ForEach`의 순서를 바꾸지 않는 것이 이 설계의 핵심이다 (`reorderGesture` 주석).
            .offset(x: dragging ? dragOffset : displacement(of: tool, step: width + Metrics.cellSpacing))
            .animation(dragging ? nil : .spring(response: 0.22, dampingFraction: 0.85), value: dragStepDelta)
            .zIndex(dragging ? 1 : 0)
            .contentShape(Rectangle())
            .onTapGesture { toggle(tool) }
            .gesture(isEditing ? reorderGesture(tool, cellWidth: width) : nil)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tool.displayName)
            .accessibilityValue(accessibilityValue(tool, enabled: enabled))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggle(tool) }
            // ★ 안 A(드래그)를 고른 근거가 성립하려면 이 둘이 **필수**다 — VoiceOver는 드래그를
            //   조작할 수 없으므로, 없으면 순서를 바꿀 방법이 아예 없다 (설계 문서 8절).
            //   **편집 모드와 무관하게 항상 붙인다.** 편집 모드는 드래그라는 시각적 어포던스를 위한
            //   것이고, 커스텀 액션에는 그 단계가 필요 없다. 요구하면 VoiceOver 사용자만 단계가 는다.
            .accessibilityAction(named: Text("왼쪽으로 이동")) { move(tool, by: -1) }
            .accessibilityAction(named: Text("오른쪽으로 이동")) { move(tool, by: 1) }
    }

    /// 순번 배지 — **켜진 도구에만** 1..n. 꺼진 도구는 툴바에 나오지 않으므로 순번이 거짓말이 된다.
    /// 시각 전용이라 접근성에서 빼고 내용은 `accessibilityValue`에 문장으로 넣는다.
    private func orderBadge(_ tool: ToolbarTool, enabled: Bool) -> some View {
        let rank = enabledRank(tool)
        return Text(rank.map(String.init) ?? "")
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Metrics.badgeDiameter, height: Metrics.badgeDiameter)
            .background(Circle().fill(Color.accentColor))
            .padding(3)
            .opacity(enabled && rank != nil ? 1 : 0)
            .accessibilityHidden(true)
    }

    /// 클립보드 자물쇠 — 켜짐/꺼짐/편집/드래그 **어느 상태에서도 항상** 붙는다.
    /// 컨테이너 앱은 `hasFullAccess`를 읽을 수 없으므로 상태를 추정하지 않는다(기획 2.3절).
    @ViewBuilder
    private func lockBadge(_ tool: ToolbarTool) -> some View {
        // **조건부 렌더가 여기서는 안전하다.** "누르는 도중 서브트리를 바꾸지 않는다"는 규율은
        // *터치 중에 바뀌는* 상태를 말한다 — 자물쇠 여부는 도구마다 고정이라 절대 바뀌지 않는다.
        // `opacity(0)`으로 숨기면 보이지 않는 자물쇠가 **VoiceOver 트리에 남는다**(시뮬 스냅숏 실측
        // 2026-09-14: 커서 셀에도 "잠금"이 붙어 나왔다).
        //
        // 순번 배지는 셀의 `overlay`라 셀과 함께 움직이고, **드래그 중에는 숫자가 바뀌지 않는다**
        // (순서 확정이 `onEnded` 한 번뿐이므로). 예전 주석은 "드래그 중에 숫자가 바뀌므로 opacity로
        // 둔다"고 적었는데 그건 `onChanged`에서 순서를 바꾸던 시절의 서술이라 지금은 사실이 아니다.
        // 배지를 여전히 opacity로 두는 이유는 **켜짐/꺼짐 토글로는 숫자가 바뀌기 때문**이다.
        if tool == .clipboard {
            Image(systemName: "lock.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Metrics.lockDiameter, height: Metrics.lockDiameter)
                .background(Circle().fill(Color(.systemGray)))
                .padding(4)
                .accessibilityHidden(true)
        }
    }

    // MARK: 이름표

    /// 아이콘만 두면 `doc.on.clipboard`가 무엇인지 모르는 사용자가 생긴다 —
    /// 방향을 고치자고 정보를 잃을 이유가 없다(디자인 0절). Dynamic Type을 따르고 최대 2줄.
    private func labels(cellWidth: CGFloat) -> some View {
        let step = cellWidth + Metrics.cellSpacing
        return HStack(spacing: Metrics.cellSpacing) {
            ForEach(tools, id: \.self) { tool in
                Text(tool.displayName)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(isOn(tool) ? Color.primary : Color.secondary)
                    .frame(width: cellWidth)
                    // **이름표는 아이콘과 같은 offset을 받아야 한다.**
                    // 예전 판은 `onChanged`에서 순서를 바꿔 스트립과 이름표가 같은 배열을 보고 함께
                    // 움직였다. 지금은 순서를 고정하고 offset으로만 비켜 주므로, 여기에 같은 offset을
                    // 걸지 않으면 **아이콘만 움직이고 이름표는 제자리에 남는다** — 이모지를 맨 왼쪽까지
                    // 끌면 1번 칸 아이콘 밑에 "키보드 내리기"라고 적히고, 손을 떼는 순간 이름표 5개가
                    // 한꺼번에 점프한다(회귀 지적 3). 디자이너가 "아이콘만 두면 무슨 도구인지 모른다"며
                    // 지켜낸 정보가 **조작하는 그 순간에만 틀린 값**을 가리키는 상태였다.
                    .offset(x: draggingTool == tool ? dragOffset : displacement(of: tool, step: step))
                    .animation(draggingTool == tool ? nil : .spring(response: 0.22, dampingFraction: 0.85),
                               value: dragStepDelta)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: 조작

    /// 셀 폭 = `min(84, (스트립 안쪽 폭 − 간격×(n−1)) ÷ n)` (디자인 2.1).
    /// 상한 84는 아이패드에서 과하게 벌어지지 않게 하는 값이다.
    ///
    /// ★ **v1.1.0에서 `n`이 5 → 6이 됐다**(📖 편입). 좁은 기기에서 칸과 **이름표**가 그만큼 좁아진다 —
    /// 이름표는 `.caption2` 2줄이라 「키보드 내리기」·「단어로 구절 찾기」가 잘릴 수 있다.
    /// **이것은 화면에서 확인하지 못했다**(실기·시뮬레이터 금지) — 보고서에 「실기 확인 필요」로 남겼다.
    /// 잘리면 손댈 곳은 여기가 아니라 `labelBoxHeight`·`lineLimit`이다.
    private func cellWidth(forStripWidth stripWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(tools.count, 1))
        let inner = stripWidth - Metrics.stripInset * 2 - Metrics.cellSpacing * (count - 1)
        return max(1, min(Metrics.cellMaxWidth, inner / count))
    }

    /// 이 도구가 지금 **툴바에 나오는 상태**인가.
    ///
    /// ★ `.bibleSearch`만 `disabledTools`를 보지 않는다 — 그 도구의 on/off는
    /// **채움글 > 성경 > 「단어로 구절 찾기」**(`bibleSearchEnabled`)가 정한다.
    /// 어긋난 저장분(`bibleSearchEnabled`가 참인데 `disabledTools`에 들어 있는 경우)은
    /// **여기서도 무해하게 무시**한다 — 사용자 데이터를 조용히 지우지 않기 위해서다.
    private func isOn(_ tool: ToolbarTool) -> Bool {
        tool.isToggleableInSettings
            ? !settings.disabledTools.contains(tool)
            : settings.bibleSearchEnabled
    }

    /// 탭으로 켜고 끄기.
    ///
    /// ★ **`.bibleSearch`는 여기서 아무 일도 하지 않는다**(끌기 전용). 이 가드가 없으면
    /// 탭이 `disabledTools`에 값을 써 넣는데, 조립 지점은 그 값을 보지 않으므로
    /// **화면만 꺼지고 실제로는 안 꺼지는** 스위치가 된다.
    /// 툴바 탭에 성경 스위치를 두지 말라는 사용자 지시(2026-09-21)가 있어 여기서는 못 끈다 —
    /// 왜 못 끄는지는 섹션 푸터가 설명한다.
    private func toggle(_ tool: ToolbarTool) {
        // ★ 조용히 삼키지 않는다 — 왜 아무 일이 없는지 조립 지점이 알린다 (2026-09-22).
        guard tool.isToggleableInSettings else {
            onBlockedToggle(tool)
            return
        }
        if settings.disabledTools.contains(tool) {
            settings.disabledTools.removeAll { $0 == tool }
        } else {
            settings.disabledTools.append(tool)
        }
    }

    /// 드래그로 자리 바꾸기. 자리가 5칸으로 고정이라 **좌표 5분할로 충분하다** —
    /// 임의 개수 List 재배열보다 단순하다(기획 4절).
    ///
    /// **롱프레스를 앞에 두지 않는다.** 편집 모드는 오른쪽 위 버튼으로 이미 들어와 있고,
    /// 아이폰 홈 화면도 흔들림 모드에서는 롱프레스 없이 바로 끌린다. 롱프레스를 넣으면
    /// 인식 지연이 생기고(설계 5절 스파이크 질문 ②) 얻는 것이 없다.
    private func reorderGesture(_ tool: ToolbarTool, cellWidth: CGFloat) -> some Gesture {
        let step = cellWidth + Metrics.cellSpacing
        // **드래그 중에는 저장 순서도 ForEach 순서도 바꾸지 않는다. 확정은 손을 뗄 때 한 번뿐이다.**
        //
        // 사용자 보고(2026-09-14, 실기 1.0.1(2)): "1번에 있는 것을 2번에 있는것과 겹치게 되면
        // 1,2번 왔다갔다 하면서 떨린다."
        //
        // 예전 판은 `onChanged`마다 `settings.toolOrder`를 바꿨다. 그러면 두 가지가 한꺼번에 터진다.
        //
        // 1. **되먹임 고리.** `DragGesture`의 기본 좌표계는 `.local` — 제스처가 붙은 **셀 자신**의
        //    좌표계다. 자리를 바꾸면 그 셀의 프레임이 한 칸 움직이고, 같은 손가락 위치가 새 좌표계에서
        //    step 만큼 다른 값으로 읽힌다. 그 값으로 목표를 다시 재면 목표가 되돌아가고 → 프레임이 또
        //    움직이고 → 값이 또 튄다. **손가락이 가만히 있어도 스스로 도는 고리**라 무한히 왕복한다.
        // 2. **`ForEach` 정체성 파괴.** 순서를 바꾸면 `ForEach(tools, id: \.self)`가 셀 뷰를 다시 만들고,
        //    진행 중인 제스처가 거기서 끊긴다. 화면과 저장값이 어긋나던 원인이다.
        //
        // 실측(iPhone 17 Pro, step 68pt, 고치기 전):
        //   1칸(68pt)→1칸 · 2칸(136pt)→**0칸** · 3칸(204pt)→**1칸**
        //   같은 136pt 세 번 반복 → 0칸 / 1칸 / 0칸  ← **같은 입력에 다른 결과 = 진동**
        //
        // 고친 방법은 셋이다.
        //   (가) 좌표계를 **스트립**으로 고정한다 — 스트립은 셀이 비켜도 움직이지 않는다.
        //   (나) 드래그 중 레이아웃 변화를 `offset`으로만 표현한다 — `ForEach` 순서는 그대로다.
        //   (다) 경계에 **이력(hysteresis)**을 준다 — `steppedDelta` 참조.
        // **제스처 우선순위는 건드리지 않았다.** 스파이크로 확인한 "세로 스크롤에 가로채이지 않는다"는
        // 성질이 그대로 남는다(고친 뒤 402pt·375pt 두 기기에서 재검증했다).
        return DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.stripSpace))
            // 제스처가 살아 있는 동안만 참. **취소돼도 SwiftUI가 스스로 false로 되돌린다** —
            // 이것이 모든 취소 경로를 덮는 리셋 트리거다 (`isDragActive` 선언부 주석).
            .updating($isDragActive) { _, active, _ in active = true }
            .onChanged { value in
                // **소유권 검사 — 한 번에 한 도구만 끈다.** 상태 넷을 셀 5개가 공유하므로,
                // 두 번째 손가락이 다른 셀을 잡으면 남의 start/target을 덮어써 **한 동작에 두 번
                // 재배열**되고 드래그 중 이웃 셀이 두 배치를 왕복하며 눈에 보이게 떤다(지적 2).
                // 아이폰 홈 화면도 한 번에 하나만 끌린다 — 두 번째 제스처는 **그냥 무시한다.**
                if let owner = draggingTool, owner != tool { return }
                if draggingTool != tool {
                    draggingTool = tool
                    dragStepDelta = 0
                }
                guard let start = tools.firstIndex(of: tool) else { return }
                dragOffset = rubberBandedOffset(value.translation.width, start: start, step: step)
                dragStepDelta = steppedDelta(current: dragStepDelta,
                                             rawSteps: value.translation.width / step,
                                             start: start)
            }
            .onEnded { value in
                guard draggingTool == tool else { return }   // 소유권 검사 (지적 2)
                // 확정은 여기서 **한 번**. App Group 쓰기도 Darwin 알림도 드래그당 1회로 줄어든다
                // (예전 판은 칸을 지날 때마다 써서 떠 있는 키보드를 여러 번 깨웠다).
                //
                // **시작 자리를 지금 배열에서 다시 읽고, 목표는 거기에 상대 칸수를 더해 낸다.**
                // 드래그 도중 「기본 순서로 되돌리기」나 VoiceOver `move(_:by:)`가 순서를 바꿔도
                // "시작 자리 + 몇 칸"은 뜻이 변하지 않는다 — 저장된 절대 인덱스로 확정하던 예전 판이
                // 오른쪽 한 칸을 엉뚱한 자리로 보내던 경로다(지적 1).
                if let start = tools.firstIndex(of: tool) {
                    let target = min(max(start + dragStepDelta, 0), tools.count - 1)
                    if target != start { reorder(from: start, to: target) }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                resetDragState(animated: true)
            }
    }

    /// **취소·성공을 가리지 않는 단 하나의 리셋 지점.**
    ///
    /// `onEnded`는 성공했을 때만 오므로 거기서만 지우면 취소 시 상태가 영원히 남는다.
    /// 그래서 `isDragActive`(`@GestureState`)가 false로 돌아오는 순간에도 이걸 부른다 —
    /// 그 신호는 전화·알림·잠금·회전·제스처 제거를 **전부** 포함한다.
    /// 여러 번 불려도 안전하도록 멱등하게 썼다.
    private func resetDragState(animated: Bool) {
        guard draggingTool != nil || dragOffset != 0 || dragStepDelta != 0 else { return }
        let clear = {
            draggingTool = nil
            dragOffset = 0
            dragStepDelta = 0
        }
        if animated {
            withAnimation(.spring(response: 0.18, dampingFraction: 0.9), clear)
        } else {
            clear()
        }
    }

    /// 끌리지 않는 셀이 비켜 줘야 하는 거리. 저장 순서는 그대로 두고 **보이기만** 옮긴다.
    private func displacement(of tool: ToolbarTool, step: CGFloat) -> CGFloat {
        guard let dragged = draggingTool, dragStepDelta != 0,
              let start = tools.firstIndex(of: dragged),
              let index = tools.firstIndex(of: tool) else { return 0 }
        let target = min(max(start + dragStepDelta, 0), tools.count - 1)
        guard start != target else { return 0 }
        if start < target, index > start, index <= target { return -step }
        if start > target, index >= target, index < start { return step }
        return 0
    }

    /// 경계를 넘으면 **점점 덜 움직이되 절대 멈추지 않는다** — 고무줄(rubber band).
    ///
    /// **예전엔 단순 클램프였는데 그게 사각지대를 만들었다**(반론자 O-3).
    /// 하한을 50pt 넘기면 51pt, 100pt 넘기면 101pt 동안 셀이 **아예 안 움직였다**(1:1).
    /// `clampedOffset(-400)` 과 `(-332)` 가 같은 값이라 **어디를 클램프해도 남는 성질**이다 —
    /// 반론자가 raw 를 먼저 가두는 수정을 넣어 보고 그대로 실패했다고 적었다.
    ///
    /// **내 예전 기각 사유가 방향이 반대였다.** "저항 곡선을 넣으면 raw 와 보이는 위치가 어긋난다"고
    /// 적었는데, **단순 클램프가 이미 어긋나게 만들고 있었다** — 손가락은 가는데 셀이 굳어 있으니
    /// 그게 최대치의 어긋남이다. iOS 스크롤 뷰가 클램프가 아니라 고무줄을 쓰는 이유가 이것이다.
    ///
    /// 곡선은 UIKit 관행과 같은 꼴이다: 초과분 `x` 를 `x / (1 + x/limit)` 로 눌러
    /// **처음엔 거의 1:1, 멀어질수록 완만**해지고 `limit` 에 점근한다. 되돌아올 때도 단조라
    /// 손가락과 셀이 같은 방향으로만 움직인다 — 사각지대가 사라진다.
    ///
    /// **확정 결과는 이 함수와 무관하다.** `dragStepDelta` 는 가두지 않은 `translation` 으로 갱신되므로
    /// 손을 떼면 올바른 자리로 간다. 여기서 고치는 것은 **보이는 것뿐**이다.
    private func rubberBandedOffset(_ raw: CGFloat, start: Int, step: CGFloat) -> CGFloat {
        let lowerBound = -CGFloat(start) * step
        let upperBound = CGFloat(tools.count - 1 - start) * step
        /// 고무줄이 늘어날 수 있는 최대 — 셀 하나 폭이면 충분하다(자리가 5칸뿐이라 멀리 갈 일이 없다).
        let limit = step
        if raw > upperBound { return upperBound + resist(raw - upperBound, limit: limit) }
        if raw < lowerBound { return lowerBound - resist(lowerBound - raw, limit: limit) }
        return raw
    }

    /// 초과분을 눌러 주는 곡선. `x → x / (1 + x/limit)`, `limit` 에 점근하고 **단조 증가**다.
    private func resist(_ overshoot: CGFloat, limit: CGFloat) -> CGFloat {
        guard overshoot > 0, limit > 0 else { return 0 }
        return overshoot / (1 + overshoot / limit)
    }

    /// 경계 이력(hysteresis)을 넣은 목표 자리 계산.
    ///
    /// **`round()`만 쓰면 정확히 0.5 지점에서 목표가 갈린다.** 손 떨림 한 픽셀이 그 선을 넘나들면
    /// 매 프레임 자리가 바뀐다 — 좌표계 고리를 끊어도 남는 두 번째 떨림 원인이다.
    /// 그래서 **전진과 후퇴의 문턱을 다르게** 둔다. 지금 자리에서 `threshold`칸 이상 더 가야 한 칸
    /// 전진하고, `threshold`칸 이상 물러나야 한 칸 후퇴한다. 0.6이면 한 칸 올라선 뒤 raw가
    /// 0.4~1.6 사이를 오가는 동안 **자리가 그대로다**(폭 1.2칸의 불감대).
    /// 0.5면 이력이 없어지고, 1.0에 가까우면 한 칸 옮기기가 뻑뻑해진다.
    private func steppedDelta(current: Int, rawSteps raw: CGFloat, start: Int) -> Int {
        let threshold: CGFloat = 0.6
        var next = current
        while raw > CGFloat(next) + threshold, start + next < tools.count - 1 { next += 1 }
        while raw < CGFloat(next) - threshold, start + next > 0 { next -= 1 }
        return next
    }

    /// VoiceOver 커스텀 액션 — 드래그 없이 한 칸씩 옮긴다.
    private func move(_ tool: ToolbarTool, by delta: Int) {
        guard let index = tools.firstIndex(of: tool) else { return }
        let target = min(max(index + delta, 0), tools.count - 1)
        guard target != index else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            reorder(from: index, to: target)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// ★★ 저장은 **반드시 여기를 거친다.**
    ///
    /// `tools`는 화면에 **보이는** 목록이라 꺼진 📖이 빠져 있다. 그것을 그대로
    /// `settings.toolOrder`에 쓰면 **안 보이는 도구가 저장에서 사라지고**,
    /// 다시 켰을 때 사용자가 끌어 둔 자리가 기본 자리로 되돌아간다.
    /// `mergingHiddenTools(into:)`가 숨은 도구를 원래 자리 번호에 되꽂는다
    /// (규칙과 근거는 그 함수 주석에 있고, 도메인 테스트가 잠근다).
    private func persist(visibleOrder: [ToolbarTool]) {
        settings.toolOrder = settings.mergingHiddenTools(into: visibleOrder)
    }

    private func reorder(from index: Int, to target: Int) {
        var order = tools
        let moved = order.remove(at: index)
        order.insert(moved, at: target)
        persist(visibleOrder: order)
    }

    private func enabledRank(_ tool: ToolbarTool) -> Int? {
        let enabled = tools.filter(isOn)
        return enabled.firstIndex(of: tool).map { $0 + 1 }
    }

    private func accessibilityValue(_ tool: ToolbarTool, enabled: Bool) -> String {
        var parts: [String] = []
        if enabled, let rank = enabledRank(tool) {
            parts.append("켜짐, \(rank)번째")
        } else {
            parts.append("꺼짐")
        }
        // 토글 라벨과 **같은 문구**를 쓴다 — 보이는 글과 읽어 주는 글이 갈리면 안 된다
        // (사용자 지시 2026-09-15: "전체 접근 필요 → 전체 접근 권한 필요").
        if tool == .clipboard { parts.append("전체 접근 권한 필요") }
        // ★ 이 셀만 이중 탭으로 안 꺼진다 — 왜인지 들리지 않으면 고장으로 읽힌다.
        //
        // **이 문장을 지우지 않았다.** 그것이 가리키던 푸터 줄은 2026-09-22에 사용자 지시로
        // 사라졌지만(「이 2줄만 남겨라」), **접근성에서 정보를 빼는 것이 더 나쁘다.**
        // 대신 반대로 맞췄다 — 같은 말을 **토스트**로 시각 사용자에게도 준다.
        // 그래서 이제 둘이 같은 상수에서 나온다.
        if !tool.isToggleableInSettings { parts.append(Self.bibleSwitchHintSpoken) }
        return parts.joined(separator: ", ")
    }
}
