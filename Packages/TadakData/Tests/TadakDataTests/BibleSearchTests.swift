import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 성경 본문 검색 — 스캐너와 랭킹.
///
/// 기대값은 전부 **번들 `bible.tdb`의 실제 내용에서 뽑은 것**이고
/// `docs/design-reviews/v1.1.0-round2-findings.md` A-4·B절의 실측표와 일치한다.
@Suite("성경 검색 스캐너")
struct BibleSearchTests {

    private let repository = BundledBibleRepository()

    /// 넉넉한 상한 — 「사랑」 517건이 다 들어온다.
    private let all = 10_000

    // 개역한글 66권 순서
    private static let genesis = 1
    private static let romans = 45
    private static let firstCorinthians = 46
    private static let hebrews = 58

    // MARK: - 건수

    @Test("낱말이 든 절을 전부 찾는다", arguments: [
        ("태초에", 7),
        ("태초에 하나님이", 1),
        ("하나님이", 1031),
        ("사랑", 517),
        ("믿음", 225),
        ("소망", 97),
        ("사랑하", 349),
        ("사랑해", 0),
    ])
    func hitCount(query: String, expected: Int) {
        #expect(repository.search(query, limit: all).count == expected)
    }

    @Test("「태초에 하나님이」는 창세기 1장 1절 하나다")
    func genesisOneOne() {
        let matches = repository.search("태초에 하나님이", limit: all)
        #expect(matches == [BibleVerseMatch(book: Self.genesis, chapter: 1, verse: 1)])
    }

    @Test("공백을 포함한 원문 그대로 찾는다 — 붙여 치면 안 맞는다")
    func spaceIsLiteral() {
        // 「태초에하나님이」는 본문에 없다. 공백을 무시하는 정규화를 하지 않는다는 계약이다
        // (채움글 단축어와 다른 규칙 — 여긴 본문 검색이다).
        #expect(repository.search("태초에하나님이", limit: all).isEmpty)
    }

    // MARK: - 2글자 미만은 스캔하지 않는다

    @Test("2글자 미만은 스캔 자체를 돌리지 않는다", arguments: ["이", "주", "말", "", " "])
    func shortQueryIsRefused(query: String) {
        // 「이」는 24,640건(전체의 79.2%)이라 결과로서 의미가 없다 (findings A-4)
        #expect(repository.search(query, limit: all).isEmpty)
    }

    @Test("딱 2글자는 스캔한다")
    func twoCharactersAreScanned() {
        #expect(repository.search("사랑", limit: all).count == 517)
    }

    // MARK: - ★ 상한은 정렬 뒤에 건다

    @Test("상한은 정렬 뒤에 건다 — 성경순 338번째 고전 13:4가 살아남는다")
    func capAppliesAfterRanking() {
        let target = BibleVerseMatch(book: Self.firstCorinthians, chapter: 13, verse: 4)

        // 스캔 도중에 잘랐다면 성경순으로 338번째인 이 절은 후보에 아예 못 들어온다.
        #expect(repository.search("사랑", limit: 5).contains(target))
        #expect(repository.search("사랑", limit: 2).contains(target))
    }

    @Test("상한만큼만 돌려준다", arguments: [1, 5, 100])
    func capLimitsCount(limit: Int) {
        #expect(repository.search("사랑", limit: limit).count == limit)
    }

    @Test("상한이 0 이하면 빈 배열이다", arguments: [0, -1])
    func nonPositiveLimit(limit: Int) {
        #expect(repository.search("사랑", limit: limit).isEmpty)
    }

    // MARK: - 랭킹 (findings B 실측 목표)

    @Test("「사랑」에서 고린도전서 13:4가 2위 이내다")
    func loveRanking() {
        let rank = repository.search("사랑", limit: all)
            .firstIndex(of: BibleVerseMatch(book: Self.firstCorinthians, chapter: 13, verse: 4))
        #expect(rank != nil && rank! < 2)
    }

