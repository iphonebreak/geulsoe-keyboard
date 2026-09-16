import XCTest

/// **임시 하네스 — 전체 접근 ON/OFF 이중 검증용** (2026-09-15).
///
/// 검증이 끝나면 **이 파일은 지운다.** 저장소에 남기지 않는다.
///
/// 우리 컨테이너 앱을 **띄우지 않는다** — 인자 없는 `XCUIApplication()` 을 쓰지 않는다.
/// 설정 앱만 만진다(방출 0). 여기서 넣는 문자열은 전부 **상수**다
/// (사용자 입력이 아니다 — `.claude/rules/security.md`).
///
/// 호스트를 **설정 앱의 검색 필드**로 잡은 이유: 사파리는 첫 실행 안내·시작 페이지 시트가
/// 좌표 탭을 가로채 재현이 안 됐다(실측 2026-09-15). 설정 앱 검색 필드는 요소로 잡힌다.
final class FAVerifyTests: XCTestCase {

    private var settings: XCUIApplication!
    private var keyboard: XCUIApplication!
    private var springboard: XCUIApplication!
    private var notes: [String] = []

    /// 클립보드에 넣어 둘 상수 — FA OFF 에서는 이 칩이 **뜨면 안 된다**.
    private static let clipText = "인증번호 483920 을 입력해 주세요"

    override func setUpWithError() throws {
        continueAfterFailure = true
        settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "notes.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 1. 자판만 켠다 (전체 접근은 건드리지 않는다 = OFF 유지)

    func test1EnableKeyboardOnly() throws {
        settings.launch()
        gotoKeyboardList()
        if settings.cells.staticTexts["글쇠"].waitForExistence(timeout: 3) {
            notes.append("글쇠가 이미 자판 목록에 있다")
        } else {
            tap(["새로운 키보드 추가…", "새로운 키보드 추가", "Add New Keyboard…"],
                in: settings.cells, label: "새 키보드 추가")
            tap(["글쇠"], in: settings.cells, label: "글쇠 선택")
        }
        tap(["글쇠"], in: settings.cells, label: "글쇠 행")
        let fullAccess = settings.switches.firstMatch
        notes.append("전체 접근 스위치 값 = \(fullAccess.waitForExistence(timeout: 5) ? (fullAccess.value as? String ?? "?") : "없음")")
        shot("1b-전체접근-값")
    }

    // MARK: - 2/4. 장면

    func test2SceneFullAccessOff() throws { try runScene(tag: "FAOFF") }
    func test4SceneFullAccessOn() throws { try runScene(tag: "FAON") }

    // MARK: - 3. 전체 접근을 켠다

    func test3TurnFullAccessOn() throws {
        settings.launch()
        gotoKeyboardList()
        tap(["글쇠"], in: settings.cells, label: "글쇠 행")
        let fullAccess = settings.switches.firstMatch
        guard fullAccess.waitForExistence(timeout: 5) else {
            notes.append("★ 전체 접근 스위치를 찾지 못했다"); shot("3x-실패"); return
        }
        if fullAccess.value as? String == "0" {
            fullAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.5)
            var allowed = false
            for candidate in [settings.alerts, springboard.alerts] {
                for label in ["허용", "Allow"] {
                    let button = candidate.buttons[label].firstMatch
                    if button.waitForExistence(timeout: 4) {
                        button.tap(); allowed = true
                        notes.append("확인 대화상자 「\(label)」 탭"); break
                    }
                }
                if allowed { break }
            }
            if !allowed { notes.append("★ 확인 대화상자를 못 잡았다") }
        }
        Thread.sleep(forTimeInterval: 1.0)
        notes.append("전체 접근 최종 값 = \(settings.switches.firstMatch.value as? String ?? "?") (1=ON)")
        shot("3b-전체접근-ON")
    }

    // MARK: - 5. 전체 접근을 다시 끈다 (대조군을 같은 하네스 판본으로 다시 돌리기 위해)

