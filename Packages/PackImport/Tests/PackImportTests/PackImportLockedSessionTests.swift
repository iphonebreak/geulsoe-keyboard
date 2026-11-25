import CryptoKit
import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 잠금 파일(`.gspack`) 받기 — 가져오기 상태기계 쪽(PDR `external-snippet-packs.md` 12-7·12-8·12-10 ④).
// 봉투 형식·암호 자체는 `GSPack*Tests`가 본다. 여기서는 세션이 ① 봉투 검사(KDF 전) → 비밀번호 화면 ② 열기(메인 밖) → 실패면 같은 화면·
// 거부 화면 ③ 풀리면 **붙여넣기와 같은 글자 경로**로 미리보기 ④ 취소·늦은 결과 ⑤ 출처 표시·메타 기본값을 지키는지 본다.
// KDF는 주입한다(시험이 PBKDF2 수십만 번을 돌지 않게) — 실제 PBKDF2와 같은 결과인지는 `GSPack*Tests`의 작동 예시가 본다.

// MARK: - 시험 도구

private let rightPassword = "맞는-비밀번호-1"
private let rightKey = [UInt8](repeating: 0x5A, count: 32)
private let wrongKey = [UInt8](repeating: 0x11, count: 32)

/// KDF 호출 수를 세는 가짜 — 맞는 비밀번호면 `rightKey`, 아니면 다른 키
private final class KDFSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var count: Int { lock.withLock { calls } }

    var derive: GSPackKeyDerivation {
        { [self] password, _, _ in
            lock.withLock { calls += 1 }
            return password == Array(rightPassword.precomposedStringWithCanonicalMapping.utf8) ? rightKey : wrongKey
        }
    }
}

/// 봉투 JSON — 값은 ASCII·한글만 쓰는 시험용이라 이스케이프가 필요 없다
private func envelopeText(name: String, rights: String, iterations: Int, salt: Data, nonce: Data, sealed: Data) -> String {
    """
    {
      "format": "geulsoe-pack",
      "version": 1,
      "inner": "csv-utf8",
      "meta": {
        "name": "\(name)",
        "rights": "\(rights)"
      },
      "encryption": {
        "scheme": "pbkdf2-sha256+aes-256-gcm",
        "iterations": \(iterations),
        "salt": "\(salt.base64EncodedString())",
        "nonce": "\(nonce.base64EncodedString())"
      },
      "ciphertext": "\(sealed.base64EncodedString())"
    }

    """
}

/// `plaintext`를 `rightKey`로 잠근 봉투 — AAD는 파서가 만든 값(12-6)을 그대로 쓴다(자리 표시 암호문으로 한 번 파싱해 얻는다)
private func lockedPack(_ plaintext: Data, name: String = "예시 팩", rights: String = "") throws -> Data {
    let salt = Data((0..<16).map { UInt8($0) })
    let nonce = Data((0..<12).map { UInt8(0xA0 + $0) })
    let placeholder = Data(envelopeText(name: name, rights: rights, iterations: 300_000, salt: salt, nonce: nonce,
                                        sealed: Data(count: GSPackLimits.tagBytes)).utf8)
    let aad = try GSPackEnvelope.parse(placeholder).additionalData
    let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: rightKey), nonce: AES.GCM.Nonce(data: nonce), authenticating: aad)
    return Data(envelopeText(name: name, rights: rights, iterations: 300_000, salt: salt, nonce: nonce,
                             sealed: box.ciphertext + box.tag).utf8)
}

private let numberedCSV = "#틀,예시{n}번\n번호,제목,본문\n1,첫째,예시 본문 하나\n2,둘째,예시 본문 둘\n"

private extension PackImportSession {
    var prompt: PackPasswordPrompt? {
        if case .password(let prompt) = phase { return prompt }
        return nil
    }
    var preview: PackImportPreview? {
        if case .preview(let preview) = phase { return preview }
        return nil
    }
}

/// 봉투를 싣고 검사까지 — 비밀번호 화면이나 거부 화면에서 멈춘다
private func startedLocked(_ data: Data) -> PackImportSession {
    var session = PackImportSession()
    if let run = session.start(.locked(data)) { session.receive(PackImportSession.compute(run, library: nil)) }
    return session
}

/// 비밀번호 한 번 — 메인 밖 일을 같은 자리에서 끝내고, 풀렸으면 글자 경로 읽기까지 마친다
@discardableResult
private func unlock(_ session: inout PackImportSession, _ password: String, spy: KDFSpy) -> Bool {
    guard let run = session.unlock(password: password) else { return false }
    let next = session.receiveUnlock(PackImportSession.open(run, deriveKey: spy.derive))
    guard let next else { return true }
    session.receive(PackImportSession.compute(next, library: nil))
    return true
}

