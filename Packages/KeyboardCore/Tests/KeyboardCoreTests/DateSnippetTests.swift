import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 날짜·시간 채움글 팩 — PDR `docs/design-reviews/date-snippet-pack.md` **12절 기대값 표를 그대로 옮긴 것**이다.
///
/// 표의 소절 번호를 스위트 이름에 적어 둔다 — 표와 테스트를 한 줄씩 대조할 수 있게.
/// 시간대는 **서울로 고정한** 달력을 주입한다(호스트 시간대와 무관하게 결정적). 제품 달력
/// (`DateSnippetParser.makeCalendar()`)의 성질은 따로 검사한다(12-3 스위트).
private enum Fixture {
    static let seoul = TimeZone(identifier: "Asia/Seoul")!

    /// 제품과 같은 성질(그레고리력·월요일 시작)에 시간대만 서울로 박은 달력
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoul
        calendar.firstWeekday = 2
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 10, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func parser(_ now: Date, style: DateSnippetStyle = .formal) -> DateSnippetParser {
        DateSnippetParser(style: style, calendar: calendar, now: { now })
    }

    /// 꼬리를 주고 **삽입될 본문**만 본다
    static func body(_ tail: String, at now: Date, style: DateSnippetStyle = .formal) -> String? {
        parser(now, style: style).suggestion(forTail: tail)?.body
    }

    static func components(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    }
}

// MARK: - 4-1 · 출력 형식 9조합 (수용 기준 1)

@Suite("날짜 채움글 4-1 — 스타일 × 종류 9조합")
struct DateSnippetFormatterTests {

    @Test("2026. 9. 27. 21:54 — 표 그대로", arguments: [
        (DateSnippetStyle.formal, DateSnippetKind.dateOnly, "2026. 9. 27."),
        (.formal, .timeOnly, "21:54"),
        (.formal, .dateAndTime, "2026. 9. 27. 21:54"),
        (.common, .dateOnly, "2026.09.27"),
        (.common, .timeOnly, "21:54"),
        (.common, .dateAndTime, "2026.09.27 21:54"),
        (.korean, .dateOnly, "2026년 9월 27일"),
        (.korean, .timeOnly, "오후 9시 54분"),
        (.korean, .dateAndTime, "2026년 9월 27일 오후 9시 54분")
    ])
    func nineCombinations(style: DateSnippetStyle, kind: DateSnippetKind, expected: String) {
        let components = Fixture.components(2026, 9, 27, 21, 54)
        #expect(DateSnippetFormatter.format(components: components, kind: kind, style: style) == expected)
    }

    @Test("규범·관행형 시간은 시·분 모두 두 자리 — 자정·정오·오전", arguments: [
        (0, 30, "00:30"), (12, 30, "12:30"), (5, 54, "05:54"), (9, 5, "09:05")
    ])
    func twentyFourHourPadding(hour: Int, minute: Int, expected: String) {
        let components = Fixture.components(2026, 9, 27, hour, minute)
        #expect(DateSnippetFormatter.format(components: components, kind: .timeOnly, style: .formal) == expected)
        #expect(DateSnippetFormatter.format(components: components, kind: .timeOnly, style: .common) == expected)
    }
}

// MARK: - 12-1 · 월·연 산술 (6-1절)

@Suite("날짜 채움글 12-1 — 월·연 산술은 Foundation 결과 그대로")
struct DateSnippetArithmeticTests {

    private func shifted(_ date: Date, _ amount: Int, _ unit: DateSnippetParser.Unit) -> Date {
        DateSnippetParser.shifted(date, by: amount, unit, calendar: Fixture.calendar) ?? .distantPast
    }

    private func ymd(_ date: Date) -> [Int] {
        let c = Fixture.calendar.dateComponents([.year, .month, .day], from: date)
        return [c.year ?? 0, c.month ?? 0, c.day ?? 0]
    }

