import Foundation
import TadakDomain

/// 가져오기 폼의 최종 값 — **폼이 최종 권위**(5-6). `#` 메타는 미리 채움일 뿐이고 파일명은 쓰지 않는다.
/// 모드별로 칸이 다르다 — 번호형 = 이름·틀(별칭 포함)·권리, 문구형 = 이름·권리(틀 칸 없음).
public struct PackForm: Equatable, Sendable {
    public var name: String
    /// 권리 표기 — 필수. 화면의 짧은 선택지(직접 작성함·사용 허락을 받음·공개 도메인·그 밖)는 **권리 증명이 아니다**(R7)
    public var license: String
    /// 번호형 `#틀` 별칭 1~8 — 첫 값이 칩 제목 형식(`titleFormat`)
    public var templateSpecs: [String]

    public init(name: String, license: String, templateSpecs: [String] = []) {
        self.name = name
        self.license = license
        self.templateSpecs = templateSpecs
    }
}

/// 최종 후보 컴파일 실패 — 내용 없는 코드(11절). 위치는 틀 순번(정수)만
public enum PackCompileFailure: Error, Equatable, Sendable {
    case nameMissing
    case nameTooLong
    case licenseMissing
    case licenseTooLong
    /// 번호형인데 틀이 없다
    case templateRequired
    /// 문구형인데 틀이 있다(혼재)
    case templateNotAllowed
    /// 틀 별칭이 8개를 넘는다(같은 쌍으로 합친 뒤)
    case tooManyPatterns
    /// `index`번째 틀(0부터)이 스키마·성경 충돌 검사를 통과하지 못했다
    case pattern(index: Int, TemplatePatternSpec.Failure)
    /// 유효 레코드 0
    case noValidRecords
}

/// 커밋 게이트 2단계 「최종 후보를 구성한다」(9-2) — 폼이 확정한 이름·틀·별칭·권리로 컴파일 → 정리 → 검증.
/// 예산(`ActivePackBudget`)과 10절 충돌 재판정은 이 결과로 커밋 직전에 다시 한다 — 미리보기 판정은 낡을 수 있다(AC-3).
public enum PackCompiler {

    public static func compile(_ draft: PackDraft, form: PackForm) throws(PackCompileFailure) -> ExternalPack {
        guard draft.isImportable else { throw .noValidRecords }
        let name = PackTextSanitizer.sanitize(form.name).text
        let license = PackTextSanitizer.sanitize(form.license).text
        guard !name.allSatisfy(\.isWhitespace) else { throw .nameMissing }
        guard PackLimits.name.admits(name) else { throw .nameTooLong }
        guard !license.allSatisfy(\.isWhitespace) else { throw .licenseMissing }
        guard PackLimits.license.admits(license) else { throw .licenseTooLong }

        let specs = form.templateSpecs
            .map { PackTextSanitizer.sanitize($0).text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        switch draft.mode {
        case .phrases:
            guard specs.isEmpty else { throw .templateNotAllowed }
            return ExternalPack(name: name, license: license, mode: .phrases, entries: draft.entries)
        case .numbered:
            guard !specs.isEmpty else { throw .templateRequired }
            // 스키마 먼저(싸다) → 같은 쌍 합치기 → 개수 → 성경 전체 n 검사(9,999 × 별칭 — 가져오기 시점에만)
            var parsed: [(index: Int, raw: String, pattern: TemplatePattern)] = []
            for (index, raw) in specs.enumerated() {
                switch TemplatePatternSpec.parse(raw) {
                case .success(let pattern):
                    // 띄어쓰기만 다른 별칭은 같은 쌍(10-4 2번) — 하나로
                    if !parsed.contains(where: { $0.pattern == pattern }) { parsed.append((index, raw, pattern)) }
                case .failure(let failure):
                    throw .pattern(index: index, failure)
                }
            }
            guard parsed.count <= PackLimits.templatePatterns else { throw .tooManyPatterns }
            for spec in parsed {
                if let n = TemplatePatternSpec.firstBibleCollision(spec.pattern, raw: spec.raw) {
                    throw .pattern(index: spec.index, .collidesWithBible(n: n))
                }
            }
            let patterns = parsed.map(\.pattern)
            let template = PackTemplate(patterns: patterns, titleFormat: specs[0], items: draft.items)
            return ExternalPack(name: name, license: license, mode: .numbered, template: template)
        }
    }
}
