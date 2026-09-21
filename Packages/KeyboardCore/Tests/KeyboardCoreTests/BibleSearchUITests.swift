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
