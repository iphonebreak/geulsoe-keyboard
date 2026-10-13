import Foundation
import Testing
import HangulEngine
import TadakDomain
@testable import KeyboardCore

// B2 — ⏎⌫ 뒤 앞 글자 모름 (1.3.1, PDR `docs/design-reviews/return-backspace-context.md`, 계획 `docs/release/v1.3.1-plan.md` §3-1).
//
// ⏎ 뒤 ⌫는 꼬리가 빈 채 앞 글자를 지운다 — KeyboardCore는 무엇을 지웠는지 모른다. 1.3.0은 이것을 「잘림」으로 적어
// `서울⏎⌫주소`(= 「서울주소」) 칩을 막았고(대가: `서울␣⏎⌫주소`·빈 입력란 ⌫ 뒤 첫 칩 없음), 자동 대문자는 1.0부터
// 빈 꼬리를 「줄 처음」으로 봐 `Hello⏎⌫x` → 「HelloX」였다.
//
// **B2-A(이번 구현)** — 리턴 키가 `.default`면 ⏎ 직전 줄 끝을 기억했다가 ⏎ **바로 다음** ⌫가 빈 꼬리를 지울 때
// **자동 대문자 판정에만** 되살린다. **칩·꼬리(`textTail`)·추천단어는 이 기억을 읽지 않는다(불변식 C7)** — 칩 쪽 1.3.0 동작은 그대로다.
// **B2-C(첫 칩 복원)는 구현하지 않았다** — B2-0 탐침 판정 대기. 아래 칩 표는 지금(1.3.0) 동작을 리턴 키 종류와 무관하게 고정한다.

// MARK: - 호스트 모형

/// 문서 호스트 — ⏎에 무엇을 하고, 우리 ⌫에 `textDidChange`를 보내나.
///
/// 「메아리」 = VC가 `documentContextBeforeInput`(빈 문서는 nil)으로 sync한다(`KeyboardViewController.textDidChange`).
/// `staleGetter`·`nilGetter`는 **⌫ 직후 동기 읽기**가 낡은 값 / nil을 내는 호스트다 — 지금 제품(B2-A)은 그 값을
/// 읽지 않으므로 메아리 없는 호스트와 같게 동작한다. B2-C가 ⌫ 직후 관찰을 넣으면 이 둘이 갈린다(`HostDocument.readRightAfterDelete`).
enum DocumentHost: CaseIterable, CustomStringConvertible, Sendable {
    /// 메모장형 — ⏎는 줄바꿈, ⌫에 메아리 없음
    case silent
    /// ⏎는 줄바꿈, ⌫마다 메아리 sync
    case echoesBackspace
    /// ⏎는 줄바꿈, 메아리 없음, ⌫ 직후 읽기는 지우기 전 값
    case staleGetter
    /// ⏎는 줄바꿈, 메아리 없음, ⌫ 직후 읽기는 nil
    case nilGetter
    /// 제출형 한 줄 입력란 — ⏎가 문서를 바꾸지 않고 키보드가 남는다, 메아리 없음
    case submitKeepsText
    /// ⏎가 입력란을 비우고 `textDidChange`(빈 문서 → nil)를 보낸다
    case submitClearsNotifying
    /// ⏎가 입력란을 비우고 아무 통지도 없다
    case submitClearsSilent

    enum ReturnBehavior: Sendable { case newline, keepsText, clears }

    /// 기대값 묶음. 지금 제품은 ⌫ 직후 읽기를 하지 않으므로 낡은·nil getter는 메아리 없는 호스트와 같은 열이다
    enum Column: Sendable { case quiet, echo, keeps, clearsNotify, clearsSilent }

    var returnBehavior: ReturnBehavior {
        switch self {
        case .silent, .echoesBackspace, .staleGetter, .nilGetter: .newline
        case .submitKeepsText: .keepsText
        case .submitClearsNotifying, .submitClearsSilent: .clears
        }
    }

    var sendsBackspaceEcho: Bool { self == .echoesBackspace }
    var notifiesAfterReturn: Bool { self == .submitClearsNotifying }

    var column: Column {
        switch self {
        case .silent, .staleGetter, .nilGetter: .quiet
        case .echoesBackspace: .echo
        case .submitKeepsText: .keeps
        case .submitClearsNotifying: .clearsNotify
        case .submitClearsSilent: .clearsSilent
        }
    }

    /// ⏎가 줄바꿈을 넣는 호스트 — `SnippetWordBoundaryTests`의 11행 표(문서가 고정된 표)가 도는 범위
    static let newlineHosts: [DocumentHost] = allCases.filter { $0.returnBehavior == .newline }

    var description: String {
        switch self {
        case .silent: "메아리 없음"
        case .echoesBackspace: "메아리"
        case .staleGetter: "낡은 getter"
        case .nilGetter: "nil getter"
        case .submitKeepsText: "제출(문서 유지)"
        case .submitClearsNotifying: "제출(비움·통지)"
        case .submitClearsSilent: "제출(비움·무통지)"
        }
    }
}

/// 호스트 문서 fake — 커서는 늘 끝. 우리 ⏎(`"\n"` 한 글자)만 호스트 동작을 따르고 나머지 쓰기는 그대로 반영한다
/// (채움글 본문의 줄바꿈은 다른 글자와 함께 한 번에 온다).
@MainActor
final class HostDocument: TextOutput {
    let host: DocumentHost
    private(set) var text = ""
    private var textBeforeLastDelete: String?

    init(host: DocumentHost) {
        self.host = host
    }

    func insertText(_ inserted: String) {
        guard inserted == "\n" else {
            text += inserted
            return
        }
        switch host.returnBehavior {
        case .newline: text += "\n"
        case .keepsText: break
        case .clears: text = ""
        }
    }

