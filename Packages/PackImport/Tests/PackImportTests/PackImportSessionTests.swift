import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 4단계 — 가져오기 상태기계 `PackImportSession`(계획서 `external-snippet-packs-1c-plan.md` 5절 4행 ①, 3-2·3-3절 4-A~4-H).
// PDR `external-snippet-packs.md` 5-1(선택이 바뀌면 원본 바이트에서 ②부터 전부 다시)·5-2 #3·#4(구분자 고르기·수동 변경)·5-3b(인코딩 R4·R18)·
// 5-5(R10 건너뜀 비율), AC-17·18·19·34. 상태기계는 순수 값이라 `compute`를 같은 스레드에서 불러 전이를 표로 본다 —
// 화면은 같은 `compute`를 메인 밖(`perform`)에서 부른다.

// MARK: - 시험 도구

private let numberedCSV = "번호,제목,본문\n1,예시 제목 하나,예시 본문 첫 줄\n2,예시 제목 둘,예시 본문 한 줄\n"
private let phrasesCSV = "단축어,제목,본문\n주소,회사 주소,예시 주소 한 줄\n새해인사,새해 인사,예시 인사 한 줄\n"
/// `C3 A9` — UTF-8로는 `é`, 한국어(CP949)로는 `챕`. 머리글은 ASCII라 두 방식 모두 머리글을 인정한다(PDR 5-3b ⑤의 반례)
private let cafeBytes = Data("trigger,body\r\ncafe,Caf\u{E9} meeting\r\n".utf8)
/// 두 후보(쉼표·세미콜론)가 모두 채택되는 표(`PackImporterTests.ambiguousAsksUser`와 같은 글)
private let ambiguousText = "단축어,본문,z;trigger;body\r\na,b,c;d;e"

private func cp949(_ text: String) -> Data { text.data(using: PackTextDecoder.cp949)! }

/// `#require`는 식을 클로저로 감싸 변경 메서드(`mutating`)를 그 안에서 부를 수 없다 — 먼저 부르고 결과만 넘긴다
func required<Value>(_ value: Value?, sourceLocation: SourceLocation = #_sourceLocation) throws -> Value {
    try #require(value, sourceLocation: sourceLocation)
}

/// 메인 밖 일을 같은 자리에서 끝낸다 — `receive`가 받았는지 돌려준다
@discardableResult
private func drive(_ session: inout PackImportSession, _ run: PackImportSession.Run?,
                   library: PackImpact.Library? = nil) -> Bool {
    guard let run else { return false }
    return session.receive(PackImportSession.compute(run, library: library))
}

private func started(_ source: PackImportSource, library: PackImpact.Library? = nil) -> PackImportSession {
    var session = PackImportSession()
    drive(&session, session.start(source), library: library)
    return session
}

private extension PackImportSession {
    var preview: PackImportPreview? {
        if case .preview(let preview) = phase { return preview }
        return nil
    }
    var review: PackEncodingReview? {
        if case .encoding(let review) = phase { return review }
        return nil
    }
    var problem: PackImportProblem? {
        if case .failed(let problem) = phase { return problem }
        return nil
    }
}

// MARK: - 전이 표

@Suite("외부 채움글 1-c 4단계 — 가져오기 상태기계 전이")
struct PackImportSessionTransitionTests {

    @Test("처음은 idle — 원본 없음, 진행 불가")
    func initial() {
        let session = PackImportSession()
        #expect(session.phase == .idle)
        #expect(!session.hasSource)
        #expect(!session.isWorking)
        #expect(!session.canProceed)
    }