// MARK: - 시험

@Suite("잠금 파일 가져오기 세션 (.gspack, 12-10 ④)")
struct PackImportLockedSessionTests {

    @Test("★ 봉투가 맞으면 비밀번호 화면 — 이름·출처는 「확인 전」 사본, 이때까지 KDF 0회")
    func validEnvelopeAsksPassword() throws {
        let spy = KDFSpy()
        let session = startedLocked(try lockedPack(Data(numberedCSV.utf8), name: "예시 팩", rights: "직접 작성"))
        let prompt = try #require(session.prompt)
        #expect(prompt.meta == GSPackMeta(name: "예시 팩", rights: "직접 작성"))
        #expect(prompt.failure == nil)
        #expect(!session.isWorking)
        #expect(session.sourceKind == .file)   // 잠금 파일도 「파일」 문구를 따른다
        #expect(spy.count == 0)
    }

    @Test("★ 맞는 비밀번호 → 붙여넣기와 같은 글자 경로로 미리보기, 출처 표시 gspack(12-8)")
    func rightPasswordOpensPreview() throws {
        let spy = KDFSpy()
        var session = startedLocked(try lockedPack(Data(numberedCSV.utf8)))
        #expect(unlock(&session, rightPassword, spy: spy))
        let preview = try #require(session.preview)
        #expect(spy.count == 1)
        #expect(preview.draft.readFromLockedPack)
        #expect(preview.draft.encoding == nil)          // 인코딩 확인을 타지 않는다(글자 경로)
        #expect(session.lastReview == nil)
        #expect(preview.draft.items.map(\.n) == [1, 2])
        #expect(!session.isWorking)
    }

    @Test("★ 틀린 비밀번호(M4) — 같은 화면에 오류, 다시 시도할 수 있다")
    func wrongPasswordStaysOnPrompt() throws {
        let spy = KDFSpy()
        var session = startedLocked(try lockedPack(Data(numberedCSV.utf8)))
        #expect(unlock(&session, "틀린-비밀번호", spy: spy))
        #expect(session.prompt?.failure == .wrongPasswordOrDamaged)
        #expect(!session.isWorking)
        #expect(session.hasSource)
        // 고쳐 치면 열린다 — 앞 오류는 지워진다
        #expect(unlock(&session, rightPassword, spy: spy))
        #expect(session.preview != nil)
        #expect(spy.count == 2)
    }

    @Test("빈 비밀번호는 시도하지 않고, 256바이트 초과는 KDF 없이 M6")
    func passwordInputErrors() throws {
        let spy = KDFSpy()
        var session = startedLocked(try lockedPack(Data(numberedCSV.utf8)))
        #expect(session.unlock(password: "") == nil)
        #expect(session.prompt?.failure == nil)
        #expect(session.unlock(password: String(repeating: "가", count: 86)) == nil)   // 86 × 3B = 258B
        #expect(session.prompt?.failure == .passwordTooLong)
        #expect(!session.isWorking)
        #expect(spy.count == 0)
    }

    @Test("★ 봉투 형식 오류(M1)·새 버전(M2)은 비밀번호 화면 없이 거부, 원본을 비운다")
    func malformedEnvelopeFails() throws {
        let session = startedLocked(Data("번호,본문\n1,평문 CSV를 이름만 바꾼 파일\n".utf8))
        #expect(session.phase == .failed(.locked(.malformed)))
        #expect(!session.hasSource)

        let good = try lockedPack(Data(numberedCSV.utf8))
        let newer = String(decoding: good, as: UTF8.self).replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")
        #expect(startedLocked(Data(newer.utf8)).phase == .failed(.locked(.newerVersion)))
    }

    @Test("봉투 상한(12-3 ①)을 넘으면 읽지 않고 M3")
    func envelopeTooLarge() {
        var session = PackImportSession()
        #expect(session.start(.locked(Data(count: GSPackLimits.envelopeBytes + 1))) == nil)
        #expect(session.phase == .failed(.locked(.tooLarge)))
        // 봉투는 평문 상한(3MB)보다 커도 받는다 — 봉투 상한까지
        var roomy = PackImportSession()
        #expect(roomy.start(.locked(Data(count: PackLimits.fileBytes + 1))) != nil)
    }

    @Test("안쪽이 UTF-8이 아니면(M5) 거부 화면 — 비밀번호 화면에 머물지 않는다")
    func unreadableInnerFails() throws {
        let spy = KDFSpy()
        var session = startedLocked(try lockedPack(Data([0xB0, 0xA1, 0x2C, 0xFF, 0xFE])))
        #expect(unlock(&session, rightPassword, spy: spy))
        #expect(session.phase == .failed(.locked(.unreadableContent)))
        #expect(!session.hasSource)
    }

