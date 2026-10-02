import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 띄어쓰기 무시 스캔 — 실데이터 `bible.tdb` 기준 (사용자 지시 2026-09-21).
///
/// > 「오래참음을 입력 하면 나오지 않고 오래 참음 이라고 타이핑 하면 나오는데
/// >  띄어쓰기를 해야 나온다 띄어쓰기 하지 않아도 나왔으면 좋겠다」
@Suite("성경 검색 띄어쓰기 무시")
struct BibleSpaceInsensitiveTests {

    private let repository = BundledBibleRepository()
    private let searcher: BundledBibleSearcher

    init() { searcher = repository.makeSearcher() }
    private let all = 10_000

    // MARK: - 사용자가 신고한 것

    @Test("★ 「오래참음」이 본문의 「오래 참음」을 찾는다")
    func findsSpacedPhrase() {
        // 본문에는 「오래 참」 20건 / 「오래참」 0건이다
        #expect(searcher.search("오래참음", limit: all).isEmpty)
        #expect(searcher.searchIgnoringSpaces("오래참음", limit: all).count == 9)
    }

    @Test("★ 「태초에하나님이」가 창세기 1:1을 찾는다")
    func findsGenesisWithoutSpace() {
        #expect(searcher.search("태초에하나님이", limit: all).isEmpty)
        let matches = searcher.searchIgnoringSpaces("태초에하나님이", limit: all)
        #expect(matches == [BibleVerseMatch(book: 1, chapter: 1, verse: 1)])
    }

    @Test("공백이 든 검색어도 같은 답을 낸다", arguments: ["오래참음", "오래 참음", "오래  참음"])
    func spacesInQueryDoNotMatter(query: String) {
        #expect(searcher.searchIgnoringSpaces(query, limit: all).count == 9)
    }

    // MARK: - 정확 스캔은 그대로다

    @Test("정확 스캔 결과가 하나도 안 바뀐다", arguments: [
        ("사랑", 517), ("믿음", 225), ("소망", 97), ("태초에", 7), ("하나님이", 1031),
    ])
    func exactSearchUnchanged(query: String, expected: Int) {
        #expect(searcher.search(query, limit: all).count == expected)
    }

    @Test("2글자 미만은 느슨 스캔도 안 돈다", arguments: ["이", "주", "", " ", "  "])
    func shortQueryRefused(query: String) {
        #expect(searcher.searchIgnoringSpaces(query, limit: all).isEmpty)
    }

    @Test("랭킹 규칙이 같다 — 「믿음」은 느슨으로도 히브리서 11:1이 1위")
    func rankingIsShared() {
        #expect(
            searcher.searchIgnoringSpaces("믿음", limit: all).first
                == BibleVerseMatch(book: 58, chapter: 11, verse: 1)
        )
    }

    @Test("편집 안내 절은 느슨 스캔에서도 빠진다")
    func editorialNoticesExcludedInLoose() {
        #expect(searcher.searchIgnoringSpaces("포함되어있음", limit: all).isEmpty)
    }

    /// ★ `maximumSkippedSpaces`는 **낱말 창 상한에서 파생된 값**이다 (2026-09-21 정정).
    ///
    /// 낱말 5개 사이에는 공백이 4개다. 예전 주석은 이것을 *"비용과 회수의 맞바꿈 지점"*이라고
    /// 적었는데 틀렸고, 3으로 줄이면 5낱말 질의가 **0% 발견**으로 떨어진다(반론자1 실측).
    ///
    /// `KeyboardCore.BibleSearchCascade.wordWindowLimit`과 **같은 값이어야 한다** —
    /// 의존성 방향 때문에 import할 수 없어 숫자를 양쪽에 두므로, 여기서 관계를 묶는다.
    @Test("★ 건너뛸 공백 상한은 낱말 창 상한에서 나온다")
    func maxSpacesFollowsWordWindow() {
        #expect(BibleByteScanner.maximumSkippedSpaces == BibleByteScanner.wordWindowLimit - 1)
        // KeyboardCore 의 wordWindowLimit 과 같은 값인지 — 숫자로 고정한다
        #expect(BibleByteScanner.wordWindowLimit == 5)
    }

    @Test("리소스가 없으면 빈 배열")
    func missingResource() {
        #expect(BundledBibleRepository(url: nil).makeSearcher().searchIgnoringSpaces("오래참음", limit: all).isEmpty)
    }
}
