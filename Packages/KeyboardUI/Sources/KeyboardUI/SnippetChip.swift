import SwiftUI
import KeyboardCore

// 채움글 칩 — 짧은 탭은 첫 후보, 길게(450ms) 눌러 무장한 뒤 손을 떼면 겹치는 후보 패널(U7).
// 계약: PDR `docs/design-reviews/external-snippet-packs.md` 10-6 ④⑤⑦ · AC-42·43·46 · R32 (가)
// 지시서: `docs/design-reviews/external-snippet-packs-u7-plan.md` 2절 ② · 6절 R2·R3·R6
//
// ★ **누르는 도중 서브트리 구조를 바꾸지 않는다**(CLAUDE.md 작업 원칙 — 트랙패드 버그 2026-09-05).
//   - 「+n」은 제목 `Text` **한 노드의 내용**이다(후보 1개면 빈 글자 — 자리 0, v3.2).
//   - 눌림은 배경 색의 투명도, 무장은 **늘 붙어 있는** 점선 오버레이의 투명도만 바꾼다.
//   표면(`SnippetChipFace`)에는 `if`·`ForEach`·`AnyView`가 없다 — `SnippetChipRenderTests`가 뷰 타입으로 고정한다.

/// 칩 누름 상태기계 — 제스처 뷰는 `swift test`가 누를 수 없어 판정만 값 타입으로 뗐다(`ChipPressStateTests`).
///
/// ```
/// idle ─손 닿음→ pressed ─450ms·조립 지점 허락→ armed
///                  │ 칩 밖으로 끌림              │ 칩 밖으로 끌림
///                  └──────────→ cancelled ←─────┘
/// 손 뗌(칩 안): pressed → 짧은 탭 · armed → 후보 패널 · cancelled → 아무것도 · 그 뒤 idle
/// ```
///
/// - **무장은 조립 지점이 허락할 때만**(`canArm`) — 퇴장 트랜지션(0.28초) 중인 칩도 히트 테스트를 받아 450ms 뒤엔
///   칩이 이미 사라졌을 수 있다(10-6 ⑤ · R3). 허락이 없으면 점선·피드백 없이 **pressed에 머물러 떼면 짧은 탭**이다 —
///   후보 1개 칩은 U7 전 `Button`과 같게 동작한다(AC-42 「지금과 같음」). 짧은 탭의 최종 방어는 조립 지점의 꼬리 정합 그대로다.
/// - **칩 밖으로 끌려 나가면 둘 다 취소**하고 다시 들어와도 되살리지 않는다 — 키에는 이동 임계가 없어 「키와 같은 값」을 쓸 수 없다
///   (지시서 F7 · 7절 제안 1). 칩 경계에서 `cancelMargin`만큼은 봐준다 — 실기로 조정할 값이다.
struct ChipPressState: Equatable {

    enum Phase: Equatable {
        case idle
        case pressed
        case armed
        case cancelled
    }

    /// 손을 뗄 때 할 일
    enum Release: Equatable {
        case none
        /// 짧은 탭 — 칩의 첫 후보를 넣는다(지금 그대로)
        case tap
        /// 무장 뒤 손 뗌 — 후보 패널을 연다(무장 순간이 아니다, v3.2 · AC-43)
        case openCandidates
    }

    /// 무장까지 — 키 길게 누르기와 공유(AC-43)
    static let armDelay: Duration = KeyboardMetrics.longPressDelay
    /// 칩 경계 밖으로 이만큼(pt)까지는 칩 안으로 본다 — 넘으면 취소. 실기로 조정(지시서 7절 제안 1)
    static let cancelMargin: CGFloat = 10

    private(set) var phase: Phase = .idle

    /// 배경 60% — 누르고 있는 동안(무장 포함). 취소되면 꺼진다
    var showsPressed: Bool { phase == .pressed || phase == .armed }
    /// 점선 테두리 — 무장된 동안만(R32 (가))
    var showsArmed: Bool { phase == .armed }

