import Foundation
import TadakDomain

/// 가져오기 원본 — **메모리에만** 있다. 로그·파일·네트워크·분석 이벤트로 내보내지 않는다(보안 규칙)
public enum PackImportSource: Equatable, Sendable {
    /// 파일 앱에서 고른 CSV(`.csv`·`.tsv`·`.txt`)의 원본 바이트 — 인코딩 판정 전
    case file(Data)
    /// 붙여 넣은 글(3-E) — 이미 글자라 인코딩 단계가 없다
    case paste(String)

    public enum Kind: Equatable, Sendable { case file, paste }

    public var kind: Kind {
        switch self {
        case .file: .file
        case .paste: .paste
        }
    }

    /// 파일 바이트 상한과 같은 잣대(붙여넣기는 UTF-8 바이트, PDR 5-2 검증 F5)
    var byteCount: Int {
        switch self {
        case .file(let data): data.count
        case .paste(let text): text.utf8.count
        }
    }
}

/// 가져오기를 멈추는 이유 — 화면은 4-G 모양으로 보인다(`PackImportCopy.failureMessage`). **내용 없는 코드**다(AC-34)
public enum PackImportProblem: Error, Equatable, Sendable {
    /// 구조 오류 — 비율과 무관하게 전체 거부(5-5)
    case structural(PackImportFailure)
    /// 고른 파일을 열지 못했다(권한·내려받기 실패) — 이유·경로를 담지 않는다
    case fileUnreadable
    /// 받을 수 있는 행이 0 — 영구 비활성(5-5). 건너뛴 행의 **위치와 사유만** 들고 간다(검증 F-7 — 초안을 들면 `#이름`·`#권리`·`#틀`
    /// 원문이 오류 값에 실린다. 4-G 화면이 보이는 것은 사유 묶음과 위치뿐이다)
    case noValidRecords([SkippedRecord])
}

/// 미리보기 모델(시안 4-E·4-F·4-H·4-I) — 받을 항목 · 건너뛴 행과 사유 · 겹치는 단축어
public struct PackImportPreview: Equatable, Sendable {
    /// 파서가 만든 초안(`PackImporter`) — 받을 항목·건너뛴 행(행 번호와 사유만)·중복·모르는 열·정리 건수
    public var draft: PackDraft
    /// 문구형의 단축어 겹침(4-I) — 번호형이거나 목록을 읽지 못했으면 nil(번호형 틀의 겹침은 폼 5-C 몫)
    public var overlap: PackDraftOverlap?

    public init(draft: PackDraft, overlap: PackDraftOverlap?) {
        self.draft = draft
        self.overlap = overlap
    }

    /// 가져올 항목 — 같은 번호·단축어를 뒤가 이긴 **뒤**의 수(팩에 실제로 들어가는 수)
    public var importCount: Int { draft.mode == .numbered ? draft.items.count : draft.entries.count }

    /// 4-H 「건너뜀 (57%)」 — 분모는 데이터 논리 레코드(R10)
    public var skippedPercent: Int { Self.percent(skipped: draft.skipped.count, of: draft.dataRecordCount) }

    /// 반올림하되, 받은 행이 있으면 100%로 보이지 않는다(299/300 → 99%)
    static func percent(skipped: Int, of total: Int) -> Int {
        guard total > 0 else { return 0 }
        let rounded = Int((Double(skipped) * 100 / Double(total)).rounded())
        return skipped < total ? min(rounded, 99) : rounded
    }
}

