import XCTest
import TadakDomain

/// 가로 방향 자판 치수 계측 하네스 (IP-2 계열).
///
/// ## 왜 시스템 앱을 호스트로 쓰는가 — 두 가지를 동시에 푼다
///
/// 1. **컨테이너 앱을 띄우지 않는다.** Firebase 도입(2026-09-11) 뒤로 `Tadak`을 실행하면
///    `FirebaseApp.configure()`가 돌아 실제 데이터가 나간다. 익스텐션에는 Firebase가
///    **0바이트**이므로(`docs/release/firebase-integration.md` 2절 증명) 시스템 앱 입력란에
///    글쇠를 띄우면 우리 자판을 **방출 0으로** 계측할 수 있다.
///    실증: 이 테스트를 돌린 전후로 앱 컨테이너의 `google-heartbeat-storage` mtime이 **바뀌지 않았다**
///    (그 파일은 `FirebaseApp.configure()`만이 건드린다 — 2026-09-11 실측).
///    → 이 파일은 인자 없는 `XCUIApplication()`을 **절대 쓰지 않는다.** 그것이 우리 앱을 띄운다.
///      (`TEST_TARGET_NAME`이 설정돼 있어 러너는 자동으로 띄우지 않는다 — 띄우는 것은 명시 호출뿐이다.)
///
/// 2. **좌표 변환이 필요 없다.** 90도 회전에서 `simctl` 스크린숏 프레임과 탭 좌표가 어긋나
///    좌표 기반 자동화가 막혔다(검증자 실측 2026-09-11). XCUITest는 **요소로 접근**하므로
///    그 문제가 아예 생기지 않는다.
///
/// ## 무엇을 남기는가
///
/// 판정은 사람이 첨부를 본다. 이 테스트는 **실패시키지 않고** 치수와 스크린숏을 첨부한다 —
/// 수용 기준(예: 종횡비 < 2.95:1)은 라운드마다 달라지므로 여기에 박지 않는다.
final class LandscapeKeyboardMetricsTests: XCTestCase {

    /// 호스트. **우리 앱이 아니다.** 위 1번 참조.
    private var host: XCUIApplication!
    private var metrics: [String: Any] = [:]

    override func setUpWithError() throws {
        continueAfterFailure = false
        // **Safari다. 설정 앱이 아니다.** 아이폰 설정 앱은 가로를 지원하지 않아 회전이 걸리지 않는다
        // (실측 2026-09-11). Safari는 가로를 지원하고 주소창이 텍스트 입력란이라 자판을 띄운다.
        // 어느 쪽이든 **우리 앱이 아니라는 것**이 핵심이다 — 방출 0.
        host = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        host.launch()
    }

