import Foundation
import TadakDomain

public struct PackImportOptions: Equatable, Sendable {
    /// 확인 화면에서 고른 인코딩 — 바꾸면 원본 바이트에서 전부 다시(5-1·AC-18)
    public var encoding: PackEncodingChoice
    /// 사용자가 고른 구분자(후보가 2개 이상일 때 또는 수동 변경) — nil이면 후보 검증(5-2)
    public var delimiter: CSVDelimiter?
    /// (xlsx) 고른 시트 — 표시 시트 목록(`XLSXWorkbookReader.sheets`, 워크북 순서)의 자리. nil이면 표시 시트가 하나일 때 그 시트,
    /// 둘 이상이면 고르기(AC-36). CSV는 보지 않는다
    public var sheet: Int?

    public init(encoding: PackEncodingChoice = .automatic, delimiter: CSVDelimiter? = nil, sheet: Int? = nil) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.sheet = sheet
    }
}

/// 행 하나만 건너뛰는 사유(5-5 — 구조 오류가 아니다). 미리보기는 「건너뛴 행 N건」을 **행 번호와 사유만** 보인다
public enum SkipReason: Equatable, Sendable {
    /// 열 수가 머리글과 다르다(빈 셀로 채우지 않는다)
    case columnCount
    /// 번호 칸이 비었다 — 서식 있는 붙여넣기로 쪼개진 `,,둘째 줄,`도 여기다
    case missingNumber
    /// 번호 형식 — `^[0-9]{1,4}(\.0+)?$`(전각은 NFKC 뒤) 아님
    case invalidNumber
    /// 번호 0 — 1~9,999 밖
    case numberOutOfRange
    /// 단축어가 비었다(문구형)
    case missingTrigger
    /// 단축어 10개 초과
    case tooManyTriggers
    /// 단축어 하나가 40자 초과
    case triggerTooLong
    /// 본문이 비었거나 공백만
    case emptyBody
    /// 제목 60자 초과
    case titleTooLong
    /// 본문 3,000자 초과(잠정 — P-8)
    case bodyTooLong
    // 6-4 — xlsx 칸이 원문이 아니다(1-e ③). 한 행에 여럿이면 이 순서의 첫 것: 수식 → 날짜 서식 → 불리언·오류 → 숫자 → 병합.
    // 이 다섯은 위의 검사(열 수·번호·단축어·본문)보다 먼저 본다 — 칸 값을 믿을 수 없는 행이라 그 값으로 한 판정이 틀린다. CSV는 내지 않는다
    /// 수식 칸(`<f>`·`t="str"`) — 캐시 값은 원문이 아니다
    case formula
    /// 날짜·시간 서식의 숫자 칸 — 원문이 이미 사라졌다
    case dateFormat
    /// 불리언(`TRUE`)·오류(`#N/A`) 칸
    case booleanOrError
    /// 번호 열 밖의 숫자 칸(R19 — 단축어·제목·본문·모르는 열) — `=2+3`→5·`007`→7처럼 원문과 다를 수 있다
    case numberCell
    /// 병합 범위와 겹치는 행(선두·비선두 모두)
    case merged
}

/// 건너뛴 행·구조 오류가 가리키는 자리 — **번호만**(AC-34)
public enum PackRecordPosition: Equatable, Sendable {
    /// CSV 논리 레코드 n(1부터, 파일 전체 기준 — 빈 레코드 포함)과 그 레코드가 시작한 물리 줄 m — 「n번째 항목(m번째 줄)」
    case record(Int, line: Int)
    /// xlsx 시트 행 번호(사용자가 엑셀에서 보는 번호) — 「n번째 행」
    case row(Int)

    /// 레코드 번호 — xlsx는 시트 행 번호
    public var record: Int {
        switch self {
        case .record(let record, _): record
        case .row(let row): row
        }
    }

    /// 레코드가 시작한 물리 줄 — xlsx는 시트 행 번호(구조 오류 코드의 `line` 자리)
    public var line: Int {
        switch self {
        case .record(_, let line): line
        case .row(let row): row
        }
    }
}

public struct SkippedRecord: Equatable, Sendable {
    public var position: PackRecordPosition
    public var reason: SkipReason

    /// CSV — 논리 레코드 번호(1부터, 파일 전체 기준)와 그 레코드가 시작한 물리 줄
    public init(record: Int, line: Int, reason: SkipReason) {
        self.init(position: .record(record, line: line), reason: reason)
    }

    /// xlsx — 시트 행 번호
    public init(row: Int, reason: SkipReason) {
        self.init(position: .row(row), reason: reason)
    }

    init(position: PackRecordPosition, reason: SkipReason) {
        self.position = position
        self.reason = reason
    }

    /// 논리 레코드 번호 — xlsx는 시트 행 번호
    public var record: Int { position.record }
    /// 물리 줄 — xlsx는 시트 행 번호
    public var line: Int { position.line }
}

/// 메타 값이 상한을 넘어 미리 채우지 않은 칸 — 폼이 최종 권위라 거부하지 않는다(5-6)
public enum MetaIssue: Equatable, Sendable {
    case nameTooLong
    case licenseTooLong
}

/// 머리글 위 정보 줄(`#` 메타, 5-3)의 칸 — 키 글자는 `field(forKey:)` **한 곳**에서 읽는다(파서·글자 확인 표본이 같이 쓴다).
/// 출처 칸의 키는 `#출처`이고 옛 `#권리`도 같은 칸이다(R27 — 이미 받은 샘플·옛 파일 호환). 둘이 함께 있으면 같은 칸이 두 번이라 중복 메타다
/// (`duplicateSourceMeta` — 문구가 두 키를 함께 말한다).
/// 코드 식별자는 `license` 그대로다(보이는 글자만 「출처」 — 글쇠·단축어 원칙과 같다)
public enum PackMetaField: Hashable, Sendable, CaseIterable {
    /// `#이름`
    case name
    /// `#틀` — 값 1~8개(별칭)
    case template
    /// `#출처`(옛 `#권리`)
    case license

