import SwiftUI

/// 정보 탭 — 개인정보 처리방침, 오픈소스 및 출처, 설치 안내 다시 보기.
struct InfoTab: View {

    let onReplayOnboarding: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink("개인정보 처리방침") { PrivacyPolicyView() }
                    NavigationLink("오픈소스 및 출처") { LicensesView() }
                }
                Section {
                    Button("설치 안내 다시 보기", action: onReplayOnboarding)
                } footer: {
                    Text("설정 > 일반 > 키보드 > 키보드 추가에서 글쇠를 추가하고, 입력할 때 지구본을 눌러 전환하세요.")
                }
            }
            .navigationTitle("정보")
        }
    }
}
