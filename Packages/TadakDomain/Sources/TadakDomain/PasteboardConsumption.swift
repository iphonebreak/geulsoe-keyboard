/// ✕·탭으로 소비한 클립보드의 `changeCount` 저장소 — 같은 클립보드의 칩을 다시 띄우지 않으려고 둔다(2026-11-25).
///
/// 담는 것은 **정수 하나**다. 클립보드 내용·해시·길이는 담지 않는다(`.claude/rules/security.md`).
/// 구현은 TadakData(`KeyboardOwnPasteboardConsumptionStore`, 키보드 전용 컨테이너) — 조립 지점만 안다.
public protocol PasteboardConsumptionStore: Sendable {
    /// 없거나 읽지 못하면 nil
    func load() -> Int?
    /// nil이면 지운다
    func save(_ changeCount: Int?)
}
