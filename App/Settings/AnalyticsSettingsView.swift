import SwiftUI

/// 이용 분석·오류 진단 끄기 화면 — App Store 심사 가이드라인 **5.1.1(ii)**가 요구하는
/// "접근 가능하고 이해하기 쉬운 동의 철회 수단"이다.
///
/// **두 곳에서 들어온다** — 정보 탭의 첫 줄, 그리고 개인정보 처리방침 화면의 분석 절.
/// 처리방침이 "이 스위치로 끄세요"라고 적고 바로 그 스위치로 갈 수 있어야 안내가 실효를 갖는다.
/// 두 진입점 모두 같은 `NavigationStack`(정보 탭) 안이라 화면은 하나로 유지된다.
///
/// 스위치 값은 `AnalyticsConsent`가 앱 전용 `UserDefaults`에 둔다 (App Group 아님 — 이유는 그 파일 주석).
struct AnalyticsSettingsView: View {

    @AppStorage(AnalyticsConsent.Key.analytics)
    private var analyticsEnabled = AnalyticsConsent.defaultValue

    @AppStorage(AnalyticsConsent.Key.crashlytics)
    private var crashlyticsEnabled = AnalyticsConsent.defaultValue

    var body: some View {
        Form {
            Section {
                Toggle("이용 분석 보내기", isOn: $analyticsEnabled)
            } header: {
                Text("이용 분석")
            } footer: {
                Text("설정 앱의 화면 조회·기능 사용 여부 같은 사용 패턴을 보냅니다. 끄면 즉시 중단됩니다. 키보드로 입력한 내용은 켜져 있든 꺼져 있든 어디에도 포함되지 않습니다.")
            }

            Section {
                Toggle("오류 진단 보내기", isOn: $crashlyticsEnabled)
            } header: {
                Text("오류 진단")
            } footer: {
                Text("앱이 비정상 종료됐을 때 발생 지점·기기 모델·OS 버전을 보내 문제를 고치는 데 씁니다. 끄면 앱을 다음에 실행할 때부터 적용되고, 꺼 둔 동안 기기에 쌓인 기록은 전송되지 않고 삭제됩니다.")
            }

            Section {
                Text("두 기능 모두 설정 앱에만 있습니다. 키보드 익스텐션에는 네트워크 기능 자체가 없어, 입력한 텍스트·클립보드·학습 단어·채움글 내용은 어떤 경우에도 전송되지 않습니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsFormWidth()
        .navigationTitle("이용 분석·오류 진단")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: analyticsEnabled) { _, _ in AnalyticsConsent.applyStoredChoices() }
        .onChange(of: crashlyticsEnabled) { _, _ in AnalyticsConsent.applyStoredChoices() }
    }
}

#Preview {
    NavigationStack { AnalyticsSettingsView() }
}
