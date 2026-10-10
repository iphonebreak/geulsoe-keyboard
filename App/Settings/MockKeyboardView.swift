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
//                                               ✕ 30×38) · KeyboardLayoutView(행 간격 7, 키 간격 5, 좌우 3, 아래 4)
// mirror: KeyboardUI/SnippetChip.swift          SnippetChip(14pt bold 제목 + 14pt 본문, 12/7 패딩, Capsule)
// mirror: KeyboardCore/LayoutDefinition.swift   dubeolsik 3행(+ shiftedLabel) + bottomRow(languageLabel: "ABC").removingGlobe()
// mirror: KeyboardUI/KeyboardRootView.swift     bibleBadge(book 12pt semibold + 13pt 숫자, 좌우 8, 높이 28, functionKey Capsule)
//                                               · 추천단어(17pt, 좌우 6 · 위아래 10, 사이 구분선 1×18 keyText 20%)
// mirror: KeyboardUI/BibleSearchPanelView.swift 책 칩(13pt, 선택 accent/keyboardBackground, 좌우 10 · 위아래 6, Capsule)
//                                               · 행(참조 13pt semibold keyText 70% + 미리보기 14pt, 좌우 10, characterKey 배경)
//                                               · 형광펜(accent, 라이트 0.38 / 다크 0.45) · 돌아가기(PanelBarButton, functionKey)

// MARK: - 팔레트

/// mirror: KeyboardUI/ResolvedTheme.swift ResolvedTheme
struct MockKeyboardPalette: Equatable {
    let keyboardBackground: Color
    let characterKey: Color
    let functionKey: Color
    let keyText: Color
    let accent: Color
    let keyCornerRadius: CGFloat
    /// 어두운 팔레트인가 — 형광펜 불투명도가 갈린다 (mirror: ResolvedTheme.isDark)
    let isDark: Bool

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
        isDark = usesDarkPalette
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
        /// ⇧ 라벨 — mirror: LayoutDefinition.dubeolsik `character(_:_:_:)`의 세 번째 인자(쌍자음·ㅒㅖ)
        var shiftedLabel: String?

        var label: String? {
            if case .label(let text) = face { return text }
            return nil
        }

        /// 지금 보이는 라벨 — ⇧가 켜져 있으면 쌍자음
        func displayedLabel(isShifted: Bool) -> String? {
            isShifted ? (shiftedLabel ?? label) : label
        }
    }

    /// mirror: LayoutDefinition.dubeolsik 1행 시프트 라벨
    static let shiftedLabels: [Character: String] = [
        "ㅂ": "ㅃ", "ㅈ": "ㅉ", "ㄷ": "ㄸ", "ㄱ": "ㄲ", "ㅅ": "ㅆ", "ㅐ": "ㅒ", "ㅔ": "ㅖ"
    ]

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
        Key(id: "hangul-\(character)", face: .label(String(character)), shiftedLabel: shiftedLabels[character])
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
            Group {
                if scene.showsBiblePanel {
                    // 배지를 누르면 자판 자리를 구절 목록이 차지한다 (v1.2.0 ⑦ 시나리오의 결과)
                    MockBiblePanel(palette: palette)
                        .transition(.opacity)
                } else {
                    MockKeyGrid(pressedKeyLabel: scene.pressedKeyLabel, isShifted: scene.isShifted, palette: palette,
                                showsKeyPreview: showsKeyPreview, showsLongPressHints: showsLongPressHints)
                }
            }
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
                if case .chip(let title, let body) = scene.scenario.reaction {
                    MockSnippetChip(title: title, bodyText: body, palette: palette, isPressed: scene.chipPressed,
                                    showsTapIndicator: scene.showsTapIndicator)
                        .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                dismissMark
            case .bible:
                // mirror: SuggestionToolbar 후보 + 배지 — 추천단어가 남은 폭을 나누고 배지·✕가 오른쪽 끝
                ForEach(Array(SnippetIntroBibleDemo.words.enumerated()), id: \.offset) { index, word in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.keyText.opacity(0.2))
                            .frame(width: 1, height: 18)
                    }
                    Text(word)
                        .font(.system(size: 17))
                        .foregroundStyle(palette.keyText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                }
                MockBibleBadge(palette: palette, isPressed: scene.chipPressed, showsTapIndicator: scene.showsTapIndicator)
                    .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.85)).combined(with: .opacity))
                dismissMark
            }
        }
        .padding(.horizontal, 10)
    }

    private var dismissMark: some View {
        Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(palette.keyText.opacity(0.6))
            .frame(width: 30, height: 38)
            .transition(.opacity)
    }

    private func toolIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(palette.keyText.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 38)
            .transition(.opacity)
    }
}

