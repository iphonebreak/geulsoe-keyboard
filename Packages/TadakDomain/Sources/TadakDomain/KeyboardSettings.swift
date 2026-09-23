import Foundation

/// 설정 앱과 키보드 익스텐션이 공유하는 설정 스키마.
///
/// **동기화 방향은 단방향이다.** 설정 앱이 App Group에 쓰고, 키보드는 읽기만 한다.
/// App Group은 Full Access 없이도 **읽기**가 되기 때문에, 이 방향을 지키는 한
/// 사용자가 전체 접근을 꺼도 설정이 정상 반영된다. 익스텐션에서 쓰기를 추가하는 순간
/// 권한 분기가 따라붙으므로, 새 필드를 넣을 때 어느 쪽이 쓰는지 먼저 정한다.
public struct KeyboardSettings: Codable, Equatable, Sendable {

    // MARK: 자판

    public var enabledHangulLayouts: [HangulLayout]
    public var activeHangulLayout: HangulLayout
    /// 사용 안 함 — `keyboardHeightScale`로 대체됐다 (호환·마이그레이션 초기값용으로만 남긴다).
    public var keyboardHeight: KeyboardHeight
    /// 자판 높이 배율 (기본 1.0). 자판 216pt × 배율, 숫자 줄 44pt × 배율.
    /// 범위·clamp는 `heightScaleRange`/`clampedHeightScale`로 앱·익스텐션이 공유한다.
    public var keyboardHeightScale: Double

    /// 높이 배율 허용 범위 (설정 슬라이더·익스텐션 계산 공통 SSOT).
    public static let heightScaleRange: ClosedRange<Double> = 0.8...1.2

    /// 범위 밖 저장값(외부 쓰기 등)을 방어한 배율.
    public var clampedHeightScale: Double {
        min(max(keyboardHeightScale, Self.heightScaleRange.lowerBound), Self.heightScaleRange.upperBound)
    }
    /// 천지인 토글 확정까지 기다리는 시간(초)
    public var cheonjiinTimeout: TimeInterval
    /// 단모음 연타 승격(ㄱㄱ→ㄲ, ㅏㅏ→ㅑ)을 인정하는 시간(초)
    public var danmoeumTimeout: TimeInterval
    public var showsKeyPreview: Bool
    public var autoCapitalization: Bool
    /// 스페이스 두 번으로 마침표 입력
    public var doubleSpacePeriod: Bool
    /// 자판 상단 숫자 줄 (두벌식·단모음·쿼티 — 천지인·기호 제외, PDR toolbar-tools)
    public var numberRowEnabled: Bool
    /// 문자 키를 길게 눌러 기호 입력 (Gboard 배열 — 두벌식·단모음·쿼티, 천지인·기호 제외, PDR long-press-symbols).
    /// 기본 켬. 끄면 키 귀퉁이 힌트도 함께 사라진다.
    public var longPressSymbolsEnabled: Bool

    // MARK: 툴바

    public var suggestionsEnabled: Bool
    /// 복사한 인증번호를 툴바 칩으로 제안. **전체 접근이 있어야만 동작한다** —
    /// 없으면 조용히 비표시 (PDR verification-code-paste).
    public var verificationCodeSuggestionsEnabled: Bool
    /// 복사한 **일반 텍스트**를 툴바 칩으로 제안할지 (기본 켬, 2026-09-15 사용자 결정).
    ///
    /// `verificationCodeSuggestionsEnabled` 와 **따로 둔다.** 성격이 다르다 —
    /// 인증번호 칩은 숫자만 보이지만 이쪽은 **복사한 내용이 그대로 보인다.**
    /// 하나로 묶으면 "인증번호만 원하는" 사용자가 내용 노출을 끌 방법이 없어진다
    /// (설계 `docs/design-reviews/paste-chip-plan.md` C-5).
    public var pasteSuggestionEnabled: Bool
    /// 클립보드 기록(툴바 클립보드 도구). 끄면 저장분을 즉시 삭제한다 — 보안 규칙 조항.
    /// 전체 접근 필요 (PDR clipboard-history).
    public var clipboardHistoryEnabled: Bool
    /// 추천단어 학습 초기화 신호. 앱이 저장소를 비우며 +1 하면, 키보드가 설정 재로드에서
    /// 변화를 보고 엔진을 재생성한다(세션 메모리 폐기). 저장소만 비우면 살아 있는
    /// 프로세스가 다음 학습 때 옛 단어를 되살린다 — PDR settings-app 결정 4.
    public var learningResetToken: Int
    /// 채움글(단축어 → 전문 자동완성) 전체 스위치.
    public var snippetsEnabled: Bool
    /// 성경 채움글 삽입 시 머리말을 앞에 넣을지 (기본 켬). 설정 앱 성경 팩 상세의 스위치 (2026-09-07).
    /// 머리말은 사용자가 친 단축어 원문 그대로다 — `창세기 1장 1절`을 쳤으면 `[창세기 1장 1절] ` (2026-09-14).
    public var bibleSnippetPrefixEnabled: Bool
    /// 끈 내장 채움글 팩 id 목록 (`"bible"`, `"anthem"`). 옵트아웃이라 새 팩은 기본 켬.
    public var disabledSnippetPacks: [String]

