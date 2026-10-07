import TadakDomain

/// 외부 채움글 **가져오기** 문구 표 — 한 곳(계획서 `external-snippet-packs-1c-plan.md` 4-4절·5절 4행 ②, 시안
/// `docs/design/external-snippet-packs/index.html` 3-A·3-B·3-E·4-A~4-C·4-E~4-I·4-G 표). 판(`PackCopySet` — CSV 전용판/xlsx 중심판)이
/// 바꾸는 줄은 판에서 읽고, 나머지는 두 판이 공유한다. 1.3.0은 **CSV 전용판**이다(AC-35 — xlsx를 가져오는 안내 0, 「엑셀에서 CSV로 저장」
/// 안내는 CSV판 시안 그대로 쓴다).
///
/// 규칙은 `PackNoticeCopy`와 같다: 해요체 · 「단축어」「채움글」 · 예산 한도 숫자 0(R2 — 보이는 숫자는 위치·개수와, 편집기·파일 형식이 이미
/// 알리는 **필드 상한**뿐이고 그 값은 `PackLimits`에서 온다) · 예시는 교회·성경 소재 0(U6) · 원인과 해결을 한 줄로(6-6).
/// **오류 문구에 파일 내용·파일 이름을 넣지 않는다**(AC-34) — 사유 코드(`PackImportFailure`·`SkipReason`)에는 위치 번호뿐이다.
/// 문구 검사는 `PackImportCopyLintTests`(숫자)·`PackCopyLintTests`(U6·금칙어·xlsx — 한 곳)가 `swift test`로 돈다.
public enum PackImportCopy {

    /// 판이 바꾸는 줄(`PackCopySet` — 시안 6절 비교표)
    private static var lines: PackCopySet.Lines { PackCopySet.current.lines }

    // MARK: - 3-A 첫 화면

    public static var heroTitle: String { lines.heroTitle }
    public static var heroMessage: String { lines.heroLead + "\n번호형(사자성어 12번처럼)·문구형(단축어 → 문구) 둘 다 돼요." }
    public static var pickFile: String { lines.pickFile }
    public static let firstTimeHeader = "처음이라면"
    public static let otherWaysHeader = "그 밖의 방법"
    /// 「그 밖의 방법」의 파일 줄 — xlsx 중심판에만(CSV 전용판은 주 버튼이 곧 CSV다)
    public static var otherFileRow: PackCopySet.Row? { lines.otherFileRow }
    public static let pasteTitle = "붙여넣기로 가져오기"
    public static let pasteRowDetail = "표를 복사해 그대로 붙여 넣어요"
    /// 3-A 바닥 — 받지 않는 파일(판에 있을 때만 — CSV 전용판은 nil이라 풋터가 없다). 「엑셀에서는 …」과 뒤의 개인정보 한 줄(「가져온 팩은 이 기기에만
    /// 저장되고 …」)을 함께 뺐다 — 같은 뜻은 처리방침에 있다(사장님 실기 2026-10-07)
    public static var startFooter: String? { lines.unsupportedFiles }

    // MARK: 3-A 「처음이라면」 샘플 · 3-C 샘플 받기(공유 시트)

    public static func sampleTitle(_ kind: PackSample.Kind) -> String {
        switch kind {
        case .numbered: "번호형 샘플"
        case .phrases: "문구형 샘플"
        }
    }

    public static func sampleDetail(_ kind: PackSample.Kind) -> String {
        switch kind {
        case .numbered: "사자성어·상용 영어처럼 번호로 고르는 자료"
        case .phrases: "단축어를 치면 문구가 떠요"
        }
    }

    /// 샘플 줄 오른쪽 알약 — 누르면 그 형식의 파일로 공유 시트가 열린다
    public static func sampleFormatLabel(_ format: PackSample.Format) -> String {
        switch format {
        case .csv: "CSV"
        case .xlsx: "엑셀"
        }
    }

    /// 알약의 손쉬운 사용 이름 — 알약 글자(「CSV」)만으로는 무엇을 받는지 모른다
    public static func sampleShareLabel(_ file: PackSample.File) -> String {
        "\(sampleTitle(file.kind)) \(sampleFormatLabel(file.format)) 받기"
    }

    // MARK: - 3-B 만드는 법 — 절 제목의 번호(1.~4.)는 화면이 붙인다
    //
    // 칸의 글은 **문장 하나에 한 줄**이다(R30 — 한 칸에 문장이 이어져 읽기 어려웠다). 화면이 줄마다 앞에 「·」를 붙인다(VoiceOver는 읽지 않는다).
    // 배열 원소가 곧 문장이다 — 문장 글자는 나누기 전과 같다(`PackGuideSentenceTests`)

