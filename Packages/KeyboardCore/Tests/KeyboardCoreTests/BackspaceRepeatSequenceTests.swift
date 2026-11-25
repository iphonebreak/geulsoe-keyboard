import Foundation
import Testing
import HangulEngine
@testable import KeyboardCore

// ⌫ 길게 누르기 단어 단계 — `InputController` 박자 처리(PDR `docs/design-reviews/backspace-word-acceleration.md` 3-1·3-2·5절).
//
// 박자 순서는 KeyboardUI 시간표(1-1)가 정한다: 터치다운 ⌫ → 글자 박자 22회(0.5~2.18초) → 2.30초 읽기 전용 닻 → 2.6초부터 0.35초마다 단어 박자.
// 여기서는 VC가 박자를 받아 부르는 순서 그대로 컨트롤러를 부른다. 문장은 전부 합성이다.

/// 박자 시험용 호스트 문서 — 문맥 읽기·선택·지움 단위를 조절한다
final class BackspaceHostDocument: TextOutput {
    enum Read {
        /// 실제 문서를 그대로 낸다
        case fresh
        /// 누름 동안 값이 멈춘 읽기(반론 CW-01 B5 — 가상 호스트)
        case frozen(String)
        /// 문맥을 주지 않는 호스트(secure 등)
        case none
    }

    private(set) var text: String
    var read: Read = .fresh
    /// 끝에서부터 선택된 글자 수 — 다음 `deleteBackward` 한 번이 선택을 통째로 지운다
    var selectedSuffix = 0
    /// 호출 한 번에 더 지우는 글자 수 — 우리 예상과 다르게 지우는 호스트(반론 CW-01 「공백 2자 삭제」류, 가상)
    var extraDeletionPerCall = 0
    /// 지우기 호출 n회 중 1회를 무시하는 간헐 이상 호스트(검증 F1 ①, 가상). 0이면 끔
    var ignoresEveryNthCall = 0
    private var deleteCalls = 0

    /// 바깥에서 문서를 바꾼다 — 커서 이동·다른 손가락 편집 흉내
    func externallyReplace(with text: String) {
        self.text = text
    }

    init(_ text: String = "") {
        self.text = text
    }

    func insertText(_ inserted: String) {
        text += inserted
    }

    func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            deleteCalls += 1
            if selectedSuffix > 0 {
                text = String(text.dropLast(selectedSuffix))
                selectedSuffix = 0
            } else if ignoresEveryNthCall > 0, deleteCalls % ignoresEveryNthCall == 0 {
                continue
            } else {
                text = String(text.dropLast(1 + extraDeletionPerCall))
            }
        }
    }

    var hasSelectedText: Bool { selectedSuffix > 0 }

    var documentContextBeforeInput: String? {
        switch read {
        case .fresh: text
        case .frozen(let value): value
        case .none: nil
        }
    }
}

@MainActor
@Suite("⌫ 단어 단계 — 박자 처리 (InputController)")
struct BackspaceRepeatSequenceTests {

    private let hold: UInt64 = 1

    private func englishController(_ document: BackspaceHostDocument) -> InputController {
        InputController(output: document, startsInHangul: false)
    }