    func deleteBackward(_ count: Int) {
        textBeforeLastDelete = text
        text = String(text.dropLast(count))
    }

    /// ⌫ 직후 **동기 읽기**가 내는 값(B2-0 탐침이 실기에서 재는 것). **지금 제품은 읽지 않는다** — B2-C가 관찰을 넣으면
    /// `TextOutput`의 읽기로 이 값을 내게 된다. 빈 문서는 nil(`documentContextBeforeInput`과 같다)
    var readRightAfterDelete: String? {
        switch host {
        case .staleGetter: textBeforeLastDelete.flatMap { $0.isEmpty ? nil : $0 }
        case .nilGetter: nil
        default: text.isEmpty ? nil : text
        }
    }
}

/// 자판 3종 — 같은 글자를 자판마다의 키로 친다
enum Layout: CaseIterable, CustomStringConvertible, Sendable {
    case dubeolsik, cheonjiin, danmoeum

    func makeSource() -> JamoSource {
        switch self {
        case .dubeolsik: DubeolsikSource()
        case .cheonjiin: CheonjiinSource()
        case .danmoeum: DanmoeumSource()
        }
    }

    /// 시험 대본에 쓰는 한글 → 이 자판의 키. 천지인 ㅓ = ㆍㅣ, ㅜ = ㅡㆍ, ㅗ = ㆍㅡ, ㅏ = ㅣㆍ, ㄹ = ㄴㄴ
    func keys(for character: Character) -> [String]? {
        let table: [Character: [Layout: [String]]] = [
            "서": [.dubeolsik: ["t", "j"], .cheonjiin: ["ㅅ", "ㆍ", "ㅣ"], .danmoeum: ["ㅅ", "ㅓ"]],
            "울": [.dubeolsik: ["d", "n", "f"], .cheonjiin: ["ㅇ", "ㅡ", "ㆍ", "ㄴ", "ㄴ"], .danmoeum: ["ㅇ", "ㅜ", "ㄹ"]],
            "주": [.dubeolsik: ["w", "n"], .cheonjiin: ["ㅈ", "ㅡ", "ㆍ"], .danmoeum: ["ㅈ", "ㅜ"]],
            "소": [.dubeolsik: ["t", "h"], .cheonjiin: ["ㅅ", "ㆍ", "ㅡ"], .danmoeum: ["ㅅ", "ㅗ"]],
            "가": [.dubeolsik: ["r", "k"], .cheonjiin: ["ㄱ", "ㅣ", "ㆍ"], .danmoeum: ["ㄱ", "ㅏ"]],
            "ㅈ": [.dubeolsik: ["w"], .cheonjiin: ["ㅈ"], .danmoeum: ["ㅈ"]]
        ]
        return table[character]?[self]
    }

    var description: String {
        switch self {
        case .dubeolsik: "두벌식"
        case .cheonjiin: "천지인"
        case .danmoeum: "단모음"
        }
    }
}

/// 대본 실행기. 대본 글자 — 한글은 자판 키로, `⏎` 리턴 · `⌫` ⌫(메아리 호스트는 이어 sync) · `␣` 공백 · `#` 123 ·
/// `⇄` 한영 · `◀` 커서 도구 ◀▶ 왕복(VC가 문맥 없이 sync 두 번) · `↺` 호스트가 보낸 `textDidChange`(외부 편집) ·
/// `◆` 떠 있는 `주소` 칩 탭(본문 「첫 줄\n」) · 그 밖은 글자 키 그대로
@MainActor
enum B2Script {
    /// 단축어 `주소`
    static let address = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "주소", title: "주소", body: "본문")])
    /// `◆` 전용 — 본문이 줄바꿈으로 끝나는 `주소`(넣고 나면 새 줄의 처음)
    static let multiLineAddress = SnippetMatcher(bible: nil, entries: [SnippetEntry(trigger: "주소", title: "주소", body: "첫 줄\n")])

    /// - Parameter onWordCommitted: 학습으로 보내는 단어를 받는다(C7 학습 칸 시험)
    static func run(
        _ script: String, host: DocumentHost, layout: Layout, returnKeyIsDefault: Bool,
        autoCapitalization: AutoCapitalization = .none, startsInEnglish: Bool = false, doubleSpacePeriod: Bool = true,
        onWordCommitted: ((String) -> Void)? = nil
    ) -> (HostDocument, InputController) {
        let document = HostDocument(host: host)
        let source = layout.makeSource()
        // 시계를 멈춰 둔다 — 천지인 ㄴㄴ → ㄹ 순환·단모음 연타 승격이 타임아웃 안에 든다
        let controller = InputController(output: document, hangulSource: source, startsInHangul: !startsInEnglish, clock: { 0 })
        controller.returnKeyIsDefault = returnKeyIsDefault
        controller.autoCapitalization = autoCapitalization
        controller.doubleSpacePeriod = doubleSpacePeriod
        controller.onWordCommitted = onWordCommitted
        for character in script {
            press(character, controller: controller, document: document, source: source, layout: layout)
        }
        return (document, controller)
    }

    /// 호스트의 `textDidChange` — VC는 `documentContextBeforeInput`으로 sync한다(빈 문서는 nil)
    static func hostNotifies(_ controller: InputController, _ document: HostDocument) {
        controller.syncWithDocument(documentTail: document.text.isEmpty ? nil : document.text)
    }

    private static func press(_ character: Character, controller: InputController, document: HostDocument,
                              source: JamoSource, layout: Layout) {
        switch character {
        case "⏎":
            controller.handle(.return)
            if document.host.notifiesAfterReturn { hostNotifies(controller, document) }
        case "⌫":
            controller.handle(.backspace)
            if document.host.sendsBackspaceEcho { hostNotifies(controller, document) }
        case "␣":
            // 천지인은 조합 중 스페이스가 이동(공백 없음)이다 — 공백을 넣으려면 한 번 더 친다
            if source.spaceAdvancesWhileComposing, controller.mode == .hangul, controller.isComposing {
                controller.handle(.space)
            }
            controller.handle(.space)
        case "#": controller.handle(.symbols)
        case "⇄": controller.handle(.toggleLanguage)
        case "◀":
            controller.syncWithDocument()
            controller.syncWithDocument()
        case "↺": hostNotifies(controller, document)
        case "◆":
            if let chip = multiLineAddress.suggestion(forTail: controller.textTail, isSecureTextEntry: false,
                                                      tailIsTruncated: controller.textTailIsTruncated) {
                controller.insertSnippet(chip)
            }
        default:
            if controller.mode == .hangul, let keys = layout.keys(for: character) {
                for key in keys { controller.handle(.character(key)) }
            } else {
                controller.handle(.character(String(character)))
            }
        }
    }

    static func chip(_ controller: InputController) -> String? {
        address.suggestion(forTail: controller.textTail, isSecureTextEntry: false,
                           tailIsTruncated: controller.textTailIsTruncated)?.trigger
    }

    /// 정답 — 문서 마지막 줄로 판정한 칩
    static func truthChip(_ document: String) -> String? {
        let lastLine = String(document.split(separator: "\n", omittingEmptySubsequences: false).last ?? "")
        return address.suggestion(forTail: lastLine, isSecureTextEntry: false, tailIsTruncated: lastLine.count > 48)?.trigger
    }
}

