import TadakDomain

// U7 — 채움글 칩을 길게 눌러 **같은 입력에 걸린 다른 후보**를 고른다
// (PDR `docs/design-reviews/external-snippet-packs.md` 10-6 · AC-37~46, 지시서 `external-snippet-packs-u7-plan.md`).
//
// 이 파일은 계산·판정·문구만 든다(KeyboardCore — `swift test`가 닿는다). 칩 제스처·패널 그림은 KeyboardUI,
// 열고 닫는 배선은 조립 지점(`KeyboardViewController`)이다.
//
// ★ 출처 이름(팩 이름)·후보 본문·개수는 **사용자 입력 유래**다 — 화면 표시에만 쓰고 로그·분석·크래시 키에 넣지 않는다(10-6 ⑧, 보안 규칙).

/// 후보가 어디서 왔나 — 목록 행에 출처로 보인다(10-6 ⑥). 칩에는 붙이지 않는다(10-4 4번).
public enum SnippetOrigin: Hashable, Sendable {
    /// 「내 채움글」
    case user
    /// 외부 팩 — 사용자가 붙인 팩 이름
    case pack(name: String)
    /// 내장 문구 팩 — `SnippetPack.anthem`·`SnippetPack.greetings`(빈 id = 어느 내장인지 모르는 옛 조립 경로)
    case builtIn(id: String)
    /// 날짜·시간 계산 팩
    case date
    /// 성경 참조
    case bible
}

/// 길게 누르기 목록의 행 하나 — 넣을 값과 출처.
public struct SnippetCandidate: Equatable, Sendable {
    public let suggestion: SnippetSuggestion
    public let origin: SnippetOrigin

    public init(suggestion: SnippetSuggestion, origin: SnippetOrigin) {
        self.suggestion = suggestion
        self.origin = origin
    }
}

/// 문구 항목·템플릿 팩의 출처 표 — `SnippetSourceComposer`가 조립하면서 만든다.
///
/// 항목마다 1바이트(지시서 초안 — 80,000항목이면 80KB)가 아니라 **조립한 줄(구간)마다 하나**를 든다. `compose`가 줄 단위로
/// `entries += …`를 하므로 같은 줄의 항목은 붙어 있다 — 구간 수는 「내 채움글」 1 + 외부 팩 ≤ 16 + 내장 ≤ 2라 항목 수와 무관하다.
/// 조회는 칩이 맞았을 때 후보 ≤ 8개에만 일어난다(키 입력 핫패스 밖).
public struct SnippetOrigins: Equatable, Sendable {

    private struct Span: Equatable, Sendable {
        /// 이 구간의 끝(배타) — 앞 구간들의 항목 수 누계
        let end: Int
        let origin: SnippetOrigin
    }

    private var spans: [Span] = []
    private var templates: [String: SnippetOrigin] = [:]

    public init() {}

    /// 다음 `count`개 항목의 출처 — `compose`가 `entries`에 붙이는 순서 그대로 부른다. 0개면 구간을 만들지 않는다.
    mutating func appendEntries(count: Int, origin: SnippetOrigin) {
        guard count > 0 else { return }
        spans.append(Span(end: (spans.last?.end ?? 0) + count, origin: origin))
    }

    /// 번호형 팩(`PackTemplateMatcher.Source.id`)의 출처
    mutating func setTemplate(sourceID: String, origin: SnippetOrigin) {
        templates[sourceID] = origin
    }

    /// 시험용 — 구간 수
    var spanCount: Int { spans.count }

    /// `entries[index]`의 출처. 표에 없으면(출처 없이 만든 매처 — 기존 호출부·시험) 「내 채움글」로 본다.
    public func entryOrigin(at index: Int) -> SnippetOrigin {
        // 구간 ≤ 19개 — 선형으로 충분하다
        for span in spans where index < span.end { return index >= 0 ? span.origin : .user }
        return .user
    }

    /// 템플릿 팩의 출처. 표에 없으면 이름 없는 외부 팩.
    public func templateOrigin(sourceID: String) -> SnippetOrigin {
        templates[sourceID] ?? .pack(name: "")
    }
}

