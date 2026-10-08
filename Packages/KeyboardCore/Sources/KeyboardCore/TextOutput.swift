/// 문서에 쓰는 최소 인터페이스.
///
/// `UITextDocumentProxy`를 이 뒤에 숨겨 `KeyboardCore`가 UIKit을 모르게 한다.
/// 테스트에서는 기록형 fake로 대체해 delete/insert 시퀀스를 그대로 검증한다.
///
/// 키 이벤트는 메인 스레드에서만 발생하므로 MainActor 격리다.
@MainActor
public protocol TextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward(_ count: Int)
    /// 호스트 문서에 선택 영역이 있나(K4 — `ReplacementGate.allowsReplacement`). **유무만** 낸다 — 선택한 글자는 넘기지 않는다.
    /// 쓰기는 아니지만 치환(지우고 넣기)이 안전한지가 이 값에 달려 있어 쓰기 인터페이스 옆에 둔다. 기본은 없음(시험 fake)
    var hasSelectedText: Bool { get }
}

public extension TextOutput {
    var hasSelectedText: Bool { false }
}
