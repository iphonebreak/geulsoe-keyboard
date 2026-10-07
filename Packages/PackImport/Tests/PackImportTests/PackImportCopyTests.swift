import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 4단계 — 가져오기 문구 표 `PackImportCopy`(계획서 `external-snippet-packs-1c-plan.md` 4-4절 · 5절 4행 ②,
// 시안 `docs/design/external-snippet-packs/index.html` 3-A·3-B·3-E·4-A~4-C·4-E~4-I, 4-G 표). **CSV 전용판**(AC-35 — xlsx 안내 0).
// 사유 → 문구 매핑은 **전부**(새 사유가 생기면 아래 `exhaustive` switch가 컴파일되지 않는다). 오류 문구에 파일 내용·파일 이름이 없다(AC-34).
// 숫자 검사는 1~3단계와 같은 잣대 — 숫자는 위치·개수·필드 상한(편집기가 이미 보이는 값)만 허용한다. U6·금칙어·xlsx(AC-35)는 6단계 `PackCopyLintTests`가 한 곳에서 본다.

// MARK: - 사유 전부

/// 컴파일러가 빠짐을 잡는다 — `PackImportFailure`에 사유를 더하면 이 switch가 깨져 문구 매핑을 같이 더하게 된다
private func exhaustive(_ failure: PackImportFailure) {
    switch failure {
    case .fileTooLarge, .emptyFile, .unsupportedEncoding, .invalidUTF8AfterBOM, .invalidUTF16, .encodingDoesNotMatchBOM, .undecodable,
         .quote, .tooManyLines, .tooManyRecords, .headerNotRecognized, .columnCountMismatch, .duplicateHeader, .duplicateHeaderAlias,
         .mixedModeHeader, .missingRequiredColumn, .tooManyColumns, .metaAfterHeader, .duplicateMeta, .unknownMeta,
         .unsupportedEscapeMeta, .metaValueCount, .metaTooManyCells, .templateInPhrasesMode:
        break
    }
}

private func exhaustive(_ reason: SkipReason) {
    switch reason {
    case .columnCount, .missingNumber, .invalidNumber, .numberOutOfRange, .missingTrigger, .tooManyTriggers, .triggerTooLong,
         .emptyBody, .titleTooLong, .bodyTooLong:
        break
    }
}

/// 위치는 시안 4-F·4-G 예시 값(12번째 항목 · 40번째 줄) — 숫자 검사가 이 둘만 지운다
private let failureTable: [(PackImportFailure, String)] = [
    (.fileTooLarge, "파일이 너무 커요. 항목을 나눠 여러 팩으로 만들어 주세요."),
    (.emptyFile, "파일에 내용이 없어요. 첫 줄에 머리글을 쓰고 항목을 넣어 주세요."),
    (.unsupportedEncoding, "이 파일의 글자 방식은 지원하지 않아요. 「CSV UTF-8」로 저장해 주세요."),
    (.invalidUTF8AfterBOM, "UTF-8이라고 표시된 파일인데 깨진 글자가 있어요. 파일이 손상됐을 수 있어요."),
    (.invalidUTF16, "UTF-16이라고 표시된 파일인데 깨진 글자가 있어요. 파일이 손상됐을 수 있어요. 「CSV UTF-8」로 다시 저장해 주세요."),
    (.encodingDoesNotMatchBOM, "파일이 알리는 글자 방식과 달라요. 파일에 맞는 방식을 골라 주세요."),
    (.undecodable(.utf8), "고른 글자 방식으로는 읽을 수 없어요. 다른 방식을 골라 보세요."),
    (.undecodable(.cp949), "고른 글자 방식으로는 읽을 수 없어요. 다른 방식을 골라 보세요."),
    (.quote(CSVQuoteError(kind: .unterminated, record: 12, line: 40)), "12번째 항목(40번째 줄) 근처에서 따옴표가 닫히지 않았어요."),
    (.quote(CSVQuoteError(kind: .characterAfterClosingQuote, record: 12, line: 40)),
     "12번째 항목(40번째 줄) 근처에서 닫는 따옴표 뒤에 글자가 더 있어요. 칸 안의 따옴표는 두 번(\"\") 써 주세요."),
    (.tooManyLines, "항목이 너무 많아요. 여러 팩으로 나눠 주세요."),
    (.tooManyRecords, "항목이 너무 많아요. 여러 팩으로 나눠 주세요."),
    (.headerNotRecognized, "머리글을 찾지 못했어요. 첫 줄(머리글)을 확인해 주세요."),
    (.columnCountMismatch(record: 12, line: 40), "칸 수가 머리글과 달라요. 12번째 항목(40번째 줄) 근처의 쉼표나 따옴표를 확인해 주세요."),
    (.duplicateHeader, "같은 이름의 열이 두 번 있어요. 하나만 남겨 주세요."),
    (.duplicateHeaderAlias, "같은 뜻의 열이 두 개 있어요(예: 「본문」과 「body」). 하나만 남겨 주세요."),
    (.mixedModeHeader, "「번호」와 「단축어」 열을 함께 쓸 수 없어요. 팩 하나는 한 종류예요."),
    (.missingRequiredColumn, "꼭 필요한 열이 없어요. 「본문」 열과 「번호」나 「단축어」 열을 넣어 주세요."),
    (.tooManyColumns, "칸이 너무 많아요. 필요한 칸만 남겨 주세요."),
    (.metaAfterHeader(record: 12, line: 40), "「#이름」 같은 정보 줄은 머리글 위에 있어야 해요. 정렬하다 아래로 내려갔는지 확인해 주세요."),
    (.duplicateMeta(record: 12, line: 40), "같은 정보 줄(#이름·#틀·#권리)이 두 번 있어요. 하나만 남겨 주세요."),
    (.unknownMeta(record: 12, line: 40), "모르는 정보 줄(#…)이 있어요. 정보 줄은 「#이름」·「#틀」·「#권리」만 쓸 수 있어요."),
    (.unsupportedEscapeMeta(record: 12, line: 40), "「#escape」 줄은 아직 쓸 수 없어요. 그 줄을 지우고 다시 가져와 주세요."),
    (.metaValueCount(record: 12, line: 40), "정보 줄의 칸 수가 맞지 않아요. 「#이름」·「#권리」는 값 하나, 「#틀」은 1~8개예요."),
    (.metaTooManyCells(record: 12, line: 40), "정보 줄의 칸 수가 맞지 않아요. 「#이름」·「#권리」는 값 하나, 「#틀」은 1~8개예요."),
    (.templateInPhrasesMode, "단축어 열이 있는 파일에는 「#틀」 줄을 쓸 수 없어요.")
]

/// 시안 4-F(CSV판) + 계획서 4-4절 「건너뛴 행」 표 — (사유, 고치는 법)
private let skipTable: [(SkipReason, String, String)] = [
    (.columnCount, "칸 수가 머리글과 달라요", "쉼표가 빠졌거나 더 있어요"),
    (.missingNumber, "번호가 비어 있어요", "번호 칸을 채워 주세요"),
    (.invalidNumber, "번호가 1~9999가 아니에요", "번호 칸을 확인해 주세요"),
    (.numberOutOfRange, "번호가 1~9999가 아니에요", "번호 칸을 확인해 주세요"),
    (.missingTrigger, "단축어가 비어 있어요", "단축어 칸을 채워 주세요"),
    (.tooManyTriggers, "단축어가 너무 많아요", "한 항목에 단축어는 10개까지예요"),
    (.triggerTooLong, "단축어가 너무 길어요", "단축어 하나는 40자까지예요"),
    (.emptyBody, "본문이 비어 있어요", "본문을 채워 주세요"),
    (.titleTooLong, "제목이 너무 길어요", "제목은 60자까지예요"),
    (.bodyTooLong, "본문이 너무 길어요", "본문은 한 칸에 3,000자까지예요")
]

private func review(selected: PackEncodingReview.Encoding, utf8Failed: Int, cp949Failed: Int) -> PackEncodingReview {
    PackEncodingReview(selected: selected,
                       utf8: .init(isReadable: utf8Failed == 0, failedLines: utf8Failed, samples: ["새해 인사"]),
                       cp949: .init(isReadable: cp949Failed == 0, failedLines: cp949Failed, samples: ["새해 인사"]),
                       recordCount: 37, multilineBodyCount: 37)
}

// MARK: - 매핑

@Suite("외부 채움글 1-c 4단계 — 가져오기 문구 매핑 (4-4절·시안 4-F·4-G)")
struct PackImportCopyMappingTests {

    @Test("★ PackImportFailure 사유 전부 → 4-G 제목 아래 문구(시안·계획서 4-4절 글자)")
    func everyFailure() {
        for (failure, expected) in failureTable {
            exhaustive(failure)
            #expect(PackImportCopy.failureMessage(.structural(failure), source: .file) == expected, "\(failure)")
        }
        #expect(PackImportCopy.failureTitle(.file) == "이 파일은 가져올 수 없어요")
    }

    @Test("붙여넣기는 「파일」 대신 붙여 넣은 글·표로 말한다")
    func pasteWording() {
        #expect(PackImportCopy.failureTitle(.paste) == "이 표는 가져올 수 없어요")
        #expect(PackImportCopy.failureMessage(.structural(.fileTooLarge), source: .paste)
                == "붙여 넣은 글이 너무 길어요. 항목을 나눠 여러 팩으로 만들어 주세요.")
        #expect(PackImportCopy.failureMessage(.structural(.emptyFile), source: .paste)
                == "붙여 넣은 글에 내용이 없어요. 첫 줄에 머리글을 쓰고 항목을 넣어 주세요.")
        #expect(PackImportCopy.failureMessage(.structural(.templateInPhrasesMode), source: .paste)
                == "단축어 열이 있는 표에는 「#틀」 줄을 쓸 수 없어요.")
        #expect(PackImportCopy.failureMessage(.structural(.headerNotRecognized), source: .paste)
                == PackImportCopy.failureMessage(.structural(.headerNotRecognized), source: .file))
    }

    @Test("상태기계의 거부 둘 — 파일을 열지 못함 · 유효 행 0(4-G 「가져올 수 있는 행이 없어요」)")
    func sessionProblems() throws {
        #expect(PackImportCopy.failureMessage(.fileUnreadable, source: .file)
                == "파일을 열 수 없어요. 파일 앱에서 이 기기에 내려받은 뒤 다시 골라 주세요.")
        let draft = try ImportHelper.draft("번호,제목,본문\n0,a,b")
        #expect(PackImportCopy.failureMessage(.noValidRecords(draft.skipped), source: .file)
                == "가져올 수 있는 행이 없어요. 건너뛴 이유를 확인해 주세요.")
    }

    @Test("머리글 예시는 머리글 사유에만, 「구조가 틀리면 통째로」 풋터는 구조 오류에만")
    func failureSections() throws {
        let header: [PackImportFailure] = [.headerNotRecognized, .duplicateHeader, .duplicateHeaderAlias, .mixedModeHeader,
                                           .missingRequiredColumn, .tooManyColumns, .columnCountMismatch(record: 12, line: 40)]
        for (failure, _) in failureTable {
            #expect(PackImportCopy.showsHeaderExample(.structural(failure)) == header.contains(failure), "\(failure)")
        }
        #expect(PackImportCopy.headerExamples == ["번호 · 제목 · 본문", "단축어 · 제목 · 본문"])
        #expect(PackImportCopy.failureFooter(.structural(.headerNotRecognized), source: .file)
                == "파일 내용은 보여 주지 않아요. 한 행이라도 구조가 틀리면 다른 행도 믿을 수 없어 통째로 받지 않아요.")
        #expect(PackImportCopy.failureFooter(.structural(.quote(CSVQuoteError(kind: .unterminated, record: 12, line: 40))), source: .paste)
                == "붙여 넣은 내용은 보여 주지 않아요. 한 행이라도 구조가 틀리면 다른 행도 믿을 수 없어 통째로 받지 않아요.")
        #expect(PackImportCopy.failureFooter(.structural(.fileTooLarge), source: .file) == "파일 내용은 보여 주지 않아요.")
        let draft = try ImportHelper.draft("번호,제목,본문\n0,a,b")
        #expect(PackImportCopy.failureFooter(.noValidRecords(draft.skipped), source: .file)
                == "건너뛴 행은 내용 없이 위치와 이유만 보여요.")
    }

    @Test("★ SkipReason 전부 → 사유 + 고치는 법 한 줄(시안 4-F CSV판·계획서 4-4절) — 상한 숫자는 PackLimits에서")
    func everySkipReason() {
        for (reason, label, fix) in skipTable {
            exhaustive(reason)
            #expect(PackImportCopy.skipReason(reason) == label, "\(reason)")
            #expect(PackImportCopy.skipFix(reason) == fix, "\(reason)")
        }
        #expect(PackImportCopy.skipTitle(SkippedRecord(record: 12, line: 40, reason: .invalidNumber))
                == "12번째 항목(40번째 줄) — 번호가 1~9999가 아니에요")
    }

    @Test("4-H 건너뛴 이유 — 같은 문구는 묶고(번호 형식·범위), 많은 것부터, 같으면 먼저 나온 것부터")
    func skipGroups() {
        let skipped: [SkipReason] = [.invalidNumber, .emptyBody, .columnCount, .numberOutOfRange, .columnCount, .invalidNumber,
                                     .columnCount, .columnCount, .columnCount, .missingTrigger]
        let groups = PackImportCopy.skipGroups(skipped.enumerated().map { SkippedRecord(record: $0.offset, line: $0.offset, reason: $0.element) })
        #expect(groups.map(\.label) == ["칸 수가 머리글과 달라요", "번호가 1~9999가 아니에요", "본문이 비어 있어요", "단축어가 비어 있어요"])
        #expect(groups.map(\.count) == [5, 3, 1, 1])
        #expect(PackImportCopy.skipReasonCount(300) == "300행")
    }

    @Test("4-H 건너뜀 비율 — 반올림, 받은 행이 있으면 100%로 보이지 않는다",
          arguments: [(340, 600, 57), (1, 2, 50), (299, 300, 99), (0, 10, 0), (0, 0, 0)])
    func skippedPercent(skipped: Int, total: Int, percent: Int) {
        #expect(PackImportPreview.percent(skipped: skipped, of: total) == percent)
    }

    /// ★ 상태 줄 표 — **고른 쪽이 깨졌을 때만** 문장, 고른 쪽이 읽히면 다른 쪽이 깨졌어도 nil(사장님 실기 2026-10-07 — 양쪽 대칭)
    static let encodingStatusTable: [(PackEncodingReview.Encoding, Int, Int, String?)] = [
        (.utf8, 0, 37, nil),                                                                        // UTF-8 고름 · CP949 깨짐 — 실기 지적
        (.cp949, 37, 0, nil),                                                                       // CP949 고름·읽힘 · UTF-8 깨짐
        (.utf8, 37, 0, "UTF-8로는 읽을 수 없어요(깨진 글자 37행). 다른 쪽을 골라 주세요."),
        (.cp949, 0, 37, "한국어(CP949)로는 읽을 수 없어요(깨진 글자 37행). 다른 쪽을 골라 주세요."),
        (.utf8, 1_234, 0, "UTF-8로는 읽을 수 없어요(깨진 글자 1,234행). 다른 쪽을 골라 주세요."),     // 검증 F-6 ② 천 단위 쉼표(S-4)
        (.cp949, 37, 1_234, "한국어(CP949)로는 읽을 수 없어요(깨진 글자 1,234행). 다른 쪽을 골라 주세요."),  // 둘 다 깨짐 — 고른 쪽 수
        (.utf8, 0, 0, "두 가지로 다 읽혀요. 표본을 보고 맞는 쪽을 골라 주세요."),                           // 4-C
        (.cp949, 0, 0, "두 가지로 다 읽혀요. 표본을 보고 맞는 쪽을 골라 주세요.")
    ]

    @Test("★ 4-B·4-C 글자 확인 상태 줄 — 고른 쪽이 깨졌을 때만 문장, 둘 다 읽히면 4-C", arguments: encodingStatusTable)
    func encodingStatus(selected: PackEncodingReview.Encoding, utf8Failed: Int, cp949Failed: Int, line: String?) {
        #expect(PackImportCopy.encodingStatus(review(selected: selected, utf8Failed: utf8Failed, cp949Failed: cp949Failed)) == line)
    }

    @Test("4-B·4-C 글자 확인 — 표 머리·방식 이름")
    func encodingLines() {
        let both = review(selected: .utf8, utf8Failed: 0, cp949Failed: 0)
        #expect(PackImportCopy.samplesHeader(both) == "파일에서 찾은 표본 — UTF-8")
        #expect(PackImportCopy.alternativeHeader(both) == "한국어(CP949)로 고르면")
        #expect(PackImportCopy.samplesHeader(review(selected: .cp949, utf8Failed: 37, cp949Failed: 0)) == "파일에서 찾은 표본")
        #expect(PackImportCopy.encodingName(.utf8) == "UTF-8")
        #expect(PackImportCopy.encodingName(.cp949) == "한국어(CP949)")
    }

    @Test("★ 4-B·4-C CSV 실물 반영(계획서 11절 F-1·F-2) — CP949 안내 줄은 **한국어(CP949)로 읽은 경우에만**, 풋터 둘째 문장")
    func cp949CautionOnlyWhenReadAsCP949() throws {
        let caution = "한국어(CP949)로 저장한 파일은 일부 기호(예: —)가 저장할 때 이미 바뀌었을 수 있어요. 엑셀에서 「CSV UTF-8」로 다시 저장하면 바뀌지 않아요."
        #expect(PackImportCopy.cp949Caution(review(selected: .cp949, utf8Failed: 37, cp949Failed: 0)) == caution)
        #expect(PackImportCopy.cp949Caution(review(selected: .cp949, utf8Failed: 0, cp949Failed: 0)) == caution)   // 4-C 둘 다 읽힘
        #expect(PackImportCopy.cp949Caution(review(selected: .utf8, utf8Failed: 0, cp949Failed: 0)) == nil)
        #expect(PackImportCopy.cp949Caution(review(selected: .utf8, utf8Failed: 0, cp949Failed: 37)) == nil)
        #expect(PackImportCopy.cp949Caution(review(selected: .cp949, utf8Failed: 0, cp949Failed: 37)) == nil, "고른 쪽이 깨지면 상태 줄만")

        // 원본 바이트에서 — CP949 파일(자동 = CP949) · BOM 없는 UTF-8(자동 = UTF-8) · BOM UTF-8(확인 화면 자체가 없다)
        let csv = "trigger,body\n새해인사,새해 복 많이 받으세요\n"
        let cp949Data = try #require(csv.data(using: PackTextDecoder.cp949))
        let cp949File = try #require(PackEncodingReview.probe(cp949Data, choice: .automatic))
        #expect(cp949File.selected == .cp949)
        #expect(PackImportCopy.cp949Caution(cp949File) == caution)
        let utf8File = try #require(PackEncodingReview.probe(Data(csv.utf8), choice: .automatic))
        #expect(utf8File.selected == .utf8)
        #expect(PackImportCopy.cp949Caution(utf8File) == nil)
        #expect(PackEncodingReview.probe(Data([0xEF, 0xBB, 0xBF]) + Data(csv.utf8), choice: .automatic) == nil)

        #expect(PackImportCopy.encodingFooter == "글자가 깨져 보이면 위에서 다른 쪽을 골라 보세요. 고르면 파일을 처음부터 다시 읽어요.\n"
                + "엑셀에서는 「CSV UTF-8」로 저장하면 이 화면이 안 나와요. Numbers·구글 시트의 CSV는 이 화면이 늘 떠요 — 표본이 맞게 보이면 「다음」을 누르세요.")
    }

    @Test("4-E 미리보기 줄 — 파일에 적힌 틀(외 n개)·모르는 열·처음 n개·같은 번호/단축어·정리·따옴표")
    func previewLines() {
        #expect(PackImportCopy.fileTemplate(["사자성어 {n}번", "성어 {n}번"]) == "사자성어 {n}번 외 1개")
        #expect(PackImportCopy.fileTemplate(["사자성어 {n}번"]) == "사자성어 {n}번")
        #expect(PackImportCopy.fileTemplate([]) == nil)
        #expect(PackImportCopy.ignoredColumns(37) == "모르는 열 37개는 가져오지 않아요.")
        #expect(PackImportCopy.firstRowsHeader(count: 37) == "처음 37개")
        #expect(PackImportCopy.duplicates(37, mode: .numbered) == "같은 번호 37개 — 뒤에 있는 것을 써요")
        #expect(PackImportCopy.duplicates(37, mode: .phrases) == "같은 단축어 37개 — 뒤에 있는 것을 써요")
        #expect(PackImportCopy.skippedHeader(count: 37) == "건너뛴 행 37개")
        #expect(PackImportCopy.importOnly(37) == "그래도 37개만 가져오기")
        #expect(PackImportCopy.partialConfirmTitle(37) == "37개만 가져올까요?")
        #expect(PackImportCopy.partialConfirmMessage(skipped: 41) == "건너뛴 41개는 가져오지 않아요.")
        #expect(PackImportCopy.partialConfirmAction(37) == "37개만 가져오기")
        #expect(PackImportCopy.triggersLine(["새해인사", "새해 인사"]) == "단축어: 새해인사, 새해 인사")
    }

    @Test("3-E 붙여넣기 요약 — 줄 수 · 칸 나누기")
    func pasteSummary() {
        #expect(PackImportCopy.pasteSummary(lines: 42, delimiter: .tab) == "42줄 · 칸 나누기: 탭")
        #expect(PackImportCopy.pasteSummary(lines: 42, delimiter: .comma) == "42줄 · 칸 나누기: 쉼표")
        #expect(PackImportCopy.pasteSummary(lines: 42, delimiter: nil) == "42줄")
    }

    @Test("★ 4-I 단축어 확인 — 내 채움글(지금은 내 채움글) · 다른 팩(꺼짐·쉬는 중 표시) · 내장 팩(이 팩이 먼저)")
    func overlapLines() {
        let overlap = PackDraftOverlap(
            userSnippets: .init(source: .userSnippets, triggers: ["주소", "새해인사"], showsBeforeDraft: true),
            packs: [.init(source: .pack("a"), triggers: ["추석인사"], showsBeforeDraft: false),
                    .init(source: .pack("b"), triggers: ["회의실"], showsBeforeDraft: true),
                    .init(source: .pack("c"), triggers: ["추석인사", "인사"], showsBeforeDraft: false)],
            builtIn: .init(source: .builtIn, triggers: ["새해인사"], showsBeforeDraft: false))
        let summaries = ["a": PackSummary(id: "a", name: "인사말 예시", mode: .phrases, itemCount: 3, titleFormat: nil, isEnabled: false, status: .off),
                         "b": PackSummary(id: "b", name: "우리 회사 상용구", mode: .phrases, itemCount: 3, titleFormat: nil, isEnabled: true, status: .on),
                         "c": PackSummary(id: "c", name: "상용 영어", mode: .phrases, itemCount: 3, titleFormat: nil, isEnabled: true,
                                          status: .restingOverLimit)]
        let lines = PackImportCopy.overlapLines(overlap, summary: { summaries[$0] })
        #expect(lines == [
            .init(message: "내 채움글과 같은 단축어 2개 — 목록에서 위에 있는 쪽이 먼저 떠요",
                  details: ["주소, 새해인사 — 새 팩은 맨 아래에 붙어서 지금은 「내 채움글」이 떠요. 이 팩 문구를 먼저 띄우려면 「팩 순서 바꾸기」에서 위로 올려요."],
                  isWarning: true),
            .init(message: "다른 팩과 같은 단축어 3개 — 위에 있는 팩이 먼저 떠요",
                  details: ["추석인사 — 「인사말 예시」 팩(꺼짐)", "회의실 — 「우리 회사 상용구」 팩", "추석인사, 인사 — 「상용 영어」 팩(쉬는 중)"],
                  isWarning: true),
            .init(message: "내장 팩과 같은 단축어 1개 — 이 팩이 먼저 떠요", details: ["새해인사 — 내장 팩보다 앞서요"], isWarning: false)
        ])
        #expect(PackImportCopy.overlapLines(PackDraftOverlap(userSnippets: nil, packs: [], builtIn: nil), summary: { _ in nil }).isEmpty)
    }

    @Test("단축어가 여섯 개 이상이면 다섯 개 뒤 「외 n개」")
    func overlapTriggerListCap() {
        let triggers = ["가", "나", "다", "라", "마", "바", "사"]
        let lines = PackImportCopy.overlapLines(
            PackDraftOverlap(userSnippets: nil, packs: [], builtIn: .init(source: .builtIn, triggers: triggers, showsBeforeDraft: false)),
            summary: { _ in nil })
        #expect(lines.first?.details == ["가, 나, 다, 라, 마 외 2개 — 내장 팩보다 앞서요"])
    }
}

