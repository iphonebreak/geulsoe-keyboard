import TadakDomain

/// 툴바 추천 칩 하나 — 탭하면 트리거를 지우고 본문을 넣는다.
public struct SnippetSuggestion: Equatable, Sendable {
    /// 문서 꼬리에서 지울 트리거 **원문**. 길이만 들고 있으면 탭 시점에 꼬리가 이미 바뀌었어도
    /// 그만큼 지워 버린다 — 칩을 두 번 누르면 방금 삽입한 본문 끝이 잘려 나갔다 (QA BLOCK-2).
    /// 삽입 직전에 꼬리와 대조하는 것이 이 값의 목적이다.
    public let trigger: String
    public let title: String
    public let body: String
    /// 본문 앞에 함께 삽입되는 머리말 — 성경은 "[고린도전서 12:3] " (사용자 결정 2026-09-03:
    /// 붙여넣은 본문이 어느 절인지 보이게). 문구 팩·사용자 문구는 nil.
    public let prefix: String?

    /// 문서 끝에서 지울 문자 수 (트리거가 차지한 길이)
    public var triggerLength: Int { trigger.count }

    public init(trigger: String, title: String, body: String, prefix: String? = nil) {
        self.trigger = trigger
        self.title = title
        self.body = body
        self.prefix = prefix
    }

    /// 실제로 문서에 들어가는 텍스트
    public var insertedText: String { (prefix ?? "") + body }
}

/// 입력 꼬리에서 채움글 트리거를 찾는다.
///
/// 우선순위: 문구 목록(entries — 사용자 문구를 내장 팩보다 앞에 넣는다) > 성경 참조(단일 절·절 범위).
/// 문구끼리 겹치면 긴 트리거가 이기고, 길이가 같으면 앞선 항목(=사용자)이 이긴다.
/// 후보는 1건만 낸다 — 다중 후보는 Phase 5 추천단어 바에 합류할 때 확장한다 (PDR).
///
/// 매칭은 키 입력 후 1회, 48자 이내 문자열 검사 + 이진 탐색이라 핫패스 부담이 없다.
public struct SnippetMatcher: Sendable {

    private let bible: (any BibleVerseRepository)?
    private let entries: [SnippetEntry]

    /// - Parameters:
    ///   - bible: 성경 본문 저장소. nil이면 성경 매칭을 건너뛴다.
    ///   - entries: 트리거 문구 목록. **사용자 문구 → 내장 팩 순서로 합쳐 넣는다.**
    /// 성경 후보 삽입 시 `[창세기 1:1] ` 머리말을 앞에 넣을지 (설정 `bibleSnippetPrefixEnabled`, 2026-09-07)
    private let biblePrefix: Bool

    /// - Parameter biblePrefix: 성경 머리말 여부 (기본 켬)
    public init(bible: (any BibleVerseRepository)?, entries: [SnippetEntry], biblePrefix: Bool = true) {
        self.bible = bible
        self.entries = entries
        self.biblePrefix = biblePrefix
    }

    public func suggestion(forTail tail: String) -> SnippetSuggestion? {
        guard !tail.isEmpty else { return nil }

        var best: SnippetEntry?
        for entry in entries
        where !entry.trigger.isEmpty && tail.hasSuffix(entry.trigger) {
            if entry.trigger.count > (best?.trigger.count ?? 0) {
                best = entry
            }
        }
        if let best {
            return SnippetSuggestion(
                trigger: best.trigger, title: best.title, body: best.body)
        }

        if let bible,
           let match = BibleReferenceParser.matchSuffix(of: tail),
           let text = Self.body(for: match, in: bible) {
            return SnippetSuggestion(
                trigger: String(tail.suffix(match.matchedLength)),
                title: match.display, body: text,
                prefix: biblePrefix ? "[\(match.display)] " : nil)
        }
        return nil
    }

    /// 참조가 가리키는 본문을 만든다.
    ///
    /// 범위(`창 1:1~13`)는 절마다 단일 조회를 반복한다 — `BibleVerseRepository`를 그대로 두기
    /// 위한 선택이다. 인접 절은 인덱스에서도 붙어 있어 mmap 페이지가 이미 따뜻하고, 절 수는
    /// `BibleReferenceParser.maxRangeVerses`로 이미 막혀 있다 (PDR bible-verse-range).
    ///
    /// 삽입 형식: 절마다 `"번호 본문"`, 줄바꿈으로 잇는다. 단일 절은 기존 그대로 번호 없이 본문만.
    /// **한 절이라도 없으면 nil** — 장 끝을 넘긴 범위에 칩을 띄우지 않기 위한 fail-closed다
    /// (단일 절이 존재하지 않을 때 칩이 안 뜨는 기존 규칙과 같다).
    private static func body(
        for match: BibleReferenceParser.Match, in bible: any BibleVerseRepository
    ) -> String? {
        guard match.isRange else {
            return bible.text(book: match.book, chapter: match.chapter, verse: match.verse)
        }
        var lines: [String] = []
        lines.reserveCapacity(match.verses.count)
        for verse in match.verses {
            guard let text = bible.text(book: match.book, chapter: match.chapter, verse: verse)
            else { return nil }
            lines.append("\(verse) \(text)")
        }
        return lines.joined(separator: "\n")
    }
}
