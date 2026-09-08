import Foundation

/// 채움글 항목 — 트리거 문구를 치면 본문 전문으로 바뀐다.
///
/// 내장 팩(애국가)과 사용자 정의 문구가 같은 형태를 쓴다. 성경은 규모(3만 절) 때문에
/// 이 형태로 들지 않고 `BibleVerseRepository`로 따로 조회한다.
public struct SnippetEntry: Codable, Equatable, Sendable {
    /// 입력 꼬리의 접미사와 정확히 일치해야 하는 문구 (예: "애국가 1절")
    public var trigger: String
    /// 추천 칩에 보여줄 짧은 이름
    public var title: String
    /// 삽입될 전문
    public var body: String

    public init(trigger: String, title: String, body: String) {
        self.trigger = trigger
        self.title = title
        self.body = body
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
