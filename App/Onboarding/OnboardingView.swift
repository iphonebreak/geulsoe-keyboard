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
            // 폭만 제한한다. `readableWidth`는 세로도 꽉 채워서 버튼이 남은 공간 한가운데로
            // 밀려난다 (2026-09-09 실측: 하단 24pt가 아니라 837pt에 떴고, 위의 TabView가
            // 눌려 페이지 인디케이터까지 화면 중앙으로 올라왔다).
            .readableContentWidth(AdaptiveLayout.onboardingMaxWidth)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 페이지

    private var introPage: some View {
        OnboardingPage(
            mark: .appIcon,
            title: "글쇠와 함께",
            items: [
                ("두벌식 · 천지인 · 단모음", "손에 맞는 한글 자판을 골라 쓰세요."),
                ("추천단어", "치던 단어의 완성 후보가 툴바에 떠요."),
                // **예시는 셋이다 — 갈래가 셋이기 때문이다** (사장님 결정 2026-09-14).
                // 사용자 요청은 "채움글에 헌법·인사말도 된다고 추가하라", 즉 **갈래를 늘리라**는 것이지
                // 예시 개수를 늘리라는 게 아니었다. 넷이던 시절의 애국가 1절과 헌법 전문은 **같은 팩**
                // (국가 상징문 `anthem`)이라 갈래로는 겹쳤고, 넷째가 402pt 기본 글자 크기에서
                // `"새해` / `인사"`로 쪼개졌다(지적 14 — 한국어는 음절 사이 어디서나 줄바꿈된다.
                // U+00A0·U+2060 둘 다 시도했으나 SwiftUI Text 가 따르지 않아 실패했다).
                // 애국가를 빼면 **성경·헌법·인사말** 셋을 그대로 덮으면서 줄바꿈도 풀린다.
                //
                // 세 예시는 전부 실제 단축어다(2026-09-14 직접 대조):
                //   창세기 1장 1절 — `BibleReferenceParser` 구문 파서 (JSON 표가 아니다.
                //                    `SnippetTests.swift:31` 이 이 문자열 그대로 단언한다)
                //   헌법 전문     — `Snippets.json` (국가 상징문 팩)
                //   새해인사      — `Greetings.json`
                ("채움글", "\u{201C}창세기 1장 1절\u{201D}, \u{201C}헌법 전문\u{201D}, \u{201C}새해인사\u{201D}처럼 치면 전문이 후보로 떠요. 내 문구도 만들 수 있어요.")
            ]
        )
    }

    private var installPage: some View {
        // 머리 그림 없음 — 아래 안내 카드가 이 쪽의 그림이다. 기어 심볼을 함께 두면
        // 그림이 둘이 되어 중복이고, 4.7인치(667pt)에서 세로가 모자란다
        // (실측: 17 Pro 에서 본문 118…664 = 546pt. 기어 54 + 간격 32 를 빼야 SE 에서 들어간다).
        OnboardingPage(
            mark: nil,
            title: "키보드 추가하기",
            items: [
                // **"글쇠의 설정으로 이동해요"는 사실이 아니었다.** `openSettingsURLString` 은
                // **설정 루트**로 간다 — 디자이너가 시뮬레이터에서 추가 전·후 각 1회 실측했다
                // (증거: docs/release/screens/settings-path-4-open-settings-lands-root.png).
                //
                // **긴 경로가 기본이고 완충은 iOS 17 쪽이 받는다** (사장님 재결정 2026-09-14, 반론자 O-4).
                // 처음엔 반대였다 — 짧은 경로를 기본에 두고 18 이상을 괄호로 받았는데, 저울이 한쪽으로만
                // 기운다: **17 에서 긴 경로는 한 홉이 비는 것뿐이지만, 18 이상에서 짧은 경로는 아예
                // 존재하지 않는 경로다.** 없는 길을 가리키는 쪽이 더 나쁘다.
                //
                // ⚠ **「앱」 묶음이 정확히 iOS 18 에서 생겼다는 애플 원문 근거는 못 잡았다.**
                // 반론자가 4회, 내가 3회 시도해 둘 다 실패했고, 설치된 런타임이 iOS 26.5 하나뿐이라
                // 17·18 을 띄워 볼 수도 없다. **완충 괄호가 양쪽을 덮는 것이 이 불확실성에 대한 답이다** —
                // 어느 버전이 경계든 두 문장 중 하나는 맞는다.
                //
                // ⚠ **「설정 열기」의 실기 동작은 아직 아무도 확인하지 못했다.** `app-settings:` 의
                // 시뮬↔실기 차이는 알려진 항목이라, 실기에서 루트가 아니라 글쇠 페이지로 바로 가면
                // 이 문구가 틀린다. 사장님이 실기로 확인하기로 했다.
                ("1. 설정 열기", "아래 버튼으로 설정을 열고, 앱 > 글쇠 > 키보드로 들어가세요.\n(iOS 17에서는 '앱' 없이 바로 글쇠가 있어요.)"),
                // 켜는 컨트롤은 **스위치**다. 실측 화면에 체크는 없다.
                ("2. 키보드 켜기", "글쇠 스위치를 켜세요."),
                ("3. 지구본 키", "입력할 때 지구본을 눌러 글쇠로 전환하세요.")
            ],
            // 세 항목을 말로 읽은 다음 같은 순서를 눈으로 한 번 더 본다 — 카드를 목록 위에 두면
            // 아직 무엇을 볼지 모르는 채로 보게 되고, 버튼 아래에 두면 행동(설정 열기)이 설명보다 앞선다.
            footer: AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    InstallIntroAnimationView()
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                }
            )
        )
    }

    private var privacyPage: some View {
        OnboardingPage(
            mark: .symbol("lock.shield"),
            title: "입력한 내용은 기기 밖으로 나가지 않아요",
            items: [
                ("키보드는 수집하지 않아요", "치신 내용, 클립보드, 학습 단어는 키보드 안에만 있고 어디로도 나가지 않아요. 키보드에는 분석 도구가 없어요."),
                ("설정 앱은 이용 분석을 해요", "이 설정 화면을 어떻게 쓰시는지와 오류 정보만 개발사에 전달돼요. 입력 내용은 여기 포함되지 않아요."),
                ("전체 접근은 선택", "켜지 않아도 핵심 기능이 전부 동작해요. 켜면 학습한 단어 유지, 복사한 인증번호 제안, 클립보드 도구와 기록, 키 입력 진동을 쓸 수 있어요.")
            ]
        )
    }
}

