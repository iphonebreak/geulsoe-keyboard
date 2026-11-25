import Foundation

/// ⌫ 단어 단계의 문맥 신선성 판정(PDR `docs/design-reviews/backspace-word-acceleration.md` 3-3).
///
/// 사슬 S = (직전 문맥, 직전에 지운 글자 수 k). `신선(C)` ⇔ ① C가 「직전 문맥에서 k자 뺀 것」(끝 64자)으로 끝난다
/// ∧ ② k = 0이거나 C가 직전 문맥과 다르다(지웠는데 그대로면 호스트가 아직 반영하지 않은 낡은 값).
/// 불일치 수는 **누름 단위로 누적**한다 — 성공해도 되돌리지 않는다(반론 CW-01: 되돌리면 「두 번 틀리면 끔」에 영영 닿지 않는 호스트가 있다).
///
/// 문맥은 메모리에서 비교만 한다 — 로그·파일·네트워크로 내보내지 않는다(보안 규칙). 누름이 끝나면 버린다.
struct BackspaceFreshness: Equatable, Sendable {

    /// 기대 문맥과 비교하는 끝 길이 — 계획이 보는 길이(≤ 48자 + 앞 1자)보다 길다
    static let comparedSuffixLength = 64
    /// 한 누름에서 이 횟수만큼 어긋나면 단어 단계를 끈다
    static let mismatchLimit = 2

    private var previous: String?
    private var deleted = 0
    /// 사슬이 **단어 단계 삭제**에서 왔나 — 그 바로 뒤 박자가 어긋나면 이 누름의 단어 단계를 끈다(검증 반영 A)
    private(set) var chainFromWordStep = false
    /// 이 누름의 불일치 수 — 누적
    private(set) var mismatches = 0

    var hasChain: Bool { previous != nil }

    /// 닻 — 읽기만 하고 지우지 않았다(k = 0)
    mutating func anchor(_ context: String) {
        previous = context
        deleted = 0
        chainFromWordStep = false
    }

    /// 읽은 문맥에서 `deleted`자를 지웠다 — `wordStep`이면 단어 단계 삭제
    mutating func record(context: String, deleted: Int, wordStep: Bool = false) {
        previous = context
        self.deleted = deleted
        chainFromWordStep = wordStep
    }

    /// 사슬을 버린다(S = ∅) — 불일치 수는 그대로다
    mutating func clearChain() {
        previous = nil
        deleted = 0
        chainFromWordStep = false
    }

    /// 기대 문맥 E가 비면(보이는 문맥을 끝까지 지움) 조건 1은 공허하다 — 그때는 조건 2만 남는다(PDR 3-3 한계)
    func isFresh(_ context: String) -> Bool {
        guard let previous else { return false }
        let expected = previous.dropLast(deleted)
        let tail = expected.suffix(Self.comparedSuffixLength)
        guard context.hasSuffix(String(tail)) else { return false }
        return deleted == 0 || context != previous
    }

    /// 불일치 1회 — 한도에 닿으면 true(이 누름의 단어 단계를 끈다)
    mutating func noteMismatch() -> Bool {
        mismatches += 1
        return mismatches >= Self.mismatchLimit
    }
}

/// 누름 세대 게이트 — 손을 뗀 뒤 큐에 남은 반복 박자를 막는다(PDR 3-4).
///
/// 끝냄은 KeyboardUI가 **동기로** 부른다(손 뗌·터치 잃음 `onChange`·사라짐). 이미 `main.async`로 큐에 들어간 박자도
/// 실행 직전에 `accepts`를 보므로 0건이 된다. `end(H)`는 지금 살아 있는 H와 같을 때만 끝낸다 — 빠른 재누름에서
/// 옛 터치의 늦은 끝냄이 새 누름을 끝내지 않는다.
struct BackspaceHoldGate: Equatable, Sendable {
    private(set) var live: UInt64?

    mutating func begin(_ hold: UInt64) {
        live = hold
    }

    mutating func end(_ hold: UInt64) {
        if live == hold { live = nil }
    }

    mutating func endAll() {
        live = nil
    }

    func accepts(_ hold: UInt64) -> Bool {
        live == hold
    }
}

/// 누름 하나의 단어 단계 상태 — 터치다운 때 생기고 누름이 끝나면 버린다
struct BackspaceHoldSession: Equatable, Sendable {
    /// 터치다운 때 VC가 읽은 `documentIdentifier` — 바뀌면 이 누름의 단어 단계만 끈다(CW-05). 내용 신선성의 증거로 쓰지 않는다
    let documentIdentifier: UUID?
    var freshness = BackspaceFreshness()
    /// 이 누름에서 단어 단계를 더 쓰지 않는다 — 이후 단어 박자는 폴백 4자(글자 단계 속도)
    var wordPhaseOff = false
}