    public static var guideTitle: String { lines.guideTitle }
    public static let guideHeaderSection = "첫 줄은 머리글"
    /// 시트 그림 — 샘플과 같은 **가짜 내용**(U6). 행마다 A·B·C 칸
    public static let guideSheet: [[String]] = [
        ["#이름", "사자성어 예시 팩", ""],
        ["#틀", "사자성어 {n}번", "성어 {n}번"],
        ["#출처", "제작자 자체 작성", ""],
        ["번호", "제목", "본문"],
        ["1", "예시 제목 하나", "예시 본문 첫 줄…"],
        ["12", "예시 제목 둘", "예시 본문 한 줄"]
    ]
    /// 시트 그림에서 정보 줄(`#…`) 다음의 머리글 행 — 굵게 보인다
    public static let guideSheetHeaderRow = 3
    public static let guideColumns = [
        "번호형은 번호 · 제목 · 본문, 문구형은 단축어 · 제목 · 본문.",
        "열 순서는 상관없고 영어 이름(number·trigger·title·body)도 돼요.",
        "제목은 비워도 돼요."
    ]
    public static let guideMetaSection = "팩 정보 줄(선택)"
    public static let guideMeta = [
        "머리글 위에 #이름 · #틀 · #출처 줄을 두면 가져올 때 미리 채워져요.",
        "정렬하다 아래로 내려가지 않게 해 주세요."
    ]
    /// CSV에는 셀 타입이 없어 바뀐 값을 파서가 알 수 없다 — 안내로만 다룬다(PDR 6-7, R20 「가 — 안내 문구만」). 판마다 다르다.
    /// `guideCells`는 칸(행)마다 문장 배열이다
    public static var guideCellsSection: String { lines.guideCellsSection }
    public static var guideCells: [[String]] { lines.guideCells }
    public static var guideCellsFooter: String { lines.guideCellsFooter }
    public static let guideSaveSection = "저장하고 옮기기"
    public static var guideSave: [String] { lines.guideSaveSteps + ["파일 앱·AirDrop·메일로 이 기기에 옮긴 뒤 「\(pickFile)」를 눌러요."] }

    // MARK: - 3-E 붙여넣기

    public static let pasteHeader = "표를 복사해 붙여 넣어요"
    public static let pasteFooter = "첫 줄은 머리글(번호·제목·본문 또는 단축어·제목·본문)이어야 해요. 엑셀·구글 시트에서 칸을 골라 복사하면 그대로 붙어요."
    public static let pastePrivacy = "클립보드는 「붙여넣기」를 눌렀을 때만 읽어요. 붙여 넣은 내용은 이 기기 안에서만 읽어요."
    public static let readButton = "읽기"
    public static let clearButton = "모두 지우기"

    /// 「42줄 · 칸 나누기: 탭」 — 구분자를 하나로 정할 수 없으면 줄 수만
    public static func pasteSummary(lines: Int, delimiter: CSVDelimiter?) -> String {
        "\(PackNoticeCopy.number(lines))줄" + (delimiter.map { " · \(delimiterLabel): \(delimiterName($0))" } ?? "")
    }

    // MARK: - 4-A 읽는 중 · 공통 버튼

    public static let flowTitle = "가져오기"
    public static let cancel = "취소"
    public static let next = "다음"
    public static let close = "닫기"

    public static func readingTitle(_ kind: PackImportSource.Kind) -> String {
        kind == .file ? "파일을 읽고 있어요" : "붙여 넣은 표를 읽고 있어요"
    }

    public static func readingMessage(_ kind: PackImportSource.Kind) -> String {
        kind == .file ? "큰 파일은 몇 초 걸려요.\n읽은 내용은 이 기기 안에서만 확인해요." : "읽은 내용은 이 기기 안에서만 확인해요."
    }

    // MARK: - 4-B·4-C 글자 확인

    public static let encodingTitle = "글자 확인"
    public static let encodingQuestion = "이 파일의 글자가 맞게 보이나요?"
    public static let encodingLabel = "글자 방식"
    /// 「행 · 여러 줄 본문 · 읽기 실패」 절의 머리(R29)
    public static let countsHeader = "불러온 개수"
    public static let rowsLabel = "행"
    public static let multilineLabel = "여러 줄 본문"
    public static let failedLabel = "읽기 실패"
    public static let alternativeFooter = "같은 파일이라도 고르는 방식에 따라 다른 글자로 읽혀요."
    /// 둘째 문장 — Numbers·구글 시트는 BOM을 못 넣어 이 화면이 매번 뜬다(계획서 11절 F-2, `verify-csv-real-mac.md`)
    public static let encodingFooter = "글자가 깨져 보이면 위에서 다른 쪽을 골라 보세요. 고르면 파일을 처음부터 다시 읽어요.\n"
        + "엑셀에서는 「CSV UTF-8」로 저장하면 이 화면이 안 나와요. Numbers·구글 시트의 CSV는 이 화면이 늘 떠요 — 표본이 맞게 보이면 「다음」을 누르세요."
    /// 미리보기에서 글자 확인으로 돌아가는 줄
    public static let reviewEncodingAgain = "글자 방식 다시 고르기"
    /// 표본 자리를 그 방식으로 못 읽을 때
    public static let unreadableSample = "이 방식으로는 읽을 수 없는 칸"

    public static func encodingName(_ encoding: PackEncodingReview.Encoding) -> String {
        encoding == .utf8 ? "UTF-8" : "한국어(CP949)"
    }

