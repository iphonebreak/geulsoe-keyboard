import Darwin
import Foundation
import Testing
@testable import TadakDomain

/// K2(codex 반론 v1.3.0 #2, 사장님 결정 2026-10-08) — 키보드 로더의 내 채움글 몫은 **넘는 것이 확정되면 그 자리에서 멈춘다.**
///
/// - 항목을 인코드하기 **전에** 원시 UTF-8 바이트(본문·제목·단축어)로 하한을 먼저 본다 — 직렬화 바이트 ≥ 원시 바이트라
///   하한이 넘으면 정확 계산도 그 자리에서 넘는다. 그 항목은 인코드하지 않는다(10MB 한 항목을 통째로 인코드하던 경로).
/// - 넘은 뒤 항목도 인코드하지 않는다. 넘은 뒤의 정확한 전체 통계는 앱(`userSnippetUsage` — `PackStore` 커밋 판정 R21)이 센다.
/// - 싣는 개수는 앱 함수와 **같다**(AC-8) — 아래 표와 `UserSnippetUsageTests.loadMatchesUsage`(무작위 4,000건)가 고정한다.
@Suite("내 채움글 몫 — 키보드 조기 종료 (K2)")
struct UserSnippetLoadTests {

    static let small = SnippetEntry(trigger: "집", title: "우리 집", body: "서울시 어딘가 1")
    /// 원시 바이트만으로 `limits`(1,000B)를 넘는 항목
    static let giant = SnippetEntry(trigger: "큰것", title: "t", body: String(repeating: "가", count: 400))  // 1,200B

    static var limits: PackBudgetLimits {
        var limits = PackBudgetLimits.candidate
        limits.bytes = 1_000
        return limits
    }

