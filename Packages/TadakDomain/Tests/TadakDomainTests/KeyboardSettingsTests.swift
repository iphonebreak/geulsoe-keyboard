import Testing
import Foundation
@testable import TadakDomain


@Suite("KeyboardSettings — 채움글 머리말")
struct BibleSnippetPrefixSettingTests {

    @Test("bibleSnippetPrefixEnabled는 구 JSON에 없으면 true, 있으면 그대로")
    func decodesWithDefault() throws {
        let legacy = Data("{}".utf8)
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: legacy).bibleSnippetPrefixEnabled == true)
        let off = Data(#"{"bibleSnippetPrefixEnabled": false}"#.utf8)
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: off).bibleSnippetPrefixEnabled == false)
        var settings = KeyboardSettings.default
        settings.bibleSnippetPrefixEnabled = false
        let roundTrip = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip.bibleSnippetPrefixEnabled == false)
    }
}

@Suite("설정 스키마")
struct KeyboardSettingsTests {

    @Test("기본값은 두벌식 하나만 켜져 있고 system 테마다")
    func defaults() {
        let settings = KeyboardSettings.default
        #expect(settings.enabledHangulLayouts == [.dubeolsik])
        #expect(settings.activeHangulLayout == .dubeolsik)
        #expect(settings.selectedThemeID == "system")
    }

    @Test("인코딩과 디코딩이 값을 보존한다")
    func codableRoundTrip() throws {
        var settings = KeyboardSettings.default
        settings.enabledHangulLayouts = [.dubeolsik, .cheonjiin, .danmoeum]
        settings.activeHangulLayout = .cheonjiin
        settings.cheonjiinTimeout = 1.2
        settings.enabledTools = [.emoji, .cursorLeft]
        settings.appearance = .dark
        settings.selectedThemeID = "midnight"

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(decoded == settings)
    }

