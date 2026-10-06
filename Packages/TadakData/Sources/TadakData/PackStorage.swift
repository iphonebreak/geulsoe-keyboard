import Foundation
import TadakDomain

// 외부 채움글 저장(1-b)의 **읽기 쪽** 공용 부품 — 위치·세대 카운터 읽기·파일 읽기·켜진 내장 문구.
// PDR `docs/design-reviews/external-snippet-packs.md` 2절(계획 A: 파일 + snapshot)·8절(snapshot 계약).
// **이 모듈(TadakData)은 키보드가 링크한다 — 여기에 쓰기 메서드를 두지 않는다.** 쓰기(`PackStore`·세대 setter·내 채움글 저장)는
// 앱 전용 모듈 PackImport에 있다(codex 반론 #11 — 키보드에서 부르면 빌드가 안 된다).

/// 저장 위치. **변환본(꺼진 팩 포함)은 앱 전용**, 키보드가 읽는 **활성 snapshot만 App Group 공유**에 둔다(2절 그림).
public enum PackStorageLocations {
    /// App Group 공유 — snapshot `g<N>/` 폴더들이 여기 생긴다. 키보드는 읽기만(전체 접근 불필요 — P-1 실측)
    public static func snapshotRoot(groupContainer: URL) -> URL {
        groupContainer.appendingPathComponent("Library/Application Support/ExternalPacks", isDirectory: true)
    }

    public static var groupContainer: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroupSettingsRepository.appGroupIdentifier)
    }

    /// snapshot 세대 폴더 `g<N>` — 앱(쓰기)과 키보드(읽기)가 같은 이름을 쓴다
    public static func generationDirectory(_ generation: Int, in root: URL) -> URL {
        root.appendingPathComponent("g\(generation)", isDirectory: true)
    }

    public static let manifestFileName = "manifest.json"
}

/// 세대 카운터 둘(8-1) — 키보드는 읽기만 한다. 값은 신호일 뿐, 내용은 snapshot 파일에서 읽는다.
public protocol PackGenerationReading: Sendable {
    /// 내 채움글을 저장할 때마다 오른다
    var userSnippetsGeneration: Int { get }
    /// 새 snapshot `g<N>`을 다 쓴 뒤 `N`으로 바뀐다(커밋 지점)
    var packsGeneration: Int { get }
}

/// App Group `UserDefaults`의 두 정수 — `keyboard.userSnippetsGeneration`·`keyboard.packsGeneration`(8-1). **읽기 전용** —
/// 쓰는 쪽(`AppGroupPackGenerationWriter`)은 앱 전용 모듈 PackImport에 있다.
public struct AppGroupPackGenerations: PackGenerationReading {
    public static let userKey = "keyboard.userSnippetsGeneration"
    public static let packsKey = "keyboard.packsGeneration"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    public var userSnippetsGeneration: Int { defaults?.integer(forKey: Self.userKey) ?? 0 }
    public var packsGeneration: Int { defaults?.integer(forKey: Self.packsKey) ?? 0 }
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

/// 켜진 내장 문구 팩 — 키보드(`KeyboardViewController.rebuildSnippetMatcher`)와 앱(PackImport `PackStore` baseline)이 같은 순서·같은 모양을 쓴다
/// (국가 상징문 → 인사·상용구). 날짜·성경은 문구가 없는 계산 팩이라 baseline에 들지 않는다.
public enum BuiltInSnippetEntries {
    public static func enabled(
        disabled: Set<String>, anthem: any SnippetRepository, greetings: any SnippetRepository
    ) -> [SnippetEntry] {
        var entries: [SnippetEntry] = []
        if !disabled.contains(SnippetPack.anthem) { entries += anthem.entries() }
        if !disabled.contains(SnippetPack.greetings) { entries += greetings.entries() }
        return entries
    }
}
