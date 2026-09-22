import SwiftUI
import KeyboardCore

/// 성경 검색 패널(화면 2) — 자판 영역을 대체한다.
///
/// 설계: `docs/design-reviews/v1.1.0-plan-v5.md` 2-3~2-7절
/// (원문은 4차 2-2~2-6절, 미리보기 창 근거는 `v1.1.0-round2-findings.md` C-3).
///
/// ```
/// [전체(137)] [창세기(13)] [출애굽기(30)] …        ← 책 필터만, 가로 스크롤
/// ────────────────────────────────────────────
/// 창 13:30  …그가 우리를 ⟦믿음⟧에서…              ← 맞은 자리 창 + 형광펜
/// 창 14:2   …⟦믿음⟧과 순종으로…
/// ```
///
/// ## ★ 검색어 칩이 없다 (사용자 지시 2026-09-21)
///
/// 원래 패널 맨 위에 `[믿음 ✕]` 칩이 있었다. 두 번에 걸쳐 없앴다.
///
/// 1. 칩이 **제 줄 하나를 통째로** 썼는데 그 줄에는 칩이 언제나 하나뿐이었다 → 필터 줄로 합쳤다
/// 2. 형광펜이 들어오자 칩 자체가 필요 없어졌다 → **없앴다**
///
/// > 「형광펜 기능 때문에 패널 안에서 칩은 안나와도 될거 같다 없애라」
///
/// 칩이 하던 *지금 무엇으로 찾고 있나*를 **형광펜이 구절 안에서 직접 보여 준다.**
/// 칩 본체 탭은 아래 「돌아가기」와 **같은 `onClose`**였으므로 중복이었고, 고유 기능인
/// ✕(친 글자 지우기)는 함께 없앴다 — 근거는
/// `docs/design-reviews/bible-panel-query-chip-removal.md`.
///
/// **`query` 프로퍼티는 남는다** — 형광펜이 칠할 자리를 찾는 데 쓴다. 지우면 형광펜이 죽는다.
///
/// 세로 예산: 칩 줄 40pt를 없애 구절 목록이 **93 → 133pt**가 됐고, 칩이 빠지며 줄 높이를
/// 36 → 34pt로 되돌려 **135pt(2.5줄 → 3.75줄)** 가 됐다.
///
/// 클립보드·이모지 패널과 **같은 구조**다(`ClipboardPanelView` 선례) — 자판 자리를 차지하고
/// 아래에 「돌아가기」 막대가 있다. 총 높이 계약(`totalKeyboardHeight`)은 건드리지 않는다.
struct BibleSearchPanelView: View {

    let query: String
    let rows: [BibleSearchRow]
    let theme: ResolvedTheme
    /// 구절 탭 — 조립 지점이 기존 `insertSnippet` 경로로 넣는다(꼬리 정합·학습 차단이 딸려 온다).
    let onRowTap: (BibleSearchRow) -> Void
    /// 「돌아가기」 — 패널만 닫고 **검색어는 남긴다**(왕복 설계 UX-1).
    /// 칩이 사라진 뒤로 패널을 닫는 **유일한 길**이다.
    let onClose: () -> Void

    /// 선택한 책. nil이면 「전체」. **패널이 스스로 들고 있는다** — 책을 바꾸는 것은
    /// 다시 스캔하는 일이 아니라 이미 받은 결과를 거르는 일이라 조립 지점까지 갈 이유가 없다
    /// (`EmojiGridView`의 카테고리 탭과 같은 선례).
    @State private var selectedBook: Int?

    private var filters: [BibleBookFilter] {
        BibleBookFilter.filters(for: rows.map(\.match))
    }

    /// 지금 탭에서 보일 행들. 「전체」면 그대로.
    private var visibleRows: [BibleSearchRow] {
        guard let selectedBook else { return rows }
        return rows.filter { $0.match.book == selectedBook }
    }

    /// 고른 책이 결과에서 사라졌으면(검색어가 바뀌었다) 「전체」로 되돌린다.
    private var effectiveBook: Int? {
        guard let selectedBook, rows.contains(where: { $0.match.book == selectedBook }) else { return nil }
        return selectedBook
    }