    @Test("2026.01.31 + 1개월 = 2026.02.28")
    func janEndPlusMonth() { #expect(ymd(shifted(Fixture.date(2026, 1, 31), 1, .month)) == [2026, 2, 28]) }

    @Test("2024.01.31 + 1개월 = 2024.02.29 (윤년)")
    func leapJanEndPlusMonth() { #expect(ymd(shifted(Fixture.date(2024, 1, 31), 1, .month)) == [2024, 2, 29]) }

    @Test("2026.03.31 − 1개월 = 2026.02.28")
    func marchEndMinusMonth() { #expect(ymd(shifted(Fixture.date(2026, 3, 31), -1, .month)) == [2026, 2, 28]) }

    @Test("2024.02.29 + 1년 = 2025.02.28")
    func leapDayPlusYear() { #expect(ymd(shifted(Fixture.date(2024, 2, 29), 1, .year)) == [2025, 2, 28]) }

    @Test("2026.01.31 + 1개월 − 1개월 = 2026.01.28 — 31로 돌아오지 않는다")
    func roundTripDoesNotRestore() {
        #expect(ymd(shifted(shifted(Fixture.date(2026, 1, 31), 1, .month), -1, .month)) == [2026, 1, 28])
    }

    @Test("2026.01.31에 1개월씩 두 번 = 2026.03.28")
    func twoSingleMonths() {
        #expect(ymd(shifted(shifted(Fixture.date(2026, 1, 31), 1, .month), 1, .month)) == [2026, 3, 28])
    }

    @Test("2026.01.31에 2개월 한 번 = 2026.03.31 — 연산 순서가 결과를 바꾼다")
    func oneDoubleMonth() { #expect(ymd(shifted(Fixture.date(2026, 1, 31), 2, .month)) == [2026, 3, 31]) }

    @Test("파서도 같은 규칙 — 1월 31일에 「1개월 후 날짜」는 2월 28일")
    func parserUsesSameArithmetic() {
        #expect(Fixture.body("1개월 후 날짜", at: Fixture.date(2026, 1, 31)) == "2026. 2. 28.")
        #expect(Fixture.body("2개월 후 날짜", at: Fixture.date(2026, 1, 31)) == "2026. 3. 31.")
    }
}

// MARK: - 12-2 · 연말·형식 코드 (4-4절)

@Suite("날짜 채움글 12-2 — 연말에 다음 해가 찍히지 않는다 (yyyy)")
struct DateSnippetYearEndTests {

    @Test("오늘 날짜 — 규범형·관행형", arguments: [
        (12, 27, "2026. 12. 27.", "2026.12.27"),
        (12, 28, "2026. 12. 28.", "2026.12.28"),
        (12, 29, "2026. 12. 29.", "2026.12.29"),
        (12, 30, "2026. 12. 30.", "2026.12.30"),
        (12, 31, "2026. 12. 31.", "2026.12.31"),
        (9, 27, "2026. 9. 27.", "2026.09.27")
    ])
    func todayAtYearEnd(month: Int, day: Int, formal: String, common: String) {
        let now = Fixture.date(2026, month, day)
        #expect(Fixture.body("오늘 날짜", at: now) == formal)
        #expect(Fixture.body("오늘 날짜", at: now, style: .common) == common)
    }
}

// MARK: - 12-3 · 비그레고리력 기기 (4-5절)

@Suite("날짜 채움글 12-3 — 기기 달력과 무관하게 양력")
struct DateSnippetCalendarTests {

    @Test("제품 달력은 그레고리력·월요일 시작·자동 추종 시간대")
    func productCalendar() {
        let calendar = DateSnippetParser.makeCalendar()
        #expect(calendar.identifier == .gregorian)
        #expect(calendar.firstWeekday == 2)
        #expect(calendar.timeZone == TimeZone.autoupdatingCurrent)
    }

    /// ★ **호스트 달력에 기대지 않는다** (검증자 비차단 지적, 2026-09-28).
    ///
    /// 옛 테스트는 기본 달력으로 만든 파서만 보고 「2026이 찍힌다」를 확인했다. 그런데 테스트를 도는 Mac이
    /// 그레고리력이면 `Calendar.current`를 쓰는 변형도 **똑같이 2026을 찍어 통과한다** — 불교력·일본력 기기의
    /// 함정을 잡지 못했다.
    ///
    /// 그래서 **달력을 주입한다.** 불교력·일본력·그레고리력을 각각 넣고 **그 달력의 연도가 찍히는지** 본다 —
    /// 계산·출력이 주입한 달력 하나만 쓴다는 것을 호스트와 무관하게 증명한다. 어딘가 `Calendar.current`가
    /// 끼면 호스트가 무엇이든 셋 중 적어도 둘이 운다. 제품이 주입하는 달력이 그레고리력인 것은
    /// 위 `productCalendar`와 조립 지점(`KeyboardViewController.dateSnippetCalendar = makeCalendar()`)이 맡는다.
    @Test("주입한 달력의 연도가 찍힌다 — 불교력 2569 · 일본력 8 · 그레고리력 2026", arguments: [
        (Calendar.Identifier.buddhist, "2569. 9. 27."),
        (.japanese, "8. 9. 27."),
        (.gregorian, "2026. 9. 27.")
    ])
    func followsInjectedCalendar(identifier: Calendar.Identifier, expected: String) {
        let now = Fixture.date(2026, 9, 27)
        var injected = Calendar(identifier: identifier)
        injected.timeZone = Fixture.seoul
        let parser = DateSnippetParser(style: .formal, calendar: injected, now: { now })
        #expect(parser.suggestion(forTail: "오늘 날짜")?.body == expected)
        #expect(DateSnippetFormatter.format(now, kind: .dateOnly, style: .formal, calendar: injected) == expected)
    }

    /// 시간대도 같은 원리 — 같은 순간을 서울(+9)·키리티마티(+14)·호놀룰루(−10) 달력에 넣으면 날짜가 갈린다.
    /// `Calendar.current`(호스트 시간대)를 쓰는 변형이면 셋이 같은 날짜를 찍어 운다.
    @Test("주입한 달력의 시간대를 따른다 — 같은 순간이 시간대마다 다른 날짜")
    func followsInjectedTimeZone() {
        let instant = Fixture.date(2026, 9, 27, 12, 0)     // 서울 정오 = UTC 03:00
        func today(_ zone: String) -> String? {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            return DateSnippetParser(style: .formal, calendar: calendar, now: { instant })
                .suggestion(forTail: "오늘 날짜")?.body
        }
        #expect(today("Asia/Seoul") == "2026. 9. 27.")
        #expect(today("Pacific/Kiritimati") == "2026. 9. 27.")   // UTC+14 → 17:00
        #expect(today("Pacific/Honolulu") == "2026. 9. 26.")     // UTC−10 → 전날 17:00
    }

    /// ★ 검증자 지적 M2c(2026-09-28) — 「오늘 날짜」는 순간을 그대로 찍어서 **공휴일 계산의 연·월 추출**
    /// (`evaluate`의 `dateComponents`)이 `Calendar.current`로 바뀌어도 잡지 못했다. 공휴일은 **추출한 연도로 날짜를
    /// 다시 만든다** — 불교력 기기에서 서기 2569년 8월 15일이 되는 변형이 그 자리다. 두 달력을 주입해 호스트와 무관하게 운다.
    @Test("공휴일도 주입한 달력의 연도로 만든다 — 불교력 광복절 2569. 8. 15. · 그레고리력 2026. 8. 15.", arguments: [
        (Calendar.Identifier.buddhist, "2569. 8. 15."),
        (.gregorian, "2026. 8. 15.")
    ])
    func holidayFollowsInjectedCalendar(identifier: Calendar.Identifier, expected: String) {
        var injected = Calendar(identifier: identifier)
        injected.timeZone = Fixture.seoul
        let now = Fixture.date(2026, 9, 27)
        #expect(DateSnippetParser(style: .formal, calendar: injected, now: { now })
            .suggestion(forTail: "광복절 날짜")?.body == expected)
    }

    /// 제품 달력은 **기기 달력·로캘을 물려받지 않는다** — `Calendar.current`를 복사해 설정만 바꾸는 변형은
    /// 그레고리력 Mac에서 식별자 검사를 통과하지만 로캘(`ko_KR` 등, 달력 선호가 실리는 곳)을 끌고 온다.
    /// 식별자로 만든 달력의 로캘은 빈 값이다(2026-09-28 실측) — 호스트와 무관하게 가른다.
    @Test("제품 달력은 기기 로캘을 물려받지 않는다")
    func productCalendarIsNotDeviceCopy() {
        #expect(DateSnippetParser.makeCalendar().locale?.identifier ?? "" == "")
    }

    @Test("기기 달력 함정이 실제로 있다 — 불교력·일본력으로 세면 2569·8년")
    func deviceCalendarTrapExists() {
        let now = Fixture.date(2026, 9, 27)
        for (identifier, year) in [(Calendar.Identifier.buddhist, 2569), (.japanese, 8)] {
            var device = Calendar(identifier: identifier)
            device.timeZone = Fixture.seoul
            #expect(device.component(.year, from: now) == year)
        }
    }
}

// MARK: - 12-4 · 자정·정오, 한글형 (4-1절)

@Suite("날짜 채움글 12-4 — 한글형 12시간제")
struct DateSnippetKoreanTimeTests {

    /// ★ 정각은 「0분」을 **생략한다**(사장님 결정 2026-09-28) — 자정·정오도 같은 규칙.
    @Test("정각은 「N시」로 끝난다", arguments: [
        (21, 0, "오후 9시"),
        (0, 0, "오전 12시"),
        (12, 0, "오후 12시"),
        (9, 0, "오전 9시")
    ])
    func koreanOnTheHour(hour: Int, minute: Int, expected: String) {
        let components = Fixture.components(2026, 9, 27, hour, minute)
        #expect(DateSnippetFormatter.format(components: components, kind: .timeOnly, style: .korean) == expected)
    }

    @Test("정각 날짜+시간도 「0분」이 없다")
    func koreanOnTheHourWithDate() {
        let components = Fixture.components(2026, 9, 27, 21, 0)
        #expect(DateSnippetFormatter.format(components: components, kind: .dateAndTime, style: .korean)
                == "2026년 9월 27일 오후 9시")
    }

    @Test("오전·오후, 자정은 오전 12시, 정오는 오후 12시, 0 채움 없음", arguments: [
        (0, 30, "오전 12시 30분"),
        (12, 30, "오후 12시 30분"),
        (9, 5, "오전 9시 5분"),
        (21, 54, "오후 9시 54분")
    ])
    func koreanClock(hour: Int, minute: Int, expected: String) {
        let components = Fixture.components(2026, 9, 27, hour, minute)
        #expect(DateSnippetFormatter.format(components: components, kind: .timeOnly, style: .korean) == expected)
        #expect(Fixture.body("지금 시간", at: Fixture.date(2026, 9, 27, hour, minute), style: .korean) == expected)
    }
}

// MARK: - 12-5 · 분기말 (6-3절)

@Suite("날짜 채움글 12-5 — 분기말은 이번 분기의 말일")
struct DateSnippetQuarterTests {

    @Test("분기말 날짜", arguments: [
        (2026, 10, 1, "2026. 12. 31."),
        (2026, 1, 1, "2026. 3. 31."),
        (2026, 6, 30, "2026. 6. 30."),
        (2026, 8, 14, "2026. 9. 30.")
    ])
    func quarterEnd(year: Int, month: Int, day: Int, expected: String) {
        #expect(Fixture.body("분기말 날짜", at: Fixture.date(year, month, day)) == expected)
    }
}

// MARK: - 12-6 · 이번 주 요일, 월요일 시작 (6-2절)

@Suite("날짜 채움글 12-6 — 한 주는 월요일에 시작한다")
struct DateSnippetWeekdayTests {

    @Test("2026.09.30(수) 이번주 일요일 날짜 = 10.04")
    func sundayOfThisWeekFromWednesday() {
        #expect(Fixture.body("이번주 일요일 날짜", at: Fixture.date(2026, 9, 30)) == "2026. 10. 4.")
    }

    @Test("2026.09.27(일) 이번주 월요일 날짜 = 09.21")
    func mondayOfThisWeekFromSunday() {
        #expect(Fixture.body("이번주 월요일 날짜", at: Fixture.date(2026, 9, 27)) == "2026. 9. 21.")
    }

    @Test("다음주·지난주 — 띄어 써도 된다", arguments: [
        ("다음주 금요일 날짜", "2026. 10. 9."),
        ("다음 주 금요일 날짜", "2026. 10. 9."),
        ("지난주 화요일 날짜", "2026. 9. 22."),
        ("이번 주 수요일 날짜", "2026. 9. 30.")
    ])
    func otherWeeks(tail: String, expected: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 9, 30)) == expected)
    }
}

