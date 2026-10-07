import Foundation
import Testing
import TadakDomain
@testable import PackImport

// 외부 채움글 1-c — 1~3단계 화면 확인 지적(`docs/release/verify-ext-1c-screen.md` 9·10절) 중 패키지가 정하는 것을 고정한다.
// S-3 가림 설명의 범위 · S-4 표시 숫자 한 함수(천 단위 쉼표) · O-1 사용법 예시는 지금 뜨는 단축어부터 · O-2 목록 손상 동안 절 풋터 ·
// O-4 편집 시트 안 알림은 「확인」만(친 내용을 잃지 않게). S-1(복구 확인 → 알림)·S-2(추가 줄 활성)는 화면 코드라 화면 확인 목록에 둔다.

private final class FixGenerations: PackGenerationWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var user = 0
    private var packs = 0
    var userSnippetsGeneration: Int { lock.withLock { user } }
    var packsGeneration: Int { lock.withLock { packs } }
    func setUserSnippetsGeneration(_ value: Int) { lock.withLock { user = value } }
    func setPacksGeneration(_ value: Int) { lock.withLock { packs = value } }
}

private final class FixSnippets: UserSnippetStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [SnippetEntry]
    init(_ entries: [SnippetEntry]) { stored = entries }
    func entries() -> [SnippetEntry] { lock.withLock { stored } }
    func save(_ entries: [SnippetEntry]) -> Bool { lock.withLock { stored = entries; return true } }
}

// MARK: - S-4 표시 숫자

@Suite("화면 확인 S-4 — 표시 숫자는 한 함수(천 단위 쉼표)")
struct DisplayNumberTests {

    @Test("천 단위 쉼표 — 지역 설정과 무관", arguments: [
        (0, "0"), (7, "7"), (999, "999"), (1_000, "1,000"), (1_300, "1,300"), (3_120, "3,120"), (65_535, "65,535"),
        (1_234_567, "1,234,567"), (-1_300, "-1,300")
    ])
    func grouping(value: Int, expected: String) {
        #expect(PackNoticeCopy.number(value) == expected)
    }

    @Test("★ 개수·위치가 나오는 문구가 모두 그 함수를 지난다 — 1,300개")
    func countsUseGrouping() {
        let summary = PackSummary(id: "a", name: "예시 팩", mode: .phrases, itemCount: 1_300, titleFormat: nil, isEnabled: true, status: .on)
        #expect(PackNoticeCopy.packRowDetail(summary) == "문구형 · 1,300개")
        #expect(PackNoticeCopy.deleteMessage(itemCount: 1_300).contains("1,300개"))
        #expect(PackNoticeCopy.overLimitBanner(loadableCount: 3_120).contains("3,120개"))
        #expect(PackNoticeCopy.hiddenTriggersHeader(count: 1_500) == "지금 안 뜨는 단축어 1,500개")
        #expect(PackImportCopy.count(1_300) == "1,300개")
        #expect(PackImportCopy.position(record: 1_234, line: 5_678) == "1,234번째 항목(5,678번째 줄)")
        #expect(PackImportCopy.skippedHeader(count: 1_200) == "건너뛴 행 1,200개")
        #expect(PackImportCopy.importOnly(1_001) == "그래도 1,001개만 가져오기")
        #expect(PackFormCopy.doneSummary(name: "예시 팩", count: 1_300) == "「예시 팩」 · 1,300개")
        #expect(PackFormCopy.skippedLine(1_300) == "건너뛴 1,300개는 가져오지 않았어요.")
        #expect(PackImportCopy.skipFix(.bodyTooLong).contains("\(PackNoticeCopy.number(PackLimits.body.characters))자"))
    }

    @Test("번호 범위는 쉼표 없이 — 번호는 단축어에 그대로 치는 식별자(시안 4-F 「1~9999」)")
    func numberRangeStaysBare() {
        #expect(PackImportCopy.skipReason(.invalidNumber).contains("1~\(PackLimits.numberRange.upperBound)"))
    }
}

// MARK: - S-3 가림 범위

@Suite("화면 확인 S-3 — 가림은 「그 끝말로 끝나는 입력」에서만")
struct ShadowRangeCopyTests {

