import Foundation

/// ✕·탭으로 소비한 클립보드 — 같은 클립보드의 칩을 다시 띄우지 않으려고 둔다(2026-11-25).
///
/// **번호만으로는 모자란다(2026-11-25 실측).** 유니버설 클립보드는 같은 글을 **새 번호로** 다시 보낸다 — 맥 클립보드 번호를
/// 기록해 보니 아이폰 복사가 맥으로 넘어간 지 8초 만에 맥이 예전 항목으로 되돌아갔고, 그 항목이 아이폰으로 다시 넘어와
/// ✕로 내린 칩이 「맥북에서 붙여넣기함」 알림과 함께 또 떴다. 그래서 내용의 **지문**을 함께 둔다.
///
/// 담는 것은 번호와 지문(기기 열쇠를 섞은 비암호 해시 16바이트 — KeyboardCore `PasteboardFingerprint`)뿐이다. 클립보드 원문·길이는 담지 않는다
/// (`.claude/rules/security.md` 클립보드 절 — 사장님 결정 2026-11-25).
public struct PasteboardConsumption: Equatable, Sendable {
    /// 소비할 때의 `UIPasteboard.changeCount`. 재부팅으로 번호가 다시 세어진 뒤에는 nil(지문만 남는다)
    public let changeCount: Int?
    /// 소비한 글의 지문. 번호만 저장하던 빌드(`218c612`)가 남긴 기록이면 nil
    public let fingerprint: Data?

    public init(changeCount: Int?, fingerprint: Data?) {
        self.changeCount = changeCount
        self.fingerprint = fingerprint
    }
}

/// 소비 기록 저장소 — 구현은 TadakData(`KeyboardOwnPasteboardConsumptionStore`, 키보드 전용 컨테이너). 조립 지점만 안다.
public protocol PasteboardConsumptionStore: Sendable {
    /// 없거나 읽지 못하면 nil
    func load() -> PasteboardConsumption?
    /// nil이면 지운다. 기록은 늘 **마지막 하나**만 덮어쓴다
    func save(_ consumption: PasteboardConsumption?)
    /// 지문 열쇠(32바이트) — 없으면 무작위로 만들어 저장한 뒤 돌려준다. 기기 밖으로 나가지 않는다
    func fingerprintKey() -> Data
}
