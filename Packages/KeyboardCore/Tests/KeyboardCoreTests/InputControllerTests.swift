import Foundation
import Testing
import HangulEngine
@testable import KeyboardCore

/// 문서에 가해진 조작을 그대로 기록하는 fake.
///
/// `text`는 최종 상태, `operations`는 시퀀스 자체 — 조합 교체 방식이 정확한
/// delete/insert를 내는지는 시퀀스로만 검증할 수 있다.
@MainActor
final class RecordingOutput: TextOutput {
    enum Operation: Equatable, CustomStringConvertible {
        case insert(String)
        case delete(Int)
        var description: String {
            switch self {
            case .insert(let text): "insert(\(text))"
            case .delete(let count): "delete(\(count))"
            }
        }
    }

    private(set) var operations: [Operation] = []
    private(set) var text = ""

    func insertText(_ inserted: String) {
        operations.append(.insert(inserted))
        text += inserted
    }

    func deleteBackward(_ count: Int) {
        operations.append(.delete(count))
        text = String(text.dropLast(count))
    }
}

@MainActor
@Suite("InputController — 조합 교체")
struct InputControllerCompositionTests {

    @Test("'안' 타이핑의 delete/insert 시퀀스가 정확하다")
    func compositionReplaceSequence() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("d"))  // ㅇ
        controller.handle(.character("k"))  // 아
        controller.handle(.character("s"))  // 안

        #expect(output.operations == [
            .insert("ㅇ"),
            .delete(1), .insert("아"),
            .delete(1), .insert("안")
        ])
        #expect(output.text == "안")
    }

    @Test("도깨비불에서 확정과 조합이 한 번에 들어간다")
    func linkingInsertsCommittedAndComposing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["r", "k", "s", "k"] { controller.handle(.character(key)) }  // 가나

        #expect(output.text == "가나")
        // 마지막 단계: "간"을 지우고 "가"(확정) + "나"(조합)를 넣는다
        #expect(output.operations.suffix(2) == [.delete(1), .insert("가나")])
    }

    @Test("스페이스가 조합을 확정하고 공백을 넣는다")
    func spaceCommitsComposition() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.space)
        controller.handle(.character("s"))  // 새 글자로 시작해야 한다

        #expect(output.text == "가 ㄴ")
    }

    @Test("백스페이스가 조합 중이면 자모를 분해한다")
    func backspaceDecomposesWhileComposing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        for key in ["r", "k", "s"] { controller.handle(.character(key)) }  // 간
        controller.handle(.backspace)                                      // 가

        #expect(output.text == "가")
        #expect(controller.isComposing)
    }

    @Test("조합이 없으면 백스페이스가 문서 한 글자를 지운다")
    func backspaceDeletesDocumentWhenNotComposing() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.space)          // "가 " — 조합 없음
        controller.handle(.backspace)

        #expect(output.text == "가")
    }

    @Test("자모가 아닌 키는 조합을 확정하고 그대로 들어간다")
    func nonJamoKeyCommitsFirst() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.character("1"))

        #expect(output.text == "가1")
        #expect(controller.isComposing == false)
    }
}

@MainActor
@Suite("InputController — 모드와 시프트")
struct InputControllerModeTests {

