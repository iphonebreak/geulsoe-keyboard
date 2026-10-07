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

/// 칸 나누기 되돌릴 곳 — 읽지 못한 것 · 돌아갈 곳(nil = 고르기 화면)
private func fallback(_ failed: CSVDelimiter, back previous: CSVDelimiter?) -> PackImportSession.DelimiterFallback {
    PackImportSession.DelimiterFallback(failed: failed, previous: previous)
}

/// 표본의 칸 글자만 — 정보 줄 여부는 따로 본다
extension PackEncodingReview.Reading {
    var texts: [String?] { samples.map { $0?.text } }
}

private func cell(_ text: String) -> PackEncodingReview.Sample? { PackEncodingReview.Sample(meta: nil, text: text) }
private func meta(_ field: PackMetaField, _ text: String) -> PackEncodingReview.Sample? { PackEncodingReview.Sample(meta: field, text: text) }

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
        #expect(review.cp949.texts.first == "단축어")
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

// MARK: - R29 칸 나누기 — 애매할 때만 고르기, 실패하면 그 자리에서 되돌리기

/// 쉼표·세미콜론 둘 다 채택되는 표인데 **세미콜론으로 끝까지 읽으면 받을 행이 0**(본문이 빈다) — 후보 시험은 통과하고 본 읽기에서 실패한다
private let semicolonEmptiesBodies = "단축어,본문,z;trigger;body\r\na,b,c;d;"

/// 쉼표·세미콜론 둘 다 채택되는데 **세미콜론으로는 시험 창(비지 않은 32개) 밖에서 따옴표 오류** — 본 읽기에서 구조 오류로 전체 거부
private let semicolonQuoteErrorLate: String = {
    var lines = ["단축어,본문,z;trigger;body"]
    for index in 1...40 { lines.append("a\(index),b\(index),c;d\(index);e\(index)") }
    lines.append("a41,b41,c;\"q\"x;e41")       // 쉼표로는 셋째 칸 가운데의 따옴표(글자), 세미콜론으로는 닫는 따옴표 뒤 글자
    return lines.joined(separator: "\r\n")
}()

@Suite("외부 채움글 1-c 4단계 — R29 칸 나누기: 애매할 때만 고르기 · 실패하면 그 자리에서 되돌리기")
struct PackImportDelimiterFallbackTests {

