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
    /// 기호 자판에 들어오기 직전의 문자 모드 — 기호에서 나갈 때 여기로 돌아간다.
    /// **읽기 전용 공개**(키패드 개정 2026-09-28): 조립 지점이 키패드 문자 복귀 키 라벨(「가」/「ABC」)을
    /// 여기서 정한다(`LayoutDefinition.layout(... letterMode:)`). 기호·키패드·숫자 패드에 있을 때만 뜻이 있다
    public private(set) var letterMode: InputMode = .hangul

    /// 문서 쓰기는 전부 이 계수기를 지난다 — `documentRevision`(D17)
    private let revisionCounter: RevisionCountingOutput
    private var output: TextOutput { revisionCounter }
    /// 마지막 이모지 칩 삽입 직후의 `documentRevision` — 그 뒤 문서가 안 바뀐 채 온 이모지 칩 탭은 퇴장 중 더블탭이다
    /// (`replaceCurrentWord`의 둘째 층). 값은 정수뿐이다 — 넣은 글자는 기억하지 않는다
    private var revisionAfterEmojiChip: Int?
    /// 마지막 채움글 삽입 직후의 `documentRevision` — 문서가 그대로인 동안 채움글 칩·삽입을 보류한다(K1, `ReplacementGate.holdsSnippets`).
    /// 정수뿐이다 — 넣은 본문은 기억하지 않는다
    private var revisionAfterSnippetInsertion: Int?
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

    /// 채움글 단축어 매칭용 확정 텍스트 꼬리. 문서가 아니라 이 파이프라인이 직접 추적한다 —
    /// 300자 문맥 제한·호스트별 프록시 편차와 무관해진다 (PDR snippet-autocomplete).
    /// 메모리에만 있고 48자 상한. 로그·파일·네트워크로 내보내지 않는다 (보안 규칙).
    private var committedTail = ""
    private let committedTailLimit = 48
    /// `committedTail`의 **앞이 잘렸나**(48자 상한으로 줄 중간에서 시작하나) — 채움글 단어 경계가 꼬리 맨 앞 글자의 앞을 모르는 경우다.
    /// 앞을 버릴 때와 빈 꼬리에서 ⌫가 추적하지 않은 앞 글자를 지울 때(`deleteCommittedCharacter`) 참이 되고,
    /// 새 줄(리턴·여러 줄 본문 삽입)이나 문맥을 모르는 sync(nil)에서 거짓이 된다. 문맥이 있는 sync는 문서로 다시 적는다. 내용은 담지 않는다.
    private var committedTailIsTruncated = false
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
    /// 숫자·기호 자판 모양 — 「123」이 어느 자판으로 들어갈지만 정한다. 조립 지점이 설정으로 갱신한다
    /// (PDR `number-symbol-keypad.md` 4-2절). 네 자판의 「123」 키는 그대로 `.symbols`를 낸다.
    public var symbolKeyboardStyle: SymbolKeyboardStyle = .qwerty
    /// 더블스페이스 인정 시간. 고정값 — 시스템 키보드 체감에 맞췄다.
    private let doubleSpaceTimeout: TimeInterval = 0.35
    /// 마지막 키가 스페이스였을 때 그 시각. 다른 입력이 끼면 nil.
    private var lastSpaceTimestamp: TimeInterval?

    /// 연타 키(`KeyEvent.multiTap` — 키패드 숫자 페이지의 `.,*/`·`-+`) 인정 시간. **설정이 아닌 상수**다 —
    /// 천지인 연타 기본값(`KeyboardSettings.cheonjiinTimeout` 0.8초)과 같은 감각으로 맞췄다. 천지인 설정을 따라가게
    /// 묶지 않은 이유: 그 슬라이더는 천지인일 때만 보이고, 이 키는 자판 종류와 무관하게 키패드형에만 있다.
    private let multiTapTimeout: TimeInterval = 0.8
    /// 진행 중인 연타 — 그 키의 글자 목록, **지금 문서에 들어가 있는 글자**의 순번, 마지막 탭 시각.
    /// 끊기는 조건: 시간 초과 · 다른 이벤트 · 조합 확정 경로(툴바 도구·후보·붙여넣기) · 모드/입력란 변경 ·
    /// sync(단, **메아리**는 봐준다 — `syncWithDocument` 주석). 끊긴 뒤에는 첫 글자부터 새로 넣는다.
    private var multiTapState: (characters: [String], index: Int, time: TimeInterval)?

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
        self.revisionCounter = RevisionCountingOutput(base: output)
        self.hangulSource = hangulSource
        self.mode = startsInHangul ? .hangul : .english
        self.clock = clock
    }

    /// 이 컨트롤러가 문서에 글자를 넣거나 지운 횟수 — 조립 지점이 입력 하나 앞뒤로 비교해 **문서 글자가 실제로
    /// 바뀌었는가**를 안다(이모지 칩 탭 뒤 숨김 해제, PDR emoji-word-suggestion D17). ⇧·한영·123·페이지 전환·천지인
    /// 이동처럼 문서를 안 바꾸는 키는 세지 않는다 — 키 종류 목록이 아니라 실제 쓰기를 세므로 새 키가 생겨도 맞다.
    /// 호스트가 바꾼 문서(sync)는 세지 않는다(우리 쓰기가 아니다).
    public var documentRevision: Int { revisionCounter.revision }

    /// K1 — 채움글을 넣은 뒤 아직 문서가 안 바뀌었나(다음 사용자 편집 전). 참이면 채움글 칩·U7·성경 배지를 띄우지 않고
    /// `insertSnippet`도 거절한다 — 조립 지점의 표시와 이 거절이 같은 식(`ReplacementGate`)이다
    public var holdsSnippetsAfterInsertion: Bool {
        ReplacementGate.holdsSnippets(revisionAfterSnippetInsertion: revisionAfterSnippetInsertion, documentRevision: documentRevision)
    }

    /// K4 — 호스트 문서에 선택 영역이 있나(유무만). 조립 지점이 후보 표시를 가를 때도 이 값을 쓴다
    public var hasSelectedText: Bool { output.hasSelectedText }

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

    /// `textTail`의 앞이 잘렸나 — 참이면 꼬리 맨 앞 글자의 앞을 모른다. 조립 지점이 채움글 매처(칩·U7 목록)에 같은 값을 넘긴다
    /// (단어 경계, PDR `snippet-shortcut-terms.md` 7절).
    ///
    /// ★ **문맥을 모르는 경우(sync(nil) — 빈 입력란·커서 도구 이동)는 잘림으로 보지 않는다.** 빈 입력란에서
    /// `documentContextBeforeInput`이 nil로 와 같은 길을 타므로, 잘림으로 보면 입력란 첫 단축어(「주소」만 친 경우)가 막힌다.
    /// 커서 도구 이동 뒤에는 호스트가 곧 textDidChange로 실제 꼬리를 다시 세운다.
    /// ★ 반대로 **꼬리를 다 지운 뒤에도 참이 남고**(검증 ⓛ2), 빈 꼬리에서 ⌫가 앞 글자(줄바꿈 등)를 지우면 참이 된다(검증 ⓜ1) —
    /// 둘 다 앞 글자를 모르는 경우라 칩을 띄우지 않는 쪽이다. 「꼬리가 비면 잘림 아님」으로 줄이지 않는다.
    public var textTailIsTruncated: Bool { committedTailIsTruncated }

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
        commitComposition()   // 연타도 여기서 끊긴다
        hangulSource = source
    }

    // MARK: - 입력란 특성 (PDR field-traits-and-live-settings)

    /// 숫자 전용 입력란 진입/이탈. `kind`가 있으면 숫자 패드 모드로, nil이면 들어오기 전
    /// 문자 모드로 돌아간다 (이미 문자 모드면 그대로). 조합은 확정된다.
    public func setNumberPad(_ kind: NumberPadKind?) {
        multiTapState = nil
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
        multiTapState = nil   // 입력란 특성이 바뀌었다 — 다른 입력란이다
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
        // 연타 키가 아닌 모든 이벤트는 연타를 끊는다(모드 전환·페이지 넘김·⌫ 포함)
        if case .multiTap = event {} else { multiTapState = nil }
        switch event {
        case .character(let key): handleCharacter(key)
        case .backspace: handleBackspace()
        case .space: handleSpace()
        case .return:
            commitComposition()
            notifyWordCommitted()
            output.insertText("\n")
            // 단축어는 줄을 넘지 않는다 — 꼬리를 새 줄에서 다시 시작한다
            committedTail.removeAll()
            committedTailIsTruncated = false
        case .shift: handleShift()
        case .toggleLanguage:
            commitComposition()
            mode = (mode == .hangul) ? .english : .hangul
            shift = .off
        case .symbols:
            commitComposition()
            // ★ 키패드형도 복귀 조건에 넣는다 — `isSymbols`(쿼티형 두 페이지)만 보면 키패드의 「ABC」가
            //   else로 빠져 **키패드를 `letterMode`에 적고 쿼티형 기호로** 가 버린다(반론자1 급소⑥-2).
            //   `isSymbols`의 뜻은 넓히지 않는다 — 쿼티형 경로도 그 술어를 지난다.
            if mode.isSymbols || mode.isKeypadPad {
                // 기호 자판(어느 페이지든)에서 누르면 들어오기 전 문자 모드로 돌아간다
                mode = letterMode
            } else {
                letterMode = mode
                // 들어갈 모드만 설정으로 고른다 — 조합 확정·천지인 리셋은 위 `commitComposition()` 한 곳이 맡는다
                mode = symbolKeyboardStyle == .keypad ? .keypadPad(page: 0) : .symbols
            }
            shift = .off
        case .symbolsAlternate:
            commitComposition()
            // 123 ↔ #+= 페이지 전환 — 문자 모드에서는 무의미하므로 무시
            if mode.isSymbols {
                mode = (mode == .symbolsAlternate) ? .symbols : .symbolsAlternate
            }
        case .keypadPageNext, .keypadPagePrevious:
            commitComposition()
            // 키패드형 한 키 순환 — 탭 = 다음(마지막 → 처음), 길게 = 이전(처음 → 마지막). 다른 모드에서는 무시
            if case .keypadPad(let page) = mode {
                let count = LayoutDefinition.keypadPageCount
                let step = event == .keypadPageNext ? 1 : -1
                mode = .keypadPad(page: ((page + step) % count + count) % count)
            }
        case .advance:
            // 천지인 이동(→) — 공백 없이 조합만 확정한다 (실측 스펙)
            commitComposition()
        case .spacer:
            break  // 스페이서 — 배열 정렬용, 입력 없음
        case .multiTap(let characters):
            handleMultiTap(characters)
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
        // 연타는 **메아리만** 봐준다(사장님 결정 2026-09-28) — 연타 두 번째부터는 ⌫ 1 + 삽입이라, 우리 ⌫에 반응해
        // textDidChange를 보내는 호스트(아래 주석)에서 끊으면 세 번째 탭이 새 「.」가 된다. 문서가 **방금 넣은 연타
        // 글자로 끝나면** 우리 편집의 메아리로 보고 이어 간다(조합 글자 메아리 규칙과 같은 모양). nil(커서 도구)이나
        // 다른 끝이면 끊는다. 알려진 부작용: 0.8초 안에 손으로 커서를 **같은 기호 바로 뒤**로 옮기면 그 기호가 바뀐다.
        let keptMultiTap = multiTapState.flatMap { state in
            documentTail?.hasSuffix(state.characters[state.index]) == true ? state : nil
        }
        defer { multiTapState = keptMultiTap }
        let composing = automaton.composingText + hangulSource.pendingText
        if let documentTail, !composing.isEmpty, documentTail.hasSuffix(composing) {
            // 문서 = 확정 + 우리 조합 그대로. 상태는 살리고 확정 꼬리만 문서 기준으로 보정한다
            (committedTail, committedTailIsTruncated) = Self.tailLine(of: String(documentTail.dropLast(composing.count)),
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
            (committedTail, committedTailIsTruncated) = Self.tailLine(of: documentTail, limit: committedTailLimit)
            // 커서 앞 단어는 이 키보드로 친 것이 아닐 수 있다 — 첫 구분자까지 학습 제외
            blocksLearningUntilSeparator = !Self.trailingHangulRun(of: committedTail).isEmpty
        } else {
            // 커서가 어디로 갔는지 모른다 — 추적해 온 꼬리도 문서와 어긋났으므로 버린다.
            // 잘림으로는 보지 않는다(`textTailIsTruncated` 주석 — 빈 입력란도 이 길이다)
            committedTail.removeAll()
            committedTailIsTruncated = false
            blocksLearningUntilSeparator = false
        }
        // 문맥을 모를 때는 시프트를 건드리지 않는다 — 커서 도구 이동 직후 nil sync가 오고 곧
        // textDidChange가 실제 꼬리를 가져오므로, 여기서 판정하면 시프트 키가 깜빡인다
        if documentTail != nil { updateAutoCapitalization() }
    }

    /// 문서 꼬리에서 마지막 줄의 끝 `limit`자 — 단축어는 줄을 넘지 않는다는 규칙과 일치.
    /// `truncated`는 마지막 줄이 `limit`자를 넘어 앞을 버렸는가(채움글 단어 경계).
    private static func tailLine(of text: String, limit: Int) -> (tail: String, truncated: Bool) {
        let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last ?? ""
        return (String(lastLine.suffix(limit)), lastLine.count > limit)
    }

    // MARK: - 문자

    private func handleCharacter(_ key: String) {
        suppressesNextWordCommit = false
        switch mode {
        case .hangul: handleHangulKey(key)
        case .english: handleEnglishKey(key)
        case .symbols, .symbolsAlternate, .numberPad, .keypadPad:
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
            // 기호/영어 모드도 꼬리를 함께 걷는다 — 단축어의 숫자·콜론이 이 모드에서
            // 지워지므로, 빠뜨리면 문서에 없는 텍스트로 칩이 뜨고 탭 시 문서를 파괴한다
            deleteCommittedCharacter()
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
            deleteCommittedCharacter()
        }
    }

    /// ⌫로 확정된 글자 하나를 지우고 꼬리도 함께 걷는다.
    ///
    /// ★ **꼬리가 이미 비어 있으면** 지운 것은 추적하지 않은 앞 글자(줄바꿈·앞 줄·48자 밖)다 — 이제 커서 앞 글자를 모르므로
    /// 잘림으로 적는다(채움글 단어 경계는 꼬리 맨 앞을 경계로 보지 않는다). 「서울」⏎⌫ 뒤 「주소」가 문서로는 「서울주소」인데
    /// 줄 처음으로 오판해 칩이 뜨던 경로다(검증 ⓜ1, 사장님 결정 2026-10-08). 다음 sync(textDidChange·등장)가 문서 문맥으로
    /// 바로잡는다 — 메아리를 보내는 호스트에선 바로 풀린다. 빈 입력란의 ⌫(지울 게 없음)도 여기서는 구별할 수 없어 같은 길이다.
    /// 꼬리를 다 지운 뒤에도 잘림이 남는 것(검증 ⓛ2)과 같은 쪽 — 모를 때는 칩을 띄우지 않는다.
    private func deleteCommittedCharacter() {
        output.deleteBackward(1)
        if committedTail.isEmpty {
            committedTailIsTruncated = true
        } else {
            committedTail.removeLast()
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

    /// 연타 키 — 첫 탭은 첫 글자를 넣고, 제한 시간 안에 **같은 키**를 다시 누르면 방금 넣은 글자를 다음 글자로
    /// 바꾼다(`. → , → - → / → .`). 교체는 더블스페이스 마침표와 같은 모양 — ⌫ 1 + 삽입, 꼬리도 마지막 글자를
    /// 같이 바꿔 **문서와 어긋나지 않는다**. 꼬리가 그 글자로 끝나지 않으면(어긋났으면) 교체하지 않고 새로 넣는다.
    private func handleMultiTap(_ characters: [String]) {
        guard let first = characters.first else { return }
        suppressesNextWordCommit = false
        let now = clock()
        if let state = multiTapState, state.characters == characters, now - state.time <= multiTapTimeout,
           committedTail.hasSuffix(state.characters[state.index]) {
            let current = state.characters[state.index]
            let nextIndex = (state.index + 1) % characters.count
            let next = characters[nextIndex]
            output.deleteBackward(current.count)
            output.insertText(next)
            committedTail.removeLast(min(current.count, committedTail.count))
            appendToTail(next)
            multiTapState = (characters, nextIndex, now)
            return
        }
        commitComposition()   // 연타 상태도 여기서 비워진다 — 새 상태는 아래에서 선다
        output.insertText(first)
        appendToTail(first)
        multiTapState = (characters, 0, now)
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
        appendToTail(" ")  // 단축어에 공백이 들어간다 ("창세기 1장 1절")
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
        // 툴바 도구·후보·붙여넣기가 여기를 지난다 — 그 사이에 문서가 바뀌므로 연타도 끊는다
        multiTapState = nil
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

    /// 채움글 삽입 — 단축어를 지우고 전문을 넣는다. `deleteBackward` + `insertText`만 쓰므로
    /// Full Access가 필요 없다. 매칭에 쓴 꼬리(`textTail`)와 문서 상태가 같아야 한다 —
    /// 키 입력 직후 조립 지점이 매칭·표시하므로 탭 시점에도 그대로다.
    ///
    /// **정합 검사(QA BLOCK-2).** 꼬리가 지금도 이 단축어로 끝날 때만 삽입한다. 검사가 없으면
    /// 같은 칩이 두 번 들어올 때(퇴장 애니메이션 0.28초 중 더블탭) 2회차가 방금 삽입한 본문 끝을
    /// `triggerLength`만큼 잘라냈다 — 절 범위(`창세기 1:1~13`)면 본문 1,444B가 다시 들어가고
    /// 앞의 10자가 사라진다. 어긋나면 **아무 것도 하지 않는다** (문서를 건드리는 쪽이 늘 더 나쁘다).
    ///
    /// **K1·K4(2026-10-08).** 꼬리 정합만으로는 본문이 자기 단축어로 끝날 때 2회차가 다시 통과한다 — 직전 채움글 삽입 뒤 문서가
    /// 그대로면 거절한다(`holdsSnippetsAfterInsertion`). 선택 영역이 있어도 거절한다(첫 `deleteBackward`가 선택 영역을 지운다).
    /// 거절은 조합 확정 **전**이다 — 문서도 조합 상태도 그대로 둔다.
    /// - Returns: 실제로 삽입했으면 true.
    @discardableResult
    public func insertSnippet(_ suggestion: SnippetSuggestion) -> Bool {
        guard !suggestion.trigger.isEmpty, textTail.hasSuffix(suggestion.trigger),
              ReplacementGate.allowsSnippetInsertion(isHeldAfterInsertion: holdsSnippetsAfterInsertion,
                                                     hasSelectedText: output.hasSelectedText)
        else { return false }
        lastSpaceTimestamp = nil
        commitComposition()  // 조합 확정 + 소스 리셋 (기존 규칙) — 문서 텍스트는 안 변한다
        output.deleteBackward(suggestion.triggerLength)
        // 머리말 + 본문. 머리말은 **사용자가 친 단축어 원문 그대로**다 — `창세기 1장 1절`을
        // 쳤으면 `[창세기 1장 1절] `이고 정규 표기로 바꾸지 않는다(2026-09-14,
        // PDR snippet-prefix-verbatim). 칩 제목만 정규 표기를 쓴다.
        let inserted = suggestion.insertedText
        output.insertText(inserted)

        committedTail.removeLast(min(suggestion.triggerLength, committedTail.count))
        // 본문 마지막 줄만 꼬리에 남긴다 — 단축어는 줄을 넘지 않는다는 규칙과 일치.
        // 본문에 줄바꿈이 있으면 문서의 마지막 줄은 본문 뒤쪽뿐이므로 **앞에 남아 있던 꼬리는
        // 버린다** — 남겨 두면 꼬리가 문서와 어긋나 다음 매칭이 엉뚱한 길이를 지운다
        // (절 범위·애국가처럼 여러 줄인 본문에서 드러난다, PDR bible-verse-range).
        if let newline = inserted.lastIndex(of: "\n") {
            committedTail.removeAll()
            committedTailIsTruncated = false   // 새 줄의 처음부터 — 본문 마지막 줄이 길면 아래 덧붙이기가 다시 잘림을 적는다
            appendToTail(String(inserted[inserted.index(after: newline)...]))
        } else {
            appendToTail(inserted)
        }
        // 본문 끝 한글 run은 사용자가 타이핑한 단어가 아니다 — 학습으로 보내지 않는다.
        // `suppressesNextWordCommit`은 다음 문자 입력에서 바로 풀리므로 한 글자만 이어 치면
        // "창조하시니라요"처럼 본문 조각이 학습 사전에 들어갔다 (QA N-2) — 붙여넣기와 같은
        // 규칙으로 **다음 구분자(공백·리턴)까지** 막는다 (`insertProvidedText`와 동일).
        suppressesNextWordCommit = true
        blocksLearningUntilSeparator = true
        // K1 — 이 삽입 뒤 문서가 바뀌기 전까지 다음 채움글을 보류한다(방금 넣은 글 끝에서 다시 맞은 구간)
        revisionAfterSnippetInsertion = documentRevision
        updateAutoCapitalization()
        return true
    }

    // MARK: - 추천단어

    /// 입력 중인 단어를 후보로 바꾼다 — 채움글과 같은 delete/insert 메커니즘.
    /// 후행 공백은 넣지 않는다 (교착어 — 조사·어미를 이어 치는 흐름, PDR word-suggestions).
    /// 선택 영역이 있으면 아무 것도 하지 않는다(K4 — 채움글과 같은 이유).
    /// - Returns: 실제로 바꿨으면 true.
    @discardableResult
    public func completeWord(_ word: String) -> Bool {
        guard ReplacementGate.allowsReplacement(hasSelectedText: output.hasSelectedText) else { return false }
        lastSpaceTimestamp = nil
        commitComposition()  // 조합 확정 + 소스 리셋 — 문서 텍스트는 안 변한다
        let current = Self.trailingHangulRun(of: committedTail)
        guard !current.isEmpty, !word.isEmpty else { return false }
        output.deleteBackward(current.count)
        output.insertText(word)
        committedTail.removeLast(min(current.count, committedTail.count))
        appendToTail(word)
        onWordCommitted?(word)
        // 여기서 이미 알렸다 — 이어지는 공백/리턴이 같은 단어를 또 보내면 이중 카운트다
        suppressesNextWordCommit = true
        updateAutoCapitalization()
        return true
    }

    /// 이모지 칩 탭 — 치던 단어를 지우고 `text`(`🚗 자동차` 또는 `🚗`)를 넣는다(PDR emoji-word-suggestion 1-2·1-3절).
    ///
    /// **정합 검사(채움글 칩과 같은 방어).** 꼬리 끝 한글 run이 **칩이 든 원본 단어와 같을 때만** 바꾼다 —
    /// 「큰자동차」에 「자동차」 칩이면 거절한다(세 글자만 지우면 「큰🚗 자동차」가 된다). **직전 문서 변경이 이모지 칩
    /// 삽입이면** 거절한다 — 혼합 칩 퇴장 중 더블탭(넣은 「자동차」가 다시 꼬리 끝 run이라 위 검사를 통과한다).
    /// 예전 「꼬리가 이미 `text`로 끝나면 거절」은 손으로 쳐 둔 「🚕 자동차」에 같은 🚕가 뽑힌 칩까지 죽였다
    /// (검증 ⑤-2b 참고 2) — 그때는 사용자가 누른 그대로 「🚕 🚕 자동차」가 맞다.
    /// 어긋나면 **아무 것도 하지 않는다.** 첫 층 방어는 조립 지점의 「지금 떠 있는 칩만」과 탭 뒤 숨김이다.
    ///
    /// **학습으로 보내지 않는다**(5-3절, 수용 기준 4) — `completeWord`와 달리 `onWordCommitted`를 부르지 않는다.
    /// 이모지가 섞인 삽입분은 사용자가 친 단어가 아니다. 다음 구분자가 넣은 「자동차」를 다시 보내지 않게
    /// `suppressesNextWordCommit`을 켜고, 이어 치면 풀려 「자동차는」처럼 사용자가 완성한 run은 학습된다.
    /// 선택 영역이 있으면 거절한다(K4 — `ReplacementGate.allowsReplacement`).
    /// - Returns: 실제로 바꿨으면 true.
    @discardableResult
    public func replaceCurrentWord(_ sourceWord: String, with text: String) -> Bool {
        guard !sourceWord.isEmpty, !text.isEmpty, currentWord == sourceWord,
              revisionAfterEmojiChip != documentRevision,
              ReplacementGate.allowsReplacement(hasSelectedText: output.hasSelectedText)
        else { return false }
        lastSpaceTimestamp = nil
        commitComposition()  // 조합 확정 + 소스 리셋 — 문서 텍스트는 안 변한다
        output.deleteBackward(sourceWord.count)
        output.insertText(text)
        committedTail.removeLast(min(sourceWord.count, committedTail.count))
        appendToTail(text)
        suppressesNextWordCommit = true
        revisionAfterEmojiChip = documentRevision
        updateAutoCapitalization()
        return true
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
            committedTailIsTruncated = true   // 앞을 버렸다 — 이제 꼬리 맨 앞은 줄 중간이다
        }
    }
}

/// 문서 쓰기를 그대로 넘기면서 실제로 글자를 넣거나 지운 횟수만 센다 — `InputController.documentRevision`.
/// 빈 삽입·0개 지우기는 넘기되 세지 않는다(문서가 안 바뀐다). 내용은 기억하지 않는다(보안 규칙).
@MainActor
private final class RevisionCountingOutput: TextOutput {
    private let base: TextOutput
    private(set) var revision = 0

    init(base: TextOutput) {
        self.base = base
    }

    func insertText(_ text: String) {
        if !text.isEmpty { revision += 1 }
        base.insertText(text)
    }

    func deleteBackward(_ count: Int) {
        if count > 0 { revision += 1 }
        base.deleteBackward(count)
    }

    var hasSelectedText: Bool { base.hasSelectedText }
}