    @Test("한/영 전환이 조합을 확정한다")
    func languageToggleCommits() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.toggleLanguage)
        controller.handle(.character("a"))

        #expect(output.text == "가a")
        #expect(controller.mode == .english)
    }

    @Test("영어 시프트 once는 한 글자만 대문자로 만든다")
    func englishShiftOnce() {
        let output = RecordingOutput()
        let controller = InputController(output: output, startsInHangul: false)

        controller.handle(.shift)
        controller.handle(.character("a"))
        controller.handle(.character("b"))

        #expect(output.text == "Ab")
        #expect(controller.shift == .off)
    }

    @Test("영어 시프트 연타는 캡스락이 된다")
    func englishCapsLock() {
        let output = RecordingOutput()
        let controller = InputController(output: output, startsInHangul: false)

        controller.handle(.shift)
        controller.handle(.shift)
        #expect(controller.shift == .capsLock)

        controller.handle(.character("a"))
        controller.handle(.character("b"))
        #expect(output.text == "AB")

        controller.handle(.shift)   // 캡스락 해제
        controller.handle(.character("c"))
        #expect(output.text == "ABc")
    }

    @Test("한글 시프트 once로 쌍자음을 입력한다")
    func hangulShiftProducesTenseConsonant() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.shift)
        controller.handle(.character("r"))  // ㄲ
        controller.handle(.character("k"))  // 까

        #expect(output.text == "까")
        #expect(controller.shift == .off)
    }

    @Test("한글 시프트 연타는 캡스락이 아니라 해제다")
    func hangulShiftDoubleTapTurnsOff() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.handle(.shift)
        controller.handle(.shift)
        #expect(controller.shift == .off)
    }

    @Test("기호 모드에서는 오토마타를 거치지 않는다")
    func symbolsBypassAutomaton() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.symbols)
        controller.handle(.character("1"))
        controller.handle(.character("!"))

        #expect(output.text == "가1!")
        #expect(controller.mode == .symbols)

        controller.handle(.symbols)   // 다시 누르면 한글로 복귀
        #expect(controller.mode == .hangul)
    }

    /// #+= 버그 수정 — 2페이지 전환이 문자 모드로 튕기지 않고, 복귀는 들어오기 전 모드로.
    @Test("기호 2페이지(#+=)는 페이지만 바꾸고, ABC는 들어오기 전 문자 모드로 돌아간다")
    func symbolPagesAndReturnToPreviousLetterMode() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.toggleLanguage)      // 영어에서 기호로 들어간다
        controller.handle(.symbols)
        #expect(controller.mode == .symbols)
        controller.handle(.symbolsAlternate)    // #+=
        #expect(controller.mode == .symbolsAlternate)
        controller.handle(.character("["))
        controller.handle(.symbolsAlternate)    // 123 — 1페이지로
        #expect(controller.mode == .symbols)
        controller.handle(.symbolsAlternate)
        controller.handle(.symbols)             // ABC — 2페이지에서도 곧장 문자 모드로
        #expect(controller.mode == .english, "영어에서 들어갔으니 영어로 돌아온다")
        #expect(output.text == "[")

        controller.handle(.symbolsAlternate)    // 문자 모드에서는 무시
        #expect(controller.mode == .english)
    }

    /// 입력란 특성 (PDR field-traits-and-live-settings)
    @Test("숫자 패드 진입은 조합을 확정하고 문자를 바로 커밋하며, 이탈 시 들어오기 전 문자 모드로 돌아간다")
    func numberPadEntersAndRestoresLetterMode() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.toggleLanguage)          // 영어
        controller.handle(.character("a"))
        controller.handle(.toggleLanguage)          // 한글
        controller.handle(.character("r"))          // ㄱ 조합 중
        controller.setNumberPad(.decimal)
        #expect(controller.mode == .numberPad(.decimal))
        #expect(output.text == "aㄱ", "진입 시 조합이 확정된다")

        controller.handle(.character("1"))
        controller.handle(.character("."))
        controller.handle(.character("5"))
        #expect(output.text == "aㄱ1.5", "숫자 패드 문자는 오토마타를 거치지 않는다")

        controller.setNumberPad(.decimal)           // 같은 종류 재적용 — 무시
        #expect(controller.mode == .numberPad(.decimal))
        controller.setNumberPad(nil)
        #expect(controller.mode == .hangul, "한글에서 들어갔으니 한글로 돌아온다")
        controller.setNumberPad(nil)                // 문자 모드에서 nil — 무시
        #expect(controller.mode == .hangul)
    }

    @Test("ASCII 입력란은 영어로 시작하고, 숫자 패드 중에는 복귀 목적지만 바꾼다")
    func asciiFieldStartsInEnglish() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.setStartsInEnglish(true)
        #expect(controller.mode == .english)
        controller.handle(.toggleLanguage)          // 사용자가 한글로 바꿀 수 있다
        #expect(controller.mode == .hangul)

        controller.setNumberPad(.plain)
        controller.setStartsInEnglish(true)         // 패드 중 — 모드는 그대로
        #expect(controller.mode == .numberPad(.plain))
        controller.setNumberPad(nil)
        #expect(controller.mode == .english, "복귀 목적지가 영어로 바뀌어 있었다")

        controller.setStartsInEnglish(false)
        #expect(controller.mode == .hangul)
    }

    @Test("리턴이 조합을 확정하고 줄바꿈을 넣는다")
    func returnCommitsAndInsertsNewline() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        controller.handle(.return)

        #expect(output.text == "가\n")
    }
}

