import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 번들 `emoji.tde` 조회 — `tools/convert_emoji.py`(CLDR 48.2 · Unicode 15.0 필터) 산출물과
/// Swift 리더의 포맷 정합까지 함께 검증한다. 대표 이모지 규칙은 KeyboardCore `RepresentativeEmojiTests`.
@Suite("이모지 역색인 — 번들 emoji.tde")
struct BundledEmojiAnnotationIndexTests {

    private let index = BundledEmojiAnnotationIndex()

    @Test("「자동차」 — 값은 CLDR 파일 순서(첫 값 🚕), 이름 일치는 🚗")
    func carKeepsFileOrderAndNameMatch() {
        let annotation = index.annotation(for: "자동차")
        #expect(annotation?.emojis == ["🚕", "🚗", "🚘", "🛻", "🛞"])
        #expect(annotation?.nameMatch == "🚗")
    }

    @Test("이름(tts) 일치 표본", arguments: [
        ("고양이", "🐈"), ("선물", "🎁"), ("사람", "🧑"),
        ("맥주", "🍻")  // PDR 2-3절 표는 「없음」이라 했지만 CLDR ko의 🍻 tts가 「맥주」다(emoji-data-import.md)
    ])
    func nameMatches(testCase: (word: String, emoji: String)) {
        let annotation = index.annotation(for: testCase.word)
        #expect(annotation?.nameMatch == testCase.emoji)
        #expect(annotation?.emojis.contains(testCase.emoji) == true)
    }

    @Test("이름 일치가 없는 단어는 후보만 있다 — 「사과」(🍎의 이름은 「빨간 사과」)")
    func candidatesWithoutNameMatch() {
        let annotation = index.annotation(for: "사과")
        #expect(annotation?.emojis == ["🙇", "🍎", "🍏"])
        #expect(annotation?.nameMatch == nil)
    }

    @Test("정렬 양 끝 키도 이진 탐색으로 찾는다")
    func boundaryKeys() {
        #expect(index.annotation(for: "가게")?.emojis == ["🏪", "🏬"])
        #expect(index.annotation(for: "힙합")?.emojis == ["🤘"])
    }

    @Test("없는 키·조사 붙은 꼴·한글 아닌 입력은 nil이다", arguments: ["자동차는", "", "ㅋㅋ", "car", "가", "힙합힙합"])
    func missingKeys(word: String) {
        #expect(index.annotation(for: word) == nil)
    }

