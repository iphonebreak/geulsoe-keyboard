import Testing
@testable import KeyboardCore

/// 키보드 등장 시 클립보드 프로브 — **내용(`string`)을 읽을지**의 표.
///
/// ★ 2026-09-29 버그(검증자 발견): 조립 지점이 `string`을 스위치 게이트보다 **먼저** 불러, 전체 접근 ON이면
/// 「복사한 인증번호 제안」·「복사한 텍스트 제안」·「클립보드 기록」을 **셋 다 꺼도**, 이미 소비·기록한 클립보드여도
/// 키보드가 뜰 때마다 내용을 읽었다(`4e4fe5a`부터). 읽기 자체를 `PasteboardProbe.read`의 클로저로 넘겨,
/// **게이트가 닫히면 그 클로저가 불리지 않는다**를 스파이로 센다.
@Suite("클립보드 프로브 — 게이트를 지나야만 내용을 읽는다")
struct PasteboardProbeTests {

    /// 읽기 스파이 — 불린 횟수를 센다
    private final class Spy {
        var hasStringsCalls = 0
        var readCalls = 0
        let hasStrings: Bool
        let content: String?
        init(hasStrings: Bool = true, content: String? = "123456") {
            self.hasStrings = hasStrings
            self.content = content
        }
        func probe(_ plan: PasteboardProbe.Plan) -> String? {
            PasteboardProbe.read(plan,
                                 hasStrings: { self.hasStringsCalls += 1; return self.hasStrings },
                                 readString: { self.readCalls += 1; return self.content })
        }
    }

    private func plan(code: Bool = false, paste: Bool = false, history: Bool = false,
                      changeCount: Int = 7, consumed: Int? = nil, recorded: Int? = nil) -> PasteboardProbe.Plan {
        PasteboardProbe.plan(codeSuggestionsEnabled: code, pasteSuggestionsEnabled: paste,
                             historyEnabled: history, changeCount: changeCount,
                             consumedChangeCount: consumed, recordedChangeCount: recorded)
    }

    @Test("★ 셋 다 꺼짐 — 새 클립보드여도 내용을 읽지 않는다(재시도도 없다)")
    func allOffNeverReads() {
        let spy = Spy()
        let p = plan()
        #expect(spy.probe(p) == nil)
        #expect(spy.readCalls == 0, "string을 부르면 안 된다 — 이번 버그")
        #expect(!p.wantsContent)
        #expect(!p.retries(afterReading: nil), "읽을 게 없으니 재시도도 없다")
    }

    @Test("★ 이미 소비·기록한 클립보드 — 스위치가 켜져 있어도 읽지 않는다")
    func consumedAndRecordedNeverReads() {
        let spy = Spy()
        let p = plan(code: true, paste: true, history: true, changeCount: 7, consumed: 7, recorded: 7)
        #expect(spy.probe(p) == nil)
        #expect(spy.readCalls == 0)
        #expect(!p.retries(afterReading: nil))
    }

    @Test("하나라도 켬 + 새 내용 — 한 번 읽는다", arguments: [
        (true, false, false), (false, true, false), (false, false, true), (true, true, true)
    ])
    func anyOnReadsOnce(code: Bool, paste: Bool, history: Bool) {
        let spy = Spy()
        #expect(spy.probe(plan(code: code, paste: paste, history: history)) == "123456")
        #expect(spy.readCalls == 1)
    }

    @Test("무엇이 필요한지 — 제안은 소비 여부로, 기록은 기록 여부로 따로 판정")
    func needsAreIndependent() {
        // 제안은 이미 소비했지만 기록은 아직 — 기록 때문에 읽는다
        let a = plan(code: true, history: true, changeCount: 7, consumed: 7, recorded: 6)
        #expect(!a.needsSuggestion && a.needsHistory && a.wantsContent)
        // 기록은 했지만 제안은 아직 — 제안 때문에 읽는다
        let b = plan(paste: true, history: true, changeCount: 7, consumed: 6, recorded: 7)
        #expect(b.needsSuggestion && !b.needsHistory && b.wantsContent)
        // 제안만 켰는데 이미 소비 — 읽지 않는다
        let c = plan(code: true, changeCount: 7, consumed: 7)
        #expect(!c.wantsContent)
        // 기록만 켰는데 이미 기록 — 읽지 않는다
        let d = plan(history: true, changeCount: 7, recorded: 7)
        #expect(!d.wantsContent)
        // 처음(소비·기록 기록 없음) — 켜진 쪽이 필요하다
        let e = plan(code: true, history: true)
        #expect(e.needsSuggestion && e.needsHistory)
    }

