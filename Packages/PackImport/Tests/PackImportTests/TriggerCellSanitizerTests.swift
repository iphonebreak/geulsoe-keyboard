import Foundation
import Testing
import TadakDomain
@testable import PackImport

/// 단축어 셀 파서 한 곳 (5-4, AC-15) · 문자 정리 (11절 / v2 10-3).
@Suite("TriggerCell (5-4, AC-15)")
struct TriggerCellTests {

    @Test("쉼표 또는 LF로 나누고 trim·빈 것 제거 — 결과에 개행이 없다", arguments: [
        ("가,나", ["가", "나"]),
        ("가\n나", ["가", "나"]),
        (" 가 ,\n 나 \n,", ["가", "나"]),
        ("주소\n인사", ["주소", "인사"]),
        ("우리집 주소", ["우리집 주소"])
    ])
    func splits(testCase: (cell: String, expected: [String])) throws {
        let triggers = try TriggerCell.parse(testCase.cell).get()
        #expect(triggers == testCase.expected)
        #expect(triggers.allSatisfy { !$0.contains("\n") })
    }

    @Test("정규화 기준 중복 제거 — 원문(먼저 나온 것)을 남긴다, 정규화는 `SnippetEntry.normalizedTrigger`")
    func dedupeByNormalizedTrigger() throws {
        #expect(try TriggerCell.parse("우리집 주소,우리집주소,우 리 집 주 소").get() == ["우리집 주소"])
    }

    @Test("항목당 10개·단축어 40자(원문) 상한")
    func limits() {
        let ten = (1...10).map { "s\($0)" }.joined(separator: ",")
        #expect((try? TriggerCell.parse(ten).get())?.count == 10)
        #expect(TriggerCell.parse(ten + ",s11") == .failure(.tooMany))
        #expect((try? TriggerCell.parse(String(repeating: "가", count: 40)).get()) != nil)
        #expect(TriggerCell.parse(String(repeating: "가", count: 41)) == .failure(.tooLong))
        #expect(TriggerCell.parse(" ,\n , ") == .failure(.empty))
    }

    /// 앱 편집기의 쉼표 규칙은 그대로다 — CSV 쪽에서만 개행을 받는다(5-4)
    @Test("`SnippetEntry.parseTriggers`는 바뀌지 않았다 — 개행은 나누지 않는다 (AC-15)")
    func editorParserUnchanged() {
        #expect(SnippetEntry.parseTriggers("주소\n인사") == ["주소\n인사"])
        #expect(SnippetEntry.parseTriggers("가, 나") == ["가", "나"])
    }
}

@Suite("문자 정리 (11절)")
struct PackTextSanitizerTests {

    @Test("CRLF·CR → LF, U+2028/2029 → LF")
    func lineBreaks() {
        #expect(PackTextSanitizer.sanitize("가\r\n나\r다\u{2028}라\u{2029}마").text == "가\n나\n다\n라\n마")
    }

    @Test("제어 문자 제거 — LF·탭은 남긴다")
    func controls() {
        let result = PackTextSanitizer.sanitize("가\u{0000}나\u{0007}\t다\n라\u{007F}\u{0085}마")
        #expect(result.text == "가나\t다\n라마")
        #expect(result.removed == 4)
    }

    @Test("bidi 재정의·격리, 방향 표식, U+200B, U+2060, 본문 중 U+FEFF 제거")
    func invisibles() {
        let input = "a\u{202A}b\u{202E}c\u{2066}d\u{2069}e\u{200E}f\u{200F}g\u{200B}h\u{2060}i\u{FEFF}j"
        let result = PackTextSanitizer.sanitize(input)
        #expect(result.text == "abcdefghij")
        #expect(result.removed == 9)
    }

    @Test("ZWJ·ZWNJ·변이 선택자 보존 — 가족 이모지·하트 VS16")
    func preserves() {
        let text = "👨\u{200D}👩\u{200D}👧 ❤\u{FE0F} 가\u{200C}나"
        #expect(PackTextSanitizer.sanitize(text) == (text, 0))
    }

    @Test("맨 앞·맨 뒤에 홀로 선 ZWJ는 뺀다")
    func loneZWJAtEdges() {
        #expect(PackTextSanitizer.sanitize("\u{200D}가나\u{200D}").text == "가나")
    }

