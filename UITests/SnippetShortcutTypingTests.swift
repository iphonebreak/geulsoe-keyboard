import XCTest
import TadakDomain

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
        var hardwareTypeTextChips: [String] = []
        for text in ["애국가 1절", "창 1:1", "우리집주소"] {
            clearByBackspace()
            host.typeText(text)
            Thread.sleep(forTimeInterval: 1.5)
            let label = chipLabel(timeout: 2)
            hardwareTypeTextChips.append(label)
            notes.append("typeText \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(label))")
        }
        shot("P1-하드웨어-타이핑")

        notes.append("— 자판 키 탭 경로 —")
        clearHostField()
        typeOnKeyboard("우리집주소")
        Thread.sleep(forTimeInterval: 1.0)
        let tapChipLabel = chipLabel()
        notes.append("자판 키 탭 «우리집주소» → 입력란 \(q(fieldValue())) / 칩 \(q(tapChipLabel))")
        shot("P2-자판키-탭")

        // ★ 단언 — **이 탐침의 두 결론을 둘 다 잠근다** (2026-09-22).
        //
        // 깨지려면: (가) 자판 탭이 익스텐션에 안 닿거나 매처가 죽었다 → **이 파일 전체가 무의미해진다**
        //           (나) `typeText`가 통하게 됐다 → **좋은 소식이다. 훨씬 싼 하네스로 갈아탈 때다**
        // 둘 다 사람이 알아야 하는 변화라 조용히 넘기지 않는다.
        XCTAssertNotEqual(tapChipLabel, "(없음)",
                          "자판 키 탭으로도 칩이 안 뜬다 — 이 하네스의 토대가 깨졌다")
        XCTAssertTrue(
            hardwareTypeTextChips.allSatisfy { $0 == "(없음)" },
            "★ 좋은 소식일 수 있다 — 하드웨어 typeText가 익스텐션에 닿기 시작했다면 "
                + "이 파일의 비싼 자판 탭 하네스를 typeText로 바꿀 수 있다. 결과: \(hardwareTypeTextChips)"
        )
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
            // 깨지려면: `SnippetEntry.normalizedTrigger`의 공백 무시가 깨졌다 —
            // 네 꼴 중 하나라도 안 뜨면 「띄어쓰기를 보지 않는다」는 계약이 거짓이 된다.
            XCTAssertTrue(label.contains(Fixture.homeTitle),
                          "\(item.0) \(q(item.1))에 칩이 안 떴다 — 칩 라벨 \(q(label))")
        }
        // ★ 「뒤 공백」 — **예전에 여기 적혀 있던 예측("안 뜨는 것이 설계다")은 틀렸다.**
        //   2026-09-16 실측: **칩이 뜬다.** 매처가 꼬리를 풀 때 공백을 통째로 건너뛰므로
        //   («우 리 집 주 소» 를 먹게 하는 바로 그 한 줄) 꼬리 끝 공백도 없는 것과 같다.
        //   탭까지 해서 본문만 깨끗이 들어가는 것은 `testTrailingSpaceChipInsertsCleanly` 가 본다.
        clearAll()
        typeOnKeyboard("우리집주소 ")
        Thread.sleep(forTimeInterval: 0.8)
        let trailing = chipLabel(timeout: 4)
        notes.append("★ D5 뒤에-공백 «우리집주소 » → 칩 \(q(trailing)) "
                     + "(**뜨는 것이 맞다** — 띄어쓰기 무시 설계의 당연한 귀결)")
        shot("D5-뒤에-공백")
        // 깨지려면: 꼬리 끝 공백을 매처가 다시 보기 시작했다(2026-09-16 실측을 뒤집는 변화다).
        XCTAssertTrue(trailing.contains(Fixture.homeTitle),
                      "뒤 공백에서 칩이 사라졌다 — 실측으로 확정한 동작이 바뀌었다")
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
        // 깨지려면: 지울 구간이 꼬리 끝 공백을 **빼먹었다**. 그러면 본문 뒤에 공백이 남거나
        // 단축어 글자가 남는다 — 사용자 문서가 더러워지는 실패다.
        XCTAssertTrue(tapped, "칩을 못 눌렀다 — 삽입 경로를 아예 못 봤다")
        XCTAssertEqual(after, Fixture.homeBody,
                       "뒤 공백이 있는 꼬리에서 본문만 깨끗이 들어가지 않았다")
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
        // 깨지려면: 지울 길이가 **정규화 길이(5자)**로 돌아갔다. 6자를 쳤는데 5자만 지우면
        // 본문 앞에 「우」가 남는다 — CLAUDE.md가 ★로 못박은 그 회귀다.
        XCTAssertTrue(tapped, "칩을 못 눌렀다")
        XCTAssertEqual(after, expected, "6자를 쳤는데 6자가 지워지지 않았다")
        XCTAssertFalse(after.contains("우" + Fixture.homeBody.prefix(3)),
                       "본문 앞에 단축어 잔재 「우」가 남았다")
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
        // 깨지려면: `InputController.insertSnippet`의 꼬리 정합 검사(2중 방어)가 뚫렸다.
        // 두 번째 탭이 들어가면 본문 **끝이 잘려 나간다**(QA BLOCK-2) — 문서 훼손이다.
        XCTAssertEqual(after, Fixture.dupBody, "두 번 탭에 본문이 잘리거나 두 번 들어갔다")
        XCTAssertEqual(occurrences(of: Fixture.dupBody, in: after), 1, "본문이 1회가 아니다")
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
            let label = chipLabel()
            notes.append("★ G\(index + 1) \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(label))")
            shot("G\(index + 1)")
            // 깨지려면: 내장 팩(`Snippets.json`)이 안 실리거나 팩이 꺼졌다 —
            // 사용자 문구만 되고 내장 팩이 죽는 회귀를 여기서 잡는다.
            XCTAssertNotEqual(label, "(없음)", "내장 팩 \(q(text))에 칩이 안 떴다")
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
            let label = chipLabel()
            notes.append("★ H\(index + 1) \(q(text)) → 입력란 \(q(fieldValue())) / 칩 \(q(label))")
            shot("H\(index + 1)")
            // 깨지려면: 성경 **참조 파서**(주소 단축어)가 깨졌다. 이번 v1.1.0 변경은
            // 키워드 검색을 더한 것이지 주소 경로를 건드린 것이 아니므로 **무변화여야 한다.**
            XCTAssertNotEqual(label, "(없음)", "성경 주소 \(q(text))에 칩이 안 떴다")
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
    /// ★ **시간 수치는 계측이고 판정이 아니다** — 단언하는 것은 *매칭이 되는가/안 되는가* 둘뿐이다.
    ///   중앙값·최소값은 첨부(`notes.txt`)로만 남기고, 빠름·느림은 사람이 본다.
    func testChipLatency() throws {
        try prepare()
        // 매칭이 **성공**하는 꼬리와 **실패**하는 꼬리를 나눠 잰다.
        // 실패 쪽이 최악이다 — 성공하면 정렬된 첫 매치에서 멈추지만 실패하면 전부 훑는다.
        var hits: [Double] = []
        var misses: [Double] = []
        var missFired = false

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
            // 깨지려면: 단축어가 100개일 때 매칭이 **10초 안에도 안 끝나거나** 아예 실패한다.
            // 시간 자체는 단언하지 않는다 — 탭 합성 왕복이 섞여 있어 문턱을 정하면 깜빡인다.
            XCTAssertTrue(appeared, "round\(round)에서 칩이 10초 안에 안 떴다")
            missFired = false
        }

        for round in 1...5 {
            clearAll()
            typeOnKeyboard("바다하나무자")         // 어떤 단축어에도 안 맞는 꼬리
            let start = Date()
            typeOnKeyboard("라")
            // 칩이 안 뜨는 것이 정상 — 마지막 키 탭이 끝나 제어가 돌아오는 시점까지를 잰다
            let elapsed = Date().timeIntervalSince(start)
            misses.append(elapsed)
            // ★ **여기에 진짜 검사력이 있다** — 어떤 단축어에도 안 맞는 꼬리에 칩이 뜨면
            //   매처가 아무 데나 발동하는 것이다(짧은 단축어가 줄을 넘어 붙던 것과 같은 종류).
            let leaked = chipElement().waitForExistence(timeout: 1.0)
            if leaked { missFired = true }
            notes.append(String(format: "★ LAT miss round%d %.3fs 칩=%@",
                                round, elapsed, leaked ? "★떴다" : "없음"))
            XCTAssertFalse(leaked, "round\(round): 안 맞는 꼬리에 칩이 떴다")
        }

        notes.append(String(format: "★ LAT 요약 hit 중앙값=%.3fs 최소=%.3fs / miss 중앙값=%.3fs 최소=%.3fs",
                            median(hits), hits.min() ?? 0, median(misses), misses.min() ?? 0))
        shot("I1-성능")
        // ★ **시간은 계측이지 판정이 아니다.** 「몇 초부터 느린가」는 사람이 정한다 —
        //   탭 합성 왕복이 섞여 있어 문턱을 걸면 깜빡인다.
        //
        // ★ 예전에는 여기서 `hits.count == 5`·`misses.count == 5`를 단언했다.
        //   **검사력이 0이었다** — 루프가 1...5를 분기 없이 `append`하므로 프로덕션이 무엇이
        //   깨져도 통과한다(검증자 지적 2026-09-23). 그런데 보고서 표는 그것을
        //   「표본 5·5」라는 검사력 있는 단언처럼 셌다. 그 오해를 코드가 막아야 한다.
        //
        // 그래서 **세는 단언을 지우고**, 실제로 프로덕션을 잡는 둘만 남겼다:
        //   - hit 루프의 `XCTAssertTrue(appeared)`  — 100개에서도 매칭이 끝나는가
        //   - miss 루프의 `XCTAssertFalse(leaked)`  — 안 맞는 꼬리에 뜨지 않는가
        XCTAssertFalse(missFired, "안 맞는 꼬리에 칩이 한 번이라도 떴다 — 매처가 아무 데나 발동한다")
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
        let badge = bibleBadge()
        let hasBadge = badge.waitForExistence(timeout: 5)
        notes.append("★ B1 「사랑」 → 입력란 \(q(fieldValue())) / 배지 \(hasBadge ? q(badge.label) : "(없음)")")
        shot("B1-배지")
        XCTAssertTrue(hasBadge, "배지가 뜨지 않았다")

        // 2) 패널
        badge.tap()
        Thread.sleep(forTimeInterval: 1.2)
        let back = keyboard.buttons[BibleSearchText.backToKeyboardLabel].firstMatch
        let opened = back.waitForExistence(timeout: 5)
        notes.append("★ B2 패널 열림=\(opened)")
        XCTAssertTrue(opened, "배지를 눌렀는데 패널이 안 열렸다")

        // 3) 책 필터 — **줄 전체가 하나의 조절 가능한 요소다**
        //
        // ## ★ 옛 술어 둘이 잘못돼 있었다 (2026-09-22 검증자 실측)
        //
        // - `label BEGINSWITH "전체 "`(뒤 공백) → 안 걸렸다. 칩 하나하나는 **접근성 트리에 없다** —
        //   `.accessibilityElement(children: .ignore)`로 줄 전체가 한 요소가 됐기 때문이다
        // - `label CONTAINS "건"` → **배지를 잡았다**(배지 낭독이 「…517건…」이다).
        //   그래서 notes에 `책 탭 1개: 단어로 구절 찾기, 517건, 목록 열기`가 찍혔다
        //
        // 둘 다 **문자열을 박아서** 난 고장이다. 이제 라벨을 `TadakDomain`에서 읽는다 —
        // 프로덕션(`BibleSearchPanelView`)이 그리는 값과 **같은 출처**다.
        //
        // 버튼이 아니라 `descendants(matching: .any)`로 찾는다 — 조절 가능한 요소의
        // XCUIElement 종류는 플랫폼이 정하고, 우리가 거기 기대면 또 깨진다.
        let filterBar = keyboard.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", BibleSearchText.bookFilterLabel)).firstMatch
        let hasFilterBar = filterBar.waitForExistence(timeout: 4)
        let filterValue = hasFilterBar ? ((filterBar.value as? String) ?? "") : ""
        notes.append("   책 거르개 있음=\(hasFilterBar) 값=\(q(filterValue))")
        shot("B2-패널")

        // 깨지려면: 책 필터 줄이 접근성 트리에서 사라졌거나(VoiceOver 사용자가 책을 못 바꾼다)
        // 읽어 주는 값이 「전체」로 시작하지 않는다(어느 책을 보고 있는지 안 들린다).
        XCTAssertTrue(hasFilterBar, "패널에 책 거르개가 없다 — VoiceOver로 책을 바꿀 길이 사라졌다")
        XCTAssertTrue(
            filterValue.hasPrefix(BibleSearchText.allBooksName),
            "책 거르개 값이 \(q(BibleSearchText.allBooksName))로 시작하지 않는다: \(q(filterValue))"
        )
        // 배지를 잡고 있지 않다는 것도 분명히 한다 — 옛 술어가 정확히 그 실수를 했다
        XCTAssertFalse(
            filterValue.hasPrefix(ToolbarTool.bibleBadgeLabelPrefix),
            "책 거르개 자리에서 배지를 잡았다 — 술어가 또 어긋났다"
        )

        // 4) 구절 탭 → 기존 삽입 경로
        let verse = keyboard.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", ":")).firstMatch
        let hasVerse = verse.waitForExistence(timeout: 3)
        if hasVerse {
            notes.append("★ B4 고른 행 \(q(verse.label))")
            verse.tap()
            Thread.sleep(forTimeInterval: 1.5)
            notes.append("   삽입 뒤 입력란 \(q(fieldValue()))")
        } else {
            notes.append("★ B4 구절 행을 못 찾았다")
        }
        shot("B4-삽입-뒤")
        // 깨지려면: 패널이 열렸는데 구절 행이 하나도 안 그려졌다 — 결과를 받고도 못 보여 주는 상태다.
        XCTAssertTrue(hasVerse, "패널에 구절 행이 없다")
    }

    /// ★ **이 시험은 더 이상 돌 수 없다 — 대상이 사라졌다** (2026-09-22 확인).
    ///
    /// 원래 보던 것: 패널 머리의 `검색어 ✕`가 **친 글자 전체**를 지우는가(계획서 2-7 N-4).
    ///
    /// **그 칩과 ✕가 2026-09-21에 사용자 지시로 삭제됐다**
    /// (`docs/design-reviews/bible-panel-query-chip-removal.md` —
    /// *「형광펜 기능 때문에 패널 안에서 칩은 안나와도 될거 같다 없애라」*).
    /// 프로덕션 전수 `grep`에서 **「검색어 지우기」 버튼은 0건**이다.
    ///
    /// ## ★ 그래서 거짓 초록이 아니라 **항상 실패**하는 시험이었다
    ///
    /// 본문이 `guard clear.waitForExistence else { return XCTFail(...) }`라 **반드시 실패한다.**
    /// 조용히 통과하는 것보다는 낫지만, 검증자가 돌릴 때마다 **사라진 기능 때문에 빨간불**이 켜져
    /// 진짜 실패를 가린다.
    ///
    /// **지우지 않고 건너뛴다.** 이 시험이 지키던 계약(*✕가 친 낱말 전체를 지운다*)이
    /// 언제 왜 없어졌는지가 다음 사람에게 필요한 정보이고, 파일에서 없애면 그 기록이 사라진다.
    ///
    /// 남은 ✕(툴바 `후보 닫기`)는 **글자를 지우지 않는다** — 배지와 후보를 내릴 뿐이다
    /// (`KeyboardViewController.handleDismissSuggestions`). 그건 다른 계약이라 여기서 안 본다.
    func testBibleSearchQueryDeleteRemovesTypedWord() throws {
        throw XCTSkip(
            "패널 검색어 칩과 ✕가 2026-09-21 사용자 지시로 삭제됐다 "
                + "(bible-panel-query-chip-removal.md). 프로덕션에 「검색어 지우기」 버튼이 없다 — "
                + "되살아나면 이 skip을 지우고 본문을 복원하라."
        )
    }

    /// 기존 패널 회귀 — 성경 패널을 끼워 넣어도 **이모지·클립보드가 그대로 열리고 닫히는가.**
    /// 패널 분기에서 성경이 앞에 있어 상호 배제가 깨지면 여기서 잡힌다.
    func testExistingPanelsStillWork() throws {
        try prepare()
        clearAll()
        Thread.sleep(forTimeInterval: 0.8)

        // ★ 옛 판은 **둘 다 못 찾아도 통과**했다 — `continue`만 하고 끝났다(검증자 지적).
        //   이제 「몇 개를 실제로 확인했는가」를 세고, 이모지는 **반드시** 있어야 한다.
        //   이모지는 전체 접근이 필요 없고(`worksWithoutFullAccess`) 기본으로 켜져 있다.
        //   클립보드는 권한에 달렸으므로 없으면 **건너뛴다고 말한다.**
        var exercised = 0
        for tool in [ToolbarTool.emoji, .clipboard] {
            let name = tool.displayName
            let button = keyboard.buttons[name].firstMatch
            guard button.waitForExistence(timeout: 4) else {
                notes.append("★ R 도구 «\(name)» 이 도구 행에 없다 (설정·권한으로 숨겨졌을 수 있다)")
                XCTAssertNotEqual(
                    tool, .emoji,
                    "이모지가 도구 행에 없다 — 권한과 무관한 도구라 숨겨질 이유가 없다"
                )
                continue
            }
            exercised += 1
            button.tap()
            Thread.sleep(forTimeInterval: 1.0)
            let back = keyboard.buttons[BibleSearchText.backToKeyboardLabel].firstMatch
            let opened = back.waitForExistence(timeout: 4)
            notes.append("★ R \(name) 패널 열림=\(opened)")
            shot("R-\(name)-열림")
            XCTAssertTrue(opened, "\(name) 패널이 열리지 않았다")
            back.tap()
            Thread.sleep(forTimeInterval: 1.0)
            let closed = !back.exists
            notes.append("   \(name) 패널 닫힘=\(closed)")
            XCTAssertTrue(closed, "\(name) 패널이 닫히지 않았다")
        }
        shot("R-자판-복귀")
        notes.append("★ R 실제로 확인한 도구 \(exercised)개")
        // 깨지려면: 도구 행이 통째로 안 나왔다 — 성경 패널을 끼우며 상호 배제가 깨진 경우다.
        // **이 한 줄이 없어서 「도구를 못 찾아도 통과」했다.**
        XCTAssertGreaterThan(exercised, 0, "도구를 하나도 확인하지 못했다 — 도구 행이 없었다")
    }

    /// ★ 사장님이 실기에서 찾은 경로 — 「하세요」에 배지가 뜨면 안 된다 (2026-09-21).
    /// 「하세」는 본문에 **6건이 실제로 걸린다.** 조사 결합 검사만이 이것을 막는다.
    func testHaseyoShowsNoBadge() throws {
        try prepare()
        let badge = bibleBadge()

        // ── ★ 양성 대조를 **먼저** 한다 (2026-09-22 구조 수정)
        //
        // 아래 `XCTAssertFalse`는 **「배지가 없다」와 「배지를 못 찾는다」를 구별하지 못한다.**
        // 술어가 틀리면 아무것도 안 걸려서 **그대로 통과**한다 — 실제로 그런 일이 있었다
        // (이름이 「성경 구절」 → 「단어로 구절 찾기」로 바뀌는 동안 술어가 안 따라왔다).
        //
        // 그래서 **먼저 이 술어로 진짜 배지를 잡아 본다.** 여기가 통과해야만 아래의 「없다」가
        // 뜻을 가진다. 순서를 뒤집으면 안 된다 — 뒤에 두면 앞의 거짓 통과를 못 막는다.
        clearAll()
        typeOnKeyboard("사랑")
        Thread.sleep(forTimeInterval: 1.5)
        let control = badge.waitForExistence(timeout: 5)
        notes.append("★ H0 양성 대조 「사랑」 → 배지 \(control ? q(badge.label) : "(없음)")")
        shot("H0-대조-사랑-배지있음")
        XCTAssertTrue(
            control,
            "양성 대조 실패 — 이 술어로는 배지를 찾을 수 없다. "
                + "아래 「하세요에 배지 없음」은 판정할 수 없으므로 여기서 멈춘다"
        )
        // 대조가 깨졌으면 아래는 의미가 없다. 거짓 초록을 만들지 않고 끝낸다.
        guard control else { return }

        // ── 본 판정: 「하세요」에는 배지가 뜨면 안 된다
        clearAll()
        typeOnKeyboard("하세요")
        Thread.sleep(forTimeInterval: 1.5)
        let appeared = badge.waitForExistence(timeout: 3)
        notes.append("★ H1 「하세요」 → 입력란 \(q(fieldValue())) / 배지 \(appeared ? q(badge.label) : "(없음)")")
        shot("H1-하세요-배지없음")
        XCTAssertFalse(appeared, "「하세요」에 배지가 떴다 — 말끝을 자르고 있다")
    }

    /// 성경 검색 배지 — **접근성 라벨의 앞부분으로** 찾는다.
    ///
    /// ## ★ 문자열을 박지 않는다 (2026-09-22)
    ///
    /// 예전에는 세 자리가 각각 `"성경 구절 "`을 박고 있었다. 도구 이름이
    /// 「성경 구절」 → 「구절 찾기」 → **「단어로 구절 찾기」**로 두 번 바뀌는 동안
    /// **UITests만 안 따라와** 배지를 못 찾았고, 그 때문에 형광펜 8조합을 아예 못 쟀다
    /// (패널을 열려면 배지를 탭해야 한다).
    ///
    /// 그래서 이름을 **도메인에서 읽는다.** 프로덕션 라벨은
    /// `KeyboardUI.BibleCountText.badgeAccessibilityLabel(count:)`이 만들고,
    /// 둘이 같은 앞부분을 쓰는지는 `BibleBadgeLabelTests`가 **`swift test`에서** 지킨다 —
    /// UITests는 앱을 실제로 실행해야 해서(Firebase 수집) 아무 때나 못 돌린다.
    private func bibleBadge() -> XCUIElement {
        keyboard.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", ToolbarTool.bibleBadgeLabelPrefix)
        ).firstMatch
    }

    // MARK: - ★ 오탭 겹침 계측 (검증자 차단 #5, 2026-09-22)

    /// 배지가 **옆 도구를 몇 % 덮는가**를 실기에서 재기 위한 **자료 수집** 테스트.
    ///
    /// ## 왜 이것이 없으면 못 재나
    ///
    /// 겹침은 「배지가 없을 때 그 도구가 있던 자리」와 「배지가 있을 때 배지가 차지한 자리」를
    /// **겹쳐 봐야** 나온다. 그런데 **도구 행만 있는 화면을 남기는 테스트가 하나도 없었다** —
    /// 기존 성경 테스트는 전부 배지를 **탭해서 패널을 여는** 흐름이라 도구 행이 화면에 안 남는다.
    ///
    /// ## ★ 「도구 행 + 배지」를 만드는 법 — 스페이스 한 번이다
    ///
    /// 도구 행은 후보가 **하나도 없을 때만** 뜬다(`KeyboardMetrics.showsDismissButton`).
    /// 「사랑」만 치면 **추천단어가 함께 떠서** 도구 행이 안 나온다.
    ///
    /// **✕로 추천단어를 내리는 길은 막혀 있다** — `handleDismissSuggestions`가
    /// *"배지도 함께 내린다"*며 `dismissedBibleTail`을 세운다. 후보 행을 통째로 내리는
    /// 버튼이라 그게 맞는 동작이고, 그래서 ✕로는 이 상태에 못 간다.
    ///
    /// 대신 **낱말 뒤에 스페이스 한 번**을 친다:
    /// - `currentWord`(마지막 한글 run)가 **빈 문자열**이 되어 추천단어가 0개다
    /// - 캐스케이드는 꼬리를 낱말로 쪼개 찾으므로 **「사랑」을 그대로 찾는다** → 배지가 남는다
    ///
    /// 둘 다 `swift test`로 미리 확인하고 이 테스트를 썼다(꼬리 `"사랑 "` →
    /// `currentWord == ""` · `matchedQuery == "사랑"`).
    ///
    /// ## ★ 남기는 것 — 도구 **이름과 좌표뿐**이다
    ///
    /// 보안 규칙 1순위(사용자 입력 텍스트를 로그·파일·네트워크로 내보내지 않는다)를 따른다.
    /// CSV에는 **입력란 내용도 문서 문맥도 담지 않는다.** 도구 이름은
    /// `ToolbarTool.displayName`에서 읽는다 — 오늘 문자열 박기 때문에 술어 3곳이 깨졌다.
    ///
    /// ## 검증자에게
    ///
    /// 이 테스트는 **판정하지 않는다.** 수치를 남길 뿐이고 임계값을 단언하지 않는다 —
    /// 「몇 %부터 위험한가」는 제품 판단이라 사람이 정한다.
    func testToolRowGeometryForMistapOverlap() throws {
        try prepare()

        // ── A) 배지 없음 — 빈 입력란
        clearAll()
        // 붙여넣기 칩이 떠 있으면 후보가 있는 것이라 도구 행이 안 나온다.
        // **지금 지운다** — 입력란이 비어 있어 내릴 배지가 없으므로 ✕가 안전하다.
        dismissCandidatesIfAny()
        Thread.sleep(forTimeInterval: 0.8)
        let noBadge = captureToolRow(state: "A")
        shot("G-A-도구행-배지없음")

        // ── B) 배지 있음 — 낱말 + **스페이스 한 번**
        typeOnKeyboard("사랑 ")
        Thread.sleep(forTimeInterval: 1.8)
        let withBadge = captureToolRow(state: "B")
        shot("G-B-도구행-배지있음")

        // ── 기록
        var rows: [String] = ["section,state,name,label,x,y,w,h,hittable"]
        rows.append(contentsOf: noBadge.rows)
        rows.append(contentsOf: withBadge.rows)

        rows.append("")
        rows.append("section,tool,center_shift_pt,overlap_pt,overlap_pct,a_w,badge_w")
        if let badge = withBadge.badge {
            for (name, before) in noBadge.tools {
                let after = withBadge.tools[name]
                let shift = after.map { $0.midX - before.midX }
                let overlap = max(0, min(before.maxX, badge.maxX) - max(before.minX, badge.minX))
                let pct = before.width > 0 ? overlap / before.width * 100 : 0
                rows.append(String(
                    format: "overlap,%@,%@,%.2f,%.1f,%.2f,%.2f",
                    name,
                    shift.map { String(format: "%.2f", $0) } ?? "(사라짐)",
                    overlap, pct, before.width, badge.width
                ))
            }
        } else {
            rows.append("overlap,(배지 없음 — B 상태를 못 만들었다),,,,,")
        }

        let csv = XCTAttachment(string: rows.joined(separator: "\n"))
        csv.name = "toolrow-geometry.csv"
        csv.lifetime = .keepAlways
        add(csv)

        notes.append("— 오탭 겹침 계측 —")
        notes.append("A(배지없음) 도구 \(noBadge.tools.count)개 / B(배지있음) 도구 \(withBadge.tools.count)개")
        notes.append("배지 \(withBadge.badge.map { String(format: "폭 %.2fpt", $0.width) } ?? "(없음)")")
        notes.append("수치는 첨부 toolrow-geometry.csv 에 있다")

        // 자료가 실제로 모였는지만 지킨다 — **겹침 %를 단언하지 않는다**(제품 판단이다).
        XCTAssertFalse(noBadge.tools.isEmpty, "A 상태에서 도구 행이 없다 — 후보가 떠 있었을 수 있다")
        XCTAssertNotNil(
            withBadge.badge,
            "B 상태에 배지가 없다 — 「사랑 」 꼬리로 배지가 떠야 한다(성경 검색이 꺼져 있는지 확인)"
        )
        XCTAssertFalse(
            withBadge.tools.isEmpty,
            "B 상태에서 도구 행이 없다 — 스페이스로 추천단어가 안 사라졌다"
        )
    }

    /// 도구 행 한 컷 — **우리 도구와 배지만** 찾아 좌표를 적는다.
    ///
    /// `keyboard.buttons`를 통째로 훑지 않는다. 자판 키·호스트 버튼까지 섞이고,
    /// 그중에는 **사용자가 친 글자가 라벨인 키**가 있어 남기면 안 된다.
    private func captureToolRow(state: String) -> ToolRowShot {
        var tools: [String: CGRect] = [:]
        var rows: [String] = []

        let screen = keyboard.frame
        rows.append(String(format: "frame,%@,screen,,%.2f,%.2f,%.2f,%.2f,", state,
                           screen.minX, screen.minY, screen.width, screen.height))

        for tool in ToolbarTool.allCases where tool != .bibleSearch {
            let button = keyboard.buttons[tool.displayName].firstMatch
            guard button.exists else { continue }
            let f = button.frame
            tools[tool.displayName] = f
            rows.append(String(format: "frame,%@,tool,%@,%.2f,%.2f,%.2f,%.2f,%@", state,
                               tool.displayName, f.minX, f.minY, f.width, f.height,
                               button.isHittable ? "yes" : "no"))
        }

        // 배지는 라벨이 문장이라 이름으로 못 찾는다 — 같은 앞부분 술어를 쓴다
        var badge: CGRect?
        let badgeElement = bibleBadge()
        if badgeElement.exists {
            let f = badgeElement.frame
            badge = f
            rows.append(String(format: "frame,%@,badge,%@,%.2f,%.2f,%.2f,%.2f,%@", state,
                               badgeElement.label, f.minX, f.minY, f.width, f.height,
                               badgeElement.isHittable ? "yes" : "no"))
        }

        // ✕가 있으면 후보가 떠 있다는 뜻 — 도구 행 상태가 아니었다는 신호다
        let dismiss = keyboard.buttons["후보 닫기"].firstMatch
        if dismiss.exists {
            let f = dismiss.frame
            rows.append(String(format: "frame,%@,dismiss,후보 닫기,%.2f,%.2f,%.2f,%.2f,", state,
                               f.minX, f.minY, f.width, f.height))
        }

        return ToolRowShot(tools: tools, badge: badge, rows: rows)
    }

    private struct ToolRowShot {
        let tools: [String: CGRect]
        let badge: CGRect?
        let rows: [String]
    }

    /// 후보(붙여넣기 칩 등)가 떠 있으면 내린다. **입력란이 빈 상태에서만 불러라** —
    /// ✕는 배지도 함께 내리므로 배지가 있을 때 누르면 만들려던 상태가 사라진다.
    private func dismissCandidatesIfAny() {
        let dismiss = keyboard.buttons["후보 닫기"].firstMatch
        guard dismiss.exists, dismiss.isHittable else { return }
        dismiss.tap()
        notes.append("★ A 상태에서 후보 ✕를 눌러 도구 행을 냈다(붙여넣기 칩으로 보인다)")
        Thread.sleep(forTimeInterval: 0.6)
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
