import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// codex 반론 v1.3.0(키보드) K1·K4 — 사장님 결정 2026-10-08, 반론 원문 `docs/release/counter-v130-codex-kb.md` #1·#4.
//
// K1: 본문이 자기 단축어로 끝나는 채움글(「주소 → 서울 주소」)을 넣으면 같은 칩이 곧바로 다시 떠, 퇴장 중(0.28초) 옛 칩 재탭이
//     VC의 동일성 검사와 꼬리 정합을 모두 통과해 `서울 서울 주소`가 됐다. → 삽입 뒤 **문서가 바뀌기 전까지**(documentRevision)
//     채움글 칩·U7·성경 배지·`insertSnippet`을 보류한다(코디네이터 회신 A안 — 경계를 걸친 구간까지 닫는다).
// K4: 선택 영역이 있으면 첫 `deleteBackward`가 선택 영역을 지워 지울 개수가 어긋난다. → 지우고 넣는 치환(채움글·U7·성경 행·
//     이모지 칩·추천단어 탭)을 거절한다(문서 무변경). 표시도 같은 입력으로 막는다.

/// 조립 지점(`updateSuggestionBar`)의 채움글 칩 식 그대로 — 매처 결과 → K1·K4 → 칩 게이트
@MainActor
private func visibleChip(_ controller: InputController, _ matcher: SnippetMatcher) -> SnippetSuggestion? {
    SnippetChipGate.visibleSnippet(
        matcher.suggestion(forTail: controller.textTail, isSecureTextEntry: false),
        isDismissed: false, hasPasteChip: false,
        allowsInsertion: ReplacementGate.allowsSnippetInsertion(
            isHeldAfterInsertion: controller.holdsSnippetsAfterInsertion, hasSelectedText: controller.hasSelectedText))
}

/// 두벌식 키 — 「주소」
private let jusoKeys = ["w", "n", "t", "h"]

@Suite("치환 게이트 — 순수 판정 표 (K1·K4)")
struct ReplacementGateTableTests {

    @Test("K4 선택 영역 — 있으면 치환하지 않는다", arguments: [(false, true), (true, false)])
    func allowsReplacement(_ row: (hasSelectedText: Bool, allowed: Bool)) {
        #expect(ReplacementGate.allowsReplacement(hasSelectedText: row.hasSelectedText) == row.allowed)
    }

    @Test("K1 보류 — 마지막 채움글 삽입 뒤 문서 쓰기 횟수가 그대로면 보류", arguments: [
        (nil as Int?, 0, false),   // 삽입한 적 없음
        (nil, 7, false),
        (3, 3, true),              // 삽입 직후 — 아무 편집 없음
        (3, 4, false),             // 한 글자라도 쓰거나 지웠다
        (3, 9, false),
    ])
    func holdsSnippets(_ row: (insertedAt: Int?, revision: Int, holds: Bool)) {
        #expect(ReplacementGate.holdsSnippets(revisionAfterSnippetInsertion: row.insertedAt, documentRevision: row.revision) == row.holds)
    }

    @Test("채움글 삽입 경로(칩·U7·성경 배지) — 보류도 선택 영역도 없을 때만", arguments: [
        (false, false, true), (true, false, false), (false, true, false), (true, true, false),
    ])
    func allowsSnippetInsertion(_ row: (held: Bool, selected: Bool, allowed: Bool)) {
        #expect(ReplacementGate.allowsSnippetInsertion(isHeldAfterInsertion: row.held, hasSelectedText: row.selected) == row.allowed)
    }

    @Test("채움글 칩 게이트 — 붙여넣기 칩·✕ 숨김·삽입 불가 중 하나라도 있으면 없음 (D19·K1·K4)")
    func snippetChipGate() {
        let matched = SnippetSuggestion(trigger: "주소", title: "주소", body: "서울 주소")
        for isDismissed in [false, true] {
            for hasPasteChip in [false, true] {
                for allowsInsertion in [false, true] {
                    let shown = SnippetChipGate.visibleSnippet(
                        matched, isDismissed: isDismissed, hasPasteChip: hasPasteChip, allowsInsertion: allowsInsertion)
                    #expect((shown != nil) == (!isDismissed && !hasPasteChip && allowsInsertion))
                }
            }
        }
    }