    @Test("★ 붙여넣기: start → reading(일하는 중) → 받으면 미리보기, 인코딩 확인 없음(비ASCII여도)")
    func pasteGoesStraightToPreview() throws {
        var session = PackImportSession()
        let run = try required(session.start(.paste(phrasesCSV)))
        #expect(session.phase == .reading)
        #expect(session.isWorking)
        #expect(session.sourceKind == .paste)
        #expect(run.source == .paste(phrasesCSV))
        #expect(run.options == PackImportOptions())
        let outcome1 = session.receive(PackImportSession.compute(run, library: nil))
        #expect(outcome1)
        let preview = try #require(session.preview)
        #expect(preview.importCount == 2)
        #expect(preview.draft.skipped.isEmpty)
        #expect(!session.isWorking)
        #expect(session.canProceed)
    }

    @Test("BOM 있는 UTF-8 파일·ASCII만 든 파일은 글자 확인 없이 미리보기(R18 — BOM 없는 비ASCII만 확인)",
          arguments: [Data([0xEF, 0xBB, 0xBF]) + Data(numberedCSV.utf8), Data("trigger,body\nhi,hello\n".utf8)])
    func noReviewWhenUnambiguous(_ data: Data) {
        let session = started(.file(data))
        #expect(session.preview != nil)
        #expect(session.lastReview == nil)
    }

    @Test("★ R18 — BOM 없는 비ASCII 파일은 글자 확인부터. 「다음」을 눌러야 미리보기")
    func bomlessNonASCIIAsksFirst() throws {
        var session = started(.file(Data(numberedCSV.utf8)))
        let review = try #require(session.review)
        #expect(review.selected == .utf8)
        #expect(review.utf8.isReadable)
        #expect(review.recordCount == 2)
        #expect(!session.canProceed)
        session.confirmEncoding()
        let preview = try #require(session.preview)
        #expect(preview.importCount == 2)
        #expect(session.canProceed)
    }

    @Test("★ CP949 파일 — 자동은 한국어(CP949)를 고르고 UTF-8로는 몇 줄이 깨지는지 센다")
    func cp949FileAutoSelected() throws {
        var session = started(.file(cp949(phrasesCSV)))
        let review = try #require(session.review)
        #expect(review.selected == .cp949)
        #expect(review.cp949.isReadable)
        #expect(!review.utf8.isReadable)
        #expect(review.utf8.failedLines == 3)                 // 머리글·두 행 — 셋 다 한글
        #expect(review.cp949.samples.first == "단축어")
        session.confirmEncoding()
        #expect(session.preview?.draft.entries.map(\.title) == ["회사 주소", "새해 인사"])
    }

    @Test("★ 고른 방식으로 읽을 수 없으면 「다음」이 먹지 않는다 — 글자 확인에 머문다")
    func unreadableChoiceBlocksConfirm() throws {
        var session = started(.file(cp949(phrasesCSV)))
        drive(&session, session.chooseEncoding(.utf8))
        let review = try #require(session.review)
        #expect(review.selected == .utf8)
        #expect(!review.utf8.isReadable)
        session.confirmEncoding()
        #expect(session.review != nil)
        #expect(!session.canProceed)
    }

    @Test("구분자 후보가 둘이면 고르기 → 고른 구분자로 원본에서 다시 → 미리보기 (5-2 #3)")
    func chooseDelimiter() throws {
        var session = started(.paste(ambiguousText))
        #expect(session.phase == .delimiter([.comma, .semicolon]))
        let run = try required(session.chooseDelimiter(.semicolon))
        #expect(run.source == .paste(ambiguousText))
        #expect(run.options.delimiter == .semicolon)
        drive(&session, run)
        #expect(session.preview?.draft.delimiter == .semicolon)
        #expect(session.preview?.draft.entries.map(\.triggers) == [["d"]])
    }

    @Test("미리보기에서 구분자를 바꾸면 원본에서 다시 읽는다 — 인코딩 선택은 그대로 (5-2 #4)")
    func manualDelimiterFromPreview() throws {
        var session = started(.paste(ambiguousText))
        drive(&session, session.chooseDelimiter(.semicolon))
        // 같은 구분자는 다시 돌리지 않는다
        let outcome2 = session.chooseDelimiter(.semicolon)
        #expect(outcome2 == nil)
        let run = try required(session.chooseDelimiter(.comma))
        #expect(run.source == .paste(ambiguousText))
        #expect(run.options == PackImportOptions(encoding: .automatic, delimiter: .comma))
        drive(&session, run)
        #expect(session.preview?.draft.delimiter == .comma)
    }

