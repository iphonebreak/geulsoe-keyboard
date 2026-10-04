import Foundation
import TadakDomain

public struct PackImportOptions: Equatable, Sendable {
    /// 확인 화면에서 고른 인코딩 — 바꾸면 원본 바이트에서 전부 다시(5-1·AC-18)
    public var encoding: PackEncodingChoice
    /// 사용자가 고른 구분자(후보가 2개 이상일 때 또는 수동 변경) — nil이면 후보 검증(5-2)
    public var delimiter: CSVDelimiter?

    public init(encoding: PackEncodingChoice = .automatic, delimiter: CSVDelimiter? = nil) {
        self.encoding = encoding
        self.delimiter = delimiter
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
}

public struct SkippedRecord: Equatable, Sendable {
    /// 논리 레코드 번호(1부터, 파일 전체 기준)
    public var record: Int
    /// 그 레코드가 시작한 물리 줄
    public var line: Int
    public var reason: SkipReason
}

/// 메타 값이 상한을 넘어 미리 채우지 않은 칸 — 폼이 최종 권위라 거부하지 않는다(5-6)
public enum MetaIssue: Equatable, Sendable {
    case nameTooLong
    case licenseTooLong
}

/// `#` 메타의 **미리 채움**(5-6 — 폼이 최종 권위, 파일명은 쓰지 않는다)
public struct PackMetaPrefill: Equatable, Sendable {
    public var name: String?
    /// 제작자가 준 권리 문구 — 선택지로 덮지 않고 원문 그대로 보인다(길이 제한 안에서)
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
    public var delimiter: CSVDelimiter
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
}

public enum PackImportOutcome: Equatable, Sendable {
    case draft(PackDraft)
    /// 채택 후보가 2개 이상 — 사용자가 고르면 `PackImportOptions.delimiter`로 다시 부른다(5-2 #3)
    case chooseDelimiter([CSVDelimiter])
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
        if let chosen {
            delimiter = chosen
        } else {
            let adopted = try adoptDelimiters(text)
            guard adopted.count == 1, let only = adopted.first else { return .chooseDelimiter(adopted) }
            delimiter = only
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
        var draft = try PackRecordReader.read(parsed.records, delimiter: delimiter)
        draft.encoding = encoding?.encoding
        draft.hadBOM = encoding?.hadBOM ?? false
        draft.needsEncodingConfirmation = encoding?.needsConfirmation ?? false
        draft.strayQuoteCount = parsed.strayQuoteCount
        return .draft(draft)
    }

    /// 5-2 — 후보마다 첫 논리 레코드들을 시험 파싱해 **머리글 인정 + 필수 열 유일 + 모드 일관 + 다음 데이터 레코드 열 수 일치**를
    /// 보는 후보를 고른다. 시험 중 quote 오류는 **그 후보만 탈락**(명확화 ①) — 시험 결과는 버리므로 데이터가 새지 않는다.
    private static func adoptDelimiters(_ text: String) throws(PackImportFailure) -> [CSVDelimiter] {
        var adopted: [CSVDelimiter] = []
        var quoteErrors: [CSVQuoteError] = []
        var headerFailure: PackImportFailure?
        for candidate in CSVDelimiter.allCases {
            let trial: CSVParseResult
            do {
                trial = try CSVRecordParser.parse(text, delimiter: candidate, maxNonBlankRecords: trialRecords)
            } catch {
                switch error {
                case .quote(let quote): quoteErrors.append(quote)
                case .tooManyLines: throw .tooManyLines
                }
                continue
            }
            switch PackRecordReader.trialVerdict(trial.records) {
            case .adopted: adopted.append(candidate)
            case .rejected(let failure): if headerFailure == nil { headerFailure = failure }
            case .noHeader: break
            }
        }
        if !adopted.isEmpty { return adopted }
        // 모든 후보가 quote 오류로 탈락 → 「따옴표 오류」를 우선(구조 오류, 5-2 #3)
        if quoteErrors.count == CSVDelimiter.allCases.count, let first = quoteErrors.first { throw .quote(first) }
        throw headerFailure ?? .headerNotRecognized
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
}

/// 논리 레코드 → 헤더·메타 판정 → 행별 검증. **xlsx(1-e)도 `RawTable`을 같은 레코드 모양으로 넘겨 이 경로를 탄다**(6-1·AC-32).
enum PackRecordReader {

    enum Field: Equatable { case number, trigger, title, body }

    /// v2 4-2 — 앞뒤 공백·대소문자 무시
    static let columnNames: [String: Field] = [
        "번호": .number, "n": .number, "no": .number, "number": .number,
        "단축어": .trigger, "trigger": .trigger, "triggers": .trigger,
        "제목": .title, "title": .title,
        "본문": .body, "내용": .body, "body": .body
    ]

    static let metaName = "#이름"
    static let metaTemplate = "#틀"
    static let metaLicense = "#권리"
    static let metaEscape = "#escape"
    static let reservedMetaKeys: Set<String> = [metaName, metaTemplate, metaLicense, metaEscape]

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

