import Foundation
import Testing
import TadakDomain
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

/// ✕·탭으로 소비한 클립보드 기록 — **번호(`changeCount`)와 내용의 지문**(2026-11-25).
///
/// 사장님 보고(2026-11-25): 복사됨 칩을 ✕로 내렸는데 나중에 키보드를 다시 열면 같은 칩이 또 떴다. 번호만 저장해서는
/// 못 막았다 — 맥 클립보드 변경 번호를 기록해 보니 아이폰에서 복사한 것이 맥으로 넘어간 지 8초 만에 맥이 **예전 항목으로
/// 되돌아가고**(번호 1072 → 1071) 그 항목이 아이폰으로 다시 넘어왔다. 유니버설 클립보드는 **같은 글을 새 번호로** 다시 보낸다.
/// 그래서 번호가 달라도 기록을 버리지 않고, 읽은 뒤 지문으로 「이미 소비한 글」인지 가린다.
@Suite("클립보드 소비 기록 — 번호와 지문")
struct PasteboardConsumptionTests {

    private let fingerprintA = Data(repeating: 0xA1, count: PasteboardFingerprint.byteCount)
    private let fingerprintB = Data(repeating: 0xB2, count: PasteboardFingerprint.byteCount)

    private func plan(changeCount: Int, consumed: PasteboardConsumption?) -> PasteboardProbe.Plan {
        PasteboardProbe.plan(codeSuggestionsEnabled: true, pasteSuggestionsEnabled: true, historyEnabled: false,
                             changeCount: changeCount, consumedChangeCount: consumed?.changeCount, recordedChangeCount: nil)
    }

    @Test("★ 같은 번호면 기록을 그대로 둔다 — 다시 열어도 읽지 않고 칩도 없다(맥 알림도 없다)")
    func keepsWhenSameClipboard() {
        let stored = PasteboardConsumption(changeCount: 17193, fingerprint: fingerprintA)
        let kept = PasteboardProbe.reconciled(stored, changeCount: 17193)
        #expect(kept == stored)
        #expect(!plan(changeCount: 17193, consumed: kept).needsSuggestion)
    }

    @Test("번호가 늘었으면 지문을 남긴 채 읽으러 간다 — 새 복사인지 다시 온 글인지는 읽은 뒤 지문으로 가린다")
    func keepsFingerprintWhenCountGrew() {
        let stored = PasteboardConsumption(changeCount: 1071, fingerprint: fingerprintA)
        let kept = PasteboardProbe.reconciled(stored, changeCount: 1075)
        #expect(kept == stored)
        #expect(plan(changeCount: 1075, consumed: kept).needsSuggestion)
    }

    @Test("재부팅으로 번호가 줄면 번호만 버리고 지문은 남긴다 — 다시 세어진 번호가 우연히 같아져 새 복사를 막지 않는다")
    func dropsCountAfterReset() {
        let reconciled = PasteboardProbe.reconciled(
            PasteboardConsumption(changeCount: 17193, fingerprint: fingerprintA), changeCount: 3)
        #expect(reconciled == PasteboardConsumption(changeCount: nil, fingerprint: fingerprintA))
        #expect(plan(changeCount: 3, consumed: reconciled).needsSuggestion)
    }

    @Test("재부팅 뒤 지문 없는 옛 기록(번호만)은 통째로 버린다")
    func dropsCountOnlyRecordAfterReset() {
        #expect(PasteboardProbe.reconciled(PasteboardConsumption(changeCount: 17193, fingerprint: nil), changeCount: 3) == nil)
    }

    @Test("기록이 없으면 없는 그대로")
    func nilStaysNil() {
        #expect(PasteboardProbe.reconciled(nil, changeCount: 5) == nil)
    }

    @Test("★ 같은 글이 새 번호로 다시 오면 알아본다 — 번호를 지금 값으로 옮겨 다음 등장은 읽지도 않는다(2026-11-25 실측)")
    func recognizesResend() {
        let stored = PasteboardConsumption(changeCount: 1071, fingerprint: fingerprintA)
        let resent = PasteboardProbe.resentConsumption(stored, changeCount: 1075, fingerprint: fingerprintA)
        #expect(resent == PasteboardConsumption(changeCount: 1075, fingerprint: fingerprintA))
        #expect(!plan(changeCount: 1075, consumed: resent).needsSuggestion)
    }

