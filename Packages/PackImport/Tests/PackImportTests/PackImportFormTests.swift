import Foundation
import Testing
import KeyboardCore
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c 5단계 — 폼·틀 검사·확정·완료(계획서 `external-snippet-packs-1c-plan.md` 5절 5행, 3-4절 5-A·5-B·5-C, 4-2절 D1~D3·G1·G2, 8절 #5).
// PDR `external-snippet-packs.md` 5-6(R7 — 폼이 최종 권위, 출처 필수·선택지는 증명이 아님 · R27 「권리」→「출처」 · R28 파일 출처를 미리 고름)·9-1·9-2(커밋 직전 재검사)·10-1(R3 틀 규칙)·10-2~10-4,
// E표 U2(켠 채 맨 아래 · 넘으면 「꺼 둔 채로」)·U3(같은 이름은 묻는다), AC-3·AC-20·AC-21~24.
// 확정 흐름은 실제 `PackStore`(임시 폴더)로 돈다 — 「버튼이 켜졌는데 저장소가 거부」·「꺼 둔 채로가 기존 팩을 밀어냄」 같은 틈은 표가 아니라 저장소에서 보인다.

// MARK: - 시험 도구

private final class FormGenerations: PackGenerationWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var user = 0
    private var packs = 0
    var userSnippetsGeneration: Int { lock.withLock { user } }
    var packsGeneration: Int { lock.withLock { packs } }
    func setUserSnippetsGeneration(_ value: Int) { lock.withLock { user = value } }
    func setPacksGeneration(_ value: Int) { lock.withLock { packs = value } }
}

private final class FormSnippets: UserSnippetStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SnippetEntry]
    init(_ entries: [SnippetEntry]) { stored = entries }
    func entries() -> [SnippetEntry] { lock.withLock { stored } }
    func save(_ entries: [SnippetEntry]) -> Bool { lock.withLock { stored = entries; return true } }
}

private final class FormIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> String { lock.withLock { value += 1; return "pack\(value)" } }
}

/// 임시 폴더의 실제 저장소 — 화면이 쓰는 `PackStoreClient`(메인 밖)로 부른다
private struct Store {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("packform-\(UUID().uuidString)", isDirectory: true)
    let user: FormSnippets
    let store: PackStore
    var client: PackStoreClient { PackStoreClient(store: store) }

    init(user: [SnippetEntry] = [], limits: PackBudgetLimits = .candidate) {
        let ids = FormIDs()
        let user = FormSnippets(user)
        self.user = user
        store = PackStore(libraryRoot: root.appendingPathComponent("library", isDirectory: true),
                          snapshotRoot: root.appendingPathComponent("snapshot", isDirectory: true),
                          generations: FormGenerations(), userSnippets: user,
                          builtInEntries: { _ in [] }, disabledBuiltIns: { [] }, notify: {}, makeID: { ids.next() }, limits: limits)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
    var library: PackImpact.Library? { store.impactLibrary() }
}

private let numberedCSV = "#이름,사자성어 예시 팩\n#틀,사자성어 {n}번,성어 {n}번\n#출처,제작자 자체 작성 예시 (가짜 내용)\n"
    + "번호,제목,본문\n1,예시 제목 하나,예시 본문 하나\n12,예시 제목 둘,예시 본문 둘\n"
private let phrasesCSV = "단축어,제목,본문\n회사주소,회사 주소,예시 주소 한 줄\n새해인사,새해 인사,예시 인사 한 줄\n"

private func numberedDraft() throws -> PackDraft { try ImportHelper.draft(numberedCSV) }
private func phrasesDraft() throws -> PackDraft { try ImportHelper.draft(phrasesCSV) }

/// 문구형 팩 — 단축어 `count`개(정규화 글자 수 = 접두 길이 + 번호)
private func phrasesPack(_ name: String, prefix: String, count: Int) -> ExternalPack {
    ExternalPack(name: name, license: "자체 작성", mode: .phrases,
                 entries: (0..<count).map { SnippetEntry(trigger: "\(prefix)\($0)", title: "\(name) \($0)", body: "본문 \($0)") })
}

private func numberedPack(_ name: String, template: String) -> ExternalPack {
    let pattern = try! TemplatePatternSpec.parse(template).get()
    return ExternalPack(name: name, license: "자체 작성", mode: .numbered, template: PackTemplate(
        patterns: [pattern], titleFormat: template, items: [PackTemplateItem(n: 1, title: "제목", body: "본문")]))
}

/// 다 채운 폼 — 이름·출처(직접 작성함)·틀은 파일 값 그대로
private func filledForm(_ draft: PackDraft, name: String? = nil) -> PackImportForm {
    var form = PackImportForm(draft: draft)
    if let name { form.name = name }
    form.licenseChoice = .selfWritten
    return form
}

/// 메인 밖 확정을 끝까지 — `perform` 결과를 그 일과 함께 상태기계에 돌려준다(화면 `PackImportFormView.run`과 같은 길)
private func run(_ confirmation: inout PackImportConfirmation, _ work: PackImportConfirmation.Work?,
                 client: PackStoreClient) async throws {
    let work = try #require(work)
    let result = await PackImportConfirmation.perform(work, client: client)
    let received = confirmation.receive(result, for: work)
    #expect(received)
}

private extension PackImportConfirmation {
    var notice: PackChangeNotice? {
        if case .rejected(let notice) = phase { return notice }
        return nil
    }
    var completion: PackImportCompletion? {
        if case .completed(let completion) = phase { return completion }
        return nil
    }
}

private func string(_ count: Int, _ character: Character = "가") -> String { String(repeating: character, count: count) }

// MARK: - ① 폼 — 필수 칸 분리(AC-20) · 출처 미선택이면 꺼짐(파일에 출처가 있으면 미리 고름, R28) · 상한

@Suite("외부 채움글 1-c 5단계 — 폼 (5-A·5-B · AC-20)")
struct PackImportFormTests {

    @Test("★ R28 번호형 — 파일 정보는 미리 채움, 파일의 `#출처`는 **미리 골라 두고** 가져오기가 켜진다")
    func numberedPrefill() throws {
        let form = PackImportForm(draft: try numberedDraft())
        #expect(form.mode == .numbered)
        #expect(form.name == "사자성어 예시 팩" && form.isNameFromFile)
        #expect(form.templates == ["사자성어 {n}번", "성어 {n}번"])
        #expect(form.isTemplateFromFile(at: 0) && form.isTemplateFromFile(at: 1))
        #expect(form.licenseChoice == .fromFile)
        #expect(form.licenseChoices == [.fromFile, .selfWritten, .permitted, .publicDomain, .custom])
        #expect(form.meta.license == "제작자 자체 작성 예시 (가짜 내용)")
        #expect(form.license == "제작자 자체 작성 예시 (가짜 내용)")
        #expect(form.licenseIssue == nil && form.isComplete)
        #expect(form.packForm.license == "제작자 자체 작성 예시 (가짜 내용)")
    }

    @Test("★ R28 — 옛 `#권리`도 같은 출처라 미리 고른다(이미 받은 샘플·옛 파일)", arguments: ["#출처", "#권리"])
    func legacyKeyIsPreselected(key: String) throws {
        let form = PackImportForm(draft: try ImportHelper.draft("\(key),옛 파일의 출처\n단축어,제목,본문\n회사주소,회사 주소,본문\n"))
        #expect(form.licenseChoice == .fromFile && form.license == "옛 파일의 출처")
        #expect(form.licenseChoices.first == .fromFile)
    }

    @Test("★ R28 — 파일에 출처가 없으면 지금처럼 비어 있고 꺼짐(AC-20) · 고르면 켜진다")
    func noSourceStaysUnselected() throws {
        var form = PackImportForm(draft: try ImportHelper.draft("#이름,우리 회사 상용구\n단축어,제목,본문\n회사주소,회사 주소,본문\n"))
        #expect(form.licenseChoice == nil && form.license == nil)
        #expect(form.licenseIssue == .licenseMissing && !form.isComplete)
        form.licenseChoice = .selfWritten
        #expect(form.isComplete)
    }

    @Test("R28 — 미리 고른 것은 바꿀 수 있고, 「그 밖」으로 옮겼다 비우면 다시 꺼진다(폼이 최종 권위)")
    func preselectionCanBeChanged() throws {
        var form = PackImportForm(draft: try numberedDraft())
        form.licenseChoice = .permitted
        #expect(form.license == "사용 허락을 받음" && form.isComplete)
        form.licenseChoice = .custom
        #expect(form.licenseIssue == .licenseMissing && !form.isComplete)
        form.licenseChoice = .fromFile
        #expect(form.isComplete)
    }

