import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 복사한 사진 도우미 (v1.3.0 ④ B) — PDR `docs/design-reviews/clipboard-image-history.md`(확정 결정 B1~B5).
//
// 클립보드에 사진이 있으면 툴바 붙여넣기 칩 자리에 썸네일 「사진 복사」 칩을 띄우고, 탭하면 그 사진을 클립보드에
// **다시 쓴다**(`localOnly`·만료 120초) — 사용자가 입력란을 길게 눌러 iOS 기본 붙여넣기로 넣게 한다.
//
// 판단은 전부 여기 있다(익스텐션 타깃은 `swift test`가 닿지 않는다). 조립 지점은 `UIPasteboard.general`을
// `CopiedPhotoPasteboard`로 감싸 넘기고 결과대로 칩을 싣기만 한다.
//
// ## 보안 규칙 클립보드 절의 예외 (`.claude/rules/security.md`) — 이 파일이 지키는 것
//
// 1. 쓰기는 `CopiedPhotoWrite`로만 나간다 — 이 값은 **이 모듈만** 만들고 `localOnly == true`와 만료 시각이 항상 든다.
//    조립 지점은 `setItems(_:options:)`의 `.localOnly`·`.expirationDate`에 그대로 넣는다(`setData`를 쓰지 않는다)
// 2. 만료는 상수 하나(`expirationInterval`, 120초) — 클립보드 쪽과 원본 사본 쪽이 **같은 값**을 쓴다(5-2 ①)
// 3. `write`를 부르는 곳은 `tap` **하나뿐**이다 — 프로브·재등장·만료·✕·끄기는 쓰지 않는다
// 4. 화소 수(64MP)·바이트(8MB)를 **디코드 전에** 본다 — 넘으면 디코드하지 않고 칩도 없다(B2·B3)
//
// 사진 바이트·썸네일은 **메모리에만** 있다 — 로그·파일·네트워크 0.

/// 사진 도우미가 쓰는 클립보드 — 조립 지점이 `UIPasteboard.general`로 구현한다(시험에서는 가짜).
@MainActor
public protocol CopiedPhotoPasteboard: AnyObject {
    /// 정수 — 내용을 가져오지 않는다
    var changeCount: Int { get }
    /// 내용을 가져오지 않는다(붙여넣기 확인 창 없음)
    var hasImages: Bool { get }
    /// 내용을 가져오지 않는다 — 「클립보드가 아직 비어 보인다」(내용 도착 전) 판정에만 쓴다
    var hasStrings: Bool { get }
    /// 첫 항목의 형식(UTI) 목록 — 내용을 가져오지 않는다
    var types: [String] { get }
    /// 압축 바이트를 가져온다(경로 A, B4) — **내용 읽기**
    func data(forType type: String) -> Data?
    /// 되쓰기 — `setItems([[type: data]], options: [.localOnly: …, .expirationDate: …])`. 사진 도우미 탭의 직접 결과로만 불린다
    func write(_ write: CopiedPhotoWrite)
}

/// 클립보드 되쓰기 한 번 — **이 모듈 밖에서는 만들 수 없다**(생성자가 internal). 그래서 조립 지점이 받는
/// 모든 쓰기에 `localOnly == true`와 만료 시각이 들어 있다(보안 규칙 예외 조건 1·2).
public struct CopiedPhotoWrite: Equatable, Sendable {
    public let type: String
    public let data: Data
    /// 항상 참 — iCloud 기기 간 자동 전파 차단. 조립 지점은 `.localOnly`에 이 값을 그대로 넣는다
    public let localOnly: Bool
    /// 항상 있다 — 이 시각에 OS가 클립보드에서 스스로 지운다
    public let expirationDate: Date

    init(type: String, data: Data, now: Date) {
        self.type = type
        self.data = data
        self.localOnly = true
        self.expirationDate = now.addingTimeInterval(CopiedPhotoHelper.expirationInterval)
    }
}

public struct CopiedPhotoPixelSize: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var pixelCount: Int { width * height }

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

/// 헤더 읽기(디코드 없음)와 축소 썸네일 — 제품은 `ImageIOCopiedPhotoDecoder`(시험에서는 가짜로 호출 순서를 본다).
public protocol CopiedPhotoDecoder {
    /// 헤더만 읽어 가로×세로 — **디코드하지 않는다**
    func pixelSize(of data: Data) -> CopiedPhotoPixelSize?
    /// 축소 썸네일 — 내장 썸네일이 있으면 그것(IfAbsent), 디코드 결과를 캐시하지 않는다
    func thumbnail(of data: Data, maxPixelSize: Int) -> CGImage?
}

