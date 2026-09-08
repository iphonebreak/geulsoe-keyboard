import TadakDomain

/// 자판 그리드 데이터. UI는 이것을 그리기만 하고 해석하지 않는다.
public struct LayoutDefinition: Equatable, Sendable {

    public struct Key: Equatable, Sendable, Identifiable {
        public let id: String
        /// 평시 라벨
        public let label: String
        /// 시프트 시 라벨 (없으면 평시와 동일)
        public let shiftedLabel: String
        public let event: KeyEvent
        /// 행 안에서의 상대 폭 (1.0 = 문자 키 기준)
        public let width: Double
        public let isFunctionKey: Bool
        /// 라벨 대신 그릴 SF Symbol 이름 (있으면 UI가 아이콘을 우선한다 — 천지인 스페이스, ✓ 리턴)
        public let symbol: String?
        /// 길게 누르면 `event` 대신 나가는 이벤트 (문장부호 키 — `.` 길게 → `,`, 설정을 켜면 문자 키의 기호
        /// `addingLongPressSymbols`). nil이면 길게 누르기 없음.
        /// UI는 `alternateLabel`을 키 귀퉁이에 작게 보여주고, 길게 눌러 무장되면 라벨을 바꿔 알린다.
        public let alternate: KeyEvent?
        /// 라벨 글자 크기(pt). nil이면 UI 기본(문자 키 22·기능 키 16). 천지인처럼 넓은 키의 자판이 데이터로 키운다.
        public let labelSize: Double?

        public init(id: String, label: String, shiftedLabel: String? = nil,
                    event: KeyEvent, width: Double = 1, isFunctionKey: Bool = false,
                    symbol: String? = nil, alternate: KeyEvent? = nil, labelSize: Double? = nil) {
            self.id = id
            self.label = label
            self.shiftedLabel = shiftedLabel ?? label
            self.event = event
            self.width = width
            self.isFunctionKey = isFunctionKey
            self.symbol = symbol
            self.alternate = alternate
            self.labelSize = labelSize
        }

        /// 길게 누르기 대체 입력의 표시 라벨 (문자 이벤트만 — 그 문자열 자체)
        public var alternateLabel: String? {
            if case .character(let text)? = alternate { return text }
            return nil
        }

        /// 라벨·심볼만 바꾼 복사 — 리턴 키를 입력란 `returnKeyType`에 맞춰 덮어쓸 때 (UI 계층)
        public func relabeled(label: String? = nil, symbol: String?) -> Key {
            Key(id: id, label: label ?? self.label, shiftedLabel: shiftedLabel, event: event,
                width: width, isFunctionKey: isFunctionKey, symbol: symbol, alternate: alternate,
                labelSize: labelSize)
        }

        /// 폭만 바꾼 복사 — 지구본이 빠질 때 이웃 키가 그 폭을 흡수한다 (`removingGlobe`)
        public func resized(width: Double) -> Key {
            Key(id: id, label: label, shiftedLabel: shiftedLabel, event: event,
                width: width, isFunctionKey: isFunctionKey, symbol: symbol, alternate: alternate,
                labelSize: labelSize)
        }

        /// 길게 누르기 대체 입력만 바꾼 복사 — 문자 키에 기호를 붙일 때 (`addingLongPressSymbols`)
        public func withAlternate(_ alternate: KeyEvent?) -> Key {
            Key(id: id, label: label, shiftedLabel: shiftedLabel, event: event,
                width: width, isFunctionKey: isFunctionKey, symbol: symbol, alternate: alternate,
                labelSize: labelSize)
        }
    }

    public let rows: [[Key]]

    // MARK: - 두벌식 (4행)

    public static let dubeolsik: LayoutDefinition = {
        func character(_ key: String, _ label: String, _ shifted: String? = nil) -> Key {
            Key(id: "hangul-\(key)", label: label, shiftedLabel: shifted, event: .character(key))
        }
        return LayoutDefinition(rows: [
            [
                character("q", "ㅂ", "ㅃ"), character("w", "ㅈ", "ㅉ"), character("e", "ㄷ", "ㄸ"),
                character("r", "ㄱ", "ㄲ"), character("t", "ㅅ", "ㅆ"), character("y", "ㅛ"),
                character("u", "ㅕ"), character("i", "ㅑ"), character("o", "ㅐ", "ㅒ"),
                character("p", "ㅔ", "ㅖ")
            ],
            [
                character("a", "ㅁ"), character("s", "ㄴ"), character("d", "ㅇ"),
                character("f", "ㄹ"), character("g", "ㅎ"), character("h", "ㅗ"),
                character("j", "ㅓ"), character("k", "ㅏ"), character("l", "ㅣ")
            ],
            [
                shiftKey(width: 1.4),
                character("z", "ㅋ"), character("x", "ㅌ"), character("c", "ㅊ"),
                character("v", "ㅍ"), character("b", "ㅠ"), character("n", "ㅜ"),
                character("m", "ㅡ"),
                backspaceKey(width: 1.4)
            ],
            bottomRow(languageLabel: "ABC")
        ])
    }()

