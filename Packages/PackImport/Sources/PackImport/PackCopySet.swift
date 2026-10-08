/// 외부 채움글 화면 문구의 **판** — PDR `docs/design-reviews/external-snippet-packs.md` 3-1(R11·R12): 「화면·안내 문구를 `xlsx 중심판`과
/// `CSV 전용판` 두 세트로 준비하고 **빌드 시점에 하나를 고른다** … 이 전환은 코드 경로가 아니라 문구·샘플 리소스만 바꾸도록 설계한다」.
///
/// 판이 바꾸는 줄은 `Lines` **한 곳**에만 있다(시안 `docs/design/external-snippet-packs/index.html` 6절 비교표·2-B·3-A·3-B의 판별 줄,
/// PDR 6-7 xlsx판 문구). 나머지 문구는 `PackNoticeCopy`·`PackImportCopy`·`PackFormCopy`가 두 판에 공유하고, 판이 바꾸는 자리는 그 표들이
/// `PackCopySet.current.lines`를 읽는다. **CSV 전용판에는 xlsx 형식·엑셀 파일을 가져오는 안내가 없다**(AC-35 — `PackCopyLintTests`가 검색한다).
///
/// 판에 넣지 않은 것: 가져온 파일 **형식**에 따라 갈리는 문구(xlsx 출처의 「시트 이름」·수식·병합 사유 등)는 판이 아니라 xlsx 파서(1-e)와 함께 온다 —
/// xlsx 중심판에서도 CSV를 가져오면 CSV 문구가 맞기 때문이다.
/// **xlsx를 받는지는 판을 따른다**(`acceptsWorkbookFiles`, 1-e ③ 코디네이터 결정) — CSV 전용판은 파일 고르기가 xlsx를 보이지 않고 가져오기도
/// xlsx로 읽지 않는다(없는 기능을 열지 않는다 — AC-35). 그래서 판 전환(`selected`) 한 줄이 곧 xlsx 열기다(R38 — 1.3.0에서 열었다).
public enum PackCopySet: String, CaseIterable, Sendable {
    /// CSV 전용판 — R12의 대비책(xlsx가 출시 게이트를 못 넘어도 CSV만으로 나갈 수 있게). 1.3.0은 이 판이 아니다(R38) — 문구·시험은 그대로 둔다
    case csv
    /// xlsx 중심판 — 「엑셀 파일 그대로 가져오기」가 주 안내, CSV는 「그 밖의 방법」(R11). **1.3.0이 내는 판**(R38 — 1-e 게이트 준비 뒤 사장님 승인 2026-10-08)
    case xlsx

    /// ★ 이 빌드의 판 — **판을 고르는 곳은 이 한 줄뿐이다.** 1.3.0은 `.xlsx`(R38 — 시험 `PackCopySetTests.selectedIsXLSX`가 지킨다).
    /// CSV 전용판으로 되돌리면 그 시험과 「지금 판」을 단정한 시험(`acceptanceFollowsCopySet`·`pickerTypes`·`prepareForSharing`·`sectionCopy`)을 함께 뒤집는다
    public static let selected: PackCopySet = .xlsx

    /// 다른 판의 문구를 볼 때만 묶는다(시험 — `PackCopySet.$previewing.withValue(.xlsx) { … }`). 앱은 묶지 않는다
    @TaskLocal public static var previewing: PackCopySet?

    /// 문구 표가 따르는 판 — 평소 `selected`
    public static var current: PackCopySet { previewing ?? selected }

    /// 파일 고르기·가져오기가 엑셀 통합 문서(xlsx)를 받나 — CSV 전용판은 받지 않는다(AC-35). 파일 형식 목록은 `PackImportFileTypes`,
    /// 가져오기 판별은 `PackImportSession.acceptsWorkbookFiles`가 이 값을 따른다
    public var acceptsWorkbookFiles: Bool { self == .xlsx }

    public var lines: Lines {
        switch self {
        case .csv: .csv
        case .xlsx: .xlsx
        }
    }

    /// 목록의 한 줄(제목 + 보조줄)
    public struct Row: Equatable, Sendable {
        public let title: String
        public let detail: String

        public init(title: String, detail: String) {
            self.title = title
            self.detail = detail
        }
    }

    /// 두 판에서 **다른 줄만** — 칸마다 두 판의 값이 다르다(같아지면 공유 문구로 옮긴다, `PackCopySetTests.linesHoldOnlyDifferences`)
    public struct Lines: Sendable {
        /// 2-B 빈 상태의 첫 문장(뒤 문장은 공유)
        let listIntro: String
        /// 3-A 주 버튼 절 — 제목 · 설명(판별 문구 한 줄 — 공유하던 둘째 줄은 2026-10-08에 뺐다) · 버튼.
        /// 판별 문구는 머리글 **자리**를 말하지 않는다(「첫 줄에」를 뺐다 — 정보 줄·빈 줄이 머리글 위에 와도 된다, 실기 피드백 2)
        let heroTitle: String
        let heroLead: String
        let pickFile: String
        /// 3-B 만드는 법 제목 — 3-A 「처음이라면」·4-G 버튼도 이 글자
        let guideTitle: String
        /// 3-A 「그 밖의 방법」의 파일 줄 — 주 버튼이 엑셀인 xlsx판에만 있다(CSV를 숨기지 않는다, 3-1)
        let otherFileRow: Row?
        /// 3-A 바닥 — 받지 않는 파일. CSV 전용판은 없다 — 「붙여넣기로 가져오기」 아래 「엑셀에서는 …」 풋터를 통째로 뺐다
        /// (사장님 실기 2026-10-07). 저장 방법은 3-B 4절이 말한다
        let unsupportedFiles: String?
        /// 3-A 샘플 알약 — 종류마다 이 순서로(시안 3-A [엑셀][CSV]). xlsx 샘플 파일은 1-e 번들 리소스다
        let sampleFormats: [PackSample.Format]
        /// 3-B 3절 — 제목 · 칸(칸마다 문장 배열, R30) · 풋터
        let guideCellsSection: String
        let guideCells: [[String]]
        let guideCellsFooter: String
        /// 3-B 4절 저장 방법 — 문장 배열(뒤의 「옮긴 뒤 …를 눌러요」 문장은 공유)
        let guideSaveSteps: [String]
    }
}