/// ImageIO 구현 — 옵션은 PDR 2-2 ②와 실기 세션 2(`v1.3.0-device-session-2-b-results.md`)에서 잰 그대로다.
public struct ImageIOCopiedPhotoDecoder: CopiedPhotoDecoder {

    public init() {}

    public func pixelSize(of data: Data) -> CopiedPhotoPixelSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, Self.sourceOptions),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, Self.sourceOptions) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CopiedPhotoPixelSize(width: width, height: height)
    }

    public func thumbnail(of data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, Self.sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,   // `…Always`는 내장 썸네일을 버리고 본 그림을 디코드한다
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailWithTransform: true         // EXIF 방향 — 세로 사진이 누워 보이지 않게
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }
}

/// 칩에 올릴 썸네일 — 같은 그림인지는 **객체 동일성**으로 본다(내용 비교를 하지 않는다).
public struct CopiedPhotoThumbnail: Equatable {
    public let image: CGImage

    public init(image: CGImage) { self.image = image }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.image === rhs.image }
}

/// 툴바 사진 칩 — 붙여넣기 칩 자리를 텍스트·인증번호 칩과 나눠 쓴다(PDR 1-2).
public struct CopiedPhotoChip: Equatable {
    public enum Stage: Equatable, Sendable {
        /// 「사진 복사」 — 클립보드에 사진이 있다. 탭하면 되쓴다
        case copyable
        /// 「복사됨 · …」 — 되썼다. 만료(120초)까지 보인다
        case copied
    }

    public let stage: Stage
    public let thumbnail: CopiedPhotoThumbnail

    public init(stage: Stage, thumbnail: CopiedPhotoThumbnail) {
        self.stage = stage
        self.thumbnail = thumbnail
    }

    /// 칩 글자 — 문구는 PDR 1-2 흐름 3·4번(반론자2 문구)
    public var title: String {
        switch stage {
        case .copyable: "사진 복사"
        case .copied: "복사됨 · 사진 붙여넣기를 지원하는 입력란에서 길게 눌러 붙여넣기"
        }
    }

    /// VoiceOver — 화면에서 잘려도 무엇을 하는지 끝까지 읽는다
    public var accessibilityLabel: String {
        switch stage {
        case .copyable: "복사한 사진, 탭하면 붙여넣을 수 있게 클립보드에 다시 담아요"
        case .copied: "사진을 클립보드에 담았어요. 사진 붙여넣기를 지원하는 입력란에서 길게 눌러 붙여넣으세요"
        }
    }
}

/// 사진 도우미를 지금 돌려도 되는가 — 수용 기준 5(`ClipboardPanelContent`와 같은 자리의 도메인 함수).
/// 하나라도 거짓이면 `hasImages`조차 보지 않는다(PDR 6-1).
public enum CopiedPhotoGate {
    public static func allowsReading(enabled: Bool, hasFullAccess: Bool, isSecureTextEntry: Bool) -> Bool {
        enabled && hasFullAccess && !isSecureTextEntry
    }
}

/// 사진 도우미의 상태 — 조립 지점이 **프로세스 수명**(`static`)으로 둔다(PDR 5-2, 키보드 VC는 등장마다 새로 만들어진다).
///
/// | 상태 | 든 것 | 칩 |
/// |---|---|---|
/// | 미리보기 | changeCount·UTI·썸네일 (**원본 바이트 없음**, B5) | 「사진 복사」 |
/// | 원본 사본 | 압축 바이트(≤ 8MB)·썸네일·만료 시각·우리가 쓴 changeCount | 「복사됨 · …」 |
///
/// 원본 사본의 이중 만료(5-2): ① 시간 — 되쓰기 만료와 **같은 시각** ② 대체 — 다른 changeCount(진짜 새 복사)를 보면
/// 읽기 **전에** 먼저 버린다 ③ 끄기 — 스위치·전체 접근이 꺼진 것을 본 그 재로드·등장에서 비운다.
public struct CopiedPhotoHelper {

