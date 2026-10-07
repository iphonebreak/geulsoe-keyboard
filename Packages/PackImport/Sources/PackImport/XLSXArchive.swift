import Foundation
import TadakDomain

/// xlsx 컨테이너(ZIP)를 **메모리에서** 연다 — 외부 채움글 1-e ①(PDR `external-snippet-packs.md` 6-5·6-5a, AC-30·33·34).
///
/// - **권위는 중앙 디렉터리다.** 파트는 중앙 디렉터리에서 **이름 완전 일치**(바이트)로 찾고, 크기·CRC·방식·위치도 중앙 디렉터리 값을 쓴다.
///   로컬 헤더·데이터 디스크립터는 그 값과 **모순되지 않는지만** 본다 — 같은 파일을 독자마다 다르게 읽게 만드는 이중 해석을 막는다.
/// - **열 때는 풀지 않는다.** `open`은 구조(EOCD·중앙 디렉터리·로컬 헤더·엔트리 범위)만 전부 검사하고, 해제는 `read`가 고른 파트 하나씩 한다.
///   읽지 않는 파트(그림·테마 등)는 끝까지 풀지 않는다.
/// - **파일 시스템에 풀지 않는다**(AC-33) — 이 타입은 URL·파일 핸들을 모른다. 결과는 부르는 쪽 메모리의 `Data`뿐이다.
/// - **상한**: 파일 바이트 · 엔트리 수 · 이름 길이 · 파트별 출력 · 해제 총량 · 압축비(`XLSXArchiveLimits`). 선언 크기는 믿지 않는다 —
///   선언이 상한을 넘으면 풀기 전에 거부하고, 선언 안이라도 실제 출력이 선언 + 1바이트가 되는 순간 멈춘다(cap+1, AC-34).
/// - 실패는 **내용 없는 코드**다(`XLSXArchiveFailure`) — 파일 바이트·엔트리 이름·시트 이름을 담지 않는다(AC-34). 로그도 쓰지 않는다.
///
/// XML 해석(workbook·sharedStrings·styles·sheet)은 다음 단계(1-e ②)다. 이 타입은 어떤 이름이 필요한지 모른다 — 부르는 쪽이 고른다.
public struct XLSXArchive: Sendable {

    /// 읽을 파트의 종류 — 출력 상한이 종류마다 다르다(6-5)
    public enum PartKind: Equatable, Sendable {
        /// `[Content_Types].xml`
        case contentTypes
        /// `_rels/.rels`·`xl/_rels/workbook.xml.rels`
        case relationships
        /// `xl/workbook.xml`
        case workbook
        /// `xl/sharedStrings.xml`
        case sharedStrings
        /// `xl/styles.xml`
        case styles
        /// 고른 시트 하나(`xl/worksheets/*.xml`)
        case worksheet
    }

    struct Entry: Sendable {
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let dataStart: Int
        let isDirectory: Bool
    }

    private let bytes: [UInt8]
    /// 이름 **바이트** → 엔트리. 찾기는 바이트 완전 일치뿐이다(대소문자·정규화·`./` 해석 없음)
    private let entries: [[UInt8]: Entry]
    public let limits: XLSXArchiveLimits
    /// 지금까지 `read`가 풀어 낸 바이트 합 — 해제 총량 상한과 비교한다
    public private(set) var inflatedBytes = 0

    /// 모든 엔트리 이름(디렉터리 엔트리 포함) — 시험·진단용, 내용은 밖으로 내보내지 않는다
    var entryNames: Set<String> {
        Set(entries.keys.map { String(decoding: $0, as: UTF8.self) })
    }

    /// 그 이름의 파트(디렉터리가 아닌 엔트리)가 있나 — 이름 완전 일치
    public func contains(_ name: String) -> Bool {
        guard let entry = entries[Array(name.utf8)] else { return false }
        return !entry.isDirectory
    }