/// 온보딩 한 페이지 — 머리 그림 + 제목 + 항목 목록 (+ 선택 footer)
///
/// `mark`가 nil이면 머리 그림을 그리지 않는다 — 2쪽처럼 footer의 안내 카드가 그 역할을 대신할 때다.
private struct OnboardingPage: View {

    let mark: OnboardingMark?
    let title: String
    let items: [(heading: String, body: String)]
    var footer: AnyView?

    var body: some View {
        // **접근성 글자 크기에서 잘리지 않게 스크롤을 붙인다** (반론자 O-1).
        //
        // 예전엔 `VStack` + `Spacer` 둘로만 짜여 있었다. 일반 최대(XXXL)까지는 멀쩡한데
        // **접근성 크기부터 깨졌다** — AX3 에서 안내 카드가 통째로 사라지고 제목이 잘리고
        // 「설정 열기」가 페이지 점과 겹쳤으며, AX5 에서는 그 버튼까지 사라졌다.
        // 1쪽은 제목과 앱 아이콘 머리 그림이 통째로 화면 밖이고, 3쪽은 프라이버시 고지 제목이
        // "설정 앱은 이용…" 으로 말줄임됐다. 내가 "XXL 에서 가장 먼저 넘칠 후보"라고 **예측만 하고
        // 확인하지 못한** 바로 그 자리다.
        //
        // `scrollBounceBehavior(.basedOnSize)` 가 핵심이다 — **내용이 화면보다 짧으면 스크롤이
        // 아예 붙지 않아** 일반 크기 화면의 동작·모양이 그대로 남는다. 넘칠 때만 스크롤이 생긴다.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        // ⚠ **남은 결함 — 페이지 점이 본문 글자를 덮는다(AX3 이상).** 이 스크롤이 고친 것은
        // "내용에 닿을 수 없다"(카드·버튼이 사라진다)는 쪽이고, 겹침은 **따로 남았다.**
        //
        // **두 가지를 시도해 둘 다 실패했다**(AX5 캡처로 확인):
        //   · `content` 에 `.padding(.bottom, 36)` — 패딩은 스크롤 **내용 끝**에만 붙는다.
        //     겹치는 글자는 화면 중간을 지나는 줄이라 맨 아래로 내려야만 효과가 있다. 그대로 겹쳤다.
        //   · `ScrollView` 에 `.safeAreaInset(edge: .bottom)` — 점은 `TabView(.page)` 가
        //     **페이지 바깥에서 위에 얹는** 것이라 페이지의 안전 영역과 무관하다. 그대로 겹쳤다.
        //
        // 남은 길은 `.tabViewStyle(.page(indexDisplayMode: .never))` 로 점을 끄고 하단 버튼 줄에
        // **우리가 직접 그리는 것**인데, 그건 `OnboardingView` 의 크롬 구조를 바꾸는 일이라
        // 세 쪽 전부에 걸린다. **범위 밖이라 손대지 않았다** — 사장님 판단을 받는다.
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)
            if let mark {
                OnboardingMarkView(mark: mark)
            }
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
            Spacer(minLength: 0)
            // 아이폰은 내용이 위쪽 1/3에 오도록 아래를 두 배로 비운다. 아이패드는 화면이 훨씬 길어
            // 같은 비율이면 아래가 통째로 비어 보이므로 위아래를 같게 둔다 (PDR ipad-support).
            // `minLength: 0` 인 이유: 스크롤 안에서 `Spacer` 가 고유 높이를 주장하면 내용이 넘칠 때
            // 여백이 먼저 자리를 차지해 **글자를 밀어낸다.** 넘칠 때는 0 으로 접혀야 한다.
            if !AdaptiveLayout.isPad { Spacer(minLength: 0) }
        }
        // 아이패드에서 폭을 제한하지 않으면 문구가 834pt 전폭에 왼쪽 위로 몰리고 오른쪽이 통째로
        // 빈다 (QA BLOCK-1 §4). 내용 자체는 왼쪽 정렬을 유지하고 블록만 가운데로 모은다.
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableWidth(AdaptiveLayout.onboardingMaxWidth)
        .padding(.horizontal, 32)
    }
}

