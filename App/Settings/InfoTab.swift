import SwiftUI

/// 정보 탭 — 개인정보 처리방침, 오픈소스 및 출처, 지원 및 문의(웹), 설치 안내 다시 보기.
///
/// **「이용 분석·오류 진단」 끄기 메뉴는 v1.3.1에서 일부러 뺐다** — 사장님 결정 N20(2026-10-14, 「다른 앱을 보았을 때
/// 필요 없음」, 수집은 유지). 빠뜨린 것이 아니니 복구하지 않는다. 심사 가이드라인 5.1.1(ii)(동의 철회 수단) 반려 위험을
/// 알고 내린 결정이며, 반려되면 그 커밋을 `git revert`한다. 이전에 끈 선택은 `AnalyticsConsent.applyStoredChoices()`가
/// 계속 적용한다. 근거 `docs/release/v131-analytics-optout-removal.md`
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
                    // 웹 지원 페이지(사용법·자주 묻는 질문·문의) — Safari로 연다. 처리방침 「전체 처리방침 보기」와 같은 호스팅(2026-10-08 사장님)
                    Link(destination: URL(string: "https://geulsoe-keyboard.web.app/support")!) {
                        HStack {
                            Text("지원 및 문의")
                                .foregroundStyle(Color.primary)
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint("Safari에서 지원 페이지를 열어요")
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