    @Test("「으로/로」 — 받침·ㄹ 받침·숫자·모르는 글자")
    func directionParticle() {
        #expect(PackNoticeCopy.directionParticle(after: "장") == "으로")
        #expect(PackNoticeCopy.directionParticle(after: "번호3번") == "으로")
        #expect(PackNoticeCopy.directionParticle(after: "자") == "로")
        #expect(PackNoticeCopy.directionParticle(after: "길") == "로")
        #expect(PackNoticeCopy.directionParticle(after: "3") == "으로")
        #expect(PackNoticeCopy.directionParticle(after: "7") == "로")
        #expect(PackNoticeCopy.directionParticle(after: "A") == "(으)로")
    }

    @Test("★ 팩 상세(2-E)·폼(5-C) 모두 「틀 전체가 안 뜬다」고 말하지 않는다")
    func noOverstatement() {
        let lines = [
            PackNoticeCopy.patternLine(.shadowed(by: ["번호3번"]), name: { $0 }),
            PackNoticeCopy.patternLine(.shadowed(by: ["장", "번"]), name: { $0 }),
            PackFormCopy.reviewDetail(.shadowed(triggers: ["장"], owner: .userSnippets), replacing: false, name: { $0 }) ?? "",
            PackFormCopy.reviewDetail(.shadowed(triggers: ["장", "번"], owner: .builtIn), replacing: false, name: { $0 }) ?? ""
        ]
        for line in lines {
            #expect(!line.contains("이 틀은 안 떠요"), "\(line)")
            #expect(line.contains("끝나는 입력에서는"), "\(line)")
        }
        #expect(lines[0] == "「…번호3번」으로 끝나는 입력에서는 단축어 「번호3번」이 먼저 떠요")
        #expect(lines[3] == "「…장」 등으로 끝나는 입력에서는 내장 팩 단축어가 먼저 떠요.")
    }
}

// MARK: - O-1 사용법 예시

@Suite("화면 확인 O-1 — 문구형 상세의 사용법 예시는 지금 뜨는 단축어부터")
struct UsageExampleTests {

    private func entry(_ triggers: [String]) -> SnippetEntry {
        SnippetEntry(triggers: triggers, title: "제목 \(triggers[0])", body: "본문")
    }

    @Test("밀린 단축어는 뒤로, 항목 안에서도 안 밀린 단축어를 보인다")
    func prefersShownTriggers() {
        let pack = ExternalPack(name: "예시", license: "자체", mode: .phrases, entries: [
            entry(["회사주소"]), entry(["새해인사", "새인사"]), entry(["회의실"]), entry(["퇴근인사"])
        ])
        #expect(PackDetail.examples(of: pack).map(\.trigger) == ["회사주소", "새해인사", "회의실"])
        let hidden: Set<String> = ["회사주소", "새해인사"]
        #expect(PackDetail.examples(of: pack, hidden: hidden).map(\.trigger) == ["새인사", "회의실", "퇴근인사"])
        // 다 밀렸으면 그래도 보인다(사용법 절이 사라지지 않게) — 「지금 안 뜨는 단축어」 절이 이유를 말한다
        let all: Set<String> = ["회사주소", "새해인사", "새인사", "회의실", "퇴근인사"]
        #expect(PackDetail.examples(of: pack, hidden: all).map(\.trigger) == ["회사주소", "새해인사", "회의실"])
    }

