import Foundation
import Testing
import TadakDomain
@testable import PackImport

/// 최종 후보 컴파일 — 폼이 최종 권위(5-6), 커밋 직전 재검사의 「최종 DTO」(9-2 2단계, AC-3 일부 · AC-20 일부).
@Suite("최종 후보 컴파일 (5-6 · 9-2)")
struct PackCompilerTests {

    private func numberedDraft() throws -> PackDraft {
        try ImportHelper.draft(data: ImportHelper.fixture("sample-numbered.original"))
    }

    private func phrasesDraft() throws -> PackDraft {
        try ImportHelper.draft(data: ImportHelper.fixture("sample-phrases.original"))
    }

    @Test("번호형 — 폼의 이름·권리·틀(별칭 순서)로 팩을 만든다, 제목 기본값은 첫 틀")
    func numbered() throws {
        let draft = try numberedDraft()
        let form = PackForm(name: "사자성어 예시 팩", license: "직접 작성함", templateSpecs: draft.meta.templateSpecs)
        let pack = try PackCompiler.compile(draft, form: form)
        #expect(pack.mode == .numbered && pack.entries.isEmpty)
        #expect(pack.name == "사자성어 예시 팩" && pack.license == "직접 작성함")
        let template = try #require(pack.template)
        #expect(template.patterns == [TemplatePattern(prefix: "사자성어", suffix: "번"), TemplatePattern(prefix: "성어", suffix: "번")])
        #expect(template.titleFormat == "사자성어 {n}번")
        #expect(template.items.count == 20)
        #expect(template.title(for: PackTemplateItem(n: 7, title: "", body: "b")) == "사자성어 7번")
    }

    /// 폼에서 바꾼 틀이 최종 DTO에 들어간다 — 미리보기 판정은 낡을 수 있다(AC-3)
    @Test("폼에서 바꾼 틀·이름이 최종 결과다 — 파일 `#틀`은 미리 채움일 뿐")
    func formIsFinalAuthority() throws {
        let pack = try PackCompiler.compile(try numberedDraft(),
                                            form: PackForm(name: "바꾼 이름", license: "공개 도메인", templateSpecs: ["고사성어 {n}번"]))
        #expect(pack.name == "바꾼 이름")
        #expect(pack.template?.patterns == [TemplatePattern(prefix: "고사성어", suffix: "번")])
        #expect(pack.template?.titleFormat == "고사성어 {n}번")
    }

    @Test("띄어쓰기만 다른 별칭은 같은 쌍 — 하나로 합친다(10-4 2번)")
    func spacingOnlyAliasesCollapse() throws {
        let pack = try PackCompiler.compile(try numberedDraft(),
                                            form: PackForm(name: "n", license: "l", templateSpecs: ["사자성어 {n}번", "사자성어{n} 번"]))
        #expect(pack.template?.patterns.count == 1)
    }

    @Test("문구형 — 틀 칸이 없다(있으면 거부), 항목은 그대로")
    func phrases() throws {
        let draft = try phrasesDraft()
        let pack = try PackCompiler.compile(draft, form: PackForm(name: "업무 상용구 예시", license: "직접 작성함"))
        #expect(pack.mode == .phrases && pack.template == nil && pack.entries.count == 15)
        #expect(throws: PackCompileFailure.templateNotAllowed) {
            try PackCompiler.compile(draft, form: PackForm(name: "n", license: "l", templateSpecs: ["가나 {n}번"]))
        }
    }

    @Test("모드별 필수 칸과 필드 상한 (AC-20 일부)", arguments: [
        (PackForm(name: "", license: "l", templateSpecs: ["사자성어 {n}번"]), PackCompileFailure.nameMissing),
        (PackForm(name: "  ", license: "l", templateSpecs: ["사자성어 {n}번"]), .nameMissing),
        (PackForm(name: String(repeating: "가", count: 41), license: "l", templateSpecs: ["사자성어 {n}번"]), .nameTooLong),
        (PackForm(name: "n", license: "", templateSpecs: ["사자성어 {n}번"]), .licenseMissing),
        (PackForm(name: "n", license: String(repeating: "가", count: 121), templateSpecs: ["사자성어 {n}번"]), .licenseTooLong),
        (PackForm(name: "n", license: "l", templateSpecs: []), .templateRequired),
        (PackForm(name: "n", license: "l", templateSpecs: ["가", "나", "다", "라", "마", "바", "사", "아", "자"].map { "별칭\($0) {n}번" }), .tooManyPatterns),
        (PackForm(name: "n", license: "l", templateSpecs: ["사자성어 {n}번", "회차2{n}번"]), .pattern(index: 1, .prefixEndsWithDigit)),
        (PackForm(name: "n", license: "l", templateSpecs: ["창세기{n}장1절"]), .pattern(index: 0, .collidesWithBible(n: 1))),
        (PackForm(name: "n", license: "l", templateSpecs: ["창 세 기 {n}장 1절"]), .pattern(index: 0, .collidesWithBible(n: 1)))
    ])
    func numberedFormRules(testCase: (form: PackForm, failure: PackCompileFailure)) throws {
        let draft = try numberedDraft()
        #expect(throws: testCase.failure) { try PackCompiler.compile(draft, form: testCase.form) }
    }

    /// 검증 F7 — 빈 칸을 거른 뒤 순번을 매기면 폼 칸과 어긋난다(`["", "회차2{n}번"]` → 예전 index 0)
    @Test("틀 오류 순번은 폼의 원래 칸 순번이다 — 빈 칸을 건너뛰어도 당기지 않는다 (F7)", arguments: [
        (["", "회차2{n}번"], PackCompileFailure.pattern(index: 1, .prefixEndsWithDigit)),
        (["  ", "사자성어 {n}번", "", "창세기{n}장1절"], .pattern(index: 3, .collidesWithBible(n: 1)))
    ])
    func patternIndexIsFormSlot(testCase: (specs: [String], failure: PackCompileFailure)) throws {
        let draft = try numberedDraft()
        #expect(throws: testCase.failure) {
            try PackCompiler.compile(draft, form: PackForm(name: "n", license: "l", templateSpecs: testCase.specs))
        }
    }

    @Test("앞 칸이 비어 있으면 제목 형식은 첫 비지 않은 칸")
    func titleFormatSkipsBlankSlots() throws {
        let pack = try PackCompiler.compile(try numberedDraft(),
                                            form: PackForm(name: "n", license: "l", templateSpecs: ["", "사자성어 {n}번"]))
        #expect(pack.template?.titleFormat == "사자성어 {n}번")
    }

    @Test("이름·권리 40·120자 경계는 받는다")
    func fieldBoundaries() throws {
        let pack = try PackCompiler.compile(try phrasesDraft(),
                                            form: PackForm(name: String(repeating: "가", count: 40), license: String(repeating: "나", count: 120)))
        #expect(pack.name.count == 40 && pack.license.count == 120)
    }

    @Test("유효 레코드 0인 초안은 컴파일하지 않는다")
    func noValidRecords() throws {
        let draft = try ImportHelper.draft("번호,본문\r\n,a")
        #expect(throws: PackCompileFailure.noValidRecords) {
            try PackCompiler.compile(draft, form: PackForm(name: "n", license: "l", templateSpecs: ["사자성어 {n}번"]))
        }
    }
}
