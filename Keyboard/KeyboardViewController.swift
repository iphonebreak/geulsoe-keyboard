import UIKit
import SwiftUI
import AVFoundation
import HangulEngine
import KeyboardCore
import KeyboardUI
import TadakDomain
import TadakData

/// 키보드 익스텐션 진입점이자 **조립 지점** — TadakData 구현을 도메인 프로토콜에
/// 주입하는 유일한 곳이다. Core/UI는 TadakData를 모른다.
final class KeyboardViewController: UIInputViewController {

    private var hostingController: UIHostingController<KeyboardRootView>?
    private var heightConstraint: NSLayoutConstraint?

    private let settingsRepository: SettingsRepository = AppGroupSettingsRepository()
    private let themeRepository: ThemeRepository = BundledThemeRepository()
    private let bibleRepository: BibleVerseRepository = BundledBibleRepository()
    private let bundledSnippetRepository: SnippetRepository = BundledSnippetRepository()
    private let greetingsSnippetRepository: SnippetRepository = BundledSnippetRepository(resourceName: "Greetings")
    private let userSnippetRepository: SnippetRepository = AppGroupSnippetRepository()

    private var settings: KeyboardSettings = .default
    private var inputController: InputController?
    private var viewState: KeyboardViewState?
    private var snippetMatcher: SnippetMatcher?
    /// 추천단어 엔진. 익스텐션 프로세스 수명 동안 유지한다 — 매 등장마다 다시 만들면
    /// Full Access 없는 기기의 세션 학습이 필드 전환마다 날아간다.
    private var suggestionEngine: SuggestionEngine?
    /// 엔진을 만들 때의 학습 초기화 토큰. 설정 앱이 토큰을 올리면 엔진을 재생성해
    /// 세션 메모리째 버린다 (저장소만 비우면 다음 학습이 옛 단어를 되살린다).
    private var appliedLearningResetToken: Int?
    /// 클립보드에서 추출한 인증번호 — 툴바 칩에 값 그대로 표시된다 (사용자 결정, PDR 개정).
    private var pasteboardCode: String?
    /// 프로브한 클립보드의 changeCount — 탭 시 **이 값**을 소비로 기록한다
    /// (탭 시점 값을 쓰면 프로브 후 새로 복사된 내용까지 소비돼 버린다 — 리뷰 반영).
    private var probedPasteboardChangeCount: Int?
    /// 칩을 탭해 소비한 클립보드 changeCount — 같은 내용을 다시 제안하지 않는다.
    private var consumedPasteboardChangeCount: Int?
    /// 클립보드 기록 — 키보드가 쓰는 App Group 데이터 (FA 필요, PDR clipboard-history).
    /// 메모리에 들고 있지 않고 필요할 때 읽는다 — 설정 앱이 끄기/지우기로 비운 것을 놓치지 않게.
    private let clipboardHistoryRepository: ClipboardHistoryRepository = AppGroupClipboardHistoryRepository()
    /// 기록에 넣은 마지막 클립보드 changeCount — 등장마다 읽어도 같은 복사를 두 번 읽지 않는다.
    private var recordedPasteboardChangeCount: Int?

    override func viewDidLoad() {
        super.viewDidLoad()
        // 클릭음 요건: inputView가 UIInputViewAudioFeedback을 채택해야 playInputClick이 난다
        // (Apple 문서). 서브뷰를 얹기 전에 루트 뷰를 교체한다.
        inputView = ClickableInputView(frame: .zero, inputViewStyle: .keyboard)
        settings = settingsRepository.load()

        let controller = InputController(
            output: ProxyTextOutput(controller: self),
            hangulSource: Self.makeHangulSource(for: settings),
            startsInHangul: true
        )
        controller.doubleSpacePeriod = settings.doubleSpacePeriod
        inputController = controller

        let state = KeyboardViewState(
            layout: .layout(for: controller.mode, hangulLayout: settings.activeHangulLayout,
                            numberRow: settings.numberRowEnabled,
                            inputModeSwitchKey: needsInputModeSwitchKey,
                            longPressSymbols: settings.longPressSymbolsEnabled),
            themeSpec: themeRepository.theme(id: settings.selectedThemeID),
            appearance: settings.appearance,
            keyboardHeight: keyboardAreaHeight,
            showsKeyPreview: settings.showsKeyPreview,
            needsInputModeSwitchKey: needsInputModeSwitchKey,
            clipboardHistoryEnabled: settings.clipboardHistoryEnabled
        )
        viewState = state
        rebuildSnippetMatcher()
        rebuildSuggestionEngineIfNeeded()
        // 학습 연결 — secure 필드는 학습에서 뺀다 (보안 규칙)
        controller.onWordCommitted = { [weak self] word in
            guard let self, self.textDocumentProxy.isSecureTextEntry != true else { return }
            // iPad 병렬 사용(Split View 등)에서는 키보드가 떠 있는 채로 설정 앱이 학습을
            // 초기화할 수 있다 — viewWillAppear가 안 와서 토큰 변화를 모르는 상태로 learn이
            // 저장하면 세션 메모리의 옛 단어가 비워진 저장소를 도로 채운다. 저장이 일어나는
            // 유일한 지점인 여기서만 토큰을 재확인한다 (단어 확정당 1회 — 핫패스 아님).
            let latestToken = self.settingsRepository.load().learningResetToken
            guard latestToken == self.appliedLearningResetToken else {
                self.rebuildSuggestionEngine(token: latestToken)  // 이번 단어는 버린다
                return
            }
            self.suggestionEngine?.learn(word: word)
        }
        installKeyboardView(state: state)
        applyBackdropColor()
        // 높이 제약은 여기서 미리 건다 — viewWillAppear에서 처음 걸면 시스템 기본 높이로 한 번 뜬 뒤
        // 우리 높이로 바뀌어 등장할 때 깜빡인다 (실기 피드백 2026-09-04). viewWillAppear는 값만 갱신한다
        updateHeight()
        // 설정 앱이 값을 저장하면 Darwin 알림이 온다 — 키보드가 떠 있는 채로 즉시 반영
        // (PDR field-traits-and-live-settings). 값은 App Group에서 다시 읽는다 (FA 불필요).
        settingsChangeObserver = SettingsChangeObserver { [weak self] in
            DispatchQueue.main.async { self?.scheduleLiveSettingsReload() }
        }
    }

