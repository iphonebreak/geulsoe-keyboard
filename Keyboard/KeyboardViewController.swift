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
    /// SwiftUI 호스트의 높이 제약 — 입력 뷰가 시스템 기본 높이로 잡히는 패스에서도
    /// 자판이 같은 크기·같은 자리에 그려지게 한다.
    private var hostHeightConstraint: NSLayoutConstraint?
    /// F1 — 이번 등장에서 첫 렌더 전에 레이아웃을 강제해야 하는가.
    private var needsFreshHostPresize = false

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
    /// 직전 등장에서 본 자판 폭. 창이 붙기 전 `presizeFreshHostIfNeeded`가 프레임을 미리 잡을 때 쓴다
    /// (익스텐션이 프로세스로 상주하므로 두 번째 등장부터는 항상 안다).
    nonisolated(unsafe) private static var lastKnownHostWidth: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        // 클릭음 요건: inputView가 UIInputViewAudioFeedback을 채택해야 playInputClick이 난다
        // (Apple 문서). 서브뷰를 얹기 전에 루트 뷰를 교체한다.
        //
        // **스타일은 `.default`다 — `.keyboard`가 아니다.** 애플 문서(Context7 확인, 2026-09-10):
        // `.keyboard`는 "blur **and tinting**을 적용해 키보드 배경을 흉내 낸다", `.default`는 "blur만".
        // 그 틴트는 `backgroundColor`가 아니라 **뷰가 스스로 그리는 것**이라 배경색 계측에 잡히지 않는다 —
        // 우리가 "우리는 아무것도 안 칠한다(pbgA=0)"고 결론 낸 구멍이 정확히 여기였다.
        // 등장 직후 입력 뷰가 852pt로 잡히는 구간에서 그 틴트가 **자판 위 555pt까지** 깔리고,
        // 퓨어 다크에서는 그것이 사용자가 본 "어두운 남색·검정 띠"가 된다.
        // 최종 화면에서 이 백드롭은 어차피 보이지 않는다 — SwiftUI 루트가 자판 사각형 전체를
        // 테마색으로 불투명하게 덮기 때문이다. 그래서 틴트를 버려도 잃는 것이 없다.
        //
        // **설정을 먼저 읽고 높이를 아는 채로 입력 뷰를 만든다.** 시스템은 입력 뷰가 붙는 순간부터
        // 크기를 묻는데, 그때 우리가 답을 못 하면 제 기본값(실기 852pt = 화면 전체)으로 컨테이너를
        // 만들고 그 둥근 회색 판이 우리 자판이 뜰 때까지 노출된다(사용자 확인 2026-09-10).
        // (`allowsSelfSizing` + `intrinsicContentSize`로 답해 보았으나 852 구간이 그대로여서 되돌렸다 —
        //  실측 없이 동작만 바꾸는 코드는 남기지 않는다. 2026-09-10)
        settings = settingsRepository.load()
        let clickable = ClickableInputView(frame: .zero, inputViewStyle: .default)
        clickable.preferredHeight = totalKeyboardHeight   // 창이 없어도 세로 기준값은 지금 알 수 있다
        inputView = clickable

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
            showsKeyPreview: showsKeyPreview,
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
        clearSystemContainerBackground()   // 조상이 이미 붙어 있으면 여기서 먼저 잡는다
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
    /// 우리 입력 뷰를 담고 있는 **시스템 컨테이너를 투명하게 만든다.**
    ///
    /// 등장 직후 시스템은 키보드 컨테이너를 화면 전체 높이(실기 852pt)로 만들고, 우리 자판은 그
    /// 아래쪽 일부만 덮는다. 우리 뷰는 자판 사각형 밖을 칠하지 않지만(마스크 실기 확인 2026-09-10),
    /// **그 조상 뷰들이 `isOpaque = true`인데 배경색이 없어** 남는 자리가 시스템 기본 판
    /// (둥근 모서리 회색)으로 합성된다 — 사용자가 본 것이 그것이다.
    ///
    /// 조상들을 투명하게 바꾸면 그 자리는 **호스트 앱이 그대로 비친다** = 키보드가 아직 안 올라온
    /// 상태와 같은 그림이 된다. 우리가 만든 뷰는 아니지만 **우리 프로세스 안의 평범한 `UIView`** 이고,
    /// 바꾸는 것도 공개 속성 두 개뿐이다. 최종 상태에서는 우리 뷰가 창을 꽉 채우므로 영향이 없다.
    private func clearSystemContainerBackground() {
        var node: UIView? = view.superview
        var depth = 0
        while let current = node, depth < 6 {
            if current.isOpaque { current.isOpaque = false }
            if current.backgroundColor != nil, current.backgroundColor != .clear {
                current.backgroundColor = .clear
            }
            node = current.superview
            depth += 1
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        clearSystemContainerBackground()
        let needs = needsInputModeSwitchKey
        if let viewState, viewState.needsInputModeSwitchKey != needs {
            viewState.needsInputModeSwitchKey = needs
            refreshLayout()
        }
        // 높이를 다시 걸어야 하는 두 경우를 **계산 결과로** 판정한다 —
        //  (1) `viewDidLoad`에서는 창이 없어 화면 높이·폭을 몰라 보수값으로 걸어 뒀다.
        //      창이 붙는 이 시점이 첫 프레임 **전**이라, 여기서 바로잡으면 사용자는 못 본다.
        //  (2) 회전·Split View로 폭이 바뀌면 아이패드 기준 높이가 달라진다.
        // 폭만 보면 (1)에서 폭이 그대로인 채 화면 높이만 확정되는 경우를 놓친다.
        if heightConstraint == nil || heightConstraint?.constant != totalKeyboardHeight {
            applyKeyboardHeight(layoutNow: false)   // 이미 레이아웃 패스 안이다 (재진입 금지)
        }
        // F1 — 폭은 여기서야 확정된다. 첫 렌더 전이므로 지금 밀면 사용자는 못 본다.
        presizeFreshHostIfNeeded(tag: "willLayout")
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
        // 호스트 뷰 배경.
        //
        // **2026-09-11 정정:** 예전 주석은 "호스트 뷰는 **자판 사각형 그 자체**라 언제나 테마 색으로
        // 칠한다"였다. 14차(`fillInputViewWithHost`)가 그 전제를 깼다 — 호스트는 이제 **상자 전체**
        // (실기 852pt)다. 그런데 이 줄이 갱신되지 않아 **호스트 혼자서도 852pt 단색**을 만들고 있었다
        // (A/B 실측: `hbgA=1.00, hOpq=1`). 검증자가 잰 555pt 단색의 다른 한 축이 이것이다.
        //
        // 16차: 호스트가 상자 전체를 덮는 구성에서는 여기서 칠하지 않는다 — 자판 사각형 뒤 칠은
        // `KeyboardRootView`가 맡는다(`transparentAbove`). 그 대신 2026-09-04의 "등장 첫 프레임
        // 밝은 번쩍임 방어"는 이 경로에서 사라진다 — 그 자리에 시스템 백드롭이 보이는 것이
        // 16차가 의도하는 정상 동작이다.
        let hostPaintsWholeBox = Self.fillInputViewWithHost && Self.transparentAboveContent
        hostingController?.view.backgroundColor = hostPaintsWholeBox ? .clear : color
        // **칠하지 않으면 불투명이라고 선언해서도 안 된다.** `isOpaque = true`인 뷰는 컴포지터에게
        // "내 bounds를 내가 전부 덮는다"고 말하는 것이라, 칠이 없으면 뒤를 그리지 않아도 되는
        // 상태가 된다(15차에서 입력 뷰에 같은 모순이 있었다 — 첫 계측이 `opq=1, bgA=-1`이었다).
        hostingController?.view.isOpaque = !hostPaintsWholeBox
        // 입력 뷰는 시스템이 화면 전체 높이로 잡는 구간이 있다(실기 852pt·30~70ms).
        // 그 구간에 이 색을 칠하면 화면을 덮는 판이 된다 — 색을 넘겨만 두고 **칠할지 말지는
        // 크기를 아는 쪽(`layoutSubviews`)이 정한다.**
        (view as? ClickableInputView)?.themeBackground = color
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // **수정 C의 안전장치.** `viewWillDisappear`에서 호스트를 떼어 두는데,
        // 같은 인스턴스가 `viewDidLoad` 없이 다시 등장하면(아이패드 다중 창 — 위 주석과 같은 경우)
        // `installKeyboardView`가 다시 돌지 않아 **자판이 통째로 비어 버린다.**
        // 그 경우 여기서 다시 설치한다. `viewDidLoad` 경로에서는 이미 설치돼 있어 걸리지 않는다.
        if Self.releaseHostOnDisappear, hostingController == nil, let viewState {
            installKeyboardView(state: viewState)
        }
        clearSystemContainerBackground()
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
        // secure도 서명에 넣는다 — 같은 앱 안에서 아이디 → 비밀번호로 필드만 바뀌면
        // viewWillAppear가 오지 않는데, 확대 미리보기는 그 즉시 꺼져야 한다 (QA N-4)
        let signature = "\(keyboardType.rawValue)/\(returnKeyType.rawValue)"
            + "/\(autocapitalizationType.rawValue)/\(proxy.isSecureTextEntry == true)"
        guard force || signature != appliedFieldSignature else { return }
        appliedFieldSignature = signature
        if viewState.showsKeyPreview != showsKeyPreview { viewState.showsKeyPreview = showsKeyPreview }

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
        if viewState.layout != layout {
            // 자판이 바뀌면 **기준 열 수가 바뀔 수 있다**(두벌식 10 ↔ 천지인 4 ↔ 숫자 패드 3).
            // 높이는 그 열 수에서 나오므로 여기서 다시 걸지 않으면 이전 자판의 높이가 남는다.
            let unitsChanged = viewState.layout.referenceUnits != layout.referenceUnits
            viewState.layout = layout
            if unitsChanged { applyKeyboardHeight() }
        }
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        releaseHostForNextAppearance()      // 수정 C — stolen 재부착을 등장 밖으로 옮긴다
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

    /// 채움글 칩 탭. **지금 툴바에 떠 있는 칩만 받는다** — 칩은 퇴장 트랜지션(0.28초) 동안에도
    /// 계층에 남아 히트 테스트를 받으므로, 빠르게 두 번 누르면 같은 칩이 두 번 들어온다.
    /// 여기서 상태를 먼저 비워 2회차를 걸러 내고, `InputController`가 꼬리 정합까지 다시 검사한다
    /// (2중 방어 — QA BLOCK-2). 삽입에 실패하면 문서를 건드리지 않고 후보만 갱신한다.
    private func handleSnippetTap(_ suggestion: SnippetSuggestion) {
        guard let viewState, viewState.snippetSuggestion == suggestion else { return }
        viewState.snippetSuggestion = nil  // 애니메이션 중 재탭 차단
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


    /// **11차 시도 토글 (임시, 2026-09-10) — 후보 2 "그 구간에 아무것도 그리지 않는다".**
    ///
    /// 근거: 10차 계측(`docs/release/flicker-attempt-10.md` 3-2)과 반론자 2차 (c).
    /// 계단의 주체는 우리 제약이 아니라 시스템 `_UIHostedWindow`/레이아웃 패스다 —
    /// 상수는 내내 최종값인데 `winH`·`pvh`·`mvh`만 874→444→266으로 함께 움직였다.

    // MARK: - 12차 시도 (2026-09-11) — "우리만 깜빡인다"

    /// **대반전:** 같은 폰·같은 iOS에서 Gboard·네이버 키보드는 깜빡임이 **전혀 없다**(사용자 슬로모션 대조).
    /// 즉 시스템 공통 동작이 아니라 **우리 코드에 원인이 있다.** HANDOFF 2절의 "네이버도 같은 창 전이"는
    /// 창 높이 곡선이 비슷하다는 뜻이지 화면에 판이 보인다는 뜻이 아니었다.
    ///
    /// **★ 최우선 단서(사용자 실기 2026-09-11):** 키보드를 올렸다 내렸다 반복하면 깜빡임이 **한 번씩 걸러**
    /// 나타난다(1회 있음 / 2회 없음 / 3회 있음 …). 앱을 껐다 다시 열면 계속 깜빡인다.
    /// 교대는 시스템 레이스가 아니라 **우리 상태**다 — `installKeyboardView`의 호스팅 컨트롤러 재사용 분기가
    /// 정확히 그 교대를 만든다(아래 `alwaysReuseHost` 주석 참조).
    ///
    /// **H0:** 깜빡임은 "**새로 만든** SwiftUI 호스트의 첫 레이아웃이 과대한(852pt) 입력 뷰 안에서 일어날 때"
    /// 난다. 재사용된 호스트는 이미 제 크기로 레이아웃된 뷰를 갖고 있어 빈 구간이 생기지 않는다.

    /// **F1 — fresh 경로를 reuse 경로처럼 만든다.**
    /// 새로 만든 호스팅 컨트롤러는 붙는 순간 아직 아무 크기로도 레이아웃되지 않았다. 그 상태로 과대한
    /// 입력 뷰에 들어가면 첫 커밋에서 자판이 제 크기로 그려질 준비가 안 돼 그 구간이 비어 보인다.
    /// 켜면 **fresh 경로에서만** 첫 렌더 전에 레이아웃을 강제한다(폭이 확정되는 첫
    /// `viewWillLayoutSubviews`에서 한 번 더 — `viewDidLoad`에는 창이 없어 폭을 모른다).
    static let presizeFreshHost = true

    /// **F2 — fresh 경로 자체를 없앤다.**
    /// 지금 조건은 `sharedHostingController.parent == nil`일 때만 재사용한다. 이전
    /// `KeyboardViewController`가 아직 살아 있으면 재사용이 막혀 **새로 만들고**, 그렇게 만든 것은
    /// `sharedHostingController == nil`일 때만 저장되므로 **버려진다** → 다음 등장에는 옛 shared가
    /// `parent == nil`이 되어 재사용된다 → **있음/없음이 교대한다.** 사용자 관찰과 정확히 일치한다.
    ///
    /// 켜면 (a) 부모가 남아 있어도 **화면에 없으면(stale)** 떼어내서 재사용하고,
    /// (b) 그래도 새로 만들어야 했다면 `sharedHostingController`를 **갱신**해 버려지지 않게 한다.
    /// 진짜로 둘이 동시에 필요한 경우(아이패드 다중 창 — 부모의 뷰가 창에 붙어 있다)만 새로 만든다.
    static let alwaysReuseHost = true


    // MARK: - 13차 (2026-09-11) — F2는 걸렸는데 깜빡임은 남았다

    /// **실기 결과(09:27 빌드, 사장님 회수):** F2는 완벽히 걸렸다 —
    /// `#host` 24줄이 fresh 1(불가피한 최초) + **reuse 23, 전부 `stolen=1`**, `live`는 2~3.
    /// **메모리 누수도 실기에서 해결 확정** — 새 pid에서 physMB 5.0 → 14.2(등장 24회, **등장당 +0.38MB**,
    /// 예열 뒤 구간은 +0.12MB). 직전 빌드들은 +3.52 ~ +4.34MB/회였다. 출시 차단 사안이 잡혔다.
    /// **그러나 사용자는 "아직도 깜빡거림이 있다"고 한다** → H0는 메모리 누수를 설명하지만
    /// **깜빡임의 원인으로는 반증 쪽**이다.

    /// **수정 A — presize를 재사용 경로에도 건다.**
    ///
    /// `presizeFreshHost`는 `isFresh`일 때만 걸린다. 그런데 F2 이후 실제 경로는 **매번 reuse(stolen)**이고,
    /// 그 경로도 `existing.view.removeFromSuperview()` → 새 입력 뷰에 `addSubview` + 제약 재생성을 한다.
    /// stolen 경로는 `willMove(toParent: nil)` + `removeFromParent()`까지 해 **컨테인먼트를 완전히 끊었다가
    /// 다시 붙인다.** 즉 **재사용 호스트도 과대한 입력 뷰 안에서 다시 레이아웃된다** —
    /// "재사용은 이미 제 크기라 필요 없다"는 12차의 전제는 stolen 재부착 때문에 **더 이상 사실이 아니다.**
    ///
    /// 실기 증거: `#presize` 줄이 **파일 전체에 1개**뿐이었다(= fresh 1회에만 돌았다).
    ///
    /// 켜면 fresh/reuse를 가리지 않고 **모든 설치 경로**에서 첫 렌더 전 레이아웃을 강제한다.
    static let presizeAllHostInstalls = true

    /// **창이 붙기 전에도 높이 제약을 만든다** (13차 수정 B).
    ///
    /// 실기에서 `#heightPinned`이 **176표본 전부 −1**이었다. 이 토글이 없으면
    /// `applyHeightConstants`가 `view.window != nil`일 때만 제약을 만드는데 `viewInstalled` 시점엔
    /// 창이 없다 → **높이 제약이 아예 없는 채로 첫 레이아웃이 돈다.**
    /// 애플 문서(Context7 확인): 커스텀 키보드는 폭은 시스템이 정하고 **세로는 개발자가
    /// `UIInputViewController.view`의 Auto Layout 높이 제약으로** 준다. 우리는 등장 구간에 그 경로를
    /// 제공하지 않고 있었다.
    ///
    /// 가로·아이패드에서 창 없이 건 값은 화면 절반 상한을 모르므로 한 번 과대할 수 있다 —
    /// 첫 `viewWillLayoutSubviews`가 바로잡는 기존 경로 그대로다(계측으로 확인한다).
    static let pinHeightBeforeWindow = true

    /// **수정 C — 등장 구간 밖에서 호스트를 미리 놓아 `stolen` 재부착을 피한다.**
    ///
    /// 사용자 실기(13차 빌드 직전): 깜빡임이 **교대가 아니라 매번** 난다. 그때 경로는 reuse 23/24였고
    /// **전부 `stolen=1`**이었다. 즉 F2가 만든 것은 "항상 재사용"이 아니라 **"항상 stolen 재사용"**이다.
    /// stolen 경로는 등장 한복판에서 `willMove(toParent: nil)` + `removeFromSuperview()` +
    /// `removeFromParent()`로 **컨테인먼트를 끊었다가 곧바로 다시 붙인다** — 자연 재사용(`parent == nil`)보다
    /// 무겁다. 우리가 그 무거운 경로를 **더 잦게** 만들었을 가능성이 있다(사장님 지적).
    ///
    /// 켜면 **퇴장 시점**(`viewWillDisappear`)에 호스트를 미리 떼어 둔다. 그러면 다음 등장에서
    /// `sharedHostingController.parent == nil`이 되어 **훔칠 필요 없는 자연 재사용**이 걸리고,
    /// 떼어내는 비용은 사용자가 보지 않는 퇴장 구간으로 옮겨간다.
    /// 뷰 그래프는 `sharedHostingController`가 계속 붙들고 있으므로 **메모리 수정은 그대로다.**
    static let releaseHostOnDisappear = true

    // MARK: - 14차 (2026-09-11) — H1: 호스트가 입력 뷰 전체를 채운다

    /// **H1 — 우리 콘텐츠가 과대 구간을 덮지 않는 구조 자체를 바꾼다.**
    ///
    /// 10~13차가 전부 실패했다. 지금 구조는 SwiftUI 호스트를 입력 뷰 **하단에 고정 높이**로 붙인다
    /// (`bottomAnchor == view.bottomAnchor` + `height == totalKeyboardHeight`). 시스템이 등장 직전
    /// 입력 뷰를 과대한 높이(실기 852pt)로 잡는 구간에는 **위쪽 약 516pt가 빈 채로 남고**,
    /// 그 자리에 시스템 반투명 백드롭이 그대로 비친다 — 그것이 사용자가 보는 판이라는 가설이다.
    ///
    /// 켜면 호스트를 **입력 뷰 전체**(top·bottom·leading·trailing)에 붙이고,
    /// SwiftUI 루트가 `fillsContainer: true`로 **내용을 하단 정렬**한다(`KeyboardRootView` 참조).
    /// 상자 전체가 테마 색으로 칠해지므로 빈 자리가 없다.
    ///
    /// **과거 실패와의 구분:** `installKeyboardView` 옛 주석의 "위아래로 늘려 붙이면 자판이 가운데
    /// 정렬돼 화면 절반을 덮었다 튀어 내려온다"는 **가운데 정렬** 때문이지 **전체 채움** 때문이 아니다.
    /// 이번에는 정렬을 `.bottom`으로 못박는다 — 자판 크기는 `state.keyboardHeight` 고정이라 변하지 않는다.
    static let fillInputViewWithHost = true

    // MARK: - 15차 (2026-09-11) — 마스크가 우리 콘텐츠를 잘라내고 있었다

    /// **15차 — 과대 구간에서 위를 잘라내지 않는다.**
    ///
    /// 검증자 실기 A/B 계측(`docs/release/qa-report-device-flicker-harness.md` 5절)이 원인을 짚었다:
    /// H1을 켜서 `#fill`의 `gap`이 13/13 전부 0이 됐는데도(호스트가 입력 뷰를 852pt로 가득 채운다)
    /// **화면 결과는 13차와 똑같았다.** 두 빌드의 `maskH`가 모두 **310**이었기 때문이다.
    ///
    /// 범인은 `layoutSubviews` 끝의 **바닥 기준 마스크**다:
    /// `visible = min(preferredHeight, bounds.height) = 310`,
    /// `bottomMask.frame.y = bounds.height − visible = 542` → **위 542pt가 잘려 나간다.**
    /// 잘린 자리에 시스템 키보드 백드롭이 합성되고, 그것이 사용자가 매번 보는 판이다.
    ///
    /// 이 마스크는 **1차 시도 때 들어온 뒤 10·11·12·13차와 H1 내내 한 번도 검증 대상이 아니었다** —
    /// 다섯 번 연속 실패의 공통 원인이다.
    ///
    /// 켜면 과대 구간(`bounds.height > preferredHeight`)에 **마스크를 걸지 않고**,
    /// 입력 뷰 배경을 **실제 테마 색으로 불투명하게 칠한다**(아래 `opaqueThemePaint`).
    /// 마스크만 풀고 칠하지 않으면 "불투명이라고 선언했는데 칠해지지 않은" 영역이 드러난다
    /// (검증자 2-1절 1국면: `opq=1`인데 `bgA=−1`).
    ///
    /// **Slide Over 경로는 그대로 둔다** — 시스템이 입력 뷰를 우리 높이보다 **작게** 잡는 경우
    /// (`bounds.height < preferredHeight`)에는 넘치는 콘텐츠가 호스트 앱 위로 새지 않도록
    /// 기존의 bounds 자르기를 유지한다. 그 경우 `visible == bounds.height`라 마스크는 곧 bounds 전체다.
    static let unmaskWhileOversized = true

    // MARK: - 16차 (2026-09-11) — 과대 구간에 불투명 면을 내놓지 않는다

    /// **16차 — 우리 콘텐츠 위쪽을 진짜 투명으로 둔다.**
    ///
    /// 검증자가 16라운드 만에 처음으로 **실제로 합성되는 것**을 쟀다
    /// (`docs/release/qa-report-keyboard-comparison.md` 5절): 우리가 컴포지터에 **처음 넘기는 프레임**이
    /// `vh=852, hh=852, bgA=1.00, opq=1` — **852pt 불투명 면인데 내용은 297pt**다. 나머지 555pt가
    /// 단색으로 26~150ms 유지된다. **사용자가 보는 판이 바로 그 555pt 단색이다.**
    ///
    /// 그리고 "구조적으로 늦어서 못 고친다"는 무너졌다 — 같은 프로브로 잰 Gboard·네이버도 과대 목표가
    /// 정확히 최종+228pt로 동일하고 과대 구간 시작은 오히려 우리보다 **늦다**(4절).
    ///
    /// **정상 등장은 "반투명 백드롭이 올라오고 그 안에 자판이 나타나는 것"이다** — 사용자가 Gboard를
    /// 슬로모션으로 보고 그렇게 묘사했다. 즉 백드롭이 보이는 것 자체가 정상이고, 문제는 그 자리에
    /// 우리가 **불투명 단색을 얹는 것**이다. 그러니 겨눌 것은 "무엇을 그릴까"가 아니라
    /// **"우리가 그 구간에 불투명 면을 내놓지 않게 하는 것"**이다.
    ///
    /// 켜면 과대 구간에서 **세 군데를 함께** 끈다(하나만 꺼서는 여전히 불투명 면이 나간다 — A/B 실측):
    ///  1. 입력 뷰(`ClickableInputView`) 배경을 **완전 투명**으로 두고 `isOpaque = false`
    ///     (15차 `opaqueThemePaint`를 과대 구간에 쓰지 않는다)
    ///  2. **SwiftUI 호스트 뷰**의 배경을 칠하지 않는다 — 14차 이후 호스트는 자판 사각형이 아니라
    ///     **상자 전체**라, 호스트가 불투명하면 그것만으로 852pt 단색이 된다
    ///     (`applyBackdropColor`의 주석이 14차 전제로 남아 있었다)
    ///  3. `KeyboardRootView`가 상자 **전체**에 칠하던 배경을 **자판 사각형 뒤에만** 칠한다
    ///     (`transparentAbove` 파라미터)
    ///
    /// **마스크는 그대로 걸지 않는다**(15차 `unmaskWhileOversized` 유지) — 마스크가 범인이었다는
    /// 검증자 결론은 유효하다. 즉 **잘라내지도 않고, 위쪽을 칠하지도 않는다.**
    ///
    /// 1차 시도("852 구간 배경 투명 + 레이어 마스크")와의 차이: 그때는 **마스크가 남아 있었고**
    /// 그것이 범인이라는 것을 몰랐다. **마스크 없는 순수 투명은 아직 한 번도 해 본 적이 없다.**
    static let transparentAboveContent = true


    /// 호스팅 컨트롤러 재사용 스위치 (위 `installKeyboardView` 주석의 근거).
    static let reuseHostingController = true
    private static var sharedHostingController: UIHostingController<KeyboardRootView>?

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
            },
            fillsContainer: Self.fillInputViewWithHost,   // 14차 H1 — 상자 전체 채움 + 하단 정렬
            transparentAbove: Self.transparentAboveContent  // 16차 — 자판 사각형 뒤에만 칠한다
        )
        // **호스팅 컨트롤러를 프로세스 수명 동안 재사용한다.**
        // 실측(2026-09-10): 등장마다 SwiftUI 트리를 새로 만들면 malloc 힙이 등장당 2.5MB씩
        // 늘고 인스턴스를 해제해도 회수되지 않는다. 증가량은 **뷰 노드 수에 비례**했다
        // (천지인 16키 +0.9MB / 두벌식+숫자줄 43키 +2.3MB / 최소 키캡 +1.3MB / 사소한 SwiftUI +0.1MB).
        // 개별 수식어(섀도·접근성·제스처)를 하나씩 빼도 줄지 않았다 = 특정 코드의 결함이 아니라
        // **트리를 새로 인스턴스화하는 것 자체**가 남긴다. 그래서 만들지 않고 `rootView`만 바꾼다.
        //
        // **아직 살아 있는 다른 인스턴스의 것은 뺏지 않는다.** 평소엔 이전 인스턴스가 먼저
        // 해제되지만(실측: 동시 생존이 1을 넘은 적 없다), 아이패드 다중 창처럼 두 인스턴스가
        // 함께 사는 경우가 있으면 그때는 각자 새로 만든다.
        let host: UIHostingController<KeyboardRootView>
        // **F2 — stale한 부모에게서 떼어낸다.** 부모가 남아 있어도 그 뷰가 창에 없으면(= 화면에서
        // 내려간 이전 인스턴스) 재사용을 막을 이유가 없다. 진짜로 둘이 동시에 필요한 경우
        // (아이패드 다중 창 — 부모의 뷰가 창에 붙어 있다)만 새로 만든다.
        let shared = Self.sharedHostingController
        var reusable = shared.flatMap { $0.parent == nil ? $0 : nil }
        var stolen = false
        if Self.reuseHostingController, Self.alwaysReuseHost, reusable == nil,
           let shared, shared.parent !== self, shared.view.window == nil {
            shared.willMove(toParent: nil)
            shared.view.removeFromSuperview()
            shared.removeFromParent()
            reusable = shared
            stolen = true
        }
        let isFresh: Bool
        if Self.reuseHostingController, let existing = reusable {
            existing.view.removeFromSuperview()
            existing.rootView = root          // 뷰 그래프는 그대로 두고 내용만 갱신
            host = existing
            isFresh = false
        } else {
            host = UIHostingController(rootView: root)
            // **F2(b)** — 새로 만든 것을 버리지 않는다. 예전에는 `shared == nil`일 때만 저장해서
            // 다음 등장이 옛 shared를 다시 집어 **교대**를 만들었다.
            if Self.reuseHostingController, Self.alwaysReuseHost || Self.sharedHostingController == nil {
                Self.sharedHostingController = host
            }
            isFresh = true
        }
        // **presize 여부는 여기서 정한다** — 아래 `preAdd` 단계가 이 값을 보기 때문이다.
        // (2026-09-11 정정: 예전에는 `addSubview` **뒤에** 정해서 `preAdd`가 영영 돌지 않았다.)
        needsFreshHostPresize = Self.presizeFreshHost && (Self.presizeAllHostInstalls || isFresh)
        // **수정 A(정밀화) — `addSubview` 하기 전에 최종 크기로 프레임을 잡고 레이아웃한다.**
        // 붙은 뒤에 미는 것보다 한 단계 이르다: 입력 뷰에 들어가는 순간 이미 제 크기로 그려져 있다.
        // 폭은 창이 붙기 전이라 모를 수 있어 **직전 등장에서 본 폭**을 쓴다(익스텐션이 상주하므로
        // 두 번째 등장부터는 항상 안다). 폭을 전혀 모르면 건너뛰고 `viewWillLayoutSubviews`에서 민다.
        if needsFreshHostPresize {
            let width = view.bounds.width > 0 ? view.bounds.width : Self.lastKnownHostWidth
            if width > 0 {
                let total = totalKeyboardHeight
                UIView.performWithoutAnimation {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    // H1이면 상자 전체 높이로, 아니면 자판 높이로 미리 잡는다.
                    let h = Self.fillInputViewWithHost && view.bounds.height > 0
                        ? view.bounds.height : total
                    host.view.frame = CGRect(x: 0, y: 0, width: width, height: h)
                    host.view.layoutIfNeeded()
                    CATransaction.commit()
                }
            }
        }
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear  // applyBackdropColor가 테마 색으로 덮는다

        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        // **F1** — fresh 경로만 첫 렌더 전에 레이아웃을 강제한다. 폭은 첫
        // `viewWillLayoutSubviews`에서야 확정되므로 그때 한 번 더 민다(`needsFreshHostPresize`).

        // 붙이는 방식은 `fillInputViewWithHost`(14차 H1)가 정한다.
        //
        //  - **켬(H1):** 입력 뷰 **전체**에 붙인다. 상자가 852pt로 잡히는 구간에도 우리 콘텐츠가
        //    그 높이를 전부 차지하고, SwiftUI 루트가 내용을 하단 정렬한다(`fillsContainer`).
        //    빈 자리가 없으니 시스템 백드롭이 비칠 곳도 없다 — 그것이 H1의 전부다.
        //  - **끔(기존):** 아래에 고정 높이로 붙인다. 상자가 몇이든 자판은 같은 자리·같은 크기로
        //    그려지지만, 그 위 남는 자리는 **비어 있다**(그 빈 자리가 판이라는 것이 H1의 가설).
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if Self.fillInputViewWithHost {
            // 높이를 주지 않고 위까지 붙인다 — 상자 높이를 그대로 따라간다.
            host.view.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            hostHeightConstraint = nil
        } else {
            let hostHeight = host.view.heightAnchor.constraint(equalToConstant: totalKeyboardHeight)
            hostHeight.priority = .required
            hostHeight.isActive = true
            hostHeightConstraint = hostHeight
        }
        hostingController = host
        if needsFreshHostPresize { presizeFreshHostIfNeeded(tag: "install") }
    }

    /// **수정 C 본체.** 퇴장할 때 호스팅 컨트롤러를 이 컨트롤러에서 떼어 둔다.
    ///
    /// 다음 등장의 `installKeyboardView`가 `parent == nil`을 보고 **자연 재사용**을 고르게 하는 것이 목적이다
    /// (F2의 `stolen` 경로를 타지 않는다). 떼어내는 비용은 사용자가 보지 않는 퇴장 구간에서 치른다.
    /// `sharedHostingController`가 뷰 그래프를 계속 붙들고 있으므로 메모리 수정에는 영향이 없다.
    private func releaseHostForNextAppearance() {
        guard Self.releaseHostOnDisappear, let host = hostingController, host.parent === self else { return }
        host.willMove(toParent: nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        hostingController = nil
        hostHeightConstraint = nil
    }

    /// **F1 본체.** 설치된 SwiftUI 호스트를 **첫 렌더 전에** 최종 크기로 한 번 레이아웃시킨다.
    ///
    /// **2026-09-11 정정:** 예전 주석은 "재사용 경로는 이미 제 크기라 이 단계가 필요 없다"였다.
    /// **더 이상 사실이 아니다** — F2의 stolen 경로가 `removeFromParent()` + 새 입력 뷰에 `addSubview`로
    /// 컨테인먼트를 끊었다 다시 붙이므로, 재사용 호스트도 과대한 입력 뷰 안에서 다시 레이아웃된다.
    /// 그래서 `presizeAllHostInstalls`로 **모든 설치 경로**에 건다(수정 A).
    ///
    /// 폭을 모르면(창이 붙기 전 `viewDidLoad`) 아무 것도 하지 않고 플래그를 남겨,
    /// 폭이 확정되는 첫 `viewWillLayoutSubviews`에서 다시 시도한다.
    private func presizeFreshHostIfNeeded(tag: String) {
        guard needsFreshHostPresize, let host = hostingController else { return }
        let width = view.bounds.width
        guard width > 0 else { return }        // 아직 폭을 모른다 — 다음 기회에
        needsFreshHostPresize = false
        Self.lastKnownHostWidth = width
        let total = totalKeyboardHeight
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // H1이면 상자 전체를 채우고, 아니면 아래 기준 자판 높이만.
            let box = view.bounds.height
            let h = Self.fillInputViewWithHost && box > 0 ? box : total
            host.view.frame = CGRect(x: 0, y: Self.fillInputViewWithHost ? 0 : max(0, box - total),
                                     width: width, height: h)
            host.view.layoutIfNeeded()
            CATransaction.commit()
        }
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
        viewState.showsKeyPreview = showsKeyPreview
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

    /// 눌린 키의 확대 미리보기를 띄울지 — 설정 ∧ **비밀번호 필드가 아닐 것**.
    /// 시스템 키보드와 같게 맞춘다: secure 입력란에서는 어깨너머로 글자가 읽히면 안 된다
    /// (보안 감사 MEDIUM-3 · QA N-4). 키캡 구조는 그대로 두고 이 플래그만 내린다 —
    /// 누르는 도중 서브트리를 바꾸면 진행 중인 터치가 제스처에서 떨어진다 (CLAUDE.md 하드 룰).
    private var showsKeyPreview: Bool {
        settings.showsKeyPreview && textDocumentProxy.isSecureTextEntry != true
    }

    /// 자판 영역 높이 — 기준 높이 × 배율(0.8~1.2), 숫자 줄이 켜져 있으면 한 행만큼 가산.
    /// 배율은 모드와 무관하게 고정이다 — 전환 시 높이가 튀지 않게 (PDR toolbar-tools 결정 3).
    private var keyboardAreaHeight: CGFloat {
        let scale = CGFloat(settings.clampedHeightScale)
        let base = keyboardBaseHeight
        // 숫자 줄도 기준 높이와 같은 비율로 커진다 — 아이폰에서는 정확히 44pt다
        let numberRowBase = base / Self.phoneBaseHeight * 44
        let numberRow = settings.numberRowEnabled ? (numberRowBase * scale).rounded() : 0
        let requested = (base * scale).rounded() + numberRow
        return min(requested, maxKeyboardAreaHeight)
    }

    /// 자판 영역의 절대 상한 — **키보드 뷰 전체가 화면의 절반을 넘지 않게** 한다.
    /// 아이폰·아이패드에 같은 규칙을 건다.
    ///
    /// 이 규칙이 닫는 두 가지 (증상은 다르고 원인은 하나 — "키보드가 화면을 얼마나 먹어도
    /// 되는가"에 대한 규칙이 없었다):
    ///
    /// 1. **아이패드**: 행 높이 상한(76pt)은 배율을 *곱하기 전에* 걸리므로 배율이 그 방어를
    ///    무력화한다. 120%면 실효 행 높이가 91.2pt가 되고 숫자 줄이 같은 비율로 한 번 더 얹힌다
    ///    — 아이패드 mini 가로에서 자판이 화면의 69.8%까지 갔다 (검증자 실측 REQ-2).
    /// 2. **아이폰**: 기준 높이가 216pt 고정이라 **방향을 아예 보지 않는다.**
    ///    실측(iPhone 17 Pro, 874×402pt) — 가로에서 우리 키보드 287pt(**71.4%**)·행 49.7pt,
    ///    같은 화면의 시스템 키보드 207pt(51.6%)·행 27.3pt. 시스템은 가로에서 행을 35% 낮춘다.
    ///    세로는 우리 341pt(39.0%) vs 시스템 329pt(37.6%)로 거의 같다 — **세로는 문제가 아니다.**
    ///
    /// 왜 상한 하나로 두 가지가 닫히는가: 가로는 화면 높이가 짧으므로 같은 비율이 자동으로
    /// 더 낮은 절대값이 된다. 방향을 직접 판정하는 분기를 두지 않아도 된다.
    /// 상한에 걸려도 행은 `VStack`이 비례로 줄여 그리므로 배열이 깨지지 않는다.
    ///
    /// **세로 무회귀 확인**(전부 상한 아래라 값이 그대로다):
    /// 아이폰 세로 최대(120%+숫자 줄) 362pt = 41.4% · 아이패드 세로 최대 468pt = 39.7%.
    /// 아이패드 **가로 기본값**(100%·숫자 줄 끔) 366pt = 44.6%도 상한 아래 —
    /// REQ-1에서 맞춘 가로 종횡비 1.13:1이 그대로 남는다.
    ///
    /// **창이 붙기 전에는 상한을 걸지 않는다.** 화면 높이를 모르는 채 고른 값은 어느 쪽으로든
    /// 추측이다 — 크게 잡으면 과대(2026-09-09 이전), 작게 잡으면 과소(보수값 170pt, 검증자 지적)다.
    /// 그래서 **그 값이 그려질 수 없게** 만들어 두고(높이 제약 자체를 첫 레이아웃까지 만들지 않는다,
    /// `updateHeight` 참조) 여기서는 상한 없이 요청값을 돌려준다 — 세로에서는 그 값이 곧 최종값이다.
    /// 창 없이 화면 크기를 얻는 지원 경로는 없다 — `UIScreen.main`은 iOS 16에서 폐기됐고
    /// 애플이 가리키는 대체 경로가 `windowScene.screen`이다 (Context7로 확인, 2026-09-09).
    private var maxKeyboardAreaHeight: CGFloat {
        guard let screenHeight = view.window?.windowScene?.screen.bounds.height, screenHeight > 0 else {
            return .greatestFiniteMagnitude
        }
        // `screen.bounds`는 현재 방향을 반영한다 — 가로에서 짧은 변이 높이로 온다
        // (아이패드 가로 실측으로 확인: 상한이 820×0.45로 걸렸다)
        let total = (screenHeight * Self.maxScreenFraction).rounded()
        let overhead = KeyboardRootView.toolbarHeight + Self.keyboardBottomPadding
        return max(Self.minKeyboardAreaHeight, total - overhead)
    }

    /// 키보드 뷰(툴바 + 자판 + 하단 여백)가 차지할 수 있는 화면 높이 비율의 상한.
    /// 시스템 키보드의 가로 점유율(아이폰 51.6% 실측 / 아이패드 ≈47%)에 맞춘 값이다.
    private static let maxScreenFraction: CGFloat = 0.5
    /// 상한이 아무리 조여도 자판이 이보다 낮아지지는 않는다 (Slide Over 등 극단적으로 짧은 창 방어).
    private static let minKeyboardAreaHeight: CGFloat = 120
    /// `KeyboardRootView`가 자판 아래에 두는 여백. 총 높이 계산과 상한이 같은 값을 봐야 한다.
    private static var keyboardBottomPadding: CGFloat { KeyboardMetrics.bottomPadding }

    // MARK: - 기기별 기준 높이 (PDR ipad-support)

    /// 아이폰 기준 높이 — 지금까지의 고정값. 아이폰에서는 이 값이 그대로 나와야 한다(회귀 금지).
    private static let phoneBaseHeight: CGFloat = 216
    /// 아이패드 행 높이 하한·상한.
    ///
    /// 상한 76은 **더 이상 실제로 걸리지 않는다** — 폭이 `KeyboardMetrics.contentMaxWidth`에서
    /// 잘리므로 행 높이는 최대 73.8pt다. 상한을 남겨 두는 이유는 이것이 원래 "가로에서 자판이
    /// 화면을 삼키지 않게" 하는 방어였는데, **그 역할은 이제 `maxKeyboardAreaHeight`가 맡기
    /// 때문**이다 (상한을 폭 계산 안에 두면 배율이 그것을 곱해 뚫는다 — REQ-2).
    /// 하한 52는 Split View·Slide Over로 폭이 320pt대까지 줄어도 아이폰(48.75pt)보다 작아지지 않게 한다.
    private static let padRowHeightRange: ClosedRange<CGFloat> = 52...76

    /// 기준 자판 높이 — **키 폭에서 되짚어** 정한다.
    ///
    /// 아이폰은 216pt 고정이다(기존 값). 아이패드는 같은 배열을 2배 넓은 화면에 그리므로
    /// 높이를 고정하면 종횡비가 1.60:1까지 벌어져 "아이폰 자판을 늘린 것"이 된다
    /// (QA BLOCK-1 실측 77.5×48.5pt). 그래서 행 높이를 키 폭에 비례시킨다 —
    /// 회전·Split View로 폭이 바뀌면 `viewWillLayoutSubviews`가 다시 계산한다.
    ///
    /// **열 수는 지금 떠 있는 배열에서 읽는다.** 예전에는 10열이 상수로 박혀 있어, 실제로는
    /// 4열인 천지인도 "두벌식이었다면"의 키 폭으로 높이를 정했다 — 그 결과 아이패드 세로에서
    /// 천지인 키가 203.5 × 69.0 = **2.95 : 1**이 됐다 (검증자 실측 UX-8).
    /// 폭 상한·목표 종횡비·키 폭 식은 전부 `KeyboardMetrics`에 있다 —
    /// **UI가 실제로 그리는 값과 여기가 갈라지면 종횡비가 어긋난다.**
    private var keyboardBaseHeight: CGFloat {
        guard traitCollection.userInterfaceIdiom == .pad else { return Self.phoneBaseHeight }
        let units = viewState?.layout.referenceUnits ?? 10
        // KeyboardUI가 자판 영역을 이 폭에서 자르고 가운데 정렬한다 — 같은 값을 되짚는다
        let width = min(layoutWidth, KeyboardMetrics.contentMaxWidth(units: units))
        guard width > 0 else { return Self.phoneBaseHeight }
        let keyWidth = KeyboardMetrics.keyWidth(availableWidth: width, units: units)
        let aspect = KeyboardMetrics.targetKeyAspect(units: units)
        let rowHeight = min(max(keyWidth / aspect, Self.padRowHeightRange.lowerBound),
                            Self.padRowHeightRange.upperBound)
        return (rowHeight * 4 + Self.rowSpacing * 3).rounded()
    }

    /// 행 간격 — `KeyboardLayoutView`와 같은 값이어야 한다. 좌우 여백·키 간격은
    /// `KeyboardMetrics`가 계산 안에서 직접 쓴다.
    private static var rowSpacing: CGFloat { KeyboardMetrics.rowSpacing }

    /// 높이 계산에 쓰는 폭. 레이아웃 전(viewDidLoad)에는 뷰 폭이 0이라 화면 폭으로 대신한다.
    private var layoutWidth: CGFloat {
        if view.bounds.width > 0 { return view.bounds.width }
        return view.window?.windowScene?.screen.bounds.width ?? 0
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

    /// 높이 제약과 SwiftUI 상태를 함께 갱신한다. 폭이 바뀌거나(회전·Split View)
    /// 자판의 기준 열 수가 바뀔 때(자판 전환·숫자 패드) 부른다.
    private func applyKeyboardHeight(layoutNow: Bool = true) {
        updateHeight(layoutNow: layoutNow)
        let height = keyboardAreaHeight
        if let viewState, viewState.keyboardHeight != height { viewState.keyboardHeight = height }
    }

    /// 키보드 뷰가 실제로 차지해야 하는 총 높이 — 툴바 + 자판 + 하단 여백.
    /// 입력 뷰 제약과 SwiftUI 호스트 높이가 **같은 값**을 봐야 한다.
    private var totalKeyboardHeight: CGFloat {
        KeyboardRootView.toolbarHeight + keyboardAreaHeight + Self.keyboardBottomPadding
    }

    /// 툴바 + 자판 높이. 시스템 제약과의 충돌을 피하려 999 우선순위.
    ///
    /// **제약을 언제 만드는가는 `pinHeightBeforeWindow`가 정한다** (`applyHeightConstants` 참조) —
    /// `pinHeightBeforeWindow`가 켜져 있으면 창이 붙기 전 `viewDidLoad`에서도 만든다. 세로 아이폰에서는
    /// 그 값이 곧 최종값이고, 가로·아이패드는 화면 절반 상한을 모른 채 건 값이라 첫 레이아웃에서 한 번
    /// 바로잡힌다(첫 `viewWillLayoutSubviews`가 첫 렌더보다 앞선다 — 실기 실측: willLayout 24ms · 첫 렌더 39ms).
    ///
    /// 시스템이 이 값을 곧바로 반영하지도 않는다 — 등장 직전 입력 뷰를 제 기본 높이(실기에서는
    /// **화면 전체 852pt**)로 30~70ms 잡는다. 그 구간에도 자판이 흔들리지 않도록 SwiftUI 호스트를
    /// **아래 기준 고정 높이**로 묶고(`installKeyboardView`), 입력 뷰가 자판 사각형 밖을 칠하지
    /// 못하게 막는다(`ClickableInputView`).
    private func updateHeight(layoutNow: Bool = true) {
        applyHeightConstants()
    }

    /// 실제 값 갱신.
    private func applyHeightConstants() {
        let total = totalKeyboardHeight
        if let heightConstraint {
            if heightConstraint.constant != total { heightConstraint.constant = total }
        } else if view.window != nil || Self.pinHeightBeforeWindow {
            // **창이 붙기 전에도 만든다** (`pinHeightBeforeWindow`).
            // 애플 문서상 커스텀 키보드의 세로 크기는 이 제약으로 준다. 제약이 없으면
            // 등장 초기 레이아웃이 "높이를 모르는 상태"로 돈다(실기 `#heightPinned` 전부 −1).
            // 세로 아이폰에서는 이 값이 곧 최종값이고(상한에 걸리지 않는다), 가로·아이패드에서
            // 상한에 걸리는 경우는 첫 `viewWillLayoutSubviews`(첫 렌더 전)에서 바로잡힌다.
            let constraint = view.heightAnchor.constraint(equalToConstant: total)
            constraint.priority = .init(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
        if let hostHeightConstraint, hostHeightConstraint.constant != total {
            hostHeightConstraint.constant = total
        }
        (view as? ClickableInputView)?.preferredHeight = total
    }
}

// MARK: - 어댑터

/// 클릭음(`UIDevice.playInputClick`)이 나려면 루트 입력 뷰가 이 프로토콜을 채택해야 한다.
private final class ClickableInputView: UIInputView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }

    /// 키보드가 실제로 차지해야 하는 높이.
    ///
    /// 시스템은 등장 직전 입력 뷰를 **제 기본 높이**로 한두 패스 잡는다(아이폰 17 Pro 세로 실측
    /// 444pt — 우리 설정과 무관한 고정값). 그 패스에서 배경색이 자판 위 빈 영역까지 덮으면
    /// 화면 절반짜리 판이 한 프레임 번쩍인다. 그리는 영역을 **아래에서 이 높이만큼**으로 잘라
    /// 어느 패스에서도 자판 사각형 밖을 칠하지 않게 한다.
    var preferredHeight: CGFloat = 0 {
        didSet {
            guard preferredHeight != oldValue else { return }
            setNeedsLayout()
        }
    }

    /// 자판 사각형에 칠할 테마 색. **크기가 맞을 때만** 실제로 칠한다 — 시스템이 이 뷰를
    /// 화면 전체 높이로 잡는 구간(실기 852pt·30~70ms)에 칠하면 화면을 덮는 판이 된다.
    var themeBackground: UIColor? {
        didSet { setNeedsLayout() }
    }

    private let bottomMask = CALayer()

    /// **15차** — 과대 구간에 실제로 칠할 **불투명** 테마 색. 테마 색을 아직 못 받았거나
    /// 알파를 못 읽으면 `nil`을 돌려 **거짓으로 불투명을 선언하지 않게** 한다
    /// (검증자가 본 "opq=1인데 bgA=−1" 모순을 만들지 않는다).
    private var opaqueThemePaint: UIColor? {
        guard let base = themeBackground else { return nil }
        let resolved = base.resolvedColor(with: traitCollection)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a), a > 0 else { return nil }
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }


    override func layoutSubviews() {
        super.layoutSubviews()
        // 마스크는 애니메이션 대상이 아니다 — 등장 중 한 프레임 늦으면 의미가 없다
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // 높이가 맞는 평상시에는 마스크를 걸지 않는다 — 마스크는 오프스크린 합성을 부르므로
        // 키 입력마다 다시 그리는 자판에 상시로 얹을 것이 아니다.
        let sized = preferredHeight > 0 && abs(bounds.height - preferredHeight) <= 0.5
        // **15차 — 과대 구간에서는 자르지 않고 실제로 칠한다.**
        // 시스템이 입력 뷰를 우리 높이보다 **크게** 잡는 구간(실기 852pt)이 여기다.
        // 예전에는 배경을 `.clear`로 두고 바닥 기준 마스크로 위를 잘라 냈다 —
        // 그래서 H1이 호스트를 852pt로 키워도 화면에 닿는 높이는 310pt 그대로였다.
        let oversized = preferredHeight > 0 && bounds.height > preferredHeight + 0.5
        if KeyboardViewController.unmaskWhileOversized, oversized {
            if layer.mask != nil { layer.mask = nil }          // 자르지 않는다
            // **16차** — 칠하지도 않는다. 투명한 채로 두면 컴포지터가 그 자리에 시스템 백드롭을 그린다.
            // 15차는 여기서 불투명 테마색을 칠했고, 그것이 검증자가 실측한 555pt 단색의 한 축이다.
            let paint: UIColor?
            if KeyboardViewController.transparentAboveContent {
                paint = nil                                   // 진짜 투명 — 단색 금지
            } else {
                paint = opaqueThemePaint                      // 15차 동작
            }
            if backgroundColor != paint { backgroundColor = paint }
            // 실제로 불투명하게 칠했을 때만 불투명이라고 선언한다.
            // 16차에서는 칠하지 않으므로 `isOpaque`도 거짓이다 — 그래야 컴포지터가 뒤를 그린다.
            let reallyOpaque = (paint != nil)
            if isOpaque != reallyOpaque { isOpaque = reallyOpaque }
            return
        }
        // 크기가 맞을 때만 칠한다. 마스크와 중복이지만 의도적이다 — 한 겹에만 기대지 않는다.
        var wanted: UIColor = sized ? (themeBackground ?? .clear) : .clear
        if backgroundColor != wanted { backgroundColor = wanted }
        // `UIInputView`는 자기를 불투명으로 표시한다. 마스크를 건 채 불투명이라고 말하는 것은
        // 모순이라 합성기가 잘려 나간 자리를 어떻게 그릴지 보장하지 못한다 — 크기가 어긋난
        // 동안에는 불투명 주장을 내린다.
        if isOpaque != sized { isOpaque = sized }
        guard preferredHeight > 0, !sized else {
            if layer.mask != nil { layer.mask = nil }
            return
        }
        // **여기는 Slide Over 경로다** (`unmaskWhileOversized`가 켜져 있으면 과대 구간은 위에서
        // 이미 돌아갔다). 시스템이 입력 뷰를 우리 높이보다 **작게** 잡는 경우 —
        // 넘치는 콘텐츠가 호스트 앱 위로 새지 않게 bounds로 자른다.
        // 그 경우 `visible == bounds.height`라 이 마스크는 곧 bounds 전체다(위를 잘라내지 않는다).
        let visible = min(preferredHeight, bounds.height)
        bottomMask.backgroundColor = UIColor.black.cgColor
        bottomMask.frame = CGRect(x: 0, y: bounds.height - visible,
                                  width: bounds.width, height: visible)
        if layer.mask !== bottomMask { layer.mask = bottomMask }
    }
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

