import Foundation
import Testing
@testable import PackImport

// 외부 채움글 1-e ② — xlsx XML → `RawTable`의 **실물 표본 대조**(PDR AC-31·6-4·6-5b, P-10 `verify-p9-p10.md` 2절 T01~T36).
// 기대표는 우리 판정 코드가 아니라 **독립 오라클**(파이썬 표준 `xml.etree`로 표본을 읽고, 날짜는 검증 문서 2절이 관측한 서식 번호
// — Mac 180·14·20, 윈도우 176·14·20, 구글 164~167·20 — 로만 판정)로 뽑았다. 셀 글은 표본의 가짜 시험 문구(T##)뿐이다.
// 표본 xlsx 자체는 작성자 실명·경로가 들어 있어 저장소에 복사하지 않고 로컬 `docs/`에서 읽는다(①과 같다 — 없으면 건너뜀).

/// 기대 셀 — `.t`는 **스칼라까지** 같아야 한다(NFD 보존 확인), `.long`은 앞 글자와 스칼라 수
enum ExpectedCell: Sendable, Equatable {
    case t(String)
    case long(String, Int)
    case n(String)
    case f
    case d
    case b
    case e
    case empty

    func matches(_ cell: RawCell) -> Bool {
        switch (self, cell) {
        case (.t(let expected), .text(let actual)): Array(expected.unicodeScalars) == Array(actual.unicodeScalars)
        case (.long(let prefix, let count), .text(let actual)): actual.hasPrefix(prefix) && actual.unicodeScalars.count == count
        case (.n(let expected), .number(let actual)): expected == actual
        case (.f, .unsupported(.formula)), (.d, .unsupported(.date)), (.b, .unsupported(.boolean)), (.e, .unsupported(.error)), (.empty, .blank): true
        default: false
        }
    }
}

struct RealRow: Sendable {
    let number: Int
    let cells: [ExpectedCell]
    let merged: Bool
    init(_ number: Int, _ cells: [ExpectedCell], merged: Bool = false) {
        self.number = number
        self.cells = cells
        self.merged = merged
    }
}

struct RealWorkbook: Sendable, CustomTestStringConvertible {
    let file: String
    let sheetName: String
    let rows: [RealRow]
    var testDescription: String { file }

    static let all: [RealWorkbook] = [
        RealWorkbook(file: "mac-excel-xlsx.xlsx", sheetName: "Sheet1", rows: mac),
        RealWorkbook(file: "win-excel-xlsx.xlsx", sheetName: "Sheet1", rows: windows),
        RealWorkbook(file: "gsheets-xlsx.xlsx", sheetName: "시트1", rows: google),
    ]

