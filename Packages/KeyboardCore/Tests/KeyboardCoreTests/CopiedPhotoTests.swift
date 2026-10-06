import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import KeyboardCore

// 복사한 사진 도우미 (v1.3.0 ④ B) — PDR `docs/design-reviews/clipboard-image-history.md` 수용 기준 8절,
// 확정 결정 B1~B5, 보안 규칙 클립보드 절의 예외(setItems + localOnly + 만료 120초 + 사용자 탭일 때만).

/// 가짜 클립보드 — **무엇을 몇 번 건드렸는지** 센다(읽기 0·쓰기 0을 단언하려고).
@MainActor
private final class FakePhotoPasteboard: CopiedPhotoPasteboard {
    var changeCount = 1
    var images: [String: Data] = [:]
    var strings = false
    private(set) var metadataReads = 0
    private(set) var dataReads = 0
    private(set) var writes: [CopiedPhotoWrite] = []

    var hasImages: Bool { metadataReads += 1; return !images.isEmpty }
    var hasStrings: Bool { metadataReads += 1; return strings }
    var types: [String] {
        metadataReads += 1
        return (strings ? ["public.utf8-plain-text"] : []) + images.keys.sorted()
    }
    var touches: Int { metadataReads + dataReads + writes.count }

    func data(forType type: String) -> Data? {
        dataReads += 1
        return images[type]
    }

    func write(_ write: CopiedPhotoWrite) {
        writes.append(write)
        images = [write.type: write.data]
        strings = false
        changeCount += 1
    }

    /// 다른 앱에서 새로 복사했다
    func copy(image type: String = "public.jpeg", bytes: Int = 1_000, strings: Bool = false) {
        images = [type: Data(repeating: 7, count: bytes)]
        self.strings = strings
        changeCount += 1
    }

    func copyText() {
        images = [:]
        strings = true
        changeCount += 1
    }
}

/// 가짜 디코더 — 화소 크기는 정해 주고, **호출 순서**를 남긴다(디코드 전에 화소 수를 봤는지).
private final class SpyPhotoDecoder: CopiedPhotoDecoder, @unchecked Sendable {
    var size = CopiedPhotoPixelSize(width: 4032, height: 3024)
    var failsThumbnail = false
    private(set) var calls: [String] = []

    func pixelSize(of data: Data) -> CopiedPhotoPixelSize? {
        calls.append("size")
        return size
    }

    func thumbnail(of data: Data, maxPixelSize: Int) -> CGImage? {
        calls.append("thumbnail")
        return failsThumbnail ? nil : PhotoFixture.image(width: 4, height: 3)
    }
}

private enum PhotoFixture {
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    static func image(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// 실제 PNG 바이트 — ImageIO 디코더를 진짜로 돌려 본다
    static func png(width: Int, height: Int) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: width, height: height), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

/// 조립 지점(`KeyboardViewController`)과 같은 순서 — 등장 프로브 → 칩 → 탭 / ✕ / 설정 재로드
@MainActor
private final class PhotoHarness {
    let pasteboard = FakePhotoPasteboard()
    let decoder = SpyPhotoDecoder()
    var helper = CopiedPhotoHelper()
    var enabled = true
    var hasFullAccess = true
    var isSecure = false
    var consumed: Int?
    var now = PhotoFixture.t0

    @discardableResult
    func appear(textChip: Bool = false) -> CopiedPhotoHelper.ProbeResult {
        helper.probe(
            enabled: enabled, hasFullAccess: hasFullAccess, isSecureTextEntry: isSecure, yieldsToText: textChip,
            consumedChangeCount: consumed, pasteboard: pasteboard, decoder: decoder, now: now)
    }

    func chip() -> CopiedPhotoChip? { helper.visibleChip(now: now) }

    @discardableResult
    func tap() -> Bool { helper.tap(pasteboard: pasteboard, decoder: decoder, now: now) }

