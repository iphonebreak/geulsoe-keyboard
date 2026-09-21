import TadakDomain

/// 꼬리에서 성경 검색어를 찾아낸 결과 — 무엇으로 찾았고, ✕가 얼마를 지워야 하는가.
public struct BibleSearchResult: Equatable, Sendable {

    /// 실제로 스캔에 쓴 문자열 — 꼬리에서 낱말 창으로 잘라 낸 **원문 그대로**(공백 포함).
    public let matchedQuery: String

    /// 문서 꼬리에 **실제로 들어 있는** 원문 — ✕가 지우고, 구절 삽입이 걷어낼 구간이다.
    ///
    /// ## ★ 이제 `matchedQuery`와 **항상 같다** (말끝 떼기 제거, 2026-09-21)
    ///
    /// 예전에는 달랐다 — 「사랑해」를 치고 「사랑」으로 맞으면 찾은 말과 지울 말이 갈렸다.
    /// **말끝 떼기를 없애면서 그 경우가 사라졌다.** 캐스케이드는 사용자가 친 문자열을
    /// 자르지 않고 그대로만 찾으므로 두 값이 갈릴 자리가 없다.
    /// 이 불변식은 `BibleSearchCascadeTests`가 잠근다.
    ///
    /// **그래도 프로퍼티는 둘 다 남긴다** — 하나로 합치는 것은 삽입 경로·UI까지 건드리는
    /// 별개 리팩터링이고, 의미가 다른 두 개념(찾은 말 / 문서에 있는 말)을 이름 하나로 뭉개면
    /// 나중에 되살리기 어렵다.
    ///
    /// 삽입 경로(`InputController.insertSnippet`)의 꼬리 정합 검사가 이 값으로 성립한다.
    public let typedText: String

    /// 꼬리 끝에서 지울 **글자 수**.
    public var deleteLength: Int { typedText.count }

    /// 랭킹 순으로 정렬된 절 주소들. 본문은 화면에 그려지는 행에서만 읽는다.
    public let matches: [BibleVerseMatch]

    public init(matchedQuery: String, typedText: String, matches: [BibleVerseMatch]) {
        self.matchedQuery = matchedQuery
        self.typedText = typedText
        self.matches = matches
    }
}

