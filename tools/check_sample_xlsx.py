#!/usr/bin/env python3
"""샘플 xlsx 검사 — 원본 CSV와 셀 대조 · AC-29(위험 시작 글자) · AC-47(개인 정보) · 6-6 (나) 구조.

근거: PDR `docs/design-reviews/external-snippet-packs.md` 6-4·6-5·6-5b·6-6·13-1, AC-29·AC-47. 제작 기록: `sample-build-record.md`.
**독립 오라클이다** — `generate_sample_xlsx.py`의 코드를 쓰지 않고 표준 `zipfile`·`xml.etree`·`csv`로만 읽는다.
그래서 스크립트 산출물뿐 아니라 **엑셀이 다시 저장한 파일**(사장님 손 단계 뒤)도 같은 기준으로 판정한다.

검사 항목(하나라도 걸리면 exit 1):
  Z1 ZIP이 열리고 모든 엔트리 CRC 정상          Z2 엔트리 이름 유일·절대 경로·`..`·`\\` 없음·비ASCII 이름은 UTF-8 플래그
  Z3 압축 방식 stored·deflate만, 암호화·ZIP64 없음  Z4 엔트리 ≤ 200 · 파일 ≤ 3MB · 압축비 ≤ 100:1
  Z5 아카이브·엔트리 주석 없음
  X1 모든 .xml·.rels 파싱, `<!DOCTYPE`·`<!ENTITY` 0  X2 콘텐츠 타입 Override ↔ 파트 1:1(모든 파트에 타입)
  X3 관계 대상 파트가 있다                        X4 워크북 콘텐츠 타입 = sheet.main+xml(매크로 아님)
  X5 `mc:Ignorable` 접두가 루트에 선언됨           X6 sst `count`·`uniqueCount` = 실제 참조 수·항목 수
  S1 표시 시트 하나 = 기대 이름, 숨김 시트 없음      S2 병합·숨김 행/열 없음
  S3 수식 0, 셀 타입 s·inlineStr·숫자만, 셀 참조 행 = 행 번호   S4 숫자 셀은 번호 열(머리글 「번호」) 데이터 행의 정수만
  S5 셀·행·열이 쓰는 스타일의 숫자 서식 = 일반(0)·텍스트(49)만 — 날짜·숫자 서식 0 (6-4·R19)
  C1 모든 셀이 원본 CSV와 같다(빈 레코드 빼고, 끝 빈 칸 떼고, 셀 안 줄바꿈은 6-4 순서 정리 뒤 LF — `_xHHHH_` 한 번 디코드)
  A29 위험 시작 글자(`= + - @`·전각·탭·CR·LF) 셀 0 — 모든 공유 문자열 항목·인라인·숫자 셀
  A47 개인 정보 0 — 작성자·수정자(빈 값·「글쇠」만 허용)·Company·Manager 값, `absPath`, 사용자 경로(`/Users/`·`/home/`·
      `C:\\`·`\\Users\\`·`file:`), 이메일 꼴, persons·customXml·custom.xml·댓글 파트 — **모든 엔트리**(XML 아닌 것은 UTF-8·UTF-16LE 바이트)
참고(판정 아님): 열 너비·줄바꿈 열·파트 목록.

사용:
  python3 tools/check_sample_xlsx.py                                    # docs 샘플 2종(각 xlsx ↔ 같은 이름 .original.csv)
  python3 tools/check_sample_xlsx.py FILE.xlsx [--kind numbered|phrases]  # 다른 파일(엑셀 저장본 등). 종류는 파일 이름에서 추정
  python3 tools/check_sample_xlsx.py FILE.xlsx --against BASE.xlsx      # + 두 파일의 셀·스타일·열·파트 차이 보고
                                                                        #   (셀 값·종류가 다르면 exit 1, 나머지는 참고)
"""

import argparse
import csv
import io
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
import zlib
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
SAMPLES = ROOT / "docs/design/external-snippet-packs"
KINDS = {"numbered": "sample-numbered", "phrases": "sample-phrases"}

MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
REL_ID = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id"
PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"
TYPES = "{http://schemas.openxmlformats.org/package/2006/content-types}"
WORKBOOK_TYPE = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"

