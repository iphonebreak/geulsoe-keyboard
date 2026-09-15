import Testing
import Foundation
@testable import TadakData
import TadakDomain

@Suite("설정 저장소")
struct AppGroupSettingsRepositoryTests {

    @Test("App Group에 접근할 수 없어도 기본값을 낸다")
    func loadFallsBackToDefault() {
        let repository = AppGroupSettingsRepository(suiteName: "group.com.charging.tadak.nonexistent.test")
        #expect(repository.load() == .default)
    }
}

@Suite("성경 저장소")
struct BundledBibleRepositoryTests {

    private let repository = BundledBibleRepository()

    @Test("알려진 절을 정확히 조회한다")
    func looksUpKnownVerses() {
        #expect(repository.text(book: 1, chapter: 1, verse: 1)
                == "태초에 하나님이 천지를 창조하시니라")
        #expect(repository.text(book: 43, chapter: 3, verse: 16)?
                .hasPrefix("하나님이 세상을 이처럼 사랑하사") == true)
        // 마지막 절 — 인덱스 끝 경계
        #expect(repository.text(book: 66, chapter: 22, verse: 21)
                == "주 예수의 은혜가 모든 자들에게 있을지어다 아멘")
        // 가장 긴 장(시편 119편)의 마지막 절 — 존재 확인
        #expect(repository.text(book: 19, chapter: 119, verse: 176) != nil)
    }

    /// **본문이 빈 절은 하나도 없어야 한다** — 빈 본문은 곧 「절삭」이고, 권리자(대한성서공회)가
    /// 명시적으로 금지한 것이다(`docs/release/ip-audit.md` 1절). 사용자에게는 "칩을 눌렀는데
    /// 아무 것도 안 들어갔다"로 보인다.
    ///
    /// 31,102절을 전수로 돈다 — mmap 이라 4.5MB 를 힙에 올리지 않고, 0.1초 안에 끝난다.
    /// `tools/convert_bible.py` 에도 같은 가드가 있지만 **여기서 한 번 더 본다**:
    /// 재생성 없이 `bible.tdb` 만 갈아 끼우는 경로가 있기 때문이다.
    @Test("번들 본문에 빈 절이 하나도 없다")
    func noEmptyVerses() {
        var empty: [String] = []
        var scanned = 0
        for book in 1...66 {
            for chapter in 1...150 {
                for verse in 1...180 {
                    guard let text = repository.text(book: book, chapter: chapter, verse: verse)
                    else { continue }
                    scanned += 1
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        empty.append("\(book) \(chapter):\(verse)")
                    }
                }
            }
        }
        // 양성 대조 — 스캔이 실제로 본문을 읽고 있다는 것부터 고정한다.
        // 이게 없으면 조회가 전부 nil 이 되는 회귀에서 "빈 절 0건"이 거짓으로 통과한다.
        #expect(scanned == 31_102, "전수 스캔이 31,102절을 읽어야 한다 — 읽은 절: \(scanned)")
        #expect(empty.isEmpty, "빈 본문 절: \(empty)")
    }

    /// 정본(개역한글판)이 **"1-2" 처럼 묶어 인쇄한 합병절**의 뒷절 21개.
    ///
    /// 절 구분이 틀린 게 아니다 — 정본 자체가 두 절을 묶어 찍었고, 합쳐진 본문은 앞절에 있다.
    /// 그래서 본문을 쪼개지 않고 뒷절에 앞절을 가리키는 표기만 둔다.
    ///
    /// **데이터를 LifeBible 로 교체하면서 12건 → 21건이 됐다**(2026-09-15). 옛 입력
    /// (`hive_sample/lib/bibleAdd.dart`)은 이 21곳을 네 형식으로 제각각 처리했고 — 빈 문자열
    /// 6건, `상동` 3건, `12절과 상동`, `8절과 같음`, 앞 숫자가 잘린 `과 동일함`(신 30:10) —
    /// 나머지 9곳은 합쳐진 본문을 뒷절에도 복제해 뒀다. LifeBible 은 21곳 전부 한 형식이다.
    /// 그중 12건은 대한성서공회 개역한글판 본문에서 합병 표기를 직접 확인했다.
    @Test("합병절의 뒷절은 앞절을 가리킨다", arguments: [
        (5, 6, 19, 18), (5, 15, 5, 4), (5, 30, 10, 9),
        (6, 2, 13, 12), (13, 16, 13, 12),
        (18, 31, 34, 33), (18, 35, 11, 10),
        (19, 92, 2, 1), (19, 92, 3, 1), (19, 105, 6, 5),
        (23, 7, 9, 8), (23, 30, 2, 1), (23, 48, 2, 1),
        (24, 21, 2, 1), (24, 32, 4, 3), (24, 32, 5, 3), (24, 33, 11, 10),
        (26, 24, 5, 4), (26, 25, 3, 2),
        (44, 15, 26, 25), (45, 9, 2, 1)
    ])
    func mergedVersePointsToFirst(book: Int, chapter: Int, verse: Int, first: Int) {
        #expect(repository.text(book: book, chapter: chapter, verse: verse)
                == "(\(first)절에 포함되어 있음)")
        // 가리키는 앞절에 실제로 본문이 있어야 표기가 말이 된다
        let head = repository.text(book: book, chapter: chapter, verse: first)
        #expect((head?.count ?? 0) > 20, "앞절 \(first)절에 합쳐진 본문이 있어야 한다")
    }

    /// **시편 72:20 은 반드시 따로 있어야 한다.**
    ///
    /// LifeBible 원본은 20절 레코드가 없고 20절 본문이 19절 끝에 마침표로 이어 붙어 있다
    /// (그래서 그쪽 절 수가 31,101 이다). 정본은 18·19·20 에 각각 번호를 달고 20절이 이 편의
    /// 마지막 절이므로 — 대한성서공회 개역한글판에서 직접 확인했다 — 합병절이 아니라 결손이다.
    /// `tools/convert_bible.py` 의 `split_psalm_72()` 가 이어 붙은 자리를 되가른다.
    /// **한 절이 사라진 채로 나가면 그게 곧 절삭이다.**
    @Test("시편 72:20 이 19절과 따로 있다")
    func psalm72LastVerseIsSeparate() {
        #expect(repository.text(book: 19, chapter: 72, verse: 19)
                == "그 영화로운 이름을 영원히 찬송할지어다 온 땅에 그 영광이 충만할지어다 아멘 아멘")
        #expect(repository.text(book: 19, chapter: 72, verse: 20)
                == "이새의 아들 다윗의 기도가 필하다")
        #expect(repository.text(book: 19, chapter: 72, verse: 21) == nil, "72편은 20절까지")
    }

    /// **1961년 발행 당시 맞춤법이 살아 있어야 한다.**
    ///
    /// 「세째·네째」는 1988년 맞춤법 개정 **전** 표기다. 옛 입력은 이걸 「셋째·넷째」로 손질한
    /// 판이었고(46/38건), 그래서 데이터를 LifeBible 로 바꿨다 — 권리자가 요구한 동일성유지권
    /// 쪽에서 원문에 가까운 판을 쓰는 것이 맞다. 조용히 옛 데이터로 돌아가는 것을 여기서 막는다.
    @Test("1961년 표기(세째·네째)가 살아 있다")
    func keepsPre1988Spelling() {
        // 창세기 2:14 한 절에 「세째」와 「네째」가 함께 있다 — 손질된 판이면 둘 다 바뀐다
        let genesis214 = repository.text(book: 1, chapter: 2, verse: 14)
        #expect(genesis214?.contains("세째") == true, "세째 강의 이름은 힛데겔이라")
        #expect(genesis214?.contains("네째") == true, "네째 강은 유브라데더라")
        #expect(genesis214?.contains("셋째") == false, "현대 표기가 섞이면 안 된다")
    }

    /// 정본이 **실제로 없는 절**에 쓰는 표기 `(없음)` 13건은 그대로 둔다 —
    /// 우리가 지어낸 것이 아니라 대한성서공회 본문에도 그렇게 적혀 있다(행 15:34 에서 확인).
    /// 합병절 표기와 혼동해 이쪽을 건드리면 안 된다.
    @Test("정본의 (없음) 표기는 건드리지 않는다", arguments: [
        (40, 17, 21), (40, 18, 11), (40, 23, 14), (41, 9, 44), (41, 9, 46),
        (41, 11, 26), (41, 15, 28), (42, 17, 36), (42, 23, 17),
        (44, 8, 37), (44, 15, 34), (44, 28, 29), (45, 16, 24)
    ])
    func absentVerseKeepsCanonicalNotation(book: Int, chapter: Int, verse: Int) {
        #expect(repository.text(book: book, chapter: chapter, verse: verse) == "(없음)")
    }

    @Test("존재하지 않는 절은 nil이다")
    func missingVersesReturnNil() {
        #expect(repository.text(book: 1, chapter: 99, verse: 1) == nil)
        #expect(repository.text(book: 1, chapter: 1, verse: 32) == nil, "창세기 1장은 31절까지")
        #expect(repository.text(book: 0, chapter: 1, verse: 1) == nil)
        #expect(repository.text(book: 67, chapter: 1, verse: 1) == nil)
        #expect(repository.text(book: -1, chapter: 1, verse: 1) == nil)
    }

    @Test("리소스가 없는 번들이면 모든 조회가 nil이다")
    func brokenBundleReturnsNil() {
        let repository = BundledBibleRepository(bundle: .main)
        #expect(repository.text(book: 1, chapter: 1, verse: 1) == nil)
    }

    /// 리뷰 MEDIUM 회귀 방어 — 헤더는 유효하지만 인덱스 엔트리가 0인 손상 파일.
    @Test("손상 인덱스 엔트리에서 크래시 없이 nil을 낸다")
    func corruptedIndexEntryReturnsNil() throws {
        var corrupt = Data("TDBB".utf8)
        for value in [UInt32(1), 1, 28] {  // version, 절 수 1, textStart 16+12
            withUnsafeBytes(of: value.littleEndian) { corrupt.append(contentsOf: $0) }
        }
        corrupt.append(Data(count: 12))  // 엔트리 전부 0 — book/chapter/verse 무효

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).tdb")
        try corrupt.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let repository = BundledBibleRepository(url: url)
        #expect(repository.text(book: 1, chapter: 1, verse: 1) == nil)
    }
}

