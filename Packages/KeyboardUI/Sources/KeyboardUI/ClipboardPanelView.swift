import SwiftUI

/// 클립보드 기록 패널 — 자판 영역을 대체한다 (툴바 클립보드 도구, PDR clipboard-history).
///
/// 항목은 최근순. 내용은 여기 표시·탭 삽입 외에 어디로도 나가지 않는다 (조립 지점이 App Group에만
/// 저장). 백그라운드 감시는 불가능하므로 "키보드가 열려 있을 때 읽은 것"만 쌓인다 — 빈 상태 안내.
struct ClipboardPanelView: View {

    let entries: [String]
    let historyEnabled: Bool
    let theme: ResolvedTheme
    let onEntryTap: (String) -> Void
    let onEntryDelete: (String) -> Void
    let onClearAll: () -> Void
    let onClose: () -> Void

    private var emptyMessage: String {
        historyEnabled
            ? "복사한 내용이 여기에 쌓여요.\n복사한 뒤 키보드를 열면 기록돼요."
            : "클립보드가 비어 있어요.\n설정에서 기록을 켜면 복사한 내용이 쌓여요."
    }

    var body: some View {
        VStack(spacing: 4) {
            if entries.isEmpty {
                Spacer()
                Text(emptyMessage)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.keyText.opacity(0.6))
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(entries, id: \.self) { entry in
                            row(entry)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            HStack(spacing: 8) {
                PanelBarButton(theme: theme, label: "자판으로 돌아가기", action: onClose) {
                    Text("돌아가기")
                        .font(.system(size: 14, weight: .medium))
                }
                if !entries.isEmpty {
                    PanelBarButton(theme: theme, label: "모두 지우기", width: .hug, action: onClearAll) {
                        Text("모두 지우기")
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func row(_ entry: String) -> some View {
        HStack(spacing: 6) {
            Button {
                onEntryTap(entry)
            } label: {
                Text(entry)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.keyText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("붙여넣기: \(entry.prefix(40))")

            Button {
                onEntryDelete(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.keyText.opacity(0.6))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("기록에서 삭제")
        }
        .background(theme.characterKey, in: RoundedRectangle(cornerRadius: theme.keyCornerRadius))
    }
}