DANGEROUS_LEADING = set("=+-@＝＋－＠\t\r\n")
ALLOWED_NUMBER_FORMATS = {0, 49}            # 일반 · 텍스트(@)
NEUTRAL_AUTHOR = {"", "글쇠"}
PATH_PATTERN = re.compile(r"/Users/|/home/|[A-Za-z]:\\|\\Users\\|file:", re.IGNORECASE)
EMAIL_PATTERN = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}")
FORBIDDEN_PARTS = re.compile(r"^(docProps/custom\.xml|customXml/|xl/persons/|xl/comments|xl/threadedComments/)", re.IGNORECASE)
ESCAPE = re.compile(r"_x([0-9A-Fa-f]{4})_")


class Report:
    def __init__(self, label):
        self.label = label
        self.failures = []
        self.notes = []

    def check(self, code, ok, detail=""):
        if not ok:
            self.failures.append(f"{code} {detail}".rstrip())
        return ok

    def note(self, text):
        self.notes.append(text)


# MARK: - 읽기

def normalize_cell_text(text):
    """6-4 순서 계약: ① XML 파서의 줄끝 정규화(expat이 이미 했다) ② `_xHHHH_` 왼쪽부터 한 번 디코드 ③ CRLF·CR → LF"""
    decoded = ESCAPE.sub(lambda match: chr(int(match.group(1), 16)), text)
    return decoded.replace("\r\n", "\n").replace("\r", "\n")


def item_text(element):
    """`<si>`·`<is>` — `<t>` 또는 `<r><t>` 이어 붙이기, `<rPh>`(발음 힌트)는 뺀다"""
    pieces = []
    for child in element:
        if child.tag == MAIN + "t":
            pieces.append(child.text or "")
        elif child.tag == MAIN + "r":
            pieces.extend(t.text or "" for t in child.findall(MAIN + "t"))
    return "".join(pieces)


def column_index(reference):
    letters = re.match(r"[A-Z]+", reference).group(0)
    index = 0
    for letter in letters:
        index = index * 26 + ord(letter) - ord("A") + 1
    return index - 1


def is_date_format(code):
    """PDR 6-4 — 따옴표 구간·이스케이프·[…]를 뺀 뒤 날짜·시간 토큰을 본다(파서와 같은 규칙을 따로 구현)"""
    stripped = re.sub(r'"[^"]*"|\\.|_.|\*.', "", code)
    if re.search(r"\[(h+|m+|s+)\]", stripped, re.IGNORECASE):
        return True
    stripped = re.sub(r"\[[^\]]*\]", "", stripped).lower().replace("general", "")
    if "a/p" in stripped or "am/pm" in stripped:
        return True
    stripped = stripped.replace("e+", "").replace("e-", "")
    return any(token in stripped for token in "ymdhseg")


def builtin_date(number_format):
    return number_format in range(14, 23) or number_format in range(27, 37) or number_format in range(45, 48) \
        or number_format in range(50, 59) or number_format in range(71, 82)


def read_csv_records(path):
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


class Workbook:
    """검사에 필요한 만큼만 읽은 통합 문서 모형"""

    def __init__(self, path, report):
        self.path = path
        self.data = Path(path).read_bytes()
        self.archive = zipfile.ZipFile(io.BytesIO(self.data))
        self.entries = {info.filename: info for info in self.archive.infolist()}
        self.parts = {}
        for name in self.entries:
            try:
                self.parts[name] = self.archive.read(name)
            except (zipfile.BadZipFile, zlib.error) as error:
                report.check("Z1", False, f"{name} 읽기 실패: {error}")
                self.parts[name] = b""
        self.report = report
        self.xml = {}
        for name, raw in self.parts.items():
            if name.endswith((".xml", ".rels")):
                try:
                    self.xml[name] = ET.fromstring(raw)
                except ET.ParseError as error:
                    report.check("X1", False, f"{name} 파싱 실패: {error}")

    def relationships(self, source):
        directory = PurePosixPath(source).parent
        rels_name = str(directory / "_rels" / (PurePosixPath(source).name + ".rels")).lstrip("./") if source else "_rels/.rels"
        root = self.xml.get(rels_name)
        if root is None:
            return rels_name, []
        result = []
        for rel in root.findall(PKG_REL + "Relationship"):
            target = rel.get("Target", "")
            if rel.get("TargetMode") == "External":
                result.append((rel, None))
                continue
            if target.startswith("/"):
                resolved = target.lstrip("/")
            else:
                parts = []
                for piece in (directory / target).parts:
                    if piece == "..":
                        parts = parts[:-1]
                    elif piece != ".":
                        parts.append(piece)
                resolved = "/".join(parts)
            result.append((rel, resolved))
        return rels_name, result


