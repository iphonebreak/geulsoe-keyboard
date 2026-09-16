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

    /// v1.0.0까지의 툴바 기본 순서. **마이그레이션 판정에만 쓴다 — 값을 바꾸지 마라.**
    ///
    /// `ToolbarTool.allCases`로는 이 값을 얻을 수 없다. `dismiss`를 맨 끝으로 옮기는 순간
    /// `allCases`는 새 순서를 돌려주기 때문에, 구 순서는 리터럴로 박아 두어야 한다.
    public static let legacyDefaultToolOrder: [ToolbarTool] =
        [.dismiss, .cursorLeft, .cursorRight, .clipboard, .emoji]

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
        defaultToolbarMode: ToolbarMode = .tools,
        enabledTools: [ToolbarTool] = ToolbarTool.allCases,
        disabledTools: [ToolbarTool] = [],
        toolOrder: [ToolbarTool] = ToolbarTool.allCases,
        // 신규 설치는 처음부터 새 순서라 전환할 것이 없다 — 완료로 시작한다.
        toolOrderMigratedV101: Bool = true,
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
        self.defaultToolbarMode = defaultToolbarMode
        self.enabledTools = enabledTools
        self.disabledTools = disabledTools
        self.toolOrder = toolOrder
        self.toolOrderMigratedV101 = toolOrderMigratedV101
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
    /// 맨 끝 — v1.0.1에서 옮겼다 (사용자 요청: 자주 쓰는 도구를 앞으로).
    case dismiss

    /// Full Access 없이 동작하는가.
    ///
    /// `clipboard`만 권한이 필요하다 (없으면 버튼 자체를 숨긴다). `emoji`는 입력 자체가
    /// 권한 없이 되고, 최근 사용은 세션 메모리라 권한 무관 (PDR toolbar-tools).
    public var worksWithoutFullAccess: Bool {
        self != .clipboard
    }

    /// 설정 앱 행·키보드 접근성 라벨 공용 (문구 개정 2026-09-08: "커서 왼쪽으로" → "왼쪽으로 커서 이동")
    public var displayName: String {
        switch self {
        case .dismiss: "키보드 내리기"
        case .cursorLeft: "왼쪽으로 커서 이동"
        case .cursorRight: "오른쪽으로 커서 이동"
        case .clipboard: "클립보드"
        case .emoji: "이모지"
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
