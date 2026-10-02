import Foundation
import TadakDomain

/// 날짜 채움글이 **무엇을** 넣는가 — 친 말에 맞춰 필요한 만큼만(PDR `date-snippet-pack.md` 4-1절).
///
/// 탭 시점 신선도 판정의 단위도 이것이 정한다 — 날짜는 **일**, 시간이 들어가면 **분**(7-2절).
public enum DateSnippetKind: Sendable, Equatable {
    case dateOnly, timeOnly, dateAndTime
}

/// 날짜 채움글 문자열의 **유일한 출력 지점** (PDR 4-3절 — 형식을 바꿀 때 고칠 자리가 여기 하나다).
///
/// | | 날짜 | 시간 | 날짜+시간 |
/// |---|---|---|---|
/// | 규범형 `formal`(기본) | `2026. 9. 27.` | `21:54` | `2026. 9. 27. 21:54` |
/// | 관행형 `common` | `2026.09.27` | `21:54` | `2026.09.27 21:54` |
/// | 한글형 `korean` | `2026년 9월 27일` | `오후 9시 54분` | `2026년 9월 27일 오후 9시 54분` |
///
/// ## `DateFormatter`를 쓰지 않는다 (4-2절)
///
/// 성분 정수를 받아 **손으로 조립한다.** 포매터를 새로 만들면 67.5µs, 조립은 0.6µs다(반론자1 실측).
/// 덤으로 두 함정이 애초에 생기지 않는다:
/// - **`YYYY` 함정(4-4절)** — 패턴 문자를 쓰지 않으니 「주 기준 연도」가 끼어들 자리가 없다.
///   (★ 나중에 누가 보조로 `DateFormatter`를 쓰게 되면 반드시 `yyyy`다 — 12월 27~31일이 다음 해로 찍힌다.)
/// - **기기 달력·숫자 체계(4-5절)** — 성분은 호출자가 그레고리력으로 뽑아 오고, 여기는 아라비아 숫자만 찍는다.
///
/// ## 시각제는 스타일이 정한다
///
/// 규범·관행형은 24시간제(시·분 두 자리), 한글형만 12시간제(0 채움 없음). **기기의 12/24시간
/// 설정은 읽지 않는다.** 한글형 자정은 「오전 12시」, 정오는 「오후 12시」(시스템 관례),
/// **정각은 「0분」을 생략한다** — 「오후 9시」(사장님 결정 2026-09-28).
///
/// 초는 어느 스타일에도 없다.
public enum DateSnippetFormatter {

    /// - Parameter components: 그레고리력으로 뽑은 `year`·`month`·`day`(날짜가 들어갈 때)와
    ///   `hour`·`minute`(시간이 들어갈 때). 없는 성분은 0으로 본다.
    public static func format(components: DateComponents, kind: DateSnippetKind, style: DateSnippetStyle) -> String {
        switch kind {
        case .dateOnly: date(components, style)
        case .timeOnly: time(components, style)
        case .dateAndTime: date(components, style) + " " + time(components, style)
        }
    }

    /// 순간을 받아 **주어진 달력으로** 성분을 뽑고 찍는다. 달력은 호출자가 그레고리력으로 고정해 넘긴다
    /// (`DateSnippetParser.makeCalendar()`) — 기기 달력(`Calendar.current`)을 여기서 쓰지 않는다.
    public static func format(_ date: Date, kind: DateSnippetKind, style: DateSnippetStyle, calendar: Calendar) -> String {
        format(
            components: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date),
            kind: kind, style: style)
    }

    private static func date(_ c: DateComponents, _ style: DateSnippetStyle) -> String {
        let year = c.year ?? 0, month = c.month ?? 0, day = c.day ?? 0
        switch style {
        case .formal: return "\(year). \(month). \(day)."
        case .common: return "\(year).\(twoDigits(month)).\(twoDigits(day))"
        case .korean: return "\(year)년 \(month)월 \(day)일"
        }
    }

    private static func time(_ c: DateComponents, _ style: DateSnippetStyle) -> String {
        let hour = c.hour ?? 0, minute = c.minute ?? 0
        switch style {
        case .formal, .common:
            return "\(twoDigits(hour)):\(twoDigits(minute))"
        case .korean:
            let meridiem = hour < 12 ? "오전" : "오후"
            let hour12 = hour % 12 == 0 ? 12 : hour % 12
            return minute == 0 ? "\(meridiem) \(hour12)시" : "\(meridiem) \(hour12)시 \(minute)분"
        }
    }

    /// 0 채움 — `String(format:)`보다 싸다(핫패스는 아니지만 적중마다 돈다)
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