    func test5TurnFullAccessOff() throws {
        settings.launch()
        gotoKeyboardList()
        tap(["글쇠"], in: settings.cells, label: "글쇠 행")
        let fullAccess = settings.switches.firstMatch
        guard fullAccess.waitForExistence(timeout: 5) else {
            notes.append("★ 전체 접근 스위치를 찾지 못했다"); shot("5x-실패"); return
        }
        if fullAccess.value as? String == "1" {
            fullAccess.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            Thread.sleep(forTimeInterval: 1.5)
        }
        Thread.sleep(forTimeInterval: 1.0)
        notes.append("전체 접근 최종 값 = \(settings.switches.firstMatch.value as? String ?? "?") (0=OFF)")
        shot("5b-전체접근-OFF")
    }

    // MARK: - 공통 장면

    private func runScene(tag: String) throws {
        UIPasteboard.general.string = Self.clipText
        notes.append("[\(tag)] 클립보드에 상수를 넣었다 (\(Self.clipText.count)자)")

        settings.terminate()
        settings.launch()
        Thread.sleep(forTimeInterval: 2.0)

        let search = searchField()
        guard let search else {
            notes.append("[\(tag)] ★ 설정 검색 필드를 못 찾았다"); shot("\(tag)-00-검색필드없음"); return
        }
        search.tap()
        Thread.sleep(forTimeInterval: 2.0)
        allowPasteIfAsked(tag: tag, step: "00-등장")
        dismissKeyboardIntro(tag: tag)
        shot("\(tag)-00a-검색필드-포커스")
        dumpKeyboards(tag: tag, step: "00a")

        try bringUpGeulsoe(tag: tag)
        Thread.sleep(forTimeInterval: 2.0)
        shot("\(tag)-A-등장직후")
        recordDialogs(tag: tag, step: "A-등장직후")
        allowPasteIfAsked(tag: tag, step: "A-등장직후")
        recordKeyboardTree(tag: tag, step: "A-등장직후")

        guard keyboard.exists else {
            notes.append("[\(tag)] ★ 글쇠가 안 떠서 이후 단계를 못 밟았다")
            return
        }

        // --- (가-0) 후보를 닫아 **도구 행**을 드러낸다.
        //     툴바는 후보(칩·추천단어)가 있으면 도구 행을 내주지 않는다(PDR toolbar-tools).
        //     FA ON 에서는 A 단계에 붙여넣기 칩이 떠 있어 도구 행이 안 보인다 — 닫고 봐야
        //     「클립보드」 도구가 FA 에 묶여 있는지 두 상태에서 같은 방법으로 비교된다.
        let closeCandidates = keyboard.buttons["후보 닫기"].firstMatch
        if closeCandidates.exists {
            closeCandidates.tap()
            Thread.sleep(forTimeInterval: 1.5)
            notes.append("[\(tag)] 「후보 닫기」 탭 — 도구 행을 드러낸다")
        } else {
            notes.append("[\(tag)] 닫을 후보가 없다 (도구 행이 이미 보인다)")
        }
        shot("\(tag)-A2-도구행")
        recordKeyboardTree(tag: tag, step: "A2-도구행")

        // --- (가) 한글 키캡을 직접 눌러 본다 — 꼬리 파이프라인이 도는지 본다.
        //     추천단어 사전은 **번들**이라 App Group 과 무관하다: 후보가 뜨면 꼬리는 정상.
        tapKey(0.278, 0.754, "ㅇ")
        tapKey(0.833, 0.754, "ㅏ")
        tapKey(0.167, 0.754, "ㄴ")
        Thread.sleep(forTimeInterval: 2.0)
        shot("\(tag)-B1-한글-안-추천단어")
        recordKeyboardTree(tag: tag, step: "B1-한글'안'")
        recordFieldValue(tag: tag, step: "B1-한글'안'")

        clearField(tag: tag)
        Thread.sleep(forTimeInterval: 1.0)

        // --- (나) 영어로 바꿔 ASCII 단축어를 키캡으로 친다 (새 스키마 triggers) ---
        tapKey(0.193, 0.8825, "한영(ABC)")
        Thread.sleep(forTimeInterval: 1.2)
        shot("\(tag)-B2-영문자판")
        // 자동 대문자가 첫 글자를 올린다(실측: "qq" → "Qq"). 앞에 한 글자를 먼저 쳐
        // 문장 시작을 소진시킨 뒤 소문자 qq 를 친다 — 꼬리는 "Aqq", 접미사 "qq" 가 맞는다.
        tapKey(0.0565, 0.754, "a")
        tapKey(0.05, 0.691, "q")
        tapKey(0.05, 0.691, "q")
        Thread.sleep(forTimeInterval: 2.0)
        shot("\(tag)-B3-qq-새스키마-키캡")
        recordChip(tag: tag, step: "B3-qq키캡", label: "채움글 NEWSCHEMA 붙여넣기")
        recordKeyboardTree(tag: tag, step: "B3-qq키캡")
        recordFieldValue(tag: tag, step: "B3-qq키캡")

        clearField(tag: tag)
        Thread.sleep(forTimeInterval: 1.0)

        // --- (다) 옛 스키마 단축어 ww 를 키캡으로 ---
        tapKey(0.15, 0.691, "w")
        tapKey(0.15, 0.691, "w")
        Thread.sleep(forTimeInterval: 2.0)
        shot("\(tag)-C-ww-옛스키마-키캡")
        recordChip(tag: tag, step: "C-ww키캡", label: "채움글 OLDSCHEMA 붙여넣기")
        recordKeyboardTree(tag: tag, step: "C-ww키캡")
        recordFieldValue(tag: tag, step: "C-ww키캡")

        // --- 칩 탭 → 본문이 들어가는가 ---
        let chip = keyboard.buttons["채움글 OLDSCHEMA 붙여넣기"]
        if chip.exists {
            chip.tap(); Thread.sleep(forTimeInterval: 2.0)
            notes.append("[\(tag)] 옛스키마 칩 탭함")
        } else {
            notes.append("[\(tag)] 옛스키마 칩이 없어 탭하지 못했다")
        }
        shot("\(tag)-D-칩-탭-후")
        recordFieldValue(tag: tag, step: "D-칩탭후")

        // --- 자판을 내렸다 올린다 (재등장 · 재프로브 경로) ---
        //
        // ★ `dismissSearch()` → 재포커스로는 못 한다 (실측 2026-09-16, 같은 자리에서 3회 연속).
        //   자판은 다시 뜨는데 **익스텐션 a11y 질의가 굳어** "Timed out while evaluating UI query"
        //   가 나고, 이 실패는 `continueAfterFailure` 와 무관하게 테스트를 통째로 끊는다
        //   (전수 열거·조준 술어 질의 둘 다 동일). 그래서 설정 앱을 껐다 켜서 **진짜 재등장**을
        //   만든다 — `viewWillAppear` → `probePasteboard()` 가 다시 도는 것은 같다.
        clearField(tag: tag)
        relaunchAndFocus(tag: tag, step: "E")
        shot("\(tag)-E-재등장")
        recordDialogs(tag: tag, step: "E-재등장")
        allowPasteIfAsked(tag: tag, step: "E-재등장")
        recordKeyboardTree(tag: tag, step: "E-재등장")

        // --- 클립보드를 새로 바꾸고 다시 등장 (reprobePasteboardIfChanged 경로) ---
        UIPasteboard.general.string = "새로 복사한 두번째 인증번호 654321"
        notes.append("[\(tag)] 클립보드를 새 상수로 바꿨다")
        relaunchAndFocus(tag: tag, step: "F")
        shot("\(tag)-F-새로복사-후-재등장")
        recordDialogs(tag: tag, step: "F-새로복사")
        allowPasteIfAsked(tag: tag, step: "F-새로복사")
        recordKeyboardTree(tag: tag, step: "F-새로복사")

        notes.append("[\(tag)] 익스텐션 요소 존재 = \(keyboard.exists)")
    }

