import XCTest

/// 테마 미리보기 카드 캡처 하네스 (v1.1.0 ③).
///
/// 4차 계획 5절이 요구한 **하나의 검증 시나리오**를 그대로 돈다 —
/// **설정 화면 → light → dark → AX3 → 테마 전환**. 라이트/다크/AX3 은 시뮬레이터가 정하고
/// (`simctl ui <UDID> appearance|content_size`), 이 테스트는 그 안에서 화면 탭을 열고
/// 카드를 찍은 뒤 **테마를 실제로 바꿔** 선택 표시가 옮겨 가는 것까지 남긴다.
///
/// ## 오염 0 — 이 하네스는 컨테이너 앱을 띄운다
///
/// v1.0.1 이 배포 중이라 실사용자 데이터가 섞인다. 세 겹으로 막는다:
/// 1. 실행 인자 `-analyticsCollectionEnabled NO` · `-crashlyticsCollectionEnabled NO`
///    (인자 도메인이 저장값보다 우선한다 — `AnalyticsConsent` 가 이 값을 읽는다)
/// 2. 첫 실행 **전에** 컨테이너에 `measurement_enabled_state = 0` (호출자 쪽 절차)
/// 3. **전용 시뮬레이터**에서만 — 남의 기기·기존 시뮬은 건드리지 않는다
final class ThemePreviewCaptureTests: XCTestCase {

    func testCaptureThemeCards() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "-hasSeenOnboarding", "YES",
            "-analyticsCollectionEnabled", "NO",
            "-crashlyticsCollectionEnabled", "NO"
        ]
        app.launch()

        let appearanceTab = app.tabBars.buttons["화면"]
        XCTAssertTrue(appearanceTab.waitForExistence(timeout: 20), "화면 탭을 찾지 못했다")
        appearanceTab.tap()

        let anchor = app.staticTexts["테마"]
        XCTAssertTrue(anchor.waitForExistence(timeout: 10), "테마 절이 보이지 않는다")
        attach(app.screenshot(), name: "theme-01-top")

        // 아래로 훑어 카드 전체를 남긴다 — AX3 에서는 세로로 길어져 한 장에 안 들어간다
        var previous = ""
        for step in 2...6 {
            app.swipeUp()
            attach(app.screenshot(), name: String(format: "theme-%02d-scroll", step))
            let signature = (app.staticTexts.allElementsBoundByIndex.last?.label ?? "")
                + app.descendants(matching: .any).count.description
            if signature == previous { break }
            previous = signature
        }

        // ★ 테마 전환 — 선택 표시가 옮겨 가는 것까지 본다
        for name in ["미드나이트", "퓨어 다크", "퓨어 라이트"] {
            let card = app.buttons.containing(.staticText, identifier: name).firstMatch
            if card.waitForExistence(timeout: 3), card.isHittable {
                card.tap()
                Thread.sleep(forTimeInterval: 1.0)
                attach(app.screenshot(), name: "theme-90-switched-\(name)")
                break
            }
        }
    }

    private func attach(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
