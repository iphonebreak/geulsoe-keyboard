import Foundation
import TadakDomain

/// 툴바 추천 칩 하나 — 탭하면 **단축어**를 지우고 본문을 넣는다.
public struct SnippetSuggestion: Equatable, Sendable {
    /// 문서 꼬리에서 지울 **단축어 원문**(사용자가 실제로 친 그대로 — 띄어쓰기 포함). 길이만 들고 있으면 탭 시점에 꼬리가 이미 바뀌었어도
    /// 그만큼 지워 버린다 — 칩을 두 번 누르면 방금 삽입한 본문 끝이 잘려 나갔다 (QA BLOCK-2).
    /// 삽입 직전에 꼬리와 대조하는 것이 이 값의 목적이다.
    public let trigger: String
    public let title: String
    public let body: String
    /// 본문 앞에 함께 삽입되는 머리말 — 성경은 "[고전 12:3] " (사용자 결정 2026-09-03:
    /// 붙여넣은 본문이 어느 절인지 보이게). **사용자가 친 단축어 원문을 그대로 되비춘다**
    /// (2026-09-14) — 정규 표기로 바꾸지 않는다. 문구 팩·사용자 문구는 nil.
    public let prefix: String?
    /// 날짜 채움글이 값을 **계산한 시각** — 날짜 칩만 가진다(문구·성경은 nil).
    public let computedAt: Date?
    /// 날짜 채움글의 종류 — 탭 시점 신선도 판정의 단위(분/일)를 정한다. 문구·성경은 nil.
    public let kind: DateSnippetKind?
    /// ★ VoiceOver가 읽을 **값** — 날짜 칩만 가진다(v1.2.0 출시 전 마무리 ①). `body`와 같은 순간·같은 값을
    /// **한글형**(`2026년 9월 27일`·`오후 9시 54분`)으로 한 번 더 만든 것이다. 규범형 `2026. 9. 27.`을 그대로 읽히면
    /// 구두점 읽기가 사용자의 VoiceOver 구두점 설정에 달려 있다(Apple 문서는 `accessibilitySpeechPunctuation`
    /// 같은 조절 수단만 적고 숫자·마침표를 어떻게 읽는지는 적지 않는다 — Context7 확인). 한글형은 구두점이 없다.
    public let spokenValue: String?
    /// U7 — **같은 꼬리 구간**에 함께 걸린 다른 후보 수(칩 「+n」, 최대 `SnippetCandidateGate.limit` − 1). 칩만 이 값을 갖고
    /// 길게 누르기 목록의 다른 행은 0이다. 본문은 들지 않는다 — 목록은 길게 누를 때 `SnippetMatcher.candidates`가 만든다(10-6 ①).
    public let alternativeCount: Int

    /// 문서 끝에서 지울 문자 수 — **꼬리 원문 기준**이다(정규화 길이가 아니다).
    public var triggerLength: Int { trigger.count }

    public init(
        trigger: String, title: String, body: String, prefix: String? = nil,
        computedAt: Date? = nil, kind: DateSnippetKind? = nil, spokenValue: String? = nil,
        alternativeCount: Int = 0
    ) {
        self.trigger = trigger
        self.title = title
        self.body = body
        self.prefix = prefix
        self.computedAt = computedAt
        self.kind = kind
        self.spokenValue = spokenValue
        self.alternativeCount = alternativeCount
    }

    /// 같은 값에 다른 후보 수만 바꾼 칩
    func withAlternativeCount(_ count: Int) -> SnippetSuggestion {
        count == alternativeCount ? self : SnippetSuggestion(
            trigger: trigger, title: title, body: body, prefix: prefix, computedAt: computedAt, kind: kind,
            spokenValue: spokenValue, alternativeCount: count)
    }

    /// 칩의 VoiceOver 라벨.
    ///
    /// - 문구·성경 칩(`spokenValue == nil`): **기존 규칙 그대로** — 「채움글 <제목> 붙여넣기」.
    /// - 날짜 칩: 날짜는 **값이 핵심**이라 값을 넣는다 — 「채움글 오늘 날짜, 2026년 9월 27일 붙여넣기」.
    ///   공휴일 상태(`· 올해`·`· 지남`·`· 오늘`)도 쉼표로 끊어 함께 읽는다 — 「광복절 날짜, 지남, 2026년 8월 15일」.
    ///   (가운뎃점 `·`은 읽기가 설정에 따라 달라 쉼표로 바꾼다.)
    public var accessibilityLabel: String {
        guard let spokenValue else { return "채움글 \(title) 붙여넣기" }
        let spokenTitle = title.replacingOccurrences(of: " · ", with: ", ")
        return "채움글 \(spokenTitle), \(spokenValue) 붙여넣기"
    }

