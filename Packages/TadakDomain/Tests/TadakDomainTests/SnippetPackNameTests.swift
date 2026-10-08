import Testing
@testable import TadakDomain

/// 내장 팩의 보이는 이름 — 설정 앱 팩 목록과 키보드 후보 패널 출처 이름표가 **같은 상수**를 쓴다(U7 A안, 2026-10-07).
///
/// 깨지려면: 이 글자를 바꾼다 — 설정 화면 글자와 후보 패널 글자가 **함께** 바뀌므로 그 자체는 어긋나지 않지만,
/// 사용자에게 보이는 이름이 바뀌는 일이라 이 시험이 먼저 울린다(설정 화면 글자는 U7 전과 같아야 한다).
@Suite("내장 팩 이름 — 설정·후보 패널 공용")
struct SnippetPackNameTests {

    @Test("★ 보이는 글자 고정 — 성경은 설정용(판본까지)과 출처용(짧게) 두 이름")
    func names() {
        #expect(SnippetPackName.anthem == "국가 상징문")
        #expect(SnippetPackName.greetings == "인사·상용구")
        #expect(SnippetPackName.date == "날짜·시간")
        #expect(SnippetPackName.bible == "성경 (개역한글)")
        #expect(SnippetPackName.bibleShort == "성경")
    }
}
