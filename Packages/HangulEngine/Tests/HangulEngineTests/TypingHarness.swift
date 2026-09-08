import Foundation
@testable import HangulEngine

/// 키 시퀀스를 실제 키보드와 같은 순서로 흘려 최종 문서 내용을 얻는다.
///
/// 실제 익스텐션에서도 이 흐름을 그대로 쓴다:
/// `JamoSource.accept` → `HangulAutomaton.input`/`replaceLast` → 문서 반영.
/// 백스페이스도 InputController와 같은 규칙이다 — 키 재생 자판(천지인)은 키 로그를
/// 하나 빼고 처음부터 재생하고, 나머지는 오토마타 자모 삭제를 쓴다.
/// 테스트가 실제 경로와 어긋나면 통과해도 의미가 없으므로 같은 순서를 유지한다.
struct TypingHarness {

    private(set) var document = ""
    private var automaton = HangulAutomaton()
    private let source: JamoSource
    private var clock: TimeInterval = 0

    /// 백스페이스 재생용 키 로그. 확정 시점(공백·리셋)마다 비운다.
    private var keystrokes: [(key: String, time: TimeInterval)] = []
    /// 로그 시작 이후 document에 더해진 글자 수 — 재생 시 걷어낼 범위
    private var runCommittedCount = 0

    init(source: JamoSource) {
        self.source = source
    }

    /// 조합 중인 글자와 pending 문자(천지인 ㆍ)까지 포함한 화면 표시 상태
    var displayed: String {
        document + automaton.composingText + source.pendingText
    }

    /// 키를 하나씩 누른다. 자판별 키 식별자는 문자 하나로 표현한다.
    mutating func type(_ keys: String, interval: TimeInterval = 0.1) {
        for key in keys {
            clock += interval
            press(String(key))
        }
    }

    /// 키 하나를 누른다. 타임아웃 테스트는 timestamp를 직접 지정한다.
    mutating func press(_ key: String, at timestamp: TimeInterval? = nil) {
        if let timestamp { clock = timestamp }
        let events = source.accept(key: key, at: clock)

        guard !events.isEmpty else {
            // 자모가 아닌 키 — 조합을 끝내고 그대로 문서에 넣는다
            document += automaton.commit().committed + source.pendingText + key
            source.reset()
            keystrokes.removeAll()
            runCommittedCount = 0
            return
        }

        if source.prefersKeystrokeReplayBackspace {
            keystrokes.append((key, clock))
        }
        applyEvents(events)
    }

    private mutating func applyEvents(_ events: [JamoEvent]) {
        for event in events {
            switch event {
            case .emit(let jamo):
                append(automaton.input(jamo).committed)
            case .replaceLast(let jamo):
                append(automaton.replaceLast(jamo).committed)
            case .pendingChanged:
                break // 표시만 바뀐다 — document에는 확정된 것이 없다
            }
        }
    }

    private mutating func append(_ committed: String) {
        document += committed
        runCommittedCount += committed.count
    }

    mutating func backspace() {
        if source.prefersKeystrokeReplayBackspace, !keystrokes.isEmpty {
            // 마지막 키 입력 취소 — 리셋 후 재생 (InputController와 동일)
            keystrokes.removeLast()
            document.removeLast(runCommittedCount)
            runCommittedCount = 0
            automaton = HangulAutomaton()
            source.reset()
            let log = keystrokes
            keystrokes.removeAll()
            for entry in log {
                keystrokes.append(entry)
                applyEvents(source.accept(key: entry.key, at: entry.time))
            }
            return
        }
        let output = automaton.backspace()
        append(output.committed)
        if output.deletesBackward, !document.isEmpty {
            document.removeLast()
        }
        source.reset()
    }

    /// 커서 이동·자판 전환·이동(→) 키가 하는 일. 조합을 확정하고 자판 상태를 비운다.
    /// pending 문자는 리터럴로 남는다 (문서에 이미 표시된 것을 지우지 않는다).
    mutating func commitAndReset() {
        document += automaton.commit().committed + source.pendingText
        source.reset()
        keystrokes.removeAll()
        runCommittedCount = 0
    }

    /// 조합까지 확정한 최종 문서 내용
    mutating func finish() -> String {
        commitAndReset()
        return document
    }
}

/// 테이블 테스트 한 줄
struct TypingCase: Sendable, CustomStringConvertible {
    let keys: String
    let expected: String
    let note: String

    init(_ keys: String, _ expected: String, _ note: String) {
        self.keys = keys
        self.expected = expected
        self.note = note
    }

    var description: String { "\(note): \"\(keys)\" → \(expected)" }
}
