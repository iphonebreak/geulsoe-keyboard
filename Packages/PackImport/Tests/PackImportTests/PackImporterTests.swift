import Foundation
import Testing
import TadakDomain
@testable import PackImport

/// 가져오기 파이프라인 — 구분자 후보·헤더/메타 dialect·열 수·행별 검증·R10 (PDR 5-2~5-5).
enum ImportHelper {
    static func draft(_ text: String, delimiter: CSVDelimiter? = nil) throws -> PackDraft {
        switch try PackImporter.read(text: text, delimiter: delimiter) {
        case .draft(let draft): return draft
        case .chooseDelimiter(let candidates):
            Issue.record("구분자 선택이 필요하다고 나왔다: \(candidates)")
            throw PackImportFailure.headerNotRecognized
        }
    }

    static func draft(data: Data, options: PackImportOptions = PackImportOptions()) throws -> PackDraft {
        switch try PackImporter.read(data, options: options) {
        case .draft(let draft): return draft
        case .chooseDelimiter(let candidates):
            Issue.record("구분자 선택이 필요하다고 나왔다: \(candidates)")
            throw PackImportFailure.headerNotRecognized
        }
    }

    static func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "csv", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    static func reasons(_ draft: PackDraft) -> [SkipReason] { draft.skipped.map(\.reason) }
}

@Suite("구분자 후보 검증 (5-2, AC-10 · AC-49)")
struct DelimiterCandidateTests {

    @Test("쉼표 CSV — 쉼표만 채택")
    func comma() throws {
        #expect(try ImportHelper.draft("단축어,본문\r\n인사,안녕하세요").delimiter == .comma)
    }

    @Test("세미콜론 CSV — 세미콜론만 채택")
    func semicolon() throws {
        let draft = try ImportHelper.draft("단축어;본문\r\n인사;안녕, 반가워요")
        #expect(draft.delimiter == .semicolon)
        #expect(draft.entries.map(\.body) == ["안녕, 반가워요"])
    }

    /// v2 반례: 「따옴표 밖 최빈값」이면 `;`가 이긴다. 후보 검증이면 `;`는 머리글이 안 되어 탈락한다
    @Test("탭 머리글 + `x;y;z;w` 반례는 탭으로 채택된다 (AC-10)")
    func tabCounterexample() throws {
        let draft = try ImportHelper.draft("단축어\t본문\tx;y;z;w\r\n인사\t안녕\t1;2;3;4")
        #expect(draft.delimiter == .tab)
        #expect(draft.ignoredColumnCount == 1)
    }

    @Test("두 후보가 모두 채택되면 사용자에게 고르게 하고, 고른 구분자로 다시 읽는다 (AC-10)")
    func ambiguousAsksUser() throws {
        let text = "단축어,본문,z;trigger;body\r\na,b,c;d;e"
        #expect(try PackImporter.read(text: text) == .chooseDelimiter([.comma, .semicolon]))
        let chosen = try ImportHelper.draft(text, delimiter: .semicolon)
        #expect(chosen.delimiter == .semicolon)
        #expect(chosen.entries.map(\.triggers) == [["d"]])
    }

    @Test("채택 후보가 0개면 머리글 오류로 거부 (AC-10)")
    func noneAdopted() {
        #expect(throws: PackImportFailure.headerNotRecognized) { try PackImporter.read(text: "foo,bar\r\n1,2") }
    }

    /// v3.4 명확화 ① — 고정 문구형 샘플의 첫 셀이 `"회의시작,회의 시작"`이라 `;`·탭으로 시험하면 quote 오류가 난다
    @Test("후보 시험의 quote 오류는 그 후보만 탈락 — 고정 문구형 샘플이 쉼표로 전부 수용된다 (AC-49 a)")
    func trialQuoteErrorDropsCandidateOnly() throws {
        let draft = try ImportHelper.draft(data: ImportHelper.fixture("sample-phrases.original"))
        #expect(draft.delimiter == .comma)
        #expect(draft.entries.count == 15)
        #expect(draft.skipped.isEmpty)
    }

    @Test("채택한 구분자로 본 파싱 중 quote 오류 → 전체 거부 (AC-49 b)")
    func adoptedDelimiterQuoteErrorRejectsAll() {
        var lines = ["단축어,본문"]
        for index in 1...39 { lines.append("문구\(index),본문\(index)") }
        lines.append("문구40,\"닫은 뒤\"글자")              // 시험 범위(앞 레코드들) 밖 — 41번째 레코드
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 41, line: 41))) {
            try PackImporter.read(text: lines.joined(separator: "\r\n"))
        }
    }

    @Test("모든 후보가 quote 오류로 탈락하면 「따옴표 오류」로 거부 (AC-49 c)")
    func allCandidatesQuoteError() {
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 1, line: 1))) {
            try PackImporter.read(text: "\"단축어\"x,본문\r\na,b")
        }
    }
}

