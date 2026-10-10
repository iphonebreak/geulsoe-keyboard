import SwiftUI
import Testing
import TadakDomain
import KeyboardCore
@testable import KeyboardUI

// U7 ② — 채움글 칩 길게 누르기·「+n」·후보 패널(KeyboardUI 몫).
// 지시서 `docs/design-reviews/external-snippet-packs-u7-plan.md` 2절 ② · PDR 10-6 ④⑤⑥⑦ · AC-42·43·46 · R32.
// 열고 닫는 배선(VC)은 ③ — 여기서는 상태기계·문구·그림만 본다.

// MARK: - 누름 상태기계

/// 칩 제스처 뷰 자체는 `swift test`가 누를 수 없다 — 판정은 값 타입 `ChipPressState`로 떼어 여기서 표로 잠근다.
@Suite("채움글 칩 — 누름 상태기계(AC-43)")
struct ChipPressStateTests {

    enum Step {
        case down
        case move(inside: Bool)
        /// 450ms — `canArm`은 조립 지점의 대답(꼬리 정합·후보 2개 이상)
        case timer(canArm: Bool)
        case release(inside: Bool)
        case reset
    }

    struct Run {
        var release: ChipPressState.Release?
        /// 무장 피드백(소리·FA일 때 진동) 횟수
        var feedback = 0
        /// 조립 지점에 무장을 물은 횟수
        var armQueries = 0
        var final = ChipPressState()
    }

    /// 칩 뷰(`SnippetChip.pressGesture`·`startArmTimer`)가 상태기계를 부르는 방식 그대로 흉내 낸다
    private func run(_ steps: [Step]) -> Run {
        var state = ChipPressState()
        var result = Run()
        for step in steps {
            switch step {
            case .down:
                state.touchDown()
            case .move(let inside):
                state.move(inside: inside)
            case .timer(let canArm):
                if state.timerFired(canArm: { result.armQueries += 1; return canArm }) { result.feedback += 1 }
            case .release(let inside):
                result.release = state.release(inside: inside)
            case .reset:
                state.reset()
            }
        }
        result.final = state
        return result
    }

    @Test("표 — 짧은 탭·무장 뒤 손 뗌·무장 불가·이동 취소·늦은 타이머", arguments: [
        // (단계, 손 뗄 때 결과, 피드백 수, 무장 물음 수)
        ([Step.down, .release(inside: true)], ChipPressState.Release.tap, 0, 0),
        ([.down, .move(inside: true), .release(inside: true)], .tap, 0, 0),
        // 450ms 무장 → 손 뗄 때 연다(무장 순간이 아니다) · 짧은 탭은 안 한다
        ([.down, .timer(canArm: true), .release(inside: true)], .openCandidates, 1, 1),
        // 무장 불가(후보 1개 · 퇴장 중 칩 · 꼬리 어긋남) — 점선·피드백 없이 지금 칩과 같게: 떼면 짧은 탭
        ([.down, .timer(canArm: false), .release(inside: true)], .tap, 0, 1),
        // 무장한 채 칩 안에서 움직여도 무장 유지
        ([.down, .timer(canArm: true), .move(inside: true), .release(inside: true)], .openCandidates, 1, 1),
        // 칩 밖으로 끌려 나가면 둘 다 취소 — 다시 들어와도 되살리지 않는다
        ([.down, .move(inside: false), .release(inside: true)], .none, 0, 0),
        ([.down, .move(inside: false), .move(inside: true), .release(inside: true)], .none, 0, 0),
        ([.down, .timer(canArm: true), .move(inside: false), .release(inside: true)], .none, 1, 1),
        // 취소된 뒤 타이머가 와도 조립 지점에 묻지도 무장하지도 않는다
        ([.down, .move(inside: false), .timer(canArm: true), .release(inside: true)], .none, 0, 0),
        // 칩 밖에서 손을 떼면(이동 이벤트 없이) 아무것도 안 한다
        ([.down, .release(inside: false)], .none, 0, 0),
        ([.down, .timer(canArm: true), .release(inside: false)], .none, 1, 1),
        // 타이머 두 번 — 피드백 1회
        ([.down, .timer(canArm: true), .timer(canArm: true), .release(inside: true)], .openCandidates, 1, 1),
        // 뷰가 사라지며 정리(onDisappear) — 그 뒤 손 뗌은 무동작
        ([.down, .timer(canArm: true), .reset, .release(inside: true)], .none, 1, 1)
    ])
    func table(steps: [Step], release: ChipPressState.Release, feedback: Int, armQueries: Int) {
        let result = run(steps)
        #expect(result.release == release)
        #expect(result.feedback == feedback)
        #expect(result.armQueries == armQueries)
        #expect(result.final.phase == .idle, "손을 떼면 언제나 처음으로")
    }

