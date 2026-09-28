import Testing
import Foundation
@testable import TadakDomain

/// 이모지 「최근 사용」 — 값 타입과 판정 (PDR `docs/design-reviews/emoji-recent-persist.md` 4·7절).
///
/// 판정이 도메인에 있어서 `swift test`가 닿는다 — 조립 지점(`KeyboardViewController`)은 이 결과대로
/// 저장소에 읽고 쓰기만 한다(반론자1 급소⑤-1: VC 안의 로직은 테스트가 못 닿았다).
@Suite("이모지 기록 — 값 타입")
struct EmojiHistoryValueTests {

    @Test("최근순 · 중복은 맨 앞으로 · 16개 상한 (수용 기준 6)")
    func recordOrderAndCap() {
        var history = EmojiHistory()
        for index in 0..<20 { history.record("e\(index)") }
        #expect(history.entries.count == EmojiHistory.maxEntries)
        #expect(history.entries.first == "e19")
        #expect(history.entries.last == "e4")
        history.record("e10")
        #expect(history.entries.first == "e10")
        #expect(history.entries.count == 16)
        #expect(history.entries.filter { $0 == "e10" }.count == 1)
    }

    @Test("빈 문자열은 기록하지 않는다")
    func ignoresEmpty() {
        var history = EmojiHistory()
        history.record("")
        #expect(history.entries.isEmpty)
    }

    @Test("저장분이 손상돼도(중복·초과) 읽을 때 정리된다 — 뷰가 문자열을 id로 쓴다")
    func decodingSanitizes() throws {
        let many = (0..<20).map { "\"x\($0)\"" }.joined(separator: ",")
        let json = #"{"entries": ["😀","😀",\#(many)], "resetToken": 3}"#
        let history = try JSONDecoder().decode(EmojiHistory.self, from: Data(json.utf8))
        #expect(history.entries.count == 16)
        #expect(Set(history.entries).count == history.entries.count)
        #expect(history.resetToken == 3)
    }

    @Test("토큰 키가 없는 저장분은 토큰 0으로 읽는다")
    func decodingWithoutToken() throws {
        let history = try JSONDecoder().decode(EmojiHistory.self, from: Data(#"{"entries":["😀"]}"#.utf8))
        #expect(history.entries == ["😀"])
        #expect(history.resetToken == 0)
    }
}

@Suite("이모지 기록 — 설정과 맞추기 (끄면 삭제 · 초기화 토큰)")
struct EmojiHistoryReconcileTests {

    private let stored = EmojiHistory(entries: ["😀", "👍"], resetToken: 2)

    @Test("같은 프로세스 재등장 — 켜져 있고 토큰이 같으면 그대로 (수용 기준 1)")
    func unchangedWhenInSync() {
        #expect(stored.reconciled(enabled: true, resetToken: 2) == stored)
    }

    @Test("꺼져 있으면 빈 기록 — 설정 토큰을 새로 든다")
    func disabledIsEmpty() {
        let result = stored.reconciled(enabled: false, resetToken: 2)
        #expect(result.entries.isEmpty)
        #expect(result.resetToken == 2)
    }

    @Test("토큰이 다르면 빈 기록 — 끄고 다시 켠 사이 키보드가 안 떴어도 되살아나지 않는다")
    func tokenMismatchClears() {
        let result = stored.reconciled(enabled: true, resetToken: 3)
        #expect(result.entries.isEmpty)
        #expect(result.resetToken == 3, "다음 확인 때 또 지우지 않게 새 토큰을 든다")
    }
}

@Suite("이모지 기록 — 탭 뒤 저장할 값")
struct EmojiHistoryTapTests {

    private let stored = EmojiHistory(entries: ["😀", "👍"], resetToken: 2)

    @Test("평소 — 맨 앞에 기록")
    func records() {
        let result = EmojiHistory.afterTap("🎉", stored: stored, enabled: true, resetToken: 2, isSecureTextEntry: false)
        #expect(result?.entries == ["🎉", "😀", "👍"])
    }

    @Test("쓰기 직전 토큰이 바뀌었으면 옛 목록을 되살리지 않는다 — 방금 누른 것만 남는다 (수용 기준 4)")
    func tokenMismatchDoesNotRevive() {
        let result = EmojiHistory.afterTap("🎉", stored: stored, enabled: true, resetToken: 3, isSecureTextEntry: false)
        #expect(result?.entries == ["🎉"])
        #expect(result?.resetToken == 3)
    }

    @Test("secure 입력란에서는 기록하지 않는다 — 새 규칙 (수용 기준 5)")
    func secureDoesNotRecord() {
        #expect(EmojiHistory.afterTap("🎉", stored: stored, enabled: true, resetToken: 2, isSecureTextEntry: true) == nil)
    }

    @Test("secure여도 토큰이 바뀌었으면 비운 기록은 저장한다 — 방금 누른 것은 넣지 않는다")
    func secureStillClearsStale() {
        let result = EmojiHistory.afterTap("🎉", stored: stored, enabled: true, resetToken: 3, isSecureTextEntry: true)
        #expect(result == EmojiHistory(entries: [], resetToken: 3))
    }

    @Test("꺼져 있으면 기록하지 않고, 남아 있던 것은 비운다")
    func disabled() {
        let result = EmojiHistory.afterTap("🎉", stored: stored, enabled: false, resetToken: 2, isSecureTextEntry: false)
        #expect(result == EmojiHistory(entries: [], resetToken: 2))
        let empty = EmojiHistory(entries: [], resetToken: 2)
        #expect(EmojiHistory.afterTap("🎉", stored: empty, enabled: false, resetToken: 2, isSecureTextEntry: false) == nil,
                "이미 비어 있으면 쓸 것이 없다")
    }
}

@Suite("KeyboardSettings — 이모지 기록")
struct EmojiHistorySettingTests {

    @Test("기본 켬·토큰 0, 구 저장분(키 없음)도 같다")
    func defaults() throws {
        #expect(KeyboardSettings.default.emojiHistoryEnabled)
        #expect(KeyboardSettings.default.emojiHistoryResetToken == 0)
        let legacy = try JSONDecoder().decode(KeyboardSettings.self, from: Data("{}".utf8))
        #expect(legacy.emojiHistoryEnabled && legacy.emojiHistoryResetToken == 0)
    }

    @Test("저장·복원")
    func roundTrip() throws {
        var settings = KeyboardSettings.default
        settings.emojiHistoryEnabled = false
        settings.emojiHistoryResetToken = 5
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: JSONEncoder().encode(settings))
        #expect(!decoded.emojiHistoryEnabled && decoded.emojiHistoryResetToken == 5)
    }
}