    public static func count(_ value: Int) -> String { "\(PackNoticeCopy.number(value))개" }

    /// 구분 줄 — 둘 다 읽힘(4-C) · **고른 쪽이 깨짐**(「다음」이 먹지 않는다). 고른 쪽이 읽히면 다른 쪽이 깨졌어도 줄이 없다(nil) —
    /// UTF-8을 골랐는데 「한국어(CP949)로는 읽을 수 없어요」가 보이던 것(사장님 실기 2026-10-07). 양쪽 대칭
    public static func encodingStatus(_ review: PackEncodingReview) -> String? {
        if review.bothReadable { return "두 가지로 다 읽혀요. 표본을 보고 맞는 쪽을 골라 주세요." }
        let selected = review.reading(review.selected)
        guard !selected.isReadable else { return nil }
        return "\(encodingName(review.selected))로는 읽을 수 없어요(깨진 글자 \(PackNoticeCopy.number(selected.failedLines))행). 다른 쪽을 골라 주세요."
    }

    /// 상태 줄 아래 한 줄 — **고른 방식이 한국어(CP949)이고 읽힐 때만**(계획서 11절 F-1). 엑셀 「쉼표로 구분된 값」(CP949)은 `—` 같은 기호를
    /// 저장할 때 이미 바꾸는데 표본에는 그 글자가 안 나와 알아챌 수 없다(`verify-csv-real-mac.md`). UTF-8로 읽은 파일·BOM 파일(확인 화면 없음)에는 없다
    public static func cp949Caution(_ review: PackEncodingReview) -> String? {
        guard review.selected == .cp949, review.cp949.isReadable else { return nil }
        return "한국어(CP949)로 저장한 파일은 일부 기호(예: —)가 저장할 때 이미 바뀌었을 수 있어요. 엑셀에서 「CSV UTF-8」로 다시 저장하면 바뀌지 않아요."
    }

    /// 표본 절 머리(R29 — 예전 「파일에서 찾은 표본」)
    public static func samplesHeader(_ review: PackEncodingReview) -> String {
        review.bothReadable ? "불러온 글자 — \(encodingName(review.selected))" : "불러온 글자"
    }

    /// 표본 한 줄 — 정보 줄은 원문(`#이름,값,`)이 아니라 「이름 : 값」(R29), 데이터 칸은 글자 그대로, 그 방식으로 못 읽은 자리는 안내
    public static func sampleLine(_ sample: PackEncodingReview.Sample?) -> String {
        guard let sample else { return unreadableSample }
        return sample.meta.map { "\(metaLabel($0)) : \(sample.text)" } ?? sample.text
    }

    /// 정보 줄 칸 이름 — 옛 `#권리`도 「출처」다(R27)
    public static func metaLabel(_ field: PackMetaField) -> String {
        switch field {
        case .name: "이름"
        case .template: "틀"
        case .license: "출처"
        }
    }

    /// 4-C — 고르지 않은 쪽 표본(흐리게)
    public static func alternativeHeader(_ review: PackEncodingReview) -> String { "\(encodingName(review.other))로 고르면" }

    // MARK: - 구분자 고르기 (5-2 #3 — 시안 컷 없음)

    public static let delimiterTitle = "칸 나누기 확인"
    public static let delimiterQuestion = "칸을 나누는 기호를 골라 주세요"
    public static let delimiterFooter = "두 가지 이상으로 칸을 나눠 읽을 수 있어요. 고르면 처음부터 다시 읽어요."
    public static let delimiterLabel = "칸 나누기"

    public static func delimiterName(_ delimiter: CSVDelimiter) -> String {
        switch delimiter {
        case .comma: "쉼표"
        case .semicolon: "세미콜론"
        case .tab: "탭"
        }
    }

    // MARK: 칸 나누기 되돌리기 (R29 — 바꾼 구분자로 읽지 못한 거부 화면)

    /// 거부 화면 제목 — 파일이 아니라 **고른 칸 나누기**가 맞지 않는다(그 아래 사유 한 줄은 4-G 그대로)
    public static func delimiterFailureTitle(_ delimiter: CSVDelimiter) -> String {
        let name = delimiterName(delimiter)
        return "칸을 \(name)\(PackNoticeCopy.directionParticle(after: name)) 나누면 읽을 수 없어요"
    }

    /// 되돌리기 버튼 — 미리보기에서 바꿨으면 직전 구분자로, 고르기 화면에서 골랐으면 고르기 화면으로
    public static func revertDelimiter(_ fallback: PackImportSession.DelimiterFallback) -> String {
        guard let previous = fallback.previous else { return "칸 나누기 다시 고르기" }
        let name = delimiterName(previous)
        return "\(name)\(PackNoticeCopy.directionParticle(after: name)) 되돌리기"
    }

    public static func revertDelimiterFooter(_ kind: PackImportSource.Kind) -> String {
        kind == .file ? "되돌리면 파일을 처음부터 다시 읽어요." : "되돌리면 붙여 넣은 표를 처음부터 다시 읽어요."
    }

