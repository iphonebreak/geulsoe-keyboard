import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 문구 검사 — **한 곳**(1-c 6단계 ②③, 계획서 `external-snippet-packs-1c-plan.md` 5절 6행).
// 1·4·5단계 시험이 저마다 들고 있던 U6 목록·금칙어·xlsx 목록을 여기로 모았다 — 규칙은 `PackCopyLint` 하나, 검사 대상은 `allScreenCopy` 하나다.
//
// - **AC-35**(PDR 15-3): CSV 전용판의 모든 화면 문구·안내·샘플 리소스에 **xlsx 형식 언급 0**. 기준은 시안 6절·어긋남 ② 판정 그대로 —
//   「`xlsx`·`.xlsx`·엑셀 파일을 가져오는 안내」는 금지, 「엑셀에서 CSV로 저장」처럼 **엑셀을 CSV를 만드는 곳으로** 가리키는 안내는 허용
// - **U6**(PDR E표): 화면 문구·샘플·`#` 예시에 교회·성경 소재 0. 예외는 `PackCopyLint.churchExceptions`에 **정확한 문자열로만** 둔다
// - 금칙어: 「트리거」(용어는 「단축어」) · 「잠시 뒤」(틀린 안내, 계획서 4-2절)
// 숫자 검사(예산 한도 숫자 0)는 단계마다 허용 목록이 달라 각 단계 시험에 남아 있다.

// MARK: - 규칙

enum PackCopyLint {

    /// U6 — 교회·성경 소재(화면 문구·예시·샘플에 쓰지 않는다)
    static let churchWords = [
        "성경", "찬송", "찬양", "성가", "예배", "교회", "기도", "설교", "목사", "장로", "주일", "복음", "하나님", "하느님",
        "예수", "그리스도", "말씀", "구절", "창세기", "시편", "요한", "개역", "아멘", "할렐루야", "성도", "선교", "십자가", "성탄"
    ]

    /// U6 예외 — **정확히 이 문자열만**. 예시·샘플이 아니라 키보드의 **기존 성경 기능**을 가리키는 거부 이유다
    /// (시안 5-C 표 그대로, 5단계 보고 「다르게 한 것」 6, 계획서 5절 6행 ③ 「기존 성경 기능 설명은 대상이 아니다」)
    static var churchExceptions: [String] { [PackFormCopy.templateFailure(.collidesWithBible(n: 51))] }

    /// U6 목록의 글자 조각이 평범한 낱말 안에 든 경우 — 이 낱말을 지우고 본다(「필요한」의 「요한」, 계획서 4-4절 「필요한 칸만 남겨 주세요」)
    static let churchFalsePositives = ["필요한"]

    /// 금칙어
    static let bannedWords = ["트리거", "잠시 뒤"]

