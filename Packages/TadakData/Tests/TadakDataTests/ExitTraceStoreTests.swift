import Foundation
import Testing
import TadakDomain
@testable import TadakData

// 백로그 14 (가) — 키보드 자기 컨테이너(표시·대기·카운터)와 App Group 발신함(키보드 쪽).
// PDR `docs/design-reviews/keyboard-crashlytics.md` 2-6·2-8·6-9·8-2-3. 호스트(macOS) 왕복만 잰다 —
// 키보드 프로세스가 죽은 뒤 값이 남는지는 실기 X1·X2.

private func withSuite(_ body: (String) throws -> Void) rethrows {
    let suite = "tadak.tests.exitTrace.\(UUID().uuidString)"
    defer { UserDefaults().removePersistentDomain(forName: suite) }
    try body(suite)
}

private let hour = 500_000

/// `body` 동안 이 suite에 일어난 쓰기(설정·지우기) 수 — 같은 바이트로 다시 쓰는 것도 센다.
/// 저장소는 suite 이름으로 자기 `UserDefaults`를 만들므로 하위 클래스를 끼울 수 없다 → 바뀜 알림을 세고,
/// 알림을 보낸 인스턴스가 이 suite에만 둔 표지 키를 보는지로 다른 시험(병렬)의 쓰기를 거른다.
private func countingWrites(to suite: String, _ body: () -> Void) -> Int {
    let marker = "tadak.tests.writeCounter.\(UUID().uuidString)"
    UserDefaults(suiteName: suite)?.set(true, forKey: marker)
    let counter = WriteCounter()
    let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                       queue: nil) { note in
        guard (note.object as? UserDefaults)?.object(forKey: marker) != nil else { return }
        counter.increment()
    }
    body()
    NotificationCenter.default.removeObserver(token)
    UserDefaults(suiteName: suite)?.removeObject(forKey: marker)
    return counter.value
}

private final class WriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private func record(_ createdAtHour: Int = hour, cls: ExitTraceClass = .abnormal) -> ExitTraceRecord {
    ExitTraceRecord(cls: cls, mode: .dubeolsik, panel: .none, transitions: [.appear], idiom: .phone,
                    widthBucket: 380, screenWidthBucket: 380, memoryBucket: 30, memoryMinBucket: 25, pressure: .none,
                    residueHours: 1, fullAccessAtCreation: false, buildNumber: 7, osCode: 260_100, createdAtHour: createdAtHour)
}

@Suite("종료 흔적 — 키보드 자기 컨테이너", .serialized)
struct ExitTraceStoreTests {

    @Test("표시는 저장소를 새로 만들어도 남는다 — 재시작 흉내")
    func markerSurvivesStoreReinstantiation() {
        withSuite { suite in
            var marker = ExitTraceMarker(pid: 41, ownerToken: 3, setAtHour: hour, buildNumber: 7,
                                         os: ExitTraceOSVersion(major: 26, minor: 1, patch: 0), idiom: .pad)
            marker.mode = .english
            marker.transitions = [.appear, .toEnglish]
            KeyboardOwnExitTraceStore(suiteName: suite).saveMarker(marker)
            #expect(KeyboardOwnExitTraceStore(suiteName: suite).loadMarker() == marker)
            KeyboardOwnExitTraceStore(suiteName: suite).saveMarker(nil)
            #expect(KeyboardOwnExitTraceStore(suiteName: suite).loadMarker() == nil)
        }
    }

    @Test("대기 목록은 20건 — 넘치면 오래된 것부터 버리고 버린 수를 돌려준다")
    func pendingListCapsAtTwentyDroppingOldestAndCountsDropped() {
        withSuite { suite in
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            var dropped = ExitTraceDropCount()
            for offset in 0..<23 { dropped = dropped + store.appendPending(record(hour + offset), nowHour: hour + 30) }
            let pending = store.loadPending()
            #expect(pending.count == 20)
            #expect(dropped == ExitTraceDropCount(overflow: 3, expired: 0))
            #expect(pending.first?.createdAtHour == hour + 3)
            #expect(pending.last?.createdAtHour == hour + 22)
        }
    }

