import SwiftUI

/// 채움글 안내 애니메이션의 **장면 상태** — 순수 값. 뷰(`SnippetIntroAnimationView`)는 이 값만 그리고,
/// 스크립트(`SnippetIntroScript`)가 시간에 따라 값을 바꾼다. 화면에 있는 동안 반복된다.
///
/// 데모 문자열은 전부 상수다 — 사용자 입력은 어디에도 들어오지 않는다 (`.claude/rules/security.md`).
struct SnippetIntroScene: Equatable, Sendable {

    enum ToolbarMode: Equatable, Sendable {
        /// 도구 행 (내리기 · 커서 ◀▶ · 이모지)
        case tools
        /// 채움글 후보 칩 — 내용은 `scenario.reaction`
        case chip
        /// 추천단어 2개 + 「단어로 구절 찾기」 배지 (v1.2.0 ⑦)
        case bible
    }

    /// 카메라 — 캔버스(360×290) 위의 어느 점을 얼마나 확대해 카드 중심에 둘지.
    struct Camera: Equatable, Sendable {
        /// 1 = 캔버스 전체가 카드에 꼭 맞는 배율. 값은 그 배율에 대한 상대 확대.
        var zoom: CGFloat
        /// 카드 중심에 올 캔버스 좌표
        var focusX: CGFloat
        var focusY: CGFloat

        /// 전체 보기 — 입력란 + 툴바 + 자판 (캔버스 중심 180·145).
        /// 날짜·시간 시나리오는 **이 배율로 친다** — 스페이스(하단 행)와 ⇧(3행 맨 왼쪽)를 눌러야 해서
        /// 자판 전체(x 3…357, y 106…286)가 보여야 한다. 확대하면 둘 중 하나가 잘린다.
        static let overview = Camera(zoom: 1, focusX: 180, focusY: 145)
        /// 타이핑 확대 — 입력란과 0~2행이 보인다 (보이는 y 8…240, 2행 끝 239·3행 시작 246). 오른쪽으로 치우친 이유:
        /// 마지막에 누르는 ㅣ가 1행 맨 오른쪽이라 눌린 키·미리보기가 잘리지 않아야 한다 (왼쪽 열 ㅂ·ㅁ·⇧는 프레임 밖)
        static let typing = Camera(zoom: 1.25, focusX: 213, focusY: 124)
        /// 칩 확대 — 칩(캔버스 x 10…310)이 통째로 들어오고 입력란도 함께 보여 치환 결과까지 한 프레임에 담긴다 (보이는 y 0…252)
        static let toolbar = Camera(zoom: 1.15, focusX: 160, focusY: 126)
        /// 배지 확대 — 오른쪽 끝의 배지(≈ x 254…310)·✕(x 320…350)와 입력란이 함께 들어온다 (보이는 x 43.5…356.5, y 0…252)
        static let badge = Camera(zoom: 1.15, focusX: 200, focusY: 126)
        /// 구절 패널 확대 — 툴바 + 패널(y 106…286)이 들어온다 (보이는 x 19…341, y 40.5…299.5)
        static let panel = Camera(zoom: 1.12, focusX: 180, focusY: 170)
    }

    /// 지금 재생 중인 시나리오 — 칩 내용·배지·패널이 여기서 나온다
    var scenario: SnippetIntroScenario = .birthday
    /// 모형 입력란의 글자 (조합 중 음절 포함 — 실제 키보드처럼 밑줄 없음)
    var text = ""
    /// 지금 눌린 키 — 라벨(두벌식 라벨은 키마다 고유) 또는 기능 키 id(`shift`)
    var pressedKeyLabel: String?
    /// ⇧ 한 번 — 1행 쌍자음 라벨(ㅃㅉㄸㄲㅆ·ㅒㅖ)이 보이고 ⇧ 표면이 `shift.fill`이 된다
    var isShifted = false
    var toolbarMode: ToolbarMode = .tools
    /// 칩(또는 배지)이 눌린 순간 (배경 60% — 눌린 키와 같은 표현)
    var chipPressed = false
    /// 칩(또는 배지) 위의 손가락 표시
    var showsTapIndicator = false
    /// 자판 자리를 구절 목록 패널이 차지한다 (성경 시나리오의 결과)
    var showsBiblePanel = false
    /// 결과가 들어왔다 — 캐럿을 숨긴다
    var showsResult = false
    var camera: Camera = .overview
    /// 루프 경계의 페이드 (결과 → 빈 입력란으로 튀지 않게)
    var canvasOpacity: Double = 1