    // MARK: - 영어 쿼티 (4행)

    public static let qwerty: LayoutDefinition = {
        func character(_ letter: String) -> Key {
            Key(id: "en-\(letter)", label: letter, shiftedLabel: letter.uppercased(),
                event: .character(letter))
        }
        return LayoutDefinition(rows: [
            "qwertyuiop".map { character(String($0)) },
            "asdfghjkl".map { character(String($0)) },
            [shiftKey(width: 1.4)]
                + "zxcvbnm".map { character(String($0)) }
                + [backspaceKey(width: 1.4)],
            bottomRow(languageLabel: "한글")
        ])
    }()

    // MARK: - 천지인 (4행 × 4열 그리드)
    //
    // Apple 10키 원형에 맞춘 배열 (2026-09-01 사용자 요청 — 애플 근접화):
    // 우측 열 = 기능열, **ㅇㅁ은 Apple과 같은 4행 2열**. 남은 차이는 스페이스가 하단 행에 있는 것과
    // 서드파티 필수 키(지구본·한영).
    // 2026-09-07 개정 (사용자 요청): 우측 열을 ⌫ · ⏎ · 문장부호(./,)로 — →(이동) 키를 빼고 그 역할은
    // **조합 중 스페이스**가 맡는다 (Apple 10키 원형, `JamoSource.spaceAdvancesWhileComposing`).
    // 한글 키 라벨은 28pt(`labelSize`) — 4열의 넓은 키에 22pt는 작다는 피드백.
    // 키 id의 자모가 그대로 JamoSource 키다. 자음 키 라벨은 순환 순서 앞 두 개를 보여준다.
    // 배열·동작 근거: docs/design-reviews/cheonjiin-danmoeum-layouts.md

    public static let cheonjiin: LayoutDefinition = {
        func jamo(_ key: String, _ label: String) -> Key {
            Key(id: "cj-\(key)", label: label, event: .character(key), labelSize: 28)
        }
        return LayoutDefinition(rows: [
            [
                jamo("ㅣ", "ㅣ"), jamo("ㆍ", "ㆍ"), jamo("ㅡ", "ㅡ"),
                backspaceKey()
            ],
            [
                jamo("ㄱ", "ㄱㅋ"), jamo("ㄴ", "ㄴㄹ"), jamo("ㄷ", "ㄷㅌ"),
                returnKey()
            ],
            [
                jamo("ㅂ", "ㅂㅍ"), jamo("ㅅ", "ㅅㅎ"), jamo("ㅈ", "ㅈㅊ"),
                // 두벌식·단모음의 ⏎ 왼쪽 키와 같은 문장부호 키 — 입력란 종류를 따른다 (PDR punctuation-key).
                // 글자는 한글 키와 같은 28pt (사용자 요청 2026-09-07 "., 키 글자 크게")
                punctuationKey(.standard, width: 1, labelSize: 28)
            ],
            [
                // 폭 합 4.0 — 위 행들과 열 경계를 맞춰 ㅇㅁ이 정확히 2열 아래에 온다 (리뷰 반영)
                Key(id: "symbols", label: "123", event: .symbols, isFunctionKey: true),
                jamo("ㅇ", "ㅇㅁ"),
                // 1폭 키라 "스페이스" 텍스트가 안 들어간다 — 아이콘 (사용자 요청 2026-09-02)
                Key(id: "space", label: " ", event: .space, symbol: "space"),
                Key(id: "globe", label: "🌐", event: .toggleLanguage, width: 0.5, isFunctionKey: true),
                Key(id: "language", label: "ABC", event: .toggleLanguage, width: 0.5, isFunctionKey: true)
            ]
        ])
    }()

    // MARK: - 단모음 (4행)
    //
    // 삼성 키보드·Gboard 공통 배열. 시프트가 없다 — 쌍자음/이중모음은 연타 승격.
    // 두벌식과의 유일한 자리 차이는 ㅗ의 상단 이동.

