import CryptoKit
import Foundation
import Testing
@testable import PackImport

/// 잠금 팩 상호운용 고정 벡터(PDR `external-snippet-packs.md` 12-11, AC-G4).
///
/// 파일은 **파이썬 독립 구현**(`tools/gspack/make_vectors.py` — `hashlib` + `cryptography`)이 만들었고, 같은 스크립트가
/// 파이썬 검증기로 기대 결과를 이미 확인했다. 여기서는 Swift 구현이 **같은 파일에 같은 결론**을 내는지 본다.
/// KDF 전 거부(M1~M3)는 주입한 KDF 스파이가 **0회**여야 한다(12-11 「앱 시험」).
/// 수 MB 경계(V27 ③·V28 ①)는 커밋하지 않고 `GSPackOpenerTests`가 시험 안에서 만든다. V30(확장자 분기)은 세션 몫이다.
@Suite("잠금 팩 — 고정 벡터 (12-11)")
struct GSPackVectorTests {

    @Test("고정 벡터 — 기대 코드·평문 해시·AAD·KDF 호출 수", arguments: GSPackFixtures.vectors)
    func vector(_ vector: GSPackVector) throws {
        let data = try GSPackFixtures.data(vector.file)
        let spy = GSPackKDFSpy()
        let outcome = gspackOutcome(data, password: try vector.password(), spy: spy)

        switch (vector.expect, outcome) {
        case ("ok", .opened(let text)):
            #expect(Data(text.utf8).sha256Hex == vector.textSha256)
            #expect(text.utf8.count == vector.textUtf8Bytes)
        case (_, .failed(let failure)):
            #expect(failure == GSPackVector.failure(for: vector.expect), "\(vector.id): \(failure)")
        default:
            Issue.record("\(vector.id): 기대 \(vector.expect)인데 열렸다")
        }

        let preKDF = ["M1", "M2", "M3"].contains(vector.expect)
        #expect(preKDF == (vector.stage == "parse"), "생성기가 적은 단계와 기대 코드가 맞아야 한다")
        #expect(spy.callCount == (preKDF ? 0 : 1), "\(vector.id): KDF 전 거부면 0회, 아니면 1회")

        if let aadHex = vector.aadHex {
            #expect(try GSPackEnvelope.parse(data).additionalData.hexString == aadHex, "AAD가 파이썬과 바이트 단위로 같다")
            #expect(try GSPackEnvelope.parse(data).iterations == vector.iterations)
        }
    }

    @Test("벡터 목록이 실제로 읽히고 12-11 표의 번호를 덮는다")
    func coverage() {
        let vectors = GSPackFixtures.vectors
        #expect(vectors.count >= 130)
        let numbers = Set(vectors.map { String($0.id.prefix(3)) })
        let expected = Set((0...29).filter { ![27, 28].contains($0) }.map { String(format: "V%02d", $0) })
        #expect(numbers == expected, "V27·V28은 시험 안에서 만든다(GSPackOpenerTests), V30은 세션 몫")
        for code in ["ok", "M1", "M2", "M4", "M5"] {
            #expect(vectors.contains { $0.expect == code }, "\(code) 벡터가 있다")
        }
    }

    @Test("V22 — 메타를 \\uXXXX로 쓴 파일과 원문 UTF-8 파일은 같은 봉투(같은 AAD·같은 암호문)")
    func escapedMetaIsSameEnvelope() throws {
        let raw = try GSPackEnvelope.parse(GSPackFixtures.data("v22-raw.gspack"))
        let escaped = try GSPackEnvelope.parse(GSPackFixtures.data("v22-escaped.gspack"))
        #expect(raw == escaped)
        #expect(raw.meta.name.unicodeScalars.contains("\u{1F600}"))
    }

    @Test("V03 — BOM은 평문 CSV 디코더(F8)와 같이 벗긴다: 한 겹·두 겹은 같은 글자, 세 겹이면 U+FEFF 하나 남음")
    func bomMatchesPlainCSVDecoder() throws {
        func opened(_ file: String, _ password: String) throws -> String {
            try GSPackOpener.open(GSPackEnvelope.parse(GSPackFixtures.data(file)), password: password)
        }
        let single = try opened("v03-bom.gspack", "bom-password-1")
        #expect(single.unicodeScalars.first != "\u{FEFF}")
        #expect(try opened("v03-double-bom.gspack", "bom-password-2") == single)
        let triple = try opened("v03-triple-bom.gspack", "bom-password-3")
        #expect(triple.unicodeScalars.first == "\u{FEFF}")
        #expect(String(triple.unicodeScalars.dropFirst()) == single)
        // 같은 바이트를 평문 CSV 경로로 읽은 결과와 같다(파서 하나 — 12-8)
        let plain = Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + Data("단축어,본문\n".utf8)
        #expect(try GSPackOpener.innerText(plain) == PackTextDecoder.decode(plain).text)
    }

