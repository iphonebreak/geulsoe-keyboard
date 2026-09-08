/// 설정 저장소 경계.
///
/// 키보드 익스텐션은 읽기만 한다. 쓰기는 컨테이너 앱 전용이며, 이 비대칭은
/// App Group의 권한 모델(읽기는 Full Access 불필요, 쓰기는 필요)에서 온다.
public protocol SettingsRepository: Sendable {
    /// 실패하지 않는다 — 접근 불가·데이터 없음이면 기본값을 낸다.
    func load() -> KeyboardSettings
}

/// 테마 저장소 경계.
public protocol ThemeRepository: Sendable {
    func availableThemes() -> [ThemeSpec]
    /// 미지의 id면 `system` 테마로 폴백한다. 실패하지 않는다.
    func theme(id: String) -> ThemeSpec
}