    @Test("손 뗀 뒤 늦게 온 타이머는 무장하지 않는다(취소가 늦어도 안전)")
    func lateTimerAfterRelease() {
        let result = run([.down, .release(inside: true), .timer(canArm: true)])
        #expect(result.release == .tap)
        #expect(result.feedback == 0 && result.armQueries == 0)
        #expect(result.final.phase == .idle)
    }

    @Test("누르지 않은 칩에 타이머·이동·손 뗌이 와도 무동작")
    func idleIgnoresEverything() {
        let result = run([.timer(canArm: true), .move(inside: false), .release(inside: true)])
        #expect(result.release == ChipPressState.Release.none)
        #expect(result.feedback == 0 && result.armQueries == 0)
    }

    @Test("화면 표시 — 눌림(배경 60%)은 누름·무장, 점선은 무장일 때만")
    func display() {
        var state = ChipPressState()
        #expect(!state.showsPressed && !state.showsArmed)
        state.touchDown()
        #expect(state.showsPressed && !state.showsArmed)
        let armed = state.timerFired(canArm: { true })
        #expect(armed)
        #expect(state.showsPressed && state.showsArmed)
        state.move(inside: false)
        #expect(!state.showsPressed && !state.showsArmed, "취소되면 눌림·점선 모두 꺼진다")
    }

    @Test("move의 반환값 = 지금 막 취소됐다(타이머를 멈출 때)")
    func moveReportsCancellation() {
        var state = ChipPressState()
        state.touchDown()
        let stayed = state.move(inside: true)
        let cancelled = state.move(inside: false)
        let again = state.move(inside: false)
        #expect(!stayed)
        #expect(cancelled)
        #expect(!again, "이미 취소된 뒤에는 다시 알리지 않는다")
    }

    @Test("칩 안 판정 — 경계 밖 여유(cancelMargin)까지는 안, 크기를 아직 모르면 안", arguments: [
        (CGPoint(x: 50, y: 15), CGSize(width: 100, height: 30), true),
        (CGPoint(x: -10, y: 15), CGSize(width: 100, height: 30), true),
        (CGPoint(x: -10.5, y: 15), CGSize(width: 100, height: 30), false),
        (CGPoint(x: 110, y: 40), CGSize(width: 100, height: 30), true),
        (CGPoint(x: 50, y: 40.5), CGSize(width: 100, height: 30), false),
        (CGPoint(x: 50, y: -11), CGSize(width: 100, height: 30), false),
        (CGPoint(x: 500, y: 500), CGSize.zero, true)
    ])
    func inside(location: CGPoint, size: CGSize, expected: Bool) {
        #expect(ChipPressState.cancelMargin == 10)
        #expect(ChipPressState.isInside(location, size: size) == expected)
    }
}

// MARK: - 450ms 공유 상수

@MainActor
@Suite("길게 누르기 450ms — 키와 칩이 한 곳(AC-43)")
struct LongPressDelayTests {

    @Test("공유 상수는 450ms이고 키캡 대체 입력·채움글 칩 무장이 같은 값을 본다")
    func shared() {
        #expect(KeyboardMetrics.longPressDelay == .milliseconds(450))
        #expect(KeyCapView.alternateDelay == KeyboardMetrics.longPressDelay)
        #expect(ChipPressState.armDelay == KeyboardMetrics.longPressDelay)
    }
}

// MARK: - 문구·접근성

@Suite("채움글 칩 — 「+n」 문구와 VoiceOver(AC-42·46)")
struct SnippetChipTextTests {

    @Test("「+n」은 제목 뒤에 공백 하나 + ①의 글자, 후보 1개면 빈 글자(자리 0)", arguments: [
        (0, ""), (1, " +1"), (2, " +2"), (7, " +7")
    ])
    func badge(count: Int, expected: String) {
        #expect(SnippetChipTitle.badge(alternativeCount: count) == expected)
    }