@MainActor
@Suite("B2 — 호스트 모형")
struct B2HostModelTests {

    @Test("⏎ — 줄바꿈 · 문서 유지 · 비움", arguments: DocumentHost.allCases)
    func returnBehavior(host: DocumentHost) {
        let (document, _) = B2Script.run("서울⏎", host: host, layout: .dubeolsik, returnKeyIsDefault: true)
        let expected = switch host.returnBehavior {
        case .newline: "서울\n"
        case .keepsText: "서울"
        case .clears: ""
        }
        #expect(document.text == expected)
    }

    @Test("⌫ 직후 읽기 — 낡은 getter는 지우기 전 값, nil getter는 nil, 나머지는 지금 문서")
    func readRightAfterDelete() {
        for host in DocumentHost.newlineHosts {
            let (document, _) = B2Script.run("서울⏎⌫", host: host, layout: .dubeolsik, returnKeyIsDefault: true)
            let expected: String? = switch host {
            case .staleGetter: "서울\n"
            case .nilGetter: nil
            default: "서울"
            }
            #expect(document.readRightAfterDelete == expected, "\(host)")
        }
    }

    @Test("대본 — 자판 3종이 같은 문서를 만든다(천지인 공백은 이동 뒤 한 번 더)", arguments: Layout.allCases)
    func layoutsTypeSameText(layout: Layout) {
        let (document, _) = B2Script.run("서울␣주소#,#가ㅈ", host: .silent, layout: layout, returnKeyIsDefault: true)
        #expect(document.text == "서울 주소,갖")
    }
}

// MARK: - B2-A 자동 대문자

/// 열마다 기대 문서 — 메아리 없음(낡은·nil getter 포함) · 메아리 · 제출(문서 유지) · 제출(비움·통지) · 제출(비움·무통지)
struct CapitalizationRow: Sendable, CustomTestStringConvertible {
    let why: String
    let rule: AutoCapitalization
    let script: String
    let startsInEnglish: Bool
    let expected: [DocumentHost.Column: String]

    init(_ why: String, _ rule: AutoCapitalization, _ script: String, startsInEnglish: Bool = true,
         quiet: String, echo: String, keeps: String, clearsNotify: String, clearsSilent: String) {
        self.why = why
        self.rule = rule
        self.script = script
        self.startsInEnglish = startsInEnglish
        expected = [.quiet: quiet, .echo: echo, .keeps: keeps, .clearsNotify: clearsNotify, .clearsSilent: clearsSilent]
    }

    var testDescription: String { why }
}

/// 표는 스위트 밖에 둔다 — `@Test(arguments:)`는 격리 밖에서 평가된다
enum B2CapitalizationRows {