/// 온보딩 페이지 머리 그림 — SF Symbol 또는 앱 아이콘 아트워크.
///
/// **왜 앱 아이콘을 `AppIcon.appiconset` 에서 직접 못 쓰나.** 앱 아이콘 세트는 이미지 에셋이
/// 아니라 홈 화면용 슬롯이라 `Image("AppIcon")` 으로 참조되지 않는다. 그래서 같은 원본에서
/// 별도 imageset `AppIconArtwork` 를 만들었다 (라이트·다크 `appearances` 쌍).
enum OnboardingMark {
    case symbol(String)
    case appIcon
}

/// 세 쪽의 **시각 무게를 맞추는 곳**. 심볼은 52pt 글리프, 아이콘은 64pt 타일인데
/// 타일이 면을 채워 더 무거우므로 크기로만 맞추지 않고 아래 규칙을 함께 쓴다.
private struct OnboardingMarkView: View {

    let mark: OnboardingMark

    /// 아이콘 변의 길이.
    ///
    /// **"심볼 52pt와 같은 광학 무게"는 사실이 아니다** — 2026-09-14 실측으로 잉크 면적이
    /// **약 4.0배**로 나왔다(타일은 64×64를 꽉 채우고 SF Symbol 글리프는 획만 칠한다).
    /// 예전 주석이 그렇게 적혀 있어 바로잡는다. **값 자체는 바꾸지 않았다** — 실제 화면에서
    /// 세 쪽의 균형이 무너져 보이지 않았고, 크기 조정은 디자이너 판단 영역이다.
    /// 균형을 다시 볼 일이 생기면 "같은 광학 무게"가 아니라 이 4.0배를 출발점으로 삼아라.
    private static let tileSide: CGFloat = 64
    /// iOS 앱 아이콘 곡률은 원이 아니라 squircle 이다. 변의 약 22.37% 가 애플 아이콘 그리드 값이고
    /// `.continuous` 가 그 곡선에 가장 가깝다.
    private static let tileCorner: CGFloat = tileSide * 0.2237

    var body: some View {
        switch mark {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)   // 위 주석 — 머리 그림은 셋 다 장식이다
        case .appIcon:
            Image("AppIconArtwork")
                .resizable()
                .interpolation(.high)
                .frame(width: Self.tileSide, height: Self.tileSide)
                // 원본은 모서리가 직각인 정사각형이다. 홈 화면과 같은 실루엣이 되도록 여기서 깎는다.
                .clipShape(RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous))
                // 라이트 아트워크는 옅은 회색이고 배경도 systemGroupedBackground(옅은 회색)라
                // 테두리가 없으면 경계가 녹는다. 그림자만으로는 위쪽 변이 안 보인다.
                .overlay(
                    RoundedRectangle(cornerRadius: Self.tileCorner, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
                // **머리 그림은 셋 다 장식이다.** 1쪽은 VoiceOver가 "글쇠 앱 아이콘, 이미지"를 읽고
                // 곧바로 제목 "글쇠와 함께"를 읽어 **같은 말을 두 번** 했고, 3쪽은 `lock.shield`의
                // 기본 라벨이 읽혔으며, 2쪽 카드만 이미 숨겨져 있었다 — 셋이 제각각이었다(지적 15).
                // 세 쪽 모두 바로 아래 제목·본문이 같은 뜻을 글로 말하므로 **그림은 숨기는 쪽으로 통일**한다.
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    OnboardingView {}
}