    var body: some View {
        GeometryReader { geometry in
            body(rowMinHeight: KeyboardMetrics.listRowMinHeight(panelWidth: geometry.size.width))
        }
    }

    private func body(rowMinHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            bookFilterBar
            Divider().overlay(theme.keyText.opacity(0.15))
            resultList(rowMinHeight: rowMinHeight)
            PanelBarButton(theme: theme, label: "자판으로 돌아가기", action: onClose) {
                Text("돌아가기")
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 책 필터 (가로 스크롤 — EmojiGridView 카테고리 바 선례)

    /// 줄 높이 **34pt**.
    ///
    /// 검색어 칩이 있던 동안은 36pt였다 — ✕ 탭 영역 32pt와 칩 캡슐이 34pt에서 빠듯해서
    /// 2pt를 더 줬었다. **칩이 사라져 그 이유가 없어졌으므로 되돌린다.**
    /// 책 칩은 13pt 글자 + 위아래 6pt = 약 27.5pt라 34pt 안에서 넉넉하다
    /// (칩이 오기 전에도 이 줄은 34pt였고 그때 잘리지 않았다).
    /// 되돌린 2pt는 그대로 구절 목록 몫이 된다.
    ///
    /// ## ★ VoiceOver — 줄 전체가 **하나의 조절 가능한 요소**다 (2026-09-21)
    ///
    /// 계획서(`v1.1.0-plan-v5.md:524`)가 *"한 칩씩 스와이프가 유일하면 **실패**"* 라고
    /// 못박은 항목이다. 고치기 전에는 대안 탐색이 **0건**이었다 — 가로 `ScrollView` 하나뿐이라
    /// VoiceOver 사용자가 구절 목록에 닿으려면 **책 칩을 전부 지나쳐야** 했다.
    /// 결과가 1,000건이면 책이 40~60개까지 생기므로, 목록에 닿는 데만 스와이프 수십 번이다.
    ///
    /// **셋 중 이것을 고른 이유.** 반론자2가 제시한 갈래는 로터 · 조절 가능한 요소 ·
    /// 칩마다 커스텀 동작 셋이었다. 로터와 커스텀 동작은 *옮겨 다니는 길*을 하나 더 얹을 뿐
    /// **칩 60개가 초점을 먹는 문제 자체는 그대로 둔다.** 조절 가능한 요소는 그 줄을
    /// **초점 하나로 줄인다** — 실제 해악이 그것이므로 이쪽을 골랐다.
    /// 덤으로 `UISegmentedControl`이 쓰는 것과 **같은 관례**라 사용자가 이미 아는 제스처다.
    ///
    /// **맞바꾼 것을 밝혀 둔다:** 칩 하나하나가 더는 초점을 받지 않으므로 **먼 책을 곧바로
    /// 고를 수 없다.** 그래서 「전체 보기」를 커스텀 동작으로 따로 둬 되돌아가는 길은 한 번에
    /// 끝나게 했다. 칩 라벨이 읽어 주던 내용(책 이름 + 건수)은 **값 문자열로 그대로 옮겼고**,
    /// 개수 표기는 배지·칩과 같은 `BibleCountText` 규칙을 쓴다.
    ///
    /// ★ **실제 낭독·이동은 확인하지 못했다** — 실기·시뮬레이터가 금지된 작업이었다.
    /// 이동 규칙과 값 문자열만 순수 함수로 내려(`BibleBookFilter.neighbor`·`spokenValue`)
    /// 테스트로 잠갔다.
    private var bookFilterBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filters) { filter in
                        bookButton(filter).id(filter.id)
                    }
                }
                .padding(.horizontal, 2)
            }
            // 고른 책이 화면 밖에 있으면 보이지 않는다 — 위/아래 스와이프로 바뀔 때 특히.
            // (`filter.id`는 `book ?? 0`이고 실제 책 번호는 1~66이라 0이 「전체」다.)
            .onChange(of: effectiveBook) { _, book in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(book ?? 0, anchor: .center)
                }
            }
        }
        .frame(height: 34)
        .padding(.top, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("책 고르기")
        .accessibilityValue(spokenFilterValue)
        .accessibilityHint("위아래로 쓸어서 책을 바꿔요")
        .accessibilityAdjustableAction { direction in
            let offset: Int
            switch direction {
            case .increment: offset = 1
            case .decrement: offset = -1
            @unknown default: return
            }
            guard let next = BibleBookFilter.neighbor(
                of: effectiveBook, in: filters, offset: offset
            ) else { return }   // 끝이면 멈춘다 — 순환하지 않는다
            selectedBook = next.book
        }
        .accessibilityAction(named: Text("전체 보기")) {
            selectedBook = nil
        }
    }

    /// 조절 가능한 요소가 읽어 줄 값 — 「시편, 24건, 40개 중 3번째」.
    private var spokenFilterValue: String {
        BibleBookFilter.spokenValue(of: effectiveBook, in: filters) {
            BibleCountText.spokenCount($0)
        }
    }

    /// 필터 칩의 글자.
    ///
    /// ## ★ 상한에 걸리면 괄호를 벗긴다 (2026-09-21)
    ///
    /// 「사람」은 실제 4,253건인데 검색이 1,000개까지만 들고 온다. 그때 `전체(1000)`이라고 쓰면
    /// **「전체」라고 하면서 3,253건을 조용히 빼는** 말이 된다. 배지는 같은 상황에서 이미
    /// `999+`를 그리고 있었다 — 둘이 다른 말을 하고 있었다.
    ///
    /// 괄호는 **정확한 수**를 뜻하게 두고, 상한에 걸리면 `전체 999+`처럼 괄호를 벗긴다.
    /// 모양이 달라지는 것 자체가 「이 수는 정확하지 않다」는 신호다.
    ///
    /// 책 칩(「아가(54)」)은 그대로다 — 상한 안에서 센 수이지만 「전체 999+」가 곁에서
    /// **이 목록은 잘렸다**고 말해 주므로 오해를 부르지 않는다.
    static func chipLabel(_ filter: BibleBookFilter) -> String {
        BibleCountText.isCapped(filter.count)
            ? "\(filter.name) \(BibleCountText.label(filter.count))"
            : "\(filter.name)(\(filter.count))"
    }

    private func bookButton(_ filter: BibleBookFilter) -> some View {
        let selected = effectiveBook == filter.book
        return Button {
            selectedBook = filter.book
        } label: {
            Text(Self.chipLabel(filter))
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(selected ? theme.keyboardBackground : theme.keyText)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    selected ? theme.accent : theme.functionKey,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(filter.name) \(BibleCountText.spokenCount(filter.count))")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 형광펜 (사용자 지시 2026-09-21)

    /// 검색어가 **행 배경 위에 얹히는** 불투명도.
    ///
    /// ## 8개 팔레트를 계산했다 — **CIEDE2000으로** (2026-09-21 정정)
    ///
    /// 형광펜은 `accent`를 행 배경(`characterKey`) 위에 얹은 것이고, 글자는 `keyText` 그대로다.
    /// `Themes.json`의 hex를 직접 읽어 잰다(앱 미실행).
    ///
    /// **★ 처음에는 CIE76으로 재고 「8개 전부 뚜렷(10 이상)」이라고 적었다. CIEDE2000에서는 거짓이었다** —
    /// 미드나이트/라이트가 **ΔE76 12.5 인데 ΔE2000 8.7**로 문턱 아래였다(반론자1 A-3).
    /// CIE76은 청록~파랑에서 색차를 **과대평가**하는 옛 식이고 미드나이트 accent가 정확히 그 영역이다.
    /// 사장님과 내가 **같은 옛 식**을 써서 둘이 일치했던 것이다.
    ///
    /// 그래서 라이트를 **0.30 → 0.38**로 올렸다. 두 지표를 **함께** 만족하는 값이다:
    ///
    /// | 테마 | 모드 | 글자 대비 | ΔE2000 |
    /// |---|---|---:|---:|
    /// | 시스템 | light | 12.58:1 | 21.6 |
    /// | 시스템 | dark | **4.74:1** | 19.9 |
    /// | 퓨어 라이트 | light | 10.19:1 | 21.6 |
    /// | 퓨어 라이트 | dark | 8.86:1 | 23.7 |
    /// | 퓨어 다크 | light | 5.74:1 | 18.7 |
    /// | 퓨어 다크 | dark | 5.76:1 | 21.4 |
    /// | 미드나이트 | light | 4.84:1 | **11.1** |
    /// | 미드나이트 | dark | 5.05:1 | 15.6 |
    ///
    /// **최저 글자 대비 4.74:1**(WCAG AA 본문 4.5 통과) · **최저 ΔE2000 11.1**(문턱 10 통과).
    /// 더 올리면 글자 대비가 먼저 깨진다 — 0.42에서 4.62, 0.46에서 **4.41로 AA 미달**이다.
    ///
    /// ## ★ 확인하지 못한 것 — 합성 공간
    ///
    /// SwiftUI의 `opacity`가 **sRGB(감마) 공간**에서 섞이는지 **선형 공간**에서 섞이는지에 따라
    /// 숫자가 달라진다. 위 표는 **sRGB 가정**이다(Core Animation 기본 동작이라 그쪽일 가능성이
    /// 높다고 본다). 선형이면 일부 조합이 AA를 못 넘는다 — **픽셀을 읽어 확인한 사람은 없다**(반론자1 A-3).
    /// 캡처 한 장이면 끝나는 확인이다.
    ///
    /// ★ **고정 노란색은 쓰지 않았다.** 어두운 팔레트(미드나이트 `characterKey` #303462) 위의
    /// 노랑은 글자색 `keyText`와 대비가 무너진다. 테마의 `accent`를 쓰면 팔레트가 스스로 보증한다.
    private var highlightOpacity: Double { theme.isDark ? 0.45 : 0.38 }

    /// 미리보기 줄에서 검색어 글자에만 배경을 깐다.
    ///
    /// **탐색은 `KeyboardCore.BibleVersePreview.highlightRanges`가 한다** — 뷰에 탐색 로직을 두면
    /// 테스트가 뷰에 묶인다. 여기서는 받은 구간에 색만 입힌다.
    ///
    /// 검색어가 창에 없으면 구간이 비어 **아무 것도 칠하지 않는다**(방어).
    /// 참조(「고전 13:4」)는 별도 `Text`라 애초에 대상이 아니다.
    private func highlighted(_ preview: String) -> AttributedString {
        var attributed = AttributedString(preview)
        for range in BibleVersePreview.highlightRanges(of: query, in: preview) {
            guard let lower = AttributedString.Index(range.lowerBound, within: attributed),
                  let upper = AttributedString.Index(range.upperBound, within: attributed)
            else { continue }
            attributed[lower..<upper].backgroundColor = theme.accent.opacity(highlightOpacity)
        }
        return attributed
    }

    // MARK: - 결과

    @ViewBuilder
    private func resultList(rowMinHeight: CGFloat) -> some View {
        if visibleRows.isEmpty {
            Spacer()
            Text("결과가 없어요.")
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText.opacity(0.6))
            Spacer()
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visibleRows) { row in
                        resultRow(row, minHeight: rowMinHeight)
                    }
                }
                .padding(.top, 2)
            }
            // 책을 바꾸면 스크롤을 맨 위로 — 새 ScrollView 인스턴스 (EmojiGridView와 같은 수법)
            .id(effectiveBook ?? -1)
        }
    }

    private func resultRow(_ row: BibleSearchRow, minHeight: CGFloat) -> some View {
        // 「전체」 탭에서만 책 이름을 붙인다 (UX-2)
        let reference = row.reference(includingBook: effectiveBook == nil)
        return Button {
            onRowTap(row)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reference)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.keyText.opacity(0.7))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(highlighted(row.preview))
                    .font(.system(size: 14))
                    .foregroundStyle(theme.keyText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: minHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.reference(includingBook: true)), \(row.preview)")
        .background(theme.characterKey, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
    }
}