@Suite("헤더·메타 dialect (5-3, AC-11 · AC-12 · AC-14)")
struct HeaderMetaTests {

    @Test("본문 셀 안의 `\\n#권리,…`는 메타가 아니고, 따옴표로 감싼 `\"#이름\"`은 메타다 (AC-11)")
    func metaIsJudgedByLogicalRecord() throws {
        let text = "\"#이름\",예시 팩\r\n#권리,진짜 권리\r\n단축어,본문\r\n인사,\"첫 줄\n#권리,가짜 권리\"\r\n"
        let draft = try ImportHelper.draft(text)
        #expect(draft.meta.name == "예시 팩")
        #expect(draft.meta.license == "진짜 권리")
        #expect(draft.entries.map(\.body) == ["첫 줄\n#권리,가짜 권리"])
    }

    @Test("메타가 머리글 뒤에 있으면 위치 오류 — 전체 거부 (AC-12)", arguments: ["#이름", "#틀", "#권리", "#escape"])
    func metaAfterHeader(key: String) {
        let text = "번호,본문\r\n1,가\r\n\(key),값"
        #expect(throws: PackImportFailure.metaAfterHeader(record: 3, line: 3)) { try PackImporter.read(text: text) }
    }

    @Test("중복 메타·알 수 없는 `#` 키·`#escape`(후속 단계) → 전체 거부 (AC-12)")
    func badMeta() {
        #expect(throws: PackImportFailure.duplicateMeta(record: 2, line: 2)) {
            try PackImporter.read(text: "#이름,가\r\n#이름,나\r\n단축어,본문\r\na,b")
        }
        #expect(throws: PackImportFailure.unknownMeta(record: 1, line: 1)) {
            try PackImporter.read(text: "#메모,가\r\n단축어,본문\r\na,b")
        }
        #expect(throws: PackImportFailure.unsupportedEscapeMeta(record: 1, line: 1)) {
            try PackImporter.read(text: "#escape,v1\r\n단축어,본문\r\na,b")
        }
    }

    @Test("`#틀` 별칭 8개(9셀)는 데이터 열 cap(8)과 충돌하지 않는다 (AC-12)")
    func templateWithEightAliases() throws {
        let aliases = ["가", "나", "다", "라", "마", "바", "사", "아"].map { "별칭\($0) {n}번" }
        let text = "#틀," + aliases.joined(separator: ",") + "\r\n번호,본문\r\n1,가"
        let draft = try ImportHelper.draft(text)
        #expect(draft.meta.templateSpecs == aliases)
        #expect(draft.items.count == 1)
    }

    @Test("메타 값 개수 위반 → 전체 거부 — trailing 빈 셀만 허용 (5-3)", arguments: [
        "#틀,a {n}번,b {n}번,c {n}번,d {n}번,e {n}번,f {n}번,g {n}번,h {n}번,i {n}번",   // 9개
        "#틀,a {n}번,,b {n}번",                                                        // 사이 빈 칸
        "#이름,",                                                                       // 값 0
        "#이름,가,나"                                                                    // 값 2
    ])
    func metaValueCount(line: String) {
        #expect(throws: PackImportFailure.metaValueCount(record: 1, line: 1)) {
            try PackImporter.read(text: line + "\r\n번호,본문\r\n1,가")
        }
    }

    @Test("메타 실효 셀이 12를 넘으면 전체 거부")
    func metaCellCap() {
        let values = (1...12).map { "v\($0) {n}번" }.joined(separator: ",")
        #expect(throws: PackImportFailure.metaTooManyCells(record: 1, line: 1)) {
            try PackImporter.read(text: "#틀,\(values)\r\n번호,본문\r\n1,가")
        }
    }

    /// P-9 실측 — 엑셀·구글 모두 메타 줄을 머리글 폭까지 빈 칸으로 채운다
    @Test("메타 짧은 행의 trailing 빈 칸(머리글 폭까지)을 받는다 (AC-49 e)")
    func metaTrailingPadding() throws {
        let draft = try ImportHelper.draft("#이름,예시,,\r\n#틀,가나 {n}번,,\r\n번호,제목,본문,비고\r\n1,t,b,x")
        #expect(draft.meta.name == "예시")
        #expect(draft.meta.templateSpecs == ["가나 {n}번"])
    }

    @Test("문구형인데 `#틀`이 있으면 혼재로 전체 거부")
    func templateInPhrases() {
        #expect(throws: PackImportFailure.templateInPhrasesMode) {
            try PackImporter.read(text: "#틀,가나 {n}번\r\n단축어,본문\r\na,b")
        }
    }

    @Test("머리글 오류 → 전체 거부 (AC-14)", arguments: [
        ("본문,본문,단축어\r\na,b,c", PackImportFailure.duplicateHeader),
        ("단축어,본문,body\r\na,b,c", .duplicateHeaderAlias),
        ("번호,단축어,본문\r\n1,a,b", .mixedModeHeader),
        ("제목,본문\r\na,b", .missingRequiredColumn),
        ("번호,제목\r\n1,a", .missingRequiredColumn),
        ("번호,본문,a,b,c,d,e,f,g\r\n1,x,,,,,,,", .tooManyColumns)
    ])
    func headerErrors(testCase: (text: String, failure: PackImportFailure)) {
        #expect(throws: testCase.failure) { try PackImporter.read(text: testCase.text) }
    }

    @Test("열 이름은 앞뒤 공백·대소문자를 보지 않고, 모르는 열은 무시하고 센다")
    func headerNames() throws {
        let draft = try ImportHelper.draft(" TRIGGERS , Title ,BODY,비고\r\na,t,b,x")
        #expect(draft.mode == .phrases)
        #expect(draft.entries == [SnippetEntry(triggers: ["a"], title: "t", body: "b")])
        #expect(draft.ignoredColumnCount == 1)
    }
}

