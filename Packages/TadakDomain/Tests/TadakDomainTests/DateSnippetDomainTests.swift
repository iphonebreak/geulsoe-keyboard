import Testing
import Foundation
@testable import TadakDomain

/// 날짜·시간 채움글 팩의 도메인 몫 — 설정 필드·팩 id·편집기 경고 판정
/// (PDR `docs/design-reviews/date-snippet-pack.md` 10절 1단계 · 3-5절 · 수용 기준 4).
@Suite("날짜 채움글 — 설정과 팩 id")
struct DateSnippetSettingsTests {

    @Test("형식은 기본 규범형이고, 구 저장분(키 없음)도 규범형으로 읽는다")
    func defaultsToFormal() throws {
        #expect(KeyboardSettings.default.dateSnippetStyle == .formal)
        let legacy = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(legacy.dateSnippetStyle == .formal)
    }

    @Test("고른 형식은 저장·복원된다", arguments: DateSnippetStyle.allCases)
    func roundTrip(style: DateSnippetStyle) throws {
        var settings = KeyboardSettings.default
        settings.dateSnippetStyle = style
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.dateSnippetStyle == style)
    }

    @Test("모르는 형식 값(다음 버전 저장분)이 와도 설정 전체를 잃지 않는다")
    func unknownStyleFallsBack() throws {
        let json = #"{"dateSnippetStyle": "future", "snippetsEnabled": false}"#
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: Data(json.utf8))
        #expect(decoded.dateSnippetStyle == .formal)
        #expect(decoded.snippetsEnabled == false, "다른 필드는 그대로 읽는다")
    }

    @Test("팩 id는 date이고 옵트아웃이라 기본 켬")
    func packID() {
        #expect(SnippetPack.date == "date")
        #expect(!KeyboardSettings.default.disabledSnippetPacks.contains(SnippetPack.date))
    }

    @Test("설정 화면 이름")
    func displayNames() {
        #expect(DateSnippetStyle.allCases.map(\.displayName) == ["규범형", "관행형", "한글형", "국제 표준(ISO 8601)"])
    }

    /// v1.3.1 국제 표준 형식(사용자 결정 2026-10-13). 저장 값은 `iso8601` — 바꾸면 고른 사용자의 설정이 규범형으로 떨어진다
    @Test("형식은 넷이고, 국제 표준은 맨 뒤에 붙는다 — 저장 값 iso8601")
    func fourStyles() {
        #expect(DateSnippetStyle.allCases == [.formal, .common, .korean, .iso8601])
        #expect(DateSnippetStyle.iso8601.rawValue == "iso8601")
    }

    @Test("저장분의 iso8601을 국제 표준으로 읽는다")
    func decodesISO8601() throws {
        let json = #"{"dateSnippetStyle": "iso8601"}"#
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: Data(json.utf8))
        #expect(decoded.dateSnippetStyle == .iso8601)
    }
}

@Suite("날짜 채움글 — 사용자 단축어 겹침 경고 (3-5절)")
struct DateSnippetOverlapWarningTests {

    @Test("「날짜」·「시간」·「시각」으로 끝나면 경고 — 띄어쓰기는 보지 않는다", arguments: [
        ["날짜"], ["오늘 날짜"], ["마감 날 짜"], ["집주소", "출근 시간"], ["지금시각"]
    ])
    func warns(triggers: [String]) {
        #expect(SnippetEntry.mayOverlapDateSnippets(triggers))
    }

    @Test("그 외는 경고하지 않는다", arguments: [
        ["집주소"], ["날짜표"], ["시간표", "우리집"], [], ["시"]
    ])
    func doesNotWarn(triggers: [String]) {
        #expect(!SnippetEntry.mayOverlapDateSnippets(triggers))
    }
}

/// B5 E13 — 「영어 추천단어」 스위치(N12, 기본 켬). 옛 저장분은 켬, 왕복, 상위 추천단어 끔 = 영어도 끔
@Suite("B5 E13 — 영어 추천단어 설정")
struct EnglishSuggestionSettingsTests {

    @Test("기본 켬 · 옛 저장분(키 없음)도 켬 · 왕복")
    func defaultsAndRoundTrip() throws {
        #expect(KeyboardSettings.default.englishSuggestionsEnabled)
        let legacy = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(legacy.englishSuggestionsEnabled)
        var settings = KeyboardSettings.default
        settings.englishSuggestionsEnabled = false
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.englishSuggestionsEnabled == false)
    }

    @Test("상위 추천단어 끔 = 영어도 끔 · secure 끔")
    func gate() {
        var settings = KeyboardSettings.default
        #expect(settings.allowsEnglishSuggestions(isSecureTextEntry: false))
        #expect(!settings.allowsEnglishSuggestions(isSecureTextEntry: true))
        settings.suggestionsEnabled = false
        #expect(!settings.allowsEnglishSuggestions(isSecureTextEntry: false))
        settings.suggestionsEnabled = true
        settings.englishSuggestionsEnabled = false
        #expect(!settings.allowsEnglishSuggestions(isSecureTextEntry: false))
    }
}
