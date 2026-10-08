import Foundation

/// 예산이 재는 네 값(PDR `external-snippet-packs.md` 9-6) — 앱이 계산하지만 **키보드는 믿지 않고 다시 센다**(9-4).
public struct PackStats: Codable, Equatable, Sendable {
    /// 매 키 입력 선형 루프의 needle 수 — 문구는 정규화 단축어 수, 번호형은 **패턴 수만**(항목 수가 아니다)
    public var needleCount: Int
    /// needle의 정규화 Character 합
    public var needleChars: Int
    /// 직렬화 Data 길이(JSON, 키 정렬·공백 없음) — 제목·단축어·패턴·본문·이름·권리·키·escape 포함
    public var bytes: Int
    /// entries + items
    public var items: Int

    public init(needleCount: Int, needleChars: Int, bytes: Int, items: Int) {
        self.needleCount = needleCount
        self.needleChars = needleChars
        self.bytes = bytes
        self.items = items
    }

    public static let zero = PackStats(needleCount: 0, needleChars: 0, bytes: 0, items: 0)

    public static func + (lhs: PackStats, rhs: PackStats) -> PackStats {
        PackStats(needleCount: lhs.needleCount + rhs.needleCount, needleChars: lhs.needleChars + rhs.needleChars,
                  bytes: lhs.bytes + rhs.bytes, items: lhs.items + rhs.items)
    }

    /// 문구 목록(내 채움글·켜진 내장·문구형 팩) — needle은 `SnippetMatcher`와 같은 규칙(정규화 뒤 빈 단축어 제외).
    /// 바이트는 배열을 통째로 인코드하지 않고 **항목마다 한 번** 인코드해 더한다(9-3 항등식 — 값은 같다, R23)
    public static func of(entries: [SnippetEntry]) -> PackStats {
        entries.indices.reduce(emptyArray) { $0 + of(entry: entries[$1], at: $1) }
    }

    /// 빈 배열 `[]` — 항목별 누적의 시작값
    static let emptyArray = PackStats(needleCount: 0, needleChars: 0, bytes: 2, items: 0)

    /// 배열의 `index`번째 항목 하나의 몫 — 직렬화는 **이 한 번뿐**이고, 둘째부터는 앞 쉼표 1바이트를 함께 센다.
    /// 배열 길이 = `2 + Σ항목 + (n−1)`(9-3)이라 `emptyArray`에서 앞부터 더하면 통째로 인코드한 길이와 같다(`UserSnippetUsageTests`가 고정)
    static func of(entry: SnippetEntry, at index: Int) -> PackStats {
        let needles = needleCharacters(of: [entry])
        return PackStats(needleCount: needles.count, needleChars: needles.reduce(0, +),
                         bytes: serializedBytes(of: entry) + (index > 0 ? 1 : 0), items: 1)
    }

    /// 외부 팩 하나 — 문구형은 항목의 단축어, 번호형은 패턴(접두+접미 정규화 길이)
    public static func of(pack: ExternalPack) -> PackStats {
        var needles = needleCharacters(of: pack.entries)
        if let template = pack.template {
            needles += template.patterns.map(\.literalLength)
        }
        return PackStats(needleCount: needles.count, needleChars: needles.reduce(0, +),
                         bytes: Self.serializedBytes(of: pack), items: pack.entries.count + (pack.template?.items.count ?? 0))
    }

    /// 항목 직렬화 바이트의 **하한** — 문자열 필드(단축어·제목·본문)의 원시 UTF-8 바이트 합(K2). JSON은 이 글자들을 UTF-8 그대로 쓰고
    /// 키·따옴표·쉼표·escape(`\"`·`\/`·`\n`·`\u0000`)는 **더하기만** 하므로 `serializedBytes(of: entry)` 이상일 수 없다(시험이 고정).
    /// 인코드하지 않는다 — 네이티브 문자열의 `utf8.count`는 길이를 다시 세지 않는다
    static func rawUTF8Bytes(of entry: SnippetEntry) -> Int {
        entry.triggers.reduce(entry.title.utf8.count + entry.body.utf8.count) { $0 + $1.utf8.count }
    }

    private static func needleCharacters(of entries: [SnippetEntry]) -> [Int] {
        entries.flatMap { entry in
            entry.triggers.map { SnippetEntry.normalizedTrigger($0).count }.filter { $0 > 0 }
        }
    }

