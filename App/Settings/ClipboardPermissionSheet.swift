import SwiftUI

/// 전체 접근이 필요한 기능을 **켜는 그 순간** 뜨는 권한 안내.
///
/// ## 클립보드 전용이 아니다 (2026-09-15)
///
/// 예전엔 제목이 "클립보드 기록 켜기"였고 1단계 본문도 "클립보드 기록은…"으로 시작했다.
/// 그런데 **전체 접근에 묶인 기능은 둘**이다 — 클립보드 기록과 복사한 인증번호 제안.
/// 인증번호 때문에 이 시트를 연 사람에게는 **제목부터 딴소리**였다(반론자 R-3).
/// 그래서 제목과 1단계를 공용으로 일반화했다. 지금은 **세 토글**(클립보드 기록 · 복사한 인증번호
/// 제안 · 복사한 텍스트 제안)이 모두 끔 → 켬에서 이 시트를 띄우고, 클립보드 절의
/// 「전체 접근 켜는 방법 보기」 버튼도 같은 시트를 연다.
///
/// ## ★ 2026-09-15 — 이 시트가 **화면의 상시 설명을 대체했다**
///
/// 툴바 탭 클립보드 절에 1·2단계 설명이 상시로 깔려 있었는데 사용자가 지우라고 했다
/// ("너무 설명이 많아서 눈에도 잘 안들어옴"). 지우면서 **정보를 잃지 않으려고** 화면 쪽에만
/// 있던 두 가지를 여기로 올렸다 — (1) 붙여넣기 확인 창에서 **「붙여넣기 허용」을 누르라**는 지시
/// (전체 접근 창의 버튼은 「허용」이고 이쪽은 「붙여넣기 허용」이라 이름이 다르다 —
/// `docs/release/settings-path-truth.md` 2-2), (2) 그 행이 **같은 화면에** 새로 생긴다는 것.
/// **이제 이 시트가 유일한 안내 경로다. 여기서 문장을 줄이면 갈 곳이 없어진다.**
///
/// ## 왜 이 시점인가
///
/// 같은 내용이 툴바 탭 클립보드 절에 **상시로도** 적혀 있다. 그런데 사용자가 "클립보드 권한을
/// 계속 물어본다"고 보고했다 — 안내가 없어서가 아니라 **토글을 켜는 순간에 없어서** 읽히지
/// 않았다. 그래서 지금 켜려는 그 동작에 붙인다.
///
/// ## ★ 정직하게 — 우리는 「허용」을 켜 줄 수 없다
///
/// **앱이 「다른 앱에서 붙여넣기 = 허용」을 코드로 바꿀 수 없다.** iOS가 사용자에게만 허용한
/// 설정이다. `UIPasteboard`를 읽으면 iOS가 확인 창을 띄우고, 그 창이 매번 안 뜨게 하려면
/// **사용자가 직접 설정에서 바꿔야 한다.**
/// 그래서 이 화면은 **유도**만 한다 — "허용됐다"고 단정하지 않는다.
/// 컨테이너 앱은 `hasFullAccess`를 읽을 수도 없어서, 상태를 표시하는 것 자체가 거짓말이 된다
/// (`ToolbarTab.clipboardSection` 주석의 설계 결정과 같은 이유 — 그 절이 예전 `fullAccessSection`을
/// 흡수했다).
///
/// ## 왜 매번 띄우는가 (한 번 보고 나면 숨기지 않는 이유)
///
/// 두 설정은 **우리가 읽을 수 없는 외부 상태**다. "한 번 봤으니 됐다"고 숨기면, 나중에 다시
/// 켜는 사용자(껐다 켜기·재설치)가 안내 없이 그대로 "왜 계속 물어보지" 상태로 돌아간다.
/// 뜨는 조건이 **끔 → 켬이라는 의도적인 동작 하나**뿐이라 잔소리가 되지 않는다.
struct ClipboardPermissionSheet: View {

    @Environment(\.dismiss) private var dismiss