    /// ✕ — 소비한 changeCount를 조립 지점의 `consumedPasteboardChangeCount`로 넘긴다
    func dismiss() {
        if let changeCount = helper.dismiss() { consumed = changeCount }
    }
}

// MARK: - 수용 기준 1 · B5 — 등장 프로브(읽기는 칩을 띄우기 전, 사장님 결정 X 2026-10-06)

@MainActor
@Suite("사진 도우미 — 등장 프로브 (수용 기준 1·B2~B5)")
struct CopiedPhotoProbeTests {

    @Test("★ 사진을 복사하고 키보드가 뜨면 썸네일 「사진 복사」 칩 — 바이트는 한 번 읽고 원본은 들고 있지 않는다")
    func probeShowsCopyableChip() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        #expect(harness.appear() == .chip)
        let chip = try #require(harness.chip())
        #expect(chip.stage == .copyable)
        #expect(chip.title == "사진 복사")
        #expect(harness.pasteboard.dataReads == 1)
        #expect(harness.decoder.calls == ["size", "thumbnail"], "★ 화소 수를 본 뒤에만 디코드한다(B2)")
        #expect(!harness.helper.holdsOriginal, "프로브는 원본 바이트를 버리고 썸네일만 든다(B5)")
        #expect(harness.pasteboard.writes.isEmpty, "★ 프로브는 쓰지 않는다 — 쓰기는 탭의 직접 결과로만")
    }

    @Test("첫 이미지 UTI를 고른다 — 텍스트 형식은 건너뛴다, 이미지 형식이 없으면 읽지 않는다")
    func firstImageType() {
        #expect(CopiedPhotoHelper.firstImageType(in: ["public.utf8-plain-text", "public.jpeg", "public.png"]) == "public.jpeg")
        #expect(CopiedPhotoHelper.firstImageType(in: ["public.png"]) == "public.png")
        #expect(CopiedPhotoHelper.firstImageType(in: ["public.utf8-plain-text", "public.url"]) == nil)
        #expect(CopiedPhotoHelper.firstImageType(in: []) == nil)
    }

    @Test("★ 64MP 초과 — 디코드하지 않고 칩도 없다, 같은 클립보드는 다시 읽지 않는다 (B2·B3)")
    func rejectsOver64MP() {
        let harness = PhotoHarness()
        harness.decoder.size = CopiedPhotoPixelSize(width: 8001, height: 8000)
        harness.pasteboard.copy()
        #expect(harness.appear() == .none)
        #expect(harness.chip() == nil)
        #expect(harness.decoder.calls == ["size"], "썸네일(디코드)을 부르지 않았다")
        let reads = harness.pasteboard.dataReads
        harness.appear()
        #expect(harness.pasteboard.dataReads == reads, "거절한 클립보드는 등장마다 다시 읽지 않는다")
        #expect(harness.chip() == nil)
    }

    @Test("64MP 정확히(8000×8000 — 실측 최대)는 통과한다")
    func accepts64MPExactly() {
        let harness = PhotoHarness()
        harness.decoder.size = CopiedPhotoPixelSize(width: 8000, height: 8000)
        harness.pasteboard.copy()
        #expect(harness.appear() == .chip)
        #expect(CopiedPhotoHelper.maxPixelCount == 64_000_000)
    }

    @Test("★ 8MB 초과 바이트 — 화소를 보기 전에 거절, 칩 없음 (2-5 「둘 다 집행」)")
    func rejectsOver8MB() {
        let harness = PhotoHarness()
        harness.pasteboard.copy(bytes: CopiedPhotoHelper.maxByteCount + 1)
        #expect(harness.appear() == .none)
        #expect(harness.chip() == nil)
        #expect(harness.decoder.calls.isEmpty)
        let exact = PhotoHarness()
        exact.pasteboard.copy(bytes: CopiedPhotoHelper.maxByteCount)
        #expect(exact.appear() == .chip, "상한 그 자체는 통과")
    }

