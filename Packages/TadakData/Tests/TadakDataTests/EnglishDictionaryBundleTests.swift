import Foundation
import Testing
@testable import TadakData

// B5 영어 추천단어 — **최종 번들** `words-en.tdw` 시험(계획 `v1.3.1-plan.md` §3-8 E12·E17, PDR `english-word-suggestions.md`).
// 가짜 사전이 아니라 `Bundle.module`의 실제 산출물을 읽는다. 금칙어·철자 오류형 목록은 변환기 입력(`tools/data-en/`)을 그대로 읽어
// 「번들에 0」을 센다 — **단어를 실패 메시지에 내지 않는다**(개수만).

private enum EnglishBundle {
    static let url = Bundle.module.url(forResource: "words-en", withExtension: "tdw")
    static let dictionary = BundledWordDictionary(url: url)

    static func top(_ prefix: String, _ limit: Int = 3) -> [String] {
        dictionary.candidates(jamoPrefix: prefix, limit: limit).map(\.word)
    }

    /// 번들 안에 이 키가 **정확히** 있나(표시형 대소문자 무시)
    static func contains(_ key: String) -> Bool {
        dictionary.candidates(jamoPrefix: key, limit: 64).contains { $0.word.lowercased() == key }
    }

    /// 변환기 입력 목록(저장소 `tools/data-en/`) — 주석 줄 제외
    static func list(_ name: String) -> [String] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let text = (try? String(contentsOf: root.appendingPathComponent("tools/data-en/\(name)"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// 헤더 그대로 읽은 (항목 수, 키 목록) — 전수 검사용
    static func allKeys() -> [String] {
        guard let url, let data = try? Data(contentsOf: url), data.count >= 16 else { return [] }
        func u32(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24 }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        let count = u32(8), blob = u32(12)
        return (0..<count).map { index in
            let entry = 16 + index * 16
            let start = blob + u32(entry)
            return String(decoding: data[start..<start + u16(entry + 4)], as: UTF8.self)
        }
    }
}

@Suite("B5 E12 — 최종 번들 words-en.tdw")
struct EnglishDictionaryBundleTests {

    @Test("파일이 있고 항목은 2만 이하 · 키는 ASCII 소문자 · 앞 아포스트로피 없음 · 3~20자")
    func shape() {
        let keys = EnglishBundle.allKeys()
        #expect(EnglishBundle.url != nil)
        #expect(!keys.isEmpty && keys.count <= 20_000)
        let bad = keys.filter { key in
            !key.allSatisfy { $0.isASCII && ($0.isLowercase || $0 == "'") } || key.hasPrefix("'") || key.hasSuffix("'")
                || !(3...20).contains(key.count)
        }.count
        #expect(bad == 0)
        #expect(keys == keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }, "키 바이트 순 정렬(이진 탐색)")
    }

    @Test("hel → hello 포함, 후보는 빈도 내림차순")
    func helloAndOrder() {
        #expect(EnglishBundle.top("hel").contains("hello"))
        let frequencies = EnglishBundle.dictionary.candidates(jamoPrefix: "th", limit: 20).map(\.frequency)
        #expect(frequencies == frequencies.sorted(by: >))
    }

    @Test("금칙어 입력 목록·철자 오류형·비단어 목록의 단어가 번들에 0 (개수만 센다)")
    func blockedWordsAbsent() {
        for name in ["blocklist.txt", "misspellings.txt", "noise.txt"] {
            let words = EnglishBundle.list(name)
            #expect(!words.isEmpty, "\(name) 읽기")
            let leaked = words.filter(EnglishBundle.contains).count
            #expect(leaked == 0, "\(name)")
        }
    }

    @Test("어간 조각 14개·ain·don은 없고 축약형이 그 자리에 있다")
    func fragmentsReplaced() {
        let stems = ["didn", "doesn", "isn", "wasn", "wouldn", "haven", "couldn", "aren", "shouldn", "weren",
                     "hasn", "hadn", "mustn", "needn"]
        for stem in stems {
            #expect(!EnglishBundle.contains(stem), "\(stem)")
            #expect(EnglishBundle.contains(stem + "'t"), "\(stem)'t")
        }
        #expect(!EnglishBundle.contains("ain") && !EnglishBundle.contains("ain't"))
        #expect(!EnglishBundle.contains("don"))
        #expect(EnglishBundle.contains("won") && EnglishBundle.contains("won't"))
    }

    @Test("축약형·대문자 원형 — 사전 형태 그대로", arguments: [
        ("don", ["don't"]), ("did", ["didn't"]), ("i'", ["I'm", "I'll", "I've"]), ("it'", ["it's"]),
        ("cou", ["could", "course", "couldn't"]), ("mond", ["Monday"]), ("iph", ["iPhone"])
    ] as [(String, [String])])
    func curatedForms(row: (prefix: String, expected: [String])) {
        let top = EnglishBundle.top(row.prefix)
        for word in row.expected { #expect(top.contains(word), "\(row.prefix) → \(top)") }
    }

    @Test("파일이 없으면 빈 사전 — 조회가 빈 배열")
    func missingFileIsEmpty() {
        #expect(BundledWordDictionary(url: nil).candidates(jamoPrefix: "hel", limit: 3).isEmpty)
    }
}

/// 기획자 합성 접두 표(`docs/release/b5-data/synthetic-prefix-table.tsv`, 107행 — 구현자와 독립) — (범주, 원하는 완성어, 3자, 4자)
private let syntheticPrefixes: [(String, String, String, String?)] = [
        ("메신저·일상", "thanks", "tha", "than"),
        ("메신저·일상", "please", "ple", "plea"),
        ("메신저·일상", "sorry", "sor", nil),
        ("메신저·일상", "tomorrow", "tom", "tomo"),
        ("메신저·일상", "today", "tod", nil),
        ("메신저·일상", "tonight", "ton", "toni"),
        ("메신저·일상", "morning", "mor", "morn"),
        ("메신저·일상", "evening", "eve", "even"),
        ("메신저·일상", "weekend", "wee", "week"),
        ("메신저·일상", "because", "bec", "beca"),
        ("메신저·일상", "really", "rea", "real"),
        ("메신저·일상", "probably", "pro", "prob"),
        ("메신저·일상", "definitely", "def", "defi"),
        ("메신저·일상", "actually", "act", "actu"),
        ("메신저·일상", "maybe", "may", nil),
        ("메신저·일상", "anyway", "any", "anyw"),
        ("메신저·일상", "whatever", "wha", "what"),
        ("메신저·일상", "welcome", "wel", "welc"),
        ("메신저·일상", "congratulations", "con", "cong"),
        ("메신저·일상", "birthday", "bir", "birt"),
        ("메신저·일상", "happy", "hap", nil),
        ("메신저·일상", "awesome", "awe", "awes"),
        ("메신저·일상", "amazing", "ama", "amaz"),
        ("메신저·일상", "beautiful", "bea", "beau"),
        ("메신저·일상", "wonderful", "won", "wond"),
        ("메신저·일상", "excellent", "exc", "exce"),
        ("메신저·일상", "appreciate", "app", "appr"),
        ("메신저·일상", "remember", "rem", "reme"),
        ("메신저·일상", "everything", "eve", "ever"),
        ("메신저·일상", "something", "som", "some"),
        ("메신저·일상", "together", "tog", "toge"),
        ("메신저·일상", "finally", "fin", "fina"),
        ("메신저·일상", "honestly", "hon", "hone"),
        ("메신저·일상", "unfortunately", "unf", "unfo"),
        ("검색", "weather", "wea", "weat"),
        ("검색", "restaurant", "res", "rest"),
        ("검색", "recipe", "rec", "reci"),
        ("검색", "directions", "dir", "dire"),
        ("검색", "tutorial", "tut", "tuto"),
        ("검색", "tickets", "tic", "tick"),
        ("검색", "discount", "dis", "disc"),
        ("검색", "reviews", "rev", "revi"),
        ("검색", "movies", "mov", "movi"),
        ("검색", "music", "mus", nil),
        ("검색", "pictures", "pic", "pict"),
        ("검색", "download", "dow", "down"),
        ("검색", "university", "uni", "univ"),
        ("검색", "hospital", "hos", "hosp"),
        ("검색", "airport", "air", "airp"),
        ("검색", "traffic", "tra", "traf"),
        ("검색", "translate", "tra", "tran"),
        ("검색", "address", "add", "addr"),
        ("검색", "hotel", "hot", nil),
        ("검색", "flight", "fli", "flig"),
        ("검색", "parking", "par", "park"),
        ("검색", "delivery", "del", "deli"),
        ("업무", "meeting", "mee", "meet"),
        ("업무", "schedule", "sch", "sche"),
        ("업무", "available", "ava", "avai"),
        ("업무", "deadline", "dea", "dead"),
        ("업무", "project", "pro", "proj"),
        ("업무", "report", "rep", "repo"),
        ("업무", "presentation", "pre", "pres"),
        ("업무", "document", "doc", "docu"),
        ("업무", "attached", "att", "atta"),
        ("업무", "regards", "reg", "rega"),
        ("업무", "invoice", "inv", "invo"),
        ("업무", "proposal", "pro", "prop"),
        ("업무", "confirm", "con", "conf"),
        ("업무", "feedback", "fee", "feed"),
        ("업무", "customer", "cus", "cust"),
        ("업무", "manager", "man", "mana"),
        ("업무", "department", "dep", "depa"),
        ("업무", "conference", "con", "conf"),
        ("업무", "budget", "bud", "budg"),
        ("업무", "contract", "con", "cont"),
        ("업무", "approval", "app", "appr"),
        ("한영 혼용", "phone", "pho", nil),
        ("한영 혼용", "email", "ema", nil),
        ("한영 혼용", "message", "mes", "mess"),
        ("한영 혼용", "video", "vid", nil),
        ("한영 혼용", "internet", "int", "inte"),
        ("한영 혼용", "website", "web", "webs"),
        ("한영 혼용", "application", "app", "appl"),
        ("한영 혼용", "online", "onl", "onli"),
        ("한영 혼용", "password", "pas", "pass"),
        ("한영 혼용", "service", "ser", "serv"),
        ("한영 혼용", "contact", "con", "cont"),
        ("한영 혼용", "profile", "pro", "prof"),
        ("축약형", "don't", "don", nil),
        ("축약형", "can't", "can", nil),
        ("축약형", "i'm", "i'", nil),
        ("축약형", "it's", "it", nil),
        ("축약형", "that's", "tha", "that"),
        ("축약형", "didn't", "did", "didn"),
        ("축약형", "doesn't", "doe", "does"),
        ("축약형", "won't", "won", nil),
        ("축약형", "you're", "you", "you'"),
        ("축약형", "i'll", "i'", nil),
        ("축약형", "i've", "i'", nil),
        ("축약형", "wouldn't", "wou", "woul"),
        ("축약형", "let's", "let", nil),
        ("요일·월", "monday", "mon", "mond"),
        ("요일·월", "wednesday", "wed", "wedn"),
        ("요일·월", "saturday", "sat", "satu"),
        ("요일·월", "january", "jan", "janu"),
        ("요일·월", "september", "sep", "sept")
]

@Suite("B5 E17 — 합성 접두 top-3 품질(최종 번들, 승인 기준)")
struct EnglishQualityGateTests {

    static func hit(_ prefix: String?, _ target: String) -> Bool? {
        guard let prefix else { return nil }
        return EnglishBundle.top(prefix).contains { $0.lowercased() == target.lowercased() }
    }

    /// 승인 기준(PDR 확정) — ① 4자 ≥ 80% ② 3자 ≥ 60% ③ 범주별 4자 ≥ 60% ④ 축약형 3자 13/13.
    /// ⑤ 상위 3에 조각·오류형·금칙어 0은 그 단어가 번들에 아예 없음(E12 `blockedWordsAbsent`·`fragmentsReplaced`)으로 성립한다
    @Test("승인 기준 ①~④")
    func approval() {
        let three = syntheticPrefixes.map { Self.hit($0.2, $0.1) ?? false }
        let four = syntheticPrefixes.compactMap { Self.hit($0.3, $0.1) }
        let threeRate = Double(three.filter { $0 }.count) / Double(three.count)
        let fourRate = Double(four.filter { $0 }.count) / Double(four.count)
        #expect(syntheticPrefixes.count == 107)
        #expect(fourRate >= 0.80, "4자 \(four.filter { $0 }.count)/\(four.count)")
        #expect(threeRate >= 0.60, "3자 \(three.filter { $0 }.count)/\(three.count)")
        for category in Set(syntheticPrefixes.map(\.0)) {
            let rows = syntheticPrefixes.filter { $0.0 == category }.compactMap { Self.hit($0.3, $0.1) }
            guard !rows.isEmpty else { continue }
            let rate = Double(rows.filter { $0 }.count) / Double(rows.count)
            #expect(rate >= 0.60, "\(category) 4자 \(rows.filter { $0 }.count)/\(rows.count)")
        }
        let contractions = syntheticPrefixes.filter { $0.0 == "축약형" }
        #expect(contractions.count == 13)
        #expect(contractions.allSatisfy { Self.hit($0.2, $0.1) == true }, "축약형 3자")
    }
}
