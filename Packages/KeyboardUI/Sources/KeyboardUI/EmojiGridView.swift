import SwiftUI

/// 이모지 그리드 — 자판 영역을 대체한다 (툴바 이모지 도구, PDR toolbar-tools).
///
/// 상단 카테고리 바는 **탭 전환**이다 — 선택한 카테고리의 그리드만 그린다.
/// (이전의 한 스크롤 안 섹션 점프(`scrollTo`)는 LazyVStack에 아직 실체화되지 않은 섹션 id를
/// 찾지 못해 실기에서 반응이 없었다 — 2026-09-02 사용자 피드백. 탭 방식은 결정적이고
/// 한 번에 그리는 셀도 한 카테고리(≤300)로 줄어 메모리에도 유리하다.)
/// 순서: 최근 사용 → 자주 쓰는 → 유니코드 블록별 카테고리(`EmojiCatalog`).
/// 최근 사용은 조립 지점의 세션 메모리다 (App Group 저장은 실사용 확인 후 별도 결정).
struct EmojiGridView: View {

    let recentEmojis: [String]
    let theme: ResolvedTheme
    let onEmojiTap: (String) -> Void
    let onBackspace: () -> Void
    let onClose: () -> Void

    private static let recentID = "recent"
    private static let frequentID = "frequent"

    // MARK: - 적응형 열 수 (PDR ipad-support)

    /// 셀 하나의 목표 폭. 이보다 넓어지면 열을 늘린다 — 아이패드에서 8열 고정이면 셀이 104pt까지
    /// 벌어져 27pt 이모지가 점점이 흩어졌다 (QA BLOCK-1).
    private static let targetCellWidth: CGFloat = 64
    /// 열 수 하한. 아이폰 폭 범위(320~440pt)는 전부 이 하한에 걸려 **8열 그대로**다 — 회귀 없음.
    private static let minimumColumns = 8
    /// 이모지 글리프는 셀 폭에 비례하되 아이폰의 27pt를 하한으로 둔다.
    private static let glyphRange: ClosedRange<CGFloat> = 27...40
    private static let glyphRatio: CGFloat = 0.55
    private static let cellSpacing: CGFloat = 2

    static func columnCount(forWidth width: CGFloat) -> Int {
        max(minimumColumns, Int(width / targetCellWidth))
    }

    static func cellWidth(forWidth width: CGFloat, columns: Int) -> CGFloat {
        guard columns > 0 else { return 0 }
        // 등장 첫 패스의 폭 0에서 음수가 나오지 않게 (KeyboardLayoutView.rowView 주석 참조)
        return max(0, width - cellSpacing * CGFloat(columns - 1)) / CGFloat(columns)
    }

    private static func glyphSize(forWidth width: CGFloat, columns: Int) -> CGFloat {
        let cell = cellWidth(forWidth: width, columns: columns)
        return min(max(cell * glyphRatio, glyphRange.lowerBound), glyphRange.upperBound)
    }

    // MARK: - 카테고리 탭 (REQ-6)

    /// **아이폰 이모지 셀 폭의 천장.** 아이폰은 항상 8열이고 가장 넓은 기기(440pt)에서도
    /// 셀이 52.5pt다. 아이패드는 12열에서 65.5pt다 — 56pt가 둘을 가른다.
    /// 이 값을 넘을 때만 카테고리 탭을 셀에 비례시킨다 → **아이폰은 38 × 28 · 아이콘 14pt 그대로다.**
    private static let phoneCellWidthCeiling: CGFloat = 56

    /// 카테고리 탭 치수 — 셀 폭에서 낸다.
    ///
    /// 상수(38 × 28 · 아이콘 14)일 때 아이패드에서는 66.5pt 이모지 위에 28pt짜리 아이콘이 놓여
    /// **카테고리만 아이폰 크기 그대로**였고, 터치 영역도 HIG 44pt에 못 미쳤다
    /// (검증자 실측 REQ-6). 가로에서는 10개가 화면 폭의 33%에만 몰려 있었다.
    static func categoryMetrics(cellWidth cell: CGFloat) -> (width: CGFloat, height: CGFloat, icon: CGFloat) {
        guard cell > phoneCellWidthCeiling else { return (38, 28, 14) }
        return (cell * 0.85, cell * 0.70, cell * 0.30)
    }

    /// 선택 카테고리 id. 첫 표시는 최근 사용(있으면) 또는 자주 쓰는.
    @State private var selectedID: String?

    private var effectiveID: String {
        if let selectedID, selectedID != Self.recentID || !recentEmojis.isEmpty { return selectedID }
        return recentEmojis.isEmpty ? Self.frequentID : Self.recentID
    }