    /// 파트 하나를 메모리에 푼다 — 상한·크기·CRC를 모두 통과해야 돌려준다
    public mutating func read(_ name: String, as kind: PartKind) throws(XLSXArchiveFailure) -> Data {
        guard let entry = entries[Array(name.utf8)], !entry.isDirectory else { throw .partMissing }
        // 선언 크기로 먼저 거른다 — 정직한 폭탄은 풀지도 않는다
        let declared = entry.uncompressedSize
        guard declared <= limits.outputLimit(for: kind) else { throw .partTooLarge }
        guard declared <= limits.totalOutputBytes - inflatedBytes else { throw .totalOutputExceeded }
        guard declared <= limits.compressionRatio * entry.compressedSize else { throw .compressionRatioExceeded }

        let payload = bytes[entry.dataStart..<(entry.dataStart + entry.compressedSize)]
        let output: [UInt8]
        if entry.method == Self.stored {
            output = Array(payload)
        } else {
            // 선언을 속인 폭탄 — 선언 + 1바이트에서 멈춘다(선언은 위에서 모든 상한 안으로 걸렀다)
            switch XLSXInflater.inflate(payload, limit: declared) {
            case .success(let inflated): output = inflated
            case .failure(.exceedsLimit): throw .sizeMismatch
            case .failure(.corrupt): throw .corruptCompressedData
            }
        }
        guard output.count == declared else { throw .sizeMismatch }
        guard CRC32.checksum(output) == entry.crc else { throw .crcMismatch }
        inflatedBytes += output.count
        return Data(output)
    }
}

// MARK: - 열기(구조 검사)

extension XLSXArchive {

    static let stored: UInt16 = 0
    static let deflated: UInt16 = 8

