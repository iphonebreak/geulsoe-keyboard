import SwiftUI
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

    private let repository = AppGroupSettingsRepository()

    var body: some View {
        TabView {
            KeyboardTab(settings: $settings)
                .tabItem { Label("자판", systemImage: "keyboard") }
            ToolbarTab(settings: $settings)
                .tabItem { Label("툴바", systemImage: "slider.horizontal.3") }
            AppearanceTab(settings: $settings)
                .tabItem { Label("화면", systemImage: "paintpalette") }
            InfoTab(onReplayOnboarding: { hasSeenOnboarding = false })
                .tabItem { Label("정보", systemImage: "info.circle") }
        }
        .onChange(of: settings) { _, updated in
            repository.save(updated)
            // 떠 있는 키보드가 즉시 다시 읽도록 (Darwin 알림, PDR field-traits-and-live-settings)
            SettingsChangeNotifier.post()
        }
        .fullScreenCover(isPresented: .init(
            get: { !hasSeenOnboarding },
            set: { hasSeenOnboarding = !$0 }
        )) {
            OnboardingView { hasSeenOnboarding = true }
        }
    }
}

#Preview {
    RootView()
}
