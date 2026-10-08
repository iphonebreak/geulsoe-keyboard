#!/usr/bin/env python3
"""고정 샘플 CSV(`sample-*.original.csv`) → 샘플 xlsx 2종(번호형·문구형) 생성.

근거: PDR `docs/design-reviews/external-snippet-packs.md` 6-6(샘플·제작 경로)·6-4(셀 정책)·13-1(R5)·AC-29·AC-47, R27(「출처」).
제작 기록: `docs/design/external-snippet-packs/sample-build-record.md` — 다시 만들면 기록의 해시도 고친다.
검사(따로 만든 오라클): `python3 tools/check_sample_xlsx.py` — 셀 대조·AC-29·AC-47·구조.

무엇을 만드나 (파이썬 표준 라이브러리만 — zipfile·csv·unicodedata):
  - 셀 = 원본 CSV와 **셀 단위로 같다**. 셀 안 줄바꿈은 LF(6-4 정리 순서 뒤의 값 — CSV의 CRLF를 LF로).
  - 행 자리 = 정보 줄 묶음(1행부터) · **빈 행 하나** · 머리글 · 데이터(사장님 실기 2026-10-08). xlsx는 빈 행을 담지 않으므로
    행 번호만 하나 띄운다(파서는 빈 레코드를 어디서든 무시한다). 정보 줄이 없으면 1행부터 빈 행 없이.
  - **굵게** = 정보 줄 키 칸(A열 `#이름`·`#틀`·`#출처`)과 머리글 칸만 — 글꼴 bold 하나. 숫자 서식은 모두 일반(numFmtId 0).
  - **표 테두리** = 머리글 행부터 마지막 데이터 행까지 × 머리글 열의 **모든 칸** 네 변 가는 실선(thin, 자동 색 — 엑셀이 쓰는 색인 64).
    빈 칸도 서식만 있는 `<c r s/>`로 써서 선을 잇는다. 정보 줄·빈 행에는 선 없음. **머리글 채우기** = 머리글 칸만 단색 `FFD9D9D9`
    (엑셀 「흰색, 배경 1, 15% 더 어둡게」 — 테마 파트가 없으므로 rgb로). 열 기본 스타일에는 선·채우기를 넣지 않는다(새로 친 칸으로 번지지 않게)
    — 실기 피드백 3(2026-10-08).
  - 번호 열(머리글 「번호」)의 정수만 숫자 셀(엑셀이 CSV를 열 때처럼, 일반 서식). 나머지는 전부 공유 문자열.
    수식·날짜 서식·불리언·숫자 서식 칸은 만들지 않는다(6-4·R19). 병합·숨김 없음.
  - 열 너비 = 글자 길이에 맞춤(`<col width customWidth>`). 한글 등 넓은 글자(동아시아 W·F·A)는 2칸으로 센다.
    본문 열(마지막 열)은 넓게 + 줄바꿈 표시(`wrapText`), 상한 BODY_WIDTH_CAP칸. 오른쪽 칸이 비어 넘쳐 보이는
    셀(정보 줄의 값)은 너비 계산에서 뺀다 — 맞추면 제목 열이 쓸데없이 넓어진다.
  - 세로 가운데 맞춤 — 한국어 엑셀 기본 스타일(표준)과 같다(이전 엑셀 저장본의 styles.xml에서 확인).
  - 문서 속성 파트(`docProps/*`)·테마·작성자·경로 없음(AC-47). 시트 이름 = 파일 이름 줄기(`sample-numbered`).
  - ZIP: 엔트리 순서·이름은 엑셀과 같은 꼴, deflate, 날짜 1980-01-01 00:00 고정, 외부 속성 0, 데이터 디스크립터·ZIP64 없음.
    같은 입력 + 같은 zlib이면 바이트가 같다(SHA-256 재현). zlib이 다르면 압축 바이트만 다를 수 있다 — 그때는
    `--check`가 파트 내용(해제 결과)으로 다시 비교한다.

사용:
  python3 tools/generate_sample_xlsx.py            # docs/design/external-snippet-packs/sample-*.xlsx 를 다시 쓴다
  python3 tools/generate_sample_xlsx.py --out DIR  # 다른 폴더에 쓴다(원본 자리는 건드리지 않는다)
  python3 tools/generate_sample_xlsx.py --check    # 쓰지 않고 재생성 결과를 기존 파일과 비교. 다르면 exit 1
"""

