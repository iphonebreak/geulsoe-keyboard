import Foundation
import Testing
@testable import PackImport

// 외부 채움글 1-e ① — xlsx 컨테이너(ZIP) 읽기의 **정상 경로**(PDR 6-5·6-5a, AC-30 「정상 bit 3·정상 bit 3 꺼짐은 수용」, AC-34 cap+1).
// 실물 표본: 샘플 xlsx 2종(개인 정보 0 — `verify-p9-p10.md` 9절)은 Fixtures에 두고, P-10 시험 파일 3개(엑셀 Mac·윈도우·구글 시트)는
// 작성자 실명·계정·경로가 들어 있어(PDR 6-6 5번) **저장소에 복사하지 않고** 로컬 전용 `docs/` 자리에서 읽는다 — 없으면 건너뛴다.

/// 실물 표본의 엔트리 이름 → 원본 크기(중앙 디렉터리 값 — `zipfile`로 확인한 수치, P-10 3절)
struct ArchiveSample: Sendable, CustomTestStringConvertible {
    let file: String
    let entries: [String: Int]
    /// 6-5b가 읽는 파트 — 이 표본에서 실제로 해제해 크기·CRC를 확인한다
    let parts: [(String, XLSXArchive.PartKind)]
    var testDescription: String { file }

    static let required: [(String, XLSXArchive.PartKind)] = [
        ("[Content_Types].xml", .contentTypes), ("_rels/.rels", .relationships), ("xl/workbook.xml", .workbook),
        ("xl/_rels/workbook.xml.rels", .relationships), ("xl/worksheets/sheet1.xml", .worksheet),
        ("xl/sharedStrings.xml", .sharedStrings), ("xl/styles.xml", .styles),
    ]

    static let bundled: [ArchiveSample] = [
        ArchiveSample(file: "sample-numbered.xlsx", entries: [
            "[Content_Types].xml": 1_168, "_rels/.rels": 588, "xl/workbook.xml": 1_279, "xl/_rels/workbook.xml.rels": 698,
            "xl/worksheets/sheet1.xml": 3_630, "xl/theme/theme1.xml": 8_722, "xl/styles.xml": 18_811, "xl/sharedStrings.xml": 2_979,
            "docProps/core.xml": 593, "docProps/app.xml": 806,
        ], parts: required),
        ArchiveSample(file: "sample-phrases.xlsx", entries: [
            "[Content_Types].xml": 930, "_rels/.rels": 297, "xl/workbook.xml": 1_278, "xl/_rels/workbook.xml.rels": 698,
            "xl/worksheets/sheet1.xml": 3_083, "xl/theme/theme1.xml": 8_722, "xl/styles.xml": 18_939, "xl/sharedStrings.xml": 2_720,
        ], parts: required),
    ]

    static let localOnly: [ArchiveSample] = [
        // 구글 시트 — 모든 엔트리 플래그 0x0808(bit 3 + bit 11), 로컬 CRC·크기 0, 서명 있는 디스크립터, [Content_Types].xml이 맨 끝
        ArchiveSample(file: "gsheets-xlsx.xlsx", entries: [
            "xl/drawings/drawing1.xml": 775, "xl/worksheets/sheet1.xml": 5_390, "xl/worksheets/_rels/sheet1.xml.rels": 298,
            "xl/theme/theme1.xml": 3_757, "xl/sharedStrings.xml": 11_190, "xl/styles.xml": 2_895, "xl/persons/person.xml": 161,
            "xl/workbook.xml": 807, "xl/_rels/workbook.xml.rels": 822, "_rels/.rels": 296, "[Content_Types].xml": 1_247,
        ], parts: required),
        // 엑셀 Mac — 플래그 0x0006, 로컬 헤더에만 채움 확장 필드(0xA220), 압축비 22.2:1(sharedStrings)
        ArchiveSample(file: "mac-excel-xlsx.xlsx", entries: [
            "[Content_Types].xml": 1_296, "_rels/.rels": 588, "xl/workbook.xml": 2_426, "xl/_rels/workbook.xml.rels": 831,
            "xl/worksheets/sheet1.xml": 6_786, "xl/theme/theme1.xml": 8_722, "xl/styles.xml": 4_273, "xl/sharedStrings.xml": 44_996,
            "xl/calcChain.xml": 206, "docProps/core.xml": 613, "docProps/app.xml": 797,
        ], parts: required),
        ArchiveSample(file: "win-excel-xlsx.xlsx", entries: [
            "[Content_Types].xml": 1_296, "_rels/.rels": 588, "xl/workbook.xml": 2_422, "xl/_rels/workbook.xml.rels": 831,
            "xl/worksheets/sheet1.xml": 6_140, "xl/theme/theme1.xml": 8_722, "xl/styles.xml": 2_961, "xl/sharedStrings.xml": 11_743,
            "xl/calcChain.xml": 206, "docProps/core.xml": 637, "docProps/app.xml": 787,
        ], parts: required),
    ]