    /// 화소 수 상한 — 실측 최대 8000×8000(B2). 넘으면 디코드하지 않고 칩도 없다(B3)
    public static let maxPixelCount = 64_000_000
    /// 바이트 상한 — 원본 사본 상한과 같다(5절). 넘으면 칩 없음(2-5 「둘 다 집행」)
    public static let maxByteCount = 8 * 1024 * 1024
    /// 되쓰기 만료이자 원본 사본 만료 — 상수 하나(3-4·5-2 ①, 보안 규칙 예외 조건 2)
    public static let expirationInterval: TimeInterval = 120
    /// 칩 썸네일 긴 변(px) — 칩 그림 24pt × 3배 + 여유
    public static let thumbnailMaxPixelSize = 96

    public enum ProbeResult: Equatable, Sendable {
        /// 칩 없음(사진 아님·상한 초과·소비함·게이트 닫힘 등)
        case none
        /// 칩 있음 — `visibleChip(now:)`
        case chip
        /// 클립보드가 아직 비어 보인다(앱을 옮겨 온 직후 내용 도착 전) — 조립 지점의 짧은 재시도에 맡긴다
        case retry
    }

    private struct Preview {
        let changeCount: Int
        let type: String
        let thumbnail: CopiedPhotoThumbnail
    }

    private struct Original {
        let data: Data
        let type: String
        let thumbnail: CopiedPhotoThumbnail
        var expiresAt: Date
        /// 우리가 되쓴 직후의 changeCount — 다음 프로브가 이 값을 보면 「새 복사」가 아니다(6-2)
        var writtenChangeCount: Int
    }

    private var preview: Preview?
    private var original: Original?
    /// 상한 초과·디코드 실패로 거절한 클립보드 — 같은 클립보드는 다시 읽지 않는다
    private var rejectedChangeCount: Int?
    private var stage: CopiedPhotoChip.Stage?

    public init() {}

    /// 원본 압축 바이트를 들고 있는가(시험·진단용 — 내용은 내보내지 않는다)
    public var holdsOriginal: Bool { original != nil }

    /// 첫 「이미지」 UTI — 실기 세션 2가 잰 규칙 그대로(사진 앱 복사는 HEIC도 JPEG가 첫 표현이었다)
    public static func firstImageType(in types: [String]) -> String? {
        types.first { UTType($0)?.conforms(to: .image) == true }
    }

    /// 키보드 등장 시 1회 읽기(+ 빈손일 때의 짧은 재시도) 안에서 부른다 — 새 폴링이 아니다.
    ///
    /// - Parameters:
    ///   - yieldsToText: 이번 프로브가 텍스트·인증번호 칩을 만들었다 — 그쪽이 이기므로 사진은 읽지 않는다(1-2)
    ///   - consumedChangeCount: ✕·탭으로 소비한 클립보드(`consumedPasteboardChangeCount` — 텍스트 칩과 공유)
    @MainActor
    public mutating func probe(
        enabled: Bool, hasFullAccess: Bool, isSecureTextEntry: Bool, yieldsToText: Bool,
        consumedChangeCount: Int?, pasteboard: any CopiedPhotoPasteboard, decoder: any CopiedPhotoDecoder, now: Date
    ) -> ProbeResult {
        stage = nil
        apply(enabled: enabled, hasFullAccess: hasFullAccess)
        guard CopiedPhotoGate.allowsReading(
            enabled: enabled, hasFullAccess: hasFullAccess, isSecureTextEntry: isSecureTextEntry) else { return .none }
        expireOriginal(now: now)
        let changeCount = pasteboard.changeCount
        if let original, original.writtenChangeCount == changeCount {
            stage = .copied                      // 우리가 쓴 것 — 새 복사로 오인하지 않는다(6-2)
            return .chip
        }
        original = nil                           // 대체 만료 — 읽기보다 먼저 버린다(2-2 ①)
        if changeCount == consumedChangeCount {
            preview = nil
            return .none
        }
        if let preview, preview.changeCount == changeCount {
            stage = .copyable                    // 이미 읽은 클립보드 — 다시 읽지 않는다
            return .chip
        }
        preview = nil
        if yieldsToText || changeCount == rejectedChangeCount { return .none }
        guard pasteboard.hasImages else { return pasteboard.hasStrings ? .none : .retry }
        guard let type = Self.firstImageType(in: pasteboard.types) else {
            rejectedChangeCount = changeCount
            return .none
        }
        guard let data = pasteboard.data(forType: type) else { return .retry }
        guard let thumbnail = Self.thumbnailWithinLimits(data, decoder: decoder) else {
            rejectedChangeCount = changeCount
            return .none
        }
        // 원본 바이트는 여기서 버린다 — 썸네일만 든다(B5). 탭할 때 다시 읽는다
        preview = Preview(changeCount: changeCount, type: type, thumbnail: thumbnail)
        stage = .copyable
        return .chip
    }