    static let keys: [String: PackMetaField] = ["#이름": .name, "#틀": .template, "#출처": .license, "#권리": .license]

    /// 앞뒤 공백을 뗀 첫 칸이 정보 줄 키면 그 칸. `#escape`·모르는 `#` 키는 nil
    public static func field(forKey key: String) -> PackMetaField? { keys[key] }
}

/// `#` 메타의 **미리 채움**(5-6 — 폼이 최종 권위, 파일명은 쓰지 않는다)
public struct PackMetaPrefill: Equatable, Sendable {
    public var name: String?
    /// 제작자가 준 출처 문구(`#출처`·옛 `#권리`) — 선택지로 덮지 않고 원문 그대로 보이고, 폼이 처음부터 고른다(R28, 길이 제한 안에서)
    public var license: String?
    /// `#틀` 원문 값(1~8) — 검사는 `TemplatePatternSpec`·`PackCompiler`
    public var templateSpecs: [String]
    public var issues: [MetaIssue]
}

/// 가져오기 미리보기용 초안 — 메모리에만 있다(로그·파일·네트워크 금지). 최종 팩은 `PackCompiler`가 폼 값으로 만든다
public struct PackDraft: Equatable, Sendable {
    /// 붙여넣기는 nil(인코딩 단계 없음)
    public var encoding: PackTextEncoding?
    public var hadBOM: Bool
    /// R18 — BOM 없는 비ASCII 파일
    public var needsEncodingConfirmation: Bool
    /// 읽은 구분자 — xlsx는 nil(칸 나누기가 없다)
    public var delimiter: CSVDelimiter?
    /// 자동 판정(5-2)이 채택한 구분자 — 구분자를 골라 읽었어도 같은 원본의 판정이다. **둘 이상일 때만** 미리보기가 「칸 나누기」를 보인다(R29). xlsx는 빈 배열
    public var delimiterCandidates: [CSVDelimiter]
    /// (xlsx) 읽은 시트의 이름 — 화면과 팩 이름 기본값(`suggestedPackName`)에만 쓴다. 로그·분석·오류 값에 싣지 않는다(6-4·AC-34). CSV는 nil
    public var sheetName: String?
    /// (xlsx) 받은 행 가운데 숨긴 행 수 — 미리보기 「숨긴 행 N개도 가져와요」(6-4: 읽되 알린다). CSV는 0
    public var hiddenRowCount: Int
    /// (xlsx) 가져오는 열(번호·단축어·제목·본문) 가운데 숨긴 열 수 — 「숨긴 열 N개도 가져와요」. CSV는 0
    public var hiddenColumnCount: Int
    public var mode: ExternalPack.Mode
    public var meta: PackMetaPrefill
    /// 문구형 항목(정규화 기준 같은 단축어는 뒤 항목이 이긴 결과)
    public var entries: [SnippetEntry]
    /// 번호형 항목(같은 번호는 뒤가 이긴 결과, 번호 오름차순)
    public var items: [PackTemplateItem]
    public var skipped: [SkippedRecord]
    /// R10 분모 — 데이터 논리 레코드(머리글·메타·빈 레코드 제외)
    public var dataRecordCount: Int
    /// 건너뛰지 않은 데이터 레코드(중복으로 덮인 것 포함)
    public var acceptedRecordCount: Int
    /// 뒤 레코드가 덮은 번호·단축어 수(「중복 N건」)
    public var duplicateCount: Int
    /// 머리글의 모르는 열(「무시한 열 N개」)
    public var ignoredColumnCount: Int
    /// 문자 정리로 뺀 글자 수(「정리 N건」, 11절)
    public var sanitizedCharacterCount: Int
    /// 따옴표 없는 셀 중간의 `"` 수
    public var strayQuoteCount: Int

    public var skippedRatio: Double { dataRecordCount == 0 ? 0 : Double(skipped.count) / Double(dataRecordCount) }
    /// 건너뜀 ≥ 50% — 자동 진행 금지, 사용자가 명시적으로 확인하면 부분 가져오기(R10)
    public var requiresConfirmation: Bool { skippedRatio >= PackLimits.skipRatioRequiringConfirmation }
    /// 유효 레코드 0이면 영구 비활성(5-5)
    public var isImportable: Bool { acceptedRecordCount > 0 }

    /// 팩 이름 칸의 기본값 후보 — (xlsx) 시트 이름. 앱이 붙인 이름(`Sheet1`·`시트1`)·빈 이름은 nil(6-4 P-10 보강), 문자 정리(11절) 뒤
    /// 이름 상한(`PackLimits.name`)을 넘으면 nil(메타 값과 같은 규칙 — 거부하지 않고 채우지 않는다, 5-6). `#이름`이 있으면 폼은 그쪽을 쓴다
    public var suggestedPackName: String? {
        guard let sheetName, let suggested = XLSXWorkbookReader.Sheet.suggestedPackName(forSheetName: sheetName) else { return nil }
        let name = PackTextSanitizer.sanitize(suggested).text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && PackLimits.name.admits(name) ? name : nil
    }
}

public enum PackImportOutcome: Equatable, Sendable {
    case draft(PackDraft)
    /// 채택 후보가 2개 이상 — 사용자가 고르면 `PackImportOptions.delimiter`로 다시 부른다(5-2 #3)
    case chooseDelimiter([CSVDelimiter])
}

