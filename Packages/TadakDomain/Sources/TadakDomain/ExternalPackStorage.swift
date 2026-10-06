import Foundation

// 외부 채움글 팩 저장(1-b) — PDR `docs/design-reviews/external-snippet-packs.md` 2절(계획 A: 파일 + snapshot, R1 확정
// 2026-10-06 P-1 통과)·7절(변환본)·8절(snapshot 계약)·9-4(키보드 재검사)·9-5(재구성 키)·10-4/U1(순서 목록).
//
// 앱(`PackStore`, TadakData)이 쓰고 키보드(`PackSnapshotLoader`, TadakData)가 읽는 **값의 모양**만 여기 둔다 —
// 파일 입출력은 TadakData, 매칭은 KeyboardCore. **팩 본문·단축어·이름·권리는 사용자 입력이다** — 로그·네트워크 0.

/// 채움글 순서 목록의 한 줄 — 「내 채움글」도 한 줄이다(U1). 위에 있는 쪽이 같은 단축어에서 먼저 뜬다.
/// 내장 팩은 이 목록 밖에서 그 뒤에 온다(10-3 분기 순서 불변).
public enum SnippetSourceSlot: Equatable, Hashable, Sendable, Codable {
    case userSnippets
    case pack(String)

    /// U1 기본 — 「내 채움글」이 맨 위(새 팩은 U2로 맨 아래라 손대지 않으면 내 채움글이 이긴다)
    public static let defaultOrder: [SnippetSourceSlot] = [.userSnippets]

    public var packID: String? {
        if case .pack(let id) = self { return id }
        return nil
    }

    // 저장 모양은 글자 하나 — "user" · "pack:<id>"
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        if raw == "user" {
            self = .userSnippets
        } else if raw.hasPrefix("pack:"), raw.count > 5 {
            self = .pack(String(raw.dropFirst(5)))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown slot"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .userSnippets: try container.encode("user")
        case .pack(let id): try container.encode("pack:\(id)")
        }
    }
}

/// 변환본 파일 하나(7절 `schema: 1`) — 앱 전용 저장소와 공유 snapshot이 **같은 바이트**를 쓴다.
/// `stats`는 앱이 계산하지만 **키보드는 믿지 않는다**(9-4 — 다시 센다).
public struct StoredExternalPack: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    /// 가져온 경로 — 진단용, 로그·분석에는 쓰지 않는다(7절)
    public enum Source: String, Codable, Sendable {
        case csv, xlsx, gspack
    }

    public var schema: Int
    /// 앱이 무작위로 만든다(이름·내용에서 만들지 않는다)
    public var packID: String
    public var source: Source
    public var pack: ExternalPack
    public var stats: PackStats

    public init(packID: String, source: Source, pack: ExternalPack) {
        self.schema = Self.schemaVersion
        self.packID = packID
        self.source = source
        self.pack = pack
        self.stats = PackStats.of(pack: pack)
    }
}

/// 공유 snapshot `g<N>`의 목차(8절). 앱이 팩 파일을 다 쓴 **뒤** 마지막에 쓰고, 그다음 `packsGeneration = N`을 올린다.
public struct PackSnapshotManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public struct Item: Codable, Equatable, Sendable {
        public var id: String
        /// snapshot 폴더 안의 파일 이름
        public var file: String
        /// 파일 실제 바이트 — 키보드는 읽기 전에 실제 크기와 대조한다(어긋나면 외부 팩 전부 제외, AC-8)
        public var bytes: Int
        /// 빠른 거절 힌트일 뿐 — 허용의 근거가 아니다(9-4 ①)
        public var stats: PackStats

        public init(id: String, file: String, bytes: Int, stats: PackStats) {
            self.id = id
            self.file = file
            self.bytes = bytes
            self.stats = stats
        }
    }

    public var schema: Int
    public var generation: Int
    /// 이 snapshot을 만들 때의 사용자 문구 revision(8-1 ①)
    public var userSnippetsRevision: Int
    /// U1 순서 — 「내 채움글」 한 줄 + **앱이 예산 안이라 판정한 켜진 팩**(쉬는 팩은 싣지 않는다, R14)
    public var order: [SnippetSourceSlot]
    /// `order`의 팩 순서 그대로
    public var packs: [Item]

    public init(generation: Int, userSnippetsRevision: Int, order: [SnippetSourceSlot], packs: [Item]) {
        self.schema = Self.schemaVersion
        self.generation = generation
        self.userSnippetsRevision = userSnippetsRevision
        self.order = order
        self.packs = packs
    }
}

extension ExternalPack {
    /// 9-4 ⑤ — 키보드가 디코드한 **뒤** 필드 상한과 모드 모양을 다시 본다(앱 검증을 믿지 않는다 — 공유 JSON·옛 저장본 방어).
    /// 넘으면 키보드는 외부 팩 전부를 싣지 않는다(AC-8). 크기(직렬화 바이트)는 예산이 따로 본다.
    public var isWithinStoredLimits: Bool {
        guard PackLimits.name.admits(name), PackLimits.license.admits(license) else { return false }
        switch mode {
        case .phrases:
            guard template == nil else { return false }
        case .numbered:
            guard entries.isEmpty, template != nil else { return false }
        }
        for entry in entries {
            guard (1...PackLimits.triggersPerEntry).contains(entry.triggers.count),
                  entry.triggers.allSatisfy({ PackLimits.trigger.admits($0) }),
                  PackLimits.title.admits(entry.title), PackLimits.body.admits(entry.body) else { return false }
        }
        if let template {
            guard (1...PackLimits.templatePatterns).contains(template.patterns.count),
                  template.patterns.allSatisfy({ PackLimits.templateLiteral.admits($0.prefix + $0.suffix) }) else { return false }
            for item in template.items {
                guard PackLimits.numberRange.contains(item.n),
                      PackLimits.title.admits(item.title), PackLimits.body.admits(item.body) else { return false }
            }
        }
        return entries.count + (template?.items.count ?? 0) <= PackLimits.dataRecords
    }
}

/// 키보드가 채움글 매처를 **다시 만들 때**를 정하는 키(9-5 · AC-9). 테마·진동·슬라이더 같은 다른 설정 알림에서는
/// 같은 값이라 매처를 다시 만들지 않는다 — 사용자 문구·팩 generation과 채움글에 관계된 설정이 바뀔 때만 바뀐다.
public struct SnippetRebuildKey: Equatable, Sendable {
    public var snippetsEnabled: Bool
    public var disabledSnippetPacks: Set<String>
    public var bibleSnippetPrefixEnabled: Bool
    public var dateSnippetStyle: DateSnippetStyle
    public var userSnippetsGeneration: Int
    public var packsGeneration: Int

    public init(settings: KeyboardSettings, userSnippetsGeneration: Int, packsGeneration: Int) {
        snippetsEnabled = settings.snippetsEnabled
        disabledSnippetPacks = Set(settings.disabledSnippetPacks)
        bibleSnippetPrefixEnabled = settings.bibleSnippetPrefixEnabled
        dateSnippetStyle = settings.dateSnippetStyle
        self.userSnippetsGeneration = userSnippetsGeneration
        self.packsGeneration = packsGeneration
    }
}
