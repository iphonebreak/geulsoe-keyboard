import Foundation
import TadakDomain

/// 번들 `bible.tdb`(개역한글 전권, 31,102절)에서 절 본문을 조회한다.
///
/// 파일은 mmap(`.mappedIfSafe`)으로 열어 **조회만 할 때는 닿는 페이지만** 물리 메모리에 올라온다 —
/// 4.5MB 전체를 힙에 올리지 않기 위한 선택이다 (60MB 익스텐션 예산).
///
/// ## ★ 단, 검색을 켜면 전체가 올라온다 (2026-09-21 정정)
///
/// `makeSearcher()`가 만드는 `BibleByteScanner`는 init에서 **본문 블롭 전체를 훑어**
/// 바이트 빈도표를 만든다(최희소 앵커를 고르려면 필요하다). 그러면 4.4MB가 전부 페이지 인된다.
/// 예전 이 주석은 *"조회가 닿는 페이지만 올라온다"*고만 적어 **검색을 켠 경우에 거짓**이었다.
/// footprint는 clean file-backed라 안 오르지만(findings A-2) RSS는 오른다.
///
/// **그래서 스캐너를 저장 프로퍼티로 두지 않는다** — 검색을 쓰지 않는 사용자(기본값이 꺼짐이다)가
/// 그 비용을 내지 않게 하려는 것이다. 자세한 근거는 `makeSearcher()`.
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

extension BundledBibleRepository {

    /// 본문 검색기를 **그때 만든다** — 조회와 **같은 mmap**을 쓴다(새로 매핑하지 않는다).
    ///
    /// ## ★ 왜 저장 프로퍼티가 아닌가 (2026-09-21, 반론자1 A-6)
    ///
    /// 예전에는 `init`이 무조건 스캐너를 만들었고, 스캐너 `init`은 **본문 4.4MB를 훑어**
    /// 바이트 빈도표를 만든다. 성경 검색은 **기본값이 꺼짐**인데 조립 지점이 저장소를
    /// 저장 프로퍼티로 들고 있어서(성경 **채움글**이 쓴다) **모든 사용자가 키보드 등장마다**
    /// 그 비용을 냈다(반론자1 실측 3.2~7.5ms).
    ///
    /// 이제 **검색이 처음 필요할 때** 조립 지점의 lazy 캐스케이드가 이것을 부른다.
    /// 꺼 둔 사용자는 빈도표를 한 번도 만들지 않는다.
    ///
    /// **왜 `lazy var`가 아닌가:** 이 타입은 `struct`이고 `BibleVerseRepository: Sendable`이다.
    /// `lazy var`는 접근이 `mutating`이 되어 `Sendable` 계약과 `let` 저장이 깨진다.
    /// 잠금 달린 캐시 박스를 새로 만드는 것보다 **호출자가 한 번 만들어 들고 있는 쪽**이 단순하다.
    ///
    /// - Returns: 리소스가 없으면 모든 검색이 빈 배열인 검색기.
    public func makeSearcher() -> BundledBibleSearcher {
        BundledBibleSearcher(
            scanner: data.map {
                BibleByteScanner(
                    data: $0,
                    verseCount: verseCount,
                    indexStart: Self.headerSize,
                    entrySize: Self.entrySize,
                    textStart: textStart
                )
            }
        )
    }
}

/// 본문 검색기 — 바이트 빈도표를 들고 있는 값. 만드는 순간 본문 전체를 한 번 훑는다.
///
/// **본문 조회(`BibleVerseRepository.text`)는 이것을 쓰지 않는다** — 그쪽은 인덱스 이진 탐색이라
/// 빈도표가 필요 없다. 그래서 둘을 나눌 수 있었다.
public struct BundledBibleSearcher: BibleVerseSearching {

    let scanner: BibleByteScanner?

    public func search(_ query: String, limit: Int) -> [BibleVerseMatch] {
        scanner?.search(query, limit: limit) ?? []
    }

    public func searchIgnoringSpaces(_ query: String, limit: Int) -> [BibleVerseMatch] {
        scanner?.searchIgnoringSpaces(query, limit: limit) ?? []
    }
}
