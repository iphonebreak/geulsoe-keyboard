import SwiftUI
import TadakDomain
import TadakData

/// 테마 목록 — 테마마다 **소형 미리보기 카드**(`ThemePreviewCard`) 하나. 화면 탭의 Section 안에
/// 인라인으로 들어간다.
///
/// ## 색 동그라미에서 미리보기 카드로 (v1.1.0)
///
/// 예전에는 이름 + 색 동그라미 다섯 개였다. 색만 봐서는 **어떤 키보드인지 알 수 없어서**
/// 사용자가 고르고 → 키보드를 열어 보고 → 아니면 되돌아오는 왕복을 했다.
/// 설계: `docs/design-reviews/v1.1.0-plan-v3.md` 5절.
///
/// **테마 개수를 고정하지 않는다** — `availableThemes()` 가 주는 만큼 전부 렌더한다.
/// 테마는 데이터 주도라 `Themes.json` 에 항목을 더하면 코드 0으로 늘어난다(CLAUDE.md).
/// 수용 기준 1번이 이것이다.
///
/// **`App/` 은 `KeyboardUI` 를 import 하지 않는다**(PDR settings-app 결정 5) — 이 파일도
/// `TadakDomain`·`TadakData` 만 쓴다.
struct ThemeRows: View {

    @Binding var selectedThemeID: String

    private let themes = BundledThemeRepository().availableThemes()

    var body: some View {
        ForEach(themes, id: \.id) { theme in
            Button {
                selectedThemeID = theme.id
            } label: {
                ThemePreviewCard(theme: theme, isSelected: theme.id == selectedThemeID)
            }
            .buttonStyle(.plain)
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