    /// 지금 칩 — 「복사됨」이 만료됐으면 원본 사본을 버리고 칩도 없다(오래된 원본을 되쓰지 않는다).
    public mutating func visibleChip(now: Date) -> CopiedPhotoChip? {
        expireOriginal(now: now)
        switch stage {
        case .copyable: return preview.map { CopiedPhotoChip(stage: .copyable, thumbnail: $0.thumbnail) }
        case .copied: return original.map { CopiedPhotoChip(stage: .copied, thumbnail: $0.thumbnail) }
        case nil: return nil
        }
    }

    /// 칩 탭 — **유일한 쓰기 지점**(보안 규칙 예외 조건 3). 썼으면 참.
    ///
    /// 「사진 복사」: 프로브 뒤 클립보드가 그대로일 때만 바이트를 다시 읽고 상한을 다시 본 뒤 되쓴다.
    /// 「복사됨」: 클립보드가 우리가 쓴 그대로이고 만료 전일 때만 들고 있던 원본으로 다시 쓴다(만료 갱신).
    @MainActor
    public mutating func tap(pasteboard: any CopiedPhotoPasteboard, decoder: any CopiedPhotoDecoder, now: Date) -> Bool {
        expireOriginal(now: now)
        switch stage {
        case .copyable:
            guard let preview, pasteboard.changeCount == preview.changeCount else { return abandon() }
            original = nil                       // 버림이 먼저다(2-2 ①)
            guard let data = pasteboard.data(forType: preview.type),
                  Self.withinLimits(data, decoder: decoder) else {
                rejectedChangeCount = preview.changeCount
                return abandon()
            }
            let write = CopiedPhotoWrite(type: preview.type, data: data, now: now)
            pasteboard.write(write)
            original = Original(
                data: data, type: preview.type, thumbnail: preview.thumbnail,
                expiresAt: write.expirationDate, writtenChangeCount: pasteboard.changeCount)
            self.preview = nil
            stage = .copied
            return true
        case .copied:
            guard var original, pasteboard.changeCount == original.writtenChangeCount else { return abandon() }
            let write = CopiedPhotoWrite(type: original.type, data: original.data, now: now)
            pasteboard.write(write)
            original.expiresAt = write.expirationDate
            original.writtenChangeCount = pasteboard.changeCount
            self.original = original
            return true
        case nil:
            return false
        }
    }

    /// ✕ — 칩을 물리고 원본 사본도 비운다. 소비할 changeCount를 돌려준다(조립 지점의 `consumedPasteboardChangeCount`).
    public mutating func dismiss() -> Int? {
        let consumed: Int? = switch stage {
        case .copyable: preview?.changeCount
        case .copied: original?.writtenChangeCount
        case nil: nil
        }
        preview = nil
        original = nil
        stage = nil
        return consumed
    }

    /// 설정 재로드·등장 — 스위치나 전체 접근이 꺼져 있으면 전부 비운다(5-2 ③ OFF 만료).
    public mutating func apply(enabled: Bool, hasFullAccess: Bool) {
        guard !enabled || !hasFullAccess else { return }
        preview = nil
        original = nil
        rejectedChangeCount = nil
        stage = nil
    }

    // MARK: - 내부

    private mutating func expireOriginal(now: Date) {
        guard let original, now >= original.expiresAt else { return }
        self.original = nil
        if stage == .copied { stage = nil }
    }

    private mutating func abandon() -> Bool {
        preview = nil
        original = nil
        stage = nil
        return false
    }

    /// 바이트 → 화소(헤더) 순으로 상한을 본다 — **디코드 전**(B2)
    private static func withinLimits(_ data: Data, decoder: any CopiedPhotoDecoder) -> Bool {
        guard data.count <= maxByteCount, let size = decoder.pixelSize(of: data) else { return false }
        return size.pixelCount <= maxPixelCount
    }

    private static func thumbnailWithinLimits(_ data: Data, decoder: any CopiedPhotoDecoder) -> CopiedPhotoThumbnail? {
        guard withinLimits(data, decoder: decoder),
              let image = decoder.thumbnail(of: data, maxPixelSize: thumbnailMaxPixelSize) else { return nil }
        return CopiedPhotoThumbnail(image: image)
    }
}