    /// 조사원2 표(`research-v131-b2-b1.md`) 1~4·14·15 + `.words` 행 + 「빈 입력란 ⌫ 먼저」. ★ = 지금(1.3.0)과 달라지는 칸.
    /// 「오늘보다 나쁨」 칸은 계획서 §3-1 한계와 PDR 6절에 적었다 — 실기 B2-0이 그런 호스트를 찾으면 수용 여부를 다시 판단한다
    static let rows: [CapitalizationRow] = [
        // 1 — 메아리 없는 호스트의 원래 증상(지금 HelloX). 제출(문서 유지)은 ⌫가 「o」를 지워 Hell — 소문자가 맞다(지금 HellX).
        //     제출(비움·무통지)은 문서가 비었는데 「Hello」를 되살려 소문자 — ★ 오늘보다 나쁨(계획서가 적은 유일한 경로)
        CapitalizationRow("1 Hello⏎⌫x — 문장 규칙", .sentences, "Hello⏎⌫x",
                          quiet: "Hellox", echo: "Hellox", keeps: "Hellx", clearsNotify: "X", clearsSilent: "x"),
        CapitalizationRow("1′ Hello⏎⌫x — 단어 규칙(.words)도 같다", .words, "Hello⏎⌫x",
                          quiet: "Hellox", echo: "Hellox", keeps: "Hellx", clearsNotify: "X", clearsSilent: "x"),
        // 2 — 빈 문서 첫 글자
        CapitalizationRow("2 x — 빈 문서", .sentences, "x",
                          quiet: "X", echo: "X", keeps: "X", clearsNotify: "X", clearsSilent: "X"),
        // 수용 기준 ② — 빈 입력란 ⌫ 먼저: 자동 대문자 「모름」 = 지금 동작(대문자) 유지
        CapitalizationRow("② ⌫x — 빈 입력란 ⌫ 먼저는 X 유지", .sentences, "⌫x",
                          quiet: "X", echo: "X", keeps: "X", clearsNotify: "X", clearsSilent: "X"),
        CapitalizationRow("②′ ⌫x — 단어 규칙", .words, "⌫x",
                          quiet: "X", echo: "X", keeps: "X", clearsNotify: "X", clearsSilent: "X"),
        // 3 — 추적한 공백을 지우면 이어짐 확실(조사원2 표의 문서 예 「hellx」는 「Hellox」의 오기로 본다 — 자동 대문자가 H를 올린다)
        CapitalizationRow("3 Hello␣⌫x — 추적한 공백을 지움", .sentences, "Hello␣⌫x",
                          quiet: "Hellox", echo: "Hellox", keeps: "Hellox", clearsNotify: "Hellox", clearsSilent: "Hellox"),
        // 4 — ⌫ 없음: 새 줄은 문장 시작. 제출(문서 유지)은 꼬리가 줄 처음으로 남아 HelloX — 백로그 6(B2 범위 밖, 지금과 같음)
        CapitalizationRow("4 Hello⏎x — 새 줄", .sentences, "Hello⏎x",
                          quiet: "Hello\nX", echo: "Hello\nX", keeps: "HelloX", clearsNotify: "X", clearsSilent: "X"),
        // 문장 끝 뒤 ⏎⌫ — 되살린 「Hello. 」가 문장 시작이라 X. 제출(문서 유지)은 ⌫가 공백을 지워 「Hello.」인데도 X —
        // 계획서 §3-1 「.default 한 줄 입력란」 한계, **지금과 같은 결과**(지금도 빈 꼬리 → X)
        CapitalizationRow("Hello.␣⏎⌫x — 문장 끝 뒤", .sentences, "Hello.␣⏎⌫x",
                          quiet: "Hello. X", echo: "Hello. X", keeps: "Hello.X", clearsNotify: "X", clearsSilent: "X"),
        // 되살린 앞부분은 같은 줄이 이어지는 동안 산다 — 공백 하나로 「문서 시작」이 되지 않는다(★ 지금은 Hello X)
        CapitalizationRow("Hello⏎⌫␣x — 되살린 앞부분은 줄이 이어지는 동안 산다", .sentences, "Hello⏎⌫␣x",
                          quiet: "Hello x", echo: "Hello x", keeps: "Hell x", clearsNotify: " X", clearsSilent: " x"),
        // ⏎⌫를 두 번 — 두 번째 ⏎는 되살린 앞부분 + 꼬리를 기억한다
        CapitalizationRow("Hello⏎⌫⏎⌫x — 두 번 반복", .sentences, "Hello⏎⌫⏎⌫x",
                          quiet: "Hellox", echo: "Hellox", keeps: "Helx", clearsNotify: "X", clearsSilent: "x"),
        // ⏎⌫ 뒤 다시 ⏎ — 새 줄이다. 되살린 앞부분을 버린다(제출(문서 유지)은 백로그 6 — 지금과 같은 HellX)
        CapitalizationRow("Hello⏎⌫⏎x — 다시 ⏎하면 새 줄", .sentences, "Hello⏎⌫⏎x",
                          quiet: "Hello\nX", echo: "Hello\nX", keeps: "HellX", clearsNotify: "X", clearsSilent: "X"),
        // ★ 알려진 한계(PDR 「.default 조건과 한계」) — 제출(문서 유지)·메아리 없음에서 ⌫가 지운 글자가 판정을 바꾸는 글자면
        //   되살린 앞부분이 실제보다 한 글자 길어 **오늘보다 나쁘다**(지금 X → x). 계획서 §3-1이 적은 「비움·무통지」 경로와 같은 종류이고,
        //   그런 호스트가 실재하는지는 B2-0 탐침이 본다. 줄바꿈 호스트에서는 맞다(Ax · Hi. Ax)
        CapitalizationRow("★ a⏎⌫x — 제출(문서 유지)에서 ⌫가 첫 글자를 지움", .sentences, "a⏎⌫x",
                          quiet: "Ax", echo: "Ax", keeps: "x", clearsNotify: "X", clearsSilent: "x"),
        CapitalizationRow("★ Hi. a⏎⌫x — 제출(문서 유지)에서 ⌫가 문장 첫 글자를 지움", .sentences, "Hi.␣a⏎⌫x",
                          quiet: "Hi. Ax", echo: "Hi. Ax", keeps: "Hi. x", clearsNotify: "X", clearsSilent: "x"),
        // 한글 ⏎⌫ 뒤 영어 전환 — 자판 3종의 한글 ⌫ 경로를 지난다(천지인 키 로그 · 단모음 연타 상태)
        CapitalizationRow("서울⏎⌫⇄x — 한글 뒤 영어 전환", .sentences, "서울⏎⌫⇄x", startsInEnglish: false,
                          quiet: "서울x", echo: "서울x", keeps: "서x", clearsNotify: "X", clearsSilent: "x")
    ]
}

