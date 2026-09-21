import Testing
import TadakDomain
@testable import KeyboardCore

/// 검색어를 물어본 순서까지 기록하는 대역.
///
/// KeyboardCore는 `TadakData`를 import하지 않는다 — 실제 `bible.tdb` 스캔은
/// `TadakDataTests/BibleSearchTests`가 맡고, 여기서는 **캐스케이드 규칙만** 고정한다.
private final class RecordingSearcher: BibleVerseSearching, @unchecked Sendable {

    /// 이 질의들에만 결과가 있다고 답한다.
    private let answers: [String: [BibleVerseMatch]]
    /// 실제 **본문 스캔**(`search`) 질의들. ★ 이 기록이 구조 보장 테스트의 근거다 —
    /// 캐스케이드가 무엇을 검색했는지 전부 여기 남는다.
    private(set) var queries: [String] = []

    /// 띄어쓰기 무시 스캔이 돌았을 때만 기록된다.
    private(set) var looseQueries: [String] = []
    private let looseAnswers: [String: [BibleVerseMatch]]

    init(_ answers: [String: [BibleVerseMatch]], loose: [String: [BibleVerseMatch]] = [:]) {
        self.answers = answers
        self.looseAnswers = loose
    }

    func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        queries.append(query)
        return Array((answers[query] ?? []).prefix(limit))
    }

    /// 띄어쓰기 무시 답은 `looseAnswers`에서 따로 준다 — 정확 답과 섞으면
    /// 「정확이 있으면 느슨을 안 돌린다」를 확인할 수 없다.
    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] {
        queries.append(query)          // 구조 검사(neverQueriesSubwordFragment)는 둘 다 본다
        looseQueries.append(query)
        return Array((looseAnswers[query] ?? []).prefix(limit))
    }
}

private let genesisOneOne = BibleVerseMatch(book: 1, chapter: 1, verse: 1)

@Suite("성경 검색 캐스케이드")
struct BibleSearchCascadeTests {

    // MARK: - 1단계 낱말 창