/// ✕를 눌렀을 때 할 일 — 조립 지점(`handleDismissSuggestions`)이 이 값대로만 움직인다.
public enum SnippetDismissEffect: Equatable, Sendable {
    /// 후보 패널**만** 닫는다 — 칩·`dismissedSnippetTail`·추천단어 억제·붙여넣기 소비를 건드리지 않는다(10-6 ⑤ · AC-43)
    case closeCandidatesPanel
    /// 지금 규칙 그대로 보이는 후보를 내린다 — 채움글 칩이 **보였으면** 그 꼬리를 숨긴다(`dismissedSnippetTail`, nil이면 그대로 둔다)
    case dismissSuggestions(hideSnippetTail: String?)
}

/// U7 판정 — 조립 지점의 조건식을 여기로 모아 `swift test`로 잠근다(`PasteChipGate`·`SnippetChipGate` 선례).
///
/// **같은 식 하나:** 무장(450ms)·패널 유지·행 탭 직전이 모두 「꼬리가 아직 그 trigger로 끝나는가」(`isStillValid`)를 쓴다.
/// 최종 방어는 여전히 `InputController.insertSnippet`의 꼬리 정합이다 — 이 게이트는 그 앞에서 **화면**을 맞추는 일이다.
public enum SnippetCandidateGate {

    /// 목록 상한(10-6 ① · AC-46). 칩 「+n」은 최대 이 값 − 1
    public static let limit = 8

    /// 패널을 열 수 있나 — 후보가 2개 이상일 때만(1개면 길게 눌러도 아무 일 없음, AC-42)
    public static func canOpen(candidateCount: Int) -> Bool {
        candidateCount >= 2
    }

    /// 꼬리가 아직 그 후보의 trigger로 끝나는가 — `insertSnippet`의 정합 검사와 같은 식(빈 trigger는 언제나 무효)
    public static func isStillValid(trigger: String, tail: String) -> Bool {
        !trigger.isEmpty && tail.hasSuffix(trigger)
    }

    /// 450ms에 무장해도 되나 — 다른 후보가 있고(AC-42) 칩이 **지금도** 유효할 때만. 퇴장 트랜지션(0.28초) 중 칩은 히트 테스트를
    /// 받으므로 450ms 뒤엔 칩이 이미 사라졌을 수 있다(10-6 ⑤) — 그때는 무장·표시·진동 모두 없다
    public static func canArm(chip: SnippetSuggestion?, tail: String) -> Bool {
        guard let chip, chip.alternativeCount > 0 else { return false }
        return isStillValid(trigger: chip.trigger, tail: tail)
    }

    /// **누른 칩**으로 무장·열기를 해도 되나(U7 ③ — 조립 지점의 `onSnippetArm`·`onSnippetCandidatesOpen`이 같은 식을 쓴다).
    ///
    /// `pressed`는 누르기 시작한 때의 칩 값이다 — 퇴장 트랜지션(0.28초) 중이면 이미 사라진 옛 칩일 수 있다. 그래서 둘을 가른다:
    /// **구간은 누른 칩**(지금 칩이 같은 trigger여야 한다), **개수는 지금 칩**(누르는 사이 「+n」이 바뀌었을 수 있다).
    /// 열기도 이 식을 **다시** 본다 — VoiceOver 「다른 후보 보기」는 450ms 무장을 거치지 않는다
    public static func canArm(pressed: SnippetSuggestion, current: SnippetSuggestion?, tail: String) -> Bool {
        keepsPanelOpen(panelTrigger: pressed.trigger, chip: current, tail: tail) && canArm(chip: current, tail: tail)
    }

    /// 후보 행 탭을 받을까 — 패널이 열려 있고(`panelTrigger` ≠ nil) 그 행이 **지금 목록**의 것이며 꼬리가 아직 그 trigger로 끝날 때만.
    /// 더블탭의 둘째 탭은 첫 탭이 패널을 닫아(trigger nil·목록 빔) 여기서 걸린다(AC-41). 최종 방어는 `insertSnippet`의 꼬리 정합이다.
    /// 칩 탭(`viewState.snippetSuggestion == 누른 칩`)과 달리 둘째 이후 행은 칩과 같은 값이 아니므로 패널 상태로 판정한다
    public static func acceptsRowTap(
        _ candidate: SnippetCandidate, panelTrigger: String?, panelCandidates: [SnippetCandidate], tail: String
    ) -> Bool {
        guard let panelTrigger, candidate.suggestion.trigger == panelTrigger, panelCandidates.contains(candidate) else {
            return false
        }
        return isStillValid(trigger: panelTrigger, tail: tail)
    }

