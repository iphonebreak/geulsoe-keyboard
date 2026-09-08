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
        #expect(decoded.clipboardHistoryEnabled == true, "클립보드 기록 신규 필드도 기본 켬")
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
    }

    /// 도구 순서 — 구 저장분에 없는 신규 도구는 뒤에 붙어야 사라지지 않는다.
    @Test("저장된 도구 순서에 없는 도구는 orderedTools가 뒤에 보정한다")
    func orderedToolsAppendsMissing() throws {
        // 구 저장분의 "cursor"는 왼쪽·오른쪽 둘로 펼쳐진다 (2026-09-03 분리)
        let legacy = #"{"toolOrder":["emoji","cursor"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)
        #expect(decoded.orderedTools == [.emoji, .cursorLeft, .cursorRight, .dismiss, .clipboard])
        #expect(KeyboardSettings.default.orderedTools == ToolbarTool.allCases)
        // 중복은 첫 등장만
        let dup = #"{"toolOrder":["cursor","cursor","dismiss"]}"#.data(using: .utf8)!
        #expect(try JSONDecoder().decode(KeyboardSettings.self, from: dup).orderedTools
                == [.cursorLeft, .cursorRight, .dismiss, .clipboard, .emoji])
    }

    @Test("도구 목록의 미지 값은 버리고 설정 전체는 살린다 — 구 cursor는 disabledTools에서도 둘로")
    func toolListsDecodeLeniently() throws {
        let json = #"{"disabledTools":["cursor","futureTool"],"toolOrder":["emoji","futureTool","dismiss"],"numberRowEnabled":true}"#
            .data(using: .utf8)!
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: json)
        #expect(decoded.disabledTools == [.cursorLeft, .cursorRight])
        #expect(decoded.orderedTools == [.emoji, .dismiss, .cursorLeft, .cursorRight, .clipboard])
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
