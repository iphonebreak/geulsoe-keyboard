import TadakDomain

/// 외부 채움글 **폼·확정·완료** 문구 표 — 한 곳(계획서 `external-snippet-packs-1c-plan.md` 5절 5행, 시안 5-A·5-B·5-C·U3·4-M).
///
/// 규칙은 `PackNoticeCopy`·`PackImportCopy`와 같다: 해요체 · 「단축어」「채움글」 · 예산 한도 숫자 0(R2 — 보이는 숫자는 **필드 상한**
/// (이름 40자·권리 120자·틀 40자·틀 8개·앞 글자 2자·틀+번호 48자)과 개수뿐이고 상한 값은 `PackLimits`에서 온다) · 예시는 교회·성경 소재 0(U6) —
/// 단 「성경 구절과 겹침」 거부 사유 한 줄은 **키보드의 기존 성경 기능**을 가리키는 이유라 예외다(시안 5-C 표, 계획서 6단계 ③).
/// 4-J(가져오기 거부) 알림은 `PackChangeNotice`(`PackNoticeCopy` D1~D3)가 낸다. 문구 검사는 `PackFormCopyTests`가 `swift test`로 돈다.
public enum PackFormCopy {

    // MARK: - 5-A · 5-B 폼

    public static let formTitle = "팩 정보"
    public static let importButton = "가져오기"
    public static let cancel = "취소"
    public static let nameLabel = "이름"
    public static let namePlaceholder = "팩 이름"
    /// 파일 `#` 줄에서 미리 채운 칸의 꼬리표
    public static let fromFileTag = "파일에서"
    /// 둘째 틀부터의 꼬리표
    public static let aliasTag = "별칭"
    /// 파일에 `#이름`이 없을 때 — CSV에는 시트 이름이 없어 빈칸이다(5-6 「파일명은 쓰지 않는다」)
    public static let nameEmptyFromFile = "파일에 이름이 없어서 빈칸으로 시작했어요."
    public static let nameTooLongFromFile = "파일에 적힌 이름이 너무 길어서 비워 뒀어요."
    /// 같은 이름 팩이 있을 때 이름 칸 아래 — 누르기 전에 미리 알린다(U3)
    public static let sameNameHint = "같은 이름의 팩이 있어요. 가져오기를 누르면 바꿀지 물어봐요."
    /// 「따로 추가」 뒤 이름 칸 아래
    public static let separateHint = "다른 이름을 써 주세요. 같은 이름의 팩이 있어요."

    /// 입력칸 글자 수 — 「7/40」(시안). 상한은 `PackLimits`
    public static func counter(_ text: String, limit: PackLimits.FieldLimit) -> String { "\(PackNoticeCopy.number(text.count))/\(PackNoticeCopy.number(limit.characters))" }

    public static let templatesHeader = "단축어 틀 — {n}에 번호가 들어가요"
    public static let templatePlaceholder = "예: 사자성어 {n}번"
    public static let addTemplate = "틀 추가"
    public static let removeTemplate = "틀 지우기"
    public static let chipPreviewHeader = "이렇게 칩이 떠요"
    /// 10-1 — 「틀+번호는 공백 포함 48자 이내」(최대 확장 40 + 4자리 = 44 ≤ `committedTail` 48)
    public static let templatesFooter = "앞 글자는 2자 이상, {n}은 한 번만 써요. 틀+번호는 띄어쓰기 포함 48자 이내로 써 주세요. "
        + "틀은 \(PackNoticeCopy.number(PackLimits.templatePatterns))개까지예요."
    public static let reviewFooter = "빨간 표시가 있으면 가져올 수 없어요. 주황 표시는 알림이에요."

    public static let licenseHeader = "권리 표기(꼭 필요해요)"
    public static let customLicensePlaceholder = "권리 표기를 직접 써요"
    public static let licenseTooLongFromFile = "파일에 적힌 권리 표기가 너무 길어서 보여 드리지 못했어요. 고르거나 직접 써 주세요."