@MainActor
@Suite("B2-A — ⏎⌫ 뒤 자동 대문자 (리턴 키 .default)")
struct B2CapitalizationTests {

    @Test("★ 표 — 호스트 7종 × 자판 3종", arguments: B2CapitalizationRows.rows, Layout.allCases)
    func table(row: CapitalizationRow, layout: Layout) {
        for host in DocumentHost.allCases {
            let (document, _) = B2Script.run(row.script, host: host, layout: layout, returnKeyIsDefault: true,
                                             autoCapitalization: row.rule, startsInEnglish: row.startsInEnglish)
            #expect(document.text == row.expected[host.column], "\(row.why) · \(host) · \(layout)")
        }
    }

    /// 변이 ③(`returnKeyType` 조건 제거)이 여기서 죽는다 — `.search`·`.go`·`.send`·`.done`는 ⏎가 제출일 수 있어 기억하지 않는다
    @Test("리턴 키가 .default가 아니면 지금 동작 그대로 — 기억하지 않는다", arguments: Layout.allCases)
    func nonDefaultReturnKeyKeepsTodayBehavior(layout: Layout) {
        let today: [DocumentHost.Column: String] = [
            .quiet: "HelloX", .echo: "Hellox", .keeps: "HellX", .clearsNotify: "X", .clearsSilent: "X"
        ]
        for host in DocumentHost.allCases {
            let (document, _) = B2Script.run("Hello⏎⌫x", host: host, layout: layout, returnKeyIsDefault: false,
                                             autoCapitalization: .sentences, startsInEnglish: true)
            #expect(document.text == today[host.column], "\(host) · \(layout)")
        }
    }

    /// 변이 ①(만료 제거)이 여기서 죽는다. 만료되면 「모름」 = 지금 동작(빈 꼬리 → 대문자)이다
    @Test("이력 만료 — ⏎와 ⌫ 사이 다른 키·커서 이동·문맥 sync, ⌫로 앞을 더 지움, 커서 이동 뒤 되살린 앞부분", arguments: [
        ("⏎ 다음 다른 키 — a를 치고 지운 뒤의 ⌫는 줄바꿈을 지워도 모른다", "Hello⏎a⌫⌫x", "HelloX"),
        ("⏎와 ⌫ 사이 커서 이동(◀▶ 왕복)", "Hello⏎◀⌫x", "HelloX"),
        ("⏎와 ⌫ 사이 호스트 textDidChange(외부 편집)", "Hello⏎↺⌫x", "HelloX"),
        ("⌫로 되살린 앞부분까지 더 지움 — 이력은 ⌫ 한 번에만 쓴다", "Hello⏎⌫⌫x", "HellX"),
        ("되살린 뒤 커서 이동 — 앞부분도 버린다(공백 하나면 문서 시작으로 본다, 지금 동작)", "Hello⏎⌫◀␣x", "Hello X")
    ] as [(String, String, String)], Layout.allCases)
    func expiry(row: (why: String, script: String, expected: String), layout: Layout) {
        for host in [DocumentHost.silent, .staleGetter, .nilGetter] {
            let (document, _) = B2Script.run(row.script, host: host, layout: layout, returnKeyIsDefault: true,
                                             autoCapitalization: .sentences, startsInEnglish: true)
            #expect(document.text == row.expected, "\(row.why) · \(host) · \(layout)")
        }
    }

