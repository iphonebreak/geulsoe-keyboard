import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 팩 상세 「전체 보기」(PDR R31, 2026-10-07) — 목록 데이터 `PackEntryList`와 그 화면 문구.
// 저장소에서 읽는 길(`PackStore.packEntries` — 꺼진 팩·읽을 수 없는 팩)은 `ExternalPackStoreTests.packEntries`가 본다.

private func phrases(_ entries: [SnippetEntry]) -> ExternalPack {
    ExternalPack(name: "회사 상용구", license: "자체 작성", mode: .phrases, entries: entries)
}

private func numbered(_ items: [PackTemplateItem], formats: [String] = ["사자성어 {n}번"]) -> ExternalPack {
    let patterns = formats.compactMap { format -> TemplatePattern? in
        let parts = format.components(separatedBy: "{n}")
        return parts.count == 2 ? TemplatePattern(prefix: SnippetEntry.normalizedTrigger(parts[0]), suffix: SnippetEntry.normalizedTrigger(parts[1])) : nil
    }
    return ExternalPack(name: "사자성어 예시 팩", license: "자체 작성", mode: .numbered,
                        template: PackTemplate(patterns: patterns, titleFormat: formats[0], items: items))
}

@Suite("팩 상세 「전체 보기」 (R31) — 목록 데이터·검색·문구")
struct PackEntryListTests {

    // MARK: 줄

    @Test("★ 문구형 — 단축어가 여럿이면 모두 쉼표로, 결과는 사용법과 같은 요약(여러 줄 이어 30자·「…」)")
    func phrasesShowEveryTrigger() {
        let long = "안녕하세요.\n오늘 회의를 시작하겠습니다.\n자료는 메일로 보내 드렸습니다."
        let list = PackEntryList(phrases([
            SnippetEntry(triggers: ["회사장", "장", "회사 주소"], title: "주소", body: "서울시 어딘가 1번지"),
            SnippetEntry(trigger: "회의시작", title: "회의", body: long)
        ]))
        #expect(list.rows.map(\.trigger) == ["회사장, 장, 회사 주소", "회의시작"], "원문 그대로(정규화하지 않는다)")
        #expect(list.rows.map(\.result) == ["→ 서울시 어딘가 1번지", PackNoticeCopy.usageResult(body: long)])
        #expect(list.rows[1].result == "→ 안녕하세요. 오늘 회의를 시작하겠습니다. 자료는 메일로…")
    }

    @Test("★ 번호형 — 대표 틀(첫 `#틀` 원문)에 번호를 넣은 단축어, 별칭 틀은 쓰지 않는다. 결과는 그 항목 본문(제목 아님)")
    func numberedUsesRepresentativeTemplate() {
        let list = PackEntryList(numbered([
            PackTemplateItem(n: 1, title: "", body: "첫 본문"),
            PackTemplateItem(n: 12, title: "따로 붙인 제목", body: "열두째 본문\n둘째 줄"),
            PackTemplateItem(n: 1300, title: "", body: "천삼백째 본문")
        ], formats: ["사자성어 {n}번", "고사성어{n}번"]))
        #expect(list.rows.map(\.trigger) == ["사자성어 1번", "사자성어 12번", "사자성어 1300번"])
        #expect(list.rows.map(\.result) == ["→ 첫 본문", "→ 열두째 본문 둘째 줄", "→ 천삼백째 본문"])
    }

    @Test("순서 — 팩 순서 그대로(문구형 = 항목 순서, 번호형 = 저장본 순서 = 번호 오름차순), id는 0부터 자리")
    func order() {
        let phraseList = PackEntryList(phrases(["다", "가", "나"].map { SnippetEntry(trigger: $0, title: $0, body: "\($0) 본문") }))
        #expect(phraseList.rows.map(\.trigger) == ["다", "가", "나"], "가나다로 다시 늘어놓지 않는다")
        #expect(phraseList.rows.map(\.id) == [0, 1, 2])
        let numberedList = PackEntryList(numbered([3, 7, 20].map { PackTemplateItem(n: $0, title: "", body: "본문 \($0)") }))
        #expect(numberedList.rows.map(\.trigger) == ["사자성어 3번", "사자성어 7번", "사자성어 20번"])
        #expect(numberedList.rows.map(\.id) == [0, 1, 2])
        #expect(PackEntryList(phrases([])).rows.isEmpty)
    }

