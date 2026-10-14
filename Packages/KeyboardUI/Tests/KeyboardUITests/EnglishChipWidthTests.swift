import AppKit
import Testing
@testable import KeyboardUI
import KeyboardCore

/// B5 C12 — 긴 영어 단어 칩. 사전 최장 단어(17자 `extraterrestrials`, `words-en.tdw` 실측)를 칩 글꼴(시스템 17pt)로 잰다.
/// 칩은 이미 한 줄·최소 0.7배 축소다(`wordChip` — 「창조하시니라」 때 고른 규칙). 0.7배면 가장 좁은 아이폰(375pt) 세 칸에도
/// 들어가므로 **길이 상한을 두지 않는다**(자르기 전에 대안 비교 — 계획 §3-8 C12 ①②). macOS 글꼴 측정이라 실기 렌더는 별도
@Suite("B5 C12 — 긴 영어 단어 칩 폭")
struct EnglishChipWidthTests {

    @Test("최장 단어 0.7배 폭이 375pt 세 칸에 들어간다")
    func longestWordFits() {
        let width = ("extraterrestrials" as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 17)]).width
        let slot = (375.0 - 2) / 3 - 12   // 칸 3개 · 구분선 2개 · 좌우 여백 6씩
        #expect(width * 0.7 <= slot, "\(width) × 0.7 vs \(slot)")
    }

    @Test("영어 후보 칩은 영어로 표시된다 — 한글·이모지 칩은 아니다")
    func englishFlag() {
        #expect(WordSuggestionCandidate.english("hello", typedRun: "hel").isEnglish)
        #expect(!WordSuggestionCandidate.word("안녕").isEnglish)
    }
}
