import Testing
@testable import KeyboardCore

/// ⌫ 길게 누르기 단어 단계 — 「두 어절」 계획(PDR `docs/design-reviews/backspace-word-acceleration.md` 1-2·1-3).
///
/// 표는 애플 기본 키보드 실측(`docs/release/measure-v132-apple-backspace.md` 2-2·2-4)을 옮긴 수용 기준이다.
/// 계획을 거듭 적용해 단계마다 남는 문맥을 단언한다 — 애플과 다른 칸은 C8(개행 = 한 단위, D1)·K5·E5(20자 초과 폴백)뿐이다.
/// 문장은 전부 합성이다.
@Suite("⌫ 단어 단계 — 두 어절 계획 (수용 기준 표)")
struct BackspaceWordPlanTests {

    /// 한 단계 — 지우면 남는 문맥. 폴백이면 nil
    private func step(_ context: String) -> String? {
        switch BackspaceWordPlan.plan(context: context) {
        case .delete(let count): String(context.dropLast(count))
        case .fallback: nil
        }
    }

    /// 단계를 `count`번 거듭 적용한 결과 목록(폴백을 만나면 거기서 nil을 넣고 멈춘다)
    private func steps(_ context: String, _ count: Int) -> [String?] {
        var current = context
        var result: [String?] = []
        for _ in 0..<count {
            guard let next = step(current) else {
                result.append(nil)
                break
            }
            result.append(next)
            current = next
            if current.isEmpty { break }
        }
        return result
    }

    @Test("C1 — 두 단어와 앞 공백 하나씩")
    func planDeletesTwoWordsWithOneLeadingSpace() {
        #expect(steps("one two three four five six", 3) == ["one two three four", "one two", ""])
    }

    @Test("C2 — 뒤 문장부호는 단어와 함께")
    func planKeepsTrailingPunctuationWithWord() {
        #expect(steps("one, two. three! four? five; six", 3) == ["one, two. three! four?", "one, two.", ""])
    }

    @Test("C3 — 공백 줄에서는 앞 공백 하나만")
    func planTakesOnlyOneLeadingSpaceFromSpaceRun() {
        #expect(steps("one   two   three   four", 2) == ["one   two  ", ""])
    }

