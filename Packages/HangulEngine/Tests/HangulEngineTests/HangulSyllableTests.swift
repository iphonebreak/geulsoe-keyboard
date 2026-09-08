import Testing
@testable import HangulEngine

@Suite("음절 조합/분해")
struct HangulSyllableTests {

    @Test("초성 + 중성으로 받침 없는 음절을 만든다")
    func composeWithoutJongseong() {
        // 가 = ㄱ(0) + ㅏ(0)
        #expect(HangulSyllable.compose(choseong: 0, jungseong: 0) == "가")
        // 힣 직전: 히 = ㅎ(18) + ㅣ(20)
        #expect(HangulSyllable.compose(choseong: 18, jungseong: 20) == "히")
    }

    @Test("종성까지 합쳐 음절을 만든다")
    func composeWithJongseong() {
        // 간 = ㄱ(0) + ㅏ(0) + ㄴ(4)
        #expect(HangulSyllable.compose(choseong: 0, jungseong: 0, jongseong: 4) == "간")
        // 힣 = ㅎ(18) + ㅣ(20) + ㅎ(27) — 완성형 마지막 음절
        #expect(HangulSyllable.compose(choseong: 18, jungseong: 20, jongseong: 27) == "힣")
    }

    @Test("표 범위를 벗어난 인덱스는 nil을 낸다")
    func composeOutOfRange() {
        #expect(HangulSyllable.compose(choseong: 19, jungseong: 0) == nil)
        #expect(HangulSyllable.compose(choseong: 0, jungseong: 21) == nil)
        #expect(HangulSyllable.compose(choseong: 0, jungseong: 0, jongseong: 28) == nil)
        #expect(HangulSyllable.compose(choseong: -1, jungseong: 0) == nil)
    }

    @Test("완성형 음절을 자모 인덱스로 되돌린다")
    func decomposeSyllable() {
        let ga = HangulSyllable.decompose("가")
        #expect(ga?.choseong == 0)
        #expect(ga?.jungseong == 0)
        #expect(ga?.jongseong == 0)

        let gan = HangulSyllable.decompose("간")
        #expect(gan?.jongseong == 4)

        let hih = HangulSyllable.decompose("힣")
        #expect(hih?.choseong == 18)
        #expect(hih?.jungseong == 20)
        #expect(hih?.jongseong == 27)
    }

    @Test("완성형이 아니면 분해하지 않는다")
    func decomposeNonSyllable() {
        #expect(HangulSyllable.decompose("ㄱ") == nil)   // 호환 자모
        #expect(HangulSyllable.decompose("A") == nil)
        // 조합형 한글(U+1100 U+1161 U+11A8)은 Character 하나지만 완성형이 아니다
        let conjoining: Character = "\u{1100}\u{1161}\u{11A8}"
        #expect(HangulSyllable.decompose(conjoining) == nil)
    }

    @Test("조합과 분해는 서로의 역이다", arguments: [0, 5, 11, 18])
    func composeDecomposeRoundTrip(choseong: Int) {
        for jungseong in HangulSyllable.jungseongTable.indices {
            for jongseong in HangulSyllable.jongseongTable.indices {
                guard let syllable = HangulSyllable.compose(
                    choseong: choseong, jungseong: jungseong, jongseong: jongseong
                ) else {
                    Issue.record("조합 실패: \(choseong)/\(jungseong)/\(jongseong)")
                    continue
                }
                let back = HangulSyllable.decompose(syllable)
                #expect(back?.choseong == choseong)
                #expect(back?.jungseong == jungseong)
                #expect(back?.jongseong == jongseong)
            }
        }
    }
}

@Suite("겹받침")
struct CompoundJongseongTests {

    @Test("겹받침을 홑받침 둘로 분해한다")
    func split() {
        // ㄳ(3) = ㄱ(1) + ㅅ(19)
        let gs = HangulSyllable.splitJongseong(3)
        #expect(gs?.first == 1)
        #expect(gs?.second == 19)

        // ㅄ(18) = ㅂ(17) + ㅅ(19)
        let bs = HangulSyllable.splitJongseong(18)
        #expect(bs?.first == 17)
        #expect(bs?.second == 19)
    }

    @Test("홑받침과 종성 없음은 분해되지 않는다")
    func splitSimple() {
        #expect(HangulSyllable.splitJongseong(0) == nil)   // 종성 없음
        #expect(HangulSyllable.splitJongseong(1) == nil)   // ㄱ
        #expect(HangulSyllable.splitJongseong(4) == nil)   // ㄴ
    }

    @Test("홑받침 둘을 겹받침으로 합친다")
    func combine() {
        #expect(HangulSyllable.combineJongseong(1, 19) == 3)    // ㄱ + ㅅ = ㄳ
        #expect(HangulSyllable.combineJongseong(8, 1) == 9)     // ㄹ + ㄱ = ㄺ
        #expect(HangulSyllable.combineJongseong(17, 19) == 18)  // ㅂ + ㅅ = ㅄ
    }

    @Test("겹받침이 되지 않는 조합은 nil을 낸다")
    func combineInvalid() {
        #expect(HangulSyllable.combineJongseong(1, 1) == nil)   // ㄱ + ㄱ
        #expect(HangulSyllable.combineJongseong(4, 4) == nil)   // ㄴ + ㄴ
        #expect(HangulSyllable.combineJongseong(19, 1) == nil)  // ㅅ + ㄱ (순서 반대)
    }

    @Test("분해한 겹받침은 다시 합쳐진다")
    func splitCombineRoundTrip() {
        for index in HangulSyllable.jongseongTable.indices {
            guard let parts = HangulSyllable.splitJongseong(index) else { continue }
            #expect(HangulSyllable.combineJongseong(parts.first, parts.second) == index)
        }
    }
}