/// (xlsx) 시트 고르기 화면의 한 줄(4-D) — 이름은 화면에만(로그·분석·오류 값에 싣지 않는다, AC-34)
public struct PackSheetSummary: Equatable, Sendable {
    /// 시트 이름(`_xHHHH_`를 푼 것)
    public let name: String
    /// 대략의 행 수 — 비지 않은 행(정보 줄·머리글 포함). 목록을 만들 때 읽지 못한 시트는 nil(고르면 그때 거부된다)
    public let rowCount: Int?

    public init(name: String, rowCount: Int?) {
        self.name = name
        self.rowCount = rowCount
    }
}

public enum PackWorkbookOutcome: Equatable, Sendable {
    case draft(PackDraft)
    /// 표시 시트가 둘 이상이고 아직 고르지 않았다 — 사용자가 고르면 `PackImportOptions.sheet`로 다시 부른다(AC-36)
    case chooseSheet([PackSheetSummary])
}

/// CSV(`.csv`·`.tsv`·`.txt`·붙여넣기) 가져오기 파이프라인(PDR `external-snippet-packs.md` 5절):
/// ① 제한 읽기 → ② 인코딩 → ③ 구분자 후보 → ④ 논리 레코드 → ⑤ 헤더·메타 → ⑥ 행별 검증 → ⑦ 정리 후 재검사.
/// 선택(인코딩·구분자)이 바뀌면 **원본 바이트에서 ②부터 전부 다시** 한다 — 이전 결과를 재사용하지 않는다(상태 없음).
///
/// 구조 오류(인코딩·quote·머리글·메타 위치)는 비율과 무관하게 **전체 거부**(throw), 행 오류는 **그 행만 건너뜀**.
public enum PackImporter {

    /// 후보 시험에 쓰는 「첫 논리 레코드들」 — **비지 않은** 레코드로 센다(메타 3·머리글·데이터 몇 개가 넉넉히 든다).
    /// 빈 레코드는 본 파싱이 어디서든 무시하므로 시험 창도 차지하지 않는다(검증 F3)
    static let trialRecords = 32
    /// 후보 채택에 보는 데이터 레코드 수 — 이 안의 열 수가 머리글과 맞아야 한다
    static let trialDataRecords = 5

    public static func read(_ data: Data, options: PackImportOptions = PackImportOptions()) throws(PackImportFailure) -> PackImportOutcome {
        let decoded = try PackTextDecoder.decode(data, choice: options.encoding)
        return try read(decoded.text, delimiter: options.delimiter, encoding: decoded)
    }

    /// 붙여넣기 — 인코딩 단계가 없다. 바이트 상한은 파일과 같다(UTF-8 길이, 파싱 전 — 4절 「제한 읽기」, 검증 F5)
    public static func read(text: String, delimiter: CSVDelimiter? = nil) throws(PackImportFailure) -> PackImportOutcome {
        guard text.utf8.count <= PackLimits.fileBytes else { throw .fileTooLarge }
        return try read(text, delimiter: delimiter, encoding: nil)
    }

    private static func read(_ text: String, delimiter chosen: CSVDelimiter?, encoding: DecodedPackText?) throws(PackImportFailure) -> PackImportOutcome {
        // 구분자 판정 앞 — 구분자·줄바꿈뿐이면 어느 구분자로 읽어도 비지 않은 레코드가 없다(검증 F4)
        guard !containsOnlySeparators(text) else { throw .emptyFile }
        let delimiter: CSVDelimiter
        let candidates: [CSVDelimiter]
        if let chosen {
            delimiter = chosen
            // 고른 구분자로 읽어도 자동 판정은 같은 원본에서 다시 한다(R29 — 미리보기가 고르기를 보일지). 판정이 실패해도 고른 것으로 읽는다
            candidates = (try? adoptDelimiters(text)) ?? []
        } else {
            let adopted = try adoptDelimiters(text)
            guard adopted.count == 1, let only = adopted.first else { return .chooseDelimiter(adopted) }
            delimiter = only
            candidates = adopted
        }
        // 본 파싱 — 여기서 난 quote 오류는 전체 거부(5-4 명확화 ①)
        let parsed: CSVParseResult
        do {
            parsed = try CSVRecordParser.parse(text, delimiter: delimiter)
        } catch {
            switch error {
            case .quote(let quote): throw .quote(quote)
            case .tooManyLines: throw .tooManyLines
            }
        }
        guard parsed.records.contains(where: { !$0.isBlank }) else { throw .emptyFile }
        let records = parsed.records.enumerated().map { PackRecord(csv: $1, number: $0 + 1) }
        var draft = try PackRecordReader.read(records, delimiter: delimiter)
        draft.delimiterCandidates = candidates
        draft.encoding = encoding?.encoding
        draft.hadBOM = encoding?.hadBOM ?? false
        draft.needsEncodingConfirmation = encoding?.needsConfirmation ?? false
        draft.strayQuoteCount = parsed.strayQuoteCount
        return .draft(draft)
    }

