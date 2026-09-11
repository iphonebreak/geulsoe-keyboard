import SwiftUI
import TadakDomain

/// 화면 탭 — 모드(시스템/라이트/다크) + 테마 목록.
struct AppearanceTab: View {

    @Binding var settings: KeyboardSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("모드", selection: $settings.appearance) {
                        Text("시스템").tag(Appearance.system)
                        Text("라이트").tag(Appearance.light)
                        Text("다크").tag(Appearance.dark)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("모드")
                } footer: {
                    Text("모든 테마는 라이트/다크 팔레트 쌍을 갖고 시스템 모드를 따라가요. 여기서 고정할 수 있어요.")
                }

                Section("테마") {
                    ThemeRows(selectedThemeID: $settings.selectedThemeID)
                }
            }
            .settingsFormWidth()
            .navigationTitle("화면")
        }
    }
}
