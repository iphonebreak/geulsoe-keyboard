import Foundation
import HangulEngine
import TadakDomain

/// 키 이벤트를 해석해 문서에 반영하는 입력 오케스트레이터. Phase 2의 심장.
///
/// **조합 교체 방식:** `UITextDocumentProxy`에는 marked text API가 없다. 조합 중인
/// 글자는 "직전 composing 글자 수만큼 지우고 새로 넣기"로 표현한다. 이 delete/insert
/// 시퀀스가 정확한지가 이 타입의 핵심 계약이고, 테스트가 그 시퀀스를 그대로 검증한다.
/// 천지인의 pending 문자(`ㆍ`/`ᆢ`)도 이 조합 영역의 일부다 — 오토마타 조합 글자
/// 뒤에 붙여 표시하고, 교체할 때 함께 지운다.
///
/// **백스페이스 두 방식:** 키 재생 자판(천지인)은 조합 run 동안의 키 로그를 유지하고
/// 백스페이스마다 마지막 키를 빼고 처음부터 재생한다 — 도깨비불 역행(가니 → 간)과
/// pending 복원(고 → ㄱㆍ)이 이 방식으로만 나온다. 나머지 자판은 오토마타의 자모
/// 단위 삭제를 쓴다. run은 확정 시점(공백·리턴·이동·자판 전환·sync)마다 끝난다.
///
/// 핫패스 규칙: 이 경로에는 계층간 DTO 변환을 두지 않는다 (PDR 참조).
@MainActor
public final class InputController {

    public private(set) var mode: InputMode
    public private(set) var shift: ShiftState = .off
    /// 기호 자판에 들어오기 직전의 문자 모드 — 기호에서 나갈 때 여기로 돌아간다
    private var letterMode: InputMode = .hangul

    private let output: TextOutput
    private var automaton = HangulAutomaton()
    private var hangulSource: JamoSource
    /// 문서에 들어가 있는 조합 중 글자 수 (교체 시 지울 개수). pending 문자 포함.
    private var composingCount = 0
    private var clock: () -> TimeInterval

    /// 백스페이스 재생용 키 로그 (`prefersKeystrokeReplayBackspace` 자판만 쌓는다)
    private var keystrokeLog: [(key: String, time: TimeInterval)] = []
    /// 로그 시작 이후 문서에 확정된 글자 수 — 재생 시 함께 걷어낼 범위
    private var runCommittedCount = 0
    /// 로그 상한. 넘으면 **이번 run이 끝날 때까지** 로그를 버리고 자모 단위
    /// 백스페이스로 폴백한다. run 중간부터 시작하는 부분 로그로 재생하면
    /// 걷어낼 범위와 재생 결과가 어긋나 확정된 텍스트까지 파괴된다.
    /// run은 공백마다 끝나므로 실사용에서 닿을 일이 거의 없다.
    private let keystrokeLogLimit = 128
    private var keystrokeLogOverflowed = false

    /// 채움글 트리거 매칭용 확정 텍스트 꼬리. 문서가 아니라 이 파이프라인이 직접 추적한다 —
    /// 300자 문맥 제한·호스트별 프록시 편차와 무관해진다 (PDR snippet-autocomplete).
    /// 메모리에만 있고 48자 상한. 로그·파일·네트워크로 내보내지 않는다 (보안 규칙).
    private var committedTail = ""
    private let committedTailLimit = 48
    /// 후보 선택·채움글 삽입 직후 참 — 꼬리 끝 단어는 이미 처리됐으므로 다음 공백/리턴이
    /// 같은 단어를 다시 학습으로 보내면 안 된다 (이중 카운트·스니펫 본문 학습 방지).
    /// 타이핑·백스페이스로 단어가 변하면 해제된다.
    private var suppressesNextWordCommit = false

    /// 외부 텍스트(붙여넣기·인증번호·이모지) 삽입 후 첫 단어 확정까지 학습을 막는다.
    /// `suppressesNextWordCommit`은 타이핑이 이어지면 풀리지만, 붙여넣은 텍스트에 한글을
    /// 이어 쳐 만들어진 run은 클립보드 유래 조각을 포함하므로 학습 저장소에 들어가면
    /// 안 된다 (보안 규칙 — 리뷰 반영). 공백/리턴에서 1회 소비된다.
    private var blocksLearningUntilSeparator = false

