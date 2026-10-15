import SwiftUI
import Testing
import TadakDomain
@testable import KeyboardUI
import KeyboardCore

/// B5 C12 — 긴 영어 단어 칩. **실기 결함(2026-10-15) 뒤 다시 썼다.**
///
/// 옛 시험은 칸 폭을 `(375 − 2) / 3 − 12`로 잡았다 — 툴바 `HStack`의 간격 10pt × 5, 좌우 여백 10pt × 2, ✕ 30pt가 빠져
/// 칸마다 약 33pt를 넓게 봤고, 그래서 「393pt 이상은 줄지 않는다」는 틀린 결론이 났다. 실기(iPhone 15 Pro, 393pt) 스크린숏
/// `docs/release/device-v131-2/c12-communic-truncated.png`(3배) 픽셀로 잰 구분선은 117pt·235pt, 칩 글자 칸은 85pt다.
/// 여기서는 계산이 아니라 **툴바를 실제로 그려**(`ImageRenderer`, 3배) 구분선 자리와 말줄임 여부를 픽셀로 본다.
///
/// **한계:** macOS에서 SwiftUI가 그린 그림이다. 다만 옛 레이아웃을 같은 방식으로 그리면 실기 스크린숏과 칩 글자 경계가
/// 1px 안에서 같았다(실기 55–294·405–653px ↔ 렌더 54–294·405–654px) — 글꼴 폭·`minimumScaleFactor` 동작이 실기와 맞는다.
/// 기기별 반올림·Dynamic Type은 실기 몫이다.
@MainActor
@Suite("B5 C12 — 긴 영어 단어 칩(그린 화면)")
struct EnglishChipWidthTests {

    private let spec = ThemeSpec(
        id: "chip-probe", displayName: "chip-probe",
        light: .init(keyboardBackground: "#FFFFFF", characterKey: "#FFFFFF",
                     functionKey: "#FFFFFF", keyText: "#000000", accent: "#007AFF"),
        dark: .init(keyboardBackground: "#FFFFFF", characterKey: "#FFFFFF",
                    functionKey: "#FFFFFF", keyText: "#000000", accent: "#007AFF"))
    private let scale: CGFloat = 3

    private struct Image {
        let pixels: [UInt8]
        let width: Int
        let height: Int
        /// 흰 바탕과 다른 픽셀(글자·구분선)
        func ink(_ x: Int, _ y: Int) -> Bool {
            let i = (y * width + x) * 4
            return 765 - Int(pixels[i]) - Int(pixels[i + 1]) - Int(pixels[i + 2]) > 120
        }
    }

    private func pixels(of view: some View) throws -> Image {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Image(pixels: pixels, width: image.width, height: image.height)
    }