    // mac-excel-xlsx.xlsx
    static let mac: [RealRow] = [
        RealRow(1, [.t("#이름"), .t("사자성어 예시 팩")]),
        RealRow(2, [.t("#틀"), .t("사자성어 {n}번"), .t("성어 {n}번")]),
        RealRow(3, [.t("#권리"), .t("제작자 자체 작성, 예시 (가짜 내용)")]),
        RealRow(4, [.t("번호"), .t("제목"), .t("본문")]),
        RealRow(5, [.n("1"), .t("기본 한글"), .t("일석이조는 한 가지 일로 두 가지 이익을 얻는다는 뜻이에요.")]),
        RealRow(6, [.n("2"), .t("쉼표, 포함"), .t("고진감래, 힘든 일 끝에 즐거운 일이 온다는 뜻이에요.")]),
        RealRow(7, [.n("3"), .t("큰따옴표"), .t("그는 \"천천히, 꾸준히\"라고 말했어요.")]),
        RealRow(8, [.n("4"), .t("줄바꿈"), .t("첫째 줄")], merged: true),
        RealRow(9, [.empty, .empty, .t("둘째 줄")], merged: true),
        RealRow(10, [.empty, .empty, .t("셋째 줄")], merged: true),
        RealRow(11, [.n("5"), .t("줄바꿈+쉼표+따옴표"), .t("첫 줄, 쉼표 있음")], merged: true),
        RealRow(12, [.empty, .empty, .t("둘째 줄 \"인용\" 있음")], merged: true),
        RealRow(13, [.empty, .empty, .t("셋째 줄")], merged: true),
        RealRow(14, [.n("6"), .t("빈 줄이 든 본문"), .t("위 문단")], merged: true),
        RealRow(16, [.empty, .empty, .t("아래 문단")], merged: true),
        RealRow(17, [.n("7"), .n("5"), .n("2")]),
        RealRow(18, [.n("8"), .n("2"), .f]),
        RealRow(19, [.n("9"), .n("-2"), .f]),
        RealRow(20, [.n("10"), .t("@a"), .f]),
        RealRow(21, [.n("11"), .n("5"), .n("1")]),
        RealRow(22, [.n("12"), .n("-3"), .t("＠abc")]),
        RealRow(23, [.n("13"), .t("'=2+3"), .t("'=1+1")]),
        RealRow(24, [.n("14"), .d, .d]),
        RealRow(25, [.n("15"), .d, .t("3월 4일")]),
        RealRow(26, [.n("16"), .d, .d]),
        RealRow(27, [.n("17"), .n("7"), .n("123")]),
        RealRow(28, [.n("18"), .t("번호 앞자리 0"), .t("번호 칸이 018이에요.")]),
        RealRow(29, [.n("19"), .n("1.23456789012345E+19"), .n("1000")]),
        RealRow(30, [.n("20"), .b, .n("0.5")]),
        RealRow(31, [.n("21"), .n("1.5"), .n("1000")]),
        RealRow(32, [.n("22"), .t("\u{A0} 앞뒤 공백 \u{A0}"), .t("끝에 공백\u{A0}")]),
        RealRow(33, [.n("23"), .t("😀 🎉"), .t("👨\u{200D}👩\u{200D}👧 ❤\u{FE0F} 🇰🇷")]),
        RealRow(34, [.n("24"), .t("\u{1107}\u{116E}\u{11AB}\u{1112}\u{1162}\u{1112}\u{1167}\u{11BC} \u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF} \u{1109}\u{1175}\u{1112}\u{1165}\u{11B7}"), .t("조합형(NFC) 한글 시험")]),
        RealRow(35, [.n("25"), .t("긴 본문"), .long("[0000]가나다라마바", 3200)]),
        RealRow(36, [.n("26"), .empty, .t("제목 칸이 비었어요.")]),
        RealRow(38, [.n("28"), .t("본문 없음")]),
        RealRow(39, [.n("29"), .t("세미콜론;포함"), .t("a;b;c|d\\e <b>&amp;</b>")]),
        RealRow(40, [.n("5"), .t("중복 번호"), .t("5번이 두 번 나와요(뒤가 이겨요).")]),
        RealRow(41, [.n("0"), .t("번호 0"), .t("범위 밖 번호(0).")]),
        RealRow(42, [.n("10000"), .t("번호 10000"), .t("범위 밖 번호(10000).")]),
        RealRow(43, [.n("35"), .t("기호"), .t("“둥근 따옴표” ‘작은’ — … ① ™")]),
        RealRow(44, [.n("36"), .t("한자·가나"), .t("漢字 日本語 ひらがな")]),
    ]
    // win-excel-xlsx.xlsx
    static let windows: [RealRow] = [
        RealRow(1, [.t("#이름"), .t("사자성어 예시 팩")]),
        RealRow(2, [.t("#틀"), .t("사자성어 {n}번"), .t("성어 {n}번")]),
        RealRow(3, [.t("#권리"), .t("제작자 자체 작성, 예시 (가짜 내용)")]),
        RealRow(4, [.t("번호"), .t("제목"), .t("본문")]),
        RealRow(5, [.n("1"), .t("기본 한글"), .t("일석이조는 한 가지 일로 두 가지 이익을 얻는다는 뜻이에요.")]),
        RealRow(6, [.n("2"), .t("쉼표, 포함"), .t("고진감래, 힘든 일 끝에 즐거운 일이 온다는 뜻이에요.")]),
        RealRow(7, [.n("3"), .t("큰따옴표"), .t("그는 \"천천히, 꾸준히\"라고 말했어요.")]),
        RealRow(8, [.n("4"), .t("줄바꿈"), .t("첫째 줄\n둘째 줄\n셋째 줄")]),
        RealRow(9, [.n("5"), .t("줄바꿈+쉼표+따옴표"), .t("첫 줄, 쉼표 있음\n둘째 줄 인용\" 있음")]),
        RealRow(10, [.t("셋째 줄\"")]),
        RealRow(11, [.n("6"), .t("빈 줄이 든 본문"), .t("위 문단\n\n아래 문단")]),
        RealRow(12, [.n("7"), .n("5"), .n("2")]),
        RealRow(13, [.n("8"), .n("2"), .f]),
        RealRow(14, [.n("9"), .n("-2"), .f]),
        RealRow(15, [.n("10"), .t("@a"), .f]),
        RealRow(16, [.n("11"), .n("5"), .n("1")]),
        RealRow(17, [.n("12"), .n("-3"), .t("＠abc")]),
        RealRow(18, [.n("13"), .t("'=2+3"), .t("'=1+1")]),
        RealRow(19, [.n("14"), .d, .d]),
        RealRow(20, [.n("15"), .d, .t("3월 4일")]),
        RealRow(21, [.n("16"), .d, .d]),
        RealRow(22, [.n("17"), .n("7"), .n("123")]),
        RealRow(23, [.n("18"), .t("번호 앞자리 0"), .t("번호 칸이 018이에요.")]),
        RealRow(24, [.n("19"), .n("1.23456789012345E+19"), .n("1000")]),
        RealRow(25, [.n("20"), .b, .n("0.5")]),
        RealRow(26, [.n("21"), .n("1.5"), .n("1000")]),
        RealRow(27, [.n("22"), .t("  앞뒤 공백  "), .t("끝에 공백 ")]),
        RealRow(28, [.n("23"), .t("😀 🎉"), .t("👨\u{200D}👩\u{200D}👧 ❤\u{FE0F} 🇰🇷")]),
        RealRow(29, [.n("24"), .t("\u{1107}\u{116E}\u{11AB}\u{1112}\u{1162}\u{1112}\u{1167}\u{11BC} \u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF} \u{1109}\u{1175}\u{1112}\u{1165}\u{11B7}"), .t("조합형(NFC) 한글 시험")]),
        RealRow(30, [.n("25"), .t("긴 본문"), .long("[0000]가나다라마바", 3200)]),
        RealRow(31, [.n("26"), .empty, .t("제목 칸이 비었어요.")]),
        RealRow(33, [.n("28"), .t("본문 없음")]),
        RealRow(34, [.n("29"), .t("세미콜론;포함"), .t("a;b;c|d\\e <b>&amp;</b>")]),
        RealRow(35, [.n("5"), .t("중복 번호"), .t("5번이 두 번 나와요(뒤가 이겨요).")]),
        RealRow(36, [.n("0"), .t("번호 0"), .t("범위 밖 번호(0).")]),
        RealRow(37, [.n("10000"), .t("번호 10000"), .t("범위 밖 번호(10000).")]),
        RealRow(38, [.n("35"), .t("기호"), .t("“둥근 따옴표” ‘작은’ — … ① ™")]),
        RealRow(39, [.n("36"), .t("한자·가나"), .t("漢字 日本語 ひらがな")]),
    ]
    // gsheets-xlsx.xlsx
    static let google: [RealRow] = [
        RealRow(1, [.t("#이름"), .t("사자성어 예시 팩")]),
        RealRow(2, [.t("#틀"), .t("사자성어 {n}번"), .t("성어 {n}번")]),
        RealRow(3, [.t("#권리"), .t("제작자 자체 작성, 예시 (가짜 내용)")]),
        RealRow(4, [.t("번호"), .t("제목"), .t("본문")]),
        RealRow(5, [.n("1.0"), .t("기본 한글"), .t("일석이조는 한 가지 일로 두 가지 이익을 얻는다는 뜻이에요.")]),
        RealRow(6, [.n("2.0"), .t("쉼표, 포함"), .t("고진감래, 힘든 일 끝에 즐거운 일이 온다는 뜻이에요.")]),
        RealRow(7, [.n("3.0"), .t("큰따옴표"), .t("그는 \"천천히, 꾸준히\"라고 말했어요.")]),
        RealRow(8, [.n("4.0"), .t("줄바꿈"), .t("첫째 줄\n둘째 줄\n셋째 줄")]),
        RealRow(9, [.n("5.0"), .t("줄바꿈+쉼표+따옴표"), .t("첫 줄, 쉼표 있음\n둘째 줄 인용\" 있음")]),
        RealRow(10, [.t("셋째 줄\"")]),
        RealRow(11, [.n("6.0"), .t("빈 줄이 든 본문"), .t("위 문단\n\n아래 문단")]),
        RealRow(12, [.n("7.0"), .n("5.0"), .n("2.0")]),
        RealRow(13, [.n("8.0"), .n("2.0"), .f]),
        RealRow(14, [.n("9.0"), .n("-2.0"), .t("-1-1")]),
        RealRow(15, [.n("10.0"), .t("@a"), .t("@SUM(1,2)")]),
        RealRow(16, [.n("11.0"), .n("5.0"), .n("1.0")]),
        RealRow(17, [.n("12.0"), .n("-3.0"), .t("＠abc")]),
        RealRow(18, [.n("13.0"), .t("=2+3"), .t("=1+1")]),
        RealRow(19, [.n("14.0"), .d, .d]),
        RealRow(20, [.n("15.0"), .d, .d]),
        RealRow(21, [.n("16.0"), .d, .d]),
        RealRow(22, [.n("17.0"), .n("7.0"), .n("123.0")]),
        RealRow(23, [.n("18.0"), .t("번호 앞자리 0"), .t("번호 칸이 018이에요.")]),
        RealRow(24, [.n("19.0"), .t("12345678901234567890"), .n("1000.0")]),
        RealRow(25, [.n("20.0"), .b, .n("0.5")]),
        RealRow(26, [.n("21.0"), .n("1.5"), .n("1000.0")]),
        RealRow(27, [.n("22.0"), .t("앞뒤 공백"), .t("끝에 공백")]),
        RealRow(28, [.n("23.0"), .t("😀 🎉"), .t("👨\u{200D}👩\u{200D}👧 ❤\u{FE0F} 🇰🇷")]),
        RealRow(29, [.n("24.0"), .t("\u{1107}\u{116E}\u{11AB}\u{1112}\u{1162}\u{1112}\u{1167}\u{11BC} \u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF} \u{1109}\u{1175}\u{1112}\u{1165}\u{11B7}"), .t("조합형(NFC) 한글 시험")]),
        RealRow(30, [.n("25.0"), .t("긴 본문"), .long("[0000]가나다라마바", 3200)]),
        RealRow(31, [.n("26.0"), .empty, .t("제목 칸이 비었어요.")]),
        RealRow(33, [.n("28.0"), .t("본문 없음")]),
        RealRow(34, [.n("29.0"), .t("세미콜론;포함"), .t("a;b;c|d\\e <b>&amp;</b>")]),
        RealRow(35, [.n("5.0"), .t("중복 번호"), .t("5번이 두 번 나와요(뒤가 이겨요).")]),
        RealRow(36, [.n("0.0"), .t("번호 0"), .t("범위 밖 번호(0).")]),
        RealRow(37, [.n("10000.0"), .t("번호 10000"), .t("범위 밖 번호(10000).")]),
        RealRow(38, [.n("35.0"), .t("기호"), .t("“둥근 따옴표” ‘작은’ — … ① ™")]),
        RealRow(39, [.n("36.0"), .t("한자·가나"), .t("漢字 日本語 ひらがな")]),
    ]
}

