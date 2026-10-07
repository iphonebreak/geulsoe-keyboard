import Foundation
import Testing
@testable import PackImport

// 외부 채움글 1-c 6단계 ① — 문구 두 벌(PDR `external-snippet-packs.md` 3-1 「`xlsx 중심판`과 `CSV 전용판` 두 세트를 준비하고 **빌드 시점에 하나를 고른다**」,
// R12 · 계획서 `external-snippet-packs-1c-plan.md` 5절 6행 ① · 시안 `docs/design/external-snippet-packs/index.html` 6절 비교표 · 3-A·3-B·2-B의 판별 줄).
// 판은 상수 하나(`PackCopySet.selected`)가 고르고, 1~5단계 문구 표는 그 판을 따른다. xlsx판은 **CSV판과 다른 줄만** 갖고 나머지는 공유한다.
// 시험은 `PackCopySet.$previewing`으로 판을 골라 같은 표를 두 번 읽는다.

/// 판이 바꾸는 문구 전부 — 표가 `PackCopySet.current`를 읽는 자리. **이 목록이 「다른 줄」 목록이다**(시안 6절 비교표의 행)
var setDependentCopy: [String] {
    var texts = [
        PackNoticeCopy.emptyListFooter,                                   // 2-B 절 설명
        PackImportCopy.heroTitle, PackImportCopy.heroMessage, PackImportCopy.pickFile,   // 3-A 주 버튼
        PackImportCopy.guideTitle,                                        // 3-A·3-B·4-G 만드는 법
        PackImportCopy.guideCellsSection, PackImportCopy.guideCellsFooter   // 3-B 3절
    ]
    texts += PackImportCopy.guideCells.flatMap { $0 } + PackImportCopy.guideSave   // 3-B 3·4절 — 문장마다 한 줄(R30)
    if let footer = PackImportCopy.startFooter { texts.append(footer) }   // 3-A 받지 않는 형식(xlsx판만 — CSV판은 풋터 없음)
    if let row = PackImportCopy.otherFileRow { texts += [row.title, row.detail] }   // 3-A 그 밖의 방법(xlsx판만)
    for kind in PackSample.Kind.allCases {                                // 3-A·3-C 샘플(판마다 형식)
        texts += PackSample.files(kind).flatMap { [PackImportCopy.sampleFormatLabel($0.format), PackImportCopy.sampleShareLabel($0), $0.displayName] }
    }
    return texts
}

/// 그 판으로 만든 화면 문구 전부(1~6단계 — `PackCopyLintTests.swift`의 `allScreenCopy`)
private func screenCopy(_ set: PackCopySet) -> [String] {
    PackCopySet.$previewing.withValue(set) { allScreenCopy }
}

@Suite("외부 채움글 1-c 6단계 ① — 문구 두 벌(CSV 전용판 / xlsx 중심판)")
struct PackCopySetTests {

    @Test("★ 1.3.0 빌드는 CSV 전용판이다(R12) — xlsx 중심판으로 바꾸는 것은 1-e 출시 게이트를 넘은 뒤 이 시험과 함께")
    func selectedIsCSV() {
        #expect(PackCopySet.selected == .csv)
        #expect(PackCopySet.current == .csv)
    }

    @Test("판을 묶지 않으면 표는 고른 판을 따르고, 묶으면 그 판을 따른다")
    func currentFollowsPreview() {
        #expect(PackCopySet.$previewing.withValue(.xlsx) { PackCopySet.current } == .xlsx)
        #expect(PackCopySet.$previewing.withValue(.csv) { PackCopySet.current } == .csv)
        #expect(PackCopySet.current == PackCopySet.selected)
    }

