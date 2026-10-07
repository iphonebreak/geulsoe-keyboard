import Darwin
import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// U7 ①(겹치는 후보) 전후 `SnippetMatcher.suggestion(forTail:)` 비용 — **평소에는 돌지 않는다.**
///
/// ```sh
/// TADAK_BENCH=1 swift test --package-path Packages/KeyboardCore -c release --filter SnippetCandidatesBenchmark
/// ```
///
/// 지시서 `external-snippet-packs-u7-plan.md` 2절 ① 「핫패스」: **칩 없는 입력 0% 변화, 칩 있는 입력 +수십 µs 이내.**
/// U7 전 숫자는 같은 시험을 U7 코드를 넣기 **전** 트리(HEAD `7a8629f`)에서 돌려 기록했다(보고서 `docs/release/impl-u7.md`) —
/// 그래서 키 입력 시간 측정(`perKey`)은 **U7 전에도 있던 API만** 쓴다. filter는 **타입 이름**이어야 한다(`DateSnippetBenchmark` 주석과 같은 함정).
/// `-c release`가 필수다.
///
/// ## 무엇을 싣나 — 예산 상한보다 무겁게
///
/// - 문구: 내장 팩 실물(317개) + 합성 문구 2,700개 ≈ needle 3,000(9-6 후보값 `needleCount` 상한) + 「새해인사」 겹침 3줄
/// - 템플릿: **팩 16개(상한)가 같은 틀 8개를 공유**하고 팩마다 항목 5,000개(예산 3,000 초과 — 일부러 무겁게). 다른 팩의 같은 번호를
///   찾는 일이 가장 많은 꼴이다(소유 1 + 후순위 15)
/// - 성경: 고정 문자열을 돌려주는 가짜 저장소(호스트에서 mmap 비용은 재지 않는다 — 두 트리에 똑같다)
///
/// ★ 호스트(macOS) 숫자다. 자릿수를 보는 용도이지 실기 수용 기준이 아니다.
@Suite(
    "U7 후보 — 핫패스 성능",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["TADAK_BENCH"] != nil)
)
struct SnippetCandidatesBenchmark {

    private struct FakeBible: BibleVerseRepository {
        func text(book: Int, chapter: Int, verse: Int) -> String? { "태초에 하나님이 천지를 창조하시니라" }
    }

