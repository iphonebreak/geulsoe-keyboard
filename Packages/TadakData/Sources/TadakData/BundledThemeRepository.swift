import Foundation
import TadakDomain

/// 번들 `Themes.json`에서 테마를 읽는다.
///
/// JSON이 깨졌거나 리소스가 없으면 코드에 내장된 최소 `system` 테마로 폴백한다 —
/// 키보드가 테마 문제로 안 뜨는 일은 없어야 한다.
public struct BundledThemeRepository: ThemeRepository, Sendable {

    private let themes: [ThemeSpec]

    /// - Parameter bundle: 테스트에서 다른 번들을 주입할 때만 쓴다. `nil`이면 패키지 리소스 번들.
    public init(bundle: Bundle? = nil) {
        let bundle = bundle ?? .module
        if let url = bundle.url(forResource: "Themes", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ThemeSpec].self, from: data),
           !decoded.isEmpty {
            self.themes = decoded
        } else {
            self.themes = [Self.fallbackSystemTheme]
        }
    }

    public func availableThemes() -> [ThemeSpec] {
        themes
    }

    public func theme(id: String) -> ThemeSpec {
        themes.first { $0.id == id }
            ?? themes.first { $0.id == "system" }
            ?? Self.fallbackSystemTheme
    }

    /// JSON 로드가 완전히 실패했을 때의 최후 보루. `Themes.json`의 system 항목과 같은 값.
    static let fallbackSystemTheme = ThemeSpec(
        id: "system",
        displayName: "시스템",
        light: .init(
            keyboardBackground: "#D1D3D9",
            characterKey: "#FFFFFF",
            functionKey: "#ADB2BC",
            keyText: "#000000",
            accent: "#007AFF"
        ),
        dark: .init(
            keyboardBackground: "#2A2A2C",
            characterKey: "#6B6B6D",
            functionKey: "#454547",
            keyText: "#FFFFFF",
            accent: "#0A84FF"
        )
    )
}
