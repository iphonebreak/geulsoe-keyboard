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

/// ★ **실제로 멈춰 서는** 검색기 — 「겹쳐 돌지 않는다」를 증명하려면 이것이 필요하다.
///
/// `CountingSearcher`는 곧바로 돌려주므로 **스캔이 시작된 순간을 잡을 수 없다.**
/// 그래서 예전 테스트는 `schedule`을 두 번 부르고 `result == nil`만 봤고,
/// 그것은 디바운스가 아직 안 터졌다는 뜻일 뿐 동시 실행과는 아무 관계가 없었다(반론자2).
///
/// 이 대역은 스캔 안에서 세마포어로 **멈춰 선다.** 그래서
/// (가) 스캔이 실제로 시작됐음을 `started`로 확인할 수 있고
/// (나) 그 상태에서 두 번째를 예약해 **동시 실행 수**를 직접 잴 수 있다.
private final class BlockingSearcher: BibleVerseSearching, @unchecked Sendable {

    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var _started = 0
    private var _running = 0
    private var _peak = 0

    /// 지금까지 **시작된** 스캔 수.
    var started: Int { lock.lock(); defer { lock.unlock() }; return _started }
    /// 한 순간에 **동시에 돌던** 스캔 수의 최댓값. 계약이 지켜지면 1이다.
    var peakConcurrent: Int { lock.lock(); defer { lock.unlock() }; return _peak }

    /// 멈춰 선 스캔 하나를 놓아 준다.
    func release() { gate.signal() }

    func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        lock.lock()
        _started += 1
        _running += 1
        _peak = max(_peak, _running)
        lock.unlock()

        gate.wait()   // ★ 여기서 멈춰 선다 — 테스트가 놓아 줄 때까지

        lock.lock()
        _running -= 1
        lock.unlock()
        return [genesisOneOne]
    }

    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] { [] }
}

/// ★ 스캐너와 **같은 방식으로** 취소를 보는 검색기 — 취소가 스캔 **안까지** 닿는지 잰다.
///
/// `BibleByteScanner`는 절 256개마다 `Task.isCancelled`를 본다. 이 대역은 그 자리를
/// 무한 루프로 흉내 낸다 — 취소가 닿지 않으면 **영영 안 끝난다.**
/// 고치기 전 코드(래퍼만 취소)에서는 이 테스트가 시간 초과로 실패한다.
private final class CooperativeSearcher: BibleVerseSearching, @unchecked Sendable {

    private let lock = NSLock()
    private var _started = 0
    private var _sawCancellation = false

    var started: Int { lock.lock(); defer { lock.unlock() }; return _started }
    var sawCancellation: Bool { lock.lock(); defer { lock.unlock() }; return _sawCancellation }