    /// 성경 키워드 검색(툴바 배지 + 구절 패널). **기본값은 꺼짐**(사용자 결정 2026-09-19).
    ///
    /// ## ★ 왜 `ToolbarTool` 케이스가 아니라 독립 `Bool`인가
    ///
    /// `disabledTools`가 **옵트아웃**이라(끈 것만 담는다) 새 케이스를 더하면
    /// **기존 사용자 전원에게 기본 켬**으로 나타난다 — 저장분 4종으로 돌려서 확인했다(반론자1 B-3).
    /// 「기본 꺼짐」 결정과 정면으로 어긋난다.
    ///
    /// 독립 `Bool`이면 디코더의 `decodeIfPresent` + 기본값 패턴이 그대로 먹어
    /// **구 저장분은 자동으로 꺼짐**으로 읽힌다. 마이그레이션 플래그가 필요 없는 이유다
    /// (`toolOrderMigratedV101` 같은 것을 또 만들지 않는다).
    public var bibleSearchEnabled: Bool
    public var defaultToolbarMode: ToolbarMode
    /// 사용 안 함 — `disabledTools`로 대체됐다. 화이트리스트는 새 도구가 구 저장분에서
    /// 조용히 꺼지는 문제가 있다 (PDR toolbar-tools 결정 2). 디코딩 호환용으로만 남긴다.
    public var enabledTools: [ToolbarTool]
    /// 끈 툴바 도구 목록 — 옵트아웃이라 새 도구는 기본 켬.
    public var disabledTools: [ToolbarTool]
    /// 툴바 도구 표시 순서 (사용자 편집 가능). 목록에 없는 도구는 `orderedTools`가 뒤에 붙인다 —
    /// 새 도구가 추가돼도 구 저장분에서 사라지지 않는다.
    public var toolOrder: [ToolbarTool]
    /// v1.0.1 툴바 순서 1회성 전환을 마쳤는가.
    ///
    /// **한 번 `true`가 되면 `toolOrder`를 다시는 자동으로 건드리지 않는다.** 값 비교만으로
    /// 판단하면, 마이그레이션 뒤 사용자가 스스로 옛 순서로 되돌려 놓았을 때 그것을 "아직
    /// 전환 안 된 구 저장분"으로 오인해 매번 다시 바꿔 버린다(영구 고착).
    public var toolOrderMigratedV101: Bool

    /// v1.1.0에서 `.bibleSearch`를 **도구 순서에 끼워 넣는 전환**을 마쳤는가.
    ///
    /// ## ★ 이 플래그는 **고착 방어가 아니라 기록**이다 — `toolOrderMigratedV101`과 다르다
    ///
    /// v1.0.1 것은 **값 비교**(`toolOrder == legacyDefaultToolOrder`)라 플래그가 없으면
    /// 사용자가 손수 옛 순서로 되돌릴 때마다 다시 덮어쓴다(영구 고착). 그래서 거기선 필수였다.
    ///
    /// 이번 것은 **존재 판정**(`toolOrder.contains(.bibleSearch)`)이라 성질이 다르다 —
    /// **한 번 끼우면 스스로 조건을 거짓으로 만든다.** 사용자가 📖를 맨 앞으로 옮겨 둬도
    /// 여전히 「있다」라서 다시 안 건드린다. 그래서 판정은 플래그를 **보지 않고** 돌리고,
    /// 플래그는 *이 저장분이 전환을 겪었는가*를 **다음 판이 알 수 있게** 남기는 용도다.
    ///
    /// ★ 디코더 기본값은 **반드시 리터럴 `false`**다. `base.`를 쓰면 `.default`가 `true`라
    /// 구 저장분 전부가 「전환 완료」로 읽혀 기록이 거짓이 된다(아래 v1.0.1 주석이 같은 함정을 적는다).
    public var bibleSearchInToolOrderMigrated: Bool

    /// v1.0.0까지의 툴바 기본 순서. **마이그레이션 판정에만 쓴다 — 값을 바꾸지 마라.**
    ///
    /// `ToolbarTool.allCases`로는 이 값을 얻을 수 없다. `dismiss`를 맨 끝으로 옮기는 순간
    /// `allCases`는 새 순서를 돌려주기 때문에, 구 순서는 리터럴로 박아 두어야 한다.
    public static let legacyDefaultToolOrder: [ToolbarTool] =
        [.dismiss, .cursorLeft, .cursorRight, .clipboard, .emoji]

    /// ★ 구 저장분의 `toolOrder`에 `.bibleSearch`를 **이모지 바로 뒤**로 끼운다 (v1.1.0).
    ///
    /// ## 왜 마이그레이션이 **반드시** 필요한가
    ///
    /// `orderedTools`가 빠진 도구를 **무조건 뒤에 붙이므로**, 그냥 두면 현실적인 v1.0.1 저장분
    /// 전부에서 📖이 **맨 끝(내리기 뒤)** 으로 간다. 더 급한 것은 그것이 *화면에만* 있는 값이
    /// 아니라는 점이다 — `ToolbarOrderPreview`가 `orderedTools`를 그대로 `toolOrder`에 되쓰므로
    /// **사용자가 순서 편집을 한 번만 건드리면 끝자리가 영구 저장돼 나중에 못 고친다.**
    ///
    /// ## 왜 「이모지 앵커」인가 — `dismiss` 앵커를 버린 이유
    ///
    /// 「이모지와 내리기 사이」가 기본 자리인데, 둘 중 무엇을 기준으로 삼느냐가 갈린다.
    /// `dismiss` 앵커(내리기 **앞**)는 **내리기를 1번으로 옮겨 둔 사용자**에게서 📖를
    /// **순서의 맨 앞에 꽂는다.** 사용자가 손수 정한 1번 자리를 빼앗는 것이 끝자리보다 나쁘다.
    /// 이모지 앵커는 이모지가 어디 있든 **문자 그대로 그 바로 뒤**라 그런 일이 없다.
    ///
    /// ## 되돌아가는 자리
    ///
    /// 이모지를 끈 사용자도 `toolOrder`에는 이모지가 남아 있다(끔은 `disabledTools`다).
    /// 그래도 방어로 `dismiss` 앞 → 맨 뒤 순으로 물러난다.
    ///
    /// ## 스플라이스 방식을 **쓰지 않았다**
    ///
    /// 「`allCases` 순서를 기준으로 다시 짜기」는 현실 저장분에서 결과가 같지만
    /// **기존 도구의 상대 순서를 바꾼다**(부분 저장분에서 「내리기」가 3번 → 6번).
    /// 사용자가 고른 순서를 건드리지 않는 것이 이 함수의 유일한 목적이다.
    public static func insertingBibleSearch(into order: [ToolbarTool]) -> [ToolbarTool] {
        // ★ 이미 있으면 **그대로 둔다** — 사용자가 옮겨 둔 자리를 되돌리지 않는다.
        //   이 한 줄이 「존재 판정은 스스로 조건을 거짓으로 만든다」의 실체다.
        guard !order.contains(.bibleSearch) else { return order }
        var result = order
        if let emoji = result.firstIndex(of: .emoji) {
            result.insert(.bibleSearch, at: emoji + 1)
        } else if let dismiss = result.firstIndex(of: .dismiss) {
            result.insert(.bibleSearch, at: dismiss)
        } else {
            result.append(.bibleSearch)
        }
        return result
    }