    public static let danmoeum: LayoutDefinition = {
        func jamo(_ character: Character) -> Key {
            Key(id: "dm-\(character)", label: String(character),
                event: .character(String(character)))
        }
        return LayoutDefinition(rows: [
            "ㅂㅈㄷㄱㅅㅗㅐㅔ".map(jamo),
            "ㅁㄴㅇㄹㅎㅓㅏㅣ".map(jamo),
            // 왼쪽 스페이서 1 + 글자 6 + ⌫ 1 = 8 — 위 행(8)과 열 폭이 같고 ㅋ~ㅡ가 2~7열에
            // 앉아 **가운데 정렬**된다 (2026-09-02 사용자 피드백: 글자 열이 왼쪽으로 쏠림).
            // 이전 ⌫ 1.5 단독 배치는 행 폭 7.5로 글자가 왼쪽부터 채워졌다.
            [Key(id: "dm-spacer", label: "", event: .spacer, isFunctionKey: true)]
                + "ㅋㅌㅊㅍㅜㅡ".map(jamo)
                + [backspaceKey()],
            bottomRow(languageLabel: "ABC")
        ])
    }()

    // MARK: - 기호 1페이지 (숫자 + 괄호·특수문자 + 기본 문장부호) / 2페이지 (#+= 그 밖의 특수문자)
    //
    // Apple 배열 기반, **두 페이지 모두 5행** (2026-09-04 사용자 요청): Apple 2페이지에 있던 괄호·특수문자
    // 줄(`[ ] { } # % ^ * + =`)을 1페이지 숫자 바로 아래로 옮겨 한 번에 닿게 하고, 2페이지는 남은
    // `_ \ | ~ …` 줄에 한국어 입력에서 자주 쓰는 기호 두 줄(※★☆♡♥♪→←↑↓ / °±×÷≠√∞·…✓)을 더한다.
    // 4행 왼쪽 키가 페이지를 오간다(1페이지 "#+=" → 2페이지, 2페이지 "123" → 1페이지).
    // 하단 행의 "ABC"는 들어오기 전 문자 모드로 돌아간다 — 기호 페이지에는 한영 키가 없다
    // (Apple과 동일; 언어 전환은 문자 자판에서 한다). 자판 높이는 고정이라 5행이면 키가 조금 낮아진다
    // (숫자 줄을 켠 문자 자판과 같은 높이 분배).

    public static let symbols: LayoutDefinition = {
        LayoutDefinition(rows: [
            "1234567890".map(symbolKey),
            ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map(symbolKey),
            ["-", "/", ":", ";", "(", ")", "₩", "&", "@", "\""].map(symbolKey),
            symbolsPunctuationRow(pageLabel: "#+="),
            symbolsBottomRow
        ])
    }()

    public static let symbolsAlternate: LayoutDefinition = {
        LayoutDefinition(rows: [
            ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map(symbolKey),
            ["※", "★", "☆", "♡", "♥", "♪", "→", "←", "↑", "↓"].map(symbolKey),
            ["°", "±", "×", "÷", "≠", "√", "∞", "·", "…", "✓"].map(symbolKey),
            symbolsPunctuationRow(pageLabel: "123"),
            symbolsBottomRow
        ])
    }()

    /// 기호 페이지 4행 — 페이지 전환 키 + `. , ? ! '` + ⌫ (두 페이지 공통)
    private static func symbolsPunctuationRow(pageLabel: String) -> [Key] {
        [Key(id: "sym-page", label: pageLabel, event: .symbolsAlternate, width: 1.4, isFunctionKey: true)]
            + [".", ",", "?", "!", "'"].map(symbolKey)
            + [backspaceKey(width: 1.4)]
    }

    // MARK: - 숫자 패드 (입력란 keyboardType — PDR field-traits-and-live-settings)
    //
    // Apple 원형: 1~9 3열, 하단 [보조][0][⌫]. 리턴 키 없음(앱이 완료 바를 제공). 서드파티
    // 필수 키인 지구본은 보조 칸을 반으로 나눠 넣는다 (UI가 needsInputModeSwitchKey로 숨긴다).

