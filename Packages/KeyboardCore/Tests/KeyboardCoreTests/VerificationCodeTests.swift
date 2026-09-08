import Foundation
import Testing
@testable import KeyboardCore

@Suite("인증번호 추출")
struct VerificationCodeDetectorTests {

    @Test("코드를 찾는 경우", arguments: [
        ("483920", "483920"),                                    // 코드 복사 그대로
        ("  483920 \n", "483920"),                               // 공백 정리
        ("1234", "1234"),                                        // 최소 4자리
        ("12345678", "12345678"),                                // 최대 8자리
        ("[Web발신]\n인증번호 483920 를 입력하세요", "483920"),      // 문자 전문
        ("인증번호는 [48392]입니다", "48392"),                      // 괄호 인접 허용
        ("승인번호 7712 (3분 내 입력)", "7712"),
        ("Your OTP code is 553201.", "553201"),
        // 키워드 앞의 금액·연도를 집지 않는다 (리뷰 반영 — 키워드 이후 run 우선)
        ("15000원 결제 승인번호 123456", "123456"),
        ("2026년 가입 인증번호 483920", "483920"),
        ("코드 1234 를 입력", "1234")
    ])
    func extracts(testCase: (String, String)) {
        #expect(VerificationCodeDetector.extractCode(from: testCase.0) == testCase.1)
    }

    @Test("코드가 아닌 경우", arguments: [
        "",
        "123",                                   // 3자리 — 짧다
        "123456789",                             // 9자리 — 길다
        "010-1234-5678",                         // 전화번호 (키워드 없음)
        "인증 문의: 010-1234-5678",                 // 키워드 있어도 하이픈 인접 run 배제
        "가격은 20000원입니다",                      // 키워드 없는 일반 숫자
        "안녕하세요"
    ])
    func rejects(text: String) {
        #expect(VerificationCodeDetector.extractCode(from: text) == nil)
    }
}

@MainActor
@Suite("InputController — 제공 텍스트 삽입")
struct InsertProvidedTextTests {

    @Test("조합을 확정하고 그대로 삽입하며 학습을 울리지 않는다")
    func insertsVerbatim() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }

        for key in ["d", "k", "s"] { controller.handle(.character(key)) }  // 안 (조합 중)
        controller.insertProvidedText("483920")
        #expect(output.text == "안483920")
        #expect(controller.textTail == "안483920")

        controller.handle(.space)
        #expect(committed.isEmpty, "붙여넣기 직후 공백이 학습을 울리면 안 된다")
    }

    /// 리뷰 반영 — 클립보드 유래 텍스트에 한글을 이어 쳐 만든 run은 학습 저장소에 들어가면 안 된다.
    @Test("붙여넣은 텍스트에 이어 친 단어는 학습하지 않고, 경계 뒤 단어부터 학습한다")
    func pastedTextDoesNotLeakIntoLearning() {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        var committed: [String] = []
        controller.onWordCommitted = { committed.append($0) }

        controller.insertProvidedText("비밀메모끝")
        for key in ["d", "l", "a"] { controller.handle(.character(key)) }  // 임
        controller.handle(.space)
        #expect(output.text == "비밀메모끝임 ")
        #expect(committed.isEmpty, "'비밀메모끝임'이 학습되면 클립보드 조각이 저장된다")

        for key in ["d", "k", "s", "s", "u", "d"] { controller.handle(.character(key)) }  // 안녕
        controller.handle(.space)
        #expect(committed == ["안녕"], "경계를 지난 뒤의 순수 타이핑은 정상 학습")
    }
}
