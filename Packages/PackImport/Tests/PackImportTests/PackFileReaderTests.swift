import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 4단계 — 파일 제한 읽기 `PackFileReader`(계획서 3-2절 3-D: 읽기 전에 크기 상한, 보안 범위 URL은 읽은 즉시 해제).
// PDR AC-34 「제한 읽기 cap+1」 — 상한보다 한 바이트만 더 읽어 넘는지 안다(파일 전체를 메모리에 올리지 않는다).

private func temporaryFile(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-reader-\(UUID().uuidString).csv")
    try data.write(to: url)
    return url
}

@Suite("외부 채움글 1-c 4단계 — 파일 제한 읽기 (AC-34)")
struct PackFileReaderTests {

    @Test("상한 안의 파일은 바이트 그대로")
    func readsWholeFile() throws {
        let data = Data("번호,제목,본문\n1,가,나\n".utf8)
        let url = try temporaryFile(data)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PackFileReader.read(url, limit: 64) == .success(data))
    }

    @Test("★ 경계 — 정확히 상한이면 받고, 한 바이트라도 넘으면 fileTooLarge(내용은 돌려주지 않는다)",
          arguments: [(10, true), (11, false), (0, true)])
    func capPlusOne(size: Int, accepted: Bool) throws {
        let url = try temporaryFile(Data(repeating: 0x41, count: size))
        defer { try? FileManager.default.removeItem(at: url) }
        let result = PackFileReader.read(url, limit: 10)
        if accepted {
            #expect(result == .success(Data(repeating: 0x41, count: size)))
        } else {
            #expect(result == .failure(.structural(.fileTooLarge)))
        }
    }

    @Test("★ 크기 정보를 믿지 않는다 — 읽기 자체가 cap+1에서 멈추고 넘으면 거부(잘라서 받지 않는다)",
          arguments: [(10, true), (11, false), (4_096, false)])
    func boundedReadAlone(size: Int, accepted: Bool) throws {
        let url = try temporaryFile(Data(repeating: 0x42, count: size))
        defer { try? FileManager.default.removeItem(at: url) }
        let result = PackFileReader.boundedRead(url, limit: 10)
        #expect(result == (accepted ? .success(Data(repeating: 0x42, count: size)) : .failure(.structural(.fileTooLarge))))
    }

    @Test("★ 제품 상한(PackLimits.fileBytes) — cap+1 바이트 파일은 거부")
    func productCap() throws {
        let url = try temporaryFile(Data(count: PackLimits.fileBytes + 1))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PackFileReader.read(url) == .failure(.structural(.fileTooLarge)))
    }

    @Test("열 수 없는 파일은 fileUnreadable — 이유·경로를 담지 않는다")
    func missingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pack-reader-missing-\(UUID().uuidString).csv")
        #expect(PackFileReader.read(url) == .failure(.fileUnreadable))
    }
}