    private static let localSignature: UInt32 = 0x0403_4b50
    private static let centralSignature: UInt32 = 0x0201_4b50
    private static let endSignature: UInt32 = 0x0605_4b50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
    private static let descriptorSignature: UInt32 = 0x0807_4b50
    private static let localSignatureBytes: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
    private static let centralSignatureBytes: [UInt8] = [0x50, 0x4B, 0x01, 0x02]
    private static let endSignatureBytes: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    /// OLE2 복합 문서 — 비밀번호 걸린 엑셀(암호화 컨테이너)·옛 `.xls`(6-5 「비 ZIP」)
    private static let compoundFileMagic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0]

    /// 받는 플래그 — bit 1·2(deflate 수준 힌트, 엑셀 0x0006) · bit 3(데이터 디스크립터, 구글 0x0808) · bit 11(UTF-8 이름)
    private static let allowedFlags: UInt16 = 0x0002 | 0x0004 | 0x0008 | 0x0800
    /// 암호화 — bit 0(암호화) · bit 6(강한 암호화) · bit 13(중앙 디렉터리 암호화)
    private static let encryptionFlags: UInt16 = 0x0001 | 0x0040 | 0x2000
    private static let dataDescriptorFlag: UInt16 = 0x0008
    private static let utf8NameFlag: UInt16 = 0x0800

    private static let endRecordBytes = 22
    private static let maxCommentBytes = 0xFFFF

    private struct CentralRecord {
        let name: [UInt8]
        let flags: UInt16
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// 구조를 전부 검사하고 연다 — 아무 파트도 풀지 않는다
    public static func open(_ data: Data, limits: XLSXArchiveLimits = .product) throws(XLSXArchiveFailure) -> XLSXArchive {
        guard data.count <= limits.fileBytes else { throw .fileTooLarge }
        let bytes = [UInt8](data)
        if bytes.starts(with: compoundFileMagic) { throw .legacyOrProtectedWorkbook }
        guard bytes.count >= endRecordBytes,
              bytes.starts(with: localSignatureBytes) || bytes.starts(with: endSignatureBytes) else { throw .notZip }

        let end = try findEndRecord(bytes)
        if end >= 20, bytes.le32(end - 20) == zip64LocatorSignature { throw .zip64 }
        let disk = bytes.le16(end + 4)
        let centralDisk = bytes.le16(end + 6)
        let entriesOnDisk = bytes.le16(end + 8)
        let entryCount = bytes.le16(end + 10)
        let centralSize = bytes.le32(end + 12)
        let centralOffset = bytes.le32(end + 16)
        if [disk, centralDisk, entriesOnDisk, entryCount].contains(0xFFFF) || centralSize == 0xFFFF_FFFF || centralOffset == 0xFFFF_FFFF {
            throw .zip64
        }
        guard disk == 0, centralDisk == 0, entriesOnDisk == entryCount else { throw .multiDisk }
        guard entryCount > 0 else { throw .noEntries }
        // `PK\5\6` 시작은 빈 아카이브에만 허용했다 — 엔트리가 있으면 첫 바이트는 로컬 헤더여야 한다(앞에서 읽는 독자는 빈 아카이브로 본다)
        guard bytes.starts(with: localSignatureBytes) else { throw .notZip }
        guard Int(entryCount) <= limits.entries else { throw .tooManyEntries }
        let centralStart = Int(centralOffset)
        guard centralStart + Int(centralSize) == end else { throw .centralDirectoryMismatch }

        let records = try readCentralDirectory(bytes, from: centralStart, to: end, count: Int(entryCount), limits: limits)

        var entries: [[UInt8]: Entry] = [:]
        var ranges: [Range<Int>] = []
        for record in records {
            let (entry, range) = try checkLocalHeader(bytes, record: record, centralStart: centralStart)
            entries[record.name] = entry
            ranges.append(range)
        }
        try checkLayout(bytes, ranges: ranges, centralStart: centralStart)
        return XLSXArchive(bytes: bytes, entries: entries, limits: limits)
    }

    /// 파일 끝에서 EOCD를 찾는다 — 주석 길이가 정확히 파일 끝까지 맞는 것이 **하나**여야 하고, 그 뒤(주석 안)에 서명이 또 있으면 안 된다
    /// (뒤에서부터 서명만 찾는 독자는 주석 안 가짜를 잡는다 — 이중 해석)
    private static func findEndRecord(_ bytes: [UInt8]) throws(XLSXArchiveFailure) -> Int {
        let lowest = max(0, bytes.count - endRecordBytes - maxCommentBytes)
        var candidates: [Int] = []
        var position = bytes.count - endRecordBytes
        while position >= lowest {
            if bytes.le32(position) == endSignature, position + endRecordBytes + Int(bytes.le16(position + 20)) == bytes.count {
                candidates.append(position)
            }
            position -= 1
        }
        guard let end = candidates.first else { throw .missingEndRecord }
        guard candidates.count == 1 else { throw .multipleEndRecords }
        if contains(endSignatureBytes, in: bytes[(end + 4)...]) { throw .multipleEndRecords }
        return end
    }

    private static func readCentralDirectory(_ bytes: [UInt8], from start: Int, to end: Int, count: Int,
                                             limits: XLSXArchiveLimits) throws(XLSXArchiveFailure) -> [CentralRecord] {
        var records: [CentralRecord] = []
        // 대소문자(ASCII)를 접은 이름 — OPC 파트 이름은 대소문자를 가리지 않아, 다른 독자는 `XL/Workbook.xml`을 같은 파트로 본다.
        // `String` 집합이라 정규화(NFC/NFD)만 다른 이름도 같은 것으로 잡는다
        var foldedNames = Set<String>()
        var cursor = start
        for _ in 0..<count {
            guard cursor + 46 <= end, bytes.le32(cursor) == centralSignature else { throw .centralDirectoryMismatch }
            let flags = bytes.le16(cursor + 8)
            let method = bytes.le16(cursor + 10)
            let crc = bytes.le32(cursor + 16)
            let compressedSize = bytes.le32(cursor + 20)
            let uncompressedSize = bytes.le32(cursor + 24)
            let nameLength = Int(bytes.le16(cursor + 28))
            let extraLength = Int(bytes.le16(cursor + 30))
            let commentLength = Int(bytes.le16(cursor + 32))
            let diskStart = bytes.le16(cursor + 34)
            let localOffset = bytes.le32(cursor + 42)
            let nameStart = cursor + 46
            let extraStart = nameStart + nameLength
            let recordEnd = extraStart + extraLength + commentLength
            guard recordEnd <= end else { throw .centralDirectoryMismatch }

            try checkEncryption(flags: flags, method: method)
            try checkExtraField(bytes[extraStart..<(extraStart + extraLength)])
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localOffset == 0xFFFF_FFFF || diskStart == 0xFFFF {
                throw .zip64
            }
            guard diskStart == 0 else { throw .multiDisk }
            guard method == stored || method == deflated else { throw .unsupportedCompression }
            guard flags & ~allowedFlags == 0 else { throw .unsupportedFlags }
            if method == stored, compressedSize != uncompressedSize { throw .storedSizeMismatch }

            let name = Array(bytes[nameStart..<extraStart])
            try checkName(name, flags: flags, limits: limits)
            let folded = String(decoding: name.map { (0x41...0x5A).contains($0) ? $0 | 0x20 : $0 }, as: UTF8.self)
            guard foldedNames.insert(folded).inserted else { throw .duplicateEntryName }

            records.append(CentralRecord(name: name, flags: flags, method: method, crc: crc, compressedSize: Int(compressedSize),
                                         uncompressedSize: Int(uncompressedSize), localHeaderOffset: Int(localOffset)))
            cursor = recordEnd
        }
        // 선언한 개수를 읽고 나서 정확히 EOCD에 닿아야 한다 — 남거나 모자라면 독자마다 엔트리 목록이 달라진다
        guard cursor == end else { throw .centralDirectoryMismatch }
        return records
    }

    private static func checkEncryption(flags: UInt16, method: UInt16) throws(XLSXArchiveFailure) {
        // 방식 99 = WinZip AES
        if flags & encryptionFlags != 0 || method == 99 { throw .encrypted }
    }

    /// 확장 필드(머리 2B + 길이 2B 반복)를 끝까지 정확히 읽는다 — ZIP64(0x0001)·암호화(0x0017 강한 암호화, 0x9901 AES)는 거부
    private static func checkExtraField(_ field: ArraySlice<UInt8>) throws(XLSXArchiveFailure) {
        var cursor = field.startIndex
        while cursor < field.endIndex {
            guard field.endIndex - cursor >= 4 else { throw .malformedExtraField }
            let header = UInt16(field[cursor]) | UInt16(field[cursor + 1]) << 8
            let size = Int(UInt16(field[cursor + 2]) | UInt16(field[cursor + 3]) << 8)
            guard cursor + 4 + size <= field.endIndex else { throw .malformedExtraField }
            switch header {
            case 0x0001: throw .zip64
            case 0x0017, 0x9901: throw .encrypted
            default: break
            }
            cursor += 4 + size
        }
    }

    /// 이름 — 길이 · 제어 문자 · 인코딩(UTF-8 플래그 없는 비ASCII는 CP437일 수 있어 모호) · 경로 조작(절대·드라이브·`\`·`..`·`.`·빈 조각).
    /// 우리는 파일로 풀지 않으므로 경로 조작이 직접 위험은 아니지만, 이런 이름이 든 xlsx는 정상 생성기가 만들지 않는다(구조 의심, 6-5)
    private static func checkName(_ name: [UInt8], flags: UInt16, limits: XLSXArchiveLimits) throws(XLSXArchiveFailure) {
        guard !name.isEmpty else { throw .invalidEntryName }
        guard name.count <= limits.nameBytes else { throw .entryNameTooLong }
        if name.contains(where: { $0 < 0x20 || $0 == 0x7F }) { throw .invalidEntryName }
        if name.contains(where: { $0 >= 0x80 }) {
            guard flags & utf8NameFlag != 0, Array(String(decoding: name, as: UTF8.self).utf8) == name else { throw .invalidEntryName }
        }
        if name.contains(0x5C) || name[0] == 0x2F { throw .unsafeEntryPath }
        if name.count >= 2, name[1] == 0x3A, (0x41...0x5A).contains(name[0] & ~0x20) { throw .unsafeEntryPath }
        let components = name.split(separator: 0x2F, omittingEmptySubsequences: false)
        for (index, component) in components.enumerated() {
            // 디렉터리 엔트리의 끝 `/`만 빈 조각을 허용한다
            if component.isEmpty, index == components.count - 1 { continue }
            if component.isEmpty || component.elementsEqual([0x2E]) || component.elementsEqual([0x2E, 0x2E]) { throw .unsafeEntryPath }
        }
    }

    /// 로컬 헤더가 중앙 디렉터리와 모순되지 않는지(6-5a 표) — 엔트리와 그 바이트 범위(로컬 헤더 시작 ~ 디스크립터 끝)를 돌려준다
    private static func checkLocalHeader(_ bytes: [UInt8], record: CentralRecord,
                                         centralStart: Int) throws(XLSXArchiveFailure) -> (Entry, Range<Int>) {
        let offset = record.localHeaderOffset
        guard offset + 30 <= centralStart else { throw .entryOutOfBounds }
        guard bytes.le32(offset) == localSignature else { throw .localHeaderMismatch(.signature) }
        let flags = bytes.le16(offset + 6)
        let method = bytes.le16(offset + 8)
        let crc = bytes.le32(offset + 14)
        let compressedSize = bytes.le32(offset + 18)
        let uncompressedSize = bytes.le32(offset + 22)
        let nameLength = Int(bytes.le16(offset + 26))
        let extraLength = Int(bytes.le16(offset + 28))
        let nameStart = offset + 30
        let dataStart = nameStart + nameLength + extraLength
        guard dataStart <= centralStart else { throw .entryOutOfBounds }
        guard nameLength == record.name.count, bytes[nameStart..<(nameStart + nameLength)].elementsEqual(record.name) else {
            throw .localHeaderMismatch(.name)
        }
        guard flags == record.flags else { throw .localHeaderMismatch(.flags) }
        guard method == record.method else { throw .localHeaderMismatch(.method) }
        // 로컬 확장 필드는 중앙과 달라도 된다(엑셀은 로컬에만 채움 필드 0xA220을 붙인다 — P-10 실측). 형식과 ZIP64·암호화만 본다
        try checkExtraField(bytes[(nameStart + nameLength)..<dataStart])

        // bit 3 꺼짐(엑셀): 중앙과 같아야 한다. 켜짐(구글): 0이거나 중앙과 같아야 한다
        let deferred = record.flags & dataDescriptorFlag != 0
        func agrees(_ local: UInt32, _ central: UInt32) -> Bool { local == central || (deferred && local == 0) }
        guard agrees(crc, record.crc) else { throw .localHeaderMismatch(.crc) }
        guard agrees(compressedSize, UInt32(record.compressedSize)) else { throw .localHeaderMismatch(.compressedSize) }
        guard agrees(uncompressedSize, UInt32(record.uncompressedSize)) else { throw .localHeaderMismatch(.uncompressedSize) }

        let dataEnd = dataStart + record.compressedSize
        guard dataEnd <= centralStart else { throw .entryOutOfBounds }
        let entryEnd = try deferred ? descriptorEnd(bytes, at: dataEnd, centralStart: centralStart, record: record) : dataEnd
        let entry = Entry(method: record.method, crc: record.crc, compressedSize: record.compressedSize,
                          uncompressedSize: record.uncompressedSize, dataStart: dataStart, isDirectory: record.name.last == 0x2F)
        return (entry, offset..<entryEnd)
    }

    /// 데이터 디스크립터(압축 데이터 바로 뒤) — 서명 있는 16B 또는 없는 12B, CRC·크기가 중앙 디렉터리와 같아야 한다. 8B 크기(ZIP64)는 거부
    private static func descriptorEnd(_ bytes: [UInt8], at position: Int, centralStart: Int,
                                      record: CentralRecord) throws(XLSXArchiveFailure) -> Int {
        let crc = record.crc
        let compressed = UInt32(record.compressedSize)
        let size = UInt32(record.uncompressedSize)
        func fits(_ length: Int) -> Bool { position + length <= centralStart }
        if fits(16), bytes.le32(position) == descriptorSignature, bytes.le32(position + 4) == crc,
           bytes.le32(position + 8) == compressed, bytes.le32(position + 12) == size {
            return position + 16
        }
        if fits(12), bytes.le32(position) == crc, bytes.le32(position + 4) == compressed, bytes.le32(position + 8) == size {
            return position + 12
        }
        if fits(24), bytes.le32(position) == descriptorSignature, bytes.le32(position + 4) == crc,
           bytes.le64(position + 8) == UInt64(compressed), bytes.le64(position + 16) == UInt64(size) {
            throw .zip64
        }
        if fits(20), bytes.le32(position) == crc, bytes.le64(position + 4) == UInt64(compressed), bytes.le64(position + 12) == UInt64(size) {
            throw .zip64
        }
        throw .dataDescriptorMismatch
    }

    /// 엔트리 범위끼리 겹치지 않고, 범위 밖 틈(맨 앞·사이·중앙 디렉터리 앞)에 헤더 서명이 숨어 있지 않다 —
    /// 로컬 헤더를 앞에서부터 읽는(스트리밍) 독자는 중앙 디렉터리에 없는 엔트리를 볼 수 있다
    private static func checkLayout(_ bytes: [UInt8], ranges: [Range<Int>], centralStart: Int) throws(XLSXArchiveFailure) {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var cursor = 0
        for range in sorted {
            guard range.lowerBound >= cursor else { throw .overlappingEntries }
            try checkGap(bytes[cursor..<range.lowerBound])
            cursor = range.upperBound
        }
        try checkGap(bytes[cursor..<centralStart])
    }

    private static func checkGap(_ gap: ArraySlice<UInt8>) throws(XLSXArchiveFailure) {
        if contains(localSignatureBytes, in: gap) || contains(centralSignatureBytes, in: gap) { throw .hiddenLocalHeader }
    }

    private static func contains(_ needle: [UInt8], in haystack: ArraySlice<UInt8>) -> Bool {
        guard haystack.count >= needle.count else { return false }
        var index = haystack.startIndex
        while index + needle.count <= haystack.endIndex {
            if haystack[index] == needle[0], haystack[index..<(index + needle.count)].elementsEqual(needle) { return true }
            index += 1
        }
        return false
    }
}

