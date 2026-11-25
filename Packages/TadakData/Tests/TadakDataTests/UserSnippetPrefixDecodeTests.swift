import Testing
import Foundation
@testable import TadakData
import TadakDomain

/// B1 가′ — 내 채움글 앞부분 디코드(PDR `keyboard-user-snippet-prefix-decode.md`).
///
/// 기준은 **지금 경로**(배열 전체 디코드 → `userSnippetLoad`)다. 새 경로는 그것과 같은 항목·같은 판정을 내야 하고(I1),
/// 디코드는 많아야 실을 개수 + 1번(I2)이다. 내 채움글 문자열은 전부 시험 상수·합성값이다.
@Suite("내 채움글 앞부분 디코드 (B1 가′)")
struct UserSnippetPrefixDecodeTests {

    // MARK: - 합성 데이터

    /// 시드 고정 난수(SplitMix64)
    struct Random {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
    }

    /// 경계를 헷갈리게 하는 조각 — 따옴표·역슬래시·괄호·쉼표·제어 문자·이모지(가족·국기)·결합 한글·`/`
    static let fragments = [
        "가", "집", "주소", " ", "\"", "\\", "]", "[", "}", "{", ",", ":", "\n", "\t", "\r", "\u{0}", "\u{1F}", "/",
        "👨‍👩‍👧‍👦", "🇰🇷", "🎉", "\u{1100}\u{1161}", "é", "\u{FEFF}", "abc", "\\u0041", "null", "true", "<>&'",
    ]

    static func text(_ random: inout Random, maxPieces: Int) -> String {
        (0..<random.below(maxPieces + 1)).map { _ in fragments[random.below(fragments.count)] }.joined()
    }

    static func entries(_ random: inout Random) -> [SnippetEntry] {
        (0..<random.below(40)).map { _ in
            let triggers = (0..<random.below(4)).map { _ in text(&random, maxPieces: 4) }
            return SnippetEntry(triggers: triggers, title: text(&random, maxPieces: 6), body: text(&random, maxPieces: 30))
        }
    }

    static func limits(_ random: inout Random) -> PackBudgetLimits {
        var limits = PackBudgetLimits.candidate
        switch random.below(4) {
        case 0: break
        case 1: limits.bytes = 20 + random.below(3_000)
        case 2: limits.items = random.below(12)
        default: limits.needleChars = random.below(60)
        }
        return limits
    }

    static func encoders() -> [JSONEncoder] {
        let plain = JSONEncoder()
        let pretty = JSONEncoder()
        pretty.outputFormatting = [.prettyPrinted, .sortedKeys]
        let unescaped = JSONEncoder()
        unescaped.outputFormatting = [.withoutEscapingSlashes]
        return [plain, pretty, unescaped]
    }

    /// 지금 경로 — 전체 디코드 뒤 한 번
    static func reference(_ data: Data, builtIn: PackStats, limits: PackBudgetLimits) -> UserSnippetSupply {
        let all = (try? JSONDecoder().decode([SnippetEntry].self, from: data)) ?? []
        return .full(all, builtIn: builtIn, limits: limits)
    }

    static func raw(_ entry: SnippetEntry) -> Int {
        entry.triggers.reduce(entry.title.utf8.count + entry.body.utf8.count) { $0 + $1.utf8.count }
    }

    // MARK: - I1 왕복 동등

    @Test("★ I1 — 무작위 내 채움글을 인코딩해 앞부분 디코드하면 전체 디코드 경로와 같은 항목·같은 판정")
    func roundTripMatchesFullDecode() throws {
        var random = Random(state: 0x2026_1020)
        var stoppedEarly = 0
        for _ in 0..<600 {
            let entries = Self.entries(&random)
            let limits = Self.limits(&random)
            let builtIn = PackStats(needleCount: random.below(5), needleChars: random.below(20), bytes: random.below(400),
                                    items: random.below(5))
            for encoder in Self.encoders() {
                let data = try encoder.encode(entries)
                let supply = UserSnippetPrefixDecoder.supply(from: data, builtIn: builtIn, limits: limits)
                let expected = Self.reference(data, builtIn: builtIn, limits: limits)
                #expect(supply == expected)
                if supply.entries.count < entries.count { stoppedEarly += 1 }
            }
        }
        #expect(stoppedEarly > 100, "넘어서 멈추는 경우가 충분히 섞여야 시험이 뜻을 갖는다")
    }

    @Test("★ 하한 — JSONEncoder 출력에서 원소별 하한이 디코드한 항목의 원시 바이트와 같다(이스케이프를 정확히 푼다)")
    func lowerBoundEqualsRawBytes() throws {
        var random = Random(state: 7)
        for _ in 0..<300 {
            let entries = Self.entries(&random)
            for encoder in Self.encoders() {
                let elements = try #require(JSONElementScanner.topLevelElements(of: try encoder.encode(entries)))
                #expect(elements.map(\.rawUTF8LowerBound) == entries.map(Self.raw))
            }
        }
    }