    @Test("디코드에 실패하면 칩 없음 — 같은 클립보드는 다시 읽지 않는다")
    func thumbnailFailureRejects() {
        let harness = PhotoHarness()
        harness.decoder.failsThumbnail = true
        harness.pasteboard.copy()
        #expect(harness.appear() == .none)
        let reads = harness.pasteboard.dataReads
        harness.appear()
        #expect(harness.pasteboard.dataReads == reads)
    }

    @Test("같은 클립보드로 다시 등장하면 다시 읽지 않고 같은 칩")
    func reappearReusesPreview() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        let first = try #require(harness.chip())
        #expect(harness.appear() == .chip)
        #expect(harness.chip() == first)
        #expect(harness.pasteboard.dataReads == 1, "바이트는 다시 읽지 않는다")
        #expect(harness.decoder.calls == ["size", "thumbnail"])
    }

    @Test("텍스트·인증번호 칩이 이기면 사진은 읽지 않는다 (1-2 — 리치 콘텐츠는 텍스트 우선)")
    func textChipWins() {
        let harness = PhotoHarness()
        harness.pasteboard.copy(strings: true)
        #expect(harness.appear(textChip: true) == .none)
        #expect(harness.chip() == nil)
        #expect(harness.pasteboard.dataReads == 0)
    }

    @Test("클립보드가 비어 보이면(내용 도착 전) 재시도, 텍스트만 있으면 재시도하지 않는다")
    func retryOnlyWhenEmpty() {
        let harness = PhotoHarness()
        harness.pasteboard.changeCount += 1           // 새 changeCount인데 내용이 아직 없다
        #expect(harness.appear() == .retry)
        harness.pasteboard.copy()                     // 내용이 도착 — 재시도에서 읽는다
        #expect(harness.appear() == .chip)
        let text = PhotoHarness()
        text.pasteboard.copyText()
        #expect(text.appear() == .none)
    }

    @Test("✕로 소비한 클립보드는 다시 띄우지 않는다 — 새로 복사하면 뜬다 (D18 소비 장치 공유)")
    func consumedIsNotShown() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.dismiss()
        #expect(harness.chip() == nil)
        let reads = harness.pasteboard.dataReads
        #expect(harness.appear() == .none)
        #expect(harness.pasteboard.dataReads == reads)
        harness.pasteboard.copy()
        #expect(harness.appear() == .chip)
    }
}

// MARK: - 수용 기준 5·6 — 게이트(전체 접근·스위치·secure)와 끄면 비우기

@MainActor
@Suite("사진 도우미 — 게이트·끄기 (수용 기준 5·6)")
struct CopiedPhotoGateTests {

    @Test("★ 게이트 8조합 — 스위치·전체 접근이 켜져 있고 secure가 아닐 때만 읽는다", arguments: [false, true])
    func gateCombinations(enabled: Bool) {
        for fullAccess in [false, true] {
            for secure in [false, true] {
                #expect(CopiedPhotoGate.allowsReading(enabled: enabled, hasFullAccess: fullAccess, isSecureTextEntry: secure)
                        == (enabled && fullAccess && !secure))
            }
        }
    }

    @Test("★ 스위치 끔 — 클립보드를 아예 건드리지 않는다(hasImages조차 0회)")
    func disabledTouchesNothing() {
        let harness = PhotoHarness()
        harness.enabled = false
        harness.pasteboard.copy()
        #expect(harness.appear() == .none)
        #expect(harness.pasteboard.touches == 0)
        #expect(harness.chip() == nil)
    }

    @Test("★ 전체 접근 끔 — 읽기 0·칩 없음 (같은 커밋의 권한 없는 경로)")
    func noFullAccessTouchesNothing() {
        let harness = PhotoHarness()
        harness.hasFullAccess = false
        harness.pasteboard.copy()
        #expect(harness.appear() == .none)
        #expect(harness.pasteboard.touches == 0)
        #expect(harness.chip() == nil)
    }

    @Test("secure 입력란 — 읽지 않고 칩도 없다, 일반 입력란으로 돌아오면 다시 보인다")
    func secureFieldHidesWithoutReading() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.isSecure = true
        let touches = harness.pasteboard.touches
        #expect(harness.appear() == .none)
        #expect(harness.pasteboard.touches == touches)
        #expect(harness.chip() == nil)
        harness.isSecure = false
        #expect(harness.appear() == .chip)
    }

    @Test("★ 탭해서 원본을 들고 있다가 스위치를 끄면(다음 설정 재로드) 원본 사본이 비워진다 (수용 기준 6)")
    func disablingClearsCache() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        #expect(harness.helper.holdsOriginal)
        harness.helper.apply(enabled: false, hasFullAccess: true)   // 설정 재로드
        #expect(!harness.helper.holdsOriginal)
        #expect(harness.chip() == nil)
    }

    @Test("전체 접근이 사라진 등장에서도 원본 사본을 비운다")
    func losingFullAccessClearsCache() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        harness.hasFullAccess = false
        harness.appear()
        #expect(!harness.helper.holdsOriginal)
    }
}