// MARK: - 12-7 · 그저께·글피 + 상대일

@Suite("날짜 채움글 12-7 — 상대일")
struct DateSnippetRelativeDayTests {

    /// ★ 글피는 **모레의 다음 날(+3)**이다(표준국어대사전). 설계서 12-7 표의 9. 29.는 모레 값을 적은
    /// 오류였고 사장님이 사전대로 정정했다(2026-09-28). 어제·모레도 같은 결정으로 넣었다.
    @Test("2026.09.27 기준", arguments: [
        ("그저께 날짜", "2026. 9. 25."),
        ("글피 날짜", "2026. 9. 30."),
        ("오늘 날짜", "2026. 9. 27."),
        ("내일 날짜", "2026. 9. 28."),
        ("어제 날짜", "2026. 9. 26."),
        ("모레 날짜", "2026. 9. 29.")
    ])
    func relativeDays(tail: String, expected: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 9, 27)) == expected)
    }

    @Test("이번달 첫날·말일, 올해 마지막날·연말 — 윤년이 아닌 2월", arguments: [
        ("이번달 첫날 날짜", "2026. 2. 1."),
        ("이번 달 말일 날짜", "2026. 2. 28."),
        ("올해 마지막날 날짜", "2026. 12. 31."),
        ("연말 날짜", "2026. 12. 31.")
    ])
    func monthAndYearBounds(tail: String, expected: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 2, 10)) == expected)
    }
}