/// 가져오기 상태기계(계획서 `external-snippet-packs-1c-plan.md` 5절 4행 ①, 시안 4-A~4-H).
///
/// ```
/// idle ─start/begin+load─▶ reading ─receive─┬─▶ encoding(R18: BOM 없는 비ASCII) ─confirmEncoding─┐
///                                            ├─▶ delimiter(후보 둘 이상, 5-2 #3) ◀────────────────────┤
///                                            ├─▶ preview(4-E·4-F·4-H·4-I) ◀──────────────────────────┤
///                                            └─▶ failed(4-G — 구조 오류·파일 못 엶·유효 0) ◀───────────┘
/// encoding ─chooseEncoding─▶ (일하는 중) ─receive─▶ encoding(새 값)
/// delimiter·preview ─chooseDelimiter─▶ (일하는 중) ─receive─▶ preview …   preview ─reviewEncodingAgain─▶ encoding
/// 어디서든 ─cancel─▶ idle(원본을 비운다)
/// ```
///
/// - **원본에서 전부 다시**(5-1·AC-18): 인코딩·구분자를 바꾸면 처음 받은 원본(`Data`·글)을 `Run`에 실어 ②부터 다시 읽는다 — 앞 결과를
///   재사용하지 않는다. 인코딩을 바꾸면 고른 구분자도 버린다(구분자 판정부터 다시, 5-3b #6).
/// - **메인 밖**: 상태기계는 값이고 무거운 일은 `Run`으로 꺼내 `compute`(순수)·`perform`(전역 큐)이 한다. 결과는 `receive`로 돌려준다.
/// - **취소·늦은 결과**: 새로 시작하거나 선택을 바꾸거나 취소하면 세대가 오른다 — 옛 세대의 결과는 받지 않는다. 취소하면 원본을 비운다.
/// - **상한**: 원본이 바이트 상한을 넘으면 계산 없이 거부하고 원본을 들고 있지 않는다. 행·줄 상한은 파서가 전체 거부로 낸다.
/// - **R10**: 건너뜀 50% 이상이면 명시 확인(`confirmPartialImport`) 전에는 진행하지 않는다(`canProceed`). 유효 0은 거부다.
///
/// 원본·초안은 사용자 데이터다 — 이 값은 메모리에만 있고 로그·분석 이벤트에 싣지 않는다(보안 규칙).
public struct PackImportSession: Equatable, Sendable {

    public enum Phase: Equatable, Sendable {
        case idle
        /// 4-A — 파일을 여는 중이거나 처음 읽는 중
        case reading
        /// 4-B·4-C — 글자 확인
        case encoding(PackEncodingReview)
        /// 구분자 후보가 둘 이상 — 사용자가 고른다(5-2 #3)
        case delimiter([CSVDelimiter])
        case preview(PackImportPreview)
        case failed(PackImportProblem)
    }

    /// 메인 밖에서 할 일 한 번 — `compute`·`perform`에 넘긴다
    public struct Run: Equatable, Sendable {
        public let generation: Int
        /// 처음 받은 원본 그대로(AC-18)
        public let source: PackImportSource
        public let options: PackImportOptions
    }

    /// `compute`의 결과 — `receive`로 돌려준다
    public struct Computation: Equatable, Sendable {
        public enum Outcome: Equatable, Sendable {
            case preview(PackImportPreview)
            case chooseDelimiter([CSVDelimiter])
            case failed(PackImportProblem)
        }

        public let generation: Int
        /// 글자 확인이 필요한 파일이면 그 화면 값(R18)
        public let review: PackEncodingReview?
        public let outcome: Outcome
    }

    public private(set) var phase: Phase = .idle
    /// 지금 읽기 선택 — 인코딩·구분자
    public private(set) var options = PackImportOptions()
    /// 메인 밖 일을 기다리는 중 — 그동안 다른 선택을 받지 않는다
    public private(set) var isWorking = false
    /// 4-H 「그래도 n개만 가져오기」를 확인했다(R10)
    public private(set) var partialImportConfirmed = false
    public private(set) var sourceKind: PackImportSource.Kind?
    /// 이 원본이 거친 글자 확인의 마지막 값 — 미리보기의 「글자 방식 다시 고르기」가 쓴다. 확인이 없던 원본이면 nil
    public private(set) var lastReview: PackEncodingReview?

    private var source: PackImportSource?
    private var generation = 0
    /// 글자 확인에서 「다음」을 눌렀다 — 그 뒤 구분자를 바꿔도 확인 화면을 다시 띄우지 않는다
    private var encodingConfirmed = false
    /// 글자 확인 화면 뒤에서 기다리는 결과
    private var pending: Computation?

    public init() {}

    /// 원본을 들고 있나 — 취소·거부 뒤에는 비어 있어야 한다(메모리에만, 끝나면 비운다)
    public var hasSource: Bool { source != nil }

