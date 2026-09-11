import Testing
import TadakDomain
@testable import KeyboardCore

/// 배열 구조 고정 — 이전에는 배열 회귀를 눈으로만 잡았다 (리뷰 지적 해소).
@Suite("LayoutDefinition 구조")
struct LayoutDefinitionTests {

    @Test("숫자 줄을 켜면 두벌식·단모음·쿼티에 1~0 줄이 붙는다")
    func numberRowPrepends() {
        for (mode, hangul): (InputMode, HangulLayout) in
            [(.hangul, .dubeolsik), (.hangul, .danmoeum), (.english, .dubeolsik)] {
            let off = LayoutDefinition.layout(for: mode, hangulLayout: hangul)
            let on = LayoutDefinition.layout(for: mode, hangulLayout: hangul, numberRow: true)
            #expect(on.rows.count == off.rows.count + 1)
            #expect(on.rows[0].map(\.label) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
            #expect(on.rows.dropFirst().map { $0.map(\.id) } == off.rows.map { $0.map(\.id) },
                    "숫자 줄 외 나머지 행은 그대로여야 한다")
        }
    }

    // MARK: - 기준 열 수 (UX-8 — 높이·폭 상한이 여기서 나온다)

    /// 검증자 실측 2026-09-09: 높이 공식이 10열을 하드코딩해 천지인 키가 203.5 x 69.0 = **2.95 : 1**까지
    /// 벌어졌다. `referenceUnits`가 자판마다 옳은 값을 내야 그 공식이 닫힌다. 값을 여기서 고정한다.
    @Test("자판별 기준 열 수 — 행마다 폭 합이 달라도 문자 행의 열 수가 나온다")
    func referenceUnitsPerLayout() {
        #expect(LayoutDefinition.dubeolsik.referenceUnits == 10)   // 행 폭 합 10 / 9 / 9.8 / 9.6
        #expect(LayoutDefinition.qwerty.referenceUnits == 10)
        #expect(LayoutDefinition.danmoeum.referenceUnits == 8)     // 8 / 8 / 8 / 9.6 — 하단 행에 끌려가면 안 된다
        #expect(LayoutDefinition.cheonjiin.referenceUnits == 4)
        #expect(LayoutDefinition.symbols.referenceUnits == 10)
        #expect(LayoutDefinition.symbolsAlternate.referenceUnits == 10)
        for kind in [NumberPadKind.plain, .decimal, .phone] {
            #expect(LayoutDefinition.numberPad(kind).referenceUnits == 3, "숫자 패드는 3열이다")
        }
    }

    /// 숫자 줄은 **한 행**이고 문자 행은 두세 행이다 — 최빈값이라 숫자 줄에 끌려가지 않는다.
    /// (첫 행을 기준으로 삼았다면 숫자 줄을 켠 단모음이 10열로 잘못 잡힌다.)
    @Test("숫자 줄을 켜도 기준 열 수는 문자 행을 따른다")
    func referenceUnitsIgnoresNumberRow() {
        let danmoeum = LayoutDefinition.layout(for: .hangul, hangulLayout: .danmoeum, numberRow: true)
        #expect(danmoeum.rows[0].count == 10, "숫자 줄이 실제로 붙어 있어야 이 테스트가 의미가 있다")
        #expect(danmoeum.referenceUnits == 8)

        let dubeolsik = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, numberRow: true)
        #expect(dubeolsik.referenceUnits == 10)
    }

    /// 지구본이 빠지면 하단 행 폭이 다시 짜인다 — 문자 행은 그대로이므로 기준도 그대로여야 한다.
    @Test("지구본 제거·길게 누르기 기호 부착은 기준 열 수를 바꾸지 않는다")
    func referenceUnitsStableAcrossVariants() {
        for hangul in [HangulLayout.dubeolsik, .danmoeum, .cheonjiin] {
            let base = LayoutDefinition.layout(for: .hangul, hangulLayout: hangul)
            let noGlobe = LayoutDefinition.layout(for: .hangul, hangulLayout: hangul,
                                                 inputModeSwitchKey: false)
            let withSymbols = LayoutDefinition.layout(for: .hangul, hangulLayout: hangul,
                                                     longPressSymbols: true)
            #expect(noGlobe.referenceUnits == base.referenceUnits)
            #expect(withSymbols.referenceUnits == base.referenceUnits)
        }
    }

    @Test("천지인과 기호 자판에는 숫자 줄이 붙지 않는다")
    func numberRowExclusions() {
        let cheonjiin = LayoutDefinition.layout(for: .hangul, hangulLayout: .cheonjiin, numberRow: true)
        #expect(cheonjiin.rows.count == LayoutDefinition.cheonjiin.rows.count)
        let symbols = LayoutDefinition.layout(for: .symbols, hangulLayout: .dubeolsik, numberRow: true)
        #expect(symbols.rows.count == LayoutDefinition.symbols.rows.count)
    }

    /// Apple 10키 원형 배열 고정 (2026-09-01 개정, 2026-09-07 우측 열 ⌫·⏎·문장부호 — cheonjiin-danmoeum-layouts.md)
    @Test("천지인은 Apple 원형 — 우측 열 ⌫·⏎·문장부호, ㅇㅁ 4행 2열, 행 폭 합 4.0, 한글 키 28pt")
    func cheonjiinMatchesAppleForm() {
        let rows = LayoutDefinition.cheonjiin.rows
        #expect(rows.count == 4)
        #expect(rows[0].map(\.label) == ["ㅣ", "ㆍ", "ㅡ", "⌫"])
        #expect(rows[1].map(\.label) == ["ㄱㅋ", "ㄴㄹ", "ㄷㅌ", "⏎"])
        #expect(rows[2].map(\.label) == ["ㅂㅍ", "ㅅㅎ", "ㅈㅊ", "."])
        #expect(rows[2][3].id == "punct" && rows[2][3].alternate == .character(","), "→ 자리에 문장부호 키")
        #expect(rows[3].map(\.id) == ["symbols", "cj-ㅇ", "space", "globe", "language"])
        #expect(!rows.flatMap { $0 }.contains { $0.event == .advance }, "→(이동) 키는 빠졌다 — 조합 중 스페이스가 대신한다")
        for row in rows {
            #expect(row.reduce(0) { $0 + $1.width } == 4.0, "열 경계 정렬 — 행 폭 합 4.0")
        }
        for key in rows.flatMap({ $0 }) {
            if (key.id.hasPrefix("cj-") && { if case .character = key.event { return true } else { return false } }())
                || key.id == "punct" {
                #expect(key.labelSize == 28, "\(key.id) 한글 키·문장부호 키 라벨 28pt")
            } else {
                #expect(key.labelSize == nil, "\(key.id)")
            }
        }
        // 다른 자판은 labelSize를 쓰지 않는다 (UI 기본)
        #expect(LayoutDefinition.dubeolsik.rows.flatMap { $0 }.allSatisfy { $0.labelSize == nil })
    }

    @Test("모든 자판의 하단 행에 지구본 키가 있다 — 심사 필수 요건")
    func globeKeyExistsEverywhere() {
        for layout in [LayoutDefinition.dubeolsik, .cheonjiin, .danmoeum, .qwerty,
                       .symbols, .symbolsAlternate] {
            #expect(layout.rows.last?.contains { $0.id == "globe" } == true)
        }
    }

    /// PDR field-traits-and-live-settings
    @Test("숫자 패드 3종 — 1~9 3열, 하단 [보조 0.5][지구본 0.5][0][⌫], 행 폭 3, 리턴 없음, 숫자 줄 미부착")
    func numberPadStructure() {
        let expectations: [(NumberPadKind, String?, KeyEvent)] = [
            (.plain, "np-spacer", .spacer),
            (.decimal, "np-dot", .character(".")),
            (.phone, "np-plus", .character("+"))
        ]
        for (kind, auxiliaryID, auxiliaryEvent) in expectations {
            let layout = LayoutDefinition.layout(for: .numberPad(kind), hangulLayout: .dubeolsik, numberRow: true)
            #expect(layout.rows.count == 4, "숫자 줄이 붙지 않는다")
            #expect(layout.rows[0].map(\.label) == ["1", "2", "3"])
            #expect(layout.rows[1].map(\.label) == ["4", "5", "6"])
            #expect(layout.rows[2].map(\.label) == ["7", "8", "9"])
            let bottom = layout.rows[3]
            #expect(bottom.map(\.id) == [auxiliaryID, "globe", "np-0", "backspace"])
            #expect(bottom[0].event == auxiliaryEvent)
            #expect(bottom[0].width == 0.5 && bottom[1].width == 0.5)
            for row in layout.rows {
                #expect(row.reduce(0) { $0 + $1.width } == 3.0, "열 경계 정렬 — 행 폭 합 3.0")
            }
            #expect(!layout.rows.flatMap { $0 }.contains { $0.event == .return }, "Apple 숫자 패드처럼 리턴 없음")
        }
    }

    @Test("천지인 스페이스는 아이콘 심볼을 갖고, 다른 자판의 스페이스는 갖지 않는다")
    func cheonjiinSpaceHasSymbol() {
        let cheonjiinSpace = LayoutDefinition.cheonjiin.rows[3].first { $0.event == .space }
        #expect(cheonjiinSpace?.symbol == "space")
        let dubeolsikSpace = LayoutDefinition.dubeolsik.rows[3].first { $0.event == .space }
        #expect(dubeolsikSpace?.symbol == nil)
    }

    @Test("relabeled는 라벨·심볼만 바꾸고 나머지는 보존한다")
    func relabeledPreservesIdentity() {
        let returnKey = LayoutDefinition.dubeolsik.rows[3].first { $0.event == .return }!
        let done = returnKey.relabeled(label: "완료", symbol: "checkmark")
        #expect(done.id == returnKey.id && done.event == .return && done.width == returnKey.width)
        #expect(done.label == "완료" && done.symbol == "checkmark")
        // 기본 ⏎는 SF Symbol `return`을 갖는다 (2026-09-07 아이콘 확대). 텍스트 라벨(검색·이동)로 덮어쓸 때는
        // symbol을 nil로 넘겨 글자가 보이고, 심볼을 그대로 넘기면 원본과 같다
        #expect(returnKey.symbol == "return")
        let search = returnKey.relabeled(label: "검색", symbol: nil)
        #expect(search.label == "검색" && search.symbol == nil && search.id == returnKey.id && search.event == .return)
        #expect(returnKey.relabeled(symbol: "return") == returnKey)
    }

    @Test("모든 ⌫·⏎·⇧ 키는 SF Symbol 표면을 갖는다 (delete.left · return · shift)")
    func backspaceAndReturnUseSymbols() {
        let layouts: [LayoutDefinition] = [.dubeolsik, .cheonjiin, .danmoeum, .qwerty, .symbols, .symbolsAlternate,
                                           .numberPad(.plain)]
        for layout in layouts {
            for key in layout.rows.flatMap({ $0 }) {
                if key.event == .backspace { #expect(key.symbol == "delete.left" && key.label == "⌫") }
                if key.event == .return { #expect(key.symbol == "return" && key.label == "⏎") }
                if key.event == .shift { #expect(key.symbol == "shift" && key.label == "⇧") }
            }
        }
    }

    @Test("단모음 3행은 스페이서 1 + ㅋㅌㅊㅍㅜㅡ + ⌫ 1 = 8폭 — 위 행과 열이 맞고 글자가 가운데 온다")
    func danmoeumThirdRowIsCentered() {
        let rows = LayoutDefinition.danmoeum.rows
        let third = rows[2]
        #expect(third.first?.event == .spacer, "왼쪽 스페이서")
        #expect(third.first?.width == 1.0)
        #expect(third.dropFirst().dropLast().map(\.label) == ["ㅋ", "ㅌ", "ㅊ", "ㅍ", "ㅜ", "ㅡ"])
        #expect(third.last?.event == .backspace)
        #expect(third.last?.width == 1.0)
        // 행 폭 합이 위 두 행(8)과 같아야 키 폭이 같고 열 경계가 맞는다
        let widths = rows.prefix(3).map { $0.reduce(0) { $0 + $1.width } }
        #expect(widths == [8, 8, 8])
        // 스페이서 폭 == ⌫ 폭 이어야 글자 블록이 정확히 가운데다
        #expect(third.first?.width == third.last?.width)
    }

    /// #+= 버그 수정 고정 — 기호 2페이지가 존재하고 페이지 키가 페이지 전환 이벤트를 낸다.
    /// 2026-09-04 사용자 요청: 두 페이지 모두 5행 — 괄호·특수문자 줄이 1페이지 숫자 아래로, 2페이지는 다른
    /// 특수문자 3줄. 4행 왼쪽 키가 페이지를 오간다.
    @Test("기호 자판은 두 페이지 5행이며 4행 왼쪽 키가 페이지를 오간다")
    func symbolPagesToggleEachOther() {
        let page1 = LayoutDefinition.symbols.rows[3][0]
        let page2 = LayoutDefinition.symbolsAlternate.rows[3][0]
        #expect(page1.label == "#+=" && page1.event == .symbolsAlternate)
        #expect(page2.label == "123" && page2.event == .symbolsAlternate)
        #expect(LayoutDefinition.symbols.rows[0].map(\.label) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        #expect(LayoutDefinition.symbols.rows[1].map(\.label) == ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
                "괄호·특수문자 줄은 1페이지 숫자 바로 아래")
        #expect(LayoutDefinition.symbols.rows[2].map(\.label) == ["-", "/", ":", ";", "(", ")", "₩", "&", "@", "\""])
        #expect(LayoutDefinition.symbolsAlternate.rows[0].map(\.label)
                == ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"])
        for layout in [LayoutDefinition.symbols, .symbolsAlternate] {
            #expect(layout.rows.count == 5)
            for row in layout.rows.prefix(3) {
                #expect(row.count == 10 && row.allSatisfy { $0.width == 1 }, "문자 줄은 10키 균등")
                #expect(row.allSatisfy { if case .character = $0.event { true } else { false } })
            }
            #expect(layout.rows[3].map(\.label).dropFirst().dropLast() == [".", ",", "?", "!", "'"])
            #expect(layout.rows[3].last?.event == .backspace)
            // 하단 ABC는 문자 모드 복귀(.symbols), 한영 키는 기호 페이지에 없다 (Apple 동일)
            let bottom = layout.rows[4]
            #expect(bottom.first?.label == "ABC" && bottom.first?.event == .symbols)
            #expect(!bottom.contains { $0.id == "language" })
        }
        // 두 페이지 문자 줄을 합쳐 같은 글자가 두 번 나오지 않는다 (. , ? ! ' 4행은 공통이라 제외)
        let page1Characters = LayoutDefinition.symbols.rows.prefix(3).flatMap { $0 }.map(\.label)
        let page2Characters = LayoutDefinition.symbolsAlternate.rows.prefix(3).flatMap { $0 }.map(\.label)
        #expect(Set(page1Characters + page2Characters).count == page1Characters.count + page2Characters.count,
                "특수문자 중복 없음")
        #expect(LayoutDefinition.layout(for: .symbolsAlternate, hangulLayout: .dubeolsik).rows.count == 5)
    }

    // MARK: - 지구본 없는 환경 (2026-09-04 사용자 요청 — 스페이스 왼쪽 빈 칸 제거)

    private func widthSum(_ row: [LayoutDefinition.Key]) -> Double {
        row.reduce(0) { $0 + $1.width }
    }

    private func approximately(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 1e-9
    }

    @Test("지구본이 필요 없으면 한영 키가 지구본 자리로 오고 스페이스가 한영 자리를 흡수한다")
    func withoutGlobeLanguageKeyMovesLeftAndSpaceWidens() {
        for (mode, hangul): (InputMode, HangulLayout) in
            [(.hangul, .dubeolsik), (.hangul, .danmoeum), (.english, .dubeolsik)] {
            let with = LayoutDefinition.layout(for: mode, hangulLayout: hangul)
            let without = LayoutDefinition.layout(for: mode, hangulLayout: hangul, inputModeSwitchKey: false)
            let bottom = without.rows.last!
            #expect(bottom.map(\.id) == ["symbols", "language", "space", "punct", "return"])
            #expect(!without.rows.flatMap { $0 }.contains { $0.id == "globe" })
            #expect(approximately(widthSum(bottom), widthSum(with.rows.last!)), "행 폭 합 유지 — 다른 키 크기 불변")
            #expect(approximately(bottom[1].width, 1.2), "한영은 지구본 폭")
            #expect(approximately(bottom[2].width, 4.4), "스페이스 3.2 + 한영 1.2")
            #expect(approximately(bottom[3].width, 1.2), "문장부호 키는 그대로")
            #expect(without.rows.dropLast().map { $0.map(\.id) } == with.rows.dropLast().map { $0.map(\.id) },
                    "하단 행만 바뀐다")
        }
        // 숫자 줄과 함께여도 하단 행 규칙은 같다
        let withNumberRow = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik,
                                                    numberRow: true, inputModeSwitchKey: false)
        #expect(withNumberRow.rows.count == 5)
        #expect(withNumberRow.rows.last?.map(\.id) == ["symbols", "language", "space", "punct", "return"])
    }

    @Test("지구본이 필요 없으면 기호·숫자 패드·천지인도 빈 칸 없이 채운다")
    func withoutGlobeOtherLayoutsFillTheGap() {
        // 기호: 한영 키가 없다 — 스페이스가 지구본 폭을 흡수
        for mode in [InputMode.symbols, .symbolsAlternate] {
            let bottom = LayoutDefinition.layout(for: mode, hangulLayout: .dubeolsik, inputModeSwitchKey: false).rows.last!
            #expect(bottom.map(\.id) == ["symbols", "space", "return"], "기호 자판에는 문장부호 키가 없다")
            #expect(approximately(bottom[1].width, 6.8), "스페이스 5.6 + 지구본 1.2")
        }
        // 천지인: 지구본·한영이 한 칸을 나눠 쓰던 것 → 한영이 칸 전체 (행 폭 합 4.0 유지 — ㅇㅁ 열 정렬)
        let cheonjiin = LayoutDefinition.layout(for: .hangul, hangulLayout: .cheonjiin, inputModeSwitchKey: false)
        #expect(cheonjiin.rows[3].map(\.id) == ["symbols", "cj-ㅇ", "space", "language"])
        #expect(cheonjiin.rows[3].last?.width == 1.0)
        #expect(widthSum(cheonjiin.rows[3]) == 4.0)
        // 숫자 패드: 보조 키가 지구본 폭을 흡수 (0·⌫ 열은 그대로, 행 폭 합 3.0)
        for kind in [NumberPadKind.plain, .decimal, .phone] {
            let pad = LayoutDefinition.layout(for: .numberPad(kind), hangulLayout: .dubeolsik, inputModeSwitchKey: false)
            #expect(pad.rows[3].count == 3 && pad.rows[3][1].id == "np-0" && pad.rows[3][2].id == "backspace")
            #expect(pad.rows[3][0].width == 1.0)
            #expect(widthSum(pad.rows[3]) == 3.0)
        }
    }

    @Test("지구본이 필요하면(기본) 배열은 그대로다")
    func withGlobeIsUnchanged() {
        let plain = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik)
        let explicit = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, inputModeSwitchKey: true)
        #expect(plain == explicit && plain == .dubeolsik)
        #expect(LayoutDefinition.dubeolsik.removingGlobe().removingGlobe()
                == LayoutDefinition.dubeolsik.removingGlobe(), "지구본이 이미 없으면 아무것도 안 한다")
    }

    // MARK: - 문장부호 키 (2026-09-04 사용자 요청 — 스페이스 오른쪽, 입력란 종류를 따른다)

    @Test("두벌식·단모음·쿼티 하단 행에는 스페이스 바로 오른쪽에 문장부호 키가 있고, 기본은 . 탭 / , 길게")
    func punctuationKeyFollowsSpace() {
        for layout in [LayoutDefinition.dubeolsik, .danmoeum, .qwerty] {
            let bottom = layout.rows.last!
            let spaceIndex = bottom.firstIndex { $0.event == .space }!
            let punct = bottom[spaceIndex + 1]
            #expect(punct.id == "punct")
            #expect(punct.label == "." && punct.event == .character("."))
            #expect(punct.alternate == .character(",") && punct.alternateLabel == ",")
            #expect(!punct.isFunctionKey, "문자 키 표면")
            #expect(approximately(widthSum(bottom), 9.6), "행 폭 합은 이전과 같다")
        }
        // 지구본 없는 변형에서도 스페이스 오른쪽 자리를 지킨다
        let noGlobe = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, inputModeSwitchKey: false).rows.last!
        #expect(noGlobe.map(\.id) == ["symbols", "language", "space", "punct", "return"])
    }

    @Test("기호·숫자 패드에는 문장부호 키가 없고, 천지인은 3행 우측에 있으며 입력란 종류를 따른다")
    func punctuationKeyExclusions() {
        for layout in [LayoutDefinition.symbols, .symbolsAlternate, .numberPad(.plain)] {
            #expect(!layout.rows.flatMap { $0 }.contains { $0.id == "punct" })
        }
        let email = LayoutDefinition.layout(for: .hangul, hangulLayout: .cheonjiin, punctuation: .email)
        #expect(email.rows[2][3].id == "punct" && email.rows[2][3].label == "@"
                && email.rows[2][3].alternate == .character("."))
        #expect(email.rows[2][3].width == 1.0, "자리·폭 유지")
        #expect(email.rows[2][3].labelSize == 28, "입력란 종류로 내용을 바꿔도 글자 크기 유지")
        #expect(email.rows.map { $0.map(\.id) } == LayoutDefinition.cheonjiin.rows.map { $0.map(\.id) })
    }

    @Test("입력란 종류별 문장부호 키 — 이메일 @/. , 주소 ./.com , 기본 ./,")
    func punctuationKeyFollowsFieldKind() {
        func punct(_ spec: PunctuationKeySpec, mode: InputMode = .english) -> LayoutDefinition.Key {
            LayoutDefinition.layout(for: mode, hangulLayout: .dubeolsik, punctuation: spec)
                .rows.last!.first { $0.id == "punct" }!
        }
        let email = punct(.email)
        #expect(email.label == "@" && email.event == .character("@") && email.alternate == .character("."))
        let url = punct(.url)
        #expect(url.label == "." && url.event == .character(".") && url.alternate == .character(".com"))
        #expect(url.alternateLabel == ".com")
        let standard = punct(.standard, mode: .hangul)
        #expect(standard.label == "." && standard.alternate == .character(","))
        // 내용만 바뀌고 자리·폭은 그대로
        let base = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik).rows.last!
        let withEmail = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, punctuation: .email).rows.last!
        #expect(base.map(\.id) == withEmail.map(\.id))
        #expect(base.map(\.width) == withEmail.map(\.width))
        // 기호 자판에는 적용할 키가 없어 그대로
        #expect(LayoutDefinition.layout(for: .symbols, hangulLayout: .dubeolsik, punctuation: .email) == .symbols)
        // 지구본 없음 + 이메일 조합
        let combo = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik,
                                            inputModeSwitchKey: false, punctuation: .email).rows.last!
        #expect(combo.map(\.id) == ["symbols", "language", "space", "punct", "return"])
        #expect(combo[3].label == "@")
    }

    @Test("relabeled·resized는 길게 누르기 대체 입력을 보존한다")
    func copiesPreserveAlternate() {
        let punct = LayoutDefinition.dubeolsik.rows.last!.first { $0.id == "punct" }!
        #expect(punct.resized(width: 2).alternate == .character(","))
        #expect(punct.relabeled(label: "x", symbol: nil).alternate == .character(","))
    }

    @Test("길게 누르기 기호 — 기호 자판 1페이지(숫자 줄 제외)와 같은 배열이 두벌식·단모음·쿼티 문자 키에 자리 순서로 붙는다")
    func longPressSymbolsMatchSymbolsKeyboard() {
        // 표는 기호 자판에서 파생된다 — 기호 자판을 고치면 길게 누르기도 같이 바뀐다
        #expect(LayoutDefinition.longPressSymbolRows == [
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
            ["-", "/", ":", ";", "(", ")", "₩", "&", "@", "\""],
            [".", ",", "?", "!", "'"]
        ])
        func alternates(_ layout: LayoutDefinition, row: Int) -> [String?] {
            layout.rows[row].filter { !$0.isFunctionKey && $0.event != .spacer }.map(\.alternateLabel)
        }
        for layout in [LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, longPressSymbols: true),
                       LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, longPressSymbols: true)] {
            #expect(alternates(layout, row: 0) == ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
            #expect(alternates(layout, row: 1) == ["-", "/", ":", ";", "(", ")", "₩", "&", "@"], "9키 — 마지막 \" 없음")
            #expect(alternates(layout, row: 2) == [".", ",", "?", "!", "'", nil, nil], "7키에 기호 5개 — ㅜ·ㅡ(n·m) 없음")
        }
        let danmoeum = LayoutDefinition.layout(for: .hangul, hangulLayout: .danmoeum, longPressSymbols: true)
        #expect(alternates(danmoeum, row: 0) == ["[", "]", "{", "}", "#", "%", "^", "*"])
        #expect(alternates(danmoeum, row: 1) == ["-", "/", ":", ";", "(", ")", "₩", "&"])
        #expect(alternates(danmoeum, row: 2) == [".", ",", "?", "!", "'", nil])
        // 하단 행은 그대로 — 문장부호 키는 자기 대체 입력(,)을 지키고 나머지는 없다
        let bottom = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, longPressSymbols: true).rows.last!
        #expect(bottom.first { $0.id == "punct" }!.alternate == .character(","))
        #expect(bottom.filter { $0.id != "punct" }.allSatisfy { $0.alternate == nil })
        // 라벨·시프트 라벨·폭·이벤트는 변하지 않는다
        let with = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, longPressSymbols: true)
        let without = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik)
        #expect(with.rows.map { $0.map(\.id) } == without.rows.map { $0.map(\.id) })
        #expect(with.rows.map { $0.map(\.shiftedLabel) } == without.rows.map { $0.map(\.shiftedLabel) })
        #expect(with.rows.map { $0.map(\.width) } == without.rows.map { $0.map(\.width) })
        #expect(with.rows.map { $0.map(\.event) } == without.rows.map { $0.map(\.event) })
    }

    @Test("길게 누르기 기호 — 꺼져 있으면 없고, 천지인·기호·숫자 패드는 켜도 없으며, 숫자 줄 키에는 붙지 않는다")
    func longPressSymbolsExclusions() {
        let off = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik)
        #expect(off.rows.flatMap { $0 }.filter { $0.alternate != nil }.map(\.id) == ["punct"], "기본은 문장부호 키만")
        let cases: [(InputMode, HangulLayout)] = [
            (.hangul, .cheonjiin), (.symbols, .dubeolsik), (.symbolsAlternate, .dubeolsik), (.numberPad(.plain), .dubeolsik)
        ]
        for (mode, hangul) in cases {
            #expect(LayoutDefinition.layout(for: mode, hangulLayout: hangul, longPressSymbols: true)
                    == LayoutDefinition.layout(for: mode, hangulLayout: hangul), "\(mode) \(hangul)")
        }
        let numberRow = LayoutDefinition.layout(for: .english, hangulLayout: .dubeolsik, numberRow: true, longPressSymbols: true)
        #expect(numberRow.rows[0].allSatisfy { $0.alternate == nil }, "숫자 줄에는 기호 없음")
        #expect(numberRow.rows[1].map(\.alternateLabel) == ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="], "숫자 줄 아래 첫 문자 행부터")
        // 지구본 제거 + 이메일 문장부호와 조합해도 기호와 문장부호 대체 입력이 함께 산다
        let combo = LayoutDefinition.layout(for: .hangul, hangulLayout: .dubeolsik, inputModeSwitchKey: false,
                                            punctuation: .email, longPressSymbols: true)
        #expect(combo.rows[0].map(\.alternateLabel) == ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="])
        #expect(combo.rows.last!.first { $0.id == "punct" }!.alternate == .character("."))
        #expect(combo.rows.last!.map(\.id) == ["symbols", "language", "space", "punct", "return"])
    }
}