// MARK: - 상한

/// xlsx 컨테이너 상한 — PDR 6-5 **후보값**(R2와 같이 실측 뒤 확정). 앱 전용(키보드는 xlsx를 모른다)이라 `PackLimits`(TadakDomain)가 아니라 여기 둔다
public struct XLSXArchiveLimits: Equatable, Sendable {
    /// 파일 바이트(압축) — CSV와 같은 3MB(`PackLimits.fileBytes`)
    public var fileBytes: Int
    /// 엔트리 수 ≤ 200
    public var entries: Int
    /// 엔트리 이름 바이트 — 정상 xlsx는 40B 안팎 `[판단]`
    public var nameBytes: Int
    /// 파트 압축비(원본 ÷ 압축) 상한 — 100:1. P-10 실물 최대 22.2:1
    public var compressionRatio: Int
    /// 해제 총량(이 아카이브에서 `read`한 합) — 20MB
    public var totalOutputBytes: Int
    /// `[Content_Types].xml` — 6-5에 값이 없어 1MB `[판단]`(실물 1.3KB)
    public var contentTypesBytes: Int
    /// `.rels` 파트 — 1MB `[판단]`(실물 0.8KB)
    public var relationshipsBytes: Int
    /// `xl/workbook.xml` — 1MB `[판단]`(실물 2.4KB)
    public var workbookBytes: Int
    /// `xl/sharedStrings.xml` — 8MB
    public var sharedStringsBytes: Int
    /// `xl/styles.xml` — 1MB
    public var stylesBytes: Int
    /// 시트 하나 — 8MB
    public var worksheetBytes: Int

