import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 실제 번들(CLDR 48.2·손질 목록 v1)의 값을 옮긴 fake 역색인 — 조회 횟수를 센다.
private final class CountingEmojiIndex: EmojiAnnotationIndex, @unchecked Sendable {
    static let cldr: [String: EmojiAnnotation] = [
        "자동차": EmojiAnnotation(emojis: ["🚕", "🚗", "🚘", "🛻", "🛞"], nameMatch: "🚗"),
        "가지": EmojiAnnotation(emojis: ["🍆"], nameMatch: "🍆")
    ]
    private(set) var lookups = 0

    func annotation(for word: String) -> EmojiAnnotation? {
        lookups += 1
        return Self.cldr[word]
    }
}

/// 결정적 난수원(SplitMix64) — 난수를 몇 번 썼는지로 「새로 뽑았나」를 본다.
private struct CountingGenerator: RandomNumberGenerator {
    private var state: UInt64
    private(set) var draws = 0

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        draws += 1
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 조립 지점(`KeyboardViewController.updateSuggestionBar`)과 **같은 순서**로 부르는 하네스 —
/// 키 입력은 처리 뒤 **문서 글자가 바뀌었을 때만** `documentDidChange()`(D17)를 부르고 `isUserEdit: true`,
/// 호스트 `textDidChange`는 `syncWithDocument` 뒤 `false`. 키보드 재표시는 VC가 새로 만들어지고(새 `InputController`)
/// 칩 상태는 프로세스 수명이라 그대로 넘어간다(D16) — `reappear`가 그 순서다.
@MainActor
private struct ChipHarness {
    private(set) var output = RecordingOutput()
    private(set) var controller: InputController
    let index = CountingEmojiIndex()
    var resolver: EmojiCandidateResolver?
    var state = EmojiChipState()
    var generator = CountingGenerator(seed: 11)
    private(set) var shown: String?

    static let car = ["🚕", "🚗", "🚘", "🛻", "🛞"]

    init(curation: EmojiCuration = EmojiCuration(overrides: ["가지": ""], fallbacks: ["치킨": "🍗"])) {
        controller = InputController(output: output)
        resolver = EmojiCandidateResolver(index: index, curation: curation)
    }

    /// 두벌식 키 — 키마다 조립 지점처럼 다시 계산한다
    mutating func type(_ keys: String) {
        for key in keys { key == "⌫" ? press(.backspace) : press(.character(String(key))) }
    }

    mutating func press(_ event: KeyEvent) {
        let revision = controller.documentRevision
        controller.handle(event)
        if controller.documentRevision != revision { state.documentDidChange() }
        recompute(isUserEdit: true)
    }

    /// 키보드를 내렸다 다시 띄운다 — VC·`InputController`는 새로, 칩 상태는 그대로(D16). 등장 sync 뒤 계산
    mutating func reappear(documentTail: String?) {
        output = RecordingOutput()
        controller = InputController(output: output)
        hostSync(documentTail: documentTail)
    }

    /// 이모지 칩 탭 — 조립 지점의 `handleWordTap` 이모지 분기와 같은 순서
    mutating func tapEmojiChip(_ candidate: WordSuggestionCandidate) -> Bool {
        guard controller.replaceCurrentWord(candidate.sourceWord, with: candidate.insertionText) else { return false }
        state.emojiChipTapped()
        recompute(isUserEdit: true)
        return true
    }

    /// 호스트 `textDidChange` — 문서 문맥(없으면 nil)으로 꼬리를 다시 세운 **뒤** 계산한다
    mutating func hostSync(documentTail: String?) {
        controller.syncWithDocument(documentTail: documentTail)
        recompute(isUserEdit: false)
    }

    mutating func recompute(isUserEdit: Bool) {
        shown = state.emoji(for: controller.currentWord, resolver: resolver, isUserEdit: isUserEdit,
                            using: &generator)
    }
}

@MainActor
@Suite("이모지 칩 — 조립 흐름 (Q1·Q10·D3·D9·검증 ⑤-2a 참고 2)")
struct EmojiChipFlowTests {

