import XCTest
import TadakDomain

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

    // MARK: - ★ 형광펜 8조합 (검증자 차단 #6, 2026-09-22)

    /// 테마 **4종 × 라이트/다크 = 8조합**에서 구절 패널을 열어 **형광펜이 칠해진 화면**을 남긴다.
    /// `-only-testing:TadakUITests/GlassThemeDeviceTests/testHighlightAcrossThemes`
    ///
    /// ## ★ 왜 App Group plist를 밖에서 못 바꾸나 — 검증자가 두 번 실패했다
    ///
    /// 테마를 밖에서(`defaults write`) 바꾸면 **앱이 뜨면서 자기 상태를 App Group에 다시 저장해
    /// 덮어쓴다.** Darwin 알림도 안 간다. 그래서 **앱 화면을 눌러 앱이 저장하게** 해야 한다 —
    /// 그것이 `selectTheme`이고, 이 시험은 그 헬퍼를 8번 돈다.
    ///
    /// ## 무엇을 남기나
    ///
    /// 조합마다 스크린숏 셋이다 — 테마 고른 직후(`selectTheme`이 찍는다) ·
    /// 배지가 뜬 툴바 · **패널(형광펜)**. 이름이 `hl-<테마>-<모드>-…`라 조합이 파일명으로 갈린다.
    ///
    /// ★ **판정은 하지 않는다.** 형광펜 대비는 픽셀을 재야 하고 그것은 검증자 몫이다.
    /// 여기서 단언하는 것은 **그 화면에 실제로 도달했는가**뿐이다 — 도달 못 한 조합이 있으면
    /// 그 조합만 실패해서 어느 테마가 문제인지 바로 갈린다.
    ///
    /// ## 선행 조건
    ///
    /// **채움글 > 성경 > 「단어로 구절 찾기」가 켜져 있어야 한다**(기본 꺼짐).
    /// 안 켜면 첫 조합에서 배지 단언이 실패하고 나머지도 같은 이유로 실패한다.
    ///
    /// ## 보안
    ///
    /// `metrics`에는 **테마 이름과 도달 여부만** 넣는다 — 입력란 내용·문서 문맥은 넣지 않는다.
    func testHighlightAcrossThemes() throws {
        let themes = ["시스템", "퓨어 라이트", "퓨어 다크", "미드나이트"]
        let modes = ["라이트", "다크"]
        var reached: [String] = []

        var themeApplied: [String] = []

        for theme in themes {
            for mode in modes {
                let tag = "hl-\(theme)-\(mode)"
                // ★ **고른 테마가 실제로 선택됐는지**까지 확인한다 — A가 바로 그 문제였다
                //   (캡처 8장이 실제로는 4상태였고 어두운 두 팔레트가 0픽셀이었다).
                let applied = selectThemeVerified(theme, mode: mode)
                if applied { themeApplied.append(tag) }
                let opened = try captureHighlightPanel(tag: tag)
                metrics["\(tag).panelOpened"] = opened
                if opened && applied { reached.append(tag) }
                // 다음 조합을 깨끗한 상태에서 시작한다
                closePanelIfOpen()
                dismissKeyboardIfShown()
            }
        }

        let expected = themes.count * modes.count
        metrics["highlight.reached"] = reached
        metrics["highlight.reachedCount"] = reached.count
        metrics["highlight.themeApplied"] = themeApplied
        metrics["highlight.expected"] = expected

        // ★ **끝나면 되돌린다** — 검증자가 손으로 복원하게 하지 않는다.
        //   사장님 실기라면 개인 설정(퓨어 다크)은 `testRestoreUserTheme`이 따로 되돌린다.
        selectThemeVerified("시스템", mode: "시스템")
        shot("hl-99-restored-system")

        // ★ ★ **여기에 단언이 한 줄도 없었다** — 8조합 중 0개가 열려도 초록이었다.
        //   이 파일에서 같은 종류가 **세 번째**다(검증자 2026-09-23).
        //   `reachedCount`는 도달 **횟수**일 뿐이라 기록만으로는 아무것도 막지 못한다.
        //
        // ## 이 단언들이 깨지려면 무엇이 잘못돼야 하는가
        //
        // - `themeApplied`: **고른 테마가 화면에 실제로 안 찍혔다.** 좌표가 빗나갔거나
        //   목록이 스크롤돼 뒤 두 테마를 못 눌렀다 — **A의 그 고장이다.**
        //   이것이 없으면 캡처가 라벨과 **다른 테마**여도 통과한다(3차에서 그렇게 지나갔다).
        // - `reached`: 테마는 맞는데 **배지가 안 뜨거나 패널이 안 열렸다.**
        //   「단어로 구절 찾기」가 꺼졌거나 검색 경로가 깨진 것이다.
        XCTAssertEqual(
            themeApplied.count, expected,
            "테마가 실제로 적용된 조합이 \(themeApplied.count)/\(expected)다 — "
                + "못 바꾼 조합: \(Set(themes.flatMap { t in modes.map { "hl-\(t)-\($0)" } }).subtracting(themeApplied).sorted())"
        )
        XCTAssertEqual(
            reached.count, expected,
            "\(expected)조합 중 \(reached.count)개만 패널에 도달했다: \(reached)"
        )
    }

    // MARK: - ★ 성능·오탭 실측 (검증자 차단 #2·#5, 2026-09-23)

    /// **입력 멈춤 → 배지 표시까지의 지연**을 잰다 — cold 3회 + warm 5회.
    /// `-only-testing:TadakUITests/GlassThemeDeviceTests/testBadgeLatencyColdAndWarm`
    ///
    /// ## 왜 이 수치가 따로 필요한가
    ///
    /// 계획서 `v1.1.0-plan-v5.md:520`의 **16.7ms는 주 스레드 프레임 예산**이다.
    /// 스캔이 `Task.detached`로 주 스레드를 나간 뒤로는 그 숫자와 직접 비교할 대상이 없다.
    /// 여기서 재는 것은 **사람이 기다리는 시간**이고, 디바운스 120ms가 **포함**된 값이다.
    ///
    /// ## cold 와 warm 을 가르는 이유
    ///
    /// cold 는 키보드를 내렸다 올린 뒤 첫 검색이다 — `makeSearcher`가 lazy 라 이때
    /// 스캐너와 바이트 빈도표가 만들어진다. warm 은 같은 세션의 반복이다.
    /// **둘을 섞으면 첫 회 비용이 평균에 묻힌다.**
    ///
    /// ★ **시간은 계측이지 판정이 아니다.** 단언하는 것은 **표본이 실제로 모였는가**와
    /// **배지가 실제로 떴는가**뿐이다 — 「몇 ms 부터 느린가」는 사람이 정한다.
    func testBadgeLatencyColdAndWarm() throws {
        var cold: [Double] = []
        var warm: [Double] = []

        for round in 1...3 {
            dismissKeyboardIfShown()
            Thread.sleep(forTimeInterval: 1.0)          // 익스텐션을 내려 다음 등장을 cold 로 만든다
            let field = inputField
            guard field.waitForExistence(timeout: 5) else { XCTFail("입력 테스트란이 없다"); return }
            clearField()
            field.tap()
            Thread.sleep(forTimeInterval: 0.8)
            try ensureTadakKeyboard(tag: "lat-cold\(round)")
            if let t = measureBadge(tag: "cold\(round)") { cold.append(t) }
        }

        for round in 1...5 {
            clearField()
            Thread.sleep(forTimeInterval: 0.4)
            if let t = measureBadge(tag: "warm\(round)") { warm.append(t) }
        }

        metrics["latency.coldSeconds"] = cold
        metrics["latency.warmSeconds"] = warm
        metrics["latency.note"] = "디바운스 120ms 포함. 마지막 키 탭 직후부터 배지 요소 등장까지."
        shot("lat-99-end")

        // 깨지려면: 배지가 한 번도 안 뜬다(검색이 죽었다) — 시간 자체는 판정하지 않는다.
        XCTAssertEqual(cold.count, 3, "cold 표본 3회를 못 모았다 — 배지가 안 뜬 회차가 있다")
        XCTAssertEqual(warm.count, 5, "warm 표본 5회를 못 모았다 — 배지가 안 뜬 회차가 있다")
    }

    /// 「사랑」을 치고 **마지막 자모 탭 직후부터** 배지가 접근성 트리에 나타날 때까지를 잰다.
    private func measureBadge(tag: String) -> Double? {
        for jamo in ["ㅅ", "ㅏ", "ㄹ", "ㅏ"] { tapKeyboardKey(jamo) }
        let badge = keyboardApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", ToolbarTool.bibleBadgeLabelPrefix)).firstMatch
        let start = Date()
        tapKeyboardKey("ㅇ")                              // ← 이 키가 검색을 일으킨다
        let appeared = badge.waitForExistence(timeout: 10)
        let elapsed = Date().timeIntervalSince(start)
        metrics["latency.\(tag).appeared"] = appeared
        metrics["latency.\(tag).seconds"] = elapsed
        return appeared ? elapsed : nil
    }

    /// ★ **오탭 — 배지가 뜬 뒤 「전에 이모지가 있던 자리」를 누르면 무엇이 열리는가.**
    /// `-only-testing:TadakUITests/GlassThemeDeviceTests/testMistapEmojiSlotOpensPanel`
    ///
    /// 검증자가 frame 으로 **겹침 70.0%**를 실측했다(`verify-v110-device-2.md`). 그러나
    /// 「실제로 성경 패널이 열리는가」는 **손가락으로 눌러 봐야** 알 수 있고, 그것이 사용자가 겪는 일이다.
    ///
    /// 단언하지 않는다 — **무엇이 열렸는지 `metrics`에 적기만 한다.** 어느 쪽이 옳은 동작인지는
    /// 제품 판단이고 사람이 정한다.
    func testMistapEmojiSlotOpensPanel() throws {
        dismissKeyboardIfShown()
        let field = inputField
        guard field.waitForExistence(timeout: 5) else { XCTFail("입력 테스트란이 없다"); return }
        clearField()
        field.tap()
        Thread.sleep(forTimeInterval: 0.8)
        try ensureTadakKeyboard(tag: "mistap")

        // ── A) 배지 없음 — 빈 입력란의 도구 행에서 이모지 자리를 기억한다
        let emoji = keyboardApp.buttons[ToolbarTool.emoji.displayName].firstMatch
        guard emoji.waitForExistence(timeout: 5) else {
            XCTFail("도구 행에 이모지가 없다 — 전체 접근이 꺼졌거나 도구가 꺼져 있다")
            return
        }
        let emojiFrame = emoji.frame
        metrics["mistap.emojiFrameA"] = "\(emojiFrame)"
        shot("mistap-1-tool-row")

        // ── B) 배지 띄우기 — 낱말 + 스페이스면 추천단어가 0개가 되고 배지는 남는다
        for jamo in ["ㅅ", "ㅏ", "ㄹ", "ㅏ", "ㅇ"] { tapKeyboardKey(jamo) }
        // ★ 스페이스는 라벨이 공백 한 칸이라 이름으로 못 찾는다 — 좌표 헬퍼를 쓴다.
        tapBottomKey(.space)
        Thread.sleep(forTimeInterval: 1.8)
        let badge = keyboardApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", ToolbarTool.bibleBadgeLabelPrefix)).firstMatch
        metrics["mistap.badgeShown"] = badge.waitForExistence(timeout: 6)
        metrics["mistap.badgeFrameB"] = "\(badge.exists ? "\(badge.frame)" : "(없음)")"
        shot("mistap-2-badge-row")

        // ── C) ★ A 의 이모지 **중심**을 좌표로 누른다 — 손 기억이 가리키는 그 자리다
        let window = app.windows.firstMatch
        let cx = emojiFrame.midX / window.frame.width
        let cy = emojiFrame.midY / window.frame.height
        window.coordinate(withNormalizedOffset: CGVector(dx: cx, dy: cy)).tap()
        Thread.sleep(forTimeInterval: 1.5)
        shot("mistap-3-after-tap")

        // 무엇이 열렸나 — 패널이면 「자판으로 돌아가기」가, 이모지면 최근/카테고리가 보인다
        let panelOpen = keyboardApp.buttons[BibleSearchText.backToKeyboardLabel].firstMatch.exists
        metrics["mistap.panelOpened"] = panelOpen
        metrics["mistap.result"] = panelOpen ? "성경 패널이 열렸다" : "성경 패널은 아니다"
    }

    /// 한 조합에서 배지를 만들고 패널을 연다. 도달했으면 `true`.
    private func captureHighlightPanel(tag: String) throws -> Bool {
        dismissKeyboardIfShown()
        let field = inputField
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("\(tag): 입력 테스트란이 없다")
            return false
        }
        clearField()
        field.tap()
        Thread.sleep(forTimeInterval: 0.8)
        try ensureTadakKeyboard(tag: tag)

        // 「사랑」 — 두벌식 자모 다섯. 개수가 나오는 낱말이면 무엇이든 되지만
        // 517건이라 배지가 `999+`로 접히지 않아 조합 간 비교가 쉽다.
        for jamo in ["ㅅ", "ㅏ", "ㄹ", "ㅏ", "ㅇ"] {
            tapKeyboardKey(jamo)
        }
        Thread.sleep(forTimeInterval: 1.5)

        // 배지 — 라벨 앞부분을 `TadakDomain`에서 읽는다(문자열을 박지 않는다)
        let badge = keyboardApp.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", ToolbarTool.bibleBadgeLabelPrefix)).firstMatch
        let hasBadge = badge.waitForExistence(timeout: 6)
        shot("\(tag)-1-badge")
        guard hasBadge else {
            metrics["\(tag).badge"] = false
            XCTFail("\(tag): 배지가 안 떴다 — 「단어로 구절 찾기」가 꺼져 있는지 확인하라")
            return false
        }
        metrics["\(tag).badge"] = true

        badge.tap()
        Thread.sleep(forTimeInterval: 1.5)
        let back = keyboardApp.buttons[BibleSearchText.backToKeyboardLabel].firstMatch
        let opened = back.waitForExistence(timeout: 5)
        // ★ 이것이 검증자가 픽셀을 잴 그림이다
        shot("\(tag)-2-highlight-panel")
        if !opened { XCTFail("\(tag): 배지를 눌렀는데 패널이 안 열렸다") }
        return opened
    }

    private func closePanelIfOpen() {
        let back = keyboardApp.buttons[BibleSearchText.backToKeyboardLabel].firstMatch
        if back.exists {
            back.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    /// 익스텐션 프로세스의 키를 라벨로 누른다. 문자 키는 라벨이 글자 그대로다
    /// (`KeyCapView.accessibilityName`). `SnippetShortcutTypingTests.tapKey`와 같은 수법이고,
    /// 검증자가 실기에서 그 경로로 「사랑」을 쳐 패널까지 연 것이 확인돼 있다.
    @discardableResult
    private func tapKeyboardKey(_ label: String) -> Bool {
        for element in [keyboardApp.keys[label].firstMatch,
                        keyboardApp.buttons[label].firstMatch,
                        keyboardApp.staticTexts[label].firstMatch] where element.exists {
            element.tap()
            Thread.sleep(forTimeInterval: 0.12)
            return true
        }
        metrics["key.missing.\(label)"] = true
        return false
    }

    private var keyboardApp: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
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
        let field = inputField
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
        _ = selectThemeVerified(name, mode: mode)
    }

    /// ★ 테마·모드를 **이름으로 고르고, 실제로 골라진 것을 확인한다** (2026-09-23).
    ///
    /// ## 왜 좌표 탭을 버렸나
    ///
    /// 검증자 실측: `testHighlightAcrossThemes`의 캡처 8장이 **실제로는 4상태뿐**이고
    /// **미드나이트·퓨어다크 팔레트가 8장 통틀어 0픽셀**이었다.
    /// 원인 후보가 둘이었는데 **둘 다 좌표 탭에서 나온다** —
    /// 목록이 스크롤되면 뒤 두 테마의 y가 어긋나고, 빗나간 탭은 **아무 일도 안 하면서 조용하다.**
    ///
    /// 그래서 **접근성 라벨로 찾는다.** 앱이 이미 그것을 달아 두었다:
    /// - 테마 행 `ThemePreviewCard`: 라벨 `"<이름>, 라이트와 다크 미리보기"` · 값 `"선택됨"`
    /// - 모드: 세그먼트 `Picker`의 「시스템」·「라이트」·「다크」
    ///
    /// ## ★ 대기만으로는 약하다 — **화면에서 바뀜을 읽는다**
    ///
    /// 고른 뒤 **선택 상태를 되읽어** 확인한다. 빗나간 탭이 조용히 지나가지 못한다.
    /// 그 위에 대기를 더한다 — `CLAUDE.md`가 적듯 앱이 저장 직후 Darwin 알림을 보내고
    /// **키보드가 120ms 디바운스 뒤 재로드**한다. 120ms는 **최소값**이라
    /// 넉넉히 **0.8초**(약 6배)를 준다: 알림이 프로세스를 건너가고, XCUITest 아래에서는
    /// 기기가 더 느리며, 어차피 다음 단계에서 키보드를 새로 올린다.
    ///
    /// - Returns: 모드·테마가 **실제로 선택된 것까지** 확인되면 `true`.
    @discardableResult
    private func selectThemeVerified(_ name: String, mode: String) -> Bool {
        dismissKeyboardIfShown()
        openTab("화면", fallback: CGPoint(x: 237, y: 800))
        Thread.sleep(forTimeInterval: 0.8)

        // ── 모드
        let modeButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", mode)).firstMatch
        var modeOK = false
        if modeButton.waitForExistence(timeout: 3) {
            modeButton.tap()
            Thread.sleep(forTimeInterval: 0.5)
            modeOK = modeButton.isSelected
        }
        metrics["theme.\(name)-\(mode).modeSelected"] = modeOK

        // ── 테마 행 — 라벨이 이름으로 시작한다
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(name),")).firstMatch
        var themeOK = false
        if row.waitForExistence(timeout: 3) {
            // 목록이 길면 화면 밖일 수 있다 — 좌표가 아니라 **요소**로 끌어온다
            if !row.isHittable { app.swipeUp(); Thread.sleep(forTimeInterval: 0.5) }
            if row.isHittable {
                row.tap()
                Thread.sleep(forTimeInterval: 0.5)
                // ★ **되읽어 확인한다** — 빗나간 탭이 조용히 지나가지 못한다
                themeOK = ((row.value as? String) ?? "").contains("선택됨") || row.isSelected
            }
        }
        metrics["theme.\(name)-\(mode).themeSelected"] = themeOK

        shot("theme-\(name)-\(mode)")

        // 키보드가 새 팔레트를 읽을 시간 (위 주석)
        Thread.sleep(forTimeInterval: 0.8)
        openTab("자판", fallback: CGPoint(x: 73, y: 800))
        Thread.sleep(forTimeInterval: 0.8)

        if !modeOK { XCTFail("모드 「\(mode)」가 선택되지 않았다") }
        if !themeOK { XCTFail("테마 「\(name)」가 선택되지 않았다 — 목록이 스크롤됐거나 이름이 다르다") }
        return modeOK && themeOK
    }

    /// 탭 막대를 **이름으로** 연다. 못 찾으면 좌표로 물러난다(어느 쪽을 썼는지 남긴다).
    private func openTab(_ name: String, fallback: CGPoint) {
        let button = app.tabBars.buttons[name].firstMatch
        if button.waitForExistence(timeout: 2), button.isHittable {
            button.tap()
            metrics["tab.\(name)"] = "label"
            return
        }
        tap(at: fallback)
        metrics["tab.\(name)"] = "fallback-coordinate"
    }

    private func runKeyboardScenario(tag: String, screenshots: Bool = true) throws {
        dismissKeyboardIfShown()
        let field = inputField
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
        // ★ 요소가 없으면 `.value(forKey:)`가 "No matches found"로 **예외를 던진다** —
        //   존재 검사를 앞에 두어 단락시킨다(검증자 실측 2026-09-23).
        let focused = inputField.exists
            && inputField.value(forKey: "hasKeyboardFocus") as? Bool == true
        if app.keyboards.count > 0 || focused {
            app.swipeDown()
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    private func clearField() {
        let clear = app.buttons["지우기"]
        if clear.exists { clear.tap(); Thread.sleep(forTimeInterval: 0.3) }
    }

    /// 컨테이너 앱의 **「입력 테스트란」**.
    ///
    /// ★ `textFields`가 아니라 **`textViews`**다 — `App/Settings/InputTestField.swift`가
    /// *"SwiftUI `TextField`가 아니라 `UITextView`를 직접 감싸는"* 구현이기 때문이다
    /// (그 파일 6~9행이 이유를 적는다: responder를 직접 제어해야 한다).
    ///
    /// 이것을 `textFields`로 찾던 다섯 자리 때문에 `testHighlightAcrossThemes`가
    /// **8조합 중 0개 도달로 죽었다** — `.value(forKey:)`가 "No matches found"로 예외를 던진다
    /// (검증자 실측 2026-09-23: 실패 시점 접근성 트리에 `TextField` 0건 · `TextView` 1건).
    /// **한 곳으로 모아 두면 앱 쪽 구현이 또 바뀌어도 여기만 고치면 된다.**
    private var inputField: XCUIElement { app.textViews.firstMatch }

    private func fieldText() -> String {
        // ★ 요소가 없을 때 `.value` 접근은 예외를 던진다 — 먼저 존재를 본다.
        guard inputField.exists else { return "" }
        let value = inputField.value as? String ?? ""
        return value == "여기에 입력해 키보드를 확인하세요" ? "" : value
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