@MainActor
@Suite("InputController — 천지인")
struct InputControllerCheonjiinTests {

    /// 타임아웃 검증용 조절 시계
    final class Clock: @unchecked Sendable {
        var now: TimeInterval = 0
    }

    private func makeController() -> (RecordingOutput, InputController, Clock) {
        let output = RecordingOutput()
        let clock = Clock()
        let controller = InputController(
            output: output,
            hangulSource: CheonjiinSource(timeout: 0.8),
            clock: { clock.now }
        )
        return (output, controller, clock)
    }

    /// 매 키마다 0.1초씩 흐르는 입력 (타임아웃 안)
    private func press(_ keys: [String], _ controller: InputController, _ clock: Clock) {
        for key in keys {
            clock.now += 0.1
            controller.handle(.character(key))
        }
    }

    @Test("pending ㆍ가 조합 영역으로 표시되고 모음으로 해소된다")
    func pendingDotDisplaySequence() {
        let (output, controller, clock) = makeController()

        press(["ㄱ", "ㆍ", "ㅡ"], controller, clock)   // ㄱ → ㄱㆍ → 고

        #expect(output.operations == [
            .insert("ㄱ"),
            .delete(1), .insert("ㄱㆍ"),
            .delete(2), .insert("고")
        ])
        #expect(output.text == "고")
    }

    @Test("pending만 있어도 조합 중이고, 확정하면 점이 리터럴로 남는다")
    func pendingOnlyState() {
        let (output, controller, clock) = makeController()

        press(["ㆍ"], controller, clock)
        #expect(controller.isComposing)

        // 조합 중 스페이스 = 이동(확정만) — 점이 리터럴로 남고 공백은 없다 (2026-09-07 스페이스 이동 겸용)
        controller.handle(.space)
        #expect(output.text == "ㆍ")
        #expect(controller.isComposing == false)
        controller.handle(.space)   // 조합 없음 → 공백
        #expect(output.text == "ㆍ ")
    }

    @Test("백스페이스가 마지막 키 입력을 취소한다 — 도깨비불 역행")
    func backspaceReplaysKeystrokes() {
        let (output, controller, clock) = makeController()

        press(["ㄱ", "ㅣ", "ㆍ", "ㄴ", "ㅣ"], controller, clock)   // 가니
        #expect(output.text == "가니")

        controller.handle(.backspace)
        #expect(output.text == "간", "실측: 가니 ⌫ → 간")
        // run 전체(확정 '가' + 조합 '니')를 걷어내고 재생 결과를 넣는다
        #expect(output.operations.suffix(2) == [.delete(2), .insert("간")])

        controller.handle(.backspace)   // 간 → 가
        controller.handle(.backspace)   // 가 → 기 (ㅏ는 ㅣ+ㆍ로 만들었으므로 ㆍ만 취소된다)
        #expect(output.text == "기")

        controller.handle(.backspace)   // 기 → ㄱ
        controller.handle(.backspace)   // ㄱ → ""
        #expect(output.text == "", "로그를 다 쓰면 빈 문서")

        controller.handle(.backspace)
        #expect(output.operations.last == .delete(1), "로그가 비면 문서 한 글자 삭제로 폴백")
    }

    @Test("조합 중 스페이스는 이동 — 공백 없이 확정하고, 조합이 없으면 공백을 넣는다 (Apple 10키, 2026-09-07)")
    func spaceAdvancesWhileComposing() {
        let (output, controller, clock) = makeController()
        press(["ㄱ", "ㅣ"], controller, clock)          // 기 (조합 중)
        controller.handle(.space)
        #expect(output.text == "기", "공백 없이 확정만")
        #expect(controller.isComposing == false)
        press(["ㄱ", "ㅣ"], controller, clock)          // 순환 없이 새 음절
        #expect(output.text == "기기")
        controller.handle(.space)                        // 조합 중 → 확정만
        controller.handle(.space)                        // 조합 없음 → 공백
        #expect(output.text == "기기 ")
        // 이동 스페이스는 더블스페이스 마침표 연쇄에 들어가지 않는다 — 두 스페이스가 ". "로 바뀌지 않았다
        #expect(!output.text.contains("."))
    }

    @Test("두벌식은 조합 중 스페이스가 여전히 공백을 넣는다 (이동 겸용은 천지인만)")
    func dubeolsikSpaceStillInsertsSpace() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.handle(.character("r")); controller.handle(.character("k"))   // 가
        controller.handle(.space)
        #expect(output.text == "가 ")
    }

    @Test("이동(→)이 공백 없이 조합을 확정한다 — 학교")
    func advanceCommitsWithoutSpace() {
        let (output, controller, clock) = makeController()

        press(["ㅅ", "ㅅ", "ㅣ", "ㆍ", "ㄱ"], controller, clock)   // 학
        controller.handle(.advance)
        press(["ㄱ", "ㆍ", "ㆍ", "ㅡ"], controller, clock)          // 교

        #expect(output.text == "학교")
    }

    @Test("자음 순환은 타임아웃 안에서만 일어난다")
    func consonantCycleRespectsTimeout() {
        let (fast, fastController, fastClock) = makeController()
        press(["ㄱ", "ㄱ"], fastController, fastClock)
        #expect(fast.text == "ㅋ")

        let (slow, slowController, slowClock) = makeController()
        slowClock.now = 0
        slowController.handle(.character("ㄱ"))
        slowClock.now = 1.0
        slowController.handle(.character("ㄱ"))
        #expect(slow.text == "ㄱㄱ")
    }

    @Test("자판 전환이 조합을 확정하고 천지인 상태를 리셋한다")
    func sourceSwapCommits() {
        let (output, controller, clock) = makeController()

        press(["ㄱ", "ㅣ", "ㆍ"], controller, clock)   // 가
        controller.setHangulSource(DubeolsikSource())
        controller.handle(.character("r"))              // ㄱ — 새 글자

        #expect(output.text == "가ㄱ")
    }

    /// 확정 텍스트 파괴 회귀 방어 — 이중 점을 결합형 ᆢ(U+11A2)로 표시하면
    /// 직전 완성 음절과 한 그래핌으로 병합되어, 글자 수 기반 delete가
    /// 확정된 글자까지 지운다. RecordingOutput의 dropLast도 그래핌 단위라
    /// 이 fake로 그대로 재현된다.
    @Test("확정 음절 뒤 이중 점이 확정 텍스트를 지우지 않는다")
    func doubleDotAfterCommittedSyllableDoesNotDestroyText() {
        let (output, controller, clock) = makeController()

        press(["ㄱ", "ㅣ", "ㆍ"], controller, clock)   // 가
        controller.handle(.advance)                     // 공백 없이 확정
        press(["ㆍ", "ㆍ", "ㅣ"], controller, clock)   // ㆍ → ㆍㆍ → ㅕ

        #expect(output.text == "가ㅕ")
    }

    /// 로그 상한(128) 초과 시 부분 로그로 재생하면 걷어낼 범위가 어긋나
    /// 확정 텍스트까지 파괴된다 — 초과하면 run이 끝날 때까지 자모 단위로 폴백한다.
    @Test("키 로그 상한 초과 후 백스페이스는 자모 단위로 폴백한다")
    func backspaceFallsBackAfterLogOverflow() {
        let (output, controller, clock) = makeController()

        // 128키: (ㄱ, ㅣ) × 64 → "기" 63개 확정 + "기" 조합 중
        for _ in 0..<64 { press(["ㄱ", "ㅣ"], controller, clock) }
        let committed = String(repeating: "기", count: 63)
        #expect(output.text == committed + "기")

        press(["ㆍ"], controller, clock)   // 129키째 — 상한 초과, ㅣ+ㆍ = ㅏ
        #expect(output.text == committed + "가")

        controller.handle(.backspace)      // 자모 단위: 가 → ㄱ (재생이면 텍스트가 깨진다)
        #expect(output.text == committed + "ㄱ")
        controller.handle(.backspace)      // ㄱ 제거
        #expect(output.text == committed)
        controller.handle(.backspace)      // 조합 없음 — 문서 한 글자 삭제
        #expect(output.text == String(repeating: "기", count: 62))
    }

    @Test("sync 후 천지인 순환이 이어지지 않는다")
    func syncResetsCheonjiinCycle() {
        let (output, controller, clock) = makeController()

        clock.now = 0.1
        controller.handle(.character("ㄱ"))
        controller.syncWithDocument()                  // 커서 이동
        clock.now = 0.2                                 // 타임아웃(0.8초) 안이지만
        controller.handle(.character("ㄱ"))

        #expect(output.text == "ㄱㄱ", "순환(ㅋ)이 아니라 새 자모여야 한다")
    }

    @Test("sync 후 백스페이스는 재생이 아니라 문서 한 글자 삭제다")
    func syncClearsKeystrokeLog() {
        let (output, controller, clock) = makeController()

        press(["ㄱ", "ㅣ", "ㆍ", "ㄴ", "ㅣ"], controller, clock)   // 가니
        controller.syncWithDocument()
        controller.handle(.backspace)

        #expect(output.operations.suffix(1) == [.delete(1)], "재생 delete/insert가 나오면 새 커서 위치의 텍스트를 파괴한다")
        #expect(output.text == "가")
    }
}