    static func bundledEntries() throws -> [SnippetEntry] {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TadakData/Sources/TadakData/Resources")
        var entries: [SnippetEntry] = []
        for name in ["Snippets", "Greetings"] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(name).json"))
            entries += try JSONDecoder().decode([SnippetEntry].self, from: data)
        }
        return entries
    }

    /// 합성 문구 — 서로 다른 단축어 `count`개(길이 4~9자)
    static func syntheticPhrases(_ count: Int) -> [SnippetEntry] {
        let syllables = Array("가나다라마바사아자차카타파하거너더러머버서어저처커터퍼허")
        return (0..<count).map { index in
            var trigger = "상용"
            var value = index
            for _ in 0..<(2 + index % 6) {
                trigger.append(syllables[value % syllables.count])
                value /= syllables.count
                value += index % 7
            }
            return SnippetEntry(trigger: trigger + "\(index)", title: "합성 \(index)", body: "합성 본문 \(index)")
        }
    }

    static let sharedPatterns = [
        TemplatePattern(prefix: "사자성어", suffix: "번"), TemplatePattern(prefix: "성어", suffix: "번"),
        TemplatePattern(prefix: "고사성어", suffix: "번"), TemplatePattern(prefix: "한자성어", suffix: "번"),
        TemplatePattern(prefix: "성구", suffix: "번"), TemplatePattern(prefix: "격언", suffix: "번"),
        TemplatePattern(prefix: "명언", suffix: "번"), TemplatePattern(prefix: "속담", suffix: "번")
    ]

    /// 팩 16개 × 같은 틀 8개 × 항목 5,000개(번호 1~5,000, 오름차순)
    static func heavyTemplateSources(packs: Int = 16, items: Int = 5_000) -> [PackTemplateMatcher.Source] {
        (0..<packs).map { pack in
            PackTemplateMatcher.Source(id: "pack\(pack)", template: PackTemplate(
                patterns: sharedPatterns, titleFormat: "사자성어 {n}번",
                items: (1...items).map { PackTemplateItem(n: $0, title: "", body: "팩\(pack) 본문 \($0)") }))
        }
    }

    static let overlap: [SnippetEntry] = [
        SnippetEntry(trigger: "새해인사", title: "내 새해", body: "내가 쓴 새해 인사"),
        SnippetEntry(trigger: "새해 인사", title: "팩 새해", body: "팩의 새해 인사")
    ]

    static func heavyMatcher() throws -> SnippetMatcher {
        let entries = overlap + syntheticPhrases(2_700) + (try bundledEntries())   // 「새해인사」는 내장에도 있다 → 3줄 겹침
        return SnippetMatcher(bible: FakeBible(), entries: entries, dates: DateSnippetParser(),
                              templates: PackTemplateMatcher(sources: heavyTemplateSources()))
    }

    /// 칩이 안 뜨는 입력(대부분의 키 입력)
    static let missTails = [
        "안녕하세요 오늘 회의는", "내일 봐요", "사랑은 오래 참고", "보내줄게 우리집", "ㅋㅋㅋ 진짜",
        "Hello world", "3일 후에", "시간표 보내", "사자성어 12", "창세기 1장"
    ]

    /// 칩이 뜨는 입력 — 분기마다
    static let hitTails: [(label: String, tail: String)] = [
        ("문구 단독(헌법 전문)", "오늘은 헌법 전문"),
        ("문구 겹침 3(새해인사)", "팀장님 새해인사"),
        ("템플릿 소유1+후순위15(성어 12번)", "오늘의 성어 12번"),
        ("날짜(오늘 날짜)", "오늘 날짜"),
        ("성경(창세기 1장 1절)", "창세기 1장 1절")
    ]

    /// 한 번 호출의 평균 µs — 7라운드 중 최소
    static func microseconds(iterations: Int = 20_000, _ body: (Int) -> Int) -> Double {
        var best = Double.infinity
        var sink = 0
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in 0..<iterations { sink &+= body(index) }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000
            best = min(best, elapsed / Double(iterations))
        }
        #expect(sink != 0)
        return best
    }

    @Test("키 하나당 suggestion µs — 칩 없음 / 칩 분기별 (U7 전후 같은 시험)")
    func perKey() throws {
        let matcher = try Self.heavyMatcher()
        var report = "\n[U7 핫패스 벤치 — needle ≈ 3,000 · 템플릿 팩 16 × 틀 8 × 항목 5,000]\n"
        let miss = Self.microseconds { matcher.suggestion(forTail: Self.missTails[$0 % Self.missTails.count])?.body.count ?? 1 }
        report += String(format: "  칩 없음(%d종 평균)            %8.2f µs\n", Self.missTails.count, miss)
        for (label, tail) in Self.hitTails {
            #expect(matcher.suggestion(forTail: tail) != nil, "전제 — \(label)는 칩이 뜬다")
            let hit = Self.microseconds { _ in matcher.suggestion(forTail: tail)?.body.count ?? 1 }
            report += String(format: "  칩: %@ %8.2f µs\n", label.padding(toLength: 28, withPad: " ", startingAt: 0), hit)
        }
        print(report)
    }

    /// 길게 누를 때 한 번 — 목록(본문 포함) 계산 µs. U7 후에만 있는 API다
    @Test("길게 누르기 1회 candidates µs (U7 후)")
    func longPress() throws {
        let matcher = try Self.heavyMatcher()
        var report = "\n[U7 길게 누르기 — candidates(forTail:) 1회]\n"
        for (label, tail) in Self.hitTails {
            let rows = matcher.candidates(forTail: tail, isSecureTextEntry: false)
            let time = Self.microseconds(iterations: 5_000) { _ in matcher.candidates(forTail: tail, isSecureTextEntry: false).count }
            report += String(format: "  %@ 행 %d개 %8.2f µs\n", label.padding(toLength: 28, withPad: " ", startingAt: 0), rows.count, time)
        }
        print(report)
    }

    /// 살아 있는 힙(바이트) — 페이지 단위 footprint는 malloc 재사용 때문에 잡음이 커서 쓰지 않는다
    static func heapInUse() -> Int {
        var stats = malloc_statistics_t()
        malloc_zone_statistics(nil, &stats)
        return Int(stats.size_in_use)
    }

    /// 매처가 **붙잡아 두는** 힙(만드는 동안의 임시 사전은 빠진다) — 3회 중앙값
    static func retained<T>(_ make: () -> T) -> Int {
        var deltas: [Int] = []
        for _ in 0..<3 {
            let before = heapInUse()
            let value = make()
            let after = heapInUse()
            withExtendedLifetime(value) { deltas.append(after - before) }
        }
        return deltas.sorted()[1]
    }

    @Test("템플릿 매처 상주 힙 — 팩 16 × 틀 8 × 항목 5,000(같은 틀). 소유 팩 하나만 실은 매처와의 차이가 U7 추가분의 상한")
    func templateMatcherRetained() {
        let sources = Self.heavyTemplateSources()
        let all = Self.retained { PackTemplateMatcher(sources: sources) }
        let ownerOnly = Self.retained { PackTemplateMatcher(sources: [sources[0]]) }
        let entries = (try? Self.bundledEntries()) ?? []
        let phrases = Self.overlap + Self.syntheticPhrases(2_700) + entries
        func makeOrigins() -> SnippetOrigins {
            var origins = SnippetOrigins()
            origins.appendEntries(count: 2, origin: .user)
            for index in 0..<16 {
                origins.appendEntries(count: 168, origin: .pack(name: "팩 \(index)"))
                origins.setTemplate(sourceID: "pack\(index)", origin: .pack(name: "팩 \(index)"))
            }
            origins.appendEntries(count: entries.count, origin: .builtIn(id: SnippetPack.greetings))
            return origins
        }
        let origins = makeOrigins()
        let originsBytes = Self.retained { makeOrigins() }
        let matcherBytes = Self.retained { SnippetMatcher(bible: nil, entries: phrases, origins: origins) }
        print(String(format: """

            [U7 상주 힙]
              템플릿 매처(소유 1 + 후순위 15)   %8.1f KB
              템플릿 매처(소유 1만)            %8.1f KB   → 차이 %.1f KB(후순위 15팩 × 틀 8 — 소유권 표 행 + U7 alternates)
              출처 표 SnippetOrigins(구간 18 + 템플릿 16)   %8.2f KB
              문구 매처(needle ≈ 3,000)        %8.1f KB

            """, Double(all) / 1_024, Double(ownerOnly) / 1_024, Double(all - ownerOnly) / 1_024,
                     Double(originsBytes) / 1_024, Double(matcherBytes) / 1_024))
    }
}