    /// 본 판정 — 구조 오류는 throw, 행 오류는 건너뜀
    static func read(_ records: [CSVRecord], delimiter: CSVDelimiter) throws(PackImportFailure) -> PackDraft {
        var meta = PackMetaPrefill(name: nil, license: nil, templateSpecs: [], issues: [])
        var seenMeta = Set<String>()
        var header: Header?
        var rows = RowCollector()

        for (offset, record) in records.enumerated() {
            let number = offset + 1
            if record.isBlank { continue }                        // 빈 레코드 — 어디서든 무시, 분모 제외
            let key = record.cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let current = header else {
                if key.hasPrefix("#") {
                    try readMeta(record, key: key, number: number, seen: &seenMeta, into: &meta)
                    continue
                }
                switch parseHeader(record.cells) {
                case .header(let parsed): header = parsed
                case .unrecognized: throw .headerNotRecognized
                case .invalid(let failure): throw failure
                }
                continue
            }
            // 머리글 뒤의 예약 메타 키 = 위치 오류(엑셀 정렬 사고)
            if reservedMetaKeys.contains(key) { throw .metaAfterHeader(record: number, line: record.line) }
            rows.dataRecordCount += 1
            guard rows.dataRecordCount <= PackLimits.dataRecords else { throw .tooManyRecords }
            guard columnsMatch(record.cells, width: current.width) else {
                rows.skip(number, record.line, .columnCount)
                continue
            }
            rows.accept(record, number: number, header: current)
        }
        guard let header else { throw .headerNotRecognized }
        if header.mode == .phrases && !meta.templateSpecs.isEmpty { throw .templateInPhrasesMode }

        let (entries, items, duplicates) = rows.finish(mode: header.mode)
        return PackDraft(encoding: nil, hadBOM: false, needsEncodingConfirmation: false, delimiter: delimiter,
                         mode: header.mode, meta: meta, entries: entries, items: items, skipped: rows.skipped,
                         dataRecordCount: rows.dataRecordCount, acceptedRecordCount: rows.accepted,
                         duplicateCount: duplicates, ignoredColumnCount: header.ignored,
                         sanitizedCharacterCount: rows.sanitized, strayQuoteCount: 0)
    }

    /// 5-3 — 메타는 머리글 앞에서만. 중복·알 수 없는 키·`#escape`(후속)·셀 cap·값 개수(trailing 빈 셀만 허용)
    private static func readMeta(
        _ record: CSVRecord, key: String, number: Int, seen: inout Set<String>, into meta: inout PackMetaPrefill
    ) throws(PackImportFailure) {
        switch key {
        case metaName, metaTemplate, metaLicense: break
        case metaEscape: throw .unsupportedEscapeMeta(record: number, line: record.line)
        default: throw .unknownMeta(record: number, line: record.line)
        }
        guard seen.insert(key).inserted else { throw .duplicateMeta(record: number, line: record.line) }
        let effective = effectiveCount(record.cells)
        guard effective <= PackLimits.metaCells else { throw .metaTooManyCells(record: number, line: record.line) }
        let values = Array(record.cells[1..<max(1, effective)])
        let allowed = key == metaTemplate ? 1...PackLimits.templatePatterns : 1...1
        guard allowed.contains(values.count), !values.contains(where: \.isEmpty) else {
            throw .metaValueCount(record: number, line: record.line)
        }
        switch key {
        case metaName:
            let value = PackTextSanitizer.sanitize(values[0]).text
            if PackLimits.name.admits(value) { meta.name = value } else { meta.issues.append(.nameTooLong) }
        case metaLicense:
            let value = PackTextSanitizer.sanitize(values[0]).text
            if PackLimits.license.admits(value) { meta.license = value } else { meta.issues.append(.licenseTooLong) }
        default:
            meta.templateSpecs = values.map { PackTextSanitizer.sanitize($0).text.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
    }
}

/// 행별 검증·정리(5-4·11절)와 중복 처리 — 순서를 지키며 모은다
private struct RowCollector {
    var dataRecordCount = 0
    var accepted = 0
    var sanitized = 0
    var skipped: [SkippedRecord] = []
    /// 번호형 — 받은 순서대로(중복은 끝에서 정리)
    private var numbered: [PackTemplateItem] = []
    private var phrases: [SnippetEntry] = []

    mutating func skip(_ record: Int, _ line: Int, _ reason: SkipReason) {
        skipped.append(SkippedRecord(record: record, line: line, reason: reason))
    }

    mutating func accept(_ record: CSVRecord, number: Int, header: PackRecordReader.Header) {
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
            guard !raw.isEmpty else { return skip(number, record.line, .missingNumber) }
            guard let n = Self.number(raw) else { return skip(number, record.line, .invalidNumber) }
            guard PackLimits.numberRange.contains(n) else { return skip(number, record.line, .numberOutOfRange) }
            guard let reason = Self.contentFailure(title: title, body: body) else {
                accepted += 1
                numbered.append(PackTemplateItem(n: n, title: title, body: body))
                return
            }
            skip(number, record.line, reason)
        case .phrases:
            switch TriggerCell.parse(clean(cell(.trigger) ?? "")) {
            case .failure(let failure):
                let reason: SkipReason = switch failure {
                case .empty: .missingTrigger
                case .tooMany: .tooManyTriggers
                case .tooLong: .triggerTooLong
                }
                skip(number, record.line, reason)
            case .success(let triggers):
                if let reason = Self.contentFailure(title: title, body: body) { return skip(number, record.line, reason) }
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
