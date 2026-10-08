import CoreGraphics
import KeyboardCore

/// 자판 영역의 치수 규칙. **KeyboardUI와 조립 지점(익스텐션)이 함께 본다** —
/// 조립 지점이 높이를 되짚을 때 UI가 실제로 그리는 폭과 다른 값을 쓰면 종횡비가 어긋난다.
/// 두 곳에 같은 상수를 복제하지 않으려고 여기 하나로 모았다.
///
/// **여기에 idiom 분기는 없다.** KeyboardUI는 아이패드를 모른다(의존성 규칙) — 전부 폭 규칙이고,
/// 아이폰 폭(320~440pt)은 모든 상한 아래라 아이폰에서는 어떤 규칙도 발동하지 않는다.
/// 아이폰이냐 아이패드냐를 판단하는 것은 조립 지점의 몫이다.
public enum KeyboardMetrics {

    // MARK: - 자판 그리드 (KeyboardRootView·KeyboardLayoutView가 실제로 쓰는 값)

    /// `KeyboardRootView`가 자판 좌우에 주는 여백(3+3).
    public static let horizontalPadding: CGFloat = 6
    /// `KeyboardLayoutView`의 키 사이 간격.
    public static let keySpacing: CGFloat = 5
    /// `KeyboardLayoutView`의 행 사이 간격.
    public static let rowSpacing: CGFloat = 7
    /// 자판 아래 여백.
    public static let bottomPadding: CGFloat = 4

    // MARK: - 길게 누르기

    /// 길게 누르기가 무장되기까지 누르고 있어야 하는 시간 — **키 대체 입력(문장부호 키 등)과 채움글 칩(U7)이 이 값 하나를 본다.**
    /// 둘로 갈리면 손 감각이 둘이 된다(PDR `external-snippet-packs.md` 10-6 ⑤ · AC-43). 스페이스 트랙패드 진입(400ms)은 다른 동작이라 별도다.
    static let longPressDelay: Duration = .milliseconds(450)

    // MARK: - 목표 종횡비

    /// 아이폰 기준 행 높이 — 216pt / 4행에서 나온 값(행 간격 제외). "아이폰에서 이 자판이 어떤
    /// 비율이었나"를 재는 자로만 쓴다.
    static let phoneRowHeight: CGFloat = 48.75
    /// 아이폰 기준 폭. 특정 기기를 지칭하는 게 아니라 위와 같은 **자**다 — 아이폰의 자판별
    /// 종횡비는 폭에 따라 조금씩 달라지므로 한 값으로 고정해 규칙을 결정적으로 만든다.
    static let phoneReferenceWidth: CGFloat = 393
    /// 10열 자판(두벌식·쿼티·기호)의 목표 종횡비. 시스템 아이패드 키보드는 1.03:1이지만 그건 열이
    /// 더 많기 때문이다 — 우리는 10열을 유지하므로 1.15까지만 좁힌다 (PDR ipad-support §1).
    static let baseKeyAspect: CGFloat = 1.15
    /// 목표 종횡비에서의 행 높이. 폭 상한은 이 높이에 목표 종횡비를 곱해 낸다.
    static let targetRowHeight: CGFloat = 73.8

    // MARK: - 계산

    /// 한 행의 키 폭(pt) — **화면(`KeyboardLayoutView.rowView`)이 쓰는 유일한 함수**다. 키는 `HStack(spacing: keySpacing)`으로 놓인다.
    ///
    /// 열 정렬 여부는 **배열(`layout.alignsColumns`)이 정한다** — 화면은 따로 boolean을 끼우지 않는다. 예전에는 `rowView`가
    /// `alignsColumns:` 인자를 넘겨서, 그 인자를 `false`로 바꿔도 테스트가 전부 녹색이었다(3차 개정, 반론자2 변이 M2).
    /// 그린 화면이 이 함수를 쓰는지는 `KeyboardRowRenderTests`가 픽셀로 본다.
    public static func keyWidths(row: [LayoutDefinition.Key], in layout: LayoutDefinition,
                                 totalWidth: CGFloat) -> [CGFloat] {
        keyWidths(units: row.map(\.width), totalWidth: totalWidth, alignsColumns: layout.alignsColumns)
    }