# MARK: - 검사

def extra_ids(extra):
    """ZIP 확장 필드의 머리 번호들(0x0001 = ZIP64)"""
    ids, offset = [], 0
    while offset + 4 <= len(extra):
        ids.append(int.from_bytes(extra[offset:offset + 2], "little"))
        offset += 4 + int.from_bytes(extra[offset + 2:offset + 4], "little")
    return ids


def check_container(book, report):
    report.check("Z1", book.archive.testzip() is None, "CRC 불일치 엔트리 있음")
    names = [info.filename for info in book.archive.infolist()]
    report.check("Z2", len(names) == len(set(names)), "중복 엔트리 이름")
    for info in book.archive.infolist():
        name = info.filename
        report.check("Z2", not (name.startswith("/") or ".." in name.split("/") or "\\" in name or name == ""), f"이름 의심: {name!r}")
        report.check("Z2", name.isascii() or info.flag_bits & 0x800, f"비ASCII 이름에 UTF-8 플래그 없음: {name!r}")
        report.check("Z3", info.compress_type in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED), f"{name} 압축 방식 {info.compress_type}")
        report.check("Z3", not info.flag_bits & 0x1, f"{name} 암호화 플래그")
        report.check("Z3", info.file_size < 0xFFFFFFFF and info.compress_size < 0xFFFFFFFF and 0x0001 not in extra_ids(info.extra),
                     f"{name} ZIP64")
        if info.compress_size:
            report.check("Z4", info.file_size / info.compress_size <= 100, f"{name} 압축비 {info.file_size / info.compress_size:.1f}")
        report.check("Z5", not info.comment, f"{name} 엔트리 주석")
    report.check("Z4", len(names) <= 200, f"엔트리 {len(names)}개")
    report.check("Z4", len(book.data) <= 3 * 1024 * 1024, f"파일 {len(book.data)}B")
    report.check("Z5", not book.archive.comment, "아카이브 주석")


def check_package(book, report):
    for name, raw in book.parts.items():
        if name.endswith((".xml", ".rels")):
            report.check("X1", b"<!DOCTYPE" not in raw and b"<!ENTITY" not in raw, f"{name} DOCTYPE·ENTITY")
            root_tag = re.search(rb"<(?!\?)([^\s>/]+)([^>]*)>", raw)
            ignorable = re.search(rb'mc:Ignorable="([^"]*)"', root_tag.group(2)) if root_tag else None
            if ignorable:
                for prefix in ignorable.group(1).split():
                    report.check("X5", b"xmlns:" + prefix + b"=" in root_tag.group(2), f"{name} mc:Ignorable 접두 {prefix.decode()} 선언 없음")

    types = book.xml.get("[Content_Types].xml")
    if not report.check("X2", types is not None, "[Content_Types].xml 없음"):
        return None
    overrides = {o.get("PartName", "").lstrip("/").lower(): o.get("ContentType") for o in types.findall(TYPES + "Override")}
    defaults = {d.get("Extension", "").lower(): d.get("ContentType") for d in types.findall(TYPES + "Default")}
    lower_parts = {name.lower(): name for name in book.parts}
    for part in overrides:
        report.check("X2", part in lower_parts, f"Override가 가리키는 파트 없음: /{part}")
    for name in book.parts:
        if name == "[Content_Types].xml" or name.endswith("/"):
            continue
        # `_rels/.rels`의 확장자는 rels다(PurePosixPath.suffix는 점으로 시작하는 이름을 확장자 없음으로 본다)
        extension = PurePosixPath(name).name.rsplit(".", 1)[-1].lower() if "." in PurePosixPath(name).name else ""
        has_type = name.lower() in overrides or extension in defaults
        report.check("X2", has_type, f"콘텐츠 타입 없는 파트: {name}")

    for source in [""] + [name for name in book.parts if not name.endswith(".rels") and name != "[Content_Types].xml"]:
        rels_name, rels = book.relationships(source)
        for rel, target in rels:
            if target is not None:
                report.check("X3", target in book.parts, f"{rels_name} → {rel.get('Target')} 없음")

    _, root_rels = book.relationships("")
    documents = [target for rel, target in root_rels if rel.get("Type", "").endswith("/officeDocument")]
    if not report.check("X4", len(documents) == 1, f"officeDocument 관계 {len(documents)}개"):
        return None
    workbook_name = documents[0]
    report.check("X4", overrides.get(workbook_name.lower()) == WORKBOOK_TYPE,
                 f"워크북 콘텐츠 타입 {overrides.get(workbook_name.lower())}")
    return workbook_name


