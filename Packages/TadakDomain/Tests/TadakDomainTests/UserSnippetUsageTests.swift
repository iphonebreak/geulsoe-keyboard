import Foundation
import Testing
@testable import TadakDomain

/// 내 채움글의 예산 몫 — 항목마다 한 번만 인코드해 앞에서부터 더한다(PDR `external-snippet-packs.md` 9-3 항등식, R23).
/// 근거: `docs/release/v1.3.0-device-session-4-p2.md` 6-4 — 배열 전체를 다시 인코드해 재구성 피크가 저장분 × 2.0만큼 늘었다.
@Suite("내 채움글 몫 — 항목별 누적 (9-3 항등식·R23)")
struct UserSnippetUsageTests {

    struct IdentityCase: Sendable, CustomTestStringConvertible {
        var name: String
        var entries: [SnippetEntry]
        var testDescription: String { name }
    }

    static let identityCases: [IdentityCase] = [
        IdentityCase(name: "빈 배열", entries: []),
        IdentityCase(name: "1개", entries: [SnippetEntry(trigger: "집", title: "우리 집", body: "서울시 어딘가 1")]),
        IdentityCase(name: "따옴표", entries: [SnippetEntry(triggers: ["\"인용\"", "따옴"], title: "\"t\"", body: "그가 \"안녕\" 했다 '홑'")]),
        IdentityCase(name: "역슬래시", entries: [SnippetEntry(trigger: "경로", title: "C:\\dir", body: "C:\\path\\x \\n \\\\ \\u0041")]),
        IdentityCase(name: "개행·탭", entries: [SnippetEntry(trigger: "줄", title: "a\nb", body: "줄1\n줄2\r\n줄3\t탭\u{8}\u{C}")]),
        IdentityCase(name: "슬래시", entries: [SnippetEntry(trigger: "1/2", title: "https://a.b/c", body: "</script> a/b/c //")]),
        IdentityCase(name: "이모지", entries: [SnippetEntry(triggers: ["👍", "🇰🇷"], title: "👨‍👩‍👧‍👦", body: "❤️ 👍🏽 🏳️‍🌈 😀")]),
        IdentityCase(name: "결합 문자", entries: [SnippetEntry(triggers: ["e\u{301}", "\u{1100}\u{1161}\u{11A8}"], title: "a\u{308}\u{323}",
                                                               body: "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF} cafe\u{301}")]),
        IdentityCase(name: "제어 문자·줄 구분자", entries: [SnippetEntry(trigger: "제어", title: "\u{0}\u{1}\u{1F}", body: "\u{7F}\u{2028}\u{2029}\u{FEFF}")]),
        IdentityCase(name: "여러 개 섞어서", entries: [
            SnippetEntry(triggers: ["우리집 주소", "집주소", "  "], title: "t", body: "b"),
            SnippetEntry(trigger: "", title: "", body: ""),
            SnippetEntry(triggers: ["\"", "\\", "/"], title: "\n", body: "😀e\u{301}"),
            SnippetEntry(trigger: "가", title: "가", body: String(repeating: "가나다/\"\\\n", count: 50)),
        ]),
    ]

    /// 9-3 항등식 — 배열 길이 = `2 + Σ항목 + (n−1)`. 인코더 자신이 지키는지(전제), 그리고 누적 구현이 전체 인코드와 같은지
    @Test("전체 직렬화 길이 == 항목별 누적 2 + Σ항목 + (n−1)", arguments: identityCases)
    func identity(_ testCase: IdentityCase) throws {
        let entries = testCase.entries
        let whole = try JSONEncoder.sorted.encode(entries).count
        let parts = try entries.map { try JSONEncoder.sorted.encode($0).count }
        #expect(whole == 2 + parts.reduce(0, +) + max(0, entries.count - 1), "인코더 전제")
        #expect(PackStats.of(entries: entries) == Self.wholeEncodeStats(entries))
        #expect(ActivePackBudget.userSnippetUsage(entries, builtIn: .zero).stats == Self.wholeEncodeStats(entries))
    }

