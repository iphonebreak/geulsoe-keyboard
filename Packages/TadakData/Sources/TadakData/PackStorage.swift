import Foundation
import TadakDomain

// 외부 채움글 저장(1-b) 공용 부품 — 위치·세대 카운터·파일 읽기·사용자 문구 저장 경계.
// PDR `docs/design-reviews/external-snippet-packs.md` 2절(계획 A: 파일 + snapshot)·8절(snapshot 계약).

/// 저장 위치. **변환본(꺼진 팩 포함)은 앱 전용**, 키보드가 읽는 **활성 snapshot만 App Group 공유**에 둔다(2절 그림).
public enum PackStorageLocations {
    /// App Group 공유 — snapshot `g<N>/` 폴더들이 여기 생긴다. 키보드는 읽기만(전체 접근 불필요 — P-1 실측)
    public static func snapshotRoot(groupContainer: URL) -> URL {
        groupContainer.appendingPathComponent("Library/Application Support/ExternalPacks", isDirectory: true)
    }

    /// 앱 전용 — 변환본 JSON과 목록(`library.json`). 키보드 프로세스에서는 부르지 않는다
    public static func appLibraryRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ExternalPacks", isDirectory: true)
    }

    public static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupSettingsRepository.appGroupIdentifier)
    }

    static func generationDirectory(_ generation: Int, in root: URL) -> URL {
        root.appendingPathComponent("g\(generation)", isDirectory: true)
    }

    static let manifestFileName = "manifest.json"
}

/// 세대 카운터 둘(8-1) — 키보드는 읽기만 한다. 값은 신호일 뿐, 내용은 snapshot 파일에서 읽는다.
public protocol PackGenerationReading: Sendable {
    /// 내 채움글을 저장할 때마다 오른다
    var userSnippetsGeneration: Int { get }
    /// 새 snapshot `g<N>`을 다 쓴 뒤 `N`으로 바뀐다(커밋 지점)
    var packsGeneration: Int { get }
}

/// 앱만 쓴다(키보드는 전체 접근 없이 App Group에 쓸 수 없다 — 비대칭).
public protocol PackGenerationWriting: PackGenerationReading {
    func setUserSnippetsGeneration(_ value: Int)
    func setPacksGeneration(_ value: Int)
}

/// App Group `UserDefaults`의 두 정수 — `keyboard.userSnippetsGeneration`·`keyboard.packsGeneration`(8-1).
public struct AppGroupPackGenerations: PackGenerationWriting {
    static let userKey = "keyboard.userSnippetsGeneration"
    static let packsKey = "keyboard.packsGeneration"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    public var userSnippetsGeneration: Int { defaults?.integer(forKey: Self.userKey) ?? 0 }
    public var packsGeneration: Int { defaults?.integer(forKey: Self.packsKey) ?? 0 }
    public func setUserSnippetsGeneration(_ value: Int) { defaults?.set(value, forKey: Self.userKey) }
    public func setPacksGeneration(_ value: Int) { defaults?.set(value, forKey: Self.packsKey) }
}

/// 키보드의 파일 읽기 — **짧게 열어 전부 읽고 바로 놓는다**(8-2). 크기를 먼저 보고(9-4 ③) 그다음 읽는다.
public protocol PackFileReading: Sendable {
    /// 실제 바이트 — 없으면 nil(앱이 더 새 세대를 만들고 지웠을 수 있다 → 재시도)
    func size(of url: URL) -> Int?
    /// 내용 — 없으면 nil. 크기는 부르는 쪽이 `size(of:)`와 대조한다
    func read(_ url: URL) -> Data?
}

/// 실제 파일 — 매핑 읽기(P-1 실측: 3MB 0.4~0.5ms, 전체 접근 끔에서 성공). snapshot 파일은 다시 쓰지 않고(새 세대 폴더에
/// 새로 쓴다) 지우기만 하므로 매핑 도중 내용이 바뀌지 않는다.
public struct SystemPackFileReader: PackFileReading {
    public init() {}

    public func size(of url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }

    public func read(_ url: URL) -> Data? {
        try? Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

/// 내 채움글 저장 경계 — 제품은 App Group `UserDefaults`(`AppGroupSnippetRepository`). **쓰기는 `PackStore`만** 한다(AC-2).
public protocol UserSnippetStoring: Sendable {
    func entries() -> [SnippetEntry]
    @discardableResult func save(_ entries: [SnippetEntry]) -> Bool
}

extension AppGroupSnippetRepository: UserSnippetStoring {}