    @Test("힌트 「다른 후보 n개」·동작 「다른 후보 보기」 — 다른 후보가 없거나 배선이 없으면 둘 다 없다", arguments: [
        (0, true, "", false),
        (1, true, "다른 후보 1개", true),
        (2, true, "다른 후보 2개", true),
        (7, true, "다른 후보 7개", true),
        (2, false, "다른 후보 2개", false)
    ])
    func accessibility(count: Int, canOpen: Bool, hint: String, offersAction: Bool) {
        #expect(SnippetChipAccessibility.hint(alternativeCount: count) == hint)
        #expect(SnippetChipAccessibility.offersCandidates(alternativeCount: count, canOpen: canOpen) == offersAction)
        #expect(SnippetChipAccessibility.actionName == "다른 후보 보기")
    }

    @Test("본문 미리보기는 첫 줄(빈 줄 건너뜀) — 칩과 패널 행이 같은 함수")
    func previewLine() {
        #expect(SnippetChipTitle.previewLine("\n\n첫 줄\n둘째 줄") == "첫 줄")
        #expect(SnippetChipTitle.previewLine("") == "")
    }

    private func candidate(_ title: String, origin: SnippetOrigin, trigger: String = "새해인사") -> SnippetCandidate {
        SnippetCandidate(suggestion: SnippetSuggestion(trigger: trigger, title: title, body: "본문"), origin: origin)
    }

    @Test("패널 머리줄 「「X」 후보 n개」 — X는 사용자가 친 꼬리 원문(R32 (다)), 후보가 없으면 빈 글자")
    func header() {
        let rows = [candidate("새해 인사", origin: .user), candidate("새해 인사", origin: .pack(name: "우리 회사 상용구")),
                    candidate("새해 인사", origin: .builtIn(id: SnippetPack.greetings))]
        #expect(SnippetCandidatesPanelView.header(for: rows) == "「새해인사」 후보 3개")
        #expect(SnippetCandidatesPanelView.header(for: []) == "")
    }

    @Test("패널 행 — 상한 8(AC-46), 행 라벨은 ①의 표 그대로")
    func rows() {
        let many = (0..<10).map { candidate("항목 \($0)", origin: .user) }
        let visible = SnippetCandidatesPanelView.visibleRows(many)
        #expect(visible.count == SnippetCandidateGate.limit)
        #expect(visible.map(\.suggestion.title) == many.prefix(8).map(\.suggestion.title))
        let row = candidate("새해 인사", origin: .pack(name: "우리 회사 상용구"))
        #expect(SnippetCandidatesPanelView.rowLabel(row) == "채움글 새해 인사, 우리 회사 상용구, 붙여넣기")
        #expect(SnippetCandidatesPanelView.originLabel(row) == "우리 회사 상용구")
    }
}

// MARK: - 그린 칩·패널 (ImageRenderer — macOS 렌더링, 실기 화면은 ③)

/// `KeyboardRowRenderTests` 선례 — 뷰를 실제로 그려 픽셀로 본다.
///
/// 팔레트에 **파랑 성분이 하나도 없다**(배경 검정 · 문자 키 빨강 · 기능 키 초록 · 글자 노랑 · accent 노랑) —
/// 그린 그림에 파랑이 보이면 테마 밖 색이 들어간 것이다(R32 (나) 「첫 후보 파랑 고정색 없음」의 회귀 방지).
@MainActor
@Suite("채움글 칩·후보 패널 — 그린 화면")
struct SnippetChipRenderTests {

    private let spec = ThemeSpec(
        id: "chip-probe", displayName: "chip-probe",
        light: .init(keyboardBackground: "#000000", characterKey: "#FF0000",
                     functionKey: "#00FF00", keyText: "#FFFF00", accent: "#FFFF00"),
        dark: .init(keyboardBackground: "#000000", characterKey: "#C00000",
                    functionKey: "#00C000", keyText: "#FFFF00", accent: "#FFFF00"))
    private let scale: CGFloat = 2

    private func theme(dark: Bool = false) -> ResolvedTheme {
        ResolvedTheme(spec: spec, appearance: dark ? .dark : .light, systemColorScheme: dark ? .dark : .light)
    }

    private struct Rendered: Equatable {
        let pixels: [UInt8]
        let width: Int
        let height: Int

