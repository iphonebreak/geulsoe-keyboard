import Foundation
import TadakDomain

/// xlsx 시트 하나를 **CSV 논리 레코드와 같은 자리**에 놓는 내부 표(PDR `external-snippet-packs.md` 6-1).
/// 이 뒤는 CSV와 같은 헤더·메타 판정 → 행별 검증 → 예산 게이트를 탄다(1-e ③, AC-32) — 이 표는 셀의 **종류**만 말하고
/// 건너뜀 사유·우선순위(6-4: 수식 → 날짜 서식 → 불리언·오류 → 숫자(번호 열 밖) → 병합)는 판정 경로가 정한다.
///
/// 메모리에만 있다(로그·파일·네트워크 금지 — 셀 글·시트 이름은 사용자 입력이다).
public struct RawTable: Equatable, Sendable {

    /// 행 하나의 칸 상한 — 메타 칸 상한(`PackLimits.metaCells` 12) + 넘침 칸 1.
    /// 그 밖의 비지 않은 셀은 마지막 칸(13번째) 하나로 **접는다**(먼저 온 것). 메타(> 12칸 거부)·머리글(> 8열 거부)·
    /// 데이터(머리글보다 넓으면 그 행 건너뜀) 어느 행이든 CSV에서 같은 셀이 낼 결과가 그대로 나고, 시트 폭(XFD = 16,384열)이
    /// 메모리를 정하지 않는다
    public static let columnLimit = PackLimits.metaCells + 1

    /// 비지 않은 행만, 시트 행 번호 오름차순 — 빈 행은 CSV에서도 어디서든 무시된다(5-4)
    public var rows: [RawRow]
    /// 숨김 열(`<cols><col hidden>`)의 0부터 센 자리 — `columnLimit` 안쪽만. 읽기는 그대로 하고 미리보기에 「숨김 N」만 보인다(6-4)
    public var hiddenColumns: [Int]

    public init(rows: [RawRow], hiddenColumns: [Int]) {
        self.rows = rows
        self.hiddenColumns = hiddenColumns
    }
}

public struct RawRow: Equatable, Sendable {
    /// 시트의 행 번호(1부터) — 사용자가 엑셀에서 보는 번호라 「n번째 행」 문구에 그대로 쓴다
    public var number: Int
    /// 0번 열부터 빽빽하게, 끝의 빈 칸은 잘라 낸다(`RawTable.columnLimit` 이하)
    public var cells: [RawCell]
    /// `<row hidden>` — 읽되 「숨김 N」으로 알린다(6-4)
    public var isHidden: Bool
    /// 병합 범위(`<mergeCell>`)와 겹치는 행 — 선두든 아니든. 병합 × 헤더/메타 = 전체 거부, 데이터 = 그 행 건너뜀(6-4)은 판정 경로 몫이다.
    /// 셀 값이 아니라 행 속성인 이유: 같은 행의 다른 사유(수식·숫자)가 병합보다 앞서야 하고(6-4 우선순위), 메타·머리글 판정에는 선두 셀 값이 필요하다
    public var isMerged: Bool

    public init(number: Int, cells: [RawCell], isHidden: Bool = false, isMerged: Bool = false) {
        self.number = number
        self.cells = cells
        self.isHidden = isHidden
        self.isMerged = isMerged
    }
}

/// 셀 하나(6-1) — 글·숫자는 **저장된 그대로**(숫자는 `<v>` 글자, 구글은 `323.0`), 해석은 판정 경로가 한다
public enum RawCell: Equatable, Sendable {
    /// 공유 문자열·인라인 문자열 — `_xHHHH_`를 한 번 풀고 줄바꿈을 LF로 맞춘 뒤(6-4 순서 계약). 문자 정리(11절)는 뒤 단계
    case text(String)
    /// 숫자 셀의 `<v>` 글자 그대로(앞뒤 공백만 뗌) — 날짜 서식이 아닌 숫자
    case number(String)
    /// 값이 없는 셀(서식만 있는 `<c>`·빈 문자열)
    case blank
    /// 원문이 아닌 셀 — 그 행은 건너뛴다(6-4)
    case unsupported(UnsupportedCellKind)
}

/// 6-4가 건너뛰는 셀 종류 — 병합은 행 속성(`RawRow.isMerged`)이다
public enum UnsupportedCellKind: Equatable, Sendable {
    /// `<f>`가 있는 셀·`t="str"`(수식 문자열) — 캐시 값은 원문이 아니다
    case formula
    /// 날짜·시간 서식의 숫자 셀·`t="d"`
    case date
    /// `t="b"`
    case boolean
    /// `t="e"`
    case error
}
