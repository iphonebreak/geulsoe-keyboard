// 설날·추석 양력 날짜 표 생성 — 한국 음력 `Calendar(identifier: .dangi)`(macOS 26+)로 계산해 Swift 소스로 쓴다.
// (사장님 결정 2026-09-28 — 음력은 이 두 명절만. 설계: docs/design-reviews/date-snippet-pack.md 0-2절)
//
// 왜 런타임 계산이 아니라 표인가: 제품 최소 iOS 17인데 `.dangi`는 iOS 26+이고, 모든 OS에 있는 `.chinese`는
// 한국 음력과 갈린다(2026~2050에서 2027·2028 설날, 2040 추석 — 이 스크립트가 `--compare`로 보여 준다).
//
// 사용:
//   swift tools/generate_lunar_holidays.swift            표를 다시 쓴다
//   swift tools/generate_lunar_holidays.swift --check    지금 계산값이 표와 같은지만 본다(생성 환경 줄은 무시). 다르면 exit 1
//   swift tools/generate_lunar_holidays.swift --compare  한국·중국 음력이 갈리는 칸을 출력한다(참고용, 파일을 쓰지 않는다)
// 산출: Packages/KeyboardCore/Sources/KeyboardCore/LunarHolidayTable.swift
//
// 한국천문연구원(KASI) 공식값과는 대조하지 않았다(인증키 필요) — `.dangi` 기준이다.

import Foundation

let firstYear = 2026
let lastYear = 2050
let seoul = TimeZone(identifier: "Asia/Seoul")!

let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Packages/KeyboardCore/Sources/KeyboardCore/LunarHolidayTable.swift")

guard #available(macOS 26, *) else {
    FileHandle.standardError.write(Data("한국 음력 .dangi는 macOS 26 이상에서만 있다 — 이 Mac에서는 만들 수 없다.\n".utf8))
    exit(2)
}

func calendar(_ identifier: Calendar.Identifier) -> Calendar {
    var calendar = Calendar(identifier: identifier)
    calendar.timeZone = seoul
    return calendar
}

let gregorian = calendar(.gregorian)

/// 양력 `year`년 안에서 음력 `month`월 `day`일(윤달 아님)이 되는 날의 양력 (월, 일).
/// 설날(1/1)은 1~2월, 추석(8/15)은 9~10월이라 한 양력 해에 꼭 한 번 있다.
func solar(_ lunar: Calendar, year: Int, month: Int, day: Int) -> (month: Int, day: Int) {
    var date = gregorian.date(from: DateComponents(year: year, month: 1, day: 1))!
    for _ in 0..<366 {
        let c = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        if c.month == month, c.day == day, c.isLeapMonth == false {
            let s = gregorian.dateComponents([.month, .day], from: date)
            return (s.month!, s.day!)
        }
        date = gregorian.date(byAdding: .day, value: 1, to: date)!
    }
    fatalError("\(year)년에 음력 \(month)/\(day)이 없다")
}

func rows(_ lunar: Calendar) -> [(year: Int, seollal: (Int, Int), chuseok: (Int, Int))] {
    (firstYear...lastYear).map { year in
        (year, solar(lunar, year: year, month: 1, day: 1), solar(lunar, year: year, month: 8, day: 15))
    }
}

let dangi = calendar(.dangi)
let arguments = Set(CommandLine.arguments.dropFirst())

if arguments.contains("--compare") {
    let chinese = rows(calendar(.chinese))
    for (korean, chinese) in zip(rows(dangi), chinese) {
        if korean.seollal != chinese.seollal {
            print("\(korean.year) 설날 한국 \(korean.seollal) / 중국 \(chinese.seollal)")
        }
        if korean.chuseok != chinese.chuseok {
            print("\(korean.year) 추석 한국 \(korean.chuseok) / 중국 \(chinese.chuseok)")
        }
    }
    exit(0)
}

let environmentPrefix = "// 생성 환경:"
let today: String = {
    let c = gregorian.dateComponents([.year, .month, .day], from: Date())
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}()

func pad(_ value: Int) -> String { value < 10 ? " \(value)" : "\(value)" }

var source = """
// ⚠️ 생성물 — 손으로 고치지 않는다. 재생성: `swift tools/generate_lunar_holidays.swift`
//    검사(표 = 지금 계산값인지): `swift tools/generate_lunar_holidays.swift --check`
// 원천: Foundation `Calendar(identifier: .dangi)`(한국 음력) · 시간대 Asia/Seoul · \(firstYear)~\(lastYear)년
\(environmentPrefix) macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · 생성일 \(today)
// KASI(한국천문연구원) 미대조 — `.dangi` 기준이다.

/// 설날(음력 1월 1일)·추석(음력 8월 15일)이 되는 **양력** 월·일 — 한 해 한 줄.
///
/// 제품 최소 iOS 17이라 한국 음력 `.dangi`(iOS 26+)를 런타임에 쓸 수 없고, 모든 OS에 있는 `.chinese`는
/// 한국과 갈린다(2027·2028 설날, 2040 추석). 그래서 생성 시점에 `.dangi`로 계산한 값을 박아 둔다.
/// 표 밖의 해는 없다(`DateSnippetParser`가 칩을 띄우지 않는다). 설계: `date-snippet-pack.md` 0-2절.
enum LunarHolidayTable {

    static let firstYear = \(firstYear)
    static let lastYear = \(lastYear)

    /// (연도, 설날 (월, 일), 추석 (월, 일)) — 연도 오름차순, 빠진 해 없음
    static let rows: [(year: Int, seollal: (month: Int, day: Int), chuseok: (month: Int, day: Int))] = [

"""
let table = rows(dangi)
for (index, row) in table.enumerated() {
    let comma = index == table.count - 1 ? "" : ","
    source += "        (\(row.year), (\(row.seollal.0), \(pad(row.seollal.1))), (\(pad(row.chuseok.0)), \(pad(row.chuseok.1))))\(comma)\n"
}
source += """
    ]
}

"""

if arguments.contains("--check") {
    func comparable(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false).filter { !$0.hasPrefix(environmentPrefix) }
    }
    guard let current = try? String(contentsOf: output, encoding: .utf8) else {
        print("표 파일이 없다: \(output.path)")
        exit(1)
    }
    if comparable(current) == comparable(source) {
        print("일치 — \(table.count)년 × 설날·추석 \(table.count * 2)칸이 지금 계산값과 같다")
        exit(0)
    }
    print("불일치 — 표를 다시 만들어야 한다: swift tools/generate_lunar_holidays.swift")
    exit(1)
}

try source.write(to: output, atomically: true, encoding: .utf8)
print("썼다: \(output.path) (\(table.count)년)")