    @Test("문구형 — 틀 칸이 없다(AC-20), 파일에 이름·출처가 없으면 빈칸·「파일에 적힌 출처」 선택지 없음")
    func phrasesHasNoTemplate() throws {
        var form = PackImportForm(draft: try phrasesDraft())
        #expect(form.mode == .phrases && form.templates.isEmpty && !form.canAddTemplate)
        #expect(form.name.isEmpty && !form.isNameFromFile)
        #expect(form.licenseChoice == nil)
        #expect(form.licenseChoices == [.selfWritten, .permitted, .publicDomain, .custom])
        form.addTemplate()
        #expect(form.templates.isEmpty)
        form.name = "우리 회사 상용구"
        form.licenseChoice = .publicDomain
        #expect(form.isComplete)
        #expect(form.packForm == PackForm(name: "우리 회사 상용구", license: "공개 도메인", templateSpecs: []))
    }

    /// 표 — (이름, 출처 선택, 직접 입력, 틀) → (이름 사유, 출처 사유, 틀 사유)
    @Test("★ 검증 표 — 이름 40 · 출처(직접 입력) 120 · 틀 필수(번호형) · 틀 스키마", arguments: [
        ("이름", PackImportForm.LicenseChoice?.some(.selfWritten), "", ["사자성어 {n}번"], nil, nil, nil),
        ("이름", nil, "", ["사자성어 {n}번"], nil, PackCompileFailure.licenseMissing, nil),
        ("", .selfWritten, "", ["사자성어 {n}번"], .nameMissing, nil, nil),
        ("   ", .selfWritten, "", ["사자성어 {n}번"], .nameMissing, nil, nil),
        (string(40), .selfWritten, "", ["사자성어 {n}번"], nil, nil, nil),
        (string(41), .selfWritten, "", ["사자성어 {n}번"], .nameTooLong, nil, nil),
        ("이름", .custom, "", ["사자성어 {n}번"], nil, .licenseMissing, nil),
        ("이름", .custom, "  ", ["사자성어 {n}번"], nil, .licenseMissing, nil),
        ("이름", .custom, string(120), ["사자성어 {n}번"], nil, nil, nil),
        ("이름", .custom, string(121), ["사자성어 {n}번"], nil, .licenseTooLong, nil),
        ("이름", .fromFile, "", ["사자성어 {n}번"], nil, nil, nil),
        ("이름", .selfWritten, "", [""], nil, nil, .templateRequired),
        ("이름", .selfWritten, "", ["", "  "], nil, nil, .templateRequired),
        ("이름", .selfWritten, "", ["", "성{n}번"], nil, nil, .pattern(index: 1, .prefixTooShort)),
        ("이름", .selfWritten, "", ["", "사자성어 {n}번"], nil, nil, nil)
    ] as [(String, PackImportForm.LicenseChoice?, String, [String], PackCompileFailure?, PackCompileFailure?, PackCompileFailure?)])
    func validationTable(name: String, choice: PackImportForm.LicenseChoice?, custom: String, templates: [String],
                         nameIssue: PackCompileFailure?, licenseIssue: PackCompileFailure?, templateIssue: PackCompileFailure?) throws {
        let draft = try numberedDraft()
        var form = PackImportForm(draft: draft)
        form.name = name
        form.licenseChoice = choice
        form.customLicense = custom
        for (index, text) in templates.enumerated() {
            if index >= form.templates.count { form.addTemplate() }
            form.setTemplate(text, at: index)
        }
        while form.templates.count > templates.count { form.removeTemplate(at: form.templates.count - 1) }
        #expect(form.nameIssue == nameIssue)
        #expect(form.licenseIssue == licenseIssue)
        #expect(form.templateIssue == templateIssue)
        #expect(form.isComplete == (nameIssue == nil && licenseIssue == nil && templateIssue == nil))

        // ★ 폼이 켠 「가져오기」와 최종 컴파일이 같은 판정이다 — 켜졌으면 컴파일이 통과하고, 꺼진 사유는 컴파일의 거부 사유와 같다
        do throws(PackCompileFailure) {
            _ = try PackCompiler.compile(draft, form: form.packForm)
            #expect(form.isComplete)
        } catch {
            #expect(!form.isComplete)
            #expect(error == nameIssue ?? licenseIssue ?? templateIssue)
        }
    }

    @Test("출처 — 고른 선택지가 출처가 된다. 파일 문구는 원문 그대로, 「그 밖」은 직접 입력")
    func licenseResolution() throws {
        var form = PackImportForm(draft: try numberedDraft())
        #expect(form.license == "제작자 자체 작성 예시 (가짜 내용)")   // R28 — 파일 출처를 미리 골랐다
        let expected: [(PackImportForm.LicenseChoice, String)] = [
            (.fromFile, "제작자 자체 작성 예시 (가짜 내용)"), (.selfWritten, "직접 작성함"), (.permitted, "사용 허락을 받음"),
            (.publicDomain, "공개 도메인")
        ]
        for (choice, text) in expected {
            form.licenseChoice = choice
            #expect(form.license == text)
        }
        form.licenseChoice = .custom
        form.customLicense = "우리 회사 총무팀 자체 작성"
        #expect(form.license == "우리 회사 총무팀 자체 작성")
        // 직접 입력은 다른 선택지로 옮겨도 남아 있다(돌아오면 다시 보인다) — 출처는 고른 것 하나
        form.licenseChoice = .publicDomain
        #expect(form.license == "공개 도메인" && form.customLicense == "우리 회사 총무팀 자체 작성")
    }

    @Test("파일 값이 상한을 넘어 미리 채우지 않은 칸 — 빈칸으로 시작하고 사유를 알린다(5-6) · 출처는 미리 고르지 않는다(R28)")
    func overlongMetaIsNotPrefilled() throws {
        let csv = "#이름,\(string(41))\n#출처,\(string(121))\n단축어,제목,본문\n회사주소,회사 주소,본문\n"
        let form = PackImportForm(draft: try ImportHelper.draft(csv))
        #expect(form.name.isEmpty && form.meta.issues == [.nameTooLong, .licenseTooLong])
        #expect(!form.licenseChoices.contains(.fromFile))
        #expect(form.licenseChoice == nil && !form.isComplete)
    }

    @Test("틀 칸 — 8개까지 추가, 마지막 한 칸은 지우지 않는다, 고치면 「파일에서」가 사라진다")
    func templateRows() throws {
        var form = PackImportForm(draft: try numberedDraft())
        for _ in 0..<10 { form.addTemplate() }
        #expect(form.templates.count == PackLimits.templatePatterns && !form.canAddTemplate)
        for _ in 0..<10 { form.removeTemplate(at: 0) }
        #expect(form.templates.count == 1 && !form.canRemoveTemplate)
        #expect(!form.isTemplateFromFile(at: 0))   // 남은 칸은 새로 더한 빈 칸

        var edited = PackImportForm(draft: try numberedDraft())
        edited.setTemplate("고사성어 {n}번", at: 0)
        #expect(!edited.isTemplateFromFile(at: 0) && edited.isTemplateFromFile(at: 1))
        edited.name = "바꾼 이름"
        #expect(!edited.isNameFromFile)
    }

    @Test("5-A 칩 미리보기 — 첫 비지 않은 틀(칩 제목 형식)에 첫 번호, 그 칸이 틀리면 없음, 문구형은 없음")
    func chipExample() throws {
        var form = PackImportForm(draft: try numberedDraft())
        #expect(form.chipExample == PackDetail.Example(trigger: "사자성어 1번", title: "예시 제목 하나", body: "예시 본문 하나"))
        form.setTemplate("", at: 0)
        #expect(form.chipExample == PackDetail.Example(trigger: "성어 1번", title: "예시 제목 하나", body: "예시 본문 하나"))
        form.setTemplate("성{n}번", at: 0)
        #expect(form.chipExample == nil)
        #expect(PackImportForm(draft: try phrasesDraft()).chipExample == nil)
    }

    @Test("파일에 틀이 없는 번호형 — 빈 칸 하나로 시작하고 틀이 필수다(PDR 5-3 ⑤ 「#틀 없어도 파싱, 컴파일에서 필수」)")
    func numberedWithoutTemplateMeta() throws {
        let form = filledForm(try ImportHelper.draft("번호,제목,본문\n1,예시 제목,예시 본문\n"), name: "이름")
        #expect(form.templates == [""] && form.templateIssue == .templateRequired && !form.isComplete)
    }
}

// MARK: - ① 같은 이름(U3)

@Suite("외부 채움글 1-c 5단계 — 같은 이름 판정 (U3)")
struct PackImportSameNameTests {

    private func summary(_ id: String, _ name: String?, status: PackSummary.Status = .on) -> PackSummary {
        PackSummary(id: id, name: name, mode: .phrases, itemCount: 1, titleFormat: nil, isEnabled: true, status: status)
    }