    @Test("「자동차」를 다 친 순간 이모지가 뜬다 — 「자동」「자동ㅊ」에서는 없다 (수용 기준 1)")
    func appearsWhenWordCompletes() {
        var harness = ChipHarness()
        harness.type("wkehd")              // 자동
        #expect(harness.shown == nil)
        harness.type("c")                  // 자동ㅊ
        #expect(harness.shown == nil)
        harness.type("k")                  // 자동차
        #expect(harness.shown.map(ChipHarness.car.contains) == true)
    }

    @Test("같은 단어 메아리 sync를 여러 번 받아도 같은 값이고 난수를 더 쓰지 않는다 (D9)")
    func echoSyncKeepsPick() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let first = harness.shown
        #expect(first != nil)
        let used = harness.generator.draws
        for _ in 0..<10 { harness.hostSync(documentTail: harness.output.text) }
        #expect(harness.shown == first)
        #expect(harness.generator.draws == used)
    }

    /// 검증 ⑤-2a 참고 2 — sync 중간값(꼬리가 잠깐 빔)으로 기억을 버리면 같은 단어인데 이모지가 바뀐다.
    @Test("호스트가 꼬리를 날렸다(nil·빈 문맥) 다시 세우면 같은 값이다", arguments: [String?.none, ""])
    func hostDropsTailThenRestores(dropped: String?) {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let first = harness.shown
        #expect(first != nil)
        let used = harness.generator.draws
        harness.hostSync(documentTail: dropped)
        #expect(harness.shown == nil, "꼬리가 빈 동안은 칩이 없다")
        harness.hostSync(documentTail: "자동차")
        #expect(harness.shown == first, "다시 세워진 같은 단어 — 같은 값")
        #expect(harness.generator.draws == used, "새로 뽑지 않았다")
    }

    @Test("사용자가 지웠다 다시 치면 새로 뽑는다")
    func retypeRedraws() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let used = harness.generator.draws
        harness.type("⌫")                  // 자동ㅊ — 다른 단어
        #expect(harness.shown == nil)
        harness.type("k")                  // 자동차 다시
        #expect(harness.generator.draws > used)
        #expect(harness.shown.map(ChipHarness.car.contains) == true)
    }

    @Test("혼합 칩 탭 → 다음 키 입력까지 이모지 칩 전부 숨김 → 다시 치면 새로 뽑아 뜬다 (수용 기준 8)")
    func mixedTapSuppressesUntilNextKey() throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        let mixed = WordSuggestionCandidate.emojiWithWord(emoji, word: "자동차")
        #expect(harness.controller.replaceCurrentWord(mixed.sourceWord, with: mixed.insertionText))
        harness.state.emojiChipTapped()
        harness.recompute(isUserEdit: true)          // 탭 처리 직후의 재계산
        #expect(harness.controller.currentWord == "자동차", "넣은 「자동차」가 다시 꼬리 끝 run이다")
        #expect(harness.shown == nil, "같은 단어지만 숨는다 — 두 번 눌러 🚕 🚕 자동차가 되지 않게")
        harness.hostSync(documentTail: harness.output.text)
        #expect(harness.shown == nil, "메아리 sync로는 풀리지 않는다")
        let used = harness.generator.draws
        harness.type("⌫ck")                 // 다음 키 입력 — 억제 해제, 지웠다 다시 친 자동차
        #expect(harness.shown.map(ChipHarness.car.contains) == true)
        #expect(harness.generator.draws > used, "새로 뽑았다")
    }

    @Test("숨긴 동안 후보 줄은 단어만이다 — 단어 3칸으로 돌아간다 (D3, 수용 기준 14)")
    func suppressedRowIsWordsOnly() {
        var state = EmojiChipState()
        state.emojiChipTapped()
        let resolver = EmojiCandidateResolver(index: CountingEmojiIndex())
        #expect(state.emoji(for: "자동차", resolver: resolver, isUserEdit: true) == nil)
        let row = WordSuggestionCandidate.row(words: ["자동차를", "자동차가", "자동차는"], emoji: nil, sourceWord: "자동차")
        #expect(row.count == 3)
        #expect(row.allSatisfy { $0.emoji == nil })
    }

    @Test("전용 칩 탭 → 꼬리 끝이 이모지라 단어가 없다")
    func emojiOnlyTap() throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        #expect(harness.controller.replaceCurrentWord("자동차", with: emoji))
        harness.state.emojiChipTapped()
        harness.recompute(isUserEdit: true)
        #expect(harness.output.text == emoji)
        #expect(harness.controller.currentWord.isEmpty)
        #expect(harness.shown == nil)
    }

    @Test("이모지 칩을 끄거나 secure면(리졸버 nil) 역색인을 보지 않고, 사용자 편집에서 기억도 버린다 (수용 기준 5)")
    func disabledComputesNothing() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        #expect(harness.shown != nil, "켜져 있을 때는 뜬다")
        let lookups = harness.index.lookups
        harness.resolver = nil
        harness.hostSync(documentTail: "자동차")
        #expect(harness.shown == nil)
        harness.type("⌫k")
        #expect(harness.shown == nil)
        #expect(harness.index.lookups == lookups, "꺼진 동안 조회 0회")
    }

    @Test("막기 단어는 칩이 없고, 묶음이 하나면 늘 그 값이다 (수용 기준 10)")
    func blockedAndSingle() {
        var harness = ChipHarness()
        harness.type("rkwl")               // 가지 — override ""
        #expect(harness.shown == nil)
        var chicken = ChipHarness()
        chicken.type("clzls")              // 치킨 — 손질 목록에만
        #expect(chicken.shown == "🍗")
    }

    @Test("키보드가 내려가면(reset) 같은 단어도 새로 뽑는다")
    func resetRedraws() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let used = harness.generator.draws
        harness.state.reset()
        harness.recompute(isUserEdit: true)
        #expect(harness.generator.draws > used)
    }
}

