import SwiftUI
import KeyboardCore

/// 키캡 하나. **자기 pressed 상태만 가진다** — 전역 상태를 구독하면
/// 키 하나 누를 때마다 자판 전체가 리빌드되어 메모리 한도에서 죽는다.
struct KeyCapView: View {

    let key: LayoutDefinition.Key
    let isShifted: Bool
    /// 캡스락 — 시프트 키 아이콘 분기(`capslock.fill`)
    var isCapsLocked: Bool = false
    let theme: ResolvedTheme
    let showsPreview: Bool
    let onEvent: (KeyEvent) -> Void
    /// 터치다운 순간 호출 — 클릭음·진동은 손가락이 닿을 때 나야 한다 (애플과 같은 감각).
    /// 이벤트(`onEvent`)는 릴리스에 나가므로 여기서 분리한다. 백스페이스 반복도 매 회 호출.
    var onPress: (() -> Void)? = nil
    /// 스페이스 트랙패드 모드 — 400ms 누르고 있으면 진입, 드래그하면 문자 단위 오프셋을 보낸다
    /// (애플 기본 키보드의 스페이스 길게 누르기 커서 이동, 사용자 요청 2026-09-03). 스페이스 키에만 주입.
    /// 진입 전 손가락 이동은 진입을 막지 않는다 — "누른 채 바로 드래그"가 사용자의 기본 동작이다
    /// (실기 피드백 2026-09-04: 12pt 흔들림 취소 규칙이 진입을 번번이 막았다).
    var onCursorDrag: ((Int) -> Void)? = nil

    @State private var isPressed = false
    /// 키의 실측 크기 — 확대 미리보기 크기를 여기서 낸다 (REQ-5).
    @State private var keySize: CGSize = .zero
    @State private var repeatTask: Task<Void, Never>?

    // 길게 누르기 대체 입력 (문장부호 키 — . 길게 → ,). 무장되면 릴리스에 `key.alternate`가 나간다
    @State private var alternateArmed = false
    @State private var alternateTask: Task<Void, Never>?

    // 트랙패드 모드 상태
    @State private var cursorMode = false
    @State private var cursorModeTask: Task<Void, Never>?
    @State private var latestTranslation: CGFloat = 0
    /// 이미 커서 이동으로 소비한 수평 이동량
    @State private var consumedTranslation: CGFloat = 0

    /// 진입까지 누르고 있어야 하는 시간 / 문자 1개당 드래그 거리
    private static let cursorModeDelay: Duration = .milliseconds(400)
    private static let cursorStep: CGFloat = 8
    /// 대체 입력이 무장되기까지 누르고 있어야 하는 시간
    private static let alternateDelay: Duration = .milliseconds(450)

    private var label: String {
        isShifted ? key.shiftedLabel : key.label
    }

    /// 표면·미리보기에 보이는 라벨 — 대체 입력이 무장되면 그 라벨로 바뀌어 "지금 떼면 이게 들어간다"를 알린다
    private var displayLabel: String {
        alternateArmed ? (alternateText ?? label) : label
    }

    /// 길게 누르기 표시 문구 — 문자 키는 `alternateLabel`(그 문자), 문자 이벤트가 아닌 대체 입력
    /// (키패드형 페이지 키의 「이전」)은 `alternateHint`. 문자 키는 힌트 필드를 비워 두므로 기존 표시 그대로다
    /// (PDR `number-symbol-keypad.md` 6절).
    private var alternateText: String? {
        key.alternateHint ?? key.alternateLabel
    }