    // MARK: 검색

    private var searchable: PackEntryList {
        PackEntryList(phrases([
            SnippetEntry(triggers: ["회사장", "장"], title: "주소", body: "서울시 어딘가 1번지"),
            SnippetEntry(trigger: "감사인사", title: "감사", body: "Thank you\n고맙습니다"),
            SnippetEntry(trigger: "회의 시작", title: "회의", body: "지금부터 회의를 시작하겠습니다.")
        ]))
    }

    @Test("★ 검색 — 단축어·본문에서 찾고, 띄어쓰기는 무시(`SnippetEntry.normalizedTrigger`), 순서 그대로",
          arguments: [
            ("회사장", ["회사장, 장"]), ("회 사 장", ["회사장, 장"]), ("회의시작", ["회의 시작"]), ("회의 시 작", ["회의 시작"]),
            ("어딘가1번지", ["회사장, 장"]), ("고맙", ["감사인사"]), ("회", ["회사장, 장", "회의 시작"]), ("시작하겠", ["회의 시작"]),
            ("you고맙", ["감사인사"])   // 본문의 줄바꿈도 띄어쓰기와 같이 지운다(같은 함수)
          ])
    func searchIgnoresSpacing(_ query: String, _ expected: [String]) {
        #expect(searchable.rows(matching: query).map(\.trigger) == expected)
    }

    @Test("검색은 대소문자를 가리지 않는다 — 이 검색에서만(코디네이터 결정 2026-10-07)", arguments: ["thank", "THANK YOU", "tHaNk"])
    func searchIgnoresCase(_ query: String) {
        #expect(searchable.rows(matching: query).map(\.trigger) == ["감사인사"])
    }

    @Test("검색 — 찾는 말이 비었거나 공백뿐이면 전부, 없으면 빈 결과(화면은 빈 상태 한 줄)")
    func searchEdges() {
        #expect(searchable.rows(matching: "") == searchable.rows)
        #expect(searchable.rows(matching: "  \n ") == searchable.rows)
        #expect(!PackEntryList.isSearching("") && !PackEntryList.isSearching("   ") && PackEntryList.isSearching(" 회 "))
        #expect(searchable.rows(matching: "없는말").isEmpty)
    }

    @Test("검색 — 조합형(NFD)·완성형(NFC) 한글은 같은 글자로 본다(양쪽을 NFC로 맞춰 바이트로 훑는다)")
    func searchIsCanonical() {
        let decomposed = "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}"   // 「한글」 조합형
        #expect(Array(decomposed.unicodeScalars) != Array("한글".unicodeScalars) && decomposed == "한글", "스칼라는 다르고 글자는 같다")
        let list = PackEntryList(phrases([
            SnippetEntry(trigger: "완성형", title: "가", body: "한글 본문"),
            SnippetEntry(trigger: "조합형", title: "나", body: decomposed + " 본문")
        ]))
        #expect(list.rows(matching: "한글").map(\.trigger) == ["완성형", "조합형"])
        #expect(list.rows(matching: decomposed).map(\.trigger) == ["완성형", "조합형"])
        #expect(list.rows(matching: "하").isEmpty, "완성형 「한」의 앞 조각 「하」는 맞지 않는다(글자 단위 비교와 같다)")
    }

    @Test("바이트 부분열 — 찾는 말이 더 길거나 비었으면 맞지 않는다")
    func byteSearchEdges() {
        #expect(PackEntryList.bytes(Array("가나다".utf8), contain: Array("나".utf8)))
        #expect(!PackEntryList.bytes(Array("가".utf8), contain: Array("가나".utf8)))
        #expect(!PackEntryList.bytes([], contain: Array("가".utf8)))
        #expect(!PackEntryList.bytes(Array("가".utf8), contain: []))
    }

    @Test("검색 — 단축어마다 따로 본다: 두 단축어에 걸친 말(「회사장, 장」의 「장,장」)은 맞지 않는다")
    func searchDoesNotSpanTriggers() {
        #expect(searchable.rows(matching: "장,장").isEmpty)
        #expect(searchable.rows(matching: "장, 장").isEmpty)
    }