    public static func numberPad(_ kind: NumberPadKind) -> LayoutDefinition {
        func digit(_ character: Character) -> Key {
            Key(id: "np-\(character)", label: String(character), event: .character(String(character)))
        }
        let auxiliary: Key = switch kind {
        case .plain: Key(id: "np-spacer", label: "", event: .spacer, width: 0.5, isFunctionKey: true)
        case .decimal: Key(id: "np-dot", label: ".", event: .character("."), width: 0.5)
        case .phone: Key(id: "np-plus", label: "+", event: .character("+"), width: 0.5)
        }
        return LayoutDefinition(rows: [
            "123".map(digit),
            "456".map(digit),
            "789".map(digit),
            [
                auxiliary,
                Key(id: "globe", label: "🌐", event: .toggleLanguage, width: 0.5, isFunctionKey: true),
                digit("0"),
                backspaceKey()
            ]
        ])
    }

    /// ⇧ — 표면은 SF Symbol `shift`. UI가 시프트 상태에 따라 `shift.fill`(once)·`capslock.fill`(캡스락)로 바꿔 그린다
    /// (2026-09-07 아이콘 확대 — 이전엔 상태 표시 없이 "⇧" 글자 16pt).
    private static func shiftKey(width: Double = 1) -> Key {
        Key(id: "shift", label: "⇧", event: .shift, width: width, isFunctionKey: true, symbol: "shift")
    }

    /// ⌫ — 라벨은 "⌫"(접근성·테스트 식별용)이고 표면은 SF Symbol `delete.left`로 그린다.
    /// 유니코드 글자 16pt는 작다는 피드백(2026-09-07) — 기능 키 심볼은 UI가 22pt로 그린다.
    private static func backspaceKey(width: Double = 1) -> Key {
        Key(id: "backspace", label: "⌫", event: .backspace, width: width, isFunctionKey: true,
            symbol: "delete.left")
    }

    /// ⏎ — 표면은 SF Symbol `return`. 입력란 `returnKeyType`에 따라 UI가 `relabeled`로 덮어쓴다
    /// (✓ 심볼 또는 "검색"·"이동" 텍스트 — 텍스트일 때는 symbol을 nil로 넘겨 글자가 보인다).
    private static func returnKey(width: Double = 1) -> Key {
        Key(id: "return", label: "⏎", event: .return, width: width, isFunctionKey: true,
            symbol: "return")
    }

    private static func symbolKey(_ character: String) -> Key {
        Key(id: "sym-\(character)", label: character, event: .character(character))
    }

    private static func symbolKey(_ character: Character) -> Key {
        symbolKey(String(character))
    }

    /// 기호 페이지 하단 행 — ABC(문자로 복귀)·지구본·스페이스·리턴
    private static let symbolsBottomRow: [Key] = [
        Key(id: "symbols", label: "ABC", event: .symbols, width: 1.2, isFunctionKey: true),
        Key(id: "globe", label: "🌐", event: .toggleLanguage, width: 1.2, isFunctionKey: true),
        Key(id: "space", label: " ", event: .space, width: 5.6),
        returnKey(width: 1.6)
    ]

    /// 최하단 행 — 기호·지구본·스페이스·**문장부호**·한영·리턴. 자판 3종이 공유한다.
    /// 지구본 키는 UI가 UIKit 버튼(다음 키보드)으로 덮는다. 시스템이 지구본을 요구하지 않는
    /// 환경에서는 `layout(... inputModeSwitchKey: false)`이 `removingGlobe()`로 이 행을 다시 짠다
    /// (한영이 지구본 자리로, 스페이스 3.2 + 1.2 = 4.4). 문장부호 키(`punct`)의 내용은 입력란 종류에
    /// 따라 `layout(... punctuation:)`이 바꾼다 — 기본 `.` 탭 / `,` 길게 (PDR punctuation-key).
    private static func bottomRow(languageLabel: String) -> [Key] {
        [
            Key(id: "symbols", label: "123", event: .symbols, width: 1.2, isFunctionKey: true),
            Key(id: "globe", label: "🌐", event: .toggleLanguage, width: 1.2, isFunctionKey: true),
            Key(id: "space", label: " ", event: .space, width: 3.2),
            punctuationKey(.standard, width: 1.2),
            Key(id: "language", label: languageLabel, event: .toggleLanguage, width: 1.2, isFunctionKey: true),
            returnKey(width: 1.6)
        ]
    }

    /// 문장부호 키 — 탭은 `primary`, 길게 누르면 `secondary`. 문자 키 표면(흰색)이다.
    /// `labelSize`는 천지인처럼 넓은 키의 자판이 넘긴다 (한글 키와 같은 28) — `replacingPunctuation`이 보존한다.
    private static func punctuationKey(_ spec: PunctuationKeySpec, width: Double, labelSize: Double? = nil) -> Key {
        Key(id: "punct", label: spec.primary, event: .character(spec.primary), width: width,
            alternate: .character(spec.secondary), labelSize: labelSize)
    }