    /// 저장된 순서 + 누락된 도구(신규) 보정. 중복은 첫 등장만 남긴다.
    public var orderedTools: [ToolbarTool] {
        var seen = Set<ToolbarTool>()
        let ordered = toolOrder.filter { seen.insert($0).inserted }
        return ordered + ToolbarTool.allCases.filter { !seen.contains($0) }
    }

    // MARK: 피드백 — 진동은 Full Access 필요. 소리는 번들 클릭음을 자체 재생한다
    //       (크기 조절 요구 — 시스템 playInputClick은 크기를 못 바꾼다. PDR feedback-intensity)

    public var hapticEnabled: Bool
    /// 진동 세기 0.2~1.0 — `UIImpactFeedbackGenerator.impactOccurred(intensity:)`에 그대로 준다
    public var hapticIntensity: Double
    public var keySoundEnabled: Bool
    /// 클릭음 크기 0.1~1.0 — 시스템 볼륨에 대한 상대값
    public var keySoundVolume: Double

    public static let hapticIntensityRange: ClosedRange<Double> = 0.2...1.0
    public static let keySoundVolumeRange: ClosedRange<Double> = 0.1...1.0

    public var clampedHapticIntensity: Double {
        min(max(hapticIntensity, Self.hapticIntensityRange.lowerBound), Self.hapticIntensityRange.upperBound)
    }

    public var clampedKeySoundVolume: Double {
        min(max(keySoundVolume, Self.keySoundVolumeRange.lowerBound), Self.keySoundVolumeRange.upperBound)
    }

    // MARK: 표시

    public var appearance: Appearance
    /// 적용할 테마 id. `ThemeRepository`에 없는 id면 구현이 `system`으로 폴백한다.
    public var selectedThemeID: String

    public init(
        enabledHangulLayouts: [HangulLayout] = [.dubeolsik],
        activeHangulLayout: HangulLayout = .dubeolsik,
        keyboardHeight: KeyboardHeight = .standard,
        keyboardHeightScale: Double = 1.0,
        cheonjiinTimeout: TimeInterval = 0.8,
        danmoeumTimeout: TimeInterval = 0.3,
        showsKeyPreview: Bool = true,
        autoCapitalization: Bool = true,
        doubleSpacePeriod: Bool = true,
        numberRowEnabled: Bool = false,
        longPressSymbolsEnabled: Bool = true,
        suggestionsEnabled: Bool = true,
        verificationCodeSuggestionsEnabled: Bool = true,
        pasteSuggestionEnabled: Bool = true,
        // **기본값이 끔이다** (사용자 결정 2026-09-11). 클립보드 기록은 사용자가 복사한 내용을
        // App Group에 남기는 유일한 경로 중 하나라, 켜는 것을 사용자가 **의식적으로 선택**하게 한다.
        //
        // 마이그레이션: 저장분에 이 키가 있으면 디코더가 그 값을 그대로 쓴다(`init(from:)` 참조).
        // 즉 **이미 켜 둔 사용자는 꺼지지 않는다.** 이 기본값은 키가 없는 경우에만 적용된다 —
        // 새 설치, 그리고 이 필드가 생기기 전(Phase 6 이전)의 저장분이다.
        clipboardHistoryEnabled: Bool = false,
        learningResetToken: Int = 0,
        snippetsEnabled: Bool = true,
        bibleSnippetPrefixEnabled: Bool = true,
        disabledSnippetPacks: [String] = [],
        bibleSearchEnabled: Bool = false,
        defaultToolbarMode: ToolbarMode = .tools,
        enabledTools: [ToolbarTool] = ToolbarTool.allCases,
        disabledTools: [ToolbarTool] = [],
        toolOrder: [ToolbarTool] = ToolbarTool.allCases,
        // 신규 설치는 처음부터 새 순서라 전환할 것이 없다 — 완료로 시작한다.
        toolOrderMigratedV101: Bool = true,
        // 같은 이유 — `allCases`에 `.bibleSearch`가 이미 들어 있다.
        bibleSearchInToolOrderMigrated: Bool = true,
        hapticEnabled: Bool = true,
        hapticIntensity: Double = 0.6,
        keySoundEnabled: Bool = false,
        keySoundVolume: Double = 0.7,
        appearance: Appearance = .system,
        selectedThemeID: String = "system"
    ) {
        self.enabledHangulLayouts = enabledHangulLayouts
        self.activeHangulLayout = activeHangulLayout
        self.keyboardHeight = keyboardHeight
        self.keyboardHeightScale = keyboardHeightScale
        self.cheonjiinTimeout = cheonjiinTimeout
        self.danmoeumTimeout = danmoeumTimeout
        self.showsKeyPreview = showsKeyPreview
        self.autoCapitalization = autoCapitalization
        self.doubleSpacePeriod = doubleSpacePeriod
        self.numberRowEnabled = numberRowEnabled
        self.longPressSymbolsEnabled = longPressSymbolsEnabled
        self.suggestionsEnabled = suggestionsEnabled
        self.verificationCodeSuggestionsEnabled = verificationCodeSuggestionsEnabled
        self.pasteSuggestionEnabled = pasteSuggestionEnabled
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.learningResetToken = learningResetToken
        self.snippetsEnabled = snippetsEnabled
        self.bibleSnippetPrefixEnabled = bibleSnippetPrefixEnabled
        self.disabledSnippetPacks = disabledSnippetPacks
        self.bibleSearchEnabled = bibleSearchEnabled
        self.defaultToolbarMode = defaultToolbarMode
        self.enabledTools = enabledTools
        self.disabledTools = disabledTools
        self.toolOrder = toolOrder
        self.toolOrderMigratedV101 = toolOrderMigratedV101
        self.bibleSearchInToolOrderMigrated = bibleSearchInToolOrderMigrated
        self.hapticEnabled = hapticEnabled
        self.hapticIntensity = hapticIntensity
        self.keySoundEnabled = keySoundEnabled
        self.keySoundVolume = keySoundVolume
        self.appearance = appearance
        self.selectedThemeID = selectedThemeID
    }

