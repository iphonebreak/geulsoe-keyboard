import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

// B5 영어 추천단어 2단계 — 엔진·run·게이트·탭 정합(계획 `v1.3.1-plan.md` §3-8 E1~E11·E14·E15, PDR `english-word-suggestions.md` C1~C14).
// 사전은 가짜다 — 실제 번들(`words-en.tdw`) 단언은 TadakData E12·E17이 맡는다.

/// 키 = 소문자 lookupKey, 표시형은 손질 원형(`I'm`·`Monday`·`iPhone`)
private struct FakeEnglishDictionary: WordDictionary {
    let entries: [(key: String, word: String, frequency: UInt32)] = [
        ("hello", "hello", 900), ("help", "help", 950), ("hell", "hell", 500), ("helmet", "helmet", 100),
        ("don't", "don't", 990), ("done", "done", 700), ("i'm", "I'm", 980), ("i'll", "I'll", 970),
        ("monday", "Monday", 300), ("money", "money", 800), ("iphone", "iPhone", 50), ("world", "world", 600)
    ]
    func candidates(jamoPrefix: String, limit: Int) -> [WordCandidate] {
        entries.filter { $0.key.hasPrefix(jamoPrefix) }.sorted { $0.frequency > $1.frequency }.prefix(limit)
            .map { WordCandidate(word: $0.word, frequency: $0.frequency) }
    }
}

// MARK: - E1 · E2 run 규칙

@Suite("B5 E1 — 영어 단어 run 규칙")
struct LatinWordRunTests {

    @Test("run 표", arguments: [
        ("Hel", "Hel"), ("hello wor", "wor"), ("don'", "don'"), ("don\u{2019}t", "don\u{2019}t"), ("'tis", "tis"),
        ("well-kn", "kn"), ("아이폰iPh", "iPh"), ("Hello, wo", "wo"), ("(abc", "abc")
    ] as [(String, String)])
    func runs(row: (tail: String, run: String)) {
        #expect(LatinWordRun.run(inTail: row.tail, isTruncated: false) == row.run, "\(row.tail)")
    }

    @Test("run 없음 — 토큰의 일부·한글 끝·비ASCII 라틴(C3)·빈 꼬리", arguments: [
        "a@exa", "v1.2abc", "abc1", "x/abc", "a:bc", "a_bc", "a#bc", "a\\bc", "a.bc",
        "iPhone이", "naïve", "caféteria", "cafe\u{301}teria", "", "hello ", "'"
    ])
    func noRun(tail: String) {
        #expect(LatinWordRun.run(inTail: tail, isTruncated: false) == nil, "\(tail.debugDescription)")
    }

    @Test("E2 — 꼬리 전체가 run이고 잘렸으면 없음, 꼬리 안에서 시작하면 있음")
    func truncation() {
        #expect(LatinWordRun.run(inTail: "hello", isTruncated: true) == nil)
        #expect(LatinWordRun.run(inTail: "abc hel", isTruncated: true) == "hel")
    }

    @Test("조회 키 — 소문자 + 굽은 아포스트로피를 곧게")
    func lookupKey() {
        #expect(LatinWordRun.lookupKey("Don\u{2019}T") == "don't")
        #expect(LatinWordRun.lookupKey("HEL") == "hel")
    }
}

// MARK: - E3 · E7 엔진

@MainActor
@Suite("B5 E3·E7 — 영어 엔진(학습 없음 구조)")
struct EnglishEngineTests {

    let engine = SuggestionEngine.english(dictionary: FakeEnglishDictionary())

    @Test("빈도순 최대 3개, 자기 자신은 뺀다")
    func basic() {
        #expect(engine.suggestions(forWord: "hel") == ["help", "hello", "hell"])
        #expect(engine.suggestions(forWord: "hell") == ["hello"], "자기 자신(hell) 제외")
        #expect(engine.suggestions(forWord: "Hell") == ["Hello"], "대소문자가 달라도 정규화 키로 자기 자신 제외")
    }

    @Test("입력 모양을 따른다 — Hel → Hello, HEL → HELLO, 손질 원형은 그대로", arguments: [
        ("Hel", ["Help", "Hello", "Hell"]), ("HEL", ["HELP", "HELLO", "HELL"]),
        ("mon", ["money", "Monday"]), ("iph", ["iPhone"]), ("i'", ["I'm", "I'll"]), ("Mon", ["Money", "Monday"])
    ] as [(String, [String])])
    func casing(row: (word: String, expected: [String])) {
        #expect(engine.suggestions(forWord: row.word) == row.expected)
    }

    @Test("굽은 아포스트로피로 쳐도 사전 형태(직선)로 낸다")
    func smartQuote() {
        #expect(engine.suggestions(forWord: "don\u{2019}").contains("don't"))
    }

