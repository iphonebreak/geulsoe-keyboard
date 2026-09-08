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
        alternateArmed ? (key.alternateLabel ?? label) : label
    }

    var body: some View {
        face
            .foregroundStyle(theme.keyText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) {
                // 길게 누르기 힌트 (문장부호 키의 ","·".com") — 무장되면 라벨 자체가 바뀌므로 숨긴다.
                // 뷰를 넣고 빼지 않고 투명도만 바꾼다 (누르는 도중 구조 변경 금지 — face 주석 참조)
                if let hint = key.alternateLabel {
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
            .accessibilityAddTraits(.isKeyboardKey)
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

    /// 눌린 키 위에 뜨는 확대 미리보기
    private var preview: some View {
        // 오버레이는 부모(키) 폭을 제안하므로 ".com" 같은 다문자 라벨이 ".c…"로 잘렸다 (실기 피드백
        // 2026-09-04) — fixedSize로 고유 폭을 쓰고, 다문자는 글자를 낮춘다
        Text(displayLabel)
            .font(.system(size: displayLabel.count > 1 ? 24 : 34))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(theme.keyText)
            .padding(.horizontal, 8)
            .frame(minWidth: 46, minHeight: 52)
            .background(theme.characterKey, in: .rect(cornerRadius: 8))
            .shadow(radius: 2)
            .offset(y: -56)
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

    private var accessibilityName: String {
        switch key.event {
        case .backspace: "지우기"
        case .space: "스페이스"
        case .return: key.symbol == "checkmark" ? "완료" : (label == "⏎" ? "리턴" : label)
        case .shift: "시프트"
        case .toggleLanguage: key.id == "globe" ? "다음 키보드" : "한영 전환"
        case .symbols: label == "ABC" ? "문자 자판" : "기호"
        case .symbolsAlternate: label == "123" ? "기호 첫 페이지" : "기호 더보기"
        case .advance: "이동"
        case .character: label
        case .spacer: ""
        }
    }
}