@MainActor
@Suite("이모지 칩 — 재표시 유지(D16)·숨김 해제는 문서가 바뀐 입력에서만(D17)")
struct EmojiChipLifetimeTests {

    @Test("D16 — 키보드를 내렸다 띄워도 같은 단어면 같은 값이고 새로 뽑지 않는다")
    func reappearSameWordKeepsPick() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let first = harness.shown
        #expect(first != nil)
        let used = harness.generator.draws
        harness.reappear(documentTail: "메모 자동차")
        #expect(harness.shown == first)
        #expect(harness.generator.draws == used)
    }

    @Test("D16 — 다시 띄운 곳의 단어가 다르면 칩이 없다 — 「다 친 순간」이 아니다(Q1)")
    func reappearOtherWordShowsNothing() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        harness.reappear(documentTail: "치킨")
        #expect(harness.shown == nil)
    }

    @Test("D16 — secure 입력란을 거치면(reset) 기억이 비어 같은 단어라도 칩이 없다")
    func secureClearsMemory() {
        var harness = ChipHarness()
        harness.type("wkehdck")
        harness.state.reset()                       // 조립 지점: secure면 reset
        harness.reappear(documentTail: "자동차")
        #expect(harness.shown == nil)
    }

    /// 숨김이 재표시를 넘어 이어지지 않으면, 다시 띄운 뒤 ⇧ 한 번에 넣은 「자동차」에 새 칩이 뜬다(겹침 위험).
    @Test("D16 — 탭 뒤 숨김도 재표시를 넘어 이어진다 — 다시 띄운 뒤 ⇧로는 칩이 안 뜬다")
    func suppressionSurvivesReappear() throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        let tapped = harness.tapEmojiChip(.emojiWithWord(emoji, word: "자동차"))
        #expect(tapped)
        harness.reappear(documentTail: "\(emoji) 자동차")
        #expect(harness.shown == nil)
        harness.press(.shift)
        #expect(harness.shown == nil)
        #expect(harness.state.isSuppressedAfterTap)
    }

    /// 검증 ⑤-2b 참고 1 — ⇧·한영·123이 숨김을 풀어 넣은 「자동차」에 새 칩이 뜨고, 다시 누르면 `🚕 🚗 자동차`.
    @Test("D17 — 혼합 탭 뒤 문서를 바꾸지 않는 키로는 숨김이 안 풀린다",
          arguments: [KeyEvent.shift, .toggleLanguage, .symbols, .advance])
    func nonEditingKeysKeepSuppression(key: KeyEvent) throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        let tapped = harness.tapEmojiChip(.emojiWithWord(emoji, word: "자동차"))
        #expect(tapped)
        harness.press(key)
        #expect(harness.shown == nil)
        #expect(harness.state.isSuppressedAfterTap)
        #expect(harness.output.text == "\(emoji) 자동차", "겹침 없음")
    }

    @Test("D17 — 글자·공백·지우기·리턴처럼 문서가 바뀐 입력에서 푼다",
          arguments: [KeyEvent.character("s"), .space, .backspace, .return])
    func editingKeysRelease(key: KeyEvent) throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        let tapped = harness.tapEmojiChip(.emojiWithWord(emoji, word: "자동차"))
        #expect(tapped)
        harness.press(.shift)
        #expect(harness.state.isSuppressedAfterTap)
        harness.press(key)
        #expect(!harness.state.isSuppressedAfterTap)
    }

    @Test("D17 — ⇧로는 안 풀리고, 지웠다 다시 치면 풀려 새로 뽑은 칩이 뜬다")
    func releaseThenRedraw() throws {
        var harness = ChipHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.shown)
        let tapped = harness.tapEmojiChip(.emojiWithWord(emoji, word: "자동차"))
        #expect(tapped)
        harness.press(.shift)
        #expect(harness.shown == nil)
        let used = harness.generator.draws
        harness.type("⌫ck")
        #expect(harness.shown.map(ChipHarness.car.contains) == true)
        #expect(harness.generator.draws > used)
    }
}

