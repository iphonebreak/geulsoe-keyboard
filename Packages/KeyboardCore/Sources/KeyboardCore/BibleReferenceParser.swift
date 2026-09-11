/// 입력 꼬리 접미사에서 성경 참조("창세기 1장 1절", "창 1:1", "창세기 1:1~13")를 찾는 구문 파서.
///
/// 여기는 **구문만** 안다 — 절이 실제로 존재하는지는 `BibleVerseRepository`(TadakData 구현)가
/// 판정한다. 책 이름 66권 테이블은 자판·데이터와 무관한 순수 도메인 지식이라 KeyboardCore에
/// 둔다 (의존성 규칙 유지). 매칭 규칙은 `docs/design-reviews/snippet-autocomplete.md`,
/// 절 범위는 `docs/design-reviews/bible-verse-range.md` 참조.
///
/// 책 이름 앞은 꼬리 시작 또는 비한글 문자여야 한다 — 한글 run 전체를 잘라 정확 일치만
/// 인정하므로 "그러나 1:1"의 "나"가 나훔으로 오인되지 않는다.
public enum BibleReferenceParser {

    public struct Match: Equatable, Sendable {
        public let book: Int
        public let chapter: Int
        /// 범위의 시작 절. 단일 절이면 `endVerse`와 같다.
        public let verse: Int
        /// 범위의 끝 절 (포함). 단일 절이면 `verse`와 같다.
        public let endVerse: Int
        /// 꼬리 끝에서 트리거가 차지하는 문자 수 (삽입 시 지울 개수)
        public let matchedLength: Int
        /// 추천 칩 제목 (예: "창세기 1:1", "창세기 1:1-13")
        public let display: String

        /// 조회할 절 구간. 파서가 `verse <= endVerse`를 보장한다.
        public var verses: ClosedRange<Int> { verse...endVerse }
        /// 두 절 이상인 범위 구문이면 참 (`창 1:1~1`처럼 접힌 범위는 거짓)
        public var isRange: Bool { endVerse > verse }
    }

    /// 한 번에 넣을 수 있는 최대 절 수. 초과하면 참조로 보지 않아 칩이 뜨지 않는다.
    /// 개역한글 1,189장 중 94.9%가 50절 이하라 "장 전체 인용"도 대부분 들어온다.
    /// 근거·측정: `docs/design-reviews/bible-verse-range.md`
    public static let maxRangeVerses = 50

    /// 범위 구분자. `~`(기호 2페이지)와 `-`(기호 1페이지)가 이 키보드로 칠 수 있는 둘이고,
    /// 나머지는 붙여넣기·타 키보드로 들어올 수 있는 같은 뜻의 문자다.
    /// em dash(—)는 범위 기호가 아니라 문장 부호라 넣지 않는다 (PDR).
    private static let rangeSeparators: Set<Character> = [
        "~",   // U+007E TILDE
        "-",   // U+002D HYPHEN-MINUS
        "\u{FF5E}",  // ～ 전각 물결
        "\u{301C}",  // 〜 물결 대시
        "\u{2013}"   // – en dash (영문 범위 표기)
    ]

    /// 꼬리의 접미사가 성경 참조 구문이면 Match를 낸다. 받는 형태:
    /// - `이름 (공백?) N장 (공백?) M절` / `이름 (공백?) N:M`
    /// - 범위: `… M(공백?)구분자(공백?)K절` / `… M절~K절` / `… N:M~K`
    ///
    /// 역순 범위(`창 1:13~1`)와 `maxRangeVerses` 초과는 참조로 보지 않는다.
    /// 장을 넘는 범위(`창 1:30~2:2`)는 지원하지 않는다 (PDR).
    public static func matchSuffix(of tail: String) -> Match? {
        let chars = Array(tail)
        var i = chars.count - 1
        guard i >= 2 else { return nil }

        let verse: Int
        let endVerse: Int
        if chars[i] == "절" {
            // 형태 A: …N장 M절 / …N장 M~K절 / …N장 M절~K절
            i -= 1
            guard let last = readNumberBackward(chars, &i) else { return nil }
            endVerse = last
            verse = readRangeStartBackward(chars, &i, allowingJeolSuffix: true) ?? last
            skipOneSpaceBackward(chars, &i)
            guard i >= 0, chars[i] == "장" else { return nil }
            i -= 1
        } else {
            // 형태 B: …N:M / …N:M~K
            guard let last = readNumberBackward(chars, &i) else { return nil }
            endVerse = last
            verse = readRangeStartBackward(chars, &i, allowingJeolSuffix: false) ?? last
            guard i >= 0, chars[i] == ":" else { return nil }
            i -= 1
        }

        guard let chapter = readNumberBackward(chars, &i) else { return nil }
        skipOneSpaceBackward(chars, &i)

        // 책 이름 — 한글 run 전체를 잘라 정확 일치만 인정한다
        let nameEnd = i
        while i >= 0, isHangulSyllable(chars[i]) { i -= 1 }
        guard nameEnd > i else { return nil }
        let name = String(chars[(i + 1)...nameEnd])
        guard let book = Self.bookNumbers[name], chapter >= 1, verse >= 1 else { return nil }
        // 역순 범위는 의도가 모호해 받지 않고, 상한 초과는 조회 전에 걸러 낸다 (PDR)
        guard endVerse >= verse, endVerse - verse + 1 <= Self.maxRangeVerses else { return nil }

        // "요한 계시록"처럼 띄어 친 두 단어 별칭 — 앞말까지 트리거로 포함해야
        // 삽입 시 "요한 " 잔여물이 남지 않는다. 앞말 run이 정확히 "요한"일 때만 확장한다.
        var matchStart = i + 1
        if name == "계시록", i >= 2, chars[i] == " ",
           chars[i - 2] == "요", chars[i - 1] == "한",
           i - 3 < 0 || !isHangulSyllable(chars[i - 3]) {
            matchStart = i - 2
        }

        let fullName = Self.fullNames[book - 1]
        return Match(
            book: book,
            chapter: chapter,
            verse: verse,
            endVerse: endVerse,
            matchedLength: chars.count - matchStart,
            display: endVerse > verse
                ? "\(fullName) \(chapter):\(verse)-\(endVerse)"
                : "\(fullName) \(chapter):\(verse)"
        )
    }