    /// AC-35 — xlsx **형식** 이름(확장자·「통합 문서」·Excel·workbook)과, 엑셀을 **가져오는 대상**으로 가리키는 말(「엑셀 파일」·「엑셀로」·알약 「엑셀」).
    /// 엑셀 뒤가 「에서」·「·」·「이나」면 CSV를 만드는 **곳**이라 허용한다(「엑셀에서 「CSV UTF-8」로 저장」·「엑셀·Numbers·구글 시트에서는」)
    static let xlsxPatterns = [#"(?i)xlsx"#, #"(?i)\.xls"#, #"(?i)excel"#, #"(?i)workbook"#, "통합 문서", "엑셀(?!에서|·|이나)"]

    static func xlsxMentions(in text: String) -> [String] {
        xlsxPatterns.filter { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func churchWords(in text: String) -> [String] {
        guard !churchExceptions.contains(text) else { return [] }
        let checked = churchFalsePositives.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
        return churchWords.filter(checked.contains)
    }

    static func bannedWords(in text: String) -> [String] { bannedWords.filter(text.contains) }
}

// MARK: - 검사 대상

/// 6단계 문구 — 3-A 「처음이라면」 샘플 줄·3-C 공유 파일 이름 · xlsx판의 「그 밖의 방법」 파일 줄(지금 판으로)
var stage6Copy: [String] {
    var texts = [PackImportCopy.samplesFooter]
    for kind in PackSample.Kind.allCases {
        texts += [PackImportCopy.sampleTitle(kind), PackImportCopy.sampleDetail(kind)]
        texts += PackSample.files(kind).flatMap { [PackImportCopy.sampleFormatLabel($0.format), PackImportCopy.sampleShareLabel($0), $0.displayName] }
    }
    if let row = PackImportCopy.otherFileRow { texts += [row.title, row.detail] }
    return texts
}

/// 화면 문구 전부(1~6단계) — **지금 판으로** 만든다. 시험은 `PackCopySet.$previewing`으로 판을 고른다
var allScreenCopy: [String] {
    stage1To3Copy + stage4Copy + PackImportCopy.guideSheet.flatMap { $0 } + stage5Copy + [PackNoticeCopy.unreadableListFooter] + stage6Copy
}

/// `#` 예시 — 만드는 법 시트 그림의 정보 줄·폼의 틀 예시(U6이 「`#` 메타 예시」를 따로 부른다)
private var metaExamples: [String] {
    PackImportCopy.guideSheet.filter { $0.first?.hasPrefix("#") == true }.flatMap { $0 }
        + [PackFormCopy.templatePlaceholder] + [TemplatePatternSpec.Failure.prefixTooShort, .reservedDateSuffix].compactMap(PackFormCopy.templateFailureExample)
}

/// 번들 샘플 파일의 셀 전부(정보 줄·머리글 포함) — 앱이 읽는 그대로(BOM·인코딩은 디코더, 셀은 CSV 파서)
func sampleCells(_ url: URL) throws -> [String] {
    let text = try PackTextDecoder.decode(Data(contentsOf: url)).text
    return try CSVRecordParser.parse(text, delimiter: .comma).records.flatMap(\.cells)
}

/// 이 빌드의 번들 샘플 폴더에 든 파일 전부
private func bundledSampleFiles() throws -> [URL] {
    let directory = try #require(PackSample.bundledDirectory)
    return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }
}

// MARK: - 앱 소스의 문자열

/// 앱(`App/`) 소스의 문자열 리터럴 — 화면에 직접 쓴 문구가 표를 거치지 않았어도 AC-35 검색에 걸리게. 주석(`//`·`/* */`)은 건너뛰고,
/// 보간 `\( … )` 안의 리터럴도 따로 모은다. 여러 줄 리터럴(`"""`)도 받는다
private struct SwiftStringLiterals {
    private let characters: [Character]
    private var index = 0
    private(set) var literals: [String] = []

    init(_ source: String) {
        characters = Array(source)
        code(untilClosingParen: false)
    }

    private func peek(_ offset: Int) -> Character? {
        index + offset < characters.count ? characters[index + offset] : nil
    }

    private mutating func code(untilClosingParen: Bool) {
        var depth = 0
        while index < characters.count {
            let character = characters[index]
            if character == "/", peek(1) == "/" {
                while index < characters.count, characters[index] != "\n" { index += 1 }
            } else if character == "/", peek(1) == "*" {
                index += 2
                while index < characters.count, !(characters[index] == "*" && peek(1) == "/") { index += 1 }
                index += 2
            } else if character == "\"" {
                string()
            } else {
                if untilClosingParen {
                    if character == "(" { depth += 1 }
                    if character == ")" {
                        if depth == 0 { index += 1; return }
                        depth -= 1
                    }
                }
                index += 1
            }
        }
    }

    private mutating func string() {
        let multiline = peek(1) == "\"" && peek(2) == "\""
        index += multiline ? 3 : 1
        var text = ""
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if peek(1) == "(" {
                    index += 2
                    code(untilClosingParen: true)
                    text += "…"
                } else {
                    if let escaped = peek(1) { text.append(escaped) }
                    index += 2
                }
                continue
            }
            if multiline, character == "\"", peek(1) == "\"", peek(2) == "\"" { index += 3; break }
            if !multiline, character == "\"" || character == "\n" { index += 1; break }
            text.append(character)
            index += 1
        }
        literals.append(text)
    }
}

/// 저장소의 `App/` 폴더 — 이 시험 파일에서 거슬러 올라간다(`Packages/PackImport/Tests/PackImportTests/`)
private let appSourceDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()   // PackImportTests · Tests · PackImport
    .deletingLastPathComponent().deletingLastPathComponent()                               // Packages · 저장소
    .appendingPathComponent("App")

private func appStringLiterals() throws -> [(file: String, literal: String)] {
    let enumerator = try #require(FileManager.default.enumerator(at: appSourceDirectory, includingPropertiesForKeys: nil))
    var found: [(String, String)] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let source = try String(contentsOf: url, encoding: .utf8)
        found += SwiftStringLiterals(source).literals.map { (url.lastPathComponent, $0) }
    }
    return found
}