    public init(fileBytes: Int, entries: Int, nameBytes: Int, compressionRatio: Int, totalOutputBytes: Int,
                contentTypesBytes: Int, relationshipsBytes: Int, workbookBytes: Int,
                sharedStringsBytes: Int, stylesBytes: Int, worksheetBytes: Int) {
        self.fileBytes = fileBytes
        self.entries = entries
        self.nameBytes = nameBytes
        self.compressionRatio = compressionRatio
        self.totalOutputBytes = totalOutputBytes
        self.contentTypesBytes = contentTypesBytes
        self.relationshipsBytes = relationshipsBytes
        self.workbookBytes = workbookBytes
        self.sharedStringsBytes = sharedStringsBytes
        self.stylesBytes = stylesBytes
        self.worksheetBytes = worksheetBytes
    }

    public static let product = XLSXArchiveLimits(
        fileBytes: PackLimits.fileBytes, entries: 200, nameBytes: 255, compressionRatio: 100, totalOutputBytes: 20_000_000,
        contentTypesBytes: 1_000_000, relationshipsBytes: 1_000_000, workbookBytes: 1_000_000,
        sharedStringsBytes: 8_000_000, stylesBytes: 1_000_000, worksheetBytes: 8_000_000
    )

    public func outputLimit(for kind: XLSXArchive.PartKind) -> Int {
        switch kind {
        case .contentTypes: contentTypesBytes
        case .relationships: relationshipsBytes
        case .workbook: workbookBytes
        case .sharedStrings: sharedStringsBytes
        case .styles: stylesBytes
        case .worksheet: worksheetBytes
        }
    }
}