/// mirror: KeyboardUI/SnippetChip.swift `SnippetChip`(`SnippetChipFace`) — 제목 굵게 + 본문 첫 줄(폭에 맞춰 … 절단)
private struct MockSnippetChip: View {

    let title: String
    /// 칩 미리보기 = 본문 첫 줄 (실제 칩도 `body`가 미리보기이자 삽입값이다)
    let bodyText: String
    let palette: MockKeyboardPalette
    let isPressed: Bool
    let showsTapIndicator: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("[\(title)]")
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            Text(bodyText)
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

/// mirror: KeyboardUI/KeyboardRootView.swift `bibleBadge` · `badgeCapsule` — 책 아이콘 + 건수, functionKey 캡슐
private struct MockBibleBadge: View {

    let palette: MockKeyboardPalette
    let isPressed: Bool
    let showsTapIndicator: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "book")
                .font(.system(size: 12, weight: .semibold))
            Text(SnippetIntroBibleDemo.count)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(palette.keyText)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(palette.functionKey.opacity(isPressed ? 0.6 : 1), in: Capsule())
        .fixedSize()
        .overlay {
            // 손가락 표시 — 칩과 같은 표현
            Circle()
                .fill(palette.keyText.opacity(0.3))
                .overlay(Circle().strokeBorder(palette.keyText.opacity(0.6), lineWidth: 1))
                .frame(width: 30, height: 30)
                .scaleEffect(showsTapIndicator ? 1 : 0.6)
                .opacity(showsTapIndicator ? 1 : 0)
                .offset(y: 6)
        }
    }
}

/// mirror: KeyboardUI/BibleSearchPanelView.swift — 책 필터 줄 + 결과 행 + 돌아가기.
/// 자판 높이(180)에 맞춰 줄였다(실제 216) — 행은 3개만 보인다. 데모 값은 `SnippetIntroBibleDemo`(실데이터 복제).
private struct MockBiblePanel: View {

    let palette: MockKeyboardPalette

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                ForEach(Array(SnippetIntroBibleDemo.filters.enumerated()), id: \.offset) { index, label in
                    let selected = index == 0   // 「전체」
                    Text(label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(selected ? palette.keyboardBackground : palette.keyText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected ? palette.accent : palette.functionKey, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            .frame(height: 30, alignment: .leading)
            .clipped()
            Rectangle()
                .fill(palette.keyText.opacity(0.15))
                .frame(height: 1)
            ForEach(Array(SnippetIntroBibleDemo.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.reference)
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(palette.keyText.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                    Text(highlighted(row.preview))
                        .font(.system(size: 14))
                        .foregroundStyle(palette.keyText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(palette.characterKey, in: RoundedRectangle(cornerRadius: palette.keyCornerRadius))
            }
            Text("돌아가기")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.keyText)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(palette.functionKey, in: RoundedRectangle(cornerRadius: palette.keyCornerRadius))
        }
        .padding(.horizontal, 1)
    }

    /// mirror: BibleSearchPanelView.highlighted — 검색어 자리에만 accent 배경(라이트 0.38 / 다크 0.45)
    private func highlighted(_ preview: String) -> AttributedString {
        var attributed = AttributedString(preview)
        let opacity = palette.isDark ? 0.45 : 0.38
        var searchStart = attributed.startIndex
        while let range = attributed[searchStart...].range(of: SnippetIntroBibleDemo.query) {
            attributed[range].backgroundColor = palette.accent.opacity(opacity)
            searchStart = range.upperBound
        }
        return attributed
    }
}

/// mirror: KeyboardUI/KeyboardRootView.swift `KeyboardLayoutView` — 행 간격 7, 키 간격 5, 폭은 행 단위 합 비례
private struct MockKeyGrid: View {

    let pressedKeyLabel: String?
    let isShifted: Bool
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
                    // 문자 키는 **보이는 라벨**로, 기능 키(⇧)는 id로 찾는다 — ⇧가 켜지면 ㅈ 키가 ㅉ로 보인다
                    isPressed: pressedKeyLabel != nil
                        && (key.displayedLabel(isShifted: isShifted) == pressedKeyLabel || key.id == pressedKeyLabel),
                    isShifted: isShifted,
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
    let isShifted: Bool
    let showsPreview: Bool
    let palette: MockKeyboardPalette

    private var labelText: String { key.displayedLabel(isShifted: isShifted) ?? "" }

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
            // mirror: KeyCapView — ⇧ 한 번이면 `shift.fill`
            Image(systemName: key.id == "shift" && isShifted ? "shift.fill" : name)
                .font(.system(size: 22, weight: .medium))
        case .label:
            Text(labelText)
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
        Text(labelText)
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
