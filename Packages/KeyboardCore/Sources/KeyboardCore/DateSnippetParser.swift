import Foundation
import TadakDomain

/// 날짜·시간 채움글 — 꼬리가 「…날짜」·「…시간」·「…시각」으로 끝나면 **그 순간** 값을 계산한다.
///
/// PDR `docs/design-reviews/date-snippet-pack.md`(양력 전용 확정판). `BibleReferenceParser`와 같은 자리의
/// 순수 로직이다 — 저장소도, 미리 계산해 둔 값도 없다(1절 「적중 순간 계산」).
///
/// ## 세 갈래 (3절)
///
/// | 갈래 | 예 | 종류 |
/// |---|---|---|
/// | (가) 닫힌 어휘 | `오늘 날짜` · `이번주 월요일 날짜` · `분기말 날짜` · `광복절 날짜` · `내년 성탄절 날짜` | 날짜 |
/// | (나) 숫자 패턴 | `3일 후 날짜` · `두 달 뒤 날짜` · `사흘 후 날짜` · `10개월 전 날짜` | 날짜 |
/// | (다) 현재 시간 | `지금 시간` · `현재 시각` / `지금 날짜 시간` | 시간 / 날짜+시간 |
///
/// **끝말 규칙 하나가 오탐 방어의 전부다**(3-1·8-4절) — 「날짜」「시간」「시각」으로 끝나지 않으면
/// 아무것도 하지 않는다. 띄어쓰기는 보지 않고(매처와 같은 규칙), 줄바꿈에서 멈춘다.
///
/// ## 달력 — 계산도 출력도 그레고리력 (4-5·4-6·6-2절)
///
/// `makeCalendar()`: 그레고리력 · 시간대 `autoupdatingCurrent` · 한 주는 **월요일** 시작.
/// 기기 달력(불교력·일본력)·기기 시간대 캐시·로캘의 주 시작을 따르지 않는다.
/// ★ `TimeZone.current`는 쓰지 않는다 — 처음 읽을 때 캐시돼 사용자가 시간대를 바꿔도 안 따라간다(Apple 문서).
/// 상주 익스텐션 안에서 `autoupdatingCurrent`가 정말 즉시 바뀌는지는 **실기 미확인**이다(14절).
///
/// ## 핫패스 (수용 기준 10)
///
/// 매처가 문구 needle을 다 본 뒤에만 부른다. 마지막 두 글자로 **먼저 거른다** — 대부분의 키 입력은
/// 글자 비교 두세 번에서 끝난다. `now()`와 달력 계산은 **맞았을 때만** 한다.
public struct DateSnippetParser: Sendable {

    /// 숫자 패턴의 단위. 주는 7일로 계산한다.
    public enum Unit: Sendable { case day, week, month, year }

    public let style: DateSnippetStyle
    public let calendar: Calendar
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - style: 출력 형식 (설정 `dateSnippetStyle`)
    ///   - calendar: 테스트에서만 바꾼다(시간대 고정). 제품은 기본값 `makeCalendar()`
    ///   - now: 테스트에서만 바꾼다. **적중한 순간에만** 불린다
    public init(
        style: DateSnippetStyle = .formal,
        calendar: Calendar = DateSnippetParser.makeCalendar(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.style = style
        self.calendar = calendar
        self.now = now
    }

    /// 제품 달력 — 그레고리력 · `autoupdatingCurrent` · 월요일 시작 (4-5·4-6·6-2절).
    /// 탭 시점 신선도 판정(`SnippetSuggestion.isStale`)도 조립 지점이 이 달력으로 한다.
    public static func makeCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }

    /// 월·연 덧셈은 **Foundation 결과 그대로**다(6-1절) — 1월 31일 + 1개월 = 2월 28일, 되돌려도 31일로
    /// 돌아오지 않는다. 주는 7일로 계산한다(주 단위 달력 필드를 쓰지 않는다 — 주 시작 설정과 무관하게).
    public static func shifted(_ date: Date, by amount: Int, _ unit: Unit, calendar: Calendar) -> Date? {
        switch unit {
        case .day: calendar.date(byAdding: .day, value: amount, to: date)
        case .week: calendar.date(byAdding: .day, value: amount * 7, to: date)
        case .month: calendar.date(byAdding: .month, value: amount, to: date)
        case .year: calendar.date(byAdding: .year, value: amount, to: date)
        }
    }