    /// 권리 선택지(R7) — 고른 선택지의 이 문구가 권리 표기로 저장된다(「파일에 적힌 표기」·「그 밖」은 그 원문·입력)
    public static func licenseLabel(_ choice: PackImportForm.LicenseChoice) -> String {
        switch choice {
        case .fromFile: "파일에 적힌 표기"
        case .selfWritten: "직접 작성함"
        case .permitted: "사용 허락을 받음"
        case .publicDomain: "공개 도메인"
        case .custom: "그 밖(직접 입력)"
        }
    }

    /// 시안 5-A·5-B 권리 절 풋터 — 선택지는 권리 증명이 아니다(R7)
    public static func licenseFooter(hasFileLicense: Bool) -> String {
        (hasFileLicense ? "파일에 적힌 문구는 고치지 않고 그대로 보여 줘요. " : "")
            + "하나를 직접 골라야 「가져오기」가 켜져요. 선택지는 권리를 증명하지 않아요. 이 내용을 쓸 권리가 있는지는 가져오는 분이 직접 확인해 주세요."
    }

    // MARK: - 5-C 틀 검사

    /// 빨강 — 시안 5-C 「틀 검사 문구」 표. 번호는 문구에 넣지 않는다(성경 겹침 번호도)
    public static func templateFailure(_ failure: TemplatePatternSpec.Failure) -> String {
        switch failure {
        case .placeholderCount: "{n}이 꼭 한 번 있어야 해요"
        case .prefixTooShort: "앞 글자가 2자 이상이어야 해요"
        case .prefixEndsWithDigit, .prefixAllDigits: "앞 글자가 숫자로 끝나면 번호와 붙어 읽혀요. 끝에 글자를 넣어 주세요"
        case .suffixEmpty: "{n} 뒤에 글자가 한 자 이상 있어야 해요"
        case .literalContainsNewline: "틀에는 줄바꿈을 쓸 수 없어요"
        case .reservedDateSuffix: "「날짜」「시간」「시각」으로 끝나면 날짜 채움글과 겹쳐요"
        case .literalTooLong: "틀은 \(PackNoticeCopy.number(PackLimits.templateLiteral.characters))자까지예요. 틀+번호는 띄어쓰기 포함 48자 이내로 써 주세요"
        case .collidesWithBible: "내장 성경 채움글의 구절 단축어와 겹쳐요"
        }
    }

    /// 빨강 둘째 줄(예) — 시안이 예를 단 사유만
    public static func templateFailureExample(_ failure: TemplatePatternSpec.Failure) -> String? {
        switch failure {
        case .prefixTooShort: "예: 사자성어 {n}번"
        case .reservedDateSuffix: "예: 회차{n}시간"
        default: nil
        }
    }

    /// 주황 첫 줄 — 위 팩의 같은 틀(10-4) · 정적 단축어 가림(10-3). 통과·빈 칸·빨강은 nil
    public static func reviewTitle(_ status: PackTemplateReview.Status, name: (String) -> String) -> String? {
        switch status {
        case .outranked(let owner): "「\(name(owner))」도 이 틀을 써요"
        case .shadowed(let triggers, let owner):
            "\(shadowOwner(owner, name: name))\(quoted(triggers))에 가려져요"
        case .empty, .ok, .invalid: nil
        }
    }

    /// 주황 둘째 줄 — 「누가 먼저 뜨나」를 그 입력의 범위로 말한다(시안 5-C·4-I 꼴 — 가림은 그 끝말로 끝나는 입력에서만이다)
    /// - Parameter replacing: 같은 이름 팩을 바꾸는 자리면 「맨 아래」가 아니다(U3)
    public static func reviewDetail(_ status: PackTemplateReview.Status, replacing: Bool, name: (String) -> String) -> String? {
        switch status {
        case .outranked(let owner):
            let ownerName = name(owner)
            return (replacing ? "목록에서 " : "새 팩은 목록 맨 아래에 붙어서 ")
                + "위에 있는 「\(ownerName)」\(PackNoticeCopy.subjectParticle(after: ownerName)) 이 틀을 가져요."
        case .shadowed(let triggers, let owner):
            let trigger = triggers.first ?? ""
            let many = triggers.count > 1
            return "「…\(trigger)」\(many ? " 등" : "")\(PackNoticeCopy.directionParticle(after: many ? "등" : trigger)) "
                + "끝나는 입력에서는 \(shadowSubject(owner, name: name)) 먼저 떠요."
        case .empty, .ok, .invalid: return nil
        }
    }

