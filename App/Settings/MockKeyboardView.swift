import SwiftUI
import TadakDomain

// 채움글 안내 애니메이션용 **모형 키보드**. 앱은 KeyboardUI를 import하지 않는다(PDR settings-app 결정 5)는
// 결정을 지키기 위해 스타일 상수를 의도적으로 복제한다. 각 복제에는 `mirror:` 주석으로 출처를 남긴다 —
// KeyboardUI의 칩·키 스타일이 바뀌면 여기도 맞춘다 (CLAUDE.md 채움글 단락, release-and-review 체크리스트).
//
// mirror: KeyboardUI/ResolvedTheme.swift        ResolvedTheme(팔레트 선택 규칙) · KeyCapSurface(단색 + 1pt 그림자)
// mirror: KeyboardUI/KeyCapView.swift           faceFontSize(22/16, 심볼 medium) · keyBackground(눌림 60%) · preview(34pt 풍선)
//                                               · 힌트(10pt, keyText 55%)
// mirror: KeyboardUI/KeyboardRootView.swift     toolbarHeight 46 · SuggestionToolbar(spacing 10, 좌우 10, 도구 20pt/85%,
//                                               ✕ 30×38) · SnippetChip(14pt bold 제목 + 14pt 본문, 12/7 패딩, Capsule)
//                                               · KeyboardLayoutView(행 간격 7, 키 간격 5, 좌우 3, 아래 4)
// mirror: KeyboardCore/LayoutDefinition.swift   dubeolsik 3행 + bottomRow(languageLabel: "ABC").removingGlobe()

// MARK: - 팔레트

/// mirror: KeyboardUI/ResolvedTheme.swift ResolvedTheme
struct MockKeyboardPalette: Equatable {
    let keyboardBackground: Color
    let characterKey: Color
    let functionKey: Color
    let keyText: Color
    let accent: Color
    let keyCornerRadius: CGFloat

    /// 팔레트 선택 규칙은 키보드와 같다 — 모드가 강제(light/dark)면 그것을, 시스템이면 호스트 colorScheme을 따른다.
    init(spec: ThemeSpec, appearance: Appearance, systemColorScheme: ColorScheme) {
        let usesDarkPalette: Bool
        switch appearance {
        case .light: usesDarkPalette = false
        case .dark: usesDarkPalette = true
        case .system: usesDarkPalette = (systemColorScheme == .dark)
        }
        let palette = usesDarkPalette ? spec.dark : spec.light
        keyboardBackground = Color(themeHex: palette.keyboardBackground)
        characterKey = Color(themeHex: palette.characterKey)
        functionKey = Color(themeHex: palette.functionKey)
        keyText = Color(themeHex: palette.keyText)
        accent = Color(themeHex: palette.accent)
        keyCornerRadius = CGFloat(spec.keyCornerRadius)
    }
}

// MARK: - 배열

/// mirror: KeyboardCore/LayoutDefinition.swift `dubeolsik` + `bottomRow("ABC")` + `removingGlobe()`
/// (Face ID 기기에서는 시스템이 지구본을 제공해 하단 행이 [123][ABC][스페이스 4.4][.][⏎]가 된다)
enum MockDubeolsikLayout {

    struct Key: Identifiable, Equatable {
        enum Face: Equatable {
            case label(String)
            case symbol(String)
        }
        let id: String
        let face: Face
        var width: Double = 1
        var isFunctionKey = false
        /// 길게 누르기 힌트 (문장부호 키의 ",")
        var hint: String?

        var label: String? {
            if case .label(let text) = face { return text }
            return nil
        }
    }

    /// mirror: KeyboardCore/LayoutDefinition.swift `longPressSymbolRows` — 설정 `longPressSymbolsEnabled`가 켜져 있을 때
    /// 문자 키 귀퉁이에 보이는 기호 = 기호 자판 1페이지 2·3·4행 (1행 `[]{}#%^*+=` · 2행 `-/:;()₩&@"` · 3행 `.,?!'`)
    static let longPressSymbolRows: [String] = ["[]{}#%^*+=", "-/:;()₩&@\"", ".,?!'"]