    /// 지구본 필요 여부는 레이아웃 시점에 확정된다 (Apple 문서 — `viewWillLayoutSubviews`에서 읽으라).
    /// viewDidLoad·viewWillAppear에서 읽은 값이 stale하면 첫 프레임 뒤 하단 행이 다시 흘러 깜빡인다
    /// (실기 피드백 2026-09-04) — 첫 레이아웃 패스(첫 프레임 전)에서 맞춰 넣고, 이후에도 바뀌면 따라간다.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let needs = needsInputModeSwitchKey
        if let viewState, viewState.needsInputModeSwitchKey != needs {
            viewState.needsInputModeSwitchKey = needs
            refreshLayout()
        }
        applyBackdropColor()  // 다크/라이트 트레이트는 여기서 확정된다 (키 캐시로 매 레이아웃 비용 없음)
    }

    // MARK: - 등장 첫 프레임 배경 (실기 피드백 2026-09-04, pure-dark 테마)

    /// SwiftUI 루트가 테마 배경을 그리기 전 프레임에는 시스템 키보드 블러(라이트 호스트에선 밝은 회색)나
    /// 투명 호스팅 뷰가 보여, 어두운 테마에서 키보드가 뜰 때마다 밝게 번쩍였다. UIKit 배경을 같은 테마 색으로
    /// 미리 칠해 어느 프레임에도 밝은 면이 없게 한다. 팔레트 선택 규칙은 `ResolvedTheme`과 같다.
    private var appliedBackdropKey: String?

    private func applyBackdropColor() {
        let style = traitCollection.userInterfaceStyle
        let key = "\(settings.selectedThemeID)/\(settings.appearance)/\(style.rawValue)"
        guard key != appliedBackdropKey else { return }
        appliedBackdropKey = key
        let spec = viewState?.themeSpec ?? themeRepository.theme(id: settings.selectedThemeID)
        let theme = ResolvedTheme(spec: spec, appearance: settings.appearance,
                                  systemColorScheme: style == .dark ? .dark : .light)
        let color = UIColor(theme.keyboardBackground)
        view.backgroundColor = color
        hostingController?.view.backgroundColor = color
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadSettingsIfChanged()
        // 설정이 그대로여도 사용자 문구는 설정 앱에서 바뀌었을 수 있다 — 항상 다시 만든다
        rebuildSnippetMatcher()
        rebuildSuggestionEngineIfNeeded()
        // needsInputModeSwitchKey는 viewDidLoad 시점엔 미확정일 수 있다
        viewState?.needsInputModeSwitchKey = needsInputModeSwitchKey
        updateHeight()
        // 키보드가 내려갔다 다시 뜨는 사이 앱이 텍스트를 바꿨을 수 있다 —
        // 이전 세션의 꼬리·후보를 문서 기준으로 다시 세운다 (textDidChange가 안 오는 호스트 방어)
        inputController?.syncWithDocument(documentTail: documentTailForSync)
        // 입력란 특성(숫자 패드·리턴 라벨·ASCII 시작)은 등장마다 다시 적용한다
        applyFieldTraits(force: true)
        // 새 필드에서는 자판부터 (@Observable은 같은 값 대입도 통지하므로 가드)
        if viewState?.showsEmojiPanel == true { viewState?.showsEmojiPanel = false }
        if viewState?.showsClipboardPanel == true { viewState?.showsClipboardPanel = false }
        dismissedSuggestionWord = nil  // ✕ 억제는 그 표시 세션에서만 (채움글 칩은 예외 — 편집 전까지 유지)
        suppressesWordSuggestionsAfterCursorMove = false
        updateVisibleTools()
        updateSuggestionBar()
        probePasteboard()
        // 첫 진동·첫 클릭음이 지연·약화되지 않게 미리 준비한다 (Apple 권고)
        if settings.hapticEnabled, hasFullAccess { hapticGenerator.prepare() }
        prepareClickPlayerIfNeeded()
    }

    // MARK: - 입력란 특성 (PDR field-traits-and-live-settings)

    /// 마지막으로 적용한 `keyboardType·returnKeyType·autocapitalizationType` 서명 — 같은 앱 안에서 필드만 바뀌면
    /// viewWillAppear가 오지 않으므로 textDidChange에서 서명 변화로 감지한다.
    private var appliedFieldSignature: String?

    private func applyFieldTraits(force: Bool) {
        guard let inputController, let viewState else { return }
        let proxy = textDocumentProxy
        let keyboardType = proxy.keyboardType ?? .default
        let returnKeyType = proxy.returnKeyType ?? .default
        let autocapitalizationType = proxy.autocapitalizationType ?? .sentences
        let signature = "\(keyboardType.rawValue)/\(returnKeyType.rawValue)/\(autocapitalizationType.rawValue)"
        guard force || signature != appliedFieldSignature else { return }
        appliedFieldSignature = signature

        // 숫자 전용 입력란 → 숫자 패드 모드. 그 외 → 들어오기 전 문자 모드로 복귀
        let numberPad: NumberPadKind? = switch keyboardType {
        case .numberPad, .asciiCapableNumberPad: .plain
        case .decimalPad: .decimal
        case .phonePad: .phone
        default: nil
        }
        inputController.setNumberPad(numberPad)
        // 스페이스 오른쪽 문장부호 키 — 입력란 종류를 따른다 (PDR punctuation-key).
        // Safari 주소창은 `.webSearch`다
        fieldPunctuation = switch keyboardType {
        case .emailAddress: .email
        case .URL, .webSearch: .url
        case .twitter: .twitter
        default: .standard
        }
        // ASCII를 요구하는 입력란(이메일·URL·asciiCapable)은 영어로 시작 — 한영 전환은 자유
        switch keyboardType {
        case .asciiCapable, .emailAddress, .URL:
            inputController.setStartsInEnglish(true)
        default:
            break
        }

        // 자동 대문자 — 입력란 규칙(.sentences 기본, 이메일·URL·비밀번호는 .none)과 설정을 합친다
        // (PDR auto-capitalization). 시프트 변화는 아래 refreshLayout이 반영한다
        fieldAutoCapitalization = Self.autoCapitalization(for: autocapitalizationType)
        applyAutoCapitalizationPolicy()

        let returnKey = Self.returnKeyFace(for: returnKeyType)
        if viewState.returnKey != returnKey { viewState.returnKey = returnKey }
        refreshLayout()
    }

    /// 마지막으로 읽은 입력란의 자동 대문자 규칙. 설정이 바뀌어도 다시 합칠 수 있게 보관한다.
    private var fieldAutoCapitalization: AutoCapitalization = .sentences
    /// 마지막으로 읽은 입력란의 문장부호 키 내용 (`refreshLayout`이 배열에 넣는다)
    private var fieldPunctuation: PunctuationKeySpec = .standard

    /// 입력란 규칙 ∧ 설정 → 컨트롤러. 입력란이 거부하면(`.none`) 설정이 켜져 있어도 동작하지 않는다.
    private func applyAutoCapitalizationPolicy() {
        inputController?.autoCapitalization = settings.autoCapitalization ? fieldAutoCapitalization : .none
    }

    private static func autoCapitalization(for type: UITextAutocapitalizationType) -> AutoCapitalization {
        switch type {
        case .none: .none
        case .words: .words
        case .sentences: .sentences
        case .allCharacters: .allCharacters
        @unknown default: .sentences
        }
    }

    /// 리턴 키 표시 — `.done`은 ✓(사용자 요청 "체크 버튼"), 나머지는 Apple 한국어 키보드 관례의 텍스트
    private static func returnKeyFace(for type: UIReturnKeyType) -> ReturnKeyFace? {
        switch type {
        case .done: .done
        case .search, .google, .yahoo: .text("검색")
        case .go: .text("이동")
        case .send: .text("보내기")
        case .next: .text("다음")
        case .join: .text("연결")
        case .continue: .text("계속")
        case .route: .text("경로")
        case .emergencyCall: .text("긴급")
        case .default: nil
        @unknown default: nil
        }
    }

    /// 현재 모드·설정에 맞는 배열을 뷰에 반영한다 (바뀐 경우에만 통지)
    private func refreshLayout() {
        guard let inputController, let viewState else { return }
        let layout = LayoutDefinition.layout(
            for: inputController.mode, hangulLayout: settings.activeHangulLayout,
            numberRow: settings.numberRowEnabled,
            inputModeSwitchKey: viewState.needsInputModeSwitchKey,  // 지구본 불필요 시 하단 행 재배치
            punctuation: fieldPunctuation,                          // 입력란 종류별 문장부호 키
            longPressSymbols: settings.longPressSymbolsEnabled)     // 문자 키 길게 → 기호 (설정)
        if viewState.layout != layout { viewState.layout = layout }
        let shifted = inputController.shift != .off
        if viewState.isShifted != shifted { viewState.isShifted = shifted }
        let capsLocked = inputController.shift == .capsLock
        if viewState.isCapsLocked != capsLocked { viewState.isCapsLocked = capsLocked }
    }

    // MARK: - 설정 즉시 반영 (PDR field-traits-and-live-settings)

    private var settingsChangeObserver: SettingsChangeObserver?
    private var liveSettingsReloadTask: Task<Void, Never>?

    /// Darwin 알림 → 120ms 디바운스 → 설정 재적용. 슬라이더 드래그처럼 연속 저장을 한 번으로 합친다.
    private func scheduleLiveSettingsReload() {
        liveSettingsReloadTask?.cancel()
        liveSettingsReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            self?.applySettingsLive()
        }
    }

    private func applySettingsLive() {
        reloadSettingsIfChanged()
        rebuildSnippetMatcher()            // 내 문구 저장도 같은 알림을 쓴다
        rebuildSuggestionEngineIfNeeded()  // 학습 초기화 토큰
        updateHeight()
        refreshLayout()
        updateVisibleTools()
        updateSuggestionBar()
        if settings.hapticEnabled, hasFullAccess { hapticGenerator.prepare() }
        prepareClickPlayerIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 클립보드 파생 값의 체류 최소화 — 다음 등장에서 프로브·패널 열기가 다시 채운다 (리뷰 반영)
        pasteboardCode = nil
        viewState?.pasteboardCode = nil
        if viewState?.clipboardEntries.isEmpty == false { viewState?.clipboardEntries = [] }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        // 커서 이동·필드 전환 — 조합 상태를 문서와 맞춘다. 호스트에 따라 우리 백스페이스의
        // 메아리로도 오므로 꼬리는 문서 문맥에서 다시 세운다 (버리면 "…3절" 재입력이 안 잡힌다)
        inputController?.syncWithDocument(documentTail: documentTailForSync)
        // 같은 앱 안에서 필드가 바뀌면 여기로만 온다 — 입력란 특성 서명이 바뀐 경우만 적용
        applyFieldTraits(force: false)
        refreshLayout()  // sync가 자동 대문자 시프트를 바꿨을 수 있다 (바뀐 경우만 통지)
        updateSuggestionBar()
    }

    /// 커서 앞 문서 텍스트 — 꼬리 재구성용. secure 필드에서는 읽지 않는다 (추천·학습·기록
    /// 제외 규칙). 메모리에만 머물고 로그·파일·네트워크로 나가지 않는다 (보안 규칙).
    private var documentTailForSync: String? {
        guard textDocumentProxy.isSecureTextEntry != true else { return nil }
        return textDocumentProxy.documentContextBeforeInput
    }

    // MARK: - 이벤트

    private func handle(_ event: KeyEvent) {
        guard let inputController else { return }
        inputController.handle(event)
        // 드물게 바뀌는 상태만 뷰에 반영한다 (모드·시프트)
        refreshLayout()
        suppressesWordSuggestionsAfterCursorMove = false  // 다시 타이핑 — 추천 재개
        updateSuggestionBar(userEdited: true)
    }

    // MARK: - 채움글 · 추천단어

    /// 설정이 켜져 있을 때만 매처를 만든다. 사용자 문구 → 내장 팩 순서 = 우선순위.
    /// 끈 팩(`disabledSnippetPacks`)은 구성에서 뺀다.
    private func rebuildSnippetMatcher() {
        guard settings.snippetsEnabled else {
            snippetMatcher = nil
            return
        }
        let disabled = settings.disabledSnippetPacks
        var entries = userSnippetRepository.entries()
        if !disabled.contains(SnippetPack.anthem) {
            entries += bundledSnippetRepository.entries()
        }
        if !disabled.contains(SnippetPack.greetings) {
            entries += greetingsSnippetRepository.entries()
        }
        snippetMatcher = SnippetMatcher(
            bible: disabled.contains(SnippetPack.bible) ? nil : bibleRepository,
            entries: entries,
            biblePrefix: settings.bibleSnippetPrefixEnabled
        )
    }

    /// 켬/끔 또는 학습 초기화 토큰이 바뀔 때만 만들고 버린다 — 유지 이유는 프로퍼티 주석 참조.
    private func rebuildSuggestionEngineIfNeeded() {
        guard settings.suggestionsEnabled else {
            suggestionEngine = nil
            return
        }
        if suggestionEngine == nil || appliedLearningResetToken != settings.learningResetToken {
            rebuildSuggestionEngine(token: settings.learningResetToken)
        }
    }

    /// 엔진을 새로 만든다 — 세션 메모리는 버려지고 저장소에서 다시 로드한다.
    private func rebuildSuggestionEngine(token: Int) {
        suggestionEngine = SuggestionEngine(
            dictionary: BundledWordDictionary(),
            userWordRepository: AppGroupUserWordRepository()
        )
        appliedLearningResetToken = token
    }

    /// 툴바 후보 갱신 — 채움글 칩이 있으면 칩만, 없으면 추천단어 최대 3개. ✕로 내린 후보는 억제.
    /// - Parameter userEdited: 사용자가 키·후보 탭으로 텍스트를 바꿨는가. 참일 때만 추천단어 ✕ 억제의
    ///   해제 조건(접두 이탈)을 평가한다. 커서 이동·textDidChange 같은 sync 경로는 꼬리가 바뀌어도 억제를
    ///   유지한다 — ✕ 뒤 ◀로 커서를 옮기면 단어가 짧아져 억제가 풀리고 후보가 되살아나던 문제
    ///   (사용자 피드백 2026-09-04). 호스트의 textDidChange 메아리가 억제를 푸는 것도 막는다.
    ///   채움글 칩의 ✕도 같은 규칙 — 사용자 편집으로 꼬리가 바뀔 때만 해제(재표시·sync로는 유지).
    private func updateSuggestionBar(userEdited: Bool = false) {
        guard let viewState, let inputController else { return }
        // 비밀번호 필드에서는 매칭·표시·학습 모두 하지 않는다 (보안 규칙)
        let secure = textDocumentProxy.isSecureTextEntry == true

        let matched: SnippetSuggestion? = secure
            ? nil
            : snippetMatcher?.suggestion(forTail: inputController.textTail)
        // ✕로 내린 추천단어는 같은 단어를 이어 치는 동안(접두 유지) 다시 띄우지 않는다.
        // 해제 판정은 사용자 편집 때만 — 커서 이동으로 꼬리가 바뀐 것은 "이어 치기"가 아니다.
        let currentWord = inputController.currentWord
        if userEdited, let dismissedWord = dismissedSuggestionWord,
           currentWord.isEmpty || !currentWord.hasPrefix(dismissedWord) {
            dismissedSuggestionWord = nil
        }
        // ✕로 내린 채움글 칩은 사용자가 편집해 꼬리가 바뀌기 전까지 숨긴다 — 재표시·커서 이동·메아리로는
        // 되살아나지 않고, 지웠다 다시 치면(꼬리 변화) 다시 뜬다 (사용자 요청 2026-09-04)
        if userEdited, let dismissedTail = Self.dismissedSnippetTail, dismissedTail != inputController.textTail {
            Self.dismissedSnippetTail = nil
        }
        let snippet = (Self.dismissedSnippetTail == nil) ? matched : nil

        // 채움글 후보가 있으면 툴바는 채움글 칩만 보인다 — 추천단어("절대"·"저를")는 함께
        // 띄우지 않는다 (사용자 결정 2026-09-03: 트리거를 쳤을 땐 "붙여넣을지"만 묻는다).
        // 커서 이동(◀▶·트랙패드) 뒤에는 다음 키 입력까지 추천단어를 띄우지 않는다 — 커서가 단어
        // 중간에 있으면 후보 탭이 커서 앞만 바꿔 "안녕하세요요"처럼 뒤 글자가 남는다.
        var words: [String] = []
        if !secure, snippet == nil, dismissedSuggestionWord == nil,
           !suppressesWordSuggestionsAfterCursorMove, let suggestionEngine {
            words = suggestionEngine.suggestions(forWord: currentWord, limit: 3)
        }
        if viewState.snippetSuggestion != snippet { viewState.snippetSuggestion = snippet }
        if viewState.wordSuggestions != words { viewState.wordSuggestions = words }

        // 인증번호 칩 — 입력을 시작하면 내려간다 (애플과 같은 감각). secure 필드 제외.
        let chipCode = (!secure && inputController.textTail.isEmpty) ? pasteboardCode : nil
        if viewState.pasteboardCode != chipCode {
            viewState.pasteboardCode = chipCode
        }
    }

    /// ✕로 내린 추천단어 — 그 단어(접두)를 이어 치는 동안 억제되고, 단어가 끝나면 자동 해제
    /// (사용자 요청 2026-09-03). 키보드 재표시 시 초기화.
    private var dismissedSuggestionWord: String?
    /// ✕로 내린 채움글 칩의 꼬리 — **사용자 편집으로 꼬리가 바뀔 때만** 해제된다. 지우고 다시 치면
    /// 꼬리가 한 번 바뀌었다 돌아오므로 칩이 다시 뜬다(사용자 요청 2026-09-04: "6 지우고 다시 6 쳐도
    /// 칩이 나와야 한다"). 편집 없이 오는 변화 — 키보드 재표시·커서 이동·호스트 textDidChange 메아리 —
    /// 로는 다시 뜨지 않는다("✕ 누르면 없어지고 다시는 나오지 않도록"). 그래서 인스턴스가 아니라 타입에
    /// 둔다(등장마다 VC가 새로 만들어져도 유지). 세션 메모리만 — 저장하지 않는다 (사용자 입력 유래 값).
    private static var dismissedSnippetTail: String?
    /// 커서 도구(◀▶)·스페이스 트랙패드로 커서를 옮긴 뒤 참 — 다음 키 입력(또는 후보 탭·재표시)까지
    /// 추천단어를 띄우지 않는다. 커서 이동은 타이핑이 아니고, 단어 중간에서의 완성은 문서를 훼손한다.
    private var suppressesWordSuggestionsAfterCursorMove = false

    /// 툴바 ✕ — 지금 보이는 후보(칩·추천단어·인증번호)를 내리고 도구 행으로 돌아간다.
    private func handleDismissSuggestions() {
        playToolbarHaptic()
        guard let inputController, let viewState else { return }
        if viewState.snippetSuggestion != nil { Self.dismissedSnippetTail = inputController.textTail }
        if !viewState.wordSuggestions.isEmpty, !inputController.currentWord.isEmpty {
            dismissedSuggestionWord = inputController.currentWord
        }
        if viewState.pasteboardCode != nil {
            // 인증번호 칩은 이 클립보드를 소비 처리해 다시 제안하지 않는다
            consumedPasteboardChangeCount = probedPasteboardChangeCount
            pasteboardCode = nil
        }
        updateSuggestionBar()
    }

    private func handleSnippetTap(_ suggestion: SnippetSuggestion) {
        playToolbarHaptic()
        inputController?.insertSnippet(suggestion)
        refreshLayout()  // 삽입으로 꼬리가 바뀌면 자동 대문자 시프트가 바뀔 수 있다
        suppressesWordSuggestionsAfterCursorMove = false
        updateSuggestionBar(userEdited: true)
    }

    // MARK: - 클립보드 읽기 (PDR verification-code-paste · clipboard-history)

    /// 키보드 등장 시 1회 클립보드를 읽는다 — 인증번호 칩(값 그대로 표시, 사용자 결정
    /// 2026-09-01)과 클립보드 기록이 **같은 읽기를 공유**한다. 두 기능이 모두 꺼져 있거나,
    /// FA가 없거나, secure 필드거나, 이 changeCount를 이미 소비·기록했으면 읽지 않는다
    /// (최소 접근). 주기 폴링이 아니고, 읽은 내용은 칩 표시·삽입·App Group 기록 외로
    /// 나가지 않는다. iOS가 첫 회 붙여넣기 확인을 띄울 수 있으며 이는 수용된 트레이드오프다.
    /// (탭 시에만 읽는 이전 방식은 detectPatterns 콜백의 @MainActor 격리 상속 크래시
    /// 이력이 있다 — 지금은 전부 메인 스레드 동기 경로라 해당 문제 자체가 없다.)
    private func probePasteboard() {
        defer { updateSuggestionBar() }
        pasteboardCode = nil
        guard hasFullAccess, textDocumentProxy.isSecureTextEntry != true else { return }
        let pasteboard = UIPasteboard.general
        let changeCount = pasteboard.changeCount
        let needsCode = settings.verificationCodeSuggestionsEnabled
            && changeCount != consumedPasteboardChangeCount
        let needsHistory = settings.clipboardHistoryEnabled
            && changeCount != recordedPasteboardChangeCount
        // 알려진 한계: 다른 기기에서 복사 직후(Universal Clipboard)에는 이 동기 읽기가
        // 전송 완료까지 지연될 수 있다 — PDR 개정 섹션·실기 체크리스트 항목.
        guard needsCode || needsHistory, pasteboard.hasStrings,
              let text = pasteboard.string else { return }
        if needsCode {
            pasteboardCode = VerificationCodeDetector.extractCode(from: text)
            probedPasteboardChangeCount = changeCount
        }
        if needsHistory {
            recordClipboardHistory(text)
            recordedPasteboardChangeCount = changeCount
        }
    }

    /// 기록 갱신 — 실제로 바뀐 경우에만 App Group에 쓴다 (FA 없으면 쓰기가 조용히 실패하지만
    /// 클립보드 기능 자체가 FA 뒤에 있어 여기 도달하지 않는다). 유일한 기록 쓰기 지점.
    private func recordClipboardHistory(_ text: String) {
        guard clipboardHistoryEnabledNow() else { return }
        var history = clipboardHistoryRepository.load()
        guard history.record(text) else { return }
        clipboardHistoryRepository.save(history)
    }

    /// iPad 병렬 사용(Split View 등)에서는 키보드가 떠 있는 채로 설정 앱이 기록을 끄고 비울 수
    /// 있다 — viewWillAppear가 안 와서 stale `settings`로 다시 쓰면 "끄면 삭제"가 깨진다.
    /// 학습 단어의 토큰 재확인과 같은 방어 — 쓰기·패널 열기 직전에만 재확인 (핫패스 아님).
    private func clipboardHistoryEnabledNow() -> Bool {
        let latest = settingsRepository.load().clipboardHistoryEnabled
        if latest != settings.clipboardHistoryEnabled {
            settings.clipboardHistoryEnabled = latest
            viewState?.clipboardHistoryEnabled = latest
        }
        return latest
    }

    /// 칩 탭 — 이미 추출해 둔 값을 넣는다. **프로브했던** 클립보드만 소비 처리한다.
    private func handlePasteboardCodeTap() {
        playToolbarHaptic()
        consumedPasteboardChangeCount = probedPasteboardChangeCount
        if let code = pasteboardCode {
            inputController?.insertProvidedText(code)
        }
        pasteboardCode = nil
        refreshLayout()
        suppressesWordSuggestionsAfterCursorMove = false
        updateSuggestionBar(userEdited: true)
    }

    private func handleWordTap(_ word: String) {
        playToolbarHaptic()
        inputController?.completeWord(word)
        refreshLayout()
        suppressesWordSuggestionsAfterCursorMove = false
        updateSuggestionBar(userEdited: true)
    }

    // MARK: - 툴바 도구 (PDR toolbar-tools)

    /// 설정(disabledTools)과 권한(FA)으로 거른 도구 목록을 뷰에 반영한다.
    private func updateVisibleTools() {
        guard let viewState else { return }
        // 사용자 편집 순서(orderedTools — 신규 도구는 뒤에 보정) → 설정·권한 필터
        let tools = settings.orderedTools.filter { tool in
            !settings.disabledTools.contains(tool)
                && (tool.worksWithoutFullAccess || hasFullAccess)
        }
        if viewState.visibleTools != tools { viewState.visibleTools = tools }
    }

    /// 툴바(도구·칩·후보·이모지) 탭 — 진동만 (사용자 요청 2026-09-02). 클릭음은 자판 키 전용.
    private func playToolbarHaptic() {
        guard settings.hapticEnabled, hasFullAccess else { return }
        hapticGenerator.impactOccurred(intensity: settings.clampedHapticIntensity)
        hapticGenerator.prepare()
    }

    private func handleToolTap(_ tool: ToolbarTool) {
        playToolbarHaptic()
        switch tool {
        case .dismiss:
            dismissKeyboard()
        case .clipboard:
            inputController?.commitComposition()
            if viewState?.showsClipboardPanel == true {
                viewState?.showsClipboardPanel = false
            } else {
                openClipboardPanel()
            }
            updateSuggestionBar()
        case .emoji:
            // 도구 사용 = 조합 확정 (천지인 연타·pending 상태가 패널을 관통하지 않게)
            inputController?.commitComposition()
            if viewState?.showsClipboardPanel == true { viewState?.showsClipboardPanel = false }
            viewState?.showsEmojiPanel.toggle()
            updateSuggestionBar()
        case .cursorLeft, .cursorRight:
            break  // UI가 onCursorMove로 보낸다
        }
    }

    /// - Parameter haptic: 툴바 ◀▶는 탭마다 진동, 스페이스 트랙패드 드래그는 연속 호출이라 없음
    private func handleCursorMove(_ offset: Int, haptic: Bool = true) {
        if haptic { playToolbarHaptic() }
        textDocumentProxy.adjustTextPosition(byCharacterOffset: offset)
        // 커서가 움직였다 — 조합·꼬리를 버린다. 이동 직후의 문서 문맥은 아직 이전 위치일 수
        // 있어 여기서 꼬리를 세우지 않는다(한 글자 어긋난 칩이 탭 시 문서를 훼손). 호스트가
        // 이어 보내는 textDidChange가 새 문맥으로 세운다.
        inputController?.syncWithDocument()
        suppressesWordSuggestionsAfterCursorMove = true
        updateSuggestionBar()
    }

    private func handleEmojiTap(_ emoji: String) {
        playToolbarHaptic()
        inputController?.insertProvidedText(emoji)
        recentEmojis.removeAll { $0 == emoji }
        recentEmojis.insert(emoji, at: 0)
        if recentEmojis.count > 16 { recentEmojis.removeLast(recentEmojis.count - 16) }
        viewState?.recentEmojis = recentEmojis
        refreshLayout()
        suppressesWordSuggestionsAfterCursorMove = false
        updateSuggestionBar(userEdited: true)
    }

    /// 이모지 최근 사용 — 세션 메모리만 (App Group 저장은 실사용 확인 후, PDR).
    private var recentEmojis: [String] = []

    // MARK: - 클립보드 기록 패널 (PDR clipboard-history)

    /// 도구 열기 = 현재 클립보드 1회 읽기 ("도구를 열었을 때만 읽는다" 조항의 원형).
    /// 기록이 켜져 있으면 저장분 전체를, 꺼져 있으면 현재 내용만 세션 목록으로 보여준다
    /// (저장 없음). secure 필드에서는 읽지도 기록하지도 않고 저장분만 보여준다.
    /// 같은 changeCount는 프로브와 동일하게 다시 기록하지 않는다 — 사용자가 ✕로 지운 현재
    /// 클립보드가 재오픈마다 되살아나지 않게 (리뷰 반영). changeCount는 읽기 **전에** 취한다.
    private func openClipboardPanel() {
        guard let viewState, hasFullAccess else { return }
        var entries: [String] = []
        let pasteboard = UIPasteboard.general
        let secure = textDocumentProxy.isSecureTextEntry == true
        if clipboardHistoryEnabledNow() {
            let changeCount = pasteboard.changeCount
            if !secure, changeCount != recordedPasteboardChangeCount,
               pasteboard.hasStrings, let current = pasteboard.string {
                recordClipboardHistory(current)
                recordedPasteboardChangeCount = changeCount
            }
            entries = clipboardHistoryRepository.load().entries
        } else if !secure, pasteboard.hasStrings, let current = pasteboard.string {
            var session = ClipboardHistory()
            session.record(current)
            entries = session.entries
        }
        viewState.clipboardEntries = entries
        if viewState.showsEmojiPanel { viewState.showsEmojiPanel = false }
        viewState.showsClipboardPanel = true
    }

    private func handleClipboardEntryTap(_ text: String) {
        playToolbarHaptic()
        inputController?.insertProvidedText(text)
        viewState?.showsClipboardPanel = false
        refreshLayout()
        suppressesWordSuggestionsAfterCursorMove = false
        updateSuggestionBar(userEdited: true)
    }

    private func handleClipboardEntryDelete(_ text: String) {
        playToolbarHaptic()
        guard let viewState else { return }
        if clipboardHistoryEnabledNow() {
            var history = clipboardHistoryRepository.load()
            history.remove(text)
            clipboardHistoryRepository.save(history)
            viewState.clipboardEntries = history.entries
        } else {
            viewState.clipboardEntries.removeAll { $0 == text }
        }
    }

    private func handleClipboardClear() {
        playToolbarHaptic()
        clipboardHistoryRepository.clear()
        viewState?.clipboardEntries = []
    }

    // MARK: - 뷰 구성

    private func installKeyboardView(state: KeyboardViewState) {
        let root = KeyboardRootView(
            state: state,
            inputModeSwitchButton: AnyView(InputModeSwitchButton(controller: self)),
            onEvent: { [weak self] event in
                DispatchQueue.main.async { self?.handle(event) }
            },
            onSnippetTap: { [weak self] suggestion in
                DispatchQueue.main.async { self?.handleSnippetTap(suggestion) }
            },
            onWordTap: { [weak self] word in
                DispatchQueue.main.async { self?.handleWordTap(word) }
            },
            onPasteboardCodeTap: { [weak self] in
                DispatchQueue.main.async { self?.handlePasteboardCodeTap() }
            },
            onToolTap: { [weak self] tool in
                DispatchQueue.main.async { self?.handleToolTap(tool) }
            },
            onCursorMove: { [weak self] offset in
                DispatchQueue.main.async { self?.handleCursorMove(offset) }
            },
            onEmojiTap: { [weak self] emoji in
                DispatchQueue.main.async { self?.handleEmojiTap(emoji) }
            },
            // 터치다운 즉시 — 지연 없이 동기 호출 (SwiftUI 제스처는 메인 스레드)
            onKeyPress: { [weak self] in self?.playKeyFeedback() },
            onClipboardEntryTap: { [weak self] text in
                DispatchQueue.main.async { self?.handleClipboardEntryTap(text) }
            },
            onClipboardEntryDelete: { [weak self] text in
                DispatchQueue.main.async { self?.handleClipboardEntryDelete(text) }
            },
            onClipboardClear: { [weak self] in
                DispatchQueue.main.async { self?.handleClipboardClear() }
            },
            // 스페이스 트랙패드 — 드래그 중 연속 호출, 지연 없이 동기 (진동 없음)
            onCursorDrag: { [weak self] offset in self?.handleCursorMove(offset, haptic: false) },
            onDismissSuggestions: { [weak self] in
                DispatchQueue.main.async { self?.handleDismissSuggestions() }
            }
        )
        let host = UIHostingController(rootView: root)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear  // applyBackdropColor가 테마 색으로 덮는다

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)

        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController = host
    }

    private func reloadSettingsIfChanged() {
        let latest = settingsRepository.load()
        guard latest != settings, let viewState else {
            settings = latest
            return
        }
        let previous = settings
        settings = latest
        viewState.themeSpec = themeRepository.theme(id: latest.selectedThemeID)
        viewState.appearance = latest.appearance
        viewState.keyboardHeight = keyboardAreaHeight
        viewState.showsKeyPreview = latest.showsKeyPreview
        viewState.clipboardHistoryEnabled = latest.clipboardHistoryEnabled
        if let inputController {
            // 자판 또는 타임아웃이 바뀌면 소스를 새로 만든다 (조합은 확정된다)
            if latest.activeHangulLayout != previous.activeHangulLayout
                || latest.cheonjiinTimeout != previous.cheonjiinTimeout
                || latest.danmoeumTimeout != previous.danmoeumTimeout {
                inputController.setHangulSource(Self.makeHangulSource(for: latest))
            }
            inputController.doubleSpacePeriod = latest.doubleSpacePeriod
            applyAutoCapitalizationPolicy()
            refreshLayout()  // 배열(자판·숫자 줄) + 시프트(자동 대문자 정책 변화)
        }
        applyBackdropColor()  // 테마·모드 변경
    }

    /// 자판 영역 높이 — 기준 216pt × 배율(0.8~1.2), 숫자 줄이 켜져 있으면 44pt × 배율 가산.
    /// 배율은 모드와 무관하게 고정이다 — 전환 시 높이가 튀지 않게 (PDR toolbar-tools 결정 3).
    private var keyboardAreaHeight: CGFloat {
        let scale = CGFloat(settings.clampedHeightScale)
        let base = (216 * scale).rounded()
        let numberRow = settings.numberRowEnabled ? (44 * scale).rounded() : 0
        return base + numberRow
    }

    /// 활성 자판 설정 → JamoSource. 조립 지점의 유일한 자판 분기다.
    private static func makeHangulSource(for settings: KeyboardSettings) -> JamoSource {
        switch settings.activeHangulLayout {
        case .dubeolsik:
            return DubeolsikSource()
        case .cheonjiin:
            return CheonjiinSource(timeout: settings.cheonjiinTimeout)
        case .danmoeum:
            return DanmoeumSource(timeout: settings.danmoeumTimeout)
        }
    }

    // MARK: - 키 피드백 (PDR height-scale-and-feedback · feedback-intensity)

    /// `.medium` 고정 + `impactOccurred(intensity:)`로 세기 조절 — 스타일을 바꾸면 질감이 달라져
    /// 슬라이더가 단조롭지 않다. 기본 0.6이 이전 `.light` 1.0과 비슷한 체감.
    private lazy var hapticGenerator = UIImpactFeedbackGenerator(style: .medium)

    /// 번들 클릭음 플레이어 — 소리 크기 조절을 위해 시스템 `playInputClick` 대신 자체 재생한다.
    /// 만들지 못하면(리소스 누락·세션 실패) `playInputClick`으로 폴백한다.
    private var clickPlayer: AVAudioPlayer?
    private var clickPlayerFailed = false

    /// 소리가 켜져 있으면 플레이어를 준비해 첫 키의 지연을 없앤다 (등장 시 호출).
    private func prepareClickPlayerIfNeeded() {
        guard settings.keySoundEnabled else {
            clickPlayer = nil  // 꺼졌으면 메모리에서 내린다
            return
        }
        if clickPlayer == nil, !clickPlayerFailed {
            guard let url = Bundle.main.url(forResource: "key_click", withExtension: "wav") else {
                clickPlayerFailed = true
                return
            }
            do {
                // ambient + mixWithOthers: 호스트 앱의 음악을 끊지 않고, 무음 스위치를 따른다
                try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                clickPlayer = player
            } catch {
                clickPlayerFailed = true
                return
            }
        }
        clickPlayer?.volume = Float(settings.clampedKeySoundVolume)
        clickPlayer?.prepareToPlay()
    }

    /// 자판 키 **터치다운**에만 (백스페이스 반복 포함) — 툴바·칩·이모지 그리드 탭은 제외
    /// (애플 기본 키보드와 같은 감각, 리뷰 반영: 릴리스 시점이면 소리가 한 박자 늦다).
    private func playKeyFeedback() {
        // 진동은 Full Access 없이 동작하지 않는다 (하드 제약) — 조용히 생략
        if settings.hapticEnabled, hasFullAccess {
            hapticGenerator.impactOccurred(intensity: settings.clampedHapticIntensity)
            hapticGenerator.prepare()
        }
        if settings.keySoundEnabled {
            if let clickPlayer {
                // 연타 시 직전 소리를 처음부터 다시 — 40ms 클릭이라 겹침이 들리지 않는다
                clickPlayer.currentTime = 0
                clickPlayer.play()
            } else {
                // 폴백 — 시스템 설정 > 사운드 > 키보드 클릭이 켜져 있을 때만 난다 (크기 조절 불가)
                UIDevice.current.playInputClick()
            }
        }
    }

    /// 툴바 + 자판 높이. 시스템 제약과의 충돌을 피하려 999 우선순위.
    private func updateHeight() {
        let total = KeyboardRootView.toolbarHeight + keyboardAreaHeight + 4
        if let heightConstraint {
            heightConstraint.constant = total
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: total)
            constraint.priority = .init(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}

// MARK: - 어댑터

/// 클릭음(`UIDevice.playInputClick`)이 나려면 루트 입력 뷰가 이 프로토콜을 채택해야 한다.
private final class ClickableInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

/// `UITextDocumentProxy` → `TextOutput`. KeyboardCore가 UIKit을 모르게 하는 경계.
private final class ProxyTextOutput: TextOutput {
    private weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    func insertText(_ text: String) {
        controller?.textDocumentProxy.insertText(text)
    }

    func deleteBackward(_ count: Int) {
        guard let proxy = controller?.textDocumentProxy else { return }
        for _ in 0..<count { proxy.deleteBackward() }
    }
}

/// 지구본 키 — 시스템 요건. `handleInputModeList`에 연결된 UIKit 버튼이어야
/// 길게 눌러 키보드 목록을 띄우는 표준 동작이 나온다.
private struct InputModeSwitchButton: UIViewRepresentable {
    weak var controller: UIInputViewController?

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        if let controller {
            button.addTarget(controller,
                             action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                             for: .allTouchEvents)
        }
        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {}
}