// MARK: - 시험

@Suite("외부 채움글 1-c 6단계 ②③ — 문구 검사 한 곳 (AC-35 · U6 · 금칙어)")
struct PackCopyLintTests {

    // MARK: 규칙 자체

    @Test("★ AC-35 규칙 — 막는 것: xlsx 형식·엑셀 파일을 가져오는 안내 / 두는 것: 엑셀에서 CSV로 저장하는 안내", arguments: [
        ("엑셀 파일 그대로 가져오기", true), ("엑셀 파일 고르기", true), ("엑셀로 팩 만드는 법", true), ("엑셀", true),
        ("번호형 샘플.xlsx", true), ("XLSX", true), ("Excel 통합 문서(.xlsx)", true), ("옛 엑셀(.xls)", true), ("매크로가 든 파일(.xlsm·.xlsb)", true),
        ("엑셀 통합 문서로 저장", true), ("Workbook", true),
        ("엑셀·Numbers·구글 시트에서는 「CSV UTF-8」로 저장한 뒤 가져와요.", false),
        ("다음부터는 엑셀에서 「CSV UTF-8」로 저장하면 이 화면이 안 나와요.", false),
        ("엑셀이나 구글 시트에서 숫자·날짜처럼 보이는 글", false),
        ("엑셀·구글 시트에서 칸을 골라 복사하면 그대로 붙어요.", false),
        ("CSV 파일 가져오기", false), ("번호형 샘플.csv", false)
    ])
    func xlsxRule(_ text: String, flagged: Bool) {
        #expect(!PackCopyLint.xlsxMentions(in: text).isEmpty == flagged, "\(text)")
    }

    @Test("U6 규칙 — 예외는 그 문자열 하나뿐(같은 낱말이 다른 문장에 들면 걸린다) · 평범한 낱말 속 조각은 지우고 본다")
    func churchRule() {
        #expect(PackCopyLint.churchExceptions == ["내장 성경 채움글의 구절 단축어와 겹쳐요"])
        #expect(PackCopyLint.churchWords(in: "내장 성경 채움글의 구절 단축어와 겹쳐요").isEmpty)
        #expect(PackCopyLint.churchWords(in: "내장 성경 채움글의 구절 단축어와 겹쳐요.") == ["성경", "구절"])
        #expect(PackCopyLint.churchWords(in: "성경 1장 예시 팩") == ["성경"])
        #expect(PackCopyLint.churchWords(in: "필요한 칸만 남겨 주세요").isEmpty)
        #expect(PackCopyLint.churchWords(in: "요한 1장") == ["요한"])
    }

    @Test("U6 예외는 낡지 않았다 — 예외 문자열은 실제로 화면에 나가고, 교회·성경 낱말을 품고 있어 예외가 아니면 걸린다")
    func exceptionsAreLive() {
        for exception in PackCopyLint.churchExceptions {
            #expect(allScreenCopy.contains(exception))
            let checked = PackCopyLint.churchFalsePositives.reduce(exception) { $0.replacingOccurrences(of: $1, with: "") }
            #expect(PackCopyLint.churchWords.contains(where: checked.contains))
        }
    }

    // MARK: AC-35