    /// 시나리오 시작 — 보이지 않는 상태에서 리셋한다
    static func initial(_ scenario: SnippetIntroScenario) -> SnippetIntroScene {
        SnippetIntroScene(scenario: scenario, text: scenario.startText, canvasOpacity: 0)
    }
    /// 동작 줄이기(접근성)에서 보여줄 정지 화면 — 첫 시나리오(생일축하) 치환이 끝난 마지막 장면
    static let finalFrame = SnippetIntroScene(scenario: .birthday, text: SnippetIntroDemo.body, showsResult: true)
}

/// 시나리오 하나 — 타이핑 → 툴바 반응 → 탭 → 결과. 순환 순서는 `loop`.
struct SnippetIntroScenario: Equatable, Sendable {

    enum Reaction: Equatable, Sendable {
        /// 채움글 칩 — 탭하면 입력란이 `body`로 바뀐다
        case chip(title: String, body: String)
        /// 「단어로 구절 찾기」 배지 — 탭하면 자판 자리에 구절 목록 패널
        case bibleBadge
    }

    let id: String
    /// 타이핑 전부터 입력란에 있는 글자 — 「3일 후 날짜」의 `3`(숫자는 기호 자판에서 치므로 그 전환은 보이지 않는다)
    var startText = ""
    let typingSteps: [SnippetIntroScript.TypingStep]
    let typingCamera: SnippetIntroScene.Camera
    let reaction: Reaction

    /// ★ 순환 순서 (사장님 결정 2026-09-27, `bible-search-discovery.md` 6절 1번 (가)) —
    /// **성경 검색을 날짜 셋보다 앞에**. 구절 찾기는 v1.1.0부터 있었는데 기본 꺼짐 + 네 단계 깊이라
    /// 발견성 부채가 더 오래됐다(먼저 갚는다). 날짜 셋은 `date-snippet-pack.md` 8-2절.
    static let loop: [SnippetIntroScenario] = [.birthday, .love, .today, .threeDaysLater, .now]

    typealias Step = SnippetIntroScript.TypingStep

    /// 생일축하 — 인사·상용구 팩 (최초 시나리오, 2026-09-08)
    static let birthday = SnippetIntroScenario(
        id: "birthday",
        typingSteps: [
            Step("ㅅ", "ㅅ"), Step("ㅐ", "새"), Step("ㅇ", "생"), Step("ㅇ", "생ㅇ"), Step("ㅣ", "생이"),
            Step("ㄹ", "생일"), Step("ㅊ", "생일ㅊ"), Step("ㅜ", "생일추"), Step("ㄱ", "생일축"),
            Step("ㅎ", "생일축ㅎ"), Step("ㅏ", "생일축하")
        ],
        typingCamera: .typing,
        reaction: .chip(title: SnippetIntroDemo.title, body: SnippetIntroDemo.body))

    /// 사랑 — 「단어로 구절 찾기」(v1.2.0 ⑦). 기능이 꺼져 있어도 모형이라 항상 재생된다(수용 기준 2).
    /// 드래그 선택(A)이 없어도 성립한다 — 단어를 치는 기존 기능만 보여 준다.
    static let love = SnippetIntroScenario(
        id: "love",
        typingSteps: [Step("ㅅ", "ㅅ"), Step("ㅏ", "사"), Step("ㄹ", "살"), Step("ㅏ", "사라"), Step("ㅇ", "사랑")],
        typingCamera: .typing,
        reaction: .bibleBadge)

    /// 오늘 날짜 — 날짜·시간 팩(v1.2.0 ②). 「짜」는 ⇧ + ㅈ
    static let today = SnippetIntroScenario(
        id: "today",
        typingSteps: [
            Step("ㅇ", "ㅇ"), Step("ㅗ", "오"), Step("ㄴ", "온"), Step("ㅡ", "오느"), Step("ㄹ", "오늘"),
            Step(" ", "오늘 "), Step("ㄴ", "오늘 ㄴ"), Step("ㅏ", "오늘 나"), Step("ㄹ", "오늘 날"),
            Step("shift", "오늘 날", shiftedAfter: true), Step("ㅉ", "오늘 날ㅉ"), Step("ㅏ", "오늘 날짜")
        ],
        typingCamera: .overview,
        reaction: .chip(title: "오늘 날짜", body: SnippetIntroDateDemo.today))

    /// 3일 후 날짜 — 숫자 패턴이 된다는 것을 보여 준다. `3`은 처음부터 있다(`startText`)
    static let threeDaysLater = SnippetIntroScenario(
        id: "threeDaysLater",
        startText: "3",
        typingSteps: [
            Step("ㅇ", "3ㅇ"), Step("ㅣ", "3이"), Step("ㄹ", "3일"), Step(" ", "3일 "),
            Step("ㅎ", "3일 ㅎ"), Step("ㅜ", "3일 후"), Step(" ", "3일 후 "),
            Step("ㄴ", "3일 후 ㄴ"), Step("ㅏ", "3일 후 나"), Step("ㄹ", "3일 후 날"),
            Step("shift", "3일 후 날", shiftedAfter: true), Step("ㅉ", "3일 후 날ㅉ"), Step("ㅏ", "3일 후 날짜")
        ],
        typingCamera: .overview,
        reaction: .chip(title: "3일 후 날짜", body: SnippetIntroDateDemo.threeDaysLater))