        func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
            let i = (y * width + x) * 4
            return (pixels[i], pixels[i + 1], pixels[i + 2])
        }
        func isBackground(x: Int, y: Int) -> Bool {
            let (r, g, b) = rgb(x: x, y: y)
            return max(r, g, b) <= 8
        }
        /// 파랑 성분 최댓값 — 팔레트에 파랑이 없으니 0 근처여야 한다
        var maxBlue: UInt8 {
            stride(from: 2, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
        }
    }

    private func render(_ view: some View) throws -> Rendered {
        let renderer = ImageRenderer(content: view.background(Color.black))
        renderer.scale = scale
        let image = try #require(renderer.cgImage)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Rendered(pixels: pixels, width: image.width, height: image.height)
    }

    private func suggestion(count: Int) -> SnippetSuggestion {
        SnippetSuggestion(trigger: "새해인사", title: "새해 인사", body: "새해 복 많이 받으세요.\n둘째 줄",
                          alternativeCount: count)
    }

    /// **U7 전 칩 겉모양 그대로**(`KeyboardRootView.SnippetChip`, HEAD `391561a`) — 「자리 0」의 기준
    private func legacyChip(_ suggestion: SnippetSuggestion, theme: ResolvedTheme) -> some View {
        HStack(spacing: 6) {
            Text("[\(suggestion.title)]")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.keyText)
                .lineLimit(1)
                .fixedSize()
            Text(SnippetChipTitle.previewLine(suggestion.body))
                .font(.system(size: 14))
                .foregroundStyle(theme.keyText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(theme.characterKey, in: Capsule())
    }

    @Test("AC-42 자리 0 — 후보 1개 제목은 U7 전 제목 `Text`와 픽셀까지 같다")
    func titleUnchangedWithoutAlternatives() throws {
        let theme = theme()
        let new = try render(SnippetChipTitle.text(title: "새해 인사", alternativeCount: 0, theme: theme).fixedSize())
        let old = try render(Text("[\("새해 인사")]").font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.keyText).fixedSize())
        #expect(new == old)
    }

    @Test("AC-42 자리 0 — 후보 1개 칩 폭·그림이 U7 전 칩과 같고, 「+n」이 붙으면 폭만 는다(기록)")
    func chipWidth() throws {
        let theme = theme()
        let old = try render(legacyChip(suggestion(count: 0), theme: theme).fixedSize())
        let zero = try render(SnippetChipFace(suggestion: suggestion(count: 0), theme: theme).fixedSize())
        #expect(zero == old, "후보 1개 칩은 U7 전과 같은 그림이다")
        let two = try render(SnippetChipFace(suggestion: suggestion(count: 2), theme: theme).fixedSize())
        let seven = try render(SnippetChipFace(suggestion: suggestion(count: 7), theme: theme).fixedSize())
        #expect(two.height == old.height && seven.height == old.height, "높이는 그대로")
        let growTwo = CGFloat(two.width - old.width) / scale
        let growSeven = CGFloat(seven.width - old.width) / scale
        // 「 +2」 12pt 굵게 — 대략 한 글자 반(macOS 글꼴 기준). 폭 기록용 하한·상한만 건다
        #expect(growTwo > 8 && growTwo < 30, "「+2」 폭 증가 \(growTwo)pt")
        #expect(abs(growSeven - growTwo) < 2, "한 자리 수끼리는 거의 같다 — +2 \(growTwo)pt · +7 \(growSeven)pt")
    }

    @Test("AC-43 — 무장 점선은 칩 밖 띠에만 그려지고 칩 그림·크기는 그대로(투명도만 바뀐다)")
    func armedOverlayOnlyAddsRing() throws {
        let theme = theme()
        let margin: CGFloat = 10
        let idle = try render(SnippetChipFace(suggestion: suggestion(count: 2), theme: theme).fixedSize().padding(margin))
        let armed = try render(SnippetChipFace(suggestion: suggestion(count: 2), theme: theme,
                                               isPressed: true, isArmed: true).fixedSize().padding(margin))
        let pressed = try render(SnippetChipFace(suggestion: suggestion(count: 2), theme: theme,
                                                 isPressed: true).fixedSize().padding(margin))
        #expect(idle.width == armed.width && idle.height == armed.height, "오버레이는 레이아웃을 바꾸지 않는다")
        // 무장 그림 − 눌림 그림 = 점선뿐. 점선 픽셀은 모두 칩 밖(평소 그림의 배경 자리)에 있다
        var ringPixels = 0
        for y in 0..<armed.height {
            for x in 0..<armed.width where armed.rgb(x: x, y: y) != pressed.rgb(x: x, y: y) {
                ringPixels += 1
                #expect(idle.isBackground(x: x, y: y), "점선이 칩 안(\(x), \(y))에 그려졌다")
            }
        }
        #expect(ringPixels > 100, "무장하면 점선이 보인다 — \(ringPixels)px")
        // 평소·눌림에는 칩 밖 띠가 비어 있다(투명도 0)
        let band = Int(margin * scale) - 2
        for y in [band, idle.height - band - 1] {
            #expect((0..<idle.width).allSatisfy { idle.isBackground(x: $0, y: y) && pressed.isBackground(x: $0, y: y) })
        }
    }

