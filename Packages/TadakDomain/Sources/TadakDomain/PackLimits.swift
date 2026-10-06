import Foundation

/// 외부 채움글 팩의 상한 — **한 곳**(PDR `external-snippet-packs.md` 5-4·9-6·10-1·11절, v2 10-1 표).
///
/// ★ **전부 후보값이다(R2).** 실측(P-2: 실기 footprint·지연, P-8: 긴 본문 삽입) 전에는 출시 안전성 승인값이
/// 아니다 — 값이 바뀌면 이 파일 한 곳만 고친다. 앱(가져오기·커밋 게이트)과 키보드(제한 읽기·집계)가 같은 값을 본다.
public enum PackLimits {

    // MARK: 필드 상한 — Character / UTF-8 바이트 / Unicode scalar 셋 다 본다(결합 문자 한 grapheme 방어, v2 10-1)

    public struct FieldLimit: Equatable, Sendable {
        public let characters: Int
        public let utf8Bytes: Int
        public let scalars: Int

        public init(characters: Int, utf8Bytes: Int, scalars: Int) {
            self.characters = characters
            self.utf8Bytes = utf8Bytes
            self.scalars = scalars
        }

        /// 세 잣대 모두 안이면 참
        public func admits(_ text: String) -> Bool {
            text.count <= characters && text.utf8.count <= utf8Bytes && text.unicodeScalars.count <= scalars
        }
    }

    /// 팩 이름 40자(5-6)
    public static let name = FieldLimit(characters: 40, utf8Bytes: 160, scalars: 120)
    /// 권리 표기 120자(5-6)
    public static let license = FieldLimit(characters: 120, utf8Bytes: 480, scalars: 360)
    /// 틀 literal(접두+접미 정규화 합) 40자(10-1) — 최대 확장 40+4자리 = 44 ≤ `committedTail` 48
    public static let templateLiteral = FieldLimit(characters: 40, utf8Bytes: 160, scalars: 120)
    /// 단축어 1개 40자(5-4 `TriggerCell`)
    public static let trigger = FieldLimit(characters: 40, utf8Bytes: 160, scalars: 120)
    /// 제목 60자
    public static let title = FieldLimit(characters: 60, utf8Bytes: 240, scalars: 180)
    /// 본문 3,000자 — 잠정, P-8 결과에 맞춰 줄일 수 있다(11절)
    public static let body = FieldLimit(characters: 3_000, utf8Bytes: 12_000, scalars: 9_000)

    // MARK: 구조 상한 (5-3·5-4·10-1)

    /// 가져올 파일 바이트(디코드 전) — 제한 읽기는 cap+1
    public static let fileBytes = 3_000_000
    /// 데이터 논리 레코드(헤더·메타·빈 레코드 제외)
    public static let dataRecords = 5_000
    /// 물리 줄 — 여러 줄 본문 때문에 정상 곡 수가 줄지 않게 논리 레코드와 분리(5-4)
    public static let physicalLines = 50_000
    /// 데이터 레코드 열(헤더 실효 폭)
    public static let dataColumns = 8
    /// 메타 레코드 셀(키 1 + 값 최대 11) — `#틀` 별칭 8개(9셀)가 데이터 cap과 충돌하지 않게 분리
    public static let metaCells = 12
    /// `#틀` 별칭(팩당 패턴) 1~8
    public static let templatePatterns = 8
    /// 항목당 단축어 10개
    public static let triggersPerEntry = 10
    /// 번호 1~9,999
    public static let numberRange = 1...9_999
    /// 외부 팩 수 — **꺼진 팩도 센다**(9-4 ② 팩 수 cap). 후보값 — P-2 「비활성 16팩」 시험값, P-2에서 확정(v3.6 ⑭)
    public static let externalPacks = 16
    /// 공유 snapshot의 manifest 바이트(9-4 ①) — 키보드가 **읽기 전에** 자른다. 팩 16개의 목차라 넉넉하다(후보값)
    public static let snapshotManifestBytes = 64 * 1024
    /// 변환본 파일이 예산 `bytes`(도메인 값 직렬화) 위에 더 쓰는 감싸기(schema·packID·source·stats·키) 여유 —
    /// 키보드의 파일 바이트 cap(9-4 ③) = 남은 예산 바이트 + 이 값. 후보값
    public static let storedPackOverheadBytes = 4 * 1024
    /// 건너뜀 비율이 이 값 이상이면 자동 진행 금지 — 경험적 초안(R10, 5-5)
    public static let skipRatioRequiringConfirmation = 0.5
}

/// 활성 집합 예산의 후보값(9-6). 구조는 확정, **숫자는 P-2 전 후보값**(R2).
public struct PackBudgetLimits: Equatable, Sendable {
    /// 매 키 입력의 선형 루프 길이 — 템플릿은 **패턴 수만** 센다
    public var needleCount: Int
    /// 정규화 Character 합(60,000 × 16B ≈ 0.9155MiB, 배열 원소만)
    public var needleChars: Int
    /// 직렬화 Data 길이
    public var bytes: Int
    /// entries + items — 독립 제약
    public var items: Int
    /// 피크 추정 상한(9-5) — **P-2 전에는 판정하지 않는다(nil)**. 모델은 `ActivePackBudget.peakEstimateBytes`
    public var peakBytes: Int?

    public init(needleCount: Int, needleChars: Int, bytes: Int, items: Int, peakBytes: Int? = nil) {
        self.needleCount = needleCount
        self.needleChars = needleChars
        self.bytes = bytes
        self.items = items
        self.peakBytes = peakBytes
    }

    /// 9-6 「후보값 표」 — 출시 안전성 승인값이 아니다
    public static let candidate = PackBudgetLimits(needleCount: 3_000, needleChars: 60_000, bytes: 3_000_000, items: 3_000)
}
