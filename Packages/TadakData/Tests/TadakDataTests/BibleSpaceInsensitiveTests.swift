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
    private let all = 10_000

    // MARK: - 사용자가 신고한 것

    @Test("★ 「오래참음」이 본문의 「오래 참음」을 찾는다")
    func findsSpacedPhrase() {
        // 본문에는 「오래 참」 20건 / 「오래참」 0건이다
        #expect(repository.search("오래참음", limit: all).isEmpty)
        #expect(repository.searchIgnoringSpaces("오래참음", limit: all).count == 9)
    }

    @Test("★ 「태초에하나님이」가 창세기 1:1을 찾는다")
    func findsGenesisWithoutSpace() {
        #expect(repository.search("태초에하나님이", limit: all).isEmpty)
        let matches = repository.searchIgnoringSpaces("태초에하나님이", limit: all)
        #expect(matches == [BibleVerseMatch(book: 1, chapter: 1, verse: 1)])
    }

    @Test("공백이 든 검색어도 같은 답을 낸다", arguments: ["오래참음", "오래 참음", "오래  참음"])
    func spacesInQueryDoNotMatter(query: String) {
        #expect(repository.searchIgnoringSpaces(query, limit: all).count == 9)
    }

    // MARK: - 정확 스캔은 그대로다

    @Test("정확 스캔 결과가 하나도 안 바뀐다", arguments: [
        ("사랑", 517), ("믿음", 225), ("소망", 97), ("태초에", 7), ("하나님이", 1031),
    ])
    func exactSearchUnchanged(query: String, expected: Int) {
        #expect(repository.search(query, limit: all).count == expected)
    }

    @Test("2글자 미만은 느슨 스캔도 안 돈다", arguments: ["이", "주", "", " ", "  "])
    func shortQueryRefused(query: String) {
        #expect(repository.searchIgnoringSpaces(query, limit: all).isEmpty)
    }

    @Test("랭킹 규칙이 같다 — 「믿음」은 느슨으로도 히브리서 11:1이 1위")
    func rankingIsShared() {
        #expect(
            repository.searchIgnoringSpaces("믿음", limit: all).first
                == BibleVerseMatch(book: 58, chapter: 11, verse: 1)
        )
    }

    @Test("편집 안내 절은 느슨 스캔에서도 빠진다")
    func editorialNoticesExcludedInLoose() {
        #expect(repository.searchIgnoringSpaces("포함되어있음", limit: all).isEmpty)
    }

    @Test("리소스가 없으면 빈 배열")
    func missingResource() {
        #expect(BundledBibleRepository(url: nil).searchIgnoringSpaces("오래참음", limit: all).isEmpty)
    }
}