    /// 위 함수의 계산부 — 밖에서 boolean을 골라 부르지 못하게 감춘다.
    ///
    /// - `alignsColumns == false`(기본 — 두벌식·쿼티·천지인·단모음·쿼티형 기호): **옛 식 그대로**. 행마다 `간격 × (키 수 − 1)`을
    ///   먼저 빼고 남은 폭을 단위 비율로 나눈다. 키 수가 다른 행끼리는 경계가 조금씩 어긋나지만, 이 자판들의 키 폭을
    ///   바꾸는 것은 요청받지 않은 변화라 그대로 둔다.
    /// - `alignsColumns == true`(키패드 4페이지·자동 숫자 패드 — `LayoutDefinition.alignsColumns`): 키마다
    ///   **자리 = (W + 간격) × 단위 ÷ 행 단위 합**, 키 폭 = 자리 − 간격. 키 수와 무관하게 **같은 단위 경계가 같은 x**에 온다 —
    ///   반 칸 둘이 한 칸과 정확히 맞물려 숫자 4행의 `0`이 위 `2 5 8` 열에 선다(사장님 폰 세션 4-1 2차 2026-09-28). 키 폭 합 +
    ///   간격 합 = W 그대로다. 옛 식에서 밀린 양은 **배치마다 다르다**(반론자2 계산): 1차 숫자 4행 지구본 없음 왼쪽 **+5pt**
    ///   (@3x 15px — 사장님 폰), 지구본 있음 왼쪽 +3.75pt(중심 +3.125pt), 자동 숫자 패드(지구본 있음) 왼쪽 +3⅓pt.
    ///
    /// **음수 방어**: 등장 첫 레이아웃 패스에서는 `totalWidth`가 0으로 온다. 그대로 계산하면 음수 폭이 SwiftUI로 들어가
    /// `Invalid frame dimension`을 수십 줄 뱉고 자판이 빈 회색으로 떴다(2026-09-09) — 두 방식 모두 0으로 눌러 둔다.
    /// 폭이 확정되면 다음 패스에서 제대로 그려진다.
    private static func keyWidths(units: [Double], totalWidth: CGFloat, alignsColumns: Bool) -> [CGFloat] {
        let totalUnits = units.reduce(0, +)
        guard totalUnits > 0 else { return units.map { _ in 0 } }
        if alignsColumns {
            return units.map { unit in
                max(0, (totalWidth + keySpacing) * CGFloat(unit) / CGFloat(totalUnits) - keySpacing)
            }
        }
        let available = max(0, totalWidth - keySpacing * CGFloat(max(0, units.count - 1)))
        return units.map { available * CGFloat($0) / CGFloat(totalUnits) }
    }

    /// 주어진 자판 폭에서 문자 키 하나의 폭. `KeyboardLayoutView.rowView`와 같은 식이다.
    public static func keyWidth(availableWidth: CGFloat, units: Double) -> CGFloat {
        guard units > 0 else { return 0 }
        let u = CGFloat(units)
        return (availableWidth - horizontalPadding - keySpacing * (u - 1)) / u
    }

    /// 이 열 수에서의 **목표 키 종횡비**(폭 : 높이).
    ///
    /// 원칙 한 줄: **아이패드에서 키가 아이폰에서보다 더 납작해지지 않게 한다.**
    /// 단, 하한은 10열 기준값 1.15다 — 아이폰에서 이미 세로로 긴 자판(두벌식 0.72:1)을
    /// 아이패드에서 더 세로로 만들지는 않는다. 넓은 화면에서 10열을 그리는 이상 키는 가로로 길어진다.
    ///
    /// 왜 필요한가: 높이 공식이 **10열을 하드코딩**하고 있었다. 실제 키 폭은 행의 열 수에서
    /// 나오는데(`KeyboardLayoutView`), 높이는 언제나 "두벌식이었다면" 기준으로 정해졌다.
    /// 그래서 아이패드 세로에서 천지인(4열) 키가 203.5 × 69.0 = **2.95 : 1**까지 벌어졌다
    /// (검증자 실측 2026-09-09 UX-8). 10열 폭 상한만으로는 닫히지 않는다 —
    /// 900pt에서도 천지인은 219.75pt 키로 2.98:1이다.
    public static func targetKeyAspect(units: Double) -> CGFloat {
        let phoneAspect = keyWidth(availableWidth: phoneReferenceWidth, units: units) / phoneRowHeight
        return max(baseKeyAspect, phoneAspect)
    }

