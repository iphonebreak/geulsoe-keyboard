import Foundation
import TadakDomain

/// 번들 `words.tdw`(FrequencyWords ko_50k 파생, 데이터 CC-BY-SA-4.0)의 추천단어 사전.
///
/// 자모 키 바이트 순으로 정렬된 인덱스를 이진 탐색해 접두 일치 범위를 찾고,
/// 범위를 순회하며 빈도 상위 후보를 고른다. 파일은 mmap(`.mappedIfSafe`) — 조회가 닿는
/// 페이지만 물리 메모리에 올라온다. 포맷·생성: `tools/convert_words.py`
/// (헤더 16B + 엔트리 16B×N + 자모/단어 UTF-8 블롭).
public struct BundledWordDictionary: WordDictionary {

    private static let headerSize = 16
    private static let entrySize = 16
    /// 짧은 접두(예: 첫 음절)의 범위 폭주 방지 상한. mmap 순차 읽기라 이 상한까지도 μs 급.
    private static let scanLimit = 8000

    private let data: Data?
    private let wordCount: Int
    private let blobStart: Int

    /// - Parameter bundle: nil이면 패키지 리소스 번들 (테스트에서만 바꾼다)
    public init(bundle: Bundle? = nil) {
        self.init(url: (bundle ?? .module).url(forResource: "words", withExtension: "tdw"))
    }

    /// 테스트 주입용. 파일이 없거나 형식이 깨졌으면 모든 조회가 빈 배열인 빈 사전이 된다.
    init(url: URL?) {
        guard let url,
              let mapped = try? Data(contentsOf: url, options: .mappedIfSafe),
              mapped.count >= Self.headerSize,
              mapped.prefix(4).elementsEqual("TDWD".utf8)
        else {
            data = nil
            wordCount = 0
            blobStart = 0
            return
        }
        let version = mapped.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self))
        }
        let count = Int(mapped.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self))
        })
        let start = Int(mapped.withUnsafeBytes {
            UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 12, as: UInt32.self))
        })
        guard version == 1, count > 0,
              start == Self.headerSize + count * Self.entrySize,
              mapped.count >= start
        else {
            data = nil
            wordCount = 0
            blobStart = 0
            return
        }
        data = mapped
        wordCount = count
        blobStart = start
    }

    public func candidates(jamoPrefix: String, limit: Int) -> [WordCandidate] {
        guard let data, limit > 0, !jamoPrefix.isEmpty else { return [] }
        let prefix = Array(jamoPrefix.utf8)
        let count = wordCount
        let blobStart = blobStart
        let total = data.count

        return data.withUnsafeBytes { raw -> [WordCandidate] in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else { return [] }
            func u16(_ offset: Int) -> Int {
                Int(UInt16(base[offset]) | UInt16(base[offset + 1]) << 8)
            }
            func u32(_ offset: Int) -> Int {
                Int(UInt32(base[offset]) | UInt32(base[offset + 1]) << 8
                    | UInt32(base[offset + 2]) << 16 | UInt32(base[offset + 3]) << 24)
            }
            func jamo(_ index: Int) -> (start: Int, length: Int) {
                let entry = Self.headerSize + index * Self.entrySize
                return (blobStart + u32(entry), u16(entry + 4))
            }
            /// 엔트리의 자모 키가 접두보다 사전순으로 앞서는가 (lower bound 판정)
            func isLess(_ index: Int) -> Bool {
                let (start, length) = jamo(index)
                guard start + length <= total else { return false }
                var i = 0
                while i < length && i < prefix.count {
                    if base[start + i] != prefix[i] { return base[start + i] < prefix[i] }
                    i += 1
                }
                return length < prefix.count
            }
            func hasPrefix(_ index: Int) -> Bool {
                let (start, length) = jamo(index)
                guard length >= prefix.count, start + length <= total else { return false }
                for i in 0..<prefix.count where base[start + i] != prefix[i] { return false }
                return true
            }

            var low = 0
            var high = count
            while low < high {
                let mid = (low + high) / 2
                if isLess(mid) { low = mid + 1 } else { high = mid }
            }

            // 접두 일치 범위를 순회하며 빈도 상위 limit개 선별
            var best: [(frequency: Int, index: Int)] = []
            var index = low
            var scanned = 0
            while index < count, scanned < Self.scanLimit, hasPrefix(index) {
                let frequency = u32(Self.headerSize + index * Self.entrySize + 12)
                if best.count < limit {
                    best.append((frequency, index))
                    best.sort { $0.frequency > $1.frequency }
                } else if frequency > best[best.count - 1].frequency {
                    best[best.count - 1] = (frequency, index)
                    best.sort { $0.frequency > $1.frequency }
                }
                index += 1
                scanned += 1
            }

            return best.compactMap { item in
                let entry = Self.headerSize + item.index * Self.entrySize
                let start = blobStart + u32(entry + 8)
                let length = u16(entry + 6)
                guard start + length <= total,
                      let word = String(bytes: raw[start..<(start + length)], encoding: .utf8)
                else { return nil }
                return WordCandidate(word: word, frequency: UInt32(item.frequency))
            }
        }
    }
}

/// App Group을 통한 사용자 학습 단어 저장소.
///
/// **키보드가 쓰는 유일한 App Group 데이터다** — 쓰기는 Full Access가 있어야 지속되며,
/// 권한이 없으면 조용히 무시된다 (`UserDefaults`는 실패를 보고하지 않아 반환값이
/// 지속을 보장하지 못한다). 그 경우 학습은 세션 메모리에만 남는다. 읽기는 권한 무관.
public struct AppGroupUserWordRepository: UserWordRepository {

    private static let key = "keyboard.userWords"
    private let suiteName: String

    public init(suiteName: String = AppGroupSettingsRepository.appGroupIdentifier) {
        self.suiteName = suiteName
    }

    public func load() -> [String: Int] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: Self.key),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data)
        else {
            return [:]
        }
        return counts
    }

    @discardableResult
    public func save(_ counts: [String: Int]) -> Bool {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(counts) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }
}