    /// ★ 탭하는 순간 **표시 단위가 바뀌었는가** — 바뀌었으면 넣지 않고 칩을 갱신한다
    /// (PDR `date-snippet-pack.md` 7-2절, 사장님 결정).
    ///
    /// 칩을 띄운 뒤 5분 있다 탭하면 「보여 준 값 = 넣는 값」 원칙 때문에 5분 전 시각이 들어간다 —
    /// 상한이 없다(반론자2). 몰래 새 값을 넣는 대신 **거절하고 새 칩을 다시 보여 준다.**
    /// 날짜는 **일**, 시간이 들어가면 **분** 단위로 본다. 문구·성경 칩(계산 시각 없음)은 늘 신선하다.
    ///
    /// - Parameter calendar: 계산에 쓴 것과 같은 달력(`DateSnippetParser.makeCalendar()`)
    public func isStale(at now: Date, calendar: Calendar) -> Bool {
        guard let computedAt, let kind else { return false }
        let granularity: Calendar.Component = kind == .dateOnly ? .day : .minute
        return !calendar.isDate(now, equalTo: computedAt, toGranularity: granularity)
    }

    /// 계산 시각만 빼고 같은 칩인가 — 날짜 칩은 매 키 입력마다 새로 계산돼 `computedAt`만 바뀐다.
    /// 조립 지점이 이것으로 **같은 칩을 다시 싣지 않는다**(뷰 갱신 낭비 방지). 값이 같다는 것은
    /// 같은 분/일 안이라는 뜻이라 옛 계산 시각을 그대로 들고 있어도 신선도 판정이 바뀌지 않는다.
    /// 다른 후보 수(U7 「+n」)가 바뀌면 다른 칩이다 — 다시 싣는다.
    public func hasSameContent(as other: SnippetSuggestion?) -> Bool {
        guard let other else { return false }
        return trigger == other.trigger && title == other.title && body == other.body
            && prefix == other.prefix && kind == other.kind && spokenValue == other.spokenValue
            && alternativeCount == other.alternativeCount
    }

    /// 실제로 문서에 들어가는 텍스트
    public var insertedText: String { (prefix ?? "") + body }
}

/// 입력 꼬리에서 채움글 **단축어**를 찾는다.
///
/// 우선순위: 문구 목록(entries — U1 순서 목록(내 채움글·외부 문구형 팩) 다음 내장 팩, `SnippetSourceComposer`) > 날짜·시간(`dates`)
/// > 외부 팩 번호형 **템플릿**(`templates`, 외부 채움글 1-b) > 성경 참조(단일 절·절 범위) — PDR `external-snippet-packs.md` 10-3.
/// 문구끼리 겹치면 **정규화 길이가 긴** 단축어가 이기고, 같으면 앞선 항목(=사용자)이 이긴다.
/// 칩은 1건이다. 같은 꼬리 구간에 함께 걸린 다른 후보는 칩을 길게 눌러 고른다(U7 — `candidates(forTail:isSecureTextEntry:limit:)`,
/// 칩은 그 수만 `alternativeCount`로 든다).
///
/// ## ★ 띄어쓰기를 보지 않는다 (2026-09-15 사장님 지시)
///
/// "우리집주소"로 등록해도 **"우리집 주소"·"우 리 집 주 소"** 로 발동한다.
/// 정규화는 **공백·개행 제거**다(`filter { !$0.isWhitespace }`).
///
/// **지울 길이는 정규화 길이가 아니라 꼬리 원문에서 실제로 맞은 구간의 길이다.**
/// 5자짜리 단축어로 등록했어도 사용자가 6자를 쳤으면 6자를 지워야 한다.
/// 그래서 `SnippetSuggestion.trigger` 에는 **꼬리에서 잘라낸 원문 그대로**를 담는다 —
/// 탭 시점의 꼬리 정합 검사(QA BLOCK-2 방어)가 그 값으로 돈다.
///
/// **범위는 `entries` 경로 전부다** — 사용자 문구와 내장 팩(애국가·인사말)까지.
/// **성경 참조 파서(`BibleReferenceParser`)는 건드리지 않는다** — 규칙을 하나로 두기 위한 결정이고
/// 거긴 이미 "애국가1절"·"애국가 1절" 양쪽을 자기 규칙으로 받는다.
///
/// ## 성능 — 키 입력마다 도는 핫패스다
///
/// - 정규화된 단축어는 **`init` 에서 미리 계산**해 둔다. 매 호출마다 다시 만들지 않는다.
/// - 꼬리도 진입 시 **한 번만** 역방향으로 풀어(비공백 글자 + 원문 인덱스) 모든 엔트리가 공유한다.
///   그래서 O(꼬리 48 + 엔트리 수 × 단축어 길이)다.
public struct SnippetMatcher: Sendable {