    @Test("이름이 같은 첫 팩 — 앞뒤 공백은 보지 않는다, 이름 모르는 팩은 맞지 않는다, 읽을 수 없는 팩도 맞는다(8절 #7)")
    func sameName() throws {
        let packs = [summary("a", nil), summary("b", "우리 회사 상용구 ", status: .unavailable), summary("c", "우리 회사 상용구"),
                     summary("d", "다른 팩")]
        var form = filledForm(try phrasesDraft(), name: " 우리 회사 상용구")
        #expect(form.sameNamePack(in: packs)?.id == "b")
        form.name = "우리 회사  상용구"
        #expect(form.sameNamePack(in: packs) == nil)
        form.name = "이름 없는 팩"
        #expect(form.sameNamePack(in: packs) == nil)
        form.name = ""
        #expect(form.sameNamePack(in: [summary("e", "")]) == nil)
    }
}

// MARK: - ② 틀 검사(5-C) — 10-1 규칙 · 성경 전체 n · 소유·가림

@Suite("외부 채움글 1-c 5단계 — 틀 검사 (5-C · 10-1 · AC-21~24)")
struct PackTemplateReviewTests {

    @Test("★ 10-1 규칙 — 빨강(거부) 사유가 칸마다 나온다, 폼의 즉시 검사와 같은 사유", arguments: [
        ("사자성어 {n}번", nil),
        ("{n}번", TemplatePatternSpec.Failure.prefixTooShort),
        ("성{n}번", .prefixTooShort),
        ("성 {n}번", .prefixTooShort),
        ("회차2{n}번", .prefixEndsWithDigit),
        ("12{n}번", .prefixAllDigits),
        ("사자성어{n}", .suffixEmpty),
        ("사자성어 {n}  ", .suffixEmpty),
        ("사자성어 번", .placeholderCount),
        ("사자성어 {n}번 {n}", .placeholderCount),
        ("회차{n}시간", .reservedDateSuffix),
        ("회차{n}번날짜", .reservedDateSuffix),
        ("회차{n}시각", .reservedDateSuffix),
        ("가나다라마바사아자차카타파하가나다라마바 {n}가나다라마바사아자차카타파하가나다라마바사", .literalTooLong),
        ("사자\n성어 {n}번", .literalContainsNewline)
    ] as [(String, TemplatePatternSpec.Failure?)])
    func schemaRules(template: String, failure: TemplatePatternSpec.Failure?) throws {
        let status = PackTemplateReview.review([template], library: nil, replacing: nil)
        #expect(status == [failure.map(PackTemplateReview.Status.invalid) ?? .ok])
        var form = filledForm(try numberedDraft())
        form.setTemplate(template, at: 0)
        #expect(form.templateFailure(at: 0) == failure)
    }

    @Test("literal 40자 경계 — 접두+접미 정규화 합 40은 받고 41은 거부(띄어쓰기는 세지 않는다)")
    func literalBoundary() {
        let forty = string(20, "가") + " {n} " + string(20, "나")
        let fortyOne = string(21, "가") + "{n}" + string(20, "나")
        #expect(PackTemplateReview.review([forty, fortyOne], library: nil, replacing: nil) == [.ok, .invalid(.literalTooLong)])
    }

    @Test("★ 성경 — 접두·접미 규칙은 통과해도 1~9,999 중 하나라도 구절로 읽히면 거부(10-2 · `창세기1장50~{n}절` 반례)")
    func bibleCollision() throws {
        let status = PackTemplateReview.review(["창세기1장50~{n}절", "", "사자성어 {n}번"], library: nil, replacing: nil)
        guard case .invalid(.collidesWithBible(let n)) = status[0] else {
            Issue.record("성경 겹침을 찾지 못했다: \(status)")
            return
        }
        #expect(n >= 50)   // 50~50(같은 절)부터 구절로 읽힌다 — 1·10(역순 범위)은 탐침을 통과하지만 전체 n은 잡는다
        #expect(Array(status.dropFirst()) == [.empty, .ok])
        // 즉시 검사(폼)는 스키마만 본다 — 성경은 이 검사가 메인 밖에서
        var form = filledForm(try numberedDraft())
        form.setTemplate("창세기1장50~{n}절", at: 0)
        #expect(form.templateFailure(at: 0) == nil)
    }

    @Test("★ 주황 — 위 팩이 같은 틀을 가진다(10-4, 새 팩은 맨 아래 U2), 바꾸기 대상 팩 자리면 그 팩은 빠진다")
    func ownership() async throws {
        let store = Store()
        defer { store.cleanup() }
        let imported = await store.client.importPack(numberedPack("예시 번호 팩 2", template: "사자성어 {n}번"), source: .csv)
        let owner = try #require({ if case .accepted(let a) = imported.result { return a.packID } else { return nil } }())
        let library = try #require(store.library)

        // 띄어쓰기만 다른 같은 쌍(10-4 2번)도 같은 틀이다
        #expect(PackTemplateReview.review(["사자성어{n} 번", "고사성어 {n}번"], library: library, replacing: nil)
                    == [.outranked(by: owner), .ok])
        // 같은 이름 팩을 바꾸는 자리라면 그 팩의 틀은 사라진다 — 알림 없음
        #expect(PackTemplateReview.review(["사자성어 {n}번"], library: library, replacing: owner) == [.ok])
    }

    @Test("★ 주황 — 정적 단축어가 틀을 가린다(10-3) · 주인은 내 채움글")
    func shadowing() throws {
        let store = Store(user: [SnippetEntry(trigger: "장", title: "장", body: "본문")])
        defer { store.cleanup() }
        let library = try #require(store.library)
        #expect(PackTemplateReview.review(["명언 {n}장", "명언 {n}번"], library: library, replacing: nil)
                    == [.shadowed(triggers: ["장"], owner: .userSnippets), .ok])
        // 목록을 못 읽었으면 주황 알림 없이 빨강·통과만
        #expect(PackTemplateReview.review(["명언 {n}장"], library: nil, replacing: nil) == [.ok])
    }

    @Test("거부만 막는다 — 주황은 가져오기를 막지 않는다")
    func onlyInvalidBlocks() {
        #expect(PackTemplateReview.Status.invalid(.prefixTooShort).blocksImport)
        #expect(!PackTemplateReview.Status.outranked(by: "a").blocksImport)
        #expect(!PackTemplateReview.Status.shadowed(triggers: ["장"], owner: nil).blocksImport)
        #expect(!PackTemplateReview.Status.ok.blocksImport && !PackTemplateReview.Status.empty.blocksImport)
    }
}

// MARK: - ③ 확정 흐름 — 전이(저장소 없이)

@Suite("외부 채움글 1-c 5단계 — 확정 흐름 전이")
struct PackImportConfirmationTransitionTests {

    private func library(_ packs: [PackSummary]) -> PackImpact.Library {
        PackImpact.Library(revision: 7, order: [.userSnippets] + packs.map { .pack($0.id) },
                           packs: packs.map { PackImpact.Pack(summary: $0, stats: .zero, content: nil) },
                           userEntries: [], builtInEntries: [], limits: .candidate)
    }

    private let existing = PackSummary(id: "old", name: "우리 회사 상용구", mode: .phrases, itemCount: 3, titleFormat: nil,
                                       isEnabled: false, status: .off)

