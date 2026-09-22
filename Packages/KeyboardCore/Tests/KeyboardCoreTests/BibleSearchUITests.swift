import Foundation
import HangulEngine
import Testing
import TadakDomain
@testable import KeyboardCore

// MARK: - 맞은 자리 창 (findings C-3)

@Suite("성경 미리보기 — 맞은 자리 창")
struct BibleVersePreviewTests {

    /// 고린도전서 13:4 — 「사랑」이 앞에 있는 경우
    private let early = "사랑은 오래 참고 사랑은 온유하며 투기하는 자가 되지 아니하며 사랑은 자랑하지 아니하며 교만하지 아니하며"
    /// 검색어가 **한참 뒤**에 있는 경우 — 머리부터 자르면 안 보인다
    private let late = "여호와께서 모세에게 일러 가라사대 이스라엘 자손에게 고하여 이르라 너희는 사랑으로 행하라"

    @Test("짧은 절은 그대로 둔다")
    func shortVerseIsUntouched() {
        let text = "믿음은 바라는 것들의 실상이요"
        #expect(BibleVersePreview.window(of: text, matching: "믿음") == text)
    }

    @Test("★ 검색어가 뒤에 있어도 창 안에 들어온다")
    func lateMatchIsVisible() {
        let window = BibleVersePreview.window(of: late, matching: "사랑")
        #expect(window.contains("사랑"))
        // 머리부터 잘랐다면 「여호와께서 모세에게…」로 시작한다
        #expect(!window.hasPrefix("여호와께서"))
        #expect(window.hasPrefix("…"))
    }

    @Test("검색어 앞 4자를 함께 보여 준다")
    func keepsLeadingContext() {
        let window = BibleVersePreview.window(of: late, matching: "사랑")
        // 「…너희는 사랑으로…」 — 앞 4자가 「는 사랑」이 아니라 검색어 **앞** 4자다
        #expect(window.contains("너희는 사랑"))
    }

    @Test("검색어가 앞에 있으면 머리부터 그대로 연다")
    func earlyMatchStartsAtHead() {
        let window = BibleVersePreview.window(of: early, matching: "사랑")
        #expect(window.hasPrefix("사랑은 오래"))
        #expect(!window.hasPrefix("…"))
    }

    @Test("잘린 쪽에만 줄임표가 붙는다")
    func ellipsisOnlyWhereTrimmed() {
        let window = BibleVersePreview.window(of: early, matching: "사랑")
        #expect(window.hasSuffix("…"))
    }

    @Test("본문에 검색어가 없으면 머리부터 자른다")
    func missingQueryFallsBackToHead() {
        let window = BibleVersePreview.window(of: early, matching: "없는낱말")
        #expect(window.hasPrefix("사랑은 오래"))
    }

    @Test("창 길이를 넘지 않는다")
    func respectsWindowLength() {
        let window = BibleVersePreview.window(of: late, matching: "사랑")
        // 양끝 줄임표 둘을 빼고 본문은 창 길이만큼
        #expect(window.replacingOccurrences(of: "…", with: "").count == BibleVersePreview.windowLength)
    }
}

// MARK: - 책 필터 · 주소 표기

@Suite("성경 검색 패널 표시")
struct BibleSearchPresentationTests {

    private func matches(_ triples: [(Int, Int, Int)]) -> [BibleVerseMatch] {
        triples.map { BibleVerseMatch(book: $0.0, chapter: $0.1, verse: $0.2) }
    }

    @Test("맨 앞은 전체, 건수는 결과 총합이다")
    func totalComesFirst() {
        let filters = BibleBookFilter.filters(for: matches([(1, 1, 1), (1, 2, 3), (45, 5, 5)]))
        #expect(filters.first?.book == nil)
        #expect(filters.first?.name == "전체")
        #expect(filters.first?.count == 3)
    }

    @Test("책은 건수 내림차순이다 — 성경순이면 많은 책이 스크롤 끝에 숨는다")
    func booksAreSortedByCount() {
        // 로마서 1건, 창세기 2건
        let filters = BibleBookFilter.filters(for: matches([(45, 1, 1), (1, 1, 1), (1, 2, 2)]))
        #expect(filters.map(\.book) == [nil, 1, 45])
        #expect(filters[1].name == "창세기")
        #expect(filters[1].count == 2)
    }

    @Test("건수가 같으면 성경순이다")
    func tiesBreakByBibleOrder() {
        let filters = BibleBookFilter.filters(for: matches([(45, 1, 1), (1, 1, 1)]))
        #expect(filters.map(\.book) == [nil, 1, 45])
    }

    @Test("결과가 없으면 필터도 없다")
    func emptyGivesNoFilters() {
        #expect(BibleBookFilter.filters(for: []).isEmpty)
    }

    @Test("전체 탭은 책 이름을 붙이고 책 탭은 장:절만 쓴다")
    func referenceDependsOnTab() {
        let row = BibleSearchRow(
            match: BibleVerseMatch(book: 46, chapter: 13, verse: 4),
            preview: "사랑은 오래 참고"
        )
        #expect(row.reference(includingBook: true) == "고전 13:4")
        #expect(row.reference(includingBook: false) == "13:4")
    }
}