/// 입력 꼬리 → 성경 검색어. **낱말 창을 좁혀 가며 사용자가 친 그대로만 찾는다.**
///
/// 설계 원문: `docs/design-reviews/v1.1.0-plan-v5.md` 3-1절
/// (2단계 「말끝 떼기」는 2026-09-21 제거 — `bible-suffix-strip-removal.md`).
///
/// ## ★ 불변식 — 사용자가 친 말을 몰래 다른 말로 바꾸지 않는다
///
/// 이 캐스케이드가 검색하는 문자열은 **언제나 꼬리의 낱말 경계로 잘라 낸 구간**이다.
/// 낱말을 글자 단위로 자른 조각은 **절대 검색하지 않는다.** 그래서 결과의
/// `matchedQuery`와 `typedText`가 항상 같고, 배지에 뜬 숫자는 **사용자가 보고 있는 말**의 건수다.
///
/// 예전에는 1단계가 전부 실패하면 마지막 낱말의 끝을 1~3자 떼어 다시 찾았다(「말끝 떼기」).
/// 사람들이 실제로 치는 낱말 3,000개 중 **424개(14.1%)** 에서 발동했고 그중 **24%가 확실히 나빴다** —
/// 「쓰레기」→「쓰레」·「아가씨」→「아가」·「오십시오」→「오십」. 막으려고 붙였던 조사 결합 검사는
/// **전제 자체가 한국어에서 거짓**이었다(「을」·「은」은 관형사형 어미이기도 하다).
/// 근거: `docs/design-reviews/bible-suffix-strip-critique-A.md`·`-B.md`.
///
/// ## ★ 붙여 친 경우 — 한계였다가 2026-09-21에 닫혔다
///
/// 예전 주석은 「태초에하나님이」처럼 공백 없이 친 경우를 *"형태소 분석 없이는 낱말 경계를 알 수
/// 없어서 **받아들이기로 한 한계**"* 라고 적었다. **사용자가 그 한계를 뒤집었다:**
///
/// > 「오래참음을 입력 하면 나오지 않고 오래 참음 이라고 타이핑 하면 나오는데 띄어쓰기를 해야
/// > 나온다 띄어쓰기 하지 않아도 나왔으면 좋겠다」
///
/// 형태소 분석을 들이지 않고 닫았다 — **공백만 무시하고 같은 글자를 같은 순서로** 찾는다.
/// 말끝 떼기처럼 *다른 낱말*로 바꾸는 것이 아니므로 오전에 잠근 불변식
/// (*사용자가 친 말을 몰래 다른 말로 바꾸지 않는다*)은 그대로다.
/// 채움글 단축어가 이미 띄어쓰기를 안 보는 것(`SnippetEntry.normalizedTrigger`)과 같은 결이다.
///
/// ## ★ 정확 먼저, 느슨 나중 — 섞지 않는다
///
/// 느슨하게만 하면 **지금 되는 것이 오염된다.** 사전 3,000 낱말 전수에서 13.6%가 건수가 늘었다 —
/// 「아주」 41 → 97건처럼 **낱말 경계를 넘어** 걸린 것이고 사용자가 원한 것이 아니다.
/// 그래서 **정확 한 바퀴를 다 돌고, 전부 0건일 때만** 느슨 한 바퀴를 돈다.
/// 결과: 「오래참음」 0 → 9건(고쳐짐) · 「아주」 41건 그대로(오염 없음).
///
/// ## 최악 10회
///
/// 정확 5회 + 느슨 5회 = **본문 훑기 최대 10회.** 오전의 5회 계약을 다시 쓴 값이다.
/// 실측 **5.84ms**로 60Hz 프레임 예산 16.7ms의 35%다(정확만 2.62ms · 느슨만 3.15ms).
/// 근거: `docs/design-reviews/bible-space-insensitive-search.md`.
public struct BibleSearchCascade: Sendable {

    /// 낱말 창 상한. **실기 실측 뒤 조정 가능한 값이지 고정 상수가 아니다**(계획서 3-2절).
    public static let wordWindowLimit = 5

    /// 이 길이 미만은 스캔하지 않는다 — 「이」 하나가 24,640건이라 결과로서 의미가 없다.
    public static let minimumQueryLength = 2

    /// ★ **띄어쓰기 무시 스캔의 최소 길이**(공백 제외 글자 수).
    ///
    /// 매직 넘버가 아니다. 공백을 뺀 구절은 **낱말 둘 이상**이고 한국어 낱말은 대개 2자 이상이므로
    /// **최소 2+2 = 4자**다. 그보다 짧은 것은 애초에 구절이 아니다.
    ///
    /// 실측이 그 판단을 뒷받침한다 — 정확 0건인 낱말이 느슨으로 걸리는 비율:
    /// 2자 356개 중 43개(그건·이건·그거… 거의 전부 헛것) · 3자 746개 중 39개 ·
    /// **4자 276개 중 5개** · 5자 50개 중 0개. 이 상한으로 헛것 87개 중 **82개가 걸러지고**
    /// 사용자가 신고한 「오래참음」(4자)·「태초에하나님이」(7자)는 **그대로 살아난다.**
    ///
    /// **스캐너가 아니라 여기 있는 이유:** 「구절은 낱말 둘 이상」은 도메인 판단이지
    /// 바이트 스캔 사정이 아니다.
    public static let minimumSpaceInsensitiveLength = 4

    private let searcher: any BibleVerseSearching
    private let resultLimit: Int