@Suite("열 수·빈 레코드·행별 검증 (5-4, AC-13 · AC-49 d)")
struct RecordValidationTests {

    @Test("열 수가 다르면 그 레코드만 건너뛴다 — 빈 셀로 채우지 않고, 초과분이 전부 빈 셀이면 받는다 (AC-13)")
    func columnCount() throws {
        let draft = try ImportHelper.draft("번호,제목,본문\r\n1,가\r\n2,나,본문2,넘침\r\n3,다,본문3,,\r\n4,라,본문4")
        #expect(draft.items.map(\.n) == [3, 4])
        #expect(ImportHelper.reasons(draft) == [.columnCount, .columnCount])
        #expect(draft.skipped.map(\.line) == [2, 3])
    }

    @Test("빈 레코드(`,,,`·빈 줄)는 어디서든 무시 — 분모·건너뜀 목록에 없다, 쪼개진 `,,둘째 줄,`는 번호 없음 (AC-49 d)")
    func blankRecordsIgnored() throws {
        let text = ",,,\r\n\r\n#이름,예시,,\r\n,,,\r\n번호,제목,본문,비고\r\n,,,\r\n1,가,첫 줄,\r\n,,둘째 줄,\r\n\r\n2,나,본문,\r\n,,,"
        let draft = try ImportHelper.draft(text)
        #expect(draft.meta.name == "예시")
        #expect(draft.dataRecordCount == 3)
        #expect(draft.acceptedRecordCount == 2)
        #expect(ImportHelper.reasons(draft) == [.missingNumber])
    }