    @Test("★ AC-35 — CSV 전용판의 화면 문구 전부(1~6단계 표)에 xlsx 언급 0")
    func csvScreenCopyHasNoXLSX() {
        let texts = PackCopySet.$previewing.withValue(.csv) { allScreenCopy }
        #expect(texts.count > 300)
        for text in texts { #expect(PackCopyLint.xlsxMentions(in: text).isEmpty, "\(PackCopyLint.xlsxMentions(in: text)): \(text)") }
    }

    @Test("★ AC-35 — CSV 전용판의 번들 리소스: 샘플 폴더에는 CSV뿐이고, 셀·파일 이름·알약에 xlsx 언급 0")
    func csvBundleHasNoXLSX() throws {
        let files = try bundledSampleFiles()
        #expect(files.map(\.lastPathComponent) == ["sample-numbered.csv", "sample-phrases.csv"])
        for url in files {
            #expect(url.pathExtension == "csv")
            for cell in try sampleCells(url) { #expect(PackCopyLint.xlsxMentions(in: cell).isEmpty, "\(url.lastPathComponent): \(cell)") }
        }
        PackCopySet.$previewing.withValue(.csv) {
            for file in PackSample.Kind.allCases.flatMap({ PackSample.files($0) }) {
                #expect(file.format == .csv)
                for text in [file.displayName, PackImportCopy.sampleFormatLabel(file.format), PackImportCopy.sampleShareLabel(file)] {
                    #expect(PackCopyLint.xlsxMentions(in: text).isEmpty, "\(text)")
                }
            }
        }
    }

    @Test("★ AC-35 — 앱(`App/`) 소스에 직접 쓴 문자열에도 xlsx 언급 0(주석 제외)")
    func appSourceHasNoXLSX() throws {
        let literals = try appStringLiterals()
        // 검색이 실제로 돈다 — 앱이 직접 쓴 문구 하나가 잡혀야 한다(SnippetCleanupView의 접근성 힌트)
        #expect(literals.contains { $0.file == "SnippetCleanupView.swift" && $0.literal == "고치기" })
        #expect(literals.count > 100)
        for (file, literal) in literals { #expect(PackCopyLint.xlsxMentions(in: literal).isEmpty, "\(file): \(literal)") }
    }

    @Test("앱 소스 검색 — 주석은 빼고, 보간 안의 문자열·여러 줄 문자열은 넣는다")
    func literalScanner() {
        let source = """
        // 주석 "xlsx"
        /* 묶음 주석 "엑셀 파일" */
        let a = "가나" // 꼬리 "엑셀로"
        let b = "앞 \\(flag ? "안쪽" : "다른") 뒤"
        let c = \"\"\"
        여러 줄 "따옴표"
        \"\"\"
        """
        let literals = SwiftStringLiterals(source).literals
        #expect(literals.contains("가나"))
        #expect(literals.contains("안쪽") && literals.contains("다른"))
        #expect(literals.contains("앞 … 뒤"))
        #expect(literals.contains { $0.contains("여러 줄") })
        #expect(!literals.contains { $0.contains("xlsx") || $0.contains("엑셀") })
    }

    @Test("AC-35 검색은 xlsx 중심판의 xlsx 줄을 실제로 잡는다 — 판을 잘못 고르면 이 검색이 실패한다")
    func xlsxSetIsCaught() {
        PackCopySet.$previewing.withValue(.xlsx) {
            for text in [PackImportCopy.heroTitle, PackImportCopy.heroMessage, PackImportCopy.pickFile, PackImportCopy.guideTitle,
                         PackImportCopy.startFooter, PackImportCopy.guideSave, PackImportCopy.guideCellsFooter, PackNoticeCopy.emptyListFooter,
                         PackImportCopy.sampleFormatLabel(.xlsx), PackSample.File(kind: .numbered, format: .xlsx).displayName] {
                #expect(!PackCopyLint.xlsxMentions(in: text).isEmpty, "\(text)")
            }
            #expect(allScreenCopy.contains { !PackCopyLint.xlsxMentions(in: $0).isEmpty })
        }
    }

    // MARK: U6

    @Test("★ U6 — 두 판의 화면 문구 전부에 교회·성경 소재 0(예외 목록의 문자열만 뺀다)", arguments: PackCopySet.allCases)
    func screenCopyHasNoChurchWords(_ set: PackCopySet) {
        for text in PackCopySet.$previewing.withValue(set, operation: { allScreenCopy }) {
            #expect(PackCopyLint.churchWords(in: text).isEmpty, "\(PackCopyLint.churchWords(in: text)): \(text)")
        }
    }

    @Test("★ U6 — `#` 예시(시트 그림의 정보 줄·틀 예시)와 번들 샘플의 모든 셀(정보 줄 포함)에 교회·성경 소재 0")
    func examplesAndSamplesHaveNoChurchWords() throws {
        #expect(metaExamples.contains("#틀") && metaExamples.contains("예: 사자성어 {n}번"))
        for text in metaExamples { #expect(PackCopyLint.churchWords(in: text).isEmpty, "\(text)") }
        for url in try bundledSampleFiles() {
            let cells = try sampleCells(url)
            #expect(cells.contains { $0.hasPrefix("#") })
            for cell in cells { #expect(PackCopyLint.churchWords(in: cell).isEmpty, "\(url.lastPathComponent): \(cell)") }
        }
    }

    // MARK: 금칙어

    @Test("★ 금칙어 0 — 두 판의 화면 문구 전부", arguments: PackCopySet.allCases)
    func noBannedWords(_ set: PackCopySet) {
        for text in PackCopySet.$previewing.withValue(set, operation: { allScreenCopy }) {
            #expect(PackCopyLint.bannedWords(in: text).isEmpty, "\(text)")
        }
    }
}
