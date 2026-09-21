import XCTest

/// 채움글 **단축어** 하네스 — 검증자가 "입력 수단이 없어" 못 닫은 항목을 실제 입력으로 닫는다 (2026-09-15).
///
/// 배경: `docs/release/verify-snippet-shortcut.md` 4절.
/// > 이번에 막힌 공통 원인은 **시뮬레이터에 임의 텍스트를 넣을 수단이 없다**는 것이다.
/// > `xcrun simctl` 에 타이핑 명령이 없고 `agent-device` 도 좌표 탭만 있다.
/// > 다음에 같은 검증이 필요하면 **UITest 하네스에 `typeText` 를 쓰는 편이 싸다**.
///
/// ## ★ `typeText` 는 답이 아니었다 — 실측으로 갈아엎었다 (2026-09-15)
///
/// `XCUIApplication.typeText` 는 **하드웨어 키 이벤트**다. 글자는 호스트 입력란에 정확히 들어가지만
/// (한글 포함 — `«가나다»` 확인) **우리 익스텐션은 그 변화를 보지 못한다.** 같은 실행 안에서 갈랐다:
///
/// | 입력 방법 | 입력란 | 칩 |
/// |---|---|---|
/// | `typeText("애국가 1절")` (내장 팩) | «애국가 1절» | **안 뜸** |
/// | `typeText("창 1:1")` (성경) | «창 1:1» | **안 뜸** |
/// | `typeText("우리집주소")` (사용자 문구) | «우리집주소» | **안 뜸** |
/// | **자판 키를 직접 탭**(ㅁㄴㅇㄹ) | «ㅁㄴㅇㄹ» | **뜸** — `채움글 탐침 붙여넣기` |
///
/// 내장 팩·성경은 App Group 과 무관한데 그것마저 안 떴으므로 원인은 주입이 아니라 **통지**다.
/// `InputController.committedTail` 은 우리 키 이벤트로만 쌓이고, 하드웨어 입력은
/// `textDidChange` → `syncWithDocument(documentTail:)` 경로를 태워야 하는데 사파리 주소창에서는
/// 그 경로로 꼬리가 서지 않았다. **자판을 실제로 누르는 것이 유일하게 확인된 입력 수단이다.**
///
/// 그래서 이 하네스는 **두벌식 자판을 눌러서 친다**(`typeOnKeyboard`). 자모로 분해해 키를
/// 접근성 라벨로 찾아 탭한다 — 사용자가 하는 그대로이므로 매칭 경로를 곧이곧대로 탄다.
///
/// ## 오염 0 — 우리 컨테이너 앱을 띄우지 않는다
///
/// 호스트는 **사파리**다. `FirebaseApp.configure()` 는 `App/TadakApp.swift` 에만 있고
/// 익스텐션에는 Firebase 가 0바이트다(`project.yml:72`).
/// → 이 파일은 인자 없는 `XCUIApplication()` 을 **절대 쓰지 않는다.** 그것이 우리 앱을 띄운다.
///
/// ## 판정
///
/// 칩은 익스텐션 프로세스의 요소로 잡는다 — 접근성 라벨이 `"채움글 \(title) 붙여넣기"` 다
/// (`KeyboardUI/KeyboardRootView.swift:435`). 키도 접근성 라벨로 잡는다
/// (`KeyCapView.accessibilityName` — 문자 키는 라벨 그대로, 기능 키는 "스페이스"·"지우기"·"기호" 등).
/// **여기 넣는 문자열은 전부 상수다**(사용자 입력이 아니다 — `.claude/rules/security.md`).
///
/// ## 사전 조건 (하네스 밖에서 준비한다 — `docs/release/verify-snippet-uitest.md` 참조)
///
/// 1. 전용 시뮬레이터 · 설치 직후 **첫 실행 전** Analytics 선차단 · 끝나면 삭제
/// 2. `KeyboardEnableSetupTests` 로 글쇠 등록 + 전체 접근
/// 3. App Group `group.com.charging.tadak` 의 `keyboard.userSnippets` 에 시험용 문구 주입
///    (plist 를 직접 쓰고 **시뮬레이터를 재부팅**해 `cfprefsd` 캐시를 무효화한다)
final class SnippetShortcutTypingTests: XCTestCase {

    private var host: XCUIApplication!
    private var keyboard: XCUIApplication!
    private var springboard: XCUIApplication!
    private var notes: [String] = []
    /// 키를 찾은 질의 종류 — 한 번만 적는다(첨부가 지저분해지지 않게).
    private var keyQueryNoted = false

