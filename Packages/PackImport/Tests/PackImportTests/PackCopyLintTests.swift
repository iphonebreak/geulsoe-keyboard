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
// - **R27**(PDR 결정 표, 2026-10-07): 외부 채움글 화면·샘플에 「권리」 0 — 보이는 이름은 「출처」다(코드 식별자 `license`는 그대로).
//   앱 전체에는 「권리 표기」 0(처리방침의 가져온 팩 문장 포함). 옛 `#권리`는 **읽기만** 받는다(파서 별칭 — 안내·샘플에 쓰지 않는다).
//   예외는 `PackCopyLint.retiredExceptions`에 **정확한 문자열로만** 둔다 — `#출처`와 `#권리`가 함께 있을 때의 거부 이유 하나(검증 O1)
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

    /// R27 — 외부 채움글 화면·샘플에서 물러난 낱말(보이는 이름은 「출처」)
    static let retiredWords = ["권리"]
    /// R27 — 앱 전체(처리방침 포함)에서 물러난 말
    static let retiredAppPhrases = ["권리 표기"]

    /// R27 예외 — **정확히 이 문자열만**. 파일에 `#출처`와 옛 `#권리`가 함께 있을 때의 거부 이유라, 파일에 실제로 쓰인 옛 키를 말해야
    /// 사용자가 무엇이 두 번인지 찾는다(검증 O1). 안내·샘플에서 옛 키를 권하는 문구가 아니다
    static var retiredExceptions: [String] { [PackImportCopy.failureMessage(.structural(.duplicateSourceMeta(record: 1, line: 1)), source: .file)] }

    static func retiredWords(in text: String) -> [String] {
        guard !retiredExceptions.contains(text) else { return [] }
        return retiredWords.filter(text.contains)
    }

    /// AC-35 — xlsx **형식** 이름(확장자 xls·xlsx·xlsm·xlsb — 점이 없어도·「통합 문서」·Excel·workbook·워크북)과, 엑셀을 **가져오는 대상**으로
    /// 가리키는 말(「엑셀 파일」·「엑셀로」·알약 「엑셀」·「엑셀·CSV 파일」). 엑셀은 **CSV를 만드는 곳**으로만 허용한다 — 「엑셀」(또는
    /// 「엑셀·Numbers·구글 시트」·「엑셀이나 구글 시트」처럼 엑셀로 시작하는 앱 목록) 바로 뒤가 「에서」여야 한다(마지막 패턴).
    /// 그래도 「엑셀에서 만든 파일을 그대로 골라요」처럼 무엇을 하라는지 없는 문장이 남으므로, 엑셀을 말하는 문장은 「CSV」나 「복사」가
    /// 함께 있어야 한다(`excelCompanions` — 검증 F-4 L1~L3)
    static let xlsxPatterns = [
        #"(?i)(?<![a-z])xls[xmb]?(?![a-z])"#, #"(?i)excel"#, #"(?i)workbook"#, "워크북", #"통합\s*문서"#,
        #"엑셀(?!(?:(?:·|이나\s)[^·\s]+(?:\s[^·\s]+)?)*에서)"#
    ]

    /// 엑셀을 말하는 문장이 함께 가져야 하는 말 하나 — CSV로 저장하라는 안내이거나 칸을 복사해 붙이라는 안내다
    static let excelCompanions = ["CSV", "복사"]

    static func xlsxMentions(in text: String) -> [String] {
        var found = xlsxPatterns.filter { text.range(of: $0, options: .regularExpression) != nil }
        if text.contains("엑셀"), !excelCompanions.contains(where: text.contains) { found.append("엑셀(CSV·복사 없음)") }
        return found
    }

    static func churchWords(in text: String) -> [String] {
        guard !churchExceptions.contains(text) else { return [] }
        let checked = churchFalsePositives.reduce(text) { $0.replacingOccurrences(of: $1, with: "") }
        return churchWords.filter(checked.contains)
    }

    static func bannedWords(in text: String) -> [String] { bannedWords.filter(text.contains) }

    /// 실기 피드백 2(2026-10-08) — 머리글 자리를 「첫 줄」로 말하지 않는다: 정보 줄(#…)·빈 줄이 머리글 위에 와도 된다(판정 규칙).
    /// 머리글을 말하는 문구에만 건다 — 「예시 본문 첫 줄…」(시트 그림의 칸)처럼 본문의 첫 줄을 말하는 글은 대상이 아니다
    static let headerPositionWords = ["첫 줄", "첫줄", "첫 행", "첫째 줄", "맨 윗줄"]

    static func headerPositionWords(in text: String) -> [String] {
        text.contains("머리글") ? headerPositionWords.filter(text.contains) : []
    }

    /// U6를 앱 리터럴에 걸 파일 — 외부 채움글 화면(목록·상세·순서·가져오기·폼·안전망·정리). 앱 전체로 넓히면 기존 성경 기능 문구가 걸린다
    static func isPackScreenFile(_ name: String) -> Bool {
        name.hasPrefix("PackImport") || ["ExternalPackViews.swift", "PackSafetyNetViews.swift", "SnippetCleanupView.swift"].contains(name)
    }
}

