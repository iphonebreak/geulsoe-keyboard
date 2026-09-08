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
}