    /// 상단 숫자 줄 (설정 `numberRowEnabled`). 숫자는 비자모 키라 기존 커밋 삽입 경로를
    /// 그대로 탄다 — 엔진 변경 없음 (PDR toolbar-tools 결정 3).
    private static let numberRowKeys: [Key] = "1234567890".map { digit in
        Key(id: "num-\(digit)", label: String(digit), event: .character(String(digit)))
    }

    // MARK: - 길게 누르기 기호 (설정 `longPressSymbolsEnabled`, PDR long-press-symbols)
    //
    // **기호 자판(123) 1페이지와 같은 배열, 숫자 줄은 뺀다** (사용자 결정 2026-09-08 — 처음의 Gboard 배열에서 개정:
    // "ㅂㅈㄷㄱㅅ 줄에 숫자는 빼고 123 자판과 배열을 같게"). 기호 자판 2·3·4행의 문자 키 라벨을 그대로 가져와
    // 문자 자판 1·2·3행에 **자리(열) 순서**로 얹는다 — 1행 `[]{}#%^*+=`, 2행 `-/:;()₩&@"`, 3행 `.,?!'`.
    // 행의 키 수가 기호 수보다 적으면 뒤 기호를 빼고(두벌식 2행 9키 → `"` 없음, 단모음 1·2행 8키), 많으면 뒤 키는
    // 비운다(3행 7키에 기호 5개 → ㅜ·ㅡ 없음). `symbols` 배열에서 파생하므로 기호 자판을 고치면 함께 바뀐다(테스트 고정).
    // 동작은 문장부호 키의 `.` 길게 → `,`와 같다 (`Key.alternate`, KeyCapView 450ms 무장) — 새 제스처 없음.
    static let longPressSymbolRows: [[String]] = (1...3).map { rowIndex in
        symbols.rows[rowIndex].filter { !$0.isFunctionKey }.map(\.label)
    }

    /// 문자 키에 길게 누르기 기호를 붙인 배열. 문자 키(문자 이벤트 · 기능 키 아님 · 대체 입력 없음)에만
    /// 행 안 순서대로 배정한다 — 문장부호 키(`punct`)는 자기 대체 입력(`,`)을 지킨다. 위 3행만 본다
    /// (하단 행은 그대로). **숫자 줄을 붙이기 전에** 적용한다 — 숫자 키에는 기호가 붙지 않는다.
    public func addingLongPressSymbols() -> LayoutDefinition {
        var rows = self.rows
        for (rowIndex, symbols) in Self.longPressSymbolRows.enumerated() where rowIndex < rows.count {
            var remaining = symbols.makeIterator()
            for (index, key) in rows[rowIndex].enumerated() {
                guard !key.isFunctionKey, key.alternate == nil, case .character = key.event,
                      let symbol = remaining.next() else { continue }
                rows[rowIndex][index] = key.withAlternate(.character(symbol))
            }
        }
        return LayoutDefinition(rows: rows)
    }

    /// 모드에 맞는 자판을 고른다. 한글 자판은 활성 배열에 따라 달라진다.
    /// - Parameters:
    ///   - numberRow: 참이면 상단에 숫자 줄을 붙인다.
    ///     **천지인 제외**(4열 그리드 구조와 충돌), **기호 자판 제외**(이미 숫자 있음).
    ///   - inputModeSwitchKey: 시스템이 지구본(다음 키보드) 키를 요구하는가(`needsInputModeSwitchKey`).
    ///     거짓이면 하단 행을 지구본 없이 다시 짠다 — 빈 칸을 남기지 않는다 (`removingGlobe`).
    ///   - punctuation: 스페이스 오른쪽 문장부호 키의 내용 — 입력란 종류를 따른다 (`replacingPunctuation`).
    ///   - longPressSymbols: 참이면 두벌식·단모음·쿼티의 문자 키에 길게 누르기 기호(기호 자판 1페이지와 같은 배열,
    ///     숫자 제외)를 붙인다 (`addingLongPressSymbols`). 천지인·기호·숫자 패드에는 붙지 않는다.
    public static func layout(
        for mode: InputMode, hangulLayout: HangulLayout, numberRow: Bool = false,
        inputModeSwitchKey: Bool = true, punctuation: PunctuationKeySpec = .standard,
        longPressSymbols: Bool = false
    ) -> LayoutDefinition {
        var base: LayoutDefinition
        switch mode {
        case .hangul:
            switch hangulLayout {
            case .dubeolsik: base = .dubeolsik
            case .cheonjiin: base = .cheonjiin
            case .danmoeum: base = .danmoeum
            }
        case .english:
            base = .qwerty
        case .symbols:
            base = .symbols
        case .symbolsAlternate:
            base = .symbolsAlternate
        case .numberPad(let kind):
            base = .numberPad(kind)
        }
        if longPressSymbols, mode.isLetter, !(mode == .hangul && hangulLayout == .cheonjiin) {
            base = base.addingLongPressSymbols()
        }
        if punctuation != .standard { base = base.replacingPunctuation(punctuation) }
        if !inputModeSwitchKey { base = base.removingGlobe() }
        guard numberRow, !mode.isSymbols, !mode.isNumberPad,
              !(mode == .hangul && hangulLayout == .cheonjiin) else { return base }
        return LayoutDefinition(rows: [numberRowKeys] + base.rows)
    }