// MARK: - 12-8 · 양력 공휴일 지난/올해 판정 (5절, 수용 기준 5·6)

@Suite("날짜 채움글 12-8 — 공휴일은 올해 값 그대로, 칩 제목에만 상태")
struct DateSnippetHolidayTests {

    @Test("광복절 전날·당일·다음날", arguments: [
        (14, "· 올해"),
        (15, "· 오늘"),
        (16, "· 지남")
    ])
    func thisYearStatus(day: Int, status: String) throws {
        let now = Fixture.date(2026, 8, day)
        let suggestion = try #require(Fixture.parser(now).suggestion(forTail: "올해 광복절 날짜"))
        #expect(suggestion.body == "2026. 8. 15.", "지나도 올해 값 그대로다")
        #expect(suggestion.title.hasSuffix(status))
        #expect(!suggestion.body.contains("·"), "상태 표식은 본문에 넣지 않는다")
    }

    @Test("당일은 **아침에도** 「오늘」이다 — 지남 판정은 일 단위")
    func sameDayMorningIsToday() throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 8, 15, 0, 1)).suggestion(forTail: "광복절 날짜"))
        #expect(suggestion.title.hasSuffix("· 오늘"))
    }

    @Test("「올해」를 안 붙여도 같다")
    func withoutThisYearPrefix() throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 12, 26)).suggestion(forTail: "성탄절 날짜"))
        #expect(suggestion.body == "2026. 12. 25.")
        #expect(suggestion.title.hasSuffix("· 지남"))
    }

    @Test("내년 광복절 날짜는 시점과 무관하게 내년", arguments: [(8, 14), (8, 16), (1, 1)])
    func nextYear(month: Int, day: Int) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, month, day)).suggestion(forTail: "내년 광복절 날짜"))
        #expect(suggestion.body == "2027. 8. 15.")
        #expect(!suggestion.title.contains("지남") && !suggestion.title.contains("· 올해"))
    }

    @Test("양력 공휴일 8종", arguments: [
        ("신정 날짜", "2026. 1. 1."), ("삼일절 날짜", "2026. 3. 1."),
        ("어린이날 날짜", "2026. 5. 5."), ("현충일 날짜", "2026. 6. 6."),
        ("광복절 날짜", "2026. 8. 15."), ("개천절 날짜", "2026. 10. 3."),
        ("한글날 날짜", "2026. 10. 9."), ("성탄절 날짜", "2026. 12. 25.")
    ])
    func allHolidays(tail: String, expected: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 9, 27)) == expected)
    }
}