    @Test("완성되지 않은 폼은 확정하지 않는다 — 출처 미선택")
    func incompleteForm() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: library([]))
        var form = PackImportForm(draft: draft)
        form.name = "이름"
        let work = confirmation.confirm(form)
        #expect(work == nil && confirmation.phase == .editing)
    }

    @Test("새 이름 — 켠 채로 가져오기(U2), 미리보기 때 읽은 revision을 넘긴다(AC-3)")
    func newName() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: library([existing]))
        let work = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
        #expect(work.action == .importNew(enabled: true) && work.expectedRevision == 7)
        #expect(work.form.name == "새 팩" && confirmation.phase == .working)
        // 일하는 동안 다시 누르면 무시(두 번 저장 금지)
        let again = confirmation.confirm(filledForm(draft, name: "새 팩"))
        #expect(again == nil)
    }

    @Test("★ 같은 이름(U3) — 묻는다 · 바꾸기 = 그 팩 교체(켬/끔 유지) · 따로 추가 = 이름 칸으로 · 취소")
    func sameName() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: library([existing]))
        let asked = confirmation.confirm(filledForm(draft, name: "우리 회사 상용구"))
        #expect(asked == nil)
        #expect(confirmation.phase == .askingSameName(existing))
        let replace = try required(confirmation.chooseReplace())
        #expect(replace.action == .replace(packID: "old", isEnabled: false) && replace.expectedRevision == 7)

        var separate = PackImportConfirmation(draft: draft, library: library([existing]))
        _ = separate.confirm(filledForm(draft, name: "우리 회사 상용구"))
        separate.chooseSeparate()
        #expect(separate.phase == .editing && separate.focusesName)
        separate.nameFocused()
        #expect(!separate.focusesName)
        let replaceAfterSeparate = separate.chooseReplace()
        #expect(replaceAfterSeparate == nil)

        var cancelled = PackImportConfirmation(draft: draft, library: library([existing]))
        _ = cancelled.confirm(filledForm(draft, name: "우리 회사 상용구"))
        cancelled.cancelSameName()
        #expect(cancelled.phase == .editing && !cancelled.focusesName)
    }

    @Test("최종 검사 실패 — 폼으로 돌아가 그 칸을 알린다, 다시 고치면 지운다")
    func compileFailure() throws {
        let draft = try numberedDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        _ = try required(confirmation.confirm(filledForm(draft)))
        let received = confirmation.receive(.compileFailed(.pattern(index: 0, .collidesWithBible(n: 51))))
        #expect(received)
        #expect(confirmation.phase == .editing && confirmation.formFailure == .pattern(index: 0, .collidesWithBible(n: 51)))
        _ = try required(confirmation.confirm(filledForm(draft)))
        #expect(confirmation.formFailure == nil)
    }

    @Test("★ 「꺼 둔 채로 가져오기」는 그 버튼이 있는 거부(D1·D2)에서만 — D3(팩 수)·다른 거부에서는 없다(8절 #5)")
    func importDisabledOnlyFromBudgetRejection() throws {
        let draft = try phrasesDraft()
        let cases: [(PackStore.Rejection, Bool, Bool)] = [
            (.gate(.packExcluded(id: "x", dimensions: [.needleChars])), false, true),     // D1
            (.gate(.packExcluded(id: "x", dimensions: [.needleChars])), true, true),      // D2
            (.gate(.tooManyPacks), false, false),                                        // D3
            (.writeFailed, false, false),                                                // F1
            (.libraryUnreadable, false, false)                                           // E1
        ]
        for (rejection, overLimit, offersDisabled) in cases {
            var confirmation = PackImportConfirmation(draft: draft, library: nil)
            _ = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
            let result = PackStore.CommitResult.rejected(rejection, rechecked: false)
            let notice = PackChangeNotice(.importPack, result: result, userSnippetsOverLimit: { overLimit }, packName: { _ in nil })
            let received = confirmation.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: nil))
            #expect(received)
            #expect(confirmation.notice == notice && confirmation.hasDraft)
            let work = confirmation.importDisabled()
            #expect((work != nil) == offersDisabled, "\(rejection)")
            if let work { #expect(work.action == .importNew(enabled: false) && work.form.name == "새 팩") }
        }
    }

    @Test("★ 알림이 먼저 닫히고 버튼 동작이 와도(SwiftUI 순서 무관) 「꺼 둔 채로」가 된다 — 다시 확정하면 그 길은 닫힌다")
    func importDisabledAfterDismiss() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        _ = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
        let result = PackStore.CommitResult.rejected(.gate(.packExcluded(id: "x", dimensions: [.needleChars])), rechecked: false)
        let notice = PackChangeNotice(.importPack, result: result, userSnippetsOverLimit: { false }, packName: { _ in nil })
        confirmation.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: nil))
        confirmation.dismissNotice()
        let disabled = confirmation.importDisabled()
        #expect(disabled?.action == .importNew(enabled: false))

        var reconfirmed = PackImportConfirmation(draft: draft, library: nil)
        _ = try required(reconfirmed.confirm(filledForm(draft, name: "새 팩")))
        reconfirmed.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: nil))
        reconfirmed.dismissNotice()
        _ = try required(reconfirmed.confirm(filledForm(draft, name: "새 팩")))
        // 다시 확정한 결과가 「꺼 둔 채로」를 주지 않는 거부(쓰기 실패)면, 닫은 뒤에도 그 길은 없다
        let failed = PackStore.CommitResult.rejected(.writeFailed, rechecked: false)
        let failedNotice = PackChangeNotice(.importPack, result: failed, userSnippetsOverLimit: { false }, packName: { _ in nil })
        reconfirmed.receive(.committed(PackChangeOutcome(result: failed, notice: failedNotice), compiled: nil))
        reconfirmed.dismissNotice()
        let closed = reconfirmed.importDisabled()
        #expect(closed == nil)
    }

    /// 저장소 없이 만든 「받음」 결과
    private func accepted(packID: String = "new") -> PackImportConfirmation.Result {
        let evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [], limits: .candidate)
        let result = PackStore.CommitResult.accepted(PackStore.Accepted(revision: 8, packID: packID, newlyExcluded: [],
                                                                        evaluation: evaluation, rechecked: false))
        return .committed(PackChangeOutcome(result: result, notice: nil), compiled: nil)
    }

    /// D1 거부 알림이 떠 있는 확정 흐름 — 「꺼 둔 채로 가져오기」가 열려 있다
    private func rejectedD1(_ draft: PackDraft) throws -> PackImportConfirmation {
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        _ = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
        let result = PackStore.CommitResult.rejected(.gate(.packExcluded(id: "x", dimensions: [.needleChars])), rechecked: false)
        let notice = PackChangeNotice(.importPack, result: result, userSnippetsOverLimit: { false }, packName: { _ in nil })
        confirmation.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: nil))
        return confirmation
    }

    @Test("★ 화면 확인 N-1 — 「꺼 둔 채로」 저장이 받아지면 완료(4-M) — 알림 닫힘·버튼 동작이 어떤 순서로 와도, 닫힘이 옛 값으로 되써도")
    func importDisabledCompletesInAnyOrder() throws {
        let draft = try phrasesDraft()
        // ① 동작 → 닫힘
        var actionFirst = try rejectedD1(draft)
        let work1 = try required(actionFirst.importDisabled())
        actionFirst.dismissNotice()
        #expect(actionFirst.phase == .working, "일하는 중에는 닫힘이 폼으로 되돌리지 않는다")
        let received1 = actionFirst.receive(accepted(), for: work1)
        #expect(received1)
        // ② 닫힘 → 동작(SwiftUI 알림은 순서를 보장하지 않는다 — 5단계 보고)
        var dismissFirst = try rejectedD1(draft)
        dismissFirst.dismissNotice()
        let work2 = try required(dismissFirst.importDisabled())
        let received2 = dismissFirst.receive(accepted(), for: work2)
        #expect(received2)
        // ③ 닫힘이 **동작 전에 읽은 값**에 `dismissNotice`를 해서 통째로 되쓴다(바인딩의 읽고-고쳐-쓰기) — 화면 확인 N-1의 증상:
        //    저장은 됐는데 단계가 폼(editing)으로 돌아가 결과를 버렸다
        var overwritten = try rejectedD1(draft)
        let stale = overwritten
        let work3 = try required(overwritten.importDisabled())
        overwritten = stale
        overwritten.dismissNotice()
        #expect(overwritten.phase == .editing, "되써진 값은 일을 시작한 적이 없는 폼이다")
        let received3 = overwritten.receive(accepted(), for: work3)
        #expect(received3, "그래도 저장소가 받았다 — 완료로 간다")

        for confirmation in [actionFirst, dismissFirst, overwritten] {
            let completion = try #require(confirmation.completion)
            #expect(completion.kind == .importedDisabled && !completion.isEnabled && completion.packID == "new")
            #expect(PackFormCopy.doneTitle(completion.kind) == "꺼 둔 채로 가져왔어요")
            #expect(!confirmation.hasDraft, "원본(초안)을 비운다 — 일반 가져오기와 같은 완료")
        }
    }

    @Test("★ 화면 확인 N-1 ② — 완료한 흐름은 다시 저장하지 않는다(가져오기·꺼 둔 채로·바꾸기·늦게 온 두 번째 결과 모두 무시)")
    func completedFlowStartsNoWork() throws {
        let draft = try phrasesDraft()
        var confirmation = try rejectedD1(draft)
        let work = try required(confirmation.importDisabled())
        confirmation.receive(accepted(), for: work)
        let done = try #require(confirmation.completion)

        let reconfirmed = confirmation.confirm(filledForm(draft, name: "새 팩"))
        let disabledAgain = confirmation.importDisabled()
        let replaced = confirmation.chooseReplace()
        #expect(reconfirmed == nil && disabledAgain == nil && replaced == nil)
        confirmation.dismissNotice()
        confirmation.cancelSameName()
        confirmation.chooseSeparate()
        let secondAccepted = confirmation.receive(accepted(packID: "again"), for: work)
        let lateFailure = confirmation.receive(.compileFailed(.nameMissing), for: work)
        let currentAccepted = confirmation.receive(accepted(packID: "again"))
        #expect(!secondAccepted && !lateFailure && !currentAccepted)
        #expect(confirmation.completion == done && !confirmation.focusesName)
    }

    @Test("거부·최종 검사 실패는 지금 하는 일의 결과만 받는다 — 되써진 폼에 늦은 거부가 알림을 띄우지 않는다")
    func rejectionOfAnotherWorkIsDropped() throws {
        let draft = try phrasesDraft()
        var confirmation = try rejectedD1(draft)
        let stale = confirmation
        let work = try required(confirmation.importDisabled())
        confirmation = stale
        confirmation.dismissNotice()
        let tooMany = PackStore.CommitResult.rejected(.gate(.tooManyPacks), rechecked: false)
        let notice = PackChangeNotice(.importDisabledPack, result: tooMany, userSnippetsOverLimit: { false }, packName: { _ in nil })
        let rejected = confirmation.receive(.committed(PackChangeOutcome(result: tooMany, notice: notice), compiled: nil), for: work)
        let failed = confirmation.receive(.compileFailed(.nameMissing), for: work)
        #expect(!rejected && !failed)
        #expect(confirmation.phase == .editing && confirmation.formFailure == nil)
    }

    @Test("거부 알림을 닫으면 폼으로 — 같은 폼을 다시 확정할 수 있다")
    func dismissNotice() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        _ = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
        let result = PackStore.CommitResult.rejected(.writeFailed, rechecked: false)
        let notice = PackChangeNotice(.importPack, result: result, userSnippetsOverLimit: { false }, packName: { _ in nil })
        confirmation.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: nil))
        confirmation.dismissNotice()
        #expect(confirmation.phase == .editing)
        let retried = confirmation.confirm(filledForm(draft, name: "새 팩"))
        #expect(retried != nil)
    }

    @Test("받았는데 팩이 쉬게 됐다면(G1·G2) 완료 화면이 그 알림을 들고 간다")
    func acceptedWithRestingPacks() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        let work = try required(confirmation.confirm(filledForm(draft, name: "새 팩")))
        let compiled = try PackCompiler.compile(draft, form: work.form)
        let evaluation = ActivePackBudget.evaluate(baseline: .zero, packs: [], limits: .candidate)
        let result = PackStore.CommitResult.accepted(PackStore.Accepted(revision: 8, packID: "new", newlyExcluded: ["a", "b"],
                                                                        evaluation: evaluation, rechecked: false))
        let notice = PackChangeNotice(.importPack, result: result, userSnippetsOverLimit: { false }, packName: { _ in "가" })
        confirmation.receive(.committed(PackChangeOutcome(result: result, notice: notice), compiled: compiled))
        let completion = try #require(confirmation.completion)
        #expect(completion.notice?.reason == .packsRested && completion.packID == "new")
    }

    @Test("늦게 온 결과(일하는 중이 아닐 때)는 받지 않는다")
    func staleResult() throws {
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: nil)
        let received = confirmation.receive(.compileFailed(.nameMissing))
        #expect(!received)
        #expect(confirmation.phase == .editing && confirmation.formFailure == nil)
    }
}