def check_privacy(book, report):
    for name, raw in book.parts.items():
        report.check("A47", not FORBIDDEN_PARTS.match(name), f"금지 파트: {name}")
        texts = [raw.decode("utf-8", "replace")]
        if not name.endswith((".xml", ".rels")):
            texts.append(raw.decode("utf-16-le", "replace"))
        for text in texts:
            report.check("A47", "abspath" not in text.lower(), f"{name}: absPath")
            path = PATH_PATTERN.search(text)
            report.check("A47", path is None, f"{name}: 사용자 경로 꼴 {path.group(0)!r}" if path else "")
            email = EMAIL_PATTERN.search(text)
            report.check("A47", email is None, f"{name}: 이메일 꼴 {email.group(0)!r}" if email else "")
        if name == "[Content_Types].xml" or name.endswith(".rels"):
            lowered = raw.decode("utf-8", "replace").lower()
            report.check("A47", "persons" not in lowered and "customxml" not in lowered, f"{name}: persons·customXml 참조")
        root = book.xml.get(name)
        if root is None:
            continue
        for element in root.iter():
            local = element.tag.rsplit("}", 1)[-1]
            value = (element.text or "").strip()
            if local in ("creator", "lastModifiedBy"):
                report.check("A47", value in NEUTRAL_AUTHOR, f"{name}: {local} = {value!r}")
            elif local in ("Company", "Manager"):
                report.check("A47", value == "", f"{name}: {local} = {value!r}")
            elif local == "author" or element.get("author"):
                report.check("A47", False, f"{name}: 작성자 {value or element.get('author')!r}")


