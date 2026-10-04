import Foundation
import Testing
@testable import TadakDomain

/// 활성 집합 예산과 커밋 게이트의 순수 계산 (PDR `external-snippet-packs.md` 9-1~9-3·9-5·9-6, AC-1 · AC-4 · AC-5 · AC-6).
/// 숫자는 후보값(R2) — `PackBudgetLimits.candidate`. 큐·저장·키보드 배선은 1-b.
@Suite("ActivePackBudget (9-6, AC-1)")
struct ActivePackBudgetTests {

    private func entry(triggers: Int, length: Int, body: String = "본문") -> SnippetEntry {
        SnippetEntry(triggers: (0..<triggers).map { index in String(repeating: "가", count: length - 1) + "\(index % 10)" },
                     title: "t", body: body)
    }

    private func pack(_ id: String, chars: Int, enabled: Bool = true, needles: Int = 1, bytes: Int = 100, items: Int = 1)
        -> ActivePackBudget.Candidate {
        ActivePackBudget.Candidate(id: id, isEnabled: enabled,
                                   stats: PackStats(needleCount: needles, needleChars: chars, bytes: bytes, items: items))
    }

    @Test("stats — 문구는 정규화 단축어 수·글자 수, 번호형은 패턴 수만, 바이트는 직렬화 길이")
    func stats() throws {
        let entries = [SnippetEntry(triggers: ["우리집 주소", "집주소", "  "], title: "t", body: "b")]
        let phrase = PackStats.of(entries: entries)
        #expect(phrase.needleCount == 2 && phrase.needleChars == 8 && phrase.items == 1)
        #expect(phrase.bytes == (try JSONEncoder.sorted.encode(entries)).count)

        let template = PackTemplate(patterns: [TemplatePattern(prefix: "사자성어", suffix: "번"), TemplatePattern(prefix: "성어", suffix: "번")],
                                    titleFormat: "사자성어 {n}번",
                                    items: (1...645).map { PackTemplateItem(n: $0, title: "", body: "본문 \($0)") })
        let numbered = ExternalPack(name: "n", license: "l", mode: .numbered, template: template)
        let stats = PackStats.of(pack: numbered)
        #expect(stats.needleCount == 2, "645개 항목은 needle이 아니다 — 패턴 수만")
        #expect(stats.needleChars == 8)
        #expect(stats.items == 645)
        #expect(stats.bytes == (try JSONEncoder.sorted.encode(numbered)).count)
    }

    /// AC-1 재서술 — 한 항목 최대(10×40 = 400자)는 통과, 3,000항목 최대 조합(1,200,000자)은 60,000 초과로 거절
    @Test("한 항목 최대 조합은 통과, 전체 최대 조합은 needleChars 초과로 제외 (AC-1)")
    func boundaryCombinations() {
        let one = PackStats.of(entries: [entry(triggers: 10, length: 40)])
        #expect(one.needleChars == 400)
        let small = ActivePackBudget.evaluate(baseline: .zero, packs: [.init(id: "one", isEnabled: true, stats: one)])
        #expect(small.included == ["one"])

        let all = PackStats(needleCount: 30_000, needleChars: 1_200_000, bytes: 2_000_000, items: 3_000)
        let big = ActivePackBudget.evaluate(baseline: .zero, packs: [.init(id: "all", isEnabled: true, stats: all)])
        #expect(big.included.isEmpty)
        #expect(big.excluded == [.init(id: "all", reason: .overflow([.needleCount, .needleChars]))])
    }

    @Test("켜진 내장(1,724자)을 먼저 차감한다 — 남은 58,276자까지만 (AC-1)")
    func builtInFirst() {
        let builtIn = PackStats(needleCount: 317, needleChars: 1_724, bytes: 0, items: 0)
        #expect(ActivePackBudget.evaluate(baseline: builtIn, packs: [pack("a", chars: 58_276)]).included == ["a"])
        #expect(ActivePackBudget.evaluate(baseline: builtIn, packs: [pack("a", chars: 58_277)]).included.isEmpty)
    }