    @Test("재부팅 뒤 번호를 잃은 기록도 지문으로 알아본다")
    func recognizesResendAfterReset() {
        let stored = PasteboardConsumption(changeCount: nil, fingerprint: fingerprintA)
        #expect(PasteboardProbe.resentConsumption(stored, changeCount: 4, fingerprint: fingerprintA)
                == PasteboardConsumption(changeCount: 4, fingerprint: fingerprintA))
    }

    @Test("다른 글이면 새 복사다 — 칩을 띄운다")
    func differentContentIsNewCopy() {
        let stored = PasteboardConsumption(changeCount: 1071, fingerprint: fingerprintA)
        #expect(PasteboardProbe.resentConsumption(stored, changeCount: 1075, fingerprint: fingerprintB) == nil)
    }

    @Test("지문 없는 기록·기록 없음은 알아보지 않는다")
    func noFingerprintNoMatch() {
        #expect(PasteboardProbe.resentConsumption(PasteboardConsumption(changeCount: 1071, fingerprint: nil),
                                                  changeCount: 1075, fingerprint: fingerprintA) == nil)
        #expect(PasteboardProbe.resentConsumption(nil, changeCount: 1075, fingerprint: fingerprintA) == nil)
    }
}

/// 소비한 클립보드의 지문 — 원문 대신 저장한다(2026-11-25 사장님 결정, `.claude/rules/security.md` 클립보드 절).
@Suite("클립보드 지문 — 기기 열쇠를 섞은 비암호 해시")
struct PasteboardFingerprintTests {

    private let key = Data(repeating: 7, count: PasteboardFingerprint.keyByteCount)

    @Test("같은 글·같은 열쇠면 같은 지문")
    func sameTextSameFingerprint() {
        #expect(PasteboardFingerprint.make("123456", key: key) == PasteboardFingerprint.make("123456", key: key))
    }

    @Test("글이 한 글자만 달라도 다른 지문")
    func differentTextDifferentFingerprint() {
        #expect(PasteboardFingerprint.make("123456", key: key) != PasteboardFingerprint.make("123457", key: key))
    }

    @Test("열쇠가 다르면(다른 기기) 같은 글도 다른 지문")
    func differentKeyDifferentFingerprint() {
        let otherKey = Data(repeating: 8, count: PasteboardFingerprint.keyByteCount)
        #expect(PasteboardFingerprint.make("123456", key: key) != PasteboardFingerprint.make("123456", key: otherKey))
    }

    @Test("지문은 16바이트이고 원문 바이트를 담지 않는다 — TadakData 저장소가 16바이트만 받는다")
    func fingerprintIsFixedSizeAndOpaque() {
        let text = String(repeating: "인증번호 482913 ", count: 40)
        let fingerprint = PasteboardFingerprint.make(text, key: key)
        #expect(PasteboardFingerprint.byteCount == 16)
        #expect(fingerprint.count == 16)
        #expect(fingerprint.range(of: Data("482913".utf8)) == nil)
    }

    @Test("★ 계산법 고정 — 빈 열쇠면 두 갈래 모두 FNV-1a 64 표준값(바꾸면 저장된 지문이 조용히 안 맞는다)")
    func algorithmIsPinned() {
        // FNV-1a 64("a") = 0xaf63dc4c8601ec8c (Fowler–Noll–Vo 공개 시험값)
        let half: [UInt8] = [0xaf, 0x63, 0xdc, 0x4c, 0x86, 0x01, 0xec, 0x8c]
        #expect(PasteboardFingerprint.make("a", key: Data()) == Data(half + half))
    }

    @Test("두 갈래는 열쇠의 앞·뒤 반쪽을 따로 쓴다")
    func halvesUseSeparateSalts() {
        let mixedKey = Data(repeating: 1, count: 16) + Data(repeating: 2, count: 16)
        let fingerprint = PasteboardFingerprint.make("123456", key: mixedKey)
        #expect(fingerprint.prefix(8) != fingerprint.suffix(8))
    }
}