    @Test("추천단어(이모지 칩 포함) 게이트 — 선택 영역이 있으면 계산하지 않는다 (K4)")
    func wordGate() {
        #expect(!WordSuggestionGate.allowsWords(
            isSecureTextEntry: false, hasSnippet: false, hasPasteChip: false, hasSelectedText: true,
            isDismissed: false, isSuppressedAfterCursorMove: false))
        #expect(WordSuggestionGate.allowsWords(
            isSecureTextEntry: false, hasSnippet: false, hasPasteChip: false, hasSelectedText: false,
            isDismissed: false, isSuppressedAfterCursorMove: false))
    }
}

@MainActor
@Suite("K1 — 본문이 자기 단축어로 끝나는 채움글: 삽입 뒤 편집 전까지 보류")
struct SnippetInsertionHoldTests {

    let output = RecordingOutput()
    let controller: InputController
    let matcher = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "주소", title: "주소", body: "서울 주소")])

    init() {
        controller = InputController(output: output)
        for key in jusoKeys { controller.handle(.character(key)) }
    }

    /// 표 1행 — 「주소」 → 칩 탭 → 「서울 주소」. 매처는 여전히 「주소」를 맞히지만 칩은 없다
    @Test("① 탭하면 「서울 주소」, 칩은 다시 뜨지 않는다")
    func noChipAfterInsertion() throws {
        let chip = try #require(visibleChip(controller, matcher))
        #expect(controller.insertSnippet(chip))
        #expect(output.text == "서울 주소")
        #expect(matcher.suggestion(forTail: controller.textTail) != nil, "전제 — 꼬리는 다시 단축어로 끝난다")
        #expect(controller.holdsSnippetsAfterInsertion)
        #expect(visibleChip(controller, matcher) == nil)
    }

    /// 표 2행 — 퇴장 중(0.28초) 옛 칩 재탭. 꼬리 정합은 통과하지만(같은 「주소」) 보류가 거절한다
    @Test("② 둘째 탭은 아무 것도 하지 않는다 — `서울 서울 주소`가 되지 않는다")
    func secondTapIsRejected() throws {
        let chip = try #require(visibleChip(controller, matcher))
        #expect(controller.insertSnippet(chip))
        let operations = output.operations
        #expect(controller.insertSnippet(chip) == false)
        #expect(output.operations == operations && output.text == "서울 주소")
        // 호스트 메아리(textDidChange)가 꼬리를 다시 세워도 문서가 안 바뀌었으므로 보류는 그대로다
        controller.syncWithDocument(documentTail: output.text)
        #expect(controller.insertSnippet(chip) == false)
        #expect(output.text == "서울 주소")
    }

    /// 표 3행 — 한 글자 치고 지우면(또는 지우고 다시 치면) 정상 판정. 다시 탭하는 것은 사용자의 선택이다
    @Test("③ 한 글자 치고 지우면 정상 — 칩이 다시 뜨고 넣어진다")
    func typingReleasesHold() throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        controller.handle(.character("r"))   // ㄱ
        #expect(!controller.holdsSnippetsAfterInsertion)
        controller.handle(.backspace)
        #expect(controller.textTail == "서울 주소")
        let again = try #require(visibleChip(controller, matcher), "편집 뒤에는 정상 판정")
        #expect(controller.insertSnippet(again))
        #expect(output.text == "서울 서울 주소")
    }

    @Test("③-2 한 글자 지우고 다시 쳐도 정상")
    func deletingReleasesHold() throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        controller.handle(.backspace)        // 「서울 주」
        #expect(!controller.holdsSnippetsAfterInsertion)
        for key in ["t", "h"] { controller.handle(.character(key)) }
        #expect(visibleChip(controller, matcher) != nil)
    }

    /// 문서를 안 바꾸는 키는 편집이 아니다 — 이모지 D17과 같은 기준(실제 쓰기 횟수)
    @Test("⇧·한영·123은 보류를 풀지 않는다", arguments: [KeyEvent.shift, .toggleLanguage, .symbols])
    func nonEditingKeysKeepHold(_ event: KeyEvent) throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        controller.handle(event)
        #expect(controller.holdsSnippetsAfterInsertion)
    }

    /// A안 부작용(보고서) — 커서만 옮긴 자리(문서 무변경)에서도 한 글자 칠 때까지 칩이 없다
    @Test("커서만 옮긴 뒤(sync)도 편집 전까지 보류 — A안 부작용")
    func cursorMoveKeepsHold() throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        controller.syncWithDocument(documentTail: nil)
        controller.syncWithDocument(documentTail: "다른 줄 주소")
        #expect(controller.holdsSnippetsAfterInsertion)
        #expect(visibleChip(controller, matcher) == nil)
    }

    /// 칩이 아닌 다른 채움글 삽입 경로(U7 다른 후보·성경 패널 행)도 같은 `insertSnippet` — 함께 보류된다
    @Test("U7 후보 행·성경 패널 행 모양의 삽입도 보류된다")
    func otherInsertionPathsAreHeld() throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        let operations = output.operations
        let row = SnippetSuggestion(trigger: "주소", title: "다른 후보", body: "부산 주소")
        let verse = SnippetSuggestion(trigger: "주소", title: "창 1:1", body: "태초에", prefix: "[창 1:1] ")
        #expect(controller.insertSnippet(row) == false)
        #expect(controller.insertSnippet(verse) == false)
        #expect(output.operations == operations)
    }

    /// 다른 칩 탭도 문서를 바꾸면 편집이다 — 이모지 칩(D17과 같은 기준)
    @Test("이모지 칩 탭(문서 변경)은 보류를 푼다")
    func emojiChipReleasesHold() throws {
        #expect(controller.insertSnippet(try #require(visibleChip(controller, matcher))))
        #expect(controller.replaceCurrentWord("주소", with: "🏠 주소"))
        #expect(!controller.holdsSnippetsAfterInsertion)
    }

    /// 거절된 삽입(꼬리 어긋남)은 보류를 만들지 않는다
    @Test("거절된 삽입은 보류를 만들지 않는다")
    func rejectedInsertionDoesNotHold() {
        #expect(controller.insertSnippet(SnippetSuggestion(trigger: "없는말", title: "t", body: "b")) == false)
        #expect(!controller.holdsSnippetsAfterInsertion)
        #expect(visibleChip(controller, matcher) != nil)
    }
}

