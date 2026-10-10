import Foundation
import Testing
@testable import PackImport

// 외부 채움글 1-e ① — **적대 아카이브 fixture 표**(PDR AC-30, 6-5·6-5a). 전부 테스트 안에서 바이트로 짓는다(`ZipFixtureBuilder`).
// 이 표는 **컨테이너(ZIP) 층**만이다 — `<!DOCTYPE>`·`<!ENTITY>`·깊은 중첩·`dimension` 거짓·매크로 콘텐츠 타입은 XML 층(1-e ②)이 같은 표에 더한다.
// 기대값은 「열기에서 거부」 / 「읽기에서 거부」 / 「제한된 채로 읽힘(원문 그대로)」 셋 중 하나다.

struct ArchiveCase: Sendable, CustomTestStringConvertible {

    enum Expectation: Sendable {
        /// `XLSXArchive.open`이 이 이유로 거부한다
        case openFails(XLSXArchiveFailure)
        /// 열기는 되고, 앞 읽기들은 성공하고, 마지막 읽기가 이 이유로 거부된다
        case readFails([Read], XLSXArchiveFailure)
        /// 열기·읽기가 되고 결과가 이 바이트 그대로다(재귀 해제·추가 해석 없음)
        case readsExactly(Read, [UInt8])
    }

    struct Read: Sendable {
        let name: String
        let kind: XLSXArchive.PartKind
        init(_ name: String, _ kind: XLSXArchive.PartKind) {
            self.name = name
            self.kind = kind
        }
    }

    let id: String
    let title: String
    var limits: XLSXArchiveLimits = .product
    let build: @Sendable () -> [UInt8]
    let expect: Expectation

    var testDescription: String { "\(id) \(title)" }
}

// MARK: - 표

extension ArchiveCase {

    static let sheet = Read("xl/worksheets/sheet1.xml", .worksheet)
    static let strings = Read("xl/sharedStrings.xml", .sharedStrings)
    static let styles = Read("xl/styles.xml", .styles)

    /// 최소 워크북을 고쳐 짓는다
    static func workbook(_ adjust: @escaping @Sendable (inout ZipSpec) -> Void) -> @Sendable () -> [UInt8] {
        {
            var spec = ZipFixture.workbook()
            adjust(&spec)
            return spec.bytes()
        }
    }

    /// 이름으로 엔트리 하나를 고친다
    static func entry(_ name: String, _ adjust: @escaping @Sendable (inout ZipEntrySpec) -> Void) -> @Sendable () -> [UInt8] {
        workbook { spec in adjust(&spec.entries[ZipFixture.index(of: name, in: spec.entries)]) }
    }

    /// 다 지은 뒤 EOCD 필드 바이트를 덮는다(오프셋은 EOCD 시작 기준)
    static func patchingEndRecord(at field: Int, _ bytes: @escaping @Sendable ([UInt8]) -> [UInt8]) -> @Sendable () -> [UInt8] {
        {
            var archive = ZipFixture.workbook().bytes()
            let end = archive.endRecordOffset
            let current = Array(archive[(end + field)..<(end + field + 4)])
            let replacement = bytes(current)
            archive.replaceSubrange((end + field)..<(end + field + replacement.count), with: replacement)
            return archive
        }
    }

    static func le16(_ value: UInt16) -> [UInt8] { var bytes: [UInt8] = []; bytes.le16(value); return bytes }
    static func le32(_ value: UInt32) -> [UInt8] { var bytes: [UInt8] = []; bytes.le32(value); return bytes }

    static let sheetName = "xl/worksheets/sheet1.xml"
    static let zeros4MB = [UInt8](repeating: 0, count: 4_000_000)

    static let all: [ArchiveCase] = fileAndEndRecord + names + methodsAndFields + localVersusCentral + inflation

