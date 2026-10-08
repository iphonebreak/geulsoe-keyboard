import Foundation

/// 외부 채움글 팩 — 사용자가 가져온 CSV(뒤에 xlsx·`.gspack`)를 검증·변환한 결과
/// (PDR `docs/design-reviews/external-snippet-packs.md` 7절 변환본, 10-1절 템플릿 스키마).
///
/// 앱(가져오기·저장)과 키보드(읽기·매칭)가 **같은 값 타입**을 쓴다 — 키보드는 stats를 믿지 않고
/// 이 값에서 다시 센다(9-4). 저장 형식(schema·packID·generation)은 저장 단계(1-b)가 감싼다.
///
/// **본문·단축어·이름·권리는 사용자 입력이다** — 로그·파일(저장소 밖)·네트워크로 내보내지 않는다(보안 규칙).
public struct ExternalPack: Codable, Equatable, Sendable {

    /// 헤더가 정한다 — `번호` 열이면 번호형, `단축어` 열이면 문구형(5-3).
    public enum Mode: String, Codable, Sendable {
        /// `#틀`(템플릿 `{n}`) + 번호별 항목 — 「사자성어 12번」을 치면 12번 본문
        case numbered
        /// 단축어 → 본문 — `SnippetEntry`와 같은 모양
        case phrases
    }

    public var name: String
    public var license: String
    public var mode: Mode
    /// 문구형 항목 — 번호형이면 빈 배열
    public var entries: [SnippetEntry]
    /// 번호형 템플릿 — 문구형이면 nil
    public var template: PackTemplate?

    public init(name: String, license: String, mode: Mode, entries: [SnippetEntry] = [], template: PackTemplate? = nil) {
        self.name = name
        self.license = license
        self.mode = mode
        self.entries = entries
        self.template = template
    }
}

/// 번호형 팩의 템플릿 — `#틀` 별칭 1~8개가 **같은 항목들**을 가리킨다(10-1).
public struct PackTemplate: Codable, Equatable, Sendable {
    /// 별칭 순서 = 팩 내부 패턴 순서(10-4 동점 규칙의 둘째 기준)
    public var patterns: [TemplatePattern]
    /// 제목이 빈 항목의 칩 제목 — `{n}`을 번호로 바꾼다(첫 `#틀` 원문)
    public var titleFormat: String
    /// 번호 오름차순, 번호는 유일하다(같은 번호는 뒤에 나온 것이 이긴 결과)
    public var items: [PackTemplateItem]

    public init(patterns: [TemplatePattern], titleFormat: String, items: [PackTemplateItem]) {
        self.patterns = patterns
        self.titleFormat = titleFormat
        self.items = items
    }

    /// 칩 제목 — 항목 제목이 비었으면 `titleFormat`의 `{n}`을 번호로 채운다(v2 4-5)
    public func title(for item: PackTemplateItem) -> String {
        item.title.isEmpty ? titleFormat.replacingOccurrences(of: "{n}", with: String(item.n)) : item.title
    }
}

/// `접두{n}접미` 한 개 — 접두·접미는 **정규화(공백 제거) 뒤** 값이다(R3·10-1).
/// 정규화는 `SnippetEntry.normalizedTrigger` **한 함수**만 쓴다(CLAUDE.md 채움글 절).
public struct TemplatePattern: Codable, Equatable, Hashable, Sendable {
    public var prefix: String
    public var suffix: String

    public init(prefix: String, suffix: String) {
        self.prefix = prefix
        self.suffix = suffix
    }

    /// 접두+접미 정규화 길이 — 긴 쪽이 이긴다(10-5), 40 이하(10-1)
    public var literalLength: Int { prefix.count + suffix.count }
}

public struct PackTemplateItem: Codable, Equatable, Sendable {
    /// 1~9,999
    public var n: Int
    /// 비면 `PackTemplate.titleFormat`으로 채운다
    public var title: String
    public var body: String

    public init(n: Int, title: String, body: String) {
        self.n = n
        self.title = title
        self.body = body
    }
}
