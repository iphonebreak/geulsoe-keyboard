import SwiftUI

/// 온보딩 2쪽("키보드 추가하기") 안내 애니메이션의 **장면 상태** — 순수 값.
/// 뷰(`InstallIntroAnimationView`)는 이 값만 그리고, 스크립트(`InstallIntroScript`)가 시간에 따라 값을 바꾼다.
/// 구조는 채움글 카드(`App/Settings/SnippetIntroScene.swift`)와 같다 — 값/스크립트/뷰 3분리, 카메라만 움직임.
///
/// 화면 글자는 전부 아래 `InstallIntroCopy` 상수다. 사용자 입력이 들어오는 경로가 없다
/// (`.claude/rules/security.md` — 온보딩은 키보드가 켜지기도 전이라 입력 자체가 존재하지 않는다).
struct InstallIntroScene: Equatable, Sendable {

    /// 카메라 — 캔버스(360×380) 위의 어느 점을 얼마나 확대해 카드 중심에 둘지.
    /// 카드에 보이는 창은 360×180(캔버스 단위)이므로 **보이는 폭 = 360/zoom · 보이는 높이 = 180/zoom**.
    struct Camera: Equatable, Sendable {
        var zoom: CGFloat
        var focusX: CGFloat
        var focusY: CGFloat

        /// 설정 목록 전체 — 캔버스 y 0…180 (머리글 + 3행 카드 전부)
        static let settings = Camera(zoom: 1, focusX: 180, focusY: 90)
        /// 스위치 확대 — 보이는 x 36…324(카드 x 40…320 전부), **y 0…144**.
        ///
        /// **focusY 는 72 다. 140 이 아니다.** 140 은 예전 3행 목록의 세 번째 행을 겨냥한 값이었다.
        /// 2박자를 실제 iOS 화면(행 하나 + 스위치)으로 다시 그리면서 카드가 46…98 로 올라왔으므로
        /// 카메라도 같이 내려왔다 — **블록 좌표를 바꾸면 카메라도 고친다**(3박자에서 이걸 안 해서
        /// 하단 키가 33% 잘렸다). 내용 범위 23.5…132 가 창 0…144 안에 전부 들어온다.
        ///
        /// zoom 1.25 를 유지하는 이유: 행 글자 시작(x 60)과 스위치 오른쪽 끝(x 296)이 한 프레임에
        /// 들어와야 한다. 1.25 면 보이는 폭이 288 이라 둘 사이 236 을 담고 좌우 여백도 남는다.
        static let settingsRow = Camera(zoom: 1.25, focusX: 180, focusY: 72)
        /// 입력 장면 — 캔버스 y **215…395** (입력창 216…248 · 자판 256…394).
        ///
        /// **focusY 는 자판 블록의 한가운데다: (216 + 394) / 2 = 305.** 보이는 높이가 180 이므로
        /// 창은 215…395 가 되어 입력창 위 1, 자판 아래 1 만큼 여유를 남기고 **전부 들어간다.**
        /// 이 값을 블록과 따로 움직이면 2026-09-14 의 그 버그가 그대로 재발한다 —
        /// 그때는 캔버스가 380 → 400 으로 커졌는데 focusY 만 옛 값(290)으로 남아
        /// 하단 키가 33% 잘리고 탭 표시가 100% 화면 밖이었다.
        /// **블록 좌표를 바꾸면 이 값도 같이 고쳐라.**
        static let keyboard = Camera(zoom: 1, focusX: 180, focusY: 305)
    }

    /// 눌린 요소 — 실제 키보드의 눌림 표현과 같은 역할
    enum Press: Equatable, Sendable {
        case none
        /// 설정 목록의 글쇠 행
        case settingsRow
        /// 자판 하단 행의 지구본 키
        case globeKey
    }