def read_sheet(book, report, workbook_name, expected_sheet):
    """S1~S5와 셀 표 — (행 번호, [셀(kind, text)]) 목록, 셀 모형(참조 → 상세), 열 정보"""
    workbook = book.xml.get(workbook_name)
    if workbook is None:
        report.check("S1", False, "워크북 파트 없음")
        return None
    sheets = workbook.findall(f"{MAIN}sheets/{MAIN}sheet")
    visible = [s for s in sheets if s.get("state", "visible") not in ("hidden", "veryHidden")]
    report.check("S1", len(sheets) == len(visible), f"숨김 시트 {len(sheets) - len(visible)}개")
    report.check("S1", [s.get("name") for s in visible] == [expected_sheet], f"표시 시트 {[s.get('name') for s in visible]}")
    if not visible:
        return None
    _, workbook_rels = book.relationships(workbook_name)
    by_id = {rel.get("Id"): (rel, target) for rel, target in workbook_rels}
    sheet_name = by_id.get(visible[0].get(REL_ID), (None, None))[1]
    sheet = book.xml.get(sheet_name)
    if not report.check("S1", sheet is not None, f"시트 파트 없음: {sheet_name}"):
        return None

    strings = []
    raw_strings = []
    string_parts = [target for rel, target in workbook_rels if rel.get("Type", "").endswith("/sharedStrings")]
    sst = book.xml.get(string_parts[0]) if string_parts else None
    if sst is not None:
        items = sst.findall(MAIN + "si")
        raw_strings = [item_text(item) for item in items]
        strings = [normalize_cell_text(text) for text in raw_strings]

    number_formats = []
    style_parts = [target for rel, target in workbook_rels if rel.get("Type", "").endswith("/styles")]
    styles = book.xml.get(style_parts[0]) if style_parts else None
    custom_formats = {}
    wrap_styles = set()
    if styles is not None:
        for fmt in styles.findall(f"{MAIN}numFmts/{MAIN}numFmt"):
            custom_formats[int(fmt.get("numFmtId"))] = fmt.get("formatCode", "")
        for index, xf in enumerate(styles.findall(f"{MAIN}cellXfs/{MAIN}xf")):
            number_formats.append(int(xf.get("numFmtId", "0")))
            alignment = xf.find(MAIN + "alignment")
            if alignment is not None and alignment.get("wrapText") in ("1", "true"):
                wrap_styles.add(index)

    def check_style(code, where, style):
        if style is None:
            return 0
        index = int(style)
        if not report.check(code, index < max(len(number_formats), 1), f"{where}: 스타일 색인 {index} 범위 밖"):
            return None
        fmt = number_formats[index] if number_formats else 0
        date = is_date_format(custom_formats[fmt]) if fmt in custom_formats else builtin_date(fmt)
        report.check(code, not date, f"{where}: 날짜 서식(numFmtId {fmt})")
        report.check(code, fmt in ALLOWED_NUMBER_FORMATS and fmt not in custom_formats, f"{where}: 숫자 서식 numFmtId {fmt}")
        return fmt

    report.check("S2", sheet.find(MAIN + "mergeCells") is None, "병합 셀 있음")
    columns = []
    for col in sheet.findall(f"{MAIN}cols/{MAIN}col"):
        report.check("S2", col.get("hidden") not in ("1", "true"), f"숨김 열 {col.get('min')}~{col.get('max')}")
        check_style("S5", f"열 {col.get('min')}~{col.get('max')}", col.get("style"))
        columns.append((int(col.get("min")), int(col.get("max")), col.get("width"), col.get("customWidth"),
                        col.get("style") is not None and int(col.get("style")) in wrap_styles))

    rows = []
    model = {}
    string_refs = 0
    for row in sheet.findall(f"{MAIN}sheetData/{MAIN}row"):
        number = int(row.get("r"))
        report.check("S2", row.get("hidden") not in ("1", "true"), f"숨김 행 {number}")
        if row.get("customFormat") in ("1", "true"):
            check_style("S5", f"행 {number}", row.get("s"))
        cells = {}
        last = -1
        for cell in row.findall(MAIN + "c"):
            column = column_index(cell.get("r")) if cell.get("r") else last + 1
            if cell.get("r"):
                report.check("S3", re.sub(r"^[A-Z]+", "", cell.get("r")) == str(number), f"{cell.get('r')}: 행 {number} 안의 셀 참조가 다른 행")
            last = column
            reference = cell.get("r") or f"#{number}:{column}"
            kind = cell.get("t", "n")
            fmt = check_style("S5", reference, cell.get("s"))
            report.check("S3", cell.find(MAIN + "f") is None, f"{reference}: 수식")
            report.check("S3", kind in ("s", "inlineStr", "n"), f"{reference}: 셀 타입 {kind}")
            value = cell.find(MAIN + "v")
            if kind == "s":
                string_refs += 1
                index = int(value.text) if value is not None else -1
                if not report.check("S3", 0 <= index < len(strings), f"{reference}: 공유 문자열 색인 {index}"):
                    continue
                text = strings[index]
            elif kind == "inlineStr":
                inline = cell.find(MAIN + "is")
                text = normalize_cell_text(item_text(inline)) if inline is not None else ""
            else:
                text = (value.text or "").strip() if value is not None else ""
            if text == "":
                continue
            cells[column] = ("number" if kind == "n" else "text", text)
            wrap = cell.get("s") is not None and int(cell.get("s")) in wrap_styles
            model[reference] = (cells[column][0], text, fmt, wrap)
        if cells:
            width = max(cells) + 1
            rows.append((number, [cells.get(i, ("blank", "")) for i in range(width)]))

    if sst is not None:
        count, unique = sst.get("count"), sst.get("uniqueCount")
        report.check("X6", unique is None or int(unique) == len(raw_strings), f"uniqueCount {unique} ≠ 항목 {len(raw_strings)}")
        report.check("X6", count is None or int(count) == string_refs, f"count {count} ≠ 참조 {string_refs}")
    return rows, model, columns, raw_strings


def check_cells(report, rows, records, raw_strings):
    header_position = next((i for i, cells in enumerate(records) if not cells[0].startswith("#")), None)
    header = records[header_position] if header_position is not None else []
    number_column = header.index("번호") if "번호" in header else None

    for position, (number, cells) in enumerate(rows):
        for column, (kind, text) in enumerate(cells):
            if kind == "number":
                ok = column == number_column and header_position is not None and position > header_position \
                    and re.fullmatch(r"[0-9]+(\.0+)?", text) is not None
                report.check("S4", ok, f"{number}행 {column + 1}열: 번호 열 밖 숫자 셀 {text!r}")
            report.check("A29", text[:1] not in DANGEROUS_LEADING, f"{number}행 {column + 1}열: 위험 시작 글자 {text!r}")
    for index, text in enumerate(raw_strings):
        report.check("A29", normalize_cell_text(text)[:1] not in DANGEROUS_LEADING, f"공유 문자열 {index}: 위험 시작 글자 {text!r}")

    actual = [[text for _, text in cells] for _, cells in rows]
    report.check("C1", len(actual) == len(records), f"행 수 {len(actual)} ≠ CSV 레코드 {len(records)}")
    differences = 0
    for position, (got, want) in enumerate(zip(actual, records)):
        if got != want:
            differences += 1
            report.check("C1", False, f"{rows[position][0]}행: xlsx {got!r} ≠ CSV {want!r}")
    return differences