    // 파일·EOCD
    static let fileAndEndRecord: [ArchiveCase] = [
        ArchiveCase(id: "F01", title: "빈 바이트", build: { [] }, expect: .openFails(.notZip)),
        ArchiveCase(id: "F02", title: "ZIP이 아닌 글(CSV)", build: { Array("번호,제목,본문\n1,가,나\n".utf8) }, expect: .openFails(.notZip)),
        ArchiveCase(id: "F03", title: "OLE2 매직 — 비밀번호 걸린 엑셀·.xls",
                    build: { [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1] + [UInt8](repeating: 0, count: 504) },
                    expect: .openFails(.legacyOrProtectedWorkbook)),
        ArchiveCase(id: "F04", title: "파일 바이트 cap+1",
                    limits: { var limits = XLSXArchiveLimits.product; limits.fileBytes = ZipFixture.workbook().bytes().count - 1; return limits }(),
                    build: { ZipFixture.workbook().bytes() }, expect: .openFails(.fileTooLarge)),
        ArchiveCase(id: "F05", title: "앞에 다른 형식을 붙인 폴리글롯(<html> + ZIP)",
                    build: workbook { $0.prefix = Array("<html><body>".utf8) }, expect: .openFails(.notZip)),
        ArchiveCase(id: "F06", title: "가짜 빈 아카이브 EOCD로 시작하고 뒤에 엔트리(앞에서 읽는 독자는 빈 파일로 본다)",
                    build: workbook { $0.prefix = [0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18) }, expect: .openFails(.notZip)),
        ArchiveCase(id: "E01", title: "EOCD 없음(잘린 파일)", build: workbook { $0.omitEndRecord = true }, expect: .openFails(.missingEndRecord)),
        ArchiveCase(id: "E02", title: "EOCD 뒤 주석 밖 쓰레기 바이트", build: workbook { $0.trailing = Array("junk".utf8) },
                    expect: .openFails(.missingEndRecord)),
        ArchiveCase(id: "E03", title: "주석 길이가 실제보다 김", build: workbook { $0.commentLength = 10 }, expect: .openFails(.missingEndRecord)),
        ArchiveCase(id: "E04", title: "EOCD 둘 — 두 번째가 첫 번째 주석 안에서 파일 끝까지 유효",
                    build: workbook { $0.comment = [0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18) },
                    expect: .openFails(.multipleEndRecords)),
        ArchiveCase(id: "E05", title: "주석 안에 EOCD 서명(뒤에서 찾는 독자는 이것을 잡는다)",
                    build: workbook { $0.comment = Array("abc".utf8) + [0x50, 0x4B, 0x05, 0x06] + Array("xyz".utf8) },
                    expect: .openFails(.multipleEndRecords)),
        ArchiveCase(id: "E06", title: "ZIP64 EOCD 로케이터", build: workbook { $0.zip64Locator = true }, expect: .openFails(.zip64)),
        ArchiveCase(id: "E07", title: "EOCD 엔트리 수 0xFFFF(ZIP64 표시)",
                    build: workbook { $0.entriesOnDisk = 0xFFFF; $0.entriesTotal = 0xFFFF }, expect: .openFails(.zip64)),
        ArchiveCase(id: "E08", title: "EOCD 중앙 디렉터리 오프셋 0xFFFFFFFF", build: workbook { $0.centralDirectoryOffset = 0xFFFF_FFFF },
                    expect: .openFails(.zip64)),
        ArchiveCase(id: "E09", title: "다중 디스크(디스크 번호 1)", build: workbook { $0.diskNumber = 1 }, expect: .openFails(.multiDisk)),
        ArchiveCase(id: "E10", title: "이 디스크 엔트리 수 ≠ 전체 엔트리 수", build: workbook { $0.entriesOnDisk = 6 }, expect: .openFails(.multiDisk)),
        ArchiveCase(id: "E11", title: "엔트리 0개(빈 아카이브)", build: { ZipSpec([]).bytes() }, expect: .openFails(.noEntries)),
        ArchiveCase(id: "E12", title: "엔트리 수 cap+1(201개)",
                    build: { ZipSpec((0...200).map { ZipEntrySpec("xl/media/f\($0).bin", "x", method: 0) }).bytes() },
                    expect: .openFails(.tooManyEntries)),
        ArchiveCase(id: "E13", title: "중앙 디렉터리 크기 거짓(+1)",
                    build: patchingEndRecord(at: 12) { le32($0.readLE32(at: 0) + 1) }, expect: .openFails(.centralDirectoryMismatch)),
        ArchiveCase(id: "E14", title: "EOCD 엔트리 수가 실제보다 많음", build: workbook { $0.entriesOnDisk = 8; $0.entriesTotal = 8 },
                    expect: .openFails(.centralDirectoryMismatch)),
        ArchiveCase(id: "E15", title: "EOCD 엔트리 수가 실제보다 적음", build: workbook { $0.entriesOnDisk = 6; $0.entriesTotal = 6 },
                    expect: .openFails(.centralDirectoryMismatch)),
        ArchiveCase(id: "E16", title: "중앙 디렉터리 레코드 서명 손상",
                    build: {
                        var archive = ZipFixture.workbook().bytes()
                        let central = Int(archive.readLE32(at: archive.endRecordOffset + 16))
                        archive[central + 2] = 0x09
                        return archive
                    },
                    expect: .openFails(.centralDirectoryMismatch)),
        ArchiveCase(id: "E17", title: "중앙 디렉터리 오프셋이 한 바이트 앞(EOCD와 어긋남)",
                    build: patchingEndRecord(at: 16) { le32($0.readLE32(at: 0) - 1) }, expect: .openFails(.centralDirectoryMismatch)),
    ]