    // MARK: - 4-D 시트 고르기 (엑셀 — 보이는 시트가 둘 이상일 때만, AC-36)

    public static let sheetTitle = "시트 고르기"
    public static let sheetHeader = "가져올 시트"
    public static let sheetFooter = "숨긴 시트는 목록에 없어요. 한 번에 한 시트만 가져와요 — 다른 시트는 다시 가져오면 돼요."
    /// 미리보기에서 고르기 화면으로(다시 읽지 않는다)
    public static let reviewSheetAgain = "시트 다시 고르기"
    /// 고른 시트를 읽지 못한 거부 화면에서 고르기 화면으로
    public static let chooseAnotherSheet = "다른 시트 고르기"

    /// 시트 줄의 보조 글 — 대략의 행 수(정보 줄·머리글 포함). 읽지 못한 시트는 nil(아무것도 쓰지 않는다)
    public static func sheetRowCount(_ count: Int?) -> String? {
        guard let count else { return nil }
        return count == 0 ? "빈 시트" : "약 \(PackNoticeCopy.number(count))행"
    }

    // MARK: - 4-E·4-F·4-H 미리보기

    public static let previewTitle = "미리보기"
    public static let importCountLabel = "가져올 항목"
    public static let skippedLabel = "건너뜀"
    public static let kindLabel = PackNoticeCopy.kindLabel
    public static let fileTemplateLabel = "파일에 적힌 틀"
    public static let showAll = "전체 보기"
    public static let allRowsTitle = "가져올 항목"
    public static let allSkippedTitle = "건너뛴 행"
    public static let skippedFooter = "건너뛴 행은 내용 없이 위치와 이유만 보여요."
    public static let skipReasonsHeader = "건너뛴 이유"
    public static let showAllSkipped = "건너뛴 행 모두 보기"
    public static let howToFix = "고치는 법 보기"

    /// 4-H 「건너뜀 (57%)」
    public static func skippedLabel(percent: Int) -> String { "\(skippedLabel) (\(PackNoticeCopy.number(percent))%)" }

    public static func modeName(_ mode: ExternalPack.Mode) -> String { mode == .numbered ? "번호형" : "문구형" }

    /// 파일의 `#틀` — 대표 틀(첫 칸) + 「외 n개」. 틀은 다음 화면(폼)에서 고친다 — 여기서는 보여 주기만
    public static func fileTemplate(_ specs: [String]) -> String? {
        guard let first = specs.first else { return nil }
        return specs.count > 1 ? "\(first) 외 \(PackNoticeCopy.number(specs.count - 1))개" : first
    }

    /// U5 「처음 5개」(문구형 4-I는 「처음 3개」)
    public static func firstRowsHeader(count: Int) -> String { "처음 \(PackNoticeCopy.number(count))개" }

    /// 모르는 열은 가져오지 않는다(열 이름은 보이지 않는다 — 건수만, PDR 5-3)
    public static func ignoredColumns(_ count: Int) -> String { "모르는 열 \(PackNoticeCopy.number(count))개는 가져오지 않아요." }

    public static func triggersLine(_ triggers: [String]) -> String { "단축어: " + triggers.joined(separator: ", ") }

    public static func skippedHeader(count: Int) -> String { "건너뛴 행 \(PackNoticeCopy.number(count))개" }

    /// 같은 번호·단축어는 뒤가 이긴다(PDR 5-4 ⑦)
    public static func duplicates(_ count: Int, mode: ExternalPack.Mode) -> String {
        "같은 \(mode == .numbered ? "번호" : "단축어") \(PackNoticeCopy.number(count))개 — 뒤에 있는 것을 써요"
    }

    /// 문자 정리(11절)로 뺀 글자 — 조용히 바꾸지 않는다
    public static func sanitized(_ count: Int) -> String { "눈에 보이지 않는 글자 \(PackNoticeCopy.number(count))개는 빼고 가져와요" }

    /// (엑셀) 숨긴 행·열도 읽는다 — 사용자의 의도를 추정하지 않고 알린다(6-4, 시안 4-F)
    public static func hiddenRows(_ count: Int) -> String { "숨긴 행 \(PackNoticeCopy.number(count))개도 가져와요" }
    public static func hiddenColumns(_ count: Int) -> String { "숨긴 열 \(PackNoticeCopy.number(count))개도 가져와요" }

    /// 따옴표 없는 칸 가운데의 `"` — 글자로 받고 건수만(5-4)
    public static func strayQuotes(_ count: Int) -> String { "칸 가운데의 따옴표 \(PackNoticeCopy.number(count))개는 글자 그대로 가져와요" }

    /// 4-H 배너
    public static func manySkippedBanner(_ kind: PackImportSource.Kind) -> String {
        kind == .file ? "절반 넘게 건너뛰어요. 파일을 고친 뒤 다시 가져오길 권해요." : "절반 넘게 건너뛰어요. 표를 고친 뒤 다시 붙여 넣길 권해요."
    }