// MARK: - 검사 대상

/// 6단계 문구 — 3-A 「처음이라면」 샘플 줄·3-C 공유 파일 이름 · xlsx판의 「그 밖의 방법」 파일 줄(지금 판으로)
var stage6Copy: [String] {
    var texts: [String] = []   // 「처음이라면」 풋터(샘플 안내)는 뺐다(사장님 실기 2026-10-07)
    for kind in PackSample.Kind.allCases {
        texts += [PackImportCopy.sampleRowTitle(kind), PackImportCopy.sampleTitle(kind), PackImportCopy.sampleDetail(kind)]
        texts += PackSample.files(kind).flatMap { [PackImportCopy.sampleFormatLabel($0.format), PackImportCopy.sampleShareLabel($0), $0.displayName] }
    }
    if let row = PackImportCopy.otherFileRow { texts += [row.title, row.detail] }
    return texts
}

/// 화면 문구 전부(1~6단계 + 1-e ③) — **지금 판으로** 만든다. 시험은 `PackCopySet.$previewing`으로 판을 고른다.
/// 엑셀 사유·시트 고르기 문구(`workbookOnlyCopy`)는 xlsx를 받는 판에서만 화면에 닿는다(CSV 전용판 세션은 xlsx를 읽지 않는다 — AC-35)
var allScreenCopy: [String] {
    stage1To3Copy + stage4Copy + PackImportCopy.guideSheet.flatMap { $0 } + stage5Copy + [PackNoticeCopy.unreadableListFooter] + stage6Copy
        + (PackCopySet.current.acceptsWorkbookFiles ? workbookOnlyCopy : [])
}

/// `#` 예시 — 만드는 법 시트 그림의 정보 줄·폼의 틀 예시(U6이 「`#` 메타 예시」를 따로 부른다)
private var metaExamples: [String] {
    PackImportCopy.guideSheet.filter { $0.first?.hasPrefix("#") == true }.flatMap { $0 }
        + [PackFormCopy.templatePlaceholder] + [TemplatePatternSpec.Failure.prefixTooShort, .reservedDateSuffix].compactMap(PackFormCopy.templateFailureExample)
}