    /// 손이 닿았다 — 처음 한 번만 의미가 있다
    mutating func touchDown() {
        guard phase == .idle else { return }
        phase = .pressed
    }

    /// 손가락이 움직였다. **지금 막 취소됐으면 true** — 뷰가 무장 타이머를 멈춘다
    @discardableResult
    mutating func move(inside: Bool) -> Bool {
        guard !inside, phase == .pressed || phase == .armed else { return false }
        phase = .cancelled
        return true
    }

    /// 450ms가 지났다. **지금 막 무장했으면 true** — 뷰가 피드백(소리·FA일 때 진동)을 1회 낸다.
    /// `canArm`은 누르고 있는 동안에만 묻는다(취소·손 뗀 뒤 늦은 타이머는 조립 지점을 부르지 않는다)
    mutating func timerFired(canArm: () -> Bool) -> Bool {
        guard phase == .pressed, canArm() else { return false }
        phase = .armed
        return true
    }

    /// 손을 뗐다 — 칩 안에서 뗐을 때만 무엇이든 한다. 언제나 idle로 돌아간다
    mutating func release(inside: Bool) -> Release {
        let result: Release
        switch phase {
        case .pressed: result = inside ? .tap : .none
        case .armed: result = inside ? .openCandidates : .none
        case .idle, .cancelled: result = .none
        }
        phase = .idle
        return result
    }

    /// 뷰가 사라짐(칩 교체·퇴장 끝) — 진행 중이던 누름을 버린다
    mutating func reset() {
        phase = .idle
    }

    /// 손가락 위치(칩 좌표)가 칩 안인가 — 경계 밖 `margin`까지 안으로 본다. 크기를 아직 모르면(첫 프레임) 안으로 본다
    static func isInside(_ location: CGPoint, size: CGSize, margin: CGFloat = cancelMargin) -> Bool {
        guard size.width > 0, size.height > 0 else { return true }
        return location.x >= -margin && location.x <= size.width + margin
            && location.y >= -margin && location.y <= size.height + margin
    }
}

/// 칩 글자 — 제목(+「+n」)과 본문 미리보기. 칩과 후보 패널 행이 같은 규칙을 쓴다.
enum SnippetChipTitle {

    /// 제목 뒤에 이어 붙는 글자 — 공백 하나 + 「+n」(①의 `SnippetCandidateText.alternativeBadge`). 후보 1개면 **빈 글자**(자리 0, AC-42)
    static func badge(alternativeCount: Int) -> String {
        let badge = SnippetCandidateText.alternativeBadge(alternativeCount: alternativeCount)
        return badge.isEmpty ? "" : " " + badge
    }

    /// 제목 `Text` **한 노드** — 「[제목]」 14pt 굵게 + 「 +n」 12pt 굵게·보조색(시안 8-B).
    ///
    /// `Text + Text`는 iOS 26 SDK에서 사라질 예정(deprecated)이라 **`Text` 보간**으로 잇는다 — 결과는 같은 `Text` 하나다
    /// (애플 문서 `Text` 「Localizing strings」 · `foregroundStyle(_:) -> Text`는 iOS 17+ — Context7 확인 2026-10-07).
    /// 제목 부분은 U7 전과 **같은 초기화**(`"[\(title)]"`)라 후보 1개 칩은 픽셀까지 그대로다(`SnippetChipRenderTests`).
    static func text(title: String, alternativeCount: Int, theme: ResolvedTheme) -> Text {
        let badgeText = Text(badge(alternativeCount: alternativeCount))
            .font(.system(size: 12, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(theme.keyText.opacity(0.55))
        return Text("[\(title)]\(badgeText)")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.keyText)
    }

    /// 본문 첫 줄(빈 줄 건너뜀) — 칩 미리보기·패널 행 둘째 줄
    static func previewLine(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
    }
}

/// 칩 VoiceOver — 라벨은 지금 그대로(`SnippetSuggestion.accessibilityLabel`), 다른 후보가 있으면 힌트와 사용자 지정 동작.
/// 문구는 ①의 표(`SnippetCandidateText`) 한 곳에서 온다(10-6 ⑦). 450ms 제스처는 VoiceOver에서 쓰기 어렵다(키캡 선례).
enum SnippetChipAccessibility {

