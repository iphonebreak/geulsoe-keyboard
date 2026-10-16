import Foundation
import Testing
@testable import TadakData

/// B5 C9 — `BundledWordDictionary(resource:)`(공개 init)로 영어 사전을 연다. 내용 단언은 1단계 E12·E17(`EnglishDictionaryBundleTests`)
@Suite("B5 C9 — 리소스 이름으로 사전 열기")
struct EnglishDictionaryResourceTests {

    @Test("words-en을 열면 hel → hello, 없는 이름은 빈 사전, 기본 init은 한글 그대로")
    func resourceInit() {
        #expect(BundledWordDictionary(resource: "words-en").candidates(jamoPrefix: "hel", limit: 3).map(\.word).contains("hello"))
        #expect(BundledWordDictionary(resource: "no-such-dictionary").candidates(jamoPrefix: "hel", limit: 3).isEmpty)
        #expect(BundledWordDictionary().candidates(jamoPrefix: "hel", limit: 3).isEmpty, "한글 사전 — 자모 키라 영어 접두에 없다")
    }
}