/// 번들 샘플 파일의 셀 전부(정보 줄·머리글 포함) — 앱이 읽는 그대로(CSV: BOM·인코딩은 디코더, 셀은 CSV 파서 / xlsx: 워크북 독자의 표 칸 +
/// 공유 문자열 항목 전부 — `workbookSampleTexts`)
func sampleCells(_ url: URL) throws -> [String] {
    if url.pathExtension == "xlsx" {
        let texts = try workbookSampleTexts(Data(contentsOf: url))
        return texts.cells + texts.sharedStrings
    }
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
        // 검증 F-4 L1~L3 — 엑셀을 가져오는 대상으로 · 할 일 없는 「엑셀에서」 · 점 없는 형식 이름
        ("엑셀·CSV 파일을 그대로 가져와요", true), ("엑셀에서 만든 파일을 그대로 골라요", true), ("XLS 파일도 돼요", true),
        ("XLS파일", true), ("xlsx로 저장", true), ("엑셀이나 CSV 파일 고르기", true), ("엑셀 워크북", true), ("통합문서", true),
        ("엑셀이나 구글 시트에서 숫자·날짜처럼 보이는 글", true),   // CSV·복사가 없다 — 무엇을 하라는지 없어 걸린다(보수적)
        ("엑셀·Numbers·구글 시트에서는 「CSV UTF-8」로 저장한 뒤 가져와요.", false),
        ("다음부터는 엑셀에서 「CSV UTF-8」로 저장하면 이 화면이 안 나와요.", false),
        // 계획서 11절 F-2 — 「엑셀은 …」은 CSV가 있어도 걸린다(규칙을 넓히지 않고 문구를 「엑셀에서는」으로, 2026-10-07 코디네이터 결정)
        ("엑셀은 「CSV UTF-8」로 저장하고, Numbers·구글 시트는 CSV로 내보낸 뒤 가져와요.", true),
        ("엑셀에서는 「CSV UTF-8」로 저장하고, Numbers·구글 시트는 CSV로 내보낸 뒤 가져와요.", false),
        ("엑셀이나 구글 시트에서 칸을 골라 복사해요.", false),
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

    /// **판별 규칙(1-e ④)** — 번들 샘플 폴더의 파일은 확장자(형식)로 판에 속한다. 판의 검사 대상은 **판이 내보내는 형식**(`sampleFormats`)의 파일이고,
    /// 그 밖의 형식 파일(CSV 전용판의 xlsx 샘플 — xlsx판 「샘플 받기」 몫)은 ① 알려진 이름뿐이고 ② 판이 꺼내지 못해야(`bundledURL` nil) 한다.
    /// 화면에 닿지 않는 파일이라 「샘플 리소스」 검색 대상이 아니다 — 대신 꺼내지 못함을 검사한다(`PackSampleEditionTests`)
    @Test("★ AC-35 — CSV 전용판의 번들 리소스: 판이 내보내는 샘플은 CSV뿐이고 셀·파일 이름·알약에 xlsx 언급 0, 번들의 xlsx 샘플은 판이 꺼내지 못한다")
    func csvBundleHasNoXLSX() throws {
        let files = try bundledSampleFiles()
        #expect(files.map(\.lastPathComponent) == ["sample-numbered.csv", "sample-numbered.xlsx", "sample-phrases.csv", "sample-phrases.xlsx"])
        try PackCopySet.$previewing.withValue(.csv) {
            let shipped = PackCopySet.current.lines.sampleFormats.map(\.fileExtension)
            #expect(shipped == ["csv"])
            for url in files where shipped.contains(url.pathExtension) {
                for cell in try sampleCells(url) { #expect(PackCopyLint.xlsxMentions(in: cell).isEmpty, "\(url.lastPathComponent): \(cell)") }
            }
            let withheld = files.filter { !shipped.contains($0.pathExtension) }
            #expect(withheld.map(\.lastPathComponent) == ["sample-numbered.xlsx", "sample-phrases.xlsx"])
            for kind in PackSample.Kind.allCases {
                #expect(PackSample.File(kind: kind, format: .xlsx).bundledURL == nil, "CSV 전용판은 xlsx 샘플을 꺼내지 못한다")
            }
            for file in PackSample.Kind.allCases.flatMap({ PackSample.files($0) }) {
                #expect(file.format == .csv && file.bundledURL != nil)
                for text in [file.displayName, PackImportCopy.sampleFormatLabel(file.format), PackImportCopy.sampleShareLabel(file)] {
                    #expect(PackCopyLint.xlsxMentions(in: text).isEmpty, "\(text)")
                }
            }
        }
    }

    @Test("판별 규칙 — xlsx 중심판은 번들 샘플 넷을 모두 내보낸다(빠진 형식 없음), 샘플 칸에도 xlsx를 말하는 글은 없다(내용은 두 형식이 같다)")
    func xlsxEditionShipsAllSamples() throws {
        let files = try bundledSampleFiles()
        try PackCopySet.$previewing.withValue(.xlsx) {
            let shipped = PackCopySet.current.lines.sampleFormats.map(\.fileExtension)
            #expect(files.allSatisfy { shipped.contains($0.pathExtension) })
            #expect(PackSample.Kind.allCases.flatMap { PackSample.files($0) }.allSatisfy { $0.bundledURL != nil })
            for url in files {
                for cell in try sampleCells(url) { #expect(PackCopyLint.xlsxMentions(in: cell).isEmpty, "\(url.lastPathComponent): \(cell)") }
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

    @Test("★ 검증 F-4 ② — 앱(`App/`) 소스에 직접 쓴 문자열도 금칙어 0(앱 전체), 외부 채움글 화면 파일은 U6도 0")
    func appSourceHasNoBannedOrChurchWords() throws {
        let literals = try appStringLiterals()
        for (file, literal) in literals { #expect(PackCopyLint.bannedWords(in: literal).isEmpty, "\(file): \(literal)") }
        // U6는 팩 화면 파일로 좁힌다 — 앱 전체면 기존 성경 기능(설정의 「성경 (개역한글)」 등) 문구가 걸린다
        let packScreen = literals.filter { PackCopyLint.isPackScreenFile($0.file) }
        #expect(Set(packScreen.map(\.file)).isSuperset(of: ["ExternalPackViews.swift", "PackImportFlowView.swift", "PackImportFormView.swift",
                                                           "PackImportViews.swift", "PackSafetyNetViews.swift", "SnippetCleanupView.swift"]),
                "검색 대상 파일이 실제로 문자열을 낸다 — 이름이 바뀌면 이 시험이 알린다")
        for (file, literal) in packScreen { #expect(PackCopyLint.churchWords(in: literal).isEmpty, "\(file): \(literal)") }
    }

    @Test("검증 F-4 ② — 앱 문자열 검색이 금칙어·U6를 실제로 잡는다(규칙이 앱 리터럴에 걸려 있다)")
    func appLiteralRulesCatch() {
        let source = #"Text("잠시 뒤 다시 해 주세요"); Text("찬송가 팩"); Text("트리거 \(n)")"#
        let literals = SwiftStringLiterals(source).literals
        #expect(literals.contains { !PackCopyLint.bannedWords(in: $0).isEmpty })
        #expect(literals.contains { !PackCopyLint.churchWords(in: $0).isEmpty })
        #expect(PackCopyLint.isPackScreenFile("PackImportFormView.swift") && PackCopyLint.isPackScreenFile("ExternalPackViews.swift"))
        #expect(!PackCopyLint.isPackScreenFile("SnippetSettingsView.swift"), "기존 채움글·성경 설정 화면은 U6 대상이 아니다")
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
                         PackImportCopy.startFooter ?? "", PackImportCopy.guideSave.joined(separator: " "), PackImportCopy.guideCellsFooter,
                         PackNoticeCopy.emptyListFooter,
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

    // MARK: R27 「권리」 → 「출처」

    @Test("★ R27 — 두 판의 화면 문구 전부에 「권리」 0(보이는 이름은 「출처」)", arguments: PackCopySet.allCases)
    func screenCopyHasNoRetiredWords(_ set: PackCopySet) {
        let texts = PackCopySet.$previewing.withValue(set, operation: { allScreenCopy })
        #expect(texts.contains { $0.contains("출처") }, "검사가 실제 출처 문구를 돈다")
        for text in texts { #expect(PackCopyLint.retiredWords(in: text).isEmpty, "\(text)") }
    }

    @Test("R27 예외는 그 문자열 하나뿐이고 낡지 않았다 — 실제로 화면에 나가고(파일·붙여넣기 둘 다), 「권리」를 품고 있어 예외가 아니면 걸린다")
    func retiredExceptionIsLive() {
        #expect(PackCopyLint.retiredExceptions == ["「#출처」와 「#권리」는 같은 정보 줄이에요. 하나만 남겨 주세요."])
        for exception in PackCopyLint.retiredExceptions {
            #expect(allScreenCopy.contains(exception))
            #expect(PackImportCopy.failureMessage(.structural(.duplicateSourceMeta(record: 1, line: 1)), source: .paste) == exception)
            #expect(PackCopyLint.retiredWords.contains(where: exception.contains))
            #expect(PackCopyLint.retiredWords(in: exception).isEmpty)
            #expect(PackCopyLint.retiredWords(in: exception + " 「#권리」") == ["권리"], "같은 낱말이 다른 문장에 들면 걸린다")
        }
    }

    @Test("★ R27 — 앱 소스: 외부 채움글 화면 파일 리터럴에 「권리」 0, 앱 전체(처리방침 포함)에 「권리 표기」 0")
    func appSourceHasNoRetiredWords() throws {
        let literals = try appStringLiterals()
        for (file, literal) in literals where PackCopyLint.isPackScreenFile(file) {
            #expect(PackCopyLint.retiredWords(in: literal).isEmpty, "\(file): \(literal)")
        }
        for (file, literal) in literals {
            #expect(!PackCopyLint.retiredAppPhrases.contains(where: literal.contains), "\(file): \(literal)")
        }
        #expect(literals.contains { $0.file == "PrivacyPolicyView.swift" && $0.literal.contains("(팩 이름·단축어·본문·출처)") },
                "처리방침의 가져온 팩 문장이 「출처」로 바뀌었다")
    }

    @Test("★ R27 — 번들 샘플의 셀에 「권리」 0 — 정보 줄 키는 `#출처`(옛 `#권리`는 읽기 별칭일 뿐)")
    func samplesUseSourceKey() throws {
        for url in try bundledSampleFiles() {
            let cells = try sampleCells(url)
            #expect(cells.contains("#출처"), "\(url.lastPathComponent)")
            for cell in cells { #expect(PackCopyLint.retiredWords(in: cell).isEmpty, "\(url.lastPathComponent): \(cell)") }
        }
    }

    // MARK: 금칙어

    @Test("★ 금칙어 0 — 두 판의 화면 문구 전부", arguments: PackCopySet.allCases)
    func noBannedWords(_ set: PackCopySet) {
        for text in PackCopySet.$previewing.withValue(set, operation: { allScreenCopy }) {
            #expect(PackCopyLint.bannedWords(in: text).isEmpty, "\(text)")
        }
    }

    // MARK: 머리글 자리 (실기 피드백 2, 2026-10-08)

    @Test("★ 실기 피드백 2 — 두 판의 화면 문구 전부에서 머리글 자리를 「첫 줄」로 말하지 않는다(정보 줄·빈 줄이 위에 와도 된다)",
          arguments: PackCopySet.allCases)
    func noFirstLineHeader(_ set: PackCopySet) {
        for text in PackCopySet.$previewing.withValue(set, operation: { allScreenCopy }) {
            #expect(PackCopyLint.headerPositionWords(in: text).isEmpty, "\(text)")
        }
    }

    @Test("머리글 자리 규칙은 옛 문구를 실제로 잡고, 본문의 첫 줄을 말하는 시트 그림 칸은 잡지 않는다")
    func headerPositionRuleCatches() {
        for old in ["첫 줄에 머리글이 있는 엑셀 파일(.xlsx)을 골라요.", "첫 줄은 머리글", "머리글을 찾지 못했어요. 첫 줄(머리글)을 확인해 주세요."] {
            #expect(!PackCopyLint.headerPositionWords(in: old).isEmpty, "\(old)")
        }
        #expect(PackImportCopy.guideSheet.joined().contains("예시 본문 첫 줄…"))
        #expect(PackCopyLint.headerPositionWords(in: "예시 본문 첫 줄…").isEmpty)
    }
}