    /// 이 열 수에서 자판 영역이 가질 수 있는 **최대 폭**. 넘으면 가운데 정렬하고 좌우는 배경색으로 둔다.
    ///
    /// 10열에서 900pt가 나온다 — 아이패드 11인치 **세로**(834pt)는 이 아래라 이미 합의된 세로
    /// 레이아웃이 그대로 남고, 가로에서만 키가 무한정 넓어지는 것을 막는다.
    /// 4열(천지인)은 584pt, 8열(단모음) 720pt, 3열(숫자 패드) 587pt.
    public static func contentMaxWidth(units: Double) -> CGFloat {
        guard units > 0 else { return .greatestFiniteMagnitude }
        let u = CGFloat(units)
        let targetKeyWidth = targetRowHeight * targetKeyAspect(units: units)
        return targetKeyWidth * u + horizontalPadding + keySpacing * (u - 1)
    }

    // MARK: - 툴바 도구 행

    /// 툴바 도구 버튼 하나의 최대 폭.
    ///
    /// 도구 행은 남는 폭을 균등 분배하는데, 아이패드 가로(자판 폭 894pt)에서는 하나당 178pt가 돼
    /// **커서 ◀ 와 ▶ 사이가 181pt(약 4.8cm)까지 벌어진다** — 한 글자를 고치려고 손이 화면을
    /// 가로지르게 된다 (검증자 실측 REQ-4). 아이폰에서는 같은 두 버튼이 약 98pt다.
    ///
    /// 100pt는 **아이폰에서 실제로 나오는 버튼 폭의 상한보다 크다.** 그래서 아이폰 도구 행은
    /// 이 상한에 걸리지 않고 지금 모습 그대로다 — 합의된 아이폰 레이아웃을 건드리지 않는다.
    ///
    /// ## ★ 도구가 **6개**가 됐다 — 다시 계산했다 (2026-09-22, 검증자 #11)
    ///
    /// 예전 주석은 「도구 4~5개에서 67.5~97.5pt」라고 적었다. `.bibleSearch`가 들어와
    /// 최대 6칸이 됐으므로 다시 잰다(`(화면 폭 − padding 20 − 간격 10×(n−1)) ÷ n`):
    ///
    /// | 도구 수 | 폭 320pt | 폭 440pt |
    /// |---|---|---|
    /// | 4개 | 67.5 | 97.5 |
    /// | 5개 | 52.0 | 76.0 |
    /// | **6개(아이콘 5 + 배지 999+)** | **36.4** | **60.4** |
    ///
    /// **칸이 늘수록 버튼은 좁아지므로 6개는 상한에서 더 멀어진다** — 결론이 바뀌지 않고
    /// **더 강해진다.** (6칸일 때 여섯 번째는 아이콘이 아니라 **배지**다. 배지는 고유 폭 +
    /// `layoutPriority(1)`이라 균등 분배에 끼지 않으므로 나머지 다섯이 남은 폭을 나눈다.
    /// 배지 폭 **44.5pt**(한 자리)~68.1pt(`999+`)를 빼고 계산한 값이 위 표다.
    /// 44.5는 검증자 CoreText 계산 44.45pt를 반올림한 것이고, 같은 모형이 517건에 준 61.36pt가
    /// **실기 실측 61.0pt**와 0.36pt로 맞았다 — `KeyboardRootView.bibleBadge` 주석 참조.)
    ///
    /// ★ **상한이 실제로 걸리는 경우는 따로 있다** — 도구 수가 적을 때다.
    /// `w ≥ 100`은 `n ≤ (화면 폭 − 10) ÷ 110`에서 참이므로 **폭 320pt에서 n ≤ 2,
    /// 폭 440pt에서 n ≤ 3**이다. 즉 사용자가 도구를 두셋만 남겼을 때 상한이 일한다.
    /// 그것은 예전부터 그랬고 6개가 되며 달라진 것이 없다.
    public static let maxToolButtonWidth: CGFloat = 100
    /// 도구 버튼 사이 간격 (툴바 `HStack`의 spacing).
    public static let toolButtonSpacing: CGFloat = 10

    /// 도구 `count`개가 차지할 수 있는 최대 폭. 넘으면 가운데로 모은다.
    ///
    /// 6칸이면 **650pt**다 — 아이폰 자판 폭(최대 420pt)은 한참 아래라 아이폰에서는 안 걸리고,
    /// 아이패드 가로에서만 일한다(이 상한을 둔 본래 이유).
    public static func toolRowMaxWidth(count: Int) -> CGFloat {
        guard count > 0 else { return .greatestFiniteMagnitude }
        return CGFloat(count) * maxToolButtonWidth + CGFloat(count - 1) * toolButtonSpacing
    }

