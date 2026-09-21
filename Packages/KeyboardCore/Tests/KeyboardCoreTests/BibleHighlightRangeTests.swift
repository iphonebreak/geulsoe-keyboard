import Testing
@testable import KeyboardCore

/// 구절 미리보기에서 **형광펜 칠할 자리**를 찾는다 (사용자 지시 2026-09-21).
///
/// 탐색을 KeyboardCore에 두는 이유: 뷰에 두면 테스트가 뷰에 묶인다.
@Suite("성경 미리보기 형광펜 구간")
struct BibleHighlightRangeTests {

    private func matched(_ query: String, _ preview: String) -> [String] {
        BibleVersePreview.highlightRanges(of: query, in: preview).map { String(preview[$0]) }
    }

    @Test("한 번 나오면 한 구간")
    func singleOccurrence() {
        #expect(matched("믿음", "그가 우리를 믿음에서 건지시고") == ["믿음"])
    }

    /// ★ 「소망」은 실데이터에서 **97건 중 6건이 한 절에 두 번 이상**이다
    /// (예: 욥기 17:15 「나의 소망이 어디 있으며 나의 소망을 누가 보겠느냐」).
    /// 첫 번째만 칠하면 나머지가 안 칠해진 채 남아 오히려 이상해 보인다.
    @Test("★ 여러 번 나오면 전부 칠한다")
    func everyOccurrence() {
        let verse = "나의 소망이 어디 있으며 나의 소망을 누가 보겠느냐"
        #expect(matched("소망", verse).count == 2)
    }

    @Test("세 번 이상도 전부")
    func threeOccurrences() {
        #expect(matched("사랑", "사랑은 오래 참고 사랑은 온유하며 사랑은 자랑하지").count == 3)
    }

    @Test("창에 없으면 빈 배열 — 아무 것도 칠하지 않는다")
    func absentQuery() {
        // `window()`가 검색어를 못 찾으면 머리부터 자르므로 실제로 일어날 수 있다
        #expect(BibleVersePreview.highlightRanges(of: "소망", in: "여호와께서 모세에게 이르시되").isEmpty)
    }

    @Test("빈 입력은 빈 배열", arguments: [("", "사랑은 오래 참고"), ("사랑", "")])
    func emptyInput(query: String, preview: String) {
        #expect(BibleVersePreview.highlightRanges(of: query, in: preview).isEmpty)
    }

    /// ★ 창은 앞뒤에 `…`이 붙는다 — **본문이 아니라 창 위에서** 찾아야 인덱스가 맞는다.
    @Test("앞뒤 줄임표가 붙어도 자리가 맞는다")
    func worksWithEllipsis() {
        let preview = "…너희는 소망으로 행하라…"
        let ranges = BibleVersePreview.highlightRanges(of: "소망", in: preview)
        #expect(ranges.count == 1)
        #expect(String(preview[ranges[0]]) == "소망")
        // 줄임표를 포함한 문자열 위의 인덱스여야 한다
        #expect(preview.distance(from: preview.startIndex, to: ranges[0].lowerBound) == 5)
    }

    @Test("구간이 겹치지 않는다")
    func rangesDoNotOverlap() {
        let preview = "사랑사랑사랑"
        let ranges = BibleVersePreview.highlightRanges(of: "사랑", in: preview)
        #expect(ranges.count == 3)
        for (a, b) in zip(ranges, ranges.dropFirst()) {
            #expect(a.upperBound <= b.lowerBound)
        }
    }

    @Test("공백이 든 검색어도 그대로 찾는다")
    func queryWithSpace() {
        #expect(matched("태초에 하나님이", "태초에 하나님이 천지를 창조하시니라") == ["태초에 하나님이"])
    }

    // MARK: - ★ 띄어쓰기 무시 (2026-09-21)
    //
    // 느슨 검색으로 걸린 절은 **창도 틀리고 형광펜도 안 나온다** — 둘 다 정확 일치로
    // 자리를 찾고 있었기 때문이다. 고치지 않으면 조용히 깨진다.

    @Test("★ 「오래참음」이 「오래 참음」에 칠해진다 — 공백을 포함한 한 덩어리로")
    func spaceInsensitiveHighlight() {
        let preview = "…주는 오래 참음으로…"
        let ranges = BibleVersePreview.highlightRanges(of: "오래참음", in: preview)

        #expect(ranges.count == 1)
        // ★ 공백을 포함한다 — 「오래」와 「참음」을 따로 칠하면 형광펜이 얼룩덜룩해진다
        #expect(String(preview[ranges[0]]) == "오래 참음")
    }

    @Test("공백이 여럿 끼어도 한 덩어리다")
    func multipleSpacesInsideMatch() {
        let preview = "태초에 하나님이 천지를"
        let ranges = BibleVersePreview.highlightRanges(of: "태초에하나님이", in: preview)

        #expect(ranges.count == 1)
        #expect(String(preview[ranges[0]]) == "태초에 하나님이")
    }

    @Test("느슨 매치도 여러 번 나오면 전부 칠한다")
    func everyLooseOccurrence() {
        let preview = "오래 참음과 오래 참음"
        #expect(BibleVersePreview.highlightRanges(of: "오래참음", in: preview).count == 2)
    }

    @Test("정확히 맞는 것이 있으면 느슨으로 넘어가지 않는다")
    func exactWins() {
        // 「사랑」이 정확히 있으므로 느슨 탐색은 돌지 않는다 — 구간이 늘어나면 안 된다
        let preview = "사랑은 오래 참고"
        let ranges = BibleVersePreview.highlightRanges(of: "사랑", in: preview)
        #expect(ranges.count == 1)
        #expect(String(preview[ranges[0]]) == "사랑")
    }

    @Test("느슨으로도 못 찾으면 빈 배열")
    func looseMissStillEmpty() {
        #expect(BibleVersePreview.highlightRanges(of: "오래참음", in: "여호와께서 모세에게").isEmpty)
    }

    // MARK: - 미리보기 창

    @Test("★ 느슨 매치에서도 맞은 자리에 창이 열린다")
    func windowOpensAtLooseMatch() {
        let verse = "여호와께서 모세에게 일러 가라사대 이스라엘 자손에게 고하여 이르라 너희는 오래 참음으로 행하라"
        let window = BibleVersePreview.window(of: verse, matching: "오래참음")

        // 머리부터 잘랐다면 「여호와께서…」로 시작한다 — 엉뚱한 자리다
        #expect(!window.hasPrefix("여호와께서"))
        #expect(window.contains("오래 참음"))
    }

    @Test("실제 창과 함께 — window가 연 자리에 형광펜이 걸린다")
    func worksWithActualWindow() {
        let verse = "여호와께서 모세에게 일러 가라사대 이스라엘 자손에게 고하여 이르라 너희는 사랑으로 행하라"
        let window = BibleVersePreview.window(of: verse, matching: "사랑")
        let ranges = BibleVersePreview.highlightRanges(of: "사랑", in: window)
        #expect(!ranges.isEmpty)
        #expect(String(window[ranges[0]]) == "사랑")
    }
}