    @Test("hasStrings가 거짓이면 string을 부르지 않고, 원하는 게 있으면 재시도한다(빈손 → 조용한 재시도)")
    func noStringsNoReadButRetry() {
        let spy = Spy(hasStrings: false)
        let p = plan(history: true)
        #expect(spy.probe(p) == nil)
        #expect(spy.readCalls == 0, "hasStrings는 확인 창을 띄우지 않지만 string은 띄울 수 있다")
        #expect(spy.hasStringsCalls == 1)
        #expect(p.retries(afterReading: nil))
    }

    @Test("게이트가 닫히면 hasStrings도 묻지 않는다 — 클립보드를 아예 건드리지 않는다")
    func closedGateTouchesNothing() {
        let spy = Spy()
        _ = spy.probe(plan())
        #expect(spy.hasStringsCalls == 0 && spy.readCalls == 0)
    }

    @Test("읽었는데 빈손(string nil) — 원하는 게 있으면 재시도")
    func emptyReadRetries() {
        let spy = Spy(hasStrings: true, content: nil)
        let p = plan(code: true)
        #expect(spy.probe(p) == nil)
        #expect(spy.readCalls == 1)
        #expect(p.retries(afterReading: nil))
        #expect(!p.retries(afterReading: "x"))
    }
}

/// ✕·탭으로 소비한 클립보드 기록을 지금 클립보드에 맞춘다 — 기록이 저장소에 남게 되면서(2026-11-25) 생긴 규칙.
///
/// 사장님 보고(2026-11-25): 복사됨 칩을 ✕로 내렸는데 나중에 키보드를 다시 열면 같은 칩이 또 떴다. 소비 기록이
/// 메모리에만 있어 키보드 프로세스가 내려가면 사라졌다. 기록을 저장하게 되면 반대로 **낡은 기록**이 문제다 —
/// 재부팅 뒤 `changeCount`가 처음부터 다시 세어지면 우연히 같은 값의 새 복사를 막을 수 있다.
/// 그래서 지금 값과 다르면 버린다. 한 부팅 안에서 `changeCount`는 늘기만 하므로 버린 값의 클립보드는 다시 오지 않는다.
@Suite("클립보드 소비 기록 — 지금 클립보드와 같을 때만 남긴다")
struct PasteboardConsumptionTests {

    @Test("★ 같은 클립보드면 기록을 남긴다 — 다시 열어도 ✕로 내린 칩이 뜨지 않는다")
    func keepsWhenSameClipboard() {
        #expect(PasteboardProbe.retainedConsumption(17193, changeCount: 17193) == 17193)
        let plan = PasteboardProbe.plan(codeSuggestionsEnabled: true, pasteSuggestionsEnabled: true, historyEnabled: false,
                                        changeCount: 17193,
                                        consumedChangeCount: PasteboardProbe.retainedConsumption(17193, changeCount: 17193),
                                        recordedChangeCount: nil)
        #expect(!plan.needsSuggestion)
    }

    @Test("새로 복사했으면(값이 다르면) 기록을 버린다 — 새 클립보드의 칩은 뜬다")
    func dropsWhenClipboardChanged() {
        #expect(PasteboardProbe.retainedConsumption(17193, changeCount: 17194) == nil)
        let plan = PasteboardProbe.plan(codeSuggestionsEnabled: false, pasteSuggestionsEnabled: true, historyEnabled: false,
                                        changeCount: 17194,
                                        consumedChangeCount: PasteboardProbe.retainedConsumption(17193, changeCount: 17194),
                                        recordedChangeCount: nil)
        #expect(plan.needsSuggestion)
    }

    @Test("재부팅으로 값이 작아져도 버린다 — 나중에 우연히 같은 값에 닿아도 새 복사를 막지 않는다")
    func dropsAfterCounterReset() {
        #expect(PasteboardProbe.retainedConsumption(17193, changeCount: 3) == nil)
    }

    @Test("기록이 없으면 없는 그대로")
    func nilStaysNil() {
        #expect(PasteboardProbe.retainedConsumption(nil, changeCount: 5) == nil)
    }
}
