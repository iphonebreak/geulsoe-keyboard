import Testing
import CoreGraphics
@testable import KeyboardUI

@Suite("EmojiCatalog")
struct EmojiCatalogTests {

    @Test("카테고리는 비어 있지 않고 전체 수는 수백 개 이상이다")
    func catalogIsPopulated() {
        let categories = EmojiCatalog.categories
        #expect(!categories.isEmpty)
        for category in categories {
            #expect(!category.emojis.isEmpty, "\(category.name) 비어 있음")
        }
        let total = categories.reduce(0) { $0 + $1.emojis.count }
        #expect(total > 800)
    }

    @Test("카테고리 간 중복 없음")
    func noDuplicatesAcrossCategories() {
        let all = EmojiCatalog.categories.flatMap(\.emojis)
        #expect(Set(all).count == all.count)
    }

    @Test("스윕 범위의 카탈로그 대상 스칼라가 전부 어느 카테고리엔가 들어 있다 — 누락 0")
    func coversEverythingInSweepRange() {
        let expected = Set(EmojiCatalog.sweepRange.compactMap { value -> UInt32? in
            guard let scalar = Unicode.Scalar(value), EmojiCatalog.isCatalogued(scalar) else { return nil }
            return value
        })
        let actual = Set(EmojiCatalog.categories.flatMap(\.emojis).map { $0.unicodeScalars.first!.value })
        let missing = expected.subtracting(actual)
        #expect(missing.isEmpty, "누락: \(missing.sorted().map { String($0, radix: 16) })")
        #expect(actual.subtracting(expected).isEmpty, "범위 밖 포함")
    }

    @Test("잔여 스윕(기타)은 작다 — 블록 범위가 대부분을 분류한다")
    func residualSweepIsSmall() {
        let other = EmojiCatalog.categories.first { $0.id == "other" }
        #expect((other?.emojis.count ?? 0) < 40, "기타: \(other?.emojis ?? [])")
    }

    @Test("이모지 표현이 기본인 단일 스칼라만 담긴다 (피부색·머리색·지역 표시자 제외)")
    func onlyEmojiPresentationScalars() {
        for emoji in EmojiCatalog.categories.flatMap(\.emojis) {
            #expect(emoji.unicodeScalars.count == 1)
            let scalar = emoji.unicodeScalars.first!
            #expect(scalar.properties.isEmojiPresentation)
            #expect(!EmojiCatalog.isExcluded(scalar), "\(emoji)")
        }
    }

    @Test("자주 쓰는 목록은 중복이 없고 모두 이모지다")
    func frequentListIsClean() {
        let frequent = EmojiCatalog.frequent
        #expect(Set(frequent).count == frequent.count)
        for emoji in frequent {
            #expect(emoji.unicodeScalars.contains { $0.properties.isEmoji }, "\(emoji)")
        }
    }
}


/// 카테고리 탭 치수 (REQ-6) — 아이폰 회귀 금지선을 단정문으로 박는다.
@Suite("이모지 카테고리 탭 치수")
struct EmojiCategoryMetricsTests {

    /// 아이폰은 항상 8열이고 가장 넓은 기기(440pt)에서도 셀이 52.5pt다 — 전부 하한에 걸려야 한다.
    @Test("아이폰 셀 폭에서는 카테고리 탭이 38 x 28 · 아이콘 14pt 그대로다")
    func phoneUnchanged() {
        for panelWidth in [320.0, 375.0, 393.0, 402.0, 440.0] as [CGFloat] {
            let gridWidth = panelWidth - 6      // KeyboardRootView의 .padding(.horizontal, 3)
            let columns = EmojiGridView.columnCount(forWidth: gridWidth)
            #expect(columns == 8, "아이폰은 항상 8열이어야 한다 (폭 \(panelWidth))")
            let cell = EmojiGridView.cellWidth(forWidth: gridWidth, columns: columns)
            let m = EmojiGridView.categoryMetrics(cellWidth: cell)
            #expect(m.width == 38 && m.height == 28 && m.icon == 14,
                    "폭 \(panelWidth) · 셀 \(cell)pt → \(m)")
        }
    }

    /// 아이패드에서는 실제로 커져야 한다 — 그게 REQ-6의 목적이다.
    @Test("아이패드 셀 폭에서는 카테고리 탭이 커지고 터치 높이가 HIG 44pt를 넘는다")
    func padScalesUp() {
        let gridWidth: CGFloat = 894 - 6        // 자판 폭 상한 안의 이모지 패널
        let columns = EmojiGridView.columnCount(forWidth: gridWidth)
        let cell = EmojiGridView.cellWidth(forWidth: gridWidth, columns: columns)
        #expect(cell > 56, "아이패드 셀 \(cell)pt는 아이폰 천장(56)을 넘어야 한다")
        let m = EmojiGridView.categoryMetrics(cellWidth: cell)
        #expect(m.width > 38 && m.icon > 14)
        #expect(m.height >= 44, "터치 높이 \(m.height)pt — HIG 44pt 이상")
    }
}
