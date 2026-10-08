/// 이모지 칩 뽑기 — **단어를 다 친 순간 한 번 뽑고, 칩이 떠 있는 동안 고정, 다시 치면 새로 뽑는다**
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 확정 결정 D9).
///
/// **사용자 편집**(키 입력·후보 탭) 뒤 재계산마다 지금 단어와 그 묶음(`EmojiCandidateResolver.candidates(for:)`)으로
/// `emoji(for:from:)`를 부른다 — **단어가 없거나 묶음이 비어도 부른다.** 그래야 「다른 단어가 됐다가(또는
/// 비었다가) 다시 그 단어」를 알아 새로 뽑는다. 호스트 sync 뒤에는 `peek(for:in:)`만 쓴다 — sync 중간값으로
/// 기억을 버리면 같은 단어인데 값이 바뀐다(검증 ⑤-2a 참고 2). 이 갈래는 `EmojiChipState`가 쥔다.
///
/// - 같은 단어가 이어서 오면(호스트 메아리 sync·재계산 포함) 같은 값 — 난수를 쓰지 않는다
/// - 단어가 바뀌거나 묶음이 비면 기억을 버린다 → 같은 단어가 다시 오면 새로 뽑는다
/// - 고정된 값이 묶음에서 빠지면(설정 재로드로 손질 목록이 바뀜) 같은 단어라도 새로 뽑는다
///
/// **기억하는 것은 지금 단어와 뽑은 이모지 하나뿐이고 메모리에만 있다** — 다음 단어에서 덮어쓰고,
/// 어디에도 기록·저장하지 않는다(보안 규칙 「입력 텍스트를 로그·파일·네트워크로 내보내지 않는다」).
/// 난수원을 주입받아(`RandomNumberGenerator`) 시드 고정 테스트가 결정적이다.
public struct EmojiDraw: Sendable {

    private var word: String?
    private var emoji: String?

    public init() {}

    public mutating func emoji<G: RandomNumberGenerator>(
        for word: String, from candidates: [String], using generator: inout G
    ) -> String? {
        guard !candidates.isEmpty else {
            reset()
            return nil
        }
        if word == self.word, let emoji, candidates.contains(emoji) {
            return emoji
        }
        let pick = candidates.randomElement(using: &generator)
        self.word = word
        self.emoji = pick
        return pick
    }

    /// 기억만 본다 — 같은 단어이고 고정 값이 아직 묶음 안이면 그 값, 아니면 nil. **기억을 버리지도 새로
    /// 뽑지도 않는다.** 사용자 편집이 아닌 재계산(호스트 sync)이 쓴다 — sync가 꼬리를 잠깐 비웠다 다시
    /// 세워도 값이 바뀌지 않게(검증 ⑤-2a 참고 2, `EmojiChipState`).
    public func peek(for word: String, in candidates: [String]) -> String? {
        guard word == self.word, let emoji, candidates.contains(emoji) else { return nil }
        return emoji
    }

    /// 시스템 난수원으로 뽑는다 — 제품 경로.
    public mutating func emoji(for word: String, from candidates: [String]) -> String? {
        var generator = SystemRandomNumberGenerator()
        return emoji(for: word, from: candidates, using: &generator)
    }

    /// 기억을 버린다 — secure 입력란·이모지 칩 탭 때 `EmojiChipState`가 부른다(키보드가 내려가는 것으로는 버리지 않는다 — D16).
    public mutating func reset() {
        word = nil
        emoji = nil
    }
}