    /// 로터 「동작」 이름 — 즉시 패널을 연다
    static let actionName = SnippetCandidateText.chipActionName

    /// 힌트 「다른 후보 n개」 — 없으면 빈 글자(= 읽지 않는다). 「+n」 글자는 따로 읽지 않는다(시안 8-H)
    static func hint(alternativeCount: Int) -> String {
        SnippetCandidateText.chipHint(alternativeCount: alternativeCount) ?? ""
    }

    /// 「다른 후보 보기」 동작을 붙이나 — 다른 후보가 있고 조립 지점이 패널을 열 수 있을 때(배선 전 ①·② 단계는 없다)
    static func offersCandidates(alternativeCount: Int, canOpen: Bool) -> Bool {
        canOpen && alternativeCount > 0
    }
}

/// 칩 **표면** — 상태를 갖지 않는 그림. 누름·무장은 값으로만 받아 **투명도로만** 그린다.
///
/// 이 뷰의 `body` 타입에 조건 분기가 없다는 것이 「누르는 도중 구조 불변」의 근거다(`SnippetChipRenderTests` — 타입 검사).
struct SnippetChipFace: View {

    let suggestion: SnippetSuggestion
    let theme: ResolvedTheme
    var isPressed = false
    var isArmed = false

    var body: some View {
        HStack(spacing: 6) {
            // 제목은 "[고린도전서 12:3]" 꼴, 본문 글자색 굵게 — accent(파랑)는 배경과
            // 대비가 약해 안 보인다는 피드백 (2026-09-03). 「+n」은 이 한 노드 안에 이어 붙는다(U7)
            SnippetChipTitle.text(title: suggestion.title, alternativeCount: suggestion.alternativeCount, theme: theme)
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
        // 눌림 = 배경 60%(키캡 `keyBackground`와 같은 값)
        .background(theme.characterKey.opacity(isPressed ? 0.6 : 1), in: Capsule())
        // 무장 = 칩 바깥 5pt의 점선(R32 (가)). **항상 붙어 있고 투명도만** 바뀐다 — 넣고 빼면 진행 중인 터치가 끊긴다.
        // 색은 테마 글자색 — 고정색을 쓰지 않는다(R32 (나), 「키 표면은 테마 색」). 툴바 높이 46 안에 든다(칩 ≈ 31 + 10)
        .overlay {
            Capsule()
                .strokeBorder(theme.keyText.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .padding(-5)
                .opacity(isArmed ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

/// 채움글 후보 칩 — 제목 + 본문 첫 줄 미리보기. 탭하면 단축어가 전문으로 바뀌고, 다른 후보가 있으면 길게 눌러 고른다.
///
/// U7 전에는 `Button`이었다. 길게 누르기를 받으려고 키캡과 같은 `DragGesture(minimumDistance: 0)` 누름으로 바꿨고,
/// 그 대가로 빠지는 버튼 의미(VoiceOver 「버튼」·기본 동작)를 접근성 수식어로 **같이** 단다(지시서 6절 R2).
struct SnippetChip: View {

    let suggestion: SnippetSuggestion
    let theme: ResolvedTheme
    /// 짧은 탭 — 첫 후보를 넣는다(지금 그대로)
    let onTap: () -> Void
    /// 450ms 무장 시점에 묻는다 — 조립 지점이 **지금 칩·꼬리**로 대답한다(`SnippetCandidateGate.canArm`).
    /// 이 칩이 쥔 값은 누르기 시작한 때의 것이라 「+n」이 그새 바뀌었을 수 있다 — 칩을 가리키는 데(trigger)만 쓰고 개수는 지금 칩에서 본다.
    /// nil이면 길게 누르기가 없다(배선 전 — U7 전 칩과 같다)
    var onArm: (() -> Bool)? = nil
    /// 무장 뒤 손 뗌·VoiceOver 동작 — 후보 패널을 연다. nil이면 길게 누르기가 없다
    var onOpenCandidates: (() -> Void)? = nil
    /// 무장 피드백 — 키 터치다운과 같은 콜백(소리, 진동은 Full Access일 때만 — 조립 지점 규칙 그대로, 10-6 ⑤)
    var onPress: (() -> Void)? = nil

    @State private var press = ChipPressState()
    @State private var armTask: Task<Void, Never>?
    /// 칩 실측 크기 — 손가락이 칩 밖으로 나갔는지 본다. **항상 있는 배경**이라 구조를 바꾸지 않는다(키캡 선례)
    @State private var size: CGSize = .zero

    /// 길게 누르기를 받나 — 다른 후보가 있고 배선돼 있을 때만. 아니면 타이머도 돌지 않아 U7 전 `Button`과 같다
    private var acceptsLongPress: Bool {
        onArm != nil && onOpenCandidates != nil && suggestion.alternativeCount > 0
    }

    var body: some View {
        SnippetChipFace(suggestion: suggestion, theme: theme, isPressed: press.showsPressed, isArmed: press.showsArmed)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { size = geometry.size }
                        .onChange(of: geometry.size) { _, newSize in size = newSize }
                }
            )
            .contentShape(Capsule())
            .gesture(pressGesture)
            // 칩이 `.id(title)` 교체·퇴장으로 사라지면 타이머·누름을 버린다(새는 작업 없음)
            .onDisappear {
                armTask?.cancel()
                armTask = nil
                press.reset()
            }
            // ★ `Button`이 아니므로 버튼 의미를 직접 단다 — 빠지면 VoiceOver·스위치 제어가 칩을 못 쓴다(R2)
            .accessibilityElement(children: .ignore)
            // 문구·성경은 「채움글 <제목> 붙여넣기」 그대로, 날짜 칩은 넣을 값까지 읽는다(`SnippetSuggestion.accessibilityLabel`)
            .accessibilityLabel(suggestion.accessibilityLabel)
            .accessibilityHint(SnippetChipAccessibility.hint(alternativeCount: suggestion.alternativeCount))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            // 수식어만 더한다 — 액션 목록은 그려지는 뷰가 아니라 표면 구조가 바뀌지 않는다(키캡 `accessibilityActions` 선례)
            .accessibilityActions {
                if let onOpenCandidates, SnippetChipAccessibility.offersCandidates(
                    alternativeCount: suggestion.alternativeCount, canOpen: true) {
                    Button(SnippetChipAccessibility.actionName) { onOpenCandidates() }
                }
            }
    }

    /// 눌림 즉시 반응하도록 키캡과 같은 `DragGesture(minimumDistance: 0)`. 판정은 `ChipPressState`가 한다
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if press.phase == .idle {
                    press.touchDown()
                    if acceptsLongPress { startArmTimer() }
                } else if press.move(inside: ChipPressState.isInside(value.location, size: size)) {
                    cancelArmTimer()
                }
            }
            .onEnded { value in
                cancelArmTimer()
                switch press.release(inside: ChipPressState.isInside(value.location, size: size)) {
                case .tap: onTap()
                case .openCandidates: onOpenCandidates?()
                case .none: break
                }
            }
    }

    /// 450ms 뒤 조립 지점에 묻고, 허락되면 무장(점선)과 피드백 1회
    private func startArmTimer() {
        armTask?.cancel()
        armTask = Task {
            try? await Task.sleep(for: ChipPressState.armDelay)
            guard !Task.isCancelled else { return }
            if press.timerFired(canArm: { onArm?() ?? false }) {
                onPress?()
            }
        }
    }

    private func cancelArmTimer() {
        armTask?.cancel()
        armTask = nil
    }
}
