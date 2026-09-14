import SwiftUI

/// 온보딩 2쪽("키보드 추가하기")의 안내 애니메이션 카드.
///
/// 장면: `설정 › 글쇠 › 키보드` 카드 → 스위치 확대·탭 → 스위치 ON → 아래로 이동 →
/// 입력창 + 애플 한글 자판 → 지구본 탭 → **그 자리에서 글쇠로 교체** → 반복.
///
/// > **2026-09-14 재설계로 이 줄을 고쳤다.** 예전 서술("키보드 목록 → 체크 → 전환 목록에서 글쇠")은
/// > **셋 다 없어진 화면**이다. 목록도 체크도 전환 목록도 그리지 않는다 — 실제 iOS 는 스위치 하나이고,
/// > 지구본은 탭하면 바로 넘어간다. 같은 파일의 `accessibilityValue` 는 이 종류의 낡음을 찾아 고쳐 놓고
/// > **머리글만 놓쳤다**(반론자 I-1). 그림을 바꾸면 이 다섯 줄부터 고친다.
///
/// 캔버스(360×400)는 **좌표계가 고정**이고 카메라 변환(`scaleEffect` + `offset`)만 움직인다.
/// 화면을 떠나면(`.task` 취소) 멈추고, 돌아오면 처음부터 다시 돈다.
/// 동작 줄이기(접근성)가 켜져 있으면 정지 화면만 보인다.
///
/// > **"루프 중 레이아웃 재계산이 없다"고 쓰지 않는다 — 한 군데 있다**(반론자 I-4).
/// > 3박자에서 `activeKeyboard` 가 바뀌면 `rowHeight` 28→24 · `rowGap` 5→4 · `firstRowTop` 262→284 가
/// > 함께 바뀌어 **키캡 약 30개의 frame·position 이 스프링 안에서 다시 계산된다.**
/// > 동작은 의도한 것이고(두 자판을 툴바 유무로 가르려면 줄 높이가 달라야 한다) 틀린 건 예전 문장이었다.
/// > **이 루프에서 가장 무거운 순간이 정확히 거기다** — CPU 피크가 3박자에서 나오는 이유이기도 하다.
///
/// **채움글 카드(`SnippetIntroAnimationView`)와 무엇이 다른가.**
/// 그 카드는 키보드 자체를 보여 주므로 `MockKeyboardView`(KeyboardUI 상수 미러)를 쓴다. 이 카드가 그리는 것은
/// **iOS 설정 화면과 입력 장면**이고, 자판은 "바뀌었다"를 보이기 위한 삽화라 두벌식 엔진·툴바·칩·테마
/// 팔레트가 필요 없다. 그래서 `MockKeyboardView`를 재사용하지도, 복제하지도 않는다.
/// (키캡 모서리만 아래 `keyCornerRadius` 에서 미러한다. **눌림 60% 는 미러하지 않는다** —
/// 왜 미러할 수 없는지는 `keyCap(width:pressed:content:)` 주석에 적었다.)
/// 근거: `docs/design-reviews/onboarding-refresh.md`.
///
/// **애플 UI를 베끼지 않는다.** 설정 화면은 행 높이·모서리·구분선만 남긴 추상 형태이고, 시스템 아이콘·
/// 실제 문구·파란 셰브런을 쓰지 않는다. 색은 전부 시스템 의미색이라 라이트·다크를 자동으로 따른다.
struct InstallIntroAnimationView: View {

    /// 캔버스 — 설정 블록(y 32…176) + 여백 + 자판 블록(y 219.5…394).
    /// 두 블록 사이를 비운 이유: 설정 확대(`.settingsRow`)에서 보이는 아래 끝이 y 212 라
    /// 자판 블록이 그보다 위에서 시작하면 확대 프레임에 다음 장면이 미리 새어 든다 (2026-09-14 실측으로 발견).
    /// **자판 블록 아래 끝(394)에 여유 6 을 더한 400 이 캔버스 높이다** — `.keyboard` 카메라가
    /// 398 까지 보므로 그보다 낮으면 키가 잘린다(지적 5·6·11 이 그 상태였다).
    static let canvasSize = CGSize(width: 360, height: 400)
    /// 카드에 한 번에 보이는 창(캔버스 단위). 카드 높이 ≈ 폭 × 0.5
    static let viewportSize = CGSize(width: 360, height: 180)
    /// mirror: App/Settings/SnippetIntroAnimationView.swift cornerRadius — 두 카드의 모서리를 같게 둔다
    static let cornerRadius: CGFloat = 10