@MainActor
@Suite("InputController — 문서 동기화")
struct InputControllerSyncTests {

    /// 커서 이동 후 조합 상태를 들고 있으면 다음 입력이 엉뚱한 위치를 덮어쓴다.
    @Test("sync 후에는 조합 교체가 일어나지 않는다")
    func syncPreventsStaleReplacement() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))     // "가" 조합 중
        controller.syncWithDocument()           // 사용자가 커서를 옮겼다

        controller.handle(.character("s"))      // ㄴ — 받침이 아니라 새 글자여야 한다

        #expect(controller.isComposing)
        // sync 이후 첫 입력에 delete가 없어야 한다 (조합 교체 금지)
        let operationsAfterSync = output.operations.suffix(1)
        #expect(operationsAfterSync == [.insert("ㄴ")])
    }

    @Test("sync는 문서를 건드리지 않는다")
    func syncDoesNotTouchDocument() {
        let output = RecordingOutput()
        let controller = InputController(output: output)

        controller.handle(.character("r"))
        controller.handle(.character("k"))
        let operationCount = output.operations.count
        controller.syncWithDocument()

        #expect(output.operations.count == operationCount)
    }
}

// MARK: - 자동 대문자 (PDR auto-capitalization)

@MainActor
@Suite("InputController — 자동 대문자")
struct InputControllerAutoCapitalizationTests {