    /// 스페이스 두 번 → ". " 치환. 조립 지점이 설정으로 갱신한다.
    public var doubleSpacePeriod = true
    /// 더블스페이스 인정 시간. 고정값 — 시스템 키보드 체감에 맞췄다.
    private let doubleSpaceTimeout: TimeInterval = 0.35
    /// 마지막 키가 스페이스였을 때 그 시각. 다른 입력이 끼면 nil.
    private var lastSpaceTimestamp: TimeInterval?

    /// 자동 대문자 규칙 — 조립 지점이 입력란 `autocapitalizationType`과 설정을 합쳐 넣는다
    /// (PDR auto-capitalization). 영어 모드에서만 동작하고, 바뀌면 즉시 다시 판정한다.
    public var autoCapitalization: AutoCapitalization = .none {
        didSet { if autoCapitalization != oldValue { updateAutoCapitalization() } }
    }
    /// 지금의 `.once`가 자동 규칙이 켠 것인가. 사용자가 켠 시프트는 규칙이 끄지 않고,
    /// 자동으로 켠 것은 시프트 한 번 탭으로 꺼진다(캡스락으로 가지 않는다) — Apple과 동일.
    private var isAutoShifted = false

    public init(
        output: TextOutput,
        hangulSource: JamoSource = DubeolsikSource(),
        startsInHangul: Bool = true,
        clock: @escaping () -> TimeInterval = { Date().timeIntervalSinceReferenceDate }
    ) {
        self.output = output
        self.hangulSource = hangulSource
        self.mode = startsInHangul ? .hangul : .english
        self.clock = clock
    }

    /// 지금 조합 중인가. 툴바 모드 전환(`ToolbarState.textDidChange`)의 입력이 된다.
    /// 천지인의 pending 점만 떠 있는 상태도 조합 중으로 본다.
    public var isComposing: Bool {
        automaton.isComposing || !hangulSource.pendingText.isEmpty
    }

    /// 채움글 매칭 대상 — 확정 꼬리 + 조합 중 글자 + pending 문자.
    /// "절"이 아직 조합 중일 때도 후보가 떠야 하므로 조합분을 포함한다.
    public var textTail: String {
        committedTail + automaton.composingText + hangulSource.pendingText
    }

    /// 입력 중인 단어 — 꼬리 끝의 한글 음절 연속 run (조합 중 음절 포함).
    /// 추천단어 매칭의 입력이 된다. 천지인 pending 점(ㆍ)은 음절이 아니라 run을 끊는다.
    public var currentWord: String {
        Self.trailingHangulRun(of: textTail)
    }

    /// 공백·리턴·후보 선택으로 단어가 확정될 때 호출된다 (한글 2자 이상만).
    /// 조립 지점이 학습 엔진에 연결한다 — secure 필드 제외는 조립 지점 책임.
    public var onWordCommitted: ((String) -> Void)?

    /// 활성 자판 변경 시 조립 지점이 호출한다. 진행 중인 조합은 확정된다.
    public func setHangulSource(_ source: JamoSource) {
        commitComposition()
        hangulSource = source
    }

    // MARK: - 입력란 특성 (PDR field-traits-and-live-settings)

    /// 숫자 전용 입력란 진입/이탈. `kind`가 있으면 숫자 패드 모드로, nil이면 들어오기 전
    /// 문자 모드로 돌아간다 (이미 문자 모드면 그대로). 조합은 확정된다.
    public func setNumberPad(_ kind: NumberPadKind?) {
        if let kind {
            guard mode != .numberPad(kind) else { return }
            commitComposition()
            if mode.isLetter { letterMode = mode }
            mode = .numberPad(kind)
            shift = .off
        } else if mode.isNumberPad {
            commitComposition()
            mode = letterMode
        }
        updateAutoCapitalization()
    }

