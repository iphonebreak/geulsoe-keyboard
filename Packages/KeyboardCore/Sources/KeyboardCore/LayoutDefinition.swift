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
        /// 길게 누르기 **힌트 문구** — `alternate`가 문자 이벤트가 **아닐 때**(키패드형 페이지 키의 「이전」) UI가
        /// 귀퉁이와 무장 표시에 쓴다(PDR `number-symbol-keypad.md` 6절). 문자 키는 `alternateLabel`(자동 파생)을 쓰고
        /// 이 필드는 비워 둔다. 표시 전용 — 동작은 `alternate`가 정한다.
        public let alternateHint: String?

        public init(id: String, label: String, shiftedLabel: String? = nil,
                    event: KeyEvent, width: Double = 1, isFunctionKey: Bool = false,
                    symbol: String? = nil, alternate: KeyEvent? = nil, labelSize: Double? = nil,
                    alternateHint: String? = nil) {
            self.id = id
            self.label = label
            self.shiftedLabel = shiftedLabel ?? label
            self.event = event
            self.width = width
            self.isFunctionKey = isFunctionKey
            self.symbol = symbol
            self.alternate = alternate
            self.labelSize = labelSize
            self.alternateHint = alternateHint
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
                labelSize: labelSize, alternateHint: alternateHint)
        }

        /// 폭만 바꾼 복사 — 지구본이 빠질 때 이웃 키가 그 폭을 흡수한다 (`removingGlobe`)
        public func resized(width: Double) -> Key {
            Key(id: id, label: label, shiftedLabel: shiftedLabel, event: event,
                width: width, isFunctionKey: isFunctionKey, symbol: symbol, alternate: alternate,
                labelSize: labelSize, alternateHint: alternateHint)
        }

        /// 길게 누르기 대체 입력만 바꾼 복사 — 문자 키에 기호를 붙일 때 (`addingLongPressSymbols`)
        public func withAlternate(_ alternate: KeyEvent?) -> Key {
            Key(id: id, label: label, shiftedLabel: shiftedLabel, event: event,
                width: width, isFunctionKey: isFunctionKey, symbol: symbol, alternate: alternate,
                labelSize: labelSize, alternateHint: alternateHint)
        }
    }

    public let rows: [[Key]]

    /// 이 자판의 **기준 열 수** — 폭 상한과 행 높이를 여기서 되짚는다.
    ///
    /// 행마다 폭 합이 다르다: 두벌식 `10 / 9 / 9.8 / 9.6`, 단모음 `8 / 8 / 8 / 9.6`,
    /// 천지인 `4 / 4 / 4 / 4`, 숫자 패드 `3 / 3 / 3 / 3`.
    /// 그래서 **가장 많은 행이 공유하는 폭 합**을 기준으로 삼는다(동률이면 큰 쪽).
    ///
    /// - 최댓값을 쓰면 단모음이 하단 행(9.6)에 끌려가 8열이 아니게 된다.
    /// - 최솟값을 쓰면 두벌식이 3행(9.0)에 끌려가 10열보다 좁아진다.
    /// - 첫 행을 쓰면 **숫자 줄(10열)을 켠 단모음**이 10열로 잘못 잡힌다.
    ///
    /// 최빈값은 이 셋을 모두 피한다: 문자 행은 자판마다 2~3개인데 숫자 줄·하단 행은 하나씩이다.
    /// 두벌식처럼 모든 행이 다른 경우(10/9/9.8/9.6)만 동률이 되고, 그때는 큰 쪽인 10이 문자 행이다.
    /// 값은 `LayoutDefinitionTests`가 자판마다 고정한다.
    public var referenceUnits: Double {
        let sums = rows.map { row in ((row.reduce(0) { $0 + $1.width }) * 100).rounded() / 100 }
        guard !sums.isEmpty else { return 10 }
        var counts: [Double: Int] = [:]
        for sum in sums { counts[sum, default: 0] += 1 }
        return counts.max { lhs, rhs in
            lhs.value != rhs.value ? lhs.value < rhs.value : lhs.key < rhs.key
        }.map(\.key) ?? 10
    }

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

    // MARK: - 키패드형 숫자·기호 (설정 `symbolKeyboardStyle == .keypad`, v1.2.0 ⑥ · 2026-09-28 개정)
    //
    // PDR `docs/design-reviews/number-symbol-keypad.md` 「개정 — 아래 줄 없애기」 배치표 그대로. **4페이지 한 키 순환** —
    // 숫자(0) → 기호1 → 기호2 → 기호3 → 숫자. 페이지 키는 탭 = 다음, 길게 = 이전(`alternate`),
    // 길게 누르기가 있다는 표시는 `alternateHint`(문자 이벤트가 아니라 `alternateLabel`이 비기 때문).
    //
    // ★ **아래 줄(쿼티형과 공유하던 하단 행)이 없다**(사장님 결정 2026-09-28, 폰 세션 4-1) — 삼성 3×4 숫자·Gboard 숫자
    //   패드처럼 문자 복귀·스페이스·⏎·⌫를 **자판 격자 안에** 둔다. 네 페이지 모두 **4행**이다.
    // ★ **쿼티형 `symbols`·`symbolsAlternate`는 한 글자도 안 바뀐다** — 문자 키 길게 누르기
    //   (`longPressSymbolRows`)가 거기서 파생되므로, 키패드형은 새 상수를 **나란히** 둔다(PDR 1절).
    // ★ 지구본은 **4행(마지막 행)에만** 있고 스페이스 왼쪽이다 — `removingGlobe()`가 마지막 행만 보고,
    //   한영 키가 없으니 **스페이스가 그 폭을 흡수**한다(행 폭 합 불변).
    // ★ **기준 열 수를 네 페이지 모두 7로 맞춘다** — 숫자 페이지 키 폭을 1.75(4 × 1.75 = 7)로 둔다.
    //   아이폰은 행마다 폭을 꽉 채우므로 모양이 같고, 아이패드는 열 수에서 높이를 되짚으므로
    //   (`KeyboardViewController.keyboardBaseHeight`) 4열·7열이 섞이면 **페이지를 넘길 때마다 높이가 흔들린다.**
    // ★ 문자 복귀 키(`id: "symbols"`) 라벨은 **돌아갈 문자 모드**다 — 여기 상수는 「가」, 영어에서 들어왔으면
    //   `layout(... letterMode: .english)`가 「ABC」로 바꾼다(라벨만, 동작은 그대로 `.symbols`).

    /// 페이지 수 — 숫자 1 + 기호 3 (사장님 결정: 55개를 빼지 않고 다 담는다)
    public static let keypadPageCount = 4

    /// 0 = 숫자, 1~3 = 기호. `layout(for: .keypadPad(page:))`가 여기서 고른다.
    public static let keypadPages: [LayoutDefinition] = [keypadNumberPage] + keypadSymbolPages

    /// 숫자 페이지 — **삼성 3×4 숫자 배열**(4행 4열, 아래 줄 없음):
    /// `1 2 3 ⌫` / `4 5 6 ⏎` / `7 8 9 .,-/` / `[페이지½][가½][0][🌐½][␣]`.
    /// `. , - /`는 **연타 키 하나**다(`KeyEvent.multiTap`) — 탭 `.`, 연타 `, - /`. VoiceOver 사용자는 연타가 어려워
    /// 네 기호가 **기호 1페이지에도** 있다. 자동 숫자 패드(`numberPad(_:)`, 숫자 전용 입력란)와는 **별개**다.
    public static let keypadNumberPage: LayoutDefinition = {
        func key(_ character: String) -> Key {
            Key(id: "kp-\(character)", label: character, event: .character(character), width: 1.75)
        }
        return LayoutDefinition(rows: [
            ["1", "2", "3"].map(key) + [backspaceKey(width: 1.75)],
            ["4", "5", "6"].map(key) + [returnKey(width: 1.75)],
            ["7", "8", "9"].map(key) + [keypadMultiTapKey],
            // 반 칸 둘 + 0 + (지구본 반 칸) + 스페이스 = 7. 지구본이 빠지면 스페이스가 3.5가 된다
            [keypadPageKey(page: 0, width: 0.875), keypadLetterKey(width: 0.875), key("0"),
             keypadGlobeKey(width: 0.875), keypadSpaceKey(width: 2.625)]
        ])
    }()

    /// `.,-/` 연타 키 — 문자 키 표면, 길게 누르기 없음. 라벨은 숫자 키와 같은 22pt(`labelSize`) —
    /// 두지 않으면 다문자 라벨 규칙(15pt)을 타서 넓은 키에 작게 박힌다
    private static let keypadMultiTapKey = Key(
        id: "kp-multitap", label: ".,-/", event: .multiTap([".", ",", "-", "/"]), width: 1.75, labelSize: 22)

    /// 기호 3페이지 — 1~3행 7×3 = **21칸**, 4행은 `[페이지][가][🌐][␣ 2][⌫][⏎]`.
    /// 1페이지는 자주 쓰는 것과 `. , - / @ ? !`(숫자 페이지 연타 키의 VoiceOver 대체 경로)를 모았고,
    /// 쿼티형 기호 55개를 **정확히 한 번씩** 담는다(예전 2페이지의 `~ ☆ ♡` 중복은 뺐다 — 1페이지에 있다).
    /// 3페이지는 남은 13개 뒤를 빈칸으로 둔다(실사용 데이터 없이 채우지 않는다 — PDR 2-2절).
    static let keypadSymbolPages: [LayoutDefinition] = [
        keypadSymbolPage(1, [
            "~", "♡", "☆", "!", "?", ".", ",",
            "@", "#", "%", "&", "*", "+", "=",
            "-", "/", ":", ";", "(", ")", "₩"
        ]),
        keypadSymbolPage(2, [
            "[", "]", "{", "}", "^", "\"", "'",
            "_", "\\", "|", "<", ">", "€", "£",
            "¥", "•", "※", "★", "♥", "♪", "→"
        ]),
        keypadSymbolPage(3, [
            "←", "↑", "↓", "°", "±", "×", "÷",
            "≠", "√", "∞", "·", "…", "✓"
        ])
    ]

    /// 21칸을 채우고(모자라면 빈칸) 7·7·7로 자른 뒤 기능 키 행을 붙인다.
    private static func keypadSymbolPage(_ page: Int, _ symbols: [String]) -> LayoutDefinition {
        let slots = 21
        var keys: [Key] = symbols.prefix(slots).map { symbol in
            Key(id: "kp-\(symbol)", label: symbol, event: .character(symbol))
        }
        // 빈칸 id는 칸마다 다르게 — 뷰가 id로 키를 가린다(한 행에 같은 id가 둘이면 안 된다)
        for index in keys.count..<slots {
            keys.append(Key(id: "kp-spacer-\(page)-\(index)", label: "", event: .spacer, isFunctionKey: true))
        }
        return LayoutDefinition(rows: [
            Array(keys[0..<7]),
            Array(keys[7..<14]),
            Array(keys[14..<21]),
            [keypadPageKey(page: page, width: 1), keypadLetterKey(width: 1), keypadGlobeKey(width: 1),
             keypadSpaceKey(width: 2), backspaceKey(width: 1), returnKey(width: 1)]
        ])
    }

    /// 페이지 키 — 탭 = 다음, 길게 = 이전. 라벨은 **지금 페이지와 다음 방향**(`1/4 ▶`, 반론자2 — 이전을 모르고
    /// 계속 순환하지 않게), 귀퉁이·무장 표시는 `◀`(`alternateHint`).
    /// 숫자 페이지의 반 칸(0.875)에도 기본 16pt 그대로 들어간다 — 가장 좁은 375pt·지구본 있음에서 키 43.6pt,
    /// 「1/4 ▶」 38.0pt(SF 16pt 실측, 2026-09-28). 넘치면 키캡의 `minimumScaleFactor(0.7)`가 줄인다.
    private static func keypadPageKey(page: Int, width: Double) -> Key {
        Key(id: "keypad-page", label: "\(page + 1)/\(keypadPageCount) ▶", event: .keypadPageNext,
            width: width, isFunctionKey: true, alternate: .keypadPagePrevious, alternateHint: "◀")
    }

    /// 문자 복귀 키 — 들어오기 전 문자 모드로 돌아간다(`.symbols`). 라벨 「가」는 기본값이고
    /// 영어면 `layout(... letterMode:)`가 「ABC」로 바꾼다
    private static func keypadLetterKey(width: Double) -> Key {
        Key(id: "symbols", label: "가", event: .symbols, width: width, isFunctionKey: true)
    }

    private static func keypadGlobeKey(width: Double) -> Key {
        Key(id: "globe", label: "🌐", event: .toggleLanguage, width: width, isFunctionKey: true)
    }

    private static func keypadSpaceKey(width: Double) -> Key {
        Key(id: "space", label: " ", event: .space, width: width)
    }

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
    // 행의 키 수가 기호 수보다 적으면 뒤 기호가 넘치고, 많으면 뒤 키가 빈다.
    //
    // **넘친 기호는 바로 다음 행의 남는 뒤 자리로 이월한다** (2026-09-14, 사용자 보고 "단모음에 @ 가 없다").
    // 이월은 자기 행 기호를 자리 순서로 다 얹은 **뒤**에만 일어나므로 "자리 기준"을 깨지 않는다 —
    // 파생 기호가 밀려나는 일은 없고, 원래 비어 있었을 자리만 채운다. 특례표가 아니라 일반 규칙이라
    // `symbols` 배열에서 파생되는 성질도 그대로다(기호 자판을 고치면 이월 내용도 함께 바뀐다).
    //   두벌식·쿼티 2행 9키 → `"`가 넘쳐 3행 첫 빈 자리(ㅜ / n)로 간다. 마지막 자리(ㅡ / m)는 여전히 빈다.
    //   단모음 2행 8키 → `@ "`가 넘치고, 3행 빈 자리 1개에 `@`가 들어간다.
    // **이월은 한 행만 간다(누적하지 않는다).** 누적하면 단모음 1행 잔여 `+ =`가 줄을 서서 3행의 단
    // 하나뿐인 빈 자리를 `+`가 가져가고 `@`는 또 버려진다 — 고치려던 문제가 그대로 남는다.
    // `symbols` 배열에서 파생하므로 기호 자판을 고치면 함께 바뀐다(테스트 고정).
    // 동작은 문장부호 키의 `.` 길게 → `,`와 같다 (`Key.alternate`, KeyCapView 450ms 무장) — 새 제스처 없음.
    static let longPressSymbolRows: [[String]] = (1...3).map { rowIndex in
        symbols.rows[rowIndex].filter { !$0.isFunctionKey }.map(\.label)
    }

    /// 문자 키에 길게 누르기 기호를 붙인 배열. 문자 키(문자 이벤트 · 기능 키 아님 · 대체 입력 없음)에만
    /// 행 안 순서대로 배정한다 — 문장부호 키(`punct`)는 자기 대체 입력(`,`)을 지킨다. 위 3행만 본다
    /// (하단 행은 그대로). **숫자 줄을 붙이기 전에** 적용한다 — 숫자 키에는 기호가 붙지 않는다.
    public func addingLongPressSymbols() -> LayoutDefinition {
        var rows = self.rows
        /// 앞 행에서 자리를 못 찾고 넘친 기호. **바로 다음 행까지만** 흘러간다 (아래 주석 참조).
        var carry: [String] = []
        for (rowIndex, symbols) in Self.longPressSymbolRows.enumerated() where rowIndex < rows.count {
            // 자기 행 기호를 자리 순서로 먼저 얹는다 — 여기가 "자리 기준"이고 바뀌지 않았다.
            // 그러고도 남는 뒤 자리에만 앞 행 이월분을 채운다. 파생 기호를 밀어내는 일은 없다.
            var placing = symbols.makeIterator()
            var spilling = carry.makeIterator()
            var overflowStart = 0
            var placedFromOwn = 0
            for (index, key) in rows[rowIndex].enumerated() {
                guard !key.isFunctionKey, key.alternate == nil, case .character = key.event else { continue }
                if let symbol = placing.next() {
                    placedFromOwn += 1
                    rows[rowIndex][index] = key.withAlternate(.character(symbol))
                } else if let spilled = spilling.next() {
                    rows[rowIndex][index] = key.withAlternate(.character(spilled))
                }
            }
            overflowStart = placedFromOwn
            // 이월은 **누적하지 않는다.** 이 행에서 넘친 것만 다음 행으로 넘긴다.
            // 누적하면 앞선 행의 잔여분이 줄을 서서 뒤 행의 빈 자리를 먼저 차지한다 —
            // 단모음이 그 사례다: 1행 잔여 `+ =`가 누적되면 3행 빈 자리를 `+`가 가져가고 `@`는 또 버려진다.
            carry = overflowStart < symbols.count ? Array(symbols[overflowStart...]) : []
        }
        return LayoutDefinition(rows: rows)
    }

    /// 모드에 맞는 자판을 고른다. 한글 자판은 활성 배열에 따라 달라진다.
    /// - Parameters:
    ///   - numberRow: 참이면 상단에 숫자 줄을 붙인다.
    ///     **천지인 제외**(4열 그리드 구조와 충돌), **기호 자판·키패드형 제외**(이미 숫자 있음).
    ///   - inputModeSwitchKey: 시스템이 지구본(다음 키보드) 키를 요구하는가(`needsInputModeSwitchKey`).
    ///     거짓이면 하단 행을 지구본 없이 다시 짠다 — 빈 칸을 남기지 않는다 (`removingGlobe`).
    ///   - punctuation: 스페이스 오른쪽 문장부호 키의 내용 — 입력란 종류를 따른다 (`replacingPunctuation`).
    ///   - longPressSymbols: 참이면 두벌식·단모음·쿼티의 문자 키에 길게 누르기 기호(기호 자판 1페이지와 같은 배열,
    ///     숫자 제외)를 붙인다 (`addingLongPressSymbols`). 천지인·기호·숫자 패드에는 붙지 않는다.
    ///   - letterMode: 키패드형에서 돌아갈 문자 모드(`InputController.letterMode`) — 문자 복귀 키 라벨만 정한다
    ///     (한글 「가」, 영어 「ABC」). 다른 자판에서는 쓰지 않는다(쿼티형 기호 자판의 「ABC」는 그대로).
    public static func layout(
        for mode: InputMode, hangulLayout: HangulLayout, numberRow: Bool = false,
        inputModeSwitchKey: Bool = true, punctuation: PunctuationKeySpec = .standard,
        longPressSymbols: Bool = false, letterMode: InputMode = .hangul
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
        case .keypadPad(let page):
            base = keypadPages[(page % keypadPageCount + keypadPageCount) % keypadPageCount]
            if letterMode == .english { base = base.relabelingLetterReturn("ABC") }
        }
        if longPressSymbols, mode.isLetter, !(mode == .hangul && hangulLayout == .cheonjiin) {
            base = base.addingLongPressSymbols()
        }
        if punctuation != .standard { base = base.replacingPunctuation(punctuation) }
        if !inputModeSwitchKey { base = base.removingGlobe() }
        // 키패드형도 제외 — 숫자 페이지가 따로 있고, 기호 페이지 위에 숫자 줄이 붙으면 6행이 된다(PDR 4-4절)
        guard numberRow, !mode.isSymbols, !mode.isNumberPad, !mode.isKeypadPad,
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

    /// 문자 복귀 키(`.symbols`)의 라벨만 바꾼 배열 — 키패드형이 영어로 돌아갈 때 「ABC」
    private func relabelingLetterReturn(_ label: String) -> LayoutDefinition {
        LayoutDefinition(rows: rows.map { row in
            row.map { $0.event == .symbols ? $0.relabeled(label: label, symbol: $0.symbol) : $0 }
        })
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