    static func encodedBytes(_ entry: SnippetEntry) -> Int {
        (try? JSONEncoder.sorted.encode(entry).count) ?? -1
    }

    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var entries: [SnippetEntry]
        var builtIn: PackStats = .zero
        var limits: PackBudgetLimits = UserSnippetLoadTests.limits
        var loadable: Int
        /// 넘지 않았나 — 참이면 `.fits(전체 stats)`
        var fits: Bool
        /// 인코드한 항목 수 — 거대 항목·넘은 뒤 항목은 0회
        var encoded: Int
        /// 넘었으면 반드시 들어 있어야 하는 항목
        var mustInclude: [PackBudgetDimension] = []
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        let small = Self.small
        let giant = Self.giant
        let one = encodedBytes(small)
        let raw = small.body.utf8.count + small.title.utf8.count + small.triggers.reduce(0) { $0 + $1.utf8.count }
        var exactTwo = limits
        exactTwo.bytes = 2 + one + 1 + one                     // 「[s,s]」 딱 맞음
        var floorPasses = limits
        floorPasses.bytes = 2 + one + 1 + one + 1 + raw        // 셋째의 하한은 들어가고 인코드하면 넘는다
        var twoItems = limits
        twoItems.items = 2
        var needles = limits
        needles.needleChars = 10
        return [
            Case(name: "작은 항목 여러 개 — 넘지 않음: 전부 싣고 전부 센다", entries: Array(repeating: small, count: 5),
                 loadable: 5, fits: true, encoded: 5),
            Case(name: "★ 단일 거대 항목 — 인코드 0회로 「초과」", entries: [giant],
                 loadable: 0, fits: false, encoded: 0, mustInclude: [.bytes]),
            Case(name: "★ 작은 앞부분 + 거대한 마지막 — 앞 3개만 인코드", entries: [small, small, small, giant],
                 loadable: 3, fits: false, encoded: 3, mustInclude: [.bytes]),
            Case(name: "★ 거대한 중간 — 그 뒤 항목은 인코드하지 않는다", entries: [small, giant, small, small],
                 loadable: 1, fits: false, encoded: 1, mustInclude: [.bytes]),
            Case(name: "하한은 통과·인코드하면 넘음 — 그 항목까지 인코드하고 멈춘다", entries: Array(repeating: small, count: 4),
                 limits: floorPasses, loadable: 2, fits: false, encoded: 3, mustInclude: [.bytes]),
            Case(name: "바이트 경계 딱 맞음 — 전부 싣는다", entries: [small, small], limits: exactTwo,
                 loadable: 2, fits: true, encoded: 2),
            Case(name: "개수 초과 — 넘는 항목은 인코드 없이 멈춘다", entries: Array(repeating: small, count: 4), limits: twoItems,
                 loadable: 2, fits: false, encoded: 2, mustInclude: [.items]),
            Case(name: "단축어 글자 수 초과 — 인코드해야 알 수 있다(needle은 하한에 없다)",
                 entries: (0..<3).map { SnippetEntry(trigger: "가나다라마바\($0)", title: "t", body: "b") }, limits: needles,
                 loadable: 1, fits: false, encoded: 2, mustInclude: [.needleChars]),
            Case(name: "내장만으로 넘음 — 하나도 인코드하지 않는다", entries: [small, small],
                 builtIn: PackStats(needleCount: 0, needleChars: 0, bytes: 2_000, items: 0),
                 loadable: 0, fits: false, encoded: 0, mustInclude: [.bytes]),
            Case(name: "빈 목록", entries: [], loadable: 0, fits: true, encoded: 0),
            Case(name: "빈 목록 + 내장 초과", entries: [], builtIn: PackStats(needleCount: 0, needleChars: 0, bytes: 2_000, items: 0),
                 loadable: 0, fits: false, encoded: 0, mustInclude: [.bytes]),
        ]
    }()

    @Test("표 — 싣는 개수(앱 함수와 같음)·넘음·인코드 횟수", arguments: cases)
    func table(_ testCase: Case) {
        var encoded = 0
        let load = ActivePackBudget.userSnippetLoad(
            testCase.entries, builtIn: testCase.builtIn, limits: testCase.limits,
            entryStats: { entry, index in
                encoded += 1
                return PackStats.of(entry: entry, at: index)
            })
        let usage = ActivePackBudget.userSnippetUsage(testCase.entries, builtIn: testCase.builtIn, limits: testCase.limits)
        let exactOverflow = ActivePackBudget.evaluate(baseline: usage.stats + testCase.builtIn, packs: [], limits: testCase.limits)
            .baselineOverflow

        #expect(load.loadableCount == testCase.loadable)
        #expect(load.loadableCount == usage.loadableCount, "AC-8 — 앱(정확 통계)과 같은 싣는 개수")
        #expect(encoded == testCase.encoded, "인코드한 항목 수")
        if testCase.fits {
            #expect(load.baseline == .fits(usage.stats), "넘지 않으면 전체 stats는 앱 함수와 같다")
            #expect(load.overflowDimensions.isEmpty && exactOverflow.isEmpty)
        } else {
            #expect(!load.overflowDimensions.isEmpty)
            #expect(Set(load.overflowDimensions).isSubset(of: Set(exactOverflow)), "넘는 항목은 정확 계산의 부분집합(하한)")
            for dimension in testCase.mustInclude {
                #expect(load.overflowDimensions.contains(dimension), "\(dimension)")
            }
        }
    }

    /// 하한의 전제 — 직렬화 바이트 ≥ 문자열 필드의 원시 UTF-8 바이트(escape·키·따옴표는 더하기만 한다)
    @Test("전제 — 인코드 바이트 ≥ 원시 UTF-8 바이트", arguments: UserSnippetUsageTests.identityCases)
    func floorIsBelowEncoding(_ testCase: UserSnippetUsageTests.IdentityCase) {
        for entry in testCase.entries {
            #expect(PackStats.rawUTF8Bytes(of: entry) <= Self.encodedBytes(entry))
        }
    }

    // MARK: - 큰 항목 시간·메모리 상한

    /// 32MB 한 항목 — 고치기 전 경로(정확 계산)는 이 기계에서 인코드 63ms·메모리 피크 +61MB였다(보고서 K2 실측).
    /// 조기 종료는 원시 바이트 수만 본다(0.6µs·+0MB). 상한은 넉넉하게 10ms·8MB — 인코드가 끼면 둘 다 넘는다
    @Test("★ 32MB 단일 항목 — 인코드 없이 10ms 안·메모리 피크 증가 8MB 미만, 앞의 작은 항목은 싣는다")
    func giantEntryIsBoundedInTimeAndMemory() {
        let giant = SnippetEntry(trigger: "큰것", title: "t", body: String(repeating: "a", count: 32_000_000))
        let entries = [Self.small, Self.small, giant]
        var load: ActivePackBudget.UserSnippetLoad?
        let peakBefore = Self.footprintPeak()
        let duration = ContinuousClock().measure {
            load = ActivePackBudget.userSnippetLoad(entries, builtIn: .zero)   // 제품 한도(3,000,000B)
        }
        let peakGrowth = Self.footprintPeak() - peakBefore
        #expect(load?.loadableCount == 2)
        #expect(load?.overflowDimensions == [.bytes])
        #expect(duration < .milliseconds(10), "\(duration)")
        #expect(peakGrowth < 8 << 20, "피크 증가 \(peakGrowth >> 20)MB")
    }

    /// 프로세스 메모리 사용량(phys_footprint)의 지금까지 최고치 — 늘었으면 그사이 그만큼 잡았다
    static func footprintPeak() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.ledger_phys_footprint_peak : 0
    }
}
