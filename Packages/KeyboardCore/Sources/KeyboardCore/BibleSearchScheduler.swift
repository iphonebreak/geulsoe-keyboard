import Foundation

/// 성경 검색 캐스케이드를 **입력이 멈춘 뒤에만** 돌린다 — 120ms 취소-재예약 디바운스.
///
/// 설계: `docs/design-reviews/v1.1.0-plan-v5.md` 3-2절(디바운스는 계획이 「필수」로 정한 항목),
/// 반론자2 F-1이 "구현에서 빠졌다"고 지적한 그 항목이다.
///
/// ## 왜 필요한가
///
/// 캐스케이드 최악은 **본문 훑기 10회**다 — 정확 5회 + 띄어쓰기 무시 5회.
/// 계약 이력: 8회(조사 검사) → 5회(말끝 떼기 제거) → **10회**(띄어쓰기 무시 추가, 2026-09-21).
/// 정확이 하나라도 걸리면 느슨은 안 돌므로 **되는 검색은 여전히 5회**이고, 10회는 0건인 입력의 값이다.
/// 키를 칠 때마다 이것이 동기로 돌면 타이핑이 그만큼 막힌다.
/// **횟수가 줄어도 디바운스가 필요하다는 결론은 그대로다** — 디바운스는 **지연을 줄이는 것이
/// 아니라 빈도를 줄인다.** 키마다가 아니라 **손이 멈출 때마다** 한 번 돈다.
///
/// ★ **1회 비용은 디바운스가 못 줄인다.** 꼬리별 실측(한 바퀴): 벤치 fixture 4.84ms ·
/// 실사용 문장 5.88ms · 비싼 낱말 줄 **13.00ms**. 그래서 스캔 자체를 **주 스레드 밖으로** 냈다
/// (`fire(tail:)` 참조). 디바운스는 빈도를, 비동기는 블록을 없앤다 — 둘 다 필요하다.
///
/// ## ★ 배지와 추천단어 개수가 여전히 「같은 값」을 쓴다 (계획서 2-1)
///
/// 계획 2-1은 배지 표시 여부와 추천단어 개수(2 vs 3)가 **같은 값**에서 나와야 한다고 못박는다.
/// 검색만 지연시키면 "배지는 아직 없는데 추천단어는 벌써 2개"가 될 수 있다.
///
/// **그래서 조립 지점은 캐스케이드를 직접 부르지 않고 이 객체의 `result`만 읽는다.**
/// 배지도 추천단어 개수도 그 한 값에서 나오므로 **어느 순간에도 둘이 어긋날 수 없다.**
/// 디바운스가 바꾸는 것은 *언제 그 값이 갱신되는가*이지 *몇 군데서 계산하는가*가 아니다.
/// 갱신이 끝나면 `onResultChanged`가 조립 지점의 툴바 갱신을 **한 번** 다시 돌려
/// 배지와 추천단어를 함께 다시 낸다.
///
/// ## 꼬리가 바뀌면 옛 결과는 **즉시** 버린다
///
/// ## ★ 실제 동시성 보장 — 이것만 참이다 (2026-09-21)
///
/// 1. **스캔은 한 번에 하나만 돈다.** 새 스캔은 앞 스캔이 *끝난 뒤에* 시작한다
///    (취소만 보내고 믿지 않는다 — 취소는 협조적이라 즉시 멈추지 않는다).
/// 2. **취소가 스캔 안까지 닿는다.** `BibleByteScanner`가 절 256개마다,
///    `BibleSearchCascade`가 훑기 사이마다 `Task.isCancelled`를 본다.
/// 3. **취소된 스캔의 결과는 절대 반영되지 않는다.**
///
/// 셋 다 `BibleSearchSchedulerTests`가 **느린 차단형 검색기**로 잠근다 —
/// 스캔을 실제로 시작시키고, 동시 실행 수와 반영 횟수를 센다.
///
/// 지연 동안 옛 결과를 들고 있으면 배지 숫자가 지금 문서와 맞지 않는다. 더 나쁜 것은
/// 그 사이에 사용자가 배지를 누르는 경우다 — 결과의 `typedText`("사랑")가 지금 꼬리("사랑해")와
/// 어긋나 ✕가 2자만 지워 「해」를 남기거나, 삽입의 꼬리 정합 검사가 조용히 거절한다.
/// **틀린 값을 잠깐 보여 주는 것보다 잠깐 안 보여 주는 쪽이 낫다.**
@MainActor
public final class BibleSearchScheduler {