    @Test("★ CSV 전용판 — 시안 6-B·3-A·3-B CSV 열 글자 그대로(4단계까지 화면에 나가던 문구와 같다)")
    func csvLines() {
        PackCopySet.$previewing.withValue(.csv) {
            #expect(PackNoticeCopy.emptyListFooter
                    == "CSV 파일로 만든 채움글 묶음(팩)을 가져와요. 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요.")
            #expect(PackImportCopy.heroTitle == "CSV 파일 가져오기")
            #expect(PackImportCopy.heroMessage == "첫 줄에 머리글이 있는 CSV 파일을 골라요. UTF-8을 권해요.\n번호형(사자성어 12번처럼)·문구형(단축어 → 문구) 둘 다 돼요.")
            #expect(PackImportCopy.pickFile == "CSV 파일 가져오기")   // 「고르기」 → 「가져오기」(사장님 실기 2026-10-07)
            #expect(PackImportCopy.guideTitle == "CSV로 팩 만드는 법")
            #expect(PackImportCopy.otherFileRow == nil)
            // 「엑셀에서는 …」 풋터를 개인정보 한 줄까지 통째로 뺐다(사장님 실기 2026-10-07)
            #expect(PackImportCopy.startFooter == nil)
            #expect(PackImportCopy.guideCellsSection == "모양이 바뀌기 쉬운 칸")
            // 칸마다 문장 하나에 한 줄(R30) — 글자는 나누기 전과 같다
            #expect(PackImportCopy.guideCells == [
                ["숫자·날짜처럼 보이는 글(예: 007, 1-2) → 열 서식을 먼저 「텍스트」로 바꾼 뒤 입력해 주세요.",
                 "그렇지 않으면 CSV에 바뀐 모양으로 저장돼요."],
                ["= + - @로 시작하는 글 → 열 서식을 먼저 「텍스트」로 바꾼 뒤 입력해 주세요.",
                 "앞에 작은따옴표(')를 붙이면 붙여넣을 때 글자로 남을 수 있어요."]
            ])
            #expect(PackImportCopy.guideCellsFooter == "가져오기 미리보기에서 처음 몇 개를 확인해 주세요.")
            #expect(PackImportCopy.guideSave == [
                "파일 ▸ 다른 이름으로 저장 ▸ 「CSV UTF-8」이 든 항목(예: CSV UTF-8(쉼표로 분리))을 골라요.",
                "「쉼표로 구분된 값」처럼 UTF-8이 없는 항목도 가져올 수 있지만 일부 기호가 바뀔 수 있어요.",
                "쉼표·세미콜론·탭 모두 알아서 읽어요.",
                "파일 앱·AirDrop·메일로 이 기기에 옮긴 뒤 「CSV 파일 가져오기」를 눌러요."
            ])
            #expect(PackSample.files(.numbered).map(\.format) == [.csv])
            #expect(PackSample.files(.phrases).map(\.format) == [.csv])
        }
    }

    @Test("★ xlsx 중심판 — 시안 6-A·3-A·3-B xlsx 열 · PDR 6-7 xlsx판 문구. 「엑셀 파일 그대로 가져오기」가 주 안내, CSV는 병행(AC-35 뒷절)")
    func xlsxLines() {
        PackCopySet.$previewing.withValue(.xlsx) {
            #expect(PackNoticeCopy.emptyListFooter
                    == "엑셀 파일로 만든 채움글 묶음(팩)을 가져와요. 사자성어·상용 영어처럼 번호로 부르는 자료도 돼요. 가져온 팩은 이 기기에만 저장돼요.")
            #expect(PackImportCopy.heroTitle == "엑셀 파일 그대로 가져오기")
            #expect(PackImportCopy.heroMessage == "첫 줄에 머리글이 있는 엑셀 파일(.xlsx)을 골라요.\n번호형(사자성어 12번처럼)·문구형(단축어 → 문구) 둘 다 돼요.")
            #expect(PackImportCopy.pickFile == "엑셀 파일 고르기")
            #expect(PackImportCopy.guideTitle == "엑셀로 팩 만드는 법")
            #expect(PackImportCopy.otherFileRow == PackCopySet.Row(title: "CSV 파일 가져오기", detail: "구글 시트·Numbers·메모장에서 만든 CSV도 돼요"))
            #expect(PackImportCopy.startFooter
                    == "받지 않는 파일: Numbers 파일(.numbers), 옛 엑셀(.xls), 매크로가 든 엑셀(.xlsm·.xlsb), 비밀번호가 걸린 엑셀, .json — "
                    + "엑셀에서 「Excel 통합 문서(.xlsx)」나 「CSV UTF-8」로 다시 저장해 주세요.")   // 뒤 개인정보 한 줄은 뺐다(2026-10-07)
            #expect(PackImportCopy.guideCellsSection == "이런 칸은 건너뛰어요")
            #expect(PackImportCopy.guideCells == [
                ["수식 → 「값만 붙여넣기」로 바꿔 주세요"],
                ["날짜로 바뀐 칸(1/2 → 1월 2일) → 그 열 서식을 「텍스트」로"],
                ["병합한 칸 → 병합을 풀어 주세요.", "숨긴 시트는 목록에 안 나와요"],
                ["= + - @로 시작하는 글 → 열 서식을 먼저 「텍스트」로 바꾼 뒤 입력해 주세요.",
                 "앞에 작은따옴표(')를 붙이면 붙여넣을 때 글자로 남을 수 있어요."]
            ])
            #expect(PackImportCopy.guideCellsFooter
                    == "엑셀에서 만들었다면 xlsx로 저장해서 가져오면 숫자·날짜로 바뀐 칸을 알려 드려요. CSV로 저장하면 바뀐 값이 그대로 들어올 수 있어요.")
            #expect(PackImportCopy.guideSave == ["파일 ▸ 다른 이름으로 저장 ▸ Excel 통합 문서(.xlsx).",
                                                 "파일 앱·AirDrop·메일로 이 기기에 옮긴 뒤 「엑셀 파일 고르기」를 눌러요."])
            #expect(PackSample.files(.numbered).map(\.format) == [.xlsx, .csv])   // 시안 3-A 알약 순서 [엑셀][CSV]
            #expect(PackSample.files(.phrases).map(\.displayName) == ["문구형 샘플.xlsx", "문구형 샘플.csv"])
        }
    }

    @Test("★ xlsx판은 CSV판과 **다른 줄만** 갖는다 — 판 구조체의 칸은 두 판에서 모두 다르다(같으면 공유 문구로 옮긴다)")
    func linesHoldOnlyDifferences() {
        let csv = Mirror(reflecting: PackCopySet.csv.lines).children.map { ($0.label ?? "", String(describing: $0.value)) }
        let xlsx = Mirror(reflecting: PackCopySet.xlsx.lines).children.map { ($0.label ?? "", String(describing: $0.value)) }
        #expect(csv.count == xlsx.count && !csv.isEmpty)
        for (left, right) in zip(csv, xlsx) {
            #expect(left.0 == right.0)
            #expect(left.1 != right.1, "같은 줄이 판 구조체에 있다: \(left.0)")
        }
    }

    @Test("★ 나머지 문구는 두 판이 공유한다 — 두 판의 화면 문구 차이는 전부 판이 바꾸는 줄(1~5단계 표가 판을 따른다)")
    func everythingElseIsShared() {
        let csv = Set(screenCopy(.csv))
        let xlsx = Set(screenCopy(.xlsx))
        let dependent = Set(PackCopySet.allCases.flatMap { set in PackCopySet.$previewing.withValue(set) { setDependentCopy } })
        let differing = csv.symmetricDifference(xlsx)
        #expect(!differing.isEmpty)
        #expect(differing.isSubset(of: dependent), "판이 모르는 차이: \(differing.subtracting(dependent).sorted())")
        // 판이 바꾸는 줄은 실제로 화면 문구에 들어 있다(검사가 빈 목록을 돌지 않는다)
        #expect(Set(PackCopySet.$previewing.withValue(.csv) { setDependentCopy }).isSubset(of: csv))
        #expect(Set(PackCopySet.$previewing.withValue(.xlsx) { setDependentCopy }).isSubset(of: xlsx))
    }

    @Test("폼 문구 표(5단계)에는 판이 바꾸는 줄이 없다 — 5-B 「시트 이름」은 판이 아니라 가져온 파일 형식에 따른다(1-e)")
    func formCopyIsShared() {
        #expect(PackCopySet.$previewing.withValue(.csv) { stage5Copy } == PackCopySet.$previewing.withValue(.xlsx) { stage5Copy })
    }
}