    /// 9-3 — 넘으면 저장 순서대로 한도까지만 싣는다. 내장은 먼저 차감한다. 넘지 않으면 전부, 넘어도 전체 stats는 끝까지 센다
    @Test("싣는 개수 — 처음 넘는 자리에서 멈춘 개수, 넘지 않으면 전부. 전체 stats는 끝까지 (AC-5)")
    func loadableCount() {
        var limits = PackBudgetLimits.candidate
        limits.needleChars = 100
        let entries = (0..<10).map { index in SnippetEntry(triggers: [String(repeating: "가", count: 19) + "\(index)"], title: "t", body: "b") }
        let builtIn = PackStats(needleCount: 1, needleChars: 30, bytes: 0, items: 0)
        let usage = ActivePackBudget.userSnippetUsage(entries, builtIn: builtIn, limits: limits)
        #expect(usage.loadableCount == 3)
        #expect(usage.stats == Self.wholeEncodeStats(entries), "넘은 뒤에도 전체를 센다 — 넘은 항목·R21 비용 비교가 전체 값을 본다")
        #expect(ActivePackBudget.userSnippetUsage(entries, builtIn: .zero, limits: limits).loadableCount == 5)
        #expect(ActivePackBudget.userSnippetUsage(Array(entries.prefix(5)), builtIn: .zero, limits: limits).loadableCount == 5, "경계 — 딱 100자")
        #expect(ActivePackBudget.userSnippetUsage(Array(entries.prefix(2)), builtIn: .zero, limits: limits).loadableCount == 2)
        #expect(ActivePackBudget.userSnippetUsage([], builtIn: .zero, limits: limits) == .init(stats: Self.wholeEncodeStats([]), loadableCount: 0))
        // 내장만으로 넘으면 하나도 싣지 않는다
        let heavy = PackStats(needleCount: 1, needleChars: 101, bytes: 0, items: 0)
        #expect(ActivePackBudget.userSnippetUsage(entries, builtIn: heavy, limits: limits).loadableCount == 0)
    }

    /// 9-3 바이트 경계 — 빈 배열 "[]" 2바이트와 둘째부터의 쉼표 1바이트까지 세어 멈춘다
    @Test("바이트 경계 — 「[]」와 쉼표까지 센 자리에서 멈춘다")
    func byteBoundary() throws {
        let entries = (0..<4).map { SnippetEntry(trigger: "k\($0)", title: "t", body: "b") }
        let one = try JSONEncoder.sorted.encode(entries[0]).count
        var limits = PackBudgetLimits.candidate
        limits.bytes = 2 + one + 1 + one          // 「[a,b]」 딱 맞음
        #expect(ActivePackBudget.userSnippetUsage(entries, builtIn: .zero, limits: limits).loadableCount == 2)
        limits.bytes -= 1                          // 쉼표 하나 모자람
        #expect(ActivePackBudget.userSnippetUsage(entries, builtIn: .zero, limits: limits).loadableCount == 1)
    }

