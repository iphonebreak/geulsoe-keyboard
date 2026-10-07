import Accessibility
import SwiftUI
import KeyboardCore
import TadakDomain

/// 겹치는 채움글 후보 패널(U7) — 칩을 길게 눌러 무장한 뒤 손을 떼면 자판 자리를 대신한다.
///
/// 계약: PDR `docs/design-reviews/external-snippet-packs.md` 10-6 ②⑥⑦ · AC-39·46 · R32 (다) · 시안 8-D·8-I·8-J.
/// 클립보드·구절 찾기 패널과 **같은 구조**다(`BibleSearchPanelView` 선례) — 자판 자리, 문자 키 색 둥근 행, 아래 「돌아가기」 막대.
///
/// ```
/// 「새해인사」 후보 3개                      ← 머리줄(R32 (다)) — 친 그대로의 단축어
/// ┌ 새해 인사                  [내 채움글] ┐ ← 행 = 제목 + 출처(오른쪽) / 본문 첫 줄
/// └ 새해 복 많이 받으세요. 올해도…        ┘
/// ┌ 새해 인사           [우리 회사 상용구] ┐
/// …                                         ← 목록만 스크롤(상한 8)
/// [            돌아가기            ]       ← 접근성 「자판으로 돌아가기」(기존 두 패널과 같은 이름)
/// ```
///
/// - **첫 행은 칩의 후보다** — 순서 계약(`candidates.first == suggestion`, AC-37)이 보장한다. 색으로 따로 표시하지 않는다
///   (R32 (나) — 시안의 진한 파랑 고정색은 하지 않는다, 「키 표면은 테마 색 단색」). 그림에는 `ResolvedTheme` 색만 쓴다.
/// - 행 탭은 조립 지점으로 보낼 뿐이다 — 꼬리 정합·삽입·패널 닫기는 조립 지점(③)이 기존 `insertSnippet` 경로로 한다.
/// - 출처 이름(팩 이름)·본문은 **사용자 유래**다 — 화면에 그리기만 하고 어디에도 기록하지 않는다(10-6 ⑧, 보안 규칙).
/// - VoiceOver(시안 8-I · U7 ③-6): 열리면 화면 변경을 알리고 **첫 행**으로 포커스를 옮긴다. 「돌아가기」는 목록(스크롤) 밖 맨 아래라
///   행을 넘기면 항상 닿고, 두 손가락 문지르기(escape)로도 닫힌다. 성경·클립보드 패널에는 이 선례가 없다 — 이 패널이 처음이다.
struct SnippetCandidatesPanelView: View {

    let candidates: [SnippetCandidate]
    let theme: ResolvedTheme
    let onRowTap: (SnippetCandidate) -> Void
    /// 「돌아가기」 — 패널만 닫는다(칩은 그대로)
    let onClose: () -> Void

    /// VoiceOver 포커스가 있는 행(몇 번째) — 열릴 때 0(첫 행 = 칩 후보)으로 옮긴다. VoiceOver가 꺼져 있으면 아무 일도 없다
    @AccessibilityFocusState private var focusedRow: Int?

    /// 머리줄 「「X」 후보 n개」 — X는 사용자가 친 꼬리 원문(후보는 모두 같은 trigger, 10-6 ①). 후보가 없으면 빈 글자
    nonisolated static func header(for candidates: [SnippetCandidate]) -> String {
        guard let trigger = candidates.first?.suggestion.trigger else { return "" }
        return SnippetCandidateText.panelHeader(trigger: trigger, count: candidates.count)
    }

    /// 그릴 행 — 상한 8(AC-46). 조립 지점이 이미 자르지만 그림 쪽도 같은 규칙을 지킨다(`candidateRowSnippet` 선례)
    nonisolated static func visibleRows(_ candidates: [SnippetCandidate]) -> [SnippetCandidate] {
        Array(candidates.prefix(SnippetCandidateGate.limit))
    }

    /// 행 VoiceOver 라벨 「채움글 <제목>, <출처>, 붙여넣기」 — 표는 ①의 `SnippetCandidateText` 한 곳(10-6 ⑦)
    nonisolated static func rowLabel(_ candidate: SnippetCandidate) -> String {
        SnippetCandidateText.rowLabel(candidate)
    }

    /// 행 오른쪽 출처 글자 — 내 채움글 / 팩 이름 / 내장 팩 이름 / 날짜·시간 / 성경
    nonisolated static func originLabel(_ candidate: SnippetCandidate) -> String {
        SnippetCandidateText.originName(candidate.origin)
    }

    var body: some View {
        // 행 최소 높이는 폭에서 나온다(UX-10) — 아이폰 36pt, 아이패드 44pt
        GeometryReader { geometry in
            body(rowMinHeight: KeyboardMetrics.listRowMinHeight(panelWidth: geometry.size.width))
        }
    }

    private func body(rowMinHeight: CGFloat) -> some View {
        VStack(spacing: 4) {
            Text(Self.header(for: candidates))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.keyText.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            // 행은 최대 8개라 지연 생성이 필요 없다 — 목록만 스크롤된다(시안 8-D)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(Self.visibleRows(candidates).enumerated()), id: \.offset) { index, candidate in
                        SnippetCandidateRow(candidate: candidate, theme: theme, minHeight: rowMinHeight) {
                            onRowTap(candidate)
                        }
                        .accessibilityFocused($focusedRow, equals: index)
                    }
                }
            }
            PanelBarButton(theme: theme, label: BibleSearchText.backToKeyboardLabel, action: onClose) {
                Text("돌아가기")
                    .font(.system(size: 14, weight: .medium))
            }
        }
        .padding(.horizontal, 4)
        // VoiceOver escape(두 손가락 Z) — 「돌아가기」와 같은 닫기
        .accessibilityAction(.escape, onClose)
        .onAppear {
            // 자판 → 패널: 화면 변경 알림(VoiceOver가 맨 앞 요소로 간다) 뒤, 한 차례 미뤄 첫 행으로 옮긴다 —
            // 나타나는 그 순간에는 행이 아직 접근성 트리에 없어 바로 주면 무시될 수 있다. 순서·체감은 실기 확인 항목
            AccessibilityNotification.ScreenChanged().post()
            Task { @MainActor in focusedRow = 0 }
        }
    }
}

/// 후보 패널의 행 하나 — 제목 + 출처(오른쪽) / 본문 첫 줄, 문자 키 색 둥근 행(클립보드·구절 찾기 행과 같은 모양).
///
/// **몇 번째 행인지 모른다** — 첫 행(칩 후보)을 색으로 따로 칠하지 않는다는 R32 (나)를 구조로 지킨다.
/// 따로 뗀 이유는 하나 더 있다: macOS `ImageRenderer`는 `ScrollView` 안을 그리지 않아, 행 그림은 이 뷰를 직접 그려 시험한다.
struct SnippetCandidateRow: View {

    let candidate: SnippetCandidate
    let theme: ResolvedTheme
    let minHeight: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(candidate.suggestion.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.keyText)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // 출처 — 같은 모양의 두 후보를 가르는 유일한 단서(10-6 ⑥). 기능 키 색 작은 이름표(시안 8-D, 고정색 없음)
                    Text(SnippetCandidatesPanelView.originLabel(candidate))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.keyText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(theme.functionKey, in: RoundedRectangle(cornerRadius: 6))
                }
                Text(SnippetChipTitle.previewLine(candidate.suggestion.body))
                    .font(.system(size: 13.5))
                    .foregroundStyle(theme.keyText.opacity(0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SnippetCandidatesPanelView.rowLabel(candidate))
        .background(theme.characterKey, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
    }
}