    @Test("네 항목이 각각 독립 제약이다", arguments: [
        (PackStats(needleCount: 3_001, needleChars: 1, bytes: 1, items: 1), [PackBudgetDimension.needleCount]),
        (PackStats(needleCount: 1, needleChars: 1, bytes: 3_000_001, items: 1), [.bytes]),
        (PackStats(needleCount: 1, needleChars: 1, bytes: 1, items: 3_001), [.items])
    ])
    func independentDimensions(testCase: (stats: PackStats, dimensions: [PackBudgetDimension])) {
        let evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [.init(id: "p", isEnabled: true, stats: testCase.stats)])
        #expect(evaluation.excluded == [.init(id: "p", reason: .overflow(testCase.dimensions))])
    }

    @Test("prefix rule — 처음 넘는 팩부터 그 뒤 전부 제외, 꺼진 팩은 세지 않는다")
    func prefixRule() {
        let evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [
            pack("a", chars: 30_000), pack("off", chars: 50_000, enabled: false), pack("b", chars: 40_000), pack("c", chars: 10)
        ])
        #expect(evaluation.included == ["a"])
        #expect(evaluation.excluded == [.init(id: "b", reason: .overflow([.needleChars])),
                                        .init(id: "c", reason: .afterEarlierOverflow)])
        #expect(evaluation.usage.needleChars == 30_000)
    }

    @Test("baseline이 이미 넘으면 외부 팩은 전부 제외된다(삭제하지 않는다 — 9-3)")
    func baselineOverflow() {
        let baseline = PackStats(needleCount: 10, needleChars: 70_000, bytes: 1, items: 1)
        let evaluation = ActivePackBudget.evaluate(baseline: baseline, packs: [pack("a", chars: 1)])
        #expect(evaluation.baselineOverflow == [.needleChars])
        #expect(evaluation.excluded == [.init(id: "a", reason: .baselineOverflow)])
    }

    /// 9-5 — `peakEstimate = old + new + decodeTransient`. 상한은 P-2 전 미정(nil = 판정 안 함)
    @Test("피크 모델 — 옛·새 매처 배열 + 가장 큰 팩 디코드 과도분, 상한을 주면 판정한다 (AC-1)")
    func peakModel() {
        let stride = MemoryLayout<Character>.stride
        let evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [pack("a", chars: 1_000, bytes: 5_000), pack("b", chars: 500, bytes: 9_000)])
        #expect(evaluation.peakEstimateBytes == 2 * 1_500 * stride + 9_000)
        var limits = PackBudgetLimits.candidate
        limits.peakBytes = 2 * 1_000 * stride + 5_000
        let gated = ActivePackBudget.evaluate(baseline: .zero, packs: [pack("a", chars: 1_000, bytes: 5_000), pack("b", chars: 500, bytes: 9_000)], limits: limits)
        #expect(gated.included == ["a"])
        #expect(gated.excluded == [.init(id: "b", reason: .overflow([.peak]))])
    }

    /// 9-3 — 키보드는 사용자 문구를 저장 순서대로 한도까지만 싣는다(앱 표시와 같은 함수)
    @Test("기존 초과본: 사용자 문구는 저장 순서대로 한도까지만, 나머지는 삭제하지 않고 안 싣는다 (AC-5)")
    func loadableUserEntries() {
        var limits = PackBudgetLimits.candidate
        limits.needleChars = 100
        let entries = (0..<10).map { index in SnippetEntry(triggers: [String(repeating: "가", count: 19) + "\(index)"], title: "t", body: "b") }
        let builtIn = PackStats(needleCount: 1, needleChars: 30, bytes: 0, items: 0)
        #expect(ActivePackBudget.loadableUserEntryCount(entries, builtIn: builtIn, limits: limits) == 3)
        #expect(ActivePackBudget.loadableUserEntryCount(entries, builtIn: .zero, limits: limits) == 5)
        #expect(ActivePackBudget.loadableUserEntryCount(Array(entries.prefix(2)), builtIn: .zero, limits: limits) == 2)
    }
}

@Suite("커밋 게이트 — 순수 판정 (9-1·9-3, R14 · R15, AC-4 · AC-6)")
struct PackCommitGateTests {

    private func candidate(_ id: String, chars: Int, enabled: Bool = true) -> ActivePackBudget.Candidate {
        ActivePackBudget.Candidate(id: id, isEnabled: enabled, stats: PackStats(needleCount: 1, needleChars: chars, bytes: 10, items: 1))
    }

    private func input(user: Int = 0, builtIn: Int = 0, _ packs: [ActivePackBudget.Candidate]) -> PackBudgetInput {
        PackBudgetInput(userSnippets: PackStats(needleCount: 0, needleChars: user, bytes: 0, items: 0),
                        builtIn: PackStats(needleCount: 0, needleChars: builtIn, bytes: 0, items: 0), packs: packs)
    }

