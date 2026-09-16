import XCTest

/// 툴바 탭 — 클립보드·전체 접근 절 **병합 전후 비교 캡처 하네스** (2026-09-15).
///
/// ## 왜 XCUITest 인가
///
/// `simctl` 은 탭을 못 한다. `RootView` 의 `TabView` 는 `selection` 바인딩이 없어 **항상 첫 탭
/// (키보드)에서 시작**하므로, 툴바 탭 화면을 찍으려면 탭을 한 번 눌러야 한다.
/// `agent-device` 는 쓰지 않는다(세션이 다른 기기로 흐르는 결함, 2026-09-15 사고).
/// 그래서 이 하네스가 **요소로** 탭을 누르고 스크린숏을 첨부로 남긴다.
///
/// ## 오염 0 — 이 파일은 앱을 띄운다. 그래서 세 겹으로 막는다
///
/// `LandscapeKeyboardMetricsTests` 와 달리 **여기는 컨테이너 앱을 띄울 수밖에 없다**(찍을 화면이
/// 앱 안에 있다). `FirebaseApp.configure()` 가 돌므로 아래 셋을 모두 건다:
///
/// 1. `-analyticsCollectionEnabled NO` · `-crashlyticsCollectionEnabled NO` — 실행 인자 도메인이
///    `UserDefaults.standard` 저장값보다 **우선**한다. `AnalyticsConsent.applyStoredChoices()` 가
///    이 값을 읽어 수집을 끈다.
/// 2. 실행 **전에** 앱 컨테이너에 `measurement_enabled_state = 0` 을 미리 써 둔다(호출자 쪽 절차).
/// 3. 전용 시뮬레이터에서만 돌린다 — 남의 기기를 건드리지 않는다.
///
/// ## 쓰는 법
///
/// 라이트/다크/큰 글자는 **테스트가 아니라 시뮬레이터가** 정한다 — 밖에서 바꾸고 다시 돌린다:
/// `xcrun simctl ui <UDID> appearance dark` · `xcrun simctl ui <UDID> content_size <크기>`
/// (`content-size` 가 아니라 **`content_size`** 다 — 하이픈으로 쓰면 simctl 이 조용히 무시하고
/// 세 캡처가 md5 까지 같아진다. 2026-09-14 에 실제로 당했다.)
///
/// 첨부 꺼내기: `xcrun xcresulttool export attachments --path <out.xcresult> --output-path <dir>`
final class ToolbarPermissionCaptureTests: XCTestCase {

    /// 툴바 탭을 열고 위에서 아래까지 훑어 찍는다.
    ///
    /// 한 장으로는 안 된다 — 병합 뒤 클립보드 절이 화면 한 장보다 길다. 스크롤하며 여러 장을 남기고
    /// 판정은 사람이 첨부를 본다(이 저장소의 다른 캡처 하네스와 같은 방식).
    func testCaptureToolbarTab() throws {
        let app = XCUIApplication()
        // 온보딩은 `@AppStorage("hasSeenOnboarding")` 라 실행 인자로 건너뛴다 —
        // 안 그러면 `fullScreenCover` 가 화면을 통째로 덮어 탭이 보이지 않는다.
        app.launchArguments += [
            "-hasSeenOnboarding", "YES",
            "-analyticsCollectionEnabled", "NO",
            "-crashlyticsCollectionEnabled", "NO"
        ]
        app.launch()

        let toolbarTab = app.tabBars.buttons["툴바"]
        XCTAssertTrue(toolbarTab.waitForExistence(timeout: 20), "툴바 탭 버튼을 찾지 못했다")
        toolbarTab.tap()

        // 탭 전환 애니메이션이 끝나기를 기다린다 — 화면 안의 아무 행이나 나타나면 됐다
        let anchor = app.staticTexts["클립보드"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "클립보드 절 머리글이 보이지 않는다")

        attach(app.screenshot(), name: "toolbar-01-top")

        // Form 을 아래로 훑는다. 스와이프 횟수는 넉넉히 잡고, 더 안 움직이면 멈춘다.
        var previous = ""
        for step in 2...6 {
            app.swipeUp()
            let shot = app.screenshot()
            attach(shot, name: String(format: "toolbar-%02d-scroll", step))
            let signature = app.descendants(matching: .any).count.description
                + (app.staticTexts.allElementsBoundByIndex.last?.label ?? "")
            if signature == previous { break }
            previous = signature
        }

        // 권한 시트 — 일반화한 제목·1단계가 실제로 그렇게 나오는지 본다.
        // 2026-09-15: 버튼 이름이 「왜 두 가지가 필요한지 보기」 → 「전체 접근 켜는 방법 보기」로
        // 바뀌었다. 옛 이름도 함께 찾는다 — **병합 전 빌드와도 같은 하네스로 비교**해야 한다.
        let sheetButton = app.buttons["전체 접근 켜는 방법 보기"].exists
            ? app.buttons["전체 접근 켜는 방법 보기"]
            : app.buttons["왜 두 가지가 필요한지 보기"]
        if sheetButton.waitForExistence(timeout: 5) {
            sheetButton.tap()
            XCTAssertTrue(app.staticTexts["전체 접근이 필요해요"].waitForExistence(timeout: 10),
                          "시트 제목이 일반화되지 않았다")
            attach(app.screenshot(), name: "sheet-01-top")
            app.swipeUp()
            attach(app.screenshot(), name: "sheet-02-scroll")
            app.swipeUp()
            attach(app.screenshot(), name: "sheet-03-scroll")
        } else {
            // 병합 **전** 빌드에는 이 버튼이 없다 — 실패가 아니라 그게 비교 대상이다
            attach(app.screenshot(), name: "sheet-00-absent")
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