@MainActor
@Suite("InputController — 문서 변경 횟수 (D17)")
struct DocumentRevisionTests {

    @Test("문서 글자를 넣거나 지운 입력만 센다", arguments: [
        (KeyEvent.character("d"), true), (.space, true), (.backspace, true), (.return, true),
        (.multiTap([".", ","]), true),
        (.shift, false), (.toggleLanguage, false), (.symbols, false), (.symbolsAlternate, false),
        (.advance, false), (.spacer, false), (.keypadPageNext, false), (.keypadPagePrevious, false)
    ])
    func countsOnlyDocumentEdits(testCase: (event: KeyEvent, changes: Bool)) {
        let controller = InputController(output: RecordingOutput())
        for key in "dkssud" { controller.handle(.character(String(key))) }  // 안녕 — 지울 글자가 있게
        let before = controller.documentRevision
        controller.handle(testCase.event)
        #expect((controller.documentRevision != before) == testCase.changes)
    }

    @Test("후보·채움글·붙여넣기·이모지 칩 삽입도 센다 — 거절된 삽입은 세지 않는다")
    func countsInsertions() {
        let controller = InputController(output: RecordingOutput())
        for key in "wkehdck" { controller.handle(.character(String(key))) }
        var revision = controller.documentRevision
        #expect(!controller.replaceCurrentWord("고양이", with: "🐈"))
        #expect(controller.documentRevision == revision, "거절은 문서를 안 바꾼다")
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        #expect(controller.documentRevision != revision)
        revision = controller.documentRevision
        controller.insertProvidedText("!")
        #expect(controller.documentRevision != revision)
    }
}

@Suite("이모지 칩 — 후보 값 (Q8·6-2절·수용 기준 11·15)")
struct WordSuggestionCandidateTests {

    @Test("두 칩은 같은 뽑은 값이고, 단어 후보 뒤에 혼합·전용 순서로 붙는다 (Q2·Q3·Q4·수용 기준 15)")
    func rowSharesOneEmoji() {
        let row = WordSuggestionCandidate.row(words: ["자동차를", "자동차가"], emoji: "🛻", sourceWord: "자동차")
        #expect(row.map(\.insertionText) == ["자동차를", "자동차가", "🛻 자동차", "🛻"])
        #expect(row.map(\.emoji) == [nil, nil, "🛻", "🛻"])
        #expect(row.map(\.sourceWord) == ["자동차를", "자동차가", "자동차", "자동차"])
        #expect(row.map(\.isEmojiOnly) == [false, false, false, true])
    }

    @Test("이모지가 없으면 단어 후보 그대로다 — 회귀 0 (수용 기준 2)")
    func rowWithoutEmoji() {
        let row = WordSuggestionCandidate.row(words: ["안녕하세요", "안녕히"], emoji: nil, sourceWord: "안녕")
        #expect(row == [.word("안녕하세요"), .word("안녕히")])
    }

    @Test("단어 후보가 없어도 이모지 칩 둘은 뜬다")
    func rowWithoutWords() {
        let row = WordSuggestionCandidate.row(words: [], emoji: "🍗", sourceWord: "치킨")
        #expect(row.map(\.insertionText) == ["🍗 치킨", "🍗"])
    }