    @Test("12-8 — 안쪽 글자는 붙여넣기 경로(PackImporter.read(text:))로 이어진다: 정상·BOM은 초안, V13 빈 평문은 「내용 없음」")
    func innerTextFeedsPastePath() throws {
        func opened(_ file: String, _ password: String) throws -> String {
            try GSPackOpener.open(GSPackEnvelope.parse(GSPackFixtures.data(file)), password: password)
        }
        for (file, password) in [("v02-korean.gspack", "한글비밀번호-2026"), ("v03-bom.gspack", "bom-password-1"),
                                 ("v03-double-bom.gspack", "bom-password-2")] {
            guard case .draft(let draft) = try PackImporter.read(text: opened(file, password)) else {
                Issue.record("\(file): 초안이 아니다")
                continue
            }
            #expect(draft.acceptedRecordCount == 2 && draft.skipped.isEmpty, "\(file): 행 2개(안녕·감사)가 그대로 들어온다")
        }
        #expect(throws: PackImportFailure.emptyFile) {
            try PackImporter.read(text: opened("v13-empty-plaintext.gspack", "empty-plain-pass"))
        }
    }
}

// MARK: - 벡터 파일

struct GSPackVector: Decodable, Sendable, CustomTestStringConvertible {
    let id: String
    let `case`: String
    let file: String
    let passwordUtf8Hex: String
    let expect: String
    let stage: String
    let aadHex: String?
    let iterations: Int?
    let textSha256: String?
    let textUtf8Bytes: Int?

    var testDescription: String { "\(id) \(self.case)" }

    /// 16진 UTF-8 → 글자(NUL·NFD를 그대로 보존)
    func password() throws -> String {
        let bytes = try #require(Data(gspackHex: passwordUtf8Hex))
        let text = String(decoding: bytes, as: UTF8.self)
        try #require(text.utf8.elementsEqual(bytes))
        return text
    }

    static func failure(for code: String) -> GSPackFailure? {
        switch code {
        case "M1": .malformed
        case "M2": .newerVersion
        case "M3": .tooLarge
        case "M4": .wrongPasswordOrDamaged
        case "M5": .unreadableContent
        case "M6": .passwordTooLong
        case "EMPTY": .passwordEmpty
        default: nil
        }
    }
}

enum GSPackFixtures {

    static let vectors: [GSPackVector] = {
        guard let url = Bundle.module.url(forResource: "vectors", withExtension: "json", subdirectory: "Fixtures/gspack"),
              let data = try? Data(contentsOf: url) else { return [] }
        struct File: Decodable { let vectors: [GSPackVector] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return (try? decoder.decode(File.self, from: data).vectors) ?? []
    }()

    static func data(_ file: String) throws -> Data {
        let name = (file as NSString).deletingPathExtension
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "gspack", subdirectory: "Fixtures/gspack"))
        return try Data(contentsOf: url)
    }
}

// MARK: - 공용 도우미 (GSPack*Tests)

/// KDF 스파이 — 호출 수를 세고 실제 KDF(기본 PBKDF2) 결과를 넘긴다
final class GSPackKDFSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var lastKey: [UInt8]?
    private let underlying: GSPackKeyDerivation

    init(_ underlying: @escaping GSPackKeyDerivation = GSPackOpener.pbkdf2) {
        self.underlying = underlying
    }

    var callCount: Int { lock.withLock { calls } }
    var derivedKey: [UInt8]? { lock.withLock { lastKey } }

    var derive: GSPackKeyDerivation {
        { [self] password, salt, iterations in
            let key = underlying(password, salt, iterations)
            lock.withLock {
                calls += 1
                lastKey = key
            }
            return key
        }
    }
}

enum GSPackOutcome: Equatable {
    case opened(String)
    case failed(GSPackFailure)
}

/// 세션과 같은 순서 — 봉투 검사(ⓐ~ⓕ) → 비밀번호·KDF·open
func gspackOutcome(_ data: Data, password: String, spy: GSPackKDFSpy) -> GSPackOutcome {
    do throws(GSPackFailure) {
        let envelope = try GSPackEnvelope.parse(data)
        return .opened(try GSPackOpener.open(envelope, password: password, deriveKey: spy.derive))
    } catch {
        return .failed(error)
    }
}

extension Data {
    init?(gspackHex hex: String) {
        guard hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var sha256Hex: String { SHA256.hash(data: self).hexString }
}

extension Sequence where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