    // MARK: - 조작

    /// iOS 시스템 **붙여넣기 확인창**을 받아 준다 — 「'글쇠'이(가) …에서 붙여넣으려고 함」.
    ///
    /// ## 이게 이번 검증의 대조군이다 (실측 2026-09-16)
    ///
    /// FA **ON** 에서만 뜬다. `probePasteboard()` 가 `UIPasteboard.general.string` 을 실제로
    /// 읽기 때문이다. 이 창이 떠 있는 동안 **익스텐션 메인 스레드가 막혀** 익스텐션을 향한 모든
    /// a11y 질의가 "process main thread busy for 30.0s" 로 끊긴다 — 첫 FA ON 회차가 그렇게 죽었다.
    /// 그래서 익스텐션에 뭘 묻기 **전에** 이걸 먼저 친다.
    ///
    /// FA **OFF** 에서는 한 번도 뜨지 않았다(`recordDialogs` 전 단계 "대화상자 = 없음").
    /// 게이트가 클립보드 읽기 자체를 막는다는 뜻이다.
    ///
    /// 질의 대상은 **스프링보드**다 — 막혀 있는 익스텐션에는 묻지 않는다.
    @discardableResult
    private func allowPasteIfAsked(tag: String, step: String) -> Bool {
        for label in ["붙여넣기 허용", "Allow Paste"] {
            let button = springboard.buttons[label].firstMatch
            if button.waitForExistence(timeout: 3) {
                button.tap()
                notes.append("[\(tag)] \(step): ★ 시스템 붙여넣기 확인창 「\(label)」 탭 (FA ON 신호)")
                Thread.sleep(forTimeInterval: 2.0)
                return true
            }
        }
        return false
    }