    // MARK: - I2 디코드 상한

    @Test("★ I2 — 맨 앞 10MB 한 항목은 디코드 0번으로 「초과」(codex M-2)")
    func giantFirstEntryIsNeverDecoded() throws {
        let giant = SnippetEntry(trigger: "큰것", title: "t", body: String(repeating: "가", count: 3_500_000))   // 10.5MB
        let data = try JSONEncoder().encode([giant, SnippetEntry(trigger: "집", title: "집", body: "서울")])
        var decodes = 0
        let supply = UserSnippetPrefixDecoder.supply(from: data, builtIn: .zero, limits: .candidate) {
            decodes += 1
            return try? JSONDecoder().decode(SnippetEntry.self, from: $0)
        }
        #expect(decodes == 0)
        #expect(supply.entries.isEmpty && supply.load.loadableCount == 0)
        #expect(!supply.load.overflowDimensions.isEmpty)
        #expect(supply == Self.reference(data, builtIn: .zero, limits: .candidate))
    }

    @Test("★ I2 — 디코드는 많아야 실을 개수 + 1번, 넘은 뒤 원소는 디코드하지 않는다")
    func decodesAtMostLoadablePlusOne() throws {
        var random = Random(state: 99)
        for _ in 0..<200 {
            let entries = Self.entries(&random)
            var limits = PackBudgetLimits.candidate
            limits.bytes = 50 + random.below(1_500)
            let data = try JSONEncoder().encode(entries)
            var decodes = 0
            let supply = UserSnippetPrefixDecoder.supply(from: data, builtIn: .zero, limits: limits) {
                decodes += 1
                return try? JSONDecoder().decode(SnippetEntry.self, from: $0)
            }
            #expect(decodes <= min(entries.count, supply.load.loadableCount + 1))
        }
    }

    @Test("중간의 거대 항목 — 그 앞까지 싣고 그 항목은 디코드하지 않는다")
    func giantMiddleEntryStopsBeforeDecode() throws {
        let small = SnippetEntry(trigger: "집", title: "우리 집", body: "서울시 어딘가 1")
        let giant = SnippetEntry(trigger: "큰것", title: "t", body: String(repeating: "a", count: 3_100_000))
        let data = try JSONEncoder().encode([small, small, giant, small])
        var decodes = 0
        let supply = UserSnippetPrefixDecoder.supply(from: data, builtIn: .zero, limits: .candidate) {
            decodes += 1
            return try? JSONDecoder().decode(SnippetEntry.self, from: $0)
        }
        #expect(decodes == 2)
        #expect(supply.entries == [small, small])
        #expect(supply == Self.reference(data, builtIn: .zero, limits: .candidate))
    }

    // MARK: - 손으로 쓴 JSON

    static func decodeHand(_ json: String, limits: PackBudgetLimits = .candidate) -> (UserSnippetSupply, UserSnippetSupply) {
        let data = Data(json.utf8)
        return (UserSnippetPrefixDecoder.supply(from: data, builtIn: .zero, limits: limits),
                Self.reference(data, builtIn: .zero, limits: limits))
    }

    @Test("손으로 쓴 정상 JSON — 옛 trigger 키·키 순서·공백·중복 키·null·모르는 키·\\u 이스케이프", arguments: [
        #"[{"trigger":"집","title":"우리 집","body":"서울"}]"#,
        #" [ { "body" : "서울" , "title":"t" , "triggers" : [ "a" , "b" ] } , {"title":"x"} ] "#,
        #"[{"triggers":null,"trigger":"집","title":"t","body":"b"}]"#,
        #"[{"triggers":[],"trigger":"집","title":"t","body":"b"}]"#,
        #"[{"title":"a","title":"bb","body":"c"}]"#,
        #"[{"triggers":["a"],"triggers":["bbbb"],"trigger":"c","body":"d"}]"#,
        #"[{"extra":{"n":[1,-2.5e+3,true,false,null,{"]":"["}]},"title":"t","body":"Aé中🎉"}]"#,
        #"[{"\u0074itle":"이스케이프 키","body":"b"}]"#,
        #"[{"title":"\ud800 짝 없는 서로게이트","body":"b"}]"#,
        #"[]"#,
    ])
    func handWrittenValidJSON(json: String) {
        var tight = PackBudgetLimits.candidate
        tight.bytes = 30
        for limits in [PackBudgetLimits.candidate, tight] {
            let (supply, expected) = Self.decodeHand(json, limits: limits)
            #expect(supply == expected, "\(json)")
        }
    }