// MARK: - 수용 기준 3·4·7·8 — 탭 → 되쓰기(localOnly·만료), 만료, 자체 쓰기

@MainActor
@Suite("사진 도우미 — 탭 → 되쓰기 (수용 기준 3·4·7·8, 보안 규칙 예외 1~3)")
struct CopiedPhotoWriteTests {

    @Test("★ 탭 → setItems 한 번, localOnly 참·만료 120초가 항상 붙는다 → 칩이 「복사됨 · …」")
    func tapWritesLocalOnlyWithExpiration() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy(image: "public.png", bytes: 2_000)
        harness.appear()
        #expect(harness.tap())
        let write = try #require(harness.pasteboard.writes.first)
        #expect(harness.pasteboard.writes.count == 1)
        #expect(write.localOnly == true)
        #expect(write.expirationDate == PhotoFixture.t0.addingTimeInterval(120))
        #expect(CopiedPhotoHelper.expirationInterval == 120)
        #expect(write.type == "public.png")
        #expect(write.data.count == 2_000, "같은 압축 바이트를 그대로 되쓴다")
        let chip = try #require(harness.chip())
        #expect(chip.stage == .copied)
        #expect(chip.title == "복사됨 · 사진 붙여넣기를 지원하는 입력란에서 길게 눌러 붙여넣기")
        #expect(harness.pasteboard.dataReads == 2, "탭에서 다시 읽는다(프로브는 원본을 버렸다)")
    }

    @Test("★ 탭 없이 쓰는 경로 0 — 프로브·재등장·만료·✕·끄기 어디서도 쓰지 않는다")
    func noWriteWithoutTap() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        for _ in 0..<3 { harness.appear() }
        harness.now = harness.now.addingTimeInterval(500)
        harness.appear()
        _ = harness.chip()
        harness.dismiss()
        harness.pasteboard.copy()
        harness.appear()
        harness.helper.apply(enabled: false, hasFullAccess: true)
        harness.enabled = false
        harness.appear()
        #expect(harness.pasteboard.writes.isEmpty)
    }

    @Test("★ 자체 쓰기를 새 복사로 오인하지 않는다 — 다시 떠도 「복사됨」, 다시 읽지 않는다 (수용 기준 7)")
    func selfWriteIsNotANewCopy() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        let reads = harness.pasteboard.dataReads
        let calls = harness.decoder.calls
        #expect(harness.appear() == .chip)
        #expect(try #require(harness.chip()).stage == .copied)
        #expect(harness.pasteboard.dataReads == reads)
        #expect(harness.decoder.calls == calls)
    }

    @Test("★ 120초가 지나면 칩이 사라지고 원본 사본도 버린다 — 오래된 원본을 되쓰지 않는다 (수용 기준 4)")
    func expiresAfter120s() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        harness.now = PhotoFixture.t0.addingTimeInterval(119)
        #expect(harness.chip()?.stage == .copied)
        harness.now = PhotoFixture.t0.addingTimeInterval(120)
        #expect(harness.chip() == nil)
        #expect(!harness.helper.holdsOriginal)
        #expect(!harness.tap())
        #expect(harness.pasteboard.writes.count == 1)
    }

    @Test("★ 다른 것을 복사하면 이전 원본을 버리고(대체 만료) 새 사진은 「사진 복사」부터 (수용 기준 4)")
    func newCopyReplaces() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        harness.pasteboard.copy(image: "public.png")
        #expect(harness.appear() == .chip)
        #expect(!harness.helper.holdsOriginal, "버림이 먼저다(2-2 ① 교체 겹침 제거)")
        #expect(try #require(harness.chip()).stage == .copyable)
        harness.pasteboard.copyText()
        #expect(harness.appear() == .none)
        #expect(harness.chip() == nil)
    }

    @Test("「복사됨」 칩을 다시 탭 — 들고 있던 원본으로 다시 쓰고 만료를 갱신한다(역시 localOnly)")
    func retapRefreshesExpiry() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        let reads = harness.pasteboard.dataReads
        harness.now = PhotoFixture.t0.addingTimeInterval(60)
        #expect(harness.tap())
        let second = try #require(harness.pasteboard.writes.last)
        #expect(harness.pasteboard.writes.count == 2)
        #expect(second.localOnly == true)
        #expect(second.expirationDate == PhotoFixture.t0.addingTimeInterval(180))
        #expect(harness.pasteboard.dataReads == reads, "클립보드를 다시 읽지 않고 들고 있던 원본을 쓴다")
        harness.now = PhotoFixture.t0.addingTimeInterval(170)
        #expect(harness.chip()?.stage == .copied, "만료가 갱신됐다")
    }

    @Test("탭 전에 클립보드가 바뀌었으면 쓰지 않는다 — 옛 사진으로 새 복사를 덮지 않는다")
    func staleTapDoesNotWrite() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.pasteboard.copyText()          // 키보드가 떠 있는 동안 호스트에서 텍스트를 복사
        #expect(!harness.tap())
        #expect(harness.pasteboard.writes.isEmpty)
        #expect(harness.chip() == nil)
    }

    @Test("「복사됨」 상태에서 다른 것을 복사했으면 다시 탭해도 쓰지 않는다")
    func staleCopiedTapDoesNotWrite() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        harness.pasteboard.copyText()
        #expect(!harness.tap())
        #expect(harness.pasteboard.writes.count == 1)
        #expect(!harness.helper.holdsOriginal)
    }

    @Test("✕ — 「복사됨」 칩을 물리면 원본 사본도 비우고 그 클립보드를 소비한다")
    func dismissCopiedClearsCache() {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        harness.tap()
        harness.dismiss()
        #expect(harness.chip() == nil)
        #expect(!harness.helper.holdsOriginal)
        #expect(harness.consumed == harness.pasteboard.changeCount)
        #expect(harness.appear() == .none)
    }
}