    // MARK: - 패널 목록 (UX-10)

    /// **아이폰 패널 폭의 천장.** 아이폰 자판 영역은 가장 넓은 기기(440pt)에서도 434pt다.
    /// 아이패드는 가장 좁은 자판(천지인 584pt)에서도 578pt다 — 500pt가 둘을 가른다.
    /// Split View로 폭이 이 아래로 줄면 아이폰과 같은 값을 쓴다(폭이 좁으면 규칙도 같다).
    public static let phonePanelWidthCeiling: CGFloat = 500

    /// 클립보드 기록 같은 패널 목록 행의 최소 높이.
    ///
    /// 상수(글자 15pt + 위아래 여백 9pt = **36pt**)일 때 아이패드에서는 같은 화면의 문자 키가
    /// 75pt인데 항목만 36pt였고, HIG 최소 터치 크기 44pt에 못 미쳤다 (검증자 실측 UX-10).
    /// 붙여넣을 항목을 고르는 목록이라 잘못 누르면 **원치 않는 텍스트가 문서에 들어간다.**
    /// 아이폰은 36pt 그대로다 — 아이폰만의 문제가 아니고, 아이폰 레이아웃은 합의된 값이다.
    public static func listRowMinHeight(panelWidth: CGFloat) -> CGFloat {
        panelWidth > phonePanelWidthCeiling ? 44 : 36
    }

    // MARK: - 툴바 후보 행 규칙 (테스트가 닿게 여기 둔다)

    /// 후보 닫기 ✕를 그리는가. 도구 행은 이 값의 **반대**일 때 그린다.
    ///
    /// ## ★ 배지는 보지 않는다 (사용자 결정 2026-09-21)
    ///
    /// 배지만 떠 있을 때는 ✕가 없어야 한다. 기획서가 *"✕를 없애면 도구 행에 못 돌아간다"* 며
    /// 유지를 권고했는데 **전제가 틀렸다** — 도구 행 조건이 배지를 보지 않으므로 배지 단독
    /// 상태에서는 `[도구 4개] [📖 N]`이 **한 줄에 함께** 그려진다. 커서·클립보드·이모지가
    /// 이미 화면에 있어 갇히지 않는다.
    ///
    /// 추천단어·채움글 칩·붙여넣기 칩의 ✕는 **그대로**다(2026-09-03 사용자 요청) —
    /// 그때는 후보가 도구 행 자리를 차지하므로 내릴 길이 ✕뿐이다.
    public static func showsDismissButton(
        hasSnippet: Bool, hasWords: Bool, hasPaste: Bool
    ) -> Bool {
        hasSnippet || hasWords || hasPaste
    }

    /// 후보 줄에 그릴 추천단어(이모지 칩 포함) — **붙여넣기 칩이 있으면 없다**(D18, 2026-10-06).
    ///
    /// 붙여넣기 칩이 있으면 그 줄은 `[칩][✕]`만이다(채움글 칩도 — `candidateRowSnippet`, D19). v1.2.0부터 둘이 한 줄에
    /// 함께 떠 `[복사됨][추천]×4[✕]`가 말줄임으로 안 보였다(실기 세션 1 K7). 조립 지점이 이미 후보를 비워
    /// 넘기지만(`WordSuggestionGate`의 `hasPasteChip`) 그림 쪽도 같은 규칙을 지킨다 — ✕를 누르면 칩이
    /// 물러나고 이 함수가 후보를 그대로 돌려준다.
    public static func candidateRowWords(
        _ words: [WordSuggestionCandidate], hasPaste: Bool
    ) -> [WordSuggestionCandidate] {
        hasPaste ? [] : words
    }

    /// 후보 줄에 그릴 채움글 칩(날짜·시간 칩 포함) — **붙여넣기 칩이 있으면 없다**(D19, 2026-10-06).
    ///
    /// 붙여넣기 칩이 먼저다 — `[붙여넣기][채움글][✕]`가 한 줄에 함께 떠 말줄임 위험이 있었다(D18 구현 중 발견).
    /// 조립 지점이 이미 비워 넘기지만(`SnippetChipGate`) 그림 쪽도 같은 규칙을 지킨다 — ✕로 붙여넣기 칩을 물리면
    /// 이 함수가 채움글 칩을 그대로 돌려주고, 칩은 평소처럼 아래에서 떠오른다.
    public static func candidateRowSnippet(_ snippet: SnippetSuggestion?, hasPaste: Bool) -> SnippetSuggestion? {
        hasPaste ? nil : snippet
    }

