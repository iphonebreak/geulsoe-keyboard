import Foundation
import Testing
import HangulEngine
import TadakDomain
@testable import KeyboardCore

/// 외부 팩 템플릿 매칭·소유권 (PDR `external-snippet-packs.md` 10-4·10-5, AC-24 · AC-25).
/// `SnippetMatcher` 배선(분기 순서 — 문구 → 내장 → 날짜 → 템플릿 → 성경)은 1-b다.
@Suite("템플릿 매칭 (10-5, AC-25)")
struct PackTemplateMatcherTests {

    private static func template(_ specs: [(String, String)], items: [Int], format: String = "사자성어 {n}번") -> PackTemplate {
        PackTemplate(patterns: specs.map { TemplatePattern(prefix: $0.0, suffix: $0.1) }, titleFormat: format,
                     items: items.map { PackTemplateItem(n: $0, title: $0 == 7 ? "" : "제목 \($0)", body: "본문 \($0)") })
    }

    private let matcher = PackTemplateMatcher(sources: [
        .init(id: "A", template: template([("사자성어", "번"), ("성어", "번")], items: [1, 7, 12, 232, 323]))
    ])

    @Test("꼬리에서 틀을 찾아 소유 팩의 n — 지울 길이는 꼬리에서 잘라낸 원문 구간(공백 포함)")
    func basic() throws {
        let match = try #require(matcher.match(tail: "오늘은 사자성어 12번"))
        #expect(match == PackTemplateMatcher.Match(sourceID: "A", n: 12, trigger: "사자성어 12번", title: "제목 12", body: "본문 12"))
    }

    @Test("별칭으로도 맞는다 — 둘 다 맞으면 literal이 긴 쪽(사자성어)이 이긴다")
    func aliasAndLongestLiteral() throws {
        #expect(matcher.match(tail: "성어12번")?.trigger == "성어12번")
        #expect(matcher.match(tail: "사자성어12번")?.trigger == "사자성어12번")
    }

    @Test("숫자열 전체 소비 — 후퇴 없음·선행 0 금지·5자리 이상 거부", arguments: [
        "사자성어3232번", "사자성어0012번", "사자성어012번", "사자성어12345번", "사자성어번"
    ])
    func digitsConsumedWhole(tail: String) {
        #expect(matcher.match(tail: tail) == nil)
    }

    @Test("제목이 빈 항목은 `titleFormat`의 `{n}`을 채운다")
    func titleFallback() {
        #expect(matcher.match(tail: "사자성어 7번")?.title == "사자성어 7번")
    }

    @Test("줄바꿈에서 멈춘다 — 다른 줄과 붙지 않는다")
    func stopsAtNewline() {
        #expect(matcher.match(tail: "사자성어\n12번") == nil)
        #expect(matcher.match(tail: "다른 줄\n사자성어12번")?.trigger == "사자성어12번")
    }

    @Test("최대 확장 44자(literal 40 + 4자리)가 꼬리 48자 안에서 맞는다")
    func longestExpansion() throws {
        let prefix = String(repeating: "가", count: 39)
        let wide = PackTemplateMatcher(sources: [.init(id: "W", template: Self.template([(prefix, "번")], items: [9_999]))])
        let match = try #require(wide.match(tail: "xx" + prefix + "9999번"))
        #expect(match.trigger.count == 44 && match.n == 9_999)
    }

    @Test("지울 길이 = 원문 구간 — `insertSnippet`이 틀 원문만 지우고 본문을 넣는다")
    @MainActor
    func insertsThroughSnippetPath() throws {
        let output = RecordingOutput()
        let controller = InputController(output: output)
        controller.insertProvidedText("앞말 사자성어 12번")
        let match = try #require(matcher.match(tail: controller.textTail))
        #expect(controller.insertSnippet(match.suggestion))
        #expect(output.text == "앞말 본문 12")
    }