@Suite("채움글 저장소")
struct SnippetRepositoryTests {

    @Test("국가 상징 팩 — 애국가 1~4절 + 국기에 대한 맹세·헌법 전문·제1조·독립선언서")
    func loadsBundledNational() {
        let entries = BundledSnippetRepository().entries()
        let anthem = entries.filter { $0.trigger.hasPrefix("애국가") }
        #expect(anthem.map(\.trigger) == ["애국가 1절", "애국가 2절", "애국가 3절", "애국가 4절"])
        #expect(anthem.first?.body.hasPrefix("동해물과 백두산이") == true)
        for entry in anthem {
            #expect(entry.body.contains("무궁화 삼천리 화려강산"), "\(entry.trigger) 후렴 포함")
        }
        let triggers = Set(entries.map(\.trigger))
        for expected in ["국기에 대한 맹세", "국기맹세", "헌법 전문", "헌법전문", "헌법 1조", "헌법 제1조", "헌법 2조", "헌법 제130조",
                         "독립선언서", "기미독립선언서"] {
            #expect(triggers.contains(expected), "\(expected)")
        }
        #expect(entries.first { $0.trigger == "헌법 전문" }?.body.hasPrefix("유구한 역사와 전통에 빛나는") == true)
        #expect(entries.first { $0.trigger == "헌법 1조" }?.body.contains("민주공화국") == true)
        // 헌법 1~130조 전부, 두 트리거 형태 (tools/convert_constitution.py — 위키문헌 원문 변환)
        for number in 1...130 {
            #expect(triggers.contains("헌법 \(number)조") && triggers.contains("헌법 제\(number)조"), "헌법 \(number)조")
        }
        // 법제처 표기 그대로 — 항 번호 뒤 공백 없음 (tools/convert_constitution.py)
        #expect(entries.first { $0.trigger == "헌법 2조" }?.body.hasPrefix("제2조 ①대한민국의 국민이 되는 요건은 법률로 정한다.") == true)
        #expect(entries.first { $0.trigger == "헌법 제130조" }?.body.hasPrefix("제130조") == true)
        #expect(entries.first { $0.trigger == "독립선언서" }?.body.hasPrefix("오등은 자에") == true)
    }

