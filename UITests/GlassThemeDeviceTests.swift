import XCTest

/// 실기 검증 하네스 — 키보드 등장·자판 전환·스페이스 반응 (2026-09-07, 리퀴드 글래스 검증용으로 만들어 범용화).
///
/// agent-device 러너가 실기에서 데몬으로 되돌아오는 접속에 실패해(터널 TCP) Xcode 자체 XCUITest로 대체한다.
/// 컨테이너 앱을 띄워 설정에서 테마·모드를 고르고, 입력 테스트란에 키보드를 올려 스크린숏(등장 직후·안정 후·
/// 자판 전환 직후)과 스페이스 반응 시간을 계측해 첨부(XCTAttachment)로 남긴다. 판정은 사람이 첨부를 본다.
///
/// 키 좌표는 배열 데이터(하단 행 폭 비율)에서 계산한다 — 익스텐션 요소의 frame은 XCUITest에 로컬 좌표로 보고돼
/// element.tap()이 엉뚱한 곳을 누른다 (docs/simulator-input-verification.md).
final class GlassThemeDeviceTests: XCTestCase {

    private var app: XCUIApplication!
    private var metrics: [String: Any] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
        // 기기 접근성 설정 — 투명도 줄이기가 켜져 있으면 iOS가 유리·블러를 불투명하게 그린다 (진단용)
        metrics["device.reduceTransparency"] = UIAccessibility.isReduceTransparencyEnabled
        metrics["device.reduceMotion"] = UIAccessibility.isReduceMotionEnabled
        metrics["device.darkerSystemColors"] = UIAccessibility.isDarkerSystemColorsEnabled
        metrics["device.systemVersion"] = UIDevice.current.systemVersion
    }

    override func tearDownWithError() throws {
        if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            let attachment = XCTAttachment(string: text)
            attachment.name = "metrics.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    // MARK: - 시나리오

    /// 테마 2종 × 모드 — 등장·자판 전환 스크린숏과 스페이스 반응 계측 (테마 간 차이 비교용)
    func testThemesDarkAndLight() throws {
        try selectTheme("퓨어 다크", mode: "다크")
        try runKeyboardScenario(tag: "puredark-다크")
        try selectTheme("시스템", mode: "라이트")
        try runKeyboardScenario(tag: "system-라이트")
    }

    /// 검증 뒤 사용자 설정 복원 — 퓨어 다크 + 모드 시스템. `-only-testing:TadakUITests/GlassThemeDeviceTests/testRestoreUserTheme`
    func testRestoreUserTheme() throws {
        try selectTheme("퓨어 다크", mode: "시스템")
    }

    /// 길게 눌러 기호 입력 (PDR long-press-symbols, 2026-09-08) — 영어 자판에서 `t`(1행 5번째)를 0.7초 누르면 `#`
    /// (기호 자판 2행 5번째), 짧게 누르면 `t`. 힌트가 그려진 자판(영어·한글) 스크린숏을 첨부한다.
    /// `-only-testing:TadakUITests/GlassThemeDeviceTests/testLongPressSymbols`
    func testLongPressSymbols() throws {
        tap(at: CGPoint(x: 73, y: 800))    // 자판 탭 — 앱이 다른 탭에서 시작할 수 있다 (좌표는 selectTheme와 동일)
        Thread.sleep(forTimeInterval: 0.8)
        shot("longpress-00-start")
        dismissKeyboardIfShown()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "입력 테스트란")
        clearField()
        field.tap()
        Thread.sleep(forTimeInterval: 1.0)
        try ensureTadakKeyboard(tag: "longpress")
        tapBottomKey(.language)   // 영어 자판 — 활성 한글 배열과 무관하게 1행이 qwertyuiop
        Thread.sleep(forTimeInterval: 0.6)
        shot("longpress-1-english-hints")
        clearField()
        let tKey = characterKeyCenter(row: 0, index: 4, count: 10)
        press(at: tKey, seconds: 0.7)
        Thread.sleep(forTimeInterval: 0.6)
        shot("longpress-2-after-long")
        let afterLong = fieldText()
        metrics["longpress.afterLong"] = afterLong
        XCTAssertEqual(afterLong, "#", "t 길게 → #")
        tap(at: tKey)
        Thread.sleep(forTimeInterval: 0.6)
        let afterTap = fieldText()
        metrics["longpress.afterTap"] = afterTap
        XCTAssertEqual(afterTap.lowercased(), "#t", "t 짧게 → t (자동 대문자는 별개)")
        shot("longpress-3-after-tap")
        tapBottomKey(.language)   // 한글 복귀
        Thread.sleep(forTimeInterval: 0.6)
        shot("longpress-4-hangul-hints")
    }

    /// 채움글 안내 카드 — 툴바 탭 > 채움글로 들어가 루프 중 스크린숏 4장 (카드 높이·카메라 프레이밍 확인, 2026-09-08 높이 축소).
    /// `-only-testing:TadakUITests/GlassThemeDeviceTests/testSnippetIntroCard`
    func testSnippetIntroCard() throws {
        tap(at: CGPoint(x: 155, y: 800))   // 툴바 탭
        Thread.sleep(forTimeInterval: 0.8)
        shot("intro-0-toolbar-tab")
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "채움글")).firstMatch
        if row.waitForExistence(timeout: 2), row.isHittable {
            row.tap()
            metrics["intro.row"] = "label"
        } else {
            tap(at: CGPoint(x: 196, y: 690))
            metrics["intro.row"] = "fallback"
        }
        for (delay, name) in [(1.6, "intro-1-typing"), (2.4, "intro-2-typed"), (2.0, "intro-3-chip"), (1.8, "intro-4-body")] {
            Thread.sleep(forTimeInterval: delay)
            shot(name)
        }
    }

    // MARK: - 단계

    /// 설정 화면 탭에서 모드·테마를 고른다. **좌표 탭** — iOS 26.1 실기에서 TabView 전환 뒤에도 접근성 계층이
    /// 이전 탭('자판') 내용을 보고해 테마 행을 요소로 찾을 수 없었다(화면은 이미 전환됨). 좌표는 녹화 프레임 실측
    /// (iPhone 15 Pro 393×852): 모드 세그먼트 y 236 (시스템 90 / 라이트 196 / 다크 306), 테마 행 x 150,
    /// y 390·460·531·601 (시스템·퓨어 라이트·퓨어 다크·미드나이트), 탭 막대 y 800 (자판 73 / 화면 237).
    private func selectTheme(_ name: String, mode: String) throws {
        dismissKeyboardIfShown()
        tap(at: CGPoint(x: 237, y: 800))   // 화면 탭
        Thread.sleep(forTimeInterval: 0.8)
        let modeX: [String: CGFloat] = ["시스템": 90, "라이트": 196, "다크": 306]
        tap(at: CGPoint(x: modeX[mode] ?? 90, y: 236))
        Thread.sleep(forTimeInterval: 0.4)
        let themeY: [String: CGFloat] = ["시스템": 390, "퓨어 라이트": 460, "퓨어 다크": 531, "미드나이트": 601]
        guard let y = themeY[name] else { XCTFail("알 수 없는 테마 \(name)"); return }
        tap(at: CGPoint(x: 150, y: y))
        Thread.sleep(forTimeInterval: 0.4)
        shot("theme-\(name)-\(mode)")
        tap(at: CGPoint(x: 73, y: 800))    // 자판 탭
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func runKeyboardScenario(tag: String, screenshots: Bool = true) throws {
        dismissKeyboardIfShown()
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "입력 테스트란")
        clearField()

        // 등장 — 탭 직후와 1초 뒤
        field.tap()
        if screenshots { shot("\(tag)-1-appear-immediate") }
        Thread.sleep(forTimeInterval: 1.0)
        if screenshots { shot("\(tag)-2-appear-settled") }

        try ensureTadakKeyboard(tag: tag)

        // 자판 전환 직후 프레임 — 한영(영어) → 123 → ABC(한글로 복귀 = 들어오기 전 모드) → 한영(한글)
        if screenshots {
            tapBottomKey(.language); shot("\(tag)-3-english-immediate")
            Thread.sleep(forTimeInterval: 0.8); shot("\(tag)-4-english-settled")
            tapBottomKey(.symbols); shot("\(tag)-5-symbols-immediate")
            Thread.sleep(forTimeInterval: 0.8); shot("\(tag)-6-symbols-settled")
            tapBottomKey(.symbols); shot("\(tag)-7-back-immediate")
            Thread.sleep(forTimeInterval: 0.8)
            tapBottomKey(.language)  // 한글로
            Thread.sleep(forTimeInterval: 0.5)
        }

        // 스페이스 반응 — 10회 탭, 각 탭이 텍스트에 반영되기까지의 지연
        clearField()
        var latencies: [Double] = []
        var before = fieldText().count
        for _ in 0..<10 {
            let start = Date()
            tapBottomKey(.space)
            var applied = false
            while Date().timeIntervalSince(start) < 2.0 {
                let now = fieldText().count
                if now > before { before = now; applied = true; break }
                Thread.sleep(forTimeInterval: 0.02)
            }
            latencies.append(applied ? Date().timeIntervalSince(start) * 1000 : -1)
            Thread.sleep(forTimeInterval: 0.15)
        }
        let finalCount = fieldText().count
        // 빠른 연속 탭 — 20회를 60ms 간격으로 넣고 누락을 본다 (반응 지연이 크면 이벤트가 밀리거나 빠진다)
        clearField()
        let burstStart = Date()
        for _ in 0..<20 {
            tapBottomKey(.space)
            Thread.sleep(forTimeInterval: 0.06)
        }
        let burstSeconds = Date().timeIntervalSince(burstStart)
        Thread.sleep(forTimeInterval: 1.5)
        let burstCount = fieldText().count
        metrics["\(tag).burst20.applied"] = burstCount
        metrics["\(tag).burst20.seconds"] = Int((burstSeconds * 1000).rounded())
        let ok = latencies.filter { $0 >= 0 }
        metrics["\(tag).spaceLatencyMs"] = latencies.map { Int($0.rounded()) }
        metrics["\(tag).spaceApplied"] = "\(ok.count)/10"
        metrics["\(tag).spaceAvgMs"] = ok.isEmpty ? -1 : Int((ok.reduce(0, +) / Double(ok.count)).rounded())
        metrics["\(tag).spaceMaxMs"] = ok.isEmpty ? -1 : Int(ok.max()!.rounded())
        metrics["\(tag).finalSpaceCount"] = finalCount
        if screenshots { shot("\(tag)-8-after-spaces") }
        XCTAssertEqual(ok.count, 10, "\(tag): 스페이스 10회 중 \(ok.count)회만 반영")
    }

    // MARK: - 키보드 좌표 (배열 데이터 기준)

    private enum BottomKey { case symbols, language, space, punct, ret }

    /// 하단 행 [123 1.2][한영 1.2][스페이스 4.4][. 1.2][⏎ 1.6] / 9.6 (지구본 불필요 기기). 수평 패딩 3, 키 간격 5.
    private func tapBottomKey(_ key: BottomKey) {
        let frame = keyboardFrame()
        let unit = (frame.width - 6 - 4 * 5) / 9.6
        let centers: [BottomKey: CGFloat] = [
            .symbols: 3 + 0.6 * unit,
            .language: 3 + 1.8 * unit + 5,
            .space: 3 + 4.6 * unit + 10,
            .punct: 3 + 7.4 * unit + 15,
            .ret: 3 + 8.8 * unit + 20
        ]
        // 툴바 46 + 4행(간격 7) 216 → 마지막 행 중심 = 상단 + 46 + 216 - 48.75/2
        let point = CGPoint(x: frame.minX + centers[key]!, y: frame.minY + 46 + 216 - 24.4)
        tap(at: point)
    }

    /// 키보드 프레임 — 익스텐션 컨테이너의 frame이 화면 좌표로 그럴듯하면 쓰고, 아니면 화면 아래에서 계산한다
    /// (시스템 하단 바 71 + 우리 키보드 266).
    private func keyboardFrame() -> CGRect {
        let screen = XCUIScreen.main.screenshot().image.size  // 포인트 단위가 아니라 픽셀일 수 있어 window 기준으로 재계산
        let window = app.windows.firstMatch.frame
        let height: CGFloat = 266
        let top = window.maxY - 71 - height
        _ = screen
        return CGRect(x: window.minX, y: top, width: window.width, height: height)
    }

    private func tap(at point: CGPoint) {
        let window = app.windows.firstMatch
        let normalized = CGVector(dx: point.x / window.frame.width, dy: point.y / window.frame.height)
        window.coordinate(withNormalizedOffset: normalized).tap()
    }

    /// 정지 길게 누르기 — 터치다운이 즉시 전달되므로 KeyCapView의 450ms 무장 타이머가 돈다
    private func press(at point: CGPoint, seconds: TimeInterval) {
        let window = app.windows.firstMatch
        let normalized = CGVector(dx: point.x / window.frame.width, dy: point.y / window.frame.height)
        window.coordinate(withNormalizedOffset: normalized).press(forDuration: seconds)
    }

    /// 문자 행의 키 중심 — 행이 균등 폭 키 `count`개로만 이루어진 경우(두벌식·쿼티 1행 10 / 2행 9).
    /// 수평 패딩 3, 키 간격 5, 툴바 46, 행 높이 48.75, 행 간격 7 (KeyboardLayoutView 미러).
    private func characterKeyCenter(row: Int, index: Int, count: Int) -> CGPoint {
        let frame = keyboardFrame()
        let keyWidth = (frame.width - 6 - CGFloat(count - 1) * 5) / CGFloat(count)
        let x = frame.minX + 3 + CGFloat(index) * (keyWidth + 5) + keyWidth / 2
        let y = frame.minY + 46 + CGFloat(row) * (48.75 + 7) + 48.75 / 2
        return CGPoint(x: x, y: y)
    }

    /// 시스템 하단 바 지구본을 길게 눌러 메뉴에서 "글쇠"를 고른다 — 항상 수행한다 (접근성 계층이 stale해 현재
    /// 키보드를 판별할 수 없다). 메뉴 항목은 **라벨로 찾는다** — 항목 순서가 기기의 등록 키보드 목록에 따라 달라
    /// 고정 좌표(6개 기준 585)가 2026-09-08엔 English (US)를 골랐다(7개 등록, 글쇠 = y 640). 못 찾으면 640으로 폴백.
    private func ensureTadakKeyboard(tag: String) throws {
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 41 / window.frame.width,
                                                          dy: 812 / window.frame.height)).press(forDuration: 1.0)
        Thread.sleep(forTimeInterval: 0.7)
        shot("\(tag)-0-keyboard-menu")
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "글쇠")).firstMatch
        if item.waitForExistence(timeout: 1.5), item.isHittable {
            item.tap()
            metrics["\(tag).keyboardMenu"] = "label"
        } else {
            tap(at: CGPoint(x: 60, y: 640))
            metrics["\(tag).keyboardMenu"] = "fallback-640"
        }
        Thread.sleep(forTimeInterval: 1.2)
        shot("\(tag)-0b-after-switch")
    }

    private func tadakKeyVisible() -> Bool {
        let predicate = NSPredicate(format: "label == %@ OR label == %@", "한영 전환", "스페이스")
        return app.descendants(matching: .any).matching(predicate).firstMatch.exists
    }

    private func dismissKeyboardIfShown() {
        // 글쇠: 툴바 도구 "키보드 내리기". 시스템 키보드: Form의 interactive 스크롤로 내린다. 둘 다 안 되면 그대로.
        let dismiss = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "키보드 내리기")).firstMatch
        if dismiss.exists {
            let window = app.windows.firstMatch
            // 익스텐션 요소 frame은 로컬 좌표라 element.tap()이 어긋날 수 있다 — 툴바 첫 도구 위치를 좌표로 탭
            let kb = keyboardFrame()
            window.coordinate(withNormalizedOffset: CGVector(dx: (kb.minX + 40) / window.frame.width,
                                                             dy: (kb.minY + 23) / window.frame.height)).tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
        if app.keyboards.count > 0 || app.textFields.firstMatch.value(forKey: "hasKeyboardFocus") as? Bool == true {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    private func clearField() {
        let clear = app.buttons["지우기"]
        if clear.exists { clear.tap(); Thread.sleep(forTimeInterval: 0.3) }
    }

    private func fieldText() -> String {
        let value = app.textFields.firstMatch.value as? String ?? ""
        return value == "여기에 입력해 키보드를 확인하세요" ? "" : value
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
