import SwiftUI

/// 채움글 안내 애니메이션의 **장면 상태** — 순수 값. 뷰(`SnippetIntroAnimationView`)는 이 값만 그리고,
/// 스크립트(`SnippetIntroScript`)가 시간에 따라 값을 바꾼다. 화면에 있는 동안 반복된다.
///
/// 데모 문자열은 전부 상수다 — 사용자 입력은 어디에도 들어오지 않는다 (`.claude/rules/security.md`).
struct SnippetIntroScene: Equatable, Sendable {

    enum ToolbarMode: Equatable, Sendable {
        /// 도구 행 (내리기 · 커서 ◀▶ · 이모지)
        case tools
        /// 채움글 후보 칩
        case chip
    }

    /// 카메라 — 캔버스(360×290) 위의 어느 점을 얼마나 확대해 카드 중심에 둘지.
    struct Camera: Equatable, Sendable {
        /// 1 = 캔버스 전체가 카드에 꼭 맞는 배율. 값은 그 배율에 대한 상대 확대.
        var zoom: CGFloat
        /// 카드 중심에 올 캔버스 좌표
        var focusX: CGFloat
        var focusY: CGFloat

        /// 전체 보기 — 입력란 + 툴바 + 자판 (캔버스 중심 180·145)
        static let overview = Camera(zoom: 1, focusX: 180, focusY: 145)
        /// 타이핑 확대 — 입력란과 0~2행이 보인다 (보이는 y 8…240, 2행 끝 239·3행 시작 246). 오른쪽으로 치우친 이유:
        /// 마지막에 누르는 ㅣ가 1행 맨 오른쪽이라 눌린 키·미리보기가 잘리지 않아야 한다 (왼쪽 열 ㅂ·ㅁ·⇧는 프레임 밖)
        static let typing = Camera(zoom: 1.25, focusX: 213, focusY: 124)
        /// 칩 확대 — 칩(캔버스 x 10…310)이 통째로 들어오고 입력란도 함께 보여 치환 결과까지 한 프레임에 담긴다 (보이는 y 0…252)
        static let toolbar = Camera(zoom: 1.15, focusX: 160, focusY: 126)
    }

    /// 모형 입력란의 글자 (조합 중 음절 포함 — 실제 키보드처럼 밑줄 없음)
    var text = ""
    /// 지금 눌린 키의 라벨 (두벌식 라벨은 키마다 고유하므로 라벨로 찾는다)
    var pressedKeyLabel: String?
    var toolbarMode: ToolbarMode = .tools
    /// 칩이 눌린 순간 (배경 60% — 눌린 키와 같은 표현)
    var chipPressed = false
    /// 칩 위의 손가락 표시
    var showsTapIndicator = false
    var camera: Camera = .overview
    /// 루프 경계의 페이드 (전문 → 빈 입력란으로 튀지 않게)
    var canvasOpacity: Double = 1

    /// 루프 시작 — 보이지 않는 상태에서 리셋한다
    static let initial = SnippetIntroScene(canvasOpacity: 0)
    /// 동작 줄이기(접근성)에서 보여줄 정지 화면 — 치환이 끝난 마지막 장면
    static let finalFrame = SnippetIntroScene(text: SnippetIntroDemo.body)
}

/// 데모에 쓰는 채움글 — `Greetings.json`의 "생일축하" 항목과 같은 값을 상수로 둔다.
/// (팩 본문이 바뀌면 여기도 맞춘다 — 애니메이션은 이 문자열의 타이핑 단계까지 미리 계산돼 있다)
enum SnippetIntroDemo {
    static let trigger = "생일축하"
    static let title = "생일 축하"
    static let body = "생일 진심으로 축하드립니다. 오늘 하루 사랑하는 사람들과 행복한 시간 보내시고, 앞으로의 한 해도 건강하고 좋은 일만 가득하길 바랍니다."
}

/// 시간표 — 한 루프(≈10초)를 순서대로 재생한다. 대기는 전부 `Task.sleep`이라 뷰가 사라지면
/// `CancellationError`로 곧바로 빠져나온다 (`.task(id:)`가 취소한다).
///
/// PhaseAnimator/KeyframeAnimator를 쓰지 않은 이유: 단계가 ~20개에 지속시간이 제각각이고(80ms 키 눌림 ~ 2.6초 정지),
/// 문자열·불리언처럼 보간되지 않는 상태를 "애니메이션 없이" 바꾸는 단계가 섞여 있다. 선형 스크립트가
/// 스토리보드 그대로 읽히고 검토도 쉽다.
enum SnippetIntroScript {