    @Test("★ 구조 오류는 전체 거부 — 원본을 바로 비운다")
    func structuralFailureClearsSource() {
        let session = started(.paste("번호,제목,본문\n1,\"닫지 않음,본문\n"))
        guard case .structural(.quote(let quote))? = session.problem else {
            Issue.record("quote 오류여야 한다: \(session.phase)")
            return
        }
        #expect(quote.kind == .unterminated)
        #expect(!session.hasSource)
        #expect(!session.canProceed)
    }

    @Test("★ 유효 행 0 — 미리보기가 아니라 거부(영구 비활성), 건너뛴 이유는 들고 간다 (5-5·AC-19)")
    func noValidRecords() throws {
        var session = started(.paste("번호,제목,본문\n0,제목,본문\n,제목,본문\n"))
        guard case .noValidRecords(let skipped)? = session.problem else {
            Issue.record("유효 0이어야 한다: \(session.phase)")
            return
        }
        #expect(skipped.map(\.reason) == [.numberOutOfRange, .missingNumber])
        #expect(!session.canProceed)
        session.confirmPartialImport()
        #expect(!session.canProceed)
    }

    @Test("★ 검증 F-7 — 유효 0 거부 값은 건너뛴 위치·사유만 든다: 파일의 `#이름`·`#권리`·`#틀`·본문이 오류 값 어디에도 없다(AC-34)")
    func noValidRecordsCarriesNoContent() throws {
        let marker = "표식글자"
        let text = "#이름,\(marker)이름\n#권리,\(marker)권리\n#틀,\(marker){n}번\n번호,제목,본문\n0,\(marker)제목,\(marker)본문\n"
        let session = started(.paste(text))
        guard case .noValidRecords(let skipped)? = session.problem else {
            Issue.record("유효 0이어야 한다: \(session.phase)")
            return
        }
        #expect(skipped.map(\.reason) == [.numberOutOfRange])
        let draft = try ImportHelper.draft(text)
        #expect(draft.meta.name == "\(marker)이름", "초안에는 메타가 있다 — 오류 값이 그것을 옮기지 않는지 본다")
        #expect(skipped == draft.skipped)
        for dumped in [String(describing: session.phase), String(reflecting: session.phase)] {
            #expect(!dumped.contains(marker), "\(dumped)")
        }
    }

    @Test("★ R10 — 건너뜀 50% 이상은 자동 진행 금지, 명시 확인 뒤에만 진행 (AC-19)",
          arguments: [(1, 1, true), (2, 1, false), (1, 3, true), (3, 2, false)])
    func skipRatioGate(accepted: Int, skipped: Int, needsConfirmation: Bool) throws {
        let rows = (0..<accepted).map { "\($0 + 1),제목,본문" } + (0..<skipped).map { _ in "0,제목,본문" }
        var session = started(.paste((["번호,제목,본문"] + rows).joined(separator: "\n")))
        let preview = try #require(session.preview)
        #expect(preview.draft.requiresConfirmation == needsConfirmation)
        #expect(session.canProceed == !needsConfirmation)
        session.confirmPartialImport()
        #expect(session.canProceed)
        #expect(session.partialImportConfirmed == needsConfirmation)
    }

