import SwiftUI
import UIKit

/// 설정 앱의 「입력 테스트」 칸.
///
/// SwiftUI `TextField`가 아니라 `UITextView`를 직접 감싸는 이유는 **하나뿐**이다 —
/// 아이패드에서 소프트 키보드 위에 iOS가 붙이는 **시스템 단축키 바**(↶ 실행취소 · ↷ 다시실행 ·
/// ⧉ 붙여넣기)를 이 칸에서만 끄기 위해서다. 그 바는 `UIResponder.inputAssistantItem`으로만
/// 제어할 수 있는데 SwiftUI `TextField`는 그 responder를 내주지 않는다.
///
/// **왜 끄는가:** 그 바는 우리 UI가 아닌데 우리 툴바 바로 위에 붙어 **툴바가 두 겹으로 보인다.**
/// 스토어 스크린숏에 그대로 찍히면 글쇠의 기능으로 오해받는다 (사용자 지적 2026-09-09).
///
/// **우리 앱 안에서만 끈다.** 키보드 익스텐션은 호스트 앱의 입력란을 건드리지 않는다 —
/// 다른 앱에서 시스템 바를 없애는 것은 사용자 기대를 깨는 짓이고, 애초에 익스텐션에는
/// 그럴 방법도 없다(`inputAssistantItem`은 입력란을 가진 responder의 것이다).
/// 아이폰에는 단축키 바 자체가 없어 이 설정은 아무 일도 하지 않는다 (Apple 문서).
///
/// ## 크기는 우리가 직접 잰다 (2026-09-09)
///
/// 긴 채움글(헌법 제1조·성경 절 범위)이 줄바꿈되지 않고 칸 밖으로 흘러나가던 결함을 고치면서
/// 크기 결정 경로를 전부 명시했다 — 가로 압축 저항 · `sizeThatFits` · 컨테이너 한 겹.
/// 근거는 `docs/design-reviews/input-test-field-wrapping.md`.
struct InputTestField: UIViewRepresentable {

    @Binding var text: String
    let placeholder: String

    /// 기존 `lineLimit(3...6)`과 같은 범위. 6줄을 넘으면 더 늘어나지 않고 안에서 스크롤한다.
    static let minHeight: CGFloat = 66
    static let maxHeight: CGFloat = 132

    func makeUIView(context: Context) -> FieldContainerView {
        let container = FieldContainerView()
        container.textView.delegate = context.coordinator
        container.placeholderLabel.text = placeholder
        context.coordinator.updatePlaceholderVisibility(in: container)
        return container
    }

    func updateUIView(_ container: FieldContainerView, context: Context) {
        if container.textView.text != text { container.textView.text = text }
        context.coordinator.updatePlaceholderVisibility(in: container)
    }