    /// 설정을 읽지 못했을 때 쓰는 기본값.
    ///
    /// 익스텐션 쪽에도 이 값이 있어야 App Group 접근이 실패해도 키보드가 동작한다.
    public static let `default` = KeyboardSettings()

    // MARK: - 구버전 호환 디코딩

    /// 필드를 추가할 때마다 여기서 `decodeIfPresent` + 기본값으로 읽는다.
    /// 사용자의 기기에 남아 있는 옛 JSON에는 새 키가 없다 — 일반 디코딩은 실패한다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let base = KeyboardSettings.default
        enabledHangulLayouts = try container.decodeIfPresent([HangulLayout].self, forKey: .enabledHangulLayouts) ?? base.enabledHangulLayouts
        activeHangulLayout = try container.decodeIfPresent(HangulLayout.self, forKey: .activeHangulLayout) ?? base.activeHangulLayout
        keyboardHeight = try container.decodeIfPresent(KeyboardHeight.self, forKey: .keyboardHeight) ?? base.keyboardHeight
        // 배율이 없는 구 저장분은 3단계 선택을 배율로 옮긴다 — 슬라이더의 5% 그리드에
        // 스냅해서 (compact 196/216→0.9, tall 244/216→1.15) 라벨이 "91%"처럼 어긋나지 않게
        // (PDR height-scale-and-feedback, 리뷰 반영)
        if let scale = try container.decodeIfPresent(Double.self, forKey: .keyboardHeightScale) {
            keyboardHeightScale = scale
        } else {
            let ratio = Double(keyboardHeight.points / KeyboardHeight.standard.points)
            keyboardHeightScale = (ratio / 0.05).rounded() * 0.05
        }
        cheonjiinTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .cheonjiinTimeout) ?? base.cheonjiinTimeout
        danmoeumTimeout = try container.decodeIfPresent(TimeInterval.self, forKey: .danmoeumTimeout) ?? base.danmoeumTimeout
        showsKeyPreview = try container.decodeIfPresent(Bool.self, forKey: .showsKeyPreview) ?? base.showsKeyPreview
        autoCapitalization = try container.decodeIfPresent(Bool.self, forKey: .autoCapitalization) ?? base.autoCapitalization
        doubleSpacePeriod = try container.decodeIfPresent(Bool.self, forKey: .doubleSpacePeriod) ?? base.doubleSpacePeriod
        numberRowEnabled = try container.decodeIfPresent(Bool.self, forKey: .numberRowEnabled) ?? base.numberRowEnabled
        longPressSymbolsEnabled = try container.decodeIfPresent(Bool.self, forKey: .longPressSymbolsEnabled) ?? base.longPressSymbolsEnabled
        suggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .suggestionsEnabled) ?? base.suggestionsEnabled
        verificationCodeSuggestionsEnabled = try container.decodeIfPresent(Bool.self, forKey: .verificationCodeSuggestionsEnabled) ?? base.verificationCodeSuggestionsEnabled
        pasteSuggestionEnabled = try container.decodeIfPresent(Bool.self, forKey: .pasteSuggestionEnabled) ?? base.pasteSuggestionEnabled
        clipboardHistoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? base.clipboardHistoryEnabled
        learningResetToken = try container.decodeIfPresent(Int.self, forKey: .learningResetToken) ?? base.learningResetToken
        snippetsEnabled = try container.decodeIfPresent(Bool.self, forKey: .snippetsEnabled) ?? base.snippetsEnabled
        bibleSnippetPrefixEnabled = try container.decodeIfPresent(Bool.self, forKey: .bibleSnippetPrefixEnabled) ?? base.bibleSnippetPrefixEnabled
        disabledSnippetPacks = try container.decodeIfPresent([String].self, forKey: .disabledSnippetPacks) ?? base.disabledSnippetPacks
        bibleSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .bibleSearchEnabled) ?? base.bibleSearchEnabled
        defaultToolbarMode = try container.decodeIfPresent(ToolbarMode.self, forKey: .defaultToolbarMode) ?? base.defaultToolbarMode
        // 도구 목록은 raw 문자열로 읽어 관대하게 매핑한다 (구 "cursor" → 왼쪽·오른쪽, 미지 값 무시)
        enabledTools = try container.decodeIfPresent([String].self, forKey: .enabledTools)
            .map(ToolbarTool.decodeList) ?? base.enabledTools
        disabledTools = try container.decodeIfPresent([String].self, forKey: .disabledTools)
            .map(ToolbarTool.decodeList) ?? base.disabledTools
        toolOrder = try container.decodeIfPresent([String].self, forKey: .toolOrder)
            .map(ToolbarTool.decodeList) ?? base.toolOrder
        // v1.0.1 툴바 순서 1회성 전환.
        //
        // 기본값이 `base`가 아니라 **리터럴 `false`**인 것이 핵심이다. `base`(= `.default`)는
        // 신규 설치용이라 이 플래그가 `true`이고, 그것을 기본값으로 쓰면 키가 없는 **구 저장분이
        // 전부 "전환 완료"로 읽혀** 마이그레이션이 아무에게도 걸리지 않는다.
        toolOrderMigratedV101 = try container.decodeIfPresent(Bool.self, forKey: .toolOrderMigratedV101) ?? false
        if !toolOrderMigratedV101 {
            // 구 기본값 그대로 쓰던 사용자만 새 기본값으로 옮긴다. 손수 바꾼 순서는 존중한다.
            // (구 저장분의 단일 "cursor" 표기는 위 `decodeList`가 이미 둘로 펼친 뒤라 비교가 성립한다.)
            if toolOrder == KeyboardSettings.legacyDefaultToolOrder {
                toolOrder = ToolbarTool.allCases
            }
            toolOrderMigratedV101 = true
        }
        // v1.1.0 — `.bibleSearch`를 이모지 바로 뒤로 끼운다.
        //
        // ★ **플래그를 보지 않고 돌린다.** 판정이 존재 여부라 이미 있으면 함수가 그대로 돌려주고,
        //   한 번 끼우면 다시는 발동하지 않는다(자기 조건을 스스로 거짓으로 만든다).
        //   플래그를 게이트로 쓰면 얻는 것 없이 「플래그만 참인데 도구는 빠진」 상태가 생길 수 있다.
        //   기본값이 리터럴 `false`인 이유는 위 v1.0.1 주석과 같다 — `base`는 `.default`라 참이다.
        bibleSearchInToolOrderMigrated =
            try container.decodeIfPresent(Bool.self, forKey: .bibleSearchInToolOrderMigrated) ?? false
        toolOrder = KeyboardSettings.insertingBibleSearch(into: toolOrder)
        bibleSearchInToolOrderMigrated = true
        hapticEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticEnabled) ?? base.hapticEnabled
        hapticIntensity = try container.decodeIfPresent(Double.self, forKey: .hapticIntensity) ?? base.hapticIntensity
        keySoundEnabled = try container.decodeIfPresent(Bool.self, forKey: .keySoundEnabled) ?? base.keySoundEnabled
        keySoundVolume = try container.decodeIfPresent(Double.self, forKey: .keySoundVolume) ?? base.keySoundVolume
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? base.appearance
        selectedThemeID = try container.decodeIfPresent(String.self, forKey: .selectedThemeID) ?? base.selectedThemeID
    }
}