    /// 자모 단위 조합 단계 — 두벌식으로 "생일축하"를 치는 11번의 키 입력 (ㅇ은 두 번 눌린다).
    /// HangulEngine을 쓰지 않고 미리 계산해 둔다 — 앱은 엔진을 import하지 않는다 (PDR settings-app 결정 5).
    struct TypingStep: Equatable, Sendable {
        let key: String
        let text: String
    }

    static let typingSteps: [TypingStep] = [
        TypingStep(key: "ㅅ", text: "ㅅ"),
        TypingStep(key: "ㅐ", text: "새"),
        TypingStep(key: "ㅇ", text: "생"),
        TypingStep(key: "ㅇ", text: "생ㅇ"),
        TypingStep(key: "ㅣ", text: "생이"),
        TypingStep(key: "ㄹ", text: "생일"),
        TypingStep(key: "ㅊ", text: "생일ㅊ"),
        TypingStep(key: "ㅜ", text: "생일추"),
        TypingStep(key: "ㄱ", text: "생일축"),
        TypingStep(key: "ㅎ", text: "생일축ㅎ"),
        TypingStep(key: "ㅏ", text: "생일축하")
    ]

    /// 장면 변경 적용자 — 애니메이션이 nil이면 즉시(트랜잭션 없이) 바꾼다.
    typealias Apply = (Animation?, (inout SnippetIntroScene) -> Void) -> Void

    /// 한 루프를 재생한다. 호출자가 반복한다.
    @MainActor
    static func run(apply: Apply) async throws {
        // 0.0 — 리셋 후 페이드 인
        apply(nil) { $0 = .initial }
        apply(.easeOut(duration: 0.3)) { $0.canvasOpacity = 1 }
        try await pause(300)

        // 0.3 — 타이핑 위치로 확대
        apply(.easeInOut(duration: 0.6)) { $0.camera = .typing }
        try await pause(700)

        // 1.0 — 자모 단위로 "생일축하" (키당 280ms)
        for step in typingSteps {
            apply(nil) { $0.text = step.text }  // 글자는 애니메이션 없이 — 크로스페이드되면 타이핑처럼 보이지 않는다
            apply(.linear(duration: 0.08)) { $0.pressedKeyLabel = step.key }
            try await pause(120)
            apply(.linear(duration: 0.08)) { $0.pressedKeyLabel = nil }
            try await pause(160)
        }
        try await pause(500)

        // 4.6 — 전체 보기로 축소, 칩 등장
        apply(.easeInOut(duration: 0.6)) { $0.camera = .overview }
        try await pause(800)
        apply(.spring(duration: 0.28, bounce: 0.25)) { $0.toolbarMode = .chip }  // mirror: KeyboardUI SuggestionToolbar 칩 스프링
        try await pause(500)

        // 5.9 — 칩으로 확대, 탭
        apply(.easeInOut(duration: 0.6)) { $0.camera = .toolbar }
        try await pause(800)
        apply(.easeOut(duration: 0.15)) { $0.showsTapIndicator = true }
        try await pause(150)
        apply(.linear(duration: 0.08)) { $0.chipPressed = true }
        try await pause(120)

        // 6.95 — 트리거가 전문으로 바뀌고 칩은 도구 행으로 돌아간다 (실제 동작: 삽입 뒤 꼬리가 트리거와 안 맞는다)
        apply(.easeInOut(duration: 0.25)) {
            $0.text = SnippetIntroDemo.body
            $0.chipPressed = false
        }
        apply(.spring(duration: 0.28, bounce: 0.25)) { $0.toolbarMode = .tools }
        try await pause(150)
        apply(.easeIn(duration: 0.25)) { $0.showsTapIndicator = false }

        // 7.1 — 결과를 읽을 시간, 페이드 아웃
        try await pause(2600)
        apply(.easeIn(duration: 0.3)) { $0.canvasOpacity = 0 }
        try await pause(350)
    }

    private static func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}