@Suite("R30 — 「팩 만드는 법」(3-B)은 칸마다 문장 하나에 한 줄")
struct PackGuideSentenceTests {

    /// 3-B 본문 칸 전부(시트 아래 열 설명 · 정보 줄 · 바뀌기 쉬운 칸 · 저장하고 옮기기) — 화면이 줄마다 앞에 「·」를 붙인다
    private func guideCellSentences() -> [[String]] {
        [PackImportCopy.guideColumns, PackImportCopy.guideMeta] + PackImportCopy.guideCells + [PackImportCopy.guideSave]
    }

    @Test("★ 한 줄에 문장이 둘 이어지지 않는다 — 마침표 뒤에 다른 문장이 붙지 않고, 빈 줄이 없다", arguments: PackCopySet.allCases)
    func oneSentencePerLine(_ set: PackCopySet) {
        PackCopySet.$previewing.withValue(set) {
            let cells = guideCellSentences()
            #expect(cells.allSatisfy { !$0.isEmpty })
            for sentence in cells.flatMap({ $0 }) {
                #expect(!sentence.isEmpty && sentence == sentence.trimmingCharacters(in: .whitespacesAndNewlines), "\(sentence)")
                #expect(!sentence.contains(". ") && !sentence.contains("\n"), "한 줄에 문장이 둘: \(sentence)")
                #expect(!sentence.hasPrefix("·"), "머리점은 화면이 붙인다 — 글자에 넣지 않는다(VoiceOver가 읽지 않게): \(sentence)")
            }
        }
    }

    @Test("★ CSV판은 본문 칸이 모두 문장 둘 이상이다 — 나누기 전 한 칸에 문장이 이어져 읽기 어려웠던 곳(사장님 실기 2026-10-07)")
    func csvCellsAreSplit() {
        PackCopySet.$previewing.withValue(.csv) {
            #expect(guideCellSentences().map(\.count) == [3, 2, 2, 2, 4])
        }
    }
}
