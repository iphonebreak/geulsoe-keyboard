import UIKit
import KeyboardCore

/// 사진 도우미(v1.3.0 ④ B)가 쓰는 `UIPasteboard.general` — **판단은 하지 않는다.** 무엇을 언제 읽고 쓰는지는
/// `CopiedPhotoHelper`(KeyboardCore)가 정하고 `swift test`가 지킨다. 여기는 그 결정을 그대로 옮기는 얇은 경계다.
///
/// ## 이 파일이 이 키보드의 **유일한** 클립보드 쓰기 지점이다 (`.claude/rules/security.md` 클립보드 절 예외)
///
/// - `setData`가 아니라 `setItems(_:options:)` — `.localOnly`와 `.expirationDate`를 **항상** 함께 준다.
///   두 값은 `CopiedPhotoWrite`가 들고 오고, 그 값은 KeyboardCore만 만들 수 있어 `localOnly`가 항상 참이다
/// - 이 `write`는 사진 칩 탭(`CopiedPhotoHelper.tap`)에서만 불린다 — 프로브·등장에서 쓰는 경로가 없다
/// - 사진 바이트를 로그·파일로 내보내지 않는다
@MainActor
final class SystemCopiedPhotoPasteboard: CopiedPhotoPasteboard {

    private var pasteboard: UIPasteboard { .general }

    var changeCount: Int { pasteboard.changeCount }
    var hasImages: Bool { pasteboard.hasImages }
    var hasStrings: Bool { pasteboard.hasStrings }
    var types: [String] { pasteboard.types }

    func data(forType type: String) -> Data? {
        pasteboard.data(forPasteboardType: type)
    }

    func write(_ write: CopiedPhotoWrite) {
        pasteboard.setItems(
            [[write.type: write.data]],
            options: [
                .localOnly: write.localOnly,
                .expirationDate: write.expirationDate
            ]
        )
    }
}