    /// 패널이 열린 채로 둘까 — 지금 칩이 패널을 연 그 구간이고 꼬리도 그대로일 때만. 아니면 즉시 닫는다(10-6 ③ · AC-41).
    /// 호스트 메아리 sync로 꼬리가 흔들려도 **trigger로 끝나는 한** 닫지 않는다(지시서 R5)
    public static func keepsPanelOpen(panelTrigger: String, chip: SnippetSuggestion?, tail: String) -> Bool {
        guard let chip, chip.trigger == panelTrigger else { return false }
        return isStillValid(trigger: panelTrigger, tail: tail)
    }

    /// ✕ — 패널이 열려 있으면 패널만 닫는다(AC-43). 닫혀 있으면 지금 규칙: 붙여넣기 칩이 있으면 채움글 칩은 그려지지 않았으므로
    /// 숨기지 않는다(D18·D19), 채움글 칩이 보였으면 그 꼬리를 숨긴다
    public static func dismissEffect(
        isCandidatesPanelOpen: Bool, hasPasteChip: Bool, hasSnippetChip: Bool, tail: String
    ) -> SnippetDismissEffect {
        if isCandidatesPanelOpen { return .closeCandidatesPanel }
        return .dismissSuggestions(hideSnippetTail: !hasPasteChip && hasSnippetChip ? tail : nil)
    }
}

/// U7 문구·VoiceOver 라벨 표 — **한 곳**(10-6 ⑦, `KeyCapAccessibility` 선례). 시험이 고정한다.
public enum SnippetCandidateText {

    /// 칩 사용자 지정 동작(로터 「동작」) — 즉시 목록을 연다
    public static let chipActionName = "다른 후보 보기"

    /// 칩 VoiceOver 힌트 — 다른 후보가 없으면 nil(라벨은 지금 그대로)
    public static func chipHint(alternativeCount: Int) -> String? {
        alternativeCount > 0 ? "다른 후보 \(alternativeCount)개" : nil
    }

    /// 칩 제목 뒤에 이어 붙는 「+n」 — 다른 후보가 없으면 **빈 글자**(자리 0, AC-42 · v3.2). VoiceOver는 이 글자를 읽지 않는다(힌트가 같은 뜻)
    public static func alternativeBadge(alternativeCount: Int) -> String {
        alternativeCount > 0 ? "+\(alternativeCount)" : ""
    }

    /// 패널 머리줄(R32 (다)) — 「「새해인사」 후보 3개」. trigger는 사용자가 친 꼬리 원문이다
    public static func panelHeader(trigger: String, count: Int) -> String {
        "「\(trigger)」 후보 \(count)개"
    }

    /// 출처 글자 — 내장 팩 이름은 설정 앱(`SnippetPackInfo`)과 **같은 상수**(`SnippetPackName`, TadakDomain)다.
    /// 성경은 짧은 이름 「성경」(설정의 「성경 (개역한글)」과 일부러 다르다)
    public static func originName(_ origin: SnippetOrigin) -> String {
        switch origin {
        case .user: "내 채움글"
        case .pack(let name): name.isEmpty ? "외부 팩" : name
        case .builtIn(let id):
            switch id {
            case SnippetPack.anthem: SnippetPackName.anthem
            case SnippetPack.greetings: SnippetPackName.greetings
            default: "기본 채움글"
            }
        case .date: SnippetPackName.date
        case .bible: SnippetPackName.bibleShort
        }
    }

    /// 목록 행 라벨 「채움글 <제목>, <출처>, 붙여넣기」(10-6 ⑦). 날짜 후보는 칩 라벨과 같은 규칙으로 **값**을 함께 읽는다
    /// (`SnippetSuggestion.accessibilityLabel` — 한글형 `spokenValue`, 가운뎃점은 쉼표로)
    public static func rowLabel(_ candidate: SnippetCandidate) -> String {
        let suggestion = candidate.suggestion
        var parts: [String]
        if let spokenValue = suggestion.spokenValue {
            parts = ["채움글 " + suggestion.title.replacingOccurrences(of: " · ", with: ", "), spokenValue]
        } else {
            parts = ["채움글 " + suggestion.title]
        }
        parts.append(originName(candidate.origin))
        parts.append("붙여넣기")
        return parts.joined(separator: ", ")
    }
}