    /// 입력란이 ASCII(이메일·URL 등)를 요구하면 영어로 시작한다. 숫자 패드 중에는 복귀 목적지만
    /// 바꾼다. 사용자는 이후 한영 키로 자유롭게 바꿀 수 있다.
    public func setStartsInEnglish(_ english: Bool) {
        let target: InputMode = english ? .english : .hangul
        if mode.isNumberPad {
            letterMode = target
        } else if mode.isLetter, mode != target {
            commitComposition()
            mode = target
            shift = .off
        }
        updateAutoCapitalization()
    }

    // MARK: - 키 이벤트

    public func handle(_ event: KeyEvent) {
        // 스페이스가 아닌 모든 이벤트는 더블스페이스 연쇄를 끊는다
        if case .space = event {} else { lastSpaceTimestamp = nil }
        switch event {
        case .character(let key): handleCharacter(key)
        case .backspace: handleBackspace()
        case .space: handleSpace()
        case .return:
            commitComposition()
            notifyWordCommitted()
            output.insertText("\n")
            // 트리거는 줄을 넘지 않는다 — 꼬리를 새 줄에서 다시 시작한다
            committedTail.removeAll()
        case .shift: handleShift()
        case .toggleLanguage:
            commitComposition()
            mode = (mode == .hangul) ? .english : .hangul
            shift = .off
        case .symbols:
            commitComposition()
            if mode.isSymbols {
                // 기호 자판(어느 페이지든)에서 누르면 들어오기 전 문자 모드로 돌아간다
                mode = letterMode
            } else {
                letterMode = mode
                mode = .symbols
            }
            shift = .off
        case .symbolsAlternate:
            commitComposition()
            // 123 ↔ #+= 페이지 전환 — 문자 모드에서는 무의미하므로 무시
            if mode.isSymbols {
                mode = (mode == .symbolsAlternate) ? .symbols : .symbolsAlternate
            }
        case .advance:
            // 천지인 이동(→) — 공백 없이 조합만 확정한다 (실측 스펙)
            commitComposition()
        case .spacer:
            break  // 스페이서 — 배열 정렬용, 입력 없음
        }
        // 시프트 탭은 사용자의 결정이라 다시 판정하지 않는다 — 판정하면 방금 끈 시프트가 도로 켜진다
        if event != .shift { updateAutoCapitalization() }
    }

    /// 커서 이동·필드 전환·앱 전환 시 호출한다 (`textDidChange` 경로).
    ///
    /// 문서 쪽 상태와 우리 조합 상태가 어긋났으므로, 조합을 **문서에 이미 있는 그대로**
    /// 확정 처리하고 내부 상태만 비운다. 지우거나 다시 넣지 않는다 — 커서가 이미
    /// 다른 곳에 가 있어 교체 방식이 오히려 문서를 훼손한다.
    ///
    /// - Parameter documentTail: 커서 앞 문서 텍스트(`documentContextBeforeInput`, 없으면 nil).
    ///   있으면 꼬리를 여기서 **다시 세운다** — 호스트가 우리 백스페이스에 반응해 보내는
    ///   textDidChange가 꼬리를 날려 "…3절"의 "절"을 지웠다 다시 치면 채움글이 안 뜨던 문제
    ///   (2026-09-03). 문서가 우리 조합 글자로 끝나 있으면(= 우리 편집의 메아리) 조합 상태도
    ///   유지한다. 문서에서 가져온 꼬리 끝 단어는 사용자가 이 키보드로 친 것이 아닐 수 있어
    ///   다음 구분자까지 학습을 막는다.
    public func syncWithDocument(documentTail: String? = nil) {
        let composing = automaton.composingText + hangulSource.pendingText
        if let documentTail, !composing.isEmpty, documentTail.hasSuffix(composing) {
            // 문서 = 확정 + 우리 조합 그대로. 상태는 살리고 확정 꼬리만 문서 기준으로 보정한다
            committedTail = Self.tailLine(of: String(documentTail.dropLast(composing.count)),
                                          limit: committedTailLimit)
            return
        }
        automaton.reset()
        hangulSource.reset()
        composingCount = 0
        keystrokeLog.removeAll()
        runCommittedCount = 0
        keystrokeLogOverflowed = false
        suppressesNextWordCommit = false
        lastSpaceTimestamp = nil
        if let documentTail {
            committedTail = Self.tailLine(of: documentTail, limit: committedTailLimit)
            // 커서 앞 단어는 이 키보드로 친 것이 아닐 수 있다 — 첫 구분자까지 학습 제외
            blocksLearningUntilSeparator = !Self.trailingHangulRun(of: committedTail).isEmpty
        } else {
            // 커서가 어디로 갔는지 모른다 — 추적해 온 꼬리도 문서와 어긋났으므로 버린다
            committedTail.removeAll()
            blocksLearningUntilSeparator = false
        }
        // 문맥을 모를 때는 시프트를 건드리지 않는다 — 커서 도구 이동 직후 nil sync가 오고 곧
        // textDidChange가 실제 꼬리를 가져오므로, 여기서 판정하면 시프트 키가 깜빡인다
        if documentTail != nil { updateAutoCapitalization() }
    }