    @Test("대기 기록은 생성 후 30일이 지나면 버린다(생성 시각 기준)")
    func pendingRecordsOlderThanThirtyDaysByCreationArePurged() {
        withSuite { suite in
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            _ = store.appendPending(record(hour), nowHour: hour)
            let later = hour + 30 * 24 + 1
            let dropped = store.appendPending(record(later), nowHour: later)
            #expect(dropped == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(store.loadPending().map(\.createdAtHour) == [later])
        }
    }

    @Test("새 기록 없이 정리만 해도 30일 지난 대기 기록을 버린다(검증 F1)")
    func prunePendingDropsExpiredWithoutAppending() {
        withSuite { suite in
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            _ = store.appendPending(record(hour), nowHour: hour)
            _ = store.appendPending(record(hour + 10 * 24), nowHour: hour + 10 * 24)
            let later = hour + 31 * 24
            #expect(store.prunePending(nowHour: later) == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(store.loadPending().map(\.createdAtHour) == [hour + 10 * 24])
            #expect(store.prunePending(nowHour: later) == ExitTraceDropCount())
        }
    }

    @Test("대기 기록 만료 경계 — 생성 후 정확히 720시간은 남고 721시간이면 버린다(구현 검증 F3)")
    func pendingRecordAtExactlyThirtyDaysIsKeptAndPurgedTheHourAfter() {
        withSuite { suite in
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            _ = store.appendPending(record(hour), nowHour: hour)
            #expect(store.prunePending(nowHour: hour + 720) == ExitTraceDropCount())
            #expect(store.loadPending().map(\.createdAtHour) == [hour])
            #expect(store.prunePending(nowHour: hour + 721) == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(store.loadPending().isEmpty)
        }
    }

    @Test("카운터는 만료 칸이 없던 저장분도 읽는다")
    func countersDecodeWithoutExpiredKey() {
        withSuite { suite in
            let json = Data(#"{"appearances":2,"abnormal":1,"orphan":0,"update":0,"stale":0,"dropped":1}"#.utf8)
            UserDefaults(suiteName: suite)?.set(json, forKey: KeyboardOwnExitTraceStore.countersKey)
            #expect(KeyboardOwnExitTraceStore(suiteName: suite).loadCounters()
                    == ExitTraceCounters(appearances: 2, abnormal: 1, dropped: 1))
        }
    }

    @Test("카운터·통계일·끈 표지가 왕복하고 clearAll이 기록을 지운다")
    func countersRoundTripAndClearAllRemovesEverything() {
        withSuite { suite in
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            store.saveCounters(ExitTraceCounters(appearances: 4, abnormal: 1))
            store.saveLastStatsDay(20_000)
            store.saveMarker(.init(pid: 1, ownerToken: 1, setAtHour: hour, buildNumber: 1,
                                   os: ExitTraceOSVersion(major: 26, minor: 0, patch: 0), idiom: .phone))
            _ = store.appendPending(record(), nowHour: hour)
            let reread = KeyboardOwnExitTraceStore(suiteName: suite)
            #expect(reread.loadCounters() == ExitTraceCounters(appearances: 4, abnormal: 1))
            #expect(reread.loadLastStatsDay() == 20_000)
            reread.clearAll()
            #expect(reread.loadMarker() == nil && reread.loadPending().isEmpty)
            #expect(reread.loadCounters() == ExitTraceCounters() && reread.loadLastStatsDay() == nil)
            reread.saveOptedOut(true)
            #expect(KeyboardOwnExitTraceStore(suiteName: suite).loadOptedOut())
        }
    }

    @Test("이모지 기록과 종료 흔적은 서로 다른 키를 쓴다")
    func emojiHistoryAndExitTraceUseDistinctKeys() {
        let exitKeys = KeyboardOwnExitTraceStore.keys
        #expect(!exitKeys.contains(KeyboardOwnEmojiHistoryRepository.key))
        #expect(exitKeys.allSatisfy { $0.hasPrefix("keyboard.exitTrace.") })
        #expect(Set(exitKeys).count == exitKeys.count)
        withSuite { suite in
            var history = EmojiHistory()
            history.record("😀")
            KeyboardOwnEmojiHistoryRepository(suiteName: suite).save(history)
            let store = KeyboardOwnExitTraceStore(suiteName: suite)
            _ = store.appendPending(record(), nowHour: hour)
            store.clearAll()
            #expect(KeyboardOwnEmojiHistoryRepository(suiteName: suite).load() == history)
        }
    }
}