    /// 5-2 — 후보마다 첫 논리 레코드들을 시험 파싱해 **머리글 인정 + 필수 열 유일 + 모드 일관 + 다음 데이터 레코드 열 수 일치**를
    /// 보는 후보를 고른다. 시험 중 quote 오류는 **그 후보만 탈락**(명확화 ①) — 시험 결과는 버리므로 데이터가 새지 않는다.
    ///
    /// 채택 0일 때 보고: 머리글을 인정한 후보의 실패(규칙 위반·열 수 불일치·**머리글 뒤 데이터 행의 quote 오류**)가 있으면 후보 순서의
    /// 첫 것 → 모든 후보가 quote 오류면 첫 quote 오류 → 그 밖은 머리글 오류. quote 오류 앞까지 머리글이 인정된 후보는 그 구분자를
    /// 지정했을 때와 같은 quote 오류를 낸다(재검증 N1 — 예전엔 `;`·탭이 「머리글 없음」이라 머리글 오류로 나갔다). 채택 규칙은 그대로다.
    private static func adoptDelimiters(_ text: String) throws(PackImportFailure) -> [CSVDelimiter] {
        var adopted: [CSVDelimiter] = []
        var quoteErrors: [CSVQuoteError] = []
        var headerFailure: PackImportFailure?
        for candidate in CSVDelimiter.allCases {
            let trial = CSVRecordParser.scan(text, delimiter: candidate, maxNonBlankRecords: trialRecords)
            switch trial.failure {
            case .tooManyLines?:
                throw .tooManyLines
            case .quote(let quote)?:
                quoteErrors.append(quote)
                // 오류 앞까지의 레코드로 머리글을 인정했다면 이 후보의 실패는 데이터 행의 quote 오류다
                if headerFailure == nil, PackRecordReader.trialVerdict(trial.result.records) != .noHeader {
                    headerFailure = .quote(quote)
                }
            case nil:
                switch PackRecordReader.trialVerdict(trial.result.records) {
                case .adopted: adopted.append(candidate)
                case .rejected(let failure): if headerFailure == nil { headerFailure = failure }
                case .noHeader: break
                }
            }
        }
        if !adopted.isEmpty { return adopted }
        if let headerFailure { throw headerFailure }
        // 모든 후보가 quote 오류로 탈락 → 「따옴표 오류」를 우선(구조 오류, 5-2 #3)
        if quoteErrors.count == CSVDelimiter.allCases.count, let first = quoteErrors.first { throw .quote(first) }
        throw .headerNotRecognized
    }

    /// 붙여넣기 화면의 「칸 나누기: 탭」(시안 3-E) — 같은 후보 시험(5-2)으로 **하나로 정해질 때만** 그 구분자. 앞 레코드(시험 창)만 본다.
    /// 보여 주기용이다 — 실제 읽기는 「읽기」를 누른 뒤 `read(text:)`가 처음부터 다시 판정한다
    public static func likelyDelimiter(_ text: String) -> CSVDelimiter? {
        guard !containsOnlySeparators(text), let adopted = try? adoptDelimiters(text), adopted.count == 1 else { return nil }
        return adopted.first
    }

    /// 빈 텍스트이거나 구분자 후보(`,`·`;`·탭)와 줄바꿈만 있다 — 공백 글자는 내용이다(빈 셀이 아니다, 5-4 명확화 ②)
    private static func containsOnlySeparators(_ text: String) -> Bool {
        text.utf8.allSatisfy { byte in
            switch byte {
            case UInt8(ascii: ","), UInt8(ascii: ";"), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"): true
            default: false
            }
        }
    }

    // MARK: - xlsx (1-e ③)

    /// 원본 판별 — xlsx 쪽 매직이면 참: ZIP 로컬 헤더 `PK\3\4`·빈 ZIP `PK\5\6`·OLE2 복합 문서(비밀번호 걸린 엑셀·옛 `.xls` — 컨테이너가
    /// 알맞은 사유로 거부한다). 참이면 인코딩·구분자 단계를 건너뛴다(6-1). BOM으로 시작하는 글은 CSV다
    public static func isWorkbook(_ data: Data) -> Bool {
        let signatures: [[UInt8]] = [[0x50, 0x4B, 0x03, 0x04], [0x50, 0x4B, 0x05, 0x06], [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]]
        return signatures.contains { data.starts(with: $0) }
    }

    /// xlsx 파이프라인 — 컨테이너·XML(1-e ①②) → 시트 하나의 `RawTable` → **CSV와 같은** 헤더·메타 판정 → 행별 검증(`PackRecordReader`, AC-32).
    /// 표시 시트가 둘 이상인데 `sheet`가 nil이면 고르기 목록을 돌려준다(AC-36 — 기본은 첫 표시 시트, 목록의 0번).
    /// 상태가 없다 — 시트를 고르면 원본 바이트에서 다시 연다(5-1과 같은 원칙). 실패는 내용 없는 코드다(AC-34)
    public static func readWorkbook(_ data: Data, sheet: Int?) throws(PackImportFailure) -> PackWorkbookOutcome {
        var reader: XLSXWorkbookReader
        do {
            reader = try XLSXWorkbookReader.open(data)
        } catch {
            throw .workbook(error)
        }
        guard let index = sheet ?? (reader.sheets.count == 1 ? 0 : nil) else {
            return .chooseSheet(sheetSummaries(&reader))
        }
        guard reader.sheets.indices.contains(index) else { throw .workbook(.sheetNotFound) }
        let chosen = reader.sheets[index]
        let table: RawTable
        do {
            table = try reader.table(for: chosen)
        } catch {
            throw .workbook(error)
        }
        var draft = try PackRecordReader.read(table)
        draft.sheetName = displayName(chosen.name)
        return .draft(draft)
    }

    /// 시트 고르기 목록 — 표시 시트마다 대략의 행 수. 한 독자의 해제 총량(①)을 나눠 쓰므로 큰 시트 뒤의 시트는 총량에 걸릴 수 있다 —
    /// 그 시트(와 읽지 못한 시트)는 행 수 없이 보이고, 고르면 새로 연 독자가 다시 읽는다(②-6 12번)
    private static func sheetSummaries(_ reader: inout XLSXWorkbookReader) -> [PackSheetSummary] {
        reader.sheets.map { sheet in
            PackSheetSummary(name: displayName(sheet.name), rowCount: try? reader.table(for: sheet).rows.count)
        }
    }