    /// 미리 정규화해 둔 단축어 하나 — 엔트리 순서와 함께 든다.
    private struct Needle: Sendable {
        /// 공백을 뺀 글자들. 매칭은 이 배열을 **뒤에서 앞으로** 훑는다.
        let characters: [Character]
        /// 이 단축어가 속한 엔트리의 인덱스 — 동점일 때 앞선 엔트리가 이기게 한다.
        let entryIndex: Int
    }

    /// 꼬리를 **한 번만** 풀어 둔 것 — 모든 분기가 공유한다(`suggestion(forTail:)` 주석).
    private struct Scan {
        let tail: String
        let characters: [Character]
        /// 비공백 글자와 그 글자의 원문 인덱스, 꼬리 끝에서부터. 줄바꿈에서 멈춘다
        let reversed: [(character: Character, index: Int)]
    }

    private let bible: (any BibleVerseRepository)?
    private let entries: [SnippetEntry]
    /// 정규화 길이 **내림차순**으로 미리 정렬해 둔다 — 첫 매치가 곧 최선이라 나머지를 안 본다.
    /// 길이가 같으면 `entryIndex` 오름차순(= 앞선 엔트리 우선).
    private let needles: [Needle]

    /// - Parameters:
    ///   - bible: 성경 본문 저장소. nil이면 성경 매칭을 건너뛴다.
    ///   - entries: 단축어 문구 목록. **사용자 문구 → 내장 팩 순서로 합쳐 넣는다.**
    /// 성경 후보 삽입 시 `[창세기 1장 1절] `(친 그대로) 머리말을 앞에 넣을지
    /// (설정 `bibleSnippetPrefixEnabled`, 2026-09-07)
    private let biblePrefix: Bool
    private let dates: DateSnippetParser?
    /// 외부 팩 번호형 템플릿(`사자성어{n}번`) — 날짜 다음·성경 앞(10-3). nil이면 이 분기를 건너뛴다
    private let templates: PackTemplateMatcher?
    /// U7 — 후보 목록의 출처(내 채움글·팩 이름·내장 팩). 칩 판정에는 쓰지 않는다
    private let origins: SnippetOrigins

    /// - Parameter biblePrefix: 성경 머리말 여부 (기본 켬)
    /// - Parameter templates: 외부 팩 템플릿 — 소유권·동점은 `PackTemplateMatcher`가 목록 순서로 정한다(10-4)
    /// - Parameter origins: 항목·템플릿 팩의 출처(`SnippetSourceComposer.Sources.origins`). 빠지면 문구는 「내 채움글」로 본다
    public init(
        bible: (any BibleVerseRepository)?, entries: [SnippetEntry], biblePrefix: Bool = true,
        dates: DateSnippetParser? = nil, templates: PackTemplateMatcher? = nil, origins: SnippetOrigins = SnippetOrigins()
    ) {
        self.bible = bible
        self.entries = entries
        self.biblePrefix = biblePrefix
        self.dates = dates
        self.templates = templates
        self.origins = origins
        // 정규화는 **여기서 한 번만** 한다 (핫패스 규율).
        // 공백만으로 이뤄진 단축어와 빈 단축어는 아예 목록에 넣지 않는다 — 꼬리 어디에나
        // 맞아 버리는 것을 원천 차단한다.
        var built: [Needle] = []
        for (index, entry) in entries.enumerated() {
            for trigger in entry.triggers {
                // **정규화는 `SnippetEntry.normalizedTrigger` 한 곳에서만** 정의한다 —
                // 설정 화면의 중복 판정과 여기의 발동 규칙이 갈리면 안 된다.
                let characters = Array(SnippetEntry.normalizedTrigger(trigger))
                guard !characters.isEmpty else { continue }
                built.append(Needle(characters: characters, entryIndex: index))
            }
        }
        built.sort {
            $0.characters.count != $1.characters.count
                ? $0.characters.count > $1.characters.count      // 긴 쪽이 먼저
                : $0.entryIndex < $1.entryIndex                   // 같으면 앞선 엔트리
        }
        needles = built
    }