    /// 설정 앱을 껐다 켜고 검색 필드에 글쇠를 다시 올린다 (위 재등장 주석 참조).
    private func relaunchAndFocus(tag: String, step: String) {
        settings.terminate()
        settings.launch()
        Thread.sleep(forTimeInterval: 2.0)
        guard let field = searchField() else {
            notes.append("[\(tag)] \(step): 재등장 — 검색 필드를 못 찾았다"); return
        }
        field.tap()
        Thread.sleep(forTimeInterval: 2.0)
        allowPasteIfAsked(tag: tag, step: "\(step)-포커스")
        dismissKeyboardIntro(tag: tag)
        try? bringUpGeulsoe(tag: tag)
        Thread.sleep(forTimeInterval: 2.5)
        allowPasteIfAsked(tag: tag, step: "\(step)-재등장")
    }

    private func gotoKeyboardList() {
        tap(["일반", "General"], in: settings.cells, label: "일반")
        tap(["키보드", "Keyboards", "Keyboard"], in: settings.cells, label: "키보드(1)")
        tap(["키보드", "Keyboards"], in: settings.cells, label: "키보드(2)")
    }

    private func searchField() -> XCUIElement? {
        for query in [settings.searchFields, settings.textFields] {
            let element = query.firstMatch
            if element.waitForExistence(timeout: 6) { return element }
        }
        return nil
    }

    private func type(_ text: String, tag: String) {
        guard let field = searchField() else { notes.append("[\(tag)] 입력란 없음"); return }
        field.typeText(text)
        notes.append("[\(tag)] typeText(\"\(text)\")")
    }