// MARK: - ③④ 확정 — 실제 저장소(U2 · AC-3 · D1~D3 · U3 · 4-M)

@Suite("외부 채움글 1-c 5단계 — 확정 · 실제 저장소")
struct PackImportCommitStoreTests {

    @Test("★ 가져오기 — 켠 채로 목록 맨 아래(U2), 폼의 최종 값이 저장된다(AC-3), 완료 화면 값(4-M), 원본을 비운다")
    func importsAtBottom() async throws {
        let store = Store()
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("먼저 팩", prefix: "먼저", count: 2), source: .csv)

        let draft = try numberedDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        var form = filledForm(draft, name: "바꾼 이름")
        form.setTemplate("고사성어 {n}번", at: 0)
        try await run(&confirmation, confirmation.confirm(form), client: store.client)

        let completion = try #require(confirmation.completion)
        #expect(completion.kind == .imported && completion.isEnabled)
        #expect(completion.name == "바꾼 이름" && completion.itemCount == 2 && completion.skippedCount == 0)
        #expect(completion.examples == [PackDetail.Example(trigger: "고사성어 1번", title: "예시 제목 하나", body: "예시 본문 하나")])
        #expect(completion.notice == nil)
        #expect(!confirmation.hasDraft)

        let summaries = store.store.summaries()
        #expect(summaries.map(\.name) == ["먼저 팩", "바꾼 이름"])
        #expect(summaries.last?.id == completion.packID && summaries.last?.isEnabled == true && summaries.last?.status == .on)
        #expect(summaries.last?.titleFormat == "고사성어 {n}번")
        #expect(store.store.packDetail(completion.packID)?.license == "직접 작성함")
    }

    /// needleChars 195 — 「큰 팩」(19자 × 10 = 190자)은 들어가고, 거기에 새 팩(「회사주소」·「새해인사」 8자)을 더하면 넘는다
    private let tight = PackBudgetLimits(needleCount: 100, needleChars: 195, bytes: 2_000_000, items: 1_000)

    @Test("★ D1 — 한도 넘음: 「꺼 둔 채로 가져오기」·닫기 → 꺼진 채 맨 아래, 앞 팩은 그대로(U2 · importDisabledPack 게이트)")
    func d1ImportDisabled() async throws {
        let store = Store(limits: tight)
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("큰 팩", prefix: string(18, "큰"), count: 10), source: .csv)
        let before = store.store.summaries()
        #expect(before.map(\.status) == [.on])

        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "새 팩")), client: store.client)
        let notice = try #require(confirmation.notice)
        #expect(notice.reason == .importExceedsLimit)
        #expect(notice.actions == [.importDisabled] && notice.dismiss == .close)
        #expect(store.store.summaries() == before)   // 거부는 아무것도 쓰지 않는다

        try await run(&confirmation, confirmation.importDisabled(), client: store.client)
        let completion = try #require(confirmation.completion)
        #expect(completion.kind == .importedDisabled && !completion.isEnabled)
        let after = store.store.summaries()
        #expect(after.count == 2 && Array(after.prefix(1)) == before)
        #expect(after.last?.id == completion.packID && after.last?.isEnabled == false && after.last?.status == .off)
    }

    @Test("★ D2 — 내 채움글이 이미 한도 초과: 정리하기·꺼 둔 채로·닫기 → 꺼 둔 채로는 받는다")
    func d2UserOverLimit() async throws {
        let user = (0..<30).map { SnippetEntry(trigger: "\(string(10, "내"))\($0)", title: "t", body: "b") }
        let store = Store(user: user, limits: tight)
        defer { store.cleanup() }
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "새 팩")), client: store.client)
        let notice = try #require(confirmation.notice)
        #expect(notice.reason == .importWhileUserOverLimit)
        #expect(notice.actions == [.organize, .importDisabled] && notice.dismiss == .close)

        try await run(&confirmation, confirmation.importDisabled(), client: store.client)
        #expect(confirmation.completion?.kind == .importedDisabled)
        #expect(store.store.summaries().map(\.isEnabled) == [false])
    }

    @Test("★ 화면 확인 N-1 — D1 「꺼 둔 채로」: 알림 닫힘이 옛 값으로 되써도 완료(꺼짐·맨 아래), 완료 뒤 다시 눌러도 같은 팩이 또 생기지 않는다")
    func d1ImportDisabledSurvivesStaleDismiss() async throws {
        let store = Store(limits: tight)
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("큰 팩", prefix: string(18, "큰"), count: 10), source: .csv)
        let draft = try phrasesDraft()
        let form = filledForm(draft, name: "새 팩")
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(form), client: store.client)
        #expect(confirmation.notice?.actions == [.importDisabled])

        let stale = confirmation
        let work = try required(confirmation.importDisabled())
        confirmation = stale
        confirmation.dismissNotice()
        let result = await PackImportConfirmation.perform(work, client: store.client)
        let received = confirmation.receive(result, for: work)
        #expect(received)
        let completion = try #require(confirmation.completion)
        #expect(completion.kind == .importedDisabled && !completion.isEnabled)

        // 화면 확인 재현 — 예전에는 폼이 남아 「가져오기」 → D1 → 「꺼 둔 채로」가 같은 이름 팩을 하나 더 만들었다
        let reconfirmed = confirmation.confirm(form)
        let disabledAgain = confirmation.importDisabled()
        #expect(reconfirmed == nil && disabledAgain == nil)
        let summaries = store.store.summaries()
        #expect(summaries.map(\.name) == ["큰 팩", "새 팩"])
        #expect(summaries.last?.id == completion.packID && summaries.last?.isEnabled == false)
    }

    @Test("★ 화면 확인 N-2 — 완료 화면 「이렇게 써 보세요」는 팩 상세와 같은 계산 — 문구형은 지금 뜨는 단축어부터(O-1)")
    func completionExamplesFollowDetailPhrases() async throws {
        let store = Store(user: [SnippetEntry(trigger: "회사주소", title: "내 주소", body: "내 본문")])
        defer { store.cleanup() }
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "새 팩")), client: store.client)
        let completion = try #require(confirmation.completion)
        #expect(completion.examples.map(\.trigger) == ["새해인사", "회사주소"], "내 채움글이 먼저 뜨는 「회사주소」는 뒤로")
        #expect(completion.examples == store.store.packDetail(completion.packID)?.examples)
    }

    @Test("★ 화면 확인 N-2 — 번호형은 이 팩이 쓰는 틀부터 — 위 팩이 대표 틀을 가지면 별칭으로(팩 상세와 같다)")
    func completionExamplesFollowDetailNumbered() async throws {
        let store = Store()
        defer { store.cleanup() }
        _ = await store.client.importPack(numberedPack("앞 팩", template: "사자성어 {n}번"), source: .csv)
        let draft = try numberedDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "뒤 팩")), client: store.client)
        let completion = try #require(confirmation.completion)
        // 별칭 「성어 {n}번」은 정규화 모양으로 저장돼 있다(화면 확인 O-5 — 상세의 틀 절과 같은 모양). 띄어쓰기는 매칭이 보지 않는다
        #expect(completion.examples == [PackDetail.Example(trigger: "성어1번", title: "예시 제목 하나", body: "예시 본문 하나")])
        #expect(completion.examples == store.store.packDetail(completion.packID)?.examples)
    }

    @Test("★ D3 — 팩이 너무 많다(꺼 둔 팩도 센다): 「꺼 둔 채로」 없음 · 확인")
    func d3TooManyPacks() async throws {
        let store = Store()
        defer { store.cleanup() }
        for index in 0..<PackLimits.externalPacks {
            let result = await store.client.importPack(phrasesPack("팩\(index)", prefix: "팩\(index)번", count: 1), source: .csv,
                                                       enabled: false)
            #expect(result.isAccepted)
        }
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "새 팩")), client: store.client)
        let notice = try #require(confirmation.notice)
        #expect(notice.reason == .importTooManyPacks && notice.actions.isEmpty && notice.dismiss == .confirm)
        let disabledWork = confirmation.importDisabled()
        #expect(disabledWork == nil)
        #expect(store.store.summaries().count == PackLimits.externalPacks)
    }

    @Test("★ AC-3 — 미리보기 뒤 저장본이 바뀌면 지금 저장본으로 다시 판정하고 알림에 그 한 줄을 붙인다")
    func rechecked() async throws {
        let store = Store(limits: tight)
        defer { store.cleanup() }
        let draft = try phrasesDraft()
        // 미리보기 때 읽은 목록(빈 목록) — 그 뒤 큰 팩이 들어온다
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        _ = await store.client.importPack(phrasesPack("큰 팩", prefix: string(18, "큰"), count: 10), source: .csv)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "새 팩")), client: store.client)
        let notice = try #require(confirmation.notice)
        #expect(notice.rechecked && notice.reason == .importExceedsLimit)
        #expect(notice.message.hasPrefix(PackNoticeCopy.recheckedLine))

        // 받는 쪽 — 그 사이 바뀌었어도 지금 판정으로 들어가면 받는다(알림 없음)
        let roomy = Store()
        defer { roomy.cleanup() }
        var accepted = PackImportConfirmation(draft: draft, library: roomy.library)
        _ = await roomy.client.importPack(phrasesPack("다른 팩", prefix: "다른", count: 1), source: .csv)
        try await run(&accepted, accepted.confirm(filledForm(draft, name: "새 팩")), client: roomy.client)
        #expect(accepted.completion?.kind == .imported && accepted.completion?.notice == nil)
        #expect(roomy.store.summaries().map(\.name) == ["다른 팩", "새 팩"])
    }

    @Test("★ U3 바꾸기 — 목록 자리·켬/끔 유지, 내용만 새 파일로 · 읽을 수 없는 팩도 바꾸면 다시 읽힌다(8절 #7)")
    func replaceKeepsPlace() async throws {
        let store = Store()
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("우리 회사 상용구", prefix: "옛", count: 3), source: .csv, enabled: false)
        _ = await store.client.importPack(phrasesPack("뒤 팩", prefix: "뒤", count: 1), source: .csv)
        let before = store.store.summaries()

        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        let asked = confirmation.confirm(filledForm(draft, name: "우리 회사 상용구"))
        #expect(asked == nil)
        #expect(confirmation.phase == .askingSameName(before[0]))
        try await run(&confirmation, confirmation.chooseReplace(), client: store.client)
        let completion = try #require(confirmation.completion)
        #expect(completion.kind == .replaced && completion.packID == before[0].id && !completion.isEnabled)

        let after = store.store.summaries()
        #expect(after.map(\.id) == before.map(\.id) && after.map(\.isEnabled) == [false, true])
        #expect(after[0].itemCount == 2)
        #expect(store.store.impactLibrary()?.pack(before[0].id)?.triggers == ["회사주소", "새해인사"])
    }

    @Test("★ R15 사용자 경로 — 켜진 팩을 더 큰 판으로 바꿔 아래 팩이 밀리면 거부(C3 「바꿀 수 없어요」), 「꺼 둔 채로」 없음, 저장본 그대로")
    func replaceDisplacingIsRejected() async throws {
        let store = Store(limits: tight)
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("우리 회사 상용구", prefix: "옛", count: 1), source: .csv)        // 2자
        _ = await store.client.importPack(phrasesPack("큰 팩", prefix: string(18, "큰"), count: 10), source: .csv)   // 190자 — 합 192
        let before = store.store.summaries()
        #expect(before.map(\.status) == [.on, .on])

        // 새 판은 8자(「회사주소」·「새해인사」) — 위 자리에서 8 + 190 = 198 > 195라 아래 「큰 팩」이 밀린다(R15)
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        let asked = confirmation.confirm(filledForm(draft, name: "우리 회사 상용구"))
        #expect(asked == nil)
        try await run(&confirmation, confirmation.chooseReplace(), client: store.client)
        let notice = try #require(confirmation.notice)
        #expect(notice.reason == .replaceExceedsLimit && notice.title == "바꿀 수 없어요")
        #expect(notice.packIDs == [before[1].id] && notice.actions.isEmpty && notice.dismiss == .confirm)
        let disabled = confirmation.importDisabled()
        #expect(disabled == nil)
        #expect(store.store.summaries() == before)
    }

    @Test("★ 검증 F-3 V05 (AC-3) — 바꾸기도 시트를 열 때 읽은 revision을 넘긴다: 그 사이 저장본이 바뀌어 거부되면 알림에 「다시 판정」 한 줄")
    func replaceRechecked() async throws {
        let store = Store(limits: tight)
        defer { store.cleanup() }
        _ = await store.client.importPack(phrasesPack("우리 회사 상용구", prefix: "옛", count: 1), source: .csv)        // 2자
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)   // 이 목록의 revision을 잡는다
        // 그 사이 큰 팩이 아래에 들어온다 — 새 판(8자)으로 바꾸면 8 + 190 > 195라 큰 팩이 밀린다(R15 거부)
        _ = await store.client.importPack(phrasesPack("큰 팩", prefix: string(18, "큰"), count: 10), source: .csv)
        let before = store.store.summaries()
        let asked = confirmation.confirm(filledForm(draft, name: "우리 회사 상용구"))
        #expect(asked == nil)
        let work = try required(confirmation.chooseReplace())
        #expect(work.expectedRevision != nil && work.expectedRevision != store.store.revision)
        let result = await PackImportConfirmation.perform(work, client: store.client)
        let received = confirmation.receive(result)
        #expect(received)
        let notice = try #require(confirmation.notice)
        #expect(notice.reason == .replaceExceedsLimit && notice.rechecked)
        #expect(notice.message.hasPrefix(PackNoticeCopy.recheckedLine))
        #expect(store.store.summaries() == before)
    }

    @Test("★ 검증 F-3 V26 (4-M) — 완료 개수는 같은 번호를 합친 **뒤** 팩에 실제로 든 수다(원본 데이터 행 수가 아니다), 건너뜀은 따로")
    func completionCountsMergedItems() async throws {
        let store = Store()
        defer { store.cleanup() }
        let csv = "#틀,사자성어 {n}번\n#권리,자체 작성\n번호,제목,본문\n1,첫 제목,첫 본문\n2,둘 제목,둘 본문\n1,고친 제목,고친 본문\n0,빈,빈\n"
        let draft = try ImportHelper.draft(csv)
        #expect(draft.dataRecordCount == 4 && draft.items.count == 2 && draft.duplicateCount == 1 && draft.skipped.count == 1)
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        try await run(&confirmation, confirmation.confirm(filledForm(draft, name: "합친 팩")), client: store.client)
        let completion = try #require(confirmation.completion)
        #expect(completion.itemCount == 2 && completion.skippedCount == 1)
        #expect(store.store.summaries().first?.itemCount == completion.itemCount, "완료 화면 수 == 목록 수")
    }

    @Test("최종 검사에서 성경 겹침 — 저장하지 않고 폼으로(그 칸 번호)")
    func compileFailureStoresNothing() async throws {
        let store = Store()
        defer { store.cleanup() }
        let draft = try numberedDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        var form = filledForm(draft)
        form.setTemplate("창세기1장50~{n}절", at: 1)
        try await run(&confirmation, confirmation.confirm(form), client: store.client)
        guard case .pattern(index: 1, .collidesWithBible) = confirmation.formFailure else {
            Issue.record("폼 실패가 아니다: \(String(describing: confirmation.formFailure))")
            return
        }
        #expect(confirmation.phase == .editing && confirmation.hasDraft)
        #expect(store.store.summaries().isEmpty)
    }

    @Test("목록을 다시 읽으면(정리 화면에서 돌아옴) 같은 이름·revision이 새 목록을 따른다")
    func refreshLibrary() async throws {
        let store = Store()
        defer { store.cleanup() }
        let draft = try phrasesDraft()
        var confirmation = PackImportConfirmation(draft: draft, library: store.library)
        _ = await store.client.importPack(phrasesPack("우리 회사 상용구", prefix: "옛", count: 1), source: .csv)
        let fresh = try #require(store.library)
        confirmation.refresh(library: fresh)
        let asked = confirmation.confirm(filledForm(draft, name: "우리 회사 상용구"))
        #expect(asked == nil)
        guard case .askingSameName = confirmation.phase else {
            Issue.record("같은 이름을 묻지 않았다")
            return
        }
        let replace = confirmation.chooseReplace()
        #expect(replace?.expectedRevision == fresh.revision)
    }
}