    /// D9 — VoiceOver가 이모지를 애플 이름표(🚕 = 「택시」)로 읽으면 칩마다 이름이 달라진다.
    /// 라벨의 단어 자리는 **원본 단어**다.
    @Test("라벨 — 단어 칩은 단어 그대로, 이모지 칩은 원본 단어로 읽는다 (수용 기준 11)")
    func accessibilityLabels() {
        #expect(WordSuggestionCandidate.word("자동차를").accessibilityLabel == "자동차를")
        #expect(WordSuggestionCandidate.emojiWithWord("🚕", word: "자동차").accessibilityLabel == "자동차 이모지 붙여넣기")
        #expect(WordSuggestionCandidate.emojiOnly("🚕", word: "자동차").accessibilityLabel == "자동차 이모지로 바꾸기")
        #expect(WordSuggestionCandidate.emojiOnly("🛞", word: "자동차").accessibilityLabel == "자동차 이모지로 바꾸기",
                "뽑은 값이 달라도 라벨은 같다")
    }

    @Test("후보 줄 게이트 — secure·채움글 칩·붙여넣기 칩(D18)·✕ 억제·커서 이동 억제 중 하나라도 있으면 추천단어(이모지 포함)를 계산하지 않는다 (4-4절)")
    func gate() {
        #expect(WordSuggestionGate.allowsWords(
            isSecureTextEntry: false, hasSnippet: false, hasPasteChip: false,
            isDismissed: false, isSuppressedAfterCursorMove: false))
        for blocked in 0..<5 {
            #expect(!WordSuggestionGate.allowsWords(
                isSecureTextEntry: blocked == 0, hasSnippet: blocked == 1, hasPasteChip: blocked == 2,
                isDismissed: blocked == 3, isSuppressedAfterCursorMove: blocked == 4))
        }
    }
}

@MainActor
@Suite("이모지 칩 — 탭 결과·학습 (Q3·Q4·1-3절·5-3절·수용 기준 3·4)")
struct EmojiChipInsertionTests {

    private func typedCar() -> (RecordingOutput, InputController) {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        for key in "wkehdck" { controller.handle(.character(String(key))) }
        return (output, controller)
    }

    @Test("혼합 칩 — 치던 단어(조합 중 음절 포함)를 지우고 「이모지 공백 단어」, 후행 공백 없음")
    func mixedSequence() {
        let (output, controller) = typedCar()
        let before = output.operations.count
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        #expect(Array(output.operations.dropFirst(before)) == [.delete(3), .insert("🚕 자동차")])
        #expect(output.text == "🚕 자동차")
        #expect(controller.textTail == "🚕 자동차")
        #expect(controller.currentWord == "자동차")
        #expect(!controller.isComposing)
    }

    @Test("전용 칩 — 지우고 이모지만")
    func emojiOnlySequence() {
        let (output, controller) = typedCar()
        let before = output.operations.count
        #expect(controller.replaceCurrentWord("자동차", with: "🚕"))
        #expect(Array(output.operations.dropFirst(before)) == [.delete(3), .insert("🚕")])
        #expect(output.text == "🚕")
        #expect(controller.textTail == "🚕")
    }

    @Test("꼬리가 칩의 원본 단어로 끝나지 않으면 아무 것도 하지 않는다", arguments: ["고양이", "자동", "동차", ""])
    func tailMismatchDoesNothing(source: String) {
        let (output, controller) = typedCar()
        let before = output.operations
        #expect(!controller.replaceCurrentWord(source, with: "🚕 \(source)"))
        #expect(output.operations == before)
    }