    @Test("공백 글자만 든 셀은 빈 셀이 아니다(trim하지 않음)")
    func whitespaceCellIsNotBlank() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n1,가\r\n , ")
        #expect(draft.dataRecordCount == 2)
        #expect(ImportHelper.reasons(draft) == [.missingNumber])
    }

    @Test("번호 — trim·전각·`323.0`·앞자리 0은 값으로, 0·5자리·글자는 건너뜀", arguments: [
        ("1", SkipReason?.none, 1), (" 2 ", nil, 2), ("３", nil, 3), ("323.0", nil, 323), ("007", nil, 7),
        ("9999", nil, 9999), ("0", .numberOutOfRange, 0), ("10000", .invalidNumber, 0),
        ("1.5", .invalidNumber, 0), ("abc", .invalidNumber, 0), ("", .missingNumber, 0), ("-3", .invalidNumber, 0)
    ])
    func numbers(testCase: (cell: String, reason: SkipReason?, n: Int)) throws {
        let draft = try ImportHelper.draft("번호,본문\r\n\(testCase.cell),본문\r\n9998,다른 행")
        if let reason = testCase.reason {
            #expect(ImportHelper.reasons(draft) == [reason])
        } else {
            #expect(draft.skipped.isEmpty)
            #expect(draft.items.contains { $0.n == testCase.n })
        }
    }

    @Test("같은 번호는 뒤가 이기고 중복 건수를 센다, 항목은 번호 오름차순")
    func duplicateNumbersLaterWins() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n5,처음\r\n2,둘\r\n5,나중")
        #expect(draft.items == [PackTemplateItem(n: 2, title: "", body: "둘"), PackTemplateItem(n: 5, title: "", body: "나중")])
        #expect(draft.duplicateCount == 1)
        #expect(draft.acceptedRecordCount == 3)
    }

    @Test("본문 없음·공백만·필드 상한 → 그 행만 건너뜀")
    func bodyAndTitleLimits() throws {
        let long = String(repeating: "가", count: 3_001)
        let longTitle = String(repeating: "나", count: 61)
        let draft = try ImportHelper.draft("번호,제목,본문\r\n1,a,\r\n2,b,\"  \n \"\r\n3,c,\(long)\r\n4,\(longTitle),본문\r\n5,e,\(String(repeating: "가", count: 3_000))")
        #expect(ImportHelper.reasons(draft) == [.emptyBody, .emptyBody, .bodyTooLong, .titleTooLong])
        #expect(draft.items.map(\.n) == [5])
    }

    @Test("문구형 — 단축어 셀은 `TriggerCell`(쉼표·LF), 제목이 비면 첫 단축어, 단축어 위반은 그 행만 건너뜀")
    func phraseRows() throws {
        let many = (1...11).map { "s\($0)" }.joined(separator: ",")
        let draft = try ImportHelper.draft("단축어,제목,본문\r\n\"가,나\n다\",,본문1\r\n,제목2,본문2\r\n\"\(many)\",,본문3\r\n\(String(repeating: "x", count: 41)),,본문4")
        #expect(draft.entries == [SnippetEntry(triggers: ["가", "나", "다"], title: "가", body: "본문1")])
        #expect(ImportHelper.reasons(draft) == [.missingTrigger, .tooManyTriggers, .triggerTooLong])
    }

    @Test("문구형 — 정규화 기준 같은 단축어는 뒤 항목이 이기고 앞 항목에서 빠진다(비면 항목째)")
    func phraseDuplicatesLaterWins() throws {
        let draft = try ImportHelper.draft("단축어,본문\r\n\"인사,안녕\",첫째\r\n인 사,둘째\r\n안녕,셋째")
        #expect(draft.entries == [SnippetEntry(triggers: ["인 사"], title: "인 사", body: "둘째"),
                                  SnippetEntry(triggers: ["안녕"], title: "안녕", body: "셋째")])
        #expect(draft.duplicateCount == 2)
    }

    @Test("문자 정리 — 위험한 보이지 않는 문자는 빼고 ZWJ 이모지는 보존, 건수를 센다(11절)")
    func sanitized() throws {
        let draft = try ImportHelper.draft("단축어,본문\r\n인사,\"안\u{200B}녕\u{202E} 👨\u{200D}👩\u{200D}👧\"")
        #expect(draft.entries.first?.body == "안녕 👨\u{200D}👩\u{200D}👧")
        #expect(draft.sanitizedCharacterCount == 2)
    }

    @Test("데이터 논리 레코드가 5,000을 넘으면 거부 — 여러 줄 본문은 레코드 수를 늘리지 않는다 (AC-16)")
    func recordCap() throws {
        let body = "\"" + Array(repeating: "줄", count: 9).joined(separator: "\n") + "\""
        let rows = (1...5_000).map { "\($0),\(body)" }
        let ok = try ImportHelper.draft("번호,본문\r\n" + rows.joined(separator: "\r\n"))
        #expect(ok.items.count == 5_000)
        #expect(throws: PackImportFailure.tooManyRecords) {
            try PackImporter.read(text: "번호,본문\r\n" + rows.joined(separator: "\r\n") + "\r\n5001,b")
        }
    }
}

@Suite("건너뜀 비율 R10 (5-5, AC-19)")
struct SkipRatioTests {

