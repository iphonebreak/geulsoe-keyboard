import Testing
@testable import HangulEngine

/// `JamoSource` 내부 상태를 accept 직접 호출로 격리 검증한다.
///
/// TypingHarness는 자모가 아닌 키에서 `source.reset()`을 대신 호출하므로,
/// 소스 **내부**의 상태 방어는 테이블 테스트로 잡히지 않는다 (뮤테이션 생존).
/// 여기서는 이벤트 수준으로 직접 고정한다.
@Suite("자판 소스 상태")
struct SourceStateTests {

    @Test("danmoeum — 자모 아닌 키가 연타 상태를 끊는다")
    func danmoeumNonJamoKeyBreaksPromotion() {
        let source = DanmoeumSource(timeout: 0.3)
        #expect(source.accept(key: "ㄱ", at: 0.1) == [.emit(.consonant("ㄱ"))])
        #expect(source.accept(key: "1", at: 0.15).isEmpty)
        // 외부에서 reset을 불러주지 않아도, 세 번째 ㄱ은 승격이 아니라 새 자모여야 한다
        #expect(source.accept(key: "ㄱ", at: 0.2) == [.emit(.consonant("ㄱ"))])
    }

    @Test("danmoeum — 연타 승격과 토글 복귀 이벤트")
    func danmoeumPromotionEvents() {
        let source = DanmoeumSource(timeout: 0.3)
        #expect(source.accept(key: "ㅏ", at: 0.1) == [.emit(.vowel("ㅏ"))])
        #expect(source.accept(key: "ㅏ", at: 0.2) == [.replaceLast(.vowel("ㅑ"))])
        #expect(source.accept(key: "ㅏ", at: 0.3) == [.replaceLast(.vowel("ㅏ"))])
    }

    @Test("cheonjiin — 자음이 오면 pending 점이 리터럴 이벤트로 확정된다")
    func cheonjiinFlushesPendingOnConsonant() {
        let source = CheonjiinSource(timeout: 0.8)
        #expect(source.accept(key: "ㆍ", at: 0.1) == [.pendingChanged])
        #expect(source.accept(key: "ㆍ", at: 0.2) == [.pendingChanged])
        #expect(source.pendingText == "ㆍㆍ")
        let events = source.accept(key: "ㄴ", at: 0.3)
        #expect(events == [.emit(.vowel("ㆍ")), .emit(.vowel("ㆍ")), .emit(.consonant("ㄴ"))])
        #expect(source.pendingText.isEmpty)
    }
}
