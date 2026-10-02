import TadakDomain

/// 검색 패널이 그릴 준비가 **끝난** 행 하나.
///
/// 주소와 본문을 붙이는 일은 조립 지점(익스텐션)이 한다 — `BibleVerseRepository`를 아는 쪽이
/// 거기뿐이기 때문이다. KeyboardUI는 완성된 문자열만 받는다.
public struct BibleSearchRow: Equatable, Sendable, Identifiable {

    /// 절 주소 — 삽입할 때 본문을 다시 읽는 열쇠이자 행의 id.
    public let match: BibleVerseMatch
    /// **맞은 자리 창** — 검색어가 보이도록 자른 미리보기 (`BibleVersePreview`).
    public let preview: String

    public var id: BibleVerseMatch { match }

    public init(match: BibleVerseMatch, preview: String) {
        self.match = match
        self.preview = preview
    }

    /// 행 머리의 주소 표기.
    ///
    /// **「전체」 탭에서는 책 이름을 붙이고**(`창 13:30`), 책 탭에서는 장:절만 쓴다(`13:30`) —
    /// 이미 그 책만 보고 있는데 매 행에 책 이름을 되풀이하면 좁은 폭을 낭비한다 (UX-2).
    public func reference(includingBook: Bool) -> String {
        let numbers = "\(match.chapter):\(match.verse)"
        guard includingBook else { return numbers }
        guard let book = BibleReferenceParser.abbreviation(ofBook: match.book) else { return numbers }
        return "\(book) \(numbers)"
    }
}

/// 책 필터 탭 하나 — 「전체(137)」 또는 「창세기(13)」.
public struct BibleBookFilter: Equatable, Sendable, Identifiable {

    /// nil이면 「전체」.
    public let book: Int?
    public let name: String
    public let count: Int

    public var id: Int { book ?? 0 }

    public init(book: Int?, name: String, count: Int) {
        self.book = book
        self.name = name
        self.count = count
    }

    /// 결과 전체에서 책 필터 줄을 만든다 — 맨 앞이 「전체」, 그 뒤는 **건수 내림차순**
    /// (같으면 성경순). 건수 순인 이유는 한 화면에 1~2개만 보이기 때문이다 —
    /// 성경순으로 두면 「아가 54건」이 스크롤 끝에 숨는다 (4차 C-4 확정).
    public static func filters(for matches: [BibleVerseMatch]) -> [BibleBookFilter] {
        guard !matches.isEmpty else { return [] }
        var counts: [Int: Int] = [:]
        for match in matches { counts[match.book, default: 0] += 1 }

        let books = counts
            .map { book, count in
                BibleBookFilter(
                    book: book,
                    name: BibleReferenceParser.fullName(ofBook: book) ?? "\(book)",
                    count: count
                )
            }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return (lhs.book ?? 0) < (rhs.book ?? 0)
            }

