import SwiftUI
import TadakDomain

/// 테마 하나의 **소형 미리보기 카드** — 고르기 전에 어떤 키보드인지 보여 준다.
///
/// ## 왜 있나
///
/// 예전 화면 탭은 테마 이름 + 색 동그라미 다섯 개가 전부였다. 실제로 어떤 키보드인지
/// **고르기 전에는 알 수 없어서** 사용자가 고르고 → 키보드를 열어 보고 → 마음에 안 들면
/// 다시 설정으로 돌아오는 왕복을 했다. 그 왕복을 없앤다.
/// 설계: `docs/design-reviews/v1.1.0-plan-v3.md` 5절 (critique-B B3-1 반영본).
///
/// ## ★ 구조 결정 — 왜 `MockKeyboardView` 를 안 쓰나
///
/// 2차 계획이 채움글 안내의 `MockKeyboardView` 를 재사용하려다 반론에서 깨졌다.
/// 그 파일은 **`SnippetIntroScene`(채움글 안내 장면)을 전제**하고 `MockKeyGrid` 가 `private` 이며
/// 두벌식 배열이 하드코딩돼 있다. **사용처가 둘로 늘면 한쪽을 고칠 때 다른 쪽이 stale 해진다.**
/// 그래서 여기 **App 전용 작은 뷰 하나**를 새로 만든다 — `MockKeyboardView` 는 손대지 않는다.
///
/// **`App/` 은 `KeyboardUI` 를 import 하지 않는다**(PDR settings-app 결정 5, 수용 기준 5번).
/// 이 파일도 `TadakDomain` 만 쓴다.
///
/// **그림 파일(PNG)로 만들지 않는다.** CLAUDE.md 가 "새 테마 추가 = `Themes.json` 한 줄
/// (코드 변경 없음)"을 못박는다. PNG 면 테마마다 이미지를 다시 만들어야 해서 그 원칙이 깨진다.
/// **코드로 그린다.**
struct ThemePreviewCard: View {

    let theme: ThemeSpec
    let isSelected: Bool

    /// 접근성 큰 글자에서 **두 미리보기를 세로로 쌓는다.** 가로로 두면 폭이 모자라 잘린다.
    /// 수용 기준 4번이 "AX3 이상에서 잘리지 않는다(스크롤 허용, 고정 높이 가정 없음)"다 —
    /// 카드가 세로로 늘어나는 것을 **허용하는 것이 설계**다.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    labeledPreview(theme.light, caption: "라이트")
                    labeledPreview(theme.dark, caption: "다크")
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    labeledPreview(theme.light, caption: "라이트")
                    labeledPreview(theme.dark, caption: "다크")
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // 카드 하나 = 접근성 요소 하나. 안의 색 사각형은 읽어 줄 것이 없다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.displayName), 라이트와 다크 미리보기")
        .accessibilityValue(isSelected ? "선택됨" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var header: some View {
        HStack {
            Text(theme.displayName)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
            }
        }
    }

    private func labeledPreview(_ palette: ThemeSpec.Palette, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
            MiniKeyboardPreview(palette: palette, cornerRadius: theme.keyCornerRadius)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 팔레트 **다섯 값을 전부** 보여 주는 최소 키보드 그림.
///
/// ## 다섯 값이 각각 어디 있나 — hex 대조로 확인할 수 있어야 한다 (수용 기준 2번)
///
/// | 팔레트 값 | 카드에서 보이는 곳 |
/// |---|---|
/// | `keyboardBackground` | 바깥 판 전체 |
/// | `characterKey` | 문자 키 세 개 |
/// | `functionKey` | 오른쪽 넓은 기능 키 하나 |
/// | **`keyText`** | 키 위의 글자·기호 — **사각형만으로는 안 보이는 값이라 글자로 얹는다** |
/// | `accent` | 위쪽 후보 칩 자리의 작은 캡슐 |
///
/// 2차 계획이 `keyText` 를 빠뜨려 반론에서 깨졌다(B3-1). 글자색은 색 사각형으로 표현할 수
/// 없으므로 **반드시 글자로** 보여 준다.
///
/// ## 배열은 실제 키보드가 아니다
///
/// 세 글자 + 기능 키 하나짜리 **상징**이다. 실제 자판(두벌식·천지인·단모음·쿼티)을 흉내 내지
/// 않는다 — 흉내 내는 순간 자판이 바뀔 때마다 여기도 따라 고쳐야 하고, 그게 `MockKeyboardView`
/// 를 재사용하지 않기로 한 이유와 같은 문제다. 여기서 보여 줄 것은 **색이지 배열이 아니다.**
private struct MiniKeyboardPreview: View {

    let palette: ThemeSpec.Palette
    let cornerRadius: Double

    /// 큰 글자에서 키도 함께 커진다 — 고정 크기로 두면 글자만 커져 키 밖으로 넘친다.
    @ScaledMetric(relativeTo: .caption2) private var keyHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption2) private var chipHeight: CGFloat = 8
    @ScaledMetric(relativeTo: .caption2) private var chipWidth: CGFloat = 30

    /// 키에 얹는 글자 — 한글 자음 셋. `keyText` 가 실제로 어떤 색인지 보이게 하는 것이 목적이다.
    private static let keyLabels = ["ㄱ", "ㄴ", "ㄷ"]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 후보 칩 자리 — `accent` 가 드러나는 유일한 자리다
            Capsule()
                .fill(Color(themeHex: palette.accent))
                .frame(width: chipWidth, height: chipHeight)
            HStack(spacing: 4) {
                ForEach(Self.keyLabels, id: \.self) { label in
                    key(fill: palette.characterKey) {
                        Text(label)
                    }
                }
                key(fill: palette.functionKey) {
                    Image(systemName: "delete.left")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(Color(themeHex: palette.keyboardBackground))
        )
        .overlay(
            // 배경이 카드 배경과 같은 색일 때(퓨어 라이트) 판의 경계가 사라지지 않게
            RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 0.5)
        )
        .accessibilityHidden(true)   // 부모 카드가 하나의 요소로 읽어 준다
    }

    private func key<Content: View>(
        fill hex: String,
        @ViewBuilder label: () -> Content
    ) -> some View {
        label()
            .font(.system(size: 11))
            .foregroundStyle(Color(themeHex: palette.keyText))
            .frame(minWidth: keyHeight, minHeight: keyHeight)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius / 2).fill(Color(themeHex: hex))
            )
    }
}