    /// 꼬리가 48자를 넘어 앞을 버리면 되살린 앞부분과 이어지지 않는다 — 앞부분도 버린다(꼬리 잘림과 같은 「앞 모름」)
    @Test("꼬리가 48자를 넘으면 되살린 앞부분을 버린다")
    func prefixDroppedWhenTailOverflows() {
        let script = "Hi⏎⌫." + String(repeating: "␣", count: 48) + "x"
        let (document, controller) = B2Script.run(script, host: .silent, layout: .dubeolsik, returnKeyIsDefault: true,
                                                  autoCapitalization: .sentences, startsInEnglish: true, doubleSpacePeriod: false)
        #expect(controller.textTailIsTruncated, "전제 — 꼬리가 「.」을 버렸다")
        #expect(document.text == "Hi." + String(repeating: " ", count: 48) + "X",
                "꼬리(공백 48)만으로 판정 — 앞부분 「Hi」를 붙이면 소문자가 된다")
    }

    /// 되살린 앞부분은 같은 줄에만 산다 — 여러 줄 본문 채움글을 넣으면 새 줄의 처음이다
    @Test("여러 줄 본문 채움글을 넣으면 되살린 앞부분을 버린다", arguments: Layout.allCases)
    func prefixDroppedByMultiLineSnippet(layout: Layout) {
        let (document, controller) = B2Script.run("Hello⏎⌫␣⇄주소◆⇄x", host: .silent, layout: layout, returnKeyIsDefault: true,
                                                  autoCapitalization: .sentences, startsInEnglish: true)
        #expect(controller.textTailIsTruncated == false, "전제 — 칩이 떴고 본문이 새 줄로 끝났다")
        #expect(document.text == "Hello 첫 줄\nX", "새 줄의 처음 — 앞부분 「Hello 」를 붙이면 소문자가 된다")
    }

    /// B2-A의 뜻 — 메아리 없는 줄바꿈 호스트에서 ⏎ 바로 ⌫는 **안 친 것과 같은 판정**이다(검증 R1).
    /// 스냅샷도 꼬리처럼 **끝 48자만** 담는다(PDR 제약 — 보관 상한, ⏎⌫를 되풀이해도 앞부분이 자라지 않는다). 그래서 공백만 48자 넘게
    /// 이은 줄은 그냥 친 줄처럼 「앞 모름」 = 지금 동작(대문자)이다 — 상한을 없애면(변이 M7) 이 행만 그냥 친 줄과 갈린다.
    /// 「두 칸 마침표」는 꼬리만 본다(C7) — ⏎⌫ 뒤 첫 공백 둘은 그냥 친 줄과 다르므로 여기서는 끈다.
    @Test("⏎⌫는 안 친 것과 같다 — 스냅샷도 꼬리처럼 끝 48자만", arguments: [
        ("Hello⏎⌫x", true),
        ("Hello⏎⌫␣x", true),
        ("Hello.␣⏎⌫x", true),
        ("Hello⏎⌫⏎⌫x", true),
        ("Hi⏎⌫" + String(repeating: "␣", count: 48) + "⏎⌫x", true),
        ("Hi⏎⌫" + String(repeating: "␣", count: 50) + "x", true),
        ("서울⏎⌫⇄x", false)
    ] as [(String, Bool)], [AutoCapitalization.sentences, .words])
    func returnBackspaceIsLikeNeverPressed(row: (script: String, startsInEnglish: Bool), rule: AutoCapitalization) {
        let plain = row.script.replacingOccurrences(of: "⏎⌫", with: "")
        for layout in Layout.allCases {
            let (typed, _) = B2Script.run(plain, host: .silent, layout: layout, returnKeyIsDefault: true,
                                          autoCapitalization: rule, startsInEnglish: row.startsInEnglish, doubleSpacePeriod: false)
            for host in [DocumentHost.silent, .staleGetter, .nilGetter] {
                let (document, _) = B2Script.run(row.script, host: host, layout: layout, returnKeyIsDefault: true,
                                                 autoCapitalization: rule, startsInEnglish: row.startsInEnglish,
                                                 doubleSpacePeriod: false)
                #expect(document.text == typed.text, "\(row.script.count)자 대본 · \(rule) · \(host) · \(layout)")
            }
        }
    }

    /// ⏎ 순간 조합 중이던 글자(천지인 pending 점·자음 순환, 단모음 연타 승격)는 ⏎가 확정해 꼬리에 넣은 뒤 기억한다 —
    /// 메아리 없는 호스트의 답이 메아리 호스트(문서 정답)와 같다(검증 R3 — 검증자 임시 시험 4칸을 옮김)
    @Test("⏎ 순간 조합 중이던 글자도 확정된 글자로 기억한다", arguments: [
        (Layout.cheonjiin, "ㅅㆍ⏎⌫⇄x", "ㅅㆍx"),
        (.cheonjiin, "ㄱㄱ⏎⌫⇄x", "ㅋx"),
        (.danmoeum, "ㄱㄱ⏎⌫⇄x", "ㄲx"),
        (.danmoeum, "ㄱㅏㅏ⏎⌫⇄x", "갸x")
    ] as [(Layout, String, String)])
    func composingAtReturn(row: (layout: Layout, script: String, expected: String)) {
        for host in DocumentHost.newlineHosts {
            let (document, _) = B2Script.run(row.script, host: host, layout: row.layout, returnKeyIsDefault: true,
                                             autoCapitalization: .sentences)
            #expect(document.text == row.expected, "\(row.layout) · \(host)")
        }
    }

    @Test("자동 대문자 규칙이 꺼져 있으면 아무 것도 바꾸지 않는다")
    func noneRuleUntouched() {
        let (document, controller) = B2Script.run("hello⏎⌫x", host: .silent, layout: .dubeolsik, returnKeyIsDefault: true,
                                                  autoCapitalization: .none, startsInEnglish: true)
        #expect(document.text == "hellox")
        #expect(controller.shift == .off)
    }
}

// MARK: - 불변식 C7 — 스냅샷은 자동 대문자 전용

@MainActor
@Suite("B2-A 불변식 C7 — ⏎ 직전 기억은 꼬리·칩·추천단어·학습으로 새지 않는다")
struct B2SnapshotIsolationTests {

    @Test("⏎⌫ 뒤 꼬리는 비고 잘림(앞 모름)이다 — 1.3.0 그대로", arguments: Layout.allCases)
    func tailStaysEmptyAndTruncated(layout: Layout) {
        for script in ["Hello⏎⌫", "서울⏎⌫"] {
            let english = script.hasPrefix("H")
            let (_, controller) = B2Script.run(script, host: .silent, layout: layout, returnKeyIsDefault: true,
                                               autoCapitalization: .sentences, startsInEnglish: english)
            #expect(controller.textTail.isEmpty, "\(script) · \(layout)")
            #expect(controller.textTailIsTruncated, "\(script) · \(layout)")
            #expect(controller.currentWord.isEmpty, "\(script) · \(layout)")
        }
    }

    /// 변이 「스냅샷을 `committedTail`로 복원」이 여기서 죽는다 — 제출(문서 유지) 호스트에서 문서는 「서」인데 꼬리가 「서울」이면
    /// 추천단어 탭이 두 글자를 지워 문서에 없는 글자를 지운다(B5 E14의 한글판)
    @Test("⏎⌫ 뒤 추천단어 탭은 문서에 없는 글자를 지우지 않는다", arguments: Layout.allCases)
    func completeWordDoesNotUseSnapshot(layout: Layout) {
        for host in DocumentHost.allCases {
            let (document, controller) = B2Script.run("서울⏎⌫", host: host, layout: layout, returnKeyIsDefault: true)
            let before = document.text
            let replaced = controller.completeWord("서울역")
            if host.sendsBackspaceEcho {
                // 메아리가 문서로 꼬리를 다시 세웠다 — 문서가 정말 「서울」로 끝나니 바꾸는 게 맞다
                #expect(replaced && document.text == "서울역", "\(host) · \(layout)")
            } else {
                #expect(!replaced, "\(host) · \(layout)")
                #expect(document.text == before, "\(host) · \(layout)")
            }
        }
    }