public enum HangulLayout: String, Codable, CaseIterable, Sendable {
    case dubeolsik
    case cheonjiin
    case danmoeum

    public var displayName: String {
        switch self {
        case .dubeolsik: "두벌식"
        case .cheonjiin: "천지인"
        case .danmoeum: "단모음"
        }
    }

    /// 3x4 그리드 자판인가. 레이아웃 높이 산정이 달라진다.
    public var isGridLayout: Bool {
        self != .dubeolsik
    }
}

public enum KeyboardHeight: String, Codable, CaseIterable, Sendable {
    case compact, standard, tall

    /// 자판 영역 높이(pt). 툴바 높이는 별도로 더한다.
    public var points: CGFloat {
        switch self {
        case .compact: 196
        case .standard: 216
        case .tall: 244
        }
    }
}

public enum ToolbarMode: String, Codable, CaseIterable, Sendable {
    case tools
    case suggestions
}

/// **선언 순서가 곧 툴바 기본 순서다** — `toolOrder` 기본값이 `allCases`이기 때문이다.
/// 순서를 바꾸면 기존 사용자에게도 영향이 가므로 `KeyboardSettings.legacyDefaultToolOrder`와
/// 마이그레이션(`toolOrderMigratedV101`)을 함께 보라.
public enum ToolbarTool: String, Codable, CaseIterable, Sendable {
    /// 커서 왼쪽/오른콽 — 원래 `cursor` 하나였던 것을 둘로 나눴다 (사용자 요청 2026-09-03:
    /// 각각 끄고 순서를 바꿀 수 있게). 구 저장분의 "cursor"는 `decodeList`가 둘로 펼친다.
    case cursorLeft
    case cursorRight
    case clipboard
    case emoji
    /// 「단어로 구절 찾기」 배지 — **v1.1.0에서 도구 순서에 들어왔다** (사용자 지시 2026-09-21).
    ///
    /// ## ★ 선언 자리가 곧 기본 자리다
    ///
    /// `toolOrder` 기본값이 `allCases`라 **여기 있는 것만으로 신규 설치가 끝난다** —
    /// `[◀ ▶ 클립 이모지 📖 내리기]`. 기존 사용자는 그것으로 안 되므로
    /// `KeyboardSettings.insertingBibleSearch(into:)`가 따로 끼운다.
    ///
    /// ## ★ 이 케이스만 `disabledTools`를 타지 않는다
    ///
    /// 켜고 끄는 것은 **채움글 > 성경 > 「단어로 구절 찾기」**가 정한다(`bibleSearchEnabled`).
    /// `disabledTools`는 옵트아웃이라 여기에 얹으면 「기본 꺼짐」 결정과 어긋난다.
    /// 판정은 `isToggleableInSettings`가 한 곳에서 한다.
    case bibleSearch
    /// 맨 끝 — v1.0.1에서 옮겼다 (사용자 요청: 자주 쓰는 도구를 앞으로).
    case dismiss