def check_file(path, kind):
    name = KINDS[kind]
    report = Report(f"{Path(path).name} ↔ {name}.original.csv")
    book = Workbook(path, report)
    check_container(book, report)
    workbook_name = check_package(book, report)
    check_privacy(book, report)
    sheet = read_sheet(book, report, workbook_name, name) if workbook_name else None
    model, columns = {}, []
    if sheet:
        rows, model, columns, raw_strings = sheet
        records = read_csv_records(SAMPLES / f"{name}.original.csv")
        check_cells(report, rows, records, raw_strings)
        cell_count = sum(1 for _, cells in rows for kind_, _ in cells if kind_ != "blank")
        report.note(f"행 {len(rows)} · 셀 {cell_count} · 공유 문자열 {len(raw_strings)} · 숫자 셀 "
                    f"{sum(1 for v in model.values() if v[0] == 'number')}")
    report.note("열 " + ", ".join(f"{lo}{'' if lo == hi else f'~{hi}'}: 너비 {width}{' 줄바꿈' if wrap else ''}"
                                  for lo, hi, width, _, wrap in columns))
    report.note("파트 " + ", ".join(book.parts))
    return report, book, model, columns


def compare(path, base_path, kind, model, columns):
    """사장님 손 단계(엑셀 열기·저장) 뒤 파일 ↔ 스크립트 산출물 — 셀 값·종류는 계약, 나머지는 참고"""
    _, base_book, base_model, base_columns = check_file(base_path, kind)
    book = zipfile.ZipFile(path)
    contract = []
    info = []
    for reference in sorted(set(model) | set(base_model), key=lambda r: (int(re.sub(r"\D", "", r) or 0), r)):
        got, want = model.get(reference), base_model.get(reference)
        if got is None or want is None or got[:2] != want[:2]:
            contract.append(f"셀 {reference}: {want[:2] if want else None} → {got[:2] if got else None}")
        elif got[2:] != want[2:]:
            info.append(f"셀 {reference} 서식: numFmt·줄바꿈 {want[2:]} → {got[2:]}")
    if columns != base_columns:
        info.append(f"열: {[(c[0], c[2], c[4]) for c in base_columns]} → {[(c[0], c[2], c[4]) for c in columns]}")
    added = sorted(set(book.namelist()) - set(base_book.parts))
    removed = sorted(set(base_book.parts) - set(book.namelist()))
    if added:
        info.append(f"추가된 파트: {', '.join(added)}")
    if removed:
        info.append(f"빠진 파트: {', '.join(removed)}")
    return contract, info


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("files", nargs="*", type=Path, help="검사할 xlsx(기본: docs 샘플 2종)")
    parser.add_argument("--kind", choices=sorted(KINDS), help="샘플 종류(기본: 파일 이름에서 추정)")
    parser.add_argument("--against", type=Path, help="비교 기준 xlsx(스크립트 산출물) — 차이 보고")
    args = parser.parse_args()

    files = args.files or [SAMPLES / f"{name}.xlsx" for name in KINDS.values()]
    failed = False
    for path in files:
        kind = args.kind or next((k for k in KINDS if k in path.name), None)
        if kind is None:
            sys.exit(f"{path.name}: 종류를 알 수 없다 — --kind numbered|phrases")
        report, _, model, columns = check_file(path, kind)
        print(f"== {report.label}")
        for note in report.notes:
            print(f"   {note}")
        if report.failures:
            failed = True
            for failure in report.failures:
                print(f"   실패 {failure}")
        else:
            print("   통과 Z1~Z5 X1~X6 S1~S5 C1(셀 차이 0) A29(위험 시작 글자 0) A47(개인 정보 0)")
        if args.against:
            contract, info = compare(path, args.against, kind, model, columns)
            print(f"   -- 차이 ↔ {args.against.name}")
            for line in contract:
                print(f"   계약 위반 {line}")
            for line in info:
                print(f"   참고 {line}")
            if not contract:
                print("   셀 값·종류 같음")
            failed = failed or bool(contract)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
