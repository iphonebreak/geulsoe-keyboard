import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 성경 검색 실측 — **평소에는 돌지 않는다.**
///
/// ```sh
/// TADAK_BENCH=1 swift test --package-path Packages/TadakData -c release --filter BibleSearchBenchmark
/// ```
///
/// **★ filter 는 타입 이름이어야 한다** — `--filter 성능`(스위트 표시 이름)으로는
/// **0건이 실행되고 "통과"처럼 보인다**(반론자2 실측 2026-09-19). 릴리스 절차에 넣으면
/// 성능을 안 재고 잰 것으로 착각한다.
///
/// `-c release` 가 **필수다.** 디버그 빌드는 바운즈 체크 때문에 스캔이 수십 배 느려서
/// 그 숫자로는 아무 것도 판단할 수 없다. 근거 표는
/// `docs/design-reviews/v1.1.0-round2-findings.md` A-1(macOS 호스트 / swiftc -O).
///
/// ## 최악은 10회다 (2026-09-21 오후)
///
/// 이 파일은 한때 **8회·20회 계약을 코드로 박아 둔 곳**이었다. 계약 이력:
/// 8회(조사 결합 검사) → **5회**(말끝 떼기 제거) → **10회**(띄어쓰기 무시 추가).
///
/// 마지막 것은 **정확 5회 + 느슨 5회**다. 정확이 전부 0건일 때만 느슨이 돌므로
/// **지금 되는 검색은 여전히 5회에서 끝난다** — 10회는 *0건인 입력*의 값이다.
/// (반론 F-2 「성능 계약과 벤치 불일치」는 여기서 계속 닫혀 있다.)
///
/// ## ★ 여기서 재는 것은 호스트 숫자다 — 실기가 아니다
///
/// 계획서 3-2절이 *"macOS 비율 기준 자체를 폐기한다"* 고 못박았다. 이 수치는 **구현이
/// findings 수준인지 확인하는 용도**이지 실기 수용 기준이 아니다. 실기 실측은 릴리스 선행 조건이다.
@Suite(
    "성경 검색 성능",
    .enabled(if: ProcessInfo.processInfo.environment["TADAK_BENCH"] != nil)
)
struct BibleSearchBenchmark {

    /// findings A-1 의 표본들.
    private static let samples = ["사랑", "믿음", "소망", "평안", "감사", "은혜", "기도"]

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// 여러 번 재서 **최소값**을 쓴다 — 최소값이 캐시·스케줄링 잡음이 가장 적게 섞인 값이다.
    private func best(of rounds: Int = 7, _ body: () -> Void) -> Double {
        (0..<rounds).map { _ in milliseconds(body) }.min() ?? 0
    }

    @Test("한 번 스캔 — findings A-1 표본")
    func singleScan() {
        let repository = BundledBibleRepository()
        var report = "\n[한 번 스캔]\n"
        for sample in Self.samples {
            let count = repository.search(sample, limit: 100).count
            let ms = best { _ = repository.search(sample, limit: 100) }
            report += String(format: "  %@ %.2fms (%d건)\n", sample, ms, count)
        }
        print(report)
    }

    /// ★ 최악은 **낱말 창 5회**다 (말끝 떼기 제거, 2026-09-21).
    ///
    /// 예전에는 1단계 5회 + 2단계(말끝 떼기) 3회 = 8회였다. 말끝 떼기가 사라져
    /// **낱말 창이 전부**가 됐다 — `KeyboardCore.BibleSearchCascade.wordWindowLimit`.
    ///
    /// ## ★ fixture 를 실제 캐스케이드 경로와 맞췄다 (반론자2 지적)
    ///
    /// 예전 fixture 는 **6·5·4·3·2낱말**이었다. 캐스케이드는 같은 꼬리에서
    /// **5·4·3·2·1낱말**을 훑는데(`wordWindowLimit = 5`), 즉 캐스케이드가 **절대 하지 않는**
    /// 6낱말 질의를 넣고 **실제로 하는** 1낱말 「은혜로운말씀」을 빼고 있었다.
    ///
    /// 사장님 대조 실측: **fixture 3.11ms / 실제 경로 2.51ms / 캐스케이드 통째로 2.12ms.**
    /// 옛 fixture 가 실제보다 **비관적**이라 성능 판단을 위험하게 만들지는 않았지만 계약이 틀렸다.
    ///
    /// 개수만 세던 것도 고쳤다 — **각 질의가 0건인지 단언한다.**
    /// 하나라도 걸리면 캐스케이드가 거기서 멈추므로 **애초에 최악 경로가 아니다.**
    @Test("★ 최악 10회 — 캐스케이드 두 바퀴(정확 + 느슨)")
    func worstCaseCascade() {
        let repository = BundledBibleRepository()

        // 꼬리 「둘 셋 넷 다섯 은혜로운말씀」에서 캐스케이드가 실제로 훑는 창 다섯 개.
        // 넓은 쪽부터 좁혀 마지막 한 낱말까지 간다.
        let missAll = [
            "둘 셋 넷 다섯 은혜로운말씀",
            "셋 넷 다섯 은혜로운말씀",
            "넷 다섯 은혜로운말씀",
            "다섯 은혜로운말씀",
            "은혜로운말씀",
        ]
        #expect(missAll.count == 5)
        // ★ 전부 0건이어야 최악이다
        for query in missAll {
            #expect(repository.search(query, limit: 100).isEmpty, "0건이 아니면 최악 경로가 아니다: \(query)")
        }

        let exact = best { for query in missAll { _ = repository.search(query, limit: 100) } }
        let loose = best { for query in missAll { _ = repository.searchIgnoringSpaces(query, limit: 100) } }
        let both = best {
            for query in missAll { _ = repository.search(query, limit: 100) }
            for query in missAll { _ = repository.searchIgnoringSpaces(query, limit: 100) }
        }
        print(String(format: "\n[최악] 정확 5회 %.2fms / 느슨 5회 %.2fms / 합계 10회 %.2fms  (예산 16.7ms)\n",
                     exact, loose, both))
    }

    /// 느슨 스캔이 **정확 스캔보다 얼마나 비싼가** — 공백 건너뛰기 비교가 붙는 값이다.
    @Test("★ 띄어쓰기 무시 — 한 번 스캔 비용")
    func spaceInsensitiveCost() {
        let repository = BundledBibleRepository()
        print("\n[띄어쓰기 무시 한 번]")
        for sample in ["오래참음", "태초에하나님이", "사랑", "은혜"] {
            let exact = best { _ = repository.search(sample, limit: 1_000) }
            let loose = best { _ = repository.searchIgnoringSpaces(sample, limit: 1_000) }
            let count = repository.searchIgnoringSpaces(sample, limit: 1_000).count
            print(String(format: "  %@ 정확 %.2fms / 느슨 %.2fms (%d건)", sample, exact, loose, count))
        }
    }

    @Test("저장소를 여는 비용 — 바이트 빈도표를 init에서 만든다")
    func initCost() {
        // 빈도표는 본문 블롭 4.4MB를 한 번 훑어 만든다. 키보드가 뜰 때 한 번 치르는 값이다.
        let ms = best(of: 3) { _ = BundledBibleRepository() }
        print(String(format: "\n[init] %.2fms\n", ms))
    }
}
