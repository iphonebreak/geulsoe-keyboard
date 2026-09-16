import Foundation
import Testing
@testable import KeyboardCore

/// 붙여넣기 칩 — 클립보드 원문에서 **툴바 한 줄**을 만든다 (사용자 요청 2026-09-15:
/// "네이버키보드와 동일하게 1줄로 보여준다 '복사했어요 맘에 드십니...' 이런식으로 보여주고
/// 누르면 붙여넣기가 됨").
@Suite("붙여넣기 칩 미리보기")
struct PasteSuggestionPreviewTests {

    @Test("여러 줄은 한 줄로 접는다 — 줄바꿈·탭·연속 공백이 공백 하나가 된다", arguments: [
        ("첫 줄\n둘째 줄", "첫 줄 둘째 줄"),
        ("앞\t뒤", "앞 뒤"),
        ("여러   공백", "여러 공백"),
        ("\n\n  가운데  \n\n", "가운데"),
        ("줄1\r\n줄2", "줄1 줄2")
    ])
    func foldsToOneLine(testCase: (String, String)) {
        #expect(PasteSuggestion.previewLine(from: testCase.0) == testCase.1)
    }

    /// 상한은 **40자**다. 근거는 `PasteSuggestion.previewLimit` 주석 참조 —
    /// 아이폰에서 실제로 보이는 글자 수(가장 넓은 기기에서도 30자 남짓)보다 넉넉히 크게 두어
    /// **화면상의 말줄임은 SwiftUI 가 기기 폭에 맞춰** 하도록 두고, 이 상한은 원문이 아무리 길어도
    /// 우리가 만드는 문자열의 크기를 묶는 역할만 한다.
    @Test("40자를 넘으면 자르고 말줄임표를 붙인다")
    func truncatesBeyondLimit() {
        let long = String(repeating: "가", count: 100)
        let preview = PasteSuggestion.previewLine(from: long)
        #expect(preview.count == PasteSuggestion.previewLimit + 1, "40자 + 말줄임표 1자")
        #expect(preview.hasSuffix("…"))
        #expect(preview.hasPrefix(String(repeating: "가", count: 10)))
    }

    @Test("딱 40자면 자르지 않는다 — 말줄임표는 실제로 잘렸을 때만 붙는다")
    func doesNotTruncateAtExactlyLimit() {
        let exact = String(repeating: "나", count: PasteSuggestion.previewLimit)
        #expect(PasteSuggestion.previewLine(from: exact) == exact)
        #expect(!PasteSuggestion.previewLine(from: exact).hasSuffix("…"))
    }

    /// **접은 뒤의 길이로 자른다.** 줄바꿈이 잔뜩 든 짧은 글이 공백 때문에 잘리면 안 된다.
    @Test("줄바꿈이 많아도 접은 결과가 40자 이하면 그대로 보인다")
    func foldsBeforeMeasuring() {
        let text = (1...10).map { "줄\($0)" }.joined(separator: "\n\n\n")
        #expect(!PasteSuggestion.previewLine(from: text).hasSuffix("…"))
    }

    @Test("이모지·결합 문자도 글자 단위로 센다 — 중간에서 깨지지 않는다")
    func countsGraphemeClusters() {
        let preview = PasteSuggestion.previewLine(from: String(repeating: "👨‍👩‍👧‍👦", count: 50))
        #expect(preview.count == PasteSuggestion.previewLimit + 1)
        #expect(preview.dropLast().allSatisfy { $0 == "👨‍👩‍👧‍👦" }, "가족 이모지가 쪼개지지 않는다")
    }
}

@Suite("붙여넣기 칩 — 인증번호와 일반 텍스트의 공존")
struct PasteSuggestionKindTests {