    /// 단계 번호 원의 지름 — **글자 크기를 따라 커진다.** 고정 22pt로 두면 접근성 큰 글자에서
    /// 숫자가 원 밖으로 잘린다(온보딩에서 같은 자리에 걸렸다).
    @ScaledMetric(relativeTo: .footnote) private var stepBadgeSize: CGFloat = 22

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    step(number: 1,
                         title: "전체 접근을 켜세요",
                         body: "클립보드 기록·복사한 인증번호 제안·복사한 텍스트 제안에 필요해요.\n"
                             + "「글쇠」를 켜면 바로 아래 「전체 접근 허용」이 나타나요.",
                         paths: [
                            (version: "iOS 18 이상", value: "설정 > 앱 > 글쇠 > 키보드"),
                            (version: "iOS 17", value: "설정 > 일반 > 키보드 > 키보드 > 글쇠")
                         ])
                    step(number: 2,
                         title: "뜨는 확인 창에서 「허용」을 누르세요",
                         body: "스위치는 켜진 것처럼 보여도, 여기서 「허용 안 함」을 누르면 도로 꺼져요.",
                         paths: [(version: nil, value: "전체 접근을 허용하겠습니까? → [허용]")])
                    step(number: 3,
                         title: "「다른 앱에서 붙여넣기」를 「허용」으로",
                         body: "이 행은 처음엔 없어요. 키보드를 한 번 쓰면 뜨는 확인 창에서 "
                             + "「붙여넣기 허용」을 누르면 생겨요.\n"
                             + "값이 \"묻기\"라 매번 물어요 — \"허용\"으로 바꾸세요.",
                         paths: [(version: nil, value: "설정 > 앱 > 글쇠 > 다른 앱에서 붙여넣기")])
                    settingsButtonNote
                }
                .padding(20)
            }
            .navigationTitle("전체 접근이 필요해요")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { settingsButton }
        }
    }

    /// 바꿀 **설정은 둘**인데 가운데에 **탭 한 번**(확인 창)이 끼어 단계는 셋이다.
    /// 그 탭을 빠뜨리면 스위치를 켜고도 안 켜진다 — 이번 실측의 핵심이라 단계로 올렸다.
    ///
    /// 「두 가지」가 아니라 **「2가지」**다 (사용자 지시 2026-09-15). `Label` 이라 보이는 글과
    /// VoiceOver 가 읽는 글이 **같은 문자열 하나**에서 나온다 — 따로 맞출 자리가 없다.
    private var header: some View {
        Label("2가지 설정을 바꿔요 — 순서가 있어요", systemImage: "lock.open")
            .font(.headline)
    }

    /// 한 단계 = 번호 + 제목 + 본문 + **경로 영역 하나 이상**.
    ///
    /// ## 왜 경로가 배열인가 — iOS 버전마다 길이 다르다
    ///
    /// 예전에는 경로 한 덩어리 안에 `(iOS 17에서는 …)` 을 괄호로 욱여넣었다. 사용자가
    /// **영역을 나누라**고 했다(2026-09-15) — 자기 버전이 어느 쪽인지 한눈에 보여야 한다.
    /// 그래서 경로마다 **독립된 상자**를 그리고 **버전 표시를 각 상자에 붙인다.**
    ///
    /// **「앱」 묶음은 iOS 18.0에서 생겼다**(애플 사용 설명서 17판/18판 본문 diff 로 확정).
    /// 우리 하한은 17이라 두 경로가 다 필요하다.
    /// **`[미확인]` iOS 17 화면을 런타임에서 본 사람이 팀에 아직 없다** — 애플의 통상 패턴에 대한
    /// **추론이지 실측이 아니다**(`docs/design-reviews/toolbar-permission-ux.md` 5-7).
    private func step(
        number: Int,
        title: String,
        body: String,
        paths: [(version: String?, value: String)]
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: stepBadgeSize, height: stepBadgeSize)
                .background(Circle().fill(.tint))
                .accessibilityHidden(true)   // 제목에 "N단계"를 합쳐 읽어 준다
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.footnote).foregroundStyle(.secondary)
                ForEach(Array(paths.enumerated()), id: \.offset) { _, path in
                    pathBox(version: path.version, value: path.value)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(number)단계. \(title). \(body). " + paths
            .map { $0.version.map { v in "\(v) 경로 " } ?? "경로 " }
            .enumerated()
            .map { index, prefix in prefix + paths[index].value }
            .joined(separator: ". "))
    }

    /// 경로 한 칸. 버전 표시가 있으면 상자 **안 맨 위**에 얹는다 — 상자 밖에 두면 어느 상자의
    /// 것인지 한 번 더 생각해야 한다.
    ///
    /// `fixedSize(horizontal:vertical:)` 로 세로를 열어 둔다. 접근성 큰 글자에서 경로가 두세 줄이
    /// 되는데, 고정 높이면 잘린다(온보딩·툴바에서 같은 자리에 걸린 적이 있다).
    private func pathBox(version: String?, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let version {
                Text(version)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
    }

    /// 아래 「글쇠 설정 열기」 버튼의 **완충 문구** — 버튼이 설정 앱을 열 뿐이라는 것.
    ///
    /// ## 왜 하단 고정 바가 아니라 스크롤 내용 끝에 있나
    ///
    /// 처음엔 버튼과 함께 `safeAreaInset` 바 안에 넣었는데, **접근성 큰 글자에서 그 바가 화면의
    /// 절반 가까이를 먹었다**(실측 2026-09-15, XXXL 캡처). 고정 바는 스크롤되지 않으므로
    /// 거기 있는 글자가 커지면 **읽을 내용이 들어갈 자리를 그만큼 빼앗는다.**
    /// 스크롤 내용 끝에 두면 기본 크기에서는 버튼 바로 위라 연결이 그대로 보이고,
    /// 큰 글자에서는 다른 본문과 함께 스크롤된다.
    private var settingsButtonNote: some View {
        Text("「글쇠」가 바로 안 보이면 「앱」에서 찾으세요.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// 설정 앱을 여는 유일한 수단. **이 버튼은 목적지를 약속하지 않는다.**
    ///
    /// ## ★ 예전 「앱이 대신 켜 줄 수는 없어요」 단락이 들고 있던 지식 (2026-09-15 이관)
    ///
    /// 그 단락은 사용자 지시로 **화면에서 지웠다**("앱이 대신 켜줄수 없어요 타이틀과 내용은 삭제").
    /// 그런데 거기 달려 있던 주석에 **버튼에 여전히 유효한 실측 정정 둘**이 적혀 있었다. 옮겨 둔다 —
    /// 뷰는 지워도 왜 이 버튼이 목적지를 보장 못 하는지는 다음 사람이 알아야 한다.
    /// 근거: `docs/release/settings-path-truth.md` (검증자, 전용 시뮬레이터 캡처 13장).
    ///
    /// 1. **`openSettingsURLString`은 글쇠 페이지를 보장하지 않는다.** 설정 앱이 떠 있으면
    ///    **마지막 본 화면**, 종료돼 있으면 **설정 루트**로 간다. 2026-09-11에 글쇠 페이지가
    ///    열린 것은 그때 마지막으로 본 화면이 글쇠였기 때문일 수 있다.
    ///    → 그래서 라벨 아래 완충 문구를 둔다. "글쇠 페이지가 열린다"고 쓰지 않는다.
    /// 2. **두 설정은 한 화면에 있지도 않다.** 「전체 접근 허용」은 `… > 글쇠 > 키보드` 안이고,
    ///    「다른 앱에서 붙여넣기」는 한 단계 바깥 `… > 글쇠`의 **독립 카드**다. 게다가
    ///    **키보드가 클립보드를 처음 읽기 전까지는 그 행이 존재하지 않는다.**
    ///    (예전 주석은 *"두 설정이 같은 딥링크에서 한 화면 안에 있다"*고 적었는데 **틀렸다.**)
    ///
    /// **앱이 대신 켜 줄 수 없다는 사실 자체**는 화면에서 빠졌지만 거짓이 되지는 않는다 —
    /// 이 시트는 어디서도 "켜 준다"고 말하지 않고 **켜는 방법만** 알려 준다.
    private var settingsButton: some View {
        Button {
            // 더 깊은 화면으로 가는 공개 URL은 없다. 경로는 위 단계에 글로 적혀 있다.
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
