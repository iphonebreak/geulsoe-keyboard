import Foundation

/// 채움글 항목 — **단축어**를 치면 본문 전문으로 바뀐다.
///
/// 내장 팩(애국가)과 사용자 정의 문구가 같은 형태를 쓴다. 성경은 규모(3만 절) 때문에
/// 이 형태로 들지 않고 `BibleVerseRepository`로 따로 조회한다.
///
/// ## 용어 — 「트리거」가 아니라 「단축어」다 (2026-09-15)
///
/// 사용자가 "트리거"의 뜻을 모른다. **iOS 설정 → 일반 → 키보드 → 텍스트 대치**가 쓰는
/// 애플 공식 한국어 용어가 「단축어」라 설명이 거의 필요 없다.
/// **코드 식별자(`trigger`·`triggers`)는 영어 그대로 둔다** — 글쇠 개명 때와 같은 원칙이다
/// (CLAUDE.md: 번들 ID·클래스 이름은 그대로, 사용자에게 보이는 문자열만 바꾼다).
public struct SnippetEntry: Codable, Equatable, Sendable {

    /// 입력 꼬리의 접미사와 맞아야 하는 단축어들. **하나에 여럿을 둘 수 있다**
    /// (예: `["우리집주소", "집주소"]`). 매칭은 **띄어쓰기를 보지 않는다** —
    /// 규칙은 `SnippetMatcher` 참조.
    ///
    /// 빈 배열이어도 크래시하지 않는다 — **발동하지 않는 죽은 항목**이 될 뿐이다.
    /// 옛 저장본에 단축어 키가 아예 없을 때 이 상태가 된다.
    public var triggers: [String]
    /// 추천 칩에 보여줄 짧은 이름
    public var title: String
    /// 삽입될 전문
    public var body: String

    /// 제목 기본값·목록 표시에 쓰는 대표 단축어. 비었으면 빈 문자열.
    public var primaryTrigger: String { triggers.first ?? "" }

    public init(triggers: [String], title: String, body: String) {
        self.triggers = triggers
        self.title = title
        self.body = body
    }

    /// 단축어가 하나뿐인 자리에서 쓰는 편의 생성자 — 내장 팩과 기존 호출부가 이 모양이다.
    public init(trigger: String, title: String, body: String) {
        self.init(triggers: [trigger], title: title, body: body)
    }

    // MARK: - Codable

    /// ## 하위 호환 — 옛 스키마를 그대로 읽는다
    ///
    /// 두 곳이 **단일 `trigger` 문자열**로 돼 있다:
    /// 1. 사용자 기기 App Group 에 이미 저장된 사용자 문구
    /// 2. **내장 팩 JSON** (`Snippets.json`·`Greetings.json`)
    ///
    /// **팩 JSON 은 고치지 않는다** — 번들 리소스를 건드리면 회귀 위험이 늘고, 디코더 한 곳이
    /// 흡수하면 끝나는 일이다. 그래서 여기서 둘 다 받는다.
    ///
    /// - `triggers` 가 있으면 그것을 쓴다 (**새 스키마가 이긴다**)
    /// - 없으면 `trigger` 를 1개짜리 배열로
    /// - 둘 다 없으면 **빈 배열** — 실패시키지 않는다. 항목 하나 때문에 목록 전체가
    ///   디코딩 실패로 사라지는 쪽이 훨씬 나쁘다
    ///
    /// 인코딩은 **`triggers` 로만** 쓴다. 옛 키를 함께 남기면 무엇이 진짜인지 모호해진다.
    private enum CodingKeys: String, CodingKey {
        case triggers
        case trigger      // 옛 스키마 전용 (읽기만)
        case title
        case body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let list = try container.decodeIfPresent([String].self, forKey: .triggers) {
            triggers = list
        } else if let single = try container.decodeIfPresent(String.self, forKey: .trigger) {
            triggers = [single]
        } else {
            triggers = []
        }
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(triggers, forKey: .triggers)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
    }
}

