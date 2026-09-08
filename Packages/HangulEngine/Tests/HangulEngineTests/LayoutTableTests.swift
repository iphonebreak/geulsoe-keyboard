import Testing
@testable import HangulEngine

/// 자판별 입력 시퀀스 → 기대 출력 테이블.
///
/// **이 프로젝트의 주 회귀 방어선이다.** 자판을 추가하거나 오토마타를 고칠 때
/// 여기에 케이스를 먼저 추가한 뒤 구현한다. `/hangul-table-test`가 이 스위트만 돌린다.
@Suite("LayoutTableTests")
struct LayoutTableTests {

    // MARK: - 두벌식

    @Test("dubeolsik 기본 조합", arguments: [
        TypingCase("dkssud", "안녕", "받침 + 다음 글자"),
        TypingCase("gksrmf", "한글", "받침 있는 두 글자"),
        TypingCase("rk", "가", "초성 + 중성"),
        TypingCase("rks", "간", "초성 + 중성 + 종성"),
        TypingCase("tprP", "세계", "시프트 복모음 ㅖ"),
        TypingCase("dhkdlfmadmf", "와이름을", "연속 도깨비불 — 받침이 계속 다음 글자로 넘어간다")
    ])
    func dubeolsikBasic(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("dubeolsik 겹받침", arguments: [
        TypingCase("djqt", "없", "ㅂ + ㅅ = ㅄ"),
        TypingCase("djqtdmf", "없을", "겹받침 뒤 새 글자"),
        TypingCase("dkfg", "앓", "ㄹ + ㅎ = ㅀ"),
        TypingCase("rkrt", "갃", "ㄱ + ㅅ = ㄳ"),
        TypingCase("dkswek", "앉다", "ㄴ + ㅈ = ㄵ 뒤 새 글자"),
        TypingCase("dkstek", "안ㅅ다", "ㄴ + ㅅ은 겹받침이 아니라 각각 남는다")
    ])
    func dubeolsikCompoundJongseong(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("dubeolsik 복모음", arguments: [
        TypingCase("rhk", "과", "ㅗ + ㅏ = ㅘ"),
        TypingCase("ghl", "회", "ㅗ + ㅣ = ㅚ"),
        TypingCase("dnjf", "월", "ㅜ + ㅓ = ㅝ"),
        TypingCase("dml", "의", "ㅡ + ㅣ = ㅢ"),
        TypingCase("rho", "괘", "ㅗ + ㅐ = ㅙ"),
        TypingCase("rhoa", "괨", "복모음 뒤에도 받침이 붙는다"),
        TypingCase("kk", "ㅏㅏ", "합쳐지지 않는 모음은 각각 남는다")
    ])
    func dubeolsikCompoundJungseong(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("dubeolsik 도깨비불", arguments: [
        TypingCase("rksk", "가나", "홑받침이 다음 초성으로"),
        TypingCase("rkrtk", "각사", "겹받침은 뒤쪽만 넘어간다"),
        TypingCase("dkstk", "안사", "ㄴ이 넘어간다"),
        TypingCase("djqtj", "업서", "ㅄ에서 ㅅ만 넘어간다"),
        TypingCase("djqtdj", "없어", "자음이 오면 겹받침이 유지된다")
    ])
    func dubeolsikLinking(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("dubeolsik 쌍자음", arguments: [
        TypingCase("Rk", "까", "ㄲ 초성"),
        TypingCase("dkT", "았", "ㅆ 받침"),
        TypingCase("dkTk", "아싸", "ㅆ 받침도 도깨비불로 넘어간다"),
        TypingCase("Ek", "따", "ㄸ 초성"),
        TypingCase("ekEk", "다따", "ㄸ은 받침이 될 수 없어 다음 글자로"),
        TypingCase("rkQk", "가빠", "ㅃ도 받침이 될 수 없다")
    ])
    func dubeolsikTenseConsonants(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("dubeolsik 자모 아닌 키", arguments: [
        TypingCase("rk1", "가1", "숫자는 조합을 끝내고 그대로 입력"),
        TypingCase("rks!", "간!", "기호도 마찬가지"),
        TypingCase("rk rk", "가 가", "공백이 글자를 나눈다")
    ])
    func dubeolsikNonJamo(testCase: TypingCase) {
        var harness = TypingHarness(source: DubeolsikSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    // MARK: - 천지인
    //
    // 기본 type() 간격 0.1초는 타임아웃(0.8초) 안이므로 같은 키 연속은 순환이 된다.
    // 타임아웃 경과 케이스만 press(at:)로 시각을 지정한다.
    // 동작 근거: docs/design-reviews/cheonjiin-danmoeum-layouts.md (iOS 10키 실측)

    @Test("cheonjiin 기본 조합", arguments: [
        TypingCase("ㄱㅣㆍ", "가", "ㅣ+ㆍ = ㅏ"),
        TypingCase("ㄱㅣㆍㄴ", "간", "받침"),
        TypingCase("ㅇㅣㆍㄴ", "안", "ㅇ 초성"),
        TypingCase("ㄴㆍㆍㅣ", "녀", "ᆢ+ㅣ = ㅕ"),
        TypingCase("ㄱㆍㅣ", "거", "ㆍ+ㅣ = ㅓ"),
        TypingCase("ㄱㆍㅡ", "고", "ㆍ+ㅡ = ㅗ"),
        TypingCase("ㄱㆍㆍㅡ", "교", "ᆢ+ㅡ = ㅛ"),
        TypingCase("ㄱㅡㆍ", "구", "ㅡ+ㆍ = ㅜ"),
        TypingCase("ㄱㅡㆍㆍ", "규", "ㅜ+ㆍ = ㅠ"),
        TypingCase("ㄱㅡㅣ", "긔", "ㅡ+ㅣ = ㅢ"),
        TypingCase("ㄱㅣㆍㅣ", "개", "ㅏ+ㅣ = ㅐ"),
        TypingCase("ㄱㆍㅣㅣ", "게", "ㅓ+ㅣ = ㅔ"),
        TypingCase("ㄱㅣㆍㆍ", "갸", "ㅏ+ㆍ = ㅑ"),
        TypingCase("ㄱㅣㆍㆍㅣ", "걔", "ㅑ+ㅣ = ㅒ"),
        TypingCase("ㄱㆍㆍㅣㅣ", "계", "ㅕ+ㅣ = ㅖ")
    ])
    func cheonjiinBasic(testCase: TypingCase) {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("cheonjiin 복모음 진행", arguments: [
        TypingCase("ㄱㆍㅡㅣ", "괴", "ㅗ+ㅣ = ㅚ"),
        TypingCase("ㄱㆍㅡㅣㆍ", "과", "ㅚ+ㆍ = ㅘ — 실측 전이"),
        TypingCase("ㄱㆍㅡㅣㆍㅣ", "괘", "ㅘ+ㅣ = ㅙ"),
        TypingCase("ㄱㅡㆍㅣ", "귀", "ㅜ+ㅣ = ㅟ"),
        TypingCase("ㄱㅡㆍㆍㅣ", "궈", "ㅠ+ㅣ = ㅝ — 실측 전이"),
        TypingCase("ㄱㅡㆍㆍㅣㅣ", "궤", "ㅝ+ㅣ = ㅞ"),
        TypingCase("ㄱㆍㅡㅣㆍㅇㅇ", "괌", "복모음 진행 뒤 받침 (ㅇㅇ 순환 = ㅁ)")
    ])
    func cheonjiinCompoundVowels(testCase: TypingCase) {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("cheonjiin 자음 순환", arguments: [
        TypingCase("ㄱㄱ", "ㅋ", "2연타 = ㅋ"),
        TypingCase("ㄱㄱㄱ", "ㄲ", "3연타 = ㄲ"),
        TypingCase("ㄱㄱㄱㄱ", "ㄱ", "4연타 = 순환 복귀"),
        TypingCase("ㄴㄴ", "ㄹ", "ㄴ→ㄹ"),
        TypingCase("ㅅㅅ", "ㅎ", "ㅅ→ㅎ"),
        TypingCase("ㅅㅅㅅ", "ㅆ", "ㅅ→ㅎ→ㅆ"),
        TypingCase("ㅇㅇ", "ㅁ", "ㅇ→ㅁ"),
        TypingCase("ㄱㅣㆍㄱㄱ", "갘", "홑받침 순환 교체"),
        TypingCase("ㅇㅣㆍㅇㅇ", "암", "받침 ㅇ→ㅁ"),
        TypingCase("ㄷㅣㆍㄴㄴㄱ", "닭", "달(ㄴ순환) + ㄱ = 겹받침"),
        TypingCase("ㄷㅣㆍㄴㄴㄱㄱ", "달ㅋ", "겹받침 뒤 성분만 순환 — 결합 불가면 다음 글자로"),
        TypingCase("ㄷㅣㆍㆍㄷㄷㄷ", "댜ㄸ", "ㄸ은 받침 불가 — 다음 글자 초성으로"),
        TypingCase("ㄱㅣㄱㅣ", "기기", "모음이 끼면 순환이 아니다")
    ])
    func cheonjiinConsonantCycle(testCase: TypingCase) {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("cheonjiin 타임아웃 — 같은 자음도 시간이 지나면 별개 자모")
    func cheonjiinTimeout() {
        var harness = TypingHarness(source: CheonjiinSource(timeout: 0.8))
        harness.press("ㄱ", at: 0)
        harness.press("ㄱ", at: 1.0)
        #expect(harness.finish() == "ㄱㄱ")

        var annyeong = TypingHarness(source: CheonjiinSource(timeout: 0.8))
        for (key, time) in [("ㅇ", 0.1), ("ㅣ", 0.2), ("ㆍ", 0.3), ("ㄴ", 0.4),
                            ("ㄴ", 1.5), ("ㆍ", 1.6), ("ㆍ", 1.7), ("ㅣ", 1.8), ("ㅇ", 1.9)] {
            annyeong.press(key, at: time)
        }
        #expect(annyeong.finish() == "안녕", "타임아웃으로 ㄴㄴ을 나눠 안녕을 만든다")
    }

    @Test("cheonjiin 이동(→) — 확정 후 같은 자음을 잇는다")
    func cheonjiinAdvance() {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type("ㅅㅅㅣㆍㄱ") // 학: ㅅㅅ = ㅎ
        harness.commitAndReset()
        harness.type("ㄱㆍㆍㅡ") // 교
        #expect(harness.finish() == "학교")
    }

    @Test("cheonjiin ㆍ 표시와 순환")
    func cheonjiinPendingDots() {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type("ㄱㆍ")
        #expect(harness.displayed == "ㄱㆍ", "단일 점은 ㆍ(U+318D)로 표시")
        harness.type("ㆍ")
        // ᆢ(U+11A2)가 아닌 ㆍ 2개인 이유: U+11A2는 결합형 중성이라 직전 완성 음절과
        // 그래핌이 병합되어 글자 수 기반 조합 교체가 확정 텍스트까지 지운다
        #expect(harness.displayed == "ㄱㆍㆍ", "이중 점은 ㆍ 2개로 표시")
        harness.type("ㆍ")
        #expect(harness.displayed == "ㄱㆍ", "3연타는 다시 단일 점 — 실측 순환")
    }

    @Test("cheonjiin pending 확정 — 자음이 오면 점이 리터럴로 남는다")
    func cheonjiinPendingFlush() {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type("ㄱㆍㄴ")
        #expect(harness.finish() == "ㄱㆍㄴ")

        var double = TypingHarness(source: CheonjiinSource())
        double.type("ㄱㆍㆍㄴ")
        #expect(double.finish() == "ㄱㆍㆍㄴ", "이중 점도 그대로 남는다")
    }

    @Test("cheonjiin 도깨비불", arguments: [
        TypingCase("ㄱㅣㆍㄴㅣ", "가니", "받침이 다음 초성으로"),
        TypingCase("ㄱㅣㆍㄴㆍㅣ", "가너", "pending을 거친 모음도 도깨비불")
    ])
    func cheonjiinLinking(testCase: TypingCase) {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("cheonjiin 백스페이스 — 마지막 키 입력 취소 (실측: 키 로그 재생)")
    func cheonjiinBackspace() {
        var harness = TypingHarness(source: CheonjiinSource())
        harness.type("ㄱㆍㅡㅣㆍㅣ") // 괘
        harness.backspace()
        #expect(harness.displayed == "과", "괘 → 과")
        harness.backspace()
        #expect(harness.displayed == "괴", "과 → 괴")
        harness.backspace()
        #expect(harness.displayed == "고", "괴 → 고")
        harness.backspace()
        #expect(harness.displayed == "ㄱㆍ", "고 → ㄱㆍ — pending까지 되돌린다")
        harness.backspace()
        #expect(harness.displayed == "ㄱ")

        var linking = TypingHarness(source: CheonjiinSource())
        linking.type("ㄱㅣㆍㄴㅣ") // 가니
        linking.backspace()
        #expect(linking.displayed == "간", "도깨비불도 역행한다 — 실측")

        var cycle = TypingHarness(source: CheonjiinSource())
        cycle.type("ㄱㅣㆍㄱㄱㄱ") // 가 + ㄱ→ㅋ→ㄲ = 갂
        cycle.backspace()
        #expect(cycle.displayed == "갘", "순환도 한 단계씩 되돌린다")
    }

    // MARK: - 단모음
    //
    // 삼성·Gboard 공통 배열. 쌍자음/이중모음은 연타 승격(2상태 토글), 시프트 없음.
    // 기본 type() 간격 0.1초 < 타임아웃 0.3초.

    @Test("danmoeum 기본과 연타 승격", arguments: [
        TypingCase("ㄱㅏ", "가", "일반 입력은 두벌식과 같다"),
        TypingCase("ㅂㅂㅏ", "빠", "ㅂㅂ = ㅃ"),
        TypingCase("ㄱㅏㅏ", "갸", "ㅏㅏ = ㅑ"),
        TypingCase("ㅇㅐㅐ", "얘", "ㅐㅐ = ㅒ"),
        TypingCase("ㅇㅔㅔ", "예", "ㅔㅔ = ㅖ"),
        TypingCase("ㄱㅗㅗ", "교", "ㅗㅗ = ㅛ"),
        TypingCase("ㄱㅜㅜ", "규", "ㅜㅜ = ㅠ"),
        TypingCase("ㄱㅓㅓ", "겨", "ㅓㅓ = ㅕ"),
        TypingCase("ㄱㅏㅅㅅ", "갔", "받침도 연타 승격"),
        TypingCase("ㄱㄱㄱ", "ㄱ", "3연타는 토글 복귀"),
        TypingCase("ㅋㅋ", "ㅋㅋ", "승격 없는 키 연타는 각각 입력"),
        TypingCase("ㄱㅗㅏ", "과", "복모음 조합은 오토마타 규칙 그대로"),
        TypingCase("ㅇㅏㄴㅣ", "아니", "도깨비불"),
        TypingCase("ㄱㅏㄷㄷㄷ", "가ㄷ", "받침 불가 승격(ㄸ)은 음절을 분리하고, 토글 복귀해도 받침으로 돌아가지 않는다 — 알려진 한계 (PDR 엣지케이스)")
    ])
    func danmoeumBasic(testCase: TypingCase) {
        var harness = TypingHarness(source: DanmoeumSource())
        harness.type(testCase.keys)
        #expect(harness.finish() == testCase.expected, "\(testCase)")
    }

    @Test("danmoeum 타임아웃 — 느린 연타는 승격되지 않는다")
    func danmoeumTimeout() {
        var harness = TypingHarness(source: DanmoeumSource(timeout: 0.3))
        harness.press("ㅏ", at: 0)
        harness.press("ㅏ", at: 0.5)
        #expect(harness.finish() == "ㅏㅏ")

        var annyeong = TypingHarness(source: DanmoeumSource(timeout: 0.3))
        for (key, time) in [("ㅇ", 0.1), ("ㅏ", 0.2), ("ㄴ", 0.3),
                            ("ㄴ", 1.0), ("ㅓ", 1.1), ("ㅓ", 1.2), ("ㅇ", 1.3)] {
            annyeong.press(key, at: time)
        }
        #expect(annyeong.finish() == "안녕", "타임아웃으로 ㄴㄴ을 나누고 ㅓㅓ는 ㅕ로")
    }

    @Test("danmoeum 백스페이스 — 자모 단위 (두벌식과 동일)")
    func danmoeumBackspace() {
        var harness = TypingHarness(source: DanmoeumSource())
        harness.type("ㄱㅏㅏ") // 갸
        harness.backspace()
        #expect(harness.displayed == "ㄱ", "ㅑ가 통째로 지워진다")
        harness.type("ㅏ")
        #expect(harness.displayed == "가", "백스페이스 뒤 연타 상태는 리셋 — 승격되지 않는다")
    }
}