    /// 지금 올라와 있는 자판. **3박자의 전부**다 — 지구본을 누르면 이 값이 바뀌고,
    /// 사용자는 자판이 그 자리에서 교체되는 것을 본다.
    ///
    /// **전환 목록을 띄우지 않는다.** iOS 에서 지구본을 **탭하면 다음 자판으로 넘어가고,
    /// 목록은 길게 눌러야** 나온다. 예전 판은 탭 뒤에 목록을 띄워 둘을 섞어 놨다
    /// (2026-09-14 검토 지적 10 의 3박자 몫). 사용자 지시대로 다시 그리면서 그 오류도 닫혔다.
    enum ActiveKeyboard: Equatable, Sendable {
        /// 기본 애플 한글 자판 — 회색 바탕에 흰 키캡, 툴바 없음
        case apple
        /// 글쇠 — 툴바가 붙고 바탕에 강조색이 섞인다
        case geulsoe
    }

    /// 설정 목록에서 글쇠가 켜졌나 (체크 표시)
    var keyboardEnabled = false
    /// 3박자에 올라와 있는 자판
    var activeKeyboard: ActiveKeyboard = .apple
    /// 입력창 커서 — 자판이 왜 올라와 있는지를 입력창이 설명한다 (사용자 지시 2026-09-14:
    /// "지구본을 누를 버튼이 안 보이니 사용자가 답답할 것 같다, 입력창을 추가하자")
    var caretVisible = true
    var press: Press = .none
    /// 누르는 지점의 손가락 표시
    var showsTapIndicator = false
    var camera: Camera = .settings
    /// 루프 경계의 페이드 (끝 장면 → 첫 장면으로 튀지 않게)
    var canvasOpacity: Double = 1

    /// 루프 시작 — 보이지 않는 상태에서 리셋한다
    static let initial = InstallIntroScene(canvasOpacity: 0)

    /// 동작 줄이기(접근성)에서 보여 줄 정지 화면.
    /// 세 장면 중 **행동을 지시하는 한 장**을 고른다 — 글쇠가 켜진 설정 목록이다
    /// (지구본 전환은 그다음 단계이고, 켜지 않으면 아예 도달하지 못한다).
    static let finalFrame = InstallIntroScene(keyboardEnabled: true)
}

/// 화면에 그려지는 글자 — 전부 상수다.
enum InstallIntroCopy {
    /// 2박자 화면의 경로 머리글. **네 홉이다.**
    ///
    /// 실제 경로는 `설정 > 앱 > 글쇠 > 키보드` 다 — 반론자가 시뮬에서 직접 걸어 확인했다
    /// (설정 루트에 「앱」 행이 있고 **글쇠는 루트에 없다**).
    ///
    /// **한때 「앱」을 뺀 세 홉이었다. 사장님이 뒤집었고 그 판단이 맞다.**
    /// 처음엔 iOS 17 하한을 이유로 짧은 쪽을 골랐는데, 저울이 한쪽으로만 기운다 —
    /// **iOS 17 에서 짧은 경로는 한 홉이 비는 것뿐이지만, iOS 18 이상에서 짧은 경로는 아예
    /// 존재하지 않는 경로다.** 없는 길을 가리키는 쪽이 더 나쁘다.
    /// 카드 폭 240pt 에 네 홉이 들어가는 것도 확인했다.
    ///
    /// 버전 차이는 **본문 문구가 완충으로 받는다**(`OnboardingView` 1번 항목) — 여긴 자리가 좁다.
    static let pathHeading = "설정 › 앱 › 글쇠 › 키보드"
    static let appName = "글쇠"
    /// 입력창에 이미 쳐져 있는 시연 문구 — **상수다.** 사용자 입력이 들어올 경로는 없다
    /// (`.claude/rules/security.md`). 온보딩은 키보드가 켜지기도 전이라 입력 자체가 존재하지 않는다.
    static let fieldText = "안녕하세요"
    /// 애플 기본 한글 자판(두벌식) 세 줄. 글쇠도 두벌식이라 **글자는 같다** —
    /// 두 자판의 차이는 글자가 아니라 **툴바 유무와 색**으로 낸다.
    static let hangulRows = ["ㅂㅈㄷㄱㅅㅛㅕㅑㅐㅔ", "ㅁㄴㅇㄹㅎㅗㅓㅏㅣ", "ㅋㅌㅊㅍㅠㅜㅡ"]
}

