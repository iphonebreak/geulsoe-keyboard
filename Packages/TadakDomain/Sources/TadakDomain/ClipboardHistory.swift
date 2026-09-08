import Foundation

/// 클립보드 기록 — 키보드가 열려 있던 시점에 읽은 클립보드 문자열의 누적 (최근순).
///
/// 백그라운드 감시는 불가능하므로 "복사한 모든 것"이 아니라 "키보드가 본 것"이다
/// (PDR clipboard-history). 내용은 App Group 밖으로 나가지 않는다 (보안 규칙).
public struct ClipboardHistory: Codable, Equatable, Sendable {

    public static let maxEntries = 30
    public static let maxEntryLength = 2_000

    /// 최근순. 첫 원소가 가장 최근.
    public private(set) var entries: [String]

    /// 순서를 보존하며 중복을 제거한다 — UI가 항목 문자열을 id로 쓰므로 저장분이 손상돼도
    /// 중복 id가 생기지 않게 한다 (디코딩도 이 경로를 탄다).
    public init(entries: [String] = []) {
        var seen = Set<String>()
        self.entries = entries.filter { seen.insert($0).inserted }
    }

    private enum CodingKeys: String, CodingKey { case entries }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(entries: try container.decodeIfPresent([String].self, forKey: .entries) ?? [])
    }

    /// 새 클립보드 내용을 기록한다. 빈 문자열은 무시, 중복은 맨 위로 이동, 상한·절단 적용.
    /// - Returns: 기록이 실제로 바뀌었는가 (저장 여부 판단용).
    @discardableResult
    public mutating func record(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let clipped = String(trimmed.prefix(Self.maxEntryLength))
        if entries.first == clipped { return false }
        entries.removeAll { $0 == clipped }
        entries.insert(clipped, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        return true
    }

    public mutating func remove(_ text: String) {
        entries.removeAll { $0 == text }
    }

    public mutating func removeAll() {
        entries.removeAll()
    }
}

/// 클립보드 기록 저장 경계 — **키보드가 쓰는 App Group 데이터** (Full Access 필요).
/// 설정 앱은 끄기·지우기 경로에서 `clear()`만 쓴다.
public protocol ClipboardHistoryRepository: Sendable {
    func load() -> ClipboardHistory
    @discardableResult
    func save(_ history: ClipboardHistory) -> Bool
    func clear()
}