    /// R23 수정의 회귀 잠금 — 옛 계산(9c797f0: 배열 전체 재인코드 → 넘으면 항목마다 두 번 인코드하며 다시 셈)과
    /// 새 함수(항목마다 한 번)가 **모든 출력에서 같다**. 시드 고정이라 결정적이다.
    @Test("무작위 비교 — 새 함수가 옛 계산과 stats·넘은 항목·싣는 개수까지 같다 (4,000건)")
    func matchesOldComputation() {
        var generator = SplitMix64(seed: 0x5EED_0023)
        var mismatches: [String] = []
        var fits = 0, truncated = 0, none = 0
        for round in 0..<4_000 {
            let entries = (0..<Int.random(in: 0...12, using: &generator)).map { _ in Self.randomEntry(&generator) }
            let builtIn = Bool.random(using: &generator)
                ? PackStats.zero
                : PackStats(needleCount: .random(in: 0...5, using: &generator), needleChars: .random(in: 0...30, using: &generator),
                            bytes: .random(in: 0...300, using: &generator), items: .random(in: 0...3, using: &generator))
            let limits = PackBudgetLimits(needleCount: .random(in: 0...25, using: &generator),
                                          needleChars: .random(in: 0...150, using: &generator),
                                          bytes: .random(in: 0...2_500, using: &generator),
                                          items: .random(in: 0...14, using: &generator),
                                          peakBytes: Int.random(in: 0..<10, using: &generator) < 3
                                              ? .random(in: 0...6_000, using: &generator) : nil)

            let old = Self.oldComputation(entries, builtIn: builtIn, limits: limits)
            let new = ActivePackBudget.userSnippetUsage(entries, builtIn: builtIn, limits: limits)
            let newOverflow = ActivePackBudget.evaluate(baseline: new.stats + builtIn, packs: [], limits: limits).baselineOverflow
            if new.stats != old.stats || newOverflow != old.overflow || new.loadableCount != old.loadable {
                mismatches.append("#\(round) n=\(entries.count) old=\(old) new=\(new) \(newOverflow)")
            }
            switch old.loadable {
            case entries.count: fits += 1
            case 0: none += 1
            default: truncated += 1
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count)건 — \(mismatches.prefix(3))")
        // 분포 가드 — 무작위가 세 갈래(전부·일부·없음)를 고루 지나야 이 비교가 의미 있다
        #expect(fits > 300 && truncated > 300 && none > 300, "전부 \(fits) · 일부 \(truncated) · 없음 \(none)")
    }

    // MARK: - 기준(옛 계산)

    /// 옛 `PackStats.of(entries:)` — 배열 전체를 한 번에 인코드
    static func wholeEncodeStats(_ entries: [SnippetEntry]) -> PackStats {
        let needles = entries.flatMap { $0.triggers.map { SnippetEntry.normalizedTrigger($0).count }.filter { $0 > 0 } }
        return PackStats(needleCount: needles.count, needleChars: needles.reduce(0, +),
                         bytes: (try? JSONEncoder.sorted.encode(entries).count) ?? -1, items: entries.count)
    }

    /// 9c797f0의 키보드 계산을 그대로 옮긴 것 — `PackSnapshotLoader.readSnapshot`·`baselineOnly`의 baseline 판정 +
    /// 옛 `ActivePackBudget.loadableUserEntryCount`(항목마다 `of(entries: [entry])` + `serializedBytes(ofEntry:)` 두 번 인코드)
    static func oldComputation(
        _ entries: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits
    ) -> (stats: PackStats, overflow: [PackBudgetDimension], loadable: Int) {
        let stats = wholeEncodeStats(entries)
        let overflow = ActivePackBudget.evaluate(baseline: stats + builtIn, packs: [], limits: limits).baselineOverflow
        guard !overflow.isEmpty else { return (stats, overflow, entries.count) }
        var usage = builtIn + PackStats(needleCount: 0, needleChars: 0, bytes: 2, items: 0)
        for (index, entry) in entries.enumerated() {
            var single = wholeEncodeStats([entry])
            single.bytes = ((try? JSONEncoder.sorted.encode(entry).count) ?? -1) + (index > 0 ? 1 : 0)
            let next = usage + single
            guard ActivePackBudget.overflowing(next, largestPackBytes: 0, limits: limits).isEmpty else {
                return (stats, overflow, index)
            }
            usage = next
        }
        return (stats, overflow, entries.count)
    }

    private static let pieces = ["가", "나", "집", "주소", "a", "Z", "1", " ", "  ", "\"", "\\", "\n", "\r\n", "\t", "/", "<", "&", "'",
                                 "😀", "👨‍👩‍👧", "🇰🇷", "👍🏽", "e\u{301}", "\u{1100}\u{1161}", "\u{0}", "\u{1F}", "\u{7F}", "\u{2028}", "ﾟ"]

    private static func randomString(_ generator: inout SplitMix64, maxPieces: Int) -> String {
        (0..<Int.random(in: 0...maxPieces, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
    }

    private static func randomEntry(_ generator: inout SplitMix64) -> SnippetEntry {
        SnippetEntry(triggers: (0..<Int.random(in: 1...3, using: &generator)).map { _ in randomString(&generator, maxPieces: 8) },
                     title: randomString(&generator, maxPieces: 4), body: randomString(&generator, maxPieces: 24))
    }
}

/// 시드 고정 난수원 — 테스트가 결정적이도록
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
