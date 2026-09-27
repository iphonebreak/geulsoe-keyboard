import Testing
@testable import KeyboardCore

/// 클립보드 기록 패널 — 기록 ON/OFF · secure · 현재 클립보드 유무 → 읽기 여부와 보여 줄 목록.
///
/// ★ 2026-09-27 사장님 지적: 「클립보드 기록이 꺼져 있는데 클립보드 아이콘을 누르면 기록 1개가 뜬다」.
/// 옛 설계는 OFF일 때 현재 클립보드를 세션 목록 1개로 보여 줬다(저장은 안 함) — 사용자 눈에는
/// 기록과 똑같이 보여 「껐는데 왜 뜨지」가 된다. OFF면 **읽지도 보여 주지도 않는다.**
@Suite("클립보드 패널 내용")
struct ClipboardPanelContentTests {

    // MARK: - 읽기 여부

    @Test("기록 OFF면 클립보드를 읽지 않는다 — 안 보여 줄 것을 읽을 이유가 없다(최소 수집)")
    func offDoesNotRead() {
        #expect(!ClipboardPanelContent.readsPasteboard(
            historyEnabled: false, isSecureTextEntry: false, alreadyRecorded: false))
        #expect(!ClipboardPanelContent.readsPasteboard(
            historyEnabled: false, isSecureTextEntry: false, alreadyRecorded: true))
    }

    @Test("기록 ON이면 아직 기록하지 않은 클립보드만 읽는다")
    func onReadsUnrecorded() {
        #expect(ClipboardPanelContent.readsPasteboard(
            historyEnabled: true, isSecureTextEntry: false, alreadyRecorded: false))
        #expect(!ClipboardPanelContent.readsPasteboard(
            historyEnabled: true, isSecureTextEntry: false, alreadyRecorded: true))
    }

    @Test("secure 필드에서는 ON/OFF 모두 읽지 않는다", arguments: [true, false])
    func secureNeverReads(historyEnabled: Bool) {
        #expect(!ClipboardPanelContent.readsPasteboard(
            historyEnabled: historyEnabled, isSecureTextEntry: true, alreadyRecorded: false))
    }

    // MARK: - 보여 줄 목록
    //
    // 현재 클립보드는 `entries`의 입력이 아니다 — 「OFF+내용 있음 → 1개」(2026-09-27 회귀)는
    // 시그니처가 막는다. 여기서는 저장분만으로 정해지는 목록을 고정한다.

    @Test("기록 OFF → 목록은 비어 있다 (2026-09-27 회귀)")
    func offShowsNothing() {
        #expect(ClipboardPanelContent.entries(historyEnabled: false, stored: []).isEmpty)
    }

    @Test("기록 OFF면 저장분이 남아 있어도 보여 주지 않는다")
    func offIgnoresStored() {
        #expect(ClipboardPanelContent.entries(historyEnabled: false, stored: ["남은 기록"]).isEmpty)
    }

    @Test("기록 OFF면 읽지도 않고 보여 주지도 않는다 — 두 판정이 함께 닫힌다")
    func offClosesBoth() {
        #expect(!ClipboardPanelContent.readsPasteboard(
            historyEnabled: false, isSecureTextEntry: false, alreadyRecorded: false))
        #expect(ClipboardPanelContent.entries(historyEnabled: false, stored: ["남은 기록"]).isEmpty)
    }

    @Test("기록 ON이면 저장분을 그대로 보여 준다 — 더하지도 빼지도 않는다")
    func onShowsStored() {
        #expect(ClipboardPanelContent.entries(historyEnabled: true, stored: ["둘", "하나"]) == ["둘", "하나"])
    }

    @Test("기록 ON + 저장분 비어 있음 → 빈 목록")
    func onEmpty() {
        #expect(ClipboardPanelContent.entries(historyEnabled: true, stored: []).isEmpty)
    }
}
