import SwiftUI

/// 정보 탭 — 개인정보 처리방침, 이용 분석·오류 진단 끄기, 오픈소스 및 출처, 설치 안내 다시 보기.
///
/// **"이용 분석·오류 진단"은 심사 가이드라인 5.1.1(ii)가 요구하는 동의 철회 수단이다.**
/// 처리방침 바로 아래 첫 화면 깊이에 둔 것이 "접근 가능하고 이해하기 쉽게"에 대한 답이다.
/// 처리방침 화면 안에서도 같은 화면으로 갈 수 있다 (`AnalyticsSettingsView`).
struct InfoTab: View {

    let onReplayOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("개인정보 처리방침") { PrivacyPolicyView() }
                    NavigationLink("이용 분석·오류 진단") { AnalyticsSettingsView() }
                    NavigationLink("오픈소스 및 출처") { LicensesView() }
                }
                Section {
                    Button("설치 안내 다시 보기", action: onReplayOnboarding)
                } footer: {
                    Text("설정 > 일반 > 키보드 > 키보드 추가에서 글쇠를 추가하고, 입력할 때 지구본을 눌러 전환하세요.")
                }
            }
            .settingsFormWidth()
            .navigationTitle("정보")
        }
    }
}