    /// 한 검색이 들고 올 절의 상한.
    ///
    /// ## ★ 왜 1,000인가 — 배지 건수와 묶여 있다
    ///
    /// 배지에 뜨는 수는 `matches.count`다. 상한을 100으로 두면 「사랑」 517건이 **100건으로**
    /// 보이고, 계획서 2-1의 **999+ 규칙이 영영 발동하지 않는다**(실측으로 잡았다 — 첫 캡처의
    /// 배지가 「성경 구절 100건」이었다). 책 필터 건수도 같이 틀어진다 —
    /// 「아가 54건」이 100건 안에서 센 수가 되어 버린다.
    ///
    /// 1,000이면 999를 한 칸 넘으므로 **넘치는 순간이 곧 999+**다. 절 주소 하나가 24바이트라
    /// 최악이 24KB고, 그마저 패널을 그리는 동안만 산다.
    public static let defaultResultLimit = 1_000

    /// - Parameter resultLimit: 한 검색이 돌려줄 최대 절 수. **정렬 뒤에** 잘린다.
    public init(searcher: any BibleVerseSearching, resultLimit: Int = defaultResultLimit) {
        self.searcher = searcher
        self.resultLimit = resultLimit
    }

    /// - Parameter tail: `InputController.committedTail`(최대 48자, 조합 확정분만).
    /// - Returns: 한 건이라도 맞으면 결과, 전부 실패하면 nil(배지 없음).
    public func search(tail: String) -> BibleSearchResult? {
        let words = tail.split(whereSeparator: { $0.isWhitespace })
        guard let lastWord = words.last else { return nil }

        // ① 정확 한 바퀴 — 지금 되는 것은 하나도 바뀌지 않는다
        if let found = pass(tail: tail, words: words, lastWord: lastWord, ignoringSpaces: false) {
            return found
        }
        // ② 전부 0건일 때만 느슨 한 바퀴 — 0건이던 자리에만 결과가 생긴다
        return pass(tail: tail, words: words, lastWord: lastWord, ignoringSpaces: true)
    }

    /// 낱말 창을 5→1로 좁히며 한 바퀴.
    ///
    /// **한 바퀴 안에서 정확/느슨을 섞지 않는다** — 「정확이 어느 길이에서든 느슨을 이긴다」가
    /// 안전한 우선순위다. 섞으면 짧은 낱말의 느슨 매치가 긴 창의 정확 매치를 이겨 버린다.
    private func pass(
        tail: String,
        words: [Substring],
        lastWord: Substring,
        ignoringSpaces: Bool
    ) -> BibleSearchResult? {
        var windowSize = min(words.count, Self.wordWindowLimit)
        while windowSize >= 1 {
            let firstWord = words[words.count - windowSize]
            // 원문 그대로 — 낱말 사이 공백을 재조립하지 않고 꼬리에서 그대로 잘라 낸다.
            // 재조립하면 「태초에  하나님이」(공백 둘)가 본문과 어긋난다.
            let candidate = String(tail[firstWord.startIndex..<lastWord.endIndex])
            if let matches = scan(candidate, ignoringSpaces: ignoringSpaces), !matches.isEmpty {
                // ★ 공백을 뺀 문자열을 넣지 않는다 — `matchedQuery == typedText` 불변식과
                //   구절 삽입의 꼬리 정합 검사가 **꼬리 원문**에 걸려 있다.
                return BibleSearchResult(
                    matchedQuery: candidate,
                    typedText: candidate,
                    matches: matches
                )
            }
            windowSize -= 1
        }
        return nil
    }

    /// 길이 문턱을 통과한 후보만 스캔한다. 문턱에 걸리면 nil(스캔 자체를 안 돈다).
    private func scan(_ candidate: String, ignoringSpaces: Bool) -> [BibleVerseMatch]? {
        if ignoringSpaces {
            let squeezed = candidate.filter { !$0.isWhitespace }
            guard squeezed.count >= Self.minimumSpaceInsensitiveLength else { return nil }
            return searcher.searchIgnoringSpaces(candidate, limit: resultLimit)
        }
        guard candidate.count >= Self.minimumQueryLength else { return nil }
        return searcher.search(candidate, limit: resultLimit)
    }
}
