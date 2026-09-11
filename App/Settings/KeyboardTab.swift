import SwiftUI
import UIKit
import TadakDomain

/// 자판 탭 — 입력 테스트, 자판(배열·높이·숫자 줄…), 영어(자동 대문자), 피드백(진동·소리).
struct KeyboardTab: View {

    @Binding var settings: KeyboardSettings

    @State private var testText = ""

    var body: some View {
        NavigationStack {
            Form {
                testSection
                layoutSection
                englishSection
                feedbackSection
            }
            .settingsFormWidth()
            .navigationTitle("자판")
            // 입력 테스트 중 빈 여백을 누르면 키보드를 내린다 (사용자 요청 2026-09-10).
            //
            // **SwiftUI 제스처를 Form에 걸지 않는다.** 두 가지를 이미 실패했다:
            //  - `onTapGesture` — 행 상호작용을 통째로 막는다.
            //  - `simultaneousGesture(TapGesture())` — 토글·슬라이더는 통과시키지만
            //    **메뉴 스타일 `Picker`(「한글 자판」)의 짧은 탭을 잡아먹는다.** 짧은 탭이
            //    제스처 경합에서 취소되고 긴 누름만 살아남아, 자판을 바꾸는 주 경로가 막혔다
            //    (검증자 R1, 2026-09-10 — `docs/release/qa-report-baseline-2026-09-10.md` 3-2).
            //
            // 대신 창에 `cancelsTouchesInView = false`인 UIKit 탭 인식기를 건다. 그것은
            // **터치를 가로채지 않고** 탭이 끝났다는 사실만 따로 알려 주므로 아래 뷰(토글·슬라이더·
            // 선택기)는 전부 원래대로 동작한다. 아래 `DismissKeyboardOnTap` 참조.
            .background(DismissKeyboardOnTap().frame(width: 0, height: 0))
            // 스크롤로도 내려간다 — iOS 설정 앱의 표준 동작이다.
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var testSection: some View {
        Section {
            // SwiftUI TextField가 아닌 이유는 InputTestField 주석 참조 —
            // 아이패드 시스템 단축키 바를 이 칸에서만 끄기 위해서다.
            InputTestField(text: $testText, placeholder: "여기에 입력해 키보드를 확인하세요")
                .frame(minHeight: InputTestField.minHeight,
                       maxHeight: InputTestField.maxHeight, alignment: .top)
            if !testText.isEmpty {
                Button("지우기") { testText = "" }
                    .foregroundStyle(.red)
            }
        } header: {
            Text("입력 테스트")
        } footer: {
            Text("키보드가 뜨면 지구본을 눌러 글쇠로 전환하세요.")
        }
    }

    private var layoutSection: some View {
        Section {
            Picker("한글 자판", selection: $settings.activeHangulLayout) {
                ForEach(HangulLayout.allCases, id: \.self) { layout in
                    Text(layout.displayName).tag(layout)
                }
            }

            if settings.activeHangulLayout == .cheonjiin {
                timeoutSlider(
                    "같은 키 연타 인정 시간",
                    value: $settings.cheonjiinTimeout,
                    range: 0.3...1.5
                )
            }
            if settings.activeHangulLayout == .danmoeum {
                timeoutSlider(
                    "연타 승격 인정 시간",
                    value: $settings.danmoeumTimeout,
                    range: 0.2...0.8
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("키보드 높이")
                    Spacer()
                    Text("\(Int((settings.clampedHeightScale * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.keyboardHeightScale,
                       in: KeyboardSettings.heightScaleRange, step: 0.05)
            }
            .padding(.vertical, 2)
            Toggle("키 미리보기", isOn: $settings.showsKeyPreview)
            Toggle("스페이스 두 번으로 마침표", isOn: $settings.doubleSpacePeriod)
            Toggle("숫자 줄 표시", isOn: $settings.numberRowEnabled)
            Toggle("길게 눌러 기호 입력", isOn: $settings.longPressSymbolsEnabled)
        } header: {
            Text("자판")
        } footer: {
            Text("숫자 줄과 길게 눌러 기호 입력은 두벌식·단모음·영어 자판에만 적용돼요.")
        }
    }

    /// 자동 대문자 — 영어 자판 전용. 입력란 규칙(`autocapitalizationType`)과 AND로 합쳐진다
    /// (PDR auto-capitalization).
    private var englishSection: some View {
        Section("영어") {
            Toggle("자동 대문자", isOn: $settings.autoCapitalization)
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("입력 진동", isOn: $settings.hapticEnabled)
            if settings.hapticEnabled {
                levelSlider("진동 세기", value: $settings.hapticIntensity,
                            range: KeyboardSettings.hapticIntensityRange)
            }
            Toggle("입력 소리", isOn: $settings.keySoundEnabled)
            if settings.keySoundEnabled {
                levelSlider("소리 크기", value: $settings.keySoundVolume,
                            range: KeyboardSettings.keySoundVolumeRange)
            }
        } header: {
            Text("피드백")
        } footer: {
            Text("진동은 전체 접근을 허용해야 동작해요.")
        }
    }

    /// 세기·크기 슬라이더 — 10% 단위, 양끝에 약/강 라벨
    private func levelSlider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int((value.wrappedValue * 100).rounded()))%")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.1) {
                Text(title)
            } minimumValueLabel: {
                Text("약").font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("강").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func timeoutSlider(
        _ title: String, value: Binding<TimeInterval>, range: ClosedRange<Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: "%.1f초", value.wrappedValue))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.1)
        }
        .padding(.vertical, 2)
    }
}