// MARK: - D18·D19 — 사진 칩도 붙여넣기 칩이다

@MainActor
@Suite("사진 도우미 — 툴바 우선순위 (D18·D19 회귀)")
struct CopiedPhotoToolbarTests {

    private func copyableChip() throws -> CopiedPhotoChip {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        return try #require(harness.chip())
    }

    @Test("★ 사진 칩이 보이면 채움글 칩·추천단어는 같은 줄에 없다 — [사진][✕] (D18·D19)")
    func photoChipStandsAlone() throws {
        let photo = PasteChipGate.visiblePhotoChip(
            try copyableChip(), hasFullAccess: true, isSecureTextEntry: false,
            isSuppressedByTyping: false, hasTextChip: false)
        let hasPasteChip = PasteChipGate.hasPasteChip(text: nil, photo: photo)
        #expect(hasPasteChip)
        let snippet = SnippetSuggestion(trigger: "새해인사", title: "새해 인사", body: "새해 복 많이 받으세요")
        #expect(SnippetChipGate.visibleSnippet(snippet, isDismissed: false, hasPasteChip: hasPasteChip) == nil)
        #expect(!WordSuggestionGate.allowsWords(
            isSecureTextEntry: false, hasSnippet: false, hasPasteChip: hasPasteChip,
            isDismissed: false, isSuppressedAfterCursorMove: false))
    }

    @Test("사진 칩 게이트 — 전체 접근·secure·타이핑 억제·텍스트 칩 중 하나라도 걸리면 없음")
    func photoChipGate() throws {
        let chip = try copyableChip()
        #expect(PasteChipGate.visiblePhotoChip(
            chip, hasFullAccess: true, isSecureTextEntry: false, isSuppressedByTyping: false, hasTextChip: false) == chip)
        for blocked in 0..<4 {
            #expect(PasteChipGate.visiblePhotoChip(
                chip, hasFullAccess: blocked != 0, isSecureTextEntry: blocked == 1,
                isSuppressedByTyping: blocked == 2, hasTextChip: blocked == 3) == nil)
        }
    }

    @Test("회귀 — 사진 칩이 없으면 채움글·추천단어 게이트는 지금과 같다")
    func noPhotoUnchanged() {
        let hasPasteChip = PasteChipGate.hasPasteChip(text: nil, photo: nil)
        #expect(!hasPasteChip)
        let snippet = SnippetSuggestion(trigger: "새해인사", title: "새해 인사", body: "새해 복 많이 받으세요")
        #expect(SnippetChipGate.visibleSnippet(snippet, isDismissed: false, hasPasteChip: hasPasteChip) == snippet)
    }

    @Test("VoiceOver 라벨 — 탭 전·뒤가 무엇을 하는지 말한다")
    func accessibilityLabels() throws {
        let harness = PhotoHarness()
        harness.pasteboard.copy()
        harness.appear()
        #expect(try #require(harness.chip()).accessibilityLabel == "복사한 사진, 탭하면 붙여넣을 수 있게 클립보드에 다시 담아요")
        harness.tap()
        #expect(try #require(harness.chip()).accessibilityLabel
                == "사진을 클립보드에 담았어요. 사진 붙여넣기를 지원하는 입력란에서 길게 눌러 붙여넣으세요")
    }
}

