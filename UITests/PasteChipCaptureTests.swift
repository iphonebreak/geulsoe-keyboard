import XCTest

/// 붙여넣기 칩 캡처 하네스 (2026-09-15).
///
/// ## 왜 사파리를 호스트로 쓰는가 — 방출 0
///
/// `LandscapeKeyboardMetricsTests` 와 같은 이유다. **우리 컨테이너 앱을 띄우지 않는다** —
/// 띄우면 `FirebaseApp.configure()` 가 돌아 실제 통계가 나간다. 익스텐션에는 Firebase 가
/// **0바이트**이므로 시스템 앱 입력란에 글쇠를 띄우면 방출 0으로 관측할 수 있다.
/// → 이 파일은 인자 없는 `XCUIApplication()` 을 **절대 쓰지 않는다.** 그것이 우리 앱을 띄운다.
///
/// ## 클립보드는 러너가 직접 채운다
///
/// `simctl pbcopy` 를 쓰면 시나리오마다 테스트를 다시 돌려야 한다. 러너 프로세스에서
/// `UIPasteboard.general` 을 쓰면 **한 번의 실행 안에서** 복사 → 칩 확인 → ✕ → 재등장 →
/// 새로 복사 → 다시 뜸 까지 이어서 찍을 수 있다. 여기서 넣는 문자열은 전부 **상수**다
/// (사용자 입력이 아니다 — `.claude/rules/security.md`).
///
/// ## 판정은 사람이 첨부를 본다
///
/// 서드파티 자판은 호스트의 접근성 트리에 들어오지 않아 요소 단언이 제한적이다
/// (`docs/simulator-input-verification.md`). 그래서 이 하네스는 **실패시키지 않고 관측만** 한다 —
/// 자판이 안 뜨면 그 사실을 첨부에 남기고 끝낸다. 캡처를 보고 사람이 판정한다.
///
/// ## ★ 2026-09-15 현재 — **여기까지는 되고 그다음이 안 된다**
///
/// 되는 것: 사파리 띄우기 · 첫 실행 안내 닫기 · 주소창 포커스 · 클립보드 채우기 ·
/// **좌표 탭이 자판에 실제로 닿는 것**(진단 캡처 `00a` 에서 "q" 가 입력됐다) ·
/// 붙여넣기 확인 창 수락 · 스크린숏 첨부.
///
/// **안 되는 것: 글쇠로 전환.** `KeyboardEnableSetupTests` 로 자판 등록과 전체 접근까지 켠 뒤에도
/// (`AppleKeyboards` 에 `com.charging.tadak.keyboard` 가 들어가 있고 전체 접근 스위치 값이 1)
/// 지구본을 좌표로 7회 쳐도 시스템 자판만 돌고 우리 익스텐션 프로세스가 **한 번도 뜨지 않는다**
/// (`log show --predicate 'process CONTAINS "Tadak"'` 에 러너만 보인다).
/// 원인은 확인하지 못했다. **고칠 사람을 위해 남긴다** — 이 지점만 뚫리면 나머지는 그대로 돈다.
final class PasteChipCaptureTests: XCTestCase {

    private var host: XCUIApplication!
    private var keyboard: XCUIApplication!
    private var springboard: XCUIApplication!
    private var notes: [String] = []

    private static let shortText = "맘에 드십니까 오늘 저녁 7시 강남역"
    private static let longText =
        "이 문장은 칩 한 줄에 절대 들어가지 않을 만큼 길게 만든 것입니다. "
        + "말줄임표가 붙는지, 그리고 탭하면 잘린 미리보기가 아니라 원문 전체가 들어가는지를 봅니다. "
        + "그래서 뒤쪽에 이렇게 계속 글자를 더 붙여 둡니다."
    private static let codeSMS = "[Web발신]\n[국민은행] 인증번호 [483920] 를 입력해주세요"
    private static let secondText = "새로 복사한 다른 내용입니다"

    override func setUpWithError() throws {
        continueAfterFailure = true
        host = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func tearDownWithError() throws {
        let text = notes.joined(separator: "\n")
        let attachment = XCTAttachment(string: text)
        attachment.name = "notes.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCapturePasteChip() throws {
        copy(Self.shortText, note: "① 일반 텍스트 복사")
        host.launch()
        dismissFirstRunDialogIfPresent()
        focusAddressField()
        // 시스템 자판의 첫 실행 안내(슬라이드 타이핑 소개)가 자판 위를 덮는다 — 여러 번 나올 수 있다
        dismissFirstRunDialogIfPresent()
        dismissFirstRunDialogIfPresent()
        allowPasteIfAsked()
        // 진단 — 좌표 탭이 자판에 닿는지부터 본다(ㅂ 자리를 친다). 닿으면 주소창에 글자가 들어간다.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.058, dy: 0.7)).tap()
        Thread.sleep(forTimeInterval: 0.8)
        shot("00a-좌표탭-진단")
        try bringUpGeulsoe()
        shot("01-일반-텍스트-칩")

        copy(Self.longText, note: "② 긴 텍스트 복사")
        reopenKeyboard()
        allowPasteIfAsked()
        shot("02-긴-텍스트-말줄임")

        copy(Self.codeSMS, note: "③ 인증번호 문자 복사")
        reopenKeyboard()
        allowPasteIfAsked()
        shot("03-인증번호-칩")

        // ✕ — 익스텐션 요소로 잡는다. 접근성 라벨은 `KeyboardRootView` 의 닫기 버튼.
        let close = keyboard.buttons["후보 닫기"]
        if close.waitForExistence(timeout: 5) {
            close.tap()
            notes.append("④ ✕ 탭 — 요소로 성공")
        } else {
            // 툴바 오른쪽 끝 ✕ — 자판 맨 위 줄이다. 요소로 못 잡으면 좌표로 친다.
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.717)).tap()
            notes.append("④ ✕ 좌표 탭 (요소로는 못 잡았다)")
        }
        Thread.sleep(forTimeInterval: 1.0)
        shot("04-X-누른-직후")

