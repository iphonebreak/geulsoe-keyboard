import Foundation

/// 테마 하나의 정의. **데이터 주도** — 새 테마 추가는 번들 JSON에 항목을 더하는 일이지
/// 코드 변경이 아니다.
///
/// 모든 테마는 라이트/다크 팔레트를 쌍으로 가진다. 호스트 앱이 다크 모드면 `dark`,
/// 라이트 모드면 `light`가 자동 적용된다. "항상 어두운 테마"는 두 팔레트를 모두
/// 다크 계열로 정의하는 식으로 만든다 — 스위치가 아니라 데이터로 표현한다.
public struct ThemeSpec: Codable, Equatable, Sendable, Identifiable {

    public var id: String
    public var displayName: String
    public var light: Palette
    public var dark: Palette
    public var keyCornerRadius: Double
    public init(id: String, displayName: String, light: Palette, dark: Palette, keyCornerRadius: Double = 8) {
        self.id = id
        self.displayName = displayName
        self.light = light
        self.dark = dark
        self.keyCornerRadius = keyCornerRadius
    }

    /// 팔레트 색은 `"#RRGGBB"` 또는 `"#RRGGBBAA"` hex 문자열.
    /// 파싱은 프레젠테이션 계층(KeyboardUI)의 몫이다 — 도메인은 문자열만 안다.
    public struct Palette: Codable, Equatable, Sendable {
        public var keyboardBackground: String
        public var characterKey: String
        public var functionKey: String
        public var keyText: String
        public var accent: String

        public init(keyboardBackground: String, characterKey: String, functionKey: String, keyText: String, accent: String) {
            self.keyboardBackground = keyboardBackground
            self.characterKey = characterKey
            self.functionKey = functionKey
            self.keyText = keyText
            self.accent = accent
        }
    }
}
