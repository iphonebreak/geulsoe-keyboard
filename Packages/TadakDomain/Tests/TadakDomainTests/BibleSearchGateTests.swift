import Foundation
import Testing
@testable import TadakDomain

/// 성경 검색 **합성 게이트**의 진리표 — 계획서 4절 수용 기준.
///
/// ## ★ 복제식을 지웠다 (2026-09-21, 검증자 2절)
///
/// 예전에는 이 파일이 조립 지점의 식을 **복제해서** 돌렸다. 그래서
/// *"프로덕션을 고쳐도 테스트가 전부 통과한다"* — 단언 12개 중 프로덕션 논리를 지키는 것이
/// **0개**였다. 익스텐션 타깃이 `swift test`에 안 닿는다는 한계 때문이었다.
///
/// 이제 식이 `KeyboardSettings.allowsBibleSearch(isSecureTextEntry:)`에 있고
/// **조립 지점과 이 테스트가 같은 함수를 부른다.** 복제식은 한 줄도 없다.
///
/// ## ★ 16조합이 아니라 24조합이다
///
/// `isSecureTextEntry`는 `Bool?`이고 프로덕션은 **nil을 「secure 아님」으로** 본다.
/// 예전 테스트의 `secure: Bool`에는 nil이 없어 **그 경로가 비어 있었다**(검증자 지적).
/// nil·true·false 셋을 다 돌려 2 × 2 × 2 × 3 = **24조합**이 된다.
@Suite("성경 검색 합성 게이트")
struct BibleSearchGateTests {

    /// ★ 프로덕션 함수를 **그대로** 부른다 — 복제식이 아니다.
    private func canSearchBible(_ settings: KeyboardSettings, secure: Bool?) -> Bool {
        settings.allowsBibleSearch(isSecureTextEntry: secure)
    }

    private func settings(bible: Bool, snippets: Bool, biblePack: Bool) -> KeyboardSettings {
        KeyboardSettings(
            snippetsEnabled: snippets,
            disabledSnippetPacks: biblePack ? [] : [SnippetPack.bible],
            bibleSearchEnabled: bible
        )
    }

    /// secure의 세 값. **nil이 여기 있는 것이 핵심이다.**
    private static let secureCases: [Bool?] = [nil, false, true]

    // MARK: - ★ 24조합 전부 (nil 포함)