    /// 주입해 둔 시험용 단축어 — 이 값과 App Group 주입 스크립트가 **같아야** 한다.
    enum Fixture {
        /// 5자로 등록한다. 6자("우리집 주소")를 쳤을 때 6자가 지워지는지 보는 항목.
        static let homeTitle = "우리집"
        static let homeBody = "서울특별시 강남구 테헤란로 152"
        /// 두 번 탭 회귀(QA BLOCK-2)용.
        static let dupTrigger = "회사주소"
        static let dupTitle = "회사"
        static let dupBody = "부산광역시 해운대구 센텀중앙로 79"
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        host = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
        springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    override func tearDownWithError() throws {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "notes.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 0. 입력 수단 탐침 (근거 보존용)

    /// 위 표를 만든 탐침. **회귀 감시용으로 남긴다** — 언젠가 `typeText` 가 통하게 되면
    /// 훨씬 싼 하네스를 쓸 수 있으므로, 그때 이 시험이 먼저 알려 준다.
    func testProbeInputMethods() throws {
        try prepare()
        notes.append("— 하드웨어 typeText 경로 —")
        for text in ["애국가 1절", "창 1:1", "우리집주소"] {
            clearByBackspace()
            host.typeText(text)
            Thread.sleep(forTimeInterval: 1.5)
            notes.append("typeText \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(chipLabel(timeout: 2)))")
        }
        shot("P1-하드웨어-타이핑")

        notes.append("— 자판 키 탭 경로 —")
        clearHostField()
        typeOnKeyboard("우리집주소")
        Thread.sleep(forTimeInterval: 1.0)
        notes.append("자판 키 탭 «우리집주소» → 입력란 \(q(fieldValue())) / 칩 \(q(chipLabel()))")
        shot("P2-자판키-탭")
    }

    // MARK: - D. 띄어쓰기 4꼴

    /// 단축어 `우리집주소`(5자)로 등록했을 때 **네 가지 꼴 전부** 칩이 떠야 한다.
    func testSpacingVariantsAllFire() throws {
        try prepare()
        let cases: [(String, String)] = [
            ("붙여쓴-원형", "우리집주소"),
            ("한-칸", "우리집 주소"),
            ("낱글자마다", "우 리 집 주 소"),
            ("앞에-공백", " 우리집주소")
        ]
        for (index, item) in cases.enumerated() {
            clearAll()
            typeOnKeyboard(item.1)
            Thread.sleep(forTimeInterval: 0.8)
            let label = chipLabel()
            notes.append("★ D\(index + 1) \(item.0) \(q(item.1)) → 입력란 \(q(fieldValue())) / 칩 \(q(label))")
            shot("D\(index + 1)-\(item.0)")
        }
        // ★ 「뒤 공백」 — **예전에 여기 적혀 있던 예측("안 뜨는 것이 설계다")은 틀렸다.**
        //   2026-09-16 실측: **칩이 뜬다.** 매처가 꼬리를 풀 때 공백을 통째로 건너뛰므로
        //   («우 리 집 주 소» 를 먹게 하는 바로 그 한 줄) 꼬리 끝 공백도 없는 것과 같다.
        //   탭까지 해서 본문만 깨끗이 들어가는 것은 `testTrailingSpaceChipInsertsCleanly` 가 본다.
        clearAll()
        typeOnKeyboard("우리집주소 ")
        Thread.sleep(forTimeInterval: 0.8)
        notes.append("★ D5 뒤에-공백 «우리집주소 » → 칩 \(q(chipLabel(timeout: 2))) "
                     + "(**뜨는 것이 맞다** — 띄어쓰기 무시 설계의 당연한 귀결)")
        shot("D5-뒤에-공백")
    }

    // MARK: - D5 후속. 뒤 공백 — **예측이 틀렸다**

    /// ★ 위 `testSpacingVariantsAllFire` 의 D5 주석은 **"뒤에 공백이면 안 뜨는 것이 설계다"** 라고
    /// 적어 두었는데 **실측은 반대였다 — 칩이 떴다**(2026-09-16).
    ///
    /// 코드를 보면 그럴 수밖에 없다`[추론]`: `SnippetMatcher.suggestion(forTail:)` 는 꼬리를 풀 때
    /// **공백을 아예 건너뛴다**(`where !characters[index].isWhitespace`). 그래서 꼬리 끝의 공백은
    /// 존재하지 않는 것과 같고 «우리집주소 » 는 «우리집주소» 로 보인다. 띄어쓰기를 무시하는
    /// 설계(D3 «우 리 집 주 소»)와 **같은 한 줄**에서 나오는 결과다.
    ///
    /// 그러면 **지울 구간에 그 뒤 공백이 들어가는가**가 진짜 질문이다.
    /// `trigger = String(characters[start...])` 는 꼬리 **끝까지** 자르므로 공백을 포함한다`[추론]`.
    /// 포함한다면 탭 뒤 입력란은 «(본문)» 이고, 포함하지 않는다면 «(본문) » 이거나 공백이 남는다.
    /// **그걸 눈으로 본다.**
    func testTrailingSpaceChipInsertsCleanly() throws {
        try prepare()
        clearAll()
        typeOnKeyboard("우리집주소 ")
        Thread.sleep(forTimeInterval: 1.0)
        let before = fieldValue()
        notes.append("★ D5b-탭전 입력란 \(q(before)) / 칩 \(q(chipLabel()))")
        shot("D5b-탭-전")

        let tapped = tapChip()
        Thread.sleep(forTimeInterval: 1.5)
        let after = fieldValue()
        notes.append("★ D5b-탭후 입력란 \(q(after)) (탭 성공 \(tapped))")
        shot("D5b-탭-후")
        notes.append("★ D5b-판정 본문만있나=\(after == Fixture.homeBody) "
                     + "/ 본문포함=\(after.contains(Fixture.homeBody)) "
                     + "/ 단축어잔재=\(after.contains("우리집주소")) "
                     + "/ 뒤공백남음=\(after.hasSuffix(" "))")
    }

    // MARK: - D. 지울 길이 = 꼬리 원문

    /// 5자(`우리집주소`)로 등록하고 **6자(`우리집 주소`)를 쳤을 때 6자가 지워진다.**
    /// 칩 탭 뒤 입력란에 앞 글자(`우`)가 남으면 실패다.
    func testDeleteLengthFollowsTypedTail() throws {
        try prepare()
        clearAll()
        let lead = "보내줄게 "          // 앞 문맥 — 이게 살아남아야 한다
        typeOnKeyboard(lead + "우리집 주소")     // 꼬리 원문 6자
        Thread.sleep(forTimeInterval: 1.0)
        let before = fieldValue()
        notes.append("★ E-탭전 입력란 \(q(before)) / 칩 \(q(chipLabel()))")
        shot("E1-탭-전")

        let tapped = tapChip()
        Thread.sleep(forTimeInterval: 1.5)
        let after = fieldValue()
        notes.append("★ E-탭후 입력란 \(q(after)) (탭 성공 \(tapped))")
        shot("E2-탭-후")

        let expected = lead + Fixture.homeBody
        notes.append("★ E-판정 기대 \(q(expected))")
        notes.append("★ E-판정 완전일치=\(after == expected) / 앞문맥보존=\(after.hasPrefix(lead)) "
                     + "/ 본문삽입=\(after.contains(Fixture.homeBody))")
        // 6자가 아니라 5자만 지웠다면 본문 앞에 "우" 가 남는다 — 그것을 직접 본다
        notes.append("★ E-잔재 «우\(Fixture.homeBody.prefix(3))» 꼴이 있나: "
                     + "\(after.contains("우" + Fixture.homeBody.prefix(3)))")
    }

    // MARK: - D. 칩 두 번 탭 (QA BLOCK-2 회귀)

    /// 빠르게 두 번 눌러도 **본문 끝이 잘려 나가지 않는다.**
    /// 방어는 `InputController.insertSnippet` 의 `textTail.hasSuffix(suggestion.trigger)` 다.
    func testDoubleTapDoesNotTruncateBody() throws {
        try prepare()
        clearAll()
        typeOnKeyboard(Fixture.dupTrigger)
        Thread.sleep(forTimeInterval: 1.0)
        notes.append("★ F-탭전 입력란 \(q(fieldValue())) / 칩 \(q(chipLabel()))")
        shot("F0-탭-전")

        // 퇴장 트랜지션(0.28초) 중에도 히트 테스트를 받는다 — 그 창을 노려 대기 없이 두 번 친다.
        //
        // ★ **요소로 두 번 탭하면 창을 못 맞춘다** (실측 2026-09-16).
        // `chipElement()` 는 술어 질의라 `.tap()` 마다 **요소를 다시 찾는다.** 첫 탭으로 칩이
        // 사라지면 두 번째 `.tap()` 은 "No matches found" 로 **던져서 시험이 거기서 죽는다** —
        // 실제로 그렇게 실패했고, 그러면 정작 보려던 "본문이 잘렸나"를 못 본다.
        //
        // 그래서 **프레임을 한 번만 읽고 좌표로 두 번 친다.** 좌표 탭은 요소 질의가 없어
        // 왕복이 없고, 칩이 사라진 뒤에도 던지지 않는다(빈 자리를 칠 뿐이다).
        // 이것이 사용자의 빠른 두 번 누르기에 가장 가깝다.
        let chip = chipElement()
        if chip.waitForExistence(timeout: 5) {
            let frame = chip.frame
            // 화면 좌표계 기준점은 스프링보드다(전체 화면 = 원점 0,0).
            let point = springboard.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            notes.append(String(format: "칩 프레임 (%.1f, %.1f, %.1f×%.1f) — 좌표로 두 번 친다",
                                frame.origin.x, frame.origin.y, frame.width, frame.height))
            point.tap()
            point.tap()
            notes.append("칩 자리를 대기 없이 좌표로 두 번 탭했다")
        } else {
            notes.append("★ 칩을 못 잡아 두 번 탭을 못 했다")
        }
        Thread.sleep(forTimeInterval: 2.0)
        let after = fieldValue()
        notes.append("★ F-탭후 입력란 \(q(after))")
        shot("F1-두-번-탭-후")
        notes.append("★ F-판정 본문온전=\(after.contains(Fixture.dupBody)) "
                     + "/ 본문횟수=\(occurrences(of: Fixture.dupBody, in: after)) "
                     + "/ 기대(1회·잘림없음)와 일치=\(after == Fixture.dupBody)")
    }

    // MARK: - D. 내장 팩 회귀

    /// `애국가 1절` 은 여전히 먹고, 띄어쓰기를 지운 `애국가1절` 도 먹는다.
    /// (본문은 60자가 넘어 **탭하지 않는다** — 뜨는지만 본다.)
    func testBuiltinPackStillFires() throws {
        try prepare()
        for (index, text) in ["애국가 1절", "애국가1절", "새해인사", "새해 인사"].enumerated() {
            clearAll()
            typeOnKeyboard(text)
            Thread.sleep(forTimeInterval: 0.8)
            notes.append("★ G\(index + 1) \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(chipLabel()))")
            shot("G\(index + 1)")
        }
    }

    // MARK: - D. 성경 무변화

    /// 성경 참조 파서는 이번 변경 **범위 밖**이라 이전과 똑같아야 한다.
    /// 단일 절·긴 표기·절 범위 셋 다 칩이 떠야 한다. (범위 본문은 줄바꿈이 있어 탭하지 않는다 —
    /// 사파리 주소창은 한 줄이라 개행이 들어가면 화면을 떠난다.)
    func testBibleUnchanged() throws {
        try prepare()
        for (index, text) in ["창 1:1", "창세기 1장 1절", "창 1:1~3"].enumerated() {
            clearAll()
            typeOnKeyboard(text)
            Thread.sleep(forTimeInterval: 0.8)
            notes.append("★ H\(index + 1) \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(chipLabel()))")
            shot("H\(index + 1)")
        }
    }

    // MARK: - E. 성능 — 단축어 100개일 때 칩이 늦는가

    /// **한계를 먼저 적는다.** 이 숫자에는 XCUITest 의 탭 합성·요소 질의 왕복이 통째로 들어간다.
    /// 매처 자체의 비용(마이크로초)은 여기서 갈라낼 수 없다 — 그건 호스트 마이크로벤치가 낸다
    /// (`docs/release/verify-snippet-uitest.md` E절). 여기서 보는 것은
    /// **"100개가 사람이 느낄 만큼 느리게 만드는가"** 하나다.
    ///
    /// 두 번 돌려 비교한다 — App Group 주입 상태(`base` 4개 ↔ `perf` 104개)를 바꾸려면
    /// plist 를 다시 쓰고 재부팅해야 한다(러너는 App Group 엔타이틀먼트가 없다).
    func testChipLatency() throws {
        try prepare()
        // 매칭이 **성공**하는 꼬리와 **실패**하는 꼬리를 나눠 잰다.
        // 실패 쪽이 최악이다 — 성공하면 정렬된 첫 매치에서 멈추지만 실패하면 전부 훑는다.
        var hits: [Double] = []
        var misses: [Double] = []

        for round in 1...5 {
            clearAll()
            typeOnKeyboard("우리집주")            // 마지막 한 글자 전까지
            let start = Date()
            typeOnKeyboard("소")                  // 이 키가 매칭을 일으킨다
            let appeared = chipElement().waitForExistence(timeout: 10)
            let elapsed = Date().timeIntervalSince(start)
            hits.append(elapsed)
            notes.append(String(format: "★ LAT hit round%d appeared=%@ %.3fs",
                                round, String(appeared), elapsed))
        }

        for round in 1...5 {
            clearAll()
            typeOnKeyboard("바다하나무자")         // 어떤 단축어에도 안 맞는 꼬리
            let start = Date()
            typeOnKeyboard("라")
            // 칩이 안 뜨는 것이 정상 — 마지막 키 탭이 끝나 제어가 돌아오는 시점까지를 잰다
            let elapsed = Date().timeIntervalSince(start)
            misses.append(elapsed)
            notes.append(String(format: "★ LAT miss round%d %.3fs", round, elapsed))
        }

        notes.append(String(format: "★ LAT 요약 hit 중앙값=%.3fs 최소=%.3fs / miss 중앙값=%.3fs 최소=%.3fs",
                            median(hits), hits.min() ?? 0, median(misses), misses.min() ?? 0))
        shot("I1-성능")
    }

    // MARK: - 단계

    // MARK: - 성경 검색 UI (v1.1.0 ①) — 배지와 패널이 실제로 그려지는가

    /// 배지 → 패널 → 책 필터 → 구절 삽입까지 한 흐름으로 본다.
    /// 판정은 전부 **익스텐션 프로세스의 접근성 라벨**로 한다.
    func testBibleSearchBadgeAndPanel() throws {
        try prepare()
        clearAll()

        // 1) 배지 — 「사랑」은 517건이라 999+ 상한에 안 걸린다
        typeOnKeyboard("사랑")
        Thread.sleep(forTimeInterval: 1.2)
        let badge = keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "성경 구절 ")).firstMatch
        let hasBadge = badge.waitForExistence(timeout: 5)
        notes.append("★ B1 「사랑」 → 입력란 \(q(fieldValue())) / 배지 \(hasBadge ? q(badge.label) : "(없음)")")
        shot("B1-배지")
        XCTAssertTrue(hasBadge, "배지가 뜨지 않았다")