    public static func skipReasonCount(_ count: Int) -> String { "\(PackNoticeCopy.number(count))행" }
    public static func importOnly(_ count: Int) -> String { "그래도 \(PackNoticeCopy.number(count))개만 가져오기" }
    public static func partialConfirmTitle(_ count: Int) -> String { "\(PackNoticeCopy.number(count))개만 가져올까요?" }
    public static func partialConfirmMessage(skipped: Int) -> String { "건너뛴 \(PackNoticeCopy.number(skipped))개는 가져오지 않아요." }
    /// 확인창의 확인 버튼
    public static func partialConfirmAction(_ count: Int) -> String { "\(PackNoticeCopy.number(count))개만 가져오기" }

    // MARK: 건너뛴 행 (4-F — 행 번호와 사유만, 5-5)

    /// CSV는 「n번째 항목(m번째 줄)」 — 여러 줄 본문 때문에 둘이 다르다(5-4)
    public static func position(record: Int, line: Int) -> String { "\(PackNoticeCopy.number(record))번째 항목(\(PackNoticeCopy.number(line))번째 줄)" }

    /// 엑셀은 「n번째 행」(엑셀에서 보이는 행 번호), CSV는 「n번째 항목(m번째 줄)」(시안 4-F 판단 ⑤)
    public static func position(_ position: PackRecordPosition) -> String {
        switch position {
        case .record(let record, let line): self.position(record: record, line: line)
        case .row(let row): "\(PackNoticeCopy.number(row))번째 행"
        }
    }

    public static func skipTitle(_ skipped: SkippedRecord) -> String {
        "\(position(skipped.position)) — \(skipReason(skipped.reason))"
    }

    public static func skipReason(_ reason: SkipReason) -> String {
        switch reason {
        case .columnCount: "칸 수가 머리글과 달라요"
        case .missingNumber: "번호가 비어 있어요"
        case .invalidNumber, .numberOutOfRange:
            "번호가 \(numberRangeText)\(PackNoticeCopy.subjectParticle(after: numberRangeText)) 아니에요"
        case .missingTrigger: "단축어가 비어 있어요"
        case .tooManyTriggers: "단축어가 너무 많아요"
        case .triggerTooLong: "단축어가 너무 길어요"
        case .emptyBody: "본문이 비어 있어요"
        case .titleTooLong: "제목이 너무 길어요"
        case .bodyTooLong: "본문이 너무 길어요"
        case .formula: "수식이에요"
        case .dateFormat: "날짜 서식이에요"
        case .booleanOrError: "TRUE·FALSE나 오류 값이에요"
        case .numberCell: "숫자로 저장된 칸이에요"
        case .merged: "병합한 칸이 있어요"
        }
    }

    /// 고치는 법 한 줄 — 상한 값은 `PackLimits`(단축어 10개·40자는 편집기가 이미 알리는 값, 본문은 P-8 잠정)
    public static func skipFix(_ reason: SkipReason) -> String {
        switch reason {
        case .columnCount: "쉼표가 빠졌거나 더 있어요"
        case .missingNumber: "번호 칸을 채워 주세요"
        case .invalidNumber, .numberOutOfRange: "번호 칸을 확인해 주세요"
        case .missingTrigger: "단축어 칸을 채워 주세요"
        case .tooManyTriggers: "한 항목에 단축어는 \(PackNoticeCopy.number(PackLimits.triggersPerEntry))개까지예요"
        case .triggerTooLong: "단축어 하나는 \(PackNoticeCopy.number(PackLimits.trigger.characters))자까지예요"
        case .emptyBody: "본문을 채워 주세요"
        case .titleTooLong: "제목은 \(PackNoticeCopy.number(PackLimits.title.characters))자까지예요"
        case .bodyTooLong: "본문은 한 칸에 \(PackNoticeCopy.number(PackLimits.body.characters))자까지예요"
        // 6-4 — 원인과 해결 한 줄(6-6). 날짜·불리언·오류·숫자는 칸에 입력할 때 엑셀이 바꾼 것이라 해결이 같다(PDR 6-4 R19 문구)
        case .formula: "「값만 붙여넣기」로 바꿔 주세요"
        case .dateFormat, .booleanOrError, .numberCell: "그 열 서식을 「텍스트」로 바꿔 주세요"
        case .merged: "병합을 풀어 주세요"
        }
    }

    /// 화면의 고치는 법 — 사유가 같아도 엑셀 행이면 엑셀 말로. 「칸 수가 머리글과 달라요」는 CSV에선 쉼표 문제지만 엑셀 행에선 머리글보다
    /// 오른쪽 칸에 값이 있는 것이다(엑셀은 빈 칸을 채우므로 모자랄 수는 없다)
    public static func skipFix(_ skipped: SkippedRecord) -> String {
        if case .row = skipped.position, skipped.reason == .columnCount { return "머리글이 없는 오른쪽 칸을 비워 주세요" }
        return skipFix(skipped.reason)
    }

    public struct SkipGroup: Equatable, Sendable {
        public let label: String
        public let count: Int
    }