    // 엔트리 이름 — 경로 조작·모호성
    static let names: [ArchiveCase] = [
        ArchiveCase(id: "N01", title: "같은 이름 두 번",
                    build: workbook { $0.entries.append(ZipEntrySpec("xl/workbook.xml", "<workbook/>")) }, expect: .openFails(.duplicateEntryName)),
        ArchiveCase(id: "N02", title: "대소문자만 다른 이름(OPC는 대소문자 무시 — 독자마다 다른 파트)",
                    build: workbook { $0.entries.append(ZipEntrySpec("XL/Workbook.XML", "<workbook/>")) }, expect: .openFails(.duplicateEntryName)),
        ArchiveCase(id: "N03", title: "`..` 상위 경로(zip slip)",
                    build: workbook { $0.entries.append(ZipEntrySpec("../../evil.xml", "x")) }, expect: .openFails(.unsafeEntryPath)),
        ArchiveCase(id: "N04", title: "절대 경로",
                    build: workbook { $0.entries.append(ZipEntrySpec("/xl/evil.xml", "x")) }, expect: .openFails(.unsafeEntryPath)),
        ArchiveCase(id: "N05", title: "백슬래시 구분자(윈도우 경로 조작)",
                    build: workbook { $0.entries.append(ZipEntrySpec(#"xl\..\..\evil.xml"#, "x")) }, expect: .openFails(.unsafeEntryPath)),
        ArchiveCase(id: "N06", title: "드라이브 문자",
                    build: workbook { $0.entries.append(ZipEntrySpec("C:/evil.xml", "x")) }, expect: .openFails(.unsafeEntryPath)),
        ArchiveCase(id: "N07", title: "`.`·빈 경로 조각(정규화하면 다른 파트와 같아짐)",
                    build: workbook { $0.entries.append(ZipEntrySpec("xl/./workbook.xml", "x")) }, expect: .openFails(.unsafeEntryPath)),
        ArchiveCase(id: "N08", title: "이름 안 NUL",
                    build: workbook { $0.entries.append(ZipEntrySpec(name: Array("xl/workbook.xml".utf8) + [0] + Array(".png".utf8), content: [0x78])) },
                    expect: .openFails(.invalidEntryName)),
        ArchiveCase(id: "N09", title: "이름 길이 cap+1(256바이트)",
                    build: workbook { $0.entries.append(ZipEntrySpec("xl/" + String(repeating: "a", count: 253), "x")) },
                    expect: .openFails(.entryNameTooLong)),
        ArchiveCase(id: "N10", title: "UTF-8 플래그 없는 비ASCII 이름(인코딩 모호)",
                    build: workbook { $0.entries.append(ZipEntrySpec("xl/문구.xml", "x")) }, expect: .openFails(.invalidEntryName)),
        ArchiveCase(id: "N11", title: "UTF-8 플래그는 있는데 깨진 UTF-8",
                    build: workbook { spec in
                        var bad = ZipEntrySpec(name: Array("xl/".utf8) + [0xC3, 0x28] + Array(".xml".utf8), content: [0x78])
                        bad.flags = 0x0806
                        spec.entries.append(bad)
                    },
                    expect: .openFails(.invalidEntryName)),
        ArchiveCase(id: "N12", title: "빈 이름", build: workbook { $0.entries.append(ZipEntrySpec("", "x")) }, expect: .openFails(.invalidEntryName)),
    ]

    // 압축 방식·플래그·확장 필드
    static let methodsAndFields: [ArchiveCase] = [
        ArchiveCase(id: "M01", title: "암호화 플래그(bit 0)", build: entry(sheetName) { $0.flags = 0x0007 }, expect: .openFails(.encrypted)),
        ArchiveCase(id: "M02", title: "강한 암호화 플래그(bit 6)", build: entry(sheetName) { $0.flags = 0x0046 }, expect: .openFails(.encrypted)),
        ArchiveCase(id: "M03", title: "AES(방식 99 + 확장 0x9901)",
                    build: entry(sheetName) {
                        $0.method = 99
                        $0.centralExtra = [0x01, 0x99, 0x07, 0x00, 0x02, 0x00, 0x41, 0x45, 0x03, 0x08, 0x00]
                    },
                    expect: .openFails(.encrypted)),
        ArchiveCase(id: "M04", title: "bzip2(방식 12)", build: entry(sheetName) { $0.method = 12 }, expect: .openFails(.unsupportedCompression)),
        ArchiveCase(id: "M05", title: "LZMA(방식 14)", build: entry(sheetName) { $0.method = 14 }, expect: .openFails(.unsupportedCompression)),
        ArchiveCase(id: "M06", title: "모르는 플래그(bit 4 enhanced deflate)", build: entry(sheetName) { $0.flags = 0x0016 },
                    expect: .openFails(.unsupportedFlags)),
        ArchiveCase(id: "M07", title: "중앙 디렉터리의 ZIP64 확장 필드", build: entry(sheetName) { $0.centralExtra = ZipFixture.zip64Extra },
                    expect: .openFails(.zip64)),
        ArchiveCase(id: "M08", title: "로컬 헤더에만 ZIP64 확장 필드", build: entry(sheetName) { $0.localExtra = ZipFixture.zip64Extra },
                    expect: .openFails(.zip64)),
        ArchiveCase(id: "M09", title: "중앙 디렉터리 압축 크기 0xFFFFFFFF",
                    build: entry(sheetName) { $0.centralCompressedSize = 0xFFFF_FFFF }, expect: .openFails(.zip64)),
        ArchiveCase(id: "M10", title: "엔트리 시작 디스크 1", build: entry(sheetName) { $0.centralDiskStart = 1 }, expect: .openFails(.multiDisk)),
        ArchiveCase(id: "M11", title: "확장 필드 길이가 남은 바이트를 넘음",
                    build: entry(sheetName) { $0.centralExtra = [0x99, 0x99, 0x10, 0x00, 0x01] }, expect: .openFails(.malformedExtraField)),
        ArchiveCase(id: "M12", title: "stored인데 압축 크기 ≠ 원본 크기",
                    build: entry(sheetName) { $0.method = 0; $0.sizeExtension = 1 }, expect: .openFails(.storedSizeMismatch)),
    ]

    // 로컬 헤더 ↔ 중앙 디렉터리(6-5a) · 엔트리 범위
    static let localVersusCentral: [ArchiveCase] = [
        ArchiveCase(id: "L01", title: "로컬 이름 ≠ 중앙(같은 길이)", build: entry("xl/workbook.xml") { $0.localName = Array("xl/workbooK.xml".utf8) },
                    expect: .openFails(.localHeaderMismatch(.name))),
        ArchiveCase(id: "L02", title: "로컬 이름 길이 ≠ 중앙", build: entry("xl/workbook.xml") { $0.localName = Array("xl/workbook.xml.bak".utf8) },
                    expect: .openFails(.localHeaderMismatch(.name))),
        ArchiveCase(id: "L03", title: "로컬 압축 방식 ≠ 중앙", build: entry(sheetName) { $0.localMethod = 0 },
                    expect: .openFails(.localHeaderMismatch(.method))),
        ArchiveCase(id: "L04", title: "로컬 플래그 ≠ 중앙(bit 3 한쪽만)", build: entry(sheetName) { $0.localFlags = 0x000E },
                    expect: .openFails(.localHeaderMismatch(.flags))),
        ArchiveCase(id: "L05", title: "중앙 오프셋이 로컬 헤더가 아닌 곳", build: entry("[Content_Types].xml") { $0.centralOffset = 1 },
                    expect: .openFails(.localHeaderMismatch(.signature))),
        ArchiveCase(id: "L06", title: "중앙 오프셋이 파일 밖", build: entry(sheetName) { $0.centralOffset = 0x00FF_FFFF },
                    expect: .openFails(.entryOutOfBounds)),
        ArchiveCase(id: "L07", title: "bit 3 꺼짐 — 로컬 CRC ≠ 중앙", build: entry(sheetName) { $0.localCRC = 0xDEAD_BEEF },
                    expect: .openFails(.localHeaderMismatch(.crc))),
        ArchiveCase(id: "L08", title: "bit 3 꺼짐 — 로컬 압축 크기 ≠ 중앙", build: entry(sheetName) { $0.localCompressedSize = 3 },
                    expect: .openFails(.localHeaderMismatch(.compressedSize))),
        ArchiveCase(id: "L09", title: "bit 3 꺼짐 — 로컬 원본 크기 ≠ 중앙", build: entry(sheetName) { $0.localUncompressedSize = 3 },
                    expect: .openFails(.localHeaderMismatch(.uncompressedSize))),
        ArchiveCase(id: "L10", title: "bit 3 켜짐 — 로컬 CRC가 0도 중앙값도 아님",
                    build: entry(sheetName) { $0 = $0.googleStyle(); $0.localCRC = 0xDEAD_BEEF },
                    expect: .openFails(.localHeaderMismatch(.crc))),
        ArchiveCase(id: "L11", title: "bit 3 켜짐 — 디스크립터 CRC ≠ 중앙",
                    build: entry(sheetName) { $0 = $0.googleStyle(); $0.descriptorCRC = 0xDEAD_BEEF },
                    expect: .openFails(.dataDescriptorMismatch)),
        ArchiveCase(id: "L12", title: "bit 3 켜짐 — 디스크립터 크기 ≠ 중앙",
                    build: entry(sheetName) { $0 = $0.googleStyle(); $0.descriptorUncompressedSize = 7 },
                    expect: .openFails(.dataDescriptorMismatch)),
        ArchiveCase(id: "L13", title: "bit 3 켜짐 — 디스크립터 없음",
                    build: entry(sheetName) {
                        $0.flags = 0x0808
                        $0.localCRC = 0
                        $0.localCompressedSize = 0
                        $0.localUncompressedSize = 0
                    },
                    expect: .openFails(.dataDescriptorMismatch)),
        ArchiveCase(id: "L14", title: "bit 3 켜짐 — ZIP64 디스크립터(8B 크기)",
                    build: entry(sheetName) { $0 = $0.googleStyle(); $0.descriptor = .zip64 }, expect: .openFails(.zip64)),
        ArchiveCase(id: "L15", title: "겹치는 엔트리 — 앞 엔트리 범위가 뒤 엔트리 로컬 헤더를 덮음",
                    build: entry("xl/workbook.xml") { $0.sizeExtension = 30 }, expect: .openFails(.overlappingEntries)),
        ArchiveCase(id: "L16", title: "다른 이름이 같은 로컬 헤더를 가리킴",
                    build: entry("xl/styles.xml") { $0.centralOffset = 0 }, expect: .openFails(.localHeaderMismatch(.name))),
        ArchiveCase(id: "L17", title: "엔트리가 중앙 디렉터리를 침범",
                    build: entry("xl/styles.xml") { $0.sizeExtension = 10_000 }, expect: .openFails(.entryOutOfBounds)),
        ArchiveCase(id: "L18", title: "엔트리 사이 틈에 숨은 로컬 헤더(중앙 디렉터리에 없음)",
                    build: workbook { spec in
                        var hidden = ZipEntrySpec("xl/worksheets/sheet1.xml", "<worksheet>숨은 시트</worksheet>")
                        hidden.listed = false
                        spec.entries.insert(hidden, at: 3)
                    },
                    expect: .openFails(.hiddenLocalHeader)),
        ArchiveCase(id: "L19", title: "맨 앞 숨은 엔트리(첫 등록 엔트리가 0에서 시작하지 않음)",
                    build: workbook { spec in
                        var hidden = ZipEntrySpec("[Content_Types].xml", "<Types/>")
                        hidden.listed = false
                        spec.entries.insert(hidden, at: 0)
                    },
                    expect: .openFails(.hiddenLocalHeader)),
        ArchiveCase(id: "L20", title: "중앙 디렉터리 앞 틈에 숨은 로컬 헤더",
                    build: workbook { spec in
                        var hidden: [UInt8] = []
                        hidden.le32(0x0403_4b50)
                        hidden += [UInt8](repeating: 0, count: 26)
                        spec.gapBeforeCentral = hidden
                    },
                    expect: .openFails(.hiddenLocalHeader)),
    ]

    // 해제(읽기) — 폭탄·출력 상한·손상·CRC·중첩
    static let inflation: [ArchiveCase] = [
        ArchiveCase(id: "R01", title: "압축비 폭탄(정직한 선언 4MB 0) — 해제 전에 거부",
                    build: entry(sheetName) { $0.content = zeros4MB }, expect: .readFails([sheet], .compressionRatioExceeded)),
        ArchiveCase(id: "R02", title: "선언을 속인 폭탄(선언 1,000B · 실제 4MB) — 1,001바이트에서 멈춤",
                    build: entry(sheetName) {
                        $0.content = zeros4MB
                        $0.centralUncompressedSize = 1_000
                        $0.localUncompressedSize = 1_000
                    },
                    expect: .readFails([sheet], .sizeMismatch)),
        ArchiveCase(id: "R03", title: "styles 파트 상한 cap+1(정직한 선언)",
                    build: entry("xl/styles.xml") { $0.content = ZipFixture.moderatelyCompressible(count: XLSXArchiveLimits.product.stylesBytes + 1) },
                    expect: .readFails([styles], .partTooLarge)),
        ArchiveCase(id: "R04", title: "거대 sharedStrings(8MB 초과, 압축비 100:1 아래)",
                    build: entry("xl/sharedStrings.xml") { $0.content = hugeSharedStrings() },
                    expect: .readFails([strings], .partTooLarge)),
        ArchiveCase(id: "R05", title: "해제 총량 상한 — 파트마다는 안이지만 합이 넘음",
                    limits: { var limits = XLSXArchiveLimits.product; limits.totalOutputBytes = 300; return limits }(),
                    build: workbook { spec in
                        spec.entries[ZipFixture.index(of: sheetName, in: spec.entries)].content = ZipFixture.moderatelyCompressible(count: 200)
                        spec.entries[ZipFixture.index(of: "xl/sharedStrings.xml", in: spec.entries)].content = ZipFixture.moderatelyCompressible(count: 200)
                    },
                    expect: .readFails([sheet, strings], .totalOutputExceeded)),
        ArchiveCase(id: "R06", title: "잘린 deflate 스트림",
                    build: entry(sheetName) { $0.compressed = Array(ZipFixture.deflate($0.content).dropLast(2)) },
                    expect: .readFails([sheet], .corruptCompressedData)),
        ArchiveCase(id: "R07", title: "deflate 끝 뒤에 남는 바이트(범위 안)",
                    build: entry(sheetName) { $0.compressed = ZipFixture.deflate($0.content) + [0, 0, 0, 0] },
                    expect: .readFails([sheet], .corruptCompressedData)),
        ArchiveCase(id: "R08", title: "deflate가 아닌 바이트(예약 블록 형식)",
                    build: entry(sheetName) { $0.compressed = [UInt8](repeating: 0xFF, count: 16) },
                    expect: .readFails([sheet], .corruptCompressedData)),
        ArchiveCase(id: "R09", title: "선언 원본 크기가 실제보다 큼",
                    build: entry(sheetName) {
                        $0.centralUncompressedSize = UInt32($0.content.count + 5)
                        $0.localUncompressedSize = UInt32($0.content.count + 5)
                    },
                    expect: .readFails([sheet], .sizeMismatch)),
        ArchiveCase(id: "R10", title: "CRC 거짓(로컬·중앙이 같은 거짓)",
                    build: entry(sheetName) { $0.centralCRC = 0x1234_5678; $0.localCRC = 0x1234_5678 },
                    expect: .readFails([sheet], .crcMismatch)),
        ArchiveCase(id: "R11", title: "stored 엔트리 CRC 거짓",
                    build: entry(sheetName) { $0.method = 0; $0.centralCRC = 0x1234_5678; $0.localCRC = 0x1234_5678 },
                    expect: .readFails([sheet], .crcMismatch)),
        ArchiveCase(id: "R12", title: "bit 3 켜짐 — CRC 거짓(중앙·디스크립터가 같은 거짓)",
                    build: entry(sheetName) { $0 = $0.googleStyle(); $0.centralCRC = 0x1234_5678; $0.descriptorCRC = 0x1234_5678 },
                    expect: .readFails([sheet], .crcMismatch)),
        ArchiveCase(id: "R13", title: "없는 파트(이름 완전 일치만)", build: { ZipFixture.workbook().bytes() },
                    expect: .readFails([Read("xl/worksheets/Sheet1.xml", .worksheet)], .partMissing)),
        ArchiveCase(id: "R14", title: "디렉터리 엔트리는 파트가 아니다",
                    build: workbook { $0.entries.append(ZipEntrySpec("xl/worksheets/", "", method: 0)) },
                    expect: .readFails([Read("xl/worksheets/", .worksheet)], .partMissing)),
        ArchiveCase(id: "R15", title: "중첩 ZIP — 시트 안의 ZIP은 풀지 않고 원문 바이트 그대로",
                    build: entry(sheetName) { $0.content = nestedArchive },
                    expect: .readsExactly(sheet, nestedArchive)),
        ArchiveCase(id: "R16", title: "읽지 않는 파트의 폭탄은 해제하지 않는다 — 필요한 파트만",
                    build: workbook { $0.entries.append(ZipEntrySpec(name: Array("xl/media/image1.bin".utf8), content: zeros4MB)) },
                    expect: .readsExactly(sheet, ZipFixture.workbookEntries()[4].content)),
    ]

    static let nestedArchive: [UInt8] = ZipFixture.workbook().bytes()

    /// `<si><t>항목N</t></si>` 반복 — 8MB를 넘고, 압축비는 100:1 아래(파일 상한 3MB 안)
    static func hugeSharedStrings() -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(XLSXArchiveLimits.product.sharedStringsBytes + 64)
        var index = 0
        while bytes.count <= XLSXArchiveLimits.product.sharedStringsBytes {
            bytes += Array("<si><t>항목\(index)</t></si>".utf8)
            index += 1
        }
        return bytes
    }
}

// MARK: - 시험

@Suite("외부 채움글 1-e ① — 적대 아카이브 fixture (AC-30 컨테이너 층)")
struct XLSXArchiveAdversarialTests {

    @Test("★ fixture ≥ 40건, id 중복 없음")
    func tableSize() {
        #expect(ArchiveCase.all.count >= 40)
        #expect(Set(ArchiveCase.all.map(\.id)).count == ArchiveCase.all.count)
    }

    @Test("★ 적대 아카이브는 전부 안전하게 거부되거나 제한된다", arguments: ArchiveCase.all)
    func adversarial(_ fixture: ArchiveCase) throws {
        let data = Data(fixture.build())
        switch fixture.expect {
        case .openFails(let failure):
            #expect(throws: failure) { _ = try XLSXArchive.open(data, limits: fixture.limits) }
        case .readFails(let reads, let failure):
            var archive = try XLSXArchive.open(data, limits: fixture.limits)
            for read in reads.dropLast() {
                _ = try archive.read(read.name, as: read.kind)
            }
            let last = try #require(reads.last)
            #expect(throws: failure) { _ = try archive.read(last.name, as: last.kind) }
        case .readsExactly(let read, let expected):
            var archive = try XLSXArchive.open(data, limits: fixture.limits)
            #expect(try archive.read(read.name, as: read.kind) == Data(expected))
        }
    }

    @Test("★ 거부 이유에 파일 내용·엔트리 이름이 실리지 않는다(AC-34)")
    func failuresCarryNoContent() {
        let marker = "비밀표식SECRET"
        let probes: [[UInt8]] = [
            ZipFixture.workbook { $0.append(ZipEntrySpec("../\(marker).xml", marker)) }.bytes(),
            ZipFixture.workbook { $0.append(ZipEntrySpec("xl/\(marker).xml", marker)); $0.append(ZipEntrySpec("xl/\(marker).xml", marker)) }.bytes(),
            ZipFixture.workbook { entries in
                entries[0].localName = Array("[Content_Types].xmL".utf8)
                entries.append(ZipEntrySpec("xl/\(marker).xml", marker))
            }.bytes(),
        ]
        for probe in probes {
            do {
                _ = try XLSXArchive.open(Data(probe))
                Issue.record("거부돼야 한다")
            } catch {
                #expect(!String(reflecting: error).contains(marker))
                #expect(!String(reflecting: error).contains("SECRET"))
            }
        }
    }
}