    /// 문서 꼬리에서 마지막 줄의 끝 `limit`자 — 트리거는 줄을 넘지 않는다는 규칙과 일치
    private static func tailLine(of text: String, limit: Int) -> String {
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return String(lastLine.suffix(limit))
    }

    // MARK: - 문자

    private func handleCharacter(_ key: String) {
        suppressesNextWordCommit = false
        switch mode {
        case .hangul: handleHangulKey(key)
        case .english: handleEnglishKey(key)
        case .symbols, .symbolsAlternate, .numberPad:
            commitComposition()
            output.insertText(key)
            appendToTail(key)
        }
    }

    private func handleHangulKey(_ key: String) {
        // 시프트 once면 대문자 키로 승격 (두벌식 쌍자음/복모음 키. 한글 자모 키는 불변).
        // 다문자 키(문장부호 키 길게 누르기 ".com")는 그대로 — 자모가 아니라 아래에서 바로 들어간다
        let effectiveKey = (shift != .off && key.count == 1) ? key.uppercased() : key
        if shift == .once { shift = .off }

        let timestamp = clock()
        let events = hangulSource.accept(key: effectiveKey, at: timestamp)
        guard !events.isEmpty else {
            // 자모가 아닌 키 — 조합을 끝내고 그대로 넣는다
            commitComposition()
            output.insertText(key)
            appendToTail(key)
            return
        }
        if hangulSource.prefersKeystrokeReplayBackspace, !keystrokeLogOverflowed {
            if keystrokeLog.count >= keystrokeLogLimit {
                keystrokeLog.removeAll()
                keystrokeLogOverflowed = true
            } else {
                keystrokeLog.append((effectiveKey, timestamp))
            }
        }
        for event in events {
            switch event {
            case .emit(let jamo):
                apply(automaton.input(jamo))
            case .replaceLast(let jamo):
                apply(automaton.replaceLast(jamo))
            case .pendingChanged:
                // 자모는 그대로, 표시(pending 문자)만 갱신한다
                apply(AutomatonOutput(committed: "", composing: automaton.composingText))
            }
        }
    }

    private func handleEnglishKey(_ key: String) {
        // 시프트는 글자 하나짜리 키에만 적용한다 — ".com" 같은 다문자 키(문장부호 키 길게 누르기)는
        // 캡스락 중에도 그대로 들어간다. once는 그래도 소비된다 (단문자 문장부호와 같은 규칙)
        let capitalizable = key.count == 1
        let text: String
        switch shift {
        case .off: text = key
        case .once:
            text = capitalizable ? key.uppercased() : key
            shift = .off
            isAutoShifted = false
        case .capsLock:
            text = capitalizable ? key.uppercased() : key
        }
        output.insertText(text)
        appendToTail(text)
    }

    // MARK: - 기능 키

    private func handleBackspace() {
        suppressesNextWordCommit = false
        guard mode == .hangul else {
            output.deleteBackward(1)
            // 기호/영어 모드도 꼬리를 함께 걷는다 — 트리거의 숫자·콜론이 이 모드에서
            // 지워지므로, 빠뜨리면 문서에 없는 텍스트로 칩이 뜨고 탭 시 문서를 파괴한다
            if !committedTail.isEmpty { committedTail.removeLast() }
            return
        }
        if hangulSource.prefersKeystrokeReplayBackspace, !keystrokeLog.isEmpty {
            replayAfterRemovingLastKeystroke()
            return
        }
        if !hangulSource.pendingText.isEmpty {
            // pending 점만 되돌린다 (자모 단위 폴백 경로 — 로그 상한 초과 시)
            hangulSource.reset()
            apply(AutomatonOutput(committed: "", composing: automaton.composingText))
        } else if automaton.isComposing {
            apply(automaton.backspace())
            // 연타 상태를 끊는다 — 지워진 자모에 이어 승격되면 안 된다 (단모음)
            hangulSource.reset()
        } else {
            output.deleteBackward(1)
            if !committedTail.isEmpty { committedTail.removeLast() }
        }
    }