    /// 4-H 「건너뛴 이유」 — 같은 문구(번호 형식·범위)는 묶고, 많은 것부터, 같으면 먼저 나온 것부터
    public static func skipGroups(_ skipped: [SkippedRecord]) -> [SkipGroup] {
        var labels: [String] = []
        var counts: [String: Int] = [:]
        for record in skipped {
            let label = skipReason(record.reason)
            if counts[label] == nil { labels.append(label) }
            counts[label, default: 0] += 1
        }
        return labels.enumerated()
            .sorted { counts[$0.element]! != counts[$1.element]! ? counts[$0.element]! > counts[$1.element]! : $0.offset < $1.offset }
            .map { SkipGroup(label: $0.element, count: counts[$0.element]!) }
    }

    // MARK: - 4-I 단축어 확인

    public static let overlapHeader = "단축어 확인"
    public static let overlapFooter = "단축어가 겹쳐도 가져올 수 있어요."

    /// 한 줄 — 주황 경고(누가 먼저 뜨는지 알아야 하는 것) 또는 파랑 정보(이 팩이 먼저)
    public struct OverlapLine: Equatable, Sendable {
        public let message: String
        public let details: [String]
        public let isWarning: Bool

        public init(message: String, details: [String], isWarning: Bool) {
            self.message = message
            self.details = details
            self.isWarning = isWarning
        }
    }

    /// 제목에 「누가 먼저 뜨는지」를 바로 쓴다(시안 4-I). 팩 이름은 사용자 입력 — 표시만
    public static func overlapLines(_ overlap: PackDraftOverlap, summary: (String) -> PackSummary?) -> [OverlapLine] {
        var lines: [OverlapLine] = []
        if let user = overlap.userSnippets {
            lines.append(OverlapLine(
                message: "내 채움글과 같은 단축어 \(PackNoticeCopy.number(user.triggers.count))개 — 목록에서 위에 있는 쪽이 먼저 떠요",
                // 가리키는 곳은 채움글 화면의 「외부 채움글」 목록 — 가져오기가 끝나면 그 화면으로 돌아간다. 순서는 길게 눌러 끌어 바꾼다(R30)
                details: ["\(listed(user.triggers)) — 새 팩은 맨 아래에 붙어서 지금은 「내 채움글」이 떠요. "
                          + "이 팩 문구를 먼저 띄우려면 「외부 채움글」 목록에서 길게 눌러 위로 올려요."],
                isWarning: true))
        }
        if !overlap.packs.isEmpty {
            var seen = Set<String>()
            let distinct = overlap.packs.flatMap(\.triggers).filter { seen.insert($0).inserted }.count
            let details = overlap.packs.map { group -> String in
                guard case .pack(let id) = group.source else { return listed(group.triggers) }
                let shown = summary(id)
                return "\(listed(group.triggers)) — 「\(shown?.name ?? PackNoticeCopy.unnamedPack)」 팩\(stateNote(shown?.status))"
            }
            lines.append(OverlapLine(message: "다른 팩과 같은 단축어 \(PackNoticeCopy.number(distinct))개 — 위에 있는 팩이 먼저 떠요", details: details, isWarning: true))
        }
        if let builtIn = overlap.builtIn {
            lines.append(OverlapLine(message: "내장 팩과 같은 단축어 \(PackNoticeCopy.number(builtIn.triggers.count))개 — 이 팩이 먼저 떠요",
                                     details: ["\(listed(builtIn.triggers)) — 내장 팩보다 앞서요"], isWarning: false))
        }
        return lines
    }

    /// 지금 안 뜨는 팩이면 이유를 괄호로(꺼짐·쉬는 중)
    private static func stateNote(_ status: PackSummary.Status?) -> String {
        switch status {
        case .off: "(꺼짐)"
        case .restingOverLimit, .restingForUserSnippets: "(쉬는 중)"
        case .on, .unavailable, nil: ""
        }
    }

    private static func listed(_ triggers: [String]) -> String {
        let shown = PackNoticeCopy.shownTriggerCount
        return triggers.prefix(shown).joined(separator: ", ") + (triggers.count > shown ? " 외 \(PackNoticeCopy.number(triggers.count - shown))개" : "")
    }

    // MARK: - 4-G 거부

    public static let headerExampleHeader = "머리글 예시"
    public static let headerExamples = ["번호 · 제목 · 본문", "단축어 · 제목 · 본문"]
    public static let pickAnotherFile = "다른 파일 고르기"
    public static let backToPaste = "붙여넣기로 돌아가기"

    public static func failureTitle(_ kind: PackImportSource.Kind) -> String {
        kind == .file ? "이 파일은 가져올 수 없어요" : "이 표는 가져올 수 없어요"
    }

    /// 제목 아래 문구 — **사유 전부**(계획서 4-4절 + 시안 4-G 표). 위치는 번호만, 파일 내용·이름은 없다(AC-34)
    public static func failureMessage(_ problem: PackImportProblem, source kind: PackImportSource.Kind) -> String {
        switch problem {
        case .fileUnreadable:
            return "파일을 열 수 없어요. 파일 앱에서 이 기기에 내려받은 뒤 다시 골라 주세요."
        case .noValidRecords:
            return "가져올 수 있는 행이 없어요. 건너뛴 이유를 확인해 주세요."
        case .structural(let failure):
            return message(failure, kind: kind)
        }
    }