@Suite("종료 흔적 — App Group 발신함(키보드 쪽)", .serialized)
struct ExitTraceOutboxTests {

    private func ackSet(_ suite: String, _ value: Int) {
        UserDefaults(suiteName: suite)?.set(value, forKey: ExitTraceOutboxRepository.ackKey)
    }

    @Test("추가할 때마다 일련번호가 커진다")
    func outboxAppendAssignsIncreasingSequence() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .stats(ExitTraceCounters(appearances: 2))], nowHour: hour)
            outbox.append([.record(record(cls: .orphan))], nowHour: hour)
            let entries = ExitTraceOutboxRepository(suiteName: suite).entries()
            #expect(entries.map(\.seq) == [1, 2, 3])
            #expect(entries[1].stats == ExitTraceCounters(appearances: 2) && entries[1].record == nil)
            #expect(entries[2].record?.cls == .orphan)
        }
    }

    @Test("ack는 발신함과 다른 키 — 키보드는 ack를 쓰지 않는다")
    func ackIsSeparateKeyFromOutbox() {
        #expect(!ExitTraceOutboxRepository.ackKey.hasPrefix(ExitTraceOutboxRepository.entryKeyPrefix))
        #expect(!ExitTraceOutboxRepository.lastSeqKey.hasPrefix(ExitTraceOutboxRepository.entryKeyPrefix))
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record())], nowHour: hour)
            #expect(UserDefaults(suiteName: suite)?.object(forKey: ExitTraceOutboxRepository.ackKey) == nil)
            #expect(outbox.ack() == 0)
            ackSet(suite, 1)
            #expect(outbox.ack() == 1)
        }
    }

    @Test("키보드는 ack 이하를 지운다")
    func keyboardPrunesOutboxUpToAck() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .record(record()), .record(record())], nowHour: hour)
            ackSet(suite, 2)
            outbox.append([], nowHour: hour)
            #expect(outbox.entries().map(\.seq) == [3])
        }
    }

    @Test("발신함 밖을 가리키는 ack — 뒤에 넣은 항목은 ack보다 큰 번호를 받는다")
    func ackBeyondOutboxIsIgnored() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record())], nowHour: hour)
            ackSet(suite, 999)
            outbox.append([.record(record())], nowHour: hour)
            let entries = outbox.entries()
            #expect(entries.count == 1)
            #expect(entries.allSatisfy { $0.seq > 999 })
        }
    }

    @Test("발신함은 50건 — 넘치면 오래된 것부터 버리고 버린 수를 돌려준다")
    func outboxCapsAtFiftyDroppingOldest() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            var dropped = ExitTraceDropCount()
            for _ in 0..<53 { dropped = dropped + outbox.append([.record(record())], nowHour: hour) }
            let entries = outbox.entries()
            #expect(entries.count == 50)
            #expect(dropped == ExitTraceDropCount(overflow: 3, expired: 0))
            #expect(entries.first?.seq == 4 && entries.last?.seq == 53)
        }
    }

    @Test("발신함은 생성 시각 기준 30일 — 최근에 옮겼어도 원래 생성이 오래면 버린다")
    func outboxEntriesOlderThanThirtyDaysByCreationArePurgedEvenIfMovedRecently() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            let now = hour + 31 * 24
            let dropped = outbox.append([.record(record(hour)), .record(record(now - 1))], nowHour: now)
            #expect(dropped == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(outbox.entries().map(\.createdAtHour) == [now - 1])
            #expect(outbox.entries().first?.record?.createdAtHour == now - 1)
        }
    }

    @Test("발신함 만료 경계 — 생성 후 정확히 720시간은 남고 721시간이면 지운다(구현 검증 F3)")
    func outboxEntryAtExactlyThirtyDaysIsKeptAndRemovedTheHourAfter() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            // 옮겨 넣는 순간에도 같은 경계 — 720시간 된 기록은 들어가고 721시간 된 기록은 만료로 센다
            let arrival = outbox.append([.record(record(hour - 720)), .record(record(hour - 721))], nowHour: hour)
            #expect(arrival == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(outbox.entries().map(\.createdAtHour) == [hour - 720])
            #expect(outbox.removeHandled(nowHour: hour) == ExitTraceDropCount())
            #expect(outbox.entries().map(\.seq) == [1])
            #expect(outbox.removeHandled(nowHour: hour + 1) == ExitTraceDropCount(overflow: 0, expired: 1))
            #expect(outbox.entries().isEmpty)
        }
    }

    @Test("읽을 수 없는 칸·키와 번호가 다른 칸은 그 칸만 버린다")
    func undecodableOutboxEntryIsDroppedNotPassedThrough() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .record(record()), .record(record())], nowHour: hour)
            let defaults = UserDefaults(suiteName: suite)
            defaults?.set(Data(#"{"seq":1,"createdAtHour":1,"record":{"cls":"crash"}}"#.utf8),
                          forKey: ExitTraceOutboxRepository.entryKey(1))
            let wrongSeq = try? JSONEncoder().encode(ExitTraceOutboxEntry(seq: 9, createdAtHour: hour, record: record(), stats: nil))
            defaults?.set(wrongSeq, forKey: ExitTraceOutboxRepository.entryKey(2))
            #expect(outbox.entries().map(\.seq) == [3])
            outbox.append([.record(record())], nowHour: hour)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(1)) == nil)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(2)) == nil)
            #expect(outbox.entries().map(\.seq) == [3, 4])
        }
    }

    // MARK: 30일 잔존 구멍(검증 때 발견) — 전체 접근을 끄면 키보드가 발신함을 못 지운다 → 앱이 지운다.
    // 단일 작성자: 칸은 고유 키(번호 재사용 없음)라 **만들기는 키보드만**, 지우기는 같은 규칙으로 양쪽(멱등) — 덮어쓰기가 없다.

    @Test("칸마다 따로 된 키 — 공유 배열이 없다")
    func outboxStoresEachEntryUnderItsOwnKey() {
        withSuite { suite in
            ExitTraceOutboxRepository(suiteName: suite).append([.record(record()), .stats(ExitTraceCounters(appearances: 1))],
                                                              nowHour: hour)
            let defaults = UserDefaults(suiteName: suite)
            #expect(defaults?.data(forKey: ExitTraceOutboxRepository.entryKey(1)) != nil)
            #expect(defaults?.data(forKey: ExitTraceOutboxRepository.entryKey(2)) != nil)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.legacyOutboxKey) == nil)
            #expect(defaults?.integer(forKey: ExitTraceOutboxRepository.lastSeqKey) == 2)
        }
    }

    @Test("키보드가 못 지우는 동안에도 앱이 생성 후 30일 지난 칸을 지운다")
    func appRemovesExpiredEntriesWhileKeyboardCannotWrite() {
        withSuite { suite in
            let keyboard = ExitTraceOutboxRepository(suiteName: suite)
            keyboard.append([.record(record(hour)), .stats(ExitTraceCounters(appearances: 3))], nowHour: hour)
            keyboard.append([.record(record(hour + 20 * 24))], nowHour: hour + 20 * 24)
            // 이후 전체 접근 꺼짐 — 키보드는 더 쓰지 못한다. 앱만 열린다
            let app = ExitTraceOutboxRepository(suiteName: suite)
            let removed = app.removeHandled(nowHour: hour + 31 * 24)
            #expect(removed == ExitTraceDropCount(overflow: 0, expired: 2))
            #expect(app.entries().map(\.seq) == [3])
            let defaults = UserDefaults(suiteName: suite)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(1)) == nil)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(2)) == nil)
        }
    }

    @Test("앱은 ack한 칸(보냈거나 버린 칸)을 바로 지운다")
    func appRemovesAckedEntriesImmediately() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .record(record()), .record(record())], nowHour: hour)
            ackSet(suite, 2)
            #expect(outbox.removeHandled(nowHour: hour) == ExitTraceDropCount())
            #expect(outbox.entries().map(\.seq) == [3])
        }
    }

    @Test("앱의 지우기는 남은 칸·번호·ack를 다시 쓰지 않는다")
    func appRemovalNeverRewritesRemainingEntriesOrSequence() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .record(record(cls: .orphan))], nowHour: hour)
            ackSet(suite, 1)
            let defaults = UserDefaults(suiteName: suite)
            let before = defaults?.data(forKey: ExitTraceOutboxRepository.entryKey(2))
            // 같은 바이트로 다시 써도 값 비교로는 못 잡는다 — 이 저장소에 일어난 쓰기 수를 센다(지운 칸 1 = 쓰기 1, 구현 검증 F4)
            let writes = countingWrites(to: suite) { outbox.removeHandled(nowHour: hour + 24) }
            #expect(writes == 1)
            #expect(defaults?.data(forKey: ExitTraceOutboxRepository.entryKey(2)) == before)
            #expect(defaults?.integer(forKey: ExitTraceOutboxRepository.lastSeqKey) == 2)
            #expect(outbox.ack() == 1)
        }
    }

    @Test("지울 것이 없으면 앱의 지우기는 발신함에 한 번도 쓰지 않는다")
    func appRemovalWithNothingDueWritesNothing() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .stats(ExitTraceCounters(appearances: 1))], nowHour: hour)
            let writes = countingWrites(to: suite) { outbox.removeHandled(nowHour: hour + 24) }
            #expect(writes == 0)
            #expect(outbox.entries().map(\.seq) == [1, 2])
        }
    }

    @Test("마지막 칸을 만료·ack로 지워도 앱은 lastSeq를 고치지 않는다 — 번호 재사용 방지(구현 검증 F4)")
    func appRemovalOfLastEntryLeavesLastSequenceUntouched() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            // 마지막 번호(3)가 가장 오래된 기록 — 앱이 열릴 때 3만 만료된다
            outbox.append([.record(record(hour)), .record(record(hour)), .record(record(hour - 700))], nowHour: hour)
            let defaults = UserDefaults(suiteName: suite)
            let expiredWrites = countingWrites(to: suite) {
                #expect(outbox.removeHandled(nowHour: hour + 30) == ExitTraceDropCount(overflow: 0, expired: 1))
            }
            #expect(expiredWrites == 1)
            #expect(outbox.entries().map(\.seq) == [1, 2])
            #expect(defaults?.integer(forKey: ExitTraceOutboxRepository.lastSeqKey) == 3)
            // 남은 칸을 전부 ack해 지워도 같다
            ackSet(suite, 2)
            let ackedWrites = countingWrites(to: suite) { outbox.removeHandled(nowHour: hour + 30) }
            #expect(ackedWrites == 2)
            #expect(outbox.entries().isEmpty)
            #expect(defaults?.integer(forKey: ExitTraceOutboxRepository.lastSeqKey) == 3)
            outbox.append([.record(record(hour + 30))], nowHour: hour + 30)
            #expect(outbox.entries().map(\.seq) == [4])
        }
    }

    @Test("앱이 다 지운 뒤에도 키보드의 새 칸은 번호를 이어 받는다 — 지운 번호를 다시 쓰지 않는다")
    func keyboardAppendAfterAppRemovalKeepsIncreasingSequence() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            outbox.append([.record(record()), .record(record())], nowHour: hour)
            ackSet(suite, 2)
            outbox.removeHandled(nowHour: hour)
            #expect(outbox.entries().isEmpty)
            outbox.append([.record(record())], nowHour: hour)
            #expect(outbox.entries().map(\.seq) == [3])
        }
    }

    @Test("상한을 넘어 버린 칸의 키는 남지 않는다")
    func overflowedEntryKeysAreRemoved() {
        withSuite { suite in
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            for _ in 0..<52 { outbox.append([.record(record())], nowHour: hour) }
            let defaults = UserDefaults(suiteName: suite)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(1)) == nil)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.entryKey(2)) == nil)
            #expect(defaults?.data(forKey: ExitTraceOutboxRepository.entryKey(3)) != nil)
        }
    }

    @Test("옛 배열 발신함(배포 전 개발 빌드)은 읽지 않고 지운다")
    func legacyArrayOutboxIsRemovedNotRead() {
        withSuite { suite in
            let defaults = UserDefaults(suiteName: suite)
            let blob = try? JSONEncoder().encode(ExitTraceOutboxEntry(seq: 1, createdAtHour: hour, record: record(), stats: nil))
            defaults?.set([blob].compactMap { $0 }, forKey: ExitTraceOutboxRepository.legacyOutboxKey)
            let outbox = ExitTraceOutboxRepository(suiteName: suite)
            #expect(outbox.entries().isEmpty)
            outbox.removeHandled(nowHour: hour)
            #expect(defaults?.object(forKey: ExitTraceOutboxRepository.legacyOutboxKey) == nil)
        }
    }
}