    @Test("눌림은 배경 60%(키와 같은 값) — 글자 앞 여백 자리의 색으로 본다")
    func pressedBackground() throws {
        let theme = theme()
        let idle = try render(SnippetChipFace(suggestion: suggestion(count: 0), theme: theme).fixedSize())
        let pressed = try render(SnippetChipFace(suggestion: suggestion(count: 0), theme: theme,
                                                 isPressed: true).fixedSize())
        let x = Int(8 * scale), y = idle.height / 2   // 캡슐 안, 글자(12pt 뒤) 앞
        #expect(idle.rgb(x: x, y: y).0 >= 250)
        #expect(abs(Int(pressed.rgb(x: x, y: y).0) - 153) <= 3, "빨강 × 0.6 = 153 — \(pressed.rgb(x: x, y: y).0)")
    }

    @Test("구조 불변 — 칩 표면의 뷰 타입에 조건 분기·선택 노드·AnyView가 없다(「+n」·눌림·무장 모두 내용·투명도만)")
    func faceHasNoConditionalSubtree() {
        let theme = theme()
        let faces = [
            SnippetChipFace(suggestion: suggestion(count: 0), theme: theme),
            SnippetChipFace(suggestion: suggestion(count: 3), theme: theme, isPressed: true, isArmed: true)
        ]
        let types = faces.map { String(reflecting: type(of: $0.body)) }
        #expect(types[0] == types[1])
        // `if`/`else` → `_ConditionalContent`, `else` 없는 `if` → 뷰의 `Optional`(`Swift.Optional<SwiftUI.…>`).
        // (`lineLimit`의 `Optional<Int>` 같은 값 수식어는 구조가 아니다 — 뷰 이름공간만 본다)
        for forbidden in ["_ConditionalContent", "Swift.Optional<SwiftUI.", "AnyView", "ForEach"] {
            #expect(!types[0].contains(forbidden), "\(forbidden) — \(types[0])")
        }
        // 기대 구조: HStack(제목 Text · 미리보기 Text) + 배경 캡슐 + 늘 붙은 점선 오버레이(투명도)
        #expect(types[0].contains("HStack<SwiftUI.TupleView<(") && types[0].contains("_OverlayModifier")
                && types[0].contains("StrokeBorderShapeView") && types[0].contains("_OpacityEffect"), "\(types[0])")
    }

    @Test("테마 색만 — 칩(평소·무장)·후보 행·패널(라이트·다크)에 파랑 성분이 없다(R32 (나) 고정 파랑 없음)", arguments: [false, true])
    func themeColorsOnly(dark: Bool) throws {
        let theme = theme(dark: dark)
        let chip = try render(SnippetChipFace(suggestion: suggestion(count: 2), theme: theme,
                                              isPressed: true, isArmed: true).fixedSize().padding(10))
        #expect(chip.maxBlue <= 8, "칩 파랑 \(chip.maxBlue)")
        // 첫 행(칩 후보)도 다른 행과 같은 뷰다 — 행은 자기가 몇 번째인지 모른다
        let rows = try render(VStack(spacing: 4) {
            ForEach(Array(candidates(3).enumerated()), id: \.offset) { _, candidate in
                SnippetCandidateRow(candidate: candidate, theme: theme, minHeight: 36, onTap: {})
            }
        }.frame(width: 388))
        #expect(rows.maxBlue <= 8, "행 파랑 \(rows.maxBlue)")
        let panel = try render(panel(theme: theme, count: 3).frame(width: 396, height: 216))
        #expect(panel.maxBlue <= 8, "패널 파랑 \(panel.maxBlue)")
    }

    private func candidates(_ count: Int) -> [SnippetCandidate] {
        let origins: [SnippetOrigin] = [.user, .pack(name: "우리 회사 상용구"), .builtIn(id: SnippetPack.greetings), .date,
                                        .bible, .pack(name: "예시 팩"), .user, .user, .user, .user]
        return (0..<count).map {
            SnippetCandidate(suggestion: SnippetSuggestion(trigger: "새해인사", title: "새해 인사",
                                                           body: "새해 복 많이 받으세요 \($0)"), origin: origins[$0])
        }
    }

    private func panel(theme: ResolvedTheme, count: Int) -> SnippetCandidatesPanelView {
        SnippetCandidatesPanelView(candidates: candidates(count), theme: theme, onRowTap: { _ in }, onClose: {})
    }

    /// 세로줄 하나(x pt)를 위→아래로 훑어 행(문자 키 빨강)·막대(기능 키 초록) 구간을 [(종류, 시작 y, 끝 y)]로
    private func columnRuns(_ image: Rendered, xPoint: CGFloat) -> [(kind: String, top: CGFloat, bottom: CGFloat)] {
        let x = Int(xPoint * scale)
        var runs: [(kind: String, top: CGFloat, bottom: CGFloat)] = []
        var previous = ""
        for y in 0..<image.height {
            let (r, g, _) = image.rgb(x: x, y: y)
            let kind = r > 150 && g < 60 ? "row" : (g > 150 && r < 60 ? "bar" : "")
            if kind != previous, !kind.isEmpty { runs.append((kind, CGFloat(y) / scale, CGFloat(y) / scale)) }
            if !kind.isEmpty { runs[runs.count - 1].bottom = CGFloat(y + 1) / scale }
            previous = kind
        }
        return runs
    }

    /// macOS `ImageRenderer`는 `ScrollView` 안(행 목록)을 그리지 않는다 — 패널은 머리줄·막대 자리만, 행은 `SnippetCandidateRow`를 직접 그려 본다.
    @Test("패널 — 위에 머리줄, 맨 아래 「돌아가기」 막대(36pt 이상, 아이폰·아이패드 폭)", arguments: [CGFloat(396), 700])
    func panelLayout(width: CGFloat) throws {
        let height: CGFloat = 216
        let image = try render(panel(theme: theme(), count: 2).frame(width: width, height: height))
        let bars = columnRuns(image, xPoint: 20).filter { $0.kind == "bar" }
        try #require(bars.count == 1, "\(bars)")
        #expect(abs(bars[0].bottom - height) <= 0.5 && bars[0].bottom - bars[0].top >= 36, "막대 \(bars[0])")
        // (x = 20pt — 둥근 모서리(반경 8)를 벗어난 자리, 가운데 「돌아가기」 글자보다 왼쪽)
        // 머리줄 글자(노랑) — 맨 위 30pt 안에 있다
        let headerInk = (0..<Int(30 * scale)).contains { y in
            (0..<image.width).contains { x in
                let (r, g, _) = image.rgb(x: x, y: y)
                return r > 100 && g > 100
            }
        }
        #expect(headerInk, "머리줄 「「새해인사」 후보 2개」가 위에 그려진다")
    }

    @Test("후보 행 — 문자 키 색 둥근 행 하나 · 오른쪽에 기능 키 색 출처 이름표 · 행 최소 높이", arguments: [CGFloat(36), 44])
    func rowLayout(minHeight: CGFloat) throws {
        let width: CGFloat = 388
        let image = try render(SnippetCandidateRow(candidate: candidates(2)[1], theme: theme(), minHeight: minHeight,
                                                   onTap: {}).frame(width: width))
        let runs = columnRuns(image, xPoint: 6)
        #expect(runs.map(\.kind) == ["row"], "\(runs.map(\.kind))")
        #expect(CGFloat(image.height) / scale >= minHeight)
        // 출처 이름표는 오른쪽 절반에(제목은 왼쪽)
        let greenRight = (0..<image.height).contains { y in
            (image.width / 2..<image.width).contains { x in
                let (r, g, _) = image.rgb(x: x, y: y)
                return g > 150 && r < 60
            }
        }
        #expect(greenRight, "출처 「우리 회사 상용구」 이름표가 오른쪽에 있다")
    }
}
