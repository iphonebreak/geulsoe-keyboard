import Foundation
import Compression
@testable import PackImport

// 외부 채움글 1-e ① — 시험용 ZIP을 **테스트 안에서 바이트로** 짓는다(AC-30: 외부 도구 0).
// 기본값은 정상 엑셀 모양(플래그 0x0006, deflate, 로컬 헤더에 CRC·크기)이고, 적대 fixture는 필드 하나씩 덮어써 만든다.
// deflate는 OS `Compression`(raw DEFLATE)으로 압축한다 — 제품의 해제 경로와 같은 프레임워크지만 반대 방향이다.

/// 엔트리 하나 — 로컬 헤더·압축 데이터·(있으면) 데이터 디스크립터·중앙 디렉터리 레코드
struct ZipEntrySpec: Sendable {

    enum Descriptor: Sendable {
        case none
        /// `PK\7\8` + CRC·크기 4B×3 (구글 시트 모양)
        case signed
        /// 서명 없는 12B
        case unsigned
        /// `PK\7\8` + CRC + 크기 8B×2 (ZIP64 디스크립터)
        case zip64
    }

    var name: [UInt8]
    var content: [UInt8]
    var method: UInt16 = 8
    var flags: UInt16 = 0x0006
    var descriptor: Descriptor = .none
    /// 압축 바이트를 통째로 바꾼다(손상·잘린 스트림·중첩 ZIP) — CRC·원본 크기는 여전히 `content` 기준
    var compressed: [UInt8]?

    // 로컬 헤더 덮어쓰기 (nil = 정상값 — 디스크립터를 쓰면 CRC·크기는 0)
    var localName: [UInt8]?
    var localMethod: UInt16?
    var localFlags: UInt16?
    var localCRC: UInt32?
    var localCompressedSize: UInt32?
    var localUncompressedSize: UInt32?
    var localExtra: [UInt8] = []

    // 중앙 디렉터리 덮어쓰기 (nil = 정상값)
    var centralCRC: UInt32?
    var centralCompressedSize: UInt32?
    var centralUncompressedSize: UInt32?
    var centralOffset: UInt32?
    var centralDiskStart: UInt16 = 0
    var centralExtra: [UInt8] = []

    // 데이터 디스크립터 덮어쓰기
    var descriptorCRC: UInt32?
    var descriptorCompressedSize: UInt32?
    var descriptorUncompressedSize: UInt32?

    /// 압축 크기를 로컬·중앙 **양쪽에서 같이** 이만큼 늘려 말한다(바이트는 그대로) — 뒤 엔트리를 덮는 겹침 구성
    var sizeExtension: UInt32 = 0
    /// 이 엔트리의 로컬 헤더 앞에 끼울 바이트
    var gapBefore: [UInt8] = []
    /// false면 로컬 헤더만 쓰고 중앙 디렉터리에는 올리지 않는다(숨은 엔트리)
    var listed = true

    init(_ name: String, _ content: String, method: UInt16 = 8) {
        self.init(name: Array(name.utf8), content: Array(content.utf8), method: method)
    }

    init(name: [UInt8], content: [UInt8], method: UInt16 = 8) {
        self.name = name
        self.content = content
        self.method = method
    }

    /// 구글 시트 모양 — 플래그 0x0808(bit 3 + bit 11), 로컬 CRC·크기 0, 서명 있는 디스크립터
    func googleStyle() -> ZipEntrySpec {
        var copy = self
        copy.flags = 0x0808
        copy.descriptor = .signed
        return copy
    }
}

/// 아카이브 전체 — 엔트리들 + 중앙 디렉터리 + EOCD
struct ZipSpec: Sendable {
    var prefix: [UInt8] = []
    var entries: [ZipEntrySpec]
    var gapBeforeCentral: [UInt8] = []
    var zip64Locator = false
    var omitEndRecord = false
    var diskNumber: UInt16 = 0
    var centralDirectoryDisk: UInt16 = 0
    var entriesOnDisk: UInt16?
    var entriesTotal: UInt16?
    var centralDirectorySize: UInt32?
    var centralDirectoryOffset: UInt32?
    var comment: [UInt8] = []
    var commentLength: UInt16?
    /// EOCD(와 주석) 뒤에 붙는 바이트
    var trailing: [UInt8] = []