    @Test("구분자를 바꾸면 부분 가져오기 확인을 다시 받는다(결과가 바뀐다)")
    func partialConfirmationResetsOnRerun() throws {
        // 쉼표로 읽으면 둘째 행의 본문이 비어 절반을 건너뛰고, 세미콜론으로 읽으면 둘 다 받는다
        var session = started(.paste(ambiguousText + "\r\nx,,y;q;w"))
        drive(&session, session.chooseDelimiter(.comma))
        #expect(session.preview?.draft.requiresConfirmation == true)
        session.confirmPartialImport()
        #expect(session.partialImportConfirmed)
        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(!session.partialImportConfirmed)
        #expect(session.preview?.draft.requiresConfirmation == false)
        #expect(session.canProceed)
    }

    @Test("단계에 맞지 않는 동작은 아무 일도 하지 않는다")
    func wrongPhaseIsNoOp() throws {
        var session = PackImportSession()
        let outcome3 = session.chooseEncoding(.cp949)
        #expect(outcome3 == nil)
        let outcome4 = session.chooseDelimiter(.tab)
        #expect(outcome4 == nil)
        session.confirmEncoding()
        session.reviewEncodingAgain()
        #expect(session.phase == .idle)

        session = started(.paste(phrasesCSV))
        let before = session
        let outcome5 = session.chooseEncoding(.cp949)          // 붙여넣기엔 인코딩 단계가 없다
        #expect(outcome5 == nil)
        session.confirmEncoding()
        session.reviewEncodingAgain()
        #expect(session == before)

        // 일하는 중에는 다른 선택을 받지 않는다
        var working = started(.paste(ambiguousText))
        _ = try required(working.chooseDelimiter(.comma))
        let outcome6 = working.chooseDelimiter(.semicolon)
        #expect(outcome6 == nil)
    }
}

// MARK: - AC-18 원본에서 다시

@Suite("외부 채움글 1-c 4단계 — 인코딩·구분자를 바꾸면 원본에서 전부 다시 (AC-18)")
struct PackImportSessionRerunTests {

    @Test("★ C3 A9 — 두 방식 모두 읽혀 확인 화면, 표본은 같은 자리를 두 방식으로 (é / 챕)")
    func bothReadable() throws {
        let session = started(.file(cafeBytes))
        let review = try #require(session.review)
        #expect(review.selected == .utf8)
        #expect(review.utf8.isReadable && review.cp949.isReadable)
        #expect(review.utf8.samples == ["Caf\u{E9} meeting"])
        #expect(review.cp949.samples == ["Caf챕 meeting"])
    }

    @Test("★ 고를 때마다 Run은 **처음 받은 원본 바이트 그대로**를 들고, 결과는 그 바이트를 새로 읽은 것과 같다")
    func everyRunCarriesOriginalBytes() throws {
        var session = started(.file(cafeBytes))
        var runs: [PackImportSession.Run] = []

        let toCP949 = try required(session.chooseEncoding(.cp949))
        runs.append(toCP949)
        drive(&session, toCP949)
        #expect(session.review?.selected == .cp949)
        session.confirmEncoding()
        let viaCP949 = try #require(session.preview)
        #expect(viaCP949.draft.entries.map(\.body) == ["Caf챕 meeting"])
        guard case .draft(let direct) = try PackImporter.read(cafeBytes, options: PackImportOptions(encoding: .cp949)) else {
            Issue.record("직접 읽기가 초안이 아니다")
            return
        }
        #expect(viaCP949.draft == direct)

        // 미리보기에서 글자 방식을 다시 고르면 확인 화면으로 — UTF-8로 되돌린 결과는 CP949로 읽은 글자를 다시 쓴 것이 아니다
        session.reviewEncodingAgain()
        #expect(session.review?.selected == .cp949)
        let toUTF8 = try required(session.chooseEncoding(.utf8))
        runs.append(toUTF8)
        drive(&session, toUTF8)
        session.confirmEncoding()
        #expect(session.preview?.draft.entries.map(\.body) == ["Caf\u{E9} meeting"])

        #expect(runs.allSatisfy { $0.source == .file(cafeBytes) })
    }

