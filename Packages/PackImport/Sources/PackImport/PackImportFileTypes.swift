import UniformTypeIdentifiers

/// 3-D 파일 고르기가 받는 형식 — **판을 따른다**(`PackCopySet.acceptsWorkbookFiles`, 1-e ③). CSV 전용판은 `.csv`·`.tsv`·`.txt`만,
/// xlsx 중심판은 엑셀 통합 문서를 앞에 더한다. 나머지 형식은 선택기에서 고를 수 없다(시안 3-D — 「받지 않는 형식」은 3-A 바닥이 미리 말한다).
/// 고른 파일이 정말 xlsx인지는 확장자가 아니라 내용(매직)으로 가른다(`PackImporter.isWorkbook`)
public enum PackImportFileTypes {

    /// 엑셀 통합 문서 — 시스템이 선언한 형식 식별자(`.xlsx`). 찾지 못하면 확장자로 짓는다
    static let workbook: UTType = UTType("org.openxmlformats.spreadsheetml.sheet")
        ?? UTType(filenameExtension: "xlsx", conformingTo: .data) ?? .data

    public static func allowed(for set: PackCopySet) -> [UTType] {
        (set.acceptsWorkbookFiles ? [workbook] : []) + [.commaSeparatedText, .tabSeparatedText, .plainText]
    }
}