@Suite("외부 채움글 1-e ② — 실물 xlsx → RawTable (AC-31·P-10)")
struct XLSXRealSampleTests {

    @Test("★ P-10 실물 3종(엑셀 Mac·윈도우·구글 시트) — 행마다 셀 종류·글·병합이 기대표대로 (로컬 전용 표본)",
          .enabled(if: ArchiveSample.localSamplesPresent, "docs/ 표본이 없는 클론에서는 건너뛴다(개인 정보 — 저장소 밖)"),
          arguments: RealWorkbook.all)
    func realGenerators(_ sample: RealWorkbook) throws {
        var reader = try XLSXWorkbookReader.open(Data(contentsOf: ArchiveSample.localURL(sample.file)))
        // 엑셀은 state 생략, 구글은 state="visible" 명시 — 둘 다 표시 시트(AC-36). 구글의 관계 id는 rId5
        #expect(reader.sheets.map(\.name) == [sample.sheetName])
        // 시트 이름 Sheet1·시트1은 팩 이름 기본값이 아니다(6-4)
        #expect(reader.sheets[0].suggestedPackName == nil)
        let table = try reader.table(for: reader.sheets[0])
        #expect(table.rows.map(\.number) == sample.rows.map(\.number))
        for (actual, expected) in zip(table.rows, sample.rows) {
            #expect(actual.cells.count == expected.cells.count, "행 \(expected.number)")
            for (index, (cell, want)) in zip(actual.cells, expected.cells).enumerated() {
                #expect(want.matches(cell), "행 \(expected.number) 열 \(index): \(cell)")
            }
            #expect(actual.isMerged == expected.merged, "행 \(expected.number)")
            #expect(!actual.isHidden)
        }
        #expect(table.hiddenColumns.isEmpty)
    }