    @Test("★ 인코딩을 바꾸면 고른 구분자도 버린다 — 구분자 판정부터 다시(5-3b #6)")
    func encodingChangeResetsDelimiter() throws {
        // 비ASCII를 넣어 글자 확인이 뜨게 한다(첫 셀은 「단축어」)
        var session = started(.file(Data(ambiguousText.utf8)))
        session.confirmEncoding()
        #expect(session.phase == .delimiter([.comma, .semicolon]))
        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(session.options.delimiter == .semicolon)
        session.reviewEncodingAgain()
        let run = try required(session.chooseEncoding(.cp949))
        #expect(run.options == PackImportOptions(encoding: .cp949, delimiter: nil))
        #expect(run.source == .file(Data(ambiguousText.utf8)))
    }

    @Test("★ 검증 F-2 (AC-18) — 칸 나누기를 바꿔도 **고른 글자 방식은 그대로**: CP949로 확정한 é/챕 파일은 구분자를 바꿔 다시 읽어도 「챕」")
    func delimiterChangeKeepsChosenEncoding() throws {
        // 두 방식 모두 읽히고(C3 A9 — é/챕) 쉼표·세미콜론 둘 다 머리글을 인정하는 표 — UTF-8이 기본(자동)이라 CP949는 사용자가 고른 값이다
        let bytes = Data("trigger,body,z;trigger;body\r\ncafe,Caf\u{E9},c;cafe;Caf\u{E9} meeting\r\n".utf8)
        var session = started(.file(bytes))
        #expect(session.review?.selected == .utf8 && session.review?.bothReadable == true)
        drive(&session, session.chooseEncoding(.cp949))
        session.confirmEncoding()
        #expect(session.phase == .delimiter([.comma, .semicolon]))

        let toSemicolon = try required(session.chooseDelimiter(.semicolon))
        #expect(toSemicolon.options == PackImportOptions(encoding: .cp949, delimiter: .semicolon))
        #expect(toSemicolon.source == .file(bytes), "원본 바이트에서 다시")
        drive(&session, toSemicolon)
        #expect(session.preview?.draft.entries.map(\.body) == ["Caf챕 meeting"])

        let toComma = try required(session.chooseDelimiter(.comma))       // 미리보기에서 바꾸기(5-2 #4)
        #expect(toComma.options == PackImportOptions(encoding: .cp949, delimiter: .comma))
        drive(&session, toComma)
        #expect(session.preview?.draft.entries.map(\.body) == ["Caf챕"], "UTF-8로 조용히 돌아가면 「Café」가 된다")
        #expect(session.preview?.draft.encoding == .cp949)
    }

    @Test("★ 검증 F-3 V03 — 「글자 방식 다시 고르기」 뒤 다른 방식을 고르면 확인 화면을 **다시** 거친다 — 못 읽는 방식으로 바로 거부(원본 잃음)되지 않는다")
    func reviewAgainRequiresConfirmationAgain() throws {
        var session = started(.file(cp949(phrasesCSV)))
        #expect(session.review?.selected == .cp949)
        session.confirmEncoding()
        #expect(session.preview != nil)

        session.reviewEncodingAgain()
        drive(&session, session.chooseEncoding(.utf8))                  // CP949 파일을 UTF-8로 — 못 읽는다
        let review = try #require(session.review, "확인 화면으로 와야 한다: \(session.phase)")
        #expect(review.selected == .utf8 && !review.utf8.isReadable)
        #expect(session.hasSource, "거부로 끝나지 않았다 — 원본이 남아 다른 쪽을 다시 고를 수 있다")
        session.confirmEncoding()                                        // 고른 쪽이 깨져 「다음」이 먹지 않는다
        #expect(session.review != nil)

        drive(&session, session.chooseEncoding(.cp949))
        #expect(session.review?.selected == .cp949, "돌아와도 확인 화면에서 「다음」을 기다린다")
        session.confirmEncoding()
        #expect(session.preview?.draft.entries.map(\.triggers) == [["주소"], ["새해인사"]])
    }