    @Test("꼬리 끝 run이 더 길면(「큰자동차」) 원본 「자동차」 칩은 거절한다")
    func longerRunRejected() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        for key in "zmswkehdck" { controller.handle(.character(String(key))) }  // 큰자동차
        #expect(controller.currentWord == "큰자동차")
        #expect(!controller.replaceCurrentWord("자동차", with: "🚕"))
    }

    /// 채움글 칩과 같은 2중 방어의 둘째 층 — 퇴장 중 더블탭(첫 층은 조립 지점의 「떠 있는 칩만」 가드).
    @Test("혼합 칩을 두 번 눌러도 「🚕 🚕 자동차」가 되지 않는다")
    func doubleTapRejected() {
        let (output, controller) = typedCar()
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        let after = output.operations
        #expect(!controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        #expect(output.operations == after)
        #expect(output.text == "🚕 자동차")
    }

    /// 검증 ⑤-2b 참고 2 — 둘째 층이 「꼬리가 삽입문으로 끝나는가」였을 때는 손으로 쳐 둔 「🚕 자동차」에 같은 🚕가
    /// 뽑히면 칩이 죽었다(눌러도 진동만). 둘째 층은 이제 「직전 문서 변경이 이모지 칩 삽입인가」만 본다.
    @Test("손으로 친 「🚕 자동차」에 🚕 혼합 칩 — 사용자가 누른 그대로 「🚕 🚕 자동차」가 된다")
    func handTypedSameEmojiAccepted() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("🚕 ")
        for key in "wkehdck" { controller.handle(.character(String(key))) }
        #expect(output.text == "🚕 자동차")
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        #expect(output.text == "🚕 🚕 자동차")
    }

    @Test("이모지 칩 삽입 뒤 문서가 바뀌면 다음 이모지 칩은 받는다")
    func guardClearsAfterDocumentEdit() {
        let (output, controller) = typedCar()
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        controller.handle(.backspace)                    // 🚕 자동
        for key in "ck" { controller.handle(.character(String(key))) }   // 🚕 자동차
        #expect(controller.replaceCurrentWord("자동차", with: "🚗 자동차"))
        #expect(output.text == "🚕 🚗 자동차")
    }

    @Test("이모지 칩은 학습으로 보내지 않는다 — 바로 이어 친 공백도 (수용 기준 4)", arguments: ["🚕 자동차", "🚕"])
    func chipNotLearned(insertion: String) {
        let (_, controller) = typedCar()
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }
        #expect(controller.replaceCurrentWord("자동차", with: insertion))
        controller.handle(.space)
        #expect(learned.isEmpty)
    }

    @Test("혼합 칩 뒤 이어 친 「는」까지의 한글 run은 정상 학습된다 (5-3절 뉘앙스)")
    func continuedRunLearned() {
        let (output, controller) = typedCar()
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }
        #expect(controller.replaceCurrentWord("자동차", with: "🚕 자동차"))
        for key in "sms" { controller.handle(.character(String(key))) }       // 는
        controller.handle(.space)
        #expect(output.text == "🚕 자동차는 ")
        #expect(learned == ["자동차는"])
    }
}

// MARK: - D18 붙여넣기 칩이 있으면 [칩][✕]만 (PDR `emoji-word-suggestion.md` D18, 실기 세션 1 K7)

/// 조립 지점(`KeyboardViewController`)과 **같은 순서**로 붙여넣기 칩과 추천단어 줄을 함께 계산하는 하네스.
///
/// - 등장(`appear`) = `probePasteboard` — 타이핑 억제를 풀고, `PasteboardProbe` 게이트를 지나면 칩을 만든다.
///   전체 접근이 없으면 읽지 않는다. 그 뒤 등장 sync(이모지 칩 상태는 프로세스 수명, D16)
/// - 키(`type`) = `updateSuggestionBar(userEdited: true)` — 타이핑 억제를 먼저 켜고 칩 → 게이트 → 이모지 순
/// - ✕(`dismiss`) = `handleDismissSuggestions` — 칩이 있으면 그 클립보드를 소비하고 칩만 내린 뒤 sync로 다시 계산
@MainActor
private struct PasteRowHarness {
    var chips = ChipHarness()
    let baseResolver: EmojiCandidateResolver?
    var hasFullAccess = true
    var hasSnippet = false
    /// 사전 엔진이 돌려줄 단어 후보(가짜) — 게이트가 닫히면 계산하지 않는다
    let engineWords = ["자동차를", "자동차가"]
    private(set) var pasteSuggestion: PasteSuggestion?
    private(set) var suppressedByTyping = false
    private(set) var probedChangeCount: Int?
    /// VC의 `static consumedPasteboardChangeCount` — 프로세스 수명
    private(set) var consumedChangeCount: Int?
    private(set) var chip: PasteSuggestion?
    private(set) var row: [WordSuggestionCandidate] = []
    private(set) var clipboardReads = 0
    /// 지난 등장 때 받은 문서 — 등장마다 출력 기록이 새로 시작되므로 그 앞에 붙여 문서 전체를 낸다
    private var documentBase = ""
    var documentText: String { documentBase + chips.output.text }

