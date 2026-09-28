import Foundation

/// 이모지 「최근 사용」 기록 — 최근순, 최대 16개 (v1.2.0 ⑤, PDR `docs/design-reviews/emoji-recent-persist.md`).
///
/// ## 어디에 저장되나 — 키보드 전용 컨테이너 (App Group 아님)
///
/// 저장소 구현은 TadakData `KeyboardOwnEmojiHistoryRepository` — 익스텐션 **자신의** `UserDefaults`다.
/// Apple: 키보드 샌드박스는 *"prevents writing to the containing app's shared group containers"* —
/// 막히는 것은 앱과 나눠 쓰는 App Group 쓰기뿐이라 **전체 접근과 무관하게** 저장된다.
/// 그래서 키보드의 App Group 쓰기(학습 단어·클립보드 기록)는 늘지 않는다.
///
/// ## 「끄면 삭제」 — 앱이 직접 못 지운다, 토큰으로 알린다
///
/// 설정 앱은 키보드 전용 컨테이너에 **접근할 수 없다**(다른 샌드박스). 그래서 끌 때 설정의
/// `emojiHistoryResetToken`을 올리고, 키보드가 **다음에 뜰 때·다음 이모지를 누를 때** 이 타입의
/// `reconciled`로 스스로 비운다. 기록이 **자기가 마지막으로 반영한 토큰(`resetToken`)을 함께 들고**
/// 있어야 프로세스가 새로 떠도 「끈 적이 있다」를 알아챈다 — 학습 단어처럼 메모리에만 들면
/// 재시작 뒤 모른다(학습 단어는 앱이 App Group을 직접 비울 수 있어 그걸로 충분했다).
///
/// ## 판정은 여기 — 조립 지점은 읽고 쓰기만
///
/// `reconciled`(등장 때)·`afterTap`(탭 때)이 순수 함수라 `swift test`가 닿는다(반론자1 급소⑤-1).
public struct EmojiHistory: Codable, Equatable, Sendable {

    public static let maxEntries = 16

    /// 최근순. 첫 원소가 가장 최근.
    public private(set) var entries: [String]
    /// 이 기록을 마지막으로 맞출 때 반영한 설정 초기화 토큰
    public private(set) var resetToken: Int

    /// 순서를 보존하며 중복을 없애고 상한을 적용한다 — 뷰가 이모지 문자열을 id로 쓰므로 저장분이
    /// 손상돼도 중복 id가 생기지 않게 한다(디코딩도 이 경로를 탄다, `ClipboardHistory`와 같은 방어).
    public init(entries: [String] = [], resetToken: Int = 0) {
        var seen = Set<String>()
        self.entries = Array(entries.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(Self.maxEntries))
        self.resetToken = resetToken
    }

    private enum CodingKeys: String, CodingKey { case entries, resetToken }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            entries: try container.decodeIfPresent([String].self, forKey: .entries) ?? [],
            resetToken: try container.decodeIfPresent(Int.self, forKey: .resetToken) ?? 0)
    }

    /// 맨 앞에 기록한다 — 중복은 맨 앞으로, 16개 상한, 빈 문자열 무시.
    public mutating func record(_ emoji: String) {
        guard !emoji.isEmpty else { return }
        entries.removeAll { $0 == emoji }
        entries.insert(emoji, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }

    /// 설정과 맞춘 **지금 보여 줄 기록**. 꺼져 있거나 토큰이 다르면(설정 앱이 끈 적이 있다) 빈 기록이고,
    /// 새 토큰을 든다 — 다음 확인 때 또 지우지 않게. 결과가 저장분과 다르면 조립 지점이 저장한다.
    public func reconciled(enabled: Bool, resetToken: Int) -> EmojiHistory {
        guard enabled, resetToken == self.resetToken else {
            return EmojiHistory(entries: [], resetToken: resetToken)
        }
        return self
    }

    /// 이모지 탭 뒤 **저장할 기록** — 저장할 것이 없으면 nil.
    ///
    /// **쓰기 직전에 설정을 다시 읽어** 넘긴다(학습 단어 선례, `KeyboardViewController.onWordCommitted`) —
    /// 아이패드 병렬 사용 중 설정 앱이 꺼도 옛 목록을 되살리지 않는다.
    /// - secure 입력란이거나 꺼져 있으면 **기록하지 않는다**(secure 제외는 v1.2.0에 새로 생긴 규칙 — PDR 5절).
    ///   단 토큰 불일치·꺼짐으로 **비워야 할 것**이 있으면 비운 기록을 돌려준다.
    public static func afterTap(
        _ emoji: String, stored: EmojiHistory, enabled: Bool, resetToken: Int, isSecureTextEntry: Bool
    ) -> EmojiHistory? {
        var history = stored.reconciled(enabled: enabled, resetToken: resetToken)
        guard enabled, !isSecureTextEntry else {
            return history == stored ? nil : history
        }
        history.record(emoji)
        return history
    }
}

/// 이모지 기록 저장 경계. 제품 구현은 **키보드 전용 컨테이너**(TadakData `KeyboardOwnEmojiHistoryRepository`).
/// 실기에서 그 컨테이너가 재시작 뒤 비는 것으로 밝혀지면 이 프로토콜 뒤 구현체 하나만 바꿔 끼운다
/// (PDR 6-3절 후퇴안 — 조립 지점의 한 줄).
public protocol EmojiHistoryRepository: Sendable {
    /// 실패하지 않는다 — 없거나 읽지 못하면 빈 기록.
    func load() -> EmojiHistory
    @discardableResult
    func save(_ history: EmojiHistory) -> Bool
    func clear()
}