    @Test("★ 시험 표가 뜻대로다 — 두 표 모두 자동 판정은 쉼표·세미콜론 둘, 쉼표로는 읽히고 세미콜론으로는 실패한다")
    func fixturesBehave() throws {
        for text in [semicolonEmptiesBodies, semicolonQuoteErrorLate] {
            #expect(try PackImporter.read(text: text) == .chooseDelimiter([.comma, .semicolon]))
            #expect(try ImportHelper.draft(text, delimiter: .comma).isImportable)
        }
        #expect(try ImportHelper.draft(semicolonEmptiesBodies, delimiter: .semicolon).isImportable == false)
        #expect(throws: PackImportFailure.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 42, line: 42))) {
            try PackImporter.read(text: semicolonQuoteErrorLate, delimiter: .semicolon)
        }
    }

    @Test("★ 하나로 정해지는 표 — 미리보기의 칸 나누기 후보가 하나뿐(화면은 고르기를 보이지 않는다)", arguments: [
        PackImportSource.paste("단축어,본문\n인사,안녕하세요\n"), .paste("단축어\t본문\n인사\t안녕, 반가워요\n"), .file(cafeBytes)
    ])
    func unambiguousHidesChoice(_ source: PackImportSource) throws {
        var session = started(source)
        session.confirmEncoding()                                   // 글자 확인이 있는 파일이면 넘긴다(없으면 아무 일 없음)
        let preview = try #require(session.preview)
        #expect(preview.draft.delimiterCandidates == [preview.draft.delimiter])
        #expect(!preview.offersDelimiterChoice)
    }

    @Test("★ 애매한 표 — 고르기 화면에서 고른 뒤 미리보기에도 고르기가 있다(후보 둘만)")
    func ambiguousKeepsChoice() throws {
        var session = started(.paste(ambiguousText))
        drive(&session, session.chooseDelimiter(.semicolon))
        let preview = try #require(session.preview)
        #expect(preview.draft.delimiter == .semicolon)
        #expect(preview.draft.delimiterCandidates == [.comma, .semicolon] && preview.offersDelimiterChoice)
    }

    @Test("★ 미리보기에서 바꾼 구분자로 실패 → 거부 화면이지만 원본을 지니고, 직전 구분자로 되돌리면 원본에서 다시 읽어 같은 미리보기 (AC-18)",
          arguments: [semicolonEmptiesBodies, semicolonQuoteErrorLate])
    func failedChangeFromPreviewReverts(_ text: String) throws {
        var session = started(.paste(text))
        drive(&session, session.chooseDelimiter(.comma))
        let before = try #require(session.preview)

        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(session.problem != nil)
        #expect(session.hasSource, "되돌릴 수 있으니 원본을 비우지 않는다")
        #expect(session.delimiterFallback == fallback(.semicolon, back: .comma))
        #expect(!session.canProceed)

        let revert = try required(session.revertDelimiter())
        #expect(run(revert, carries: text, delimiter: .comma))
        // 일하는 동안 화면은 그대로(버튼이 사라지지 않고 꺼진다) — 두 번 누르면 무시
        #expect(session.isWorking && session.delimiterFallback == fallback(.semicolon, back: .comma))
        let again = session.revertDelimiter()
        #expect(again == nil)
        drive(&session, revert)
        #expect(session.preview == before, "되돌린 결과 = 원본을 쉼표로 처음부터 읽은 것")
        #expect(session.delimiterFallback == nil && session.hasSource)
    }

    @Test("★ 고르기 화면에서 고른 구분자로 실패 → 되돌리면 고르기 화면으로(자동 판정부터 다시)")
    func failedChoiceRevertsToChooser() throws {
        var session = started(.paste(semicolonEmptiesBodies))
        #expect(session.phase == .delimiter([.comma, .semicolon]))
        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(session.problem == .noValidRecords([SkippedRecord(record: 2, line: 2, reason: .emptyBody)]))
        #expect(session.delimiterFallback == fallback(.semicolon, back: nil) && session.hasSource)

        let revert = try required(session.revertDelimiter())
        #expect(revert.options == PackImportOptions(encoding: .automatic, delimiter: nil))
        drive(&session, revert)
        #expect(session.phase == .delimiter([.comma, .semicolon]))
        drive(&session, session.chooseDelimiter(.comma))
        #expect(session.preview?.draft.delimiter == .comma)
    }

    @Test("★ 고른 글자 방식은 되돌려도 그대로 — CP949로 확정한 파일의 칸 나누기 실패를 되돌리면 CP949로 원본에서 다시 읽는다")
    func revertKeepsChosenEncoding() throws {
        // 두 방식 모두 읽히고(é/챕) 쉼표·세미콜론 둘 다 채택 — 세미콜론으로는 본문이 빈다. UTF-8이 자동이라 CP949는 사용자가 고른 값이다
        let bytes = Data("trigger,body,z;trigger;body\r\ncafe,Caf\u{E9},c;cafe;\r\n".utf8)
        var session = started(.file(bytes))
        drive(&session, session.chooseEncoding(.cp949))
        session.confirmEncoding()
        #expect(session.phase == .delimiter([.comma, .semicolon]))
        drive(&session, session.chooseDelimiter(.comma))
        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(session.delimiterFallback == fallback(.semicolon, back: .comma))
        let revert = try required(session.revertDelimiter())
        #expect(revert.options == PackImportOptions(encoding: .cp949, delimiter: .comma))
        #expect(revert.source == .file(bytes))
        drive(&session, revert)
        #expect(session.preview?.draft.entries.map(\.body) == ["Caf챕"], "UTF-8로 조용히 돌아가면 「Café」가 된다")
    }

    @Test("★ 칸 나누기를 바꾼 것이 아닌 거부는 지금처럼 끝 — 되돌릴 것이 없고 원본을 비운다", arguments: [
        "번호,제목,본문\n1,\"닫지 않음,본문\n", "번호,제목,본문\n0,제목,본문\n", "foo,bar\n1,2\n"
    ])
    func otherFailuresHaveNoFallback(_ text: String) {
        var session = started(.paste(text))
        #expect(session.problem != nil)
        #expect(session.delimiterFallback == nil && !session.hasSource)
        let revert = session.revertDelimiter()
        #expect(revert == nil)
    }

    @Test("되돌릴 수 있는 거부에서도 취소하면 원본·되돌릴 곳을 비운다 · 새로 시작해도 비운다")
    func cancelClearsFallback() throws {
        var session = started(.paste(semicolonEmptiesBodies))
        drive(&session, session.chooseDelimiter(.semicolon))
        #expect(session.delimiterFallback == fallback(.semicolon, back: nil))
        session.cancel()
        #expect(session.delimiterFallback == nil && !session.hasSource && session.phase == .idle)

        session = started(.paste(semicolonEmptiesBodies))
        drive(&session, session.chooseDelimiter(.semicolon))
        _ = session.begin(.paste)
        #expect(session.delimiterFallback == nil && !session.hasSource)
    }

    @Test("되돌리기는 그 거부 화면에서만 — 미리보기·고르기·글자 확인에서는 아무 일도 없다")
    func revertOnlyFromFallbackFailure() throws {
        var session = started(.paste(ambiguousText))
        let fromChooser = session.revertDelimiter()
        #expect(fromChooser == nil)
        drive(&session, session.chooseDelimiter(.comma))
        let fromPreview = session.revertDelimiter()
        #expect(fromPreview == nil)
        var encoding = started(.file(cafeBytes))
        let fromEncoding = encoding.revertDelimiter()
        #expect(fromEncoding == nil)
    }

    @Test("늦게 온 실패는 받지 않는다 — 바꾼 뒤 곧바로 취소하면 되돌릴 곳도 생기지 않는다")
    func staleFailureIgnored() throws {
        var session = started(.paste(semicolonEmptiesBodies))
        drive(&session, session.chooseDelimiter(.comma))
        let toSemicolon = try required(session.chooseDelimiter(.semicolon))
        session.cancel()
        let received = session.receive(PackImportSession.compute(toSemicolon, library: nil))
        #expect(!received)
        #expect(session.delimiterFallback == nil && session.phase == .idle)
    }

    /// 되돌리기 Run이 **처음 받은 원본 그대로**와 그 구분자를 들었는지
    private func run(_ run: PackImportSession.Run, carries text: String, delimiter: CSVDelimiter) -> Bool {
        run.source == .paste(text) && run.options.delimiter == delimiter
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
        #expect(review.utf8.texts == ["Caf\u{E9} meeting"])
        #expect(review.cp949.texts == ["Caf챕 meeting"])
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
        #expect(review.utf8.texts[0] == "새해 인사")
        #expect(review.utf8.texts[1] == "회사 주소")
        #expect(review.utf8.texts[2] == String(repeating: "긴", count: PackEncodingReview.sampleLength) + "…")
        #expect(review.utf8.samples.allSatisfy { $0?.meta == nil }, "데이터 칸은 정보 줄이 아니다")
    }

    // MARK: R29 — 정보 줄은 「이름 : …」 꼴로, 한 줄이 표본 하나

    @Test("★ R29 — 머리글 위 정보 줄은 원문(`#이름,…,`)이 아니라 칸과 값으로: 한 줄 = 표본 하나(줄을 더 만들지 않는다)")
    func metaLinesBecomeLabeledSamples() throws {
        let text = "#이름,사자성어 넘버스,\n#틀,넘버스성어 {n}번\n#출처,자체 작성\n번호,제목,본문\n1,가나,다라\n"
        let review = try #require(started(.file(Data(text.utf8))).review)
        #expect(review.utf8.samples == [meta(.name, "사자성어 넘버스"), meta(.template, "넘버스성어 {n}번"), meta(.license, "자체 작성")])
        #expect(review.utf8.samples.map(PackImportCopy.sampleLine) == ["이름 : 사자성어 넘버스", "틀 : 넘버스성어 {n}번", "출처 : 자체 작성"])
    }

    @Test("★ R29 — 옛 `#권리` 줄도 「출처 : …」 · 따옴표로 감싼 키·값 · 틀 별칭은 「, 」로 잇는다 · 끝의 빈 칸(시트 폭 패딩)은 뺀다")
    func metaLineVariants() throws {
        let text = "\"#권리\",\"글쇠, 자체 작성\",,\n#틀,사자성어 {n}번,성어 {n}번,,\n단축어,본문\n가,나\n"
        let review = try #require(started(.file(Data(text.utf8))).review)
        #expect(review.utf8.samples.map(PackImportCopy.sampleLine)
                    == ["출처 : 글쇠, 자체 작성", "틀 : 사자성어 {n}번, 성어 {n}번", "단축어"])
    }

    @Test("R29 — 정보 줄은 키 뒤의 첫 구분자로만 나눈다 — 값 안의 다른 기호(`;`·쉼표)는 글자 그대로")
    func metaLineOwnSeparator() throws {
        let comma = try #require(started(.file(Data("#출처,가; 나\n단축어,본문\n".utf8))).review)
        #expect(comma.utf8.samples.first == meta(.license, "가; 나"))
        let semicolon = try #require(started(.file(Data("#출처;가, 나;;\n단축어;본문\n".utf8))).review)
        #expect(semicolon.utf8.samples.first == meta(.license, "가, 나"))
    }

    @Test("R29 — 정보 줄 표본 한 줄과 데이터 칸이 섞여 처음 세 개 · 값이 길면 값을 자른다")
    func metaAndCellsMixed() throws {
        let long = String(repeating: "긴", count: 60)
        let text = "#이름,\(long)\n단축어,본문\n가나,다라\n마바,사아\n"
        let review = try #require(started(.file(Data(text.utf8))).review)
        #expect(review.utf8.samples == [meta(.name, String(repeating: "긴", count: PackEncodingReview.sampleLength) + "…"), cell("단축어"), cell("본문")])
    }

    @Test("R29 — 머리글 뒤의 `#`(본문 칸)는 정보 줄이 아니다 · 모르는 `#` 키는 칸 이름 없이 원문 그대로(파서가 따로 거부한다)")
    func notMetaLines() throws {
        let afterHeader = try #require(started(.file(Data("trigger,body\nhi,#해시 본문\n".utf8))).review)
        #expect(afterHeader.utf8.samples == [cell("#해시 본문")])
        let unknown = try #require(started(.file(Data("#메모,값 하나,,\n단축어,본문\n가,나\n".utf8))).review)
        #expect(unknown.utf8.samples.first == cell("#메모,값 하나"))
    }

    @Test("★ R29 — 같은 자리를 두 방식으로(4-C): CP949 파일의 정보 줄은 한국어(CP949)로 「이름 : …」, UTF-8로는 읽을 수 없는 칸")
    func metaLineSamePlaceBothEncodings() throws {
        let review = try #require(started(.file(cp949("#이름,사자성어 넘버스\n번호,제목,본문\n1,가,나\n"))).review)
        #expect(review.selected == .cp949)
        #expect(review.cp949.samples.first == meta(.name, "사자성어 넘버스"))
        #expect(review.utf8.samples.first == .some(nil))
        #expect(PackImportCopy.sampleLine(nil) == PackImportCopy.unreadableSample)
    }

    @Test("NUL이 든 파일·두 방식 모두 못 읽는 파일은 확인 화면 없이 거부(지원하지 않는 인코딩)",
          arguments: [Data([0x41, 0x00, 0xEA, 0xB0, 0x80]), Data([0x41, 0x2C, 0x80, 0x80, 0x0A])])
    func unreadableEverywhere(_ data: Data) {
        let session = started(.file(data))
        #expect(session.problem == .structural(.unsupportedEncoding))
        #expect(session.lastReview == nil)
    }
}
