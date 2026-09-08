import Foundation

/// 추천단어 후보. `frequency`는 출처 내 상대 빈도 — 출처가 다른 후보끼리는 비교하지 않는다
/// (사용자 단어가 사전보다 항상 우선한다는 랭킹 규칙은 SuggestionEngine에 있다).
public struct WordCandidate: Equatable, Sendable {
    public let word: String
    public let frequency: UInt32

    public init(word: String, frequency: UInt32) {
        self.word = word
        self.frequency = frequency
    }
}

/// 내장 사전 경계. 키는 **평탄한 호환 자모 시퀀스**다 ("안녕핫" → "ㅇㅏㄴㄴㅕㅇㅎㅏㅅ") —
/// 조합 중간 상태까지 접두 매칭하기 위한 설계 (PDR word-suggestions 참조).
/// 자모 분해는 호출자(KeyboardCore) 책임이고, 구현은 바이트 비교만 한다.
public protocol WordDictionary: Sendable {
    /// 자모 접두로 시작하는 후보를 빈도 내림차순으로 최대 `limit`개. 실패하지 않는다.
    func candidates(jamoPrefix: String, limit: Int) -> [WordCandidate]
}

/// 사용자 학습 단어 저장 경계.
///
/// **주의 — 이 데이터만 예외적으로 키보드가 쓴다.** App Group 쓰기는 Full Access가
/// 있어야만 실제로 지속되므로, 권한이 없으면 저장이 조용히 무시되고 세션 메모리 학습만
/// 남는다. 읽기는 권한 무관. 학습 데이터는 기기 밖으로 나가지 않는다 (보안 규칙).
public protocol UserWordRepository: Sendable {
    /// 단어 → 사용 횟수. 접근 불가·데이터 없음이면 빈 딕셔너리.
    func load() -> [String: Int]
    /// 저장을 시도한다. **쓰기 실패(Full Access 없음)는 감지되지 않을 수 있다** —
    /// `UserDefaults`는 실패를 보고하지 않으므로 반환값 `true`가 지속을 보장하지 않는다.
    @discardableResult
    func save(_ counts: [String: Int]) -> Bool
}