    /// 로컬 전용 P-10 표본 자리 — 저장소 루트의 `docs/`(.gitignore)
    static func localURL(_ file: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // PackImportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // PackImport
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // KeyBoard
            .appendingPathComponent("docs/design/external-snippet-packs/p9-out/\(file)")
    }

    static var localSamplesPresent: Bool {
        localOnly.allSatisfy { FileManager.default.fileExists(atPath: localURL($0.file).path) }
    }
}

@Suite("외부 채움글 1-e ① — xlsx 컨테이너 읽기 (6-5·6-5a)")
struct XLSXArchiveTests {

    private func verify(_ sample: ArchiveSample, data: Data) throws {
        var archive = try XLSXArchive.open(data)
        #expect(archive.entryNames == Set(sample.entries.keys))
        for (name, kind) in sample.parts {
            let part = try archive.read(name, as: kind)
            #expect(part.count == sample.entries[name], "\(name)")
            #expect(part.starts(with: Array("<?xml".utf8)), "\(name)")
        }
    }

    @Test("★ 샘플 xlsx 2종(재압축 판, 플래그 0x0000) — 엔트리·필요한 파트가 기대대로", arguments: ArchiveSample.bundled)
    func bundledSamples(_ sample: ArchiveSample) throws {
        let name = (sample.file as NSString).deletingPathExtension
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "xlsx", subdirectory: "Fixtures"))
        try verify(sample, data: Data(contentsOf: url))
    }

    @Test("★ P-10 실물 xlsx 3종(구글 bit 3·엑셀 Mac·윈도우) — 엔트리·필요한 파트가 기대대로 (로컬 전용 표본)",
          .enabled(if: ArchiveSample.localSamplesPresent, "docs/ 표본이 없는 클론에서는 건너뛴다(개인 정보 — 저장소 밖)"),
          arguments: ArchiveSample.localOnly)
    func realGeneratorSamples(_ sample: ArchiveSample) throws {
        try verify(sample, data: Data(contentsOf: ArchiveSample.localURL(sample.file)))
    }

    @Test("★ 합성 정상 — 엑셀 모양(bit 3 꺼짐)·구글 모양(서명 있는/없는 디스크립터)·stored·로컬만의 채움 확장 필드",
          arguments: ["excel", "google-signed", "google-unsigned", "stored", "padding"])
    func syntheticAccepted(_ style: String) throws {
        var entries = ZipFixture.workbookEntries()
        for index in entries.indices {
            switch style {
            case "google-signed": entries[index] = entries[index].googleStyle()
            case "google-unsigned": entries[index] = entries[index].googleStyle(); entries[index].descriptor = .unsigned
            case "stored": entries[index].method = 0; entries[index].flags = 0
            case "padding": entries[index].localExtra = ZipFixture.excelPaddingExtra
            default: break
            }
        }
        var archive = try XLSXArchive.open(ZipSpec(entries).build())
        #expect(archive.entryNames.count == entries.count)
        for (name, kind) in ArchiveSample.required {
            let expected = entries[ZipFixture.index(of: name, in: entries)].content
            #expect(try archive.read(name, as: kind) == Data(expected), "\(name)")
        }
    }

    @Test("구글 모양 — 로컬 헤더에 0 대신 중앙 디렉터리와 같은 값을 써도 받는다(6-5a 「0이 아니고 중앙과도 다르면 거부」)")
    func deferredHeaderWithRealValues() throws {
        var entries = ZipFixture.workbookEntries()
        entries[4] = entries[4].googleStyle()
        let payload = ZipFixture.deflate(entries[4].content)
        entries[4].localCRC = CRC32.checksum(entries[4].content)
        entries[4].localCompressedSize = UInt32(payload.count)
        entries[4].localUncompressedSize = UInt32(entries[4].content.count)
        var archive = try XLSXArchive.open(ZipSpec(entries).build())
        #expect(try archive.read("xl/worksheets/sheet1.xml", as: .worksheet) == Data(entries[4].content))
    }

    @Test("UTF-8 플래그(bit 11)가 있는 비ASCII 이름은 받는다 — 이름 완전 일치로만 찾는다")
    func utf8FlaggedName() throws {
        var extra = ZipEntrySpec("xl/media/그림.bin", "x", method: 0)
        extra.flags = 0x0800
        var archive = try XLSXArchive.open(ZipFixture.workbook { $0.append(extra) }.build())
        #expect(archive.entryNames.contains("xl/media/그림.bin"))
        #expect(try archive.read("xl/media/그림.bin", as: .relationships) == Data("x".utf8))
    }

    @Test("★ 파일 바이트 경계 — 정확히 상한이면 받는다(cap+1은 적대 표 F04)")
    func fileByteBoundary() throws {
        let bytes = ZipFixture.workbook().build()
        var limits = XLSXArchiveLimits.product
        limits.fileBytes = bytes.count
        #expect(throws: Never.self) { _ = try XLSXArchive.open(bytes, limits: limits) }
    }

    @Test("★ 파트 출력 경계 — 정확히 상한이면 받고, 한 바이트 넘으면 partTooLarge", arguments: [(0, true), (1, false)])
    func partOutputBoundary(over: Int, accepted: Bool) throws {
        var limits = XLSXArchiveLimits.product
        let content = ZipFixture.workbookEntries()[4].content
        limits.worksheetBytes = content.count - over
        var archive = try XLSXArchive.open(ZipFixture.workbook().build(), limits: limits)
        if accepted {
            #expect(try archive.read("xl/worksheets/sheet1.xml", as: .worksheet) == Data(content))
        } else {
            #expect(throws: XLSXArchiveFailure.partTooLarge) { _ = try archive.read("xl/worksheets/sheet1.xml", as: .worksheet) }
        }
    }

    @Test("★ 압축비 경계 — 실제 압축비가 상한 안이면 받는다")
    func ratioBoundary() throws {
        var limits = XLSXArchiveLimits.product
        let content = [UInt8](repeating: 0x41, count: 100_000)
        let compressed = ZipFixture.deflate(content).count
        let spec = ZipFixture.workbook { $0[4].content = content }
        limits.compressionRatio = (content.count + compressed - 1) / compressed  // 올림 — 정확히 상한 안
        var archive = try XLSXArchive.open(spec.build(), limits: limits)
        #expect(try archive.read("xl/worksheets/sheet1.xml", as: .worksheet).count == content.count)
        limits.compressionRatio -= 1
        var tight = try XLSXArchive.open(spec.build(), limits: limits)
        #expect(throws: XLSXArchiveFailure.compressionRatioExceeded) { _ = try tight.read("xl/worksheets/sheet1.xml", as: .worksheet) }
    }

    @Test("제품 상한값 — PDR 6-5 후보값(파일 3MB·엔트리 200·압축비 100·sheet/sharedStrings 8MB·styles 1MB·합계 20MB)")
    func productLimits() {
        let limits = XLSXArchiveLimits.product
        #expect(limits.fileBytes == 3_000_000)
        #expect(limits.entries == 200)
        #expect(limits.compressionRatio == 100)
        #expect(limits.worksheetBytes == 8_000_000)
        #expect(limits.sharedStringsBytes == 8_000_000)
        #expect(limits.stylesBytes == 1_000_000)
        #expect(limits.totalOutputBytes == 20_000_000)
        #expect(limits.nameBytes == 255)
    }

    @Test("CRC32 표준 벡터(IEEE 802.3) — 「123456789」 → CBF43926")
    func crcVector() {
        #expect(CRC32.checksum(Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum([]) == 0)
    }
}