    /// 인사·상용구 팩 — 자체 작성 문구, 붙여쓰기·띄어쓰기 트리거 쌍 (PDR snippet-packs-greetings-national)
    @Test("인사·상용구 팩을 읽고, 세 팩의 트리거가 서로 겹치지 않는다")
    func loadsGreetingsAndTriggersAreUnique() {
        let greetings = BundledSnippetRepository(resourceName: "Greetings").entries()
        #expect(greetings.count >= 20)
        for expected in ["새해인사", "새해 인사", "생일축하", "조의문", "조문답례", "감사인사", "사과문", "쾌유기원",
                         "입사인사", "입사 인사", "퇴사인사", "첫인사", "안부인사", "크리스마스인사", "졸업축하", "입학축하"] {
            #expect(greetings.contains { $0.trigger == expected }, "\(expected)")
        }
        for entry in greetings {
            #expect(!entry.body.isEmpty && !entry.title.isEmpty, "\(entry.trigger)")
            #expect(entry.trigger.count >= 3, "짧은 트리거는 오탐 — \(entry.trigger)")
        }
        let all = greetings + BundledSnippetRepository().entries()
        #expect(Set(all.map(\.trigger)).count == all.count, "팩 간·팩 내 트리거 중복 없음")
    }

    @Test("리소스가 없는 번들이면 빈 배열이다")
    func brokenBundleReturnsEmpty() {
        #expect(BundledSnippetRepository(bundle: .main).entries().isEmpty)
    }