    private static func message(_ failure: PackImportFailure, kind: PackImportSource.Kind) -> String {
        switch failure {
        case .fileTooLarge:
            kind == .file ? "파일이 너무 커요. 항목을 나눠 여러 팩으로 만들어 주세요." : "붙여 넣은 글이 너무 길어요. 항목을 나눠 여러 팩으로 만들어 주세요."
        case .emptyFile:
            (kind == .file ? "파일에" : "붙여 넣은 글에") + " 내용이 없어요. 첫 줄에 머리글을 쓰고 항목을 넣어 주세요."
        case .unsupportedEncoding:
            "이 파일의 글자 방식은 지원하지 않아요. 「CSV UTF-8」로 저장해 주세요."
        case .invalidUTF8AfterBOM:
            "UTF-8이라고 표시된 파일인데 깨진 글자가 있어요. 파일이 손상됐을 수 있어요."
        case .invalidUTF16:
            "UTF-16이라고 표시된 파일인데 깨진 글자가 있어요. 파일이 손상됐을 수 있어요. 「CSV UTF-8」로 다시 저장해 주세요."
        case .encodingDoesNotMatchBOM:
            "파일이 알리는 글자 방식과 달라요. 파일에 맞는 방식을 골라 주세요."
        case .undecodable:
            "고른 글자 방식으로는 읽을 수 없어요. 다른 방식을 골라 보세요."
        case .quote(let quote):
            switch quote.kind {
            case .unterminated:
                "\(position(record: quote.record, line: quote.line)) 근처에서 따옴표가 닫히지 않았어요."
            case .characterAfterClosingQuote:
                "\(position(record: quote.record, line: quote.line)) 근처에서 닫는 따옴표 뒤에 글자가 더 있어요. 칸 안의 따옴표는 두 번(\"\") 써 주세요."
            }
        case .tooManyLines, .tooManyRecords:
            "항목이 너무 많아요. 여러 팩으로 나눠 주세요."
        case .headerNotRecognized:
            "머리글을 찾지 못했어요. 첫 줄(머리글)을 확인해 주세요."
        case .columnCountMismatch(let record, let line):
            "칸 수가 머리글과 달라요. \(position(record: record, line: line)) 근처의 쉼표나 따옴표를 확인해 주세요."
        case .duplicateHeader:
            "같은 이름의 열이 두 번 있어요. 하나만 남겨 주세요."
        case .duplicateHeaderAlias:
            "같은 뜻의 열이 두 개 있어요(예: 「본문」과 「body」). 하나만 남겨 주세요."
        case .mixedModeHeader:
            "「번호」와 「단축어」 열을 함께 쓸 수 없어요. 팩 하나는 한 종류예요."
        case .missingRequiredColumn:
            "꼭 필요한 열이 없어요. 「본문」 열과 「번호」나 「단축어」 열을 넣어 주세요."
        case .tooManyColumns:
            "칸이 너무 많아요. 필요한 칸만 남겨 주세요."
        case .metaAfterHeader:
            "「#이름」 같은 정보 줄은 머리글 위에 있어야 해요. 정렬하다 아래로 내려갔는지 확인해 주세요."
        case .duplicateMeta:
            "같은 정보 줄(#이름·#틀·#출처)이 두 번 있어요. 하나만 남겨 주세요."
        case .duplicateSourceMeta:
            // 옛 키 이름을 말하는 유일한 문구 — 파일에 실제로 쓰인 글자라야 찾는다(R27 lint 예외, `PackCopyLint.retiredExceptions`)
            "「#출처」와 「#권리」는 같은 정보 줄이에요. 하나만 남겨 주세요."
        case .unknownMeta:
            "모르는 정보 줄(#…)이 있어요. 정보 줄은 「#이름」·「#틀」·「#출처」만 쓸 수 있어요."
        case .unsupportedEscapeMeta:
            "「#escape」 줄은 아직 쓸 수 없어요. 그 줄을 지우고 다시 가져와 주세요."
        case .metaValueCount, .metaTooManyCells:
            "정보 줄의 칸 수가 맞지 않아요. 「#이름」·「#출처」는 값 하나, 「#틀」은 1~\(PackNoticeCopy.number(PackLimits.templatePatterns))개예요."
        case .templateInPhrasesMode:
            "단축어 열이 있는 \(kind == .file ? "파일" : "표")에는 「#틀」 줄을 쓸 수 없어요."
        case .mergedHeaderOrMeta:
            "머리글이나 정보 줄에 병합한 칸이 있어요. 병합을 풀어 주세요."
        case .nonTextHeaderCell:
            "머리글이나 정보 줄에 수식·날짜처럼 글이 아닌 칸이 있어요. 그 칸을 글로 바꿔 주세요."
        case .workbook(let workbook):
            workbookMessage(workbook)
        }
    }