    @Test("★ 화면 확인 N-2 — 번호형 예시는 이 팩이 쓰는 틀부터: 위 팩·단축어에 밀린 틀은 건너뛰고, 다 밀렸으면 대표 틀")
    func numberedPrefersOwnedPattern() throws {
        let first = try TemplatePatternSpec.parse("사자성어 {n}번").get()
        let alias = try TemplatePatternSpec.parse("성어 {n}번").get()
        let pack = ExternalPack(name: "예시", license: "자체", mode: .numbered, template: PackTemplate(
            patterns: [first, alias], titleFormat: "사자성어 {n}번", items: [PackTemplateItem(n: 3, title: "제목", body: "본문")]))
        func pattern(_ value: TemplatePattern, _ display: String, _ status: PackStanding.PatternStatus) -> PackStanding.Pattern {
            PackStanding.Pattern(pattern: value, display: display, status: status)
        }
        let triggers = { (patterns: [PackStanding.Pattern]) in PackDetail.examples(of: pack, patterns: patterns).map(\.trigger) }
        #expect(PackDetail.examples(of: pack) == [PackDetail.Example(trigger: "사자성어 3번", title: "제목")], "자리를 모르면 대표 틀")
        #expect(triggers([pattern(first, "사자성어 {n}번", .owned(sharedWith: [])), pattern(alias, "성어{n}번", .owned(sharedWith: []))])
                    == ["사자성어 3번"])
        #expect(triggers([pattern(first, "사자성어 {n}번", .outranked(by: "a")), pattern(alias, "성어{n}번", .owned(sharedWith: []))])
                    == ["성어3번"])
        #expect(triggers([pattern(first, "사자성어 {n}번", .owned(sharedWith: [])), pattern(alias, "성어{n}번", .outranked(by: "a"))])
                    == ["사자성어 3번"])
        // 다 밀렸으면 그래도 보인다(문구형 O-1과 같다 — 사용법 절이 사라지지 않게, 상세의 틀 절이 이유를 말한다)
        #expect(triggers([pattern(first, "사자성어 {n}번", .shadowed(by: ["번"])), pattern(alias, "성어{n}번", .outranked(by: "a"))])
                    == ["사자성어 3번"])
    }

    @Test("★ 저장소의 팩 상세 — 내 채움글이 먼저 뜨는 단축어는 예시 앞에 오지 않는다(U1 계산과 같은 입력)")
    func packDetailUsesStanding() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("o1-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PackStore(libraryRoot: root.appendingPathComponent("library"), snapshotRoot: root.appendingPathComponent("snapshot"),
                              generations: FixGenerations(),
                              userSnippets: FixSnippets([SnippetEntry(trigger: "회사주소", title: "내 주소", body: "내 본문")]),
                              builtInEntries: { _ in [] }, disabledBuiltIns: { [] }, notify: {}, makeID: { "p1" })
        let pack = ExternalPack(name: "예시", license: "자체", mode: .phrases,
                                entries: [entry(["회사주소"]), entry(["새해인사"]), entry(["회의실"]), entry(["퇴근인사"])])
        #expect(store.importPack(pack, source: .csv).isAccepted)
        let detail = try #require(store.packDetail("p1"))
        #expect(detail.standing?.hiddenTriggers.map(\.trigger) == ["회사주소"])
        #expect(detail.examples.map(\.trigger) == ["새해인사", "회의실", "퇴근인사"])
    }
}

// MARK: - O-2 목록 손상 동안 절 풋터

@Suite("화면 확인 O-2 — 목록 손상 동안 「외부 채움글」 절은 빈 상태가 아니라 손상 한 줄")
struct ExternalSectionFooterTests {

    @Test("읽히지 않는 세 상태 → 손상 한 줄(팩 유무와 무관) · 읽히면 2-B 빈 상태 / 2-C는 풋터 없음(사장님 실기 2026-10-07)", arguments: [
        (true, PackLibraryStatus.readable, PackNoticeCopy.emptyListFooter as String?),
        (false, .readable, nil),
        (true, .unreadable, PackNoticeCopy.unreadableListFooter),
        (true, .corrupt, PackNoticeCopy.unreadableListFooter),
        (false, .unknownSchema, PackNoticeCopy.unreadableListFooter)
    ])
    func footer(isEmpty: Bool, status: PackLibraryStatus, expected: String?) {
        #expect(PackNoticeCopy.externalSectionFooter(isEmpty: isEmpty, libraryStatus: status) == expected)
    }

    /// U6·금칙어·xlsx는 6단계 `PackCopyLintTests`가 본다(`allScreenCopy`에 이 줄이 들어 있다)
    @Test("문구 — 지시 그대로 · 숫자 0")
    func copy() {
        #expect(PackNoticeCopy.unreadableListFooter == "외부 채움글 목록을 읽을 수 없어요. 위에서 목록을 복구해 주세요.")
        #expect(!PackNoticeCopy.unreadableListFooter.contains { $0.isNumber })
    }
}

