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
        task = Task { [weak self] in
            guard let delay = self?.delay, let sleep = self?.sleep else { return }
            await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.fire(tail: tail)
        }
    }

    /// 예약을 버리고 결과도 지운다 — 게이트가 닫혔을 때(secure·칩·✕) 조립 지점이 부른다.
    public func cancel() {
        task?.cancel()
        task = nil
        result = nil
        searchedTail = nil
    }

    /// 디바운스가 만료됐다. **여기가 유일하게 스캔하는 자리다.**
    /// 테스트가 시간을 기다리지 않고 직접 부를 수 있게 `internal`로 둔다.
    func fire(tail: String) {
        // 그새 꼬리가 바뀌었거나 게이트가 닫혔으면 버린다 — 옛 결과를 반영하지 않는다
        guard isStillValid(tail) else { return }
        let found = cascade.search(tail: tail)
        result = found
        searchedTail = tail
        onResultChanged()
    }
}