    final class Clock: @unchecked Sendable {
        var now: TimeInterval = 0
    }

    private func makeEnglish(_ rule: AutoCapitalization) -> (RecordingOutput, InputController) {
        let output = RecordingOutput()
        let controller = InputController(output: output, startsInHangul: false)
        controller.autoCapitalization = rule
        return (output, controller)
    }

    /// 공백·리턴은 키 이벤트로, 나머지는 문자 키로 친다
    private func type(_ text: String, _ controller: InputController) {
        for character in text {
            switch character {
            case " ": controller.handle(.space)
            case "\n": controller.handle(.return)
            default: controller.handle(.character(String(character)))
            }
        }
    }

    @Test("문장 규칙 — 문서 시작과 마침표·물음표+공백 뒤에만 시프트가 켜진다")
    func sentencesCapitalizeAtStartAndAfterTerminator() {
        let (output, controller) = makeEnglish(.sentences)
        #expect(controller.shift == .once, "문서 시작")
        type("hi there", controller)
        #expect(output.text == "Hi there")
        #expect(controller.shift == .off, "공백 뒤라도 마침표가 없으면 소문자")
        type(". ", controller)
        #expect(controller.shift == .once)
        type("ok? ", controller)
        #expect(controller.shift == .once, "물음표 뒤")
        type("fine", controller)
        #expect(output.text == "Hi there. Ok? Fine")
    }

    @Test("마침표 직후(공백 없음)에는 켜지지 않는다 — 'e.g'류를 대문자로 만들지 않는다")
    func sentencesNeedSpaceAfterTerminator() {
        let (output, controller) = makeEnglish(.sentences)
        type("a.", controller)
        #expect(controller.shift == .off)
        type("b", controller)
        #expect(output.text == "A.b")
    }