    @Test("분모 = 데이터 논리 레코드, 50% 미만은 자동 진행")
    func belowHalf() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n1,a\r\n2,b\r\n,c")
        #expect(draft.dataRecordCount == 3 && draft.skipped.count == 1)
        #expect(!draft.requiresConfirmation && draft.isImportable)
    }

    @Test("50% 이상이면 자동 진행 금지(명시 확인 시 부분 가져오기)")
    func halfOrMore() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n1,a\r\n,b")
        #expect(draft.skippedRatio == 0.5)
        #expect(draft.requiresConfirmation && draft.isImportable)
    }

    @Test("유효 레코드 0이면 가져오기 불가")
    func noValid() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n,a\r\n0,b")
        #expect(!draft.isImportable)
    }

    @Test("구조 오류는 비율과 무관하게 전체 거부")
    func structuralErrorRegardlessOfRatio() {
        var lines = ["번호,본문"]
        for index in 1...50 { lines.append("\(index),본문") }
        lines.append("#권리,뒤에 온 메타")
        #expect(throws: PackImportFailure.metaAfterHeader(record: 52, line: 52)) {
            try PackImporter.read(text: lines.joined(separator: "\r\n"))
        }
    }
}

/// 실물 — P-9(2026-10-04) 검증자 손 시뮬레이션(`docs/release/verify-p9-p10.md` 5-2)과 같은 값이어야 한다.
/// 개인 정보 없음(가짜 내용·작성자/경로/메일 0건)을 복사 전에 확인했다.
@Suite("실물 CSV·고정 샘플 (P-9 기대값)")
struct RealFileTests {

    /// ★ 검증자 시뮬레이션(5-2)은 필드 상한을 적용하지 않았다 — T25 「긴 본문」(3,200자)이 PDR 11절 본문 상한
    ///   3,000자(잠정, P-8)를 넘어 **건너뜀 1이 더 나온다**(수용 30→29 · 건너뜀 8→9 · 21%→24%). 구조 수치(데이터 38 ·
    ///   번호 없음 5 · 본문 없음 1 · 번호 범위 2 · 중복 1)는 검증자와 같다. 본문 상한이 3,200자 이상으로 바뀌면 검증자 수치로 돌아간다.
    @Test("Mac 엑셀 「CSV UTF-8」 — BOM·쉼표·메타 패딩, 데이터 38 · 수용 29 · 건너뜀 9(24%, T25 본문 상한 포함) · 중복 1")
    func macExcelCSVUTF8() throws {
        let draft = try ImportHelper.draft(data: ImportHelper.fixture("mac-excel-csvutf8"))
        #expect(draft.encoding == .utf8 && draft.hadBOM && !draft.needsEncodingConfirmation)
        #expect(draft.delimiter == .comma && draft.mode == .numbered)
        #expect(draft.meta.name == "사자성어 예시 팩")
        #expect(draft.meta.license == "제작자 자체 작성, 예시 (가짜 내용)")
        #expect(draft.meta.templateSpecs == ["사자성어 {n}번", "성어 {n}번"])
        #expect(draft.ignoredColumnCount == 1)
        #expect(draft.dataRecordCount == 38)
        #expect(draft.acceptedRecordCount == 29)
        #expect(draft.skipped.count == 9)
        let reasons = ImportHelper.reasons(draft)
        #expect(reasons.filter { $0 == .missingNumber }.count == 5)
        #expect(reasons.filter { $0 == .emptyBody }.count == 1)
        #expect(reasons.filter { $0 == .numberOutOfRange || $0 == .invalidNumber }.count == 2)
        #expect(reasons.filter { $0 == .bodyTooLong }.count == 1, "T25 — 3,200자")
        #expect(draft.skipped.first { $0.reason == .bodyTooLong }?.record == 35, "메타 3 + 머리글 + 쪼개진 줄들 뒤")
        #expect(draft.duplicateCount == 1)
        #expect(draft.items.count == 28)
        #expect(draft.items.first { $0.n == 5 }?.title == "중복 번호", "T30이 T05를 덮는다")
        #expect(draft.items.contains { $0.n == 25 } == false)
        #expect(Int((draft.skippedRatio * 100).rounded()) == 24)
        #expect(!draft.requiresConfirmation && draft.isImportable)
    }

    /// 위와 같이 T25(3,200자)가 본문 상한으로 하나 더 — 검증자 수용 30·건너뜀 3·9% → 29·4·12%
    @Test("구글 시트 CSV — BOM 없음(확인 화면)·셀 안 LF, 데이터 33 · 수용 29 · 건너뜀 4(12%, T25 포함) · 중복 1")
    func googleSheetsCSV() throws {
        let draft = try ImportHelper.draft(data: ImportHelper.fixture("gsheets-csv"))
        #expect(draft.encoding == .utf8 && !draft.hadBOM && draft.needsEncodingConfirmation)
        #expect(draft.delimiter == .comma && draft.mode == .numbered)
        #expect(draft.meta.templateSpecs == ["사자성어 {n}번", "성어 {n}번"])
        #expect(draft.dataRecordCount == 33)
        #expect(draft.acceptedRecordCount == 29)
        #expect(draft.skipped.count == 4)
        #expect(ImportHelper.reasons(draft).filter { $0 == .bodyTooLong }.count == 1)
        #expect(draft.duplicateCount == 1)
        #expect(draft.items.count == 28)
        #expect(draft.items.first { $0.n == 4 }?.body.contains("\n") == true, "셀 안 줄바꿈 보존")
        #expect(Int((draft.skippedRatio * 100).rounded()) == 12)
    }