    /// ★ **secure 입력란이면 아무것도 매칭하지 않는다** — 문구·성경·날짜 전부(보안 규칙).
    ///
    /// 이 게이트는 원래 조립 지점(`KeyboardViewController.updateSuggestionBar`)의 삼항식에만 있어
    /// `swift test`가 닿지 않았다(반론자1 — 날짜 팩 수용 기준 8). 같은 규칙을 여기로 옮겨 테스트로 잠근다.
    public func suggestion(forTail tail: String, isSecureTextEntry: Bool) -> SnippetSuggestion? {
        isSecureTextEntry ? nil : suggestion(forTail: tail)
    }

    /// 칩 — 분기 순서대로 처음 맞은 후보. 맞았으면 **같은 꼬리 구간**에 함께 걸린 다른 후보 수를 `alternativeCount`로 단다(U7 「+n」).
    ///
    /// ## 핫패스 (10-6 ① (a)(b) · 지시서 2절 ①)
    ///
    /// 칩이 **안 뜨는** 입력(대부분의 키 입력)은 U7 전과 같은 일만 한다 — 네 분기가 모두 빗나가면 끝이다.
    /// 칩이 **맞았을 때만** 뒤 후보를 **세기만** 한다(값·제목·본문을 만들지 않는다): 같은 정규화 길이의 뒤 needle(정렬돼 있어 연속 구간) ·
    /// 뒤 분기 하나씩(날짜 끝말·템플릿 접미 거절은 O(1), 다른 팩 번호는 이진 탐색) · 성경 본문 존재 확인(빈 절은 후보가 아니다 —
    /// 목록과 **같은 판정**). 상한 8에서 멈춘다. 개수는 칩과 함께 보여야 하므로 미루지 않는다. 목록(`candidates`)은 길게 누를 때만 만든다.
    public func suggestion(forTail tail: String) -> SnippetSuggestion? {
        guard !tail.isEmpty else { return nil }
        guard let (chip, count) = walk(Self.scan(tail), limit: SnippetCandidateGate.limit, visit: nil) else { return nil }
        return chip.withAlternativeCount(count - 1)
    }

    /// U7 — 칩을 길게 눌렀을 때의 후보 목록(10-6 ①②, AC-37~39 · AC-45 · AC-46).
    ///
    /// - **같은 꼬리 구간에 맞은 것만**: 칩과 같은 시작 위치 = 같은 `trigger`(꼬리에서 잘라낸 원문). 더 짧게·길게 맞은 것은 없다.
    ///   그래서 모든 행의 지울 길이가 같고, 탭 때의 정합 검사는 기존 `insertSnippet` 그대로다(새 삽입 경로 없음).
    /// - **순서** = 분기(문구 → 날짜 → 템플릿 → 성경) → U1 목록 순서(내장 팩은 뒤) → 팩 안 패턴 순서. 템플릿은 소유 팩 다음에
    ///   **소유하지 못한 팩의 같은 번호**(10-4는 칩에 대해 불변 — 소유 팩에 n이 없으면 칩도 목록도 없다).
    /// - 첫 원소는 `suggestion(forTail:)`과 **같은 값**이다(`alternativeCount` 포함, 기본 `limit`일 때). 둘째부터는 개수 0.
    /// - secure 입력란·빈 꼬리·칩 없음이면 빈 배열.
    public func candidates(
        forTail tail: String, isSecureTextEntry: Bool, limit: Int = SnippetCandidateGate.limit
    ) -> [SnippetCandidate] {
        guard !isSecureTextEntry, limit > 0, !tail.isEmpty else { return [] }
        var list: [SnippetCandidate] = []
        list.reserveCapacity(min(limit, SnippetCandidateGate.limit))
        guard walk(Self.scan(tail), limit: limit, visit: { list.append($0) }) != nil else { return [] }
        list[0] = SnippetCandidate(suggestion: list[0].suggestion.withAlternativeCount(list.count - 1), origin: list[0].origin)
        return list
    }

    // MARK: - 판정 — 칩과 목록이 **같은 함수**를 쓴다(「+2」인데 행이 둘인 어긋남 방지)

