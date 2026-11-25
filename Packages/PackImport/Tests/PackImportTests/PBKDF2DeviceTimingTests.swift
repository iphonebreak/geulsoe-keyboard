import Foundation
import Testing
@testable import PackImport

// P-5 게이트 — PBKDF2-HMAC-SHA256 반복 수별 소요 시간(PDR `external-snippet-packs.md` 12-5).
// **평소 `swift test`에서는 돌지 않는다**(맥에서 2M 반복 × 5회만 해도 수 초). 실기에서 잴 때만 켠다:
//   TEST_RUNNER_GSPACK_TIMING=1 xcodebuild test -scheme PackImport -destination 'id=<기기>' -only-testing:PackImportTests/PBKDF2DeviceTimingTests
// (xcodebuild는 `TEST_RUNNER_` 접두를 떼고 시험 프로세스 환경에 넣는다). 결과는 시험 첨부가 아니라 실패 없는 기록(`Issue` 아님)으로
// 표준 출력에 한 줄씩 남긴다 — 숫자(반복 수·밀리초)뿐, 비밀번호·키는 시험용 상수다(사용자 입력 아님).
@Suite("PBKDF2 실기 시간 (P-5)", .enabled(if: ProcessInfo.processInfo.environment["GSPACK_TIMING"] == "1"))
struct PBKDF2DeviceTimingTests {

    @Test("반복 300k·600k·1M·2M 각 5회 중앙값")
    func measure() throws {
        let password = Array("timing-password-2026".utf8)
        let salt = Data((0..<16).map { UInt8($0) })
        for iterations in [300_000, 600_000, 1_000_000, 2_000_000] {
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                let key = GSPackOpener.pbkdf2(password, salt, iterations)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                #expect(key?.count == 32)
                samples.append(elapsed)
            }
            let median = samples.sorted()[samples.count / 2]
            print("GSPACK-P5 iterations=\(iterations) median_ms=\(Int(median.rounded())) samples_ms=\(samples.map { Int($0.rounded()) })")
        }
    }
}