    @Test("고정 번호형 샘플 원본 — 20개 전부 수용, 메타 셋")
    func sampleNumbered() throws {
        let draft = try ImportHelper.draft(data: ImportHelper.fixture("sample-numbered.original"))
        #expect(draft.mode == .numbered && draft.items.count == 20 && draft.skipped.isEmpty)
        #expect(draft.meta.name == "사자성어 예시 팩")
        #expect(draft.meta.templateSpecs == ["사자성어 {n}번", "성어 {n}번"])
        #expect(draft.meta.license == "글쇠 고정 샘플 — 자체 작성 문구(가짜 내용)")
    }

    @Test("고정 문구형 샘플 원본 — 15개 전부 수용, 「회의시작,회의 시작」은 정규화로 하나")
    func samplePhrases() throws {
        let draft = try ImportHelper.draft(data: ImportHelper.fixture("sample-phrases.original"))
        #expect(draft.mode == .phrases && draft.entries.count == 15 && draft.skipped.isEmpty)
        #expect(draft.entries.first?.triggers == ["회의시작"])
        #expect(draft.entries[2].triggers == ["감사", "감사인사"])
        #expect(draft.entries[1].body == "안녕하세요.\n다음 주 중 편하신 시간을 알려 주시면 일정을 맞춰 보겠습니다.\n감사합니다.")
    }

    @Test("인코딩을 바꾸면 원본 바이트에서 전부 다시 — UTF-8 샘플을 CP949로 고르면 BOM 불일치로 거부 (AC-18)")
    func manualEncodingOnRealFile() throws {
        let data = try ImportHelper.fixture("sample-numbered.original")
        #expect(throws: PackImportFailure.encodingDoesNotMatchBOM) {
            try PackImporter.read(data, options: PackImportOptions(encoding: .cp949))
        }
        let google = try ImportHelper.fixture("gsheets-csv")
        #expect(throws: PackImportFailure.undecodable(.cp949)) {
            try PackImporter.read(google, options: PackImportOptions(encoding: .cp949))
        }
    }

    @Test("합성 CP949 번호형 파일(실물 교체 대기) — 엄격 CP949로 읽혀 같은 파이프라인을 탄다")
    func syntheticCP949() throws {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.dosKorean.rawValue)))
        let text = "#이름,사자성어 예시 팩\r\n#틀,사자성어 {n}번\r\n#권리,자체 작성\r\n번호,제목,본문\r\n1,일석이조,한 가지 일로 두 가지 이익\r\n2,고진감래,\"쓴 것이 다하면\n단 것이 온다\"\r\n"
        let draft = try ImportHelper.draft(data: try #require(text.data(using: encoding)))
        #expect(draft.encoding == .cp949 && draft.needsEncodingConfirmation)
        #expect(draft.items.map(\.n) == [1, 2])
        #expect(draft.items[1].body == "쓴 것이 다하면\n단 것이 온다")
    }
}

/// 검증(`docs/release/verify-ext-1a.md`) F2·F3 — 5-2 #2 규칙(앞 데이터 5개 중 절반 이상)은 그대로, 실패 보고와 시험 창만 고친다
@Suite("구분자 시험 보강 (5-2, F2 · F3)")
struct DelimiterTrialFollowUpTests {

    /// F2 — 머리글은 멀쩡한데 「머리글을 확인하세요」로 거부되던 경우. 위치는 시험 창 안의 첫 불일치 데이터 레코드
    @Test("머리글은 인정됐는데 앞 데이터 과반의 열 수가 틀리면 열 수 불일치로 거부 — 머리글 오류가 아니다 (F2)")
    func columnCountMismatchIsNotHeaderError() {
        let text = "번호,제목,본문\r\n1,가\r\n2,나\r\n3,다\r\n4,라,본문\r\n5,마,본문\r\n6,바,본문"
        #expect(throws: PackImportFailure.columnCountMismatch(record: 2, line: 2)) { try PackImporter.read(text: text) }
    }

