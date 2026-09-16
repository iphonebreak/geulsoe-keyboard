import TadakDomain

/// 툴바 추천 칩 하나 — 탭하면 **단축어**를 지우고 본문을 넣는다.
public struct SnippetSuggestion: Equatable, Sendable {
    /// 문서 꼬리에서 지울 **단축어 원문**(사용자가 실제로 친 그대로 — 띄어쓰기 포함). 길이만 들고 있으면 탭 시점에 꼬리가 이미 바뀌었어도
    /// 그만큼 지워 버린다 — 칩을 두 번 누르면 방금 삽입한 본문 끝이 잘려 나갔다 (QA BLOCK-2).
    /// 삽입 직전에 꼬리와 대조하는 것이 이 값의 목적이다.
    public let trigger: String
    public let title: String
    public let body: String
    /// 본문 앞에 함께 삽입되는 머리말 — 성경은 "[고전 12:3] " (사용자 결정 2026-09-03:
    /// 붙여넣은 본문이 어느 절인지 보이게). **사용자가 친 단축어 원문을 그대로 되비춘다**
    /// (2026-09-14) — 정규 표기로 바꾸지 않는다. 문구 팩·사용자 문구는 nil.
    public let prefix: String?

    /// 문서 끝에서 지울 문자 수 — **꼬리 원문 기준**이다(정규화 길이가 아니다).
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

/// 입력 꼬리에서 채움글 **단축어**를 찾는다.
///
/// 우선순위: 문구 목록(entries — 사용자 문구를 내장 팩보다 앞에 넣는다) > 성경 참조(단일 절·절 범위).
/// 문구끼리 겹치면 **정규화 길이가 긴** 단축어가 이기고, 같으면 앞선 항목(=사용자)이 이긴다.
/// 후보는 1건만 낸다 — 다중 후보는 Phase 5 추천단어 바에 합류할 때 확장한다 (PDR).
///
/// ## ★ 띄어쓰기를 보지 않는다 (2026-09-15 사장님 지시)
///
/// "우리집주소"로 등록해도 **"우리집 주소"·"우 리 집 주 소"** 로 발동한다.
/// 정규화는 **공백·개행 제거**다(`filter { !$0.isWhitespace }`).
///
/// **지울 길이는 정규화 길이가 아니라 꼬리 원문에서 실제로 맞은 구간의 길이다.**
/// 5자짜리 단축어로 등록했어도 사용자가 6자를 쳤으면 6자를 지워야 한다.
/// 그래서 `SnippetSuggestion.trigger` 에는 **꼬리에서 잘라낸 원문 그대로**를 담는다 —
/// 탭 시점의 꼬리 정합 검사(QA BLOCK-2 방어)가 그 값으로 돈다.
///
/// **범위는 `entries` 경로 전부다** — 사용자 문구와 내장 팩(애국가·인사말)까지.
/// **성경 참조 파서(`BibleReferenceParser`)는 건드리지 않는다** — 규칙을 하나로 두기 위한 결정이고
/// 거긴 이미 "애국가1절"·"애국가 1절" 양쪽을 자기 규칙으로 받는다.
///
/// ## 성능 — 키 입력마다 도는 핫패스다
///
/// - 정규화된 단축어는 **`init` 에서 미리 계산**해 둔다. 매 호출마다 다시 만들지 않는다.
/// - 꼬리도 진입 시 **한 번만** 역방향으로 풀어(비공백 글자 + 원문 인덱스) 모든 엔트리가 공유한다.
///   그래서 O(꼬리 48 + 엔트리 수 × 단축어 길이)다.
public struct SnippetMatcher: Sendable {

    /// 미리 정규화해 둔 단축어 하나 — 엔트리 순서와 함께 든다.
    private struct Needle: Sendable {
        /// 공백을 뺀 글자들. 매칭은 이 배열을 **뒤에서 앞으로** 훑는다.
        let characters: [Character]
        /// 이 단축어가 속한 엔트리의 인덱스 — 동점일 때 앞선 엔트리가 이기게 한다.
        let entryIndex: Int
    }

    private let bible: (any BibleVerseRepository)?
    private let entries: [SnippetEntry]
    /// 정규화 길이 **내림차순**으로 미리 정렬해 둔다 — 첫 매치가 곧 최선이라 나머지를 안 본다.
    /// 길이가 같으면 `entryIndex` 오름차순(= 앞선 엔트리 우선).
    private let needles: [Needle]

    /// - Parameters:
    ///   - bible: 성경 본문 저장소. nil이면 성경 매칭을 건너뛴다.
    ///   - entries: 단축어 문구 목록. **사용자 문구 → 내장 팩 순서로 합쳐 넣는다.**
    /// 성경 후보 삽입 시 `[창세기 1장 1절] `(친 그대로) 머리말을 앞에 넣을지
    /// (설정 `bibleSnippetPrefixEnabled`, 2026-09-07)
    private let biblePrefix: Bool