    /// 꼬리 전체를 받는 진입점(테스트·단독 사용). 매처는 이미 풀어 둔 꼬리를 넘기는 아래 함수를 쓴다.
    public func suggestion(forTail tail: String) -> SnippetSuggestion? {
        let characters = Array(tail)
        var reversed: [(character: Character, index: Int)] = []
        reversed.reserveCapacity(Self.window)
        for index in stride(from: characters.count - 1, through: 0, by: -1) {
            let character = characters[index]
            if character.isNewline { break }
            if character.isWhitespace { continue }
            reversed.append((character, index))
            if reversed.count == Self.window { break }
        }
        return suggestion(characters: characters, reversed: reversed)
    }

    /// 매처(`SnippetMatcher`)가 부른다 — 꼬리를 **한 번만** 풀어 공유한다(매처와 같은 규칙:
    /// 줄바꿈에서 멈추고 공백은 건너뛴다, 원문 인덱스를 함께 든다).
    func suggestion(
        characters: [Character], reversed: [(character: Character, index: Int)]
    ) -> SnippetSuggestion? {
        // 끝말로 먼저 거른다 — 여기서 대부분의 키 입력이 끝난다
        guard reversed.count >= 2 else { return nil }
        let last = reversed[0].character, before = reversed[1].character
        let endsWithDate = before == "날" && last == "짜"
        let endsWithTime = before == "시" && (last == "간" || last == "각")
        guard endsWithDate || endsWithTime else { return nil }

        // 마지막 몇 글자를 **정방향 비공백 배열**로 — 모든 규칙이 이 위에서 접미사로 돈다
        let count = min(Self.window, reversed.count)
        var window: [Character] = []
        window.reserveCapacity(count)
        for offset in stride(from: count - 1, through: 0, by: -1) {
            window.append(reversed[offset].character)
        }

        let match = endsWithTime ? Self.matchTime(window) : Self.matchDate(window)
        guard let match else { return nil }

        // ★ 여기서 처음으로 「지금」을 읽는다 — 적중한 순간 계산(1절)
        let now = now()
        guard let (date, title) = evaluate(match, now: now) else { return nil }
        let start = reversed[match.length - 1].index
        return SnippetSuggestion(
            trigger: String(characters[start...]),
            title: title,
            body: DateSnippetFormatter.format(date, kind: match.kind, style: style, calendar: calendar),
            computedAt: now,
            kind: match.kind,
            // VoiceOver용 — 같은 값을 **한글형**으로(출력 지점은 여전히 `DateSnippetFormatter` 하나다)
            spokenValue: DateSnippetFormatter.format(date, kind: match.kind, style: .korean, calendar: calendar))
    }

    // MARK: - 뜻 → 값