    @Test("글자 확인으로 돌아갔다가 그대로 「다음」 — 같은 결과로 돌아온다(다시 읽지 않는다)")
    func reviewAgainAndBack() throws {
        var session = started(.file(Data(numberedCSV.utf8)))
        session.confirmEncoding()
        let before = try #require(session.preview)
        session.reviewEncodingAgain()
        #expect(session.review != nil)
        #expect(!session.isWorking)
        session.confirmEncoding()
        #expect(session.preview == before)
    }
}

// MARK: - 취소 · 늦게 온 결과

@Suite("외부 채움글 1-c 4단계 — 취소·늦은 결과")
struct PackImportSessionCancelTests {

    @Test("★ 읽는 중 취소 — idle로, 원본을 비우고, 늦게 온 결과는 버린다")
    func cancelWhileReading() throws {
        var session = PackImportSession()
        let run = try required(session.start(.paste(phrasesCSV)))
        session.cancel()
        #expect(session.phase == .idle)
        #expect(!session.hasSource)
        #expect(!session.isWorking)
        let outcome7 = session.receive(PackImportSession.compute(run, library: nil))
        #expect(!outcome7)
        #expect(session.phase == .idle)
    }

    @Test("★ 파일을 여는 중 취소 — 나중에 도착한 바이트를 받지 않는다(메모리에 남기지 않는다)")
    func cancelWhileLoadingFile() {
        var session = PackImportSession()
        let ticket = session.begin(.file)
        #expect(session.phase == .reading)
        session.cancel()
        let outcome8 = session.load(.file(Data(numberedCSV.utf8)), ticket: ticket)
        #expect(outcome8 == nil)
        #expect(!session.hasSource)
        session.failToLoad(.fileUnreadable, ticket: ticket)
        #expect(session.phase == .idle)
    }

    @Test("새 가져오기를 시작하면 앞 가져오기의 표는 무효 — 옛 ticket으로는 싣지 못한다")
    func newBeginInvalidatesOldTicket() {
        var session = PackImportSession()
        let old = session.begin(.file)
        let new = session.begin(.file)
        let outcome9 = session.load(.file(Data(numberedCSV.utf8)), ticket: old)
        #expect(outcome9 == nil)
        let outcome10 = session.load(.file(Data(numberedCSV.utf8)), ticket: new)
        #expect(outcome10 != nil)
    }

    @Test("★ 선택을 빨리 두 번 바꾸면 앞 결과는 버리고 마지막 것만 받는다")
    func staleRunIgnored() throws {
        var session = started(.file(cafeBytes))
        let first = try required(session.chooseEncoding(.cp949))
        let firstResult = PackImportSession.compute(first, library: nil)
        let outcome11 = session.receive(firstResult)
        #expect(outcome11)
        let second = try required(session.chooseEncoding(.utf8))
        let outcome12 = session.receive(firstResult)               // 이미 받은(옛) 결과를 다시 넣어도 무시
        #expect(!outcome12)
        #expect(session.isWorking)
        let outcome13 = session.receive(PackImportSession.compute(second, library: nil))
        #expect(outcome13)
        #expect(session.review?.selected == .utf8)
    }

    @Test("읽기 실패(파일을 열지 못함)는 그 ticket일 때만 거부로")
    func failToLoad() {
        var session = PackImportSession()
        let ticket = session.begin(.file)
        session.failToLoad(.fileUnreadable, ticket: ticket)
        #expect(session.phase == .failed(.fileUnreadable))
        #expect(!session.isWorking)
    }

    @Test("미리보기·거부에서 취소해도 원본을 비운다")
    func cancelClearsAfterPreview() {
        var session = started(.paste(phrasesCSV))
        #expect(session.hasSource)
        session.cancel()
        #expect(!session.hasSource)
        #expect(session.lastReview == nil)
        #expect(session.options == PackImportOptions())
    }
}

