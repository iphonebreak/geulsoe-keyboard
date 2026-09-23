/// 성경 검색 화면이 **읽어 주는 문자열**의 출처.
///
/// ## ★ 왜 도메인에 있나 — 세 타깃이 같은 값을 봐야 한다
///
/// 이 값들은 **프로덕션이 그리고 UITests가 술어로 찾는다.** 그런데 둘은 서로를 못 본다 —
/// UITests는 앱 타깃 번들이고 `KeyboardUI`·`KeyboardCore`는 앱에만 링크된다.
/// 그래서 문자열이 양쪽에 **따로 박혔고**, 이름이 바뀔 때마다 한쪽만 고쳐져 깨졌다:
///
/// | 언제 | 무엇이 깨졌나 |
/// |---|---|
/// | 2026-09-22 오전 | 배지 술어 3곳이 옛 이름(`"성경 구절 "`)이라 **형광펜 8조합을 못 쟀다** |
/// | 2026-09-22 오후 | 책 필터 술어가 실제 라벨과 어긋나 **패널 책 필터를 검증 못 했다** |
///
/// **`TadakDomain`은 의존성 0이라 세 곳 모두가 본다** — `KeyboardCore`·`KeyboardUI`는 물론
/// `TadakUITests`도 2026-09-22부터 이것을 링크한다(`project.yml`).
/// 그러니 **여기 한 곳에 두면 갈릴 수가 없다.**
///
/// ★ 새 문자열을 UI 파일에 직접 박지 마라. 테스트가 찾아야 하는 것이면 여기로 올려라.
public enum BibleSearchText {

    /// 패널의 책 필터 줄이 읽어 주는 이름. 줄 전체가 **하나의 조절 가능한 요소**다
    /// (칩 하나하나는 접근성 트리에 없다 — `BibleSearchPanelView.bookFilterBar` 주석).
    public static let bookFilterLabel = "책 고르기"

    /// 책을 고르지 않았을 때의 필터 이름. 필터 줄의 **첫 항목**이고, 읽어 주는 값이
    /// 「전체, 517건, 4개 중 1번째」처럼 이 이름으로 시작한다.
    public static let allBooksName = "전체"

    /// 패널을 닫고 자판으로 돌아가는 막대.
    public static let backToKeyboardLabel = "자판으로 돌아가기"
}

public extension ToolbarTool {

    /// 성경 배지가 읽어 주는 문장의 **앞부분**(건수 앞까지).
    ///
    /// ## ★ 규약이 세 곳에 복제돼 있던 것을 여기로 모았다 (2026-09-22)
    ///
    /// 검증자가 짚었다 — 같은 식(`"…, "`)이 **세 번** 적혀 있었다:
    /// `UITests` 상수 · `KeyboardUI.BibleCountText` · 그 계약 테스트.
    /// 계약 테스트가 UITests 상수를 **참조하지 않고 세 번째로 다시 적어서**,
    /// *UITests만 혼자 고치면 어떤 테스트도 울지 않는* 상태였다.
    ///
    /// 「패키지 테스트가 앱 타깃 파일을 못 본다」는 한계는 진짜지만,
    /// **셋 다 `TadakDomain`은 본다.** 그래서 한계를 우회하지 않고 **출처를 아래로 내렸다.**
    ///
    /// 쉼표로 끊는 이유: 붙이면 *「단어로 구절 찾기」가 517건*으로 들려 뜻이 뒤집힌다.
    static var bibleBadgeLabelPrefix: String {
        "\(ToolbarTool.bibleSearch.displayName), "
    }
}