// MARK: - 실패

/// xlsx 컨테이너 거부 사유 — **내용 없는 열거형**(AC-34): 파일 바이트·엔트리 이름·시트 이름·위치 숫자를 담지 않는다.
/// 사용자에게 보이는 문구는 가져오기 화면(1-e ③)이 이 코드에서 만든다
public enum XLSXArchiveFailure: Error, Equatable, Sendable {

    /// 로컬 헤더가 중앙 디렉터리와 다르게 말한 필드(6-5a)
    public enum LocalHeaderField: Equatable, Sendable {
        /// 중앙 디렉터리가 가리킨 자리에 로컬 헤더 서명이 없다(오프셋 불일치)
        case signature
        case name
        case flags
        case method
        case crc
        case compressedSize
        case uncompressedSize
    }

    /// 파일 바이트가 상한을 넘는다
    case fileTooLarge
    /// ZIP이 아니다(로컬 헤더 서명으로 시작하지 않음 — 다른 형식·앞에 덧붙인 바이트)
    case notZip
    /// OLE2 복합 문서 — 비밀번호 걸린 엑셀이거나 옛 `.xls`
    case legacyOrProtectedWorkbook
    /// 파일 끝까지 정확히 맞는 EOCD가 없다(잘림·끝 뒤 쓰레기)
    case missingEndRecord
    /// EOCD가 둘 이상이거나 주석 안에 EOCD 서명이 있다
    case multipleEndRecords
    /// ZIP64(로케이터·0xFFFF/0xFFFFFFFF 표시·확장 필드 0x0001·8B 디스크립터)
    case zip64
    /// 다중 디스크(분할 아카이브)
    case multiDisk
    /// 엔트리가 없다
    case noEntries
    /// 엔트리 수가 상한을 넘는다
    case tooManyEntries
    /// 중앙 디렉터리의 위치·크기·개수·레코드 서명이 EOCD와 맞지 않는다
    case centralDirectoryMismatch
    /// 엔트리 이름이 길이 상한을 넘는다
    case entryNameTooLong
    /// 엔트리 이름이 비었거나 제어 문자·잘못된 인코딩을 담았다
    case invalidEntryName
    /// 엔트리 이름이 절대 경로·드라이브·`\`·`..`·`.`·빈 경로 조각을 담았다
    case unsafeEntryPath
    /// 같은 이름(대소문자·정규화만 다른 것 포함)이 두 번
    case duplicateEntryName
    /// 암호화 엔트리
    case encrypted
    /// stored·deflate가 아닌 압축 방식
    case unsupportedCompression
    /// 모르는 플래그 비트
    case unsupportedFlags
    /// 확장 필드 구조가 깨졌다
    case malformedExtraField
    /// stored인데 압축 크기 ≠ 원본 크기
    case storedSizeMismatch
    /// 엔트리가 파일 밖이나 중앙 디렉터리 안을 가리킨다
    case entryOutOfBounds
    /// 로컬 헤더가 중앙 디렉터리와 모순된다
    case localHeaderMismatch(LocalHeaderField)
    /// 데이터 디스크립터가 없거나 중앙 디렉터리와 다르다
    case dataDescriptorMismatch
    /// 엔트리 범위가 서로 겹친다
    case overlappingEntries
    /// 엔트리 범위 밖에 숨은 헤더 서명이 있다
    case hiddenLocalHeader
    /// 찾는 파트가 없다(이름 완전 일치)
    case partMissing
    /// 파트 출력이 그 종류의 상한을 넘는다
    case partTooLarge
    /// 해제 총량이 상한을 넘는다
    case totalOutputExceeded
    /// 압축비가 상한을 넘는다(폭탄)
    case compressionRatioExceeded
    /// deflate가 손상됐다(형식 오류·잘림·끝 뒤 남는 바이트)
    case corruptCompressedData
    /// 실제 출력 크기 ≠ 선언 크기
    case sizeMismatch
    /// 해제 결과 CRC ≠ 중앙 디렉터리 CRC
    case crcMismatch
}

// MARK: - 바이트 읽기 (작은 끝 — 부르는 쪽이 범위를 먼저 확인한다)

private extension Array where Element == UInt8 {
    func le16(_ index: Int) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }

    func le32(_ index: Int) -> UInt32 {
        UInt32(self[index]) | UInt32(self[index + 1]) << 8 | UInt32(self[index + 2]) << 16 | UInt32(self[index + 3]) << 24
    }

    func le64(_ index: Int) -> UInt64 {
        UInt64(le32(index)) | UInt64(le32(index + 4)) << 32
    }
}