        // 2) 패널
        badge.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let back = keyboard.buttons["자판으로 돌아가기"].firstMatch
        notes.append("★ B2 패널 열림=\(back.waitForExistence(timeout: 5))")
        let filters = keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "전체 ")).firstMatch
        notes.append("   전체 탭 \(filters.exists ? q(filters.label) : "(없음)")")
        shot("B2-패널")

        // 3) 책 필터 — 두 번째 탭(건수 1위 책)을 눌러 본다
        let books = keyboard.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "건")).allElementsBoundByIndex
        notes.append("   책 탭 \(books.count)개: \(books.prefix(4).map { $0.label }.joined(separator: " / "))")
        if books.count > 1 {
            books[1].tap()
            Thread.sleep(forTimeInterval: 0.8)
            shot("B3-책-필터")
        }

        // 4) 구절 탭 → 기존 삽입 경로
        let verse = keyboard.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", ":")).firstMatch
        if verse.waitForExistence(timeout: 3) {
            notes.append("★ B4 고른 행 \(q(verse.label))")
            verse.tap()
            Thread.sleep(forTimeInterval: 1.5)
            notes.append("   삽입 뒤 입력란 \(q(fieldValue()))")
        } else {
            notes.append("★ B4 구절 행을 못 찾았다")
        }
        shot("B4-삽입-뒤")
    }

    /// ✕ 는 **친 글자 전체**를 지운다 (계획서 2-7 N-4).
    /// 말끝 떼기 제거(2026-09-21) 뒤에는 찾은 말과 친 말이 언제나 같다.
    func testBibleSearchQueryDeleteRemovesTypedWord() throws {
        try prepare()
        clearAll()

        // ★ 2026-09-21 개정 — 말끝 떼기를 없애면서 「사랑해」는 0건이 됐다.
        //   예전엔 이 테스트가 「사랑해」→「사랑」 폴백으로 배지를 띄우고 ✕가 **3자**를
        //   지우는지 봤다. 이제 찾은 말과 친 말이 언제나 같으므로 직접 친 낱말로 본다.
        typeOnKeyboard("사랑")
        Thread.sleep(forTimeInterval: 1.2)
        let badge = keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "성경 구절 ")).firstMatch
        guard badge.waitForExistence(timeout: 5) else {
            notes.append("★ X1 「사랑」에 배지가 안 떴다")
            shot("X1-배지-없음")
            return XCTFail("배지가 뜨지 않았다")
        }
        notes.append("★ X1 「사랑」 → 배지 \(q(badge.label))")
        badge.tap()
        Thread.sleep(forTimeInterval: 1.0)

        let chipLabel = keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "검색어 ")).firstMatch
        notes.append("   머리 칩 \(chipLabel.exists ? q(chipLabel.label) : "(없음)")")
        shot("X2-패널")

        let clear = keyboard.buttons["검색어 지우기"].firstMatch
        guard clear.waitForExistence(timeout: 3) else {
            return XCTFail("검색어 지우기 버튼이 없다")
        }
        clear.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let after = fieldValue()
        notes.append("★ X3 ✕ 뒤 입력란 \(q(after)) — 한 글자라도 남으면 실패다")
        shot("X3-지운-뒤")
        XCTAssertEqual(after, "", "✕ 가 친 낱말 전체를 지우지 않았다")
    }

    /// 기존 패널 회귀 — 성경 패널을 끼워 넣어도 **이모지·클립보드가 그대로 열리고 닫히는가.**
    /// 패널 분기에서 성경이 앞에 있어 상호 배제가 깨지면 여기서 잡힌다.
    func testExistingPanelsStillWork() throws {
        try prepare()
        clearAll()
        Thread.sleep(forTimeInterval: 0.8)

        for tool in ["이모지", "클립보드"] {
            let button = keyboard.buttons[tool].firstMatch
            guard button.waitForExistence(timeout: 4) else {
                notes.append("★ R 도구 «\(tool)» 이 도구 행에 없다 (설정·권한으로 숨겨졌을 수 있다)")
                continue
            }
            button.tap()
            Thread.sleep(forTimeInterval: 1.0)
            let back = keyboard.buttons["자판으로 돌아가기"].firstMatch
            let opened = back.waitForExistence(timeout: 4)
            notes.append("★ R \(tool) 패널 열림=\(opened)")
            shot("R-\(tool)-열림")
            XCTAssertTrue(opened, "\(tool) 패널이 열리지 않았다")
            back.tap()
            Thread.sleep(forTimeInterval: 1.0)
            let closed = !back.exists
            notes.append("   \(tool) 패널 닫힘=\(closed)")
            XCTAssertTrue(closed, "\(tool) 패널이 닫히지 않았다")
        }
        shot("R-자판-복귀")
    }

    /// ★ 사장님이 실기에서 찾은 경로 — 「하세요」에 배지가 뜨면 안 된다 (2026-09-21).
    /// 「하세」는 본문에 **6건이 실제로 걸린다.** 조사 결합 검사만이 이것을 막는다.
    func testHaseyoShowsNoBadge() throws {
        try prepare()
        clearAll()

        typeOnKeyboard("하세요")
        Thread.sleep(forTimeInterval: 1.5)
        let badge = keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "성경 구절 ")).firstMatch
        let appeared = badge.waitForExistence(timeout: 3)
        notes.append("★ H1 「하세요」 → 입력란 \(q(fieldValue())) / 배지 \(appeared ? q(badge.label) : "(없음)")")
        shot("H1-하세요-배지없음")
        XCTAssertFalse(appeared, "「하세요」에 배지가 떴다 — 말끝을 자르고 있다")

        // ★ 2026-09-21 개정 — 예전엔 여기서 「사랑해」가 폴백으로 떠야 했다.
        //   말끝 떼기를 없앴으므로 이제 「사랑해」도 0건이다(받아들인 손실).
        //   대신 **직접 친 낱말은 그대로 떠야 한다**는 것을 같은 실행에서 확인한다 —
        //   검색 기능 자체가 죽지 않았음을 보는 자리다.
        clearAll()
        typeOnKeyboard("사랑")
        Thread.sleep(forTimeInterval: 1.5)
        let good = badge.waitForExistence(timeout: 5)
        notes.append("★ H2 「사랑」 → 배지 \(good ? q(badge.label) : "(없음)")")
        shot("H2-사랑-배지있음")
        XCTAssertTrue(good, "직접 친 「사랑」까지 안 뜬다 — 검색이 통째로 죽었다")
    }

    private func prepare() throws {
        host.launch()
        dismissAllContinues()
        focusAddressField()
        dismissAllContinues()
        dismissAllContinues()
        bringUpGeulsoe()
        XCTAssertTrue(keyboard.waitForExistence(timeout: 10), "글쇠 익스텐션이 뜨지 않았다")
        // 자판이 한글 모드인지 확인 — 기호 페이지가 남아 있으면 첫 글자가 엉뚱하게 들어간다
        layer = .hangul
        returnToHangulIfNeeded()
    }

    /// 글쇠를 올린다 — **지구본은 길게**(탭은 다음 자판으로 순환할 뿐이다).
    private func bringUpGeulsoe() {
        if keyboard.exists { notes.append("글쇠가 이미 올라와 있다"); return }
        for attempt in 1...4 {
            springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.955))
                .press(forDuration: 0.9)
            Thread.sleep(forTimeInterval: 1.2)
            for app in [springboard, host] {
                guard let app else { continue }
                let item = app.staticTexts["글쇠"].firstMatch
                if item.waitForExistence(timeout: 2), item.isHittable { item.tap(); break }
            }
            Thread.sleep(forTimeInterval: 2.0)
            let allow = springboard.buttons["붙여넣기 허용"].firstMatch
            if allow.waitForExistence(timeout: 3) { allow.tap() }
            if keyboard.exists { notes.append("글쇠 올라옴 (\(attempt)회차)"); return }
        }
        notes.append("★ 글쇠를 올리지 못했다")
    }

    private func focusAddressField() {
        let any = host.textFields.firstMatch
        if any.waitForExistence(timeout: 8) { any.tap(); Thread.sleep(forTimeInterval: 1.5) }
        else { notes.append("주소창을 찾지 못했다") }
    }

    /// 사파리 첫 실행 안내 + 시스템 자판 소개 — 여럿이 겹쳐 뜬다.
    private func dismissAllContinues() {
        for _ in 0..<4 {
            var tapped = false
            for app in [host, springboard] {
                guard let app else { continue }
                for label in ["계속", "Continue"] {
                    let button = app.buttons[label].firstMatch
                    if button.exists, button.isHittable {
                        button.tap(); tapped = true
                        Thread.sleep(forTimeInterval: 0.8)
                        break
                    }
                }
                if tapped { break }
            }
            if !tapped { return }
        }
    }

    // MARK: - 입력란 비우기
    //
    // **호스트의 ✕ 로만 지우면 안 된다.** 우리 익스텐션의 꼬리(`committedTail`)는 우리 키
    // 이벤트로만 움직이므로, 호스트가 지운 것을 익스텐션은 모른다(위 탐침 표와 같은 이유).
    // 그래서 **우리 ⌫ 로 지운다** — 문서와 꼬리가 함께 준다.

    private func clearAll() {
        clearByBackspace()
    }

    private func clearByBackspace(limit: Int = 90) {
        var taps = 0
        while taps < limit {
            let remaining = fieldValue().count
            if remaining == 0 { break }
            let batch = min(remaining + 2, limit - taps, 12)
            for _ in 0..<batch { tapKey("지우기", settle: 0.06) }
            taps += batch
            Thread.sleep(forTimeInterval: 0.4)
        }
        if taps >= limit { notes.append("★ 지우기 \(limit)회로도 안 비었다: \(q(fieldValue()))") }
    }

    /// 호스트의 ✕ 로 지운다 — **꼬리는 그대로 남는다.** 탐침에서만 쓴다.
    private func clearHostField() {
        for label in ["텍스트 지우기", "Clear text", "지우기"] {
            let button = host.buttons[label].firstMatch
            if button.exists, button.isHittable { button.tap(); Thread.sleep(forTimeInterval: 0.6); return }
        }
    }

    // MARK: - ★ 두벌식 자판으로 실제로 치기

    private enum Layer { case hangul, symbols1, symbols2 }
    private var layer: Layer = .hangul

    /// 문자열을 **자판 키를 눌러서** 친다. 한글은 자모로 분해하고, 숫자·기호는 기호 페이지를 오간다.
    private func typeOnKeyboard(_ text: String) {
        for character in text { typeCharacter(character) }
    }

    private func typeCharacter(_ character: Character) {
        if character == " " {
            returnToHangulIfNeeded()
            tapKey("스페이스")
            return
        }
        if let strokes = Self.hangulStrokes(for: character) {
            returnToHangulIfNeeded()
            for stroke in strokes {
                if stroke.shifted { tapKey("시프트", settle: 0.12) }
                tapKey(stroke.label)
            }
            return
        }
        if Self.symbolsPage1.contains(String(character)) {
            switchTo(.symbols1)
            tapKey(String(character))
            return
        }
        if Self.symbolsPage2.contains(String(character)) {
            switchTo(.symbols2)
            tapKey(String(character))
            return
        }
        notes.append("★ 칠 수 없는 글자를 건너뛴다: \(q(String(character)))")
    }

    private func returnToHangulIfNeeded() {
        guard layer != .hangul else { return }
        tapKey("문자 자판", settle: 0.4)
        layer = .hangul
    }

    private func switchTo(_ target: Layer) {
        guard layer != target else { return }
        switch (layer, target) {
        case (.hangul, .symbols1):
            tapKey("기호", settle: 0.4)
        case (.hangul, .symbols2):
            tapKey("기호", settle: 0.4)
            tapKey("기호 더보기", settle: 0.4)
        case (.symbols1, .symbols2):
            tapKey("기호 더보기", settle: 0.4)
        case (.symbols2, .symbols1):
            tapKey("기호 첫 페이지", settle: 0.4)
        case (_, .hangul):
            tapKey("문자 자판", settle: 0.4)
        default:
            break
        }
        layer = target
    }

    /// 접근성 라벨로 키를 찾아 탭한다. 요소 종류는 빌드마다 다를 수 있어 넷을 차례로 본다.
    @discardableResult
    private func tapKey(_ label: String, settle: TimeInterval = 0.10) -> Bool {
        let candidates: [(String, XCUIElement)] = [
            ("keys", keyboard.keys[label].firstMatch),
            ("buttons", keyboard.buttons[label].firstMatch),
            ("staticTexts", keyboard.staticTexts[label].firstMatch),
            ("other", keyboard.otherElements[label].firstMatch)
        ]
        for (kind, element) in candidates where element.exists {
            element.tap()
            if !keyQueryNoted {
                notes.append("키 질의 종류: \(kind) (예: \(q(label)))")
                keyQueryNoted = true
            }
            if settle > 0 { Thread.sleep(forTimeInterval: settle) }
            return true
        }
        notes.append("★ 키를 못 찾았다: \(q(label))")
        return false
    }

    /// 한 글자를 두벌식 키 시퀀스로. 한글 음절·호환 자모만 처리하고 나머지는 nil.
    private static func hangulStrokes(for character: Character) -> [(label: String, shifted: Bool)]? {
        let scalar = character.unicodeScalars.first!
        // 완성형 음절 — 초·중·종으로 쪼갠다
        if (0xAC00...0xD7A3).contains(scalar.value) {
            let index = Int(scalar.value) - 0xAC00
            let cho = index / (21 * 28)
            let jung = (index % (21 * 28)) / 28
            let jong = index % 28
            var strokes = jamoStrokes(choseong[cho])
            strokes += jamoStrokes(jungseong[jung])
            if jong > 0 { strokes += jamoStrokes(jongseong[jong]) }
            return strokes
        }
        // 호환 자모 낱글자 (ㄱ~ㅎ, ㅏ~ㅣ)
        if (0x3131...0x3163).contains(scalar.value) {
            return jamoStrokes(String(character))
        }
        return nil
    }

    /// 자모 하나 → 키 시퀀스. 겹자모는 두 번 누른다(두벌식 규칙).
    private static func jamoStrokes(_ jamo: String) -> [(label: String, shifted: Bool)] {
        if let parts = compound[jamo] { return parts.flatMap(jamoStrokes) }
        if let base = shifted[jamo] { return [(base, true)] }
        return [(jamo, false)]
    }

    private static let choseong = ["ㄱ", "ㄲ", "ㄴ", "ㄷ", "ㄸ", "ㄹ", "ㅁ", "ㅂ", "ㅃ", "ㅅ",
                                   "ㅆ", "ㅇ", "ㅈ", "ㅉ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]
    private static let jungseong = ["ㅏ", "ㅐ", "ㅑ", "ㅒ", "ㅓ", "ㅔ", "ㅕ", "ㅖ", "ㅗ", "ㅘ",
                                    "ㅙ", "ㅚ", "ㅛ", "ㅜ", "ㅝ", "ㅞ", "ㅟ", "ㅠ", "ㅡ", "ㅢ", "ㅣ"]
    private static let jongseong = ["", "ㄱ", "ㄲ", "ㄳ", "ㄴ", "ㄵ", "ㄶ", "ㄷ", "ㄹ", "ㄺ",
                                    "ㄻ", "ㄼ", "ㄽ", "ㄾ", "ㄿ", "ㅀ", "ㅁ", "ㅂ", "ㅄ", "ㅅ",
                                    "ㅆ", "ㅇ", "ㅈ", "ㅊ", "ㅋ", "ㅌ", "ㅍ", "ㅎ"]

    /// 시프트를 눌러야 나오는 자모 → 시프트 없는 같은 자리 키
    /// (`LayoutDefinition.dubeolsik` 의 `shiftedLabel` 그대로).
    private static let shifted: [String: String] = [
        "ㄲ": "ㄱ", "ㄸ": "ㄷ", "ㅃ": "ㅂ", "ㅆ": "ㅅ", "ㅉ": "ㅈ", "ㅒ": "ㅐ", "ㅖ": "ㅔ"
    ]

    /// 두 키로 만드는 겹자모 (복모음·겹받침)
    private static let compound: [String: [String]] = [
        "ㅘ": ["ㅗ", "ㅏ"], "ㅙ": ["ㅗ", "ㅐ"], "ㅚ": ["ㅗ", "ㅣ"],
        "ㅝ": ["ㅜ", "ㅓ"], "ㅞ": ["ㅜ", "ㅔ"], "ㅟ": ["ㅜ", "ㅣ"], "ㅢ": ["ㅡ", "ㅣ"],
        "ㄳ": ["ㄱ", "ㅅ"], "ㄵ": ["ㄴ", "ㅈ"], "ㄶ": ["ㄴ", "ㅎ"],
        "ㄺ": ["ㄹ", "ㄱ"], "ㄻ": ["ㄹ", "ㅁ"], "ㄼ": ["ㄹ", "ㅂ"], "ㄽ": ["ㄹ", "ㅅ"],
        "ㄾ": ["ㄹ", "ㅌ"], "ㄿ": ["ㄹ", "ㅍ"], "ㅀ": ["ㄹ", "ㅎ"], "ㅄ": ["ㅂ", "ㅅ"]
    ]

    /// 기호 자판 1·2페이지 문자 — `LayoutDefinition.symbols` / `.symbolsAlternate` 그대로.
    private static let symbolsPage1 = Set("1234567890[]{}#%^*+=-/:;()₩&@\".,?!'".map(String.init))
    private static let symbolsPage2 = Set("_\\|~<>€£¥•※★☆♡♥♪→←↑↓°±×÷≠√∞·…✓".map(String.init))

    // MARK: - 관측

    /// 입력란 값. **사파리는 비어 있을 때 자리 표시자를 `value` 로 준다** — 그걸 빈 값으로 본다.
    /// (`PasteProbeTests` 도 같은 함정을 기록해 뒀다: "길이만 보면 속는다".)
    private func fieldValue() -> String {
        let raw = (host.textFields.firstMatch.value as? String) ?? ""
        return Self.placeholders.contains(raw) ? "" : raw
    }

    private static let placeholders: Set<String> = [
        "검색 또는 웹사이트 이름 입력", "Search or enter website name"
    ]

    /// 채움글 칩 — 접근성 라벨이 `채움글 … 붙여넣기` 로 시작한다.
    private func chipElement() -> XCUIElement {
        keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "채움글 ")).firstMatch
    }

    private func chipLabel(timeout: TimeInterval = 4) -> String {
        let chip = chipElement()
        guard chip.waitForExistence(timeout: timeout) else { return "(없음)" }
        return chip.label
    }

    @discardableResult
    private func tapChip() -> Bool {
        let chip = chipElement()
        guard chip.waitForExistence(timeout: 5) else { return false }
        chip.tap()
        return true
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        var count = 0
        var range = haystack.startIndex..<haystack.endIndex
        while let found = haystack.range(of: needle, range: range) {
            count += 1
            range = found.upperBound..<haystack.endIndex
        }
        return count
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// 첨부에 남길 때 앞뒤를 분명히 보이게 감싼다(공백이 끝에 있는지 눈으로 가른다).
    private func q(_ text: String) -> String { "«\(text)»" }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