// MARK: - O-4 알림을 띄우는 자리

/// 모든 쓰기 × 거부 사유 × 저장 전 한도 상태 — 나올 수 있는 알림 전부
private let everyNotice: [(PackChangeNotice.Operation, PackChangeNotice)] = {
    let rejections: [PackStore.Rejection] = [
        .gate(.baselineOverLimit([.items])), .gate(.baselineOverLimit([.needleChars])), .gate(.displacesPacks(["a"])),
        .gate(.packExcluded(id: "a", dimensions: [.needleChars])), .gate(.tooManyPacks), .gate(.invalidDisabledImport(id: "a")),
        .moreThanOneItem, .notFound, .invalidOrder, .writeFailed, .libraryUnreadable, .packUnavailable("a")
    ]
    var all: [(PackChangeNotice.Operation, PackChangeNotice)] = []
    for operation in PackChangeNotice.Operation.allCases {
        for rejection in rejections {
            for overLimit in [false, true] {
                if let notice = PackChangeNotice(operation, result: .rejected(rejection, rechecked: false),
                                                 userSnippetsOverLimit: { overLimit }, packName: { _ in "팩" }) {
                    all.append((operation, notice))
                }
            }
        }
    }
    return all
}()

@Suite("화면 확인 O-4 — 알림 버튼은 띄우는 자리가 연결한 것만")
struct NoticePresenterTests {

    @Test("★ 편집 시트 안 — A3 정리하기·E1 목록 복구를 빼고 「확인」만(친 내용을 잃지 않게)")
    func editorSheetHasNoActions() throws {
        let a3 = try #require(PackChangeNotice(.saveUserSnippet, result: .rejected(.gate(.baselineOverLimit([.needleChars])), rechecked: false),
                                               userSnippetsOverLimit: { true }, packName: { _ in nil }))
        let e1 = try #require(PackChangeNotice(.saveUserSnippet, result: .rejected(.libraryUnreadable, rechecked: false),
                                               userSnippetsOverLimit: { false }, packName: { _ in nil }))
        #expect(a3.reason == .userSaveWhileOverLimit && a3.actions == [.organize])
        #expect(e1.reason == .libraryUnreadable && e1.actions == [.recoverLibrary])
        #expect(a3.actions(in: .editorSheet).isEmpty && e1.actions(in: .editorSheet).isEmpty)
        #expect(a3.dismiss == .confirm && e1.dismiss == .confirm)
        // 채움글 화면(같은 알림이 시트 밖에서 날 때)은 그대로 정리하기·목록 복구를 준다
        #expect(a3.actions(in: .settings) == [.organize] && e1.actions(in: .settings) == [.recoverLibrary])
        // 편집 시트 안에서는 어떤 알림도 동작 버튼이 없다
        for (_, notice) in everyNotice { #expect(notice.actions(in: .editorSheet).isEmpty) }
    }

    /// 가져오기 시트가 부르는 쓰기 — 새 팩·꺼 둔 채로·같은 이름 바꾸기. 셋 다 켜기 거부(`packUnavailable`)는 낼 수 없다
    private static let importOperations: Set<PackChangeNotice.Operation> = [.importPack, .importDisabledPack, .replacePack]

    @Test("가져오기 시트 — 가져오기·바꾸기 알림의 버튼을 하나도 빠뜨리지 않는다(D1 꺼 둔 채로 · D2·C3b 정리하기 · E1 복구)")
    func importFlowKeepsImportActions() {
        for (operation, notice) in everyNotice where Self.importOperations.contains(operation) && notice.reason != .packUnavailable {
            #expect(notice.actions(in: .importFlow) == notice.actions, "\(operation) \(notice.reason)")
        }
    }

    @Test("그 밖 화면 — 가져오기 아닌 알림의 버튼은 예전 그대로(빠지는 것 없음)")
    func settingsKeepsOtherActions() {
        for (operation, notice) in everyNotice where !Self.importOperations.contains(operation) {
            #expect(notice.actions(in: .settings) == notice.actions, "\(operation) \(notice.reason)")
        }
    }
}
