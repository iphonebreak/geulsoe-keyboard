import XCTest

/// **임시 조사 하네스 (TEMP-PROBE-TRACE) — 조사 끝나면 지운다.**
///
/// `probePasteboard()` 가 「다른 앱에서 붙여넣기 = 묻기」 상태에서 무엇을 보는지 **실측**한다.
/// 사용자 보고("복사했는데 칩이 안 뜬다")의 원인을 추측이 아니라 관측으로 확정하려는 것이다.
///
/// ## 벽을 넘는 한 줄 — 지구본은 **길게** 누른다
///
/// 검증자가 찾았다(`docs/release/verify-paste-chip.md` 1-1). 탭은 **다음 자판으로 순환**할 뿐이라
/// 글쇠를 지목하지 못한다. 길게 눌러야 목록이 뜨고 고를 수 있다. 내가 7회 막혔던 자리다.
///
/// ## 오염 0
///
/// **우리 컨테이너 앱을 띄우지 않는다** — 호스트는 사파리다. 익스텐션에는 Firebase 가 0바이트다.
final class PasteProbeTests: XCTestCase {

    private var host: XCUIApplication!
    private var keyboard: XCUIApplication!
    private var springboard: XCUIApplication!
    private var notes: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = true
        host = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func tearDownWithError() throws {
        let a = XCTAttachment(string: notes.joined(separator: "\n"))
        a.name = "probe-notes.txt"
        a.lifetime = .keepAlways
        add(a)
    }

    /// (가) 확인 창에서 **허용** — 검증자가 "시스템 붙여넣기가 수행된다"고 관측한 경로.
    func testAllow() throws { try run(answer: .allow) }
    /// (나) 확인 창에서 **거부**
    func testDeny() throws { try run(answer: .deny) }
    /// (다) 확인 창을 **그냥 둔다** — 아무것도 안 누르고 캡처만 남긴다
    func testIgnore() throws { try run(answer: .ignore) }

