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
    /// 클립보드 기록(툴바 클립보드 도구). 끄면 저장분을 즉시 삭제한다 — 보안 규칙 조항.
    /// 전체 접근 필요 (PDR clipboard-history).
    public var clipboardHistoryEnabled: Bool
    /// 추천단어 학습 초기화 신호. 앱이 저장소를 비우며 +1 하면, 키보드가 설정 재로드에서
    /// 변화를 보고 엔진을 재생성한다(세션 메모리 폐기). 저장소만 비우면 살아 있는
    /// 프로세스가 다음 학습 때 옛 단어를 되살린다 — PDR settings-app 결정 4.
    public var learningResetToken: Int
    /// 채움글(트리거 → 전문 자동완성) 전체 스위치.
    public var snippetsEnabled: Bool
    /// 성경 채움글 삽입 시 머리말 `[창세기 1:1] `을 앞에 넣을지 (기본 켬). 설정 앱 성경 팩 상세의 스위치 (2026-09-07).
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
        clipboardHistoryEnabled: Bool = true,
        learningResetToken: Int = 0,
        snippetsEnabled: Bool = true,
        bibleSnippetPrefixEnabled: Bool = true,
        disabledSnippetPacks: [String] = [],
        defaultToolbarMode: ToolbarMode = .tools,
        enabledTools: [ToolbarTool] = ToolbarTool.allCases,
        disabledTools: [ToolbarTool] = [],
        toolOrder: [ToolbarTool] = ToolbarTool.allCases,
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
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.learningResetToken = learningResetToken
        self.snippetsEnabled = snippetsEnabled
        self.bibleSnippetPrefixEnabled = bibleSnippetPrefixEnabled
        self.disabledSnippetPacks = disabledSnippetPacks
        self.defaultToolbarMode = defaultToolbarMode
        self.enabledTools = enabledTools
        self.disabledTools = disabledTools
        self.toolOrder = toolOrder
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

public enum ToolbarTool: String, Codable, CaseIterable, Sendable {
    case dismiss
    /// 커서 왼쪽/오른콽 — 원래 `cursor` 하나였던 것을 둘로 나눴다 (사용자 요청 2026-09-03:
    /// 각각 끄고 순서를 바꿀 수 있게). 구 저장분의 "cursor"는 `decodeList`가 둘로 펼친다.
    case cursorLeft
    case cursorRight
    case clipboard
    case emoji

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
