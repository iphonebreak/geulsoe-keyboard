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
    /// 툴바에 띄울 채움글 후보. 단축어 근처에서만 nil↔값이 바뀌고
    /// 구독자는 툴바뿐이라 키캡 뷰 리빌드를 일으키지 않는다 (성능 규율 유지).
    public var snippetSuggestion: SnippetSuggestion?
    /// 추천단어 후보 (최대 3개). 채움글 칩이 있으면 조립 지점이 비워 넣는다 (칩만 표시).
    /// 구독자는 툴바뿐 — 키캡 리빌드 없음.
    public var wordSuggestions: [String]
    /// 툴바 붙여넣기 칩 — **인증번호 또는 복사한 일반 텍스트** 하나. nil이면 칩 없음.
    ///
    /// 2026-09-15 이전에는 `pasteboardCode: String?`(인증번호 전용)였다. 사용자 요구로
    /// 일반 텍스트도 칩이 되면서 **무엇을 보여 주고 무엇을 넣을지가 달라졌다** —
    /// 일반 칩은 보이는 것(잘린 미리보기)과 넣는 것(원문 전체)이 다르다. 그 둘을 문자열 하나로는
    /// 표현할 수 없어 값 타입으로 올렸다 (`KeyboardCore.PasteSuggestion`).
    public var pasteSuggestion: PasteSuggestion?
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

    // MARK: - 성경 검색 (v1.1.0 ①)

    /// 툴바 성경 배지에 띄울 결과 건수. **nil이면 배지 없음**(0건 포함).
    ///
    /// 조립 지점이 우선순위(채움글 칩 > 붙여넣기 칩 > 배지)를 이미 적용해 넣는다 —
    /// 뷰는 이 값이 있으면 그린다. **추천단어 개수 분기도 조립 지점이 같은 값으로 한다**
    /// (계획서 2-1: 두 곳에서 따로 계산하면 "배지는 없는데 추천단어는 2개"가 된다).
    public var bibleMatchCount: Int?
    /// 자판 대신 성경 검색 패널을 보여줄지.
    public var showsBibleSearchPanel: Bool
    /// 패널 머리 칩에 보이는 검색어 — 캐스케이드가 실제로 맞춘 구절이다.
    public var bibleSearchQuery: String
    /// 패널에 그릴 결과 행들 (랭킹 순). 조립 지점이 본문을 읽어 미리보기까지 만들어 넣는다.
    public var bibleSearchRows: [BibleSearchRow]

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
        pasteSuggestion: PasteSuggestion? = nil,
        visibleTools: [ToolbarTool] = [],
        showsEmojiPanel: Bool = false,
        recentEmojis: [String] = [],
        showsClipboardPanel: Bool = false,
        clipboardEntries: [String] = [],
        clipboardHistoryEnabled: Bool = true,
        returnKey: ReturnKeyFace? = nil,
        bibleMatchCount: Int? = nil,
        showsBibleSearchPanel: Bool = false,
        bibleSearchQuery: String = "",
        bibleSearchRows: [BibleSearchRow] = []
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
        self.pasteSuggestion = pasteSuggestion
        self.visibleTools = visibleTools
        self.showsEmojiPanel = showsEmojiPanel
        self.recentEmojis = recentEmojis
        self.showsClipboardPanel = showsClipboardPanel
        self.clipboardEntries = clipboardEntries
        self.clipboardHistoryEnabled = clipboardHistoryEnabled
        self.returnKey = returnKey
        self.bibleMatchCount = bibleMatchCount
        self.showsBibleSearchPanel = showsBibleSearchPanel
        self.bibleSearchQuery = bibleSearchQuery
        self.bibleSearchRows = bibleSearchRows
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