    @Test("열 수 불일치 위치는 메타·빈 레코드를 포함한 파일 기준 번호")
    func columnCountMismatchPosition() {
        let text = "#이름,예시\r\n\r\n번호,제목,본문\r\n1,\"여러\n줄\",본문\r\n2,가\r\n3,나\r\n4,다\r\n5,라,본문"
        #expect(throws: PackImportFailure.columnCountMismatch(record: 5, line: 6)) { try PackImporter.read(text: text) }
    }

    @Test("앞 데이터 5개 중 2개만 틀리면 채택하고 그 행만 건너뛴다 — 규칙 자체는 그대로")
    func minorityMismatchStillAdopted() throws {
        let draft = try ImportHelper.draft("번호,제목,본문\r\n1,가\r\n2,나\r\n3,다,본문\r\n4,라,본문\r\n5,마,본문")
        #expect(draft.items.map(\.n) == [3, 4, 5])
        #expect(ImportHelper.reasons(draft) == [.columnCount, .columnCount])
    }

    /// F3 — 시험 창 32는 **비지 않은** 레코드로 센다(본 파싱은 빈 레코드를 어디서든 무시한다)
    @Test("머리글 앞 빈 레코드·빈 줄이 32개를 넘어도 시험 창을 다 쓰지 않는다 (F3)", arguments: [",,\r\n", "\r\n", ",,,,\n"])
    func blankRecordsDoNotFillTrialWindow(blank: String) throws {
        let text = String(repeating: blank, count: 40) + "번호,본문\r\n1,가\r\nx,나"
        let draft = try ImportHelper.draft(text)
        #expect(draft.items.map(\.n) == [1])
        #expect(draft.skipped == [SkippedRecord(record: 43, line: 43, reason: .invalidNumber)])
    }

    @Test("비지 않은 레코드가 32개를 넘은 뒤의 quote 오류는 여전히 본 파싱의 전체 거부 — 빈 레코드가 섞여도 같다")
    func trialWindowCountsNonBlankOnly() {
        var lines = ["단축어,본문"]
        for index in 1...39 { lines.append("문구\(index),본문\(index)"); lines.append(",") }
        lines.append("문구40,\"닫은 뒤\"글자")
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 80, line: 80))) {
            try PackImporter.read(text: lines.joined(separator: "\r\n"))
        }
    }
}

/// 검증 F4·F5 — 빈 파일은 구분자 판정 앞에서, 붙여넣기도 파일과 같은 바이트 상한을 파싱 전에
@Suite("빈 파일·크기 상한 (F4 · F5 · T6)")
struct EmptyAndSizeTests {

    @Test("내용 없는 파일은 머리글 오류가 아니라 빈 파일 — 빈 데이터·BOM만·빈 줄만·구분자만 (F4 · T6)", arguments: [
        [UInt8](), [0xEF, 0xBB, 0xBF], Array("\r\n\n\r".utf8), Array(",,,\r\n,,,".utf8), Array(";\t,\n".utf8),
        [0xFF, 0xFE, 0x2C, 0x00, 0x0A, 0x00]
    ])
    func emptyFile(data: [UInt8]) {
        #expect(throws: PackImportFailure.emptyFile) { try PackImporter.read(Data(data)) }
    }

    @Test("붙여넣기·구분자를 고른 경우도 같다")
    func emptyPasteAndChosenDelimiter() {
        #expect(throws: PackImportFailure.emptyFile) { try PackImporter.read(text: "") }
        #expect(throws: PackImportFailure.emptyFile) { try PackImporter.read(text: "\n,,\n", delimiter: .semicolon) }
        #expect(throws: PackImportFailure.emptyFile) { try PackImporter.read(text: "\"\",\"\"", delimiter: .comma) }
    }

    @Test("공백 글자만 든 파일은 빈 파일이 아니다 — 공백 셀은 빈 셀이 아니다(5-4 명확화 ②)")
    func whitespaceIsNotEmpty() {
        #expect(throws: PackImportFailure.headerNotRecognized) { try PackImporter.read(text: "  \r\n ") }
    }

    /// F5 — 같은 내용 파일은 `fileTooLarge`인데 붙여넣기는 끝까지 파싱했다(12MB 4.95초)
    @Test("붙여넣기도 UTF-8 바이트 상한(3,000,000)을 파싱 전에 본다 — 글자 수가 아니라 바이트 (F5)")
    func pasteByteCap() {
        #expect(throws: PackImportFailure.fileTooLarge) { try PackImporter.read(text: String(repeating: ",", count: 3_000_001)) }
        #expect(throws: PackImportFailure.fileTooLarge) { try PackImporter.read(text: String(repeating: "가", count: 1_000_001)) }
        #expect(throws: PackImportFailure.fileTooLarge) {
            try PackImporter.read(text: String(repeating: ",", count: 3_000_001), delimiter: .comma)
        }
        // 경계 — 3,000,000바이트는 상한을 넘지 않는다(내용이 없어 빈 파일)
        #expect(throws: PackImportFailure.emptyFile) { try PackImporter.read(text: String(repeating: ",", count: 3_000_000)) }
    }
}