    /// - Parameter biblePrefix: 성경 머리말 여부 (기본 켬)
    public init(bible: (any BibleVerseRepository)?, entries: [SnippetEntry], biblePrefix: Bool = true) {
        self.bible = bible
        self.entries = entries
        self.biblePrefix = biblePrefix
        // 정규화는 **여기서 한 번만** 한다 (핫패스 규율).
        // 공백만으로 이뤄진 단축어와 빈 단축어는 아예 목록에 넣지 않는다 — 꼬리 어디에나
        // 맞아 버리는 것을 원천 차단한다.
        var built: [Needle] = []
        for (index, entry) in entries.enumerated() {
            for trigger in entry.triggers {
                // **정규화는 `SnippetEntry.normalizedTrigger` 한 곳에서만** 정의한다 —
                // 설정 화면의 중복 판정과 여기의 발동 규칙이 갈리면 안 된다.
                let characters = Array(SnippetEntry.normalizedTrigger(trigger))
                guard !characters.isEmpty else { continue }
                built.append(Needle(characters: characters, entryIndex: index))
            }
        }
        built.sort {
            $0.characters.count != $1.characters.count
                ? $0.characters.count > $1.characters.count      // 긴 쪽이 먼저
                : $0.entryIndex < $1.entryIndex                   // 같으면 앞선 엔트리
        }
        needles = built
    }

    public func suggestion(forTail tail: String) -> SnippetSuggestion? {
        guard !tail.isEmpty else { return nil }

        // 꼬리를 **한 번만** 뒤에서 앞으로 풀어 둔다 — 비공백 글자와 그 글자의 원문 인덱스.
        // 모든 단축어가 이 배열 하나를 공유한다.
        let characters = Array(tail)
        var reversed: [(character: Character, index: Int)] = []
        reversed.reserveCapacity(characters.count)
        for index in stride(from: characters.count - 1, through: 0, by: -1)
        where !characters[index].isWhitespace {
            reversed.append((characters[index], index))
        }

        // `needles` 는 정규화 길이 내림차순이라 **첫 매치가 곧 최선**이다.
        for needle in needles {
            guard needle.characters.count <= reversed.count else { continue }
            var matched = true
            for offset in 0..<needle.characters.count
            where reversed[offset].character != needle.characters[needle.characters.count - 1 - offset] {
                matched = false
                break
            }
            guard matched else { continue }
            // 잘라낼 구간은 **마지막으로 맞은 글자**에서 꼬리 끝까지 —
            // 그 앞의 공백은 포함하지 않는다("보내줄게 우리집 주소"에서 앞 공백을 안 먹는다).
            let start = reversed[needle.characters.count - 1].index
            let entry = entries[needle.entryIndex]
            return SnippetSuggestion(
                trigger: String(characters[start...]),
                title: entry.title, body: entry.body)
        }

        if let bible,
           let match = BibleReferenceParser.matchSuffix(of: tail),
           let text = Self.body(for: match, in: bible) {
            // 머리말은 **사용자가 친 단축어 원문 그대로**다 (사용자 보고 2026-09-14).
            // `match.display`(정규 표기)를 쓰면 "창세기 1장 1절"을 친 사람도 `[창세기 1:1] `을
            // 받아 표기가 제멋대로 바뀐다. 칩 제목(`title`)은 정규 표기를 그대로 쓴다.
            let trigger = String(tail.suffix(match.matchedLength))
            return SnippetSuggestion(
                trigger: trigger,
                title: match.display, body: text,
                prefix: biblePrefix ? "[\(trigger)] " : nil)
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
    ///
    /// **본문이 빈 절도 "없는 절"과 똑같이 다룬다**(`nonEmpty`). 조회는 성공했는데 본문이
    /// 비어 있으면 사용자에게는 "칩을 눌렀는데 아무 것도 안 들어갔다"가 된다 —
    /// 2026-09-15 에 실제로 그랬다(정본이 "1-2" 로 묶어 인쇄한 합병절의 뒷절 6개가 원본
    /// 데이터에서 빈 문자열이었다: 사 30:2 · 사 48:2 · 렘 21:2 · 겔 24:5 · 행 15:26 · 롬 9:2).
    /// 데이터는 고쳤고 `tools/convert_bible.py` 가 재발을 막지만, **매처도 데이터를 믿지 않는다.**
    private static func body(
        for match: BibleReferenceParser.Match, in bible: any BibleVerseRepository
    ) -> String? {
        guard match.isRange else {
            return nonEmpty(bible.text(book: match.book, chapter: match.chapter, verse: match.verse))
        }
        var lines: [String] = []
        lines.reserveCapacity(match.verses.count)
        for verse in match.verses {
            guard let text = nonEmpty(
                bible.text(book: match.book, chapter: match.chapter, verse: verse))
            else { return nil }
            lines.append("\(verse) \(text)")
        }
        return lines.joined(separator: "\n")
    }

    /// 공백만 남는 본문은 없는 것으로 본다 — 눈에 비어 보이는 것이 사용자에게는 같은 버그다.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }
}
