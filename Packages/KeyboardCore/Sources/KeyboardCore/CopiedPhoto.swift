import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 복사한 사진 도우미 (v1.3.0 ④ B) — PDR `docs/design-reviews/clipboard-image-history.md`(확정 결정 B1~B5).
//
// 클립보드에 사진이 있으면 툴바 붙여넣기 칩 자리에 썸네일 「복사한 사진」 칩을 띄우고, 탭하면 그 사진을 클립보드에
// **다시 쓴다**(`localOnly`·만료 120초) — 사용자가 입력란을 길게 눌러 iOS 기본 붙여넣기로 넣게 한다.
//
// 판단은 전부 여기 있다(익스텐션 타깃은 `swift test`가 닿지 않는다). 조립 지점은 `UIPasteboard.general`을
// `CopiedPhotoPasteboard`로 감싸 넘기고 결과대로 칩을 싣기만 한다.
//
// ## 보안 규칙 클립보드 절의 예외 (`.claude/rules/security.md`) — 이 파일이 지키는 것
//
// 1. 쓰기는 `CopiedPhotoWrite`로만 나간다 — 이 값은 **이 모듈만** 만들고 `localOnly == true`와 만료 시각이 항상 든다.
//    조립 지점은 `setItems(_:options:)`의 `.localOnly`·`.expirationDate`에 그대로 넣는다(`setData`를 쓰지 않는다)
// 2. 만료는 상수 하나(`expirationInterval`, 120초) — 「복사됨」 칩도 같은 시각에 사라진다
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
        /// 「복사한 사진」 — 클립보드에 사진이 있다. 탭하면 되쓴다
        case copyable
        /// 「길게 눌러 붙여넣기」 — 되썼다. 만료(120초)까지 보인다
        case copied
    }

    public let stage: Stage
    public let thumbnail: CopiedPhotoThumbnail

    public init(stage: Stage, thumbnail: CopiedPhotoThumbnail) {
        self.stage = stage
        self.thumbnail = thumbnail
    }

    /// 칩 글자 — **안내형, 짧게**(B7, 2026-10-06 실기 확인). 옛 「사진 복사」는 누르면 붙여넣어지는 줄 알게 했고,
    /// 옛 「복사됨 · 사진 붙여넣기를 지원하는 입력란에서 길게 눌러 붙여넣기」는 칩에서 잘려 앞부분만 보였다(F6).
    /// 탭 전은 **무엇인지**, 탭 뒤는 **할 일 하나**만 말한다 — 키보드가 사진을 직접 넣는 API는 없어 붙여넣기는 사용자 몫이다.
    public var title: String {
        switch stage {
        case .copyable: "복사한 사진"
        case .copied: "길게 눌러 붙여넣기"
        }
    }

    /// VoiceOver — 화면 글자가 짧은 대신 **뜻을 풀어** 읽는다(탭하면 무엇이 되는지, 그다음 무엇을 하는지)
    public var accessibilityLabel: String {
        switch stage {
        case .copyable: "복사한 사진. 탭하면 붙여넣을 수 있게 준비해요"
        case .copied: "사진 붙여넣기 준비 완료. 입력란을 길게 눌러 붙여넣기를 고르세요"
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

/// 사진 도우미의 상태 — 조립 지점이 **프로세스 수명**(`static`)으로 둔다(키보드 VC는 등장마다 새로 만들어진다).
///
/// ★ **사진 바이트를 들고 있지 않다**(B6, 2026-10-06 — 검증 F2). 원본 사본·이중 만료·8MB 캐시 상한은 없다.
/// 「복사됨」 칩을 다시 누르면 클립보드에 아직 남은 **우리가 쓴 그 항목**(자체 쓰기 `changeCount`가 같을 때만)을
/// 다시 읽어 되쓴다 — 그래서 「끄면 사본 삭제」·「120초 뒤 사본 삭제」를 지킬 사본 자체가 없다.
///
/// | 단계 | 든 것(메모리) | 칩 |
/// |---|---|---|
/// | 미리보기 | changeCount·UTI·썸네일(긴 변 96px) — 원본 바이트 없음(B5) | 「복사한 사진」 |
/// | 되씀 | UTI·썸네일·만료 시각·우리가 쓴 changeCount — 원본 바이트 없음(B6) | 「길게 눌러 붙여넣기」 |
///
/// 비우기: 다른 changeCount(진짜 새 복사)를 보면 「되씀」을 버린다 · 만료가 지나면 칩이 없다 ·
/// 스위치나 전체 접근이 꺼진 것을 본 그 재로드·등장에서 전부 비운다.
public struct CopiedPhotoHelper {

    /// 화소 수 상한 — 실측 최대 8000×8000(B2). 넘으면 디코드하지 않고 칩도 없다(B3)
    public static let maxPixelCount = 64_000_000
    /// 읽기 바이트 상한 — 넘으면 디코드하지 않고 칩도 없다(2-5 「화소 수와 둘 다 집행」)
    public static let maxByteCount = 8 * 1024 * 1024
    /// 되쓰기 만료 — 상수 하나(3-4, 보안 규칙 예외 조건 2). 「복사됨」 칩도 이 시각에 사라진다
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

    /// 되쓴 뒤의 표식 — **바이트가 없다**(B6)
    private struct Written {
        let type: String
        let thumbnail: CopiedPhotoThumbnail
        var expiresAt: Date
        /// 우리가 되쓴 직후의 changeCount — 다음 프로브가 이 값을 보면 「새 복사」가 아니다(6-2).
        /// 재탭은 클립보드가 **이 값 그대로일 때만** 그 항목을 다시 읽어 쓴다
        var changeCount: Int
    }

    private var preview: Preview?
    private var written: Written?
    /// 상한 초과·디코드 실패로 거절한 클립보드 — 같은 클립보드는 다시 읽지 않는다
    private var rejectedChangeCount: Int?
    private var stage: CopiedPhotoChip.Stage?

    public init() {}

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
        expireWritten(now: now)
        let changeCount = pasteboard.changeCount
        if let written, written.changeCount == changeCount {
            stage = .copied                      // 우리가 쓴 것 — 새 복사로 오인하지 않는다(6-2)
            return .chip
        }
        written = nil                            // 다른 클립보드 — 「복사됨」은 끝났다
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

    /// 지금 칩 — 「복사됨」이 만료됐으면 칩이 없다(지난 사진을 되쓰지 않는다).
    public mutating func visibleChip(now: Date) -> CopiedPhotoChip? {
        expireWritten(now: now)
        switch stage {
        case .copyable: return preview.map { CopiedPhotoChip(stage: .copyable, thumbnail: $0.thumbnail) }
        case .copied: return written.map { CopiedPhotoChip(stage: .copied, thumbnail: $0.thumbnail) }
        case nil: return nil
        }
    }

    /// 칩 탭 — **유일한 쓰기 지점**(보안 규칙 예외 조건 3). 썼으면 참.
    ///
    /// 클립보드가 **그 칩이 가리키는 항목 그대로**일 때만 바이트를 읽고 상한을 다시 본 뒤 되쓴다 —
    /// 「복사한 사진」은 프로브가 본 changeCount, 「길게 눌러 붙여넣기」는 우리가 쓴 changeCount(B6 — 들고 있는 사본이 없다).
    /// 그 사이 다른 것(같은 형식의 다른 사진 포함)을 복사했으면 **읽지도 쓰지도 않고** 칩을 거둔다 —
    /// 사용자가 방금 복사한 것에 120초 만료를 붙이지 않는다.
    @MainActor
    public mutating func tap(pasteboard: any CopiedPhotoPasteboard, decoder: any CopiedPhotoDecoder, now: Date) -> Bool {
        expireWritten(now: now)
        let target: (changeCount: Int, type: String, thumbnail: CopiedPhotoThumbnail)
        switch stage {
        case .copyable:
            guard let preview else { return abandon() }
            target = (preview.changeCount, preview.type, preview.thumbnail)
        case .copied:
            guard let written else { return abandon() }
            target = (written.changeCount, written.type, written.thumbnail)
        case nil:
            return false
        }
        guard pasteboard.changeCount == target.changeCount else { return abandon() }
        guard let data = pasteboard.data(forType: target.type), Self.withinLimits(data, decoder: decoder) else {
            rejectedChangeCount = target.changeCount
            return abandon()
        }
        let write = CopiedPhotoWrite(type: target.type, data: data, now: now)
        pasteboard.write(write)
        // 바이트(`data`)는 여기서 버려진다 — 남기는 것은 표식뿐이다(B6)
        written = Written(
            type: target.type, thumbnail: target.thumbnail,
            expiresAt: write.expirationDate, changeCount: pasteboard.changeCount)
        preview = nil
        stage = .copied
        return true
    }

    /// ✕ — 칩을 물린다. 소비할 changeCount를 돌려준다(조립 지점의 `consumedPasteboardChangeCount`).
    public mutating func dismiss() -> Int? {
        let consumed: Int? = switch stage {
        case .copyable: preview?.changeCount
        case .copied: written?.changeCount
        case nil: nil
        }
        preview = nil
        written = nil
        stage = nil
        return consumed
    }

    /// 설정 재로드·등장 — 스위치나 전체 접근이 꺼져 있으면 미리보기·표식을 전부 비운다(사진 바이트는 원래 없다, B6).
    public mutating func apply(enabled: Bool, hasFullAccess: Bool) {
        guard !enabled || !hasFullAccess else { return }
        preview = nil
        written = nil
        rejectedChangeCount = nil
        stage = nil
    }

    // MARK: - 내부

    private mutating func expireWritten(now: Date) {
        guard let written, now >= written.expiresAt else { return }
        self.written = nil
        if stage == .copied { stage = nil }
    }

    private mutating func abandon() -> Bool {
        preview = nil
        written = nil
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