    /// Full Access 없이 동작하는가.
    ///
    /// `clipboard`만 권한이 필요하다 (없으면 버튼 자체를 숨긴다). `emoji`는 입력 자체가
    /// 권한 없이 되고, 최근 사용은 세션 메모리라 권한 무관 (PDR toolbar-tools).
    ///
    /// ★ **화이트리스트로 바꾸지 마라.** `bibleSearch`는 번들 `bible.tdb`를 mmap으로 읽을 뿐이라
    /// 권한이 필요 없는데, 목록 방식으로 바꾸면서 빠뜨리면 **전체 접근을 끈 사용자에게서
    /// 📖 자리가 조용히 사라진다.** `ToolbarToolTests`가 이것을 잠근다.
    public var worksWithoutFullAccess: Bool {
        self != .clipboard
    }

    /// 설정 앱 순서 편집에서 **눌러서 끌 수 있는가.**
    ///
    /// `bibleSearch`만 거짓이다 — 그 도구의 on/off는 `disabledTools`가 아니라
    /// **채움글 > 성경 > 「단어로 구절 찾기」**(`bibleSearchEnabled`)가 정한다.
    /// 툴바 탭에 성경 스위치를 두지 말라는 사용자 지시(2026-09-21)가 있어 여기서는
    /// **끌 수 없다.** 설명 줄도 2026-09-22에 사용자 지시로 지웠다 — 대신 **꺼져 있으면
    /// 스트립에 아예 안 보인다**(`toolsShownInOrderEditor`).
    public var isToggleableInSettings: Bool {
        self != .bibleSearch
    }


    /// 설정 앱 행·키보드 접근성 라벨 공용. **도구 이름의 출처다.**
    ///
    /// ## ★ 「유일한 자리」가 아니다 — 사실대로 적는다 (2026-09-22 정정)
    ///
    /// 예전 주석은 *"이 저장소에서 도구 이름이 나오는 유일한 자리 · 박힌 문자열 0건"*이라고
    /// 단언했는데 **틀렸다**(검증자 지적). 지금 이 값을 **읽어 쓰는 곳**과
    /// **글자로 남아 있는 곳**은 이렇다:
    ///
    /// | 어디 | 어떻게 |
    /// |---|---|
    /// | 키보드 툴바 버튼 접근성 라벨 | 읽어 쓴다 |
    /// | 설정 앱 순서 편집 스트립(아이콘 라벨·이름표) | 읽어 쓴다 |
    /// | 성경 배지 낭독(`BibleCountText.badgeAccessibilityLabel`) | 읽어 쓴다 |
    /// | 채움글 > 성경의 「단어로 구절 찾기」 스위치 제목 | 읽어 쓴다 (2026-09-22부터) |
    /// | UITests 배지 술어·자판 판별 | 읽어 쓴다 (2026-09-22부터) |
    /// | 채움글 > 성경 **푸터 문장** 안의 「단어로 구절 찾기」 | ★ **글자로 남아 있다** |
    ///
    /// 마지막 하나는 **문장 안이라 일부러 남겼다** — 이름을 보간하면 **조사가 따라가지 못한다**
    /// (지금은 받침 없는 「기」라 「도」가 맞지만 이름이 받침으로 끝나면 깨진다).
    /// 이름을 바꾸면 그 줄은 **사람이 읽고 고쳐야 한다.**
    ///
    /// ## 커서 두 개의 문구 이력 — **세 번째로 바꾸는 사람을 위해**
    ///
    /// | 언제 | 무엇 | 왜 |
    /// |---|---|---|
    /// | 2026-09-08 | 「커서 왼쪽으로」 → **「왼쪽으로 커서 이동」** | 방향이 먼저 와야 읽힌다 |
    /// | **2026-09-22** | 「오른쪽으로 커서 이동」 → **「우측 커서 이동」**(좌측도 같이) | **도구가 6개가 되며 SE에서 잘렸다** |
    ///
    /// 두 번째 개정의 근거는 **우리가 만든 잘림**이다 — `.bibleSearch`를 넣어 스트립이 6칸이
    /// 되면서 SE(375pt)에서 칸 폭이 좁아졌고, 검증자가 **실화면**에서
    /// 「오른쪽으로/로 커서…」가 잘리는 것을 확인했다
    /// (`docs/release/verify-v110-copytrim.md` 0-2절, 증거
    /// `qa-evidence/verify-v110-copytrim/02-se-six-tools-truncated.png`).
    /// 텍스트 폭 실측: 최장 토막이 「오른쪽으로」 **47.6pt** → 「우측」 **19.0pt**.
    ///
    /// ★ **📖이 꺼진 사용자(5칸)는 잘리지 않았다.** 즉 이름이 나빠서가 아니라 **칸이 늘어서**다.
    /// 이름을 되돌리려면 먼저 칸 수를 5로 되돌리거나 스트립 레이아웃을 바꿔야 한다.
    public var displayName: String {
        switch self {
        case .dismiss: "키보드 내리기"
        case .cursorLeft: "좌측 커서 이동"
        case .cursorRight: "우측 커서 이동"
        case .clipboard: "클립보드"
        case .emoji: "이모지"
        // 설정 앱 채움글 > 성경의 스위치와 **같은 이름**이다 — 켜는 곳을 찾을 수 있어야 한다.
        //
        // ★ 「구절 찾기」에서 바꿨다 (사용자 지시 2026-09-22). 그 이름은 **주소로 찾는
        //   단축어와 구분이 안 됐다** — 이 기능의 정체는 「단어로」다.
        //   「성경」을 넣지 않는다: 도구 목록에서는 📖 아이콘이, 성경 화면에서는 제목이 그 몫을 한다.
        case .bibleSearch: "단어로 구절 찾기"
        }
    }

