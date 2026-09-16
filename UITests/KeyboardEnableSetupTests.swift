import XCTest

/// **시뮬레이터에 글쇠를 켜 두는 준비용 하네스** (2026-09-15).
///
/// 캡처 하네스(`PasteChipCaptureTests`)를 돌리려면 시뮬레이터에 글쇠가 **자판으로 켜져 있고
/// 전체 접근까지 허용**돼 있어야 한다. 그런데 `simctl` 은 탭을 못 하고,
/// `defaults write .GlobalPreferences AppleKeyboards` 로 목록에 문자열을 넣어 봐도
/// **시스템이 인정하지 않는다**(실측 2026-09-15 — 목록에는 들어가지만 지구본을 돌아도 나오지 않는다).
///
/// 그래서 **설정 앱을 요소로 걸어서** 켠다. 검증자가 `settings-path-truth.md` 에서 손으로 걸은
/// 바로 그 경로를 자동화한 것이다:
/// `설정 > 일반 > 키보드 > 키보드 > 새로운 키보드 추가… > 글쇠` → 다시 `글쇠` 행 → `전체 접근 허용` → `허용`
///
/// **우리 앱을 띄우지 않는다** — 설정 앱만 만진다(방출 0).
/// 한 번 켜 두면 그 시뮬레이터에서 계속 유지되므로 캡처 때마다 돌릴 필요는 없다.
final class KeyboardEnableSetupTests: XCTestCase {

    private var settings: XCUIApplication!
    private var springboard: XCUIApplication!
    private var notes: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "setup-notes.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEnableGeulsoeKeyboard() throws {
        settings.launch()
        tap(["일반", "General"], in: settings.cells, label: "일반")
        tap(["키보드", "Keyboards", "Keyboard"], in: settings.cells, label: "키보드(1)")
        tap(["키보드", "Keyboards"], in: settings.cells, label: "키보드(2)")
        shot("s1-키보드-목록")

        if settings.cells.staticTexts["글쇠"].waitForExistence(timeout: 3) {
            notes.append("글쇠가 이미 켜져 있다")
        } else {
            tap(["새로운 키보드 추가…", "새로운 키보드 추가", "Add New Keyboard…", "Add New Keyboard"],
                in: settings.cells, label: "새 키보드 추가")
            shot("s2-추가할-키보드-목록")
            tap(["글쇠"], in: settings.cells, label: "글쇠 선택")
            notes.append("글쇠를 자판 목록에 추가했다")
        }
        shot("s3-키보드-추가-후")

        // 전체 접근 — 글쇠 행을 눌러 들어가면 스위치가 있다
        tap(["글쇠"], in: settings.cells, label: "글쇠 행")
        let fullAccess = settings.switches.firstMatch
        if fullAccess.waitForExistence(timeout: 5) {
            if fullAccess.value as? String == "0" {
                // **요소 가운데를 누르면 행이 눌리고 스위치는 안 바뀐다**(실측 2026-09-15).
                // 스위치 손잡이가 있는 오른쪽 끝을 좌표로 친다.
                fullAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
                Thread.sleep(forTimeInterval: 1.5)
                notes.append("전체 접근 스위치 탭 — 직후 값: \(fullAccess.value as? String ?? "?")")
                shot("s3b-스위치-탭-직후")
                // ★ 스위치를 켜면 iOS 확인 대화상자가 뜬다 — 「허용」을 눌러야 실제로 켜진다.
                // **대화상자는 `alerts` 로 잡아야 한다.** 그냥 `buttons` 로 찾으면 못 잡고,
                // 그러면 스위치가 **도로 꺼진다** — 2026-09-15 에 이 하네스가 실제로 그렇게 실패했고
                // 그게 검증자가 `settings-path-truth.md` 2-1 에서 경고한 바로 그 함정이다.
                var allowed = false
                for candidate in [settings.alerts, springboard.alerts] {
                    for label in ["허용", "Allow"] {
                        let button = candidate.buttons[label].firstMatch
                        if button.waitForExistence(timeout: 4) {
                            button.tap()
                            notes.append("확인 대화상자 「\(label)」 탭 — 이 한 번을 놓치면 도로 꺼진다")
                            allowed = true
                            break
                        }
                    }
                    if allowed { break }
                }
                if !allowed { notes.append("★ 확인 대화상자를 잡지 못했다 — 전체 접근이 도로 꺼졌을 것이다") }
                // 결과를 다시 읽어 실제로 켜졌는지 확인한다
                notes.append("전체 접근 스위치 최종 값: \(settings.switches.firstMatch.value as? String ?? "?")")
            } else {
                notes.append("전체 접근이 이미 켜져 있다")
            }
        } else {
            notes.append("★ 전체 접근 스위치를 찾지 못했다")
        }
        shot("s4-전체접근-후")
    }

    // MARK: - 도구

    private func tap(_ labels: [String], in query: XCUIElementQuery, label: String) {
        for text in labels {
            let cell = query.staticTexts[text].firstMatch
            if cell.waitForExistence(timeout: 6) {
                cell.tap()
                notes.append("\(label) → 「\(text)」 탭")
                return
            }
            let button = settings.buttons[text].firstMatch
            if button.exists {
                button.tap()
                notes.append("\(label) → 버튼 「\(text)」 탭")
                return
            }
        }
        notes.append("★ \(label): \(labels) 중 어느 것도 찾지 못했다")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