    /// 지구본 키를 빼고 그 자리를 이웃이 채운 배열 — 시스템이 지구본을 요구하지 않는 환경
    /// (`needsInputModeSwitchKey == false` — Face ID iPhone처럼 시스템이 키보드 아래 바에 지구본을
    /// 제공하는 기기, iPad 등). 이전에는 UI가 지구본 칸을
    /// 비워 두어 스페이스 왼쪽에 빈 칸이 남았다 (2026-09-04 사용자 요청으로 재배치).
    ///
    /// - 넓은 스페이스바 자판(두벌식·단모음·쿼티): **한영 키가 지구본 자리로** 오고, 스페이스가
    ///   한영 자리까지 넓어진다 — `[기호][한영][스페이스][⏎]`
    /// - 천지인: 지구본·한영이 나눠 쓰던 칸을 한영이 통째로 갖는다 (행 폭 합 4.0 유지 — ㅇㅁ 열 정렬)
    /// - 한영 키가 없는 자판(기호·숫자 패드): 스페이스가 있으면 스페이스가, 없으면 왼쪽 보조 키가 폭을 흡수한다
    ///
    /// 행 폭 합은 변하지 않으므로 다른 키 크기는 그대로다.
    public func removingGlobe() -> LayoutDefinition {
        guard var bottom = rows.last,
              let globeIndex = bottom.firstIndex(where: { $0.id == "globe" }) else { return self }
        let globe = bottom.remove(at: globeIndex)
        if let languageIndex = bottom.firstIndex(where: { $0.id == "language" }) {
            let language = bottom.remove(at: languageIndex)
            if let spaceIndex = bottom.firstIndex(where: { $0.event == .space }),
               (globeIndex..<languageIndex).contains(spaceIndex) {
                // [기호][지구본][스페이스][한영][⏎] → [기호][한영][스페이스+한영 폭][⏎]
                bottom[spaceIndex] = bottom[spaceIndex]
                    .resized(width: bottom[spaceIndex].width + language.width)
                bottom.insert(language.resized(width: globe.width), at: globeIndex)
            } else {
                // 천지인 [..][스페이스][지구본 0.5][한영 0.5] → [..][스페이스][한영 1.0]
                bottom.insert(language.resized(width: language.width + globe.width), at: globeIndex)
            }
        } else {
            let absorber = bottom.firstIndex(where: { $0.event == .space }) ?? max(globeIndex - 1, 0)
            bottom[absorber] = bottom[absorber].resized(width: bottom[absorber].width + globe.width)
        }
        return LayoutDefinition(rows: Array(rows.dropLast()) + [bottom])
    }

    /// 문장부호 키의 내용을 입력란 종류에 맞게 바꾼 배열 (이메일 `@`/`.`, 주소 `.`/`.com`).
    /// 키가 없는 자판(기호·숫자 패드)은 그대로다. 자리·폭은 바뀌지 않는다. 모든 행을 본다 — 천지인은 3행 우측.
    public func replacingPunctuation(_ spec: PunctuationKeySpec) -> LayoutDefinition {
        var rows = self.rows
        for (rowIndex, row) in rows.enumerated() {
            if let index = row.firstIndex(where: { $0.id == "punct" }) {
                rows[rowIndex][index] = Self.punctuationKey(spec, width: row[index].width, labelSize: row[index].labelSize)
                return LayoutDefinition(rows: rows)
            }
        }
        return self
    }
}