// MARK: - 문구 표(5단계) — 매핑 전부 · 숫자 (U6·금칙어·xlsx는 6단계 `PackCopyLintTests`가 한 곳에서 본다)

/// 5단계가 내는 문구 — 문구 검사(숫자 · `allScreenCopy`의 U6·금칙어·xlsx)를 받는다. 부를 때마다 지금 판으로 만든다
var stage5Copy: [String] {
    var texts = [
        PackFormCopy.formTitle, PackFormCopy.importButton, PackFormCopy.nameLabel, PackFormCopy.namePlaceholder,
        PackFormCopy.fromFileTag, PackFormCopy.aliasTag, PackFormCopy.nameEmptyFromFile, PackFormCopy.nameTooLongFromFile,
        PackFormCopy.templatesHeader, PackFormCopy.templatePlaceholder, PackFormCopy.addTemplate, PackFormCopy.removeTemplate,
        PackFormCopy.chipPreviewHeader, PackFormCopy.templatesFooter, PackFormCopy.reviewFooter, PackFormCopy.licenseHeader,
        PackFormCopy.customLicensePlaceholder, PackFormCopy.licenseFooter(hasFileLicense: true),
        PackFormCopy.licenseFooter(hasFileLicense: false), PackFormCopy.licenseTooLongFromFile, PackFormCopy.sameNameHint,
        PackFormCopy.sameNameTitle, PackFormCopy.sameNameMessage("사자성어 예시 팩"), PackFormCopy.sameNameMessage("업무 상용구 A"),
        PackFormCopy.replaceButton, PackFormCopy.separateButton, PackFormCopy.cancel, PackFormCopy.separateHint,
        PackFormCopy.doneHeader, PackFormCopy.tryHeader, PackFormCopy.nextTimeLine, PackFormCopy.disabledLine,
        PackFormCopy.replacedLine, PackFormCopy.backToSnippets, PackFormCopy.skippedLine(37),
        PackFormCopy.doneSummary(name: "사자성어 예시 팩", count: 37)
    ]
    texts += PackImportForm.LicenseChoice.allCases.map(PackFormCopy.licenseLabel)
    texts += [PackImportCompletion.Kind.imported, .importedDisabled, .replaced].map(PackFormCopy.doneTitle)
    texts += allPatternFailures.flatMap { [PackFormCopy.templateFailure($0), PackFormCopy.templateFailureExample($0)].compactMap { $0 } }
    texts += allReviewStatuses.compactMap(PackFormCopy.templateStatusLabel)
    texts += allCompileFailures.map(PackFormCopy.compileFailure)
    let names = ["예시 번호 팩 2": "예시 번호 팩 2"]
    texts += [PackTemplateReview.Status.outranked(by: "예시 번호 팩 2"),
              .shadowed(triggers: ["장"], owner: .userSnippets), .shadowed(triggers: ["장", "번"], owner: .pack("예시 번호 팩 2")),
              .shadowed(triggers: ["장"], owner: .builtIn), .shadowed(triggers: ["장"], owner: nil)]
        .flatMap { status -> [String] in
            [PackFormCopy.reviewTitle(status, name: { names[$0] ?? "" }),
             PackFormCopy.reviewDetail(status, replacing: false, name: { names[$0] ?? "" }),
             PackFormCopy.reviewDetail(status, replacing: true, name: { names[$0] ?? "" })].compactMap { $0 }
        }
    return texts
}

