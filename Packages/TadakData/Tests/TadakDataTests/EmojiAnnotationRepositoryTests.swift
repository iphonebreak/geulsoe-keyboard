import Foundation
import Testing
import TadakDomain
@testable import TadakData

/// 번들 `emoji.tde` 조회 — `tools/convert_emoji.py`(CLDR 48.2 · Unicode 15.0 필터) 산출물과
/// Swift 리더의 포맷 정합까지 함께 검증한다. 묶음 규칙은 TadakDomain `EmojiCurationCandidatesTests`·KeyboardCore `EmojiCandidateTests`.
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

    /// 검증 ⑤-1 참고 4 — 값 블롭이 깨져 조각이 빠지면 순번이 다른 이모지를 가리킬 수 있다.
    @Test("값 조각 수가 엔트리의 개수와 다르면 이름 일치를 믿지 않는다")
    func emojiCountMismatchDropsNameMatch() throws {
        let key = Data("자동차".utf8)
        let value = Data("🚕\u{1F}\u{1F}🚗".utf8)  // 빈 조각 하나 — split이 건너뛰어 조각 2개
        var file = Data("TDEM".utf8)
        for v in [UInt32(1), 1, 32] {
            withUnsafeBytes(of: v.littleEndian) { file.append(contentsOf: $0) }
        }
        // nameMatch 2 · count 3(선언) — 실제 조각은 2개라 2번째(🚗)가 맞는지 보장할 수 없다
        for v in [UInt32(0), UInt32(value.count) << 16 | UInt32(key.count), UInt32(key.count),
                  UInt32(3) << 16 | 2] {
            withUnsafeBytes(of: v.littleEndian) { file.append(contentsOf: $0) }
        }
        file.append(key)
        file.append(value)
        let url = try temporaryFile(file)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(BundledEmojiAnnotationIndex(url: url).annotation(for: "자동차")
                == EmojiAnnotation(emojis: ["🚕", "🚗"], nameMatch: nil))
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

    /// 손질 목록 v1(확정 결정 D8) — 기획자 초안 127개에서 1음절 8개(돈·물·책·피·꽃·뼈·곰·봄)를 뺀 119개.
    @Test("번들 목록은 override 10(막기 4)·fallback 109 = 119개다")
    func bundledCurationCounts() throws {
        let url = try #require(Bundle.module.url(forResource: "EmojiCuration", withExtension: "json"),
                               "리소스가 번들에 있어야 한다")
        let curation = BundledEmojiCurationRepository(url: url).curation()
        #expect(curation == BundledEmojiCurationRepository().curation())
        #expect(curation.overrides.count == 10)
        #expect(curation.overrides.filter { $0.value.isEmpty }.keys.sorted() == ["가면", "가지", "뒤로", "파리"])
        #expect(curation.fallbacks.count == 109)
        #expect(curation.overrides["맥주"] == "🍺", "D7")
    }

    /// 검증 ⑤-1 주의 1 — 값 검사를 호스트 런타임 `isEmojiPresentation`(이 Mac은 Unicode 17)으로 하면
    /// 🫩(U+1FAE9, Unicode 16 — iOS 17이 못 그림)이 통과한다. 변환기가 내보낸 Unicode 15.0 기준선으로 본다.
    @Test("번들 목록의 키는 한글 2~12자, 값은 iOS 17 기준선 안의 이모지다 — 빈 문자열은 override(막기)에만")
    func bundledCurationShape() throws {
        let curation = BundledEmojiCurationRepository().curation()
        let pattern = try Regex("[가-힣]{2,12}")
        for (section, entries) in [("override", curation.overrides), ("fallback", curation.fallbacks)] {
            for (word, emoji) in entries {
                #expect(word.wholeMatch(of: pattern) != nil, "\(section) 키: \(word)")
                if emoji.isEmpty {
                    #expect(section == "override", "fallback 빈 문자열은 뜻이 없다: \(word)")
                } else {
                    #expect(IOS17EmojiBaseline.contains(emoji), "\(section) 값: \(word) → \(emoji)")
                }
            }
        }
    }

    @Test("기준선은 Unicode 15.0 카탈로그 1,170개 — 16.0 이모지·텍스트 기본·피부색·ZWJ는 밖이다")
    func baselineFixture() {
        #expect(IOS17EmojiBaseline.count == 1_170)
        #expect(IOS17EmojiBaseline.ranges.reduce(0) { $0 + $1.count } == IOS17EmojiBaseline.count)
        #expect(IOS17EmojiBaseline.contains("🚗") && IOS17EmojiBaseline.contains("🩷"), "🩷는 15.0")
        for outside in ["\u{1FAE9}", "❤", "❤️", "🏻", "👍🏻", "👨‍👩‍👧", "🇰", "🍺🍻", "가"] {
            #expect(!IOS17EmojiBaseline.contains(outside), "밖이어야 한다: \(outside)")
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

/// 실제 `emoji.tde` + `EmojiCuration.json`으로 묶음 규칙(TadakDomain `EmojiCuration.candidates`)을 돌린다 —
/// 키보드가 쓸 값 그대로다(D9·D10). KeyboardCore `EmojiCandidateResolver`는 여기에 단어 꼴 검사만 더한다.
@Suite("이모지 후보 묶음 — 실제 번들 (D9·D10)")
struct BundledEmojiCandidateTests {

    private let index = BundledEmojiAnnotationIndex()
    private let curation = BundledEmojiCurationRepository().curation()

    private func bundle(_ word: String) -> [String] {
        curation.candidates(for: word, annotation: index.annotation(for: word))
    }

    @Test("「자동차」는 CLDR 후보 5개 전부 — 🚗·🚕 모두")
    func car() {
        #expect(bundle("자동차") == ["🚕", "🚗", "🚘", "🛻", "🛞"])
    }

    @Test("「맥주」 묶음에 🍺가 있다 — D7은 랜덤 안에서 흡수된다")
    func beer() {
        #expect(bundle("맥주") == ["🫚", "🍺", "🍻"])
    }

    @Test("막기 4개는 CLDR 후보가 있어도 빈 묶음이다", arguments: ["가지", "가면", "파리", "뒤로"])
    func blocked(word: String) {
        #expect(index.annotation(for: word) != nil, "CLDR에는 있다 — 막기가 일을 한다")
        #expect(bundle(word).isEmpty)
    }

    /// 브리프는 「치킨 [🍗]」로 적었지만 CLDR ko에 「치킨」 키(🐔)가 있다 — D9 합집합이라 둘 다 묶음이다.
    @Test("「치킨」은 CLDR 🐔 ∪ 손질 🍗, 역색인 밖 「콜라」는 손질 값 하나")
    func curationValues() {
        #expect(bundle("치킨") == ["🐔", "🍗"])
        #expect(index.annotation(for: "콜라") == nil)
        #expect(bundle("콜라") == ["🥤"])
    }

    @Test("「다이아몬드」 — tts ♦는 텍스트 기본이라 걸러지고, 묶음은 💍·💎 (기획자 가정 확인)")
    func diamond() {
        #expect(index.annotation(for: "다이아몬드") == EmojiAnnotation(emojis: ["💍", "💎"], nameMatch: nil))
        #expect(bundle("다이아몬드") == ["💍", "💎"])
    }

    @Test("「자동차는」은 빈 묶음이다 (Q5)")
    func particleForm() {
        #expect(bundle("자동차는").isEmpty)
    }

    @Test("손질 목록의 막기 아닌 키는 전부 묶음이 비어 있지 않고 그 값을 담는다 (전수)")
    func everyCuratedWordHasBundle() {
        var checked = 0
        for (word, emoji) in curation.overrides.merging(curation.fallbacks, uniquingKeysWith: { a, _ in a })
        where !emoji.isEmpty {
            let candidates = bundle(word)
            #expect(candidates.contains(emoji), "\(word) → \(emoji)")
            checked += 1
        }
        #expect(checked == 115, "119 − 막기 4")
    }
}
