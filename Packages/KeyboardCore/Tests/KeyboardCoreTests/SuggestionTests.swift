import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

@Suite("JamoDecomposer")
struct JamoDecomposerTests {

    @Test("음절을 평탄 자모로 분해한다 — 겹받침·조합 복모음 포함", arguments: [
        ("안녕핫", "ㅇㅏㄴㄴㅕㅇㅎㅏㅅ"),
        ("갃", "ㄱㅏㄱㅅ"),        // 겹받침 ㄳ → ㄱㅅ
        ("회사", "ㅎㅗㅣㅅㅏ"),     // 복모음 ㅚ → ㅗㅣ
        ("띄어", "ㄸㅡㅣㅇㅓ"),     // 복모음 ㅢ → ㅡㅣ
        ("약", "ㅇㅑㄱ")          // 원자 모음(ㅑ)은 그대로
    ])
    func decomposes(testCase: (String, String)) {
        #expect(JamoDecomposer.decompose(testCase.0) == testCase.1)
    }

    /// 리뷰 반영 — 초성만 조합 중인 상태에서도 후보가 이어져야 한다.
    @Test("맨 끝의 단독 자음은 자모 시퀀스에 그대로 붙는다")
    func trailingConsonantJamo() {
        #expect(JamoDecomposer.decompose("안녕ㅎ") == "ㅇㅏㄴㄴㅕㅇㅎ")
        #expect(JamoDecomposer.decompose("ㅎ") == "ㅎ")
        #expect(JamoDecomposer.decompose("ㅎ안") == nil, "끝이 아닌 자음은 허용하지 않는다")
        #expect(JamoDecomposer.decompose("안ㅏ") == nil, "모음 단독은 허용하지 않는다")
    }

    @Test("음절이 아닌 문자가 섞이면 nil이다", arguments: ["a안", "안1", "ㅋㅋ", ""])
    func rejectsNonSyllables(text: String) {
        // 빈 문자열은 빈 시퀀스다 — nil이 아니라 ""
        if text.isEmpty {
            #expect(JamoDecomposer.decompose(text) == "")
        } else {
            #expect(JamoDecomposer.decompose(text) == nil)
        }
    }
}

/// 자모 접두 필터만 하는 fake — 실제 정렬/이진 탐색은 TadakData 테스트가 맡는다.
private struct FakeWordDictionary: WordDictionary {
    let entries: [(word: String, frequency: UInt32)]

    func candidates(jamoPrefix: String, limit: Int) -> [WordCandidate] {
        entries
            .filter { JamoDecomposer.decompose($0.word)?.hasPrefix(jamoPrefix) ?? false }
            .sorted { $0.frequency > $1.frequency }
            .prefix(limit)
            .map { WordCandidate(word: $0.word, frequency: $0.frequency) }
    }
}

private final class FakeUserWordRepository: UserWordRepository, @unchecked Sendable {
    var stored: [String: Int]
    var saveSucceeds = true
    private(set) var saveCount = 0

    init(stored: [String: Int] = [:]) {
        self.stored = stored
    }

    func load() -> [String: Int] { stored }

    func save(_ counts: [String: Int]) -> Bool {
        saveCount += 1
        guard saveSucceeds else { return false }
        stored = counts
        return true
    }
}

@MainActor
@Suite("SuggestionEngine")
struct SuggestionEngineTests {

    private let dictionary = FakeWordDictionary(entries: [
        ("안녕", 100), ("안녕하세요", 50), ("안녕히", 10), ("안건", 30)
    ])

    @Test("조합 중간 상태를 포함해 접두 일치 후보를 빈도순으로 낸다")
    func ranksByFrequency() {
        let engine = SuggestionEngine(dictionary: dictionary)
        #expect(engine.suggestions(forWord: "안녕하") == ["안녕하세요"])
        #expect(engine.suggestions(forWord: "안") == ["안녕", "안녕하세요", "안건"])
    }