/// 지금 first responder를 내려 키보드를 감춘다.
///
/// 입력 테스트 칸은 `UITextView`를 감싼 `InputTestField`라 SwiftUI `@FocusState`가 닿지 않는다
/// (그 칸이 UIKit인 이유는 아이패드 시스템 단축키 바를 끄기 위해서다 — `InputTestField` 주석 참조).
/// 그래서 responder 사슬에 `resignFirstResponder`를 흘려보낸다. 컨테이너 앱이라 `UIApplication`을 쓸 수 있다
/// (키보드 익스텐션에서는 못 쓴다).
@MainActor
func dismissKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}

/// 빈 여백 탭으로 키보드를 내린다 — **Form의 스크롤 뷰에 붙는 UIKit 탭 인식기.**
///
/// SwiftUI 제스처로는 풀 수 없었다(위 `KeyboardTab.body` 주석의 실패 두 건).
/// `cancelsTouchesInView = false`인 `UITapGestureRecognizer`는 **터치를 가로채지 않는다** —
/// 아래 뷰는 터치를 그대로 받고 우리는 "탭이 끝났다"는 사실만 별도로 전달받는다.
/// `delaysTouchesEnded = false`까지 꺼야 touch-up이 지연 없이 아래로 내려간다(기본값은 `true`).
///
/// **붙이는 자리는 Form의 스크롤 뷰다**(2026-09-10, 검증자 지적 반영). 예전에는 창에 붙였는데,
/// 그러면 KeyboardTab이 살아 있는 동안 **앱 전체의 탭**이 이 인식기를 거친다 — 탭 바·내비게이션 바처럼
/// 이 화면과 무관한 곳까지 포함된다. 스크롤 뷰에 붙이면 "이 Form 안의 탭"으로 범위가 좁혀지고,
/// 원 요구("Form의 빈 여백")와도 정확히 겹친다. 스크롤 뷰를 아직 못 찾은 첫 패스에서는 창으로
/// 폴백하고, 찾는 즉시 옮겨 단다.
private struct DismissKeyboardOnTap: UIViewRepresentable {

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let anchor = AnchorView()
        anchor.isUserInteractionEnabled = false   // 자리만 잡고 터치는 건드리지 않는다
        anchor.onWindowChange = { [coordinator = context.coordinator] anchor in
            coordinator.attach(from: anchor)
        }
        return anchor
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    /// 창에 붙는 순간을 알려 주는 신호는 `didMoveToWindow`뿐이다 —
    /// `updateUIView`는 뷰가 아직 창에 없을 때도 불린다.
    final class AnchorView: UIView {
        var onWindowChange: ((UIView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(self)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {

        private weak var host: UIView?
        private var recognizer: UITapGestureRecognizer?
        /// 스크롤 뷰에 제대로 붙었는가. 거짓이면 창 폴백 상태라 다음 기회에 다시 시도한다.
        private var attachedToScrollView = false

        func attach(from anchor: UIView) {
            let scrollView = Self.enclosingScrollView(of: anchor)
            let target: UIView? = scrollView ?? anchor.window
            guard let target else { return }
            // 이미 같은 자리에 붙어 있고, 그 자리가 스크롤 뷰라면 그대로 둔다.
            if target === host, attachedToScrollView || scrollView == nil { return }
            detach()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            // 이 세 줄이 R1의 핵심이다 — 인식기가 아래 뷰의 터치를 훔치거나 늦추지 않는다.
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            target.addGestureRecognizer(tap)
            host = target
            recognizer = tap
            attachedToScrollView = (scrollView != nil)
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
            host = nil
            attachedToScrollView = false
        }

        private static func enclosingScrollView(of view: UIView) -> UIScrollView? {
            var node: UIView? = view.superview
            while let current = node {
                if let scroll = current as? UIScrollView { return scroll }
                node = current.superview
            }
            return nil
        }

        @objc private func handleTap() { dismissKeyboard() }

        /// 누구와도 경합하지 않는다 — 항상 함께 인식한다.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// **조작 대상을 누른 터치는 받지 않는다 — 빈 여백만 받는다.**
        ///
        /// 기획자 결정 (A)(`docs/release/ux-decision-keyboardtab-dismiss.md`):
        /// 이 화면은 "키보드를 띄운 채 슬라이더·토글을 바꾸면 그 자리에서 키보드가 바뀐다"는
        /// 라이브 미리보기가 존재 이유다. 컨트롤을 만질 때마다 키보드가 내려가면 그 기능이 성립하지 않는다.
        ///
        /// 두 갈래를 거른다:
        ///  - **텍스트 입력**(`UITextView`·`UITextField`) — 칸을 눌러 포커스한 그 손가락이 떼는 순간
        ///    도로 내려가는 것을 막는다.
        ///  - **`UIControl`** — SwiftUI `Toggle`은 실제 `UISwitch`, `Slider`는 실제 `UISlider`로
        ///    내려온다(iOS 26.5 실측: `UISwitch < UIKitPlatformViewHost<…Switch>`,
        ///    `UISlider < UIKitPlatformViewHost<…SystemSlider>`). 그래서 `UIControl` 조상 하나로
        ///    토글·슬라이더·버튼이 함께 걸러진다.
        ///
        /// **메뉴 스타일 `Picker`(「한글 자판」)는 이 규칙으로 걸러지지 않는다.** iOS 26.5 실측에서
        /// 그 행의 터치는 `CellHostingView < _UICollectionViewListCellContentView < ListCollectionViewCell`에
        /// 떨어지고 **`UIControl`이 없으며**, 붙어 있는 제스처 인식기(hover·longPress)까지
        /// **비대화 행 배경과 완전히 같다** — 터치 시점에 둘을 가를 구조적 단서가 없다.
        /// SwiftUI가 호스팅 뷰 안에서 자체 라우팅으로 메뉴를 열기 때문이다.
        /// 선택기 자체는 정상 동작한다(인식기가 터치를 가로채지 않으므로 짧은 탭에 메뉴가 열리고
        /// 선택도 반영된다 — R1 수정 그대로). 다만 그 탭에서는 키보드가 함께 내려간다.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            var node = touch.view
            while let current = node {
                if current is UITextView || current is UITextField { return false }
                if current is UIControl { return false }
                node = current.superview
            }
            return true
        }
    }
}