// MARK: - AC-34 · 문구 검사

/// AC-34 — 오류 문구에 파일 내용·파일 이름이 없다. 표식 글자를 품은 파일을 실제로 거부시켜 본다
private let marker = "비밀표식"

@Suite("외부 채움글 1-c 4단계 — 오류 문구에 파일 내용 0 (AC-34)")
struct PackImportCopyContentLeakTests {

    @Test("★ 거부·건너뜀 문구에 파일 글자가 섞이지 않는다 — 표식이 든 칸을 사유마다 실제로 거부시켜 본다",
          arguments: [
            "번호,제목,본문\n1,\"\(marker)\n",                              // quote 닫히지 않음
            "번호,제목,본문\n1,\"\(marker)\"x,본문\n",                       // 닫는 따옴표 뒤 글자
            "\(marker),본문\n가,나\n",                                    // 머리글 없음(표식이 머리글 칸)
            "번호,본문,\(marker),본문\n1,가,나,다\n",                       // 같은 열 두 번
            "#\(marker),값\n번호,본문\n1,가\n",                            // 모르는 정보 줄
            "번호,본문\n1,가\n#이름,\(marker)\n",                          // 정보 줄이 머리글 뒤
            "번호,제목,본문\n\(marker),가,나\n",                          // 유효 0 — 번호 형식(건너뜀)
            "단축어,본문\n\(marker)\(String(repeating: "길", count: 60)),가\n"  // 유효 0 — 단축어 길이
          ])
    func noContentInMessages(_ text: String) throws {
        for source in [PackImportSource.paste(text), .file(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8))] {
            var session = PackImportSession()
            let run = try required(session.start(source))
            session.receive(PackImportSession.compute(run, library: nil))
            guard case .failed(let problem) = session.phase else {
                Issue.record("거부여야 한다: \(session.phase)")
                return
            }
            var shown = [PackImportCopy.failureTitle(source.kind), PackImportCopy.failureMessage(problem, source: source.kind),
                         PackImportCopy.failureFooter(problem, source: source.kind)]
            if case .noValidRecords(let skipped) = problem {
                shown += skipped.flatMap { [PackImportCopy.skipTitle($0), PackImportCopy.skipFix($0.reason)] }
                shown += PackImportCopy.skipGroups(skipped).map(\.label)
            }
            for text in shown { #expect(!text.contains(marker), "\(text)") }
        }
    }
}

