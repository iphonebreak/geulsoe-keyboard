import Foundation

/// 글자 확인 화면(시안 4-B·4-C)의 값 — **BOM 없는 비ASCII 파일이면 항상** 이 화면부터(PDR 5-3b ⑤, R18).
///
/// 자동 판정은 추정이다(`C3 A9` = UTF-8 `é` = CP949 `챕`). 그래서 두 방식으로 각각 읽어 **같은 자리의 표본**을 나란히 보이고,
/// 읽히지 않는 방식은 몇 줄이 깨지는지 센다. 사용자가 고르면 상태기계가 **원본 바이트에서 전부 다시** 읽는다(5-1·AC-18) —
/// 이 값은 그 한 번의 읽기에서 나온 보기일 뿐 다음 읽기에 재사용하지 않는다.
///
/// 표본은 파일 내용이다 — **이 기기 화면에만** 보이고 로그·분석 이벤트·오류 문구에 싣지 않는다(보안 규칙·AC-34).
public struct PackEncodingReview: Equatable, Sendable {

    /// 확인 화면이 고르게 하는 두 방식(5-3b ⑤ 「UTF-8 ↔ 한국어(CP949)」)
    public enum Encoding: Equatable, Sendable, CaseIterable {
        case utf8, cp949

        var choice: PackEncodingChoice { self == .utf8 ? .utf8 : .cp949 }
    }

    /// 한 방식으로 읽어 본 결과
    public struct Reading: Equatable, Sendable {
        /// 파일 전체가 이 방식으로 엄격하게 읽힌다(`PackTextDecoder`와 같은 판정)
        public var isReadable: Bool
        /// 이 방식으로 읽히지 않는 줄 수(4-B 「깨진 글자 n행」) — 읽히면 0
        public var failedLines: Int
        /// 표본 — 두 방식이 **같은 자리**(같은 바이트 구간)를 읽은 것. 그 자리를 이 방식으로 못 읽으면 nil
        public var samples: [String?]

        public init(isReadable: Bool, failedLines: Int, samples: [String?]) {
            self.isReadable = isReadable
            self.failedLines = failedLines
            self.samples = samples
        }
    }

    /// 지금 고른 방식 — 자동이면 디코더의 자동 순서(엄격 UTF-8 → 엄격 CP949)가 고른 것
    public var selected: Encoding
    public var utf8: Reading
    public var cp949: Reading
    /// 고른 방식으로 읽은 표의 데이터 행 수(4-B 「행」) — 표를 만들지 못했으면(구조 오류 등) nil
    public var recordCount: Int?
    /// 여러 줄 본문 수(4-B 「여러 줄 본문」, 5-3b ⑤ 「본문 개행 수」)
    public var multilineBodyCount: Int?

    public init(selected: Encoding, utf8: Reading, cp949: Reading, recordCount: Int?, multilineBodyCount: Int?) {
        self.selected = selected
        self.utf8 = utf8
        self.cp949 = cp949
        self.recordCount = recordCount
        self.multilineBodyCount = multilineBodyCount
    }

    public func reading(_ encoding: Encoding) -> Reading { encoding == .utf8 ? utf8 : cp949 }

    /// 고르지 않은 쪽
    public var other: Encoding { selected == .utf8 ? .cp949 : .utf8 }

    /// 두 방식 모두 파일 전체를 읽는다(4-C)
    public var bothReadable: Bool { utf8.isReadable && cp949.isReadable }

    /// 표본 수와 한 표본의 글자 수 — 길면 자르고 「…」
    static let sampleCount = 3
    public static let sampleLength = 30

    // MARK: - 원본 바이트에서