// MARK: - 3-3 · 숫자 패턴 (수용 기준 2)

@Suite("날짜 채움글 3-3 — 숫자 패턴")
struct DateSnippetNumberTests {

    @Test("2026.09.27 기준", arguments: [
        ("3일 후 날짜", "2026. 9. 30."),
        ("2주 뒤 날짜", "2026. 10. 11."),
        ("2주일 후 날짜", "2026. 10. 11."),
        ("10개월 전 날짜", "2025. 11. 27."),
        ("3달 후 날짜", "2026. 12. 27."),
        ("1년 이전 날짜", "2025. 9. 27."),
        ("5해 후 날짜", "2031. 9. 27."),
        ("999일 후 날짜", "2029. 6. 22."),
        ("사흘 후 날짜", "2026. 9. 30."),
        ("열흘 뒤 날짜", "2026. 10. 7."),
        ("일주일 후 날짜", "2026. 10. 4."),
        ("보름 뒤 날짜", "2026. 10. 12."),
        ("두 달 후 날짜", "2026. 11. 27."),
        ("한 해 전 날짜", "2025. 9. 27."),
        ("세 주 뒤 날짜", "2026. 10. 18.")
    ])
    func patterns(tail: String, expected: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 9, 27)) == expected)
    }

    @Test("받지 않는 것 — 조용히 무반응", arguments: [
        "0일 후 날짜",       // 0
        "1000일 후 날짜",    // 999 초과
        "세일 후 날짜",       // 고유어 수 + 「일」은 받지 않는다 (「세일」)
        "열두 달 후 날짜",    // 11 이상 고유어 — 「두 달」로 잘못 읽지 않는다
        "스물두 달 후 날짜",
        "1.5년 후 날짜",      // 소수 — 「5년」으로 잘못 읽지 않는다
        "3일 날짜",           // 방향 없음
        "날짜",
        "오늘",               // 끝말 없음
        "3일 후"
    ])
    func rejects(tail: String) {
        #expect(Fixture.body(tail, at: Fixture.date(2026, 9, 27)) == nil)
    }
}