    @Test("★ 푸는 중 취소 — 늦게 온 결과는 버린다(세대 비교, 12-5)")
    func cancelDropsLateUnlock() throws {
        let spy = KDFSpy()
        var session = startedLocked(try lockedPack(Data(numberedCSV.utf8)))
        let run = try required(session.unlock(password: rightPassword))
        #expect(session.isWorking)
        #expect(session.unlock(password: rightPassword) == nil)   // 동시에 하나만
        session.cancel()
        #expect(session.receiveUnlock(PackImportSession.open(run, deriveKey: spy.derive)) == nil)
        #expect(session.phase == .idle)
        #expect(!session.hasSource)
    }

    @Test("메타 기본값 — 안쪽에 #이름·#출처가 없으면 봉투 값, 있으면 안쪽 값(다르면 알린다)")
    func lockedMetaPrefill() throws {
        let spy = KDFSpy()
        var bare = startedLocked(try lockedPack(Data(numberedCSV.utf8), name: "봉투 이름", rights: "봉투 출처"))
        unlock(&bare, rightPassword, spy: spy)
        let bareDraft = try #require(bare.preview?.draft)
        #expect(bareDraft.meta.name == "봉투 이름")
        #expect(bareDraft.meta.license == "봉투 출처")
        #expect(!bareDraft.lockedMetaDiffers)

        let inner = "#이름,안쪽 이름\n#출처,봉투 출처\n" + numberedCSV
        var named = startedLocked(try lockedPack(Data(inner.utf8), name: "봉투 이름", rights: "봉투 출처"))
        unlock(&named, rightPassword, spy: spy)
        let namedDraft = try #require(named.preview?.draft)
        #expect(namedDraft.meta.name == "안쪽 이름")
        #expect(namedDraft.lockedMetaDiffers)

        var same = startedLocked(try lockedPack(Data(inner.utf8), name: "안쪽 이름", rights: ""))
        unlock(&same, rightPassword, spy: spy)
        #expect(same.preview?.draft.lockedMetaDiffers == false)
    }

    @Test("평문 파일·붙여넣기는 잠금 표시가 없다")
    func plainSourcesAreNotLocked() throws {
        var session = PackImportSession()
        if let run = session.start(.paste(numberedCSV)) { session.receive(PackImportSession.compute(run, library: nil)) }
        let draft = try #require(session.preview?.draft)
        #expect(!draft.readFromLockedPack && !draft.lockedMetaDiffers)
    }

    @Test("확장자로만 봉투 경로를 고른다(대소문자 무시, V30)")
    func extensionDecidesLockedPath() {
        #expect(PackImportFileTypes.isLockedPack(URL(fileURLWithPath: "/tmp/a.gspack")))
        #expect(PackImportFileTypes.isLockedPack(URL(fileURLWithPath: "/tmp/a.GSPack")))
        #expect(!PackImportFileTypes.isLockedPack(URL(fileURLWithPath: "/tmp/a.gspack.csv")))
        #expect(!PackImportFileTypes.isLockedPack(URL(fileURLWithPath: "/tmp/a.csv")))
    }
}

@Suite("받은 편지함 사본 정리 (12-10 ③)")
struct LockedPackInboxTests {

    private func scratch() throws -> (root: URL, inbox: URL, outside: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-test-\(UUID().uuidString)", isDirectory: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        let outside = root.appendingPathComponent("Picked", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        return (root, inbox, outside)
    }

