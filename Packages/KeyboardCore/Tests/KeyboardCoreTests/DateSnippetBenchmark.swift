import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 날짜 팩 추가 전후 `SnippetMatcher.suggestion(forTail:)` 비용 — **평소에는 돌지 않는다.**
///
/// ```sh
/// TADAK_BENCH=1 swift test --package-path Packages/KeyboardCore -c release --filter DateSnippetBenchmark
/// ```
///
/// PDR `date-snippet-pack.md` 수용 기준 10: **차이 10µs 이하.** filter는 **타입 이름**이어야 한다
/// (스위트 표시 이름으로 걸면 0건이 돌고 통과처럼 보인다 — `BibleSearchBenchmark` 주석과 같은 함정).
/// `-c release`가 필수다 — 디버그 빌드 숫자로는 판단하지 않는다.
///
/// ## 무엇을 싣나
///
/// 내장 팩 단축어 **실물**을 읽는다(`TadakData/Resources/Snippets.json`·`Greetings.json`, 317개) —
/// KeyboardCore는 TadakData를 import하지 않으므로(의존성 규칙) 파일을 경로로 읽어 도메인 타입으로 디코딩한다.
/// 성경 저장소는 싣지 않는다 — 두 매처에 똑같이 빠져 차이에 영향이 없다.
///
/// ★ 호스트(macOS) 숫자다. 자릿수를 보는 용도이지 실기 수용 기준이 아니다.
@Suite(
    "날짜 채움글 성능",
    .enabled(if: ProcessInfo.processInfo.environment["TADAK_BENCH"] != nil)
)
struct DateSnippetBenchmark {

    private static func bundledEntries() throws -> [SnippetEntry] {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()        // KeyboardCoreTests
            .deletingLastPathComponent()        // Tests
            .deletingLastPathComponent()        // KeyboardCore
            .deletingLastPathComponent()        // Packages
            .appendingPathComponent("TadakData/Sources/TadakData/Resources")
        var entries: [SnippetEntry] = []
        for name in ["Snippets", "Greetings"] {
            let data = try Data(contentsOf: resources.appendingPathComponent("\(name).json"))
            entries += try JSONDecoder().decode([SnippetEntry].self, from: data)
        }
        return entries
    }

    /// 키 입력마다 도는 **빗나가는** 꼬리(대부분의 입력) — 끝말이 「날짜/시간/시각」이 아니다
    private static let missTails = [
        "안녕하세요 오늘 회의는", "내일 봐요", "사랑은 오래 참고", "보내줄게 우리집", "ㅋㅋㅋ 진짜",
        "Hello world", "3일 후에", "시간표 보내", "날짜를"
    ]
    /// 끝말은 맞지만 날짜 단축어가 아닌 꼬리 — 파서가 끝까지 훑는 최악의 빗나감
    private static let nearMissTails = ["우리 약속 날짜", "마감 시간", "그 날짜", "몇 시각"]
    /// 맞는 꼬리 — 값까지 계산한다
    private static let hitTails = ["오늘 날짜", "3일 후 날짜", "지금 시간", "다음주 금요일 날짜", "올해 성탄절 날짜"]

    /// 한 번 호출의 평균 µs — 7라운드 중 최소(스케줄링 잡음이 가장 적은 값)
    private func microseconds(_ matcher: SnippetMatcher, _ tails: [String], iterations: Int = 20_000) -> Double {
        var best = Double.infinity
        var sink = 0
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in 0..<iterations {
                sink &+= matcher.suggestion(forTail: tails[index % tails.count])?.body.count ?? 1
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000
            best = min(best, elapsed / Double(iterations))
        }
        #expect(sink != 0)      // 최적화가 호출을 지우지 못하게
        return best
    }

    @Test("팩 추가 전후 차이 ≤ 10µs (수용 기준 10)")
    func beforeAfter() throws {
        let entries = try Self.bundledEntries()
        let before = SnippetMatcher(bible: nil, entries: entries)
        let after = SnippetMatcher(bible: nil, entries: entries, dates: DateSnippetParser())

        var report = "\n[날짜 팩 벤치 — 내장 단축어 \(entries.flatMap(\.triggers).count)개]\n"
        for (label, tails) in [("빗나감(일반 입력)", Self.missTails),
                               ("끝말만 맞음", Self.nearMissTails),
                               ("적중(값 계산)", Self.hitTails)] {
            let a = microseconds(before, tails)
            let b = microseconds(after, tails)
            report += String(format: "  %@: 전 %.3fµs · 후 %.3fµs · 차이 %+.3fµs\n", label, a, b, b - a)
            #expect(b - a <= 10, "\(label) 차이가 10µs를 넘었다")
        }
        print(report)
    }
}