    init() { baseResolver = chips.resolver }

    /// 키보드 등장 — 다른 앱에서 복사하고 돌아온 순간. 문서는 그대로다
    mutating func appear(changeCount: Int, clipboard: String) {
        let documentTail = documentText
        pasteSuggestion = nil
        probedChangeCount = nil
        suppressedByTyping = false
        if hasFullAccess {
            let plan = PasteboardProbe.plan(
                codeSuggestionsEnabled: true, pasteSuggestionsEnabled: true, historyEnabled: false,
                changeCount: changeCount, consumedChangeCount: consumedChangeCount, recordedChangeCount: nil)
            let text = PasteboardProbe.read(plan, hasStrings: { true }, readString: {
                clipboardReads += 1
                return clipboard
            })
            if let text, plan.needsSuggestion {
                pasteSuggestion = PasteSuggestion.make(from: text)
                probedChangeCount = changeCount
            }
        }
        gateBeforeEmoji()
        documentBase = documentTail
        chips.reappear(documentTail: documentTail)
        finishRow()
    }

    mutating func type(_ keys: String) {
        suppressedByTyping = true
        gateBeforeEmoji()
        chips.type(keys)
        finishRow()
    }

    /// ✕ — 칩이 있으면 그 클립보드를 소비하고 칩을 내린다(추천단어는 안 보였으니 억제하지 않는다)
    mutating func dismiss() {
        if chip != nil {
            consumedChangeCount = probedChangeCount
            pasteSuggestion = nil
        }
        gateBeforeEmoji()
        chips.recompute(isUserEdit: false)
        finishRow()
    }

    private var wordsAllowed: Bool {
        WordSuggestionGate.allowsWords(
            isSecureTextEntry: false, hasSnippet: hasSnippet, hasPasteChip: chip != nil,
            isDismissed: false, isSuppressedAfterCursorMove: false)
    }

    /// 칩 판정 → 게이트 → 이모지 리졸버 — 조립 지점의 순서
    private mutating func gateBeforeEmoji() {
        chip = PasteChipGate.visibleChip(
            pasteSuggestion, hasFullAccess: hasFullAccess, isSecureTextEntry: false,
            isSuppressedByTyping: suppressedByTyping)
        chips.resolver = wordsAllowed ? baseResolver : nil
    }

    private mutating func finishRow() {
        row = WordSuggestionCandidate.row(
            words: wordsAllowed ? engineWords : [], emoji: chips.shown, sourceWord: chips.controller.currentWord)
    }
}

@MainActor
@Suite("D18 — 붙여넣기 칩이 있으면 [칩][✕]만, ✕로 물리면 추천단어·이모지 칩 (실기 세션 1 K7)")
struct PasteChipWordRowTests {

    private static let copied = "다른 앱에서 복사한 글"

    /// 「자동차」 이모지 칩 상태에서 다른 앱으로 가 복사하고 메모로 돌아온다 — 실기에서 본 바로 그 순서
    private func carThenCopyAndReturn() throws -> (PasteRowHarness, emoji: String) {
        var harness = PasteRowHarness()
        harness.type("wkehdck")
        let emoji = try #require(harness.chips.shown)
        #expect(harness.row.count == 4, "복사 전 — [단어][단어][🚗 자동차][🚗]")
        harness.appear(changeCount: 7, clipboard: Self.copied)
        return (harness, emoji)
    }

    @Test("★ 붙여넣기 칩 + 단어·이모지 후보 → 칩만 남고 후보 줄은 비어 있다 (K7 재현)")
    func pasteChipHidesWordsAndEmoji() throws {
        let (harness, _) = try carThenCopyAndReturn()
        #expect(harness.chip?.kind == .text)
        #expect(harness.row.isEmpty, "[복사됨][추천]×4[✕]가 아니라 [복사됨][✕]")
        #expect(harness.chips.shown == nil)
    }