    /// SF Symbol 이름 — 키보드 툴바 도구 버튼과 설정 앱 도구 행이 같은 아이콘을 쓴다 (사용자 요청 2026-09-08).
    public var symbolName: String {
        switch self {
        case .dismiss: "keyboard.chevron.compact.down"
        case .cursorLeft: "chevron.left"
        case .cursorRight: "chevron.right"
        case .clipboard: "doc.on.clipboard"
        case .emoji: "face.smiling"
        // 툴바 배지(`KeyboardRootView.badgeCapsule`)와 같은 기호
        case .bibleSearch: "book"
        }
    }

    /// 저장된 도구 목록을 관대하게 디코딩한다 — 모르는 값은 버리고(미래 스키마), 구 값
    /// `"cursor"`는 왼쪽·오른쪽 둘로 펼친다. 배열 디코딩이 한 원소 때문에 통째로 실패해
    /// 설정 전체가 기본값으로 떨어지는 일을 막는다.
    static func decodeList(_ rawValues: [String]) -> [ToolbarTool] {
        rawValues.flatMap { raw -> [ToolbarTool] in
            if raw == "cursor" { return [.cursorLeft, .cursorRight] }
            return ToolbarTool(rawValue: raw).map { [$0] } ?? []
        }
    }
}

public enum Appearance: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

public extension KeyboardSettings {

    /// ★ 성경 검색 **합성 게이트** — 지금 검색이 동작해도 되는가.
    ///
    /// 넷이 **모두 참**이어야 한다. 하나라도 거짓이면 스캔 0회·배지 없음·열린 패널 즉시 닫힘.
    ///
    /// | 게이트 | 왜 |
    /// |---|---|
    /// | `bibleSearchEnabled` | 사용자 스위치. **기본 꺼짐**(사용자 결정 2026-09-19) |
    /// | `snippetsEnabled` | 성경 검색은 채움글의 성경 팩 위에 선다 — 채움글을 끄면 함께 꺼진다 |
    /// | 성경 팩이 켜져 있음 | `disabledSnippetPacks`에 `bible`이 없어야 한다 |
    /// | secure가 아님 | 비밀번호 칸에서는 매칭·표시를 하지 않는다(보안 규칙) |
    ///
    /// ## ★ 왜 조립 지점이 아니라 여기 있나 (검증자 2절)
    ///
    /// 예전에는 이 식이 `KeyboardViewController`에 있었다. 익스텐션 타깃은 `swift test`가
    /// 닿지 않아서 **테스트가 같은 식을 복제**했고, 그러면 *"프로덕션을 고쳐도 테스트가 전부
    /// 통과한다"* — 단언 12개 중 프로덕션 논리를 지키는 것이 **0개**였다.
    /// 식을 도메인으로 옮겨 테스트가 **이 함수를 직접** 부른다.
    ///
    /// ## ★ `isSecureTextEntry`가 `Bool?`인 이유
    ///
    /// `UITextDocumentProxy.isSecureTextEntry`는 옵셔널이고, **nil은 「secure 아님」으로 본다**
    /// (모르면 막지 않는다 — 다른 게이트 셋이 이미 닫혀 있다). 예전 테스트는 `Bool`만 돌려
    /// **nil 경로가 비어 있었다.** 그 구분을 서명에 남긴다.
    func allowsBibleSearch(isSecureTextEntry: Bool?) -> Bool {
        bibleSearchEnabled
            && snippetsEnabled
            && !disabledSnippetPacks.contains(SnippetPack.bible)
            && isSecureTextEntry != true
    }

    /// ★ 툴바 도구 행에 **실제로 그릴 도구 목록** (v1.1.0).
    ///
    /// 사용자 편집 순서(`orderedTools`)에 세 가지 필터를 건다.
    ///
    /// | 필터 | 적용 대상 |
    /// |---|---|
    /// | 전체 접근 | `clipboard`만 권한이 필요하다 |
    /// | `disabledTools` | **끌 수 있는 도구 다섯**뿐 (옵트아웃) |
    /// | 합성 게이트 + 배지 유무 | `.bibleSearch` **전용** |
    ///
    /// ## ★ `.bibleSearch`가 `disabledTools`를 타지 않는 이유
    ///
    /// `disabledTools`는 옵트아웃이라(끈 것만 담는다) 새 케이스를 얹으면
    /// **기존 사용자 전원에게 기본 켬**으로 나타난다 — 「기본 꺼짐」 결정과 정면으로 어긋난다.
    /// 그래서 on/off는 채움글 > 성경이 정하고(`allowsBibleSearch`), 여기서는 **자리와 순서만** 준다.
    ///
    /// ## ★ 0건이면 **칸을 없앤다**
    ///
    /// 자리를 비워 두지 않는다. 사용자가 같은 날 추천단어 줄에서 빈 칸을 직접 물렸기 때문이다
    /// (`docs/design-reviews/bible-badge-slot-revert.md`).
    /// **그 대가로 도구 자리가 입력마다 움직인다** — 알고 고른 것이고, 되돌아갈 후보(빈 칸 유지)는
    /// `docs/design-reviews/bible-badge-tool-order.md`에 있다.
    ///
    /// ## ★ 어긋난 저장분은 **무해하게 둔다**
    ///
    /// `bibleSearchEnabled`가 참인데 `disabledTools`에 `bibleSearch`가 들어 있는 저장분이
    /// 생길 수 있다(손으로 고친 App Group, 미래 스키마). 디코더에서 지우지 않는다 —
    /// 조용히 사용자 데이터를 지우면 나중에 복구할 근거가 사라진다. **읽는 쪽에서 무시**한다.
    ///
    /// ## ★ 왜 조립 지점이 아니라 여기 있나
    ///
    /// `allowsBibleSearch`와 같은 이유다 — 익스텐션 타깃은 `swift test`가 닿지 않아
    /// 거기 두면 테스트가 식을 복제하고, 그러면 프로덕션을 고쳐도 테스트가 전부 통과한다.
    ///
    /// - Parameter hasBibleBadge: 지금 배지에 띄울 건수가 **있는가**(0건이면 거짓).
    func visibleTools(
        hasFullAccess: Bool,
        isSecureTextEntry: Bool?,
        hasBibleBadge: Bool
    ) -> [ToolbarTool] {
        orderedTools.filter { tool in
            guard tool.worksWithoutFullAccess || hasFullAccess else { return false }
            guard tool.isToggleableInSettings else {
                return hasBibleBadge && allowsBibleSearch(isSecureTextEntry: isSecureTextEntry)
            }
            return !disabledTools.contains(tool)
        }
    }

