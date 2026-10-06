import Foundation

/// 붙여넣기 화면의 개요 — 줄 수와, 하나로 정해지면 칸 나누기(시안 3-E 「42줄 · 칸 나누기: 탭」). **보여 주기용**이다 — 실제 읽기는 「읽기」를
/// 누른 뒤 `PackImportSession`이 처음부터 다시 판정한다. 붙인 글은 사용자 데이터라 이 값은 개수와 구분자만 든다(글을 들지 않는다)
public struct PackPasteOverview: Equatable, Sendable {
    public let lines: Int
    public let delimiter: CSVDelimiter?

    public init(lines: Int, delimiter: CSVDelimiter?) {
        self.lines = lines
        self.delimiter = delimiter
    }

    /// 줄 수는 줄바꿈 수 + 1(마지막이 줄바꿈이면 그 줄은 세지 않는다). 칸 나누기는 앞부분만 보는 후보 시험(`PackImporter.likelyDelimiter`)
    public static func of(_ text: String) -> PackPasteOverview {
        let breaks = text.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        return PackPasteOverview(lines: breaks + (text.hasSuffix("\n") ? 0 : 1), delimiter: PackImporter.likelyDelimiter(text))
    }

    /// `of`를 전역 큐에서(큰 글이 메인을 막지 않게). 기다리는 사이 부른 작업이 취소됐으면(글이 또 바뀌었다) nil — 늦은 결과가 새 글의
    /// 「n줄」을 덮지 않게(검증 F-8 ③ — 화면은 `.task(id: text)`라 글이 바뀌면 앞 작업이 취소된다)
    public static func perform(_ text: String, queue: DispatchQueue = .global(qos: .userInitiated)) async -> PackPasteOverview? {
        let overview = await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: of(text)) }
        }
        return Task.isCancelled ? nil : overview
    }
}
