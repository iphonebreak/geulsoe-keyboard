import SwiftUI

/// 개인정보 처리방침 — 앱 내 화면.
///
/// "입력 내용을 수집·전송하지 않는다"는 `.claude/rules/security.md`의 의무 문구이며,
/// **코드가 이 문서와 어긋나면 코드가 아니라 규칙 위반이다** (네트워크 코드 추가 금지).
/// App Store Connect에는 같은 내용의 웹 URL 게시가 별도로 필요하다 — `docs/release-and-review.md`.
struct PrivacyPolicyView: View {

    var body: some View {
        List {
            Section("수집하지 않는 것") {
                policyItem(
                    "입력 내용",
                    "키보드로 입력한 모든 내용은 수집·저장·전송되지 않습니다. 글쇠에는 네트워크 기능 자체가 없습니다."
                )
                policyItem(
                    "개인 정보와 사용 통계",
                    "계정, 광고 식별자, 분석 도구를 사용하지 않습니다."
                )
            }

            Section("기기 안에만 저장되는 것") {
                policyItem(
                    "키보드 설정",
                    "자판·테마 등 설정은 이 기기의 앱 전용 저장 공간(App Group)에만 저장됩니다."
                )
                policyItem(
                    "내 문구 (채움글)",
                    "직접 추가한 트리거와 본문은 기기 안에만 저장되며, 설정 > 채움글에서 삭제할 수 있습니다."
                )
                policyItem(
                    "학습 단어 (추천단어)",
                    "자주 쓰는 단어의 사용 횟수만 기기 안에 저장됩니다. 비밀번호 입력란에서는 학습하지 않으며, 설정의 '학습 단어 초기화'로 모두 삭제할 수 있습니다."
                )
                policyItem(
                    "클립보드 기록",
                    "클립보드 기록이 켜져 있고 전체 접근이 허용된 경우, 키보드가 열릴 때와 툴바의 클립보드 도구를 열 때 읽은 클립보드 내용(최근 30개, 항목당 2,000자까지)을 기기 안에만 저장합니다. 비밀번호 입력란에서는 기록하지 않습니다. 항목별 삭제·모두 지우기가 가능하고, 설정에서 기록을 끄면 저장된 기록이 즉시 삭제됩니다."
                )
            }

            Section("전체 접근 허용") {
                policyItem(
                    "켜지 않아도 됩니다",
                    "한글 입력·채움글·추천단어 등 핵심 기능은 전체 접근 없이 동작합니다. 전체 접근에 의존하는 것은 네 가지입니다: 학습한 단어의 영구 저장(없으면 키보드가 열려 있는 동안만 유지), 복사한 인증번호 제안, 클립보드 도구와 기록, 그리고 키 입력 진동."
                )
                policyItem(
                    "클립보드",
                    "클립보드는 주기적으로 감시하지 않습니다. 읽는 시점은 키보드가 열릴 때 1회(인증번호 제안 또는 클립보드 기록이 켜진 경우)와 클립보드 도구를 열 때뿐입니다. 인증번호 제안은 클립보드에서 찾은 번호를 툴바에 표시하며, 찾은 번호는 툴바 표시와 입력란 삽입 외에 저장·전송되지 않습니다 (클립보드 기록이 켜져 있으면 복사한 원문은 위 '클립보드 기록'에 남습니다). 두 기능은 각각 설정에서 끌 수 있습니다."
                )
            }

            Section {
                Text("앱을 삭제하면 위의 모든 데이터가 함께 삭제됩니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .settingsFormWidth()
        .navigationTitle("개인정보 처리방침")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func policyItem(_ heading: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(heading)
                .font(.headline)
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
