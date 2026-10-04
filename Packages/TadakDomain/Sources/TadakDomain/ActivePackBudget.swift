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

    /// 문구 목록(내 채움글·켜진 내장·문구형 팩) — needle은 `SnippetMatcher`와 같은 규칙(정규화 뒤 빈 단축어 제외)
    public static func of(entries: [SnippetEntry]) -> PackStats {
        let needles = needleCharacters(of: entries)
        return PackStats(needleCount: needles.count, needleChars: needles.reduce(0, +),
                         bytes: Self.serializedBytes(of: entries), items: entries.count)
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

    private static func needleCharacters(of entries: [SnippetEntry]) -> [Int] {
        entries.flatMap { entry in
            entry.triggers.map { SnippetEntry.normalizedTrigger($0).count }.filter { $0 > 0 }
        }
    }

    /// 결정적 직렬화 — 키 정렬, 공백 없음. 인코딩 실패(이 타입들에서는 일어나지 않는다)는 0으로 둔다
    static func serializedBytes<Value: Encodable>(of value: Value) -> Int {
        (try? encoder.encode(value).count) ?? 0
    }

    /// 항목 하나의 직렬화 길이 — 배열 길이 = `2 + Σ항목 + (n−1)`(쉼표)라 앞에서부터 더할 수 있다(9-3)
    static func serializedBytes(ofEntry entry: SnippetEntry) -> Int {
        serializedBytes(of: entry)
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

    /// 9-3 — baseline이 넘을 때 키보드가 싣는 내 채움글 개수: **저장 순서대로 한도까지만**(나머지는 지우지 않고 안 싣는다).
    /// 내장은 번들 고정량이라 먼저 차감하고 항상 싣는다. 앱의 「일부만 사용 중」 안내도 이 함수로 센다.
    public static func loadableUserEntryCount(
        _ entries: [SnippetEntry], builtIn: PackStats, limits: PackBudgetLimits = .candidate
    ) -> Int {
        var usage = builtIn + PackStats(needleCount: 0, needleChars: 0, bytes: 2, items: 0)   // 빈 배열 "[]"
        for (index, entry) in entries.enumerated() {
            var single = PackStats.of(entries: [entry])
            single.bytes = PackStats.serializedBytes(ofEntry: entry) + (index > 0 ? 1 : 0)      // 쉼표
            let next = usage + single
            guard overflowing(next, largestPackBytes: 0, limits: limits).isEmpty else { return index }
            usage = next
        }
        return entries.count
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
        /// 「꺼 둔 채로 가져오기」(U2) — 꺼진 팩은 예산에 들지 않아 **팩 수 상한만** 본다(v3.6 ⑭)
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
        case .importDisabledPack:
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
        case .afterEarlierOverflow, nil: []
        }
    }
}