/// 내장 채움글 팩 id — `KeyboardSettings.disabledSnippetPacks`와 조립 지점 필터가 공유한다.
public enum SnippetPack {
    public static let bible = "bible"
    /// 국가 상징문 — 애국가 1~4절, 국기에 대한 맹세, 헌법 전문·제1조, 기미독립선언서 서두 (2026-09-07 확장).
    /// id는 구 저장분 호환을 위해 "anthem" 그대로 둔다.
    public static let anthem = "anthem"
    /// 인사·상용구 — 명절 인사, 축하, 조의, 감사, 사과 (자체 작성 문구, 2026-09-07)
    public static let greetings = "greetings"
}

/// 채움글 목록 경계 — 내장 팩과 사용자 문구가 이 프로토콜로 합쳐진다.
///
/// 사용자 문구는 설정 앱이 App Group에 쓰고 키보드는 읽기만 한다
/// (`SettingsRepository`와 같은 단방향 — Full Access 불필요).
public protocol SnippetRepository: Sendable {
    /// 실패하지 않는다 — 접근 불가·데이터 없음이면 빈 배열을 낸다.
    func entries() -> [SnippetEntry]
}

/// 성경 본문 조회 경계. 책 번호는 개역한글 66권 순서(1=창세기 … 66=요한계시록).
public protocol BibleVerseRepository: Sendable {
    /// 존재하지 않는 절이면 nil. 실패하지 않는다 (리소스 불가 시에도 nil).
    func text(book: Int, chapter: Int, verse: Int) -> String?
}

public extension SnippetEntry {

    /// 매칭·중복 판정에 쓰는 정규화 — **공백·개행을 없앤다.**
    /// "우리집주소"와 "우리집 주소"와 "우 리 집 주 소"는 전부 같은 것으로 본다
    /// (사장님 지시 2026-09-15). `SnippetMatcher` 가 쓰는 규칙과 **같은 함수**여야 한다 —
    /// 두 군데서 따로 정의하면 설정 화면의 중복 판정과 키보드의 발동이 갈린다.
    static func normalizedTrigger(_ trigger: String) -> String {
        trigger.filter { !$0.isWhitespace }
    }