    @Test("번호형 검색 — 단축어(틀에 번호)와 본문, 띄어쓰기 무시")
    func numberedSearch() {
        let list = PackEntryList(numbered((1...30).map { PackTemplateItem(n: $0, title: "", body: $0 == 25 ? "특별한 본문" : "본문 \($0)") }))
        #expect(list.rows(matching: "사자성어12번").map(\.trigger) == ["사자성어 12번"])
        #expect(list.rows(matching: "3").map(\.trigger) == ["사자성어 3번", "사자성어 13번", "사자성어 23번", "사자성어 30번"])
        #expect(list.rows(matching: "특별").map(\.trigger) == ["사자성어 25번"])
    }

    // MARK: 수천 개

    @Test("★ 3,000 항목 — 줄 만들기·검색 시간(메인 밖에서 돌지만 가벼워야 한다). 본문 1,000자씩 — UTF-8 약 9MB로 예산 바이트 확정값(3MB)의 세 배(보수적)")
    func threeThousandEntries() {
        let body = String(repeating: "가나다라마바사 아자차카타파하 ", count: 66)   // 약 1,000자
        let pack = phrases((0..<3_000).map { index in
            SnippetEntry(triggers: ["단축어 \(index)", "별칭\(index)"], title: "제목 \(index)", body: "\(index)번째 \(body)")
        })
        let clock = ContinuousClock()
        var list: PackEntryList?
        let build = clock.measure { list = PackEntryList(pack) }
        guard let list else { Issue.record("목록을 만들지 못했다"); return }
        #expect(list.rows.count == 3_000)
        var found: [PackEntryList.Row] = []
        let miss = clock.measure { found = list.rows(matching: "어디에도없는말") }   // 끝까지 다 훑는 가장 나쁜 경우
        #expect(found.isEmpty)
        let hit = clock.measure { found = list.rows(matching: "별칭 2999") }
        #expect(found.map(\.id) == [2_999])
        let broad = clock.measure { found = list.rows(matching: "가나") }
        #expect(found.count == 3_000)
        print("R31 3,000 항목 — 만들기 \(build) · 없는 말 \(miss) · 한 개 \(hit) · 전부 맞음 \(broad)")
        // 디버그 빌드·기기 차를 넉넉히 본 상한 — 실측(2026-10-07, 디버그): 만들기 0.5~0.9초(다른 시험과 함께 돌면 느려진다) · 검색 약 7ms.
        // 검색이 글자 단위 `String.contains`였을 때는 release로도 0.14초였다 — 바이트 검색이 풀리면 이 상한이 잡는다
        #expect(build < .seconds(3))
        #expect(miss < .milliseconds(100) && hit < .milliseconds(100) && broad < .milliseconds(100))
    }

    // MARK: 문구

    @Test("★ 문구 — 「전체 보기 (n개)」는 천 단위 쉼표, 머리 한 줄은 꺼짐만 새 문구·쉬는 중은 목록 보조줄 그대로·켬은 없음")
    func copy() {
        #expect(PackNoticeCopy.allEntriesRow(count: 3) == "전체 보기 (3개)")
        #expect(PackNoticeCopy.allEntriesRow(count: 3_000) == "전체 보기 (3,000개)")
        #expect(PackNoticeCopy.allEntriesStatusLine(.off) == "꺼져 있어서 지금은 안 떠요")
        #expect(PackNoticeCopy.allEntriesStatusLine(.on) == nil)
        #expect(PackNoticeCopy.allEntriesStatusLine(.restingOverLimit) == PackNoticeCopy.statusLine(.restingOverLimit))
        #expect(PackNoticeCopy.allEntriesStatusLine(.restingForUserSnippets) == PackNoticeCopy.statusLine(.restingForUserSnippets))
        #expect(PackNoticeCopy.allEntriesHeader(count: 1_300, isSearching: false) == "채움글 1,300개")
        #expect(PackNoticeCopy.allEntriesHeader(count: 12, isSearching: true) == "찾은 채움글 12개")
        #expect(PackNoticeCopy.allEntriesNoMatch.hasSuffix("요."))
    }
}