    /// 변이 M3e(학습이 앞부분을 읽음)가 여기서 죽는다(검증 C1). 제출(문서 유지) 호스트에서 문서는 「서가 」인데 「서울가」를
    /// 배우면 문서에 없는 단어가 학습 사전에 들어간다. 학습은 추적한 꼬리만 본다 — ⏎ 때 「서울」을 한 번 배우고, ⏎⌫ 뒤 「가」는
    /// 한 글자라 배우지 않는다(메아리 호스트는 sync가 학습을 다음 구분자까지 막는다)
    @Test("⏎⌫ 뒤 학습은 되살린 앞부분을 읽지 않는다 — 문서에 없는 「서울가」를 배우지 않는다",
          arguments: ["␣", "⏎"], Layout.allCases)
    func learningDoesNotUseSnapshot(separator: String, layout: Layout) {
        for host in DocumentHost.allCases {
            let learned = LearnedWords()
            let (document, _) = B2Script.run("서울⏎⌫가" + separator, host: host, layout: layout, returnKeyIsDefault: true,
                                             onWordCommitted: { learned.words.append($0) })
            #expect(learned.words == ["서울"], "\(host) · \(layout) · 문서 \(document.text.debugDescription)")
        }
    }
}

/// 학습으로 보낸 단어를 모은다(시험 전용 — 합성 입력뿐)
@MainActor
final class LearnedWords {
    var words: [String] = []
}

// MARK: - 칩 (B2-C 미구현 — 1.3.0 동작 고정)

/// 열마다 (문서, 칩). `knownFalsePositive` — 정답과 다른 칩이 뜨는 열(백로그 6, B2 범위 밖)
struct ChipRow: Sendable, CustomTestStringConvertible {
    let why: String
    let script: String
    let expected: [DocumentHost.Column: Cell]
    let knownFalsePositive: Set<DocumentHost.Column>

    struct Cell: Sendable, Equatable {
        let document: String
        let chip: String?
    }

    init(_ why: String, _ script: String,
         quiet: (String, String?), echo: (String, String?), keeps: (String, String?),
         clearsNotify: (String, String?), clearsSilent: (String, String?),
         knownFalsePositive: Set<DocumentHost.Column> = []) {
        self.why = why
        self.script = script
        expected = [
            .quiet: Cell(document: quiet.0, chip: quiet.1), .echo: Cell(document: echo.0, chip: echo.1),
            .keeps: Cell(document: keeps.0, chip: keeps.1),
            .clearsNotify: Cell(document: clearsNotify.0, chip: clearsNotify.1),
            .clearsSilent: Cell(document: clearsSilent.0, chip: clearsSilent.1)
        ]
        self.knownFalsePositive = knownFalsePositive
    }

    var testDescription: String { why }
}

/// 표는 스위트 밖에 둔다 — `@Test(arguments:)`는 격리 밖에서 평가된다
enum B2ChipRows {