    @Test("C4 — 하이픈은 경계, 앞쪽 하이픈은 남는다")
    func planSplitsAtHyphen() {
        #expect(steps("state-of-the-art well-known e-mail", 4)
                == ["state-of-the-art well-known", "state-of-the-art", "state-of-", ""])
    }

    @Test("C5 — 단어 안 아포스트로피는 단어 글자")
    func planKeepsApostropheInsideWord() {
        #expect(steps("don't can't it's we're they'll", 3) == ["don't can't it's", "don't", ""])
    }

    @Test("C6 — URL은 / . ? = &에서 나뉜다 (5단계)")
    func planSplitsUrlAtSlashDotQueryEqualsAmpersand() {
        #expect(steps("go to https://www.example.com/path/to/page?x=1&y=2", 5) == [
            "go to https://www.example.com/path/to/page?x=1&",
            "go to https://www.example.com/path/to/page?",
            "go to https://www.example.com/path/",
            "go to https://www.example.",
            "go to https://",
        ])
    }

    @Test("C7 — 숫자 안 , .는 붙이고 전화번호 하이픈은 나눈다")
    func planKeepsDigitGroupingInsideNumber() {
        #expect(steps("call 010-1234-5678 or 3.14159 and 1,000,000", 4)
                == ["call 010-1234-5678 or 3.14159", "call 010-1234-5678", "call 010-", ""])
    }

    @Test("C8 — 개행 하나는 한 단위 (D1)")
    func planCountsNewlineAsOneUnit() {
        #expect(steps("alpha bravo\ncharlie delta\n\necho foxtrot", 5)
                == ["alpha bravo\ncharlie delta\n\n", "alpha bravo\ncharlie delta", "alpha bravo\n", "alpha", ""])
    }

    @Test("C9 — 이메일은 @ .에서 나뉜다")
    func planSplitsEmailAtAtSign() {
        #expect(steps("mail me test.user@example.com", 3) == ["mail me test.user@", "mail me", ""])
    }

    @Test("K1 — 어절 둘씩, 조사·어미를 나누지 않는다")
    func planDeletesTwoEojeol() {
        #expect(steps("오늘은 날씨가 정말 좋네요 우리 같이 산책해요", 4)
                == ["오늘은 날씨가 정말 좋네요 우리", "오늘은 날씨가 정말", "오늘은", ""])
    }

    @Test("K2 — 띄어쓰기 없는 한글 20자는 한 단계")
    func planDeletesTwentyCharacterSpacelessHangul() {
        let token = "서울특별시강남구테헤란로백이십삼길사십오"
        #expect(token.count == 20)
        #expect(steps(token, 1) == [""])
    }

    @Test("K3 — 한글·영문이 섞여도 나누지 않는다 (19자)")
    func planDoesNotSplitAtScriptChange() {
        let token = "한국어와English가섞인문장입니다"
        #expect(token.count == 19)
        #expect(steps(token, 1) == [""])
    }

    @Test("K4 — 뒤 문장부호는 어절과 함께")
    func planDeletesTrailingPunctuationWithEojeol() {
        #expect(steps("1월 2일에 만나요. 그럼 안녕!", 3) == ["1월 2일에 만나요.", "1월", ""])
    }

    @Test("K5 — 띄어쓰기 없는 토큰이 20자를 넘으면 폴백")
    func planFallsBackForSpacelessTokenOverTwenty() {
        let token = "대한민국서울특별시강남구테헤란로백이십삼길사십오번지제일빌딩십층일호실우편번호육삼오사칠공일이삼사"
        #expect(token.count == 49)   // PDR 1-3·실측의 49자 토큰
        #expect(BackspaceWordPlan.plan(context: "가나다 라마바 " + token) == .fallback(.wordTooLong))
    }

    @Test("E5 — 긴 영어 단어(45자)도 폴백")
    func planFallsBackForLongLatinWord() {
        #expect(BackspaceWordPlan.plan(context: "abc def pneumonoultramicroscopicsilicovolcanoconiosis")
                == .fallback(.wordTooLong))
    }

    @Test("CW-08 — 둘째 단위만 길면 첫 단위만 지운다")
    func planDeletesOnlyFirstUnitWhenSecondExceedsLimit() {
        let context = "x " + String(repeating: "가", count: 30) + " ab"
        #expect(BackspaceWordPlan.plan(context: context) == .delete(count: 3))
    }

    @Test("검증 F2 — 한 단계 정확히 48자는 지우고 49자는 폴백")
    func planBoundaryAtFortyEight() {
        #expect(BackspaceWordPlan.plan(context: "a" + String(repeating: "!", count: 47)) == .delete(count: 48))
        #expect(BackspaceWordPlan.plan(context: "a" + String(repeating: "!", count: 48)) == .fallback(.stepTooLong))
        // 둘째 단위가 합계를 48에 딱 맞추면 함께, 49로 넘기면 첫 단위만(CW-08)
        let first = " " + String(repeating: "b", count: 20)                       // 21자
        #expect(BackspaceWordPlan.plan(context: "c" + String(repeating: "!", count: 26) + first) == .delete(count: 48))
        #expect(BackspaceWordPlan.plan(context: "c" + String(repeating: "!", count: 27) + first) == .delete(count: 21))
    }

    @Test("한 단계 48자를 넘으면 폴백 — 구분자 줄 50자")
    func planFallsBackWhenStepExceedsFortyEight() {
        #expect(BackspaceWordPlan.plan(context: "a" + String(repeating: "!", count: 50)) == .fallback(.stepTooLong))
    }

    @Test("문맥 맨 앞에 닿으면 보이는 만큼만 (과소 삭제)")
    func planDeletesOnlyVisibleWhenSpanReachesContextStart() {
        #expect(BackspaceWordPlan.plan(context: "bc def") == .delete(count: 6))
    }

    @Test("스칼라가 둘 이상인 글자가 든 단위는 폴백 (실측 2-5의 6종)")
    func planFallsBackOnMultiScalarCharacter() {
        let clusters = [
            "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}",  // 가족 ZWJ
            "\u{1F1F0}\u{1F1F7}",                                            // 국기
            "\u{1F44D}\u{1F3FD}",                                            // 피부색
            "1\u{FE0F}\u{20E3}",                                             // 키캡
            "e\u{0301}",                                                     // 결합 악센트
            "\u{1112}\u{1161}\u{11AB}",                                      // 조합형 자모
        ]
        for cluster in clusters {
            #expect(BackspaceWordPlan.plan(context: "ab cd " + cluster) == .fallback(.multiScalarCharacter),
                    "끝 단위에 복합 문자")
            // 둘째 단위에만 있으면 첫 단위만(CW-08과 같은 규칙)
            #expect(BackspaceWordPlan.plan(context: "ab " + cluster + " cd") == .delete(count: 3), "둘째 단위에 복합 문자")
        }
    }

    @Test("CW-09 — CRLF는 개행이지 복합 문자가 아니다")
    func planTreatsCRLFAsNewlineNotMultiScalar() {
        #expect(steps("line one\r\nline two", 3) == ["line one\r\n", "line", ""])
    }

    @Test("빈 문맥은 폴백")
    func planFallsBackOnEmptyContext() {
        #expect(BackspaceWordPlan.plan(context: "") == .fallback(.emptyContext))
    }
}