// MARK: - 상한

@Suite("외부 채움글 1-c 4단계 — 크기·행 상한")
struct PackImportSessionLimitTests {

    @Test("★ 파일·붙여넣기가 바이트 상한을 넘으면 계산 없이 바로 거부 — 원본을 들고 있지 않는다")
    func byteCapBeforeCompute() {
        var file = PackImportSession()
        let ticket = file.begin(.file)
        let outcome14 = file.load(.file(Data(count: PackLimits.fileBytes + 1)), ticket: ticket)
        #expect(outcome14 == nil)
        #expect(file.phase == .failed(.structural(.fileTooLarge)))
        #expect(!file.hasSource)

        var paste = PackImportSession()
        let outcome15 = paste.start(.paste(String(repeating: "가", count: PackLimits.fileBytes / 3 + 1)))
        #expect(outcome15 == nil)
        #expect(paste.phase == .failed(.structural(.fileTooLarge)))
        #expect(!paste.hasSource)
    }

    @Test("경계 — 정확히 상한이면 받는다")
    func byteCapBoundary() {
        var session = PackImportSession()
        let ticket = session.begin(.file)
        let outcome16 = session.load(.file(Data(count: PackLimits.fileBytes)), ticket: ticket)
        #expect(outcome16 != nil)
    }

    @Test("★ 물리 줄·데이터 행 상한은 전체 거부로 끝난다(일부만 받지 않는다)")
    func lineAndRecordCaps() {
        let lines = String(repeating: "\n", count: PackLimits.physicalLines + 1)
        #expect(started(.paste("번호,제목,본문" + lines + "1,a,b")).problem == .structural(.tooManyLines))

        let rows = (1...PackLimits.dataRecords + 1).map { "\($0 % 9_000 + 1),제목,본문" }.joined(separator: "\n")
        #expect(started(.paste("번호,제목,본문\n" + rows)).problem == .structural(.tooManyRecords))
    }
}

// MARK: - 글자 확인 화면 값 (4-B·4-C)

@Suite("외부 채움글 1-c 4단계 — 글자 확인 값 (5-3b ⑤)")
struct PackEncodingReviewTests {

    @Test("행 수·여러 줄 본문 수는 고른 방식으로 읽은 표에서")
    func counts() throws {
        let text = "단축어,본문\n가,\"첫 줄\n둘째 줄\"\n나,한 줄\n다,\"셋\n넷\"\n"
        let session = started(.file(Data(text.utf8)))
        let review = try #require(session.review)
        #expect(review.recordCount == 3)
        #expect(review.multilineBodyCount == 2)
    }

    @Test("표본은 비ASCII가 든 칸의 처음 세 개 — 따옴표·앞뒤 공백을 떼고 길면 자른다")
    func samples() throws {
        let long = String(repeating: "긴", count: 60)
        let text = "trigger,body\nhi,\" 새해 인사 \"\nyo,회사 주소\nok,\(long)\nno,또 하나\n"
        let review = try #require(started(.file(Data(text.utf8))).review)
        #expect(review.utf8.samples.count == 3)
        #expect(review.utf8.samples[0] == "새해 인사")
        #expect(review.utf8.samples[1] == "회사 주소")
        #expect(review.utf8.samples[2] == String(repeating: "긴", count: PackEncodingReview.sampleLength) + "…")
    }

    @Test("NUL이 든 파일·두 방식 모두 못 읽는 파일은 확인 화면 없이 거부(지원하지 않는 인코딩)",
          arguments: [Data([0x41, 0x00, 0xEA, 0xB0, 0x80]), Data([0x41, 0x2C, 0x80, 0x80, 0x0A])])
    func unreadableEverywhere(_ data: Data) {
        let session = started(.file(data))
        #expect(session.problem == .structural(.unsupportedEncoding))
        #expect(session.lastReview == nil)
    }
}
