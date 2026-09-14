import SwiftUI

/// 클립보드 기록을 **켜는 그 순간** 뜨는 권한 안내.
///
/// ## 왜 이 시점인가
///
/// 같은 내용이 툴바 탭의 「전체 접근」 안내(`ToolbarTab.fullAccessSection`)에 **이미 상시로**
/// 적혀 있다. 그런데 사용자가 "클립보드 권한을 계속 물어본다"고 보고했다 — 안내가 없어서가
/// 아니라 **토글을 켜는 순간에 없어서** 읽히지 않았다. 그래서 지금 켜려는 그 동작에 붙인다.
///
/// ## ★ 정직하게 — 우리는 「허용」을 켜 줄 수 없다
///
/// **앱이 「다른 앱에서 붙여넣기 = 허용」을 코드로 바꿀 수 없다.** iOS가 사용자에게만 허용한
/// 설정이다. `UIPasteboard`를 읽으면 iOS가 확인 창을 띄우고, 그 창이 매번 안 뜨게 하려면
/// **사용자가 직접 설정에서 바꿔야 한다.**
/// 그래서 이 화면은 **유도**만 한다 — "허용됐다"고 단정하지 않는다.
/// 컨테이너 앱은 `hasFullAccess`를 읽을 수도 없어서, 상태를 표시하는 것 자체가 거짓말이 된다
/// (`ToolbarTab.fullAccessSection` 주석의 설계 결정과 같은 이유).
///
/// ## 왜 매번 띄우는가 (한 번 보고 나면 숨기지 않는 이유)
///
/// 두 설정은 **우리가 읽을 수 없는 외부 상태**다. "한 번 봤으니 됐다"고 숨기면, 나중에 다시
/// 켜는 사용자(껐다 켜기·재설치)가 안내 없이 그대로 "왜 계속 물어보지" 상태로 돌아간다.
/// 뜨는 조건이 **끔 → 켬이라는 의도적인 동작 하나**뿐이라 잔소리가 되지 않는다.
struct ClipboardPermissionSheet: View {

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    step(number: 1,
                         title: "전체 접근을 켜세요",
                         body: "클립보드 기록은 키보드가 복사한 내용을 읽어야 동작해요. "
                             + "전체 접근이 없으면 기록이 쌓이지 않아요.",
                         path: "글쇠 > 키보드 > 전체 접근 허용")
                    step(number: 2,
                         title: "「다른 앱에서 붙여넣기」를 「허용」으로 바꾸세요",
                         body: "처음 값이 \"묻기\"라서 키보드가 복사한 내용을 읽을 때마다 iOS가 "
                             + "확인 창을 띄워요. 계속 물어보는 게 이것 때문이에요. "
                             + "\"허용\"으로 바꾸면 묻지 않아요.",
                         path: "글쇠 > 다른 앱에서 붙여넣기 > 허용")
                    honestNote
                }
                .padding(20)
            }
            .navigationTitle("클립보드 기록 켜기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { settingsButton }
        }
    }

    private var header: some View {
        Label("두 가지를 바꿔야 매번 묻지 않아요", systemImage: "doc.on.clipboard")
            .font(.headline)
    }

    private func step(number: Int, title: String, body: String, path: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
                Text(path)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            }
        }
    }

    /// **여기서 거짓말하지 않는다.** 우리가 켜 줄 수 없다는 사실을 그대로 적는다.
    ///
    /// 경로는 **시뮬레이터에서 실제로 열어 확인한 것**이다 — 처음엔 "전체 접근은 설정 맨 위로
    /// 올라가 일반 > 키보드로 가야 한다"고 썼는데 **틀렸다.** `openSettingsURLString`이 여는
    /// `설정 > 글쇠` 페이지에 「키보드 ›」 행이 있고 그 안에 「전체 접근 허용」이 있다.
    /// 즉 **두 설정이 같은 딥링크에서 한 화면 안에 있다.**
    /// (증거: `docs/design-reviews/clipboard-permission-ux.md`)
    private var honestNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("앱이 대신 켜 줄 수는 없어요")
                .font(.footnote.weight(.semibold))
            Text("이 두 가지는 iOS가 사용자만 바꿀 수 있게 해 둔 설정이라, 글쇠가 코드로 켜지 못해요. "
                 + "아래 버튼이 글쇠 설정 화면을 열어 줘요 — 위 두 항목이 거기 바로 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var settingsButton: some View {
        Button {
            // 컨테이너 앱은 **자기 설정 페이지**만 열 수 있다. 다행히 그 페이지에 두 항목이
            // 모두 있다(실측). 더 깊은 화면으로 바로 가는 공개 URL은 없어 경로를 글로 함께 적는다.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            Label("글쇠 설정 열기", systemImage: "arrow.up.forward.app")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .background(.bar)
    }
}