// MARK: - 3-4 · 현재 시간 (수용 기준 2)

@Suite("날짜 채움글 3-4 — 현재 시간")
struct DateSnippetNowTests {

    @Test("시간만 — 넷 다 동의어", arguments: ["현재 시간", "지금 시간", "현재 시각", "지금 시각"])
    func timeOnly(tail: String) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 9, 27, 21, 54, 30)).suggestion(forTail: tail))
        #expect(suggestion.body == "21:54", "초는 넣지 않는다")
        #expect(suggestion.kind == .timeOnly)
    }

    @Test("날짜+시간 — 한 스냅숏", arguments: ["지금 날짜 시간", "지금 날짜 시각"])
    func dateAndTime(tail: String) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 9, 27, 21, 54)).suggestion(forTail: tail))
        #expect(suggestion.body == "2026. 9. 27. 21:54")
        #expect(suggestion.kind == .dateAndTime)
    }
}

// MARK: - 칩 모양 · 단축어 원문

@Suite("날짜 채움글 — 칩 값과 단축어 원문")
struct DateSnippetSuggestionShapeTests {

    @Test("제목은 짧은 이름, 본문은 계산값, 머리말 없음, 계산 시각을 든다")
    func shape() throws {
        let now = Fixture.date(2026, 9, 27, 21, 54)
        let suggestion = try #require(Fixture.parser(now).suggestion(forTail: "오늘 날짜"))
        #expect(suggestion.title == "오늘 날짜")
        #expect(suggestion.body == "2026. 9. 27.")
        #expect(suggestion.prefix == nil)
        #expect(suggestion.computedAt == now)
        #expect(suggestion.kind == .dateOnly)
    }

    @Test("지울 단축어는 꼬리 원문 그대로 — 앞말은 빼고 사이 공백은 넣는다", arguments: [
        ("약속은 3일 후 날짜", "3일 후 날짜"),
        ("오늘  날짜", "오늘  날짜"),
        ("회의는 다음 주 금요일 날짜", "다음 주 금요일 날짜"),
        ("지금 날짜 시간", "지금 날짜 시간")
    ])
    func triggerIsVerbatim(tail: String, trigger: String) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 9, 27)).suggestion(forTail: tail))
        #expect(suggestion.trigger == trigger)
    }

    @Test("줄바꿈 너머는 단축어가 아니다")
    func stopsAtNewline() {
        #expect(Fixture.body("오늘\n날짜", at: Fixture.date(2026, 9, 27)) == nil)
    }
}