    var body: some View {
        face
            .foregroundStyle(theme.keyText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 키 실측 크기 — 확대 미리보기가 키에 비례하려면 필요하다 (REQ-5).
            // **항상 있는 배경**이라 누르는 도중 구조가 바뀌지 않는다.
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { keySize = geometry.size }
                        .onChange(of: geometry.size) { _, size in keySize = size }
                }
            )
            .overlay(alignment: .topTrailing) {
                // 길게 누르기 힌트 (문장부호 키의 ","·".com") — 무장되면 라벨 자체가 바뀌므로 숨긴다.
                // 뷰를 넣고 빼지 않고 투명도만 바꾼다 (누르는 도중 구조 변경 금지 — face 주석 참조)
                if let hint = alternateText {
                    // 힌트 크기는 라벨 크기에 비례 (기본 22 → 10, 천지인 28 → 13)
                    Text(hint)
                        .font(.system(size: key.labelSize.map { CGFloat($0) * 0.45 } ?? 10, weight: .medium))
                        .foregroundStyle(theme.keyText.opacity(0.55))
                        .lineLimit(1)
                        .padding(.top, 3)
                        .padding(.trailing, 5)
                        .opacity(alternateArmed ? 0 : 1)
                        .allowsHitTesting(false)
                }
            }
            .modifier(KeyCapSurface(
                background: keyBackground,
                cornerRadius: theme.keyCornerRadius
            ))
            .overlay(alignment: .top) {
                // 스페이스는 미리보기를 띄우지 않는다 (사용자 요청 2026-09-03)
                if isPressed, showsPreview, !key.isFunctionKey, key.event != .space {
                    preview
                }
            }
            .gesture(pressGesture)
            .accessibilityLabel(accessibilityName)
            // 힌트는 연타 키에만 있다(나머지는 빈 문자열 = 읽지 않는다). 수식어만 — 표면 구조는 그대로다
            .accessibilityHint(KeyCapAccessibility.hint(for: key) ?? "")
            .accessibilityAddTraits(.isKeyboardKey)
            // ★ 길게 누르기의 VoiceOver 대체 — 로터 「동작」에서 고른다(v1.2.0 출시 전 마무리 ②).
            //   **접근성 수식어만 더한다** — 액션 목록은 그려지는 뷰가 아니라서 누르는 도중 표면 구조가 바뀌지 않는다
            //   (작업 원칙). 어느 키에 붙이는지는 `KeyCapAccessibility.alternateAction` 주석(범위와 근거).
            .accessibilityActions {
                if let action = KeyCapAccessibility.alternateAction(for: key) {
                    Button(action.name) {
                        onPress?()
                        onEvent(action.event)
                    }
                }
            }
    }

    /// 키 표면 — 심볼이 있으면 아이콘, 없으면 라벨. 리턴 키의 한글 라벨(검색·보내기)은 살짝 작게.
    /// 트랙패드 모드 중에는 스페이스에 좌우 화살표를 띄워 상태를 알린다.
    ///
    /// **항상 하나의 `Text` 노드다 — 누르는 도중 뷰 구조를 바꾸지 않는다.** 이전에는 `if cursorMode { Image }
    /// else { Text }`로 분기해, 트랙패드 진입(400ms) 순간 표면이 Text→Image로 갈아끼워지면서 진행 중인
    /// 터치가 `DragGesture`에서 떨어져 나갔다 — 이후 이동·릴리스가 전달되지 않아 커서가 안 움직이고
    /// `onEnded`는 다음 터치 때야 왔다 (시뮬레이터 로그로 확정, 2026-09-05). 아이콘은 `Text(Image(...))`로
    /// 같은 노드 안에서 내용만 바꾼다. 문장부호 키의 `.com` 전환이 살아남은 이유도 내용 변경뿐이었기 때문.
    private var face: some View {
        faceText
            .font(.system(size: faceFontSize, weight: faceUsesSymbol ? .medium : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var faceUsesSymbol: Bool { cursorMode || key.symbol != nil }

    private var faceText: Text {
        if cursorMode { return Text(Image(systemName: "arrow.left.and.right")) }
        if key.event == .shift {
            // 시프트 상태 표시 — Apple과 같이 once는 채운 화살표, 캡스락은 캡스락 심볼
            return Text(Image(systemName: isCapsLocked ? "capslock.fill" : (isShifted ? "shift.fill" : "shift")))
        }
        if let symbol = key.symbol { return Text(Image(systemName: symbol)) }
        return Text(displayLabel)
    }

    private var faceFontSize: CGFloat {
        if cursorMode { return 18 }
        // 기능 키 심볼(⌫·⏎·✓)은 22pt — 17pt는 작다는 피드백 (2026-09-07). 문자 키 심볼(천지인 스페이스)은 18
        if key.symbol != nil { return key.isFunctionKey ? 22 : 18 }
        if let size = key.labelSize { return CGFloat(size) }  // 자판 데이터가 정한 크기 (천지인 28)
        guard key.isFunctionKey else {
            // 문장부호 키가 길게 눌려 ".com"을 보일 때 — 1.2폭 키에 들어가게 낮춘다
            return displayLabel.count > 1 ? 15 : 22
        }
        return key.event == .return && label != "⏎" ? 15 : 16
    }

    private var keyBackground: Color {
        let base = key.isFunctionKey ? theme.functionKey : theme.characterKey
        return isPressed ? base.opacity(0.6) : base
    }

    /// **아이폰 문자 키 폭의 천장.** 아이폰은 가장 넓은 기기(440pt)에서도 문자 키가 38.9pt다
    /// (`(440 − 6 − 45) / 10`). 46pt를 넘는 문자 키는 아이패드뿐이므로, 이 값을 넘을 때만
    /// 미리보기를 키에 비례시킨다 — **아이폰은 어떤 기기·어떤 배율에서도 46 × 52 그대로다.**
    static let phoneKeyWidthCeiling: CGFloat = 46
    /// 아이폰에서의 미리보기 : 키 비율 (46 / 35.1 = 1.31, 52 / 48.75 = 1.07).
    /// 아이패드에서도 같은 비율을 재현해야 '확대'로 읽힌다.
    static let previewWidthRatio: CGFloat = 1.31
    static let previewHeightRatio: CGFloat = 1.07

    /// 눌린 키 위에 뜨는 확대 미리보기
    ///
    /// 크기가 상수(46 × 52)일 때 아이패드에서는 키(78 × 69)보다 **작아서**
    /// '확대 미리보기'가 아니라 작은 꼬리표로 보였다 (검증자 실측 REQ-5 — 폭 47% · 높이 28% 작다).
    /// 그래서 키 실측 크기에 아이폰과 같은 비율을 곱한다.
    /// 미리보기 상자 크기 — 키 실측 크기에서 낸다. 값을 테스트로 고정하려고 분리했다.
    static func previewSize(keySize: CGSize) -> CGSize {
        // 아이폰에서는 상수가 그대로 이긴다 (위 phoneKeyWidthCeiling 주석)
        guard keySize.width > phoneKeyWidthCeiling else { return CGSize(width: 46, height: 52) }
        return CGSize(
            // 천지인처럼 아주 넓은 키(140pt)에서 미리보기가 과하게 커지지 않게 증가폭도 묶는다
            width: min(keySize.width * previewWidthRatio, keySize.width + 30),
            height: keySize.height * previewHeightRatio
        )
    }

    private var preview: some View {
        let box = Self.previewSize(keySize: keySize)
        let width = box.width
        let height = box.height
        // 글자도 상자와 같은 비율로 (아이폰 34pt 기준)
        let glyph = (displayLabel.count > 1 ? 24.0 : 34.0) * (height / 52)
        // 오버레이는 부모(키) 폭을 제안하므로 ".com" 같은 다문자 라벨이 ".c…"로 잘렸다 (실기 피드백
        // 2026-09-04) — fixedSize로 고유 폭을 쓰고, 다문자는 글자를 낮춘다
        return Text(displayLabel)
            .font(.system(size: glyph))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(theme.keyText)
            .padding(.horizontal, 8)
            .frame(minWidth: width, minHeight: height)
            .background(theme.characterKey, in: .rect(cornerRadius: 8))
            .shadow(radius: 2)
            .offset(y: -(height + 4))
            .allowsHitTesting(false)
    }

    /// 눌림 즉시 반응해야 하므로 DragGesture(minimumDistance: 0)를 쓴다.
    /// 백스페이스는 누르는 순간 1회 + 길게 누르면 반복. 스페이스는 400ms 누르고 있으면 트랙패드 모드 —
    /// 그 전에 움직여도 취소하지 않는다(진입 시점까지의 이동은 버린다). 400ms 전에 떼면 그냥 스페이스.
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                latestTranslation = value.translation.width
                guard isPressed else {
                    isPressed = true
                    onPress?()
                    if key.event == .backspace {
                        onEvent(.backspace)
                        startBackspaceRepeat()
                    } else if key.event == .space, onCursorDrag != nil {
                        startCursorModeTimer()
                    } else if key.alternate != nil {
                        startAlternateTimer()
                    }
                    return
                }
                if cursorMode {
                    // 8pt마다 문자 1개 — 소비한 만큼만 누적해 잔여 이동을 다음으로 넘긴다
                    let delta = value.translation.width - consumedTranslation
                    let steps = Int((delta / Self.cursorStep).rounded(.towardZero))
                    if steps != 0 {
                        onCursorDrag?(steps)
                        consumedTranslation += CGFloat(steps) * Self.cursorStep
                    }
                }
            }
            .onEnded { _ in
                isPressed = false
                repeatTask?.cancel()
                repeatTask = nil
                cursorModeTask?.cancel()
                cursorModeTask = nil
                if cursorMode {
                    cursorMode = false  // 트랙패드 모드였으면 스페이스를 넣지 않는다
                    return
                }
                alternateTask?.cancel()
                alternateTask = nil
                let armed = alternateArmed
                alternateArmed = false
                if key.event != .backspace {
                    // 길게 눌러 무장됐으면 대체 입력(","·".com"), 아니면 본래 이벤트
                    onEvent(armed ? (key.alternate ?? key.event) : key.event)
                }
            }
    }

    /// 길게 누르기 — 450ms 뒤 대체 입력으로 무장한다. 표면 라벨이 바뀌고 키 피드백이 1회 난다.
    private func startAlternateTimer() {
        alternateTask = Task {
            try? await Task.sleep(for: Self.alternateDelay)
            guard !Task.isCancelled else { return }
            alternateArmed = true
            onPress?()
        }
    }

    private func startBackspaceRepeat() {
        repeatTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            while !Task.isCancelled {
                onPress?()
                onEvent(.backspace)
                try? await Task.sleep(for: .milliseconds(80))
            }
        }
    }

    private func startCursorModeTimer() {
        cursorModeTask = Task {
            try? await Task.sleep(for: Self.cursorModeDelay)
            guard !Task.isCancelled else { return }
            consumedTranslation = latestTranslation  // 진입 시점까지의 흔들림은 버린다
            cursorMode = true
            onPress?()  // 진입 피드백 (진동·클릭)
        }
    }

    /// VoiceOver 이름·힌트 — 표는 `KeyCapAccessibility` 한 곳(테스트가 고정한다)
    private var accessibilityName: String { KeyCapAccessibility.name(for: key, label: label) }
}