    /// 마지막 키 입력 취소 — run 전체를 걷어내고 로그를 재생해 다시 넣는다.
    private func replayAfterRemovingLastKeystroke() {
        keystrokeLog.removeLast()
        let deleteCount = composingCount + runCommittedCount

        automaton.reset()
        hangulSource.reset()
        var committed = ""
        for entry in keystrokeLog {
            for event in hangulSource.accept(key: entry.key, at: entry.time) {
                switch event {
                case .emit(let jamo):
                    committed += automaton.input(jamo).committed
                case .replaceLast(let jamo):
                    committed += automaton.replaceLast(jamo).committed
                case .pendingChanged:
                    break
                }
            }
        }

        if deleteCount > 0 {
            output.deleteBackward(deleteCount)
        }
        let composing = automaton.composingText + hangulSource.pendingText
        let text = committed + composing
        if !text.isEmpty {
            output.insertText(text)
        }
        composingCount = composing.count
        // 꼬리에서 run 확정분을 걷어내고 재생 결과로 다시 채운다 (문서 조작과 동일한 교체)
        committedTail.removeLast(min(runCommittedCount, committedTail.count))
        appendToTail(committed)
        runCommittedCount = committed.count
    }

    private func handleSpace() {
        // 천지인: 조합 중 스페이스는 이동(확정만, 공백 없음) — Apple 10키. 배열에서 →(이동) 키를 뺀 대신이다
        // (2026-09-07). 이동 뒤의 공백은 첫 공백이라 더블스페이스 마침표 연쇄에 넣지 않는다.
        if mode == .hangul, hangulSource.spaceAdvancesWhileComposing, isComposing {
            commitComposition()
            lastSpaceTimestamp = nil
            return
        }
        let now = clock()
        // 더블스페이스 → ". ". 직전 공백의 앞이 문장 문자일 때만 — 연속 공백으로
        // 정렬하려는 의도를 마침표로 오변환하지 않는다 (PDR release-readiness 결정 4).
        if doubleSpacePeriod,
           let last = lastSpaceTimestamp, now - last <= doubleSpaceTimeout,
           committedTail.hasSuffix(" "),
           let beforeSpace = committedTail.dropLast().last,
           Self.isSentenceCharacter(beforeSpace) {
            output.deleteBackward(1)
            output.insertText(". ")
            committedTail.removeLast()
            appendToTail(". ")
            lastSpaceTimestamp = nil
            return
        }

        commitComposition()
        notifyWordCommitted()
        output.insertText(" ")
        appendToTail(" ")  // 트리거에 공백이 들어간다 ("창세기 1장 1절")
        lastSpaceTimestamp = now
    }

    /// 더블스페이스 마침표가 어울리는 직전 문자 — 한글 음절·영숫자·닫는 문장부호.
    private static func isSentenceCharacter(_ character: Character) -> Bool {
        if let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1,
           (0xAC00...0xD7A3).contains(scalar.value) {
            return true
        }
        if character.isLetter || character.isNumber { return true }
        return ")\"'”’」』〉]".contains(character)
    }

    private func handleShift() {
        switch shift {
        case .off: shift = .once
        case .once:
            // 영어만 캡스락. 한글에서 시프트 연타는 해제로 동작한다.
            // 자동 대문자가 켠 once는 탭 한 번에 꺼진다 — 캡스락이 아니다 (Apple 동일)
            shift = (mode == .english && !isAutoShifted) ? .capsLock : .off
        case .capsLock: shift = .off
        }
        isAutoShifted = false
    }

    // MARK: - 조합 반영