/// 시간표 — 한 루프(≈10.6초)를 순서대로 재생한다. 대기는 전부 `Task.sleep`이라
/// 뷰가 사라지면 `CancellationError`로 곧바로 빠져나온다 (`.task(id:)`가 취소한다).
///
/// 온보딩 2쪽의 항목 1·2·3 을 그대로 세 박자로 옮겼다:
///   1. 설정 열기  → 설정의 키보드 목록이 나타난다
///   2. 키보드 켜기 → 글쇠 행을 눌러 체크가 붙는다
///   3. 지구본 키  → 아래로 내려가 지구본을 누르고 전환 목록에서 글쇠를 고른다
enum InstallIntroScript {

    /// 장면 변경 적용자 — 애니메이션이 nil 이면 즉시(트랜잭션 없이) 바꾼다.
    typealias Apply = (Animation?, (inout InstallIntroScene) -> Void) -> Void

    /// 한 루프를 재생한다. 호출자가 반복한다.
    @MainActor
    static func run(apply: Apply) async throws {
        // 0.00 — 리셋 후 페이드 인 (1단계: 설정 열기 — 목록이 나타난다)
        apply(nil) { $0 = .initial }
        apply(.easeOut(duration: 0.3)) { $0.canvasOpacity = 1 }
        try await pause(1000)

        // 1.00 — 글쇠 행으로 확대 (2단계: 키보드 켜기)
        apply(.easeInOut(duration: 0.6)) { $0.camera = .settingsRow }
        try await pause(1200)

        // 2.20 — 행을 누른다
        apply(.easeOut(duration: 0.15)) { $0.showsTapIndicator = true }
        try await pause(150)
        apply(.linear(duration: 0.08)) { $0.press = .settingsRow }
        try await pause(150)

        // 2.50 — 체크가 붙는다. 스프링 값은 실제 키보드의 칩 등장과 같다
        // mirror: KeyboardUI/KeyboardRootView.swift SuggestionToolbar 칩 스프링
        apply(.spring(duration: 0.28, bounce: 0.25)) {
            $0.keyboardEnabled = true
            $0.press = .none
        }
        try await pause(300)
        apply(.easeIn(duration: 0.25)) { $0.showsTapIndicator = false }
        try await pause(1200)

        // 4.20 — 아래로 내려간다 (3단계: 지구본 키). 입력창과 **애플 기본 자판**이 보인다.
        apply(.easeInOut(duration: 0.7)) { $0.camera = .keyboard }
        try await pause(700)

        // 4.90 — 커서가 한 번 깜빡인다. 입력창이 "지금 입력 중"이라는 걸 말한다.
        apply(nil) { $0.caretVisible = false }
        try await pause(420)
        apply(nil) { $0.caretVisible = true }
        try await pause(600)

        // 5.92 — 지구본을 누른다
        apply(.easeOut(duration: 0.15)) { $0.showsTapIndicator = true }
        try await pause(180)
        apply(.linear(duration: 0.08)) { $0.press = .globeKey }
        try await pause(240)

        // 6.34 — **그 자리에서 자판이 글쇠로 바뀐다.** 목록은 뜨지 않는다 (`ActiveKeyboard` 주석).
        apply(.spring(duration: 0.34, bounce: 0.18)) {
            $0.activeKeyboard = .geulsoe
            $0.press = .none
        }
        try await pause(320)
        apply(.easeIn(duration: 0.25)) { $0.showsTapIndicator = false }

        // 6.91 — 결과를 읽을 시간, 페이드 아웃
        try await pause(2600)
        apply(.easeIn(duration: 0.3)) { $0.canvasOpacity = 0 }
        try await pause(350)
    }

    private static func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}