    private var currentEmojis: [String] {
        switch effectiveID {
        case Self.recentID: recentEmojis
        case Self.frequentID: EmojiCatalog.frequent
        default: EmojiCatalog.categories.first { $0.id == effectiveID }?.emojis ?? EmojiCatalog.frequent
        }
    }

    var body: some View {
        // 카테고리 탭 크기도 폭에서 나오므로 그리드 GeometryReader보다 **바깥에서** 폭을 한 번 읽는다
        // (카테고리 바는 그리드의 형제라 안쪽 GeometryReader의 값을 볼 수 없다)
        GeometryReader { outer in
            let outerColumns = Self.columnCount(forWidth: outer.size.width)
            let outerCell = Self.cellWidth(forWidth: outer.size.width, columns: outerColumns)
            body(cellWidth: outerCell)
        }
    }

    private func body(cellWidth: CGFloat) -> some View {
        VStack(spacing: 4) {
            categoryBar(cellWidth: cellWidth)
            // 열 수·글리프 크기는 **실제 폭에서** 나온다 — idiom 분기 없이 아이패드·Split View·
            // 회전에 그대로 따라간다 (KeyboardUI는 UIKit idiom을 모른다, 의존성 규칙)
            GeometryReader { geometry in
                let columns = Self.columnCount(forWidth: geometry.size.width)
                let glyph = Self.glyphSize(forWidth: geometry.size.width, columns: columns)
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Self.cellSpacing),
                                       count: columns),
                        spacing: Self.cellSpacing
                    ) {
                        ForEach(currentEmojis, id: \.self) { emoji in
                            Button {
                                onEmojiTap(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: glyph))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 3)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
                // 카테고리를 바꾸면 스크롤을 맨 위로 — 새 ScrollView 인스턴스
                .id(effectiveID)
            }

            HStack(spacing: 8) {
                PanelBarButton(theme: theme, label: "자판으로 돌아가기", action: onClose) {
                    Text("돌아가기")
                        .font(.system(size: 14, weight: .medium))
                }
                PanelBarButton(theme: theme, label: "지우기", width: .fixed(72), action: onBackspace) {
                    Image(systemName: "delete.left")
                        .font(.system(size: 15))
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// 카테고리 탭 바 — 배경 없이 아이콘만, 선택은 진하게 + 밑줄 (사용자 요청: 버튼 뒷배경 제거).
    /// 크기는 이모지 셀 폭에서 나온다 (REQ-6) — 아이폰은 하한에 걸려 그대로다.
    private func categoryBar(cellWidth: CGFloat) -> some View {
        let metrics = Self.categoryMetrics(cellWidth: cellWidth)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if !recentEmojis.isEmpty {
                    categoryButton(id: Self.recentID, symbol: "clock", label: "최근 사용", metrics: metrics)
                }
                categoryButton(id: Self.frequentID, symbol: "star", label: "자주 쓰는", metrics: metrics)
                ForEach(EmojiCatalog.categories) { category in
                    categoryButton(id: category.id, symbol: category.symbol,
                                   label: category.name, metrics: metrics)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: metrics.height + 2)
    }

    private func categoryButton(
        id: String, symbol: String, label: String,
        metrics: (width: CGFloat, height: CGFloat, icon: CGFloat)
    ) -> some View {
        let selected = effectiveID == id
        return Button {
            selectedID = id
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: metrics.icon, weight: selected ? .semibold : .regular))
                    .foregroundStyle(theme.keyText.opacity(selected ? 1 : 0.45))
                Capsule()
                    .fill(selected ? theme.accent : .clear)
                    .frame(width: metrics.icon + 2, height: 2)
            }
            .frame(width: metrics.width, height: metrics.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// 패널 하단 바 버튼(돌아가기·지우기·모두 지우기) — **버튼 표면 전체가 터치 영역**이다.
/// `.plain` 스타일은 라벨의 불투명 픽셀만 히트 테스트해 글자만 눌리는 문제가 있었다
/// (2026-09-02 사용자 피드백) — `contentShape`로 표면 전체를 잡는다.
struct PanelBarButton<Label: View>: View {

    enum Width {
        /// 남은 폭을 채운다
        case fill
        /// 고정 폭
        case fixed(CGFloat)
        /// 내용 폭 + 여백
        case hug
    }

    let theme: ResolvedTheme
    let label: String
    var width: Width = .fill
    let action: () -> Void
    @ViewBuilder let content: () -> Label

    var body: some View {
        Button(action: action) {
            sized(content().foregroundStyle(theme.keyText))
                .padding(.vertical, 9)
                .frame(minHeight: 36)
                .background(theme.functionKey, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
                .contentShape(RoundedRectangle(cornerRadius: theme.keyCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func sized(_ view: some View) -> some View {
        switch width {
        case .fill: view.frame(maxWidth: .infinity)
        case .fixed(let value): view.frame(width: value)
        case .hug: view.padding(.horizontal, 14)
        }
    }
}
