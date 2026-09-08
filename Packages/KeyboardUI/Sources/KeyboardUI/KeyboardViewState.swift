import Foundation
import Observation
import KeyboardCore
import TadakDomain

/// 자판 뷰가 구독하는 최소 상태.
///
/// 키 입력마다 바뀌는 것(조합 텍스트)은 여기 넣지 않는다 — 그건 문서로 바로 가고
/// 자판 뷰는 몰라도 된다. 여기 있는 값들은 드물게 바뀐다 (모드 전환, 시프트, 테마).
@Observable
public final class KeyboardViewState {

    public var layout: LayoutDefinition
    public var isShifted: Bool
    /// 캡스락 상태 — 시프트 키 아이콘(`capslock.fill`) 표시용. 조립 지점이 `refreshLayout`에서 넣는다.
    public var isCapsLocked: Bool = false
    public var themeSpec: ThemeSpec
    public var appearance: Appearance
    public var keyboardHeight: CGFloat
    public var showsKeyPreview: Bool
    public var needsInputModeSwitchKey: Bool
    /// 툴바에 띄울 채움글 후보. 트리거 근처에서만 nil↔값이 바뀌고
    /// 구독자는 툴바뿐이라 키캡 뷰 리빌드를 일으키지 않는다 (성능 규율 유지).
    public var snippetSuggestion: SnippetSuggestion?
    /// 추천단어 후보 (최대 3개). 채움글 칩이 있으면 조립 지점이 비워 넣는다 (칩만 표시).
    /// 구독자는 툴바뿐 — 키캡 리빌드 없음.
    public var wordSuggestions: [String]
    /// 클립보드에서 추출한 인증번호 — 칩에 값 그대로 표시된다. nil이면 칩 없음.
    public var pasteboardCode: String?
    /// 툴바 도구 행에 보일 도구들 — 조립 지점이 설정(disabledTools)·권한(FA) 필터 후 넣는다.
    /// 후보(칩·추천단어)가 하나라도 있으면 후보가 우선한다 (PDR toolbar-tools).
    public var visibleTools: [ToolbarTool]
    /// 자판 대신 이모지 그리드를 보여줄지.
    public var showsEmojiPanel: Bool
    /// 이모지 그리드의 최근 사용 행 — 세션 메모리 (조립 지점 관리).
    public var recentEmojis: [String]
    /// 자판 대신 클립보드 기록 패널을 보여줄지.
    public var showsClipboardPanel: Bool
    /// 클립보드 기록 (최근순) — 조립 지점이 App Group에서 읽어 넣는다.
    public var clipboardEntries: [String]
    /// 기록 설정이 켜져 있는지 — 패널 빈 상태 안내 문구 분기용.
    public var clipboardHistoryEnabled: Bool
    /// 입력란 `returnKeyType`에 따른 리턴 키 표시 (nil = 기본 ⏎). 배열은 그대로 두고 UI가 덮어쓴다.
    public var returnKey: ReturnKeyFace?

    public init(
        layout: LayoutDefinition,
        isShifted: Bool = false,
        themeSpec: ThemeSpec,
        appearance: Appearance = .system,
        keyboardHeight: CGFloat = 216,
        showsKeyPreview: Bool = true,
        needsInputModeSwitchKey: Bool = false,
        snippetSuggestion: SnippetSuggestion? = nil,
        wordSuggestions: [String] = [],
        pasteboardCode: String? = nil,
        visibleTools: [ToolbarTool] = [],
        showsEmojiPanel: Bool = false,
        recentEmojis: [String] = [],
        showsClipboardPanel: Bool = false,
        clipboardEntries: [String] = [],
        clipboardHistoryEnabled: Bool = true,
        returnKey: ReturnKeyFace? = nil
    ) {
        self.layout = layout
        self.isShifted = isShifted
        self.themeSpec = themeSpec
        self.appearance = appearance
        self.keyboardHeight = keyboardHeight
        self.showsKeyPreview = showsKeyPreview
        self.needsInputModeSwitchKey = needsInputModeSwitchKey
        self.snippetSuggestion = snippetSuggestion
        self.wordSuggestions = wordSuggestions
        self.pasteboardCode = pasteboardCode
        self.visibleTools = visibleTools
        self.showsEmojiPanel = showsEmojiPanel
        self.recentEmojis = recentEmojis
        self.showsClipboardPanel = showsClipboardPanel
        self.clipboardEntries = clipboardEntries
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.returnKey = returnKey
    }
}

/// 리턴 키 표시 — 라벨(검색·보내기…) 또는 심볼(✓). 둘 다 nil이면 기본.
public struct ReturnKeyFace: Equatable, Sendable {
    public let label: String?
    public let symbol: String?

    public init(label: String? = nil, symbol: String? = nil) {
        self.label = label
        self.symbol = symbol
    }

    public static let done = ReturnKeyFace(symbol: "checkmark")
    public static func text(_ label: String) -> ReturnKeyFace { ReturnKeyFace(label: label) }
}
