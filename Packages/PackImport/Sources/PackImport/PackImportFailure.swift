import Foundation

/// 가져오기 **전체 거부** 사유 — 구조 오류(5-5: 비율과 무관하게 전체 거부).
///
/// ★ **내용 없는 열거형이다**(11절 누출 경로 — 디코딩 오류 객체). 파일 글자·셀 값·파일 이름을 담지 않고
/// 위치는 레코드·줄 번호(정수)로만 말한다. 사용자에게 보이는 문구는 UI(1-c)가 이 코드에서 만든다.
public enum PackImportFailure: Error, Equatable, Sendable {
    /// 파일이 `PackLimits.fileBytes`보다 크다 — 붙여넣기도 UTF-8 바이트로 같은 상한(파싱 전, 검증 F5)
    case fileTooLarge
    /// 내용이 없다 — 빈 파일·BOM만·빈 줄만·구분자만(비지 않은 레코드 0). 구분자 판정 **앞에서** 본다(검증 F4)
    case emptyFile
    /// UTF-32 BOM, 또는 BOM 없이 엄격 UTF-8·엄격 CP949 둘 다 실패(BOM 없는 UTF-16·다른 ANSI 포함, 5-3b #1·#4)
    case unsupportedEncoding
    /// UTF-8 BOM인데 본문이 UTF-8이 아니다 — 손상, CP949로 폴백하지 않는다(5-3b #2)
    case invalidUTF8AfterBOM
    /// UTF-16 BOM인데 홀수 바이트·서로게이트 오류(5-3b #3)
    case invalidUTF16
    /// 사용자가 고른 인코딩이 BOM이 말하는 인코딩과 다르다(R4)
    case encodingDoesNotMatchBOM
    /// 사용자가 고른 인코딩으로 엄격 디코드가 실패했다 — replacement character로 복구하지 않는다
    case undecodable(PackEncodingChoice)
    /// 채택한 구분자로 본 파싱에서 난 quote 오류, 또는 **모든 후보가 quote 오류로 탈락**(5-2 #3·5-4)
    case quote(CSVQuoteError)
    /// 물리 줄이 `PackLimits.physicalLines`를 넘는다 — 4-G 사유는 `tooManyRecords`와 같은 「항목이 너무 많아요」(⑪, 문구는 1-c)
    case tooManyLines
    /// 데이터 논리 레코드가 `PackLimits.dataRecords`를 넘는다 — 4-G 「항목이 너무 많아요」(⑪, 문구는 1-c)
    case tooManyRecords
    /// 어떤 구분자 후보로도 머리글을 인정할 수 없다(「머리글을 확인하세요」 + 예시)
    case headerNotRecognized
    /// 머리글은 인정됐는데 시험 창의 앞 데이터 레코드 과반이 머리글과 열 수가 다르다(5-2 #2) — 위치는 그 안의 첫 불일치 레코드.
    /// 예전에는 `headerNotRecognized`로 보고해 머리글을 고쳐도 풀리지 않았다(검증 F2). 4-G 사유 문구는 1-c
    case columnCountMismatch(record: Int, line: Int)
    /// 같은 열 이름 두 번(`본문`,`본문`)
    case duplicateHeader
    /// 같은 뜻의 별칭 두 개(`본문`+`body`)
    case duplicateHeaderAlias
    /// `번호`와 `단축어`가 함께 있다(모드 혼재)
    case mixedModeHeader
    /// 필수 열이 없다 — 본문, 그리고 번호·단축어 중 하나
    case missingRequiredColumn
    /// 머리글 실효 폭이 `PackLimits.dataColumns`를 넘는다 — 4-G 「칸이 너무 많아요」(⑪, 문구는 1-c)
    case tooManyColumns
    /// 예약 메타 키(`#이름`·`#틀`·`#출처`(옛 `#권리`)·`#escape`)가 머리글 **뒤**에 있다 — 엑셀 정렬 사고(5-3)
    case metaAfterHeader(record: Int, line: Int)
    /// 같은 메타 칸이 두 번 — `#출처`와 옛 `#권리`는 한 칸이라 함께 있어도 여기다(R27)
    case duplicateMeta(record: Int, line: Int)
    /// 알 수 없는 `#` 키
    case unknownMeta(record: Int, line: Int)
    /// `#escape` — 가역 escape(R6·13-2)는 내보내기·왕복 단계(후속)라 아직 받지 않는다
    case unsupportedEscapeMeta(record: Int, line: Int)
    /// 값 개수 위반 — `#이름`·`#출처` 1개, `#틀` 1~8개(trailing 빈 셀만 허용)
    case metaValueCount(record: Int, line: Int)
    /// 메타 레코드 실효 셀이 `PackLimits.metaCells`를 넘는다
    case metaTooManyCells(record: Int, line: Int)
    /// 문구형(`단축어` 열)인데 `#틀`이 있다(혼재)
    case templateInPhrasesMode
}

/// quote 오류의 위치 — 내용 없이 번호만(1부터)
public struct CSVQuoteError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// 따옴표가 닫히지 않았다
        case unterminated
        /// 닫는 따옴표 뒤에 구분자·레코드 끝이 아닌 문자가 왔다
        case characterAfterClosingQuote
    }

    public let kind: Kind
    /// 논리 레코드 번호(1부터)
    public let record: Int
    /// 그 레코드가 시작한 물리 줄(1부터)
    public let line: Int

    public init(kind: Kind, record: Int, line: Int) {
        self.kind = kind
        self.record = record
        self.line = line
    }
}