import argparse
import csv
import hashlib
import io
import re
import sys
import unicodedata
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "docs/design/external-snippet-packs"
NAMES = ("sample-numbered", "sample-phrases")

# 열 너비(엑셀 「문자 수」 단위) — 넓은 글자 2칸 기준
BODY_WIDTH_CAP = 80     # 본문 열 상한 — 번호형 본문 최장 75칸이 한 줄에 들어간다
WIDTH_PADDING = 2       # 칸 여백(양옆 1칸씩)
WIDTH_MIN = 6
MAX_DIGIT_WIDTH_PX = 7  # 엑셀 너비 공식의 「최대 숫자 폭」(px) — 기본 글꼴 11pt 근사

# AC-29 — 스프레드시트가 수식·명령으로 읽을 수 있는 시작 글자(PDR 13-1, PackSampleTests와 같은 집합)
DANGEROUS_LEADING = set("=+-@＝＋－＠\t\r\n")

NS_MAIN = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
NS_REL = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
NS_PKG_REL = "http://schemas.openxmlformats.org/package/2006/relationships"
NS_TYPES = "http://schemas.openxmlformats.org/package/2006/content-types"
DECLARATION = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\r\n'

# XML 1.0에서 쓸 수 없는 글자(탭·LF·CR 제외 제어 문자, 서로게이트, U+FFFE·U+FFFF)
INVALID_XML = re.compile("[\x00-\x08\x0b\x0c\x0e-\x1f\ud800-\udfff￾￿]")


def fail(message):
    sys.exit(f"generate_sample_xlsx: {message}")


def read_records(path):
    """CSV 논리 레코드 — 빈 레코드는 뺀다, 끝 빈 칸은 뗀다, 셀 안 CRLF·CR → LF(6-4)"""
    with open(path, encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.reader(handle))
    records = []
    for row in rows:
        cells = [cell.replace("\r\n", "\n").replace("\r", "\n") for cell in row]
        while cells and cells[-1] == "":
            cells.pop()
        if cells:
            records.append(cells)
    return records


def display_units(text):
    """가장 긴 줄의 표시 폭 — 동아시아 넓은 글자(W·F)와 모호 글자(A — 한국어 글꼴에서 넓게 그린다)는 2칸"""
    return max((sum(2 if unicodedata.east_asian_width(ch) in "WFA" else 1 for ch in line)
                for line in text.split("\n")), default=0)


def excel_width(chars):
    """엑셀 열 너비 공식 — Truncate([문자 수 × 최대 숫자 폭 + 5px] / 최대 숫자 폭 × 256) / 256"""
    return int((chars * MAX_DIGIT_WIDTH_PX + 5) / MAX_DIGIT_WIDTH_PX * 256) / 256


def column_letter(index):
    letters = ""
    index += 1
    while index:
        index, rest = divmod(index - 1, 26)
        letters = chr(ord("A") + rest) + letters
    return letters


def escape(text):
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def escape_shared(text):
    """공유 문자열 — 글자 그대로의 `_xHHHH_`는 엑셀처럼 `_x005F_`로 감싼다(읽는 쪽이 한 번 디코드한다 — 6-4)"""
    return escape(re.sub(r"_(?=x[0-9A-Fa-f]{4}_)", "_x005F_", text))


def escape_attribute(text):
    return escape(text).replace('"', "&quot;")


