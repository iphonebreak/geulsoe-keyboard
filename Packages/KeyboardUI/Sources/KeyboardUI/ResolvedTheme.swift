import SwiftUI
import TadakDomain

/// `ThemeSpec`(도메인, hex 문자열) → SwiftUI `Color` 해석. hex 파싱은 프레젠테이션의 몫.
///
/// 팔레트 선택 규칙: `Appearance`가 강제(light/dark)면 그것을, `system`이면
/// 호스트 앱의 colorScheme을 따른다. 모든 테마가 light/dark 쌍을 갖고 있어
/// "항상 어두운 테마"도 데이터로 표현된다 (pure-dark는 두 팔레트 모두 다크 계열).
public struct ResolvedTheme: Equatable {

    public let keyboardBackground: Color
    public let characterKey: Color
    public let functionKey: Color
    public let keyText: Color
    public let accent: Color
    public let keyCornerRadius: CGFloat
    public let isDark: Bool

    public init(spec: ThemeSpec, appearance: Appearance, systemColorScheme: ColorScheme) {
        let usesDarkPalette: Bool
        switch appearance {
        case .light: usesDarkPalette = false
        case .dark: usesDarkPalette = true
        case .system: usesDarkPalette = (systemColorScheme == .dark)
        }
        let palette = usesDarkPalette ? spec.dark : spec.light

        self.keyboardBackground = Color(hex: palette.keyboardBackground)
        self.characterKey = Color(hex: palette.characterKey)
        self.functionKey = Color(hex: palette.functionKey)
        self.keyText = Color(hex: palette.keyText)
        self.accent = Color(hex: palette.accent)
        self.keyCornerRadius = CGFloat(spec.keyCornerRadius)
        self.isDark = usesDarkPalette
    }
}

extension Color {
    /// `"#RRGGBB"` / `"#RRGGBBAA"` 파싱. 형식이 깨졌으면 자홍색 — 테마 JSON 오류를
    /// 조용히 검정으로 숨기지 않고 눈에 띄게 만든다.
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard Scanner(string: cleaned).scanHexInt64(&value),
              cleaned.count == 6 || cleaned.count == 8 else {
            self = .init(red: 1, green: 0, blue: 1)
            return
        }
        if cleaned.count == 6 { value = (value << 8) | 0xFF }
        self = .init(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}

/// 키캡 표면 — 테마 색 단색 + 1pt 아래 그림자. **OS 버전별 표면 분기는 이 타입 밖으로 내보내지 않는다.**
///
/// iOS 26 Liquid Glass는 쓰지 않는다 (2026-09-07 최종 — 실기 iOS 26.1에서 유리가 납작한 회색으로만 렌더되고
/// 상시 유리·인트로·옵트인 테마 세 가지 시도 모두 문제가 있어 테마와 함께 삭제. 근거: PDR clean-architecture-and-themes).
public struct KeyCapSurface: ViewModifier {

    let background: Color
    let cornerRadius: CGFloat

    public init(background: Color, cornerRadius: CGFloat) {
        self.background = background
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(background, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1)
    }
}
