import SwiftUI

/// 아이패드 대응 레이아웃 보정 (PDR ipad-support).
///
/// 설정 앱은 아이폰 폭(320~440pt)을 전제로 짜였다. 아이패드 세로는 834pt, 13인치는 1024pt라
/// 같은 화면이 그대로 늘어나면 Form 행의 토글이 화면 오른쪽 끝에 붙고 온보딩 문구가 왼쪽 위로
/// 몰린다 (QA BLOCK-1 §4). 애플 자체 설정 앱도 넓은 화면에서는 내용 폭을 제한한다.
///
/// **아이폰에서는 아무 것도 하지 않는다** — idiom으로 분기해 회귀 여지를 없앤다
/// (`horizontalSizeClass`는 아이폰 Max 가로에서도 `.regular`라 폭을 잘못 좁힌다).
enum AdaptiveLayout {
    /// 설정 Form 내용의 최대 폭. 아이패드 세로(834pt)에서 좌우에 100pt씩 남는 값.
    static let formMaxWidth: CGFloat = 640
    /// 온보딩 한 페이지 내용의 최대 폭.
    static let onboardingMaxWidth: CGFloat = 560

    static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
}

private struct ReadableWidth: ViewModifier {
    let maxWidth: CGFloat
    /// 폭을 좁히면 좌우에 빈 띠가 생긴다 — 그 띠를 같은 색으로 칠해 화면이 갈라져 보이지 않게 한다.
    let background: Color?

    func body(content: Content) -> some View {
        if AdaptiveLayout.isPad {
            content
                // Form 자체 배경을 숨기고 아래에서 전폭으로 칠한다 — 폭만 좁히면 좌우·상하 여백이
                // 흰 띠로 남아 화면이 세 조각으로 보인다 (2026-09-08 실기 확인)
                .scrollContentBackground(background == nil ? .automatic : .hidden)
                .frame(maxWidth: maxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background?.ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    /// 아이패드에서만 내용 폭을 제한하고 가운데로 모은다. 아이폰은 그대로다.
    ///
    /// **세로로도 꽉 채운다** (`maxHeight: .infinity`) — 배경을 전폭으로 칠하려면 그래야 한다.
    /// 그래서 VStack 안의 **버튼처럼 크기가 정해진 뷰에는 쓰면 안 된다**: 남은 세로 공간을
    /// 전부 먹고 그 한가운데에 자리 잡아, 하단에 붙어 있어야 할 버튼이 허공에 뜬다
    /// (2026-09-09 실측 — 온보딩 버튼이 화면 하단 24pt가 아니라 837pt에 떴다).
    /// 그런 자리에는 `readableContentWidth(_:)`를 쓴다.
    func readableWidth(_ maxWidth: CGFloat, background: Color? = nil) -> some View {
        modifier(ReadableWidth(maxWidth: maxWidth, background: background))
    }

    /// 아이패드에서만 **폭만** 제한한다 — 세로 배치는 건드리지 않는다.
    /// 아이폰은 뷰를 그대로 돌려주므로 회귀 여지가 없다.
    @ViewBuilder
    func readableContentWidth(_ maxWidth: CGFloat) -> some View {
        if AdaptiveLayout.isPad {
            frame(maxWidth: maxWidth)
        } else {
            self
        }
    }

    /// 설정 탭의 Form에 붙인다 — 아이패드에서 행이 전폭으로 늘어나지 않게.
    func settingsFormWidth() -> some View {
        readableWidth(AdaptiveLayout.formMaxWidth, background: Color(.systemGroupedBackground))
    }
}
