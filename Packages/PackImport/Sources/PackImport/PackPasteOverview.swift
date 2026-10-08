import Foundation
import TadakDomain

/// 붙여넣기 화면의 개요 — 줄 수와, 하나로 정해지면 칸 나누기(시안 3-E 「42줄 · 칸 나누기: 탭」). **보여 주기용**이다 — 실제 읽기는 「읽기」를
/// 누른 뒤 `PackImportSession`이 처음부터 다시 판정한다. 붙인 글은 사용자 데이터라 이 값은 개수와 구분자만 든다(글을 들지 않는다)
public struct PackPasteOverview: Equatable, Sendable {
    public let lines: Int
    public let delimiter: CSVDelimiter?
    /// 글이 3MB(파일과 같은 바이트 상한, 4절 제한 읽기)를 넘는다 — 줄 수·칸 나누기를 **세지 않았다**(codex 반론 #3). 「읽기」도 같은 상한으로
    /// 계산 없이 거부하므로 화면은 그 문구를 미리 보인다(`PackImportCopy.pasteSummary(_:)`)
    public let isTooLarge: Bool

    public init(lines: Int, delimiter: CSVDelimiter?, isTooLarge: Bool = false) {
        self.lines = lines
        self.delimiter = delimiter
        self.isTooLarge = isTooLarge
    }

    static let tooLarge = PackPasteOverview(lines: 0, delimiter: nil, isTooLarge: true)

    /// 줄 수는 줄바꿈 수 + 1(마지막이 줄바꿈이면 그 줄은 세지 않는다). 칸 나누기는 앞부분만 보는 후보 시험(`PackImporter.likelyDelimiter`).
    /// 3MB를 넘으면 세지 않는다(`isTooLarge`)
    public static func of(_ text: String) -> PackPasteOverview {
        measure(text) { false } ?? .tooLarge
    }

    /// `of`의 몸통 — **상한을 먼저** 보고(넘으면 아무것도 세지 않는다), 무거운 칸 나누기 시험(글자 단위 파싱) 중에도 몇 천 글자마다 취소를
    /// 본다(codex 반론 #3). 줄 세기는 바이트 한 번 훑기(3MB에 수 ms)라 따로 묻지 않는다. 취소되면 nil
    static func measure(_ text: String, isCancelled: @escaping () -> Bool) -> PackPasteOverview? {
        guard text.utf8.count <= PackLimits.fileBytes else { return .tooLarge }
        let cancellation = PackCancellation(isCancelled)
        let breaks = text.utf8.reduce(0) { $0 + ($1 == UInt8(ascii: "\n") ? 1 : 0) }
        let delimiter = PackImporter.likelyDelimiter(text, cancellation: cancellation)
        guard !cancellation.isCancelled else { return nil }
        return PackPasteOverview(lines: breaks + (text.hasSuffix("\n") ? 0 : 1), delimiter: delimiter)
    }

    /// 「붙여넣기」 버튼이 받은 글들을 줄바꿈으로 잇는다 — **잇기 전에** 바이트(구분자 줄바꿈 포함)를 센다(codex 반론 #3). 3MB를 넘으면
    /// 잇지 않고 nil — 화면은 글을 바꾸지 않고 「너무 길어요」를 보인다
    public static func joinedPaste(_ strings: [String]) -> String? {
        var total = max(0, strings.count - 1)
        for string in strings {
            total += string.utf8.count
            if total > PackLimits.fileBytes { return nil }
        }
        return strings.joined(separator: "\n")
    }

    /// `measure`를 전역 큐에서(큰 글이 메인을 막지 않게). 부른 작업이 취소되면(글이 또 바뀌었다) **계산 중에도** 멈추고 nil — 늦은 결과가
    /// 새 글의 「n줄」을 덮지 않게(검증 F-8 ③ — 화면은 `.task(id: text)`라 글이 바뀌면 앞 작업이 취소된다)
    public static func perform(_ text: String, queue: DispatchQueue = .global(qos: .userInitiated)) async -> PackPasteOverview? {
        let flag = CancellationFlag()
        let overview = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: measure(text, isCancelled: flag.isRaised)) }
            }
        } onCancel: {
            flag.raise()
        }
        return Task.isCancelled ? nil : overview
    }
}

/// 작업 취소를 큐 안의 계산에 넘기는 깃발 — 취소 처리기가 올리고, 계산이 몇 천 글자마다 본다
private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func raise() { lock.withLock { raised = true } }
    @Sendable func isRaised() -> Bool { lock.withLock { raised } }
}