    @Test("★ ✕ → 붙여넣기 칩이 물러나고 지금 단어의 추천단어·이모지 칩이 나온다 — 이모지는 복사 전과 같은 값 (D16·D18)")
    func dismissRevealsWordRow() throws {
        var (harness, emoji) = try carThenCopyAndReturn()
        let draws = harness.chips.generator.draws
        harness.dismiss()
        #expect(harness.chip == nil)
        #expect(harness.row == WordSuggestionCandidate.row(
            words: ["자동차를", "자동차가"], emoji: emoji, sourceWord: "자동차"))
        #expect(harness.chips.generator.draws == draws, "새로 뽑지 않았다 — 칩이 가린 동안 기억을 버리지 않았다")
    }

    @Test("★ ✕로 물린 클립보드는 다시 띄워도 칩이 없다 — 내용도 다시 읽지 않는다, 새로 복사하면 뜬다")
    func dismissedClipboardDoesNotReturn() throws {
        var (harness, _) = try carThenCopyAndReturn()
        harness.dismiss()
        let reads = harness.clipboardReads
        harness.appear(changeCount: 7, clipboard: Self.copied)
        #expect(harness.chip == nil)
        #expect(harness.row.count == 4, "후보 줄이 그대로 — [단어][단어][🚗 자동차][🚗]")
        #expect(harness.clipboardReads == reads, "소비한 클립보드는 읽지도 않는다")
        harness.appear(changeCount: 8, clipboard: "또 복사한 글")
        #expect(harness.chip != nil, "새 복사(changeCount 변화)는 다시 뜬다")
        #expect(harness.row.isEmpty)
    }

    @Test("회귀 — 글자를 치면 붙여넣기 칩이 물러나고 후보가 뜬다(클립보드는 소비하지 않는다)")
    func typingStillReleasesChip() throws {
        var (harness, _) = try carThenCopyAndReturn()
        harness.type("fmf")                       // 자동차를
        #expect(harness.chip == nil)
        #expect(harness.row.contains(.word("자동차를")))
        harness.appear(changeCount: 7, clipboard: Self.copied)
        #expect(harness.chip != nil, "타이핑 억제는 그 등장 동안뿐 — 소비가 아니므로 다음 등장에 다시 뜬다")
    }

    @Test("회귀 — 인증번호 칩도 같은 규칙이다")
    func verificationCodeChipToo() {
        var harness = PasteRowHarness()
        harness.type("wkehdck")
        harness.appear(changeCount: 9, clipboard: "[Web발신] 인증번호 [268755]를 입력하세요")
        #expect(harness.chip?.kind == .verificationCode)
        #expect(harness.row.isEmpty)
        harness.dismiss()
        #expect(harness.row.count == 4)
    }

    @Test("회귀 — 전체 접근 OFF면 붙여넣기 칩이 없고(읽지도 않는다) 후보 줄은 지금과 같다")
    func noFullAccessUnchanged() {
        var harness = PasteRowHarness()
        harness.hasFullAccess = false
        harness.type("wkehdck")
        harness.appear(changeCount: 7, clipboard: Self.copied)
        #expect(harness.chip == nil)
        #expect(harness.clipboardReads == 0)
        #expect(harness.row.count == 4)
    }

    @Test("회귀 — 채움글 칩이 있으면 붙여넣기 칩이 있든 없든 추천단어를 계산하지 않는다(현행 우선순위)")
    func snippetPriorityUnchanged() {
        for hasPasteChip in [false, true] {
            #expect(!WordSuggestionGate.allowsWords(
                isSecureTextEntry: false, hasSnippet: true, hasPasteChip: hasPasteChip,
                isDismissed: false, isSuppressedAfterCursorMove: false))
        }
    }

    @Test("붙여넣기 칩 게이트 — 전체 접근·secure·타이핑 억제 중 하나라도 걸리면 칩 없음")
    func pasteChipGate() throws {
        let paste = try #require(PasteSuggestion.make(from: Self.copied))
        #expect(PasteChipGate.visibleChip(
            paste, hasFullAccess: true, isSecureTextEntry: false, isSuppressedByTyping: false) == paste)
        for blocked in 0..<3 {
            #expect(PasteChipGate.visibleChip(
                paste, hasFullAccess: blocked != 0, isSecureTextEntry: blocked == 1,
                isSuppressedByTyping: blocked == 2) == nil)
        }
        #expect(PasteChipGate.visibleChip(
            nil, hasFullAccess: true, isSecureTextEntry: false, isSuppressedByTyping: false) == nil)
    }
}