    /// 미리보기에서 「다음」(5단계 폼)으로 갈 수 있나 — 받을 항목이 있고, 절반 이상 건너뛰면 명시 확인 뒤(R10·AC-19)
    public var canProceed: Bool {
        guard !isWorking, case .preview(let preview) = phase, preview.draft.isImportable else { return false }
        return !preview.draft.requiresConfirmation || partialImportConfirmed
    }

    // MARK: - 시작

    /// 새 가져오기 — 앞 가져오기를 버리고 4-A로. 파일은 이 뒤에 메인 밖에서 열어 `load`로 싣는다(그 사이 취소되면 싣지 않는다)
    public mutating func begin(_ kind: PackImportSource.Kind) -> Int {
        cancel()
        phase = .reading
        sourceKind = kind
        isWorking = true
        return generation
    }

    /// 열어 둔 원본을 싣는다 — `begin`이 준 표(ticket)가 지금 것이 아니면(취소·새 시작) 받지 않는다. 바이트 상한을 넘으면 계산 없이 거부
    public mutating func load(_ source: PackImportSource, ticket: Int) -> Run? {
        guard ticket == generation, phase == .reading, self.source == nil, source.kind == sourceKind else { return nil }
        guard source.byteCount <= PackLimits.fileBytes else {
            finish(.failed(.structural(.fileTooLarge)))
            return nil
        }
        self.source = source
        return Run(generation: generation, source: source, options: options)
    }

    /// 파일을 열지 못했다(제한 읽기 실패) — 그 표일 때만
    public mutating func failToLoad(_ problem: PackImportProblem, ticket: Int) {
        guard ticket == generation, phase == .reading, source == nil else { return }
        finish(.failed(problem))
    }

    /// `begin` + `load` — 붙여넣기처럼 원본이 이미 손에 있을 때
    public mutating func start(_ source: PackImportSource) -> Run? {
        load(source, ticket: begin(source.kind))
    }

    // MARK: - 결과 받기

    /// 메인 밖 결과를 받는다 — 옛 세대(취소·선택 변경 전)의 결과면 버리고 거짓
    @discardableResult
    public mutating func receive(_ computation: Computation) -> Bool {
        guard computation.generation == generation, isWorking, source != nil else { return false }
        isWorking = false
        guard let review = computation.review else {
            apply(computation.outcome)
            return true
        }
        lastReview = review
        if encodingConfirmed {
            apply(computation.outcome)
        } else {
            pending = computation
            phase = .encoding(review)
        }
        return true
    }

    // MARK: - 선택

    /// 4-B·4-C — 다른 방식으로 읽어 본다. 원본에서 전부 다시, 고른 구분자는 버린다(5-3b #6)
    public mutating func chooseEncoding(_ encoding: PackEncodingReview.Encoding) -> Run? {
        guard !isWorking, case .encoding(let review) = phase, review.selected != encoding else { return nil }
        options = PackImportOptions(encoding: encoding.choice, delimiter: nil)
        return rerun()
    }

    /// 4-B·4-C 「다음」 — 고른 방식으로 파일 전체가 읽힐 때만
    public mutating func confirmEncoding() {
        guard !isWorking, case .encoding(let review) = phase, review.reading(review.selected).isReadable, let pending else { return }
        encodingConfirmed = true
        self.pending = nil
        apply(pending.outcome)
    }

    /// 미리보기·구분자 고르기에서 글자 확인으로 돌아간다 — 다시 읽지 않는다(지금 결과를 그 화면 뒤에 둔다)
    public mutating func reviewEncodingAgain() {
        guard !isWorking, source != nil, let review = lastReview else { return }
        let outcome: Computation.Outcome
        switch phase {
        case .preview(let preview): outcome = .preview(preview)
        case .delimiter(let candidates): outcome = .chooseDelimiter(candidates)
        default: return
        }
        encodingConfirmed = false
        pending = Computation(generation: generation, review: review, outcome: outcome)
        phase = .encoding(review)
    }