    /// AC-25 — 3종 자판으로 실제로 쳐서 꼬리를 만들고 같은 결과가 나온다
    @Test("3종 자판 입력 시퀀스 — 두벌식·천지인·단모음으로 「가나12장」을 치면 n=12", arguments: ["dubeolsik", "cheonjiin", "danmoeum"])
    @MainActor
    func threeLayouts(layout: String) throws {
        let source: JamoSource
        let prefixKeys: [String]
        let suffixKeys: [String]
        switch layout {
        case "cheonjiin":
            source = CheonjiinSource(timeout: 10)
            prefixKeys = ["ㄱ", "ㅣ", "ㆍ", "ㄴ", "ㅣ", "ㆍ"]
            suffixKeys = ["ㅈ", "ㅣ", "ㆍ", "ㅇ"]
        case "danmoeum":
            source = DanmoeumSource()
            prefixKeys = ["ㄱ", "ㅏ", "ㄴ", "ㅏ"]
            suffixKeys = ["ㅈ", "ㅏ", "ㅇ"]
        default:
            source = DubeolsikSource()
            prefixKeys = ["r", "k", "s", "k"]
            suffixKeys = ["w", "k", "d"]
        }
        let output = RecordingOutput()
        let controller = InputController(output: output, hangulSource: source)
        for key in prefixKeys { controller.handle(.character(key)) }
        controller.handle(.symbols)
        for key in ["1", "2"] { controller.handle(.character(key)) }
        controller.handle(.symbols)
        for key in suffixKeys { controller.handle(.character(key)) }
        #expect(controller.textTail == "가나12장")
        let matcher = PackTemplateMatcher(sources: [.init(id: "K", template: Self.template([("가나", "장")], items: [12], format: "가나 {n}장"))])
        let match = try #require(matcher.match(tail: controller.textTail))
        #expect(match.n == 12 && match.trigger == "가나12장")
        #expect(controller.insertSnippet(match.suggestion))
        #expect(output.text == "본문 12")
    }

    /// 검증 T4 — AC-25 「숫자열 전체·후퇴 없음·선행 0·44자」를 꼬리 주입이 아니라 3종 자판으로 실제로 쳐서
    private static let syllableKeys: [String: [String: [String]]] = [
        "dubeolsik": ["가": ["r", "k"], "나": ["s", "k"], "장": ["w", "k", "d"]],
        "cheonjiin": ["가": ["ㄱ", "ㅣ", "ㆍ"], "나": ["ㄴ", "ㅣ", "ㆍ"], "장": ["ㅈ", "ㅣ", "ㆍ", "ㅇ"]],
        "danmoeum": ["가": ["ㄱ", "ㅏ"], "나": ["ㄴ", "ㅏ"], "장": ["ㅈ", "ㅏ", "ㅇ"]]
    ]

    /// `prefix`(한글) → 기호 자판에서 `digits` → `suffix`(한글)를 그 자판으로 친다
    @MainActor
    private static func typed(_ layout: String, prefix: [String], digits: String, suffix: [String]) -> (InputController, RecordingOutput) {
        let source: JamoSource = switch layout {
        case "cheonjiin": CheonjiinSource(timeout: 10)
        case "danmoeum": DanmoeumSource()
        default: DubeolsikSource()
        }
        let keys = syllableKeys[layout] ?? [:]
        let output = RecordingOutput()
        let controller = InputController(output: output, hangulSource: source)
        for syllable in prefix { for key in keys[syllable] ?? [] { controller.handle(.character(key)) } }
        controller.handle(.symbols)
        for digit in digits { controller.handle(.character(String(digit))) }
        controller.handle(.symbols)
        for syllable in suffix { for key in keys[syllable] ?? [] { controller.handle(.character(key)) } }
        return (controller, output)
    }

    @Test("3종 자판 — 숫자열 전체 소비(3232는 32로 후퇴하지 않는다)·선행 0 거부 (AC-25 · T4)", arguments: ["dubeolsik", "cheonjiin", "danmoeum"])
    @MainActor
    func threeLayoutsDigitRules(layout: String) throws {
        let (whole, _) = Self.typed(layout, prefix: ["가", "나"], digits: "3232", suffix: ["장"])
        #expect(whole.textTail == "가나3232장")
        let only32 = PackTemplateMatcher(sources: [.init(id: "K", template: Self.template([("가나", "장")], items: [32]))])
        #expect(only32.match(tail: whole.textTail) == nil)
        let has3232 = PackTemplateMatcher(sources: [.init(id: "K", template: Self.template([("가나", "장")], items: [32, 3_232]))])
        #expect(has3232.match(tail: whole.textTail)?.n == 3_232)

        let (leadingZero, _) = Self.typed(layout, prefix: ["가", "나"], digits: "012", suffix: ["장"])
        #expect(leadingZero.textTail == "가나012장")
        let has12 = PackTemplateMatcher(sources: [.init(id: "K", template: Self.template([("가나", "장")], items: [12]))])
        #expect(has12.match(tail: leadingZero.textTail) == nil)
    }