    /// 기다리는 시간. **`KeyboardViewController.scheduleLiveSettingsReload`와 같은 120ms**다 —
    /// 이 저장소에 이미 있는 디바운스 관례를 그대로 쓴다(새 값을 만들 근거가 없다).
    /// 체감이 늦으면 줄여도 되는 값이고, 줄이면 손이 멈출 때마다 도는 빈도만 올라간다.
    public static let defaultDelay: Duration = .milliseconds(120)

    /// 지금 배지·추천단어 개수가 함께 읽는 **그 값**. 꼬리가 바뀌면 즉시 nil이 된다.
    public private(set) var result: BibleSearchResult?

    /// `result`가 어느 꼬리의 것인가. 같은 꼬리로는 다시 예약하지 않는다(재진입 방지).
    public private(set) var searchedTail: String?

    private let cascade: BibleSearchCascade
    private let delay: Duration
    private let sleep: @Sendable (Duration) async -> Void
    /// 만료 시점에 **다시** 묻는다 — 그 사이 secure 전환·칩 등장·✕가 있었을 수 있고,
    /// 꼬리도 바뀌었을 수 있다. 조립 지점이 게이트와 꼬리를 함께 판정한다.
    private let isStillValid: (String) -> Bool
    /// 결과가 실제로 바뀌었을 때만 부른다.
    private let onResultChanged: () -> Void

    private var task: Task<Void, Never>?

    /// 지금 도는 **실제** 스캔 핸들.
    ///
    /// ## ★ 예전에는 여기에 감싼 Task가 들어 있었다 — 취소가 닿지 않았다 (2026-09-21 수정)
    ///
    /// 고치기 전 코드는 `Task.detached { ... }`를 만들어 놓고 `Task { _ = await scan.value }`
    /// **래퍼**를 저장했다. 래퍼를 취소해도 unstructured detached 태스크로는 취소가 전파되지
    /// 않으므로 실제 스캔은 끝까지 돌았다 — **키보드가 내려가도 돌았다.** 그런데 주석은
    /// *"겹쳐 돌 이유가 없다"*고 단언했고, 그것을 지킨다는 테스트는 스캔을 시작조차 하지
    /// 않았다(반론자2). 지금은 **detached 핸들 자체**를 들고 있다.
    ///
    /// ## ★ 취소했다고 지우지 않는다
    ///
    /// 취소는 **협조적**이라 즉시 멈추지 않는다. 그래서 `schedule`·`cancel`은 취소만 보내고
    /// 핸들은 남긴다 — 다음 스캔이 이 핸들을 **기다려** 시작하기 때문이다(`fire` 참조).
    /// 여기서 nil로 지우면 아직 도는 스캔과 새 스캔이 겹친다.
    private var scanTask: Task<BibleSearchResult?, Never>?

    public init(
        cascade: BibleSearchCascade,
        delay: Duration = BibleSearchScheduler.defaultDelay,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        isStillValid: @escaping (String) -> Bool,
        onResultChanged: @escaping () -> Void
    ) {
        self.cascade = cascade
        self.delay = delay
        self.sleep = sleep
        self.isStillValid = isStillValid
        self.onResultChanged = onResultChanged
    }

    deinit {
        task?.cancel()
        scanTask?.cancel()
    }

    /// 이 꼬리로 검색을 예약한다. 키 입력마다 불린다 — **여기서는 절대 스캔하지 않는다.**
    public func schedule(tail: String) {
        // 이미 이 꼬리로 낸 결과가 있다 — 다시 돌 이유가 없다.
        // (`onResultChanged` → 툴바 갱신 → 여기로 되돌아오는 재진입을 끊는 자리이기도 하다.)
        guard searchedTail != tail else { return }

        // 꼬리가 바뀌었다 — 옛 결과는 지금 문서와 맞지 않으므로 즉시 버린다
        result = nil
        searchedTail = nil

        task?.cancel()
        // 돌고 있는 스캔에 취소를 보낸다. **핸들은 남긴다** — 다음 스캔이 이것이 끝나기를
        // 기다려 직렬화한다. 여기서 nil로 지우면 둘이 겹친다.
        scanTask?.cancel()
        task = Task { [weak self] in
            guard let delay = self?.delay, let sleep = self?.sleep else { return }
            await sleep(delay)
            guard !Task.isCancelled else { return }
            await self?.fire(tail: tail)
        }
    }

