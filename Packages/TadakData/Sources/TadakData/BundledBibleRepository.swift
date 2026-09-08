import Foundation
import TadakDomain

/// 번들 `bible.tdb`(개역한글 전권, 31,102절)에서 절 본문을 조회한다.
///
/// 파일은 mmap(`.mappedIfSafe`)으로 열어 조회가 닿는 페이지만 물리 메모리에 올라온다 —
/// 4.5MB 전체를 힙에 올리지 않기 위한 선택이다 (60MB 익스텐션 예산).
/// 포맷 정의와 생성 스크립트: `tools/convert_bible.py`
/// (헤더 16B + 절당 12B 인덱스 + UTF-8 텍스트 블롭, 리틀엔디언, (책,장,절) 정렬).
public struct BundledBibleRepository: BibleVerseRepository {

    private static let headerSize = 16
    private static let entrySize = 12

    private let data: Data?
    private let verseCount: Int
    private let textStart: Int

    /// - Parameter bundle: nil이면 패키지 리소스 번들 (테스트에서만 바꾼다)
    public init(bundle: Bundle? = nil) {
        self.init(url: (bundle ?? .module).url(forResource: "bible", withExtension: "tdb"))
    }

    /// 테스트 주입용. 파일이 없거나 형식이 깨졌으면 모든 조회가 nil인 빈 저장소가 된다 —
    /// 키보드는 리소스 문제로 멈추면 안 된다.
    init(url: URL?) {
        guard let url,
              let mapped = try? Data(contentsOf: url, options: .mappedIfSafe),
              mapped.count >= Self.headerSize,
              mapped.prefix(4).elementsEqual("TDBB".utf8),
              Self.readUInt32(mapped, at: 4) == 1
        else {
            data = nil
            verseCount = 0
            textStart = 0
            return
        }
        let count = Int(Self.readUInt32(mapped, at: 8))
        let start = Int(Self.readUInt32(mapped, at: 12))
        guard count > 0,
              start == Self.headerSize + count * Self.entrySize,
              mapped.count >= start
        else {
            data = nil
            verseCount = 0
            textStart = 0
            return
        }
        data = mapped
        verseCount = count
        textStart = start
    }

    public func text(book: Int, chapter: Int, verse: Int) -> String? {
        guard let data, let key = Self.key(book, chapter, verse) else { return nil }

        var low = 0
        var high = verseCount - 1
        while low <= high {
            let mid = (low + high) / 2
            let entry = Self.headerSize + mid * Self.entrySize
            // 엔트리 값도 파일에서 읽은 비신뢰 데이터다 — 0이 들어 있으면(손상)
            // 크래시 대신 조회 실패로 처리한다 (키보드는 리소스 문제로 멈추면 안 된다)
            guard let entryKey = Self.key(
                Int(Self.readUInt16(data, at: entry)),
                Int(Self.readUInt16(data, at: entry + 2)),
                Int(Self.readUInt16(data, at: entry + 4))
            ) else { return nil }
            if entryKey == key {
                let length = Int(Self.readUInt16(data, at: entry + 6))
                let start = textStart + Int(Self.readUInt32(data, at: entry + 8))
                guard start + length <= data.count else { return nil }
                return String(data: data.subdata(in: start..<(start + length)), encoding: .utf8)
            }
            if entryKey < key {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return nil
    }

    /// (책,장,절) → 정렬 비교 가능한 단일 키. 포맷의 UInt16 범위를 벗어나면 nil.
    private static func key(_ book: Int, _ chapter: Int, _ verse: Int) -> UInt64? {
        guard (1...0xFFFF).contains(book),
              (1...0xFFFF).contains(chapter),
              (1...0xFFFF).contains(verse) else { return nil }
        return UInt64(book) << 32 | UInt64(chapter) << 16 | UInt64(verse)
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes {
            UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
        }
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
        }
    }
}
