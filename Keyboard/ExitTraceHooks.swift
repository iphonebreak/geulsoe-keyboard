import UIKit
import os
import KeyboardCore
import TadakDomain
import TadakData

// 백로그 14 (가) 키보드 비정상 종료 흔적 — 조립 지점의 플랫폼 쪽(환경·메모리 표본기·메모리 압박 이벤트).
// 판정·기록은 KeyboardCore `ExitTraceRecorder`가 하고, `KeyboardViewController`는 생명주기 지점에서 부르기만 한다.
// PDR `docs/design-reviews/keyboard-crashlytics.md` 2-3·8-2, 보안 규칙 N21. 로그(os_log 포함)·파일·네트워크 없음 —
// `import os`는 `os_proc_available_memory` 하나 때문이다.
//
// `os_proc_available_memory`는 필수 사유 API 다섯 범주(디스크 공간·부팅 시간·파일 시각·활성 키보드·UserDefaults) 어디에도
// 들지 않는다(TN3183, 2026-10-23 Context7 재확인) — 매니페스트 변경 없음. 시계는 `Date`만 쓴다(부팅 시간 범주 회피).

enum ExitTraceHooks {

    /// 키보드 자기 컨테이너 + App Group 발신함(쓰기는 전체 접근이 있을 때만 — 판정기가 그때만 부른다)
    nonisolated static func makeRecorder() -> ExitTraceRecorder {
        ExitTraceRecorder(store: KeyboardOwnExitTraceStore(), outbox: ExitTraceOutboxRepository(),
                          environment: environment(), availableMemory: availableMemory)
    }

    /// pid·빌드 번호(`CFBundleVersion` — CI는 업로드마다 다르고 개발 설치는 늘 같다, PDR 8-3 M5)·OS 3정수
    nonisolated static func environment() -> ExitTraceEnvironment {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String).flatMap(Int.init) ?? 0
        return ExitTraceEnvironment(pid: getpid(), buildNumber: build,
                                    os: ExitTraceOSVersion(major: version.majorVersion, minor: version.minorVersion,
                                                           patch: version.patchVersion))
    }

    /// 이 프로세스가 한도까지 쓸 수 있는 남은 메모리(바이트) — 0(알 수 없음)이면 표본 없음
    nonisolated static func availableMemory() -> UInt64? {
        let bytes = os_proc_available_memory()
        return bytes > 0 ? UInt64(bytes) : nil
    }

    @MainActor
    static func currentIdiom() -> ExitTraceIdiom {
        UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
    }

    /// 화면 폭 — 창이 아직 없으면 0(다음 높이 적용 때 채워진다)
    @MainActor
    static func screenWidth(of view: UIView) -> Double {
        Double(view.window?.windowScene?.screen.bounds.width ?? 0)
    }
}

/// 메모리 압박 `DispatchSource` 하나 — 이벤트 구동(폴링 아님). VC가 `viewDidLoad`에서 시작하고 `deinit`에서 취소한다.
/// 핸들러는 표시를 한 번 갱신할 뿐이다(키 입력 경로 아님).
final class ExitTraceMemoryPressureWatcher: @unchecked Sendable {
    private let lock = NSLock()
    private var source: DispatchSourceMemoryPressure?

    func start(recording recorder: ExitTraceRecorder) {
        lock.withLock {
            guard source == nil else { return }
            let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
            pressure.setEventHandler { [weak pressure] in
                guard let event = pressure?.data else { return }
                recorder.memoryPressure(event.contains(.critical) ? .critical : .warning)
            }
            pressure.resume()
            source = pressure
        }
    }

    func cancel() {
        lock.withLock {
            source?.cancel()
            source = nil
        }
    }
}
