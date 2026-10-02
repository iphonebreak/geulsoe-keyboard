import Foundation
import TadakDomain

/// 번들 `emoji.tde`(Unicode CLDR 48.2 한국어 이모지 주석 파생, Unicode License v3 — `LICENSE-emoji.md`)의
/// 단어 → 이모지 역색인.
///
/// 키(한글 단어) UTF-8 바이트 순으로 정렬된 인덱스를 이진 탐색해 **정확 일치** 한 항목을 찾는다.
/// 파일은 mmap(`.mappedIfSafe`) — 조회가 닿는 페이지만 물리 메모리에 올라온다(전체 약 94KiB, PDR 2-7절).
/// 포맷·생성: `tools/convert_emoji.py` (헤더 16B + 엔트리 16B×N + 키/값 UTF-8 블롭, 값 구분자 U+001F).
/// 근거: `docs/design-reviews/emoji-data-import.md`
public struct BundledEmojiAnnotationIndex: EmojiAnnotationIndex {

    private static let headerSize = 16
    private static let entrySize = 16
    private static let separator = UInt8(0x1F)

    private let data: Data?
    private let keyCount: Int
    private let blobStart: Int

    /// - Parameter bundle: nil이면 패키지 리소스 번들 (테스트에서만 바꾼다)
    public init(bundle: Bundle? = nil) {
        self.init(url: (bundle ?? .module).url(forResource: "emoji", withExtension: "tde"))
    }

    /// 테스트 주입용. 파일이 없거나 형식이 깨졌으면 모든 조회가 nil인 빈 역색인이 된다.
    init(url: URL?) {
        guard let url,
              let mapped = try? Data(contentsOf: url, options: .mappedIfSafe),
              mapped.count >= Self.headerSize,
              mapped.prefix(4).elementsEqual("TDEM".utf8)
        else {
            data = nil
            keyCount = 0
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
            keyCount = 0
            blobStart = 0
            return
        }
        data = mapped
        keyCount = count
        blobStart = start
    }

    public func annotation(for word: String) -> EmojiAnnotation? {
        guard let data, !word.isEmpty else { return nil }
        let key = Array(word.utf8)
        let count = keyCount
        let blobStart = blobStart
        let total = data.count

        return data.withUnsafeBytes { raw -> EmojiAnnotation? in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else { return nil }
            func u16(_ offset: Int) -> Int {
                Int(UInt16(base[offset]) | UInt16(base[offset + 1]) << 8)
            }
            func u32(_ offset: Int) -> Int {
                Int(UInt32(base[offset]) | UInt32(base[offset + 1]) << 8
                    | UInt32(base[offset + 2]) << 16 | UInt32(base[offset + 3]) << 24)
            }
            /// 엔트리 키와 찾는 키의 바이트 비교 — 음수면 엔트리가 앞선다. 파일 밖이면 nil
            func compare(_ index: Int) -> Int? {
                let entry = Self.headerSize + index * Self.entrySize
                let start = blobStart + u32(entry)
                let length = u16(entry + 4)
                guard start + length <= total else { return nil }
                var i = 0
                while i < length && i < key.count {
                    if base[start + i] != key[i] { return Int(base[start + i]) - Int(key[i]) }
                    i += 1
                }
                return length - key.count
            }

            var low = 0
            var high = count - 1
            while low <= high {
                let mid = (low + high) / 2
                guard let order = compare(mid) else { return nil }
                if order < 0 {
                    low = mid + 1
                } else if order > 0 {
                    high = mid - 1
                } else {
                    let entry = Self.headerSize + mid * Self.entrySize
                    let start = blobStart + u32(entry + 8)
                    let length = u16(entry + 6)
                    guard start + length <= total else { return nil }
                    let emojis = raw[start..<(start + length)]
                        .split(separator: Self.separator)
                        .compactMap { String(bytes: $0, encoding: .utf8) }
                    guard !emojis.isEmpty else { return nil }
                    let nameMatch = u16(entry + 12)
                    return EmojiAnnotation(
                        emojis: emojis,
                        nameMatch: (1...emojis.count).contains(nameMatch) ? emojis[nameMatch - 1] : nil)
                }
            }
            return nil
        }
    }
}

/// 번들 `EmojiCuration.json` — 사람이 고른 대표 이모지(손질 목록, PDR Q7·Q9). 형식은 `EmojiCuration`.
/// 값 검사(한글 2~12자 키, iOS 17 카탈로그 안의 단일 이모지)는 `tools/convert_emoji.py`가 매 실행 한다.
public struct BundledEmojiCurationRepository: EmojiCurationRepository {

    private let loaded: EmojiCuration

    /// - Parameter bundle: nil이면 패키지 리소스 번들 (테스트에서만 바꾼다)
    public init(bundle: Bundle? = nil) {
        self.init(url: (bundle ?? .module).url(forResource: "EmojiCuration", withExtension: "json"))
    }

    /// 테스트 주입용. 파일이 없거나 깨졌으면 빈 목록이다.
    init(url: URL?) {
        guard let url,
              let data = try? Data(contentsOf: url),
              let curation = try? JSONDecoder().decode(EmojiCuration.self, from: data)
        else {
            loaded = .empty
            return
        }
        loaded = curation
    }

    public func curation() -> EmojiCuration {
        loaded
    }
}