    @Test("한 글자·비영문은 후보 없음")
    func guards() {
        #expect(engine.suggestions(forWord: "h").isEmpty)
        #expect(engine.suggestions(forWord: "안녕").isEmpty)
    }

    @Test("E7 — 영어 엔진은 학습하지 않는다(learn은 아무 것도 바꾸지 않는다)")
    func noLearning() {
        let before = engine.suggestions(forWord: "wor")
        for _ in 0..<5 { engine.learn(word: "worldwide") }
        #expect(engine.suggestions(forWord: "wor") == before)
    }

    @Test("E4 — 한글 엔진은 그대로(영어 단어는 후보 없음)")
    func hangulEngineUnchanged() {
        let hangul = SuggestionEngine(dictionary: FakeEnglishDictionary())
        #expect(hangul.suggestions(forWord: "hel").isEmpty, "한글 엔진은 자모 분해가 안 되는 단어에 후보를 내지 않는다")
    }
}

// MARK: - E5 게이트

@Suite("B5 E5 — 영어 후보 게이트(N13 제품 선택 포함)")
struct EnglishSuggestionGateTests {

    @Test("표", arguments: [
        // (영어 문맥, 이메일/URL, ASCII 전용, secure, 자동 교정 끔, 스위치, 기대)
        (true, false, false, false, false, true, true),
        (false, false, false, false, false, true, false),   // 한글 모드·한글→123
        (true, true, false, false, false, true, false),     // 이메일·URL
        (true, false, true, false, false, true, false),     // .asciiCapable — 제품 선택(C13)
        (true, false, false, true, false, true, false),     // secure
        (true, false, false, false, true, true, false),     // autocorrectionType == .no — 제품 선택(C13)
        (true, false, false, false, false, false, false)    // 스위치 끔(상위 추천단어 끔 포함)
        // textContentType 칸(C14) — 1.3.1은 읽지 않는다. 영어 학습(1.3.2 후보) 전 필수 차단 조건
    ] as [(Bool, Bool, Bool, Bool, Bool, Bool, Bool)])
    func table(row: (Bool, Bool, Bool, Bool, Bool, Bool, Bool)) {
        let field = EnglishFieldTraits(isEmailOrURL: row.1, isASCIICapable: row.2, isSecure: row.3, autocorrectionDisabled: row.4)
        #expect(EnglishSuggestionGate.allows(isEnglishContext: row.0, field: field, settingEnabled: row.5) == row.6)
    }

    @Test("E10 ✕ 억제 — 정규화 키로 이어 치는 동안 유지, 벗어나면 풀린다")
    func dismissal() {
        #expect(EnglishDismissal.isStillDismissed(dismissedKey: "hel", currentRun: "Hell"))
        #expect(EnglishDismissal.isStillDismissed(dismissedKey: "don'", currentRun: "don\u{2019}t"))
        #expect(!EnglishDismissal.isStillDismissed(dismissedKey: "hel", currentRun: "he"))
        #expect(!EnglishDismissal.isStillDismissed(dismissedKey: "hel", currentRun: nil))
    }
}

// MARK: - E6 · E8 · E9 · E11 · E14 · E15 InputController

@MainActor
@Suite("B5 E6~E15 — InputController 영어")
struct EnglishInputControllerTests {

    private func english() -> (RecordingOutput, InputController) {
        let output = RecordingOutput()
        return (output, InputController(output: output, startsInHangul: false))
    }

    private func type(_ text: String, _ controller: InputController) {
        for character in text {
            controller.handle(character == " " ? .space : .character(String(character)))
        }
    }

    @Test("E6 — run과 치환: 앞 텍스트 보존·후행 공백 없음")
    func replace() {
        let (output, controller) = english()
        type("say hel", controller)
        #expect(controller.isEnglishSuggestionContext)
        #expect(controller.currentLatinWord == "hel")
        #expect(controller.completeLatinWord("hello", expectingRun: "hel"))
        #expect(output.text == "say hello")
        #expect(controller.currentLatinWord == "hello")
    }