    private func evaluate(_ match: Match, now: Date) -> (Date, String)? {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = c.year, let month = c.month else { return nil }
        switch match.meaning {
        case .now:
            return (now, match.title)
        case .relativeDays(let days):
            return Self.shifted(now, by: days, .day, calendar: calendar).map { ($0, match.title) }
        case .shift(let amount, let unit):
            return Self.shifted(now, by: amount, unit, calendar: calendar).map { ($0, match.title) }
        case .weekday(let week, let dayIndex):
            // 월요일 시작(6-2절) — 식으로 직접 센다. `firstWeekday`에도 2를 넣어 두었지만
            // 주 경계 API 대신 식을 쓰면 달력 설정이 바뀌어도 답이 흔들리지 않는다.
            let weekday = calendar.component(.weekday, from: now)       // 1=일 … 7=토
            let mondayIndex = (weekday + 5) % 7                          // 월=0 … 일=6
            return Self.shifted(now, by: week * 7 + dayIndex - mondayIndex, .day, calendar: calendar)
                .map { ($0, match.title) }
        case .monthFirst:
            return day(year, month, 1).map { ($0, match.title) }
        case .monthLast:
            return lastDay(year, month).map { ($0, match.title) }
        case .yearLast:
            return day(year, 12, 31).map { ($0, match.title) }
        case .quarterEnd:
            // 이번 분기의 말일(6-3절) — 10월 1일에도 12월 31일
            return lastDay(year, (month - 1) / 3 * 3 + 3).map { ($0, match.title) }
        case .holiday(let holidayMonth, let holidayDay, let nextYear):
            guard let holiday = day(year + (nextYear ? 1 : 0), holidayMonth, holidayDay) else { return nil }
            // 올해 값 그대로 + **제목에만** 상태(5절). 판정은 일 단위 — 당일 아침에도 「오늘」
            guard !nextYear else { return (holiday, match.title) }
            let status = calendar.isDate(now, inSameDayAs: holiday) ? "오늘" : (now > holiday ? "지남" : "올해")
            return (holiday, "\(match.title) · \(status)")
        }
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func lastDay(_ year: Int, _ month: Int) -> Date? {
        guard let first = day(year, month, 1),
              let days = calendar.range(of: .day, in: .month, for: first)?.count
        else { return nil }
        return day(year, month, days)
    }

    // MARK: - 꼬리 → 뜻

    /// 풀어 볼 꼬리 길이(비공백 글자 수). 가장 긴 단축어가 9자(`999개월이전날짜`)이고
    /// 그 앞 한 글자(경계 검사)까지 보면 충분하다.
    static let window = 14

    enum Meaning: Sendable {
        case now
        case relativeDays(Int)
        case shift(Int, Unit)
        case weekday(week: Int, dayIndex: Int)
        case monthFirst, monthLast, yearLast, quarterEnd
        case holiday(month: Int, day: Int, nextYear: Bool)
    }

    struct Match: Sendable {
        let meaning: Meaning
        let kind: DateSnippetKind
        /// 꼬리 끝에서 센 **비공백** 글자 수 — 지울 원문의 시작 위치를 정한다
        let length: Int
        /// 칩 제목(공휴일은 상태가 뒤에 붙는다)
        let title: String
    }

    private struct Word: Sendable {
        let key: [Character]
        let meaning: Meaning
        let title: String
        init(_ key: String, _ meaning: Meaning, _ title: String) {
            self.key = Array(key)
            self.meaning = meaning
            self.title = title
        }
    }

    // (다) 현재 시간 — 끝말까지 포함한 전체가 키다. 긴 것이 먼저(「지금날짜시간」이 「지금시간」보다 앞)
    private static let timeWords: [(word: Word, kind: DateSnippetKind)] = [
        (Word("지금날짜시간", .now, "지금 날짜 시간"), .dateAndTime),
        (Word("지금날짜시각", .now, "지금 날짜 시각"), .dateAndTime),
        (Word("현재시간", .now, "현재 시간"), .timeOnly),
        (Word("지금시간", .now, "지금 시간"), .timeOnly),
        (Word("현재시각", .now, "현재 시각"), .timeOnly),
        (Word("지금시각", .now, "지금 시각"), .timeOnly)
    ]

    /// (가) 닫힌 어휘 — 끝말 「날짜」를 뺀 키. **긴 키가 먼저**라 「올해광복절」이 「광복절」보다 먼저 맞는다
    /// (「올해」까지 지운다).
    private static let dateWords: [Word] = {
        var words: [Word] = [
            // 상대일 — 글피는 모레의 다음 날(+3, 표준국어대사전). 어제·모레는 사장님 결정(2026-09-28)으로 더했다
            Word("그저께", .relativeDays(-2), "그저께 날짜"),
            Word("어제", .relativeDays(-1), "어제 날짜"),
            Word("오늘", .relativeDays(0), "오늘 날짜"),
            Word("내일", .relativeDays(1), "내일 날짜"),
            Word("모레", .relativeDays(2), "모레 날짜"),
            Word("글피", .relativeDays(3), "글피 날짜"),
            // 이번 달 · 올해 · 분기
            Word("이번달첫날", .monthFirst, "이번달 첫날 날짜"),
            Word("이번달말일", .monthLast, "이번달 말일 날짜"),
            Word("올해마지막날", .yearLast, "올해 마지막날 날짜"),
            Word("올해연말", .yearLast, "연말 날짜"),
            Word("연말", .yearLast, "연말 날짜"),
            Word("분기말", .quarterEnd, "분기말 날짜")
        ]
        for (prefix, week) in [("이번주", 0), ("다음주", 1), ("지난주", -1)] {
            for (dayIndex, day) in ["월", "화", "수", "목", "금", "토", "일"].enumerated() {
                words.append(Word("\(prefix)\(day)요일", .weekday(week: week, dayIndex: dayIndex),
                                  "\(prefix) \(day)요일 날짜"))
            }
        }
        // 양력 공휴일 8종(3-2절) — 대체·임시공휴일은 넣지 않는다(매년 정부 발표로 바뀐다)
        let holidays: [(String, Int, Int)] = [
            ("신정", 1, 1), ("삼일절", 3, 1), ("어린이날", 5, 5), ("현충일", 6, 6),
            ("광복절", 8, 15), ("개천절", 10, 3), ("한글날", 10, 9), ("성탄절", 12, 25)
        ]
        for (name, month, day) in holidays {
            let thisYear = Meaning.holiday(month: month, day: day, nextYear: false)
            words.append(Word(name, thisYear, "\(name) 날짜"))
            words.append(Word("올해\(name)", thisYear, "\(name) 날짜"))
            words.append(Word("내년\(name)", .holiday(month: month, day: day, nextYear: true), "내년 \(name) 날짜"))
        }
        return words.sorted { $0.key.count > $1.key.count }
    }()

    private static func matchTime(_ window: [Character]) -> Match? {
        for (word, kind) in timeWords where window.hasSuffix(word.key) {
            return Match(meaning: word.meaning, kind: kind, length: word.key.count, title: word.title)
        }
        return nil
    }

    private static func matchDate(_ window: [Character]) -> Match? {
        let stem = window.dropLast(2)          // 「날짜」를 뗀다
        for word in dateWords where stem.hasSuffix(word.key) {
            return Match(meaning: word.meaning, kind: .dateOnly, length: word.key.count + 2, title: word.title)
        }
        return matchShift(stem).map {
            Match(meaning: .shift($0.amount, $0.unit), kind: .dateOnly, length: $0.length + 2, title: $0.title + " 날짜")
        }
    }

    // MARK: (나) 숫자 패턴 — <숫자> <단위> <방향> 날짜

    /// 날을 세는 고유어(단위를 품고 있다) — 하루~열흘·보름·일주일(3-3절)
    private static let dayCountWords: [(key: [Character], amount: Int, unit: Unit)] = [
        ("여드레", 8, Unit.day), ("아흐레", 9, .day), ("일주일", 1, .week),
        ("하루", 1, .day), ("이틀", 2, .day), ("사흘", 3, .day), ("나흘", 4, .day),
        ("닷새", 5, .day), ("엿새", 6, .day), ("이레", 7, .day), ("열흘", 10, .day), ("보름", 15, .day)
    ].map { (Array($0.0), $0.1, $0.2) }

    /// 고유어 수 한~열(3-3절). 긴 것이 먼저
    private static let nativeNumbers: [(key: [Character], value: Int)] = [
        ("다섯", 5), ("여섯", 6), ("일곱", 7), ("여덟", 8), ("아홉", 9),
        ("한", 1), ("두", 2), ("세", 3), ("네", 4), ("열", 10)
    ].map { (Array($0.0), $0.1) }

    /// 이 글자가 고유어 수 **앞에** 붙어 있으면 11 이상(열두·스물두·서른…)이다 — 받지 않는다.
    /// 「열두 달」을 「두 달」로 잘못 읽는 것을 막는다.
    private static let nativeTensEndings: Set<Character> = ["열", "물", "른", "흔", "쉰", "순", "든"]

    /// 아라비아 숫자 **앞에** 이 글자가 있으면 소수·음수·날짜 조각이다(「1.5년」을 「5년」으로 읽지 않는다)
    private static let digitBlockers: Set<Character> = [".", ",", "-", "/", ":"]

    private static func matchShift(_ stem: ArraySlice<Character>) -> (amount: Int, unit: Unit, length: Int, title: String)? {
        // 방향 — 「이전」을 「전」보다 먼저
        let sign: Int, directionText: String
        if stem.hasSuffix(["이", "전"]) {
            sign = -1; directionText = "이전"
        } else if let last = stem.last, last == "후" || last == "뒤" || last == "전" {
            sign = last == "전" ? -1 : 1; directionText = String(last)
        } else {
            return nil
        }
        let rest = stem.dropLast(directionText.count)

        // 단위를 품은 고유어(사흘·보름·일주일…)
        for word in dayCountWords where rest.hasSuffix(word.key) {
            guard !precededBy(rest, count: word.key.count, in: nativeTensEndings) else { return nil }
            let length = word.key.count + directionText.count
            return (sign * word.amount, word.unit, length, "\(String(word.key)) \(directionText)")
        }

        // 단위 — 「개월」·「주일」을 먼저
        let unit: Unit, unitText: String
        if rest.hasSuffix(["개", "월"]) {
            unit = .month; unitText = "개월"
        } else if rest.hasSuffix(["주", "일"]) {
            unit = .week; unitText = "주일"
        } else if let last = rest.last {
            switch last {
            case "일": unit = .day
            case "주": unit = .week
            case "달": unit = .month
            case "년", "해": unit = .year
            default: return nil
            }
            unitText = String(last)
        } else {
            return nil
        }
        let numberPart = rest.dropLast(unitText.count)

        // 아라비아 숫자 1~999 — 숫자 run 전체를 본다(「1000」의 뒤 세 자리를 따로 읽지 않는다)
        var digitCount = 0
        for character in numberPart.reversed() {
            guard character.isASCII, character.isNumber else { break }
            digitCount += 1
        }
        if digitCount > 0 {
            guard digitCount <= 3,
                  !precededBy(numberPart, count: digitCount, in: digitBlockers),
                  let value = Int(String(numberPart.suffix(digitCount))),
                  (1...999).contains(value)
            else { return nil }
            let length = digitCount + unitText.count + directionText.count
            return (sign * value, unit, length, "\(value)\(unitText) \(directionText)")
        }

        // 고유어 수 한~열 — 「일」 단위는 받지 않는다(「세일 후 날짜」를 사흘로 읽지 않는다)
        guard unit != .day else { return nil }
        for number in nativeNumbers where numberPart.hasSuffix(number.key) {
            guard !precededBy(numberPart, count: number.key.count, in: nativeTensEndings) else { return nil }
            let length = number.key.count + unitText.count + directionText.count
            return (sign * number.value, unit, length, "\(String(number.key)) \(unitText) \(directionText)")
        }
        return nil
    }

    /// `slice`의 끝 `count`글자 **바로 앞** 글자가 `set`에 있는가
    private static func precededBy(_ slice: ArraySlice<Character>, count: Int, in set: Set<Character>) -> Bool {
        let position = slice.endIndex - count - 1
        return position >= slice.startIndex && set.contains(slice[position])
    }
}

private extension Array where Element == Character {
    func hasSuffix(_ suffix: [Character]) -> Bool { self[...].hasSuffix(suffix) }
}

private extension ArraySlice where Element == Character {
    func hasSuffix(_ suffix: [Character]) -> Bool {
        guard suffix.count <= count else { return false }
        var index = endIndex
        for character in suffix.reversed() {
            index -= 1
            if self[index] != character { return false }
        }
        return true
    }
}