private let allPatternFailures: [TemplatePatternSpec.Failure] = [
    .placeholderCount, .prefixTooShort, .prefixEndsWithDigit, .prefixAllDigits, .suffixEmpty, .literalContainsNewline,
    .reservedDateSuffix, .literalTooLong, .collidesWithBible(n: 51)
]

/// 틀 칸 상태 전부(빈 칸·빨강·통과·주황 둘)
private let allReviewStatuses: [PackTemplateReview.Status] = [
    .empty, .invalid(.prefixTooShort), .ok, .outranked(by: "a"), .shadowed(triggers: ["장"], owner: .userSnippets)
]

private let allCompileFailures: [PackCompileFailure] = [
    .nameMissing, .nameTooLong, .licenseMissing, .licenseTooLong, .templateRequired, .templateNotAllowed, .tooManyPatterns,
    .pattern(index: 0, .prefixTooShort), .noValidRecords
]

/// 숫자 허용 — 시안 예시(사자성어 {n}번 · 회차{n}번)와 **필드 상한**(이름 40자 · 출처 120자 · 틀 literal 40자 · 틀+번호 48자 ·
/// 틀 8개 · 앞 글자 2자)뿐. 개수 표시(37개)는 시험 값. 예산 한도(R2) 숫자는 여기에 없다
private let stage5AllowedNumbers = ["40자까지", "120자까지", "48자 이내", "8개까지", "2자 이상", "37개", "예시 번호 팩 2", "업무 상용구 A"]

@Suite("외부 채움글 1-c 5단계 — 문구 표 (5-A·5-B·5-C·U3·4-M)")
struct PackFormCopyTests {

    @Test("★ 틀 사유 전부에 문구가 있다(새 사유가 생기면 이 표가 실패한다)")
    func everyPatternFailureHasCopy() {
        for failure in allPatternFailures {
            #expect(!PackFormCopy.templateFailure(failure).isEmpty)
        }
        #expect(Set(allPatternFailures.map(PackFormCopy.templateFailure)).count == allPatternFailures.count - 1)  // 숫자 끝·숫자뿐은 한 문구
        #expect(PackFormCopy.templateFailure(.prefixEndsWithDigit) == PackFormCopy.templateFailure(.prefixAllDigits))
    }