    /// PDR 2-6절·D5 — 텍스트 기본 이모지(❤·♨ 등 VS16 필요)는 범위 밖이라 그것만 걸려 있던 키는 사라진다.
    @Test("iOS 17 카탈로그 밖 이모지는 없다 — 텍스트 기본 이모지만 걸린 키는 사라진다")
    func catalogFiltered() throws {
        #expect(index.annotation(for: "온천") == nil, "♨ 텍스트 기본")
        #expect(index.annotation(for: "주차장") == nil, "🅿 텍스트 기본")
        let love = try #require(index.annotation(for: "사랑"))
        #expect(!love.emojis.contains("❤"))
        for word in ["자동차", "사랑", "하트", "얼굴", "시간"] {
            for emoji in index.annotation(for: word)?.emojis ?? [] {
                let scalars = Array(emoji.unicodeScalars)
                #expect(scalars.count == 1 && scalars[0].properties.isEmojiPresentation,
                        "\(word): 단일 스칼라 이모지 표현만")
            }
        }
    }

    @Test("리소스가 없는 번들이면 빈 역색인이다")
    func missingResource() {
        #expect(BundledEmojiAnnotationIndex(bundle: .main).annotation(for: "자동차") == nil)
    }

    @Test("헤더가 깨졌으면 빈 역색인이다")
    func brokenHeader() throws {
        let url = try temporaryFile(Data("TDWD-not-emoji".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BundledEmojiAnnotationIndex(url: url).annotation(for: "자동차") == nil)
    }

    /// 유효 헤더 + 블롭 밖을 가리키는 엔트리 — OOB 없이 nil이어야 한다(BundledWordDictionary와 같은 방어).
    @Test("손상 엔트리(파일 밖 오프셋)에서 크래시 없이 nil이다")
    func corruptedEntry() throws {
        var corrupt = Data("TDEM".utf8)
        for value in [UInt32(1), 1, 32] {  // version, 키 수 1, blobStart 16+16
            withUnsafeBytes(of: value.littleEndian) { corrupt.append(contentsOf: $0) }
        }
        // keyOffset 9999 · keyLen 9 · valuesLen 4 · valuesOffset 9999 · nameMatch 1 · count 1
        for value in [UInt32(9999), UInt32(4) << 16 | 9, 9999, UInt32(1) << 16 | 1] {
            withUnsafeBytes(of: value.littleEndian) { corrupt.append(contentsOf: $0) }
        }
        corrupt.append(Data("자동차".utf8))
        let url = try temporaryFile(corrupt)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BundledEmojiAnnotationIndex(url: url).annotation(for: "자동차") == nil)
    }

    @Test("이름 일치 순번이 값 개수를 넘으면 이름 일치 없이 값만 낸다")
    func nameMatchOutOfRange() throws {
        let key = Data("자동차".utf8)
        let value = Data("🚗".utf8)
        var file = Data("TDEM".utf8)
        for v in [UInt32(1), 1, 32] {
            withUnsafeBytes(of: v.littleEndian) { file.append(contentsOf: $0) }
        }
        // keyOffset 0 · keyLen · valuesLen · valuesOffset = keyLen · nameMatch 5(범위 밖) · count 1
        for v in [UInt32(0), UInt32(value.count) << 16 | UInt32(key.count), UInt32(key.count),
                  UInt32(1) << 16 | 5] {
            withUnsafeBytes(of: v.littleEndian) { file.append(contentsOf: $0) }
        }
        file.append(key)
        file.append(value)
        let url = try temporaryFile(file)
        defer { try? FileManager.default.removeItem(at: url) }
        let annotation = BundledEmojiAnnotationIndex(url: url).annotation(for: "자동차")
        #expect(annotation == EmojiAnnotation(emojis: ["🚗"], nameMatch: nil))
    }

    private func temporaryFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("emoji-\(UUID().uuidString).tde")
        try data.write(to: url)
        return url
    }
}

@Suite("손질 목록 — 번들 EmojiCuration.json")
struct BundledEmojiCurationRepositoryTests {

    /// 손질 목록은 아직 비어 있다(13절 4번 — 기획자가 `curation-candidates.csv`로 초안을 만든다).
    /// 채워진 뒤에도 이 검사가 형식을 지킨다 — iOS 17 기준(Unicode 15.0) 검사는 변환기가 한다.
    @Test("번들 목록이 읽히고, 키는 한글 2~12자·값은 빈 문자열 또는 단일 이모지다")
    func bundledCurationShape() throws {
        let url = try #require(Bundle.module.url(forResource: "EmojiCuration", withExtension: "json"),
                               "리소스가 번들에 있어야 한다")
        #expect(BundledEmojiCurationRepository(url: url).curation()
                == BundledEmojiCurationRepository().curation())
        let curation = BundledEmojiCurationRepository().curation()
        let pattern = try Regex("^[가-힣]{2,12}$")
        for (word, emoji) in curation.overrides.merging(curation.fallbacks, uniquingKeysWith: { a, _ in a }) {
            #expect(word.wholeMatch(of: pattern) != nil, "키: \(word)")
            let scalars = Array(emoji.unicodeScalars)
            #expect(emoji.isEmpty || (scalars.count == 1 && scalars[0].properties.isEmojiPresentation),
                    "값: \(word) → \(emoji)")
        }
    }

    @Test("JSON의 override·fallback이 각 목록으로 읽힌다")
    func decodesSections() throws {
        let url = try temporaryFile(#"{"override":{"맥주":"🍺","다리":""},"fallback":{"사과":"🍎"}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BundledEmojiCurationRepository(url: url).curation()
                == EmojiCuration(overrides: ["맥주": "🍺", "다리": ""], fallbacks: ["사과": "🍎"]))
    }

    @Test("리소스가 없거나 깨졌으면 빈 목록이다")
    func missingOrBroken() throws {
        #expect(BundledEmojiCurationRepository(bundle: .main).curation() == .empty)
        let url = try temporaryFile("[1, 2")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BundledEmojiCurationRepository(url: url).curation() == .empty)
    }

    private func temporaryFile(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("curation-\(UUID().uuidString).json")
        try Data(text.utf8).write(to: url)
        return url
    }
}