def check_cell(name, row_number, text):
    if INVALID_XML.search(text):
        fail(f"{name} {row_number}행: XML에 쓸 수 없는 글자 — {text!r}")
    if text[:1] in DANGEROUS_LEADING:
        fail(f"{name} {row_number}행: 위험 시작 글자(AC-29) — {text!r}")


def build_parts(name, records):
    """엔트리 이름 → XML 바이트(엑셀과 같은 엔트리 순서)"""
    header_index = next((i for i, cells in enumerate(records) if not cells[0].startswith("#")), None)
    if header_index is None:
        fail(f"{name}: 머리글 줄이 없다")
    header = records[header_index]
    number_column = header.index("번호") if "번호" in header else None
    column_count = max(len(cells) for cells in records)
    body_column = column_count - 1
    table_width = len(header)           # 표 영역의 열 = 머리글 열
    if body_column == 0:
        fail(f"{name}: 열이 하나뿐이다 — 정보 줄 키 칸과 본문 열이 겹친다")
    gap = 1 if header_index else 0      # 정보 줄 묶음과 머리글 사이 빈 행(정보 줄이 있을 때만)

    def style_of(index, column):
        """스타일 색인(아래 cellXfs) — 표 칸(머리글·데이터)은 테두리, 머리글은 + 굵게·채우기, 정보 줄 키 칸은 굵게만. 본문 열은 + 줄바꿈"""
        wrap = 1 if column == body_column else 0
        if index >= header_index and column < table_width:
            return (5 if index == header_index else 3) + wrap
        return 2 if index < header_index and column == 0 else wrap

    # 공유 문자열(처음 나온 순서, 중복 제거 — 엑셀과 같다)과 셀
    strings, string_index, string_refs = [], {}, 0
    rows_xml = []
    for index, cells in enumerate(records):
        row_number = index + 1 + (gap if index >= header_index else 0)
        cells_xml = []
        span = max(len(cells), table_width) if index >= header_index else len(cells)
        for column in range(span):
            text = cells[column] if column < len(cells) else ""
            reference = f"{column_letter(column)}{row_number}"
            style_index = style_of(index, column)
            style = f' s="{style_index}"' if style_index else ""
            if text == "":
                if index >= header_index and column < table_width:
                    cells_xml.append(f'<c r="{reference}"{style}/>')     # 값 없이 서식만 — 표 테두리를 잇는다
                continue
            check_cell(name, row_number, text)
            if column == number_column and index > header_index and re.fullmatch(r"[0-9]+", text):
                cells_xml.append(f'<c r="{reference}"{style}><v>{int(text)}</v></c>')
                continue
            if text not in string_index:
                string_index[text] = len(strings)
                strings.append(text)
            string_refs += 1
            cells_xml.append(f'<c r="{reference}"{style} t="s"><v>{string_index[text]}</v></c>')
        rows_xml.append(f'<row r="{row_number}">{"".join(cells_xml)}</row>')

    # 열 너비 — 셀이 그 열 안에 들어가야 하는 경우만 센다(본문 열은 줄바꿈이라 늘 센다).
    # 오른쪽 칸이 비어 있으면 엑셀이 글을 옆으로 넘겨 보여 주므로(정보 줄의 값) 세지 않는다
    fit = [0] * column_count
    for cells in records:
        for column, text in enumerate(cells):
            neighbour_empty = column + 1 >= len(cells) or cells[column + 1] == ""
            if text and (column == body_column or not neighbour_empty):
                fit[column] = max(fit[column], display_units(text))
    fit[body_column] = min(fit[body_column], BODY_WIDTH_CAP)
    cols_xml = []
    for column, units in enumerate(fit):
        width = excel_width(max(units + WIDTH_PADDING, WIDTH_MIN))
        style = ' style="1"' if column == body_column else ""
        cols_xml.append(f'<col min="{column + 1}" max="{column + 1}" width="{width!r}"{style} customWidth="1"/>')

    last_reference = f"{column_letter(column_count - 1)}{len(records) + gap}"
    sheet = (f'{DECLARATION}<worksheet xmlns="{NS_MAIN}" xmlns:r="{NS_REL}">'
             f'<dimension ref="A1:{last_reference}"/>'
             '<sheetViews><sheetView tabSelected="1" workbookViewId="0"/></sheetViews>'
             f'<cols>{"".join(cols_xml)}</cols>'
             f'<sheetData>{"".join(rows_xml)}</sheetData>'
             '</worksheet>')

    def shared_item(text):
        # 앞뒤 공백·줄바꿈·탭이 있으면 보존 표시(엑셀과 같다)
        preserve = ' xml:space="preserve"' if text != text.strip() or "\n" in text or "\t" in text else ""
        return f"<si><t{preserve}>{escape_shared(text)}</t></si>"

    shared_strings = (f'{DECLARATION}<sst xmlns="{NS_MAIN}" count="{string_refs}" uniqueCount="{len(strings)}">'
                      f'{"".join(shared_item(text) for text in strings)}</sst>')

    # 스타일 — 0: 표준(세로 가운데), 1: 표준 + 줄바꿈(본문 열), 2: 굵게(정보 줄 키 칸),
    # 3: 표 칸(테두리), 4: 표 칸 + 줄바꿈, 5: 머리글(굵게·채우기·테두리), 6: 머리글 + 줄바꿈(본문 열의 머리글 칸).
    # 모두 일반 서식(numFmtId 0) — 날짜·숫자 서식 없음. 글꼴 1 = 글꼴 0 + 굵게. 채우기 0·1은 엑셀이 늘 두는 자리(none·gray125),
    # 채우기 2 = 단색 연한 회색. 테두리 1 = 네 변 가는 실선 · 자동 색(색인 64 — 엑셀이 「자동」으로 쓰는 값)
    font = '<sz val="11"/><name val="맑은 고딕"/><family val="2"/><charset val="129"/>'
    thin = '<color indexed="64"/>'
    middle = '<alignment vertical="center"/>'
    wrapped = '<alignment vertical="center" wrapText="1"/>'

    def xf(font_id, fill_id, border_id, alignment, applies):
        flags = "".join(f' apply{kind}="1"' for kind in applies)
        return f'<xf numFmtId="0" fontId="{font_id}" fillId="{fill_id}" borderId="{border_id}" xfId="0"{flags}>{alignment}</xf>'

    cell_xfs = [
        xf(0, 0, 0, middle, ()),
        xf(0, 0, 0, wrapped, ("Alignment",)),
        xf(1, 0, 0, middle, ("Font",)),
        xf(0, 0, 1, middle, ("Border",)),
        xf(0, 0, 1, wrapped, ("Border", "Alignment")),
        xf(1, 2, 1, middle, ("Font", "Fill", "Border")),
        xf(1, 2, 1, wrapped, ("Font", "Fill", "Border", "Alignment")),
    ]
    styles = (f'{DECLARATION}<styleSheet xmlns="{NS_MAIN}">'
              f'<fonts count="2"><font>{font}</font><font><b/>{font}</font></fonts>'
              '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
              '<fill><patternFill patternType="solid"><fgColor rgb="FFD9D9D9"/><bgColor indexed="64"/></patternFill></fill></fills>'
              '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>'
              f'<border><left style="thin">{thin}</left><right style="thin">{thin}</right><top style="thin">{thin}</top>'
              f'<bottom style="thin">{thin}</bottom><diagonal/></border></borders>'
              f'<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0">{middle}</xf></cellStyleXfs>'
              f'<cellXfs count="{len(cell_xfs)}">{"".join(cell_xfs)}</cellXfs>'
              '<cellStyles count="1"><cellStyle name="표준" xfId="0" builtinId="0"/></cellStyles>'
              '</styleSheet>')

    workbook = (f'{DECLARATION}<workbook xmlns="{NS_MAIN}" xmlns:r="{NS_REL}">'
                '<bookViews><workbookView/></bookViews>'
                f'<sheets><sheet name="{escape_attribute(name)}" sheetId="1" r:id="rId1"/></sheets>'
                '</workbook>')

    def relationship(rid, kind, target):
        base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        return f'<Relationship Id="{rid}" Type="{base}/{kind}" Target="{target}"/>'

    root_rels = (f'{DECLARATION}<Relationships xmlns="{NS_PKG_REL}">'
                 f'{relationship("rId1", "officeDocument", "xl/workbook.xml")}</Relationships>')
    workbook_rels = (f'{DECLARATION}<Relationships xmlns="{NS_PKG_REL}">'
                     f'{relationship("rId1", "worksheet", "worksheets/sheet1.xml")}'
                     f'{relationship("rId2", "styles", "styles.xml")}'
                     f'{relationship("rId3", "sharedStrings", "sharedStrings.xml")}</Relationships>')

    ml = "application/vnd.openxmlformats-officedocument.spreadsheetml"
    content_types = (f'{DECLARATION}<Types xmlns="{NS_TYPES}">'
                     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
                     '<Default Extension="xml" ContentType="application/xml"/>'
                     f'<Override PartName="/xl/workbook.xml" ContentType="{ml}.sheet.main+xml"/>'
                     f'<Override PartName="/xl/worksheets/sheet1.xml" ContentType="{ml}.worksheet+xml"/>'
                     f'<Override PartName="/xl/styles.xml" ContentType="{ml}.styles+xml"/>'
                     f'<Override PartName="/xl/sharedStrings.xml" ContentType="{ml}.sharedStrings+xml"/>'
                     '</Types>')

    return [
        ("[Content_Types].xml", content_types),
        ("_rels/.rels", root_rels),
        ("xl/workbook.xml", workbook),
        ("xl/_rels/workbook.xml.rels", workbook_rels),
        ("xl/worksheets/sheet1.xml", sheet),
        ("xl/styles.xml", styles),
        ("xl/sharedStrings.xml", shared_strings),
    ]