    /// 「내 채움글 」·「「팩」의 단축어 」·「내장 팩 단축어 」·「단축어 」
    private static func shadowOwner(_ owner: PackImpact.Source?, name: (String) -> String) -> String {
        switch owner {
        case .userSnippets?: "내 채움글 "
        case .pack(let id)?: "「\(name(id))」의 단축어 "
        case .builtIn?: "내장 팩 단축어 "
        case nil: "단축어 "
        }
    }

    /// 「내 채움글이」·「「팩」의 단축어가」·「내장 팩 단축어가」·「그 단축어가」
    private static func shadowSubject(_ owner: PackImpact.Source?, name: (String) -> String) -> String {
        switch owner {
        case .userSnippets?: "내 채움글이"
        case .pack(let id)?: "「\(name(id))」의 단축어가"
        case .builtIn?: "내장 팩 단축어가"
        case nil: "그 단축어가"
        }
    }

    /// 「「장」」·「「장」 외 1개」
    private static func quoted(_ triggers: [String]) -> String {
        let first = "「\(triggers.first ?? "")」"
        return triggers.count > 1 ? "\(first) 외 \(PackNoticeCopy.number(triggers.count - 1))개" : first
    }

    /// 최종 검사(확정 때 `PackCompiler`)가 거부한 칸 — 폼이 그 칸 아래에 보인다. 폼이 미리 막는 사유도 빠짐없이 둔다
    public static func compileFailure(_ failure: PackCompileFailure) -> String {
        switch failure {
        case .nameMissing: "이름을 써 주세요."
        case .nameTooLong: "이름은 \(PackNoticeCopy.number(PackLimits.name.characters))자까지예요."
        case .licenseMissing: "권리 표기를 골라 주세요."
        case .licenseTooLong: "권리 표기는 \(PackNoticeCopy.number(PackLimits.license.characters))자까지예요."
        case .templateRequired: "틀을 하나 이상 써 주세요."
        case .tooManyPatterns: "틀은 \(PackNoticeCopy.number(PackLimits.templatePatterns))개까지예요."
        case .pattern(_, let pattern): templateFailure(pattern)
        // 폼으로는 생길 수 없는 사유(문구형에 틀 · 받을 항목 0) — 내용 없이 처음부터
        case .templateNotAllowed, .noValidRecords: "문제가 생겨서 가져오지 못했어요. 처음부터 다시 해 주세요."
        }
    }

    // MARK: - U3 같은 이름

    public static let sameNameTitle = "같은 이름의 팩이 있어요"

    public static func sameNameMessage(_ name: String) -> String {
        "「\(name)」\(PackNoticeCopy.subjectParticle(after: name)) 이미 있어요. 바꾸면 목록 자리와 켬/끔은 그대로고 내용만 새 파일로 바뀌어요."
    }

    public static let replaceButton = "바꾸기"
    public static let separateButton = "따로 추가"

    // MARK: - 4-M 완료

    /// 완료 화면 제목 줄(내비게이션 제목)
    public static let doneHeader = "가져오기"

    public static func doneTitle(_ kind: PackImportCompletion.Kind) -> String {
        switch kind {
        case .imported: "가져왔어요"
        case .importedDisabled: "꺼 둔 채로 가져왔어요"
        case .replaced: "바꿨어요"
        }
    }

    /// 「「사자성어 예시 팩」 · 641개」
    public static func doneSummary(name: String, count: Int) -> String { "「\(name)」 · \(PackNoticeCopy.number(count))개" }

    public static func skippedLine(_ count: Int) -> String { "건너뛴 \(PackNoticeCopy.number(count))개는 가져오지 않았어요." }

    public static let tryHeader = "이렇게 써 보세요"
    public static let nextTimeLine = "키보드가 다음에 뜰 때부터 써요."
    /// 꺼진 채로 들어왔거나(D1·D2) 꺼진 팩을 바꿨을 때
    public static let disabledLine = "꺼져 있어서 지금은 안 떠요. 채움글 화면에서 팩을 눌러 켜면 써요."
    public static let replacedLine = "목록 자리와 켬/끔은 그대로예요."
    public static let backToSnippets = "채움글로 돌아가기"
}