    /// 검증 F1 — 키의 `\b \f \n \r \t` 이스케이프는 **푼 값(제어 문자)**으로 비교해야 한다. 글자(b·f·n·r·t)로 담으면
    /// `"\title"`(탭 + itle)을 `title` 필드로 세어 하한이 원시 바이트보다 커지고, 옛 경로(1개·한도 안)와 달리 「0개 + 초과」가 된다.
    /// 이 키들은 디코더에게 모르는 키다. 마지막 줄은 글자로 담아도 필드 이름이 되지 않는 키(대조군 — 고치기 전에도 통과한다)
    @Test("★ F1 — 제어 문자 이스케이프 키(\\title·\\trigger·\\triggers·\\body)는 필드로 세지 않는다", arguments: [
        #"[{"KEYtitle":"LONG","body":"b"}]"#,
        #"[{"KEYtrigger":"LONG","body":"b"}]"#,
        #"[{"KEYtriggers":["LONG"],"body":"b"}]"#,
        #"[{"title":"t","KEYbody":"LONG"}]"#,
        #"[{"KEYnbody":"LONG","KEYrtitle":"LONG","KEYftrigger":"LONG","body":"b"}]"#,
    ])
    func escapedControlKeysAreNotFields(template: String) throws {
        let json = template.replacingOccurrences(of: "KEY", with: "\\")
            .replacingOccurrences(of: "LONG", with: String(repeating: "가", count: 20))   // 60B — 필드로 세면 tight 한도(60B)를 넘는다
        let data = Data(json.utf8)
        let elements = try #require(JSONElementScanner.topLevelElements(of: data))
        let decoded = try JSONDecoder().decode([SnippetEntry].self, from: data)
        #expect(elements.map(\.rawUTF8LowerBound) == decoded.map(Self.raw), "하한이 원시 바이트와 같아야 한다 — \(json)")
        var tight = PackBudgetLimits.candidate
        tight.bytes = 60   // 그 항목의 직렬화(약 40B)는 들어간다
        for limits in [PackBudgetLimits.candidate, tight] {
            let (supply, expected) = Self.decodeHand(json, limits: limits)
            #expect(supply == expected, "\(json)")
            #expect(supply.entries.count == 1, "\(json)")
        }
    }

    /// 문법 손상은 새 경로에서 0개다(RFC 8259 그대로). **옛 경로와 늘 같지는 않다**(검증 F3) — 후행 쉼표(`[{"title":"t",}]`·
    /// `[{"title":"t"},]`)와 비표준 숫자(`01`·`1.`·`-`)는 macOS(Xcode 27) Foundation의 옛 경로가 관대하게 받아 1개였다.
    /// 앱 `JSONEncoder` 저장분에는 없는 입력이다 — PDR 엣지케이스 표
    @Test("손상 → 0개", arguments: [
        "", " ", "{}", "\"집\"", "[", "[{]", #"[{"title":"t"}"#, #"[{"title":"t"}]x"#, #"[{"title":"t",}]"#,
        #"[{"title":"t"},]"#, #"[{"title":"\x"}]"#, #"[{"title":"\u12"}]"#, "[{\"title\":\"a\nb\"}]",
        #"[{"title":01}]"#, #"[{"title":-}]"#, #"[{"title":1.}]"#, #"[{"title":tru}]"#, #"[{"title" "t"}]"#,
    ])
    func corruptIsEmpty(json: String) {
        let supply = UserSnippetPrefixDecoder.supply(from: Data(json.utf8), builtIn: .zero, limits: .candidate)
        #expect(supply == .full([], builtIn: .zero, limits: .candidate), "\(json)")
    }

    @Test("손상 — 너무 깊은 중첩은 0개(스택 보호)")
    func tooDeepIsEmpty() {
        let depth = JSONElementScanner.maxDepth + 5
        let json = "[{\"x\":" + String(repeating: "[", count: depth) + String(repeating: "]", count: depth) + "}]"
        let supply = UserSnippetPrefixDecoder.supply(from: Data(json.utf8), builtIn: .zero, limits: .candidate)
        #expect(supply.entries.isEmpty)
    }