/// ★ 책 필터 줄의 **접근성 이동 규칙** (2026-09-21).
///
/// 패널의 책 필터 줄은 VoiceOver에서 **하나의 조절 가능한 요소**다 — 위/아래 스와이프로
/// 책을 바꾼다(`BibleSearchPanelView.bookFilterBar`). 계획서가
/// *"한 칩씩 스와이프가 유일하면 실패"* 라고 못박은 항목을 닫은 것이다.
///
/// ★ **실제 낭독·이동은 확인하지 못했다**(실기·시뮬레이터 금지). 화면 없이 잠글 수 있는 것은
/// 이동 규칙과 읽어 줄 문자열뿐이라, 그 둘만 순수 함수로 내려 여기서 고정한다.
@Suite("성경 패널 책 필터 — 접근성 이동")
struct BibleBookFilterAdjustmentTests {

    /// 「사랑」 결과의 모양을 흉내 낸 필터 줄 — 전체 + 책 셋.
    private let filters = BibleBookFilter.filters(for: [
        BibleVerseMatch(book: 19, chapter: 1, verse: 1),
        BibleVerseMatch(book: 19, chapter: 2, verse: 1),
        BibleVerseMatch(book: 19, chapter: 3, verse: 1),
        BibleVerseMatch(book: 1, chapter: 1, verse: 1),
        BibleVerseMatch(book: 1, chapter: 2, verse: 1),
        BibleVerseMatch(book: 46, chapter: 13, verse: 4),
    ])

    @Test("줄 모양이 전체 → 건수 내림차순이다 — 이동 규칙의 전제")
    func filterOrder() {
        #expect(filters.map(\.name) == ["전체", "시편", "창세기", "고린도전서"])
        #expect(filters.map(\.count) == [6, 3, 2, 1])
    }

    @Test("위로 쓸면 다음 책, 아래로 쓸면 이전 책")
    func stepsForwardAndBack() {
        #expect(BibleBookFilter.neighbor(of: nil, in: filters, offset: 1)?.name == "시편")
        #expect(BibleBookFilter.neighbor(of: 19, in: filters, offset: 1)?.name == "창세기")
        #expect(BibleBookFilter.neighbor(of: 1, in: filters, offset: -1)?.name == "시편")
        #expect(BibleBookFilter.neighbor(of: 19, in: filters, offset: -1)?.name == "전체")
    }

    @Test("★ 끝에서는 멈춘다 — 순환하지 않는다")
    func stopsAtBothEnds() {
        // 맨 앞(전체)에서 더 뒤로 갈 곳이 없다
        #expect(BibleBookFilter.neighbor(of: nil, in: filters, offset: -1) == nil)
        // 맨 뒤(고린도전서)에서 더 앞으로 갈 곳이 없다
        #expect(BibleBookFilter.neighbor(of: 46, in: filters, offset: 1) == nil)
    }

    @Test("검색어가 바뀌어 고른 책이 사라져도 자리를 잃지 않는다 — 맨 앞에 선 것으로 본다")
    func unknownBookFallsBackToFirst() {
        #expect(BibleBookFilter.neighbor(of: 66, in: filters, offset: 1)?.name == "시편")
        #expect(BibleBookFilter.neighbor(of: 66, in: filters, offset: -1) == nil)
    }

    @Test("필터가 없으면 아무 데도 못 간다 — 빈 결과에서 터지지 않는다")
    func emptyFiltersGoNowhere() {
        #expect(BibleBookFilter.neighbor(of: nil, in: [], offset: 1) == nil)
        #expect(BibleBookFilter.spokenValue(of: nil, in: []) { "\($0)건" } == "")
    }

    @Test("★ 읽어 줄 값에 이름·건수·자리가 다 들어간다")
    func spokenValueIsUnderstandable() {
        #expect(
            BibleBookFilter.spokenValue(of: nil, in: filters) { "\($0)건" }
                == "전체, 6건, 4개 중 1번째"
        )
        #expect(
            BibleBookFilter.spokenValue(of: 19, in: filters) { "\($0)건" }
                == "시편, 3건, 4개 중 2번째"
        )
    }

    /// ★ 개수 표기는 **배지·칩과 같은 규칙**을 써야 한다 — 상한에 걸리면 「999건 이상」이다.
    /// (규칙 자체는 `BibleCountText`가 갖고 있고 KeyboardUI에 있다. 여기서는 주입만 확인한다.)
    @Test("상한에 걸린 건수는 호출자가 준 표기를 그대로 읽는다")
    func cappedCountUsesInjectedWording() {
        let big = BibleBookFilter.filters(for: (1...5).map {
            BibleVerseMatch(book: 19, chapter: 1, verse: $0)
        })
        let spoken = BibleBookFilter.spokenValue(of: nil, in: big) { _ in "999건 이상" }
        #expect(spoken == "전체, 999건 이상, 2개 중 1번째")
    }
}