/// 4단계가 내는 모든 문구 — 문구 검사(숫자 · `allScreenCopy`의 U6·금칙어·xlsx)를 받는다. 개수·위치는 1~3단계와 같은 표시 값(37·41 · 12번째·40번째)으로 만든다.
/// 부를 때마다 지금 판으로 만든다(6단계 — 판을 바꿔 가며 읽는다)
var stage4Copy: [String] {
    var texts = [
        PackImportCopy.heroTitle, PackImportCopy.heroMessage, PackImportCopy.pickFile, PackImportCopy.firstTimeHeader,
        PackImportCopy.guideTitle, PackImportCopy.otherWaysHeader, PackImportCopy.pasteTitle, PackImportCopy.pasteRowDetail,
        PackImportCopy.startFooter,
        PackImportCopy.guideHeaderSection, PackImportCopy.guideColumns, PackImportCopy.guideMetaSection, PackImportCopy.guideMeta,
        PackImportCopy.guideCellsSection, PackImportCopy.guideCellsFooter, PackImportCopy.guideSaveSection, PackImportCopy.guideSave,
        PackImportCopy.pasteHeader, PackImportCopy.pasteFooter, PackImportCopy.pastePrivacy, PackImportCopy.readButton,
        PackImportCopy.clearButton, PackImportCopy.pasteSummary(lines: 37, delimiter: .tab),
        PackImportCopy.flowTitle, PackImportCopy.readingTitle(.file), PackImportCopy.readingTitle(.paste),
        PackImportCopy.readingMessage(.file), PackImportCopy.readingMessage(.paste),
        PackImportCopy.cancel, PackImportCopy.next, PackImportCopy.close,
        PackImportCopy.encodingTitle, PackImportCopy.encodingQuestion, PackImportCopy.alternativeFooter,
        PackImportCopy.rowsLabel, PackImportCopy.multilineLabel, PackImportCopy.failedLabel, PackImportCopy.count(37),
        PackImportCopy.encodingFooter, PackImportCopy.reviewEncodingAgain, PackImportCopy.unreadableSample,
        PackImportCopy.delimiterTitle, PackImportCopy.delimiterQuestion, PackImportCopy.delimiterFooter, PackImportCopy.delimiterLabel,
        PackImportCopy.encodingLabel,
        PackImportCopy.previewTitle, PackImportCopy.importCountLabel, PackImportCopy.skippedLabel, PackImportCopy.skippedLabel(percent: 57),
        PackImportCopy.kindLabel, PackImportCopy.modeName(.numbered), PackImportCopy.modeName(.phrases),
        PackImportCopy.fileTemplateLabel, PackImportCopy.showAll, PackImportCopy.ignoredColumns(37), PackImportCopy.firstRowsHeader(count: 37),
        PackImportCopy.allRowsTitle, PackImportCopy.allSkippedTitle,
        PackImportCopy.skippedHeader(count: 37), PackImportCopy.skippedFooter, PackImportCopy.duplicates(37, mode: .numbered),
        PackImportCopy.duplicates(37, mode: .phrases), PackImportCopy.sanitized(37), PackImportCopy.strayQuotes(37),
        PackImportCopy.manySkippedBanner(.file), PackImportCopy.manySkippedBanner(.paste),
        PackImportCopy.skipReasonsHeader, PackImportCopy.skipReasonCount(37), PackImportCopy.showAllSkipped,
        PackImportCopy.howToFix, PackImportCopy.importOnly(37), PackImportCopy.partialConfirmTitle(37),
        PackImportCopy.partialConfirmMessage(skipped: 41), PackImportCopy.partialConfirmAction(37), PackImportCopy.overlapHeader, PackImportCopy.overlapFooter,
        PackImportCopy.failureTitle(.file), PackImportCopy.failureTitle(.paste), PackImportCopy.headerExampleHeader,
        PackImportCopy.pickAnotherFile, PackImportCopy.backToPaste
    ]
    texts += PackImportCopy.headerExamples
    texts += PackImportCopy.guideCells
    texts += [PackEncodingReview.Encoding.utf8, .cp949].map(PackImportCopy.encodingName)
    texts += CSVDelimiter.allCases.map(PackImportCopy.delimiterName)
    for selected in [PackEncodingReview.Encoding.utf8, .cp949] {
        for failed in [(0, 0), (37, 0), (0, 37)] {
            let shown = review(selected: selected, utf8Failed: failed.0, cp949Failed: failed.1)
            texts += [PackImportCopy.samplesHeader(shown), PackImportCopy.alternativeHeader(shown)]
            texts += [PackImportCopy.encodingStatus(shown), PackImportCopy.cp949Caution(shown)].compactMap { $0 }
        }
    }
    for kind in [PackImportSource.Kind.file, .paste] {
        let problems: [PackImportProblem] = failureTable.map { .structural($0.0) } + [.fileUnreadable]
        texts += problems.flatMap { [PackImportCopy.failureMessage($0, source: kind), PackImportCopy.failureFooter($0, source: kind)] }
    }
    texts += skipTable.flatMap { [PackImportCopy.skipReason($0.0), PackImportCopy.skipFix($0.0),
                                  PackImportCopy.skipTitle(SkippedRecord(record: 12, line: 40, reason: $0.0))] }
    let overlap = PackDraftOverlap(
        userSnippets: .init(source: .userSnippets, triggers: ["주소"], showsBeforeDraft: true),
        packs: [.init(source: .pack("a"), triggers: ["추석인사"], showsBeforeDraft: false)],
        builtIn: .init(source: .builtIn, triggers: ["회의실"], showsBeforeDraft: false))
    texts += PackImportCopy.overlapLines(overlap, summary: { _ in
        PackSummary(id: "a", name: "인사말 예시", mode: .phrases, itemCount: 3, titleFormat: nil, isEnabled: false, status: .off)
    }).flatMap { [$0.message] + $0.details }
    return texts
}

