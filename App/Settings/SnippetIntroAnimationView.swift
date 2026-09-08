import SwiftUI
import TadakDomain
import TadakData

/// 채움글 화면 상단의 안내 애니메이션 카드 — iOS 설정 > 제어 센터 상단의 반복 애니메이션과 같은 역할.
///
/// 장면: "생일축하" 타이핑을 확대 → 축소 → 툴바에 뜬 채움글 칩을 확대 → 탭 → 전문으로 치환 → 반복.
/// 캔버스(모형 화면 360×336)는 고정 레이아웃이고 **카메라 변환(scaleEffect + offset)만** 움직인다 —
/// 루프 중 레이아웃 재계산이 없다. 화면을 떠나면(`.task` 취소) 멈추고, 돌아오면 처음부터 다시 돈다.
/// 동작 줄이기(접근성)가 켜져 있으면 마지막 장면 정지 화면만 보인다.
struct SnippetIntroAnimationView: View {

    let themeID: String
    let appearance: Appearance
    let showsKeyPreview: Bool
    /// 설정 `longPressSymbolsEnabled` — 모형 키에도 같은 기호 힌트를 보인다 (기본 켬)
    var showsLongPressHints = true

    /// 모형 화면 — 호스트 띠(60) + 키보드(230 = 툴바 46 + 자판 180 + 아래 4) = 360×290. 카드 높이 ≈ 폭 × 0.81
    /// (처음 70 + 266 = 336, 폭 × 0.93은 너무 높다는 피드백 2026-09-08)
    static let hostHeight: CGFloat = 60
    static let canvasSize = CGSize(width: MockKeyboardView.width, height: hostHeight + MockKeyboardView.height)
    static let cornerRadius: CGFloat = 10

    @State private var scene: SnippetIntroScene = .initial
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    private static let themeRepository = BundledThemeRepository()

    /// 재생 조건 — 바뀌면 `.task`가 취소·재시작된다 (앱 백그라운드, 동작 줄이기 전환)
    private struct TimelineKey: Equatable {
        let isActive: Bool
        let reduceMotion: Bool
    }

    var body: some View {
        let palette = MockKeyboardPalette(
            spec: Self.themeRepository.theme(id: themeID),
            appearance: appearance,
            systemColorScheme: colorScheme
        )
        GeometryReader { geometry in
            let fit = geometry.size.width / Self.canvasSize.width
            let scale = fit * scene.camera.zoom
            MockPhoneCanvas(scene: scene, palette: palette, showsKeyPreview: showsKeyPreview,
                            showsLongPressHints: showsLongPressHints)
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .scaleEffect(scale, anchor: .center)
                .offset(
                    x: (Self.canvasSize.width / 2 - scene.camera.focusX) * scale,
                    y: (Self.canvasSize.height / 2 - scene.camera.focusY) * scale
                )
                .opacity(scene.canvasOpacity)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(Self.canvasSize.width / Self.canvasSize.height, contentMode: .fit)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("채움글 사용 예")
        .accessibilityValue("입력란에 생일축하를 치면 툴바에 [생일 축하] 칩이 뜨고, 칩을 누르면 축하 인사 전문으로 바뀌어요.")
        .accessibilityAddTraits(.isImage)
        .task(id: TimelineKey(isActive: scenePhase == .active, reduceMotion: reduceMotion)) {
            guard !reduceMotion, scenePhase == .active else {
                scene = .finalFrame
                return
            }
            do {
                while true {
                    try Task.checkCancellation()
                    try await SnippetIntroScript.run { animation, mutate in
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

/// 모형 화면 — 메시지 앱풍 호스트 띠(＋ · 입력란 · 보내기) 위에 모형 키보드. 호스트 색은 시스템 모드를,
/// 키보드 색은 테마를 따른다 (모드를 강제한 테마가 다크 호스트 위에 뜨는 실제 상황과 같다).
private struct MockPhoneCanvas: View {

    let scene: SnippetIntroScene
    let palette: MockKeyboardPalette
    let showsKeyPreview: Bool
    let showsLongPressHints: Bool

    private var showsBody: Bool { scene.text == SnippetIntroDemo.body }

    var body: some View {
        VStack(spacing: 0) {
            hostStrip
                .frame(width: MockKeyboardView.width, height: SnippetIntroAnimationView.hostHeight)
                .background(Color(.systemBackground))
            MockKeyboardView(scene: scene, palette: palette, showsKeyPreview: showsKeyPreview,
                             showsLongPressHints: showsLongPressHints)
        }
        .accessibilityHidden(true)
    }

    /// 입력란은 아래 가장자리(y 54)에 붙어 위로 자란다 — 메시지 앱의 작성란처럼 전문이 들어오면 2줄로 커진다
    private var hostStrip: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color(.secondarySystemFill))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .position(x: 41, y: 35)

            composeField
                .frame(width: 230, height: showsBody ? 52 : 38)
                .position(x: 185, y: 54 - (showsBody ? 26 : 19))

            Circle()
                .fill(palette.accent)
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                }
                .position(x: 329, y: 35)
        }
    }

    private var composeField: some View {
        HStack(alignment: .top, spacing: 1) {
            Text(scene.text.isEmpty ? "메시지" : scene.text)
                .font(.system(size: 15))
                .foregroundStyle(scene.text.isEmpty ? Color(.placeholderText) : Color(.label))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            // 캐럿 — 깜빡이지 않는다(상시 애니메이션을 하나 더 두지 않음). 전문이 들어오면 숨긴다
            RoundedRectangle(cornerRadius: 1)
                .fill(palette.accent)
                .frame(width: 2, height: 18)
                .opacity(showsBody ? 0 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(.systemBackground), in: Capsule())
        .overlay(Capsule().strokeBorder(Color(.separator), lineWidth: 1))
    }
}

#Preview("채움글 안내") {
    NavigationStack {
        Form {
            Section {
                SnippetIntroAnimationView(themeID: "system", appearance: .system, showsKeyPreview: true)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Toggle("채움글 사용", isOn: .constant(true))
            }
        }
        .navigationTitle("채움글")
    }
}