    /// 크기를 SwiftUI에 **직접** 돌려준다 (iOS 16+). 이 구현이 없으면 SwiftUI는 UIKit의
    /// intrinsic content size로 칸을 재는데, 줄바꿈하지 않은 UITextView의 그 폭은 행 폭보다 훨씬 넓다.
    ///
    /// - 폭: 제안받은 행 폭을 그대로 되돌려 텍스트가 그 폭에서 줄바꿈하게 한다.
    ///   (이전 구현은 `bounds.width`가 0인 첫 레이아웃에서 `UIScreen.main.bounds.width` —
    ///   안전 영역·폼 여백을 뺀 실제 행 폭보다 넓은 값 — 으로 높이를 재 한 줄씩 어긋났다.)
    /// - 높이: 그 폭에서의 내용 높이를 66~132pt로 자른다.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView container: FieldContainerView,
                      context: Context) -> CGSize? {
        guard let width = Self.layoutWidth(proposal, in: container) else { return nil }
        let fitted = container.textView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        ).height
        // 6줄(= maxHeight)을 넘으면 더 늘어나는 대신 안에서 스크롤 — 폼 행이 무한정 자라지 않게 한다.
        // 토글은 레이아웃을 한 번 더 돌리게 하지만, `fitted`는 폭에만 의존하므로 두 번째 패스에서
        // 같은 값이 나와 수렴한다.
        let needsScroll = fitted > Self.maxHeight
        if container.textView.isScrollEnabled != needsScroll {
            container.textView.isScrollEnabled = needsScroll
        }
        return CGSize(width: width,
                      height: min(max(fitted, Self.minHeight), Self.maxHeight))
    }

    /// 제안 폭이 없거나(`.unspecified`) 무한대면 현재 bounds로, 그것도 0이면 `nil`을 돌려
    /// SwiftUI 기본 계산에 맡긴다 — 실제 배치 패스에서는 폼이 항상 유한한 행 폭을 제안한다.
    private static func layoutWidth(_ proposal: ProposedViewSize, in view: UIView) -> CGFloat? {
        if let width = proposal.width, width > 0, width < .greatestFiniteMagnitude { return width }
        return view.bounds.width > 0 ? view.bounds.width : nil
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    /// 텍스트 뷰를 감싸는 **평범한** 컨테이너.
    ///
    /// `UITextView`를 representable의 루트로 그대로 내보내면 폼 행(`ListCollectionViewCell`)의
    /// 높이가 SwiftUI가 돌려받은 132pt가 아니라 **텍스트 뷰의 `contentSize`를 따라 계속 자란다**
    /// (실측 2026-09-09: 셀 높이 = `max(162, contentSize − 100)`). 텍스트 뷰 자체는 132pt로
    /// 잘려 있으니 그 아래로 빈 흰 공간만 길게 남는다. 스크롤 뷰가 아닌 컨테이너를 한 겹 씌우면
    /// 셀이 따라갈 `contentSize`가 없어져 행 높이가 우리가 돌려준 값에 고정된다.
    final class FieldContainerView: UIView {

        let textView = UITextView()
        let placeholderLabel = UILabel()

        override init(frame: CGRect) {
            super.init(frame: frame)

            textView.font = .preferredFont(forTextStyle: .body)
            textView.adjustsFontForContentSizeCategory = true
            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.isScrollEnabled = false   // 내용에 맞춰 늘어난다 (높이는 sizeThatFits가 잡는다)
            // 가로 압축 저항을 낮춘다. 기본값(750)이면 `isScrollEnabled = false`인 UITextView의
            // intrinsic 폭 — **가장 긴 문단을 한 줄로 편** 폭 — 이 제안받은 행 폭을 이겨
            // 줄바꿈이 일어나지 않고 칸 밖으로 흘러나간다 (헌법 제1조 채움글 결함, 2026-09-09).
            textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            textView.setContentHuggingPriority(.defaultLow, for: .vertical)

            // ★ 이 한 쌍이 아이패드 단축키 바를 끈다. 빈 배열이면 바가 통째로 사라진다 (Apple 문서).
            textView.inputAssistantItem.leadingBarButtonGroups = []
            textView.inputAssistantItem.trailingBarButtonGroups = []

            placeholderLabel.font = .preferredFont(forTextStyle: .body)
            placeholderLabel.adjustsFontForContentSizeCategory = true
            placeholderLabel.textColor = .placeholderText
            placeholderLabel.numberOfLines = 0
            placeholderLabel.isUserInteractionEnabled = false

            addSubview(textView)
            addSubview(placeholderLabel)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// 오토레이아웃을 쓰지 않는다 — 제약이 걸리면 셀이 다시 그 크기를 따라간다.
        override func layoutSubviews() {
            super.layoutSubviews()
            textView.frame = bounds
            let available = CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
            let labelHeight = placeholderLabel.sizeThatFits(available).height
            placeholderLabel.frame = CGRect(x: 0, y: 0, width: bounds.width, height: labelHeight)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func updatePlaceholderVisibility(in container: FieldContainerView) {
            container.placeholderLabel.isHidden = !container.textView.text.isEmpty
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            if let container = textView.superview as? FieldContainerView {
                updatePlaceholderVisibility(in: container)
            }
        }
    }
}