/// 숫자 검사가 지우는 것 — 글자 방식 이름 · 시안 예시(사자성어 12번 · 007 · 1-2) · 표시 위치·개수(12번째·40번째·37·41·57%) ·
/// 편집기·파일 형식이 이미 사용자에게 보이는 **필드 상한**(단축어 10개·40자, 제목 60자, 본문 3,000자 — P-8 잠정, 번호 1~9999, #틀 1~8개).
/// 예산 한도(R2) 숫자는 여기에 없다 — 들어가면 검사에 걸린다
private let stage4AllowedNumbers = ["UTF-8", "UTF-16", "CP949", "사자성어 12번", "007", "1-2", "12번째", "40번째", "37개", "37행",
                                    "37줄", "41개", "57%", "10개까지", "40자까지", "60자까지", "3,000자까지", "1~9999", "1~8개"]

/// 표시 개수 — 「외 n개」와 4-I 「같은 단축어 n개」
private let countPatterns = [#"외 \d+개"#, #"같은 단축어 \d+개"#]

@Suite("외부 채움글 1-c 4단계 — 문구 검사 (숫자)")
struct PackImportCopyLintTests {

    @Test("★ 숫자는 허용 목록뿐 — 예산 한도 숫자 0(8절 #3)")
    func onlyAllowedNumbers() {
        for text in stage4Copy {
            var rest = countPatterns.reduce(text) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
            for allowed in stage4AllowedNumbers { rest = rest.replacingOccurrences(of: allowed, with: "") }
            #expect(!rest.contains { $0.isNumber }, "\(text)")
        }
    }

    @Test("필드 상한 문구는 PackLimits와 같은 값이다(상한을 바꾸면 문구도 따라온다)")
    func limitsFollowConstants() {
        #expect(PackImportCopy.skipFix(.tooManyTriggers).contains("\(PackLimits.triggersPerEntry)개"))
        #expect(PackImportCopy.skipFix(.triggerTooLong).contains("\(PackLimits.trigger.characters)자"))
        #expect(PackImportCopy.skipFix(.titleTooLong).contains("\(PackLimits.title.characters)자"))
        #expect(PackImportCopy.skipReason(.invalidNumber).contains("\(PackLimits.numberRange.upperBound)"))
        #expect(PackImportCopy.failureMessage(.structural(.metaValueCount(record: 1, line: 1)), source: .file)
                    .contains("1~\(PackLimits.templatePatterns)개"))
    }
}
