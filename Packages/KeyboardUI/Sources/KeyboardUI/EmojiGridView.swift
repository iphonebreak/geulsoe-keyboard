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

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 8)
    private static let recentID = "recent"
    private static let frequentID = "frequent"

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
        VStack(spacing: 4) {
            categoryBar
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 2) {
                    ForEach(currentEmojis, id: \.self) { emoji in
                        Button {
                            onEmojiTap(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 27))
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

    /// 카테고리 탭 바 — 배경 없이 아이콘만, 선택은 진하게 + 밑줄 (사용자 요청: 버튼 뒷배경 제거)
    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                if !recentEmojis.isEmpty {
                    categoryButton(id: Self.recentID, symbol: "clock", label: "최근 사용")
                }
                categoryButton(id: Self.frequentID, symbol: "star", label: "자주 쓰는")
                ForEach(EmojiCatalog.categories) { category in
                    categoryButton(id: category.id, symbol: category.symbol, label: category.name)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 30)
    }

    private func categoryButton(id: String, symbol: String, label: String) -> some View {
        let selected = effectiveID == id
        return Button {
            selectedID = id
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    .foregroundStyle(theme.keyText.opacity(selected ? 1 : 0.45))
                Capsule()
                    .fill(selected ? theme.accent : .clear)
                    .frame(width: 16, height: 2)
            }
            .frame(width: 38, height: 28)
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