    /// 화면에 그릴 시트 이름 — `_xHHHH_`로 들어온 제어·방향 재정의·제로폭 문자를 문자 정리(11절)로 뺀다(보안 검토 S7 — 표시 위장).
    /// 길이는 ②의 시트 이름 상한(255B)에 묶여 있다
    static func displayName(_ name: String) -> String {
        PackTextSanitizer.sanitize(name).text
    }
}

/// 판정 경로에 들어가는 레코드 하나 — CSV 논리 레코드와 xlsx 시트 행이 **같은 모양**으로 들어온다(6-1·AC-32).
/// 판정(`PackRecordReader`)은 이 값만 보고 원본 형식을 묻지 않는다 — xlsx 행이 더 가진 것은 칸 종류(6-4)·병합·숨김뿐이고, CSV에서는 비어 있다
struct PackRecord: Equatable {

    /// 칸 하나가 원문이 아닌 사정 — 판정이 그 행을 건너뛸지(6-4) 본다. 글·빈 칸은 `.text`
    enum CellKind: Equatable {
        case text
        /// 숫자 칸 — `cells`에는 `<v>` 글자 그대로(번호 열이면 받는다, R19)
        case number
        case unsupported(UnsupportedCellKind)
    }

    /// 칸 글 — **trim하지 않는다**. CSV는 셀 그대로, xlsx는 글·숫자 글자 그대로이고 빈 칸·원문이 아닌 칸은 빈 글
    var cells: [String]
    /// 칸 종류(`cells`와 같은 자리) — CSV는 빈 배열(모든 칸이 글)
    var kinds: [CellKind]
    var position: PackRecordPosition
    var isMerged: Bool
    var isHidden: Bool

    /// CSV 논리 레코드 — 번호는 파일 전체 기준(빈 레코드 포함, 1부터)
    init(csv record: CSVRecord, number: Int) {
        cells = record.cells
        kinds = []
        position = .record(number, line: record.line)
        isMerged = false
        isHidden = false
    }

    /// xlsx 시트 행 — **`RawTable.columnLimit` 칸까지 빈 칸으로 채운다.** xlsx는 빈 칸을 저장하지 않을 뿐 행에는 모든 열이 있다 —
    /// 끝 빈 칸이 모자라다고 「열 수」로 건너뛰면 안 된다(스프레드시트가 저장한 CSV도 표 폭까지 채운다, 5-3). 넘침 칸(13번째)에 글이 있으면
    /// 메타는 칸 상한, 데이터는 「열 수」로 CSV와 같은 결과가 난다(②-6 2번)
    init(row: RawRow) {
        var cells: [String] = []
        var kinds: [CellKind] = []
        for cell in row.cells {
            switch cell {
            case .text(let text): cells.append(text); kinds.append(.text)
            case .number(let literal): cells.append(literal); kinds.append(.number)
            case .blank: cells.append(""); kinds.append(.text)
            case .unsupported(let kind): cells.append(""); kinds.append(.unsupported(kind))
            }
        }
        let padding = max(0, RawTable.columnLimit - cells.count)
        self.cells = cells + Array(repeating: "", count: padding)
        self.kinds = kinds + Array(repeating: .text, count: padding)
        position = .row(row.number)
        isMerged = row.isMerged
        isHidden = row.isHidden
    }

    /// 빈 레코드 — 모든 칸이 빈 글이고 원문이 아닌 칸도 없다(5-4 명확화 ②). xlsx 표는 빈 행을 담지 않는다
    var isBlank: Bool { cells.allSatisfy(\.isEmpty) && kinds.allSatisfy { $0 == .text } }

    /// 원문이 아닌 칸(수식·날짜·불리언·오류)이 있다
    var hasUnsupportedCell: Bool { kinds.contains { if case .unsupported = $0 { true } else { false } } }
}

/// 논리 레코드 → 헤더·메타 판정 → 행별 검증. **xlsx(1-e)도 `RawTable`을 같은 레코드 모양(`PackRecord`)으로 넘겨 이 경로를 탄다**(6-1·AC-32).
enum PackRecordReader {

    enum Field: Equatable { case number, trigger, title, body }

    /// v2 4-2 — 앞뒤 공백·대소문자 무시
    static let columnNames: [String: Field] = [
        "번호": .number, "n": .number, "no": .number, "number": .number,
        "단축어": .trigger, "trigger": .trigger, "triggers": .trigger,
        "제목": .title, "title": .title,
        "본문": .body, "내용": .body, "body": .body
    ]

    static let metaEscape = "#escape"
    /// 머리글 뒤에 오면 위치 오류인 키 — 칸 키 전부(옛 `#권리` 포함, `PackMetaField`)와 `#escape`
    static let reservedMetaKeys: Set<String> = Set(PackMetaField.keys.keys).union([metaEscape])

    struct Header: Equatable {
        var columns: [Field: Int]
        var width: Int
        var ignored: Int
        var mode: ExternalPack.Mode { columns[.number] != nil ? .numbered : .phrases }
    }

    enum HeaderResult: Equatable {
        case header(Header)
        /// 아는 열 이름이 하나도 없다 — 이 구분자로는 머리글이 아니다
        case unrecognized
        /// 아는 열 이름은 있는데 규칙 위반 — 그 사유로 전체 거부
        case invalid(PackImportFailure)
    }

    enum TrialVerdict: Equatable {
        case adopted
        case rejected(PackImportFailure)
        case noHeader
    }