    /// 닻(2.30초) 뒤 단어 박자를 `count`번 — 결과 목록
    private func anchorThenWords(_ controller: InputController, _ count: Int, documentIdentifier: UUID? = nil) -> [BackspaceRepeatOutcome] {
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: documentIdentifier)
        return (0..<count).map { _ in
            controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: documentIdentifier)
        }
    }

    private func wordSteps(_ outcomes: [BackspaceRepeatOutcome]) -> Int {
        outcomes.filter { if case .deletedWords = $0 { true } else { false } }.count
    }

    @Test("글자 박자도 끝낸 누름이면 받지 않는다 — 손 뗀 뒤 예약 박자 0 (폐기 조건 1)")
    func characterTickAfterHoldEndedIsNotAccepted() {
        let document = BackspaceHostDocument("one two")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        controller.endBackspaceHold(hold)
        #expect(!controller.acceptsBackspaceTick(hold))
        #expect(controller.handleBackspaceRepeat(hold, phase: .character, documentIdentifier: nil) == .ignored)
        #expect(document.text == "one two")
    }

    @Test("살아 있는 누름의 글자 박자는 현행 ⌫ 1회")
    func characterTickOfLiveHoldDeletesOne() {
        let document = BackspaceHostDocument("one two")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.acceptsBackspaceTick(hold))
        #expect(controller.handleBackspaceRepeat(hold, phase: .character, documentIdentifier: nil) == .backspaces(count: 1))
        #expect(document.text == "one tw")
    }

    @Test("닻 뒤 단어 박자는 두 단위를 지우고 꼬리를 문서로 다시 세운다")
    func anchorThenWordTickDeletesTwoWords() {
        let document = BackspaceHostDocument("one two three four five six")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil) == .anchored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .deletedWords(count: 9))
        #expect(document.text == "one two three four")
        #expect(controller.textTail == "one two three four")
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .deletedWords(count: 11))
        #expect(document.text == "one two")
    }

    @Test("닻은 읽기 전용 — 지우지 않고 리비전도 그대로")
    func anchorIsReadOnly() {
        let document = BackspaceHostDocument("one two three")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        let revision = controller.documentRevision
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        #expect(document.text == "one two three")
        #expect(controller.documentRevision == revision)
    }

    @Test("조합 중이면 단어 박자는 현행 ⌫ 최대 4회 — 조합이 끝나면 멈춘다 (두벌식)")
    func wordTickWhileComposingDoesAtMostFourAutomatonBackspaces() {
        let document = BackspaceHostDocument()
        let controller = InputController(output: document)
        for key in ["r", "k", "s", "k"] { controller.handle(.character(key)) }   // 가나
        controller.handle(.space)
        for key in ["g", "k", "s", "r", "m", "f"] { controller.handle(.character(key)) }   // 한글 — 「글」 조합 중
        #expect(document.text == "가나 한글")
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil) == .ignored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 3))
        #expect(document.text == "가나 한")
    }

    @Test("ⓔ 천지인 40타 붙여 쓰기 — 키 로그가 4.00초 박자에 다 걷힌다 (CW-03)")
    func cheonjiinLongLogClearsAtCharacterSpeed() {
        let document = BackspaceHostDocument()
        let controller = InputController(output: document, hangulSource: CheonjiinSource())
        for _ in 0..<20 {
            controller.handle(.character("ㄴ"))
            controller.handle(.character("ㅣ"))
        }
        #expect(controller.hasBackspaceReplayState)
        // 터치다운 1회 + 글자 박자 22회(0.5~2.18초)
        controller.handle(.backspace)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        for _ in 0..<22 { _ = controller.handleBackspaceRepeat(hold, phase: .character, documentIdentifier: nil) }
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        var wordTicks = 0
        while controller.hasBackspaceReplayState, wordTicks < 20 {
            _ = controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil)
            wordTicks += 1
        }
        // 2.6 + 0.35 × (wordTicks − 1)초에 끝난다 — 4.00초면 5박자
        #expect(wordTicks <= 5)
    }

    @Test("선택이 있으면 단어 박자는 선택 삭제 1회")
    func wordTickWithSelectionDeletesSelectionOnce() {
        let document = BackspaceHostDocument("alpha bravo charlie")
        document.selectedSuffix = 7
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil) == .ignored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 1))
        #expect(document.text == "alpha bravo ")
    }

    @Test("ⓕ 문서 식별자가 바뀌면 단어 단계만 끄고 글자 단위(4자)로 계속 (CW-05)")
    func documentIdentifierChangeTurnsOffWordPhaseOnly() {
        let first = UUID()
        let second = UUID()
        let document = BackspaceHostDocument("one two three four five six seven")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: first)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: first) == .anchored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: second) == .backspaces(count: 4))
        #expect(document.text == "one two three four five six s")
        // 처음 문서로 돌아와도 이 누름의 단어 단계는 꺼진 채다
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: first) == .backspaces(count: 4))
        #expect(controller.acceptsBackspaceTick(hold))
    }

    @Test("문맥이 없으면 단어 박자는 4자 폴백")
    func nilContextFallsBackToFourCharacters() {
        let document = BackspaceHostDocument("one two three")
        document.read = .none
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil) == .ignored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 4))
        #expect(document.text == "one two t")
    }

    @Test("20자 넘는 토큰은 4자씩 — 신선성은 그대로 이어진다")
    func fallbackWhenWordTooLongDeletesFour() {
        let token = String(repeating: "x", count: 30)
        let document = BackspaceHostDocument("abc " + token)
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        let outcomes = anchorThenWords(controller, 3)
        #expect(outcomes == [.backspaces(count: 4), .backspaces(count: 4), .backspaces(count: 4)])
        #expect(document.text == "abc " + String(repeating: "x", count: 18))
    }

    /// 반론2 C2W-02 — 폴백은 그 토큰이 없어질 때까지의 보호가 아니다. 매 박자 다시 재므로 20자 이하가 되는 박자에
    /// 남은 토큰과 앞 어절을 한 단계에 지운다(경계 21→17, 22→18)
    @Test("C2W-02 긴 토큰은 4자씩 줄다가 20자 이하가 되면 앞 어절과 함께 지운다", arguments: [
        (21, [BackspaceRepeatOutcome.backspaces(count: 4), .deletedWords(count: 21)]),
        (22, [.backspaces(count: 4), .deletedWords(count: 22)]),
        (26, [.backspaces(count: 4), .backspaces(count: 4), .deletedWords(count: 22)]),
    ])
    func longTokenFallsBackUntilTwentyThenDeletesWithPreviousWord(length: Int, expected: [BackspaceRepeatOutcome]) {
        let document = BackspaceHostDocument("KEEP ok " + String(repeating: "a", count: length))
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(anchorThenWords(controller, expected.count) == expected)
        #expect(document.text == "KEEP")
    }

    @Test("검증 F1 ① 간헐 이상 호스트(호출 n회 중 1회 무시) — 잘못된 단어 단계는 누름당 1회 이하 (A)", arguments: [5, 7, 9, 11, 13])
    func intermittentHostDeletesAtMostOneWrongWordStepPerHold(period: Int) {
        let document = BackspaceHostDocument((1...40).map { "word\($0)" }.joined(separator: " "))
        document.ignoresEveryNthCall = period
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        var wrongWordSteps = 0
        for _ in 0..<20 {
            let before = document.text.count
            let outcome = controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil)
            if case .deletedWords(let count) = outcome, before - document.text.count != count { wrongWordSteps += 1 }
        }
        #expect(wrongWordSteps <= 1)
    }

    @Test("검증 반영 A — 단어 단계 바로 뒤 박자가 불일치면 그 누름의 단어 단계를 끈다")
    func mismatchRightAfterWordStepTurnsOffWordPhase() {
        let document = BackspaceHostDocument("zero one two three four five six seven eight nine")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .deletedWords(count: 11))
        document.externallyReplace(with: "zero one two three four five six")   // 커서 이동·외부 편집 한 번
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 4))
        // 문서가 다시 신선해도 이 누름에서는 단어 단계를 쓰지 않는다
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 4))
    }

    @Test("검증 반영 D — 불일치 뒤 박자는 지우지 않는 닻(k = 0), 다음 박자에 단어 단계")
    func mismatchAfterAnchorReanchorsWithoutDeleting() {
        let document = BackspaceHostDocument("zero one two three four five six")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        document.externallyReplace(with: "zero one two three four five")   // 닻 뒤 바깥 변화 — 단어 단계 직후가 아니다
        let revision = controller.documentRevision
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .anchored)
        #expect(document.text == "zero one two three four five")
        #expect(controller.documentRevision == revision)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .deletedWords(count: 10))
        #expect(document.text == "zero one two three")
    }

    @Test("검증 F2 — 조합·키 로그가 많아도 단어 박자 하나에 현행 ⌫는 4회까지")
    func composingTickCapsAtFourBackspaces() {
        let document = BackspaceHostDocument()
        let controller = InputController(output: document, hangulSource: CheonjiinSource())
        for _ in 0..<20 {
            controller.handle(.character("ㄴ"))
            controller.handle(.character("ㅣ"))
        }
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 4))
        #expect(controller.hasBackspaceReplayState)
    }

    @Test("검증 F2 — 새 누름이 시작되면 옛 누름의 박자는 버린다(컨트롤러)")
    func oldHoldTickIsDroppedAfterNewHoldBegins() {
        let document = BackspaceHostDocument("one two three")
        let controller = englishController(document)
        controller.beginBackspaceHold(1, documentIdentifier: nil)
        controller.beginBackspaceHold(2, documentIdentifier: nil)
        #expect(!controller.acceptsBackspaceTick(1))
        #expect(controller.handleBackspaceRepeat(1, phase: .character, documentIdentifier: nil) == .ignored)
        #expect(controller.handleBackspaceRepeat(1, phase: .word, documentIdentifier: nil) == .ignored)
        #expect(document.text == "one two three")
        #expect(controller.acceptsBackspaceTick(2))
    }

    @Test("검증 F2 — 누름이 끝나면 세션(문맥 사본)을 버린다")
    func endingHoldClearsSession() {
        let document = BackspaceHostDocument("one two three")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil)
        #expect(controller.hasBackspaceSession)
        controller.endBackspaceHold(hold)
        #expect(!controller.hasBackspaceSession)
        controller.beginBackspaceHold(hold + 1, documentIdentifier: nil)
        _ = controller.handleBackspaceRepeat(hold + 1, phase: .anchor, documentIdentifier: nil)
        controller.endAllBackspaceHolds()
        #expect(!controller.hasBackspaceSession)
    }

    @Test("검증 F6 — 단모음 연타 승격 조합 중이면 현행 ⌫ 의미 먼저")
    func danmoeumPromotedComposingFollowsExistingBackspace() {
        let document = BackspaceHostDocument()
        let controller = InputController(output: document, hangulSource: DanmoeumSource(), clock: { 0 })
        for key in ["ㄴ", "ㅏ"] { controller.handle(.character(key)) }
        controller.handle(.space)
        for key in ["ㄱ", "ㅏ", "ㅏ"] { controller.handle(.character(key)) }   // ㅏㅏ → ㅑ 승격, 「갸」 조합 중
        #expect(document.text == "나 갸")
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        #expect(controller.handleBackspaceRepeat(hold, phase: .anchor, documentIdentifier: nil) == .ignored)
        #expect(controller.handleBackspaceRepeat(hold, phase: .word, documentIdentifier: nil) == .backspaces(count: 2))
        #expect(document.text == "나 ")
        #expect(!controller.hasBackspaceReplayState)
    }

    @Test("ⓖ 우리 예상과 다르게 지우는 호스트 — 잘못된 단어 단계는 누름당 1회 (CW-01)")
    func optimisticHostMisdeleteStopsAfterOneWrongStep() {
        // 읽기는 바로잡힌 실제 값(다음 박자 전에 바로잡힘 — 낙관 사본 모형에서 감지 가능한 쪽)
        let document = BackspaceHostDocument((1...20).map { "word\($0)" }.joined(separator: " "))
        document.extraDeletionPerCall = 1
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        let outcomes = anchorThenWords(controller, 8)
        #expect(wordSteps(outcomes) == 1)
    }

    @Test("ⓗ 누름 동안 멈춘 읽기 — 잘못된 단어 단계는 누름당 최대 1회 (CW-01)")
    func frozenReadDeletesAtMostOneWordStepPerHold() {
        let initial = (1...20).map { "word\($0)" }.joined(separator: " ")
        let document = BackspaceHostDocument(initial)
        document.read = .frozen(initial)
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        let outcomes = anchorThenWords(controller, 8)
        #expect(wordSteps(outcomes) == 1)
        // 꺼진 뒤에는 4자 폴백(글자 단계 속도)으로 계속 지운다
        #expect(outcomes.last == .backspaces(count: 4))
    }

    @Test("단어 단계 뒤 꼬리는 문서로 다시 서고, 꼬리 끝 한글 어절은 학습하지 않는다")
    func wordTickRebuildsTailFromDocumentAndBlocksLearningForHangulRun() {
        let document = BackspaceHostDocument("오늘은 날씨가 정말 좋네요")
        let controller = InputController(output: document)
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = anchorThenWords(controller, 1)
        #expect(document.text == "오늘은 날씨가")
        #expect(controller.textTail == "오늘은 날씨가")
        #expect(!controller.textTailIsTruncated)
        controller.endBackspaceHold(hold)
        controller.handle(.space)
        #expect(!learned.contains("날씨가"))
    }

    @Test("C7 — 단어 박자는 ⏎ 스냅샷을 쓰지 않고 문서로 꼬리를 세운다")
    func wordTickDoesNotReadReturnSnapshot() {
        let document = BackspaceHostDocument()
        let controller = englishController(document)
        controller.returnKeyIsDefault = true
        for character in "abc def" { controller.handle(character == " " ? .space : .character(String(character))) }
        controller.handle(.return)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = anchorThenWords(controller, 1)
        // 개행 한 단위 + `def`와 앞 공백 — 남은 문서가 꼬리다
        #expect(document.text == "abc")
        #expect(controller.textTail == "abc")
    }

    /// 지우기 전 마지막 키가 스페이스였어도(더블스페이스 시각 안) 단어 박자 뒤 스페이스는 공백 하나다 — 연쇄를 끊는다
    @Test("단어 박자 뒤 스페이스는 그냥 공백 — 더블스페이스 연쇄를 끊는다")
    func wordTickClearsMultiTapAndDoubleSpace() {
        let document = BackspaceHostDocument()
        let controller = InputController(output: document, startsInHangul: false, clock: { 100 })
        for character in "one two three four " {
            controller.handle(character == " " ? .space : .character(String(character)))
        }
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        _ = anchorThenWords(controller, 1)
        #expect(document.text == "one two")
        controller.endBackspaceHold(hold)
        controller.handle(.space)
        #expect(document.text == "one two ")
    }

    @Test("단어 박자는 문서 리비전을 올린다 — 이모지 칩 숨김 해제(D17)")
    func wordTickIncrementsDocumentRevision() {
        let document = BackspaceHostDocument("one two three")
        let controller = englishController(document)
        controller.beginBackspaceHold(hold, documentIdentifier: nil)
        let revision = controller.documentRevision
        _ = anchorThenWords(controller, 1)
        #expect(controller.documentRevision > revision)
    }
}