    @Test("입력 중인 단어와 같은 후보는 뺀다")
    func excludesSelf() {
        let engine = SuggestionEngine(dictionary: dictionary)
        #expect(engine.suggestions(forWord: "안녕") == ["안녕하세요", "안녕히"])
    }

    @Test("사용자 학습 단어가 사전보다 우선한다")
    func userWordsWin() {
        let repository = FakeUserWordRepository(stored: ["안녕콘": 3])
        let engine = SuggestionEngine(dictionary: dictionary, userWordRepository: repository)
        #expect(engine.suggestions(forWord: "안녕") == ["안녕콘", "안녕하세요", "안녕히"])
    }

    @Test("학습한 단어가 즉시 후보에 반영되고 저장이 시도된다")
    func learnsAndPersists() {
        let repository = FakeUserWordRepository()
        let engine = SuggestionEngine(dictionary: nil, userWordRepository: repository)
        engine.learn(word: "파랑새")
        #expect(engine.suggestions(forWord: "파랑") == ["파랑새"])
        #expect(repository.stored == ["파랑새": 1])
    }

    @Test("저장 실패(Full Access 없음)여도 세션 학습은 동작한다")
    func sessionLearningSurvivesSaveFailure() {
        let repository = FakeUserWordRepository()
        repository.saveSucceeds = false
        let engine = SuggestionEngine(dictionary: nil, userWordRepository: repository)
        engine.learn(word: "파랑새")
        #expect(engine.suggestions(forWord: "파랑") == ["파랑새"])
        #expect(repository.stored.isEmpty)
    }

    @Test("학습 상한을 넘으면 카운트 하위부터 버린다")
    func evictsLowestCount() {
        let engine = SuggestionEngine(dictionary: nil, userWordRepository: nil, userWordLimit: 2)
        engine.learn(word: "가나다")
        engine.learn(word: "가나다")
        engine.learn(word: "가나요")
        engine.learn(word: "가나방")  // 상한 초과 — 하위(가나요 또는 가나방 중 1회짜리) 제거
        let hits = engine.suggestions(forWord: "가나")
        #expect(hits.count == 2)
        #expect(hits.first == "가나다")
    }

    @Test("한글 2자 미만·비한글·조합 중 자음이 낀 run은 학습하지 않는다")
    func learnFilters() {
        let repository = FakeUserWordRepository()
        let engine = SuggestionEngine(dictionary: nil, userWordRepository: repository)
        engine.learn(word: "가")
        engine.learn(word: "ab")
        engine.learn(word: "가1")
        engine.learn(word: "안녕ㅎ")
        #expect(repository.saveCount == 0)
    }

    /// 리뷰 반영 — 상한 초과 저장분은 로드 시점에 잘라 수렴시킨다.
    @Test("로드된 데이터가 상한을 넘으면 카운트 상위만 남긴다")
    func trimsOversizedLoad() {
        let repository = FakeUserWordRepository(
            stored: ["가나다": 3, "가나요": 2, "가나방": 1])
        let engine = SuggestionEngine(
            dictionary: nil, userWordRepository: repository, userWordLimit: 2)
        let hits = engine.suggestions(forWord: "가나")
        #expect(hits == ["가나다", "가나요"], "하위(가나방)는 로드에서 잘린다")
    }
}

@MainActor
@Suite("InputController — 단어 추적과 완성")
struct InputControllerWordTests {

    @Test("조합 중 음절까지 포함해 현재 단어를 추적한다")
    func currentWordTracksComposition() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["d", "k", "s", "s", "u", "d"] { controller.handle(.character(key)) }  // 안녕
        #expect(controller.currentWord == "안녕")

        controller.handle(.space)
        #expect(controller.currentWord == "", "공백이 단어를 끊는다")