/// 키캡의 VoiceOver 대체 동작 — 길게 누르기(`Key.alternate`)를 **로터 「동작」**으로 연다.
///
/// 길게 누르기는 450ms 무장 제스처라 VoiceOver 사용자가 쓰기 어렵다(「두 번 탭 후 누르고 있기」가 통과하는지도
/// 실기 미확인). 그래서 키패드형 페이지 키의 「이전 페이지」가 VoiceOver에서 **닿지 않았다**.
///
/// ## 범위 — 어느 키에 붙이나
///
/// | 키 | 붙이나 | 근거 |
/// |---|---|---|
/// | 키패드 **페이지 키**(`keypadPagePrevious`) | **붙인다** | 「이전」은 이 키 말고 갈 길이 없다(다음으로 세 번 돌 수는 있다) |
/// | 스페이스 옆 **문장부호 키**(`punct` — `,`·`.com`·`#`) | **붙인다** | 한 자판에 **하나뿐**이고, 문자 자판을 떠나지 않고 `,`를 얻는 유일한 길이다 |
/// | 문자 키의 **길게 누르기 기호**(`[`·`#`·`@` … 26개 남짓) | **붙이지 않는다** | 전부 「123」 기호 자판에 있다(길게 누르기는 지름길일 뿐). 붙이면 VoiceOver가 **글자 키에 초점이 갈 때마다** 「동작 사용 가능」을 덧붙여 읽어 타이핑 흐름이 시끄러워진다 |
///
/// 판정은 여기 한 곳이다 — `KeyCapAccessibilityTests`가 고정한다.
enum KeyCapAccessibility {

