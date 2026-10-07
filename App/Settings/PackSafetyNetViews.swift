import SwiftUI
import PackImport

// 외부 채움글 1-c 2단계 — 안전망 화면 부품(계획서 `external-snippet-packs-1c-plan.md` 4-1 ㉠㉡㉢·4-3절, PDR R24·R25).
// 문구는 전부 `PackNoticeCopy`(PackImport — `swift test`가 U6·금칙어·한도 숫자를 검사한다). 팩 이름은 **표시만** 한다(로그·분석 이벤트 0).

/// 채움글 화면 맨 위 배너 한 줄 — 시안 4-N 모양(주황 바탕·경고 아이콘·아래 파란 버튼). 버튼은 글자만 눌린다(행 전체가 눌리지 않게)
struct SnippetNoticeBanner: View {
    let message: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.subheadline)
                if let actionTitle {
                    Button(actionTitle, action: action)
                        .buttonStyle(.borderless)
                }
            }
        }
        .listRowBackground(Color.orange.opacity(0.12))
    }
}

extension View {
    /// 채움글 변경 알림 — 사유별 제목·문구(`PackChangeNotice`, 계획서 4-2절). 동작 버튼은 **띄우는 자리가 연결한 것만** 그린다
    /// (`PackChangeNotice.Presenter` — 패키지 시험이 자리별 버튼을 고정한다). `onAction`이 정리 화면·복구 시트·삭제 확인·
    /// 꺼 둔 채로 가져오기로 보낸다. `onDismiss`는 닫는 버튼(「확인」·「닫기」)을 눌렀을 때 — 닫힘 바인딩이 상태를 옮기지 않는 자리
    /// (가져오기 폼, 화면 확인 N-1)가 이것으로 닫는다
    func packChangeNoticeAlert(
        _ notice: Binding<PackChangeNotice?>, in presenter: PackChangeNotice.Presenter = .settings,
        onDismiss: (@MainActor () -> Void)? = nil,
        onAction: @escaping @MainActor (PackChangeNotice.Action) -> Void
    ) -> some View {
        alert(notice.wrappedValue?.title ?? "", isPresented: Binding(
            get: { notice.wrappedValue != nil },
            set: { if !$0 { notice.wrappedValue = nil } }
        ), presenting: notice.wrappedValue) { shown in
            ForEach(shown.actions(in: presenter), id: \.self) { action in
                Button(action.label) { onAction(action) }
            }
            Button(shown.dismiss.label, role: .cancel) { onDismiss?() }
        } message: { shown in
            Text(shown.message)
        }
    }

    /// 목록 복구(R24) 흐름 — `isPresented`가 켜지면 찾은 팩 수를 세고(메인 밖) 확인 알림(취소·복구)을 띄운다. **「복구」를 눌렀을 때만** 복구하고
    /// 결과를 알린 뒤 `onFinish`(화면이 상태를 다시 읽는다)
    func packLibraryRecovery(isPresented: Binding<Bool>, onFinish: @escaping @MainActor () -> Void) -> some View {
        modifier(PackLibraryRecoveryFlow(isPresented: isPresented, onFinish: onFinish))
    }
}

private struct PackLibraryRecoveryFlow: ViewModifier {
    @Binding var isPresented: Bool
    let onFinish: @MainActor () -> Void

    /// 확인 알림에 보일 찾은 팩 수
    @State private var packCount: Int?
    @State private var showsConfirmation = false
    @State private var result: PackLibraryRecovery?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                isPresented = false
                Task {
                    // 그 사이 목록이 읽히게 됐으면(다른 화면에서 복구) 시트 없이 끝낸다
                    guard let count = await PackStoreClient.live.recoveryPreview() else {
                        onFinish()
                        return
                    }
                    packCount = count
                    showsConfirmation = true
                }
            }
            // ★ 알림(가운데 창)으로 묻는다 — `confirmationDialog`는 iOS 26에서 팝오버로 떠 「취소」를 그리지 않았다(화면 확인 S-1).
            //   되돌릴 수 없는 일(목록을 다시 만듦)을 묻는 창이라 「취소」·「복구」 둘이 늘 보여야 한다(계획서 4-3절)
            .alert(PackNoticeCopy.recoveryTitle, isPresented: $showsConfirmation, presenting: packCount) { _ in
                Button(PackNoticeCopy.recoveryCancel, role: .cancel) {}
                Button(PackNoticeCopy.recoveryConfirm) {
                    Task {
                        let recovered = await PackStoreClient.live.recoverLibrary()
                        if recovered != .notNeeded { result = recovered }
                        onFinish()
                    }
                }
            } message: { count in
                Text(PackNoticeCopy.recoveryMessage(packCount: count))
            }
            .alert(resultTitle, isPresented: Binding(
                get: { result != nil },
                set: { if !$0 { result = nil } }
            ), presenting: result) { _ in
                Button(PackChangeNotice.Action.confirm.label, role: .cancel) {}
            } message: { shown in
                Text(Self.message(shown))
            }
    }

    private var resultTitle: String {
        switch result {
        case .recovered: PackNoticeCopy.recoveredTitle
        case .failed: PackNoticeCopy.recoveryFailedTitle
        case .notNeeded, nil: ""
        }
    }

    private static func message(_ result: PackLibraryRecovery) -> String {
        switch result {
        case .recovered(let packs, _, _): PackNoticeCopy.recoveredMessage(packCount: packs)
        case .failed: PackNoticeCopy.recoveryFailedMessage
        case .notNeeded: ""
        }
    }
}