// MARK: - 실제 ImageIO — 헤더로 화소 수, 축소 썸네일

@Suite("사진 도우미 — ImageIO 디코더")
struct ImageIOCopiedPhotoDecoderTests {

    @Test("헤더만 읽어 화소 크기를 낸다")
    func readsPixelSize() throws {
        let data = PhotoFixture.png(width: 40, height: 30)
        let size = try #require(ImageIOCopiedPhotoDecoder().pixelSize(of: data))
        #expect(size == CopiedPhotoPixelSize(width: 40, height: 30))
        #expect(size.pixelCount == 1_200)
    }

    @Test("썸네일은 긴 변이 상한 이하로 줄어든다")
    func makesSmallThumbnail() throws {
        let data = PhotoFixture.png(width: 400, height: 300)
        let thumbnail = try #require(ImageIOCopiedPhotoDecoder().thumbnail(of: data, maxPixelSize: 40))
        #expect(max(thumbnail.width, thumbnail.height) <= 40)
    }

    @Test("그림이 아닌 바이트는 nil")
    func garbageIsNil() {
        let garbage = Data("not an image".utf8)
        #expect(ImageIOCopiedPhotoDecoder().pixelSize(of: garbage) == nil)
        #expect(ImageIOCopiedPhotoDecoder().thumbnail(of: garbage, maxPixelSize: 40) == nil)
    }
}