    /// 꼬리를 뒤에서 앞으로 한 번 푼다.
    ///
    /// ## ★ 줄바꿈에서 **멈춘다** (사장님 결정 2026-09-23)
    ///
    /// 예전에는 개행도 `isWhitespace`라 **공백처럼 건너뛰었다.** 그래서
    /// 「우 리 집 주 소」가 먹는 것과 **같은 규칙으로 줄이 갈려도 붙었고**,
    /// 2~3자 짧은 단축어가 **엉뚱한 줄에서 발동**할 수 있었다.
    ///
    /// 개행 앞은 **다른 줄**이므로 같은 단축어의 일부가 아니다 — 거기서 끊는다.
    /// `isNewline`을 **먼저** 본다: 개행은 `isWhitespace`이기도 해서 순서를 바꾸면
    /// 그냥 건너뛰어 버린다(`\n`·`\r`·`\r\n` 전부 `isNewline`이 잡는다).
    ///
    /// ★ **`SnippetEntry.normalizedTrigger`는 건드리지 않았다.** 그 함수는 설정의
    ///   중복 판정과 여기의 발동이 공유하는 단일 출처이고, 등록된 단축어에 개행이 들어갈
    ///   일은 없다 — 고칠 자리는 **꼬리를 되짚는 여기**다.
    ///
    /// ★ 지울 길이 불변식은 그대로다. `start`는 여전히 **마지막으로 맞은 글자의 원문 인덱스**라
    ///   개행 뒤에서만 잡히고, 잘라낸 원문이 줄을 넘지 않는다.
    private static func scan(_ tail: String) -> Scan {
        let characters = Array(tail)
        var reversed: [(character: Character, index: Int)] = []
        reversed.reserveCapacity(characters.count)
        for index in stride(from: characters.count - 1, through: 0, by: -1) {
            let character = characters[index]
            if character.isNewline { break }        // 줄 경계 — 그 앞은 다른 줄이다
            if character.isWhitespace { continue }  // 같은 줄 안의 공백만 건너뛴다
            reversed.append((character, index))
        }
        return Scan(tail: tail, characters: characters, reversed: reversed)
    }

    /// needle이 꼬리 끝에 맞나(공백 무시)
    @inline(__always)
    private static func matches(_ needle: Needle, _ reversed: [(character: Character, index: Int)]) -> Bool {
        guard needle.characters.count <= reversed.count else { return false }
        for offset in 0..<needle.characters.count
        where reversed[offset].character != needle.characters[needle.characters.count - 1 - offset] {
            return false
        }
        return true
    }

    /// 처음 맞은 needle — **키 입력마다 needle 전부(≈ 3,000)를 도는 핫패스 루프**라 따로 둔다.
    ///
    /// ★ 칩 처리 코드(같은 구간 후보 세기·중복 거르기)와 한 루프에 섞어 두었더니 **빗나가는 입력이 8.0 → 9.2µs**로 느려졌다
    /// (최적화 결과가 바뀐다 — U7 ① 벤치 `SnippetCandidatesBenchmark` 실측, 2026-10-07). 루프 모양은 U7 전 그대로다.
    @inline(never)
    private func firstPhrase(_ reversed: [(character: Character, index: Int)]) -> Int? {
        var index = 0
        for needle in needles {
            if needle.characters.count <= reversed.count {
                var matched = true
                for offset in 0..<needle.characters.count
                where reversed[offset].character != needle.characters[needle.characters.count - 1 - offset] {
                    matched = false
                    break
                }
                if matched { return index }
            }
            index += 1
        }
        return nil
    }