    /// 실기와 같은 툴바 — 추천단어 + ✕(닫기 콜백이 있어야 ✕ 자리 30pt가 생긴다)
    private func toolbar(_ candidates: [WordSuggestionCandidate], width: CGFloat) throws -> Image {
        let state = KeyboardViewState(layout: LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik),
                                      themeSpec: spec, wordSuggestions: candidates)
        let theme = ResolvedTheme(spec: spec, appearance: .light, systemColorScheme: .light)
        let view = SuggestionToolbar(
            state: state, theme: theme, onSnippetTap: nil, onWordTap: { _ in }, onPasteboardCodeTap: nil,
            onToolTap: nil, onCursorMove: nil, onDismissSuggestions: {}, onBibleBadgeTap: nil,
            onSnippetArm: nil, onSnippetCandidatesOpen: nil, onKeyPress: nil)
            .frame(width: width, height: KeyboardRootView.toolbarHeight)
            .background(Color.white)
        return try pixels(of: view)
    }

    /// 잉크 열 묶음(글자 사이 틈 < 4pt는 한 묶음) — (시작 x, 끝 x, 위 y, 아래 y)
    private struct Run { var minX: Int; var maxX: Int; var minY: Int; var maxY: Int }

    private func runs(_ image: Image) -> [Run] {
        var result: [Run] = []
        var current: Run?
        var gap = 0
        for x in 0..<image.width {
            let ys = (0..<image.height).filter { image.ink(x, $0) }
            if let top = ys.first, let bottom = ys.last {
                if var run = current, gap < Int(4 * scale) {
                    run.maxX = x; run.minY = min(run.minY, top); run.maxY = max(run.maxY, bottom)
                    current = run
                } else {
                    if let run = current { result.append(run) }
                    current = Run(minX: x, maxX: x, minY: top, maxY: bottom)
                }
                gap = 0
            } else {
                gap += 1
            }
        }
        if let run = current { result.append(run) }
        return result
    }

    /// 구분선 — 폭 2pt 이하·높이 16pt 이상인 묶음(구분선 18pt, 글자는 14pt 안)
    private func isDivider(_ run: Run) -> Bool {
        run.maxX - run.minX + 1 <= Int(2 * scale) && run.maxY - run.minY + 1 >= Int(16 * scale)
    }

    /// 말줄임 판정 — 글자 묶음의 오른쪽 끝 3pt 잉크가 **기준선 근처의 작은 점뿐**이면 「…」다.
    /// (`r`처럼 끝이 작은 글자는 잉크가 위쪽이라 걸리지 않는다. 아래 `detectorCatchesEllipsis`가 이 판정기를 먼저 시험한다)
    private func endsWithEllipsis(_ image: Image, _ run: Run) -> Bool {
        let band = max(run.minX, run.maxX - Int(3 * scale))...run.maxX
        let ys = (run.minY...run.maxY).filter { y in band.contains { image.ink($0, y) } }
        guard let top = ys.first, let bottom = ys.last else { return false }
        let height = run.maxY - run.minY + 1
        return bottom - top + 1 < height / 4 && top > run.minY + height / 2
    }

    // MARK: - 판정기 자체

    @Test("판정기 — 좁은 칸의 「communicati…」는 말줄임, 넉넉한 칸은 아님, `…r` 끝 단어도 아님")
    func detectorCatchesEllipsis() throws {
        func text(_ word: String, width: CGFloat) -> some View {
            Text(word).font(.system(size: 17)).foregroundStyle(.black).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: width, height: 40).background(Color.white)
        }
        let truncated = try pixels(of: text("communication", width: 80))
        let fits = try pixels(of: text("communication", width: 130))
        let endsWithR = try pixels(of: text("together", width: 130))
        #expect(runs(truncated).contains { endsWithEllipsis(truncated, $0) })
        #expect(!runs(fits).contains { endsWithEllipsis(fits, $0) })
        #expect(!runs(endsWithR).contains { endsWithEllipsis(endsWithR, $0) })
    }

    // MARK: - 칸 폭 — 실기 스크린숏과 맞춘 값

    @Test("한글 줄 칸 폭은 그대로 — 구분선이 실기 자리(393pt: 117·235pt)에 선다", arguments: [
        (393.0, [117.0, 235.0]), (375.0, [111.0, 223.0])
    ] as [(Double, [Double])])
    func hangulRowUnchanged(row: (width: Double, dividers: [Double])) throws {
        let image = try toolbar(["사랑합니다", "사랑해요", "사랑"].map(WordSuggestionCandidate.word), width: row.width)
        let dividers = runs(image).filter(isDivider).map { CGFloat($0.minX) / scale }
        #expect(dividers.count == 2)
        for (measured, expected) in zip(dividers, row.dividers) {
            #expect(abs(measured - expected) <= 0.7, "\(measured) vs \(expected)")
        }
    }

    // MARK: - 영어 줄 — 말줄임 없음

    /// (화면 폭, 후보, 보여야 하는 칩 수). `underst`·`than`은 비례 배분으로 셋이 다 들어가는 실제 줄, `communic`은 실기 결함 줄 —
    /// 정확히 재면 0.7배에서 1.3pt 남아 아슬아슬하게 들어가지만 추정(× 0.76)은 안 들어간다고 보고 셋째를 숨긴다(기기 반올림 여유).
    /// `recommend`는 사전 전체에서 가장 넓은 실제 줄, 마지막은 사전에서 가장 넓은 세 단어를 억지로 묶은 줄(17자 최장 포함)
    @Test("영어 줄 — 어느 칩도 말줄임되지 않는다(필요하면 마지막 후보를 숨긴다)", arguments: [
        (393.0, ["understand", "understood", "understanding"], 3),
        (375.0, ["understand", "understood", "understanding"], 3),
        (393.0, ["thank", "thanks", "thanksgiving"], 3),
        (393.0, ["communication", "communicate", "communications"], 2),
        (375.0, ["communication", "communicate", "communications"], 2),
        (393.0, ["recommended", "recommendation", "recommendations"], 2),
        (375.0, ["recommended", "recommendation", "recommendations"], 2),
        (375.0, ["misunderstanding", "misunderstood", "misunderstand"], 2),
        (375.0, ["extraterrestrial", "extraterrestrials"], 2),
        (375.0, ["extraterrestrials", "recommendations", "misunderstanding"], 2),
        (393.0, ["hello", "help", "hell"], 3)
    ] as [(Double, [String], Int)])
    func englishRowNeverTruncates(row: (width: Double, words: [String], chips: Int)) throws {
        let candidates = row.words.map { WordSuggestionCandidate.english($0, typedRun: String($0.prefix(3))) }
        let image = try toolbar(candidates, width: row.width)
        let all = runs(image)
        let dividers = all.filter(isDivider)
        #expect(dividers.count + 1 == row.chips, "칩 수")
        let truncated = all.filter { !isDivider($0) && endsWithEllipsis(image, $0) }.count
        #expect(truncated == 0)
    }

    /// 단어 하나를 1배(17pt)로 따로 그린 잉크 폭(pt)
    private func inkWidth(_ word: String) throws -> CGFloat {
        let image = try pixels(of: Text(word).font(.system(size: 17)).foregroundStyle(.black).fixedSize()
            .padding(8).background(Color.white))
        let text = try #require(runs(image).first)
        return CGFloat(text.maxX - text.minX + 1) / scale
    }

    /// 검증 머지 조건 C1(변이 X1 — `dropLast`를 `dropFirst`로 바꿔 **빈도 최고 후보를 숨겨도** 칩 개수 시험은 통과했다).
    /// 숨김 줄에서 남는 두 칩은 1배로 그려진다(두 칸이면 칸 글자 폭 135pt 이상 — 배분식 1·2단계) → 칩 잉크 폭이 **앞의 두 단어**의
    /// 단독 렌더 폭과 같아야 한다. 이 줄들의 앞 둘과 뒤 둘은 폭이 3pt 넘게 달라(`communication` 117 ↔ `communications` 125) 구별된다
    @Test("셋째를 숨긴 줄은 앞의 두 후보(빈도 상위)를 보인다", arguments: [
        (393.0, ["communication", "communicate", "communications"]),
        (375.0, ["communication", "communicate", "communications"]),
        (393.0, ["recommended", "recommendation", "recommendations"]),
        (375.0, ["misunderstanding", "misunderstood", "misunderstand"])
    ] as [(Double, [String])])
    func hiddenRowShowsTopTwo(row: (width: Double, words: [String])) throws {
        let candidates = row.words.map { WordSuggestionCandidate.english($0, typedRun: String($0.prefix(3))) }
        let image = try toolbar(candidates, width: row.width)
        // ✕(오른쪽 끝 30pt 버튼, 글리프 ≈ 폭 − 31pt)는 칩이 아니다 — 오른쪽 40pt 안에서 시작하는 묶음은 뺀다
        let chips = runs(image).filter { !isDivider($0) && $0.minX < Int((row.width - 40) * scale) }
            .map { CGFloat($0.maxX - $0.minX + 1) / scale }
        #expect(chips.count == 2, "칩 수")
        let expected = try row.words.prefix(2).map(inkWidth)
        for (measured, want) in zip(chips, expected) {
            #expect(abs(measured - want) <= 1, "\(measured) vs \(want)")
        }
    }

    /// 권고 X7(변이 — 자간 여유 상한 0.76을 0.80으로 올려도 살아남았다). 실제 사전 줄 중 **0.76이면 들어가고 0.80이면 숨겨지는** 경계 사례:
    /// 영어 줄 몫(393pt 333 · 375pt 315)에서 최소 폭 = 글자 합 × 상한 + 여백 36 + 구분선·간격 42. 글자 합이 393pt `understand` 줄 323.9pt,
    /// 375pt `commu` 줄 304.6pt라 상한 0.76이면 323.9 → 324.2 ≤ 333 · 304.6 → 309.5 ≤ 315, 0.80이면 337.1 · 321.7로 넘친다.
    /// 둘 다 실제로는 0.7배 안에 들어가는 줄이다(말줄임 0) — 상한을 올리면 들어가는 줄에서 셋째를 숨겨 실패한다
    @Test("경계 사례 — 0.76이면 들어가는 줄은 셋 다 보인다(상한을 올리면 숨겨 실패)", arguments: [
        (393.0, ["understanding", "understands", "understandable"]),
        (375.0, ["community", "communication", "communicate"])
    ] as [(Double, [String])])
    func boundaryRowKeepsThree(row: (width: Double, words: [String])) throws {
        let candidates = row.words.map { WordSuggestionCandidate.english($0, typedRun: String($0.prefix(3))) }
        let image = try toolbar(candidates, width: row.width)
        let all = runs(image)
        #expect(all.filter(isDivider).count + 1 == 3, "칩 수")
        #expect(all.filter { !isDivider($0) && endsWithEllipsis(image, $0) }.isEmpty)
    }

    @Test("짧은 영어 줄은 지금 모양 그대로 — 같은 폭(한글 줄과 같은 구분선 자리)")
    func shortEnglishRowKeepsEqualWidths() throws {
        let image = try toolbar(["hello", "help", "hell"].map { .english($0, typedRun: "hel") }, width: 393)
        let dividers = runs(image).filter(isDivider).map { CGFloat($0.minX) / scale }
        #expect(dividers.count == 2)
        for (measured, expected) in zip(dividers, [117.0, 235.0]) { #expect(abs(measured - expected) <= 0.7) }
    }

    @Test("영어 후보 칩은 영어로 표시된다 — 한글·이모지 칩은 아니다")
    func englishFlag() {
        #expect(WordSuggestionCandidate.english("hello", typedRun: "hel").isEnglish)
        #expect(!WordSuggestionCandidate.word("안녕").isEnglish)
    }
}