    /// 이 원본이 글자 확인을 거쳐야 하나 — BOM 없음 · 비ASCII 있음 · NUL 없음(NUL이면 자동이 지원하지 않는 인코딩으로 거부, 5-3b #4) ·
    /// 두 방식 중 하나라도 읽힘(둘 다 못 읽으면 확인할 것 없이 거부). 확인이 필요 없으면 nil
    static func probe(_ data: Data, choice: PackEncodingChoice) -> PackEncodingReview? {
        let bytes = [UInt8](data)
        let hasBOM = bytes.starts(with: [0xEF, 0xBB, 0xBF]) || bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])
            || bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF])
        guard !hasBOM, bytes.contains(where: { $0 >= 0x80 }), !bytes.contains(0x00) else { return nil }
        // 판정은 디코더 그대로(엄격 + 왕복) — 화면이 「읽힌다」고 한 방식은 가져오기도 읽는다
        let utf8Readable = (try? PackTextDecoder.decode(data, choice: .utf8)) != nil
        let cp949Readable = (try? PackTextDecoder.decode(data, choice: .cp949)) != nil
        guard utf8Readable || cp949Readable else { return nil }

        let selected: Encoding = switch choice {
        case .automatic: utf8Readable ? .utf8 : .cp949
        case .utf8: .utf8
        case .cp949: .cp949
        }
        let segments = sampleSegments(bytes)
        func reading(_ readable: Bool, _ decode: (ArraySlice<UInt8>) -> String?) -> Reading {
            Reading(isReadable: readable, failedLines: readable ? 0 : failedLineCount(bytes, decode: decode),
                    samples: segments.map { decode($0).map(trimmedSample) })
        }
        return PackEncodingReview(selected: selected, utf8: reading(utf8Readable, strictUTF8), cp949: reading(cp949Readable, strictCP949),
                                  recordCount: nil, multilineBodyCount: nil)
    }

    /// 비ASCII가 든 **칸 모양 구간**의 처음 몇 개 — 줄(LF·CR)과 흔한 구분자(`,`·`;`·탭)로 자른다. 모두 ASCII라 CP949의 둘째 바이트
    /// (0x41 이상)와 겹치지 않아, 같은 구간을 두 방식으로 읽으면 같은 자리가 나온다(4-C의 é / 챕)
    static func sampleSegments(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        var segments: [ArraySlice<UInt8>] = []
        var start = 0
        for index in 0...bytes.count {
            let isEnd = index == bytes.count
            guard isEnd || [0x0A, 0x0D, 0x2C, 0x3B, 0x09].contains(bytes[index]) else { continue }
            let segment = bytes[start..<index]
            if segment.contains(where: { $0 >= 0x80 }) {
                segments.append(segment)
                if segments.count == sampleCount { break }
            }
            start = index + 1
        }
        return segments
    }

    /// 앞뒤 공백·감싼 따옴표를 떼고 길면 자른다
    static func trimmedSample(_ text: String) -> String {
        var sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if sample.hasPrefix("\"") { sample.removeFirst() }
        if sample.hasSuffix("\"") { sample.removeLast() }
        sample = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        return sample.count > sampleLength ? String(sample.prefix(sampleLength)) + "…" : sample
    }

    /// 비ASCII가 든 줄 가운데 이 방식으로 엄격하게 읽히지 않는 줄 수. LF는 두 방식 모두 다른 글자의 일부가 될 수 없다
    static func failedLineCount(_ bytes: [UInt8], decode: (ArraySlice<UInt8>) -> String?) -> Int {
        bytes.split(separator: 0x0A, omittingEmptySubsequences: true)
            .filter { line in line.contains { $0 >= 0x80 } && decode(line) == nil }
            .count
    }

    /// `PackTextDecoder`와 같은 엄격성(표준 라이브러리 디코드 + 왕복) — 구간 단위
    static func strictUTF8(_ bytes: ArraySlice<UInt8>) -> String? {
        let text = String(decoding: bytes, as: UTF8.self)
        return text.utf8.elementsEqual(bytes) ? text : nil
    }

    static func strictCP949(_ bytes: ArraySlice<UInt8>) -> String? {
        let data = Data(bytes)
        guard let text = String(data: data, encoding: PackTextDecoder.cp949), text.data(using: PackTextDecoder.cp949) == data else {
            return nil
        }
        return text
    }
}