    @Test(
        "★ 넷이 모두 참인 조합에서만 검색이 돈다 — secure는 nil·false·true 셋 다",
        arguments: [false, true], [false, true]
    )
    func truthTable(bible: Bool, snippets: Bool) {
        for biblePack in [false, true] {
            for secure in Self.secureCases {
                // nil은 「secure 아님」이다 — 모르면 막지 않는다
                let expected = bible && snippets && biblePack && secure != true
                let actual = canSearchBible(
                    settings(bible: bible, snippets: snippets, biblePack: biblePack),
                    secure: secure
                )
                #expect(
                    actual == expected,
                    "bible=\(bible) snippets=\(snippets) pack=\(biblePack) secure=\(String(describing: secure))"
                )
            }
        }
    }

    @Test("24조합 중 참은 정확히 둘이다 — secure가 nil일 때와 false일 때")
    func exactlyTwoTrueCombinations() {
        var trueCount = 0
        var total = 0
        for bible in [false, true] {
            for snippets in [false, true] {
                for biblePack in [false, true] {
                    for secure in Self.secureCases {
                        total += 1
                        if canSearchBible(
                            settings(bible: bible, snippets: snippets, biblePack: biblePack),
                            secure: secure
                        ) { trueCount += 1 }
                    }
                }
            }
        }
        #expect(total == 24)
        #expect(trueCount == 2)
    }

    /// ★ 검증자가 짚은 빈 경로 — 프로덕션은 `!= true`라 **nil이 통과**한다.
    @Test("★ secure가 nil이면 「secure 아님」으로 본다 — 모르면 막지 않는다")
    func nilSecureIsTreatedAsNotSecure() {
        let all = settings(bible: true, snippets: true, biblePack: true)
        #expect(canSearchBible(all, secure: nil))
        #expect(canSearchBible(all, secure: false))
        #expect(!canSearchBible(all, secure: true))
    }

    // MARK: - 게이트 하나씩 꺼 본다

    @Test("게이트 하나만 꺼도 검색이 멈춘다", arguments: ["bible", "snippets", "pack", "secure"])
    func anySingleGateStopsSearch(which: String) {
        let all = settings(
            bible: which != "bible",
            snippets: which != "snippets",
            biblePack: which != "pack"
        )
        #expect(!canSearchBible(all, secure: which == "secure" ? true : nil))
    }

    // MARK: - ★ 기본값은 꺼짐 (사용자 결정 2026-09-19)

    @Test("★ 기본값이 꺼짐이다")
    func defaultIsOff() {
        #expect(KeyboardSettings.default.bibleSearchEnabled == false)
        #expect(!canSearchBible(.default, secure: nil))
    }

    /// ★ 옵트아웃 함정을 피했는지 — `ToolbarTool` 케이스로 만들었다면 구 저장분에서 **켜짐**이 된다.
    @Test("★ 구 저장분은 꺼짐으로 읽힌다 — 마이그레이션 플래그가 필요 없다")
    func legacyPayloadDecodesOff() throws {
        // 이 키가 아예 없는 저장분 (v1.0.1까지의 모든 사용자)
        let legacy = Data(#"{"snippetsEnabled":true,"disabledSnippetPacks":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyboardSettings.self, from: legacy)

        #expect(decoded.bibleSearchEnabled == false)
        #expect(!canSearchBible(decoded, secure: nil))
    }

    /// ★ 스위치가 **채움글 > 성경 팩 상세**로 옮겨 가면서 생긴 물음 (2026-09-21).
    ///
    /// 「이 팩 사용」을 끄면 단어로 구절 찾기도 함께 꺼진다(합성 게이트). 그런데 팩을 다시 켰을 때
    /// 사용자가 켜 뒀던 단어로 구절 찾기가 **살아 있어야** 한다 — 안 그러면 팩을 잠깐 껐다 켠 것만으로
    /// 설정이 조용히 초기화된다.
    ///
    /// 설정 화면의 「이 팩 사용」 바인딩은 `disabledSnippetPacks`만 건드린다
    /// (`SnippetSettingsView.enabledBinding`). `bibleSearchEnabled`는 **독립 Bool**이라 보존된다.
    @Test("★ 성경 팩을 껐다 켜도 단어로 구절 찾기 값이 보존된다")
    func packToggleKeepsBibleSearchValue() {
        var settings = KeyboardSettings.default
        settings.bibleSearchEnabled = true
        #expect(canSearchBible(settings, secure: nil))

        // 팩 끄기 — 설정 화면이 하는 것과 같은 조작
        settings.disabledSnippetPacks.append(SnippetPack.bible)
        #expect(!canSearchBible(settings, secure: nil))   // 함께 꺼진다
        #expect(settings.bibleSearchEnabled)                // ★ 값은 남아 있다

        // 다시 켜기
        settings.disabledSnippetPacks.removeAll { $0 == SnippetPack.bible }
        #expect(canSearchBible(settings, secure: nil))    // ★ 그대로 돌아온다
    }

    @Test("저장했다 읽으면 값이 남는다")
    func roundTrips() throws {
        var settings = KeyboardSettings.default
        settings.bibleSearchEnabled = true
        let decoded = try JSONDecoder().decode(
            KeyboardSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(decoded.bibleSearchEnabled)
    }
}

/// ★ 툴바 도구 행에 📖 칸이 언제 생기고 사라지나 (v1.1.0).
///
/// **프로덕션 함수(`KeyboardSettings.visibleTools`)를 직접 부른다** — 식을 복제하지 않는다.
/// 익스텐션 타깃은 `swift test`가 닿지 않아서, 조립 지점에 식을 두면
/// 프로덕션을 고쳐도 테스트가 전부 통과한다(검증자 2026-09-21).
@Suite("툴바 도구 — 성경 배지 칸")
struct BibleSearchToolSlotTests {

    /// 검색이 켜지고 성경 팩도 켜진, 「배지가 나올 수 있는」 설정.
    private var on: KeyboardSettings {
        var s = KeyboardSettings()
        s.bibleSearchEnabled = true
        return s
    }

    @Test("★ 켠 채 0건이면 칸이 없고, 1건 이상이면 생긴다")
    func slotFollowsBadge() {
        let zero = on.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: false)
        let some = on.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
        #expect(!zero.contains(.bibleSearch))
        #expect(some.contains(.bibleSearch))
        // 자리 예약이 아니다 — 0건이면 도구가 **다섯**이고 칸을 나눠 갖는다
        #expect(zero.count == 5 && some.count == 6)
        // 기본 자리 = 이모지와 키보드 내리기 사이
        #expect(some == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
    }

    @Test("★ 꺼져 있으면 건수가 있어도 칸이 없다")
    func offNeverShowsSlot() {
        let off = KeyboardSettings()   // bibleSearchEnabled 기본 꺼짐
        #expect(off.bibleSearchEnabled == false)
        for badge in [true, false] {
            let tools = off.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: badge)
            #expect(!tools.contains(.bibleSearch))
            #expect(tools.count == 5, "나머지 다섯은 그대로다 — 꺼진 사용자의 툴바는 예전과 같다")
        }
    }

    @Test("★ 합성 게이트가 닫히면 칸도 닫힌다 — 채움글·팩·secure")
    func compositeGateClosesSlot() {
        var noSnippets = on; noSnippets.snippetsEnabled = false
        var noPack = on; noPack.disabledSnippetPacks = [SnippetPack.bible]
        #expect(!noSnippets.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
            .contains(.bibleSearch))
        #expect(!noPack.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
            .contains(.bibleSearch))
        #expect(!on.visibleTools(hasFullAccess: true, isSecureTextEntry: true, hasBibleBadge: true)
            .contains(.bibleSearch))
        // nil은 「secure 아님」이다 — 모르면 막지 않는다
        #expect(on.visibleTools(hasFullAccess: true, isSecureTextEntry: nil, hasBibleBadge: true)
            .contains(.bibleSearch))
    }

    @Test("★ disabledTools에 bibleSearch가 있어도 동작에 영향이 없다")
    func mismatchedSaveIsHarmless() {
        var odd = on
        odd.disabledTools = [.bibleSearch]
        let tools = odd.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
        #expect(tools.contains(.bibleSearch), "옵트아웃 목록을 타지 않는다")
        // 값 자체는 **지우지 않는다** — 조용히 사용자 데이터를 지우면 복구할 근거가 사라진다
        #expect(odd.disabledTools == [.bibleSearch])
    }

    @Test("★ 전체 접근이 꺼져도 📖 칸은 남는다 — 사라지는 것은 클립보드뿐")
    func slotSurvivesWithoutFullAccess() {
        let tools = on.visibleTools(hasFullAccess: false, isSecureTextEntry: false, hasBibleBadge: true)
        #expect(tools == [.cursorLeft, .cursorRight, .emoji, .bibleSearch, .dismiss])
    }

    @Test("사용자가 옮긴 자리를 그대로 쓴다 — 필터는 순서를 바꾸지 않는다")
    func honoursUserOrder() {
        var moved = on
        moved.toolOrder = [.bibleSearch, .dismiss, .emoji, .clipboard, .cursorLeft, .cursorRight]
        let tools = moved.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
        #expect(tools.first == .bibleSearch)
        #expect(tools == moved.toolOrder)
    }

    @Test("끈 도구는 그대로 빠진다 — 📖가 그 규칙을 흐리지 않는다")
    func disabledToolsStillApply() {
        var s = on
        s.disabledTools = [.clipboard, .emoji]
        let tools = s.visibleTools(hasFullAccess: true, isSecureTextEntry: false, hasBibleBadge: true)
        #expect(tools == [.cursorLeft, .cursorRight, .bibleSearch, .dismiss])
    }
}

