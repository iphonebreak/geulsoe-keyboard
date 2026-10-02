import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 키보드 전용 컨테이너 저장소 — **호스트(macOS)에서의 왕복**만 잰다.
///
/// 저장소 인스턴스를 새로 만들어 읽는 것이 「프로세스가 새로 떴을 때」의 흉내다(메모리 캐시가 없다는 확인).
/// 실제 키보드 프로세스가 죽고 다시 떴을 때 값이 남는지는 **실기 확인 항목**이다
/// (`docs/release/v1.2.0-emoji-recent-device-check.md`).
@Suite("이모지 기록 — 전용 컨테이너 저장소", .serialized)
struct EmojiHistoryRepositoryTests {

    /// 테스트마다 따로 쓰는 도메인 — 호스트의 `UserDefaults.standard`를 더럽히지 않는다
    private func withSuite(_ body: (String) throws -> Void) rethrows {
        let suite = "tadak.tests.emoji.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try body(suite)
    }

    @Test("저장한 기록을 **새 인스턴스**가 그대로 읽는다 — 재등장·재시작 흉내 (수용 기준 1·2·3)")
    func roundTripAcrossInstances() {
        withSuite { suite in
            var history = EmojiHistory(resetToken: 4)
            history.record("😀")
            history.record("👍")
            #expect(KeyboardOwnEmojiHistoryRepository(suiteName: suite).save(history))
            let reloaded = KeyboardOwnEmojiHistoryRepository(suiteName: suite).load()
            #expect(reloaded == history)
            #expect(reloaded.entries == ["👍", "😀"])
        }
    }

    @Test("비어 있으면 빈 기록 — 실패하지 않는다")
    func emptyLoad() {
        withSuite { suite in
            #expect(KeyboardOwnEmojiHistoryRepository(suiteName: suite).load() == EmojiHistory())
        }
    }

    @Test("clear는 저장분을 없앤다")
    func clearRemoves() {
        withSuite { suite in
            let repository = KeyboardOwnEmojiHistoryRepository(suiteName: suite)
            repository.save(EmojiHistory(entries: ["😀"], resetToken: 1))
            repository.clear()
            #expect(KeyboardOwnEmojiHistoryRepository(suiteName: suite).load() == EmojiHistory())
        }
    }

    @Test("App Group 스위트에 쓰지 않는다 — 키보드의 App Group 쓰기를 늘리지 않는다")
    func doesNotTouchAppGroup() {
        #expect(KeyboardOwnEmojiHistoryRepository().suiteName == nil, "기본은 익스텐션 자신의 도메인(standard)")
        #expect(KeyboardOwnEmojiHistoryRepository.key != "keyboard.clipboardHistory")
    }
}

@Suite("이모지 기록 — 후퇴안 저장소(메모리)")
struct InMemoryEmojiHistoryRepositoryTests {

    @Test("같은 인스턴스 안에서 왕복하고 clear로 비운다")
    func roundTrip() {
        let repository = InMemoryEmojiHistoryRepository()
        repository.save(EmojiHistory(entries: ["😀"], resetToken: 1))
        #expect(repository.load().entries == ["😀"])
        repository.clear()
        #expect(repository.load() == EmojiHistory())
    }
}