/// 배분식 — 그린 화면 없이 수만 본다
@Suite("B5 C12 — 영어 칩 폭 배분식")
struct EnglishChipWidthFormulaTests {

    @Test("모두 같은 폭 칸에 들어가면 같은 폭(지금 모양)")
    func equalWhenAllFit() {
        #expect(KeyboardMetrics.englishChipWidths(naturalWidths: [48, 52, 60], available: 291, padding: 6) == [97, 97, 97])
    }

    @Test("1배 폭 합이 들어가면 각자 1배 폭 + 남는 폭을 똑같이")
    func naturalPlusExtra() {
        #expect(KeyboardMetrics.englishChipWidths(naturalWidths: [60, 60, 141], available: 291, padding: 6) == [70, 70, 151])
    }

    @Test("안 들어가면 글자 폭에 비례 — 글자 배율이 모두 같다")
    func proportional() {
        let naturals: [CGFloat] = [128.8, 115.1, 137.3]   // communication·communicate·communications + 여백 12
        let widths = KeyboardMetrics.englishChipWidths(naturalWidths: naturals, available: 291, padding: 6)
        #expect(abs(widths.reduce(0, +) - 291) < 0.001)
        let ratios = zip(widths, naturals).map { ($0 - 12) / ($1 - 12) }
        #expect(ratios.allSatisfy { abs($0 - ratios[0]) < 0.0001 })
    }

    @Test("최소 폭 — 글자 × 0.76 + 여백 + 구분선·간격. 393pt 줄(영어 줄 몫 333pt)에 underst 줄은 들어가고 communic·recommend 줄은 안 들어간다")
    func minimumWidth() {
        let understand: [CGFloat] = [98.7, 99.4, 121.9]
        let communic: [CGFloat] = [128.8, 115.1, 137.3]
        let recommend: [CGFloat] = [122.6, 140.8, 149.3]
        let rowWidth: CGFloat = 393 - 20 - 10 - 30   // 좌우 여백 · ✕ 앞 간격 · ✕
        #expect(KeyboardMetrics.englishRowMinimumWidth(naturalWidths: understand, padding: 6) <= rowWidth)
        #expect(KeyboardMetrics.englishRowMinimumWidth(naturalWidths: communic, padding: 6) > rowWidth)
        #expect(KeyboardMetrics.englishRowMinimumWidth(naturalWidths: recommend, padding: 6) > rowWidth)
        #expect(KeyboardMetrics.englishRowFixedWidth(chips: 3) == 42)
    }
}
