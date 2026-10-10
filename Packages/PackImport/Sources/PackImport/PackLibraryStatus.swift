/// 외부 채움글 목록(`library.json`, 앱 전용)의 상태 — 1-c 계획서 `external-snippet-packs-1c-plan.md` 2절 G4·4-1 ㉡.
///
/// 읽히지 않는 목록은 **빈 목록으로 보지 않는다**(검증 C1, PDR 9-3) — 그동안 모든 커밋이 `libraryUnreadable`로 막힌다(내 채움글
/// 저장·삭제·내장 토글까지). 키보드는 영향이 없다(마지막 snapshot과 내 채움글을 따로 읽는다). 빠져나가는 길은 복구(R24)다.
public enum PackLibraryStatus: Equatable, Sendable {
    /// 읽힌다 — 파일이 아예 없는 처음 상태도 여기다(빈 목록)
    case readable
    /// 파일은 있는데 열 수 없다(권한·입출력)
    case unreadable
    /// 열리는데 내용이 망가졌다(JSON·모양)
    case corrupt
    /// 이 앱이 모르는 schema — 새 버전의 글쇠가 쓴 목록(설치했다 되돌린 경우)
    case unknownSchema
    /// 목록 파일이 **없는데** 가져온 팩 파일이나 복구 보관본이 남아 있다 — 복구 도중 앱이 끝났거나 목록만 사라졌다(codex 반론 #1).
    /// 처음 상태(빈 목록)로 보면 정리가 팩 파일을 모두 지우므로 복구가 필요한 상태로 본다
    case missing

    /// 복구(R24)가 필요한가 — 읽히지 않는 셋
    public var needsRecovery: Bool { self != .readable }
}

/// 목록 복구(R24 — 변환본에서 목록 다시 만들기)의 결과
public enum PackLibraryRecovery: Equatable, Sendable {
    /// 다시 만들었다 — 찾은 팩 수(읽을 수 없는 팩 포함, 모두 꺼짐), 그중 변환본을 읽을 수 없는 팩 수, 원래 목록의 보관본 이름
    /// (목록 파일이 없던 `.missing`이면 보관할 것이 없어 nil)
    case recovered(packs: Int, unreadable: Int, backupFileName: String?)
    /// 목록이 읽힌다 — 아무것도 하지 않았다
    case notNeeded
    /// 원래 목록의 보관본을 만들지 못했거나 새 목록·snapshot을 쓰지 못했다 — **원래 목록은 제자리에 그대로다**
    case failed
}