    /// 후보 줄에 성경 배지를 그리는가 — 붙여넣기 칩이 있으면 그리지 않는다(D18, `candidateRowWords`와 같은 이유).
    /// 조립 지점은 칩이 있으면 검색 예약부터 하지 않는다(배지 수 nil).
    public static func candidateRowShowsBadge(hasPaste: Bool) -> Bool {
        !hasPaste
    }

    /// 추천단어를 몇 개까지 띄울까 — **실제 배지 유무**로 갈린다.
    ///
    /// ## ★ 자리 예약을 되돌렸다 (2026-09-21 저녁 → 밤)
    ///
    /// 낮에는 성경 검색이 **켜져 있기만 하면** 배지 자리를 비워 두고 추천단어를 2개로 고정했다.
    /// 자리가 안 움직이는 대신 **배지가 없을 때 오른쪽이 비어 보였고**, 사용자가 실기에서
    /// 그것을 보고 되돌리라고 했다:
    ///
    /// > 「성경 키워드 개수가 0개일떄 … **기본적으로 3개가 나오도록** 하자
    /// >  성경 키워드 갯수가 1개 이상일떄에는 **추천단어 2개** 나오도록 하자」
    ///
    /// 그래서 **게이트가 아니라 배지 유무**로 정한다. 켠 사용자라도 결과가 0건이면 3개다.
    /// 되살아난 위험(배지가 뜰 때 자리가 움직인다)은 `KeyboardRootView.bibleBadge` 주석의 표에 있다.
    public static func wordSuggestionLimit(hasBadge: Bool) -> Int {
        hasBadge ? 2 : 3
    }

    /// 이모지 칩(혼합·전용)이 뜰 때의 단어 후보 개수 — **한 칸 적게**(PDR `emoji-word-suggestion.md` Q2).
    ///
    /// | | 이모지 없음(숨김 동안 포함, D3) | 이모지 있음 |
    /// |---|---|---|
    /// | 배지 없음 | 단어 3 | 단어 2 + `[🚗 자동차][🚗]` = 4칸 |
    /// | 배지 있음 | 단어 2 | 단어 1 + `[🚗 자동차 │ 🚗]`(둘째 칸을 반으로) = 2칸 |
    public static func wordSuggestionLimit(hasBadge: Bool, hasEmojiChips: Bool) -> Int {
        wordSuggestionLimit(hasBadge: hasBadge) - (hasEmojiChips ? 1 : 0)
    }

    /// 추천단어 칩 안쪽 좌우 여백 — **이모지 칩이 뜬 줄만 0**(D6 여백C: 칩 사이 간격 10pt는 그대로, 배지 반쪽 칩도 0).
    /// 이모지가 없는 3칩 줄은 지금 그대로 6이다. 글자는 기존 `minimumScaleFactor(0.7)`로 줄인다(4-5절).
    public static func wordChipHorizontalPadding(hasEmojiChips: Bool) -> CGFloat {
        hasEmojiChips ? 0 : 6
    }

    /// 후보를 칸으로 묶는다 — 칸 하나가 툴바의 균등 분배 단위다.
    /// 배지가 있을 때만 혼합·전용 두 이모지 칩이 **한 칸을 반씩** 나눈다(Q2 배지판·4-3절) — 단어 후보 칸이
    /// 0개로 떨어지지 않는다. 그 밖에는 후보 하나에 칸 하나(이모지가 없으면 v1.2.0과 같다).
    public static func wordChipSlots(_ candidates: [WordSuggestionCandidate], hasBadge: Bool) -> [[WordSuggestionCandidate]] {
        let emojiChips = candidates.filter { $0.emoji != nil }
        guard hasBadge, !emojiChips.isEmpty else { return candidates.map { [$0] } }
        return candidates.filter { $0.emoji == nil }.map { [$0] } + [emojiChips]
    }

    /// 자판 배열의 기준 열 수에서 곧바로 최대 폭을 낸다.
    public static func contentMaxWidth(for layout: LayoutDefinition) -> CGFloat {
        contentMaxWidth(units: layout.referenceUnits)
    }
}