// MARK: - 7-2 · 탭할 때 표시 단위가 바뀌었으면 넣지 않는다 (수용 기준 7)

@Suite("날짜 채움글 7-2 — 탭 시점 신선도")
struct DateSnippetStalenessTests {

    private func suggestion(kind: DateSnippetKind, at computedAt: Date) -> SnippetSuggestion {
        SnippetSuggestion(trigger: "t", title: "t", body: "b", computedAt: computedAt, kind: kind)
    }

    @Test("시간 칩 — 같은 분이면 넣고, 분이 바뀌면 갱신")
    func timeGranularity() {
        let chip = suggestion(kind: .timeOnly, at: Fixture.date(2026, 9, 27, 21, 54, 10))
        #expect(!chip.isStale(at: Fixture.date(2026, 9, 27, 21, 54, 59), calendar: Fixture.calendar))
        #expect(chip.isStale(at: Fixture.date(2026, 9, 27, 21, 55, 0), calendar: Fixture.calendar))
        let both = suggestion(kind: .dateAndTime, at: Fixture.date(2026, 9, 27, 21, 54, 10))
        #expect(both.isStale(at: Fixture.date(2026, 9, 27, 21, 55, 0), calendar: Fixture.calendar))
    }

    @Test("날짜 칩 — 같은 날이면 넣고, 자정을 넘기면 갱신")
    func dayGranularity() {
        let chip = suggestion(kind: .dateOnly, at: Fixture.date(2026, 9, 27, 0, 0, 1))
        #expect(!chip.isStale(at: Fixture.date(2026, 9, 27, 23, 59, 59), calendar: Fixture.calendar))
        #expect(chip.isStale(at: Fixture.date(2026, 9, 28, 0, 0, 0), calendar: Fixture.calendar))
    }

    @Test("문구·성경 칩은 계산 시각이 없어 항상 신선하다")
    func nonDateNeverStale() {
        let chip = SnippetSuggestion(trigger: "t", title: "t", body: "b")
        #expect(!chip.isStale(at: .distantFuture, calendar: Fixture.calendar))
    }

    @Test("같은 내용이면 계산 시각만 다른 칩은 바꾸지 않는다")
    func sameContentIgnoresComputedAt() {
        let a = suggestion(kind: .timeOnly, at: Fixture.date(2026, 9, 27, 21, 54, 10))
        let b = suggestion(kind: .timeOnly, at: Fixture.date(2026, 9, 27, 21, 54, 40))
        #expect(a != b)
        #expect(a.hasSameContent(as: b))
        #expect(!a.hasSameContent(as: SnippetSuggestion(trigger: "t", title: "t", body: "다른 값")))
        #expect(!a.hasSameContent(as: nil))
    }
}

// MARK: - 매처 배선 (3-5절 우선순위 · 수용 기준 3·8·9)

@MainActor
@Suite("날짜 채움글 — SnippetMatcher 배선")
struct DateSnippetMatcherTests {

    private let now = Fixture.date(2026, 9, 27, 21, 54)
    private var dates: DateSnippetParser { Fixture.parser(now) }

    @Test("날짜 팩이 켜져 있으면 매처가 날짜 칩을 낸다")
    func matcherProducesDate() {
        let matcher = SnippetMatcher(bible: nil, entries: [], dates: dates)
        #expect(matcher.suggestion(forTail: "오늘 날짜")?.body == "2026. 9. 27.")
    }

    @Test("사용자 단축어가 내장 날짜보다 먼저다 — 확정 동작(3-5절)")
    func userEntryWins() {
        let user = SnippetEntry(trigger: "날짜", title: "내 날짜", body: "사용자 본문")
        let matcher = SnippetMatcher(bible: nil, entries: [user], dates: dates)
        #expect(matcher.suggestion(forTail: "오늘 날짜")?.body == "사용자 본문")
    }

    @Test("팩을 끄면(dates 없음) 세 갈래 전부 빠진다", arguments: ["오늘 날짜", "3일 후 날짜", "지금 시간"])
    func disabledPack(tail: String) {
        let matcher = SnippetMatcher(bible: nil, entries: [], dates: nil)
        #expect(matcher.suggestion(forTail: tail) == nil)
    }

