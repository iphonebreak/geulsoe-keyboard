import Foundation

/// 자판 하나를 나타낸다. **자판별 차이는 전부 여기에서만 발생한다.**
///
/// 두벌식은 키 하나가 자모 하나로 바로 매핑되지만, 천지인·단모음은 이전 키와
/// 타이밍에 따라 결과가 달라지므로 내부 상태를 가진다. 그 상태 때문에 `reset()`이
/// 프로토콜에 있다 — 커서 이동, 앱 전환, 툴바 도구 사용, 자판 전환 시 반드시 호출한다.
/// 호출을 빠뜨리면 "ㄱ을 눌렀는데 ㅋ이 나오는" 버그가 된다.
public protocol JamoSource: AnyObject {

    /// 자판 식별자 (`dubeolsik`, `cheonjiin`, `danmoeum`)
    var identifier: String { get }

    /// 키 입력 하나를 자모 이벤트로 변환한다.
    /// - Parameters:
    ///   - key: 자판 고유 키 식별자
    ///   - timestamp: 입력 시각. 토글 타임아웃 판정에 쓰는 자판이 있다.
    /// - Returns: 이번 입력으로 발생한 자모 이벤트. **빈 배열 = 자모가 아닌 키**
    ///   (호출자가 조합을 끝내고 그대로 입력한다). 상태만 바뀌었으면 `.pendingChanged`를 낸다.
    func accept(key: String, at timestamp: TimeInterval) -> [JamoEvent]

    /// 내부 상태를 초기화한다.
    func reset()

    /// 아직 자모로 확정되지 않았지만 화면에 보여야 하는 문자 (천지인의 `ㆍ`/`ᆢ`).
    /// 조합 중 글자 **뒤에** 붙여 표시한다. 상태가 없는 자판은 항상 빈 문자열.
    var pendingText: String { get }

    /// 백스페이스를 "마지막 키 입력 취소"로 처리할 자판인가.
    /// 참이면 호출자가 키 로그를 유지하고 백스페이스 시 리셋 후 재생한다 (천지인).
    /// 거짓이면 오토마타의 자모 단위 삭제를 쓴다 (두벌식·단모음).
    var prefersKeystrokeReplayBackspace: Bool { get }

    /// 조합 중 스페이스를 "이동"(확정만, 공백 없음)으로 처리할 자판인가 — Apple 10키 원형 동작.
    /// 참이면 호출자가 조합 중 스페이스에서 공백을 넣지 않고 조합만 확정한다 (천지인 — 같은 자음을
    /// 순환 없이 이어 칠 때 →(이동) 키 대신 스페이스를 쓴다, 2026-09-07). 조합이 없으면 공백.
    var spaceAdvancesWhileComposing: Bool { get }
}

public extension JamoSource {
    var pendingText: String { "" }
    var prefersKeystrokeReplayBackspace: Bool { false }
    var spaceAdvancesWhileComposing: Bool { false }
}

/// `JamoSource`가 내보내는 이벤트.
///
/// 천지인처럼 이미 낸 자모를 되돌려 다른 자모로 바꾸는 자판이 있어서,
/// 단순히 "자모를 추가한다"만으로는 표현되지 않는다.
public enum JamoEvent: Equatable, Sendable {
    /// 새 자모를 흘려보낸다
    case emit(Jamo)
    /// 직전에 내보낸 자모를 이 자모로 교체한다 (토글 순환: ㄱ → ㅋ → ㄲ).
    /// 호출자는 `HangulAutomaton.replaceLast(_:)`로 반영한다.
    case replaceLast(Jamo)
    /// 자모는 나오지 않았지만 `pendingText`가 바뀌었다 — 표시만 갱신하면 된다 (천지인 `ㆍ`)
    case pendingChanged
}