        reopenKeyboard()
        allowPasteIfAsked()
        shot("05-X-뒤-재등장-칩없음")

        copy(Self.secondText, note: "⑤ 새로 복사")
        reopenKeyboard()
        allowPasteIfAsked()
        shot("06-새로-복사하면-다시-뜬다")
    }

    // MARK: - 단계

    private func copy(_ text: String, note: String) {
        UIPasteboard.general.string = text
        notes.append("\(note): \(text.count)자")
    }

    /// 자판을 내렸다 다시 올린다 — `viewWillAppear` 가 다시 돌아야 억제·재등장을 볼 수 있다.
    ///
    /// 사파리 버전마다 「취소」 버튼이 있기도 없기도 해서 **화면 윗부분을 좌표로 탭**해
    /// 첫 응답자를 내린다. 요소 이름에 기대지 않는다.
    private func reopenKeyboard() {
        host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        Thread.sleep(forTimeInterval: 1.0)
        focusAddressField()
        Thread.sleep(forTimeInterval: 1.0)
    }

    private func focusAddressField() {
        for id in ["TabBarItemTitle", "URL", "Address"] {
            let field = host.textFields[id]
            if field.waitForExistence(timeout: 5) {
                field.tap()
                return
            }
        }
        let any = host.textFields.firstMatch
        if any.waitForExistence(timeout: 5) { any.tap() }
        else { notes.append("주소창을 찾지 못했다") }
    }

    /// 사파리 첫 실행 안내와 **시스템 자판의 슬라이드 타이핑 소개**를 닫는다.
    /// 둘 다 「계속」이고, 자판 쪽 것은 호스트가 아니라 **자판 프로세스**에 있다.
    private func dismissFirstRunDialogIfPresent() {
        for app in [host, springboard, keyboard, XCUIApplication(bundleIdentifier: "com.apple.keyboard")] {
            guard let app else { continue }
            for label in ["계속", "Continue"] {
                let button = app.buttons[label]
                if button.waitForExistence(timeout: 2), button.isHittable {
                    button.tap()
                    notes.append("첫 실행 안내 「\(label)」 닫음 (\(app.description.prefix(40)))")
                    return
                }
            }
        }
    }

    /// iOS 「다른 앱에서 붙여넣기 = 묻기」(기본값) 확인 창 — 뜨면 허용한다.
    /// 이 창이 뜬다는 사실 자체가 `settings-path-truth.md` 2-2 의 관측과 같다.
    private func allowPasteIfAsked() {
        for label in ["붙여넣기 허용", "Allow Paste"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 4) {
                button.tap()
                notes.append("붙여넣기 확인 창 → 「\(label)」 탭")
                return
            }
        }
    }

    /// 글쇠가 올라오게 한다. 이미 마지막 사용 자판이면 그대로, 아니면 지구본을 돈다.
    private func bringUpGeulsoe(maxHops: Int = 6) throws {
        // 시스템 자판이 먼저 뜨는 것이 보통이다 — **지구본을 돌아** 글쇠까지 간다.
        // 지구본은 그때그때 떠 있는 자판 프로세스에 있으므로 호스트의 `keyboards` 로 찾는다.
        for hop in 0...maxHops {
            if keyboard.waitForExistence(timeout: hop == 0 ? 6 : 4) {
                notes.append("글쇠 익스텐션을 찾았다 (지구본 \(hop)회)")
                return
            }
            // 지구본은 그때 떠 있는 자판 프로세스에 있어 요소로 잘 안 잡힌다
            // (시스템 자판은 호스트의 `keyboards` 로도 iOS 26.5 에서 안 잡혔다 — 실측).
            // **좌표로 친다.** 지구본은 자판 왼쪽 아래 끝 고정 자리다.
            var tapped = false
            for candidate in [host.keyboards.buttons["다음 키보드"].firstMatch,
                              host.keyboards.buttons["Next keyboard"].firstMatch] where candidate.exists {
                candidate.tap()
                tapped = true
                break
            }
            if !tapped {
                // **스프링보드 좌표를 쓴다.** 호스트(사파리) 좌표로 치면 자판 영역에 닿지 않는다 —
                // 자판은 다른 프로세스가 그 위에 그리고, 호스트 프레임이 그 영역을 포함하지 않는다
                // (실측 2026-09-15: 사파리 좌표로 7번 쳐도 자판이 하나도 안 바뀌었다).
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.955)).tap()
                notes.append("지구본 좌표 탭 (\(hop + 1)회)")
            }
            Thread.sleep(forTimeInterval: 1.5)
        }
        notes.append("★ 글쇠 익스텐션 요소를 찾지 못했다 — 시뮬레이터에 자판이 켜지지 않았다")
        shot("00-글쇠-없음")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