    @State private var scene: InstallIntroScene = .initial
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// 재생 조건 — 바뀌면 `.task`가 취소·재시작된다 (앱 백그라운드, 동작 줄이기 전환)
    private struct TimelineKey: Equatable {
        let isActive: Bool
        let reduceMotion: Bool
    }

    var body: some View {
        GeometryReader { geometry in
            let fit = geometry.size.width / Self.viewportSize.width
            let scale = fit * scene.camera.zoom
            InstallIntroCanvas(scene: scene)
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .scaleEffect(scale, anchor: .center)
                .offset(
                    x: (Self.canvasSize.width / 2 - scene.camera.focusX) * scale,
                    y: (Self.canvasSize.height / 2 - scene.camera.focusY) * scale
                )
                .opacity(scene.canvasOpacity)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(Self.viewportSize.width / Self.viewportSize.height, contentMode: .fit)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        // 온보딩 배경(systemGroupedBackground)과 카드 배경(secondarySystemGroupedBackground)은
        // 라이트에서 둘 다 흰색이라 테두리가 없으면 카드가 배경에 녹는다 (채움글 카드는 Form 행 안이라 필요 없었다).
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.6), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("글쇠를 켜는 방법")
        // **그림이 바뀌면 이 문장도 바뀐다.** 예전 값은 "설정의 키보드 목록에서 글쇠를 눌러 켜고"였는데
        // 2박자를 실제 화면(행 하나 + 스위치)으로 다시 그리면서 **목록도 탭도 없어졌다.**
        // VoiceOver 사용자는 그림을 볼 수 없으므로 이 문장이 그림의 전부다 — 어긋나면 그게 오정보다.
        .accessibilityValue("설정 > 앱 > 글쇠 > 키보드에서 글쇠 스위치를 켜고, 입력할 때 지구본을 눌러 글쇠로 바꿔요.")
        .accessibilityAddTraits(.isImage)
        .task(id: TimelineKey(isActive: scenePhase == .active, reduceMotion: reduceMotion)) {
            guard !reduceMotion, scenePhase == .active else {
                scene = .finalFrame
                return
            }
            do {
                while true {
                    try Task.checkCancellation()
                    try await InstallIntroScript.run { animation, mutate in
                        if let animation {
                            withAnimation(animation) { mutate(&scene) }
                        } else {
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { mutate(&scene) }
                        }
                    }
                }
            } catch {
                // CancellationError — 화면을 떠났거나 재생 조건이 바뀌었다. 다음 등장 때 처음부터.
            }
        }
    }
}

// MARK: - 캔버스

/// 고정 좌표계(360×400) 위에 두 블록을 그린다. 블록의 **바깥 사각형**은 전부 상수다.
/// 장면 값에 따라 바뀌는 것은 대부분 색·투명도·스위치 노브 위치인데, **예외가 하나 있다** —
/// `activeKeyboard` 가 바뀌면 자판 줄 높이·간격·시작 y 가 함께 바뀌어 키캡 프레임이 다시 계산된다
/// (반론자 I-4, 파일 상단 주석 참조). 바깥 사각형이 같아 카드 높이는 흔들리지 않는다.
private struct InstallIntroCanvas: View {

