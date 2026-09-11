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
    /// 100pt는 **아이폰에서 실제로 나오는 버튼 폭의 상한보다 크다**(폭 320~440pt · 도구 4~5개에서
    /// 67.5~97.5pt). 그래서 아이폰 도구 행은 이 상한에 걸리지 않고 지금 모습 그대로다 —
    /// 합의된 아이폰 레이아웃을 건드리지 않는다.
    public static let maxToolButtonWidth: CGFloat = 100
    /// 도구 버튼 사이 간격 (툴바 `HStack`의 spacing).
    public static let toolButtonSpacing: CGFloat = 10

    /// 도구 `count`개가 차지할 수 있는 최대 폭. 넘으면 가운데로 모은다.
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

    /// 자판 배열의 기준 열 수에서 곧바로 최대 폭을 낸다.
    public static func contentMaxWidth(for layout: LayoutDefinition) -> CGFloat {
        contentMaxWidth(units: layout.referenceUnits)
    }
}
