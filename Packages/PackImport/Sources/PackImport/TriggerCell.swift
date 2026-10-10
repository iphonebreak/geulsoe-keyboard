import Foundation
import TadakDomain

/// 단축어 셀 파서 — **한 곳**(PDR `external-snippet-packs.md` 5-4).
///
/// 쉼표 **또는 LF**로 나누고 → trim → 빈 것 제거 → `SnippetEntry.normalizedTrigger` 기준 중복 제거(먼저 나온 원문을 남긴다)
/// → 항목당 10개·단축어 40자(원문). 바깥 구분자가 탭·`;`여도 셀 안 구분은 쉼표·개행이다.
///
/// 앱 편집기의 `SnippetEntry.parseTriggers`(쉼표만)는 **바꾸지 않는다** — CSV 쪽에서만 개행을 받고, 결과에 개행이 남지
/// 않음을 보장한다(v2는 `주소\n인사`가 한 단축어가 되어 정규화로 `주소인사`로 합쳐졌다). 셀은 문자 정리(11절) 뒤에 넣는다 —
/// 정리가 CR·U+2028을 LF로 바꾼 뒤라 여기서는 LF만 본다.
public enum TriggerCell {

    public enum Failure: Error, Equatable, Sendable {
        /// 나눈 뒤 남는 단축어가 없다
        case empty
        /// `PackLimits.triggersPerEntry`(10) 초과
        case tooMany
        /// 단축어 하나가 `PackLimits.trigger`(40자·160B·120 scalar) 초과
        case tooLong
    }

    public static func parse(_ cell: String) -> Result<[String], Failure> {
        var seen = Set<String>()
        var triggers: [String] = []
        for piece in cell.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            let trigger = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            // 공백만으로 된 단축어는 위에서 걸렀다 — 정규화가 빈 값이 되는 일은 없다
            guard seen.insert(SnippetEntry.normalizedTrigger(trigger)).inserted else { continue }
            guard PackLimits.trigger.admits(trigger) else { return .failure(.tooLong) }
            triggers.append(trigger)
        }
        guard !triggers.isEmpty else { return .failure(.empty) }
        guard triggers.count <= PackLimits.triggersPerEntry else { return .failure(.tooMany) }
        return .success(triggers)
    }
}
