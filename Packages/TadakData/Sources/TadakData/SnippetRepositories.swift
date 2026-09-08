import Foundation
import TadakDomain

/// 번들 JSON 하나가 내장 채움글 팩 하나다.
///
/// - `Snippets.json` — 국가 상징문(팩 id `anthem`): 애국가 1~4절(작사자 미상 공유저작물), 국기에 대한 맹세·헌법
///   전문·전 조문(저작권법 제7조 비보호 저작물, 법제처 원문 — `tools/convert_constitution.py`), 기미독립선언서 서두(1919, 만료).
/// - `Greetings.json` — 인사·상용구(팩 id `greetings`): 자체 작성 문구.
/// 저작권 있는 본문(찬송가 등)은 곡별 확인 전에는 넣지 않는다 (`docs/design-reviews/snippet-autocomplete.md`,
/// `snippet-packs-greetings-national.md`).
public struct BundledSnippetRepository: SnippetRepository {

    private let bundled: [SnippetEntry]

    /// - Parameters:
    ///   - resourceName: 번들 JSON 이름 (기본 `Snippets` = 국가 상징 팩, `Greetings` = 인사·상용구 팩)
    ///   - bundle: nil이면 패키지 리소스 번들 (테스트에서만 바꾼다)
    public init(resourceName: String = "Snippets", bundle: Bundle? = nil) {
        guard let url = (bundle ?? .module).url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([SnippetEntry].self, from: data)
        else {
            bundled = []
            return
        }
        bundled = entries
    }

    public func entries() -> [SnippetEntry] {
        bundled
    }
}

/// App Group을 통한 사용자 정의 채움글 저장소.
///
/// `AppGroupSettingsRepository`와 같은 단방향이다 — `save()`는 컨테이너 앱 전용이고,
/// 키보드 익스텐션은 `entries()`만 쓴다 (읽기는 Full Access 불필요).
public struct AppGroupSnippetRepository: SnippetRepository {

    private static let key = "keyboard.userSnippets"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    /// 사용자 문구를 읽는다. 접근 불가·데이터 없음이면 빈 배열 — 실패하지 않는다.
    public func entries() -> [SnippetEntry] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.key),
              let entries = try? JSONDecoder().decode([SnippetEntry].self, from: data)
        else {
            return []
        }
        return entries
    }

    /// 사용자 문구를 쓴다. **컨테이너 앱에서만 호출한다** (Phase 6 관리 화면).
    /// - Returns: 저장에 성공했는지. 익스텐션에서 Full Access 없이 호출하면 `false`.
    @discardableResult
    public func save(_ entries: [SnippetEntry]) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(entries) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
