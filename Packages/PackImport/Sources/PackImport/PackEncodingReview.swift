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

    /// 표본 하나 — 데이터 칸 하나, 또는 머리글 위 정보 줄 **한 줄**(R29 — 원문 `#이름,값,` 대신 화면이 「이름 : 값」으로 보인다.
    /// 줄을 더 만들지 않는다). 문구(「이름」·「출처」…)는 화면 쪽 문구 표(`PackImportCopy.sampleLine`)가 붙인다
    public struct Sample: Equatable, Sendable {
        /// 정보 줄이면 그 칸(이름·틀·출처 — 옛 `#권리`도 출처), 데이터 칸·모르는 `#` 키면 nil
        public var meta: PackMetaField?
        /// 칸 글자(앞뒤 공백·감싼 따옴표를 떼고 길면 자른 것). 정보 줄이면 값들을 「, 」로 이은 것(끝의 빈 칸 제외)
        public var text: String

        public init(meta: PackMetaField?, text: String) {
            self.meta = meta
            self.text = text
        }
    }

    /// 한 방식으로 읽어 본 결과
    public struct Reading: Equatable, Sendable {
        /// 파일 전체가 이 방식으로 엄격하게 읽힌다(`PackTextDecoder`와 같은 판정)
        public var isReadable: Bool
        /// 이 방식으로 읽히지 않는 줄 수(4-B 「깨진 글자 n행」) — 읽히면 0
        public var failedLines: Int
        /// 표본 — 두 방식이 **같은 자리**(같은 바이트 구간)를 읽은 것. 그 자리를 이 방식으로 못 읽으면 nil
        public var samples: [Sample?]

        public init(isReadable: Bool, failedLines: Int, samples: [Sample?]) {
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

    /// 표본 수와 한 표본의 글자 수 — 길면 자르고 「…」. 두 줄이다(사장님 실기 2026-10-07 — 셋일 때 머리글 칸이 다 차지했다)
    static let sampleCount = 2
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
        let units = sampleUnits(bytes)
        func reading(_ readable: Bool, _ decode: (ArraySlice<UInt8>) -> String?) -> Reading {
            Reading(isReadable: readable, failedLines: readable ? 0 : failedLineCount(bytes, decode: decode),
                    samples: units.map { sample($0, decode: decode) })
        }
        return PackEncodingReview(selected: selected, utf8: reading(utf8Readable, strictUTF8), cp949: reading(cp949Readable, strictCP949),
                                  recordCount: nil, multilineBodyCount: nil)
    }

    /// 표본 자리 하나 — 같은 바이트 구간을 두 방식이 각자 읽는다(4-C)
    struct SampleUnit: Equatable {
        /// 칸 구간들 — 데이터 칸이면 하나, 정보 줄이면 그 줄의 칸 전부(끝의 빈 칸 제외)
        var cells: [ArraySlice<UInt8>]
        /// 머리글 위 `#` 줄(첫 칸이 `#`·`"#`로 시작)이면 그 줄을 나눈 구분자 — 칸 이름은 읽은 글자로 정한다(방식마다 다를 수 있다). 데이터 칸이면 nil
        var metaSeparator: UInt8?
    }

    /// 표본 자리 두 개 — **실제 데이터가 보이게** 고른다(사장님 실기 2026-10-07: 표본이 머리글 칸 「단축어·제목·본문」뿐이라
    /// 글자가 맞는지 알 수 없었다).
    ///
    /// 1. 머리글 위 `#` 줄 가운데 비ASCII가 든 **첫 줄 하나**(R29 — 그 줄 전체가 자리 하나, 「이름 : 값」으로 보인다)
    /// 2. 데이터 줄마다 **칸 하나** — 한글이 든 칸이 우선(두 방식 어느 쪽으로 읽어도 한글이 나오는 칸 — 바이트만 보고 정하므로 두 방식이
    ///    **같은 자리**를 보인다), 없으면 비ASCII가 든 첫 칸. 한글 칸이 있는 줄이 먼저다
    /// 3. **머리글 줄**(첫 `#` 아닌 줄)의 칸은 위 둘로 모자랄 때만 채운다 — 사용자가 적은 데이터가 아니라 칸 이름이다
    ///
    /// 보이는 순서는 파일 순서다. 칸은 줄(LF·CR)과 흔한 구분자(`,`·`;`·탭)로 자른다 — 모두 ASCII라 CP949의 둘째 바이트(0x41 이상)와
    /// 겹치지 않아, 같은 구간을 두 방식으로 읽으면 같은 자리가 나온다(4-C의 é / 챕). 따옴표는 보지 않으므로 여러 줄 본문의 다음 줄도
    /// 데이터 줄 하나로 센다(보여 주기용). 머리글 뒤(첫 `#` 아닌 줄 다음)의 `#`는 본문 글자다(5-3)
    static func sampleUnits(_ bytes: [UInt8]) -> [SampleUnit] {
        var meta: SampleUnit?
        var header: [SampleUnit] = []
        // 데이터 줄 자리 — 한글 칸이 있는 줄을 먼저 고르고, 보일 때는 줄 순서(`line`)로 늘어놓는다
        var hangulRows: [(line: Int, unit: SampleUnit)] = []
        var otherRows: [(line: Int, unit: SampleUnit)] = []
        var beforeHeader = true
        var lineStart = 0
        var lineNumber = 0
        for index in 0...bytes.count where index == bytes.count || bytes[index] == 0x0A || bytes[index] == 0x0D {
            let line = bytes[lineStart..<index]
            lineStart = index + 1
            let cells = line.split(omittingEmptySubsequences: false, whereSeparator: separators.contains)
            guard cells.contains(where: { !$0.isEmpty }) else { continue }   // 빈 줄·구분자만 — 머리글 앞이어도 그대로
            lineNumber += 1
            if beforeHeader, startsWithHash(cells[0]) {
                guard meta == nil, line.contains(where: { $0 >= 0x80 }) else { continue }
                // 정보 줄은 키 뒤의 첫 구분자 하나로만 나눈다 — 값 안의 다른 기호(`;`·탭)는 글자다
                let separator = line.first(where: separators.contains) ?? 0x2C
                var metaCells = line.split(omittingEmptySubsequences: false) { $0 == separator }
                while metaCells.last?.isEmpty == true { metaCells.removeLast() }   // 끝의 빈 칸(시트 폭 패딩)
                meta = SampleUnit(cells: metaCells, metaSeparator: separator)
            } else if beforeHeader {
                beforeHeader = false
                header = cells.filter { $0.contains { $0 >= 0x80 } }.prefix(sampleCount).map { SampleUnit(cells: [$0], metaSeparator: nil) }
            } else {
                let nonASCII = cells.filter { $0.contains { $0 >= 0x80 } }
                guard let first = nonASCII.first else { continue }
                if let hangul = nonASCII.first(where: containsHangul) {
                    hangulRows.append((lineNumber, SampleUnit(cells: [hangul], metaSeparator: nil)))
                } else if otherRows.count < sampleCount {
                    otherRows.append((lineNumber, SampleUnit(cells: [first], metaSeparator: nil)))
                }
                if hangulRows.count == rowCount(meta) { break }   // 데이터 한글 칸이 찼으면 더 볼 것이 없다
            }
        }
        // 파일 순서 — 정보 줄 → (모자라면) 머리글 칸 → 데이터 줄
        let rows = (hangulRows + otherRows).prefix(rowCount(meta)).sorted { $0.line < $1.line }.map(\.unit)
        let headerFill = header.prefix(rowCount(meta) - rows.count)
        return (meta.map { [$0] } ?? []) + headerFill + rows
    }

    /// 데이터 줄 표본 수 — 정보 줄 표본이 있으면 하나 덜
    private static func rowCount(_ meta: SampleUnit?) -> Int { sampleCount - (meta == nil ? 0 : 1) }

    /// 두 방식 중 하나로라도 읽으면 한글(음절·자모)이 나오는 칸 — 사람이 글자가 맞는지 알아볼 수 있는 칸이다. 바이트만 보고 정한다
    static func containsHangul(_ cell: ArraySlice<UInt8>) -> Bool {
        [strictUTF8(cell), strictCP949(cell)].contains { text in
            text?.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x1100...0x11FF).contains($0.value)
                || (0x3130...0x318F).contains($0.value) } ?? false
        }
    }

    /// 칸을 자르는 흔한 구분자 `,`·`;`·탭 — 따옴표는 보지 않는다(보여 주기용, 본 읽기는 `CSVRecordParser`)
    static let separators: Set<UInt8> = [0x2C, 0x3B, 0x09]

    /// 앞 공백과 여는 따옴표 하나를 건너 `#`로 시작하나(ASCII — 두 방식이 같게 본다)
    static func startsWithHash(_ cell: ArraySlice<UInt8>) -> Bool {
        var rest = cell.drop { $0 == 0x20 }
        if rest.first == 0x22 { rest = rest.dropFirst() }
        return rest.first == 0x23
    }

    /// 표본 자리 하나를 한 방식으로 — 그 자리의 칸 하나라도 이 방식으로 못 읽으면 nil
    static func sample(_ unit: SampleUnit, decode: (ArraySlice<UInt8>) -> String?) -> Sample? {
        var texts: [String] = []
        for cell in unit.cells {
            guard let text = decode(cell) else { return nil }
            texts.append(text)
        }
        guard let separator = unit.metaSeparator else { return texts.first.map { Sample(meta: nil, text: trimmedSample($0)) } }
        let key = unquoted(texts[0])
        guard let field = PackMetaField.field(forKey: key) else {
            // 모르는 키 — 칸 이름 없이 그 줄 원문(파서가 따로 거부한다). 이 방식으로 읽은 글자가 키가 아닐 때도 여기다(4-C의 다른 쪽)
            return Sample(meta: nil, text: trimmedSample(texts.joined(separator: String(UnicodeScalar(separator)))))
        }
        let values = texts.dropFirst().map(unquoted).filter { !$0.isEmpty }
        return Sample(meta: field, text: truncated(values.joined(separator: ", ")))
    }

    /// 앞뒤 공백·감싼 따옴표를 떼고 길면 자른다
    static func trimmedSample(_ text: String) -> String { truncated(unquoted(text)) }

    /// 앞뒤 공백과 감싼 따옴표(한쪽만 있어도)를 뗀다
    static func unquoted(_ text: String) -> String {
        var sample = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if sample.hasPrefix("\"") { sample.removeFirst() }
        if sample.hasSuffix("\"") { sample.removeLast() }
        return sample.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func truncated(_ text: String) -> String {
        text.count > sampleLength ? String(text.prefix(sampleLength)) + "…" : text
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