    /// 오토마타 출력 → 문서 반영. **조합 교체의 유일한 구현 지점.**
    /// 조합 영역 = 오토마타 조합 글자 + 자판의 pending 문자 (천지인 ㆍ).
    private func apply(_ result: AutomatonOutput) {
        if composingCount > 0 {
            output.deleteBackward(composingCount)
        }
        if result.deletesBackward {
            output.deleteBackward(1)
            // 확정됐던 글자가 문서에서 지워졌다 (도깨비불 역행) — 꼬리도 함께 걷는다
            if !committedTail.isEmpty { committedTail.removeLast() }
        }
        let composing = result.composing + hangulSource.pendingText
        let text = result.committed + composing
        if !text.isEmpty {
            output.insertText(text)
        }
        composingCount = composing.count
        runCommittedCount += result.committed.count
        appendToTail(result.committed)
    }

    /// 진행 중인 조합을 확정한다 (문서 텍스트는 그대로, 꼬리는 유지).
    /// 툴바 도구(이모지 패널 등)를 열 때 조립 지점이 호출한다 — 천지인 규칙
    /// "툴바 도구 사용 시 반드시 리셋"의 공개 진입점 (리뷰 반영).
    public func commitComposition() {
        // 조합 글자(pending 포함)는 이미 문서에 들어가 있다 — 상태만 확정으로 바꾼다.
        // pending 점은 그대로 리터럴로 남는다 (PDR 결정).
        appendToTail(automaton.composingText + hangulSource.pendingText)
        keystrokeLog.removeAll()
        runCommittedCount = 0
        keystrokeLogOverflowed = false
        composingCount = 0
        if automaton.isComposing {
            _ = automaton.commit()
        }
        hangulSource.reset()
    }

    // MARK: - 채움글

    /// 채움글 삽입 — 트리거를 지우고 전문을 넣는다. `deleteBackward` + `insertText`만 쓰므로
    /// Full Access가 필요 없다. 매칭에 쓴 꼬리(`textTail`)와 문서 상태가 같아야 한다 —
    /// 키 입력 직후 조립 지점이 매칭·표시하므로 탭 시점에도 그대로다.
    public func insertSnippet(_ suggestion: SnippetSuggestion) {
        lastSpaceTimestamp = nil
        commitComposition()  // 조합 확정 + 소스 리셋 (기존 규칙) — 문서 텍스트는 안 변한다
        output.deleteBackward(suggestion.triggerLength)
        let inserted = suggestion.insertedText  // 머리말("[창세기 1:1] ") + 본문
        output.insertText(inserted)

        committedTail.removeLast(min(suggestion.triggerLength, committedTail.count))
        // 본문 마지막 줄만 꼬리에 남긴다 — 트리거는 줄을 넘지 않는다는 규칙과 일치
        let lastLine = inserted.split(
            separator: "\n", omittingEmptySubsequences: false).last
        appendToTail(String(lastLine ?? ""))
        // 본문 끝 한글 run은 사용자가 타이핑한 단어가 아니다 — 학습으로 보내지 않는다
        suppressesNextWordCommit = true
        updateAutoCapitalization()
    }

    // MARK: - 추천단어

    /// 입력 중인 단어를 후보로 바꾼다 — 채움글과 같은 delete/insert 메커니즘.
    /// 후행 공백은 넣지 않는다 (교착어 — 조사·어미를 이어 치는 흐름, PDR word-suggestions).
    public func completeWord(_ word: String) {
        lastSpaceTimestamp = nil
        commitComposition()  // 조합 확정 + 소스 리셋 — 문서 텍스트는 안 변한다
        let current = Self.trailingHangulRun(of: committedTail)
        guard !current.isEmpty, !word.isEmpty else { return }
        output.deleteBackward(current.count)
        output.insertText(word)
        committedTail.removeLast(min(current.count, committedTail.count))
        appendToTail(word)
        onWordCommitted?(word)
        // 여기서 이미 알렸다 — 이어지는 공백/리턴이 같은 단어를 또 보내면 이중 카운트다
        suppressesNextWordCommit = true
        updateAutoCapitalization()
    }