    /// 머리글 실효 폭 — **trailing 빈 칸은 무시**(메타가 넓어 앱이 머리글까지 패딩한 경우, 5-3)
    static func effectiveCount(_ cells: [String]) -> Int {
        (cells.lastIndex { !$0.isEmpty } ?? -1) + 1
    }

    static func parseHeader(_ cells: [String]) -> HeaderResult {
        let width = effectiveCount(cells)
        let names = cells.prefix(width).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var columns: [Field: Int] = [:]
        var seenNames = Set<String>()
        var duplicateName = false
        var duplicateAlias = false
        var ignored = 0
        for (index, name) in names.enumerated() {
            guard let field = columnNames[name] else {
                if !name.isEmpty { ignored += 1 }
                continue
            }
            if !seenNames.insert(name).inserted {
                duplicateName = true
            } else if columns[field] != nil {
                duplicateAlias = true
            }
            if columns[field] == nil { columns[field] = index }
        }
        guard !columns.isEmpty else { return .unrecognized }
        if width > PackLimits.dataColumns { return .invalid(.tooManyColumns) }
        if duplicateName { return .invalid(.duplicateHeader) }
        if duplicateAlias { return .invalid(.duplicateHeaderAlias) }
        if columns[.number] != nil && columns[.trigger] != nil { return .invalid(.mixedModeHeader) }
        guard columns[.body] != nil, columns[.number] != nil || columns[.trigger] != nil else {
            return .invalid(.missingRequiredColumn)
        }
        return .header(Header(columns: columns, width: width, ignored: ignored))
    }

    /// 데이터 레코드의 열 수 — 머리글 실효 폭과 같거나, 초과분이 전부 빈 셀이어야 한다(패딩 금지)
    static func columnsMatch(_ cells: [String], width: Int) -> Bool {
        cells.count >= width && cells.dropFirst(width).allSatisfy(\.isEmpty)
    }

    static func isMetaKey(_ cell: String) -> Bool {
        cell.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#")
    }

    /// 후보 시험 — 메타(키 모양만)·빈 레코드를 건너뛰고 첫 레코드를 머리글로 판정, 뒤 데이터 몇 개의 열 수를 본다.
    ///
    /// 「다음 데이터 레코드들의 열 수가 머리글과 일치」(5-2 #2)는 **본 데이터 중 절반 이상**으로 읽는다 — 앞쪽에 열 수가 틀린
    /// 행이 하나 있다고 구분자를 버리면 「열 수가 다른 레코드는 그 행만 건너뜀」(5-4)이 성립하지 않는다. 잘못된 구분자는
    /// 머리글부터 인정되지 않거나 대부분의 행에서 열 수가 어긋나 걸러진다.
    ///
    /// 머리글은 인정됐는데 과반이 틀리면 그 후보는 `columnCountMismatch`로 탈락한다 — 머리글 오류가 아니다(검증 F2).
    /// 위치는 시험한 데이터 중 첫 불일치 레코드(파일 기준 번호 — 빈 레코드 포함, 본 파싱과 같다).
    static func trialVerdict(_ records: [CSVRecord]) -> TrialVerdict {
        var header: Header?
        var seen = 0
        var matched = 0
        var firstMismatch: (record: Int, line: Int)?
        for (offset, record) in records.enumerated() where !record.isBlank {
            guard let current = header else {
                if isMetaKey(record.cells[0]) { continue }
                switch parseHeader(record.cells) {
                case .header(let parsed): header = parsed
                case .unrecognized: return .noHeader
                case .invalid(let failure): return .rejected(failure)
                }
                continue
            }
            seen += 1
            if columnsMatch(record.cells, width: current.width) {
                matched += 1
            } else if firstMismatch == nil {
                firstMismatch = (offset + 1, record.line)
            }
            if seen >= PackImporter.trialDataRecords { break }
        }
        guard header != nil else { return .noHeader }
        guard matched * 2 < seen, let firstMismatch else { return .adopted }
        return .rejected(.columnCountMismatch(record: firstMismatch.record, line: firstMismatch.line))
    }

    /// xlsx 시트 표 — 행을 `PackRecord`로 바꿔 **같은** 본 판정에 넣는다(AC-32). 숨긴 열은 가져오는 열만 센다
    static func read(_ table: RawTable) throws(PackImportFailure) -> PackDraft {
        try read(table.rows.map(PackRecord.init(row:)), delimiter: nil, hiddenColumns: Set(table.hiddenColumns))
    }