/// 검증 T5 — 파서 수준에만 있던 「닫히지 않은 따옴표」·물리 줄 cap을 가져오기 수준에서. ⑪ cap 사유 코드도 여기서 고정
@Suite("가져오기 수준 구조 오류 (AC-13 · AC-16 · ⑪, T5)")
struct ImportStructuralErrorTests {

    @Test("모든 후보에서 셀 시작 따옴표가 안 닫히면 「따옴표 오류」(닫히지 않음) (AC-13)")
    func unterminatedInEveryCandidate() {
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .unterminated, record: 3, line: 3))) {
            try PackImporter.read(text: "번호,본문\r\n1,가\r\n\"닫히지 않음\r\n2,나")
        }
    }

    @Test("시험 창 뒤에서 안 닫힌 따옴표는 본 파싱의 전체 거부 (AC-13)")
    func unterminatedAfterTrialWindow() {
        var lines = ["번호,본문"]
        for index in 1...40 { lines.append("\(index),본문\(index)") }
        lines.append("41,\"열고 안 닫음")
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .unterminated, record: 42, line: 42))) {
            try PackImporter.read(text: lines.joined(separator: "\r\n"))
        }
    }

    @Test("물리 줄 50,000 초과는 `tooManyLines`, 그 안이면 데이터 레코드 cap으로 `tooManyRecords` (AC-16 · ⑪)")
    func lineCapThenRecordCap() {
        let header = "번호,본문\r\n"
        #expect(throws: PackImportFailure.tooManyLines) {
            try PackImporter.read(text: header + String(repeating: "1,가\r\n", count: 50_000))
        }
        #expect(throws: PackImportFailure.tooManyRecords) {
            try PackImporter.read(text: header + String(repeating: "1,가\r\n", count: 49_999))
        }
    }

    @Test("머리글 실효 폭 8 초과는 `tooManyColumns` — trailing 빈 칸은 세지 않는다 (⑪)")
    func columnCap() throws {
        #expect(throws: PackImportFailure.tooManyColumns) { try PackImporter.read(text: "번호,본문,a,b,c,d,e,f,g\r\n1,x,,,,,,,") }
        let padded = try ImportHelper.draft("번호,본문,a,b,c,d,e,f,,\r\n1,x,,,,,,,,")
        #expect(padded.items.map(\.n) == [1] && padded.ignoredColumnCount == 6)
    }
}

/// 검증 T3·F8 — 수동 인코딩 선택이 디코더뿐 아니라 **가져오기 끝(본문)까지** 결과를 바꾸는지
@Suite("수동 인코딩 — 가져오기 끝까지 (AC-18, T3 · F8)")
struct ManualEncodingImportTests {

    /// `C3 A9` = UTF-8 「é」 = CP949 「챕」. API가 상태 없음이라 선택마다 원본 바이트에서 전부 다시 읽는다
    @Test("같은 바이트가 자동·UTF-8이면 본문 é, CP949면 챕 (AC-18 · T3)")
    func sameBytesDifferentBodies() throws {
        let data = Data("n,body\n1,caf".utf8) + Data([0xC3, 0xA9]) + Data("\n".utf8)
        for choice in [PackEncodingChoice.automatic, .utf8] {
            let draft = try ImportHelper.draft(data: data, options: PackImportOptions(encoding: choice))
            #expect(draft.encoding == .utf8 && draft.needsEncodingConfirmation)
            #expect(draft.items.map(\.body) == ["caf\u{E9}"])
        }
        let korean = try ImportHelper.draft(data: data, options: PackImportOptions(encoding: .cp949))
        #expect(korean.encoding == .cp949 && korean.needsEncodingConfirmation)
        #expect(korean.items.map(\.body) == ["caf\u{CC55}"])
    }

    @Test("BOM이 두 번 붙은 UTF-8 파일도 머리글을 찾는다 (F8)")
    func doubleBOMImport() throws {
        let draft = try ImportHelper.draft(data: Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + Data("번호,본문\r\n1,가".utf8))
        #expect(draft.hadBOM && draft.items.map(\.n) == [1])
    }
}
