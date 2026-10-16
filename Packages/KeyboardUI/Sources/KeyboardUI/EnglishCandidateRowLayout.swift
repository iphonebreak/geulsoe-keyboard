import SwiftUI

/// 영어 추천단어 줄(B5 C12 — 실기 결함 수정 2026-10-15). 칩과 구분선을 번갈아 받아 **긴 후보에 더 넓게** 배분한다.
///
/// 왜 따로 있나: 툴바 `HStack`은 칩을 같은 폭으로 나눈다. 393pt 아이폰에서 칩 글자 칸은 85pt인데 `communication`(1배 117pt)은
/// 0.7배 하한에서도 86pt라 말줄임됐다(실기 `docs/release/device-v131-2/c12-communic-truncated.png`). 한글 줄은 건드리지 않고 —
/// 툴바가 영어 줄일 때만 이 레이아웃을 쓴다. 배분식은 `KeyboardMetrics.englishChipWidths`(시험으로 고정).
///
/// - 이상 폭(제안 폭 없음)은 **0.7배 하한으로 잘리지 않는 최소 폭**을 돌려준다 — 툴바의 `ViewThatFits`가 이 값으로
///   「후보 전부」가 안 되면 「마지막 하나 뺀 것」을 고른다. 그래서 어느 칩도 말줄임되지 않는다(표시 = 탭 삽입 = VoiceOver 라벨).
/// - 구조는 바꾸지 않는다 — 프레임만 정한다. 누르는 도중 서브트리 불변 규칙과 무관하다.
struct EnglishCandidateRowLayout: Layout {

    let padding: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let parts = Self.split(subviews)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height)).height }.max() ?? 0
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = proposed
        } else {
            let naturals = parts.chips.map { $0.sizeThatFits(.unspecified).width }
            let dividerWidth = parts.dividers.first.map { $0.sizeThatFits(.unspecified).width } ?? 1
            width = proposal.width == nil
                ? KeyboardMetrics.englishRowMinimumWidth(naturalWidths: naturals, padding: padding, dividerWidth: dividerWidth)
                : naturals.reduce(0, +) + KeyboardMetrics.englishRowFixedWidth(chips: naturals.count, dividerWidth: dividerWidth)
        }
        return CGSize(width: width, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let parts = Self.split(subviews)
        let dividerWidth = parts.dividers.first.map { $0.sizeThatFits(.unspecified).width } ?? 1
        let available = bounds.width - KeyboardMetrics.englishRowFixedWidth(chips: parts.chips.count, dividerWidth: dividerWidth)
        let widths = KeyboardMetrics.englishChipWidths(
            naturalWidths: parts.chips.map { $0.sizeThatFits(.unspecified).width }, available: available, padding: padding)
        var x = bounds.minX
        var chipIndex = 0
        for subview in subviews {
            if subview[CandidateDividerKey.self] {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
                x += size.width + KeyboardMetrics.candidateRowSpacing
            } else {
                let width = chipIndex < widths.count ? widths[chipIndex] : 0
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                              proposal: ProposedViewSize(width: width, height: bounds.height))
                x += width + KeyboardMetrics.candidateRowSpacing
                chipIndex += 1
            }
        }
    }

    private static func split(_ subviews: Subviews) -> (chips: [LayoutSubview], dividers: [LayoutSubview]) {
        (subviews.filter { !$0[CandidateDividerKey.self] }, subviews.filter { $0[CandidateDividerKey.self] })
    }
}

/// 후보 줄 구분선 표시 — `EnglishCandidateRowLayout`이 칩과 구분선을 가른다
struct CandidateDividerKey: LayoutValueKey {
    static let defaultValue = false
}