@MainActor
@Suite("K1 — 기존과 같은 경우·경계를 걸친 구간")
struct SnippetInsertionHoldEdgeTests {

    /// 표 4행 — 본문이 단축어로 안 끝나면 기존과 같다: 칩 없음(매처가 안 맞힌다), 이어 치면 정상
    @Test("④ 본문이 단축어로 안 끝나면 기존과 같다")
    func bodyNotEndingWithTrigger() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "집", title: "우리 집", body: "서울시 어딘가 1")])
        for key in ["w", "l", "q"] { controller.handle(.character(key)) }   // 집
        let chip = try #require(visibleChip(controller, matcher))
        #expect(controller.insertSnippet(chip))
        #expect(output.operations.suffix(2) == [.delete(1), .insert("서울시 어딘가 1")], "삽입 시퀀스는 그대로")
        #expect(visibleChip(controller, matcher) == nil)
        controller.handle(.space)
        for key in ["w", "l", "q"] { controller.handle(.character(key)) }
        #expect(visibleChip(controller, matcher) == chip, "이어 치면 정상")
    }

    /// A안 — 삽입 전 글 + 본문에 걸친 구간(「가가나」 → 「가나」 → 다시 「가나」)도 닫힌다
    @Test("경계를 걸친 구간 — 삽입 전 글과 본문에 걸쳐 다시 맞아도 보류된다")
    func spanningSegmentIsHeld() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        let matcher = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "가나", title: "가나", body: "나")])
        for key in ["r", "k", "r", "k", "s", "k"] { controller.handle(.character(key)) }   // 가가나
        let chip = try #require(visibleChip(controller, matcher))
        #expect(controller.insertSnippet(chip))
        #expect(output.text == "가나")
        #expect(matcher.suggestion(forTail: controller.textTail) == chip, "전제 — 같은 후보가 다시 맞는다")
        #expect(visibleChip(controller, matcher) == nil)
        #expect(controller.insertSnippet(chip) == false)
        #expect(output.text == "가나")
    }
}