    /// **인증번호가 뽑히면 그쪽이 이긴다.** 번호만 보여주는 편이 명확하고, 사용자가
    /// "인증번호만 잘 보여주고 붙여넣기가 가능하도록"이라고 못박았다.
    /// 두 칩이 동시에 뜨는 일은 없다 (설계 C-4).
    @Test("인증번호가 뽑히면 인증번호 칩이다 — 넣는 것도 번호만")
    func codeWins() throws {
        let clipboard = "[Web발신]\n인증번호 483920 를 입력하세요"
        let suggestion = try #require(PasteSuggestion.make(from: clipboard))
        #expect(suggestion.kind == .verificationCode)
        #expect(suggestion.preview == "483920")
        #expect(suggestion.insertText == "483920", "원문 전체가 아니라 번호만 넣는다")
    }

    /// **탭하면 원문 전체가 들어간다** — 칩에 보인 미리보기가 아니다.
    /// 그래서 잘렸다는 것을 말줄임표로 반드시 알린다.
    @Test("일반 텍스트는 미리보기만 자르고, 넣는 것은 원문 전체다")
    func textInsertsWholeOriginal() throws {
        let clipboard = String(repeating: "가", count: 100)
        let suggestion = try #require(PasteSuggestion.make(from: clipboard))
        #expect(suggestion.kind == .text)
        #expect(suggestion.preview.count == PasteSuggestion.previewLimit + 1)
        #expect(suggestion.insertText == clipboard, "원문 100자가 그대로 들어간다")
    }

    /// **비밀번호로 거르지 않는다** — 사용자 명시 결정(2026-09-15):
    /// "비밀번호 관련 없이 모두 보여준다 복사했으면". 복사한 것은 사용자가 복사한 것이다.
    /// (붙여넣을 **입력란**이 `isSecureTextEntry` 인 경우는 별개 규칙이고 호출자가 막는다.)
    @Test("비밀번호처럼 보이는 문자열도 그대로 칩이 된다", arguments: [
        "Hunter2!@#", "correct horse battery staple", "p@ssw0rd"
    ])
    func doesNotFilterSecretLookingText(text: String) throws {
        let suggestion = try #require(PasteSuggestion.make(from: text))
        #expect(suggestion.kind == .text)
        #expect(suggestion.insertText == text)
    }

    @Test("비었거나 공백뿐이면 칩이 없다", arguments: ["", "   ", "\n\n", "\t"])
    func noChipForBlank(text: String) {
        #expect(PasteSuggestion.make(from: text) == nil)
    }
}

@Suite("붙여넣기 칩 — 설정 스위치 두 개의 조합")
struct PasteSuggestionSettingsTests {

    private let code = "인증번호 483920 입니다"
    private let plain = "https://example.com/very/long/path"

    /// **인증번호만 끄면** 인증번호 문자도 일반 칩으로 뜬다 — 그 사용자는 "내용을 보여 주는 것"은
    /// 허락했고 "번호만 뽑는 특별 취급"만 껐다. 칩이 통째로 사라지는 것이 오히려 놀랍다.
    @Test("인증번호 스위치만 끄면 인증번호 문자도 일반 칩이 된다")
    func codeOffFallsBackToText() throws {
        let suggestion = try #require(PasteSuggestion.make(from: code, allowsCode: false, allowsText: true))
        #expect(suggestion.kind == .text)
        #expect(suggestion.insertText == code, "번호만이 아니라 문자 전문이 들어간다")
    }

    /// **일반만 끄면** 인증번호는 그대로 뜬다 — 예전(v1.0.0) 동작이다.
    @Test("일반 스위치만 끄면 인증번호 칩은 그대로다")
    func textOffKeepsCode() throws {
        let suggestion = try #require(PasteSuggestion.make(from: code, allowsCode: true, allowsText: false))
        #expect(suggestion.kind == .verificationCode)
        #expect(PasteSuggestion.make(from: plain, allowsCode: true, allowsText: false) == nil)
    }

    @Test("둘 다 끄면 아무 칩도 없다", arguments: ["인증번호 483920 입니다", "아무 문장"])
    func bothOffMeansNoChip(text: String) {
        #expect(PasteSuggestion.make(from: text, allowsCode: false, allowsText: false) == nil)
    }
}
