import SwiftUI

/// 첫 실행 온보딩 — 소개 → 키보드 추가 방법 → 프라이버시 약속.
///
/// 표시 여부(`hasSeenOnboarding`)는 standard UserDefaults다 — 키보드가 읽을 일이 없는
/// 앱 로컬 상태라 App Group 스키마에 넣지 않는다 (PDR release-readiness 결정 2).
struct OnboardingView: View {

    let onFinish: () -> Void

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                introPage.tag(0)
                installPage.tag(1)
                privacyPage.tag(2)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 {
                    withAnimation { page += 1 }
                } else {
                    onFinish()
                }
            } label: {
                Text(page < 2 ? "다음" : "시작하기")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 페이지

    private var introPage: some View {
        OnboardingPage(
            symbol: "keyboard",
            title: "글쇠와 함께",
            items: [
                ("두벌식 · 천지인 · 단모음", "손에 맞는 한글 자판을 골라 쓰세요."),
                ("추천단어", "치던 단어의 완성 후보가 툴바에 떠요."),
                ("채움글", "\"창세기 1장 1절\", \"애국가 1절\"을 치면 전문이 후보로 떠요. 내 문구도 만들 수 있어요.")
            ]
        )
    }

    private var installPage: some View {
        OnboardingPage(
            symbol: "gearshape",
            title: "키보드 추가하기",
            items: [
                ("1. 설정 열기", "아래 버튼을 누르면 글쇠의 설정으로 이동해요."),
                ("2. 키보드 켜기", "키보드 항목에서 '글쇠'를 켜세요."),
                ("3. 지구본 키", "입력할 때 지구본을 눌러 글쇠로 전환하세요.")
            ],
            footer: AnyView(
                Button("설정 열기") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
            )
        )
    }

    private var privacyPage: some View {
        OnboardingPage(
            symbol: "lock.shield",
            title: "입력 내용은 기기 밖으로 나가지 않아요",
            items: [
                ("수집·전송 없음", "글쇠에는 네트워크 기능 자체가 없어요. 입력한 내용을 수집하거나 어디로도 보내지 않아요."),
                ("전체 접근은 선택", "켜지 않아도 핵심 기능이 전부 동작해요. 켜면 학습한 단어가 유지되고, 복사한 인증번호 제안과 키 입력 진동을 쓸 수 있어요."),
                ("내가 지울 수 있어요", "학습 단어와 내 문구는 설정에서 언제든 삭제할 수 있어요.")
            ]
        )
    }
}

/// 온보딩 한 페이지 — 심볼 + 제목 + 항목 목록 (+ 선택 footer)
private struct OnboardingPage: View {

    let symbol: String
    let title: String
    let items: [(heading: String, body: String)]
    var footer: AnyView?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
            Text(title)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.heading)
                            .font(.headline)
                        Text(item.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let footer {
                footer
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }
}

#Preview {
    OnboardingView {}
}