    @Test("★ 받은 편지함 안의 .gspack만 지운다 — 밖(파일 앱에서 고른 원본)·다른 형식은 그대로")
    func discardOnlyInboxCopies() throws {
        let (root, inbox, outside) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let copy = inbox.appendingPathComponent("팩.gspack")
        let picked = outside.appendingPathComponent("팩.gspack")
        let csv = inbox.appendingPathComponent("표.csv")
        for url in [copy, picked, csv] { try Data("x".utf8).write(to: url) }

        #expect(LockedPackInbox.isInboxCopy(copy, inboxes: [inbox]))
        #expect(!LockedPackInbox.isInboxCopy(picked, inboxes: [inbox]))
        #expect(!LockedPackInbox.isInboxCopy(csv, inboxes: [inbox]))

        LockedPackInbox.discard(picked, inboxes: [inbox])
        LockedPackInbox.discard(csv, inboxes: [inbox])
        LockedPackInbox.discard(copy, inboxes: [inbox])
        #expect(FileManager.default.fileExists(atPath: picked.path))
        #expect(FileManager.default.fileExists(atPath: csv.path))
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test("쓸어 내기 — 받은 편지함의 .gspack 전부, 다른 파일은 남는다. 받은 편지함이 없어도 조용하다")
    func sweepRemovesLockedCopies() throws {
        let (root, inbox, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["a.gspack", "b.GSPACK", "c.csv"]
        for name in names { try Data("x".utf8).write(to: inbox.appendingPathComponent(name)) }
        LockedPackInbox.sweep(inboxes: [inbox, root.appendingPathComponent("없는 곳", isDirectory: true)])
        let left = try FileManager.default.contentsOfDirectory(atPath: inbox.path).sorted()
        #expect(left == ["c.csv"])
    }

    @Test("정리 대상 — 시스템 받은 편지함(Documents/Inbox·tmp/<번들 ID>-Inbox) + 대기 폴더")
    func inboxCandidates() {
        let system = LockedPackInbox.systemInboxDirectories(bundleIdentifier: "com.charging.tadak")
        #expect(system.map(\.lastPathComponent) == ["Inbox", "com.charging.tadak-Inbox"])
        let directories = LockedPackInbox.inboxDirectories(bundleIdentifier: "com.charging.tadak")
        #expect(directories.map(\.lastPathComponent) == ["Inbox", "com.charging.tadak-Inbox", "LockedPackHold"])
    }

    @Test("★ 받자마자 대기 폴더로 옮긴다 — 시스템이 tmp 사본을 약 1분 뒤 지워도 기다리던 파일이 남는다(iOS 17 실기 2026-11-08)")
    func holdMovesSystemInboxCopy() throws {
        let (root, inbox, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let hold = root.appendingPathComponent("Hold", isDirectory: true)
        let copy = inbox.appendingPathComponent("찬송가.gspack")
        let body = Data("envelope".utf8)
        try body.write(to: copy)

        let held = LockedPackInbox.hold(copy, systemInboxes: [inbox], holdDirectory: hold)
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(held.deletingLastPathComponent().resolvingSymlinksInPath().path == hold.resolvingSymlinksInPath().path)
        #expect(held.pathExtension == "gspack")
        // 원래 파일 이름을 남기지 않는다(같은 이름을 두 번 받아도 겹치지 않는다)
        #expect(held.lastPathComponent != copy.lastPathComponent)
        #expect(try Data(contentsOf: held) == body)
        // 다 쓰면 정리 대상이다
        #expect(LockedPackInbox.isInboxCopy(held, inboxes: [inbox, hold]))
        LockedPackInbox.discard(held, inboxes: [inbox, hold])
        #expect(!FileManager.default.fileExists(atPath: held.path))
    }

    @Test("같은 이름을 두 번 받아도 둘 다 대기 폴더에 남는다")
    func holdTwoCopiesOfSameName() throws {
        let (root, inbox, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let hold = root.appendingPathComponent("Hold", isDirectory: true)
        let copy = inbox.appendingPathComponent("팩.gspack")
        try Data("1".utf8).write(to: copy)
        let first = LockedPackInbox.hold(copy, systemInboxes: [inbox], holdDirectory: hold)
        try Data("2".utf8).write(to: copy)
        let second = LockedPackInbox.hold(copy, systemInboxes: [inbox], holdDirectory: hold)
        #expect(first != second)
        #expect(try Data(contentsOf: first) == Data("1".utf8))
        #expect(try Data(contentsOf: second) == Data("2".utf8))
    }

    @Test("받은 편지함 밖(파일 앱 원본)·다른 형식·없는 파일은 옮기지 않고 그대로 돌려준다")
    func holdLeavesOthersAlone() throws {
        let (root, inbox, outside) = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let hold = root.appendingPathComponent("Hold", isDirectory: true)
        let picked = outside.appendingPathComponent("팩.gspack")
        let csv = inbox.appendingPathComponent("표.csv")
        let missing = inbox.appendingPathComponent("없음.gspack")
        for url in [picked, csv] { try Data("x".utf8).write(to: url) }

        #expect(LockedPackInbox.hold(picked, systemInboxes: [inbox], holdDirectory: hold) == picked)
        #expect(LockedPackInbox.hold(csv, systemInboxes: [inbox], holdDirectory: hold) == csv)
        // 옮기기 실패 — 받은 URL 그대로(그때는 곧바로 읽는다)
        #expect(LockedPackInbox.hold(missing, systemInboxes: [inbox], holdDirectory: hold) == missing)
        #expect(FileManager.default.fileExists(atPath: picked.path))
        #expect(FileManager.default.fileExists(atPath: csv.path))
    }
}
