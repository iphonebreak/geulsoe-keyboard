/// 이모지 칩의 상태 — 뽑기(`EmojiDraw`, D9)와 탭 뒤 억제(Q10)를 한곳에 쥔다
/// (PDR `docs/design-reviews/emoji-word-suggestion.md` 1-2절·3-2절, 검증 ⑤-2a 참고 2).
///
/// 조립 지점은 추천단어 줄을 다시 계산할 때마다 `emoji(for:resolver:isUserEdit:)`를 부르고,
/// 결과를 `WordSuggestionCandidate.row(words:emoji:sourceWord:)`에 넘긴다.
///
/// ## 사용자 편집과 sync를 가른다 (검증 ⑤-2a 참고 2)
///
/// `EmojiDraw`의 계약은 「단어가 없거나 묶음이 비어도 부른다 — 그래야 다시 친 것을 안다」이다. 그런데
/// 호스트의 `textDidChange`(메아리)는 문맥을 **잠깐 비웠다가** 다시 줄 수 있다 — 그 중간값으로 부르면
/// 같은 단어인데 기억을 버려 이모지가 바뀐다(D9 위반). `EmojiDraw`는 「사용자가 다른 단어를 쳤다」와
/// 「sync 중간값」을 구별할 수 없으므로 여기서 가른다:
/// - **사용자 편집**(키·후보 탭 직후, `isUserEdit: true`) — 계약 그대로 부른다. 단어가 바뀌거나 비면 기억을 버린다
/// - **sync**(호스트 `textDidChange`·등장·설정 재로드, `false`) — **기억을 버리지도 새로 뽑지도 않는다.**
///   다시 세운 꼬리의 단어가 기억한 단어와 같을 때만 그 값을 보여 준다(`EmojiDraw.peek`)
///
/// ## 키보드를 내렸다 띄워도 같은 칩 (D16)
///
/// 조립 지점은 이 값을 **프로세스 수명**으로 둔다(`static` — `dismissedSnippetTail`과 같은 방식, VC는 등장마다 새로
/// 만들어진다). 등장 sync는 `peek`이라 커서 앞 단어가 **기억한 단어와 같으면 같은 값**을 다시 보여 주고, 다르면 칩이
/// 없다 — 그 단어는 사용자가 「다 친 순간」이 아니다(Q1). secure 입력란이면 `reset()`으로 비운다.
///
/// ## 탭 뒤 억제 (Q10·D3)
///
/// 혼합 칩 `[🚗 자동차]`를 탭해도 꼬리 끝 한글 run은 넣은 「자동차」라 같은 칩이 바로 다시 뜬다 — 두 번
/// 누르면 `🚗 🚗 자동차`다. 그래서 이모지 칩(혼합·전용) 탭 뒤에는 **문서 글자가 바뀐 입력이 올 때까지 전부 숨긴다**
/// (D17 — ⇧·한영·123처럼 문서를 안 바꾸는 키로는 안 풀린다. 풀렸다면 넣은 「자동차」에 새로 뽑은 칩이 떠
/// `🚕 🚗 자동차`가 됐다, 검증 ⑤-2b 참고 1). 조립 지점이 입력 앞뒤 `InputController.documentRevision`을 비교해
/// 바뀌었을 때만 `documentDidChange()`를 부른다. 탭한 칩의 기억도 버린다 — 다음에 뜨는 칩은 새로 뽑는다.
/// 숨김은 재표시를 넘어 이어진다(D16 — 다시 띄운 뒤 ⇧ 한 번에 겹침 칩이 뜨면 안 된다).
///
/// **기억은 메모리에만 있다** — 단어 하나와 이모지 하나. 기록·저장·로그 없음(보안 규칙).
public struct EmojiChipState: Sendable {

    private var draw = EmojiDraw()
    /// 이모지 칩 탭 뒤 참 — 문서 글자가 바뀐 입력(`documentDidChange`)에서 풀린다(D17)
    public private(set) var isSuppressedAfterTap = false

    public init() {}

    /// 이번 재계산에 실을 이모지 — nil이면 이모지 칩 없음(단어 칸은 원래 개수, D3).
    /// - Parameters:
    ///   - word: 꼬리를 **다시 세운 뒤**의 지금 단어(`InputController.currentWord`)
    ///   - resolver: nil이면 칩을 계산하지 않는다(설정 끔·secure·채움글 칩 등 게이트가 닫힘). 역색인을 보지 않는다
    ///   - isUserEdit: 사용자 편집 직후인가 — 위 「사용자 편집과 sync를 가른다」
    public mutating func emoji<G: RandomNumberGenerator>(
        for word: String, resolver: EmojiCandidateResolver?, isUserEdit: Bool, using generator: inout G
    ) -> String? {
        guard !isSuppressedAfterTap else { return nil }
        let candidates = resolver?.candidates(for: word) ?? []
        guard isUserEdit else { return draw.peek(for: word, in: candidates) }
        return draw.emoji(for: word, from: candidates, using: &generator)
    }

    /// 시스템 난수원으로 — 제품 경로.
    public mutating func emoji(for word: String, resolver: EmojiCandidateResolver?, isUserEdit: Bool) -> String? {
        var generator = SystemRandomNumberGenerator()
        return emoji(for: word, resolver: resolver, isUserEdit: isUserEdit, using: &generator)
    }

    /// 사용자 입력(키·단어 후보·채움글·붙여넣기·이모지 판·클립보드)이 **문서 글자를 실제로 바꿨다** — 탭 뒤 숨김을 푼다(D17).
    /// 조립 지점이 입력 앞뒤 `InputController.documentRevision`이 달라졌을 때만 부른다.
    public mutating func documentDidChange() {
        isSuppressedAfterTap = false
    }

    /// 이모지 칩(혼합·전용)을 탭했다 — 다음 사용자 편집까지 숨기고, 기억도 버린다(Q10).
    public mutating func emojiChipTapped() {
        isSuppressedAfterTap = true
        draw.reset()
    }

    /// secure 입력란이다 — 기억·숨김을 전부 비운다. 키보드가 내려가는 것으로는 비우지 않는다(D16).
    public mutating func reset() {
        draw.reset()
        isSuppressedAfterTap = false
    }
}
