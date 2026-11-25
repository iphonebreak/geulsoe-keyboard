import Foundation
import Testing

/// 잠금 팩 소스 검사(PDR `external-snippet-packs.md` 12-4 「로그」·12-11 단위 시험, security.md 1순위).
///
/// 비밀번호·복호화본·봉투 값이 로그·오류 설명으로 새는 길을 **소스에서** 막는다 — 실패는 값 없는 열거형이고,
/// 출력 API·오류 설명 API를 이 파일들에서 아예 쓰지 않는다. 암호는 OS 제공만(서드파티 import 0, 12-12 ①).
@Suite("잠금 팩 — 소스 검사 (로그 0 · OS 암호만)")
struct GSPackSourceScanTests {

    static let forbiddenTokens = ["print(", "NSLog", "os_log", "Logger(", "debugPrint", "localizedDescription",
                                  "String(describing:", "dump(", "Crashlytics", "Analytics", "URLSession"]
    static let allowedImports: Set<String> = ["Foundation", "CommonCrypto", "CryptoKit", "TadakDomain"]

    @Test("GSPack*.swift에 출력·오류 설명·전송 API가 없다")
    func noLoggingAPIs() throws {
        let sources = try Self.gspackSources()
        #expect(sources.count >= 7, "검사 대상 파일을 실제로 찾았다: \(sources.map(\.name))")
        for (name, text) in sources {
            for token in Self.forbiddenTokens {
                #expect(!text.contains(token), "\(name)에 \(token)")
            }
        }
    }

    @Test("GSPack*.swift는 OS 프레임워크와 도메인만 import한다")
    func importsAreOSOnly() throws {
        for (name, text) in try Self.gspackSources() {
            let imports = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("import ") || $0.hasPrefix("@testable import ") || $0.hasPrefix("@preconcurrency import ") }
                .compactMap { $0.split(separator: " ").last.map(String.init) }
            #expect(Set(imports).isSubset(of: Self.allowedImports), "\(name): \(imports)")
        }
    }

    @Test("검사가 실제로 잡는다 — 금칙 토큰을 넣은 글은 걸린다")
    func scannerCatches() {
        let sample = #"let x = 1; print(password); throw error.localizedDescription"#
        #expect(Self.forbiddenTokens.contains { sample.contains($0) })
    }

    /// `Packages/PackImport/Sources/PackImport/GSPack*.swift` — 이 시험 파일에서 거슬러 올라간다
    static func gspackSources() throws -> [(name: String, text: String)] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()   // PackImportTests · Tests
            .deletingLastPathComponent()                               // PackImport
            .appendingPathComponent("Sources/PackImport")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("GSPack") && $0.hasSuffix(".swift") }
            .sorted()
        return try names.map { ($0, try String(contentsOf: directory.appendingPathComponent($0), encoding: .utf8)) }
    }
}
