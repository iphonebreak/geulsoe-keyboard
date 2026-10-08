import Foundation

/// (xlsx) 시트 이름을 **화면에 그리는** 규칙 — 4-D 시트 고르기 목록과 초안의 `sheetName`이 이 한 곳을 지나고, 팩 이름 기본값
/// (`XLSXWorkbookReader.Sheet.suggestedPackName`)도 같은 정리(`cleaned`)를 쓴다.
///
/// 보안 검토 S7(문자 정리로 제어·방향 재정의·제로폭 문자를 뺀다) 뒤에 남던 구별 문제를 고친다 — 검증 `verify-ext-1e-123.md` 2절 끝 관찰,
/// 사장님 결정 2026-10-08:
/// - ⓒ 줄바꿈(`_x000A_`)·탭과 공백 묶음은 공백 하나로, 앞뒤 공백은 뗀다
/// - ⓐ 보이는 글자가 없는 이름(`_x200B_`만·공백만·한글 채움 문자만)은 「시트 n」 — n은 **목록에 보이는 자리**(숨긴 시트 제외, 1부터 — 엑셀 탭도
///   숨긴 시트를 보여 주지 않는다, 코디네이터 확인 2026-10-08)
/// - ⓑ 같은 모양의 이름이 둘 이상이면 뒤 것부터 「이름 (k)」 — k는 2부터, 다른 시트의 이름과 같은 모양이 되는 k는 건너뛴다(결과는 모두 다른 모양)
///
/// 원래 이름(`XLSXWorkbookReader.Sheet.name`)은 그대로 둔다 — 시트는 **자리**로 고르고 이름은 저장하지 않는다. 「시트 n」·「 (k)」는 목록의
/// 구별 표시라 팩 이름 기본값에 싣지 않는다. 이름은 화면에만 — 로그·분석·오류 값에 싣지 않는다(6-4·AC-34)
enum PackSheetNames {

    /// 4-D 목록에 보일 이름 — 표시 시트 순서 그대로, 같은 개수
    static func display(_ names: [String]) -> [String] {
        let bases = names.enumerated().map { position, name in cleaned(name) ?? PackImportCopy.untitledSheetName(position + 1) }
        var taken = Set(bases.map(appearance))
        var shown = Set<String>()
        // 같은 모양마다 다음에 시도할 k — 같은 이름이 많아도 처음부터 다시 세지 않는다
        var nextOrdinal: [String: Int] = [:]
        return bases.map { base in
            let key = appearance(base)
            guard !shown.insert(key).inserted else { return base }
            var ordinal = nextOrdinal[key, default: 2]
            var candidate = PackImportCopy.duplicateSheetName(base, ordinal)
            while taken.contains(appearance(candidate)) {
                ordinal += 1
                candidate = PackImportCopy.duplicateSheetName(base, ordinal)
            }
            nextOrdinal[key] = ordinal + 1
            taken.insert(appearance(candidate))
            return candidate
        }
    }

    /// ⓒ 정리한 이름 — 문자 정리(11절, S7) → 공백 글자(줄바꿈·탭·전각 공백 포함) 묶음을 공백 하나로 → 앞뒤 공백 뗌.
    /// 보이는 글자가 없으면 nil(ⓐ). 보이지 않는 글자(ZWNJ·변이 선택자 등)는 이름에 남긴다 — 가족 이모지처럼 모양을 이루기도 해서 판정에서만 뺀다
    static func cleaned(_ name: String) -> String? {
        let joined = PackTextSanitizer.sanitize(name).text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return appearance(joined).contains { !$0.isWhitespace } ? joined : nil
    }

    /// ⓑ 「같은 모양」 판정 열쇠 — 보이지 않는 글자(Unicode Default_Ignorable_Code_Point: ZWJ·ZWNJ·변이 선택자·한글 채움 문자·소프트 하이픈 등)를
    /// 뺀 글. 정준 동치(NFC/NFD)는 `String`의 같음이 본다
    static func appearance(_ name: String) -> String {
        var key = ""
        key.unicodeScalars.append(contentsOf: name.unicodeScalars.lazy.filter { !$0.properties.isDefaultIgnorableCodePoint })
        return key
    }
}