    @Test("3종 자판 — 최대 확장 44자(접두 39 + 4자리 + 접미 1)를 쳐서 틀 원문 44자를 지우고 본문을 넣는다 (AC-25 · T4)",
          arguments: ["dubeolsik", "cheonjiin", "danmoeum"])
    @MainActor
    func threeLayoutsLongestExpansion(layout: String) throws {
        let prefix = Array(repeating: "가", count: 39)
        let (controller, output) = Self.typed(layout, prefix: prefix, digits: "9999", suffix: ["장"])
        #expect(controller.textTail == prefix.joined() + "9999장")
        let matcher = PackTemplateMatcher(sources: [.init(id: "W", template: Self.template([(prefix.joined(), "장")], items: [9_999]))])
        let match = try #require(matcher.match(tail: controller.textTail))
        #expect(match.n == 9_999 && match.trigger.count == 44)
        #expect(controller.insertSnippet(match.suggestion))
        #expect(output.text == "본문 9999")
    }
}

@Suite("소유권·동점·순서 (10-4, AC-24)")
struct PackTemplateOwnershipTests {

    private static func source(_ id: String, _ prefix: String, _ suffix: String, items: [Int]) -> PackTemplateMatcher.Source {
        .init(id: id, template: PackTemplate(patterns: [TemplatePattern(prefix: prefix, suffix: suffix)], titleFormat: "\(prefix) {n}\(suffix)",
                                             items: items.map { PackTemplateItem(n: $0, title: "\(id)\($0)", body: "\(id) 본문 \($0)") }))
    }

    @Test("같은 (접두,접미) 쌍은 목록 순서의 첫 팩이 소유 — 뒤 팩은 「후순위」로 표시")
    func firstInOrderOwns() {
        let matcher = PackTemplateMatcher(sources: [Self.source("A", "사자성어", "번", items: [1]), Self.source("B", "사자성어", "번", items: [1, 2])])
        #expect(matcher.match(tail: "사자성어1번")?.sourceID == "A")
        #expect(matcher.ownership == [
            .init(sourceID: "A", pattern: TemplatePattern(prefix: "사자성어", suffix: "번"), status: .owned),
            .init(sourceID: "B", pattern: TemplatePattern(prefix: "사자성어", suffix: "번"), status: .outranked(by: "A"))
        ])
    }

    @Test("소유 팩에 n이 없으면 nil — 다른 팩·다른 판본으로 후퇴하지 않는다")
    func noFallback() {
        let matcher = PackTemplateMatcher(sources: [Self.source("A", "사자성어", "번", items: [1]), Self.source("B", "사자성어", "번", items: [1, 2])])
        #expect(matcher.match(tail: "사자성어2번") == nil)
    }

    @Test("순서를 바꾸면 소유권이 다시 판정된다(U1 — 목록 순서)")
    func reorderChangesOwner() {
        let matcher = PackTemplateMatcher(sources: [Self.source("B", "사자성어", "번", items: [1, 2]), Self.source("A", "사자성어", "번", items: [1])])
        #expect(matcher.match(tail: "사자성어2번")?.sourceID == "B")
        #expect(matcher.ownership.last?.status == .outranked(by: "B"))
    }

    @Test("서로 다른 쌍이 겹치면 literal이 긴 쪽 — 그 소유 팩에 n이 없으면 짧은 쪽으로 후퇴하지 않는다")
    func longerPairWinsWithoutFallback() {
        let matcher = PackTemplateMatcher(sources: [Self.source("S", "사자성어", "번", items: [5]), Self.source("L", "새사자성어", "번", items: [1])])
        #expect(matcher.match(tail: "새사자성어 1번")?.sourceID == "L")
        #expect(matcher.match(tail: "새사자성어 5번") == nil)
        #expect(matcher.match(tail: "옛 사자성어 5번")?.sourceID == "S")
    }

    @Test("같은 팩 안의 같은 쌍은 한 번만 — 패턴 순서가 팩 내부 순서")
    func patternOrderWithinPack() {
        let template = PackTemplate(patterns: [TemplatePattern(prefix: "사자성어", suffix: "번"), TemplatePattern(prefix: "성어", suffix: "번")],
                                    titleFormat: "사자성어 {n}번", items: [PackTemplateItem(n: 1, title: "t", body: "b")])
        let matcher = PackTemplateMatcher(sources: [.init(id: "A", template: template)])
        #expect(matcher.ownership.map(\.pattern) == template.patterns)
        #expect(matcher.ownership.allSatisfy { $0.status == .owned })
    }
}
