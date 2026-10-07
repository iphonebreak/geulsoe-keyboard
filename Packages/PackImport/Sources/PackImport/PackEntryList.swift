import Foundation
import TadakDomain

/// 팩 상세 「전체 보기」(R31, PDR `external-snippet-packs.md` 결정 표)의 읽기 모델 — 그 팩의 **모든 항목**을 「단축어 → 들어가는 문구」로.
///
/// - 문구형: 단축어가 여럿이면 **모두**(쉼표로 잇는다)
/// - 번호형: **대표 틀**(첫 `#틀` 원문, `PackTemplate.titleFormat`)에 번호를 넣은 단축어 — 「사자성어 12번」
/// - 결과 줄: 사용법과 **같은 함수**(`PackNoticeCopy.usageResult(body:)` — 여러 줄을 이어 30자·「…」)
/// - 순서: 팩 순서 그대로(문구형 = 항목 순서, 번호형 = 번호 오름차순 — 저장본이 이미 그 순서다)
///
/// 항목이 수천이어도 화면이 버벅이지 않게 줄과 검색 키를 **한 번에 만들어 둔다**(메인 밖 — `PackStoreClient.packEntries`). 검색은 그 키를
/// 훑기만 한다. 단축어·본문은 사용자 입력이다 — 화면에 표시만 하고 로그·분석 이벤트로 내보내지 않는다(보안 규칙)
public struct PackEntryList: Equatable, Sendable {

    public struct Row: Identifiable, Equatable, Sendable {
        /// 팩 안 자리(0부터) — 목록 id
        public let id: Int
        /// 친 단축어 — 문구형은 전부 쉼표로, 번호형은 대표 틀에 번호
        public let trigger: String
        /// 들어가는 문구 요약 — 사용법과 같은 함수
        public let result: String
        /// 검색 키 — 단축어마다·본문 전체를 `searchKey`로(단축어를 이은 표시 문자열로 찾으면 두 단축어에 걸친 말이 맞아 버린다)
        let triggerKeys: [[UInt8]]
        let bodyKey: [UInt8]
    }

    public let rows: [Row]

    public init(_ pack: ExternalPack) {
        if let template = pack.template {
            rows = template.items.enumerated().map { index, item in
                let trigger = template.titleFormat.replacingOccurrences(of: TemplatePatternSpec.placeholder, with: String(item.n))
                return Row(id: index, trigger: trigger, result: PackNoticeCopy.usageResult(body: item.body),
                           triggerKeys: [Self.searchKey(trigger)], bodyKey: Self.searchKey(item.body))
            }
        } else {
            rows = pack.entries.enumerated().map { index, entry in
                Row(id: index, trigger: entry.triggers.joined(separator: Self.triggerSeparator),
                    result: PackNoticeCopy.usageResult(body: entry.body),
                    triggerKeys: entry.triggers.map(Self.searchKey), bodyKey: Self.searchKey(entry.body))
            }
        }
    }

    /// 검색 — 단축어 하나나 본문에 찾는 말이 들어 있는 줄(띄어쓰기·대소문자 무시), 순서 그대로. 찾는 말이 비었으면(공백뿐 포함) 전부
    public func rows(matching query: String) -> [Row] {
        let key = Self.searchKey(query)
        guard !key.isEmpty else { return rows }
        return rows.filter { row in row.triggerKeys.contains { Self.bytes($0, contain: key) } || Self.bytes(row.bodyKey, contain: key) }
    }

    /// 찾는 말이 있나 — 공백뿐이면 없다(전부 보인다). 화면의 절 머리(「찾은 채움글 n개」)·빈 상태가 쓴다
    public static func isSearching(_ query: String) -> Bool { !searchKey(query).isEmpty }

    /// 문구형 단축어를 잇는 자리 — 「회사장, 장」
    static let triggerSeparator = ", "

    /// 검색 정규화 — 띄어쓰기 무시는 `SnippetEntry.normalizedTrigger` **한 함수**(설정 중복 판정·키보드 발동과 같은 규칙).
    /// 대소문자 무시는 **이 검색에서만** 더 건다(「thank」로 「Thank you」 — 코디네이터 결정 2026-10-07). 매칭·저장은 대소문자를 가린다.
    ///
    /// 키는 **NFC로 맞춘 UTF-8 바이트**다 — `String.contains`는 글자 단위로 비교해 3,000 × 1,000자에서 release로도 한 번에 0.14초가
    /// 걸렸다(글자마다 칠 때마다). 양쪽을 NFC로 맞춘 뒤 바이트로 훑으면 정준 등가(조합형·완성형 한글)를 그대로 지키고, UTF-8은 코드 포인트 경계에서만 맞는다
    static func searchKey(_ text: String) -> [UInt8] {
        Array(SnippetEntry.normalizedTrigger(text).lowercased().precomposedStringWithCanonicalMapping.utf8)
    }

    /// 바이트 부분열 — `memmem`(찾는 말이 비지 않았을 때만 부른다)
    static func bytes(_ haystack: [UInt8], contain needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return haystack.withUnsafeBytes { big in
            needle.withUnsafeBytes { little in memmem(big.baseAddress, big.count, little.baseAddress, little.count) != nil }
        }
    }
}