    /// 본 판정 — 구조 오류는 throw, 행 오류는 건너뜀. CSV·xlsx가 같은 길이다: 원본 형식을 묻지 않고 레코드의 칸·칸 종류·병합만 본다
    /// (CSV 레코드는 칸 종류가 모두 글이고 병합이 없어 xlsx 몫의 검사가 언제나 통과한다)
    static func read(_ records: [PackRecord], delimiter: CSVDelimiter?, hiddenColumns: Set<Int> = []) throws(PackImportFailure) -> PackDraft {
        var meta = PackMetaPrefill(name: nil, license: nil, templateSpecs: [], issues: [])
        var seenMeta: [PackMetaField: String] = [:]
        var header: Header?
        var rows = RowCollector()

        for record in records {
            let position = record.position
            if record.isBlank { continue }                        // 빈 레코드 — 어디서든 무시, 분모 제외
            let key = record.cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let current = header else {
                if key.hasPrefix("#") {
                    try checkStructureRow(record)
                    try readMeta(record, key: key, seen: &seenMeta, into: &meta)
                    continue
                }
                switch parseHeader(record.cells) {
                case .unrecognized: throw .headerNotRecognized
                case .header(let parsed):
                    try checkStructureRow(record)
                    header = parsed
                case .invalid(let failure):
                    try checkStructureRow(record)
                    throw failure
                }
                continue
            }
            // 머리글 뒤의 예약 메타 키 = 위치 오류(엑셀 정렬 사고)
            if reservedMetaKeys.contains(key) { throw .metaAfterHeader(record: position.record, line: position.line) }
            rows.dataRecordCount += 1
            guard rows.dataRecordCount <= PackLimits.dataRecords else { throw .tooManyRecords }
            if let reason = cellSkipReason(record, numberColumn: current.columns[.number]) {
                rows.skip(position, reason)
                continue
            }
            guard columnsMatch(record.cells, width: current.width) else {
                rows.skip(position, .columnCount)
                continue
            }
            rows.accept(record, header: current)
        }
        guard let header else { throw .headerNotRecognized }
        if header.mode == .phrases && !meta.templateSpecs.isEmpty { throw .templateInPhrasesMode }

        let (entries, items, duplicates) = rows.finish(mode: header.mode)
        return PackDraft(encoding: nil, hadBOM: false, needsEncodingConfirmation: false, delimiter: delimiter,
                         delimiterCandidates: delimiter.map { [$0] } ?? [], sheetName: nil, hiddenRowCount: rows.acceptedHidden,
                         hiddenColumnCount: Set(header.columns.values).intersection(hiddenColumns).count,
                         mode: header.mode, meta: meta, entries: entries, items: items,
                         skipped: rows.skipped, dataRecordCount: rows.dataRecordCount, acceptedRecordCount: rows.accepted,
                         duplicateCount: duplicates, ignoredColumnCount: header.ignored,
                         sanitizedCharacterCount: rows.sanitized, strayQuoteCount: 0)
    }

    /// 머리글·정보 줄(6-4) — 병합과 겹치면 전체 거부(비선두 칸이 비어 열 구조를 믿을 수 없다), 원문이 아닌 칸(수식·날짜·불리언·오류)이 있어도
    /// 전체 거부 `[판단 1-e ③]`(그 줄의 값을 알 수 없다 — 데이터 행처럼 건너뛸 수 없는 줄이다). 숫자 칸은 글자 그대로 읽는다(CSV와 같다).
    /// 머리글로 인정되지 않는 줄(제목 줄)은 여기 오지 않는다 — CSV처럼 「머리글을 찾지 못했어요」가 먼저다
    private static func checkStructureRow(_ record: PackRecord) throws(PackImportFailure) {
        if record.isMerged { throw .mergedHeaderOrMeta(record: record.position.record, line: record.position.line) }
        if record.hasUnsupportedCell { throw .nonTextHeaderCell(record: record.position.record, line: record.position.line) }
    }

    /// 6-4 — 원문이 아닌 칸이 있는 데이터 행의 사유. 우선순위(한 행에 여럿이면 첫 것): 수식 → 날짜 서식 → 불리언·오류 →
    /// 숫자(번호 열 밖 — 단축어·제목·본문·모르는 열·머리글 밖, R19) → 병합. 행의 **모든 칸**을 본다. CSV 레코드는 언제나 nil
    static func cellSkipReason(_ record: PackRecord, numberColumn: Int?) -> SkipReason? {
        var found: SkipReason?
        var rank = Int.max
        for (index, kind) in record.kinds.enumerated() {
            let reason: SkipReason
            switch kind {
            case .text: continue
            case .number:
                guard index != numberColumn else { continue }
                reason = .numberCell
            case .unsupported(.formula): reason = .formula
            case .unsupported(.date): reason = .dateFormat
            case .unsupported(.boolean), .unsupported(.error): reason = .booleanOrError
            }
            if let candidate = cellReasonOrder.firstIndex(of: reason), candidate < rank {
                rank = candidate
                found = reason
            }
        }
        return found ?? (record.isMerged ? .merged : nil)
    }

    /// 6-4 사유 순서 — 병합은 행 속성이라 칸 사유가 없을 때만
    private static let cellReasonOrder: [SkipReason] = [.formula, .dateFormat, .booleanOrError, .numberCell]

