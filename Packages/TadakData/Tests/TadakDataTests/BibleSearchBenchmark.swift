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
        let repository = BundledBibleRepository().makeSearcher()
        var report = "\n[한 번 스캔]\n"
        for sample in Self.samples {
            let count = repository.search(sample, limit: 100).count
            let ms = best { _ = repository.search(sample, limit: 100) }
            report += String(format: "  %@ %.2fms (%d건)\n", sample, ms, count)
        }
        print(report)
    }

    /// ★ **fixture 하나로는 최악을 못 본다** (2026-09-21 정정, 반론자1 A-1).
    ///
    /// 예전 벤치는 「둘 셋 넷 다섯 은혜로운말씀」 **하나**만 쓰고 5.51ms를 얻어
    /// *"예산 16.7ms의 35%"* 라고 적었다. **값은 재현되지만 fixture가 최악이 아니다** —
    /// 느슨 스캔 비용은 **앵커 히트 수**를 따라가 질의마다 10배까지 차이 난다
    /// (ko_50k 4,000낱말 전수: 중앙 0.90ms · p95 2.19ms · **최대 6.39ms**).
    ///
    /// 그래서 **실사용 문장**을 넣고 **최소·중앙·최대를 전부** 찍는다.
    /// `min`만 찍으면 사용자가 겪는 나쁜 쪽이 안 보인다.
    @Test("★ 캐스케이드 한 바퀴 — 꼬리별 최소·중앙·최대")
    func worstCaseCascade() {
        let repository = BundledBibleRepository().makeSearcher()

        /// 꼬리 하나가 도는 창 다섯 — 캐스케이드가 실제로 훑는 순서 그대로.
        func windows(_ tail: String) -> [String] {
            let words = tail.split(separator: " ")
            return (1...min(words.count, 5)).reversed().map {
                words.suffix($0).joined(separator: " ")
            }
        }

        /// 정확 5회 + 느슨 5회 = 한 바퀴.
        func roundMilliseconds(_ tail: String) -> Double {
            milliseconds {
                for query in windows(tail) {
                    _ = repository.search(query, limit: 1_000)
                    _ = repository.searchIgnoringSpaces(query, limit: 1_000)
                }
            }
        }

        let tails = [
            ("벤치 fixture", "둘 셋 넷 다섯 은혜로운말씀"),
            ("실사용 문장", "그래서 내가 말했잖아 지금 당장 어디예요"),
            ("비싼 낱말 다섯", "위해서가 어디예요 자네에겐 시간이야 괴물이야"),
        ]
        print("\n[캐스케이드 한 바퀴 — 40회]  예산 16.7ms")
        for (name, tail) in tails {
            let runs = (0..<40).map { _ in roundMilliseconds(tail) }.sorted()
            let median = runs[runs.count / 2]
            print(String(format: "  %-16@ 최소 %5.2f / 중앙 %5.2f / 최대 %5.2f ms  (예산의 %.0f%%)",
                         name as NSString, runs.first ?? 0, median, runs.last ?? 0,
                         (runs.last ?? 0) / 16.7 * 100))
        }
    }

    /// 느슨 스캔이 **정확 스캔보다 얼마나 비싼가** — 공백 건너뛰기 비교가 붙는 값이다.
    @Test("★ 띄어쓰기 무시 — 한 번 스캔 비용")
    func spaceInsensitiveCost() {
        let repository = BundledBibleRepository().makeSearcher()
        print("\n[띄어쓰기 무시 한 번]")
        for sample in ["오래참음", "태초에하나님이", "사랑", "은혜"] {
            let exact = best { _ = repository.search(sample, limit: 1_000) }
            let loose = best { _ = repository.searchIgnoringSpaces(sample, limit: 1_000) }
            let count = repository.searchIgnoringSpaces(sample, limit: 1_000).count
            print(String(format: "  %@ 정확 %.2fms / 느슨 %.2fms (%d건)", sample, exact, loose, count))
        }
    }

    /// ★ **꺼 둔 사용자가 빈도표 비용을 안 내는지** — 수치로 증명한다 (반론자1 A-6).
    ///
    /// 예전에는 `BundledBibleRepository.init`이 무조건 스캐너를 만들었고, 스캐너 init이
    /// 본문 4.4MB를 훑어 바이트 빈도표를 만들었다. 성경 검색은 **기본값이 꺼짐**인데
    /// 조립 지점이 저장소를 저장 프로퍼티로 들고 있어(성경 **채움글**이 쓴다)
    /// **모든 사용자가 키보드 등장마다** 그 값을 냈다.
    ///
    /// 이제 스캐너는 `makeSearcher()`로 분리됐다. 아래 둘의 차이가 **꺼 둔 사용자가 아끼는 값**이다.
    @Test("★ 저장소를 여는 비용 — 꺼짐 / 켜짐")
    func initCost() {
        // 꺼진 사용자 경로: 저장소만 연다(mmap + 헤더 검증). 빈도표 없음.
        let closed = best(of: 5) { _ = BundledBibleRepository() }
        // 켠 사용자 경로: 저장소 + 검색기(본문 전체 훑기 → 빈도표)
        let opened = best(of: 5) {
            let store = BundledBibleRepository()
            _ = store.makeSearcher()
        }
        // 검색기만 따로 — 이것이 예전에 모두가 내던 값이다
        let store = BundledBibleRepository()
        let searcherOnly = best(of: 5) { _ = store.makeSearcher() }

        print(String(
            format: "\n[init] 꺼짐 %.3fms / 켜짐 %.3fms / 검색기만 %.3fms  (차이가 꺼 둔 사용자가 아끼는 값)\n",
            closed, opened, searcherOnly
        ))
        // 꺼진 경로가 켠 경로보다 **확실히** 싸야 한다 — 아니면 분리가 안 된 것이다
        #expect(closed < opened)
    }
}