        controller.handle(.character("1"))
        #expect(controller.currentWord == "", "비한글은 단어가 아니다")
    }

    /// 리뷰 반영 — 음절 시작(초성만 조합 중)마다 후보가 끊기면 안 된다.
    @Test("초성만 조합 중인 상태도 현재 단어에 포함된다")
    func currentWordIncludesLeadingConsonant() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["d", "k", "s", "s", "u", "d", "g"] { controller.handle(.character(key)) }
        #expect(output.text == "안녕ㅎ")
        #expect(controller.currentWord == "안녕ㅎ")

        // 이 상태에서 후보를 골라도 정확히 3글자(안·녕·ㅎ)만 지워진다
        controller.completeWord("안녕하세요")
        #expect(output.operations.suffix(2) == [.delete(3), .insert("안녕하세요")])
        #expect(output.text == "안녕하세요")
    }

    /// 리뷰 반영 — 후보 선택 단어가 이어지는 공백에서 두 번 학습되면 랭킹이 왜곡된다.
    @Test("후보 선택 직후의 공백은 같은 단어를 다시 알리지 않는다")
    func noDoubleLearnAfterCompletion() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }

        for key in ["d", "k", "s", "s", "u", "d", "g", "k"] { controller.handle(.character(key)) }
        controller.completeWord("안녕하세요")
        controller.handle(.space)
        #expect(committed == ["안녕하세요"], "탭 1회 = 학습 1회")

        // 단어를 수정하면 다시 학습 대상이 된다
        controller.handle(.backspace)  // 공백 삭제
        controller.handle(.backspace)  // 확정된 "요" 삭제 — 타이핑 재개
        controller.handle(.space)
        #expect(committed.count == 2, "수정된 단어는 새로 확정된 단어다")
    }

    @Test("채움글 삽입 직후의 공백은 본문 끝 단어를 학습하지 않는다")
    func snippetBodyIsNotLearned() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }
        let anthem = SnippetEntry(trigger: "애국가 1절", title: "애국가 1절",
                                  body: "동해물과 백두산이")
        let matcher = SnippetMatcher(bible: nil, entries: [anthem])

        for key in ["d", "o", "r", "n", "r", "r", "k"] { controller.handle(.character(key)) }
        controller.handle(.space)  // "애국가" 학습 — 사용자가 타이핑한 단어
        controller.handle(.character("1"))
        for key in ["w", "j", "f"] { controller.handle(.character(key)) }  // 절
        controller.insertSnippet(matcher.suggestion(forTail: controller.textTail)!)
        controller.handle(.space)
        #expect(committed == ["애국가"], "본문 끝 단어(백두산이)는 학습되지 않는다")
    }

    @Test("공백·리턴에서 확정 단어를 알린다 (2자 이상만)")
    func notifiesOnCommit() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }

        for key in ["d", "k", "s", "s", "u", "d"] { controller.handle(.character(key)) }
        controller.handle(.space)
        for key in ["r", "k"] { controller.handle(.character(key)) }  // 가 (1자)
        controller.handle(.return)
        #expect(committed == ["안녕"], "1자 단어는 학습 대상이 아니다")
    }

    @Test("후보 선택이 입력 중인 단어만 바꾼다")
    func completeWordReplacesCurrentWord() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }

        controller.handle(.character("d"))  // ㅇ→ 일단 다른 텍스트
        controller.handle(.character("k"))  // 아
        controller.handle(.space)
        for key in ["d", "k", "s", "s", "u", "d", "g", "k"] { controller.handle(.character(key)) }  // 안녕하
        #expect(output.text == "아 안녕하")

        controller.completeWord("안녕하세요")
        #expect(output.operations.suffix(2) == [.delete(3), .insert("안녕하세요")])
        #expect(output.text == "아 안녕하세요")
        #expect(controller.textTail == "아 안녕하세요")
        #expect(controller.currentWord == "안녕하세요")
        #expect(committed == ["안녕하세요"])
    }
}