    /// 지금 시간
    static let now = SnippetIntroScenario(
        id: "now",
        typingSteps: [
            Step("ㅈ", "ㅈ"), Step("ㅣ", "지"), Step("ㄱ", "직"), Step("ㅡ", "지그"), Step("ㅁ", "지금"),
            Step(" ", "지금 "), Step("ㅅ", "지금 ㅅ"), Step("ㅣ", "지금 시"), Step("ㄱ", "지금 식"),
            Step("ㅏ", "지금 시가"), Step("ㄴ", "지금 시간")
        ],
        typingCamera: .overview,
        reaction: .chip(title: "지금 시간", body: SnippetIntroDateDemo.now))
}

/// 데모에 쓰는 채움글 — `Greetings.json`의 "생일축하" 항목과 같은 값을 상수로 둔다.
/// (팩 본문이 바뀌면 여기도 맞춘다 — 애니메이션은 이 문자열의 타이핑 단계까지 미리 계산돼 있다)
enum SnippetIntroDemo {
    static let trigger = "생일축하"
    static let title = "생일 축하"
    static let body = "생일 진심으로 축하드립니다. 오늘 하루 사랑하는 사람들과 행복한 시간 보내시고, 앞으로의 한 해도 건강하고 좋은 일만 가득하길 바랍니다."
}

/// 날짜·시간 팩 데모 값 — **규범형**(기본 출력 형식, 실제 삽입값과 같은 모양).
/// mirror: KeyboardCore/DateSnippetFormatter.swift `.formal` — `2026. 9. 27.` · `21:54` (0 채움은 시·분만).
/// 기준 시각 2026-09-27 21:54(PDR `date-snippet-pack.md` 4-1절 표와 같다). 실제 칩은 치는 순간을 계산한다.
enum SnippetIntroDateDemo {
    static let today = "2026. 9. 27."
    static let threeDaysLater = "2026. 9. 30."
    static let now = "21:54"
}

/// 「단어로 구절 찾기」 데모 값 — **실제 `bible.tdb`·`words.tdw`로 계산한 값을 그대로** 복제했다(2026-09-28).
/// `BibleSearchCascade.search(tail: "사랑")` → 517건 · 첫 행·책 필터, `SuggestionEngine.suggestions("사랑", limit: 2)`
/// (배지가 있으면 추천단어는 2개 — `KeyboardMetrics.wordSuggestionLimit`). 성경·사전 데이터를 바꾸면 다시 뽑는다.
enum SnippetIntroBibleDemo {
    static let query = "사랑"
    /// mirror: KeyboardUI/BibleCountText.swift `label` — 999 이하는 그대로
    static let count = "517"
    static let words = ["사랑해", "사랑하는"]
    /// mirror: KeyboardUI/BibleSearchPanelView.swift `chipLabel` — 「이름(건수)」
    static let filters = ["전체(517)", "아가(54)", "시편(40)", "요한복음(39)"]
    /// mirror: `BibleSearchRow.reference(includingBook: true)` · `BibleVersePreview.window` (40자 창 + …)
    static let rows: [(reference: String, preview: String)] = [
        ("요일 4:10", "사랑은 여기 있으니 우리가 하나님을 사랑한 것이 아…"),
        ("고전 13:4", "사랑은 오래 참고 사랑은 온유하며 투기하는 자가 되…"),
        ("고전 13:8", "사랑은 언제까지든지 떨어지지 아니하나 예언도 폐하고…")
    ]
}

/// 시간표 — 시나리오 하나(≈8~11초)를 순서대로 재생한다. 대기는 전부 `Task.sleep`이라 뷰가 사라지면
/// `CancellationError`로 곧바로 빠져나온다 (`.task(id:)`가 취소한다).
///
/// PhaseAnimator/KeyframeAnimator를 쓰지 않은 이유: 단계가 ~20개에 지속시간이 제각각이고(80ms 키 눌림 ~ 2.6초 정지),
/// 문자열·불리언처럼 보간되지 않는 상태를 "애니메이션 없이" 바꾸는 단계가 섞여 있다. 선형 스크립트가
/// 스토리보드 그대로 읽히고 검토도 쉽다.
enum SnippetIntroScript {