/// ★ 설정 앱 **순서 편집 스트립**에 📖이 언제 보이고, 안 보일 때 저장이 어떻게 되나
/// (사용자 지시 2026-09-22).
///
/// 전날에는 꺼진 📖도 흐리게 보여 줬다. 사용자가 뒤집었다 —
/// **OFF면 아예 안 보인다.** 그런데 「안 보인다」를 「저장에서도 없다」로 구현하면
/// 사용자가 끌어 둔 자리를 잃는다. 이 스위트가 그 경계를 고정한다.
@Suite("순서 편집 스트립 — 꺼진 단어로 구절 찾기")
struct OrderEditorVisibilityTests {

    private var on: KeyboardSettings {
        var s = KeyboardSettings()
        s.bibleSearchEnabled = true
        return s
    }

    @Test("★ 꺼져 있으면 스트립 목록에 없다")
    func hiddenWhenOff() {
        let off = KeyboardSettings()
        #expect(off.bibleSearchEnabled == false)
        #expect(off.toolsShownInOrderEditor()
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .dismiss])
        // 저장에는 그대로 있다 — 보이는 것과 저장된 것은 다르다
        #expect(off.orderedTools.contains(.bibleSearch))
    }

    @Test("★ 켜면 보이고, 자리는 toolOrder가 정한 자리다")
    func shownAtSavedPositionWhenOn() {
        #expect(on.toolsShownInOrderEditor()
                == [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss])
        var moved = on
        moved.toolOrder = [.bibleSearch, .dismiss, .emoji, .clipboard, .cursorLeft, .cursorRight]
        #expect(moved.toolsShownInOrderEditor().first == .bibleSearch)
        #expect(moved.toolsShownInOrderEditor() == moved.toolOrder)
    }

    @Test("꺼진 도구(disabledTools)는 그대로 보인다 — 여기서 다시 켜야 하니까")
    func disabledToolsStayVisible() {
        var s = on
        s.disabledTools = [.clipboard, .emoji]
        #expect(s.toolsShownInOrderEditor().contains(.clipboard))
        #expect(s.toolsShownInOrderEditor().contains(.emoji))
    }

    // MARK: - ★★ 핵심 함정 — 안 보이는 도구가 저장에서 사라지면 자리를 잃는다

    @Test("★★ OFF인 동안 다른 도구를 재배열해 저장해도 bibleSearch가 빠지지 않는다")
    func hiddenToolSurvivesReorder() {
        var off = KeyboardSettings()
        off.toolOrder = [.cursorLeft, .cursorRight, .clipboard, .emoji, .bibleSearch, .dismiss]

        // 스트립이 보여 준 다섯을 사용자가 재배열했다(내리기를 맨 앞으로)
        var visible = off.toolsShownInOrderEditor()
        #expect(visible == [.cursorLeft, .cursorRight, .clipboard, .emoji, .dismiss])
        let moved = visible.remove(at: 4)
        visible.insert(moved, at: 0)

        let saved = off.mergingHiddenTools(into: visible)
        // ★ 숨은 📖이 **원래 자리 번호(5번째 = index 4)** 에 되꽂힌다
        #expect(saved == [.dismiss, .cursorLeft, .cursorRight, .clipboard, .bibleSearch, .emoji])
        #expect(saved.contains(.bibleSearch), "이 단언이 깨지면 사용자가 끌어 둔 자리를 잃는다")
        #expect(saved.count == 6)
    }

    @Test("★★ 켰다 껐다 켜도 옮겨 둔 자리가 그대로다")
    func positionSurvivesOnOffOn() {
        // 켠 채로 📖을 맨 앞으로 끌었다
        var s = on
        var visible = s.toolsShownInOrderEditor()
        let badge = visible.remove(at: 4)
        visible.insert(badge, at: 0)
        s.toolOrder = s.mergingHiddenTools(into: visible)
        #expect(s.toolOrder.first == .bibleSearch)

        // 껐다 — 화면에서 사라지지만 저장은 그대로다
        s.bibleSearchEnabled = false
        #expect(!s.toolsShownInOrderEditor().contains(.bibleSearch))
        #expect(s.toolOrder.first == .bibleSearch)

        // 끈 동안 아무것도 안 건드리고 저장만 한 번 더 일어나도 살아남는다
        s.toolOrder = s.mergingHiddenTools(into: s.toolsShownInOrderEditor())
        #expect(s.toolOrder.first == .bibleSearch)

        // 다시 켰다 — 끌어 둔 맨 앞 자리 그대로
        s.bibleSearchEnabled = true
        #expect(s.toolsShownInOrderEditor().first == .bibleSearch)
    }

    @Test("숨은 것이 없으면 merging은 그대로 돌려준다")
    func mergingIsIdentityWhenNothingHidden() {
        let order: [ToolbarTool] = [.dismiss, .emoji, .bibleSearch, .clipboard, .cursorLeft, .cursorRight]
        var s = on
        s.toolOrder = order
        #expect(s.mergingHiddenTools(into: order) == order)
    }

    @Test("자리 번호가 남은 길이를 넘으면 맨 뒤에 붙인다 — 도구가 줄어든 경우 방어")
    func mergingClampsIndex() {
        var off = KeyboardSettings()
        off.toolOrder = [.cursorLeft, .cursorRight, .clipboard, .emoji, .dismiss, .bibleSearch]
        // 보이는 목록에서 둘을 빼고 넘긴다(있을 수 없는 입력이지만 터지지 않아야 한다)
        let saved = off.mergingHiddenTools(into: [.cursorLeft, .cursorRight])
        #expect(saved == [.cursorLeft, .cursorRight, .bibleSearch])
    }

    // MARK: - 이름

    @Test("★ 도구 이름이 「단어로 구절 찾기」다 — 설정 토글 제목과 같은 문자열")
    func displayNameIsRenamed() {
        #expect(ToolbarTool.bibleSearch.displayName == "단어로 구절 찾기")
        // 「구절 찾기」 단독은 주소로 찾는 단축어와 구분이 안 됐다 — 정체는 「단어로」다
        #expect(ToolbarTool.bibleSearch.displayName.hasPrefix("단어로"))
        #expect(ToolbarTool.bibleSearch.symbolName == "book")
    }
}