    /// ★ 설정 앱 **순서 편집 스트립에 보이는** 도구들 (사용자 지시 2026-09-22).
    ///
    /// 전날에는 꺼진 📖도 **흐리게** 보여 줬다(「켰을 때 어디 나타날지 미리 알 수 있다」).
    /// **사용자가 뒤집었다** — *「채움글 > 성경 > 단어로 구절 찾기에서 ON하면 보여주고
    /// OFF 하면 보여주지 말것」*. 그래서 꺼져 있으면 목록에서 **아예 빠진다.**
    ///
    /// 나머지 다섯은 꺼져도 보인다 — 그쪽은 **여기서** 켜고 끄므로 보여야 다시 켤 수 있다.
    /// 📖은 여기서 켤 수 없으니 보일 이유도 없다는 것이 이 차이의 근거다.
    ///
    /// ★ **「보인다」와 「저장된다」는 다르다.** 안 보이는 동안에도 `toolOrder`에는 남아 있어야
    /// 사용자가 끌어 둔 자리를 잃지 않는다 — `mergingHiddenTools(into:)`가 그것을 지킨다.
    func toolsShownInOrderEditor() -> [ToolbarTool] {
        orderedTools.filter { $0.isToggleableInSettings || bibleSearchEnabled }
    }

    /// ★★ 스트립에서 재배열한 결과를 **저장할 때** 쓸 전체 순서.
    ///
    /// ## 이것이 없으면 사용자가 옮겨 둔 자리를 잃는다 — 이 함수가 있는 이유
    ///
    /// 순서 편집은 화면에 **보이는 목록**을 재배열해 그대로 `toolOrder`에 쓴다.
    /// 📖이 꺼져 화면에서 빠진 동안 사용자가 다른 도구를 하나라도 끌면,
    /// 그 저장에서 **`.bibleSearch`가 배열에서 사라진다.** 그러면 다시 켰을 때
    /// `orderedTools`의 보정이 📖을 **맨 뒤로** 돌린다 — 끌어 둔 자리가 조용히 없어진다.
    ///
    /// ## ★ 무엇을 보장하고 무엇을 보장하지 않나 (검증자가 경계 9종을 돌려 확정, 2026-09-22)
    ///
    /// 예전 주석은 *「자리를 보존한다」*고만 적었다. **그 말은 넓다** — 아래가 정확한 계약이다.
    ///
    /// | | |
    /// |---|---|
    /// | **보장한다** | **절대 자리 번호**(원래 몇 번째였나) · 범위 초과 시 맨 뒤로 clamp · 숨은 항목 생존 · 디코더 마이그레이션과 무충돌 |
    /// | **보장하지 않는다** | **이웃 관계** · 중복·누락 입력 검증 |
    ///
    /// **「이웃 관계는 아니다」가 무슨 뜻인가.** 📖이 3번이고 그 앞이 「내리기」였다면,
    /// 사용자가 보이는 목록을 뒤섞은 뒤에도 📖은 **여전히 3번**이지만 그 앞은
    /// 「이모지」일 수 있다. 사용자가 *「내리기 옆에 뒀다」*고 기억한다면 그 기억은 깨진다.
    /// **자리 번호를 고른 것은 의도다** — 이웃을 좇으려면 안 보이는 도구가 보이는 도구들의
    /// 재배열을 따라 움직여야 하고, 그것은 사용자가 보지 못한 규칙이다.
    ///
    /// **중복·누락은 막지 않는다.** 그런 입력이 오면 결과에 그대로 남고,
    /// 저장 후 재디코딩에서 `orderedTools`가 **길이만 복구**한다(자리는 밀린다).
    /// 호출자가 정상 목록을 주는 것이 전제다 — 스트립은 항상 그렇게 준다.
    ///
    /// ## 어떻게
    ///
    /// 숨은 도구를 **원래 자리 번호에** 되꽂는다. `orderedTools` 순서로 돌기 때문에
    /// 숨은 것이 여럿이어도 앞에서부터 차례로 제자리에 들어간다.
    ///
    /// ★ **숨은 도구가 둘 이상인 경우는 지금 타입으로 도달할 수 없다** —
    /// `isToggleableInSettings`가 거짓인 케이스가 📖 하나뿐이다.
    /// **둘 이상이 되는 날**, 이 함수는 지금처럼 각자의 원래 번호에 꽂으면 된다(코드 변경 없음).
    /// 다만 그때는 **번호가 서로 밀려 뒤 도구가 한 칸씩 뒤로 간다** — 앞에서부터 꽂기 때문이다.
    /// 그 동작이 맞는지는 그때 정해야 하고, 지금 미리 정하지 않는다.
    ///
    /// - Parameter visibleOrder: 스트립이 만든 **보이는 도구들의** 새 순서.
    ///   중복·누락이 없다고 가정한다.
    func mergingHiddenTools(into visibleOrder: [ToolbarTool]) -> [ToolbarTool] {
        let shown = Set(toolsShownInOrderEditor())
        var result = visibleOrder
        for tool in orderedTools where !shown.contains(tool) {
            let original = orderedTools.firstIndex(of: tool) ?? result.count
            result.insert(tool, at: min(original, result.count))
        }
        return result
    }
}
