import Testing
import SwiftUI
import TadakDomain
@testable import KeyboardUI

@Suite("테마 해석")
struct ResolvedThemeTests {

    private let spec = ThemeSpec(
        id: "test", displayName: "테스트",
        light: .init(keyboardBackground: "#FFFFFF", characterKey: "#EEEEEE",
                     functionKey: "#CCCCCC", keyText: "#000000", accent: "#007AFF"),
        dark: .init(keyboardBackground: "#000000", characterKey: "#222222",
                    functionKey: "#111111", keyText: "#FFFFFF", accent: "#0A84FF")
    )

    @Test("system 모드는 호스트 colorScheme을 따른다")
    func systemFollowsColorScheme() {
        let light = ResolvedTheme(spec: spec, appearance: .system, systemColorScheme: .light)
        let dark = ResolvedTheme(spec: spec, appearance: .system, systemColorScheme: .dark)
        #expect(light.isDark == false)
        #expect(dark.isDark)
        #expect(light != dark)
    }

    @Test("강제 light/dark는 colorScheme을 무시한다")
    func forcedAppearanceOverrides() {
        let forcedLight = ResolvedTheme(spec: spec, appearance: .light, systemColorScheme: .dark)
        let forcedDark = ResolvedTheme(spec: spec, appearance: .dark, systemColorScheme: .light)
        #expect(forcedLight.isDark == false)
        #expect(forcedDark.isDark)
    }

    @Test("hex 6자리와 8자리를 파싱한다")
    func hexParsing() {
        #expect(Color(hex: "#FF0000") == Color(red: 1, green: 0, blue: 0, opacity: 1))
        #expect(Color(hex: "00FF00") == Color(red: 0, green: 1, blue: 0, opacity: 1))
        #expect(Color(hex: "#0000FF80") == Color(red: 0, green: 0, blue: 1, opacity: Double(0x80) / 255))
    }

    @Test("깨진 hex는 자홍색으로 눈에 띄게 실패한다", arguments: ["", "#GG0000", "#FFF", "#12345"])
    func brokenHexIsMagenta(hex: String) {
        #expect(Color(hex: hex) == Color(red: 1, green: 0, blue: 1))
    }
}
