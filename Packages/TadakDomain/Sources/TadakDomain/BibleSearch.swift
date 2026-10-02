/// 성경 **본문 검색**의 도메인 경계 — 주소만 오간다.
///
/// 설계: `docs/design-reviews/v1.1.0-plan-v5.md` 3절, 실측 근거는
/// `docs/design-reviews/v1.1.0-round2-findings.md` A·B절.

/// 검색이 찾아낸 절 **하나의 주소**. 책 번호는 개역한글 66권 순서(1=창세기 … 66=요한계시록)로
/// `BibleVerseRepository`와 같다.
///
/// ## 왜 본문(`String`)을 담지 않나
///
/// 「사랑」은 517건이 맞는다. 517개의 `String`을 만들면 **절마다 `String(data:)`** 를 하는 것과
/// 같아져서 실측 240배(0.43ms → 102ms)가 그대로 돌아온다
/// (findings A-1). 본문은 **화면에 실제로 그려지는 행에서만** `BibleVerseRepository.text(...)`로 읽는다.
public struct BibleVerseMatch: Equatable, Hashable, Sendable {

    public let book: Int
    public let chapter: Int
    public let verse: Int

    public init(book: Int, chapter: Int, verse: Int) {
        self.book = book
        self.chapter = chapter
        self.verse = verse
    }
}

/// 성경 본문 검색 경계.
///
/// ## 왜 `BibleVerseRepository`에 메서드를 더하지 않고 프로토콜을 따로 두나
///
/// 본문 조회(주소 → 본문)와 검색(낱말 → 주소들)은 **쓰는 쪽이 다르다** — 채움글의 성경 참조는
/// 조회만 필요하고, 검색 화면은 둘 다 필요하다. 기존 프로토콜에 요구사항을 더하면 조회만 쓰는
/// 기존 구현·테스트 대역이 전부 깨진다. 한 타입이 둘 다 채택하는 것은 자유다
/// (`BundledBibleRepository`가 그렇게 한다).
public protocol BibleVerseSearching: Sendable {

    /// 본문에 `query`가 **그대로 들어 있는** 절들을 랭킹 순으로 돌려준다.
    ///
    /// - 2글자 미만이면 **빈 배열**이다. 스캔 자체를 돌리지 않는다 —
    ///   「이」 하나가 24,640건(전체의 79.2%)이라 결과로서 의미가 없다 (findings A-4).
    /// - 정렬은 (가) 정의형 → (나) 같은 장 출현 절 수 → (다) 절 안 출현 횟수 → 성경순 (findings B).
    /// - **`limit`은 정렬한 뒤에 자른다.** 스캔 도중에 자르면 성경순 338번째인 고린도전서 13:4가
    ///   후보에 **아예 못 들어온다** (findings A-4).
    /// - 실패하지 않는다 — 리소스가 없으면 빈 배열이다.
    func search(_ query: String, limit: Int) -> [BibleVerseMatch]

    /// **띄어쓰기를 보지 않는** 검색 — 「오래참음」이 본문의 「오래 참음」을 찾는다.
    ///
    /// 같은 글자를 **같은 순서로** 찾고 공백만 무시한다. 랭킹·상한 규칙은 위 `search`와 같다.
    ///
    /// ## 왜 `search`에 플래그를 더하지 않고 메서드를 나눴나
    ///
    /// 이 프로토콜은 2026-09-21 오전에 `contains(_:followedByAnyOf:)`를 지워 요구사항이
    /// `search` 하나가 됐다. 다시 늘리는 것이므로 이유를 적는다.
    ///
    /// 1. **선행 조건이 다르다.** `search`는 2글자 미만을 스스로 거부한다. 이쪽은 **4글자**
    ///    (공백 제외)를 요구하는데 그 규칙은 *구절은 낱말 둘 이상*이라는 **도메인 판단**이라
    ///    호출자(`BibleSearchCascade`)가 건다. 계약이 다른 둘을 한 서명에 담으면
    ///    문서가 "플래그가 참이면 …, 거짓이면 …"으로 갈라진다
    /// 2. **고르는 시점이 정적이다.** 캐스케이드는 1바퀴에서 정확, 2바퀴에서 느슨을 **고정으로**
    ///    부른다. 실행 중에 고르지 않으므로 런타임 플래그일 이유가 없다
    /// 3. 호출부가 `search(q, limit: n, ignoringSpaces: false)`로 길어지지 않는다
    ///
    /// 구현은 한 경로를 공유한다(`BibleByteScanner.run`) — 랭킹이 둘로 갈라지지 않게 하기 위해서다.
    ///
    /// - Returns: 랭킹 순. 2글자 미만이거나 리소스가 없으면 빈 배열.
    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch]
}