    /// 분기 순서대로 훑어 **처음 맞은 것(칩)** 과, 칩과 **같은 구간**(같은 trigger)에 맞은 뒤 후보를 센다 — 최대 `limit`개(칩 포함).
    ///
    /// - 칩을 정하는 판정은 U7 전 `suggestion(forTail:)`과 같다: 문구(정규화 길이 내림차순 첫 매치) → 날짜 → 템플릿(소유 팩, 후퇴 금지) → 성경.
    /// - `visit`이 nil이면 **세기만** 한다(칩 하나만 만든다 — 키 입력 핫패스). nil이 아니면 칩부터 순서대로 후보 값을 만들어 넘긴다(길게 누를 때).
    /// - Returns: 칩과 후보 수(칩 포함). 아무것도 안 맞으면 nil
    private func walk(_ scan: Scan, limit: Int, visit: ((SnippetCandidate) -> Void)?) -> (SnippetSuggestion, Int)? {
        var chip: SnippetSuggestion?
        var count = 0
        /// 후보 하나 — 값은 `visit`이 있을 때만 만든다
        func add(_ suggestion: () -> SnippetSuggestion, _ origin: () -> SnippetOrigin) {
            count += 1
            visit?(SnippetCandidate(suggestion: suggestion(), origin: origin()))
        }
        func setChip(_ suggestion: SnippetSuggestion, _ origin: () -> SnippetOrigin) {
            chip = suggestion
            add({ suggestion }, origin)
        }

        // 문구 — `needles` 는 정규화 길이 내림차순이라 **첫 매치가 곧 최선**이다.
        if let index = firstPhrase(scan.reversed) {
            let first = needles[index]
            // 잘라낼 구간은 **마지막으로 맞은 글자**에서 꼬리 끝까지 —
            // 그 앞의 공백은 포함하지 않는다("보내줄게 우리집 주소"에서 앞 공백을 안 먹는다).
            let trigger = String(scan.characters[scan.reversed[first.characters.count - 1].index...])
            func phrase(_ needle: Needle) -> SnippetSuggestion {
                let entry = entries[needle.entryIndex]
                return SnippetSuggestion(trigger: trigger, title: entry.title, body: entry.body)
            }
            setChip(phrase(first)) { origins.entryOrigin(at: first.entryIndex) }
            // 같은 정규화 길이로 맞은 needle = 같은 구간(같은 역방향 풀이를 공유한다, 지시서 F2). 정렬돼 있어 연속이다.
            // 한 항목의 별칭 여럿이 같은 정규화로 겹치면 인접해 있다 — 항목 단위로 한 번만
            var lastEntry = first.entryIndex
            var shown = [first.entryIndex]
            var next = index + 1
            while count < limit, next < needles.count, needles[next].characters.count == first.characters.count {
                let needle = needles[next]
                next += 1
                guard needle.entryIndex != lastEntry, Self.matches(needle, scan.reversed) else { continue }
                lastEntry = needle.entryIndex
                // ★ **같은 출처의 같은 내용(제목·본문)은 한 번만** — 사용자에게 구별되지 않는 행이고 무엇을 골라도 문서가 같다.
                //   내장 팩 JSON에 띄어쓰기만 다른 옛 중복 항목이 23쌍 있다(「새해인사」/「새해 인사」, 제목·본문 동일 — 정규화 도입 전의
                //   별칭 표기, JSON은 고치지 않는다). 거르지 않으면 내장 인사말 칩마다 「+1」이 붙는다(실데이터 시험이 잠근다)
                guard !shown.contains(where: { isSameRow($0, needle.entryIndex) }) else { continue }
                shown.append(needle.entryIndex)
                add({ phrase(needle) }, { origins.entryOrigin(at: needle.entryIndex) })
            }
        }

        // 날짜·시간 팩 — **문구 다음, 성경 앞**(PDR `date-snippet-pack.md` 3-5절).
        // 사용자 문구가 먼저라 「날짜」로 끝나는 사용자 단축어가 이긴다(확정 동작 — 편집기가 경고한다).
        // 끝말(날짜·시간·시각)이 아니면 두어 번의 글자 비교로 끝난다. 값은 맞았을 때만 계산한다.
        if count < limit, let dates, let date = dates.suggestion(characters: scan.characters, reversed: scan.reversed) {
            if let chip {
                if date.trigger == chip.trigger { add({ date }, { .date }) }   // 뒤 분기는 같은 구간만
            } else {
                setChip(date) { .date }
            }
        }

        // 외부 팩 번호형 템플릿 — **날짜 다음, 성경 앞**(10-3). 정적 단축어가 같은 꼬리를 먼저 가져가면 그 패턴은 가려진다.
        // 소유 팩에 그 번호가 없으면 아무것도 없고 다른 판본으로 후퇴하지 않는다(10-4 5번). 지울 구간은 꼬리에서 잘라낸 원문이다.
        // 성경 참조와 겹치는 패턴은 가져오기에서 이미 거부됐다(10-2, 1~9,999 전체 검사).
        if count < limit, let templates {
            templates.forEachMatch(characters: scan.characters, reversed: scan.reversed) { raw in
                if let chip {
                    // 템플릿 적중은 모두 같은 구간이다 — 칩과 다르면 이 분기는 통째로 빠진다
                    guard raw.trigger == chip.trigger else { return false }
                    add({ raw.match.suggestion }, { origins.templateOrigin(sourceID: raw.sourceID) })
                } else {
                    setChip(raw.match.suggestion) { origins.templateOrigin(sourceID: raw.sourceID) }
                }
                return count < limit
            }
        }

        if count < limit, let bible = bibleSuggestion(scan.tail) {
            if let chip {
                if bible.trigger == chip.trigger { add({ bible }, { .bible }) }
            } else {
                setChip(bible) { .bible }
            }
        }
        return chip.map { ($0, count) }
    }