    @Test("사용자 문구 저장·읽기가 왕복한다")
    func userSnippetsRoundTrip() {
        let suite = "test.tadak.snippets.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let repository = AppGroupSnippetRepository(suiteName: suite)
        #expect(repository.entries().isEmpty, "저장 전에는 비어 있다")

        let saved = [SnippetEntry(trigger: "우리집", title: "집 주소", body: "서울시 어딘가 123")]
        #expect(repository.save(saved))
        #expect(repository.entries() == saved)
    }
}

@Suite("추천단어 사전")
struct BundledWordDictionaryTests {

    private let dictionary = BundledWordDictionary()

    /// Python 변환기와 Swift 분해 규칙의 정합성까지 함께 검증하는 조회.
    @Test("자모 접두로 빈도 상위 후보를 낸다")
    func prefixLookup() {
        let hits = dictionary.candidates(jamoPrefix: "ㅇㅏㄴㄴㅕㅇ", limit: 3)
        #expect(hits.map(\.word) == ["안녕", "안녕하세요", "안녕히"],
                "원본 빈도(4963/3692/434) 순서")
    }

    @Test("조합 중간 상태(받침으로 붙은 초성)도 접두 매칭된다")
    func midCompositionPrefix() {
        // "안녕핫" — ㅅ이 받침인 상태. 자모로는 안녕하세요의 접두다
        let hits = dictionary.candidates(jamoPrefix: "ㅇㅏㄴㄴㅕㅇㅎㅏㅅ", limit: 3)
        #expect(hits.first?.word == "안녕하세요")
    }

    @Test("일치가 없거나 입력이 비면 빈 배열이다")
    func noMatch() {
        #expect(dictionary.candidates(jamoPrefix: "ㅋㅋㅋㅋㅋㅋㅋㅋㅋ", limit: 3).isEmpty)
        #expect(dictionary.candidates(jamoPrefix: "", limit: 3).isEmpty)
        #expect(dictionary.candidates(jamoPrefix: "ㅇㅏ", limit: 0).isEmpty)
    }

    @Test("리소스가 없는 번들이면 빈 사전이다")
    func brokenBundleReturnsEmpty() {
        let dictionary = BundledWordDictionary(bundle: .main)
        #expect(dictionary.candidates(jamoPrefix: "ㅇㅏ", limit: 3).isEmpty)
    }

    /// 리뷰 반영 — 유효 헤더 + 파일 밖을 가리키는 엔트리에서 OOB 없이 빈 결과여야 한다.
    @Test("손상 엔트리(파일 밖 오프셋)에서 크래시 없이 빈 배열이다")
    func corruptedEntryReturnsEmpty() throws {
        var corrupt = Data("TDWD".utf8)
        for value in [UInt32(1), 1, 32] {  // version, 단어 수 1, blobStart 16+16
            withUnsafeBytes(of: value.littleEndian) { corrupt.append(contentsOf: $0) }
        }
        // 엔트리: jamoOffset/wordOffset이 블롭 밖(9999)을 가리킨다
        for value in [UInt32(9999), UInt32(6) << 16 | UInt32(6), 9999, 10] {
            withUnsafeBytes(of: value.littleEndian) { corrupt.append(contentsOf: $0) }
        }
        corrupt.append(Data("자모키".utf8))  // 작은 블롭

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).tdw")
        try corrupt.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let dictionary = BundledWordDictionary(url: url)
        #expect(dictionary.candidates(jamoPrefix: "ㅇㅏ", limit: 3).isEmpty)
    }
}