    func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        lock.lock(); _started += 1; lock.unlock()
        while !Task.isCancelled { usleep(500) }
        lock.lock(); _sawCancellation = true; lock.unlock()
        return []
    }

    func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] { [] }
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
    func schedulingNeverScans() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        for tail in ["사", "사랑", "사랑하", "사랑하는", "사랑하는자"] {
            scheduler.schedule(tail: tail)
        }

        #expect(searcher.searchCount == 0)
        #expect(scheduler.result == nil)
    }

    @Test("손이 멈춘 뒤 한 번만 돈다")
    func firesOnceAfterTypingStops() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        for tail in ["사", "사랑하", "사랑"] { scheduler.schedule(tail: tail) }
        #expect(searcher.searchCount == 0)

        await scheduler.fire(tail: "사랑")
        #expect(scheduler.result?.matchedQuery == "사랑")
        // 마지막 꼬리 하나만 훑었다 — 앞의 두 꼬리는 스캔되지 않았다
        #expect(!searcher.queries.contains("사랑하"))
        #expect(!searcher.queries.contains("사"))
    }

    // MARK: - 꼬리가 바뀌면 옛 결과를 즉시 버린다

    @Test("★ 꼬리가 바뀌는 순간 옛 결과가 사라진다")
    func staleResultIsDroppedImmediately() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        #expect(scheduler.result != nil)

        // 사용자가 한 자 더 쳤다 — 「사랑」의 결과는 지금 문서와 맞지 않는다.
        // 남겨 두면 배지를 눌렀을 때 ✕가 2자만 지워 「해」가 남는다.
        scheduler.schedule(tail: "사랑해")
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
    }

    @Test("★ 만료 시점에 꼬리가 달라졌으면 결과를 쓰지 않는다")
    func expiredSearchWithStaleTailIsDiscarded() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        // 지금 진짜 꼬리는 「사랑해」다
        let scheduler = makeScheduler(searcher, validTail: "사랑해")

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")   // 늦게 도착한 옛 예약

        #expect(scheduler.result == nil)
        #expect(searcher.searchCount == 0)   // 스캔조차 하지 않는다
    }

    @Test("게이트가 닫혔으면 만료돼도 돌지 않는다")
    func closedGateSkipsScan() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = BibleSearchScheduler(
            cascade: BibleSearchCascade(searcher: searcher),
            sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            isStillValid: { _ in false },     // secure 전환·✕·칩 등장
            onResultChanged: {}
        )

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")

        #expect(scheduler.result == nil)
        #expect(searcher.searchCount == 0)
    }

    // MARK: - ★ 비동기가 만든 위험 (2026-09-21)

    /// ★ 스캔이 주 스레드 밖으로 나가면서 **도는 사이에 꼬리가 바뀔 수 있다.**
    /// 진입 시점에는 유효했는데 **돌아왔을 때는 아닌** 경우 — 반영하면 옛 결과가 새 꼬리 위에 얹힌다.
    @Test("★ 스캔이 도는 사이 꼬리가 바뀌면 결과를 버린다")
    func staleAfterScanIsDiscarded() async {
        final class Gate: @unchecked Sendable { var valid = true }
        let gate = Gate()
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        var updates = 0
        let scheduler = BibleSearchScheduler(
            cascade: BibleSearchCascade(searcher: searcher),
            sleep: { _ in try? await Task.sleep(for: .seconds(3_600)) },
            isStillValid: { _ in
                // 첫 물음(진입)은 통과, 두 번째 물음(반영 직전)은 거절 — 그새 사용자가 더 쳤다
                defer { gate.valid = false }
                return gate.valid
            },
            onResultChanged: { updates += 1 }
        )

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")

        #expect(searcher.searchCount > 0)   // 스캔은 돌았다
        #expect(scheduler.result == nil)    // ★ 그런데 반영하지 않았다
        #expect(updates == 0)
    }

    @Test("새 예약이 오면 옛 결과를 즉시 버린다 — **디바운스 만료 전** 상태만 본다")
    func newScheduleDropsPendingResult() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        scheduler.schedule(tail: "사랑해")
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
        // ★ 이 테스트는 **동시 실행을 증명하지 않는다.** 예전 이름
        //   「겹쳐 돌지 않는다」는 거짓이었다 — 여기서는 디바운스가 아직 안 터져
        //   스캔이 시작조차 하지 않는다. 진짜 증명은 아래 `scansNeverOverlap`이다.
    }

    // MARK: - ★ 동시성 계약 — 느린 차단형 검색기로 **실제로** 증명한다 (2026-09-21)

    /// 조건이 참이 될 때까지 **주 스레드를 막지 않고** 기다린다.
    /// 끝내 참이 안 되면 그냥 돌아온다 — 판정은 호출자의 `#expect`가 한다(행 걸림 없음).
    private func waitUntil(
        _ timeout: Duration = .seconds(5),
        _ condition: () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// 디바운스를 **실제로 흘려보내는** 스케줄러 — 주입 지점(`sleep`)을 즉시 반환으로 둔다.
    private func makeFlowingScheduler(
        _ searcher: any BibleVerseSearching,
        onChanged: @escaping () -> Void = {}
    ) -> BibleSearchScheduler {
        BibleSearchScheduler(
            cascade: BibleSearchCascade(searcher: searcher),
            delay: .zero,
            sleep: { _ in },                 // 디바운스가 즉시 만료된다 → fire까지 실제로 간다
            isStillValid: { _ in true },
            onResultChanged: onChanged
        )
    }

    @Test("★ 스캔은 겹쳐 돌지 않는다 — 동시 실행 수를 실제로 센다")
    func scansNeverOverlap() async {
        let searcher = BlockingSearcher()
        var applied = 0
        let scheduler = makeFlowingScheduler(searcher, onChanged: { applied += 1 })

        scheduler.schedule(tail: "사랑")

        // ★ 첫 스캔이 **실제로 시작될 때까지** 기다린다.
        //   이것이 예전 테스트에 없던 것이다 — 시작도 안 한 스캔은 겹칠 수가 없다.
        await waitUntil { searcher.started == 1 }
        #expect(searcher.started == 1)

        // 첫 스캔이 멈춰 선 채로 두 번째를 예약한다
        scheduler.schedule(tail: "소망")
        // 두 번째 디바운스가 만료돼 `fire`까지 도달할 시간을 충분히 준다
        try? await Task.sleep(for: .milliseconds(60))

        // ★ 그래도 두 번째 스캔은 시작하지 않았다 — 앞 스캔이 끝나기를 기다린다
        #expect(searcher.started == 1)

        searcher.release()                       // 취소된 첫 스캔을 놓아 준다
        await waitUntil { searcher.started == 2 }
        searcher.release()                       // 두 번째도 놓아 준다
        await waitUntil { scheduler.searchedTail != nil }

        #expect(searcher.peakConcurrent == 1)    // ★ 동시 실행 수 1
        #expect(applied == 1)                    // ★ 취소된 결과가 반영된 횟수 0
        #expect(scheduler.searchedTail == "소망")
        #expect(scheduler.result?.matchedQuery == "소망")
    }

    @Test("★ 취소가 스캔 **안까지** 닿는다 — 돌던 스캔이 스스로 멈춘다")
    func cancellationReachesRunningScan() async {
        let searcher = CooperativeSearcher()
        let scheduler = makeFlowingScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        await waitUntil { searcher.started == 1 }
        #expect(searcher.started == 1)           // 스캔이 실제로 돌고 있다

        scheduler.cancel()                       // ★ 여기서 취소가 나간다

        await waitUntil { searcher.sawCancellation }
        // 고치기 전 코드(래퍼만 취소)에서는 이 줄이 실패한다 — 루프가 영영 안 끝난다
        #expect(searcher.sawCancellation)
        #expect(scheduler.result == nil)
    }

    @Test("★ 취소된 스캔의 결과는 반영되지 않는다")
    func cancelledScanResultIsNeverApplied() async {
        let searcher = BlockingSearcher()
        var applied = 0
        let scheduler = makeFlowingScheduler(searcher, onChanged: { applied += 1 })

        scheduler.schedule(tail: "사랑")
        await waitUntil { searcher.started == 1 }

        scheduler.cancel()          // 게이트가 닫혔다(secure 전환·칩 등장·✕)
        searcher.release()          // 돌던 스캔이 **결과를 들고** 끝난다
        try? await Task.sleep(for: .milliseconds(60))

        #expect(applied == 0)
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
    }

    // MARK: - 재진입

    @Test("같은 꼬리로는 다시 예약하지 않는다 — 툴바 갱신이 되돌아와도 안 돈다")
    func sameTailDoesNotReschedule() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        var updates = 0
        let scheduler = makeScheduler(searcher, onChanged: { updates += 1 })

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        let afterFirst = searcher.searchCount

        // 결과 갱신 알림을 받은 조립 지점이 툴바를 다시 그리며 같은 꼬리로 또 예약한다
        scheduler.schedule(tail: "사랑")
        scheduler.schedule(tail: "사랑")

        #expect(searcher.searchCount == afterFirst)   // 더 안 돈다
        #expect(scheduler.result != nil)              // 결과는 그대로 살아 있다
        #expect(updates == 1)
    }

    @Test("결과가 생기면 조립 지점에 한 번 알린다")
    func notifiesOnce() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        var updates = 0
        let scheduler = makeScheduler(searcher, onChanged: { updates += 1 })

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        #expect(updates == 1)
    }

    // MARK: - 취소

    @Test("취소하면 결과도 예약도 사라진다")
    func cancelClearsEverything() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        #expect(scheduler.result != nil)

        scheduler.cancel()
        #expect(scheduler.result == nil)
        #expect(scheduler.searchedTail == nil)
    }

    @Test("취소한 뒤에는 같은 꼬리로 다시 예약된다")
    func rescheduleAfterCancel() async {
        let searcher = CountingSearcher(["사랑": [genesisOneOne], "사랑은": [genesisOneOne]])
        let scheduler = makeScheduler(searcher)

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        scheduler.cancel()

        scheduler.schedule(tail: "사랑")
        await scheduler.fire(tail: "사랑")
        #expect(scheduler.result?.matchedQuery == "사랑")
    }

    // MARK: - 관례

    @Test("디바운스는 이 저장소의 기존 관례와 같은 120ms다")
    func delayMatchesRepositoryConvention() async {
        // `KeyboardViewController.scheduleLiveSettingsReload()`와 같은 값
        #expect(BibleSearchScheduler.defaultDelay == .milliseconds(120))
    }
}