    init(_ entries: [ZipEntrySpec]) {
        self.entries = entries
    }

    func build() -> Data { Data(bytes()) }

    func bytes() -> [UInt8] {
        var out = prefix
        var central: [UInt8] = []
        var listedCount = 0
        for entry in entries {
            out += entry.gapBefore
            let offset = out.count
            let payload = entry.compressed ?? (entry.method == 8 ? ZipFixture.deflate(entry.content) : entry.content)
            let crc = CRC32.checksum(entry.content)
            let compressedSize = UInt32(payload.count) + entry.sizeExtension
            let size = UInt32(entry.content.count)
            let deferred = entry.descriptor != .none
            let localName = entry.localName ?? entry.name

            out.le32(0x0403_4b50)
            out.le16(20)
            out.le16(entry.localFlags ?? entry.flags)
            out.le16(entry.localMethod ?? entry.method)
            out.le16(0)       // 시각
            out.le16(0x0021)  // 1980-01-01
            out.le32(entry.localCRC ?? (deferred ? 0 : crc))
            out.le32(entry.localCompressedSize ?? (deferred ? 0 : compressedSize))
            out.le32(entry.localUncompressedSize ?? (deferred ? 0 : size))
            out.le16(UInt16(localName.count))
            out.le16(UInt16(entry.localExtra.count))
            out += localName
            out += entry.localExtra
            out += payload

            let descriptorCRC = entry.descriptorCRC ?? crc
            let descriptorCompressed = entry.descriptorCompressedSize ?? compressedSize
            let descriptorSize = entry.descriptorUncompressedSize ?? size
            switch entry.descriptor {
            case .none:
                break
            case .signed:
                out.le32(0x0807_4b50)
                out.le32(descriptorCRC)
                out.le32(descriptorCompressed)
                out.le32(descriptorSize)
            case .unsigned:
                out.le32(descriptorCRC)
                out.le32(descriptorCompressed)
                out.le32(descriptorSize)
            case .zip64:
                out.le32(0x0807_4b50)
                out.le32(descriptorCRC)
                out.le64(UInt64(descriptorCompressed))
                out.le64(UInt64(descriptorSize))
            }

            guard entry.listed else { continue }
            listedCount += 1
            central.le32(0x0201_4b50)
            central.le16(45)  // 만든 버전(엑셀과 같다)
            central.le16(20)
            central.le16(entry.flags)
            central.le16(entry.method)
            central.le16(0)
            central.le16(0x0021)
            central.le32(entry.centralCRC ?? crc)
            central.le32(entry.centralCompressedSize ?? compressedSize)
            central.le32(entry.centralUncompressedSize ?? size)
            central.le16(UInt16(entry.name.count))
            central.le16(UInt16(entry.centralExtra.count))
            central.le16(0)  // 주석
            central.le16(entry.centralDiskStart)
            central.le16(0)
            central.le32(0)
            central.le32(entry.centralOffset ?? UInt32(offset))
            central += entry.name
            central += entry.centralExtra
        }
        out += gapBeforeCentral
        let centralOffset = out.count
        out += central
        if zip64Locator {
            out.le32(0x0706_4b50)
            out.le32(0)
            out.le64(UInt64(out.count))
            out.le32(1)
        }
        if !omitEndRecord {
            out.le32(0x0605_4b50)
            out.le16(diskNumber)
            out.le16(centralDirectoryDisk)
            out.le16(entriesOnDisk ?? UInt16(listedCount))
            out.le16(entriesTotal ?? UInt16(listedCount))
            out.le32(centralDirectorySize ?? UInt32(central.count))
            out.le32(centralDirectoryOffset ?? UInt32(centralOffset))
            out.le16(commentLength ?? UInt16(comment.count))
            out += comment
        }
        out += trailing
        return out
    }
}

enum ZipFixture {