    /// 4-G 엑셀 행(시안 표) — 컨테이너·XML 거부 코드를 사용자가 할 수 있는 일로 묶는다: 비밀번호·옛 형식 / 매크로 / 너무 큼 / 항목 많음 /
    /// 보이는 시트 없음 / 그 밖은 「읽을 수 없어요」 하나(계획 ③ — 손상·적대 구조를 사용자가 구별할 까닭이 없다). 칸 하나가 상한(엑셀 셀 최대 쪽)을
    /// 넘는 `textTooLong`도 엑셀이 만들 수 없는 파일이라 그 묶음이다(승인 메모 ③ — 본문 상한을 넘는 칸은 CSV처럼 행에서 다룬다).
    /// **xlsx를 받는 판에서만 닿는다**(CSV 전용판 세션은 xlsx로 읽지 않는다 — AC-35). 시트 이름·파트 이름·내용 없음(AC-34)
    private static func workbookMessage(_ failure: XLSXWorkbookFailure) -> String {
        switch failure {
        case .archive(.legacyOrProtectedWorkbook):
            "비밀번호가 걸렸거나 옛 형식(.xls)인 엑셀이에요. 비밀번호를 풀고 「Excel 통합 문서(.xlsx)」로 저장해 주세요."
        case .macroEnabled:
            "매크로가 든 파일은 받지 않아요. 「Excel 통합 문서(.xlsx)」로 다시 저장해 주세요."
        case .archive(.fileTooLarge), .archive(.partTooLarge), .archive(.totalOutputExceeded), .archive(.compressionRatioExceeded), .tooMuchText:
            message(.fileTooLarge, kind: .file)
        case .tooManyRows, .tooManyCells, .tooManySharedStrings:
            message(.tooManyRecords, kind: .file)
        case .noVisibleSheet:
            "보이는 시트가 없어요. 숨긴 시트는 가져오지 않으니 숨기기를 풀어 주세요."
        case .archive, .doctypeOrEntity, .unsupportedTextEncoding, .malformedXML, .nestingTooDeep, .tooManyAttributes, .notSpreadsheet,
             .textTooLong, .unsafeRelationshipTarget,
             .brokenRelationship, .unexpectedPart, .malformedPart, .sheetNotFound, .invalidSharedStringIndex, .invalidStyleIndex,
             .invalidCellReference, .unknownCellType, .invalidMergeRange:
            "이 엑셀 파일을 읽을 수 없어요. 엑셀에서 「Excel 통합 문서(.xlsx)」로 다시 저장해 주세요."
        }
    }

    /// 「머리글 예시」 절을 보일 사유 — 머리글을 고치면 풀리는 것
    public static func showsHeaderExample(_ problem: PackImportProblem) -> Bool {
        guard case .structural(let failure) = problem else { return false }
        switch failure {
        case .headerNotRecognized, .duplicateHeader, .duplicateHeaderAlias, .mixedModeHeader, .missingRequiredColumn, .tooManyColumns,
             .columnCountMismatch:
            return true
        default:
            return false
        }
    }

    /// 풋터 — 내용을 보이지 않는다는 말 + 구조 오류면 「통째로 받지 않는」 이유, 유효 0이면 건너뛴 행 안내
    public static func failureFooter(_ problem: PackImportProblem, source kind: PackImportSource.Kind) -> String {
        if case .noValidRecords = problem { return skippedFooter }
        let hidden = "\(kind == .file ? "파일" : "붙여 넣은") 내용은 보여 주지 않아요."
        return isStructure(problem) ? hidden + " 한 행이라도 구조가 틀리면 다른 행도 믿을 수 없어 통째로 받지 않아요." : hidden
    }

    /// 열 경계·머리글·정보 줄이 틀려 다른 행도 믿을 수 없는 사유(5-5 「구조 오류」) — 크기·인코딩·빈 파일은 아니다
    private static func isStructure(_ problem: PackImportProblem) -> Bool {
        guard case .structural(let failure) = problem else { return false }
        switch failure {
        case .quote, .columnCountMismatch, .headerNotRecognized, .duplicateHeader, .duplicateHeaderAlias, .mixedModeHeader,
             .missingRequiredColumn, .tooManyColumns, .metaAfterHeader, .duplicateMeta, .duplicateSourceMeta, .unknownMeta, .unsupportedEscapeMeta,
             .metaValueCount, .metaTooManyCells, .templateInPhrasesMode, .mergedHeaderOrMeta, .nonTextHeaderCell:
            return true
        // 엑셀 컨테이너·XML 거부는 「한 행이 틀려서」가 아니라 파일을 못 읽은 것이다
        case .fileTooLarge, .emptyFile, .unsupportedEncoding, .invalidUTF8AfterBOM, .invalidUTF16, .encodingDoesNotMatchBOM,
             .undecodable, .tooManyLines, .tooManyRecords, .workbook:
            return false
        }
    }

    // MARK: - 안

    /// 번호 범위는 쉼표 없이 — 번호는 개수가 아니라 단축어에 그대로 치는 식별자다(「사자성어 9999번」, 시안 4-F 「1~9999」). 개수·위치만 `number`
    private static let numberRangeText = "\(PackLimits.numberRange.lowerBound)~\(PackLimits.numberRange.upperBound)"
}