    @Test("낱말 창을 좁혀 가다 맞는 데서 멈춘다")
    func narrowsWordWindow() {
        let searcher = RecordingSearcher(["태초에 하나님이": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "어제 목사님이 태초에 하나님이")

        #expect(result?.matchedQuery == "태초에 하나님이")
        #expect(result?.matches == [genesisOneOne])
        // 넓은 창부터 좁혀 온다
        #expect(searcher.queries == [
            "어제 목사님이 태초에 하나님이",
            "목사님이 태초에 하나님이",
            "태초에 하나님이",
        ])
    }

    @Test("맞은 구간만 지운다 — 앞 낱말은 건드리지 않는다")
    func deleteLengthIsTheWindow() {
        let searcher = RecordingSearcher(["태초에 하나님이": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "어제 목사님이 태초에 하나님이")

        // 「태초에 하나님이」 = 공백 포함 8자
        #expect(result?.deleteLength == 8)
    }

    @Test("낱말 창은 5개가 상한이다")
    func windowIsCappedAtFive() {
        let searcher = RecordingSearcher([:])
        let cascade = BibleSearchCascade(searcher: searcher)
        _ = cascade.search(tail: "하나 둘 셋 넷 다섯 여섯 일곱")

        #expect(searcher.queries.first == "셋 넷 다섯 여섯 일곱")
        // 정확 5회 + 느슨 4회 = 9회. 느슨의 마지막 창 「일곱」은 공백을 빼면 2자라
        // 4자 문턱에 걸려 안 돈다 (2026-09-21 띄어쓰기 무시 추가).
        #expect(searcher.queries.count == 9)
        #expect(BibleSearchCascade.wordWindowLimit == 5)
    }

    @Test("낱말 사이 공백을 원문 그대로 들고 간다")
    func preservesOriginalSpacing() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "태초에  하나님이")

        // 공백 둘을 하나로 재조립하면 본문과 어긋난다
        #expect(searcher.queries.contains("태초에  하나님이"))
    }

    // MARK: - ★ 말끝 떼기 제거 (사용자 결정 2026-09-21)
    //
    // 아래는 **예전에 2단계(어미 폴백)를 확인하던 테스트를 뒤집은 것**이다. 지우지 않고
    // 뒤집는 이유는 같은 입력이 이제 무엇을 내는지가 이 변경의 계약이기 때문이다 —
    // 다음 사람이 「왜 「사랑해」에 배지가 안 뜨지」 할 때 여기서 답을 찾아야 한다.
    //
    // 근거: `docs/design-reviews/bible-suffix-strip-critique-A.md`·`-B.md`,
    //       결정 기록 `bible-suffix-strip-removal.md`.

    /// 예전 이름 `trimsSuffixOfLastWord` — 「마지막 낱말에서 어미를 뗀다」를 뒤집었다.
    @Test("★ 마지막 낱말을 자르지 않는다 — 친 그대로만 찾는다")
    func neverStripsSuffix() {
        // 본문에 「사랑」은 517건 있지만 사용자가 친 것은 「사랑해」다.
        let searcher = RecordingSearcher(["사랑": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "사랑해")

        #expect(result == nil)
        #expect(searcher.queries == ["사랑해"])
    }

    /// ★ **받아들인 손실을 명시로 잠근다.**
    ///
    /// 「사랑해」·「감사합니다」는 예전에 각각 517·176건을 자동으로 찾아 줬다.
    /// 이제 안 찾는다. **이것은 버그가 아니라 사용자 결정(2026-09-21)이다.**
    ///
    /// 되돌리기 전에 읽을 것: 말끝 떼기는 사람들이 실제로 치는 낱말 3,000개 중
    /// **424개(14.1%)** 에서 발동했고 그중 **24%가 확실히 나빴다**(「쓰레기」→「쓰레」·
    /// 「아가씨」→「아가」·「오십시오」→「오십」). 좋은 사례를 살리려던 조사 결합 검사는
    /// **전제가 한국어에서 거짓**이었다.
    ///
    /// **어간은 친 낱말의 접두사라 지우개 한두 번이면 그대로 나온다** —
    /// 「사랑해」를 치는 도중에 이미 「사랑」 517건 배지가 떠 있었다.
    @Test("★ 받아들인 손실 — 좋은 사례도 이제 안 찾는다", arguments: [
        "사랑해", "사랑합니다", "감사합니다", "기도했어요", "위로해", "용서해",
    ])
    func acceptedLossIsLocked(tail: String) {
        // 어간은 본문에 있다고 답하게 해 둔다 — 그런데도 nil이어야 한다.
        let searcher = RecordingSearcher([
            "사랑": [genesisOneOne], "감사": [genesisOneOne], "기도": [genesisOneOne],
            "위로": [genesisOneOne], "용서": [genesisOneOne],
        ])
        #expect(BibleSearchCascade(searcher: searcher).search(tail: tail) == nil)
    }

    /// 사장님이 실기에서 찾았던 경로. 예전에는 조사 결합 검사가 막았는데,
    /// 이제는 **자를 일이 없어서** 애초에 생기지 않는다.
    @Test("★ 「하세요」는 배지가 뜨지 않는다 — 이제 자르지 않으니까")
    func haseyoProducesNoBadge() {
        // 본문에서 「하세」는 실제로 6건이 걸린다. 그래도 검색조차 하지 않아야 한다.
        let searcher = RecordingSearcher(["하세": Array(repeating: genesisOneOne, count: 6)])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "하세요")

        #expect(result == nil)
        #expect(!searcher.queries.contains("하세"))
    }

    /// ★ **이 테스트가 「다음 말끝」 회귀를 원천 차단하는 장치다.**
    ///
    /// 개별 낱말 목록보다 이것이 중요하다 — 낱말 목록은 새 말끝이 나올 때마다 늘지만,
    /// 이 검사는 **구조**를 본다: 캐스케이드가 검색한 문자열은 전부 꼬리의
    /// **낱말 경계로 잘라 낸 구간**이어야 한다. 낱말을 글자 단위로 자른 조각이
    /// 질의에 하나라도 있으면 실패한다.
    @Test("★ 낱말을 글자 단위로 자른 조각은 절대 검색하지 않는다", arguments: [
        "사랑해", "오십시오", "그러니까", "쓰레기", "아가씨", "자기야", "알았어",
        "어제 목사님이 태초에 하나님이", "하나 둘 셋 넷 다섯 사랑하는자들", "태초에하나님이",
    ])
    func neverQueriesSubwordFragment(tail: String) {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: tail)

        // 꼬리의 낱말 경계로 만들 수 있는 후보 전부 — 이것 말고는 검색하면 안 된다
        let words = tail.split(whereSeparator: { $0.isWhitespace })
        var allowed = Set<String>()
        for size in 1...max(words.count, 1) where size <= words.count {
            let first = words[words.count - size]
            allowed.insert(String(tail[first.startIndex..<words[words.count - 1].endIndex]))
        }

        for query in searcher.queries {
            #expect(allowed.contains(query), "낱말 경계 밖의 질의: \(query)")
        }
    }

    /// 계약 이력: 8회(조사 검사) → 5회(말끝 떼기 제거) → **10회**(띄어쓰기 무시 추가, 2026-09-21).
    /// 실측 5.84ms로 60Hz 예산 16.7ms의 35%다.
    @Test("★ 최악은 본문 훑기 10회다 — 정확 5 + 느슨 5")
    func worstCaseIsTenScans() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "하나 둘 셋 넷 다섯 사랑하는자들")

        #expect(searcher.queries.count == 10)
        #expect(searcher.queries.count <= BibleSearchCascade.wordWindowLimit * 2)
        // 정확이 전부 0건이라 느슨이 돌았다
        #expect(searcher.looseQueries.count == 5)
    }

    /// ★ **이 변경의 핵심 계약.** 찾은 말과 문서에 있는 말이 갈릴 자리가 없어졌다.
    @Test("★ 불변식 — 결과가 나오면 언제나 matchedQuery == typedText", arguments: [
        "사랑", "태초에 하나님이", "어제 목사님이 태초에 하나님이", "태초에  하나님이", "믿음",
    ])
    func matchedQueryAlwaysEqualsTypedText(tail: String) {
        let searcher = RecordingSearcher([
            "사랑": [genesisOneOne], "믿음": [genesisOneOne],
            "태초에 하나님이": [genesisOneOne], "태초에  하나님이": [genesisOneOne],
        ])
        let found = BibleSearchCascade(searcher: searcher).search(tail: tail)
        // ★ 이 단언이 없으면 캐스케이드가 망가져 전부 nil이 될 때 **핵심 계약 테스트가
        //   조용히 통과한다.** 인자 다섯은 전부 결과가 나오는 입력이다(검증자 5/5 확인).
        #expect(found != nil)
        guard let result = found else { return }

        #expect(result.matchedQuery == result.typedText)
        #expect(result.deleteLength == result.matchedQuery.count)
    }

    /// 예전 이름 `wordWindowSkipsNounCheck` — 조사 검사가 없어져 이름만 바뀌었다.
    @Test("낱말 창은 친 구절 그대로 찾는다")
    func wordWindowSearchesVerbatim() {
        let searcher = RecordingSearcher(["태초에 하나님이": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "어제 태초에 하나님이")

        #expect(result?.matchedQuery == "태초에 하나님이")
        #expect(result?.typedText == "태초에 하나님이")
    }

    /// 예전 이름 `noDuplicateScans` — 말끝 떼기 시절에는 같은 문자열을 두 번 훑는 것이 낭비였다.
    /// 지금은 **정확과 느슨이 같은 후보를 각각 한 번씩** 본다. 그건 중복이 아니라 다른 검색이다 —
    /// 「오래참음」은 공백이 없는데도 느슨으로 보면 본문의 「오래 참음」이 걸린다.
    @Test("정확·느슨이 같은 후보를 각각 한 번씩만 본다")
    func eachCandidateScannedOncePerPass() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "어제 사랑해")

        // 정확 2회(어제 사랑해 / 사랑해) + 느슨 1회(사랑해는 공백 빼면 3자라 문턱 미달)
        #expect(searcher.queries == ["어제 사랑해", "사랑해", "어제 사랑해"])
        #expect(searcher.looseQueries == ["어제 사랑해"])
    }

    // MARK: - ★ 띄어쓰기 무시 (사용자 지시 2026-09-21)
    //
    // > 「오래참음을 입력 하면 나오지 않고 오래 참음 이라고 타이핑 하면 나오는데
    // >  띄어쓰기를 해야 나온다 띄어쓰기 하지 않아도 나왔으면 좋겠다」
    //
    // 설계의 핵심은 **정확 먼저, 느슨 나중**이다. 느슨하게만 하면 사전 3,000 낱말 중 13.6%가
    // 건수가 늘어 지금 되는 것이 오염된다(「아주」 41 → 97건).

    /// ★ **이 테스트가 1-3절의 핵심이다.** 정확이 1건이라도 있으면 느슨은 **아예 안 돈다** —
    /// 그래서 「아주」·「여기」 같은 기존 결과가 한 건도 안 늘어난다.
    @Test("★ 정확이 1건이라도 있으면 느슨을 안 돌린다")
    func exactResultSuppressesLoosePass() {
        let searcher = RecordingSearcher(
            ["아주": [genesisOneOne]],
            loose: ["아주": Array(repeating: genesisOneOne, count: 97)]   // 느슨하면 97건이 된다
        )
        let result = BibleSearchCascade(searcher: searcher).search(tail: "아주")

        #expect(result?.matches.count == 1)          // 41건 자리 — 늘지 않았다
        #expect(searcher.looseQueries.isEmpty)       // 느슨은 질의조차 안 했다
    }

    @Test("정확이 전부 0건이어야 느슨이 돈다")
    func loosePassRunsOnlyWhenExactFails() {
        let searcher = RecordingSearcher([:], loose: ["오래참음": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "오래참음")

        #expect(result?.matches.count == 1)
        #expect(searcher.looseQueries == ["오래참음"])
        #expect(searcher.queries.count <= 10)
    }

    /// 사용자가 신고한 바로 그 경로.
    @Test("★ 「오래참음」이 본문의 「오래 참음」을 찾는다")
    func spaceInsensitiveFindsSpacedVerse() {
        let searcher = RecordingSearcher([:], loose: ["오래참음": Array(repeating: genesisOneOne, count: 9)])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "오래참음")

        #expect(result?.matches.count == 9)
        // ★ 공백을 뺀 문자열을 넣지 않는다 — 꼬리 원문 그대로다
        #expect(result?.matchedQuery == "오래참음")
        #expect(result?.typedText == "오래참음")
    }

    @Test("★ 공백을 빼고 4자 미만이면 느슨을 안 돌린다", arguments: ["그건", "이거", "말이야", "가 나"])
    func shortCandidatesSkipLoosePass(tail: String) {
        // 2~3자는 느슨으로 걸리는 것이 거의 전부 헛것이다(2자 356개 중 43개)
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: tail)

        #expect(searcher.looseQueries.isEmpty)
    }

    @Test("딱 4자면 느슨을 돌린다")
    func fourCharactersRunsLoosePass() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "오래참음")
        #expect(searcher.looseQueries == ["오래참음"])
        #expect(BibleSearchCascade.minimumSpaceInsensitiveLength == 4)
    }

    @Test("공백은 길이에서 빼고 센다 — 「오래 참음」은 4자다")
    func lengthIgnoresSpaces() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "오래 참음")
        #expect(searcher.looseQueries.contains("오래 참음"))
    }

    @Test("느슨 결과에도 matchedQuery == typedText 불변식이 산다")
    func invariantHoldsForLooseResults() {
        let searcher = RecordingSearcher([:], loose: ["태초에하나님이": [genesisOneOne]])
        let result = BibleSearchCascade(searcher: searcher).search(tail: "어제 태초에하나님이")

        #expect(result?.matchedQuery == result?.typedText)
    }

    // MARK: - 2글자 미만

    @Test("2글자 미만은 스캔을 아예 안 돌린다", arguments: ["이", "주", "", "  "])
    func shortTailIsNeverScanned(tail: String) {
        let searcher = RecordingSearcher([:])
        let result = BibleSearchCascade(searcher: searcher).search(tail: tail)

        #expect(result == nil)
        #expect(searcher.queries.isEmpty)
    }

    /// 예전 이름 `stopsTrimmingBelowMinimum` — 뗄 것이 없어져 질의가 하나뿐이다.
    @Test("한 낱말 꼬리는 그 낱말 하나만 검색한다")
    func singleWordTailQueriesOnce() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "사랑해")

        #expect(searcher.queries == ["사랑해"])
    }

    // MARK: - 실패

    @Test("전부 실패하면 nil이다 — 배지 없음")
    func noMatchReturnsNil() {
        #expect(BibleSearchCascade(searcher: RecordingSearcher([:])).search(tail: "어제 회식했다") == nil)
    }

    @Test("붙여 친 경우는 낱말 하나로 떨어진다")
    func noSpacesFallsBackToSingleToken() {
        let searcher = RecordingSearcher([:])
        _ = BibleSearchCascade(searcher: searcher).search(tail: "태초에하나님이")

        // 공백이 없으면 낱말이 하나 — 창은 전체 문자열 하나뿐이다.
        // 정확으로 한 번, 0건이라 느슨으로 한 번. **이 두 번째가 사용자 요청을 푸는 자리다** —
        // 「태초에하나님이」가 본문의 「태초에 하나님이」를 찾는다(2026-09-21).
        #expect(searcher.queries == ["태초에하나님이", "태초에하나님이"])
        #expect(searcher.looseQueries == ["태초에하나님이"])
    }

    @Test("기본 상한이 999+ 규칙과 맞물린다")
    func defaultLimitMatchesBadgeCap() {
        // 상한이 999 이하면 배지가 999+ 에 절대 못 닿는다 (실측으로 잡은 결함)
        #expect(BibleSearchCascade.defaultResultLimit > 999)
    }

    @Test("상한을 그대로 넘겨 준다")
    func passesResultLimitThrough() {
        let many = (1...10).map { BibleVerseMatch(book: 1, chapter: 1, verse: $0) }
        let searcher = RecordingSearcher(["사랑은": many])
        let result = BibleSearchCascade(searcher: searcher, resultLimit: 3).search(tail: "사랑은")

        #expect(result?.matches.count == 3)
    }
}
