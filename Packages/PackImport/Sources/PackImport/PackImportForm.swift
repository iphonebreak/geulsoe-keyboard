import TadakDomain

/// 가져오기 폼(시안 5-A 번호형 · 5-B 문구형 — PDR `external-snippet-packs.md` 5-6·R7, AC-20, 계획서 5절 5행 ①).
///
/// - **모드별 필수 칸이 다르다(AC-20):** 번호형 = 이름 · 틀(별칭 포함, 첫 칸이 칩 제목) · 출처, 문구형 = 이름 · 출처(**틀 칸이 아예 없다**).
/// - **파일의 `#` 줄은 미리 채움, 폼이 최종 권위(5-6).** 파일명은 쓰지 않는다. `#이름`이 없는 xlsx는 시트 이름이 이름 칸 기본값이다(6-4). 상한을 넘은 파일 값은 채우지 않고 빈칸으로 시작한다(`meta.issues`).
/// - **출처는 필수다**(화면 이름 「출처」 — R27, 코드 식별자는 `license` 그대로). **파일에 `#출처`(옛 `#권리`)가 있으면 그 원문을 미리 골라 둔다**
///   (R28 — 시안 리뷰 수정 1 「미리 고르지 않는다」를 바꿨다). 파일에 없거나 상한을 넘어 미리 채우지 않았으면 비어 있고 「가져오기」가 꺼진다(AC-20).
///   선택지는 **증명이 아니다**(R7). 파일에 적힌 제작자 문구는 선택지로 덮지 않고 원문 그대로 첫 선택지로 보인다. 폼이 최종 권위라 바꿀 수 있다.
/// - 칸 검사는 `PackCompiler`의 같은 함수(`nameFailure`·`licenseFailure`·`cleanedTemplate` + `TemplatePatternSpec.parse`)다 —
///   「가져오기」가 켜졌는데 최종 컴파일이 거부하는 칸이 없다. 성경 전체 n 검사(10-2)만 비싸서 `PackTemplateReview`가 메인 밖에서 한다.
///
/// 이름·출처·틀은 사용자 입력이다 — 메모리에만 있고 로그·분석 이벤트로 내보내지 않는다(보안 규칙).
public struct PackImportForm: Equatable, Sendable {

    /// 출처 선택지(R7) — 「파일에 적힌 출처」는 파일에 `#출처`(옛 `#권리`)가 있을 때만
    public enum LicenseChoice: Hashable, Sendable, CaseIterable {
        case fromFile
        case selfWritten
        case permitted
        case publicDomain
        /// 그 밖(직접 입력) — 아래 입력칸(120자)
        case custom
    }

    public let mode: ExternalPack.Mode
    /// 파일에서 읽은 미리 채움 — 「파일에서」 꼬리표와 제작자 출처 문구
    public let meta: PackMetaPrefill
    public var name: String
    /// 번호형 틀 칸(별칭 순서) — 문구형은 언제나 비었다
    public private(set) var templates: [String]
    /// 고른 출처 — nil이면 아직 고르지 않았다(가져오기 꺼짐). 파일에 출처가 있으면 처음부터 `.fromFile`(R28)
    public var licenseChoice: LicenseChoice?
    /// 「그 밖(직접 입력)」 칸 — 다른 선택지로 옮겨도 남겨 둔다(돌아오면 다시 보인다)
    public var customLicense: String
    /// 칩 미리보기에 쓰는 파일의 첫 번호 항목(번호형)
    private let exampleItem: PackTemplateItem?

    public init(draft: PackDraft) {
        mode = draft.mode
        meta = draft.meta
        exampleItem = draft.items.first
        // `#이름`이 먼저, 없으면 (xlsx) 시트 이름 — 앱이 붙인 `Sheet1`·`시트1`이나 상한을 넘는 이름은 빈칸(6-4, 1-e ③)
        name = draft.meta.name ?? draft.suggestedPackName ?? ""
        switch draft.mode {
        case .phrases: templates = []
        case .numbered: templates = draft.meta.templateSpecs.isEmpty ? [""] : Array(draft.meta.templateSpecs.prefix(PackLimits.templatePatterns))
        }
        licenseChoice = draft.meta.license == nil ? nil : .fromFile
        customLicense = ""
    }

    // MARK: - 출처

    public var licenseChoices: [LicenseChoice] {
        LicenseChoice.allCases.filter { $0 != .fromFile || meta.license != nil }
    }

    /// 저장될 출처 — 고른 선택지의 문구(파일 문구는 원문, 「그 밖」은 직접 입력). 고르지 않았으면 nil
    public var license: String? {
        switch licenseChoice {
        case nil: nil
        case .fromFile: meta.license
        case .custom: customLicense
        case .selfWritten?, .permitted?, .publicDomain?: licenseChoice.map(PackFormCopy.licenseLabel)
        }
    }