    /// 외부에서 온 텍스트(인증번호 붙여넣기 등)를 그대로 삽입한다.
    /// 조합은 확정되고, 삽입분은 학습 대상이 아니다.
    public func insertProvidedText(_ text: String) {
        guard !text.isEmpty else { return }
        lastSpaceTimestamp = nil
        commitComposition()
        output.insertText(text)
        appendToTail(text)
        suppressesNextWordCommit = true
        blocksLearningUntilSeparator = true
        updateAutoCapitalization()
    }

    // MARK: - 자동 대문자 (PDR auto-capitalization)

    /// 텍스트가 바뀐 뒤마다 호출된다. 영어 모드에서 꼬리가 문장/단어 시작이면 시프트를 자동으로
    /// 켜고(`isAutoShifted`), 자동으로 켠 시프트가 더는 맞지 않으면 끈다. 사용자가 켠 시프트와
    /// 캡스락은 건드리지 않는다. 한글 모드는 대상이 아니다 (한글 시프트 = 쌍자음).
    private func updateAutoCapitalization() {
        if shift != .once { isAutoShifted = false }
        guard mode == .english, shift != .capsLock else { return }
        let wantsCapital = Self.wantsCapital(after: committedTail, rule: autoCapitalization)
        if wantsCapital, shift == .off {
            shift = .once
            isAutoShifted = true
        } else if !wantsCapital, shift == .once, isAutoShifted {
            shift = .off
            isAutoShifted = false
        }
    }

    /// 꼬리(커서 앞 텍스트, 줄 단위) 기준 판정. 꼬리가 비면 문서·줄 시작이다.
    static func wantsCapital(after tail: String, rule: AutoCapitalization) -> Bool {
        switch rule {
        case .none:
            return false
        case .allCharacters:
            return true
        case .words:
            return tail.last?.isWhitespace ?? true
        case .sentences:
            guard let last = tail.last else { return true }
            // 마침표 바로 뒤(공백 없음)는 아니다 — "e.g" 같은 입력을 대문자로 만들지 않는다
            guard last.isWhitespace else { return false }
            var body = Substring(tail)
            while let character = body.last, character.isWhitespace { body.removeLast() }
            // 닫는 따옴표·괄호는 문장 부호 뒤에 올 수 있다 — 건너뛴다
            while let character = body.last, Self.closingPunctuation.contains(character) { body.removeLast() }
            guard let terminator = body.last else { return true }  // 공백만 있었다 — 문서 시작
            return Self.sentenceTerminators.contains(terminator)
        }
    }

    private static let sentenceTerminators: Set<Character> = [".", "!", "?", "…", "。", "！", "？"]
    private static let closingPunctuation: Set<Character> = [")", "\"", "'", "”", "’", "」", "』", "〉", "]"]

    private func notifyWordCommitted() {
        // 공백/리턴 = 경계 통과. 외부 텍스트에 이어 친 run은 여기서 한 번 걸러지고 끝난다
        let blocked = blocksLearningUntilSeparator
        blocksLearningUntilSeparator = false
        guard !suppressesNextWordCommit, !blocked, let onWordCommitted else { return }
        let word = Self.trailingHangulRun(of: committedTail)
        if word.count >= 2 {
            onWordCommitted(word)
        }
    }

    /// 꼬리 끝의 한글 단어 run. 음절 연속이며, **맨 끝의 단독 자음 1개는 포함한다** —
    /// "안녕ㅎ"(초성만 조합 중)에서도 후보가 이어져야 음절 시작마다 툴바가 깜빡이지 않는다.
    private static func trailingHangulRun(of text: String) -> String {
        var word = ""
        var isLastCharacter = true
        for character in text.reversed() {
            guard let scalar = character.unicodeScalars.first,
                  character.unicodeScalars.count == 1 else { break }
            let isSyllable = (0xAC00...0xD7A3).contains(scalar.value)
            let isConsonantJamo = (0x3131...0x314E).contains(scalar.value)
            if isSyllable || (isLastCharacter && isConsonantJamo) {
                word.insert(character, at: word.startIndex)
            } else {
                break
            }
            isLastCharacter = false
        }
        return word
    }

    private func appendToTail(_ text: String) {
        guard !text.isEmpty else { return }
        committedTail += text
        if committedTail.count > committedTailLimit {
            committedTail.removeFirst(committedTail.count - committedTailLimit)
        }
    }
}