    override func tearDownWithError() throws {
        // 방향을 원래대로 — 다음 테스트·다음 세션이 가로 상태를 물려받지 않게.
        XCUIDevice.shared.orientation = .portrait
        if !metrics.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]) {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "metrics.json"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        host = nil
    }

    /// 가로에서 자판을 띄우고 키보드 프레임과 키 치수를 남긴다.
    func testLandscapeKeyboardMetrics() throws {
        XCUIDevice.shared.orientation = .landscapeLeft
        // 회전 자체를 단언하지 않는다 — 호스트가 가로를 지원하는지는 기기·앱마다 다르고,
        // 이 하네스는 판정하지 않고 **관측만** 한다. 실제 프레임은 아래 record가 남긴다.
        metrics["device.orientation"] = XCUIDevice.shared.orientation.rawValue

        dismissFirstRunDialogIfPresent()
        try focusSearchField()

        // **서드파티 자판은 호스트의 `keyboards`로 안 잡힌다.** 익스텐션이 별도 프로세스라
        // 호스트 앱의 접근성 트리에 들어오지 않는다(실측 2026-09-11: 화면에는 글쇠가 떠 있는데
        // `host.keyboards.element`가 15초 동안 exists=false).
        // 익스텐션을 **자기 번들 ID로** 잡으면 요소가 보인다.
        // 좌표는 익스텐션 창 로컬로 보고되지만(`docs/simulator-input-verification.md`),
        // **종횡비는 원점 오프셋에 영향받지 않으므로** 이 하네스 목적에는 충분하다.
        let keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
        XCTAssertTrue(keyboard.waitForExistence(timeout: 15), "글쇠 익스텐션 요소를 찾지 못했다")

        record(keyboard: keyboard, stage: "first")
        attachScreenshot(named: "01-landscape-first")

        // 글쇠가 이미 마지막 사용 자판이면 바로 뜬다. 아니면 지구본을 돈다.
        try switchToGeulsoe(maxHops: 6)
        record(keyboard: keyboard, stage: "geulsoe")
        recordKeyPitch(keyboard: keyboard, stage: "geulsoe")
        attachScreenshot(named: "02-landscape-geulsoe")
    }

    // MARK: - 단계

    /// Safari 첫 실행 안내("Safari 검색은 이제 …")가 뜨면 닫는다.
    /// 이게 떠 있으면 주소창 탭을 먹어 자판이 뜨지 않는다(실측 2026-09-11).
    private func dismissFirstRunDialogIfPresent() {
        for label in ["계속", "Continue"] {
            let button = host.buttons[label]
            if button.waitForExistence(timeout: 3) {
                button.tap()
                metrics["firstRunDialog"] = label
                return
            }
        }
    }

    private func focusSearchField() throws {
        // 주소창. 요소로 찾는다 — 좌표를 쓰지 않는다.
        // Safari는 버전·로케일에 따라 searchField로도 textField로도 노출돼 둘 다 본다.
        let search = host.searchFields.firstMatch
        let text = host.textFields.firstMatch
        let field = search.waitForExistence(timeout: 5) ? search : text
        XCTAssertTrue(field.waitForExistence(timeout: 10), "주소창을 찾지 못했다")
        field.tap()
    }

    /// 글쇠가 나올 때까지 지구본을 돈다. 찾으면 `true`.
    ///
    /// 왜 횟수 제한을 두는가: 활성 자판 구성은 기기마다 다르고, 글쇠가 꺼져 있으면 영원히 돈다.
    /// 그때는 **실패시키지 않고** 어디까지 돌았는지 남긴다 — 하네스가 판정하지 않는다는 원칙.
    @discardableResult
    private func switchToGeulsoe(maxHops: Int) throws -> Bool {
        var seen: [String] = []
        for hop in 0..<maxHops {
            let keyboard = XCUIApplication(bundleIdentifier: "com.charging.tadak.keyboard")
            guard keyboard.exists else { break }
            // 글쇠는 툴바에 우리 도구를 갖고 있다 — 이름은 **도메인에서 읽는다.**
            //
            // ★ 예전에는 "왼쪽으로 커서 이동"을 박아 뒀는데 2026-09-22에 「좌측 커서 이동」으로
            //   바뀌면서 **죽은 분기**가 됐다(「키보드 내리기」가 우연히 살아 있어 안 들켰다).
            //   같은 종류의 고장이 `SnippetShortcutTypingTests`에서는 실제로 검증을 막았다.
            if keyboard.buttons[ToolbarTool.dismiss.displayName].exists
                || keyboard.buttons[ToolbarTool.cursorLeft.displayName].exists {
                metrics["switch.hops"] = hop
                metrics["switch.seen"] = seen
                return true
            }
            seen.append(keyboard.identifier)
            let globe = keyboard.buttons["다음 키보드"]
            guard globe.exists else { break }
            globe.tap()
            _ = keyboard.waitForExistence(timeout: 3)
        }
        metrics["switch.hops"] = -1
        metrics["switch.seen"] = seen
        metrics["switch.note"] = "글쇠를 찾지 못했다 — 이 기기에서 글쇠가 켜져 있는지 확인하라"
        return false
    }

    // MARK: - 기록

    /// 키보드 프레임과 **키 하나**의 치수를 남긴다.
    /// 종횡비 판정의 원재료다 — 임계값은 여기서 정하지 않는다.
    private func record(keyboard: XCUIElement, stage: String) {
        guard keyboard.exists else {
            metrics["\(stage).keyboard"] = "없음"
            return
        }
        let frame = keyboard.frame
        metrics["\(stage).keyboard.height"] = Double(frame.height)
        metrics["\(stage).keyboard.width"] = Double(frame.width)
        metrics["\(stage).screen.width"] = Double(host.frame.width)
        metrics["\(stage).screen.height"] = Double(host.frame.height)
        if host.frame.height > 0 {
            metrics["\(stage).keyboard.screenFraction"] = Double(frame.height / host.frame.height)
        }
        // **우리 키캡은 `keys`가 아니라 `buttons`다.** `keys`는 시스템 자판용 타입이고
        // 글쇠는 SwiftUI로 그린 버튼이다(실측 2026-09-11: `keys.count == 0`, 화면에는 자판이 있었다).
        //
        // 키 하나를 대표로 잡아 폭·높이·종횡비를 남긴다. 좌표 원점은 익스텐션 창 로컬이라
        // 절대 위치는 신뢰하지 않지만 **크기와 비율은 그대로 쓸 수 있다.**
        // 키캡이 어떤 타입으로 노출되는지 한 번에 남긴다 — 다음 사람이 헤매지 않게.
        metrics["\(stage).count.buttons"] = keyboard.buttons.count
        metrics["\(stage).count.keys"] = keyboard.keys.count
        metrics["\(stage).count.staticTexts"] = keyboard.staticTexts.count
        metrics["\(stage).count.otherElements"] = keyboard.otherElements.count
        metrics["\(stage).count.images"] = keyboard.images.count

        // 한글 자모 라벨을 가진 요소를 찾아 어느 타입에 있는지 기록한다.
        for (name, query) in [("buttons", keyboard.buttons),
                              ("staticTexts", keyboard.staticTexts),
                              ("otherElements", keyboard.otherElements)] {
            let jamo = query.matching(NSPredicate(format: "label IN %@", ["ㅂ", "ㅈ", "ㄷ", "ㄱ", "ㅅ"]))
            if jamo.count > 0 {
                let e = jamo.element(boundBy: 0)
                metrics["\(stage).jamo.type"] = name
                metrics["\(stage).jamo.count"] = jamo.count
                metrics["\(stage).jamo.label"] = e.label
                metrics["\(stage).jamo.width"] = Double(e.frame.width)
                metrics["\(stage).jamo.height"] = Double(e.frame.height)
                if e.frame.height > 0 {
                    metrics["\(stage).jamo.aspect"] = Double(e.frame.width / e.frame.height)
                }
                break
            }
        }

        let buttons = keyboard.buttons

        // 가장 흔한 크기를 문자 키로 본다 — 스페이스·리턴 같은 넓은 키에 휘둘리지 않는다.
        var sizes: [String: (CGSize, String, Int)] = [:]
        for i in 0..<min(buttons.count, 40) {
            let b = buttons.element(boundBy: i)
            guard b.exists else { continue }
            let f = b.frame
            guard f.width > 0, f.height > 0 else { continue }
            let key = String(format: "%.1fx%.1f", f.width, f.height)
            let prev = sizes[key]
            sizes[key] = (f.size, prev?.1 ?? b.label, (prev?.2 ?? 0) + 1)
        }
        if let (size, label, count) = sizes.values.max(by: { $0.2 < $1.2 }) {
            metrics["\(stage).key.width"] = Double(size.width)
            metrics["\(stage).key.height"] = Double(size.height)
            metrics["\(stage).key.aspect"] = Double(size.width / size.height)
            metrics["\(stage).key.sampleLabel"] = label
            metrics["\(stage).key.sameSizeCount"] = count
        }
    }

    /// 키 **표면** 치수를 인접 자모의 중심 거리에서 되짚는다.
    ///
    /// 왜 필요한가: 우리 키캡은 `Button`이 아니라 **`Text` 노드 하나**라
    /// (`CLAUDE.md` 작업 원칙 — 트랙패드 버그 대응) 요소 프레임이 **글리프 경계**로 나온다.
    /// 자모 하나의 프레임은 19.3 × 26.3처럼 글자 크기이지 키 크기가 아니다.
    ///
    /// 그런데 **중심 사이 거리는 키 피치**다 — 피치 = 키 폭 + 키 간격(`KeyboardMetrics.keySpacing` 5pt).
    /// 세로도 같다 — 행 피치 = 행 높이 + 행 간격(7pt).
    /// **원점이 익스텐션 창 로컬이어도 거리는 그대로**라 좌표 오프셋 문제를 타지 않는다.
    private func recordKeyPitch(keyboard: XCUIApplication, stage: String) {
        // 한글 자모 한 글자짜리 라벨만 모은다 — 스페이스·리턴 같은 넓은 키를 섞지 않는다.
        var points: [(CGRect, String)] = []
        let texts = keyboard.staticTexts
        for i in 0..<min(texts.count, 80) {
            let e = texts.element(boundBy: i)
            guard e.exists else { continue }
            let label = e.label
            guard label.count == 1,
                  let scalar = label.unicodeScalars.first,
                  (0x3131...0x3163).contains(Int(scalar.value)) else { continue }  // ㄱ~ㅣ
            let f = e.frame
            guard f.width > 0, f.height > 0 else { continue }
            points.append((f, label))
        }
        metrics["\(stage).pitch.sampleCount"] = points.count
        guard points.count >= 4 else {
            metrics["\(stage).pitch.note"] = "자모 표본이 모자라 피치를 못 냈다"
            return
        }

        // 행 묶기 — **고정 버킷을 쓰지 않는다.** 10pt 버킷으로 나눴더니 한 행이 여러 버킷으로
        // 쪼개져 행 피치가 2.6pt로 나왔다(실측 2026-09-11, 실제 행 높이는 37pt대다).
        // 세로 중심을 정렬해 **간격이 벌어지는 곳에서 끊는다** — 행 수를 미리 알 필요가 없다.
        let sortedByY = points.sorted { $0.0.midY < $1.0.midY }
        var rowGroups: [[(CGRect, String)]] = []
        for p in sortedByY {
            // **그룹의 첫 원소(씨앗)와 비교한다.** 직전 원소와 비교하면 미세한 드리프트가
            // 연쇄돼 서로 다른 행이 하나로 붙는다(실측: 4행이 3그룹, 한 그룹에 20표본).
            if let seed = rowGroups.last?.first, abs(p.0.midY - seed.0.midY) <= p.0.height {
                rowGroups[rowGroups.count - 1].append(p)
            } else {
                rowGroups.append([p])
            }
        }
        metrics["\(stage).pitch.rowGroupCount"] = rowGroups.count
        guard let row = rowGroups.max(by: { $0.count < $1.count }), row.count >= 3 else {
            metrics["\(stage).pitch.note"] = "행을 묶지 못했다"
            return
        }
        let xs = row.map(\.0.midX).sorted()
        let gaps = zip(xs.dropFirst(), xs).map { $0 - $1 }.sorted()
        let pitch = gaps[gaps.count / 2]   // 중앙값 — 행 끝의 넓은 키에 휘둘리지 않는다
        metrics["\(stage).pitch.rowSampleCount"] = row.count
        metrics["\(stage).pitch.keyPitch"] = Double(pitch)
        metrics["\(stage).pitch.keyWidth"] = Double(pitch - 5)   // KeyboardMetrics.keySpacing

        // 행 피치 — 각 행의 세로 중심(평균) 사이 거리 중앙값.
        let rowCenters = rowGroups
            .map { group in group.map(\.0.midY).reduce(0, +) / CGFloat(group.count) }
            .sorted()
        if rowCenters.count >= 2 {
            let rowGaps = zip(rowCenters.dropFirst(), rowCenters).map { $0 - $1 }.sorted()
            let rowPitch = rowGaps[rowGaps.count / 2]
            metrics["\(stage).pitch.rowPitch"] = Double(rowPitch)
            metrics["\(stage).pitch.rowHeight"] = Double(rowPitch - 7)   // KeyboardMetrics.rowSpacing
            let keyWidth = pitch - 5, rowHeight = rowPitch - 7
            if rowHeight > 0 {
                metrics["\(stage).pitch.keyAspect"] = Double(keyWidth / rowHeight)
            }
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
