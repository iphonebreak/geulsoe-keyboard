import Foundation

/// 「글쇠로 열기」가 건넨 잠금 파일 **사본** 정리(PDR `external-snippet-packs.md` 12-10 ③).
///
/// 시스템은 다른 앱에서 「글쇠로 열기」한 파일을 앱 컨테이너의 받은 편지함(`Documents/Inbox` 또는 `tmp/<번들 ID>-Inbox`)에 **복사해** 건넨다
/// (`LSSupportsOpeningDocumentsInPlace` = NO). 가져오기가 끝나면(성공·취소·실패·시트 닫기) 그 사본을 지우고, 앱이 뒤로 갈 때(진행 중인 가져오기가 없을 때) 남은 `*.gspack`을 쓸어 낸다.
///
/// - **받은 편지함·대기 폴더 밖은 절대 지우지 않는다** — 파일 앱에서 고른 원본(사용자 파일)은 그대로 둔다.
/// - **파일 날짜·크기·수정 시각을 읽지 않는다** — 매니페스트에 File Timestamp 사유가 없다(날짜로 고르면 required-reason API가 된다).
///   목록은 속성 미리 읽기 없이(`includingPropertiesForKeys: []`) 이름만 본다.
/// - 실패는 조용히 넘긴다(다음 시작 때 다시 쓸어 낸다). 파일 이름·경로를 로그로 남기지 않는다.
///
/// ★ **시스템이 tmp 받은 편지함 사본을 약 1분 뒤 스스로 지운다**(iPhone SE 2세대 iOS 17.0.3 실기 실측 2026-11-08 — 받은 뒤 약 60초,
/// 앱이 앞에 떠 있어도, 세 번 모두 같았다. 시뮬레이터 iOS 18.6은 `Documents/Inbox`에 두고 지우지 않아 못 봤다).
/// 온보딩 중이거나 다른 시트가 떠 있어 바로 읽지 못한 파일이 그 사이 사라져 「파일을 열 수 없어요」가 났다.
/// 그래서 받자마자 `hold`로 **앱이 쥔 대기 폴더**(`tmp/LockedPackHold`)로 옮긴다 — 정리(`discard`·`sweep`)는 대기 폴더도 함께 본다.
public enum LockedPackInbox {

    /// 대기 폴더 이름 — 시스템 받은 편지함에서 옮겨 온 사본만 둔다
    static let holdFolderName = "LockedPackHold"

    /// 시스템이 사본을 넣는 받은 편지함 — 실제 착지 위치는 iOS 판마다 다르다(실기 iOS 17.0.3 = `tmp/<번들 ID>-Inbox`, 시뮬레이터 iOS 18.6 = `Documents/Inbox`)
    public static func systemInboxDirectories(fileManager: FileManager = .default, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [URL] {
        var directories: [URL] = []
        if let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            directories.append(documents.appendingPathComponent("Inbox", isDirectory: true))
        }
        if let bundleIdentifier {
            directories.append(fileManager.temporaryDirectory.appendingPathComponent("\(bundleIdentifier)-Inbox", isDirectory: true))
        }
        return directories
    }

    /// 앱이 쥔 대기 폴더 — 시스템이 건드리지 않는다(tmp라 앱이 꺼져 있을 때 시스템 정리 대상이 되는 것은 괜찮다)
    public static func holdDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.temporaryDirectory.appendingPathComponent(holdFolderName, isDirectory: true)
    }

    /// 정리 대상 — 시스템 받은 편지함 + 대기 폴더
    public static func inboxDirectories(fileManager: FileManager = .default, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> [URL] {
        systemInboxDirectories(fileManager: fileManager, bundleIdentifier: bundleIdentifier) + [holdDirectory(fileManager: fileManager)]
    }

    /// 「글쇠로 열기」로 받은 **시스템 받은 편지함 사본**을 대기 폴더로 옮기고 새 위치를 돌려준다(같은 컨테이너 안 이름 바꾸기 — 크기·날짜를 읽지 않는다).
    /// 받은 편지함 밖(파일 앱 원본)·이미 대기 폴더에 있는 파일·옮기기 실패는 **받은 URL 그대로** 돌려준다(그때는 예전처럼 곧바로 읽어야 한다).
    /// 새 이름은 `<UUID>.gspack` — 같은 이름 파일을 두 번 받아도 겹치지 않고, 원래 파일 이름은 남기지 않는다
    public static func hold(_ url: URL, fileManager: FileManager = .default, systemInboxes: [URL]? = nil, holdDirectory hold: URL? = nil) -> URL {
        guard isInboxCopy(url, inboxes: systemInboxes ?? systemInboxDirectories(fileManager: fileManager)) else { return url }
        let directory = hold ?? holdDirectory(fileManager: fileManager)
        let destination = directory.appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(GSPackLimits.fileExtension)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }

    /// `url`이 받은 편지함 **바로 안**의 잠금 파일인가(심볼릭 링크 `/private/var` ↔ `/var`를 풀어 비교)
    public static func isInboxCopy(_ url: URL, inboxes: [URL]) -> Bool {
        guard url.isFileURL, PackImportFileTypes.isLockedPack(url) else { return false }
        let parent = canonicalPath(url.deletingLastPathComponent())
        return inboxes.contains { canonicalPath($0) == parent }
    }

    /// 가져오기가 끝난 사본 하나를 지운다 — 받은 편지함·대기 폴더 안일 때만
    public static func discard(_ url: URL, fileManager: FileManager = .default, inboxes: [URL]? = nil) {
        guard isInboxCopy(url, inboxes: inboxes ?? inboxDirectories(fileManager: fileManager)) else { return }
        try? fileManager.removeItem(at: url)
    }

    /// 앱이 뒤로 갈 때(진행 중인 가져오기가 없을 때) — 받은 편지함·대기 폴더의 `*.gspack`만 쓸어 낸다(다른 파일·하위 폴더는 건드리지 않는다)
    public static func sweep(fileManager: FileManager = .default, inboxes: [URL]? = nil) {
        for inbox in inboxes ?? inboxDirectories(fileManager: fileManager) {
            guard let names = try? fileManager.contentsOfDirectory(at: inbox, includingPropertiesForKeys: [], options: []) else { continue }
            for url in names where PackImportFileTypes.isLockedPack(url) && !url.hasDirectoryPath {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