    /// 키 입력 한 번 — 자모 단위 조합 결과를 미리 계산해 둔다.
    /// HangulEngine을 쓰지 않는다 — 앱은 엔진을 import하지 않는다 (PDR settings-app 결정 5).
    /// 같은 키 연속(ㅇ→ㅇ)도 두 단계이고, ⇧도 한 단계다(`key == "shift"`, 글자는 그대로).
    struct TypingStep: Equatable, Sendable {
        /// 누르는 키 — 라벨(⇧가 켜져 있으면 쌍자음 라벨) 또는 기능 키 id(`shift`), 스페이스는 `" "`
        let key: String
        let text: String
        /// 이 키를 뗀 뒤 ⇧ 상태 — ⇧는 한 번(once)이라 쌍자음을 치고 나면 꺼진다
        let shiftedAfter: Bool

        init(_ key: String, _ text: String, shiftedAfter: Bool = false) {
            self.key = key
            self.text = text
            self.shiftedAfter = shiftedAfter
        }
    }

    /// 장면 변경 적용자 — 애니메이션이 nil이면 즉시(트랜잭션 없이) 바꾼다.
    typealias Apply = (Animation?, (inout SnippetIntroScene) -> Void) -> Void

    /// 시나리오 하나를 재생한다. 호출자가 `SnippetIntroScenario.loop`를 돌며 반복한다.
    @MainActor
    static func run(_ scenario: SnippetIntroScenario, apply: Apply) async throws {
        // 0.0 — 리셋 후 페이드 인
        apply(nil) { $0 = .initial(scenario) }
        apply(.easeOut(duration: 0.3)) { $0.canvasOpacity = 1 }
        try await pause(300)

        // 0.3 — 타이핑 위치로 (날짜·시간은 전체 보기 그대로 — Camera.overview 주석)
        if scenario.typingCamera != .overview {
            apply(.easeInOut(duration: 0.6)) { $0.camera = scenario.typingCamera }
            try await pause(700)
        }

        // 자모 단위로 친다 (키당 280ms)
        for step in scenario.typingSteps {
            apply(nil) { $0.text = step.text }  // 글자는 애니메이션 없이 — 크로스페이드되면 타이핑처럼 보이지 않는다
            apply(.linear(duration: 0.08)) { $0.pressedKeyLabel = step.key }
            try await pause(120)
            apply(.linear(duration: 0.08)) { $0.pressedKeyLabel = nil }
            apply(nil) { $0.isShifted = step.shiftedAfter }   // ⇧ 라벨 전환은 즉시 (실제 키보드도 전환 애니메이션 없음)
            try await pause(160)
        }
        try await pause(500)

        // 전체 보기로 축소, 툴바 반응 등장
        if scenario.typingCamera != .overview {
            apply(.easeInOut(duration: 0.6)) { $0.camera = .overview }
            try await pause(800)
        }
        let isBible = scenario.reaction == .bibleBadge
        apply(.spring(duration: 0.28, bounce: 0.25)) { $0.toolbarMode = isBible ? .bible : .chip }  // mirror: KeyboardUI 칩 스프링
        try await pause(500)

        // 반응 요소로 확대, 탭
        apply(.easeInOut(duration: 0.6)) { $0.camera = isBible ? .badge : .toolbar }
        try await pause(800)
        apply(.easeOut(duration: 0.15)) { $0.showsTapIndicator = true }
        try await pause(150)
        apply(.linear(duration: 0.08)) { $0.chipPressed = true }
        try await pause(120)

        switch scenario.reaction {
        case .chip(_, let body):
            // 단축어가 결과로 바뀌고 칩은 도구 행으로 돌아간다 (실제 동작: 삽입 뒤 꼬리가 단축어와 안 맞는다)
            apply(.easeInOut(duration: 0.25)) {
                $0.text = body
                $0.chipPressed = false
                $0.showsResult = true
            }
            apply(.spring(duration: 0.28, bounce: 0.25)) { $0.toolbarMode = .tools }
            try await pause(150)
            apply(.easeIn(duration: 0.25)) { $0.showsTapIndicator = false }
        case .bibleBadge:
            // 배지를 누르면 자판 자리에 구절 목록 — 결과를 읽을 수 있게 패널로 카메라를 옮긴다
            apply(.easeInOut(duration: 0.25)) {
                $0.chipPressed = false
                $0.showsBiblePanel = true
                $0.showsResult = true
            }
            try await pause(150)
            apply(.easeIn(duration: 0.25)) { $0.showsTapIndicator = false }
            try await pause(350)
            apply(.easeInOut(duration: 0.6)) { $0.camera = .panel }
            try await pause(600)
        }

        // 결과를 읽을 시간, 페이드 아웃
        try await pause(2600)
        apply(.easeIn(duration: 0.3)) { $0.canvasOpacity = 0 }
        try await pause(350)
    }

    private static func pause(_ milliseconds: Int) async throws {
        try await Task.sleep(for: .milliseconds(milliseconds))
    }
}