    @Test("단어 규칙 — 공백마다 켜진다")
    func wordsCapitalizeEveryWord() {
        let (output, controller) = makeEnglish(.words)
        type("new york city", controller)
        #expect(output.text == "New York City")
    }

    @Test("전부 대문자 규칙 — 글자마다 다시 켜진다")
    func allCharactersKeepShiftOn() {
        let (output, controller) = makeEnglish(.allCharacters)
        type("abc d", controller)
        #expect(output.text == "ABC D")
        #expect(controller.shift == .once)
    }

    @Test("자동으로 켜진 시프트는 한 번 탭으로 꺼지고(캡스락 아님), 사용자가 켠 시프트는 규칙이 끄지 않는다")
    func tapCancelsAutoShiftButManualShiftSurvives() {
        let (output, controller) = makeEnglish(.sentences)
        #expect(controller.shift == .once)
        controller.handle(.shift)
        #expect(controller.shift == .off, "자동 once → 탭 → 해제 (캡스락으로 가지 않는다)")
        type("a", controller)
        #expect(output.text == "a")
        controller.handle(.shift)   // 사용자가 켠 once
        controller.handle(.space)   // 문장 규칙상 소문자 자리 — 그래도 유지
        #expect(controller.shift == .once)
        type("b", controller)
        #expect(output.text == "a B")
    }

    @Test("백스페이스로 꼬리가 바뀌면 다시 판정한다")
    func backspaceReevaluates() {
        let (output, controller) = makeEnglish(.sentences)
        type("hi. w", controller)
        #expect(output.text == "Hi. W")
        #expect(controller.shift == .off)
        controller.handle(.backspace)   // "Hi. " — 문장 시작 자리
        #expect(controller.shift == .once)
        controller.handle(.backspace)   // "Hi." — 공백 없음
        #expect(controller.shift == .off)
    }

    @Test("리턴 뒤 새 줄은 문장 시작이다")
    func returnStartsSentence() {
        let (output, controller) = makeEnglish(.sentences)
        type("one\ntwo", controller)
        #expect(output.text == "One\nTwo")
    }

    @Test("한글 모드에는 영향이 없고, 영어로 전환·리턴하는 순간 판정한다")
    func hangulUnaffectedAndToggleEvaluates() {
        let output = RecordingOutput()
        let controller = InputController(output: output)   // 한글 시작
        controller.autoCapitalization = .sentences
        #expect(controller.shift == .off, "한글 모드 — 문서 시작이어도 시프트를 켜지 않는다")
        controller.handle(.character("d"))
        controller.handle(.character("k"))   // 아
        controller.handle(.space)
        controller.handle(.toggleLanguage)
        #expect(controller.mode == .english)
        #expect(controller.shift == .off, "'아 ' 뒤 — 문장 끝이 아니다")
        controller.handle(.return)
        #expect(controller.shift == .once, "새 줄 = 문장 시작")
        controller.handle(.toggleLanguage)
        #expect(controller.shift == .off, "한글로 돌아가면 시프트 해제")
    }

    @Test("기호 자판에서 마침표를 치고 돌아오면 공백 뒤에 켜진다")
    func symbolsRoundTrip() {
        let (output, controller) = makeEnglish(.sentences)
        type("hi", controller)
        controller.handle(.symbols)
        controller.handle(.character("."))
        controller.handle(.symbols)   // 영어로 복귀 — "Hi." 공백 없음
        #expect(controller.mode == .english && controller.shift == .off)
        controller.handle(.space)
        #expect(controller.shift == .once)
        type("x", controller)
        #expect(output.text == "Hi. X")
    }

    @Test("더블스페이스 마침표 뒤에도 켜진다")
    func doubleSpacePeriodTriggers() {
        let output = RecordingOutput()
        let clock = Clock()
        let controller = InputController(output: output, startsInHangul: false, clock: { clock.now })
        controller.autoCapitalization = .sentences
        type("hi", controller)
        controller.handle(.space)
        clock.now += 0.1
        controller.handle(.space)
        #expect(output.text == "Hi. ")
        #expect(controller.shift == .once)
    }

