import Foundation
import TadakDomain

/// 키보드 등장 시 클립보드 프로브 — **내용(`string`)을 읽을지** (PDR verification-code-paste · clipboard-history).
///
/// 조립 지점(`KeyboardViewController.probePasteboard`)에 판정이 있으면 `swift test`가 닿지 않아 여기로 뺐다.
/// 조립 지점은 전체 접근·secure 입력란을 먼저 거른 뒤 `plan`을 만들고, **읽기는 `read`에 클로저로 넘긴다** —
/// 게이트를 지나야만 그 클로저가 불린다. 스파이 테스트가 「안 불렸다」를 센다(`PasteboardProbeTests`).
///
/// ★ 2026-09-29 수정(검증자 발견, 출시 차단): 조립 지점이 `pasteboard.string`을 스위치 게이트보다 **먼저** 불러,
/// 전체 접근 ON이면 「복사한 인증번호 제안」·「복사한 텍스트 제안」·「클립보드 기록」을 **셋 다 꺼도**, 이미 소비·기록한
/// 클립보드여도 키보드가 뜰 때마다 내용을 읽었다(`4e4fe5a`, v1.1.0부터). `.claude/rules/security.md`
/// 「두 기능이 모두 꺼져 있으면 읽지 않는다」·최소 접근 위반이고, `string`은 iOS 붙여넣기 알림을 띄울 수도 있다.
public enum PasteboardProbe {

    /// 이번 등장에서 무엇이 필요한가. 둘 다 거짓이면 **클립보드를 건드리지 않는다**(재시도도 없다).
    public struct Plan: Equatable, Sendable {
        /// 칩 후보를 만들 차례 — 인증번호·텍스트 제안 중 하나라도 켬 + 이 `changeCount`를 아직 칩으로 소비하지 않음
        public let needsSuggestion: Bool
        /// 기록할 차례 — 클립보드 기록 켬 + 이 `changeCount`를 아직 기록하지 않음
        public let needsHistory: Bool

        public var wantsContent: Bool { needsSuggestion || needsHistory }

        /// 빈손(내용이 아직 안 옴)이면 짧게 다시 시도할지 — 원하는 게 있을 때만(2026-09-15 재시도 규칙 그대로)
        public func retries(afterReading content: String?) -> Bool { wantsContent && content == nil }
    }

    /// - Parameters:
    ///   - consumedChangeCount: 칩을 탭해 이미 쓴 클립보드의 `changeCount`
    ///   - recordedChangeCount: 이미 기록에 넣은 클립보드의 `changeCount`
    public static func plan(
        codeSuggestionsEnabled: Bool,
        pasteSuggestionsEnabled: Bool,
        historyEnabled: Bool,
        changeCount: Int,
        consumedChangeCount: Int?,
        recordedChangeCount: Int?
    ) -> Plan {
        Plan(
            needsSuggestion: (codeSuggestionsEnabled || pasteSuggestionsEnabled) && changeCount != consumedChangeCount,
            needsHistory: historyEnabled && changeCount != recordedChangeCount)
    }

    /// 등장 때 저장해 둔 소비 기록을 지금 번호에 맞춘다 — **번호가 줄었을 때만** 번호를 버린다.
    ///
    /// - 번호가 같으면 그대로 — `plan`이 읽지 않는다(칩도 맥 알림도 없다).
    /// - 번호가 늘었어도 그대로 — 새 복사인지, 유니버설 클립보드가 **같은 글을 새 번호로** 다시 보낸 것인지는
    ///   읽은 뒤 지문으로 가린다(`resentConsumption`, 2026-11-25 실측). 예전에는 여기서 기록을 버려 다시 온 글의 칩이 또 떴다.
    /// - 번호가 줄었으면 재부팅이다(한 부팅 안에서 `changeCount`는 늘기만 한다) — 번호만 버리고 지문은 남긴다.
    ///   다시 세어진 번호가 우연히 기록과 같아지면 새 복사를 읽지도 않고 막기 때문이다. 지문도 없으면 기록을 버린다.
    public static func reconciled(_ consumption: PasteboardConsumption?, changeCount: Int) -> PasteboardConsumption? {
        guard let consumption else { return nil }
        guard let consumed = consumption.changeCount, changeCount < consumed else { return consumption }
        guard let fingerprint = consumption.fingerprint else { return nil }
        return PasteboardConsumption(changeCount: nil, fingerprint: fingerprint)
    }

    /// 읽은 클립보드가 **이미 소비한 글이 새 번호로 다시 온 것**인가 — 맞으면 번호를 지금 값으로 옮긴 기록, 아니면 nil.
    ///
    /// 맞으면 조립 지점은 칩을 띄우지 않고 이 기록을 저장한다 — 다음 등장은 번호가 같아 읽지도 않는다.
    /// 다르면 새 복사다(칩을 띄운다). 그때도 옛 기록은 남긴다 — 맥이 그 글을 나중에 또 보낼 수 있다.
    public static func resentConsumption(
        _ consumption: PasteboardConsumption?, changeCount: Int, fingerprint: Data
    ) -> PasteboardConsumption? {
        guard let stored = consumption?.fingerprint, stored == fingerprint else { return nil }
        return PasteboardConsumption(changeCount: changeCount, fingerprint: fingerprint)
    }

    /// **게이트 → `hasStrings` → `string`** 순서로만 읽는다.
    ///
    /// - 게이트(`plan.wantsContent`)가 닫히면 두 클로저 모두 부르지 않는다 — 클립보드를 아예 건드리지 않는다.
    /// - `hasStrings`는 내용을 가져오지 않아 붙여넣기 확인 창을 띄우지 않는다. 참일 때만 `string`을 **한 번** 부른다.
    public static func read(_ plan: Plan, hasStrings: () -> Bool, readString: () -> String?) -> String? {
        guard plan.wantsContent else { return nil }
        guard hasStrings() else { return nil }
        return readString()
    }
}