    @Test("맨 앞·맨 뒤 ZWJ가 여럿이어도 전부 떼고 하나하나 센다 — ZWJ만 든 글은 빈 글, 가운데 ZWJ는 남는다")
    func manyEdgeZWJ() {
        #expect(PackTextSanitizer.sanitize("\u{200D}\u{200D}\u{200D}가\u{200D}나\u{200D}\u{200D}") == ("가\u{200D}나", 5))
        #expect(PackTextSanitizer.sanitize(String(repeating: "\u{200D}", count: 4)) == ("", 4))
        #expect(PackTextSanitizer.sanitize("\u{200B}\u{200D}가") == ("가", 2), "앞의 제로폭 공백을 빼고 나면 ZWJ가 맨 앞이다")
    }
}

// 검증 F3(`docs/release/verify-ext-1e-123.md`) — 맨 앞 ZWJ를 하나씩 `removeFirst()`로 떼면 앞 ZWJ 수 × 글 길이(제곱)다.
// 3MB 붙여넣기(앞 ZWJ 99.9만 개) 실측 33.2초(디버그) — CSV판 출하 경로다. 결과는 작은 입력에서 같으니 큰 입력 + 경과 시간 상한으로 고정한다
@Suite("문자 정리 — 맨 앞 ZWJ 떼기는 선형 (검증 F3)")
struct PackTextSanitizerTimeTests {

    private func seconds(_ work: () -> Void) -> Double {
        let duration = ContinuousClock().measure(work)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// 본문 열을 줄 첫 칸에 둔다 — 쉼표 바로 뒤의 ZWJ는 CSV 파서가 쉼표와 한 글자로 묶는다(검증 관찰, 범위 밖)
    private let leadingZWJ = 999_000
    private var pasted: String { "본문,번호\n" + String(repeating: "\u{200D}", count: leadingZWJ) + "가,1\n" }

    @Test("★ 3MB 붙여넣기(본문 앞 ZWJ 99.9만 개) — 5초 안에 초안, 본문은 「가」, 정리 99.9만 건", .timeLimit(.minutes(1)))
    func pastedLeadingZWJ() throws {
        let text = pasted
        #expect(text.utf8.count <= PackLimits.fileBytes)
        var outcome: PackImportOutcome?
        let elapsed = seconds { outcome = try? PackImporter.read(text: text) }
        guard case .draft(let draft)? = outcome else { Issue.record("초안이 아니다: \(String(describing: outcome))"); return }
        #expect(draft.items.map(\.body) == ["가"] && draft.sanitizedCharacterCount == leadingZWJ)
        #expect(elapsed < 5, "\(elapsed)초")   // 상한 5초 — 고치기 전 꼴은 33~117초라 여유가 크다. 1초는 CPU 부하에서 흔들렸다(검증 G1)
    }

    @Test("★ 같은 글을 파일로(UTF-8) — 디코드 뒤 같은 함수라 5초 안", .timeLimit(.minutes(1)))
    func fileLeadingZWJ() throws {
        let data = Data(pasted.utf8)
        var outcome: PackImportOutcome?
        let elapsed = seconds { outcome = try? PackImporter.read(data) }
        guard case .draft(let draft)? = outcome else { Issue.record("초안이 아니다: \(String(describing: outcome))"); return }
        #expect(draft.items.map(\.body) == ["가"] && draft.sanitizedCharacterCount == leadingZWJ)
        #expect(elapsed < 5, "\(elapsed)초")   // 상한 5초 — 고치기 전 꼴은 33~117초라 여유가 크다. 1초는 CPU 부하에서 흔들렸다(검증 G1)
    }

    @Test("함수 자체 — 앞 ZWJ 100만 개 + 뒤 ZWJ 100만 개도 5초 안")
    func sanitizeDirectly() {
        let zwj = String(repeating: "\u{200D}", count: 1_000_000)
        var result: (text: String, removed: Int)?
        let elapsed = seconds { result = PackTextSanitizer.sanitize(zwj + "가" + zwj) }
        #expect(result?.text == "가" && result?.removed == 2_000_000)
        #expect(elapsed < 5, "\(elapsed)초")   // 상한 5초 — 고치기 전 꼴은 33~117초라 여유가 크다. 1초는 CPU 부하에서 흔들렸다(검증 G1)
    }
}