def build_xlsx(name, records):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for entry, text in build_parts(name, records):
            info = zipfile.ZipInfo(entry, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 0      # MS-DOS — 실행 환경과 상관없이 같은 바이트
            info.external_attr = 0
            archive.writestr(info, text.encode("utf-8"))
    return buffer.getvalue()


def parts_of(data):
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        return [(info.filename, archive.read(info)) for info in archive.infolist()]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", type=Path, help="쓸 폴더(기본: 원본 CSV 옆 — docs/design/external-snippet-packs)")
    parser.add_argument("--check", action="store_true", help="쓰지 않고 기존 파일과 비교(다르면 exit 1)")
    args = parser.parse_args()

    out_dir = args.out or SAMPLES
    mismatch = False
    for name in NAMES:
        source = SAMPLES / f"{name}.original.csv"
        data = build_xlsx(name, read_records(source))
        target = out_dir / f"{name}.xlsx"
        digest = hashlib.sha256(data).hexdigest()
        if args.check:
            existing = target.read_bytes() if target.exists() else b""
            if existing == data:
                print(f"같음  {target.name}  {digest}")
            elif existing and parts_of(existing) == parts_of(data):
                print(f"파트 같음(압축 바이트만 다름 — zlib 차이)  {target.name}")
            else:
                print(f"다름  {target.name}")
                mismatch = True
            continue
        out_dir.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        print(f"{target.relative_to(ROOT) if target.is_relative_to(ROOT) else target}  {len(data)}B  sha256 {digest}")
        print(f"  입력 {source.name}  sha256 {hashlib.sha256(source.read_bytes()).hexdigest()}")
    if mismatch:
        sys.exit(1)


if __name__ == "__main__":
    main()
