import Foundation
import Testing
@testable import TadakDomain

@Suite("클립보드 기록")
struct ClipboardHistoryTests {

    @Test("최근순으로 쌓이고 중복은 맨 위로 이동한다")
    func recordsMostRecentFirst() {
        var history = ClipboardHistory()
        let first = history.record("첫째")
        let second = history.record("둘째")
        #expect(first && second)
        #expect(history.entries == ["둘째", "첫째"])
        let moved = history.record("첫째")
        #expect(moved, "중복은 위치만 바뀌어도 변경으로 본다")
        #expect(history.entries == ["첫째", "둘째"])
        let unchanged = history.record("첫째")
        #expect(unchanged == false, "맨 위와 같으면 변경 없음")
    }

    @Test("빈 문자열·공백은 무시하고 앞뒤 공백을 정리한다")
    func ignoresBlank() {
        var history = ClipboardHistory()
        let blank = history.record("   ")
        let empty = history.record("")
        let padded = history.record("  내용  ")
        #expect(blank == false && empty == false && padded)
        #expect(history.entries == ["내용"])
    }

    @Test("상한(30개)과 항목 길이(2,000자)를 지킨다")
    func enforcesLimits() {
        var history = ClipboardHistory()
        for index in 0..<40 { history.record("항목\(index)") }
        #expect(history.entries.count == ClipboardHistory.maxEntries)
        #expect(history.entries.first == "항목39")

        history.record(String(repeating: "가", count: 5_000))
        #expect(history.entries.first?.count == ClipboardHistory.maxEntryLength)
    }

    @Test("항목 삭제와 전체 삭제")
    func removal() {
        var history = ClipboardHistory(entries: ["a", "b", "c"])
        history.remove("b")
        #expect(history.entries == ["a", "c"])
        history.removeAll()
        #expect(history.entries.isEmpty)
    }

    @Test("손상된 저장분(중복 항목)도 디코딩 시 순서 보존 dedup된다 — UI id 충돌 방지")
    func decodingDedups() throws {
        let corrupt = #"{"entries":["a","b","a","c","b"]}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(ClipboardHistory.self, from: corrupt)
        #expect(decoded.entries == ["a", "b", "c"])
        #expect(ClipboardHistory(entries: ["x", "x"]).entries == ["x"])
    }
}