@MainActor
@Suite("K4 — 선택 영역이 있으면 지우고 넣는 치환을 거절한다")
struct SelectionReplacementTests {

    let output = RecordingOutput()
    let controller: InputController
    let matcher = SnippetMatcher(bible: nil, entries: [
        SnippetEntry(trigger: "주소", title: "주소", body: "서울 주소"),
        SnippetEntry(trigger: "주소", title: "회사 주소", body: "판교 주소"),
    ])

    init() {
        controller = InputController(output: output)
        for key in jusoKeys { controller.handle(.character(key)) }
    }

    @Test("채움글 칩 — 선택 영역이 있으면 칩이 없고, 탭이 와도 문서를 건드리지 않는다")
    func snippetChipRefused() throws {
        let chip = try #require(visibleChip(controller, matcher))
        output.hasSelectedText = true
        #expect(visibleChip(controller, matcher) == nil, "표시도 막는다")
        let operations = output.operations
        #expect(controller.insertSnippet(chip) == false)
        #expect(output.operations == operations && output.text == "주소")
        #expect(controller.isComposing, "조합 상태도 그대로 — 거절은 아무 것도 하지 않는다")
        #expect(!controller.holdsSnippetsAfterInsertion, "거절은 보류를 만들지 않는다")
        output.hasSelectedText = false
        #expect(visibleChip(controller, matcher) != nil, "선택이 풀리면 다시 뜬다")
        #expect(controller.insertSnippet(chip))
        #expect(output.text == "서울 주소")
    }

    @Test("U7 후보 행·성경 패널 행도 같은 경로 — 거절")
    func candidateRowsRefused() {
        let rows = matcher.candidates(forTail: controller.textTail, isSecureTextEntry: false)
        #expect(rows.count == 2)
        output.hasSelectedText = true
        let operations = output.operations
        for row in rows { #expect(controller.insertSnippet(row.suggestion) == false) }
        #expect(controller.insertSnippet(SnippetSuggestion(trigger: "주소", title: "창 1:1", body: "태초에", prefix: "[창 1:1] ")) == false)
        #expect(output.operations == operations)
    }

    @Test("이모지 칩(replaceCurrentWord) — 거절, 선택이 풀리면 정상")
    func emojiChipRefused() {
        output.hasSelectedText = true
        let operations = output.operations
        #expect(controller.replaceCurrentWord("주소", with: "🏠 주소") == false)
        #expect(output.operations == operations)
        output.hasSelectedText = false
        #expect(controller.replaceCurrentWord("주소", with: "🏠 주소"))
        #expect(output.text == "🏠 주소")
    }

    @Test("추천단어 탭(completeWord) — 거절, 선택이 풀리면 정상")
    func wordCompletionRefused() {
        output.hasSelectedText = true
        let operations = output.operations
        #expect(controller.completeWord("주소록") == false)
        #expect(output.operations == operations)
        output.hasSelectedText = false
        #expect(controller.completeWord("주소록"))
        #expect(output.text == "주소록")
    }

    /// 선택 영역에서도 타이핑·⌫는 그대로다 — 거절은 지우고 넣는 **치환**만이다(호스트가 선택 영역을 바꾸고 sync가 꼬리를 다시 세운다)
    @Test("선택 영역이 있어도 키 입력은 막지 않는다")
    func typingIsNotBlocked() {
        output.hasSelectedText = true
        let count = output.operations.count
        controller.handle(.character("r"))
        #expect(output.operations.count > count)
    }
}