    @Test("★ 샘플 xlsx 2종 — 모든 셀이 원본 CSV(`*.original.csv`)와 같다(번호 열 숫자 포함, 줄바꿈은 LF)",
          arguments: ["sample-numbered", "sample-phrases"])
    func bundledSamplesMatchOriginalCSV(_ name: String) throws {
        let xlsx = try #require(Bundle.module.url(forResource: name, withExtension: "xlsx", subdirectory: "Fixtures"))
        let csv = try #require(Bundle.module.url(forResource: "\(name).original", withExtension: "csv", subdirectory: "Fixtures"))
        var reader = try XLSXWorkbookReader.open(Data(contentsOf: xlsx))
        #expect(reader.sheets.map(\.name) == [name])
        #expect(reader.sheets[0].suggestedPackName == name)
        let table = try reader.table(for: reader.sheets[0])

        let decoded = try PackTextDecoder.decode(Data(contentsOf: csv), choice: .automatic)
        let records = try CSVRecordParser.parse(decoded.text, delimiter: .comma).records.filter { !$0.isBlank }
        // 지금 Fixtures의 xlsx는 아직 옛 `#권리`판이다(R27 — ④에서 `#출처`판으로 다시 만들면 이 치환을 뺀다)
        let expected = records.map { record in
            Array(record.cells.map { $0 == "#출처" ? "#권리" : $0.replacingOccurrences(of: "\r\n", with: "\n") }
                .reversed().drop(while: \.isEmpty).reversed())
        }
        let actual = table.rows.map { row in
            row.cells.map { cell -> String in
                switch cell {
                case .text(let text): text
                case .number(let literal): literal
                case .blank: ""
                case .unsupported(let kind): "<\(kind)>"
                }
            }
        }
        #expect(actual == expected)
        #expect(table.rows.allSatisfy { !$0.isMerged && !$0.isHidden })
    }
}