    static func rows(longPressHints: Bool) -> [[Key]] {
        let base: [[Key]] = [
            "ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ".map { jamo($0) },
            "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ".map { jamo($0) },
            [Key(id: "shift", face: .symbol("shift"), width: 1.4, isFunctionKey: true)]
                + "ㅋㅌㅊㅍㅠㅜㅡ".map { jamo($0) }
                + [Key(id: "backspace", face: .symbol("delete.left"), width: 1.4, isFunctionKey: true)],
            [
                Key(id: "symbols", face: .label("123"), width: 1.2, isFunctionKey: true),
                Key(id: "language", face: .label("ABC"), width: 1.2, isFunctionKey: true),
                Key(id: "space", face: .label(" "), width: 4.4),
                Key(id: "punct", face: .label("."), width: 1.2, hint: ","),
                Key(id: "return", face: .symbol("return"), width: 1.6, isFunctionKey: true)
            ]
        ]
        guard longPressHints else { return base }
        // mirror: LayoutDefinition.addingLongPressSymbols — 문자 키에만, 행 안 순서대로
        return base.enumerated().map { rowIndex, row in
            guard rowIndex < longPressSymbolRows.count else { return row }
            var remaining = longPressSymbolRows[rowIndex].makeIterator()
            return row.map { key in
                guard !key.isFunctionKey, key.hint == nil, let symbol = remaining.next() else { return key }
                var copy = key
                copy.hint = String(symbol)
                return copy
            }
        }
    }

    private static func jamo(_ character: Character) -> Key {
        Key(id: "hangul-\(character)", face: .label(String(character)))
    }
}

// MARK: - 키보드 (툴바 + 자판)

/// 실제 키보드와 같은 치수(폭 360 · 툴바 46 · 자판 216 · 아래 4)로 그린다. 입력은 없다 — 장면 값만 반영한다.
struct MockKeyboardView: View {

    let scene: SnippetIntroScene
    let palette: MockKeyboardPalette
    let showsKeyPreview: Bool
    /// 설정 `longPressSymbolsEnabled` — 켜져 있으면 실제 키보드처럼 문자 키 귀퉁이에 기호 힌트가 보인다
    var showsLongPressHints = true

    /// mirror: KeyboardUI/KeyboardRootView.swift `KeyboardRootView.toolbarHeight`
    static let toolbarHeight: CGFloat = 46
    /// 자판 높이 — 실제 키보드의 높이 배율 ≈83%에 해당(216 × 0.83). 카드가 너무 높다는 피드백(2026-09-08)으로
    /// 100%(216)에서 낮췄다. 행 높이 (180 − 21) / 4 = 39.75. 툴바·간격·키 스타일은 그대로다.
    static let keysHeight: CGFloat = 180
    static let bottomPadding: CGFloat = 4
    static let width: CGFloat = 360
    static var height: CGFloat { toolbarHeight + keysHeight + bottomPadding }

    var body: some View {
        VStack(spacing: 0) {
            MockToolbar(scene: scene, palette: palette)
                .frame(height: Self.toolbarHeight)
            MockKeyGrid(pressedKeyLabel: scene.pressedKeyLabel, palette: palette, showsKeyPreview: showsKeyPreview,
                        showsLongPressHints: showsLongPressHints)
                .frame(height: Self.keysHeight)
                .padding(.horizontal, 3)
                .padding(.bottom, Self.bottomPadding)
        }
        .frame(width: Self.width, height: Self.height)
        .background(palette.keyboardBackground)
    }
}

/// mirror: KeyboardUI/KeyboardRootView.swift `SuggestionToolbar`
private struct MockToolbar: View {

    let scene: SnippetIntroScene
    let palette: MockKeyboardPalette

    var body: some View {
        HStack(spacing: 10) {
            switch scene.toolbarMode {
            case .tools:
                // 기본 도구 순서 중 Full Access 없이도 보이는 것들 (클립보드 제외)
                toolIcon("keyboard.chevron.compact.down")
                toolIcon("chevron.left")
                toolIcon("chevron.right")
                toolIcon("face.smiling")
            case .chip:
                MockSnippetChip(palette: palette, isPressed: scene.chipPressed, showsTapIndicator: scene.showsTapIndicator)
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.keyText.opacity(0.6))
                    .frame(width: 30, height: 38)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10)
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(palette.keyText.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 38)
            .transition(.opacity)
    }
}