    /// 두 문구 항목이 목록에서 같은 행인가 — 제목·출처·본문이 모두 같다(짧은 것부터 비교)
    private func isSameRow(_ a: Int, _ b: Int) -> Bool {
        entries[a].title == entries[b].title
            && origins.entryOrigin(at: a) == origins.entryOrigin(at: b)
            && entries[a].body == entries[b].body
    }

    /// 성경 참조 칩 — 본문이 없거나 빈 절이면 nil(`body(for:in:)`)
    private func bibleSuggestion(_ tail: String) -> SnippetSuggestion? {
        guard let bible,
              let match = BibleReferenceParser.matchSuffix(of: tail),
              let text = Self.body(for: match, in: bible)
        else { return nil }
        // 머리말은 **사용자가 친 단축어 원문 그대로**다 (사용자 보고 2026-09-14).
        // `match.display`(정규 표기)를 쓰면 "창세기 1장 1절"을 친 사람도 `[창세기 1:1] `을
        // 받아 표기가 제멋대로 바뀐다. 칩 제목(`title`)은 정규 표기를 그대로 쓴다.
        let trigger = String(tail.suffix(match.matchedLength))
        return SnippetSuggestion(
            trigger: trigger,
            title: match.display, body: text,
            prefix: biblePrefix ? "[\(trigger)] " : nil)
    }

    /// 참조가 가리키는 본문을 만든다.
    ///
    /// 범위(`창 1:1~13`)는 절마다 단일 조회를 반복한다 — `BibleVerseRepository`를 그대로 두기
    /// 위한 선택이다. 인접 절은 인덱스에서도 붙어 있어 mmap 페이지가 이미 따뜻하고, 절 수는
    /// `BibleReferenceParser.maxRangeVerses`로 이미 막혀 있다 (PDR bible-verse-range).
    ///
    /// 삽입 형식: 절마다 `"번호 본문"`, 줄바꿈으로 잇는다. 단일 절은 기존 그대로 번호 없이 본문만.
    /// **한 절이라도 없으면 nil** — 장 끝을 넘긴 범위에 칩을 띄우지 않기 위한 fail-closed다
    /// (단일 절이 존재하지 않을 때 칩이 안 뜨는 기존 규칙과 같다).
    ///
    /// **본문이 빈 절도 "없는 절"과 똑같이 다룬다**(`nonEmpty`). 조회는 성공했는데 본문이
    /// 비어 있으면 사용자에게는 "칩을 눌렀는데 아무 것도 안 들어갔다"가 된다 —
    /// 2026-09-15 에 실제로 그랬다(정본이 "1-2" 로 묶어 인쇄한 합병절의 뒷절 6개가 원본
    /// 데이터에서 빈 문자열이었다: 사 30:2 · 사 48:2 · 렘 21:2 · 겔 24:5 · 행 15:26 · 롬 9:2).
    /// 데이터는 고쳤고 `tools/convert_bible.py` 가 재발을 막지만, **매처도 데이터를 믿지 않는다.**
    private static func body(
        for match: BibleReferenceParser.Match, in bible: any BibleVerseRepository
    ) -> String? {
        guard match.isRange else {
            return nonEmpty(bible.text(book: match.book, chapter: match.chapter, verse: match.verse))
        }
        var lines: [String] = []
        lines.reserveCapacity(match.verses.count)
        for verse in match.verses {
            guard let text = nonEmpty(
                bible.text(book: match.book, chapter: match.chapter, verse: verse))
            else { return nil }
            lines.append("\(verse) \(text)")
        }
        return lines.joined(separator: "\n")
    }

    /// 공백만 남는 본문은 없는 것으로 본다 — 눈에 비어 보이는 것이 사용자에게는 같은 버그다.
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return text
    }
}