    @Test("캡스락은 자동 규칙이 건드리지 않는다")
    func capsLockUntouched() {
        let (output, controller) = makeEnglish(.sentences)
        controller.handle(.shift)   // 자동 once → 해제
        controller.handle(.shift)   // once (수동)
        controller.handle(.shift)   // 캡스락
        #expect(controller.shift == .capsLock)
        type("ab cd", controller)
        #expect(output.text == "AB CD")
        #expect(controller.shift == .capsLock)
    }

    @Test("문서 동기화로 꼬리가 들어오면 판정하고, 문맥을 모르면 상태를 건드리지 않는다")
    func syncEvaluatesOnlyWithKnownTail() {
        let (_, controller) = makeEnglish(.sentences)
        controller.syncWithDocument(documentTail: "Hello world")
        #expect(controller.shift == .off)
        controller.syncWithDocument(documentTail: "Hello world. ")
        #expect(controller.shift == .once)
        controller.syncWithDocument()   // 커서 위치 불명 — 커서 도구 이동 직후
        #expect(controller.shift == .once, "깜빡임 방지 — 실제 문맥이 올 때까지 유지")
        controller.syncWithDocument(documentTail: "Hello world. Again")
        #expect(controller.shift == .off)
    }

    @Test("규칙이 none이면 켜지지 않고, 켜져 있던 자동 시프트는 none으로 바뀌면 꺼진다")
    func noneNeverCapitalizes() {
        let (output, controller) = makeEnglish(.none)
        type("a. b", controller)
        #expect(output.text == "a. b")
        controller.autoCapitalization = .sentences
        #expect(controller.shift == .off, "'a. b' 뒤 — 문장 중간")
        type(". ", controller)
        #expect(controller.shift == .once)
        controller.autoCapitalization = .none   // 입력란이 바뀌어 거부
        #expect(controller.shift == .off)
    }

    @Test("닫는 따옴표·괄호 뒤의 마침표 공백도 문장 끝으로 본다")
    func closingPunctuationBeforeSpace() {
        let (_, controller) = makeEnglish(.sentences)
        controller.syncWithDocument(documentTail: "He said \"hi.\" ")
        #expect(controller.shift == .once)
        controller.syncWithDocument(documentTail: "(see above.) ")
        #expect(controller.shift == .once)
        controller.syncWithDocument(documentTail: "\"quoted\" ")
        #expect(controller.shift == .off)
        controller.syncWithDocument(documentTail: "   ")
        #expect(controller.shift == .once, "공백만 있으면 문서 시작으로 본다")
    }

    @Test("외부 텍스트 삽입 뒤에도 꼬리로 판정한다")
    func providedTextReevaluates() {
        let (output, controller) = makeEnglish(.sentences)
        controller.insertProvidedText("Done. ")
        #expect(output.text == "Done. ")
        #expect(controller.shift == .once)
        controller.insertProvidedText("123456")
        #expect(controller.shift == .off)
    }
}

// MARK: - 다문자 키 (문장부호 키 길게 누르기 — ".com")

@MainActor
@Suite("InputController — 다문자 키")
struct InputControllerMultiCharacterKeyTests {

    @Test("다문자 키(.com)는 시프트·캡스락에도 대문자가 되지 않고, once는 소비된다")
    func multiCharacterKeyIsNeverUppercased() {
        let output = RecordingOutput()
        let controller = InputController(output: output, startsInHangul: false)
        controller.handle(.shift)
        controller.handle(.character(".com"))
        #expect(output.text == ".com")
        #expect(controller.shift == .off, "once는 소비된다")
        controller.handle(.shift)
        controller.handle(.shift)   // 캡스락
        controller.handle(.character(".com"))
        controller.handle(.character("a"))
        #expect(output.text == ".com.comA")
    }

    @Test("한글 모드에서 문장부호 키는 조합을 확정하고 그대로 들어간다 (시프트 중에도 그대로)")
    func punctuationCommitsCompositionInHangul() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.handle(.character("r"))
        controller.handle(.character("k"))   // 가 (조합 중)
        controller.handle(.character(".com"))
        #expect(output.text == "가.com")
        #expect(controller.isComposing == false)
        controller.handle(.shift)
        controller.handle(.character("@"))
        #expect(output.text == "가.com@")
        controller.handle(.character(","))
        #expect(output.text == "가.com@,")
    }
}