    @Test("「믿음」에서 히브리서 11:1이 1위다")
    func faithRanking() {
        #expect(
            repository.search("믿음", limit: all).first
                == BibleVerseMatch(book: Self.hebrews, chapter: 11, verse: 1)
        )
    }

    @Test("「소망」에서 로마서 15:13이 5위 이내다")
    func hopeRanking() {
        let rank = repository.search("소망", limit: all)
            .firstIndex(of: BibleVerseMatch(book: Self.romans, chapter: 15, verse: 13))
        #expect(rank != nil && rank! < 5)
    }

    @Test("정의형(낱말+은/는/이/가로 시작)이 앞선다")
    func definitionalComesFirst() {
        let top = repository.search("믿음", limit: 5)
        // 히브리서 11:1 「믿음은 바라는 것들의 실상이요…」
        #expect(top.first == BibleVerseMatch(book: Self.hebrews, chapter: 11, verse: 1))
        // 상위권이 전부 정의형이다 — 본문을 실제로 읽어 확인한다
        for match in top {
            let text = repository.text(book: match.book, chapter: match.chapter, verse: match.verse)
            #expect(text?.hasPrefix("믿음은") == true || text?.hasPrefix("믿음이") == true)
        }
    }

    @Test("같은 결과는 몇 번을 불러도 같다")
    func deterministic() {
        #expect(repository.search("소망", limit: 20) == repository.search("소망", limit: 20))
    }

    // MARK: - 편집 안내 절 34건은 결과에서 뺀다

    @Test("본문 대신 편집 안내가 든 절은 검색에 안 걸린다")
    func editorialNoticesAreExcluded() {
        // 34건의 본문은 `(없음)` 또는 `(N절에 포함되어 있음)` 이다
        // (docs/design-reviews/bible-curation-blocklist.md).
        #expect(repository.search("포함되어 있음", limit: all).isEmpty)

        // 「없음」은 **진짜 본문에도 90건 있다**(「…없음을…」). blocklist 13건만 빠지고
        // 나머지는 그대로 나와야 한다 — 모양이 겹친다고 본문을 지우면 안 된다.
        #expect(repository.search("없음", limit: all).count == 90)

        // 로마서 9:2는 blocklist 에 있다 — 조회로는 여전히 읽히지만 검색에는 안 나온다
        #expect(repository.text(book: Self.romans, chapter: 9, verse: 2) == "(1절에 포함되어 있음)")
        #expect(!repository.search("1절에", limit: all).contains(
            BibleVerseMatch(book: Self.romans, chapter: 9, verse: 2)
        ))
    }

    @Test("진짜 본문의 삽입구(괄호로 시작하는 절)는 안 빠진다")
    func realParentheticalVersesSurvive() {
        // 신명기 3:9 「(헤르몬산을 시돈 사람은 시룐이라 칭하고…)」 — 괄호로 시작하지만 본문이다
        let deuteronomy = 5
        #expect(repository.search("헤르몬산을", limit: all)
            .contains(BibleVerseMatch(book: deuteronomy, chapter: 3, verse: 9)))
    }

    // MARK: - 조사 결합 검사는 사라졌다 (2026-09-21)
    //
    // 여기 있던 24건(살려야 12 · 걸러야 12)과 한 번 훑기 API 테스트는 **말끝 떼기와 함께
    // 제거했다.** 그 테스트들이 고정하던 전제 — 「명사에는 조사가 붙고 동사 어간에는 안 붙는다」 —
    // 가 한국어에서 거짓임이 실측으로 드러났기 때문이다(「알았은」이 31,102절 중 1건 있어
    // 「알았」이 명사로 통과했고, 「을」·「은」은 관형사형 어미이기도 하다).
    // 근거: `docs/design-reviews/bible-suffix-strip-critique-A.md` 4-2절.
    //
    // 제거 전 상태의 기록은 `docs/release/qa-evidence/bible-search-noun-check/NOTES.md`에 남아 있다.

    // MARK: - 리소스가 없을 때

    @Test("리소스가 없으면 검색은 빈 배열이다 — 실패하지 않는다")
    func missingResource() {
        let empty = BundledBibleRepository(url: nil)
        #expect(empty.search("사랑", limit: all).isEmpty)
        #expect(empty.text(book: 1, chapter: 1, verse: 1) == nil)
    }
}