    /// 5-3 — 메타는 머리글 앞에서만. 중복(같은 **칸** — `#출처`와 옛 `#권리`는 한 칸)·알 수 없는 키·`#escape`(후속)·셀 cap·
    /// 값 개수(trailing 빈 셀만 허용). `seen`은 칸마다 처음 쓴 키 — 키가 다른 중복(`#출처`+`#권리`)은 문구가 따로다(검증 O1)
    private static func readMeta(
        _ record: PackRecord, key: String, seen: inout [PackMetaField: String], into meta: inout PackMetaPrefill
    ) throws(PackImportFailure) {
        let number = record.position.record
        let line = record.position.line
        guard let field = PackMetaField.field(forKey: key) else {
            if key == metaEscape { throw .unsupportedEscapeMeta(record: number, line: line) }
            throw .unknownMeta(record: number, line: line)
        }
        if let first = seen[field] {
            // 키가 둘인 칸은 출처뿐이다 — 키가 다르면 `#출처`와 `#권리`가 함께 있는 것
            throw first == key ? .duplicateMeta(record: number, line: line) : .duplicateSourceMeta(record: number, line: line)
        }
        seen[field] = key
        let effective = effectiveCount(record.cells)
        guard effective <= PackLimits.metaCells else { throw .metaTooManyCells(record: number, line: line) }
        let values = Array(record.cells[1..<max(1, effective)])
        let allowed = field == .template ? 1...PackLimits.templatePatterns : 1...1
        guard allowed.contains(values.count), !values.contains(where: \.isEmpty) else {
            throw .metaValueCount(record: number, line: line)
        }
        switch field {
        case .name:
            let value = PackTextSanitizer.sanitize(values[0]).text
            if PackLimits.name.admits(value) { meta.name = value } else { meta.issues.append(.nameTooLong) }
        case .license:
            let value = PackTextSanitizer.sanitize(values[0]).text
            if PackLimits.license.admits(value) { meta.license = value } else { meta.issues.append(.licenseTooLong) }
        case .template:
            meta.templateSpecs = values.map { PackTextSanitizer.sanitize($0).text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}

/// 행별 검증·정리(5-4·11절)와 중복 처리 — 순서를 지키며 모은다
private struct RowCollector {
    var dataRecordCount = 0
    var accepted = 0
    /// 받은 행 가운데 숨긴 행(xlsx 「숨김 N」, 6-4) — 중복으로 덮인 것 포함(`accepted`와 같은 잣대)
    var acceptedHidden = 0
    var sanitized = 0
    var skipped: [SkippedRecord] = []
    /// 번호형 — 받은 순서대로(중복은 끝에서 정리)
    private var numbered: [PackTemplateItem] = []
    private var phrases: [SnippetEntry] = []

    mutating func skip(_ position: PackRecordPosition, _ reason: SkipReason) {
        skipped.append(SkippedRecord(position: position, reason: reason))
    }

    mutating func accept(_ record: PackRecord, header: PackRecordReader.Header) {
        let before = accepted
        accept(record, position: record.position, header: header)
        if accepted > before, record.isHidden { acceptedHidden += 1 }
    }

    private mutating func accept(_ record: PackRecord, position number: PackRecordPosition, header: PackRecordReader.Header) {
        func cell(_ field: PackRecordReader.Field) -> String? {
            header.columns[field].map { record.cells[$0] }
        }
        func clean(_ text: String) -> String {
            let result = PackTextSanitizer.sanitize(text)
            sanitized += result.removed
            return result.text
        }
        let title = clean(cell(.title) ?? "")
        let body = clean(cell(.body) ?? "")

        switch header.mode {
        case .numbered:
            let raw = (cell(.number) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return skip(number, .missingNumber) }
            guard let n = Self.number(raw) else { return skip(number, .invalidNumber) }
            guard PackLimits.numberRange.contains(n) else { return skip(number, .numberOutOfRange) }
            guard let reason = Self.contentFailure(title: title, body: body) else {
                accepted += 1
                numbered.append(PackTemplateItem(n: n, title: title, body: body))
                return
            }
            skip(number, reason)
        case .phrases:
            switch TriggerCell.parse(clean(cell(.trigger) ?? "")) {
            case .failure(let failure):
                let reason: SkipReason = switch failure {
                case .empty: .missingTrigger
                case .tooMany: .tooManyTriggers
                case .tooLong: .triggerTooLong
                }
                skip(number, reason)
            case .success(let triggers):
                if let reason = Self.contentFailure(title: title, body: body) { return skip(number, reason) }
                accepted += 1
                phrases.append(SnippetEntry(triggers: triggers, title: title.isEmpty ? triggers[0] : title, body: body))
            }
        }
    }

    /// 같은 번호는 뒤가 이긴다(번호 오름차순). 문구형은 정규화 기준 같은 단축어를 뒤 항목이 가져가고, 단축어가 다 빠진 앞 항목은 없앤다
    func finish(mode: ExternalPack.Mode) -> (entries: [SnippetEntry], items: [PackTemplateItem], duplicates: Int) {
        switch mode {
        case .numbered:
            var latest: [Int: PackTemplateItem] = [:]
            for item in numbered { latest[item.n] = item }
            return ([], latest.values.sorted { $0.n < $1.n }, numbered.count - latest.count)
        case .phrases:
            var owner: [String: Int] = [:]                // 정규화 단축어 → 마지막 항목 위치
            for (index, entry) in phrases.enumerated() {
                for trigger in entry.triggers { owner[SnippetEntry.normalizedTrigger(trigger)] = index }
            }
            var duplicates = 0
            var result: [SnippetEntry] = []
            for (index, entry) in phrases.enumerated() {
                let kept = entry.triggers.filter { owner[SnippetEntry.normalizedTrigger($0)] == index }
                duplicates += entry.triggers.count - kept.count
                guard !kept.isEmpty else { continue }
                result.append(SnippetEntry(triggers: kept, title: entry.title, body: entry.body))
            }
            return (result, [], duplicates)
        }
    }

    /// v2 4-5 — `^[0-9]{1,4}(\.0+)?$`(전각은 NFKC 뒤). 앞자리 0은 값으로 본다(xlsx 6-4 번호 열과 같은 결과)
    static func number(_ raw: String) -> Int? {
        let normalized = raw.precomposedStringWithCompatibilityMapping
        var digits = Substring(normalized)
        if let dot = digits.firstIndex(of: ".") {
            let fraction = digits[digits.index(after: dot)...]
            guard !fraction.isEmpty, fraction.allSatisfy({ $0 == "0" }) else { return nil }
            digits = digits[..<dot]
        }
        guard (1...4).contains(digits.count), digits.allSatisfy({ $0.asciiValue.map { (48...57).contains($0) } ?? false })
        else { return nil }
        return Int(digits)
    }

    /// 본문 없음(공백만 포함) → 상한 → 그 행만 건너뜀
    static func contentFailure(title: String, body: String) -> SkipReason? {
        if body.allSatisfy(\.isWhitespace) { return .emptyBody }
        if !PackLimits.title.admits(title) { return .titleTooLong }
        if !PackLimits.body.admits(body) { return .bodyTooLong }
        return nil
    }
}