        // 이름은 `TadakDomain`에서 읽는다 — **UITests가 같은 값을 술어로 쓴다**
        return [BibleBookFilter(book: nil, name: BibleSearchText.allBooksName, count: matches.count)] + books
    }

    /// 접근성 **조절 가능한 요소**(위/아래 스와이프)가 옮겨 갈 이웃 책.
    ///
    /// ## 왜 여기 있나
    ///
    /// 패널의 책 필터 줄은 VoiceOver에서 **하나의 조절 가능한 요소**다
    /// (`BibleSearchPanelView.bookFilterBar`). 그 이동 규칙을 뷰 안에 두면
    /// **화면 없이는 검증할 수 없다** — 실기·시뮬레이터가 금지된 이번 작업에서는 더욱 그렇다.
    /// 그래서 순수 함수로 내려 `BibleSearchPresentationTests`가 잠근다.
    ///
    /// **끝에서는 멈춘다(순환하지 않는다).** VoiceOver의 조절 가능한 요소는 슬라이더·
    /// 스테퍼와 같은 관례를 따르고, 그쪽은 범위 끝에서 멈춘다. 순환시키면 사용자가
    /// 「끝까지 왔다」를 알 방법이 없어 무한히 쓸게 된다.
    ///
    /// - Parameter book: 지금 고른 책. nil이면 「전체」.
    /// - Parameter offset: +1이면 다음, -1이면 이전.
    /// - Returns: 옮겨 갈 필터. 끝이라 움직일 데가 없으면 nil.
    public static func neighbor(
        of book: Int?, in filters: [BibleBookFilter], offset: Int
    ) -> BibleBookFilter? {
        guard !filters.isEmpty else { return nil }
        // 지금 고른 것을 못 찾으면 맨 앞(「전체」)에 서 있는 것으로 본다
        let current = filters.firstIndex { $0.book == book } ?? 0
        let target = current + offset
        guard filters.indices.contains(target) else { return nil }
        return filters[target]
    }

    /// VoiceOver가 읽을 값 — 「시편, 24건, 40개 중 3번째」.
    ///
    /// 개수만 읽으면 **어디쯤인지** 알 수 없어 위/아래 스와이프를 몇 번 더 해야 하는지
    /// 가늠할 수 없다. 그래서 자리를 함께 읽는다(슬라이더가 값과 범위를 함께 읽는 것과 같다).
    /// 개수 표기는 배지·칩과 **같은 규칙**을 쓴다(호출자가 `BibleCountText`로 만들어 넘긴다).
    public static func spokenValue(
        of book: Int?, in filters: [BibleBookFilter], count: (Int) -> String
    ) -> String {
        guard !filters.isEmpty else { return "" }
        let index = filters.firstIndex { $0.book == book } ?? 0
        let filter = filters[index]
        return "\(filter.name), \(count(filter.count)), \(filters.count)개 중 \(index + 1)번째"
    }
}

/// 본문에서 **검색어가 보이는 창**을 잘라낸다.
///
/// ## 왜 머리부터 자르면 안 되나 (findings C-3)
///
/// 기존 칩·목록 행은 본문을 앞에서부터 잘랐다. 그런데 재어 보니
/// **「사랑」 결과의 68%, 「구원」의 88%는 앞 12자 안에 검색어가 없다** —
/// 그렇게 그리면 사용자가 **왜 이 절이 걸렸는지 못 본다.**
/// 그래서 검색어 **앞 4자부터** 창을 연다.
public enum BibleVersePreview {

    /// 검색어 앞에 남겨 둘 글자 수.
    public static let leadingContext = 4
    /// 창 전체 길이(글자).
    public static let windowLength = 28

    /// - Parameters:
    ///   - text: 절 본문 전체.
    ///   - query: 스캔에 쓴 검색어. 본문에 없으면(있을 수 없지만 방어) 앞에서부터 자른다.
    /// - Returns: 잘린 쪽에 `…`이 붙은 한 줄.
    public static func window(
        of text: String,
        matching query: String,
        leadingContext: Int = leadingContext,
        windowLength: Int = windowLength
    ) -> String {
        let characters = Array(text)
        guard characters.count > windowLength else { return text }

        // 검색어가 시작하는 자리 — 없으면 0(머리부터).
        // `firstIndex`가 정확 탐색에 실패하면 공백을 건너뛰며 한 번 더 본다 —
        // 띄어쓰기 무시로 걸린 절에서 **엉뚱한 자리에 창이 열리는 것**을 막는다.
        let matchStart = firstIndex(of: Array(query.filter { !$0.isWhitespace }), in: characters)
            ?? firstIndex(of: Array(query), in: characters)
            ?? 0
        let start = max(0, min(matchStart - leadingContext, characters.count - windowLength))
        let end = min(characters.count, start + windowLength)

        var window = String(characters[start..<end])
        if start > 0 { window = "…" + window }
        if end < characters.count { window += "…" }
        return window
    }