    let scene: InstallIntroScene

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            settingsBlock
            keyboardBlock
        }
        .frame(width: InstallIntroAnimationView.canvasSize.width,
               height: InstallIntroAnimationView.canvasSize.height,
               alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: 설정 블록 — 실제 iOS 화면 그대로 (내용 y 23.5…132)
    //
    // **디자이너가 시뮬레이터로 iOS 설정을 직접 걸어 실측한 화면이다** (2026-09-14, PDR B-0).
    // `설정 > 앱 > 글쇠 > 키보드` 는 **「글쇠」 행 하나 + 스위치(꺼짐) + 경고 문단**이 전부다
    // (증거: `docs/release/screens/settings-path-2-keyboard-before.png`).
    //
    // 예전 판이 그리던 **한국어/English/글쇠 3행 목록은 iOS 어디에도 없다.** 행을 탭하면 체크가
    // 붙는다고 그렸는데 실제로 켜는 컨트롤은 **스위치**다 — 검토 지적 8·10 의 2박자 몫이 여기서 닫힌다.
    //
    // **애플 UI 를 베끼지 않는 선**(PDR B-6): 경고 문단은 글자로 옮기지 않고 회색 막대 둘로만 두고,
    // 시스템 아이콘·내비게이션 바·뒤로 화살표를 그리지 않는다. **「전체 접근 허용」 행도 그리지 않는다** —
    // 켠 뒤 행이 생기면 카드 높이가 루프 중에 바뀌어 "레이아웃 고정, 카메라만 이동"을 깨고,
    // 우리 문구가 "선택"이라 부르는 것이 설치 안내에 같이 보이면 필수처럼 읽힌다.

    private static let pathCardRect = CGRect(x: 40, y: 46, width: 280, height: 52)
    private static let rowTextX: CGFloat = 60
    private static let textBoxWidth: CGFloat = 180
    private static let switchTrack = CGRect(x: 245, y: 57, width: 51, height: 31)
    private static let knobDiameter: CGFloat = 27
    private static let knobOffX: CGFloat = 262.5
    private static let knobOnX: CGFloat = 278.5

    // 자판 블록
    /// mirror: App/Settings/MockKeyboardView.swift 키캡 모서리(테마 기본 5)보다 삽화라 조금 크게 둔다
    private static let keyCornerRadius: CGFloat = 8

    private var settingsBlock: some View {
        ZStack(alignment: .topLeading) {
            Text(InstallIntroCopy.pathHeading)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 240, alignment: .leading)
                .position(x: 180, y: 30)

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color(.separator).opacity(0.8), lineWidth: 0.5)
                )
                .frame(width: Self.pathCardRect.width, height: Self.pathCardRect.height)
                .position(x: Self.pathCardRect.midX, y: Self.pathCardRect.midY)

            Text(InstallIntroCopy.appName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.label))
                .frame(width: Self.textBoxWidth, alignment: .leading)
                .position(x: Self.rowTextX + Self.textBoxWidth / 2, y: 72)

            toggleSwitch
            warningBars

            if scene.showsTapIndicator, scene.camera.zoom > 1 {
                tapIndicator.position(x: 270.5, y: 72.5)
            }
        }
    }

    /// iOS 스위치. **켜짐만 `systemGreen` 이다** — 실제 화면이 초록이라 사실이고,
    /// 우리 파랑으로 바꾸면 오히려 실제와 달라진다(PDR B-6).
    private var toggleSwitch: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(scene.keyboardEnabled ? Color(.systemGreen) : Color(.systemFill))
                .frame(width: Self.switchTrack.width, height: Self.switchTrack.height)
                .position(x: Self.switchTrack.midX, y: Self.switchTrack.midY)

            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                // 눌린 노브만 살짝 커진다 — 카드 높이는 그대로라 레이아웃이 흔들리지 않는다.
                .frame(width: knobSize, height: knobSize)
                .position(x: scene.keyboardEnabled ? Self.knobOnX : Self.knobOffX, y: 72.5)
        }
    }

    private var knobSize: CGFloat {
        scene.press == .settingsRow ? Self.knobDiameter + 2 : Self.knobDiameter
    }

    /// 타사 키보드 경고 문단 — **글자로 옮기지 않는다.** 회색 막대 둘로 "문단이 있다"만 말한다.
    private var warningBars: some View {
        ZStack(alignment: .topLeading) {
            ForEach([(CGFloat(60), CGFloat(300), CGFloat(112)),
                     (CGFloat(60), CGFloat(250), CGFloat(125))], id: \.2) { x0, x1, y in
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(Color(.separator))
                    .frame(width: x1 - x0, height: 7)
                    .position(x: (x0 + x1) / 2, y: y + 3.5)
            }
        }
    }

    // MARK: 입력 블록 (y 216…394 — 입력창 216…248 · 자판 256…394)
    //
    // **3박자는 "입력창 + 자판" 이다.** 사용자 지시(2026-09-14): "지구본을 누를 버튼이 안 보이니
    // 사용자가 답답할 것 같다, 입력창을 추가하자. 지구본을 누르고 기본 애플키보드에서 글쇠
    // 키보드로 바뀌는 모습을 보여주라." 입력창이 **자판이 왜 올라와 있는지**를 설명하고,
    // 지구본을 누르면 **그 자리에서** 자판이 교체된다(전환 목록을 띄우지 않는다 — `ActiveKeyboard` 주석).
    //
    // 세로 예산: 216…394 = 178 이고 카메라가 보는 높이는 180 이다. **2 밖에 안 남는다** —
    // 여기 수치를 키우면 바로 잘린다. 캔버스 높이 400 과 `Camera.keyboard.focusY = 305` 가
    // 이 범위에서 나온 값이다. 셋은 함께 움직인다.

    private static let fieldRect = CGRect(x: 40, y: 216, width: 280, height: 32)
    private static let boardRect = CGRect(x: 20, y: 256, width: 320, height: 138)

    private var keyboardBlock: some View {
        ZStack(alignment: .topLeading) {
            inputField
            keyboardSurface
            if scene.showsTapIndicator, scene.camera.focusY > 250 {
                tapIndicator
                    // **지구본 키 한가운데에 얹는다.** 키 아래는 카메라 창 밖이다 —
                    // 예전 판이 키 아래에 둬서 탭 표시가 100% 안 보였다(지적 5).
                    .position(x: Self.globeCenterX, y: globeCenterY)
            }
        }
    }

    /// 입력창 — 시연 문구는 상수이고 커서는 장면 값이 켜고 끈다.
    private var inputField: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(.separator), lineWidth: 1)
                }
                .frame(width: Self.fieldRect.width, height: Self.fieldRect.height)

            HStack(spacing: 2) {
                Text(InstallIntroCopy.fieldText)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(.label))
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 18)
                    .opacity(scene.caretVisible ? 1 : 0)
            }
            .padding(.leading, 12)
        }
        .frame(width: Self.fieldRect.width, height: Self.fieldRect.height)
        .position(x: Self.fieldRect.midX, y: Self.fieldRect.midY)
    }

    // MARK: 자판 두 벌
    //
    // **글자는 같다. 두벌식이니 당연하다.** 차이는 **툴바 유무와 바탕색**으로 낸다 —
    // 바뀌기 전과 후가 구분돼야 3박자가 성립한다(사용자 지시: "기본 애플키보드에서 글쇠
    // 키보드로 바뀌는 모습"). 애플 쪽은 회색 바탕에 흰 키캡, 글쇠 쪽은 강조색이 섞인 바탕에
    // **툴바 한 줄**이 붙는다. 툴바는 글쇠의 서명이라 도착 신호로 가장 분명하다.
    //
    // **KeyboardUI 를 import 하지 않는다** — 모형으로 그린다(파일 상단 규율).

    private var isGeulsoe: Bool { scene.activeKeyboard == .geulsoe }
    /// 글쇠는 툴바(20)가 위에 붙어 키 줄이 그만큼 낮아진다. 두 벌의 **바깥 사각형은 같다.**
    private var rowHeight: CGFloat { isGeulsoe ? 24 : 28 }
    private var rowGap: CGFloat { isGeulsoe ? 4 : 5 }
    private var firstRowTop: CGFloat { isGeulsoe ? Self.boardRect.minY + 28 : Self.boardRect.minY + 6 }
    private func rowTop(_ index: Int) -> CGFloat { firstRowTop + CGFloat(index) * (rowHeight + rowGap) }
    private var globeCenterY: CGFloat { rowTop(3) + rowHeight / 2 }
    private static let globeCenterX: CGFloat = 48

    private var keyboardSurface: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isGeulsoe ? Color.accentColor.opacity(0.12) : Color(.systemGray5))
                .frame(width: Self.boardRect.width, height: Self.boardRect.height)
                .position(x: Self.boardRect.midX, y: Self.boardRect.midY)

            if isGeulsoe { toolbarStrip }

            ForEach(Array(InstallIntroCopy.hangulRows.enumerated()), id: \.offset) { index, row in
                letterRow(row, at: index)
            }
            bottomRow
        }
    }

    /// 글쇠 툴바 — 도구 아이콘 다섯. 실제 툴바가 하는 일을 형태로만 옮긴다.
    private var toolbarStrip: some View {
        HStack(spacing: 14) {
            ForEach(["chevron.left", "chevron.right", "doc.on.clipboard", "face.smiling", "keyboard.chevron.compact.down"], id: \.self) { name in
                Image(systemName: name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: Self.boardRect.width - 16, height: 20)
        .position(x: Self.boardRect.midX, y: Self.boardRect.minY + 14)
    }

    /// 글자 줄. 세 줄 모두 **가운데 정렬**이라 줄마다 키 수가 달라도 균형이 맞는다.
    private func letterRow(_ row: String, at index: Int) -> some View {
        let keys = Array(row)
        let width = Self.keyWidth
        let total = CGFloat(keys.count) * width + CGFloat(keys.count - 1) * Self.keyGap
        return HStack(spacing: Self.keyGap) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, ch in
                keyCap(width: width) {
                    Text(String(ch))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Color(.label))
                }
            }
        }
        .frame(width: total, height: rowHeight)
        .position(x: Self.boardRect.midX, y: rowTop(index) + rowHeight / 2)
    }

    /// 하단 행 — 지구본 · 스페이스 · 리턴. **지구본이 이 장면의 주인공이다.**
    private var bottomRow: some View {
        let y = rowTop(3) + rowHeight / 2
        return ZStack(alignment: .topLeading) {
            keyCap(width: 44, pressed: scene.press == .globeKey) {
                Image(systemName: "globe")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(.label))
            }
            .position(x: Self.globeCenterX, y: y)

            keyCap(width: 168) { Color.clear }
                .position(x: 160, y: y)

            keyCap(width: 44) {
                Image(systemName: "return")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(.label))
            }
            .position(x: 292, y: y)
        }
    }

    private static let keyGap: CGFloat = 3
    /// 가장 긴 줄(10키)이 자판 안쪽 폭에 들어가도록 되짚는다.
    private static let keyWidth: CGFloat = (boardRect.width - 12 - keyGap * 9) / 10

    @ViewBuilder
    private func keyCap<Content: View>(width: CGFloat, pressed: Bool = false,
                                       @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.keyCornerRadius, style: .continuous)
                // **여기는 `KeyCapView` 를 미러하지 않는다 — 미러할 수 없다.**
                // 실제 규칙은 `isPressed ? base.opacity(0.6) : base`(KeyCapView:139)이고 거기서
                // `base` 는 **불투명한 테마 키 색**이다. 키보드 배경이 키보다 어두우니 60%로 내리면
                // 어두워지는데, 이 모형의 키캡 바탕은 **흰 키캡**이라 같은 식이 반대로 작동한다.
                // 그래서 규칙을 **"눌리면 바탕과의 대비를 키운다"** 로 바꿔 적는다.
                // 라이트: 흰 키캡(255) → systemGray3(199) = 56단계. 다크에서도 같은 방향으로 벌어진다.
                // 예전 판은 1.6단계 차이에 **눌린 쪽이 더 밝아** 사실상 신호가 없었다(지적 7).
                .fill(pressed ? Color(.systemGray3) : Color(.systemBackground))
            content()
        }
        .frame(width: width, height: rowHeight)
    }

    /// 누르는 지점 표시 — 손가락 대신 반투명 원 하나. 실제 손 그림은 라이트·다크 양쪽에서
    /// 색을 맞추기 어렵고 캔버스 확대에 따라 커져 조잡해진다.
    private var tapIndicator: some View {
        Circle()
            .fill(Color(.label).opacity(0.22))
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(Color(.label).opacity(0.35), lineWidth: 1.5))
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

#Preview("온보딩 설치 안내") {
    VStack {
        InstallIntroAnimationView()
            .padding(.horizontal, 32)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(.systemGroupedBackground))
}