    private func clearField(tag: String) {
        guard let field = searchField() else { return }
        let current = (field.value as? String) ?? ""
        guard !current.isEmpty, current != "검색" else { return }
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,
                              count: min(current.count + 2, 90)))
        Thread.sleep(forTimeInterval: 0.8)
        notes.append("[\(tag)] 입력란 지움 (이전 \(current.count)자)")
    }

    /// 시스템 자판의 슬라이딩 타이핑 안내 「계속」을 닫는다 — 자판 위를 덮는다.
    private func dismissKeyboardIntro(tag: String) {
        for _ in 0..<3 {
            var tapped = false
            for app in [settings, springboard, keyboard,
                        XCUIApplication(bundleIdentifier: "com.apple.keyboard")] {
                guard let app else { continue }
                for label in ["계속", "Continue"] {
                    let button = app.buttons[label].firstMatch
                    if button.exists, button.isHittable {
                        button.tap(); tapped = true
                        notes.append("[\(tag)] 자판 안내 「\(label)」 닫음")
                        break
                    }
                }
                if tapped { break }
            }
            if !tapped { return }
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    /// 글쇠를 올린다 — **지구본은 길게 눌러야 목록이 뜬다**(`verify-paste-chip.md` 1-1).
    private func bringUpGeulsoe(tag: String) throws {
        if keyboard.waitForExistence(timeout: 4) {
            notes.append("[\(tag)] 글쇠가 이미 떠 있다"); return
        }
        for attempt in 1...5 {
            var pressed = false
            // 지구본을 요소로 먼저 찾는다 (시스템 자판은 호스트의 keyboards 로 잡힐 때가 있다)
            for candidate in [settings.keyboards.buttons["다음 키보드"].firstMatch,
                              settings.keyboards.buttons["Next keyboard"].firstMatch,
                              springboard.buttons["다음 키보드"].firstMatch] where candidate.exists {
                candidate.press(forDuration: 0.9)
                pressed = true
                notes.append("[\(tag)] 지구본 요소 길게 (\(attempt)회차)")
                break
            }
            if !pressed {
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.1045, dy: 0.953))
                    .press(forDuration: 0.9)
                notes.append("[\(tag)] 지구본 좌표 길게 (\(attempt)회차)")
            }
            Thread.sleep(forTimeInterval: 1.5)
            shot("\(tag)-00b-\(attempt)-지구본-길게")
            dumpKeyboards(tag: tag, step: "00b-\(attempt)")

            var picked = false
            for app in [springboard, settings] {
                guard let app else { continue }
                for element in app.staticTexts.allElementsBoundByIndex
                where element.label == "글쇠" && element.isHittable {
                    element.tap(); picked = true
                    notes.append("[\(tag)] 메뉴 「글쇠」 라벨 탭 (\(attempt)회차)")
                    break
                }
                if picked { break }
            }
            if !picked {
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.112, dy: 0.802)).tap()
                notes.append("[\(tag)] 메뉴 「글쇠」 좌표 탭 (\(attempt)회차)")
            }
            Thread.sleep(forTimeInterval: 2.0)
            if keyboard.waitForExistence(timeout: 4) {
                notes.append("[\(tag)] 글쇠 익스텐션을 찾았다 (\(attempt)회차)")
                return
            }
        }
        notes.append("[\(tag)] ★ 글쇠 익스텐션을 끝내 못 띄웠다")
        shot("\(tag)-00-글쇠-없음")
    }

    /// 자판 영역은 **스프링보드 정규화 좌표**로 친다 — 호스트 좌표는 자판에 닿지 않고,
    /// 익스텐션 요소의 rect 는 익스텐션 윈도우 로컬이라 쓸 수 없다
    /// (`docs/simulator-input-verification.md`).
    private func tapKey(_ dx: CGFloat, _ dy: CGFloat, _ name: String) {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        notes.append("  키캡 탭: \(name)")
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func dismissSearch() {
        for label in ["취소", "Cancel"] {
            let button = settings.buttons[label].firstMatch
            if button.exists, button.isHittable { button.tap(); return }
        }
        // 못 찾으면 화면 위쪽을 쳐서 포커스를 뺀다
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }

    // MARK: - 관측

    /// 지금 떠 있는 자판의 요소 트리를 남긴다 — 지구본·메뉴 자리를 찾기 위한 것.
    private func dumpKeyboards(tag: String, step: String) {
        let attachment = XCTAttachment(string: settings.keyboards.debugDescription
                                       + "\n\n=== SPRINGBOARD ===\n"
                                       + springboard.debugDescription)
        attachment.name = "\(tag)-\(step)-tree.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func recordKeyboardTree(tag: String, step: String) {
        Thread.sleep(forTimeInterval: 0.8)
        guard keyboard.waitForExistence(timeout: 4) else {
            notes.append("[\(tag)] \(step): 익스텐션 요소 없음"); return
        }
        var labels: [String] = []
        for element in keyboard.buttons.allElementsBoundByIndex where !element.label.isEmpty {
            labels.append(element.label)
        }
        notes.append("[\(tag)] \(step): 익스텐션 버튼 \(labels.count)개 → \(labels.joined(separator: " | "))")
        // 붙여넣기 칩은 **라벨 접두사**로 따로 못 박는다 — FA OFF 에서 0개여야 한다.
        let paste = labels.filter { $0.contains("붙여넣기") && !$0.hasPrefix("채움글") }
        notes.append("[\(tag)] \(step): 붙여넣기 칩 \(paste.count)개 \(paste.joined(separator: " | "))")
        notes.append("[\(tag)] \(step): 클립보드 도구 존재 = \(labels.contains { $0.contains("클립보드") })")
    }

    /// 재등장 직후에는 **전수 열거(`allElementsBoundByIndex`)가 타임아웃**하고, 그 실패는
    /// `continueAfterFailure` 와 무관하게 테스트를 끊는다(실측 2026-09-16, 같은 자리에서 2회).
    /// 그래서 이 단계는 **필요한 것만 조준 질의**한다 — 붙여넣기 칩과 클립보드 도구.
    /// 칩 라벨은 `KeyboardRootView.swift:399-402` 의 "복사한 …​ 붙여넣기".
    private func recordChips(tag: String, step: String) {
        let pasteChip = keyboard.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "복사한")).firstMatch
        notes.append("[\(tag)] \(step): 붙여넣기 칩 존재 = \(pasteChip.waitForExistence(timeout: 4))"
                     + (pasteChip.exists ? " 「\(pasteChip.label)」" : ""))
        let clipboardTool = keyboard.buttons["클립보드"].firstMatch
        notes.append("[\(tag)] \(step): 클립보드 도구 존재 = \(clipboardTool.exists)")
        let snippetChip = keyboard.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "채움글")).firstMatch
        notes.append("[\(tag)] \(step): 채움글 칩 존재 = \(snippetChip.exists)")
    }

    private func recordChip(tag: String, step: String, label: String) {
        notes.append("[\(tag)] \(step): 「\(label)」 존재 = \(keyboard.buttons[label].waitForExistence(timeout: 4))")
    }

    /// 대화상자 조회는 **떠 있지 않은 앱을 물으면 질의가 타임아웃**한다(실측 2026-09-16:
    /// 재등장 직후 익스텐션에 `alerts`를 물어 "Timed out while evaluating UI query" 로
    /// 장면이 통째로 끊겼다). 그래서 `exists` 로 먼저 거르고 `firstMatch` 만 본다.
    private func recordDialogs(tag: String, step: String) {
        var found: [String] = []
        for app in [springboard, settings] {
            guard let app else { continue }
            let alert = app.alerts.firstMatch
            if alert.exists { found.append(alert.label) }
        }
        for label in ["붙여넣기 허용", "Allow Paste", "붙여넣기 허용 안 함"] {
            let button = springboard.buttons[label].firstMatch
            if button.exists { found.append("버튼:\(label)") }
        }
        notes.append("[\(tag)] \(step): 대화상자 = \(found.isEmpty ? "없음" : found.joined(separator: " | "))")
    }

    private func recordFieldValue(tag: String, step: String) {
        let value = (searchField()?.value as? String) ?? "(못 읽음)"
        notes.append("[\(tag)] \(step): 입력란 값 = \(value.prefix(140))")
    }

    private func tap(_ labels: [String], in query: XCUIElementQuery, label: String) {
        for text in labels {
            let cell = query.staticTexts[text].firstMatch
            if cell.waitForExistence(timeout: 6) {
                cell.tap(); notes.append("\(label) → 「\(text)」 탭"); return
            }
            let button = settings.buttons[text].firstMatch
            if button.exists { button.tap(); notes.append("\(label) → 버튼 「\(text)」"); return }
        }
        notes.append("★ \(label): \(labels) 중 못 찾음")
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