    @Test("쓰는 원소의 필드 타입 오류는 0개(지금과 같다)")
    func schemaErrorInUsedPrefixIsEmpty() {
        let (supply, expected) = Self.decodeHand(#"[{"title":"a","body":"b"},{"title":3,"body":"c"}]"#)
        #expect(supply.entries.isEmpty)
        #expect(supply == expected)
    }

    @Test("받아들인 차이 — 멈춘 자리 뒤 원소의 필드 타입 오류는 보지 않고 앞부분을 싣는다(지금은 0개)")
    func schemaErrorAfterCutoffKeepsPrefix() {
        var limits = PackBudgetLimits.candidate
        limits.items = 1
        let (supply, expected) = Self.decodeHand(#"[{"title":"a","body":"b"},{"title":"c"},{"title":3}]"#, limits: limits)
        #expect(supply.entries == [SnippetEntry(triggers: [], title: "a", body: "b")])
        #expect(!supply.load.overflowDimensions.isEmpty)
        #expect(expected.entries.isEmpty, "지금 경로는 전체 디코드가 실패해 0개 — 이 차이를 PDR이 받아들였다")
    }

    // MARK: - 로더 — 판정을 다시 세지 않는다(I1) · 재시도 재사용(R1-9)

    final class ScriptedGenerations: PackGenerationReading, @unchecked Sendable {
        private let lock = NSLock()
        private var userReads = 0
        private var packsReads = 0
        let user: @Sendable (Int) -> Int
        let packs: @Sendable (Int) -> Int
        init(user: @escaping @Sendable (Int) -> Int = { _ in 1 }, packs: @escaping @Sendable (Int) -> Int = { _ in 0 }) {
            self.user = user
            self.packs = packs
        }
        var userSnippetsGeneration: Int { lock.withLock { userReads += 1; return user(userReads) } }
        var packsGeneration: Int { lock.withLock { packsReads += 1; return packs(packsReads) } }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() { lock.withLock { value += 1 } }
        var count: Int { lock.withLock { value } }
    }

    static let emptyRoot = FileManager.default.temporaryDirectory.appendingPathComponent("b1-prefix-\(UUID().uuidString)")

    @Test("★ I1 — 넘어서 멈춘 판정을 로더가 그대로 쓴다: baseline 초과면 외부 팩을 읽지 않는다")
    func loaderKeepsStoppedVerdict() throws {
        let small = SnippetEntry(trigger: "집", title: "우리 집", body: "서울시 어딘가 1")
        var limits = PackBudgetLimits.candidate
        limits.items = 2
        let data = try JSONEncoder().encode(Array(repeating: small, count: 5))
        // 팩 세대 1 — 판정을 잘못 「맞음」으로 다시 세면 snapshot을 읽으러 가서 소실(vanished)로 끝난다
        let loader = PackSnapshotLoader(snapshotRoot: Self.emptyRoot, generations: ScriptedGenerations(packs: { _ in 1 }),
                                        userSnippetData: { data }, limits: limits)
        let result = loader.load(builtIn: [])
        #expect(result.userEntries == [small, small])
        #expect(!result.baselineOverflow.isEmpty)
        #expect(result.dropped == nil && result.packFilesRead == 0 && result.attempts == 1)
    }

    @Test("★ R1-9 — 팩 세대만 흔들리면 재시도는 내 채움글을 다시 읽지 않는다")
    func retryReusesWhenUserGenerationUnchanged() throws {
        let data = try JSONEncoder().encode([SnippetEntry(trigger: "집", title: "집", body: "서울")])
        let reads = Counter()
        // 첫 회: 앞 0 → 뒤 1(어긋남). 그 뒤 세대 1이지만 snapshot이 없어 소실 → 3회째까지
        let loader = PackSnapshotLoader(snapshotRoot: Self.emptyRoot,
                                        generations: ScriptedGenerations(packs: { $0 >= 2 ? 1 : 0 }),
                                        userSnippetData: { reads.increment(); return data })
        let result = loader.load(builtIn: [])
        #expect(result.attempts == 3 && result.dropped == .vanished)
        #expect(reads.count == 1)
        #expect(result.userEntries == [SnippetEntry(trigger: "집", title: "집", body: "서울")])
    }

    @Test("★ R1-9 — 읽는 도중 사용자 세대가 바뀌면 다음 회는 다시 읽는다")
    func retryRereadsWhenUserGenerationChanges() throws {
        let data = try JSONEncoder().encode([SnippetEntry(trigger: "집", title: "집", body: "서울")])
        let reads = Counter()
        let loader = PackSnapshotLoader(snapshotRoot: Self.emptyRoot,
                                        generations: ScriptedGenerations(user: { $0 }),   // 읽을 때마다 오른다
                                        userSnippetData: { reads.increment(); return data })
        let result = loader.load(builtIn: [])
        #expect(result.attempts == 3 && result.dropped == .inconsistentGenerations)
        #expect(reads.count == 3)
        #expect(result.userEntries.count == 1)
    }

    @Test("데이터 없음 — 0개, 실패하지 않는다")
    func missingDataIsEmpty() {
        let loader = PackSnapshotLoader(snapshotRoot: Self.emptyRoot, generations: ScriptedGenerations(),
                                        userSnippetData: { nil })
        let result = loader.load(builtIn: [])
        #expect(result.userEntries.isEmpty && result.baselineOverflow.isEmpty && result.dropped == nil)
    }
}