    /// raw DEFLATE(RFC 1951) — `COMPRESSION_ZLIB` 인코더. 빈 입력은 빈 고정 블록 `03 00`
    static func deflate(_ input: [UInt8]) -> [UInt8] {
        guard !input.isEmpty else { return [0x03, 0x00] }
        let capacity = input.count + input.count / 8 + 1_024
        var output = [UInt8](repeating: 0, count: capacity)
        let written = output.withUnsafeMutableBufferPointer { destination in
            input.withUnsafeBufferPointer { source in
                compression_encode_buffer(destination.baseAddress!, capacity, source.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        precondition(written > 0, "deflate 실패 — 시험 도구")
        return Array(output.prefix(written))
    }

    /// 6-5b의 파트를 갖춘 최소 워크북 — 컨테이너 층은 XML을 해석하지 않으므로 내용은 모양만 갖춘다
    static func workbookEntries() -> [ZipEntrySpec] {
        [
            ZipEntrySpec("[Content_Types].xml", #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/></Types>"#),
            ZipEntrySpec("_rels/.rels", #"<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Target="xl/workbook.xml"/></Relationships>"#),
            ZipEntrySpec("xl/workbook.xml", #"<?xml version="1.0" encoding="UTF-8"?><workbook><sheets><sheet name="문구" sheetId="1" r:id="rId1"/></sheets></workbook>"#),
            ZipEntrySpec("xl/_rels/workbook.xml.rels", #"<?xml version="1.0" encoding="UTF-8"?><Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>"#),
            ZipEntrySpec("xl/worksheets/sheet1.xml", #"<?xml version="1.0" encoding="UTF-8"?><worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c></row></sheetData></worksheet>"#),
            ZipEntrySpec("xl/sharedStrings.xml", #"<?xml version="1.0" encoding="UTF-8"?><sst count="1" uniqueCount="1"><si><t>회의시작</t></si></sst>"#),
            ZipEntrySpec("xl/styles.xml", #"<?xml version="1.0" encoding="UTF-8"?><styleSheet><cellXfs count="1"><xf numFmtId="0"/></cellXfs></styleSheet>"#),
        ]
    }

    /// 최소 워크북에서 이름이 같은 엔트리 하나만 고친다
    static func workbook(_ adjust: (inout [ZipEntrySpec]) -> Void = { _ in }) -> ZipSpec {
        var entries = workbookEntries()
        adjust(&entries)
        return ZipSpec(entries)
    }

    static func index(of name: String, in entries: [ZipEntrySpec]) -> Int {
        entries.firstIndex { $0.name == Array(name.utf8) }!
    }

    /// 압축이 적당히 되는(비율 100:1 아래) 결정적 바이트 — 출력 상한 시험용
    static func moderatelyCompressible(count: Int) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(count)
        var state: UInt32 = 0x1234_5678
        while bytes.count < count {
            state = state &* 1_664_525 &+ 1_013_904_223
            bytes.append(UInt8(0x61 + (state >> 24) % 16))
        }
        return bytes
    }

    /// ZIP64 확장 필드(머리 0x0001) — 크기 8B 둘
    static let zip64Extra: [UInt8] = [0x01, 0x00, 0x10, 0x00] + [UInt8](repeating: 0, count: 16)
    /// 엑셀이 로컬 헤더에만 붙이는 채움 필드(머리 0xA220) — 중앙 디렉터리와 달라도 정상이다(P-10 실측)
    static let excelPaddingExtra: [UInt8] = [0x20, 0xA2, 0x04, 0x00, 0x28, 0xA0, 0x00, 0x02]
}

extension Array where Element == UInt8 {
    mutating func le16(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8(value >> 8))
    }

    mutating func le32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    mutating func le64(_ value: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) { append(UInt8((value >> UInt64(shift)) & 0xFF)) }
    }

    /// 작은 끝(little-endian) 32비트 값 읽기 — 시험에서 EOCD 필드를 찾을 때
    func readLE32(at index: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(self[index + $1]) << UInt32(8 * $1) }
    }

    /// 마지막 EOCD 위치(시험이 직접 만든 정상 아카이브용)
    var endRecordOffset: Int {
        let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
        var index = count - 22
        while index >= 0 {
            if Array(self[index..<index + 4]) == signature { return index }
            index -= 1
        }
        preconditionFailure("EOCD 없음 — 시험 도구")
    }
}