    // MARK: - 틀 칸

    public var canAddTemplate: Bool { mode == .numbered && templates.count < PackLimits.templatePatterns }
    public var canRemoveTemplate: Bool { templates.count > 1 }

    public mutating func setTemplate(_ text: String, at index: Int) {
        guard templates.indices.contains(index) else { return }
        templates[index] = text
    }

    public mutating func addTemplate() {
        guard canAddTemplate else { return }
        templates.append("")
    }

    public mutating func removeTemplate(at index: Int) {
        guard canRemoveTemplate, templates.indices.contains(index) else { return }
        templates.remove(at: index)
    }

    // MARK: - 검사 — `PackCompiler`와 같은 함수

    /// 이름 칸 사유 — `nameMissing`·`nameTooLong`
    public var nameIssue: PackCompileFailure? { PackCompiler.nameFailure(name) }

    /// 출처 사유 — 고르지 않았거나 직접 입력이 비면 `licenseMissing`, 직접 입력이 120자를 넘으면 `licenseTooLong`
    public var licenseIssue: PackCompileFailure? {
        guard let license else { return .licenseMissing }
        return PackCompiler.licenseFailure(license)
    }

    /// 틀 칸 하나의 즉시 검사(10-1 스키마) — 빈 칸·통과면 nil. 성경 겹침은 `PackTemplateReview`
    public func templateFailure(at index: Int) -> TemplatePatternSpec.Failure? {
        guard mode == .numbered, templates.indices.contains(index) else { return nil }
        let cleaned = PackCompiler.cleanedTemplate(templates[index])
        guard !cleaned.isEmpty, case .failure(let failure) = TemplatePatternSpec.parse(cleaned) else { return nil }
        return failure
    }

    /// 틀 사유 — 번호형인데 모두 비었으면 `templateRequired`, 아니면 첫 스키마 실패(칸 순번은 화면 칸 그대로 — F7)
    public var templateIssue: PackCompileFailure? {
        guard mode == .numbered else { return nil }
        if templates.allSatisfy({ PackCompiler.cleanedTemplate($0).isEmpty }) { return .templateRequired }
        for index in templates.indices {
            if let failure = templateFailure(at: index) { return .pattern(index: index, failure) }
        }
        return nil
    }

    /// 필수 칸이 다 찼고 빨간 표시(스키마)가 없다 — 「가져오기」가 켜지는 조건. 성경 겹침은 확정 때 최종 컴파일이 다시 막는다
    public var isComplete: Bool { nameIssue == nil && licenseIssue == nil && templateIssue == nil }

    /// 최종 컴파일 입력(`PackCompiler.compile`)
    public var packForm: PackForm {
        PackForm(name: name, license: license ?? "", templateSpecs: mode == .numbered ? templates : [])
    }

    /// 5-A 「이렇게 칩이 떠요」 — 칩 제목 형식(첫 비지 않은 틀 칸, `PackCompiler`와 같은 자리)에 파일의 첫 번호를 넣은 모양.
    /// 팩 상세·완료 화면과 같은 함수(`PackDetail.examples`). 그 칸이 규칙에 맞지 않거나 문구형이면 nil
    public var chipExample: PackDetail.Example? {
        guard mode == .numbered, let item = exampleItem,
              let format = templates.lazy.map(PackCompiler.cleanedTemplate).first(where: { !$0.isEmpty }),
              case .success = TemplatePatternSpec.parse(format) else { return nil }
        return PackDetail.examples(of: ExternalPack(name: "", license: "", mode: .numbered,
                                                    template: PackTemplate(patterns: [], titleFormat: format, items: [item]))).first
    }

    // MARK: - 「파일에서」 꼬리표

    public var isNameFromFile: Bool { meta.name.map { $0 == name } ?? false }

    public func isTemplateFromFile(at index: Int) -> Bool {
        meta.templateSpecs.indices.contains(index) && templates.indices.contains(index) && meta.templateSpecs[index] == templates[index]
    }

    // MARK: - 같은 이름(U3)

    /// 목록에서 이름이 같은 **첫** 팩(목록 순서) — 앞뒤 공백만 무시한다. 이름을 모르는 팩은 맞지 않는다.
    /// 읽을 수 없는 팩도 맞는다 — 같은 이름으로 다시 가져와 바꾸면 복구된다(계획서 8절 #7)
    public func sameNamePack(in packs: [PackSummary]) -> PackSummary? {
        let key = Self.nameKey(name)
        guard !key.isEmpty else { return nil }
        return packs.first { $0.name.map(Self.nameKey) == key }
    }

    static func nameKey(_ name: String) -> String {
        PackTextSanitizer.sanitize(name).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