extension PackCopySet.Lines {

    /// 두 판이 함께 쓰는 「모양이 바뀌기 쉬운 칸」 줄 — 엑셀 붙여넣기에서 작은따옴표가 글자로 남는다(PDR 6-7 T13)
    private static let leadingSymbolCell = [
        "= + - @로 시작하는 글 → 열 서식을 먼저 「텍스트」로 바꾼 뒤 입력해 주세요.",
        "앞에 작은따옴표(')를 붙이면 붙여넣을 때 글자로 남을 수 있어요."
    ]

    /// CSV 전용판 — 시안 6-B·3-A·3-B의 CSV 열, 3-B 3절은 PDR 6-7의 CSV 전용판 안내(R20 「가 — 안내 문구만」)
    static let csv = PackCopySet.Lines(
        listIntro: "CSV 파일로 만든 채움글 묶음(팩)을 가져와요.",
        heroTitle: "CSV 파일 가져오기",
        heroLead: "머리글이 있는 CSV 파일을 골라요. UTF-8을 권해요.",
        pickFile: "CSV 파일 가져오기",
        guideTitle: "CSV로 팩 만드는 법",
        otherFileRow: nil,
        unsupportedFiles: nil,
        sampleFormats: [.csv],
        guideCellsSection: "모양이 바뀌기 쉬운 칸",
        guideCells: [
            ["숫자·날짜처럼 보이는 글(예: 007, 1-2) → 열 서식을 먼저 「텍스트」로 바꾼 뒤 입력해 주세요.",
             "그렇지 않으면 CSV에 바뀐 모양으로 저장돼요."],
            leadingSymbolCell
        ],
        guideCellsFooter: "가져오기 미리보기에서 처음 몇 개를 확인해 주세요.",
        guideSaveSteps: [
            "파일 ▸ 다른 이름으로 저장 ▸ 「CSV UTF-8」이 든 항목(예: CSV UTF-8(쉼표로 분리))을 골라요.",
            "「쉼표로 구분된 값」처럼 UTF-8이 없는 항목도 가져올 수 있지만 일부 기호가 바뀔 수 있어요.",
            "쉼표·세미콜론·탭 모두 알아서 읽어요."
        ]
    )

    /// xlsx 중심판 — 시안 6-A·3-A·3-B의 xlsx 열 그대로, 3-B 3절 풋터는 PDR 6-7의 xlsx 중심판 문구. **1-e가 출시 전에 다시 검토한다**
    static let xlsx = PackCopySet.Lines(
        listIntro: "엑셀 파일로 만든 채움글 묶음(팩)을 가져와요.",
        heroTitle: "엑셀 파일 그대로 가져오기",
        heroLead: "머리글이 있는 엑셀 파일(.xlsx)을 골라요.",
        pickFile: "엑셀 파일 고르기",
        guideTitle: "엑셀로 팩 만드는 법",
        otherFileRow: PackCopySet.Row(title: "CSV 파일 가져오기", detail: "구글 시트·Numbers·메모장에서 만든 CSV도 돼요"),
        unsupportedFiles: "받지 않는 파일: Numbers 파일(.numbers), 옛 엑셀(.xls), 매크로가 든 엑셀(.xlsm·.xlsb), 비밀번호가 걸린 엑셀, .json — "
            + "엑셀에서 「Excel 통합 문서(.xlsx)」나 「CSV UTF-8」로 다시 저장해 주세요.",
        sampleFormats: [.xlsx, .csv],
        guideCellsSection: "이런 칸은 건너뛰어요",
        guideCells: [
            ["수식 → 「값만 붙여넣기」로 바꿔 주세요"],
            ["날짜로 바뀐 칸(1/2 → 1월 2일) → 그 열 서식을 「텍스트」로"],
            ["병합한 칸 → 병합을 풀어 주세요.", "숨긴 시트는 목록에 안 나와요"],
            leadingSymbolCell
        ],
        guideCellsFooter: "엑셀에서 만들었다면 xlsx로 저장해서 가져오면 숫자·날짜로 바뀐 칸을 알려 드려요. CSV로 저장하면 바뀐 값이 그대로 들어올 수 있어요.",
        guideSaveSteps: ["파일 ▸ 다른 이름으로 저장 ▸ Excel 통합 문서(.xlsx)."]
    )
}