    @Test("secure 입력란에서는 날짜도 문구도 매칭하지 않는다")
    func secureField() {
        let user = SnippetEntry(trigger: "집주소", title: "집", body: "서울")
        let matcher = SnippetMatcher(bible: nil, entries: [user], dates: dates)
        #expect(matcher.suggestion(forTail: "오늘 날짜", isSecureTextEntry: true) == nil)
        #expect(matcher.suggestion(forTail: "집주소", isSecureTextEntry: true) == nil)
        #expect(matcher.suggestion(forTail: "오늘 날짜", isSecureTextEntry: false)?.body == "2026. 9. 27.")
    }

    @Test("날짜 끝말이 아니면 날짜 분기는 아무것도 하지 않는다 — 문구·성경 동작 그대로")
    func otherTailsUntouched() {
        let user = SnippetEntry(trigger: "집주소", title: "집", body: "서울")
        let matcher = SnippetMatcher(bible: nil, entries: [user], dates: dates)
        #expect(matcher.suggestion(forTail: "우리 집주소")?.body == "서울")
        #expect(matcher.suggestion(forTail: "안녕하세요") == nil)
    }

    @Test("삽입 계약 그대로 — 단축어만 지우고 값을 넣는다")
    func insertionContract() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("약속 오늘 날짜")
        let matcher = SnippetMatcher(bible: nil, entries: [], dates: dates)
        let suggestion = try #require(matcher.suggestion(forTail: controller.textTail))
        #expect(controller.insertSnippet(suggestion))
        #expect(output.text == "약속 2026. 9. 27.")
        #expect(!controller.insertSnippet(suggestion), "같은 칩 두 번째 탭은 꼬리 정합 검사가 막는다")
    }
}

// MARK: - VoiceOver — 날짜 칩은 넣을 값을 읽는다 (v1.2.0 출시 전 마무리 ①)

@Suite("날짜 채움글 — 칩 VoiceOver 라벨")
struct DateSnippetAccessibilityTests {

    @Test("날짜·시간 칩은 값을 한글형으로 읽는다 — 설정한 출력 형식과 무관", arguments: [
        ("오늘 날짜", DateSnippetStyle.formal, "채움글 오늘 날짜, 2026년 9월 27일 붙여넣기"),
        ("오늘 날짜", .common, "채움글 오늘 날짜, 2026년 9월 27일 붙여넣기"),
        ("지금 시간", .formal, "채움글 지금 시간, 오후 9시 54분 붙여넣기"),
        ("지금 날짜 시간", .formal, "채움글 지금 날짜 시간, 2026년 9월 27일 오후 9시 54분 붙여넣기"),
        ("사흘 후 날짜", .formal, "채움글 사흘 후 날짜, 2026년 9월 30일 붙여넣기")
    ])
    func readsValue(tail: String, style: DateSnippetStyle, expected: String) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 9, 27, 21, 54), style: style).suggestion(forTail: tail))
        #expect(suggestion.accessibilityLabel == expected)
    }

    @Test("공휴일 상태도 읽는다 — 가운뎃점은 쉼표로", arguments: [
        (14, "채움글 광복절 날짜, 올해, 2026년 8월 15일 붙여넣기"),
        (15, "채움글 광복절 날짜, 오늘, 2026년 8월 15일 붙여넣기"),
        (16, "채움글 광복절 날짜, 지남, 2026년 8월 15일 붙여넣기")
    ])
    func readsHolidayStatus(day: Int, expected: String) throws {
        let suggestion = try #require(Fixture.parser(Fixture.date(2026, 8, day)).suggestion(forTail: "광복절 날짜"))
        #expect(suggestion.accessibilityLabel == expected)
    }

    @Test("문구·성경 칩은 기존 라벨 그대로 — 「채움글 <제목> 붙여넣기」")
    func otherChipsUnchanged() {
        let greeting = SnippetSuggestion(trigger: "생일축하", title: "생일 축하", body: "생일 진심으로…")
        #expect(greeting.accessibilityLabel == "채움글 생일 축하 붙여넣기")
        let bible = SnippetSuggestion(trigger: "창 1:1", title: "창세기 1:1", body: "태초에…", prefix: "[창 1:1] ")
        #expect(bible.accessibilityLabel == "채움글 창세기 1:1 붙여넣기")
    }
}