    /// ★ **이 조사의 핵심 산출물** — 같은 앱 경로와 앱 전환 경로를 **한 번의 실행 안에서** 재현해
    /// 트레이스가 어느 줄에서 갈리는지 본다.
    ///
    /// 사용자 보고: *"같은앱에서 복사하고 키보드를 내렸다가 다시 올리면 칩은 잘 뜬다"* /
    /// *"홈으로 이동해 다른 앱에서 복사하고 복귀하면 안 뜬다"*.
    func testSameAppVersusAppSwitch() throws {
        host.launch()
        dismissAllContinues()
        focusAddressField()
        dismissAllContinues()
        dismissAllContinues()
        bringUpGeulsoe()
        shot("A0-글쇠-올림")

        // ── 경로 A: 같은 앱 ─────────────────────────────────────────
        stamp("A 시작")
        UIPasteboard.general.string = "같은앱 경로 확인용 문장입니다"
        stamp("A 복사")
        lowerKeyboard()
        focusAddressField()
        Thread.sleep(forTimeInterval: 2.5)
        stamp("A 재등장 완료")
        shot("A1-같은앱-재등장")

        // ── 경로 B: 앱 전환 ─────────────────────────────────────────
        stamp("B 시작")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 2.0)
        UIPasteboard.general.string = "앱전환 경로 확인용 다른 문장입니다"
        stamp("B 복사(홈 화면에서)")
        host.activate()
        Thread.sleep(forTimeInterval: 2.0)
        focusAddressField()
        Thread.sleep(forTimeInterval: 3.0)
        stamp("B 재등장 완료")
        shot("B1-앱전환-복귀")
    }

    /// ★ **사장님 1순위 가설 재현** — 4자리 숫자를 복사하고 **입력란에 글자가 있는 상태**로
    /// 글쇠를 올리면, `make` 가 `.verificationCode` 를 주고 그 종류는 꼬리 게이트를 타므로
    /// 칩이 숨는다. 기대하는 트레이스: `decide kind=code tailEmpty=false chip=hidden`.
    ///
    /// 글자는 **시스템 자판으로** 미리 친다 — 글쇠로 치면 `pasteChipSuppressedByTyping` 이 켜져
    /// 무엇이 원인인지 갈리지 않는다.
    func testCodeKindWithNonEmptyField() throws {
        UIPasteboard.general.string = "1234"          // 4자리 숫자 = isCodeLike
        notes.append("클립보드 = 4자리 숫자")

        host.launch()
        dismissAllContinues()
        focusAddressField()
        dismissAllContinues()
        dismissAllContinues()

        // 시스템 자판으로 글자를 미리 넣는다 → textTail 이 비지 않는다
        host.typeText("abc")
        Thread.sleep(forTimeInterval: 1.0)
        notes.append("입력란에 abc 입력 (시스템 자판)")
        shot("C0-글자-넣은-뒤")

        bringUpGeulsoe()
        Thread.sleep(forTimeInterval: 2.0)
        shot("C1-글쇠-올린-뒤-칩이-있나")
        stamp("C 관측 시점")
    }

    /// ★ **유령 소비 재현 시도** — 칩을 띄운 뒤 **홈 제스처(화면 아래에서 위로)** 를 흉내 내
    /// `consume from=tap` 이 찍히는지 본다. 툴바는 자판 맨 위라 위로 쓸면 그 위를 지나간다.
    func testHomeSwipeConsumesChip() throws {
        UIPasteboard.general.string = "홈 제스처 실험용 스무 자 남짓 문장"
        host.launch()
        dismissAllContinues()
        focusAddressField()
        dismissAllContinues()
        dismissAllContinues()
        bringUpGeulsoe()
        Thread.sleep(forTimeInterval: 2.0)
        shot("H0-칩이-떠-있나")
        stamp("칩 확인 시점")

        // 홈 제스처 — 화면 맨 아래에서 위로 길게 쓴다. 자판 전체를 지나간다.
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.995))
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
        bottom.press(forDuration: 0.05, thenDragTo: top)
        Thread.sleep(forTimeInterval: 2.5)
        stamp("홈 제스처 완료")
        shot("H1-홈-제스처-뒤")

        // 복귀해서 다시 띄운다 — 칩이 남아 있나
        host.activate()
        Thread.sleep(forTimeInterval: 2.0)
        focusAddressField()
        Thread.sleep(forTimeInterval: 2.5)
        stamp("복귀 뒤")
        shot("H2-복귀-뒤-칩이-있나")
    }

    private func stamp(_ label: String) {
        notes.append(String(format: "%.3f  %@", Date().timeIntervalSince1970, label))
    }

    /// 글쇠를 올린다 — **지구본은 길게**(검증자 1-1).
    private func bringUpGeulsoe() {
        if keyboard.exists { return }
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.955))
            .press(forDuration: 0.9)
        Thread.sleep(forTimeInterval: 1.2)
        for app in [springboard, host] {
            guard let app else { continue }
            let item = app.staticTexts["글쇠"].firstMatch
            if item.waitForExistence(timeout: 2), item.isHittable {
                item.tap()
                notes.append("글쇠 선택")
                break
            }
        }
        Thread.sleep(forTimeInterval: 2.0)
        // 「묻기」면 확인 창이 뜬다 — 허용해 둔다(사용자 기기는 「허용」이라 창이 없다)
        let allow = springboard.buttons["붙여넣기 허용"].firstMatch
        if allow.waitForExistence(timeout: 4) { allow.tap(); notes.append("확인 창 허용") }
    }

    /// 키보드를 내린다 — 페이지 윗부분을 좌표로 탭해 첫 응답자를 내린다.
    private func lowerKeyboard() {
        host.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        Thread.sleep(forTimeInterval: 1.5)
    }

    private enum Answer { case allow, deny, ignore }

    private func run(answer: Answer) throws {
        UIPasteboard.general.string = "오늘 회의는 오후 세시로 옮겨졌습니다"
        notes.append("클립보드 설정 완료 (19자)")

        host.launch()
        dismissAllContinues()          // 사파리 첫 실행 안내
        focusAddressField()
        dismissAllContinues()          // 시스템 자판의 슬라이드 타이핑 소개
        dismissAllContinues()
        shot("00-자판-올린-직후")

        // ★ 지구본을 **길게** 누른다 — 탭이 아니다.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.955))
            .press(forDuration: 0.9)
        Thread.sleep(forTimeInterval: 1.2)
        shot("01-지구본-길게-누른-직후")

        // 목록에서 글쇠 고르기 — 요소로 먼저, 안 되면 좌표로
        var picked = false
        for app in [springboard, host] {
            guard let app else { continue }
            let item = app.staticTexts["글쇠"].firstMatch
            if item.waitForExistence(timeout: 2), item.isHittable {
                item.tap(); picked = true
                notes.append("목록에서 「글쇠」 요소로 선택")
                break
            }
        }
        if !picked {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.80)).tap()
            notes.append("목록에서 좌표로 선택 시도")
        }
        Thread.sleep(forTimeInterval: 2.0)
        shot("02-글쇠-전환-직후")

        // 확인 창 — 뜨는지부터 본다
        let allow = springboard.buttons["붙여넣기 허용"].firstMatch
        let deny = springboard.buttons["붙여넣기 허용 안 함"].firstMatch
        let appeared = allow.waitForExistence(timeout: 5)
        notes.append("붙여넣기 확인 창 떴나: \(appeared)")

        switch answer {
        case .allow where appeared:
            allow.tap(); notes.append("→ 「붙여넣기 허용」 탭")
        case .deny where appeared:
            if deny.exists { deny.tap(); notes.append("→ 「붙여넣기 허용 안 함」 탭") }
            else { notes.append("→ 거부 버튼을 못 찾았다") }
        case .ignore:
            notes.append("→ 아무것도 누르지 않는다")
        default:
            notes.append("→ 확인 창이 없어 아무 동작 없음")
        }
        Thread.sleep(forTimeInterval: 2.0)
        shot("03-답한-뒤")

        // 주소창에 글자가 들어갔는가 — 검증자의 "시스템 붙여넣기 수행" 관측을 가른다
        // **자리 표시자("검색 또는 웹사이트 이름 입력", 16자)가 value 로 온다** — 길이만 보면 속는다.
        // 붙여넣은 문자열(19자)이 들어갔는지는 **그 문자열이 실제로 있는지**로 가른다.
        let fieldValue = host.textFields.firstMatch.value as? String ?? "(없음)"
        let pasted = fieldValue.contains("오늘 회의는")
        notes.append("★ 주소창에 붙여넣기 흔적: \(pasted) (값 길이 \(fieldValue.count)자) "
                     + "— true 면 「허용」 탭이 시스템 붙여넣기를 수행한 것이다")
        shot("04-주소창-상태")
    }

    // MARK: - 도구

    private func focusAddressField() {
        let any = host.textFields.firstMatch
        if any.waitForExistence(timeout: 8) { any.tap(); Thread.sleep(forTimeInterval: 1.5) }
        else { notes.append("주소창을 찾지 못했다") }
    }

    /// 「계속」이 **여럿** 있다 — 사파리 첫 실행 안내와 시스템 자판 소개가 겹쳐 뜬다.
    /// 하나만 닫고 돌아오면 남은 것이 자판을 덮어 지구본을 못 누른다(2026-09-15 실측).
    private func dismissAllContinues() {
        for _ in 0..<4 {
            var tapped = false
            // **우리 익스텐션은 여기서 묻지 않는다** — 아직 안 떴을 때 질의하면
            // `kAXErrorServerNotFound` 로 테스트가 죽는다(2026-09-15 실측).
            for app in [host, springboard] {
                guard let app else { continue }
                for label in ["계속", "Continue"] {
                    let b = app.buttons[label].firstMatch
                    if b.exists, b.isHittable {
                        b.tap(); tapped = true
                        notes.append("「\(label)」 닫음")
                        Thread.sleep(forTimeInterval: 0.8)
                        break
                    }
                }
                if tapped { break }
            }
            if !tapped { return }
        }
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
