import SwiftUI
import TadakDomain
import TadakData

/// 테마 목록 행 — 라이트/다크 팔레트 스와치 + 체크마크. 화면 탭의 Section 안에 인라인으로 들어간다.
///
/// 실물 키보드 미리보기(KeyboardUI 재사용)는 후속 후보 — 앱은 KeyboardUI를 import하지
/// 않는다는 결정을 유지한다 (PDR settings-app 결정 5).
struct ThemeRows: View {

    @Binding var selectedThemeID: String

    private let themes = BundledThemeRepository().availableThemes()

    var body: some View {
        ForEach(themes, id: \.id) { theme in
            Button {
                selectedThemeID = theme.id
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(theme.displayName)
                            .foregroundStyle(.primary)
                        HStack(spacing: 10) {
                            paletteSwatches(theme.light, caption: "라이트")
                            paletteSwatches(theme.dark, caption: "다크")
                        }
                    }
                    Spacer()
                    if theme.id == selectedThemeID {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func paletteSwatches(_ palette: ThemeSpec.Palette, caption: String) -> some View {
        HStack(spacing: 5) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(Array([
                palette.keyboardBackground, palette.characterKey,
                palette.functionKey, palette.keyText, palette.accent
            ].enumerated()), id: \.offset) { _, hex in
                Circle()
                    .fill(Color(themeHex: hex))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
            }
        }
    }
}

extension Color {
    /// `"#RRGGBB"` / `"#RRGGBBAA"` 파싱 — `KeyboardUI.ResolvedTheme`의 파서와 같은 계약을
    /// 미러링한다 (형식이 깨졌으면 자홍색으로 드러낸다). 계약을 좁히면 8자리 팔레트를 가진
    /// 테마에서 키보드는 정상인데 이 피커만 색이 엉킨다 (리뷰 반영).
    init(themeHex hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard Scanner(string: cleaned).scanHexInt64(&value),
              cleaned.count == 6 || cleaned.count == 8 else {
            self = .init(red: 1, green: 0, blue: 1)
            return
        }
        if cleaned.count == 6 { value = (value << 8) | 0xFF }
        self.init(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}