    @Test("켜기 — 자신이 제외되면 거부 (AC-6)")
    func enableExcludedSelf() {
        let current = input([candidate("a", chars: 50_000), candidate("b", chars: 20_000, enabled: false)])
        let proposed = input([candidate("a", chars: 50_000), candidate("b", chars: 20_000)])
        #expect(PackCommitGate.judge(.enablePack(id: "b"), current: current, proposed: proposed)
                == .reject(.packExcluded(id: "b", dimensions: [.needleChars])))
    }

    /// R15 — 앞 순서 팩을 켜서 뒤 팩이 밀리면 거부
    @Test("켜기 — 앞 팩이 포함되며 기존 포함 팩이 밀리면 거부 (R15, AC-6)")
    func enableDisplaces() {
        let current = input([candidate("a", chars: 40_000, enabled: false), candidate("b", chars: 30_000)])
        let proposed = input([candidate("a", chars: 40_000), candidate("b", chars: 30_000)])
        #expect(PackCommitGate.judge(.enablePack(id: "a"), current: current, proposed: proposed) == .reject(.displacesPacks(["b"])))
    }

    @Test("가져오기 확정(맨 아래 켠 채) — 자신이 들어가면 받는다, 못 들어가면 거부(「꺼 둔 채로 가져오기」는 화면 몫)")
    func importAppended() {
        let current = input([candidate("a", chars: 10_000)])
        let fits = input([candidate("a", chars: 10_000), candidate("new", chars: 1_000)])
        guard case .accept(let evaluation, let newlyExcluded) = PackCommitGate.judge(.importPack(id: "new"), current: current, proposed: fits) else {
            Issue.record("받아야 한다"); return
        }
        #expect(evaluation.included == ["a", "new"] && newlyExcluded.isEmpty)
        let tooBig = input([candidate("a", chars: 10_000), candidate("new", chars: 60_000)])
        #expect(PackCommitGate.judge(.importPack(id: "new"), current: current, proposed: tooBig)
                == .reject(.packExcluded(id: "new", dimensions: [.needleChars])))
    }

    @Test("내장 팩 켜기로 외부 팩이 밀리면 거부 — 두 토글 경로가 이 함수 하나 (AC-6)")
    func builtInToggle() {
        let current = input(builtIn: 0, [candidate("a", chars: 59_000)])
        let proposed = input(builtIn: 1_724, [candidate("a", chars: 59_000)])
        #expect(PackCommitGate.judge(.enableBuiltIn, current: current, proposed: proposed) == .reject(.displacesPacks(["a"])))
    }

    /// R14 — 외부 팩 때문에 사용자 문구 저장을 막지 않는다. baseline 자체가 넘으면만 거부
    @Test("내 문구 저장 — baseline이 넘으면 거부, 외부 팩 때문이면 받고 밀린 팩을 경고 (R14, AC-4)")
    func saveUserSnippets() {
        let current = input(user: 1_000, [candidate("a", chars: 58_000)])
        let pushesPack = input(user: 3_000, [candidate("a", chars: 58_000)])
        guard case .accept(let evaluation, let newlyExcluded) = PackCommitGate.judge(.saveUserSnippets, current: current, proposed: pushesPack) else {
            Issue.record("받아야 한다"); return
        }
        #expect(newlyExcluded == ["a"] && evaluation.included.isEmpty)
        let overBaseline = input(user: 60_001, [])
        #expect(PackCommitGate.judge(.saveUserSnippets, current: current, proposed: overBaseline)
                == .reject(.baselineOverLimit([.needleChars])))
    }

    @Test("끄기·삭제·순서 변경·내 문구 삭제·비활성 교체는 거부하지 않는다 — 다시 계산한 결과를 돌려준다", arguments: [
        PackCommitGate.Change.disablePack(id: "a"), .deletePack(id: "a"), .reorderPacks, .deleteUserSnippets,
        .disableBuiltIn, .replaceInactivePack(id: "z")
    ])
    func reductionsNeverReject(change: PackCommitGate.Change) {
        let current = input([candidate("a", chars: 30_000), candidate("b", chars: 20_000)])
        let proposed = input([candidate("b", chars: 20_000), candidate("a", chars: 30_000, enabled: false)])
        guard case .accept = PackCommitGate.judge(change, current: current, proposed: proposed) else {
            Issue.record("거부하면 안 된다: \(change)"); return
        }
    }

    @Test("내 문구 삭제로 예산이 회복되면 켜 둔 팩이 결정적으로 다시 포함된다(자동 재활성이 아니라 함수 결과)")
    func recoveryIsDeterministic() {
        let current = input(user: 59_000, [candidate("a", chars: 5_000)])
        let proposed = input(user: 100, [candidate("a", chars: 5_000)])
        guard case .accept(let evaluation, _) = PackCommitGate.judge(.deleteUserSnippets, current: current, proposed: proposed) else {
            Issue.record("받아야 한다"); return
        }
        #expect(evaluation.included == ["a"])
    }

    @Test("같은 이름 활성 팩 교체 — 교체 후 집합으로, 자신이 빠지면 거부")
    func replaceActive() {
        let current = input([candidate("a", chars: 10_000)])
        let proposed = input([candidate("a", chars: 70_000)])
        #expect(PackCommitGate.judge(.replaceActivePack(id: "a"), current: current, proposed: proposed)
                == .reject(.packExcluded(id: "a", dimensions: [.needleChars])))
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
