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

    /// 끌고 있는 도구와 그 순간의 x 이동량. 셀 하나를 지날 때마다 자리를 바꾸고 offset을 그만큼 뺀다.
    @State private var draggingTool: ToolbarTool?
    @State private var dragOffset: CGFloat = 0
    /// 드래그를 **시작한** 자리. 이동량을 매번 여기서부터 다시 계산한다 — 아래 주석 참조.
    @State private var dragStartIndex: Int?

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

    private var tools: [ToolbarTool] { settings.orderedTools }

    var body: some View {
        GeometryReader { proxy in
            let width = cellWidth(forStripWidth: proxy.size.width)
            VStack(spacing: Metrics.labelTopSpacing) {
                strip(cellWidth: width)
                labels(cellWidth: width)
            }
        }
        // GeometryReader는 높이를 스스로 정하지 못하므로 바깥에서 고정한다.
        .frame(height: Metrics.stripHeight + Metrics.labelTopSpacing + 30)
        .animation(.easeInOut(duration: 0.25), value: isEditing)
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
    /// **누르는 도중 서브트리 구조를 바꾸지 않는다** (CLAUDE.md 2026-09-05 트랙패드 버그와 같은 이유).
    /// 켜짐/꺼짐·집힘·편집 모드를 전부 **배경·테두리·transform·투명도**로만 표현한다.
    /// `if`로 아이콘을 갈아끼우거나 오버레이를 넣고 빼면 진행 중인 터치가 제스처에서 떨어진다.
    private func cell(_ tool: ToolbarTool, width: CGFloat) -> some View {
        let enabled = !settings.disabledTools.contains(tool)
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
            .offset(x: dragging ? dragOffset : 0)
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
        // 2026-09-14: 커서 셀에도 "잠금"이 붙어 나왔다). 순번 배지는 드래그 중에 숫자가 바뀌므로
        // 그쪽만 opacity로 둔다.
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
        HStack(spacing: Metrics.cellSpacing) {
            ForEach(tools, id: \.self) { tool in
                Text(tool.displayName)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(settings.disabledTools.contains(tool) ? Color.secondary : Color.primary)
                    .frame(width: cellWidth)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: 조작

    /// 셀 폭 = `min(84, (스트립 안쪽 폭 − 간격×4) ÷ 5)` (디자인 2.1).
    /// 상한 84는 아이패드에서 과하게 벌어지지 않게 하는 값이고, 최소 폭 375pt에서 55.8pt가 나온다.
    private func cellWidth(forStripWidth stripWidth: CGFloat) -> CGFloat {
        let count = CGFloat(max(tools.count, 1))
        let inner = stripWidth - Metrics.stripInset * 2 - Metrics.cellSpacing * (count - 1)
        return max(1, min(Metrics.cellMaxWidth, inner / count))
    }

    private func toggle(_ tool: ToolbarTool) {
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
        return DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingTool != tool {
                    draggingTool = tool
                    dragStartIndex = tools.firstIndex(of: tool)
                }
                guard let start = dragStartIndex else { return }
                // **기준은 항상 드래그를 시작한 자리다.** `translation`은 시작점부터의 누적 이동량이므로,
                // 목표 자리도 누적값 하나로 계산해야 한다. 예전 판은 매 프레임 `dragOffset`을
                // `translation`으로 덮어쓴 뒤 자리를 바꿀 때마다 한 칸씩 빼는 방식이었는데,
                // 다음 프레임에 덮어쓰기가 그 보정을 지워서 **한 번 끌 때 여러 칸이 밀렸다**
                // (시뮬 실측 2026-09-14: 한 칸 끌었는데 저장값이 3칸 이동, 화면과 저장값이 어긋남).
                let steps = Int((value.translation.width / step).rounded())
                let target = min(max(start + steps, 0), tools.count - 1)
                if let index = tools.firstIndex(of: tool), index != target {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        reorder(from: index, to: target)
                    }
                }
                // 자리를 옮긴 만큼은 셀이 이미 이동했으므로 offset에서 뺀다 — 손가락 아래 붙어 보인다.
                dragOffset = value.translation.width - CGFloat(target - start) * step
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.9)) {
                    draggingTool = nil
                    dragOffset = 0
                }
                dragStartIndex = nil
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
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

    private func reorder(from index: Int, to target: Int) {
        var order = tools
        let moved = order.remove(at: index)
        order.insert(moved, at: target)
        settings.toolOrder = order
    }

    private func enabledRank(_ tool: ToolbarTool) -> Int? {
        let enabled = tools.filter { !settings.disabledTools.contains($0) }
        return enabled.firstIndex(of: tool).map { $0 + 1 }
    }

    private func accessibilityValue(_ tool: ToolbarTool, enabled: Bool) -> String {
        var parts: [String] = []
        if enabled, let rank = enabledRank(tool) {
            parts.append("켜짐, \(rank)번째")
        } else {
            parts.append("꺼짐")
        }
        if tool == .clipboard { parts.append("전체 접근 필요") }
        return parts.joined(separator: ", ")
    }
}
