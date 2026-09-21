import Foundation
import Testing
import TadakDomain
@testable import KeyboardCore

/// 스캔 횟수를 세는 대역 — **디바운스가 실제로 스캔을 미루는지**는 이 수로만 확인할 수 있다.
private final class CountingSearcher: BibleVerseSearching, @unchecked Sendable {

    private let answers: [String: [BibleVerseMatch]]
    private(set) var searchCount = 0
    private(set) var queries: [String] = []

    init(_ answers: [String: [BibleVerseMatch]] = [:]) {
        self.answers = answers
    }

    func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        searchCount += 1
        queries.append(query)
        return Array((answers[query] ?? []).prefix(limit))
    }

    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] {
        searchCount += 1
        queries.append(query)
        return []
    }
}

private let genesisOneOne = BibleVerseMatch(book: 1, chapter: 1, verse: 1)

@MainActor
@Suite("성경 검색 디바운스")
struct BibleSearchSchedulerTests {

    /// 테스트 안에서 **타이머가 저절로 터지지 않게** 한다 — 만료는 `fire`로 직접 몬다.
    /// 실제 시간에 기대면 느린 기계에서 깜빡인다.
    private func makeScheduler(
        _ searcher: CountingSearcher,
        validTail: String? = nil,
        onChanged: @escaping () -> Void = {}
    ) -> BibleSearchScheduler {
        BibleSearchScheduler(
            cascade: BibleSearchCascade(searcher: searcher),
            sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            isStillValid: { tail in validTail == nil || tail == validTail },
            onResultChanged: onChanged
        )
    }

    // MARK: - 연속 입력 중에는 스캔이 돌지 않는다

    @Test("★ 예약만으로는 한 번도 스캔하지 않는다")
    func schedulingNeverScans() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        for tail in ["사", "사랑", "사랑하", "사랑하는", "사랑하는자"] {
            scheduler.schedule(tail: tail)
        }

        #expect(searcher.searchCount == 0)
        #expect(scheduler.result == nil)
    }

    @Test("손이 멈춘 뒤 한 번만 돈다")
    func firesOnceAfterTypingStops() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        for tail in ["사", "사랑하", "사랑"] { scheduler.schedule(tail: tail) }
        #expect(searcher.searchCount == 0)

        scheduler.fire(tail: "사랑")
        #expect(scheduler.result?.matchedQuery == "사랑")
        // 마지막 꼬리 하나만 훑었다 — 앞의 두 꼬리는 스캔되지 않았다
        #expect(!searcher.queries.contains("사랑하"))
        #expect(!searcher.queries.contains("사"))
    }

    // MARK: - 꼬리가 바뀌면 옛 결과를 즉시 버린다

    @Test("★ 꼬리가 바뀌는 순간 옛 결과가 사라진다")
    func staleResultIsDroppedImmediately() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        #expect(scheduler.result != nil)

        // 사용자가 한 자 더 쳤다 — 「사랑」의 결과는 지금 문서와 맞지 않는다.
        // 남겨 두면 배지를 눌렀을 때 ✕가 2자만 지워 「해」가 남는다.
        scheduler.schedule(tail: "사랑해")
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
    }

    @Test("★ 만료 시점에 꼬리가 달라졌으면 결과를 쓰지 않는다")
    func expiredSearchWithStaleTailIsDiscarded() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        // 지금 진짜 꼬리는 「사랑해」다
        let scheduler = makeScheduler(searcher, validTail: "사랑해")

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")   // 늦게 도착한 옛 예약

        #expect(scheduler.result == nil)
        #expect(searcher.searchCount == 0)   // 스캔조차 하지 않는다
    }

    @Test("게이트가 닫혔으면 만료돼도 돌지 않는다")
    func closedGateSkipsScan() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = BibleSearchScheduler(
            cascade: BibleSearchCascade(searcher: searcher),
            sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            isStillValid: { _ in false },     // secure 전환·✕·칩 등장
            onResultChanged: {}
        )

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")

        #expect(scheduler.result == nil)
        #expect(searcher.searchCount == 0)
    }

    // MARK: - 재진입

    @Test("같은 꼬리로는 다시 예약하지 않는다 — 툴바 갱신이 되돌아와도 안 돈다")
    func sameTailDoesNotReschedule() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        var updates = 0
        let scheduler = makeScheduler(searcher, onChanged: { updates += 1 })

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        let afterFirst = searcher.searchCount

        // 결과 갱신 알림을 받은 조립 지점이 툴바를 다시 그리며 같은 꼬리로 또 예약한다
        scheduler.schedule(tail: "사랑")
        scheduler.schedule(tail: "사랑")

        #expect(searcher.searchCount == afterFirst)   // 더 안 돈다
        #expect(scheduler.result != nil)              // 결과는 그대로 살아 있다
        #expect(updates == 1)
    }

    @Test("결과가 생기면 조립 지점에 한 번 알린다")
    func notifiesOnce() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        var updates = 0
        let scheduler = makeScheduler(searcher, onChanged: { updates += 1 })

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        #expect(updates == 1)
    }

    // MARK: - 취소

    @Test("취소하면 결과도 예약도 사라진다")
    func cancelClearsEverything() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        #expect(scheduler.result != nil)

        scheduler.cancel()
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
    }

    @Test("취소한 뒤에는 같은 꼬리로 다시 예약된다")
    func rescheduleAfterCancel() {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        scheduler.cancel()

        scheduler.schedule(tail: "사랑")
        scheduler.fire(tail: "사랑")
        #expect(scheduler.result?.matchedQuery == "사랑")
    }

    // MARK: - 관례

    @Test("디바운스는 이 저장소의 기존 관례와 같은 120ms다")
    func delayMatchesRepositoryConvention() {
        // `KeyboardViewController.scheduleLiveSettingsReload()`와 같은 값
        #expect(BibleSearchScheduler.defaultDelay == .milliseconds(120))
    }
}