    /// `i`(끝 절 숫자 바로 앞)가 범위 구분자면 시작 절을 읽고 `i`를 그 앞으로 옮긴다.
    /// 구분자 양옆 공백은 한 칸까지 받는다 — 책 이름·장 구조가 여전히 정확히 맞아야 하므로
    /// 오탐 위험이 낮다. **실패하면 `i`를 건드리지 않는다** (호출부가 단일 절로 계속 파싱한다).
    /// - Parameter allowingJeolSuffix: 형태 A의 `1절~13절`처럼 시작 절 뒤 "절"을 허용할지
    private static func readRangeStartBackward(
        _ chars: [Character], _ i: inout Int, allowingJeolSuffix: Bool
    ) -> Int? {
        var j = i
        skipOneSpaceBackward(chars, &j)
        guard j >= 0, rangeSeparators.contains(chars[j]) else { return nil }
        j -= 1
        skipOneSpaceBackward(chars, &j)
        if allowingJeolSuffix, j >= 0, chars[j] == "절" { j -= 1 }
        guard let start = readNumberBackward(chars, &j) else { return nil }
        i = j
        return start
    }

    /// i 위치에서 뒤로 숫자(1~3자리)를 읽는다. 성공 시 i는 숫자 앞으로 이동.
    private static func readNumberBackward(_ chars: [Character], _ i: inout Int) -> Int? {
        var digits: [Character] = []
        while i >= 0, chars[i].isASCII, chars[i].isNumber {
            digits.insert(chars[i], at: 0)
            i -= 1
        }
        // 성경 장·절은 최대 3자리 (시편 150편, 119편 176절)
        guard (1...3).contains(digits.count), let value = Int(String(digits)) else { return nil }
        return value
    }

    private static func skipOneSpaceBackward(_ chars: [Character], _ i: inout Int) {
        if i >= 0, chars[i] == " " { i -= 1 }
    }

    private static func isHangulSyllable(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1
        else { return false }
        return (0xAC00...0xD7A3).contains(scalar.value)
    }

    // MARK: - 개역한글 66권

    static let fullNames: [String] = [
        "창세기", "출애굽기", "레위기", "민수기", "신명기",
        "여호수아", "사사기", "룻기", "사무엘상", "사무엘하",
        "열왕기상", "열왕기하", "역대상", "역대하", "에스라",
        "느헤미야", "에스더", "욥기", "시편", "잠언",
        "전도서", "아가", "이사야", "예레미야", "예레미야애가",
        "에스겔", "다니엘", "호세아", "요엘", "아모스",
        "오바댜", "요나", "미가", "나훔", "하박국",
        "스바냐", "학개", "스가랴", "말라기",
        "마태복음", "마가복음", "누가복음", "요한복음", "사도행전",
        "로마서", "고린도전서", "고린도후서", "갈라디아서", "에베소서",
        "빌립보서", "골로새서", "데살로니가전서", "데살로니가후서",
        "디모데전서", "디모데후서", "디도서", "빌레몬서", "히브리서",
        "야고보서", "베드로전서", "베드로후서", "요한일서", "요한이서",
        "요한삼서", "유다서", "요한계시록"
    ]

    /// 관용 약칭 (개역 표준 약어). 순서는 fullNames와 동일.
    private static let abbreviations: [String] = [
        "창", "출", "레", "민", "신",
        "수", "삿", "룻", "삼상", "삼하",
        "왕상", "왕하", "대상", "대하", "스",
        "느", "에", "욥", "시", "잠",
        "전", "아", "사", "렘", "애",
        "겔", "단", "호", "욜", "암",
        "옵", "욘", "미", "나", "합",
        "습", "학", "슥", "말",
        "마", "막", "눅", "요", "행",
        "롬", "고전", "고후", "갈", "엡",
        "빌", "골", "살전", "살후",
        "딤전", "딤후", "딛", "몬", "히",
        "약", "벧전", "벧후", "요일", "요이",
        "요삼", "유", "계"
    ]

    /// 정식 명칭·약칭·통용 별칭 → 책 번호(1~66)
    private static let bookNumbers: [String: Int] = {
        var map: [String: Int] = [:]
        for (index, name) in fullNames.enumerated() { map[name] = index + 1 }
        for (index, name) in abbreviations.enumerated() { map[name] = index + 1 }
        map["계시록"] = 66  // "요한 계시록"처럼 띄어 쳐도 run이 "계시록"으로 잡힌다
        return map
    }()
}