    /// 예약을 버리고 결과도 지운다 — 게이트가 닫혔을 때(secure·칩·✕) 조립 지점이 부른다.
    public func cancel() {
        task?.cancel()
        task = nil
        // 같은 이유로 핸들은 남긴다(위 `schedule` 주석).
        scanTask?.cancel()
        result = nil
        searchedTail = nil
    }

    /// 디바운스가 만료됐다. **여기가 유일하게 스캔하는 자리다.**
    /// 테스트가 시간을 기다리지 않고 직접 부를 수 있게 `internal`로 둔다.
    ///
    /// ## ★ 스캔은 주 스레드 **밖**에서 돈다 (2026-09-21, 반론자1 A-1)
    ///
    /// 디바운스는 **빈도만** 줄이고 1회 비용은 그대로다. 실측상 한 바퀴가 실사용 문장에서
    /// 5.9ms, 비싼 낱말 줄에서 **13.0ms**(예산의 78%)다 — 손이 멈춘 120ms 뒤에 그만큼
    /// **주 스레드가 한 번 막혔다.** 실기는 더 나쁘다(macOS 비율은 계획서가 폐기했다).
    ///
    /// 타입이 전부 `Sendable`이라(`BibleSearchCascade`·`BibleVerseSearching`·`BibleVerseMatch`)
    /// 스캔만 떼어 낼 수 있었다. **이 클래스는 `@MainActor`를 유지한다** — 상태는 계속 주 스레드에 있다.
    ///
    /// ## ★ 돌아온 뒤 `isStillValid`를 **한 번 더** 본다
    ///
    /// 비동기가 되면서 스캔이 도는 사이 꼬리가 바뀔 수 있다. 반영 직전에 다시 묻지 않으면
    /// **옛 결과가 새 꼬리 위에 얹힌다.** *틀린 값을 잠깐 보여 주는 것보다 잠깐 안 보여 주는 쪽이 낫다.*
    ///
    /// ## ★ 겹쳐 돌지 않게 하는 방법 — 취소를 **믿지 않는다** (2026-09-21)
    ///
    /// 취소는 협조적이다. 보냈다고 그 순간 멈추는 것이 아니라, 스캐너가 다음 확인점
    /// (절 256개)에 닿아야 빠져나온다. 그러니 *취소를 보냈으니 겹칠 리 없다*는 추론은 틀렸다.
    ///
    /// 그래서 두 가지를 함께 한다:
    /// - **보낸다** — 앞 스캔의 진짜 핸들을 취소해 빨리 끝나게 한다(일을 줄인다)
    /// - **기다린다** — 새 스캔은 `await previous?.value` 뒤에야 본문을 훑는다(겹침을 없앤다)
    ///
    /// 기다리는 것은 **주 스레드가 아니라 detached 스캔 쪽**이다. 주 스레드는 계속 논다.
    func fire(tail: String) async {
        // 그새 꼬리가 바뀌었거나 게이트가 닫혔으면 버린다 — 옛 결과를 반영하지 않는다
        guard isStillValid(tail) else { return }

        // ① 앞 스캔에 **진짜** 취소를 보낸다 (핸들을 들고 있으므로 이제 닿는다)
        let previous = scanTask
        previous?.cancel()

        // ② 새 스캔은 앞 스캔이 **끝난 뒤에만** 본문을 훑는다 — 여기가 직렬화 지점이다
        let cascade = self.cascade   // Sendable — 주 스레드 밖으로 넘긴다
        let scan = Task.detached(priority: .userInitiated) { () -> BibleSearchResult? in
            _ = await previous?.value
            guard !Task.isCancelled else { return nil }
            return cascade.search(tail: tail)
        }
        scanTask = scan

        let found = await scan.value
        // 내 스캔이 아직 현재 스캔이면 핸들을 놓는다 — 결과(최대 1,000 주소)를 붙들지 않는다.
        // 그새 새 스캔이 들어섰다면 그쪽 직렬화 사슬을 끊지 않도록 그대로 둔다.
        if scanTask == scan { scanTask = nil }

        // ★ 돌아왔다 — 그 사이에 바뀌었을 수 있다. 반영 직전에 다시 본다.
        //   `scan.isCancelled`가 **취소된 결과 0회 반영**을 보장하는 자리다
        //   (`Task.isCancelled`는 테스트가 `fire`를 직접 부를 때 비어 있다).
        guard !scan.isCancelled, !Task.isCancelled, isStillValid(tail) else { return }
        result = found
        searchedTail = tail
        onResultChanged()
    }
}
