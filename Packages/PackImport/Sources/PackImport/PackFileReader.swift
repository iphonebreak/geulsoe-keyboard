import Foundation
import TadakDomain

/// 고른 파일을 **제한해서** 읽는다(계획서 3-2절 3-D, PDR AC-34 「제한 읽기 cap+1」).
///
/// - 크기 정보가 상한을 넘으면 열지 않는다. 크기 정보를 믿지 않고 **상한 + 1바이트까지만** 읽어 넘는지 안다 — 큰 파일을 통째로
///   메모리에 올리지 않는다.
/// - 보안 범위 URL(파일 앱 선택기)은 **읽은 직후 해제**한다(이 함수가 돌아올 때 이미 해제돼 있다).
/// - 실패는 내용 없는 코드다 — 파일 이름·경로·내용을 담지 않는다(AC-34). 읽은 바이트는 부르는 쪽 메모리에만 있다(로그·파일로 내보내지 않는다).
///
/// 파일 IO라 **메인 밖에서** 부른다(`read(_:limit:) async`).
public enum PackFileReader {

    public static func read(_ url: URL, limit: Int = PackLimits.fileBytes) -> Result<Data, PackImportProblem> {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
            return .failure(.structural(.fileTooLarge))
        }
        // iCloud 등 내려받기가 필요한 파일도 읽히게 조정자를 거친다(읽기만, 바꾸지 않음)
        var result: Result<Data, PackImportProblem> = .failure(.fileUnreadable)
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { readURL in
            result = boundedRead(readURL, limit: limit)
        }
        return coordinationError == nil ? result : .failure(.fileUnreadable)
    }

    /// 메인 밖에서 — 화면은 `await` 동안 멈추지 않는다
    public static func read(_ url: URL, limit: Int = PackLimits.fileBytes,
                            queue: DispatchQueue = .global(qos: .userInitiated)) async -> Result<Data, PackImportProblem> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: read(url, limit: limit)) }
        }
    }

    /// 크기 정보를 믿지 않는 두 번째 방어 — 상한 + 1바이트에서 멈춘다(크기 정보가 없거나 틀린 파일·그 사이 커진 파일)
    static func boundedRead(_ url: URL, limit: Int) -> Result<Data, PackImportProblem> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.fileUnreadable) }
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: limit + 1 - data.count)
            } catch {
                return .failure(.fileUnreadable)
            }
            // 파일 끝이면 nil(또는 빈 Data)
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
        }
        return data.count > limit ? .failure(.structural(.fileTooLarge)) : .success(data)
    }
}