    /// 마이그레이션 함정 방어 — 사용자 기기에 남은 옛 JSON에는 새 필드가 없다.
    @Test("selectedThemeID가 없는 구버전 JSON도 디코딩된다")
    func decodesLegacyJSONWithoutThemeID() throws {
        let legacy = """
        {"enabledHangulLayouts":["dubeolsik"],"activeHangulLayout":"dubeolsik",
         "keyboardHeight":"tall","cheonjiinTimeout":0.8,"showsKeyPreview":true,
         "autoCapitalization":true,"doubleSpacePeriod":true,"suggestionsEnabled":true,
         "defaultToolbarMode":"tools","enabledTools":["cursor","clipboard","emoji"],
         "hapticEnabled":true,"keySoundEnabled":false,"appearance":"system"}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.selectedThemeID == "system")
        #expect(decoded.keyboardHeight == .tall)
        #expect(decoded.danmoeumTimeout == 0.3, "Phase 3 신규 필드도 기본값으로 채워진다")
    }

    /// Phase 5.5 마이그레이션 함정 방어 — snippetsEnabled가 없는 저장분은 기본 켬으로 읽힌다.
    @Test("snippetsEnabled가 없는 구버전 JSON은 기본 켬으로 디코딩된다")
    func decodesLegacyJSONWithoutSnippetsEnabled() throws {
        let legacy = #"{"activeHangulLayout":"dubeolsik","suggestionsEnabled":false}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.snippetsEnabled == true)
        #expect(decoded.suggestionsEnabled == false, "있는 필드는 그대로 읽힌다")
    }

    /// Phase 6 마이그레이션 함정 방어 — 팩 목록·초기화 토큰이 없는 저장분.
    @Test("Phase 6 신규 필드가 없는 구버전 JSON은 기본값으로 디코딩된다")
    func decodesLegacyJSONWithoutPhase6Fields() throws {
        let legacy = #"{"snippetsEnabled":false,"suggestionsEnabled":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.disabledSnippetPacks.isEmpty, "옵트아웃 목록 기본 = 전부 켬")
        #expect(decoded.learningResetToken == 0)
        #expect(decoded.snippetsEnabled == false)
        #expect(decoded.verificationCodeSuggestionsEnabled == true, "Phase 7 신규 필드도 기본 켬")
        // 2026-09-11 기본값 전환: 키가 없는 저장분은 이제 **끔**으로 읽힌다.
        // 이 JSON에는 clipboardHistoryEnabled 키 자체가 없다.
        #expect(decoded.clipboardHistoryEnabled == false, "키가 없으면 새 기본값(끔)")
        #expect(decoded.hapticIntensity == 0.6, "진동 세기 기본 — 이전 .light 1.0과 비슷한 체감")
        #expect(decoded.keySoundVolume == 0.7)
    }

    @Test("진동 세기·소리 크기는 범위 밖 저장분을 clamp한다")
    func clampsFeedbackLevels() throws {
        let json = #"{"hapticIntensity":5.0,"keySoundVolume":-1}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        #expect(decoded.clampedHapticIntensity == 1.0)
        #expect(decoded.clampedKeySoundVolume == 0.1)
    }

    // MARK: - 클립보드 기록 기본값 전환 마이그레이션 (2026-09-11)
    //
    // 위험은 "안 꺼지는 것"이 아니라 **이미 켜 둔 사용자가 조용히 꺼지는 것**이다.
    // 끄면 보안 규칙상 저장분을 즉시 삭제하므로(PDR clipboard-history) 기록이 사라진다.
    // 아래 넷이 그 경계를 고정한다. 인라인 휴리스틱으로 값을 되돌리지 않는다 —
    // 툴바 순서에서 겪은 "영구 고착" 계열의 함정을 여기서 반복하지 않기 위해서다.

    @Test("마이그레이션 1 — 새 설치는 클립보드 기록이 꺼져 있다")
    func clipboardDefaultsOffOnFreshInstall() {
        #expect(KeyboardSettings().clipboardHistoryEnabled == false)
        #expect(KeyboardSettings.default.clipboardHistoryEnabled == false)
    }

    @Test("★ 마이그레이션 2 — 이미 켜 둔 사용자는 업데이트해도 꺼지지 않는다")
    func clipboardStaysOnForExistingUser() throws {
        // 앱이 설정을 저장하면 모든 키가 들어간다(구조체 전체를 인코딩한다).
        // 즉 한 번이라도 설정을 저장한 사용자는 이 키를 갖고 있다.
        let stored = #"{"clipboardHistoryEnabled":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: stored)
        #expect(decoded.clipboardHistoryEnabled == true,
                "저장된 값이 있으면 그대로 존중한다 — 기본값은 새 설치에만 적용된다")
    }

    @Test("마이그레이션 3 — 꺼 둔 사용자도 그대로다")
    func clipboardStaysOffForExistingUser() throws {
        let stored = #"{"clipboardHistoryEnabled":false}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: stored)
                .clipboardHistoryEnabled == false)
    }

    @Test("마이그레이션 4 — 키가 없는 구 저장분은 새 기본값(끔)을 따른다")
    func clipboardFollowsNewDefaultWhenKeyAbsent() throws {
        // 이 필드가 생기기 전(Phase 6 이전)의 저장분이다. 사용자가 켠 적이 없으므로
        // "존중할 선택"이 존재하지 않는다 — 안전한 쪽(끔)으로 간다.
        let ancient = #"{"activeHangulLayout":"cheonjiin"}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: ancient)
                .clipboardHistoryEnabled == false)
    }

    @Test("마이그레이션 5 — 켜 둔 값이 라운드트립을 견딘다")
    func clipboardOnSurvivesRoundTrip() throws {
        var settings = KeyboardSettings()
        settings.clipboardHistoryEnabled = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: data)
                .clipboardHistoryEnabled == true)
    }

    @Test("clipboardHistoryEnabled=false는 라운드트립에서 보존된다")
    func preservesClipboardHistoryOff() throws {
        var settings = KeyboardSettings.default
        settings.clipboardHistoryEnabled = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: data)
        #expect(decoded.clipboardHistoryEnabled == false)
    }

    @Test("필드 대부분이 빠진 최소 JSON도 기본값으로 채워진다")
    func decodesMinimalJSON() throws {
        let minimal = #"{"activeHangulLayout":"cheonjiin"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: minimal)
        #expect(decoded.activeHangulLayout == .cheonjiin)
        #expect(decoded.enabledTools == ToolbarTool.allCases)
        #expect(decoded.selectedThemeID == "system")
    }

    @Test("두벌식만 그리드 자판이 아니다")
    func gridLayoutFlag() {
        #expect(HangulLayout.dubeolsik.isGridLayout == false)
        #expect(HangulLayout.cheonjiin.isGridLayout)
        #expect(HangulLayout.danmoeum.isGridLayout)
    }

    @Test("클립보드만 Full Access를 요구한다")
    func fullAccessRequirement() {
        #expect(ToolbarTool.clipboard.worksWithoutFullAccess == false)
        #expect(ToolbarTool.cursorLeft.worksWithoutFullAccess && ToolbarTool.cursorRight.worksWithoutFullAccess)
        #expect(ToolbarTool.emoji.worksWithoutFullAccess)
        #expect(ToolbarTool.dismiss.worksWithoutFullAccess)
        // ★ 번들 bible.tdb를 mmap으로 읽을 뿐이라 권한이 필요 없다. 화이트리스트로 바꾸면서
        //   빠뜨리면 **전체 접근을 끈 사용자에게서 📖 자리가 조용히 사라진다.**
        #expect(ToolbarTool.bibleSearch.worksWithoutFullAccess)
        // 전수 — 클립보드 하나만 거짓이다
        #expect(ToolbarTool.allCases.filter { !$0.worksWithoutFullAccess } == [.clipboard])
    }

    /// 도구 순서 — 구 저장분에 없는 신규 도구는 뒤에 붙어야 사라지지 않는다.
    @Test("저장된 도구 순서에 없는 도구는 orderedTools가 뒤에 보정한다")
    func orderedToolsAppendsMissing() throws {
        // 구 저장분의 "cursor"는 왼쪽·오른쪽 둘로 펼쳐진다 (2026-09-03 분리)
        let legacy = #"{"toolOrder":["emoji","cursor"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        // 뒤에 붙는 순서는 `allCases` 순서다 — v1.0.1에서 dismiss가 맨 끝으로 갔다.
        // v1.1.0: 📖은 **뒤에 붙지 않는다** — 디코더가 이모지 바로 뒤로 끼운 뒤라서다
        #expect(decoded.orderedTools == [.emoji, .bibleSearch, .cursorLeft, .cursorRight, .clipboard, .dismiss])
        #expect(KeyboardSettings.default.orderedTools == ToolbarTool.allCases)
        // 중복은 첫 등장만
        let dup = #"{"toolOrder":["cursor","cursor","dismiss"]}"#.data(using: .utf8)!
        // 이모지가 저장 순서에 없으면 `dismiss` 앞으로 물러난다 (그 다음이 맨 뒤)
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: dup).orderedTools
                == [.cursorLeft, .cursorRight, .bibleSearch, .dismiss, .clipboard, .emoji])
    }

    // MARK: - v1.0.1 툴바 순서 1회성 마이그레이션 (fixture 5종)
    //
    // 위험은 "안 바뀌는 것"이 아니라 **매번 바뀌는 것**이다. 값 비교만으로 판단하면 전환 뒤
    // 사용자가 스스로 옛 순서로 되돌려도 그것을 구 저장분으로 오인해 계속 덮어쓴다(영구 고착).
    // 그래서 플래그를 따로 둔다. 아래 5종이 그 경계를 전부 고정한다.

    @Test("마이그레이션 1 — 신규 설치는 새 기본값이고 전환 완료 상태로 시작한다")
    func migrationFreshInstall() {
        let fresh = KeyboardSettings()
        #expect(fresh.toolOrder == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
        #expect(fresh.toolOrder == ToolbarTool.allCases)
        #expect(fresh.toolOrderMigratedV101, "신규 설치는 전환할 것이 없다")
    }

    @Test("마이그레이션 2 — 구 기본값 그대로 쓰던 저장분은 새 기본값으로 1회 전환된다")
    func migrationLegacyDefault() throws {
        let legacy = #"{"toolOrder":["dismiss","cursorLeft","cursorRight","clipboard","emoji"]}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.toolOrder == ToolbarTool.allCases, "dismiss가 맨 끝으로")
        #expect(decoded.toolOrderMigratedV101, "전환했으면 플래그가 선다")
    }

    @Test("마이그레이션 3 — 손수 바꾼 순서는 건드리지 않는다")
    func migrationCustomOrderPreserved() throws {
        let custom = #"{"toolOrder":["emoji","dismiss","clipboard","cursorLeft","cursorRight"]}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: custom)
        // ★ 기존 도구의 **상대 순서는 하나도 안 바뀐다.** 📖만 이모지 바로 뒤에 끼었다 —
        //   스플라이스 방식을 안 쓴 이유가 이것이다(그쪽은 dismiss를 2번→6번으로 민다).
        #expect(decoded.toolOrder == [.emoji, .bibleSearch, .dismiss, .clipboard, .cursorLeft, .cursorRight],
                "사용자가 정한 순서는 그대로")
        #expect(decoded.toolOrderMigratedV101, "전환 대상이 아니어도 플래그는 선다 — 다시 묻지 않는다")
    }

    @Test("마이그레이션 4 — 전환 뒤 사용자가 옛 순서로 되돌려도 다시 덮어쓰지 않는다")
    func migrationDoesNotRepeat() throws {
        // 플래그가 이미 true인데 순서가 구 기본값과 같은 상태 = 사용자가 직접 그렇게 만든 것.
        let reverted = #"""
        {"toolOrder":["dismiss","cursorLeft","cursorRight","clipboard","emoji"],
         "toolOrderMigratedV101":true}
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: reverted)
        #expect(decoded.toolOrder == KeyboardSettings.legacyDefaultToolOrder + [.bibleSearch],
                "사용자 선택이므로 유지된다 — 여기서 덮어쓰면 영구 고착 버그다. 📖만 이모지 뒤에 붙는다")
        #expect(decoded.toolOrderMigratedV101)
    }

    @Test("마이그레이션 5 — 구형 단일 cursor 표기 저장분도 펼쳐진 뒤 전환된다")
    func migrationLegacyCursorToken() throws {
        // 2026-09-03 이전 저장분은 "cursor" 하나였다. decodeList가 둘로 펼친 뒤라야
        // 구 기본값과의 비교가 성립한다 — 이 경로가 막히면 그 사용자만 옛 순서에 고착된다.
        let ancient = #"{"toolOrder":["dismiss","cursor","clipboard","emoji"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: ancient)
        #expect(decoded.toolOrder == ToolbarTool.allCases, "펼친 결과가 구 기본값이므로 전환된다")
        #expect(decoded.toolOrderMigratedV101)
    }

    // MARK: - ★ v1.1.0 — 📖를 도구 순서에 끼우는 마이그레이션 (저장분 fixture)
    //
    // **이것이 이번 변경의 위험 전부다.** `orderedTools`가 빠진 도구를 무조건 뒤에 붙이므로,
    // 마이그레이션이 없으면 현실적인 v1.0.1 저장분 전부에서 📖이 **맨 끝(내리기 뒤)** 으로 간다.
    // 그리고 `ToolbarOrderPreview`가 `orderedTools`를 그대로 `toolOrder`에 되쓰므로
    // **사용자가 순서 편집을 한 번 건드리면 그 끝자리가 영구 저장된다.**

    @Test("📖 저장분 1 — 신규 설치는 선언 순서 그대로다")
    func bibleOrderFreshInstall() {
        #expect(KeyboardSettings().toolOrder
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
        #expect(KeyboardSettings().bibleSearchInToolOrderMigrated, "끼울 것이 없다")
    }

    @Test("📖 저장분 2 — v1.0.1 기본 순서: 이모지 바로 뒤")
    func bibleOrderV101Default() throws {
        // v1.0.1 기본값 = 그때의 `allCases`
        let saved = #"{"toolOrder":["cursorLeft","cursorRight","clipboard","emoji","dismiss"],"toolOrderMigratedV101":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
        #expect(decoded.toolOrder
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
        #expect(decoded.bibleSearchInToolOrderMigrated)
    }

    @Test("📖 저장분 3 — 사용자가 바꾼 순서: 기존 상대 순서가 하나도 안 바뀐다")
    func bibleOrderCustom() throws {
        let saved = #"{"toolOrder":["dismiss","emoji","clipboard","cursorRight","cursorLeft"],"toolOrderMigratedV101":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
        #expect(decoded.toolOrder
                == [.dismiss, .emoji, .bibleSearch, .clipboard, .cursorRight, .cursorLeft])
        // ★ 「내리기」를 1번에 둔 사용자다. `dismiss` 앵커였다면 📖이 **맨 앞**에 꽂혀
        //   사용자가 손수 정한 1번 자리를 빼앗았다. 이모지 앵커는 그런 일이 없다.
        #expect(decoded.toolOrder.first == .dismiss, "사용자가 정한 1번 자리를 빼앗지 않는다")
        // 📖를 뺀 나머지가 저장분과 **완전히 같다**
        #expect(decoded.toolOrder.filter { $0 != .bibleSearch }
                == [.dismiss, .emoji, .clipboard, .cursorRight, .cursorLeft])
    }

    @Test("📖 저장분 4 — 이모지를 끈 사용자도 이모지 **자리** 뒤다")
    func bibleOrderEmojiDisabled() throws {
        // 끔은 `disabledTools`라 `toolOrder`에는 이모지가 그대로 남는다
        let saved = #"{"toolOrder":["cursorLeft","cursorRight","clipboard","emoji","dismiss"],"disabledTools":["emoji"],"toolOrderMigratedV101":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
        #expect(decoded.toolOrder
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
        #expect(decoded.disabledTools == [.emoji], "끔 상태는 그대로")
    }

    @Test("📖 저장분 5 — v1.0.0(단일 cursor + 구 기본 순서)은 v1.0.1 전환을 거친 뒤 끼워진다")
    func bibleOrderAncient() throws {
        let saved = #"{"toolOrder":["dismiss","cursor","clipboard","emoji"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
        // 펼치면 구 기본값 → v1.0.1 전환으로 `allCases`(📖 포함) → 이미 있으므로 끼우지 않는다
        #expect(decoded.toolOrder == ToolbarTool.allCases)
        #expect(decoded.toolOrderMigratedV101 && decoded.bibleSearchInToolOrderMigrated)
    }

    @Test("★ 📖 저장분 6 — 이미 📖가 있으면 **어디 있든 그대로 둔다**")
    func bibleOrderAlreadyPresentIsPreserved() throws {
        // 사용자가 📖를 맨 앞으로 옮겨 둔 v1.1.0 저장분.
        // **플래그 유/무 양쪽**에서 보존돼야 한다 — 판정이 존재 여부라 플래그와 무관하다.
        let moved = [ToolbarTool.bibleSearch, .cursorLeft, .cursorRight, .clipboard, .emoji, .dismiss]
        for flag in ["true", "false"] {
            let saved = """
            {"toolOrder":["bibleSearch","cursorLeft","cursorRight","clipboard","emoji","dismiss"],
             "toolOrderMigratedV101":true,"bibleSearchInToolOrderMigrated":\(flag)}
            """.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
            #expect(decoded.toolOrder == moved, "플래그 \(flag)에서도 사용자 자리를 되돌리지 않는다")
        }
    }

    @Test("★ 📖 전환 플래그는 리터럴 false에서 출발한다 — 구 저장분이 「완료」로 읽히면 기록이 거짓이다")
    func bibleOrderFlagDefaultsToFalseNotBase() throws {
        // 키가 없는 구 저장분: 끼워 넣기가 **실제로 일어나야** 한다.
        // `base`(= .default)를 기본값으로 썼다면 true로 읽혀도 이 판정은 존재 여부라 결과는 같지만,
        // 플래그가 「이 저장분은 전환을 겪지 않았다」를 기록하지 못한다.
        let saved = #"{"toolOrder":["emoji"],"toolOrderMigratedV101":true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: saved)
        #expect(decoded.toolOrder == [.emoji, .bibleSearch])
        #expect(decoded.orderedTools
                == [.emoji, .bibleSearch, .cursorLeft, .cursorRight, .clipboard, .dismiss])
    }

    @Test("📖 끼우기 — 이모지가 없으면 내리기 앞, 그것도 없으면 맨 뒤")
    func bibleOrderFallbackAnchors() {
        #expect(KeyboardSettings.insertingBibleSearch(into: [.clipboard, .dismiss, .cursorLeft])
                == [.clipboard, .bibleSearch, .dismiss, .cursorLeft])
        #expect(KeyboardSettings.insertingBibleSearch(into: [.clipboard, .cursorLeft])
                == [.clipboard, .cursorLeft, .bibleSearch])
        #expect(KeyboardSettings.insertingBibleSearch(into: []) == [.bibleSearch])
    }

    // MARK: - ★ 📖만 설정에서 못 끈다

    @Test("★ 📖는 설정에서 끌 수 없다 — 나머지 다섯은 끌 수 있다")
    func bibleSearchIsNotToggleable() {
        #expect(ToolbarTool.bibleSearch.isToggleableInSettings == false)
        #expect(ToolbarTool.allCases.filter(\.isToggleableInSettings)
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .dismiss])
        // 여섯 중 다섯만 탭으로 꺼진다 — 스트립의 탭 가드와 접근성 값이 이 사실에 걸려 있다
        #expect(ToolbarTool.allCases.count == 6)
    }

    // MARK: - ★ 도구 이름 — SE에서 잘리지 않아야 한다 (2026-09-22)

    @Test("★ 커서 두 개의 이름이 짧아졌다 — 도구가 6개가 되며 SE에서 잘렸다")
    func cursorNamesShortened() {
        #expect(ToolbarTool.cursorLeft.displayName == "좌측 커서 이동")
        #expect(ToolbarTool.cursorRight.displayName == "우측 커서 이동")
    }

    /// ★ **이 테스트가 잠그는 것은 문자열이 아니라 「왜 바꿨나」다.**
    ///
    /// 순서 편집 스트립의 이름표는 `.caption2`(11pt) **2줄**이고 공백에서 줄바꿈한다.
    /// SE(375pt)·도구 6칸에서 칸 폭이 **약 45~51pt**라, 공백으로 끊은 한 토막이
    /// **5글자(≈55pt)면 넘쳐 잘린다.** 실제로 「오른쪽으로 커서 이동」의 「오른쪽으로」(5글자)가
    /// 검증자 실화면에서 잘렸다(`verify-v110-copytrim.md` 0-2절).
    ///
    /// 4글자(≈44pt)까지는 들어간다 — 「클립보드」가 그 경계에 있고 잘리지 않았다.
    /// **그래서 상한을 4로 잠근다.** 새 도구를 넣거나 이름을 바꿀 때 이 테스트가 먼저 운다.
    @Test("★ 어떤 도구 이름도 공백으로 끊은 한 토막이 4글자를 넘지 않는다")
    func noToolNameChunkExceedsFourCharacters() {
        for tool in ToolbarTool.allCases {
            let longest = tool.displayName
                .split(separator: " ")
                .map(\.count)
                .max() ?? 0
            #expect(longest <= 4, "\(tool.displayName)의 최장 토막이 \(longest)글자다 — SE 6칸에서 잘린다")
        }
        // 고치기 전에는 이 상한을 넘던 것이 있었다는 사실 자체를 남긴다
        #expect("오른쪽으로".count == 5)
    }

    @Test("도구 목록의 미지 값은 버리고 설정 전체는 살린다 — 구 cursor는 disabledTools에서도 둘로")
    func toolListsDecodeLeniently() throws {
        let json = #"{"disabledTools":["cursor","futureTool"],"toolOrder":["emoji","futureTool","dismiss"],"numberRowEnabled":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        #expect(decoded.disabledTools == [.cursorLeft, .cursorRight])
        #expect(decoded.orderedTools == [.emoji, .bibleSearch, .dismiss, .cursorLeft, .cursorRight, .clipboard])
        #expect(decoded.numberRowEnabled == true, "한 원소가 이상해도 다른 필드는 정상 디코딩")
    }

    /// 높이 배율 마이그레이션 — 3단계 선택이 배율로 보존되어야 한다.
    @Test("배율이 없는 구 저장분은 3단계 높이를 배율로 옮긴다")
    func migratesHeightPresetToScale() throws {
        let tall = try JSONDecoder().decode(
            KeyboardSettings.self, from: #"{"keyboardHeight":"tall"}"#.data(using: .utf8)!)
        #expect(abs(tall.keyboardHeightScale - 1.15) < 0.001, "244/216=1.13 → 5% 그리드 스냅")
        let compact = try JSONDecoder().decode(
            KeyboardSettings.self, from: #"{"keyboardHeight":"compact"}"#.data(using: .utf8)!)
        #expect(abs(compact.keyboardHeightScale - 0.9) < 0.001, "196/216=0.907 → 0.9")
        // 범위 밖 저장값은 clamp된다
        var wild = KeyboardSettings.default
        wild.keyboardHeightScale = 1.5
        #expect(wild.clampedHeightScale == 1.2)
        wild.keyboardHeightScale = 0.3
        #expect(wild.clampedHeightScale == 0.8)
        // 배율이 있으면 그대로 (3단계 값과 무관)
        let scaled = try JSONDecoder().decode(
            KeyboardSettings.self,
            from: #"{"keyboardHeight":"tall","keyboardHeightScale":0.85}"#.data(using: .utf8)!)
        #expect(scaled.keyboardHeightScale == 0.85)
        #expect(KeyboardSettings.default.keyboardHeightScale == 1.0)
    }

    /// Phase 4 마이그레이션 함정 방어 — 구 저장분의 화이트리스트(enabledTools)에는
    /// 신규 dismiss가 없다. 옵트아웃(disabledTools)으로 읽으므로 새 도구가 기본 켬이어야 한다.
    @Test("구버전 enabledTools 저장분에서도 새 도구는 기본 켬이다")
    func decodesLegacyToolsAsAllEnabled() throws {
        let legacy = #"{"enabledTools":["cursor","clipboard","emoji"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.disabledTools.isEmpty, "옵트아웃 기본 = 전부 켬 (dismiss 포함)")
        #expect(decoded.numberRowEnabled == false, "숫자 줄 기본 끔")
    }
}

@Suite("테마 스펙")
struct ThemeSpecTests {

    @Test("JSON에서 테마를 디코딩한다")
    func decodesFromJSON() throws {
        let json = """
        {"id":"midnight","displayName":"미드나이트",
         "light":{"keyboardBackground":"#1A1B2E","characterKey":"#2A2C4A",
                  "functionKey":"#20223A","keyText":"#E8E9F5","accent":"#7B8CFF"},
         "dark":{"keyboardBackground":"#12131F","characterKey":"#222440",
                 "functionKey":"#1A1C30","keyText":"#E8E9F5","accent":"#7B8CFF"},
         "keyCornerRadius":8}
        """.data(using: .utf8)!
        let theme = try JSONDecoder().decode(ThemeSpec.self, from: json)
        #expect(theme.id == "midnight")
        #expect(theme.light.accent == "#7B8CFF")
        #expect(theme.dark.keyboardBackground == "#12131F")
    }

    @Test("longPressSymbolsEnabled가 없는 구버전 JSON은 기본 켬으로 디코딩되고, 끈 값은 왕복 보존된다")
    func longPressSymbolsDefaultsToOn() throws {
        let legacy = Data(#"{"activeHangulLayout":"dubeolsik","numberRowEnabled":true}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.longPressSymbolsEnabled == true)
        #expect(decoded.numberRowEnabled == true, "옆 필드는 그대로 읽힌다")
        var settings = KeyboardSettings.default
        settings.longPressSymbolsEnabled = false
        let roundTrip = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(roundTrip.longPressSymbolsEnabled == false)
    }
}

/// **기존 설치의 저장본에는 새 키가 없다** — 폴백이 실제로 「켬」을 주는지 못 박는다.
///
/// 2026-09-15 에 사용자가 "복사했는데 칩이 안 뜬다"고 보고했을 때 의심 목록에 오른 자리다:
/// `pasteSuggestionEnabled` 는 이번에 새로 생긴 필드라 **v1.0.1 이전에 저장된 JSON 에는 없다.**
/// `decodeIfPresent ?? base` 가 기본 켬을 주지 않으면 **기존 사용자는 칩을 영영 못 본다.**
/// 마이그레이션 함정이라 실제 JSON 으로 확인한다.
@Suite("설정 마이그레이션 — 새 키가 없는 옛 저장본")
struct KeyboardSettingsMigrationTests {

    @Test("pasteSuggestionEnabled 키가 없으면 켬으로 온다")
    func pasteSuggestionDefaultsOnForOldPayload() throws {
        // 옛 저장본을 흉내 낸다 — 새 키가 아예 없다
        let json = """
        {"clipboardHistoryEnabled":true,"verificationCodeSuggestionsEnabled":true}
        """
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: Data(json.utf8))
        #expect(settings.pasteSuggestionEnabled == true, "새 키가 없으면 기본 켬이어야 한다")
    }

    @Test("빈 JSON 객체도 기본값 전부로 온다")
    func emptyPayloadYieldsDefaults() throws {
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(settings.pasteSuggestionEnabled == true)
        #expect(settings.verificationCodeSuggestionsEnabled == true)
    }

    @Test("명시적으로 꺼 둔 저장본은 존중한다")
    func explicitFalseIsRespected() throws {
        let json = #"{"pasteSuggestionEnabled":false}"#
        let settings = try JSONDecoder().decode(KeyboardSettings.self, from: Data(json.utf8))
        #expect(settings.pasteSuggestionEnabled == false)
    }
}

/// 단축어 정규화 — **설정 화면의 중복 판정과 키보드의 발동이 같은 함수를 써야 한다.**
/// 두 군데서 따로 정의하면 "저장은 됐는데 안 뜬다"가 생긴다.
@Suite("단축어 정규화")
struct SnippetTriggerNormalizationTests {

    @Test("공백·개행을 없앤다", arguments: [
        ("우리집주소", "우리집주소"),
        ("우리집 주소", "우리집주소"),
        ("우 리 집 주 소", "우리집주소"),
        ("  우리집\t주소\n", "우리집주소"),
        ("", "")
    ])
    func normalizes(testCase: (String, String)) {
        #expect(SnippetEntry.normalizedTrigger(testCase.0) == testCase.1)
    }

    /// 목록 id 는 **정규화 단축어를 이어 붙인 것**이라, 띄어쓰기만 다른 항목은 같은 id 가 된다
    /// (= 중복으로 걸러진다).
    @Test("띄어쓰기만 다른 항목은 같은 목록 id 를 갖는다")
    func listIDIgnoresSpacing() {
        let a = SnippetEntry(triggers: ["우리집주소", "집주소"], title: "A", body: "본문")
        let b = SnippetEntry(triggers: ["우리집 주소", "집 주소"], title: "B", body: "다른 본문")
        #expect(a.snippetListID == b.snippetListID)
    }

    @Test("단축어 집합이 다르면 목록 id 도 다르다")
    func listIDDistinguishesDifferentSets() {
        let a = SnippetEntry(triggers: ["집주소"], title: "A", body: "본문")
        let b = SnippetEntry(triggers: ["집주소", "우리집주소"], title: "B", body: "본문")
        #expect(a.snippetListID != b.snippetListID)
    }
}

/// 단축어 **쉼표 파싱** — 편집 시트가 받은 한 줄을 단축어 목록으로 쪼개는 규칙.
///
/// 이 규칙은 원래 `SnippetEditorView` 안의 `private var parsedTriggers` 라 **테스트가 닿지
/// 않았다.** 검증자가 코드를 읽어 8가지를 추적했지만 그건 추적이지 테스트가 아니다
/// (`docs/release/verify-snippet-shortcut.md` 5-1). 그 8가지를 여기에 그대로 고정한다.
@Suite("단축어 쉼표 파싱")
struct SnippetTriggerParsingTests {

    @Test("쉼표로 쪼갠다 — 띄어쓰기 3꼴이 모두 같은 결과", arguments: [
        "우리집주소, 집주소",     // 1. 쉼표 + 공백
        "우리집주소,집주소",       // 2. 공백 없음
        "우리집주소 , 집주소"      // 3. 쉼표 앞뒤 공백
    ])
    func splitsOnComma(input: String) {
        #expect(SnippetEntry.parseTriggers(input) == ["우리집주소", "집주소"])
    }

    @Test("빈 조각은 버린다 — 연속 쉼표·끝 쉼표·공백만 있는 조각", arguments: [
        ("우리집주소,,집주소", ["우리집주소", "집주소"]),        // 4. 연속 쉼표
        ("우리집주소,", ["우리집주소"]),                       // 5. 맨 끝 쉼표
        ("우리집주소, , 집주소", ["우리집주소", "집주소"]),      // 6. 공백만 있는 조각
        (",우리집주소", ["우리집주소"]),
        ("  우리집주소  ", ["우리집주소"])
    ])
    func dropsEmptyPieces(testCase: (String, [String])) {
        #expect(SnippetEntry.parseTriggers(testCase.0) == testCase.1)
    }

    /// 7. 정규화(공백 제거) 기준으로 같으면 하나로 합친다.
    @Test("띄어쓰기만 다른 단축어는 하나로 합친다")
    func mergesNormalizedDuplicates() {
        #expect(SnippetEntry.parseTriggers("우리집주소, 우리집 주소") == ["우리집주소"])
        #expect(SnippetEntry.parseTriggers("우 리 집 주 소, 우리집주소").count == 1)
        #expect(SnippetEntry.parseTriggers("집주소, 집주소, 집주소") == ["집주소"])
    }

    /// 8. 건질 게 하나도 없으면 빈 배열 — 편집 시트의 저장 버튼이 이걸로 비활성된다.
    @Test("건질 게 없으면 0개", arguments: [",", "", "   ", ",,,", " , , "])
    func yieldsNothing(input: String) {
        #expect(SnippetEntry.parseTriggers(input).isEmpty)
    }

    /// **정규화는 중복 판정에만 쓴다 — 저장되는 값은 사용자가 친 원문이다.**
    /// 이게 뒤집히면 목록에 "우리집 주소"로 등록한 것이 "우리집주소"로 보인다.
    @Test("원문을 그대로 보존한다 (정규화한 값을 저장하지 않는다)")
    func preservesRawInput() {
        #expect(SnippetEntry.parseTriggers("우리집 주소, 집 주소") == ["우리집 주소", "집 주소"])
    }

    /// 중복을 합칠 때 살아남는 것은 **먼저 친 쪽의 원문**이다.
    @Test("중복을 합치면 먼저 친 원문이 남는다")
    func keepsFirstSpelling() {
        #expect(SnippetEntry.parseTriggers("우리집 주소, 우리집주소") == ["우리집 주소"])
        #expect(SnippetEntry.parseTriggers("우리집주소, 우리집 주소") == ["우리집주소"])
    }

    /// 입력 순서를 그대로 지킨다 (첫 단축어가 제목 기본값이 되므로 순서가 보이는 값이다).
    @Test("입력 순서를 지킨다")
    func preservesOrder() {
        #expect(SnippetEntry.parseTriggers("가, 나, 다, 라") == ["가", "나", "다", "라"])
    }
}