@Suite("외부 채움글 1-e ① — raw DEFLATE 해제 (Compression `COMPRESSION_ZLIB`)")
struct XLSXInflaterTests {

    @Test("왕복 — 출력은 원문 그대로", arguments: [1, 1_000, 200_000])
    func roundTrip(count: Int) {
        let content = ZipFixture.moderatelyCompressible(count: count)
        #expect(XLSXInflater.inflate(ZipFixture.deflate(content), limit: count) == .success(content))
    }

    @Test("★ 출력 상한 cap+1 — 정확히 상한이면 받고, 넘으면 상한+1에서 멈춘다")
    func limit() {
        let content = [UInt8](repeating: 0, count: 1_000_000)
        let compressed = ZipFixture.deflate(content)
        #expect(XLSXInflater.inflate(compressed, limit: 1_000_000) == .success(content))
        #expect(XLSXInflater.inflate(compressed, limit: 999_999) == .failure(.exceedsLimit))
        #expect(XLSXInflater.inflate(compressed, limit: 0) == .failure(.exceedsLimit))
    }

    @Test("빈 deflate(03 00)는 빈 출력")
    func emptyStream() {
        #expect(XLSXInflater.inflate([0x03, 0x00], limit: 0) == .success([]))
    }

    @Test("손상 — 빈 입력·잘림·남는 바이트·zlib 머리(78 9C)가 붙은 스트림", arguments: ["empty", "truncated", "trailing", "zlib-header"])
    func corrupt(_ kind: String) {
        let content = ZipFixture.moderatelyCompressible(count: 5_000)
        let compressed = ZipFixture.deflate(content)
        let input: [UInt8] = switch kind {
        case "empty": []
        case "truncated": Array(compressed.dropLast(3))
        case "trailing": compressed + [0x00]
        default: [0x78, 0x9C] + compressed
        }
        #expect(XLSXInflater.inflate(input, limit: 10_000) == .failure(.corrupt))
    }
}