    /// VoiceOver가 읽는 키 이름. `label`은 **지금 보이는** 라벨(시프트 반영)이다.
    ///
    /// - 문자 복귀 키(`.symbols`) — 키패드형은 돌아갈 모드를 라벨로 보여 주므로(「가」/「ABC」, 2026-09-28 개정)
    ///   **둘 다 「문자 자판」**이다. 문자 자판의 「123」만 「기호」.
    /// - 연타 키(`.multiTap`) — 라벨 `.,-/`를 그대로 읽으면 「점 쉼표…」가 기호 낭독 설정에 따라 들쭉날쭉하다.
    ///   글자마다 이름을 붙여 「마침표 쉼표 하이픈 슬래시」로 읽는다.
    static func name(for key: LayoutDefinition.Key, label: String) -> String {
        switch key.event {
        case .backspace: "지우기"
        case .space: "스페이스"
        case .return: key.symbol == "checkmark" ? "완료" : (label == "⏎" ? "리턴" : label)
        case .shift: "시프트"
        case .toggleLanguage: key.id == "globe" ? "다음 키보드" : "한영 전환"
        case .symbols: (label == "ABC" || label == "가") ? "문자 자판" : "기호"
        case .symbolsAlternate: label == "123" ? "기호 첫 페이지" : "기호 더보기"
        case .advance: "이동"
        case .keypadPageNext: "다음 페이지"
        case .keypadPagePrevious: "이전 페이지"
        case .multiTap(let characters): characters.map { spokenNames[$0] ?? $0 }.joined(separator: " ")
        case .character: label
        case .spacer: ""
        }
    }