@Suite("사용자 단어 저장소")
struct UserWordRepositoryTests {

    @Test("저장·읽기가 왕복하고, 빈 스위트는 빈 딕셔너리다")
    func roundTrip() {
        let suite = "test.tadak.userwords.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let repository = AppGroupUserWordRepository(suiteName: suite)
        #expect(repository.load().isEmpty)
        #expect(repository.save(["타닥": 3, "채움글": 1]))
        #expect(repository.load() == ["타닥": 3, "채움글": 1])
    }
}

@Suite("클립보드 기록 저장소")
struct ClipboardHistoryRepositoryTests {

    @Test("빈 스위트는 빈 기록, 저장·읽기가 왕복하고, clear로 비워진다")
    func roundTripAndClear() {
        let suite = "test.tadak.clipboard.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }

        let repository = AppGroupClipboardHistoryRepository(suiteName: suite)
        #expect(repository.load().entries.isEmpty)

        var history = ClipboardHistory()
        history.record("첫 번째")
        history.record("두 번째")
        #expect(repository.save(history))
        #expect(repository.load().entries == ["두 번째", "첫 번째"])

        repository.clear()
        #expect(repository.load().entries.isEmpty, "끄기/지우기 경로 — 저장분이 남지 않는다")
    }
}

@Suite("테마 저장소")
struct BundledThemeRepositoryTests {

    @Test("번들 JSON에서 기본 테마 4개를 읽는다")
    func loadsBundledThemes() {
        let repository = BundledThemeRepository()
        let ids = repository.availableThemes().map(\.id)
        #expect(ids == ["system", "pure-light", "pure-dark", "midnight"])
    }

    @Test("id로 테마를 찾는다")
    func findsThemeByID() {
        let repository = BundledThemeRepository()
        #expect(repository.theme(id: "midnight").displayName == "미드나이트")
    }

    @Test("미지의 id는 system으로 폴백한다")
    func unknownIDFallsBackToSystem() {
        let repository = BundledThemeRepository()
        #expect(repository.theme(id: "does-not-exist").id == "system")
    }

    @Test("리소스가 없는 번들이면 내장 system 테마로 폴백한다")
    func brokenBundleFallsBack() {
        // 리소스가 없는 번들 — 메인 번들(테스트 러너)에는 Themes.json이 없다
        let repository = BundledThemeRepository(bundle: .main)
        #expect(repository.availableThemes().count == 1)
        #expect(repository.theme(id: "anything").id == "system")
    }

    @Test("모든 테마가 라이트/다크 팔레트 쌍을 가진다")
    func allThemesHaveBothPalettes() {
        for theme in BundledThemeRepository().availableThemes() {
            #expect(!theme.light.keyboardBackground.isEmpty, "\(theme.id) light")
            #expect(!theme.dark.keyboardBackground.isEmpty, "\(theme.id) dark")
        }
    }
}
