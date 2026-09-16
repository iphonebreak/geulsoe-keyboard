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
        ("코드 1234 를 입력", "1234"),
        // ★ 구글 표준 꼴 `G-123456` (2026-09-15 추가). 하이픈 인접 run 배제 규칙에 걸려
        // **못 잡던 것**이다 — 조사에서 미탐으로 확인됐다. 전화번호 배제 규칙을 건드리지 않으려고
        // 「G-」 라는 글자를 요구하는 좁은 규칙으로만 뚫는다. 넣을 값은 **숫자만**이다
        // (구글 문자의 "G-123456 is your Google verification code"에서 입력란에 치는 것은 숫자다).
        ("G-483920 is your Google verification code", "483920"),
        ("G-123456이 Google 인증 코드입니다", "123456"),
        ("g-5678", "5678")                                       // 소문자도 같다
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
        "010-1234-5678로 연락주세요",                // G- 규칙이 전화번호를 건드리지 않는다
        "SG-1234 창고 재고 확인",                    // 「G-」 앞에 글자가 붙으면 구글 꼴이 아니다
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

/// 사용자가 실기에서 실제로 받은 문자 — 보고될 때마다 여기에 고정한다.
///
/// **문자 앱에서 길게 눌러 복사하면 본문 전체가 들어온다.** 그래서 이 경로가 실사용의 기본이고,
/// 「코드 복사」로 숫자만 오는 경우가 오히려 예외다. 실제 표본이 가장 값진 회귀 자산이다.
/// 번호는 전부 보고에 실린 값이고 개인정보가 아니다.
@Suite("실제 문자 표본")
struct RealWorldSMSTests {
    @Test("KG이니시스 인증번호 문자 전문에서 번호만 뽑는다")
    func kginicis() {
        let sms = """
        [Web발신]
        [KG이니시스]
        인증번호 [268755]를
        입력해 주세요.
        """
        #expect(VerificationCodeDetector.extractCode(from: sms) == "268755")
    }
}

/// 실제 형식군 스트레스에서 나온 **오탐** 표본 (2026-09-16).
///
/// 64개 표본을 네 형식군(은행·결제 / 포털·메신저 / 공공·통신 / 형식 가장자리)으로 훑어
/// 오탐 19건·미탐 6건을 찾았고, 반증 단계가 그중 실재 근거가 강한 것만 남겼다.
/// **오탐이 미탐보다 나쁘다** — `PasteSuggestion.make` 가 "인증번호가 뽑히면 그쪽이 이긴다"라서,
/// 엉뚱한 숫자가 뽑히면 사용자는 인증에 실패할 뿐 아니라 **원래 복사한 것을 붙여넣을
/// 「복사됨」 칩 자체를 잃는다.** 미탐은 그 칩으로 떨어져 전문이 보이므로 복구된다.
@Suite("오탐 방지 — 실제 형식군")
struct FalsePositiveGuardTests {

    // MARK: 「인증서」는 증명서지 번호가 아니다 (실재 근거 강함)

    @Test("금융인증서 만료 안내의 연도를 집지 않는다")
    func certificateExpiryYear() {
        #expect(VerificationCodeDetector.extractCode(
            from: "금융인증서 유효기간이 2026년 9월 30일 만료됩니다") == nil)
    }

    @Test("공동인증서 갱신 안내의 대표번호 조각을 집지 않는다")
    func certificateRenewalPhone() {
        #expect(VerificationCodeDetector.extractCode(
            from: "공동인증서 갱신 안내 1588 0000") == nil)
    }

    @Test("KB 공동인증서 만료 문자에서 점 구분 날짜를 집지 않는다")
    func certificateDottedDate() {
        let sms = """
        [Web발신]
        [KB국민은행]
        고객님의 공동인증서가
        2026.09.30 만료됩니다.
        인터넷뱅킹에서 갱신해 주세요.
        """
        #expect(VerificationCodeDetector.extractCode(from: sms) == nil)
    }

    // MARK: 단위가 붙은 숫자는 번호가 아니다

    @Test("본인인증 완료 문자의 금액을 집지 않는다")
    func amountAfterVerification() {
        #expect(VerificationCodeDetector.extractCode(
            from: "본인인증이 완료되었습니다. 25000원") == nil)
    }

    @Test("로그인 인증 감지 알림의 연도를 집지 않는다 — 애초에 코드가 없는 문자다")
    func loginAlertHasNoCode() {
        #expect(VerificationCodeDetector.extractCode(
            from: "[Web발신] 2026년 09월 16일 10시 30분 새로운 기기에서 로그인 인증이 감지되었습니다.") == nil)
    }

    // MARK: 「~코드」 합성어는 인증이 아니다

    @Test("할인코드 광고의 금액을 집지 않는다")
    func discountCodeAmount() {
        #expect(VerificationCodeDetector.extractCode(
            from: "[Web발신] [쿠팡] 첫 구매 할인코드로 3000원 즉시 할인! 9/30까지") == nil)
    }

    @Test("프로모션코드 안내의 금액을 집지 않는다")
    func promotionCodeAmount() {
        let sms = """
        [Web발신]
        [신한카드] 승인 4,500원
        스타벅스 강남점
        프로모션코드 등록 시 10000원 할인
        """
        #expect(VerificationCodeDetector.extractCode(from: sms) == nil)
    }

    @Test("바코드 안내의 접수 숫자를 집지 않는다")
    func barcodeNumber() {
        #expect(VerificationCodeDetector.extractCode(
            from: "[Web발신] [CJ대한통운] 편의점 반품 접수 바코드 39281 을 제시하세요.") == nil)
    }

    // MARK: 확실한 말이 있으면 그쪽이 이긴다

    @Test("머리말의 「본인인증」이 아니라 본문의 「인증번호」에서 뽑는다")
    func strongKeywordWinsOverHeading() {
        let sms = """
        [Web발신]
        [한국전력] 본인인증 안내
        고객번호 482913
        인증번호 771203
        """
        #expect(VerificationCodeDetector.extractCode(from: sms) == "771203")
    }
}