    /// 편집 시트의 쉼표 입력을 단축어 목록으로. 빈 것 제거 + **정규화 기준** 중복 제거.
    ///
    /// 쉼표로 나누고 각각 trim 한 뒤, 빈 조각을 버리고, `normalizedTrigger` 가 같은 것을
    /// 하나로 합친다 (`우리집주소, 우리집 주소` → 1개).
    ///
    /// **저장되는 값은 사용자가 친 원문이다** — 정규화는 **중복 판정에만** 쓴다.
    /// `우리집 주소` 로 쳤으면 `우리집 주소` 가 남는다 (목록 표시가 입력한 모양 그대로여야 한다).
    ///
    /// 길이·개수 상한은 **여기서 보지 않는다** — 편집 시트가 원문 기준으로 판정한다.
    ///
    /// 뷰(`SnippetEditorView`) 안의 `private var` 였던 것을 여기로 옮겼다 —
    /// 테스트가 닿지 않아 파싱 규칙이 고정되지 않았다 (검증자 제안 5-1, 2026-09-15).
    static func parseTriggers(_ input: String) -> [String] {
        var seen = Set<String>()
        return input
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert(Self.normalizedTrigger($0)).inserted }
    }

    /// 편집·추가 결과를 **내 채움글 목록에 반영한다.**
    ///
    /// ## ★ 왜 도메인에 있나
    ///
    /// 이 규칙은 설정 화면(`App/`)의 `save`에 있었는데 **`swift test`가 닿지 않는다.**
    /// 그래서 「고치면 자리가 뒤로 튄다」를 **아무도 못 잡았다**(검증자 2026-09-23 실측).
    /// 합성 게이트·`mergingHiddenTools`와 같은 이유로 여기로 내렸다.
    ///
    /// ## 규칙
    ///
    /// | | |
    /// |---|---|
    /// | **추가**(`editing == nil`) | **맨 뒤**에 붙인다 — 방금 만든 것이 끝에 오는 것이 자연스럽다 |
    /// | **편집**(`editing != nil`) | **원본이 있던 자리**를 지킨다 |
    ///
    /// ## ★ 두 번 지우는 구조와 인덱스가 부딪히는 자리
    ///
    /// 지워야 할 것이 둘이다 — **원본**(단축어를 통째로 바꿨을 때 옛 항목이 남지 않게)과
    /// **단축어가 겹치는 기존 항목**(한쪽만 겹쳐도 어느 쪽이 발동할지 사용자가 알 수 없다).
    ///
    /// 그런데 겹쳐서 지워지는 항목이 **원본보다 앞에 있으면 자리가 그만큼 당겨진다.**
    /// 그래서 원본 인덱스를 그대로 쓰면 안 되고, **앞에서 지워진 개수만큼 빼야** 한다
    /// (`removedBefore`). 이 보정을 빠뜨리면 항목이 지워진 수만큼 뒤로 밀린다.
    ///
    /// 원본을 목록에서 못 찾으면(있을 수 없는 입력) **맨 뒤**로 간다 — 잃어버리지는 않는다.
    ///
    /// - Parameter editing: 고치는 중인 원본. nil이면 추가다.
    static func applying(
        _ entry: SnippetEntry, editing original: SnippetEntry?, to list: [SnippetEntry]
    ) -> [SnippetEntry] {
        let originalIndex = original.flatMap { target in
            list.firstIndex { $0.snippetListID == target.snippetListID }
        }
        let incoming = Set(entry.triggers.map(Self.normalizedTrigger))

        var kept: [SnippetEntry] = []
        var removedBefore = 0
        for (index, existing) in list.enumerated() {
            let isOriginal = original.map { $0.snippetListID == existing.snippetListID } ?? false
            let overlaps = existing.triggers.contains { incoming.contains(Self.normalizedTrigger($0)) }
            guard isOriginal || overlaps else {
                kept.append(existing)
                continue
            }
            if let originalIndex, index < originalIndex { removedBefore += 1 }
        }

        guard let originalIndex else {
            kept.append(entry)      // 추가 — 맨 뒤
            return kept
        }
        kept.insert(entry, at: min(originalIndex - removedBefore, kept.count))
        return kept
    }

    /// ★ 단축어에 **쉼표**가 들어 있는가 — 편집 왕복에서 **쪼개지는** 항목이다.
    ///
    /// ## 왜 이것이 존재할 수 있나 (2026-09-23 `git log` 확인)
    ///
    /// v1.0.1까지 편집기는 단축어 칸이 **하나**였고 검증이 *공백 trim + 40자*뿐이었다 —
    /// **쉼표를 막지 않았다**(`d3707be:App/Settings/SnippetSettingsView.swift` 139·173행).
    /// 그리고 `triggers` 스키마로 올라올 때 디코더는 옛 단일 값을 **그대로 한 원소로** 싣는다
    /// (`triggers = [single]`) — 쪼개지 않는다.
    ///
    /// 그래서 `"가,나"` 같은 단축어가 **저장분에 있을 수 있다.**
    /// 지금 편집기는 불러올 때 `joined(", ")`, 저장할 때 `parseTriggers`가 쉼표로 나누므로
    /// **열었다 저장만 해도 둘로 갈린다** — 게다가 발동 범위가 넓어진다
    /// (`"가,나"` 하나가 `"가"`·`"나"` 둘이 되어 아무 데서나 뜬다).
    ///
    /// ## ★ 그래서 고치지 않고 **알린다**
    ///
    /// 마이그레이션으로 조용히 바꾸는 것이 더 위험하다 — 사용자가 등록한 값을 우리가
    /// 해석해서 덮어쓰는 것이고, 되돌릴 근거도 남지 않는다.
    /// **편집기가 경고를 띄우고 사용자가 정한다.** 저장을 막지도 않는다.
    var hasCommaInTrigger: Bool {
        triggers.contains { $0.contains(",") }
    }

    /// 목록 `ForEach` 의 안정된 id. 단축어가 여럿이라 하나만 쓰면 서로 다른 항목이 같은 id 를
    /// 가질 수 있다. 정규화한 단축어를 이어 붙여 쓴다.
    var snippetListID: String {
        triggers.map(Self.normalizedTrigger).joined(separator: "\u{1F}")
    }
}