    /// 구분자를 고르거나(5-2 #3) 미리보기에서 바꾼다(5-2 #4) — 원본에서 전부 다시, 인코딩 선택은 그대로
    public mutating func chooseDelimiter(_ delimiter: CSVDelimiter) -> Run? {
        guard !isWorking else { return nil }
        switch phase {
        case .delimiter: break
        case .preview(let preview): guard preview.draft.delimiter != delimiter else { return nil }
        default: return nil
        }
        options.delimiter = delimiter
        return rerun()
    }

    /// 4-H — 절반 넘게 건너뛰어도 받을 수 있는 것만 가져오겠다고 **명시** 확인(R10). 유효 0은 거부라 해당 없다
    public mutating func confirmPartialImport() {
        guard !isWorking, case .preview(let preview) = phase, preview.draft.isImportable, preview.draft.requiresConfirmation else { return }
        partialImportConfirmed = true
    }

    /// 취소·닫기 — idle로, 원본·결과를 비운다. 메인 밖에서 돌던 일의 결과는 세대가 달라 버려진다
    public mutating func cancel() {
        generation += 1
        phase = .idle
        options = PackImportOptions()
        isWorking = false
        partialImportConfirmed = false
        sourceKind = nil
        lastReview = nil
        source = nil
        encodingConfirmed = false
        pending = nil
    }

    // MARK: - 안

    private mutating func rerun() -> Run? {
        guard let source else { return nil }
        generation += 1
        isWorking = true
        return Run(generation: generation, source: source, options: options)
    }

    private mutating func apply(_ outcome: Computation.Outcome) {
        partialImportConfirmed = false
        switch outcome {
        case .preview(let preview): phase = .preview(preview)
        case .chooseDelimiter(let candidates): phase = .delimiter(candidates)
        case .failed(let problem): finish(.failed(problem))
        }
    }

    /// 거부는 끝이다 — 원본을 바로 비운다(다시 읽을 길이 없다)
    private mutating func finish(_ failed: Phase) {
        phase = failed
        isWorking = false
        source = nil
        pending = nil
    }

    // MARK: - 메인 밖에서 할 일

    /// 한 번의 읽기 — **순수**하다(같은 Run이면 같은 결과). 원본 바이트에서 인코딩→구분자→파싱→검증을 전부 한다(5-1·AC-18).
    /// - Parameter library: 단축어 겹침(4-I)을 셀 지금 목록 — 못 읽었으면 nil(겹침 안내 없이 미리보기)
    public static func compute(_ run: Run, library: PackImpact.Library?) -> Computation {
        var review: PackEncodingReview?
        if case .file(let data) = run.source { review = PackEncodingReview.probe(data, choice: run.options.encoding) }

        let outcome: Computation.Outcome
        do throws(PackImportFailure) {
            let read: PackImportOutcome = switch run.source {
            case .file(let data): try PackImporter.read(data, options: run.options)
            case .paste(let text): try PackImporter.read(text: text, delimiter: run.options.delimiter)
            }
            switch read {
            case .chooseDelimiter(let candidates):
                outcome = .chooseDelimiter(candidates)
            case .draft(let draft):
                let overlap = draft.mode == .phrases ? library.map { PackImpact.overlap(ofDraft: draft.entries, in: $0) } : nil
                let preview = PackImportPreview(draft: draft, overlap: overlap)
                outcome = draft.isImportable ? .preview(preview) : .failed(.noValidRecords(draft.skipped))
                review?.recordCount = draft.dataRecordCount
                review?.multilineBodyCount = draft.mode == .numbered ? draft.items.filter { $0.body.contains("\n") }.count
                    : draft.entries.filter { $0.body.contains("\n") }.count
            }
        } catch {
            outcome = .failed(.structural(error))
        }
        return Computation(generation: run.generation, review: review, outcome: outcome)
    }

    /// `compute`를 전역 큐에서 — 화면(메인)은 `await` 동안 멈추지 않는다. 큰 파일(3MB) 파싱이 메인을 막지 않게(1-c G8).
    /// Swift 협력 스레드 풀이 아니라 GCD 큐로 넘긴다(`PackStoreClient.run`과 같은 이유)
    public static func perform(_ run: Run, library: PackImpact.Library?,
                               queue: DispatchQueue = .global(qos: .userInitiated)) async -> Computation {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: compute(run, library: library)) }
        }
    }
}
