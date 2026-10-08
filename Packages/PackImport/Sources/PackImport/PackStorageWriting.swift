import Foundation
import TadakData
import TadakDomain

// 외부 채움글 저장(1-b)의 **쓰기 쪽** 부품 — 앱 전용 모듈(PackImport)에만 있다. 키보드가 링크하는 TadakData에는 읽기 쪽만 남는다
// (`PackGenerationReading`·`AppGroupPackGenerations`(읽기 전용)·`PackFileReading`·`PackSnapshotLoader`) — 키보드 코드가 여기 있는
// 쓰기를 부르면 **빌드가 실패한다**(codex 반론 #11, 사장님 결정 2026-10-06).

/// 세대 카운터 쓰기 — 앱(`PackStore`)만 쓴다(키보드는 전체 접근 없이 App Group에 쓸 수 없다 — 비대칭).
public protocol PackGenerationWriting: PackGenerationReading {
    func setUserSnippetsGeneration(_ value: Int)
    func setPacksGeneration(_ value: Int)
}

/// App Group `UserDefaults`의 두 정수를 **쓰는** 쪽 — 읽기는 TadakData `AppGroupPackGenerations`와 같은 키를 본다.
public struct AppGroupPackGenerationWriter: PackGenerationWriting {
    private let reader: AppGroupPackGenerations
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
        self.reader = AppGroupPackGenerations(suiteName: suiteName)
    }

    private var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    public var userSnippetsGeneration: Int { reader.userSnippetsGeneration }
    public var packsGeneration: Int { reader.packsGeneration }
    public func setUserSnippetsGeneration(_ value: Int) { defaults?.set(value, forKey: AppGroupPackGenerations.userKey) }
    public func setPacksGeneration(_ value: Int) { defaults?.set(value, forKey: AppGroupPackGenerations.packsKey) }
}

/// 내 채움글 저장 경계 — **쓰기는 `PackStore`만** 한다(AC-2).
public protocol UserSnippetStoring: Sendable {
    func entries() -> [SnippetEntry]
    @discardableResult func save(_ entries: [SnippetEntry]) -> Bool
}

/// 제품 — App Group `UserDefaults`의 내 채움글. 읽기는 TadakData `AppGroupSnippetRepository`(키보드도 쓴다)와 같고,
/// **쓰기는 여기에만** 있다(키보드 바이너리에 실리지 않는다).
public struct AppGroupUserSnippetStore: UserSnippetStoring {
    private let suiteName: String
    private let reader: AppGroupSnippetRepository

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
        self.reader = AppGroupSnippetRepository(suiteName: suiteName)
    }

    public func entries() -> [SnippetEntry] { reader.entries() }

    /// 사용자 문구를 쓴다 — **컨테이너 앱에서만**(`PackStore`의 커밋 안). 쓸 수 없으면 false
    @discardableResult
    public func save(_ entries: [SnippetEntry]) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(entries) else { return false }
        defaults.set(data, forKey: AppGroupSnippetRepository.storageKey)
        return true
    }
}

extension PackStorageLocations {
    /// 앱 전용 — 변환본 JSON과 목록(`library.json`). 키보드는 이 위치를 모른다
    public static func appLibraryRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ExternalPacks", isDirectory: true)
    }
}