    /// 결정적 직렬화 — 키 정렬, 공백 없음. 인코딩 실패(이 타입들에서는 일어나지 않는다)는 0으로 둔다
    static func serializedBytes<Value: Encodable>(of value: Value) -> Int {
        (try? encoder.encode(value).count) ?? 0
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

public enum PackBudgetDimension: String, CaseIterable, Sendable {
    case needleCount, needleChars, bytes, items
    /// 9-5 피크 모델 — 상한이 주어졌을 때만 판정한다(P-2 전 nil)
    case peak
}

/// 활성 집합 예산 — **앱과 키보드가 같은 함수**를 부른다(앱 표시 == 키보드 동작, AC-8 전제).
///
/// ## 결정적 규칙 (prefix rule, v2 8-2 · v3 9-3)
///
/// baseline(내 채움글 + 켜진 내장)이 **먼저 예산을 차지**하고 이 함수로 제외되지 않는다. 남은 예산에 외부 팩을
/// **사용자가 정한 순서대로** 넣다가 **처음으로 넘는 팩부터 그 뒤 전부**를 뺀다 — 배낭처럼 건너뛰며 담지 않는다.
/// baseline 자체가 넘으면(옛 저장본) 외부 팩은 전부 빠지고 **아무것도 지우지 않는다**(9-3).
public enum ActivePackBudget {

    public struct Candidate: Equatable, Sendable {
        public var id: String
        /// 꺼진 팩은 세지도 포함·제외 목록에 넣지도 않는다
        public var isEnabled: Bool
        public var stats: PackStats

        public init(id: String, isEnabled: Bool, stats: PackStats) {
            self.id = id
            self.isEnabled = isEnabled
            self.stats = stats
        }
    }

    public enum ExclusionReason: Equatable, Sendable {
        /// 이 팩을 넣으면 넘는 항목들
        case overflow([PackBudgetDimension])
        /// 앞 팩이 이미 넘어 그 뒤라서 빠졌다(prefix rule)
        case afterEarlierOverflow
        /// baseline이 이미 넘어 외부 팩 전부가 빠졌다
        case baselineOverflow
        /// 앱 저장본에서 이 팩의 변환본을 읽을 수 없어 판정에서 뺐다(검증 C5) — 예산과 무관, 이 함수는 내지 않는다.
        /// `PackStore`가 판정 단계에서 붙인다(snapshot도 이 판정대로 — 앱 판정 == 키보드, AC-8)
        case unavailable
    }

    public struct Exclusion: Equatable, Sendable {
        public var id: String
        public var reason: ExclusionReason

        public init(id: String, reason: ExclusionReason) {
            self.id = id
            self.reason = reason
        }
    }

    public struct Evaluation: Equatable, Sendable {
        /// 포함된 팩 id — 사용자 순서 그대로
        public var included: [String]
        public var excluded: [Exclusion]
        /// baseline이 넘는 항목(비면 정상)
        public var baselineOverflow: [PackBudgetDimension]
        /// baseline + 포함된 팩
        public var usage: PackStats
        /// 9-5 피크 추정 — `2 × needleChars × Character stride + 가장 큰 포함 팩의 직렬화 바이트`
        public var peakEstimateBytes: Int

        public func isIncluded(_ id: String) -> Bool { included.contains(id) }
    }

    /// 9-5 — 옛 매처와 새 매처가 동시에 살아 있는 동안의 needle 배열 원소(16B/Character) + 한 팩 디코드 과도분.
    /// **상수는 P-2로 보정한다** — 문자열 저장·헤더·정렬·DTO는 아직 모델에 없다(9-6 표의 각주와 같다).
    public static func peakEstimateBytes(needleChars: Int, largestPackBytes: Int) -> Int {
        2 * needleChars * MemoryLayout<Character>.stride + largestPackBytes
    }

    public static func evaluate(
        baseline: PackStats, packs: [Candidate], limits: PackBudgetLimits = .candidate
    ) -> Evaluation {
        let baselineOverflow = overflowing(baseline, largestPackBytes: 0, limits: limits)
        var usage = baseline
        var largest = 0
        var included: [String] = []
        var excluded: [Exclusion] = []
        var overflowed = !baselineOverflow.isEmpty
        for pack in packs where pack.isEnabled {
            guard !overflowed else {
                excluded.append(Exclusion(id: pack.id, reason: baselineOverflow.isEmpty ? .afterEarlierOverflow : .baselineOverflow))
                continue
            }
            let next = usage + pack.stats
            let nextLargest = max(largest, pack.stats.bytes)
            let dimensions = overflowing(next, largestPackBytes: nextLargest, limits: limits)
            if dimensions.isEmpty {
                usage = next
                largest = nextLargest
                included.append(pack.id)
            } else {
                overflowed = true
                excluded.append(Exclusion(id: pack.id, reason: .overflow(dimensions)))
            }
        }
        return Evaluation(included: included, excluded: excluded, baselineOverflow: baselineOverflow, usage: usage,
                          peakEstimateBytes: peakEstimateBytes(needleChars: usage.needleChars, largestPackBytes: largest))
    }

    /// 내 채움글의 예산 몫 — `userSnippetUsage`의 결과
    public struct UserSnippetUsage: Equatable, Sendable {
        /// 내 채움글 **전체**의 stats — `PackStats.of(entries:)`와 같다
        public var stats: PackStats
        /// 키보드가 싣는 개수(9-3) — `내장 + 앞 k개`가 넘지 않는 가장 큰 k. 넘지 않으면 전부
        public var loadableCount: Int

        public init(stats: PackStats, loadableCount: Int) {
            self.stats = stats
            self.loadableCount = loadableCount
        }
    }

    /// 9-3 — 내 채움글을 **한 번 훑어** 전체 stats와 싣는 개수를 함께 낸다. 앱(`PackStore` 판정 입력·「일부만 사용 중」 안내)이 쓴다.
    /// 키보드(`PackSnapshotLoader`)는 넘으면 멈추는 `userSnippetLoad`를 쓴다(K2) — 싣는 개수는 이 함수와 같다(AC-8, 시험이 고정).
    /// 저장 순서대로 한도까지만 싣고 나머지는 지우지 않는다. 내장은 번들 고정량이라 먼저 차감하고 항상 싣는다.
    ///
    /// R23(P-2 6-4) — 예전에는 기준 바이트를 내려고 배열 전체를 다시 인코드했고(넘으면 항목마다 두 번 더), 재구성 피크가 내 채움글
    /// 크기의 약 2배만큼 늘었다. 이제 항목마다 **한 번만** 인코드해 앞에서부터 더한다(항등식 `2 + Σ항목 + (n−1)`). 처음 넘는 자리가
    /// 싣는 개수이고, 넘은 뒤에도 끝까지 더한다 — 넘은 항목(`baselineOverflow`)과 R21 비용 비교가 **전체** 값을 보기 때문이다.
    /// 남은 항목도 하나씩 인코드하고 바로 놓으므로 한꺼번에 잡히는 직렬화 버퍼는 가장 큰 항목 하나다.
    public static func userSnippetUsage(
        _ entries: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits = .candidate
    ) -> UserSnippetUsage {
        var stats = PackStats.emptyArray
        var loadable: Int?
        for (index, entry) in entries.enumerated() {
            stats = stats + PackStats.of(entry: entry, at: index)
            // 네 값과 피크 모두 항목이 늘면 줄지 않으므로 처음 넘은 자리 뒤는 전부 넘는다 — 첫 자리만 기록한다
            if loadable == nil, !overflowing(builtIn + stats, largestPackBytes: 0, limits: limits).isEmpty {
                loadable = index
            }
        }
        return UserSnippetUsage(stats: stats, loadableCount: loadable ?? entries.count)
    }

    /// 키보드 로더의 내 채움글 몫 — `userSnippetLoad`의 결과(K2)
    public struct UserSnippetLoad: Equatable, Sendable {
        public enum Baseline: Equatable, Sendable {
            /// 내 채움글 + 내장이 한도 안 — 내 채움글 **전체** stats(`userSnippetUsage(...).stats`와 같다)
            case fits(PackStats)
            /// 넘는다 — 멈춘 자리에서 **확인된** 넘는 항목(비지 않음). 끝까지 세지 않으므로 전체를 센 `baselineOverflow`의
            /// 부분집합(하한)이다. 키보드는 넘었는지만 본다 — 정확한 넘는 항목·비용은 앱(`userSnippetUsage`)이 센다
            case overflow([PackBudgetDimension])
        }

        /// 싣는 개수 — `userSnippetUsage(...).loadableCount`와 **같다**(AC-8)
        public var loadableCount: Int
        public var baseline: Baseline

        public init(loadableCount: Int, baseline: Baseline) {
            self.loadableCount = loadableCount
            self.baseline = baseline
        }

        /// 넘는 항목 — 한도 안이면 빈 배열
        public var overflowDimensions: [PackBudgetDimension] {
            if case .overflow(let dimensions) = baseline { return dimensions }
            return []
        }
    }

    /// K2(codex 반론 v1.3.0 #2) — **키보드 전용** 내 채움글 몫. 싣는 개수는 `userSnippetUsage`와 같고(AC-8), 넘는 것이 확정되면
    /// **그 자리에서 멈춘다.** 내 채움글 본문에는 읽기 상한이 없어 10MB 한 항목도 저장될 수 있는데, `userSnippetUsage`는 그 항목을
    /// 통째로 인코드한 **뒤** 넘는 것을 알았고 넘은 뒤에도 끝까지 인코드했다.
    ///
    /// 1. 항목마다 **인코드 전에** 하한(`rawUTF8Bytes` + 앞 쉼표, 개수 +1)을 더해 본다 — 하한이 넘으면 정확 계산도 이 자리에서 넘으므로
    ///    인코드하지 않고 「초과」로 끝낸다. 하한에 없는 단축어 수·글자 수는 인코드하며 센다(단축어는 설정이 40자로 막는다).
    /// 2. 인코드한 누적이 넘어도 그 자리에서 끝낸다 — 뒤 항목은 인코드하지 않는다.
    ///
    /// 앱(`PackStore`)은 이 함수를 쓰지 않는다 — 커밋 판정(R21)이 넘은 뒤 **전체** 비용을 비교하므로 정확 통계(`userSnippetUsage`)가 필요하다.
    public static func userSnippetLoad(
        _ entries: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits = .candidate
    ) -> UserSnippetLoad {
        userSnippetLoad(entries, builtIn: builtIn, limits: limits, entryStats: PackStats.of(entry:at:))
    }

    /// 시험용 — `entryStats`(항목 하나의 몫 = 인코드 1회)를 바꿔 끼워 **몇 항목을 인코드했는지** 센다
    static func userSnippetLoad(
        _ entries: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits,
        entryStats: (SnippetEntry, Int) -> PackStats
    ) -> UserSnippetLoad {
        var stats = PackStats.emptyArray
        for (index, entry) in entries.enumerated() {
            let comma = index > 0 ? 1 : 0
            let floor = stats + PackStats(needleCount: 0, needleChars: 0, bytes: PackStats.rawUTF8Bytes(of: entry) + comma, items: 1)
            let floorOverflow = overflowing(builtIn + floor, largestPackBytes: 0, limits: limits)
            guard floorOverflow.isEmpty else {
                return UserSnippetLoad(loadableCount: index, baseline: .overflow(floorOverflow))
            }
            stats = stats + entryStats(entry, index)
            let overflow = overflowing(builtIn + stats, largestPackBytes: 0, limits: limits)
            guard overflow.isEmpty else {
                return UserSnippetLoad(loadableCount: index, baseline: .overflow(overflow))
            }
        }
        // 항목이 없으면 내장 + 「[]」만으로 넘을 수 있다(있으면 위에서 이미 봤다)
        let overflow = overflowing(builtIn + stats, largestPackBytes: 0, limits: limits)
        return UserSnippetLoad(loadableCount: entries.count, baseline: overflow.isEmpty ? .fits(stats) : .overflow(overflow))
    }

    static func overflowing(_ usage: PackStats, largestPackBytes: Int, limits: PackBudgetLimits) -> [PackBudgetDimension] {
        var dimensions: [PackBudgetDimension] = []
        if usage.needleCount > limits.needleCount { dimensions.append(.needleCount) }
        if usage.needleChars > limits.needleChars { dimensions.append(.needleChars) }
        if usage.bytes > limits.bytes { dimensions.append(.bytes) }
        if usage.items > limits.items { dimensions.append(.items) }
        if let peak = limits.peakBytes,
           peakEstimateBytes(needleChars: usage.needleChars, largestPackBytes: largestPackBytes) > peak {
            dimensions.append(.peak)
        }
        return dimensions
    }
}

/// 커밋 게이트 입력 — 내 채움글 + 켜진 내장(baseline) + 사용자 순서의 외부 팩
public struct PackBudgetInput: Equatable, Sendable {
    public var userSnippets: PackStats
    public var builtIn: PackStats
    public var packs: [ActivePackBudget.Candidate]

    public init(userSnippets: PackStats, builtIn: PackStats, packs: [ActivePackBudget.Candidate]) {
        self.userSnippets = userSnippets
        self.builtIn = builtIn
        self.packs = packs
    }

    public var baseline: PackStats { userSnippets + builtIn }
}

/// 커밋 게이트의 **순수 판정**(9-1 경로표·9-3) — 직렬 큐·revision 재검사·snapshot 쓰기는 `PackStore`(1-b)가 한다.
///
/// 큐는 **최종 후보**(폼이 확정한 이름·틀·별칭·권리로 컴파일한 팩의 stats, 9-2 2단계)로 `current`·`proposed`를 만들고
/// 이 함수를 커밋 직전에 다시 부른다(5단계 — revision이 바뀌었으면 다시 구성해서 다시).
public enum PackCommitGate {

    public enum Change: Equatable, Sendable {
        /// 가져오기 최종 확정 — 새 팩은 켠 채 맨 아래(U2)
        case importPack(id: String)
        /// 「꺼 둔 채로 가져오기」(U2) — 꺼진 팩은 예산에 들지 않아 **팩 수 상한만** 본다(v3.6 ⑭).
        /// `proposed`에서 새 팩은 **꺼진 채 맨 아래**여야 한다 — 아니면 `invalidDisabledImport`(재검증 N2)
        case importDisabledPack(id: String)
        case enablePack(id: String)
        /// 같은 이름 팩 교체(위치·켬/끔 유지) — 켜져 있을 때
        case replaceActivePack(id: String)
        /// 꺼진 팩 교체 — 활성 예산을 보지 않는다(파일·팩 개별 cap만, 가져오기 단계가 본다)
        case replaceInactivePack(id: String)
        /// 내장 팩 켜기 — 설정의 두 토글 경로가 이 하나를 쓴다
        case enableBuiltIn
        case disableBuiltIn
        /// 내 문구 추가·수정
        case saveUserSnippets
        case deleteUserSnippets
        case disablePack(id: String)
        case deletePack(id: String)
        case reorderPacks
    }

    public enum Rejection: Equatable, Sendable {
        /// 대상 팩이 예산 밖이다 — 화면은 「꺼 둔 채로 가져오기」를 줄 수 있다(U2)
        case packExcluded(id: String, dimensions: [PackBudgetDimension])
        /// 지금 포함된 팩이 밀려난다(R15) — 「먼저 다른 팩을 끄거나 순서를 바꾸세요」
        case displacesPacks([String])
        /// 내 문구 + 켜진 내장이 하드 한도를 넘는 채로 넘은 항목이 늘었다(R14·R21) — 「문구가 너무 많아요」. 담는 것은 넘는 항목 전부
        case baselineOverLimit([PackBudgetDimension])
        /// 외부 팩 수가 `PackLimits.externalPacks`를 넘는다(꺼진 팩 포함, v3.6 ⑭)
        case tooManyPacks
        /// 「꺼 둔 채로 가져오기」의 전제 — 새 팩이 **꺼진 채 목록 맨 아래**, 나머지는 현재 저장본 그대로 — 를 어겼다. 예산을 보지 않는 경로라 어기면 기존 팩을
        /// 밀어내고도 받게 된다(재검증 N2). 부르는 쪽(1-b)의 계약 위반이라 화면 문구 대상이 아니다
        case invalidDisabledImport(id: String)
    }

    public enum Decision: Equatable, Sendable {
        /// 받는다 — `newlyExcluded`는 이번 변경으로 snapshot에서 쉬게 될 팩(경고용, R14)
        case accept(ActivePackBudget.Evaluation, newlyExcluded: [String])
        case reject(Rejection)
    }

    public static func judge(
        _ change: Change, current: PackBudgetInput, proposed: PackBudgetInput, limits: PackBudgetLimits = .candidate
    ) -> Decision {
        let before = ActivePackBudget.evaluate(baseline: current.baseline, packs: current.packs, limits: limits)
        let after = ActivePackBudget.evaluate(baseline: proposed.baseline, packs: proposed.packs, limits: limits)
        let excludedAfter = Set(after.excluded.map(\.id))
        let newlyExcluded = before.included.filter { excludedAfter.contains($0) }

        switch change {
        case .importPack(let id):
            guard proposed.packs.count <= PackLimits.externalPacks else { return .reject(.tooManyPacks) }
            return judgeActivation(of: id, after: after, newlyExcluded: newlyExcluded)
        case .enablePack(let id), .replaceActivePack(let id):
            return judgeActivation(of: id, after: after, newlyExcluded: newlyExcluded)
        case .importDisabledPack(let id):
            // 전제 셋: 새 팩이 **꺼진 채 맨 아래**이고, 그 팩을 뺀 나머지가 **현재 저장본 그대로**(v3.9 N2 잔여 — 앞에 같은 id가
            // 또 있거나 다른 팩 상태가 바뀐 제안을 받지 않는다). 예산을 보지 않는 경로라 어기면 기존 팩을 밀어내고도 받게 된다
            guard let last = proposed.packs.last, last.id == id, !last.isEnabled,
                  Array(proposed.packs.dropLast()) == current.packs else {
                return .reject(.invalidDisabledImport(id: id))
            }
            guard proposed.packs.count <= PackLimits.externalPacks else { return .reject(.tooManyPacks) }
            return .accept(after, newlyExcluded: newlyExcluded)
        case .enableBuiltIn:
            if let rejection = baselineRejection(current: current.baseline, proposed: proposed.baseline, after: after) {
                return .reject(rejection)
            }
            guard newlyExcluded.isEmpty else { return .reject(.displacesPacks(newlyExcluded)) }
            return .accept(after, newlyExcluded: [])
        case .saveUserSnippets:
            // R14 — 외부 팩 때문에 막지 않는다(밀린 팩은 경고). baseline 판정은 내장 켜기와 같다(R21)
            if let rejection = baselineRejection(current: current.baseline, proposed: proposed.baseline, after: after) {
                return .reject(rejection)
            }
            return .accept(after, newlyExcluded: newlyExcluded)
        case .replaceInactivePack, .disableBuiltIn, .deleteUserSnippets, .disablePack, .deletePack, .reorderPacks:
            // 한도 감소 방향(또는 활성 예산 무관) — 거부 없음. 포함 목록을 다시 계산해 돌려준다(9-1)
            return .accept(after, newlyExcluded: newlyExcluded)
        }
    }

    /// 외부 팩을 켜는 쪽(가져오기·켜기·활성 교체) — 자신이 빠지면 거부, 기존 포함 팩이 밀리면 거부(R15)
    private static func judgeActivation(of id: String, after: ActivePackBudget.Evaluation, newlyExcluded: [String]) -> Decision {
        guard after.isIncluded(id) else {
            return .reject(.packExcluded(id: id, dimensions: dimensions(of: id, in: after)))
        }
        guard newlyExcluded.isEmpty else { return .reject(.displacesPacks(newlyExcluded)) }
        return .accept(after, newlyExcluded: [])
    }

    /// R21(⑬) — 변경 뒤 baseline이 **넘는 항목 중 하나라도 변경 전보다 늘었으면** 거부한다. 줄이거나 같은 변경은 넘은 채로도 받는다
    /// (옛 초과본을 줄이는 수정은 「신규」가 아니다 — 9-3 자동 삭제 금지 취지). 한도 안에서 새로 넘기는 변경은 넘는 항목이
    /// 반드시 늘었으므로 같은 규칙으로 거부된다. 새 추가는 네 값이 모두 느는 변경이다.
    ///
    /// 「늘었다」는 **넘은 항목에서만** 본다 — 넘은 글자 수를 줄이면서 한도 안의 단축어 수가 는 수정은 초과를 악화시키지 않는다.
    /// 내 문구 저장과 내장 팩 켜기가 이 한 함수를 쓴다(검증 F6).
    private static func baselineRejection(current: PackStats, proposed: PackStats, after: ActivePackBudget.Evaluation) -> Rejection? {
        let grown = after.baselineOverflow.filter { cost(of: $0, in: proposed) > cost(of: $0, in: current) }
        return grown.isEmpty ? nil : .baselineOverLimit(after.baselineOverflow)
    }

    /// baseline의 항목별 비용 — 피크는 baseline만으로 잰다(포함 팩 없음, `evaluate`와 같은 모델)
    private static func cost(of dimension: PackBudgetDimension, in stats: PackStats) -> Int {
        switch dimension {
        case .needleCount: stats.needleCount
        case .needleChars: stats.needleChars
        case .bytes: stats.bytes
        case .items: stats.items
        case .peak: ActivePackBudget.peakEstimateBytes(needleChars: stats.needleChars, largestPackBytes: 0)
        }
    }

    private static func dimensions(of id: String, in evaluation: ActivePackBudget.Evaluation) -> [PackBudgetDimension] {
        switch evaluation.excluded.first(where: { $0.id == id })?.reason {
        case .overflow(let dimensions): dimensions
        case .baselineOverflow: evaluation.baselineOverflow
        case .afterEarlierOverflow, .unavailable, nil: []
        }
    }
}