    /// 조사원2 표 5~15. 「메아리 없음」 열의 `서울␣⏎⌫주소`·`⏎⌫주소`는 B2-C가 채택되면 **의도적으로 뒤집을 칸**이다(PDR 5절) —
    /// 이번에는 뒤집지 않는다. `⌫주소`(⑤)는 B2-C에서도 뒤집지 않는다.
    static let rows: [ChipRow] = [
        ChipRow("5 서울⏎⌫주소 — 줄바꿈을 지워 붙었다(1.3.0이 막은 오탐)", "서울⏎⌫주소",
                quiet: ("서울주소", nil), echo: ("서울주소", nil), keeps: ("서주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("6 서울␣⏎⌫주소 — 앞이 공백(메아리 없음 열은 B2-C 칸)", "서울␣⏎⌫주소",
                quiet: ("서울 주소", nil), echo: ("서울 주소", "주소"), keeps: ("서울주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("7 ⌫주소 — 빈 입력란 ⌫ 먼저(⑤ 뒤집지 않는다)", "⌫주소",
                quiet: ("주소", nil), echo: ("주소", "주소"), keeps: ("주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("8 ⏎⌫주소 — 빈 입력란 리턴을 지움(메아리 없음 열은 B2-C 칸)", "⏎⌫주소",
                quiet: ("주소", nil), echo: ("주소", "주소"), keeps: ("주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("9 주소 — 빈 입력란 첫 단축어", "주소",
                quiet: ("주소", "주소"), echo: ("주소", "주소"), keeps: ("주소", "주소"),
                clearsNotify: ("주소", "주소"), clearsSilent: ("주소", "주소")),
        // 제출(문서 유지)에서 ⏎ 뒤 꼬리는 「줄 처음」으로 남는다 — 문서는 「서울주소」인데 칩이 뜬다. 백로그 6(1.3.0부터, B2 범위 밖)
        ChipRow("10 서울⏎주소 — 줄바꿈 뒤", "서울⏎주소",
                quiet: ("서울\n주소", "주소"), echo: ("서울\n주소", "주소"), keeps: ("서울주소", "주소"),
                clearsNotify: ("주소", "주소"), clearsSilent: ("주소", "주소"), knownFalsePositive: [.keeps]),
        ChipRow("11 서울주소 — 붙은 꼴", "서울주소",
                quiet: ("서울주소", nil), echo: ("서울주소", nil), keeps: ("서울주소", nil),
                clearsNotify: ("서울주소", nil), clearsSilent: ("서울주소", nil)),
        ChipRow("12 서울,주소 — 문장부호는 경계", "서울#,#주소",
                quiet: ("서울,주소", "주소"), echo: ("서울,주소", "주소"), keeps: ("서울,주소", "주소"),
                clearsNotify: ("서울,주소", "주소"), clearsSilent: ("서울,주소", "주소")),
        ChipRow("12′ (주소 — 괄호는 경계", "#(#주소",
                quiet: ("(주소", "주소"), echo: ("(주소", "주소"), keeps: ("(주소", "주소"),
                clearsNotify: ("(주소", "주소"), clearsSilent: ("(주소", "주소")),
        ChipRow("12″ 서울2주소 — 숫자는 경계 아님", "서울#2#주소",
                quiet: ("서울2주소", nil), echo: ("서울2주소", nil), keeps: ("서울2주소", nil),
                clearsNotify: ("서울2주소", nil), clearsSilent: ("서울2주소", nil)),
        ChipRow("13 49자 넘는 줄을 ⌫로 다 지운 뒤 주소 — 앞을 모른다(메아리가 오면 풀린다)",
                "#" + String(repeating: "1", count: 61) + "#" + String(repeating: "⌫", count: 61) + "주소",
                quiet: ("주소", nil), echo: ("주소", "주소"), keeps: ("주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("14 서울⏎◀⌫주소 — ⏎와 ⌫ 사이 커서 이동, nil sync를 문서 시작으로 승격하지 않는다", "서울⏎◀⌫주소",
                quiet: ("서울주소", nil), echo: ("서울주소", nil), keeps: ("서주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("14′ 서울␣⏎◀⌫주소 — 앞이 공백이어도 커서 이동 뒤엔 모른다", "서울␣⏎◀⌫주소",
                quiet: ("서울 주소", nil), echo: ("서울 주소", "주소"), keeps: ("서울주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("14″ 서울⏎↺⌫주소 — ⏎와 ⌫ 사이 외부 편집(textDidChange)", "서울⏎↺⌫주소",
                quiet: ("서울주소", nil), echo: ("서울주소", nil), keeps: ("서주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        ChipRow("서울⏎ㅈ⌫⌫주소 — 조합 자모를 지운 뒤 줄바꿈(자판별 ⌫ 경로)", "서울⏎ㅈ⌫⌫주소",
                quiet: ("서울주소", nil), echo: ("서울주소", nil), keeps: ("서주소", nil),
                clearsNotify: ("주소", nil), clearsSilent: ("주소", nil)),
        // 추적한 글자만 지우면 줄 처음 그대로. 제출(문서 유지)은 백로그 6과 같은 뿌리(⏎ 뒤 꼬리가 줄 처음)
        ChipRow("서울⏎가␣⌫⌫주소 — 추적한 글자만 지움", "서울⏎가␣⌫⌫주소",
                quiet: ("서울\n주소", "주소"), echo: ("서울\n주소", "주소"), keeps: ("서울주소", "주소"),
                clearsNotify: ("주소", "주소"), clearsSilent: ("주소", "주소"), knownFalsePositive: [.keeps])
    ]
}

@MainActor
@Suite("B2 — 칩은 1.3.0 그대로 (B2-C 미구현), 리턴 키 종류와 무관")
struct B2ChipTests {

    @Test("표 — 호스트 7종 × 자판 3종 × 리턴 키(.default / 그 밖)", arguments: B2ChipRows.rows, Layout.allCases)
    func table(row: ChipRow, layout: Layout) {
        for returnKeyIsDefault in [true, false] {
            for host in DocumentHost.allCases {
                let (document, controller) = B2Script.run(row.script, host: host, layout: layout,
                                                          returnKeyIsDefault: returnKeyIsDefault)
                let label = "\(row.why) · \(host) · \(layout) · 리턴 키 \(returnKeyIsDefault ? ".default" : "그 밖")"
                let chip = B2Script.chip(controller)
                #expect(document.text == row.expected[host.column]?.document, "\(label) — 전제(문서)")
                #expect(chip == row.expected[host.column]?.chip, "\(label)")
                // 거짓 양성 0 — 칩은 정답이거나 없다. 백로그 6 열만 예외(알려진 오탐, B2 범위 밖)
                let truth = B2Script.truthChip(document.text)
                if row.knownFalsePositive.contains(host.column) {
                    #expect(chip != nil && chip != truth, "\(label) — 백로그 6 칸이 바뀌었다면 표를 고친다")
                } else {
                    #expect(chip == nil || chip == truth, "\(label) — 거짓 양성")
                }
            }
        }
    }

    /// 계획서 §3-1 「모든 호스트 단언」 — 불변식 ③의 핵심 두 경로
    @Test("★ 불변식 — 모든 호스트·자판·리턴 키에서 서울⏎⌫주소 · 서울␣⏎(제출)⌫주소에 칩 없음", arguments: Layout.allCases)
    func noChipOnJoinedAddress(layout: Layout) {
        for returnKeyIsDefault in [true, false] {
            for host in DocumentHost.allCases {
                let (_, joined) = B2Script.run("서울⏎⌫주소", host: host, layout: layout, returnKeyIsDefault: returnKeyIsDefault)
                #expect(B2Script.chip(joined) == nil, "서울⏎⌫주소 · \(host) · \(layout)")
                guard host.returnBehavior != .newline else { continue }
                let (_, submitted) = B2Script.run("서울␣⏎⌫주소", host: host, layout: layout, returnKeyIsDefault: returnKeyIsDefault)
                #expect(B2Script.chip(submitted) == nil, "서울␣⏎(제출)⌫주소 · \(host) · \(layout)")
            }
        }
    }
}
