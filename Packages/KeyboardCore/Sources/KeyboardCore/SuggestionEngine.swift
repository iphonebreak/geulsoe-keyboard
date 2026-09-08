import Foundation
import HangulEngine
import TadakDomain

/// 음절 문자열 → 평탄한 호환 자모 시퀀스.
///
/// 사전(`words.tdw`)의 키와 같은 규칙이어야 한다 — 겹받침·조합 복모음은 분해하고
/// ㅑㅕㅛㅠ 등 원자 모음은 그대로 둔다. Python 변환기(`tools/convert_words.py`)가
/// 이 규칙을 복제하며, 불일치는 TadakData의 실리소스 조회 테스트가 잡는다.
public enum JamoDecomposer {

    /// 현대 한글 음절이 아닌 문자가 섞이면 nil (추천 대상이 아니다).
    /// 예외: **맨 끝의 단독 자음 1개**는 그대로 시퀀스에 붙는다 — "안녕ㅎ"(초성만 조합 중)이
    /// "안녕하세요"의 자모 접두로 매칭되게 하기 위해서다.
    public static func decompose(_ text: String) -> String? {
        var out = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            guard let (cho, jung, jong) = HangulSyllable.decompose(character) else {
                if index == characters.count - 1,
                   let scalar = character.unicodeScalars.first,
                   character.unicodeScalars.count == 1,
                   (0x3131...0x314E).contains(scalar.value) {
                    out.append(character)
                    return out
                }
                return nil
            }
            out.append(HangulSyllable.choseongTable[cho])
            if let (first, second) = HangulSyllable.splitJungseong(jung) {
                out.append(HangulSyllable.jungseongTable[first])
                out.append(HangulSyllable.jungseongTable[second])
            } else {
                out.append(HangulSyllable.jungseongTable[jung])
            }
            if jong != 0 {
                if let (first, second) = HangulSyllable.splitJongseong(jong) {
                    // 겹받침 테이블의 인덱스는 항상 유효한 종성이다
                    out.append(HangulSyllable.jongseongTable[first]!)
                    out.append(HangulSyllable.jongseongTable[second]!)
                } else {
                    out.append(HangulSyllable.jongseongTable[jong]!)
                }
            }
        }
        return out
    }
}

/// 입력 중인 단어의 완성 후보를 고른다.
///
/// 랭킹: 접두 일치하는 **사용자 학습 단어(카운트 순) > 내장 사전(빈도 순)**. 입력 중인
/// 단어와 동일한 후보는 뺀다. 학습 데이터는 App Group에 저장을 시도하되, 쓰기는
/// Full Access가 있어야 성공한다 — 실패하면 세션 메모리 학습으로 조용히 동작한다 (PDR).
@MainActor
public final class SuggestionEngine {

    private let dictionary: (any WordDictionary)?
    private let userWordRepository: (any UserWordRepository)?
    private let userWordLimit: Int
    private var userWords: [String: Int]
    /// 단어 → 자모 키. 매 키 입력마다 사용자 단어 전체를 재분해하지 않기 위한 캐시.
    private var userJamoKeys: [String: String] = [:]

    public init(
        dictionary: (any WordDictionary)?,
        userWordRepository: (any UserWordRepository)? = nil,
        userWordLimit: Int = 400
    ) {
        self.dictionary = dictionary
        self.userWordRepository = userWordRepository
        self.userWordLimit = userWordLimit

        var loaded = userWordRepository?.load() ?? [:]
        // 저장분이 상한을 넘어 있을 수 있다 (상한 하향, 외부 쓰기) — learn의 "호출당 1개
        // 제거"는 이 경우를 수렴시키지 못하므로 로드 시점에 상한으로 자른다
        if loaded.count > userWordLimit {
            loaded = Dictionary(uniqueKeysWithValues:
                loaded.sorted { $0.value > $1.value }.prefix(userWordLimit)
                    .map { ($0.key, $0.value) })
        }
        self.userWords = loaded
        for word in loaded.keys {
            userJamoKeys[word] = JamoDecomposer.decompose(word)
        }
    }

    /// 입력 중인 단어(마지막 한글 run, 조합 중 음절 포함)에 대한 후보. 최대 `limit`개.
    public func suggestions(forWord word: String, limit: Int = 3) -> [String] {
        guard limit > 0, !word.isEmpty, let jamo = JamoDecomposer.decompose(word)
        else { return [] }

        var results: [String] = []

        let userHits = userWords
            .filter { entry in
                entry.key != word && (userJamoKeys[entry.key]?.hasPrefix(jamo) ?? false)
            }
            .sorted { $0.value > $1.value }
            .map(\.key)
        results.append(contentsOf: userHits.prefix(limit))

        if results.count < limit, let dictionary {
            // 자기 자신·사용자 단어와의 중복 제거 몫까지 여유 있게 받는다
            for candidate in dictionary.candidates(jamoPrefix: jamo, limit: limit + 2) {
                if results.count >= limit { break }
                if candidate.word != word, !results.contains(candidate.word) {
                    results.append(candidate.word)
                }
            }
        }
        return results
    }

    /// 확정된 단어를 학습한다. **완성 음절 2자 이상만** — "안녕ㅎ"처럼 조합 중 자음이
    /// 낀 run은 단어가 아니다. 저장 실패는 정상 경로 — 세션 학습으로 남는다.
    public func learn(word: String) {
        guard word.count >= 2,
              word.allSatisfy({ HangulSyllable.decompose($0) != nil }) else { return }
        userWords[word, default: 0] += 1
        userJamoKeys[word] = JamoDecomposer.decompose(word)
        if userWords.count > userWordLimit {
            // 카운트 하위부터 버린다 — init에서 트림하므로 호출당 최대 1개 초과다
            if let lowest = userWords.min(by: { $0.value < $1.value }) {
                userWords.removeValue(forKey: lowest.key)
                userJamoKeys.removeValue(forKey: lowest.key)
            }
        }
        userWordRepository?.save(userWords)
    }
}
