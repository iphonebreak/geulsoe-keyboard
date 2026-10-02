import Testing
import KeyboardCore
@testable import KeyboardUI

/// 배지와 패널이 **같은 규칙**을 쓰는지 — 둘이 다른 말을 하던 것이 2026-09-21에 닫혔다.
///
/// 계기: 「사람」은 실제 4,253건인데 검색 상한이 1,000이라
/// **배지는 `999+`, 패널은 `전체(1000)`** 이라고 서로 다르게 그렸다.
@Suite("성경 검색 건수 표기")
struct BibleCountTextTests {

    @Test("999 이하는 그 수 그대로", arguments: [0, 1, 517, 998, 999])
    func exactBelowCap(count: Int) {
        #expect(BibleCountText.label(count) == "\(count)")
        #expect(!BibleCountText.isCapped(count))
        #expect(BibleCountText.spokenCount(count) == "\(count)건")
    }

    @Test("999를 넘으면 999+", arguments: [1_000, 1_514, 4_253])
    func cappedAboveLimit(count: Int) {
        #expect(BibleCountText.label(count) == "999+")
        #expect(BibleCountText.isCapped(count))
        #expect(BibleCountText.spokenCount(count) == "999건 이상")
    }

    // MARK: - 패널 「전체」 칩

    private func totalChip(_ count: Int) -> String {
        BibleSearchPanelView.chipLabel(BibleBookFilter(book: nil, name: "전체", count: count))
    }

    @Test("★ 상한에 걸리면 「전체 999+」 — 괄호를 벗겨 정확한 수가 아님을 알린다")
    func cappedTotalChip() {
        // 검색이 1,000개까지만 들고 오므로 「전체(1000)」은 3,253건을 조용히 빼는 말이 된다
        #expect(totalChip(1_000) == "전체 999+")
    }

    @Test("상한에 안 걸리면 지금 그대로 「전체(517)」")
    func exactTotalChip() {
        #expect(totalChip(517) == "전체(517)")
        #expect(totalChip(135) == "전체(135)")
    }

    @Test("책 칩은 그대로다 — 상한 안에서 센 수다")
    func bookChipUnchanged() {
        let song = BibleBookFilter(book: 22, name: "아가", count: 54)
        #expect(BibleSearchPanelView.chipLabel(song) == "아가(54)")
    }

    @Test("★ 배지와 「전체」 칩이 같은 수를 말한다", arguments: [517, 999, 1_000, 4_253])
    func badgeAndPanelAgree(count: Int) {
        // 배지가 그리는 글자(KeyboardRootView) = BibleCountText.label
        let badge = BibleCountText.label(count)
        let chip = totalChip(count)
        #expect(chip.contains(badge))
    }
}