/// mirror: KeyboardUI/KeyboardRootView.swift `SnippetChip` — 제목 굵게 + 본문 첫 줄(폭에 맞춰 … 절단)
private struct MockSnippetChip: View {

    let palette: MockKeyboardPalette
    let isPressed: Bool
    let showsTapIndicator: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("[\(SnippetIntroDemo.title)]")
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            Text(SnippetIntroDemo.body)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(palette.keyText)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(palette.characterKey.opacity(isPressed ? 0.6 : 1), in: Capsule())
        .overlay(alignment: .leading) {
            // 손가락 표시 — 제목 위에 잠깐 나타난다
            Circle()
                .fill(palette.keyText.opacity(0.3))
                .overlay(Circle().strokeBorder(palette.keyText.opacity(0.6), lineWidth: 1))
                .frame(width: 30, height: 30)
                .scaleEffect(showsTapIndicator ? 1 : 0.6)
                .opacity(showsTapIndicator ? 1 : 0)
                .padding(.leading, 40)
                .offset(y: 6)
        }
    }
}

/// mirror: KeyboardUI/KeyboardRootView.swift `KeyboardLayoutView` — 행 간격 7, 키 간격 5, 폭은 행 단위 합 비례
private struct MockKeyGrid: View {

    let pressedKeyLabel: String?
    let palette: MockKeyboardPalette
    let showsKeyPreview: Bool
    let showsLongPressHints: Bool

    var body: some View {
        let rows = MockDubeolsikLayout.rows(longPressHints: showsLongPressHints)
        GeometryReader { geometry in
            VStack(spacing: 7) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    rowView(row, totalWidth: geometry.size.width)
                }
            }
        }
    }

    private func rowView(_ row: [MockDubeolsikLayout.Key], totalWidth: CGFloat) -> some View {
        let totalUnits = row.reduce(0) { $0 + $1.width }
        let spacing: CGFloat = 5
        let available = totalWidth - spacing * CGFloat(row.count - 1)
        return HStack(spacing: spacing) {
            ForEach(row) { key in
                MockKeyCap(
                    key: key,
                    isPressed: key.label != nil && key.label == pressedKeyLabel,
                    showsPreview: showsKeyPreview,
                    palette: palette
                )
                .frame(width: available * CGFloat(key.width) / CGFloat(totalUnits))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// mirror: KeyboardUI/KeyCapView.swift — 표면·글자 크기·눌림·미리보기·힌트
private struct MockKeyCap: View {

    let key: MockDubeolsikLayout.Key
    let isPressed: Bool
    let showsPreview: Bool
    let palette: MockKeyboardPalette

    var body: some View {
        face
            .foregroundStyle(palette.keyText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                if let hint = key.hint {
                    Text(hint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(palette.keyText.opacity(0.55))
                        .padding(.top, 3)
                        .padding(.trailing, 5)
                }
            }
            // mirror: KeyCapSurface — 단색 + 1pt 아래 그림자
            .background(background, in: .rect(cornerRadius: palette.keyCornerRadius))
            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1)
            .overlay(alignment: .top) {
                if isPressed, showsPreview, !key.isFunctionKey, key.id != "space" {
                    preview
                }
            }
    }

    @ViewBuilder
    private var face: some View {
        switch key.face {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 22, weight: .medium))
        case .label(let text):
            Text(text)
                .font(.system(size: key.isFunctionKey ? 16 : 22))
                .lineLimit(1)
        }
    }

    private var background: Color {
        let base = key.isFunctionKey ? palette.functionKey : palette.characterKey
        return isPressed ? base.opacity(0.6) : base
    }

    /// mirror: KeyCapView.preview — 34pt, 최소 46×52, characterKey 모서리 8, 그림자 2, 위로 56
    private var preview: some View {
        Text(key.label ?? "")
            .font(.system(size: 34))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(palette.keyText)
            .padding(.horizontal, 8)
            .frame(minWidth: 46, minHeight: 52)
            .background(palette.characterKey, in: .rect(cornerRadius: 8))
            .shadow(radius: 2)
            .offset(y: -56)
    }
}