    @Test("시안 5-C 문구 그대로")
    func mockupCopy() {
        #expect(PackFormCopy.templateFailure(.placeholderCount) == "{n}이 꼭 한 번 있어야 해요")
        #expect(PackFormCopy.templateFailure(.prefixTooShort) == "앞 글자가 2자 이상이어야 해요")
        #expect(PackFormCopy.templateFailureExample(.prefixTooShort) == "예: 사자성어 {n}번")
        #expect(PackFormCopy.templateFailure(.reservedDateSuffix) == "「날짜」「시간」「시각」으로 끝나면 날짜 채움글과 겹쳐요")
        #expect(PackFormCopy.templateFailureExample(.reservedDateSuffix) == "예: 회차{n}번", "화면 확인 N-3 — 거부되는 「회차{n}시간」이 아니라 통과하는 예")
        #expect(PackFormCopy.reviewTitle(.outranked(by: "a"), name: { _ in "예시 번호 팩 2" }) == "「예시 번호 팩 2」도 이 틀을 써요")
        #expect(PackFormCopy.reviewDetail(.outranked(by: "a"), replacing: false, name: { _ in "예시 번호 팩 2" })
                    == "새 팩은 목록 맨 아래에 붙어서 위에 있는 「예시 번호 팩 2」가 이 틀을 가져요.")
        #expect(PackFormCopy.reviewTitle(.shadowed(triggers: ["장"], owner: .userSnippets), name: { $0 }) == "내 채움글 「장」에 가려져요")
        #expect(PackFormCopy.reviewDetail(.shadowed(triggers: ["장"], owner: .userSnippets), replacing: false, name: { $0 })
                    == "「…장」으로 끝나는 입력에서는 내 채움글이 먼저 떠요.")
        #expect(PackFormCopy.sameNameMessage("사자성어 예시 팩")
                    == "「사자성어 예시 팩」이 이미 있어요. 바꾸면 목록 자리와 켬/끔은 그대로고 내용만 새 파일로 바뀌어요.")
        #expect(PackFormCopy.doneSummary(name: "사자성어 예시 팩", count: 641) == "「사자성어 예시 팩」 · 641개")
        #expect(PackFormCopy.skippedLine(4) == "건너뛴 4개는 가져오지 않았어요.")
    }

    @Test("★ R27·R28 — 폼의 「권리 표기」는 「출처」다(머리·입력칸·선택지·사유·풋터). 파일 출처를 미리 고른다는 말은 파일 출처가 있을 때만")
    func sourceCopy() {
        #expect(PackFormCopy.licenseHeader == "출처(꼭 필요해요)")
        #expect(PackFormCopy.customLicensePlaceholder == "출처를 직접 써요")
        #expect(PackFormCopy.licenseTooLongFromFile == "파일에 적힌 출처가 너무 길어서 보여 드리지 못했어요. 고르거나 직접 써 주세요.")
        #expect(PackFormCopy.licenseLabel(.fromFile) == "파일에 적힌 출처")
        #expect(PackFormCopy.compileFailure(.licenseMissing) == "출처를 골라 주세요.")
        #expect(PackFormCopy.compileFailure(.licenseTooLong) == "출처는 120자까지예요.")
        #expect(PackFormCopy.licenseFooter(hasFileLicense: true)
                    == "파일에 적힌 출처를 고치지 않고 그대로 골라 뒀어요. 맞지 않으면 다른 것을 골라 주세요. "
                    + "고른 선택지는 증명이 아니에요. 이 내용을 써도 되는지는 가져오는 분이 직접 확인해 주세요.")
        #expect(PackFormCopy.licenseFooter(hasFileLicense: false)
                    == "하나를 직접 골라야 「가져오기」가 켜져요. 고른 선택지는 증명이 아니에요. 이 내용을 써도 되는지는 가져오는 분이 직접 확인해 주세요.")
        // 보이는 글자에 「권리」가 남지 않는다(이 표 전부 — `PackCopyLintTests`가 화면 전체를 다시 본다)
        for text in stage5Copy { #expect(!text.contains("권리"), "\(text)") }
    }

    @Test("★ 화면 확인 N-3 — 빨강 아래 「예:」 줄은 **통과하는 입력**이다(고친 예) — 그 사유로 다시 거부되면 실패")
    func failureExamplesPass() throws {
        var checked = 0
        for failure in allPatternFailures {
            guard let example = PackFormCopy.templateFailureExample(failure) else { continue }
            let spec = try #require(example.hasPrefix("예: ") ? String(example.dropFirst(3)) : nil, "\(example)")
            #expect((try? TemplatePatternSpec.parse(spec).get()) != nil, "\(failure) — \(example)")
            checked += 1
        }
        #expect(checked == 2, "예를 단 사유는 앞 글자 짧음·날짜 끝말 둘")
        #expect(TemplatePatternSpec.parse("회차{n}시간") == .failure(.reservedDateSuffix), "옛 예는 바로 그 사유로 거부되는 입력이었다")
    }

    @Test("★ 화면 확인 N-7 — 틀 칸 상태 아이콘의 VoiceOver 이름(기호 기본 이름 「선택됨」 대신) — 빨강·통과·주황이 서로 다르다")
    func templateStatusLabels() {
        #expect(PackFormCopy.templateStatusLabel(.ok) == "통과")
        #expect(PackFormCopy.templateStatusLabel(.invalid(.prefixTooShort)) == "가져올 수 없음")
        #expect(PackFormCopy.templateStatusLabel(.outranked(by: "a")) == "알림")
        #expect(PackFormCopy.templateStatusLabel(.shadowed(triggers: ["장"], owner: nil)) == "알림")
        #expect(PackFormCopy.templateStatusLabel(.empty) == nil, "빈 칸은 아이콘이 없다")
        #expect(!allReviewStatuses.compactMap(PackFormCopy.templateStatusLabel).contains("선택됨"))
    }

    @Test("★ 숫자는 필드 상한·시안 예시뿐 — 예산 한도 숫자 0 — 두 판 모두(검증 G2)", arguments: PackCopySet.allCases)
    func onlyAllowedNumbers(_ set: PackCopySet) {
        for text in PackCopySet.$previewing.withValue(set, operation: { stage5Copy }) {
            var rest = text.replacingOccurrences(of: #"「[^」]*」 · [\d,]+개"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(건너뛴|외) [\d,]+개"#, with: "", options: .regularExpression)
            for allowed in stage5AllowedNumbers { rest = rest.replacingOccurrences(of: allowed, with: "") }
            #expect(!rest.contains { $0.isNumber }, "\(text)")
        }
    }

    @Test("상한 문구는 PackLimits를 따른다")
    func limitsFollowConstants() {
        #expect(PackFormCopy.templatesFooter.contains("\(PackLimits.templatePatterns)개까지"))
        #expect(PackFormCopy.templateFailure(.literalTooLong).contains("\(PackLimits.templateLiteral.characters)자까지"))
        #expect(PackFormCopy.compileFailure(.nameTooLong).contains("\(PackLimits.name.characters)자까지"))
        #expect(PackFormCopy.compileFailure(.licenseTooLong).contains("\(PackLimits.license.characters)자까지"))
        #expect(PackFormCopy.counter("가나다", limit: PackLimits.name) == "3/\(PackLimits.name.characters)")
        // 검증 F-6 ③ — 「2자」「48자」도 상수에서(틀 검사와 같은 값)
        let prefix = "\(TemplatePatternSpec.minimumPrefixCharacters)자 이상"
        #expect(PackFormCopy.templatesFooter.hasPrefix("앞 글자는 \(prefix),"))
        #expect(PackFormCopy.templateFailure(.prefixTooShort) == "앞 글자가 \(prefix)이어야 해요")
        let expanded = "띄어쓰기 포함 \(TemplatePatternSpec.expandedTriggerCharacters)자 이내"
        #expect(PackFormCopy.templatesFooter.contains(expanded) && PackFormCopy.templateFailure(.literalTooLong).contains(expanded))
    }

    @Test("★ 검증 F-6 ③ — 「앞 글자 2자」는 틀 검사가 실제로 막는 길이다 — 상수 하나가 문구와 검사를 함께 정한다")
    func prefixMinimumIsTheRule() {
        let short = String(repeating: "가", count: TemplatePatternSpec.minimumPrefixCharacters - 1)
        let enough = String(repeating: "가", count: TemplatePatternSpec.minimumPrefixCharacters)
        #expect(TemplatePatternSpec.parse("\(short){n}번") == .failure(.prefixTooShort))
        #expect((try? TemplatePatternSpec.parse("\(enough){n}번").get()) != nil)
        #expect(TemplatePatternSpec.minimumPrefixCharacters == 2, "시안 5-C 「앞 글자가 2자 이상」")
    }

    @Test("★ 검증 F-6 ③ — 「틀+번호 48자」는 키보드가 매칭에 보는 꼬리 길이다(거울 값 대조) — 최대 확장(틀 40 + 번호 4자리 + 띄어쓰기 2)이 그 안에 든다")
    @MainActor
    func expandedLimitMirrorsKeyboardTail() {
        final class Sink: TextOutput {
            func insertText(_ text: String) {}
            func deleteBackward(_ count: Int) {}
        }
        let controller = InputController(output: Sink())
        controller.syncWithDocument(documentTail: String(repeating: "가", count: TemplatePatternSpec.expandedTriggerCharacters + 20))
        #expect(controller.textTail.count == TemplatePatternSpec.expandedTriggerCharacters)
        let digits = String(PackLimits.numberRange.upperBound).count
        #expect(PackLimits.templateLiteral.characters + digits + 2 <= TemplatePatternSpec.expandedTriggerCharacters)
    }

    @Test("★ 검증 F-6 ① — 폼으로 생길 수 없는 사유(버그)는 F3 꼴 — 「처음부터 다시」가 아니라 「앱을 다시 열어」, 내용 없음")
    func impossibleFailuresUseInternalErrorCopy() {
        for failure in [PackCompileFailure.templateNotAllowed, .noValidRecords] {
            #expect(PackFormCopy.compileFailure(failure) == "문제가 생겨서 가져오지 못했어요. 앱을 다시 열어 주세요.")
        }
        #expect(PackNoticeCopy.message(.internalError, firstName: "", count: 0).hasSuffix("앱을 다시 열어 주세요."), "F3과 같은 끝말")
    }
}