    /// 미리보기 창 안에서 검색어가 **나오는 자리 전부** — 형광펜 칠할 구간이다.
    ///
    /// ## 왜 「전부」인가 (사용자 지시 2026-09-21)
    ///
    /// 「소망」 같은 낱말은 **한 절에 두 번 이상** 나온다. 첫 번째만 칠하면 나머지가 안 칠해진
    /// 채로 남아 오히려 「왜 저것만?」이 된다. 실데이터에서 「소망」 97건 중 한 절 안 두 번 이상이
    /// 실제로 있다(보고서 참조).
    ///
    /// ## 왜 본문이 아니라 **창** 위에서 찾나
    ///
    /// `window(of:matching:)`이 만든 창은 앞뒤에 `…`이 붙을 수 있어 **절 본문의 인덱스와
    /// 어긋난다.** 그래서 칠할 자리는 반드시 화면에 그릴 그 문자열 위에서 찾는다.
    ///
    /// ## 성능
    ///
    /// 창이 28자로 짧다는 점에 기댄다 — 목록은 `LazyVStack`이라 보이는 행만 그리고,
    /// 행마다 도는 것은 28자 탐색이다. **절 본문 전체를 다시 훑지 않는다.**
    ///
    /// - Returns: 겹치지 않는 구간들. 검색어가 비었거나 창에 없으면 **빈 배열**(아무 것도 안 칠한다).
    public static func highlightRanges(of query: String, in preview: String) -> [Range<String.Index>] {
        guard !query.isEmpty, !preview.isEmpty else { return [] }
        var ranges: [Range<String.Index>] = []
        var searchStart = preview.startIndex
        // `.literal` — 지역화 규칙으로 「소망」이 다른 글자에 맞는 일이 없게 한다
        while let found = preview.range(
            of: query, options: [.literal], range: searchStart..<preview.endIndex
        ) {
            ranges.append(found)
            searchStart = found.upperBound
        }
        if !ranges.isEmpty { return ranges }

        // ★ 정확히 못 찾았다 — 띄어쓰기 무시 검색으로 걸린 절이다(2026-09-21).
        //   그냥 두면 **형광펜이 하나도 안 칠해진다.** 공백을 건너뛰며 다시 찾는다.
        let characters = Array(preview)
        let needle = Array(query.filter { !$0.isWhitespace })
        return spaceInsensitiveSpans(of: needle, in: characters).map { span in
            preview.index(preview.startIndex, offsetBy: span.lowerBound)
                ..< preview.index(preview.startIndex, offsetBy: span.upperBound)
        }
    }

    /// 글자 배열 안에서 `needle`이 처음 나오는 자리. `String.range(of:)`를 쓰지 않는 이유는
    /// 창을 **글자 수**로 잘라야 해서 인덱스가 글자 단위여야 하기 때문이다.
    ///
    /// **정확히 못 찾으면 공백을 건너뛰며 한 번 더 본다** — 띄어쓰기 무시 검색으로 걸린 절은
    /// 「오래참음」으로 찾았는데 본문은 「오래 참음」이라 정확 탐색이 실패한다(2026-09-21).
    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        for start in 0...(haystack.count - needle.count) {
            var matched = true
            for offset in needle.indices where haystack[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched { return start }
        }
        return spaceInsensitiveSpans(of: needle, in: haystack).first?.lowerBound
    }

    /// 공백을 건너뛰며 `needle`이 맞는 **본문 구간들**(글자 인덱스, 끝 배타).
    ///
    /// ## ★ 구간에 공백을 포함한다
    ///
    /// 「오래참음」으로 찾은 「오래 참음」은 **공백을 포함한 5글자 한 덩어리**로 돌려준다.
    /// 「오래」와 「참음」을 따로 주고 공백을 비우면 형광펜이 **얼룩덜룩해진다** —
    /// 사용자가 보는 것은 *한 낱말을 찾았다*인데 화면은 *두 조각을 찾았다*로 보인다.
    /// 형광펜은 「여기가 맞은 자리다」를 말하는 것이고, 그 자리는 끊긴 곳이 아니라 이어진 구간이다.
    ///
    /// needle 쪽 공백은 호출자가 빼서 넘긴다. 본문 쪽 공백만 건너뛴다.
    static func spaceInsensitiveSpans(of needle: [Character], in haystack: [Character]) -> [Range<Int>] {
        guard !needle.isEmpty else { return [] }
        var spans: [Range<Int>] = []
        var start = 0
        while start < haystack.count {
            // 공백에서 시작하는 매치는 없다 — 시작점을 흐리지 않는다
            if haystack[start].isWhitespace { start += 1; continue }
            var cursor = start
            var index = 0
            while index < needle.count, cursor < haystack.count {
                if haystack[cursor].isWhitespace { cursor += 1; continue }
                guard haystack[cursor] == needle[index] else { break }
                cursor += 1
                index += 1
            }
            if index == needle.count {
                spans.append(start..<cursor)
                start = cursor          // 겹치지 않게
            } else {
                start += 1
            }
        }
        return spans
    }
}