    @Test("E7 — 영어 치환은 학습 콜백을 부르지 않는다")
    func noLearningCallback() {
        let (_, controller) = english()
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }
        type("hel", controller)
        #expect(controller.completeLatinWord("hello", expectingRun: "hel"))
        controller.handle(.space)
        #expect(learned.isEmpty)
    }

    @Test("E4 — 한글 회귀 방벽: 한글 모드는 영어 run·영어 문맥이 없고, 한글 completeWord는 학습 콜백을 그대로 1회 부른다")
    func hangulRegression() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var learned: [String] = []
        controller.onWordCommitted = { learned.append($0) }
        for key in ["d", "k", "s", "s", "u", "d", "g"] { controller.handle(.character(key)) }
        #expect(controller.isEnglishSuggestionContext == false)
        #expect(controller.currentLatinWord == nil)
        #expect(controller.completeWord("안녕하세요"))
        #expect(learned == ["안녕하세요"])
        #expect(output.text == "안녕하세요")
        // 한글 모드에서 들어온 라틴 글자(붙여넣기 등)에도 영어 run을 내지 않는다(C4)
        controller.insertProvidedText(" hel")
        #expect(controller.currentLatinWord == nil)
    }

    @Test("E8 — 끝이 한글이면 영어 run 없음, 한글 경로만")
    func mixed() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("iPhone이")
        #expect(controller.currentLatinWord == nil)
        #expect(controller.isEnglishSuggestionContext == false)
    }

    @Test("E9 — 영어→123→' 는 영어 문맥, 한글→123은 아니다")
    func symbolsMode() {
        let (_, controller) = english()
        type("don", controller)
        controller.handle(.symbols)
        controller.handle(.character("'"))
        #expect(controller.isEnglishSuggestionContext)
        #expect(controller.currentLatinWord == "don'")

        let output = RecordingOutput()
        let hangul = InputController(output: output)
        hangul.handle(.symbols)
        #expect(hangul.isEnglishSuggestionContext == false)
    }

    @Test("E11 — 영어 run에서 이모지 해석 대상(한글 run)은 비어 있다")
    func emojiUntouched() {
        let (_, controller) = english()
        type("car", controller)
        #expect(controller.currentWord.isEmpty)
    }

    @Test("E15 — 늦은 탭·연속 탭·한글 전환 뒤에는 문서를 바꾸지 않는다")
    func tapConsistency() {
        let (output, controller) = english()
        type("hel", controller)
        controller.handle(.character("p"))
        #expect(!controller.completeLatinWord("hello", expectingRun: "hel"), "늦은 탭 — run이 바뀌었다")
        #expect(output.text == "help")
        #expect(controller.completeLatinWord("helpful", expectingRun: "help"))
        #expect(!controller.completeLatinWord("helpful", expectingRun: "help"), "연속 탭 — 이미 바뀌었다")
        #expect(output.text == "helpful")
        controller.handle(.toggleLanguage)
        #expect(!controller.completeLatinWord("helpfully", expectingRun: "helpful"), "한글 모드")
        #expect(output.text == "helpful")
    }

    @Test("E15 — 호스트가 꼬리를 바꿔 run이 길어졌으면(같은 접미라도) 거절")
    func runChangedByHost() {
        let (output, controller) = english()
        type("hel", controller)
        controller.syncWithDocument(documentTail: "shel")   // 호스트가 앞에 글자를 넣었다(문서 쓰기는 기록 안 됨)
        #expect(controller.currentLatinWord == "shel")
        #expect(!controller.completeLatinWord("hello", expectingRun: "hel"), "run이 표시 당시(hel)와 다르다")
        #expect(output.text == "hel", "우리 쪽 쓰기 없음")
    }

    @Test("E15 — 선택 영역이 있으면 거절(K4)")
    func selection() {
        let (output, controller) = english()
        type("hel", controller)
        output.hasSelectedText = true
        #expect(!controller.completeLatinWord("hello", expectingRun: "hel"))
        #expect(output.text == "hel")
    }

    /// C7 — B2-A 스냅샷은 자동 대문자 전용. 제출(문서 유지) 입력란에서 ⏎⌫ 뒤 문서는 「Hell」인데, 스냅샷을 꼬리로 되살리면 영어 치환이
    /// 문서에 없는 글자를 지운다. 꼬리는 잘림(앞 모름)이라 run이 없고 탭은 거절된다
    @Test("E14 — 제출형 ⏎⌫ 뒤 영어 치환은 문서에 없는 글자를 지우지 않는다")
    func b2SnapshotNotUsed() {
        let document = HostDocument(host: .submitKeepsText)
        let controller = InputController(output: document, startsInHangul: false)
        controller.returnKeyIsDefault = true
        for key in ["H", "e", "l", "l", "o"] { controller.handle(.character(key)) }
        controller.handle(.return)
        controller.handle(.backspace)
        for key in ["w", "o"] { controller.handle(.character(key)) }
        #expect(document.text == "Hellwo")
        #expect(controller.currentLatinWord == nil, "꼬리 전체가 run이고 앞을 모른다(E2)")
        #expect(!controller.completeLatinWord("world", expectingRun: "wo"))
        #expect(!controller.completeLatinWord("Helloworld", expectingRun: "Hellowo"))
        #expect(document.text == "Hellwo")
    }
}
