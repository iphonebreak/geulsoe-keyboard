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
/// **읽기 전용** — 키보드 익스텐션도 이 타입을 쓴다(읽기는 Full Access 불필요). 쓰기는 앱 전용 모듈 PackImport의
/// `AppGroupUserSnippetStore`가 `PackStore` 커밋 안에서만 한다(외부 채움글 1-b — 키보드 바이너리에 쓰기 코드가 실리지 않게).
public struct AppGroupSnippetRepository: SnippetRepository {

    /// App Group `UserDefaults` 키 — 쓰는 쪽(PackImport)도 같은 키를 쓴다
    public static let storageKey = "keyboard.userSnippets"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    /// 사용자 문구를 읽는다. 접근 불가·데이터 없음이면 빈 배열 — 실패하지 않는다.
    public func entries() -> [SnippetEntry] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.storageKey),
              let entries = try? JSONDecoder().decode([SnippetEntry].self, from: data)
        else {
            return []
        }
        return entries
    }
}
