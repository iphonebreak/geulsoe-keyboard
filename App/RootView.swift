import SwiftUI
import PackImport
import TadakDomain
import TadakData

/// 설정 앱 루트 — 탭 4개(자판·툴바·화면·정보)로 나눈다 (한 페이지가 길어져 나눔, 2026-09-02).
///
/// 원칙 1: **앱이 쓰고 키보드가 읽는다.** 설정 변경 즉시 `AppGroupSettingsRepository.save`
/// (별도 저장 버튼 없음). 원칙 2: **동작하는 설정만 노출한다** (PDR settings-app).
/// `settings`는 여기 한 곳이 소유하고 각 탭은 Binding으로 받는다 — 저장 지점이 하나다.
struct RootView: View {

    @State private var settings = AppGroupSettingsRepository().load()
    /// 앱 로컬 상태 — App Group이 아니다 (키보드가 읽을 일이 없다)
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    private let repository = AppGroupSettingsRepository()

    /// 「글쇠로 열기」로 받은 잠금 파일(`.gspack`) 가져오기 시트(PDR `external-snippet-packs.md` 12-10 ②)
    @State private var openedPack: PackImportRequest?
    /// 온보딩 중이거나 시트가 이미 떠 있을 때 받은 **마지막 하나** — 온보딩이 끝나거나 시트가 닫히면 이어서 연다
    @State private var queuedPackURL: URL?
    /// 지금 시트가 읽는 파일 — 시트가 닫히면(`finishOpenedPack`) 받은 편지함 사본이면 지운다. `onDismiss` 때는 `openedPack`이 이미 nil이라 따로 둔다
    @State private var presentedPackURL: URL?

    var body: some View {
        TabView {
            KeyboardTab(settings: $settings)
                .tabItem { Label("키보드", systemImage: "keyboard") }
            ToolbarTab(settings: $settings)
                .tabItem { Label("툴바", systemImage: "slider.horizontal.3") }
            AppearanceTab(settings: $settings)
                .tabItem { Label("화면", systemImage: "paintpalette") }
            InfoTab(settings: $settings, onReplayOnboarding: { hasSeenOnboarding = false })
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        // 앱 실행 때 한 번 — 외부 채움글 저장소의 옛 snapshot 세대·안 쓰는 변환본 정리(PDR `external-snippet-packs.md` 8-2, 앱 실행·변경
        // 때만). 사용자 데이터는 지우지 않는다(9-3). **메인 밖에서**(`PackStoreClient`, 1-c G8) — `.task`는 메인 액터라 그대로 부르면
        // `PackStore`의 `queue.sync` 파일 정리 동안 첫 화면이 멈춘다
        .task(priority: .utility) { await PackStoreClient.live.maintain() }
        // 「글쇠로 열기」가 받은 편지함에 남긴 잠금 파일 사본을 쓸어 낸다(12-10 ③, 날짜를 읽지 않는다). PDR은 「앱 시작 시」인데,
        // 차가운 실행에서는 `onOpenURL`이 `.task`보다 늦게 올 수 있어 막 받은 사본을 읽기 전에 지울 수 있다 — 그래서 **앱이 뒤로 갈 때**,
        // 잠금 파일 시트·대기열이 없을 때만 한다(진행 중 사본은 시트가 닫힌 뒤 `finishOpenedPack`이 지운다)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background, openedPack == nil, presentedPackURL == nil, queuedPackURL == nil else { return }
            LockedPackInbox.sweep()
        }
        // 「글쇠로 열기」 — 파일 URL이고 확장자가 `.gspack`일 때만(그 밖의 URL은 무시). 경로·이름은 로그·화면·분석에 남기지 않는다
        // 받자마자 시스템 받은 편지함에서 앱이 쥔 대기 폴더로 옮긴다 — iOS 17 실기는 tmp 받은 편지함 사본을 약 1분 뒤 스스로 지워,
        // 온보딩 중에 받아 기다리던 파일이 「파일을 열 수 없어요」가 됐다(`LockedPackInbox.hold`, 실측 2026-11-08)
        .onOpenURL { url in
            guard url.isFileURL, PackImportFileTypes.isLockedPack(url) else { return }
            openLockedPack(LockedPackInbox.hold(url))
        }
        .sheet(item: $openedPack, onDismiss: finishOpenedPack) { request in
            // 완료(`.completed`)는 루트에서는 따로 할 일이 없다 — 설정 안 목록 강조는 채움글 화면에서 연 시트의 몫이다
            PackImportFlowView(request: request) { _ in }
        }
        .onChange(of: settings) { _, updated in
            repository.save(updated)
            // 떠 있는 키보드가 즉시 다시 읽도록 (Darwin 알림, PDR field-traits-and-live-settings)
            SettingsChangeNotifier.post()
        }
        // 활성화될 때마다 — 키보드 종료 흔적(백로그 14 (가), PDR `keyboard-crashlytics.md` 2-8). ① 이전 버전에서 끈 이용 분석 선택을
        // 키보드 설정에 전달한다(값이 같으면 변화 없음 → 위 `onChange`가 저장·알림을 한 곳에서 한다) ② 발신함을 보낸다(건별 ack)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            settings = settings.withExitTraceEnabled(ExitTraceConsentSync.analyticsEnabled)
            KeyboardExitReporter.report(analyticsEnabled: ExitTraceConsentSync.analyticsEnabled)
        }
        // 온보딩 중에 받은 잠금 파일은 덮개가 **다 닫힌 뒤** 연다 — 닫히는 중에 시트를 띄우면 시트 화면이 사라졌다 다시 생긴다(실측)
        .fullScreenCover(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { hasSeenOnboarding = !$0 }
        ), onDismiss: openQueuedPack) {
            OnboardingView { hasSeenOnboarding = true }
        }
    }
}

extension RootView {

    /// 곧바로 가져오기 시트를 띄운다(Q7 권고). 온보딩이 떠 있거나 시트가 이미 있으면 마지막 하나만 보관한다 — 밀려난 사본은 지운다
    private func openLockedPack(_ url: URL) {
        if hasSeenOnboarding, openedPack == nil {
            present(url)
            return
        }
        if let replaced = queuedPackURL, replaced != url { LockedPackInbox.discard(replaced) }
        queuedPackURL = url
    }

    private func openQueuedPack() {
        guard hasSeenOnboarding, openedPack == nil, let url = queuedPackURL else { return }
        queuedPackURL = nil
        present(url)
    }

    private func present(_ url: URL) {
        presentedPackURL = url
        openedPack = PackImportRequest(origin: .file(url), canPickAnother: false)
    }

    /// 시트가 닫힌 뒤 — 방금 닫힌 시트가 읽던 받은 편지함 사본을 지우고(12-10 ③, 받은 편지함 밖은 건드리지 않는다) 기다리던 파일을 연다.
    /// `onDismiss`는 닫힌 **뒤** 한 번이라 시트 화면이 다시 그려져도 읽기 전에 지우는 일이 없다
    private func finishOpenedPack() {
        if let url = presentedPackURL { LockedPackInbox.discard(url) }
        presentedPackURL = nil
        openQueuedPack()
    }
}

#Preview {
    RootView()
}