    /// VoiceOver 힌트 — 연타 키에만. VoiceOver로는 연타(0.8초 안에 두 번 탭)가 어렵다는 것까지 알린다 —
    /// 네 기호는 페이지 키 한 번 너머 기호 1페이지(2/4)에도 있다(`LayoutDefinition.keypadSymbolPages` 주석).
    static func hint(for key: LayoutDefinition.Key) -> String? {
        guard case .multiTap = key.event else { return nil }
        return "빠르게 다시 누를 때마다 다음 기호로 바뀜. 네 기호는 다음 페이지에도 있음"
    }

    private static let spokenNames: [String: String] = [
        ".": "마침표", ",": "쉼표", "-": "하이픈", "/": "슬래시"
    ]

    struct AlternateAction: Equatable {
        /// 로터에 보이는 이름
        let name: String
        let event: KeyEvent
    }

    static func alternateAction(for key: LayoutDefinition.Key) -> AlternateAction? {
        guard let alternate = key.alternate else { return nil }
        switch alternate {
        case .keypadPagePrevious:
            return AlternateAction(name: "이전 페이지", event: alternate)
        case .keypadPageNext:
            return AlternateAction(name: "다음 페이지", event: alternate)
        case .character(let text):
            // 문자 키 기호는 제외 — 위 표. 문장부호 키 하나만.
            guard key.id == "punct" else { return nil }
            return AlternateAction(name: "\(text) 입력", event: alternate)
        default:
            return nil
        }
    }
}
