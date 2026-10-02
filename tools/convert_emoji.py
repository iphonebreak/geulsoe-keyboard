#!/usr/bin/env python3
"""CLDR 한국어 이모지 주석 → emoji.tde (한글 단어 → 이모지 역색인) 변환.

원본: Unicode CLDR `common/annotations/ko.xml` + `common/annotationsDerived/ko.xml`
      — 안정판 release-48-2를 **커밋 해시로 고정**하고 입력 SHA-256을 검증한다(바뀌면 실패).
      라이선스 Unicode License v3 (SPDX Unicode-3.0) — 고지: Resources/LICENSE-emoji.md
필터: Unicode 15.0 `emoji-data.txt` — iOS 17.0이 그리는 이모지 기준선. `EmojiCatalog.isCatalogued`와
      같은 조건(Emoji_Presentation이고 피부색·머리색·지역 표시자가 아닌 단일 스칼라)을 **최소 OS의
      유니코드 버전으로** 평가한다. 텍스트 기본 이모지(❤ 등 VS16 필요)는 빠진다(PDR D5).
근거·수치·변환 규칙: docs/design-reviews/emoji-data-import.md, emoji-word-suggestion.md 2절

역색인: keyword(`|` 분할·trim)와 tts를 모두 키로 삼고, (키, 이모지) 중복은 제거, 값은 XML 파일
순서(annotations → annotationsDerived)를 지킨다. 키는 한글 음절 2~12자(`^[가-힣]{2,12}$`)만.
**파일 순서는 대표성과 무관하다**(코드포인트 순 — 「자동차」의 첫 값은 🚕) — 대표 이모지는
런타임이 손질 목록 > tts 완전 일치 > 검토한 대체로 고른다(KeyboardCore `RepresentativeEmojiResolver`).

포맷 (리틀엔디언) — BundledEmojiAnnotationIndex가 mmap으로 읽는다:
  헤더   16B : magic 'TDEM' | version u32 | 키 수 u32 | 블롭 시작 u32
  엔트리 16B × N : keyOffset u32 | keyLen u16 | valuesLen u16 | valuesOffset u32
                   | nameMatch u16 | emojiCount u16
                   (키 UTF-8 바이트 순 정렬, 오프셋은 블롭 시작 기준.
                    nameMatch = tts가 키와 같은 이모지의 1-기반 순번, 0 = 없음)
  블롭   : 키 UTF-8 + 값(이모지 UTF-8을 U+001F로 이은 것) 연속

사용:
  python3 tools/convert_emoji.py                     # 받기(캐시)·검증·생성 + 손질 목록 검사
  python3 tools/convert_emoji.py --stats [--ref main-396355a] [--host-catalog FILE]
                                                     # 반론자2 실측 재현표 출력(파일 쓰지 않음)
  python3 tools/convert_emoji.py --curation-csv PATH [--top 300]
                                                     # words.tdw × CLDR 손질 후보표
입력 원본은 tools/data/cldr/<커밋>/에 캐시한다(저장소에 넣지 않는다 — 고정 URL + 해시로 재현).
"""

import argparse
import csv
import hashlib
import json
import re
import struct
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = Path(__file__).resolve().parent / "data/cldr"
RESOURCES = ROOT / "Packages/TadakData/Sources/TadakData/Resources"
OUTPUT = RESOURCES / "emoji.tde"
CURATION = RESOURCES / "EmojiCuration.json"
WORDS = RESOURCES / "words.tdw"

VERSION = 1
KEY_PATTERN = re.compile(r"^[가-힣]{2,12}$")
SEPARATOR = "\x1f"

# 고정 입력 — 커밋 해시는 불변이다. 태그나 main을 매번 읽지 않는다(안정판과 main은 키 95개가 다르다).
CLDR_REFS = {
    # 제품 데이터. 조사 시점(2026-10-02) 최신 안정판 — release-48-2 태그(태그 객체 fc1fd058…)가 가리키는 커밋
    "release-48-2": {
        "commit": "11299982335beb974c1c63c45265184e759c0f41",
        "files": {
            "common/annotations/ko.xml":
                "1d7007de84c0431f892b3f8c87b24835c8f8474a1711a2406592aaf24f5db72d",
            "common/annotationsDerived/ko.xml":
                "c624e7369d0b283c9f7085360157b7f5f701260b36e4e5ff3f9552ce196dbbb8",
            "LICENSE":
                "b49d0e9f8ead51ca8b7df6fec89cc3ae6809198b4b9d43c74216da0118f23f5b",
        },
    },
    # 재현 전용 — 반론자2가 PDR 2-2절 수치를 잰 개발본(main, 2026-09-28). --stats로만 쓴다
    "main-396355a": {
        "commit": "396355a8aa317fade56f3a35914d4ea48031a85b",
        "files": {
            "common/annotations/ko.xml":
                "19b38845e0b4deed4153a710f84f523b733a689541b617d2ca8fcbaba970e6d0",
            "common/annotationsDerived/ko.xml":
                "f03e72542e5178babfa085aeabda6e33f88191a41164c7806ebf6e07701d392c",
            "LICENSE":
                "65eb33419e22a297550a811b5b535f5e532f9a7e0114b516c0ea18afd53c3804",
        },
    },
}
PRODUCT_REF = "release-48-2"
CLDR_RAW = "https://raw.githubusercontent.com/unicode-org/cldr/{commit}/{path}"

EMOJI_DATA_URL = "https://www.unicode.org/Public/15.0.0/ucd/emoji/emoji-data.txt"
EMOJI_DATA_SHA256 = "29071dba22c72c27783a73016afb8ffaeb025866740791f9c2d0b55cc45a3470"

# EmojiCatalog.sweepRange·isExcluded 복제 — 카탈로그와 같은 조건이어야 추천 이모지가 이모지 판에도 있다
SWEEP_RANGE = range(0x2000, 0x1FAFF + 1)
HAIR_COMPONENTS = range(0x1F9B0, 0x1F9B3 + 1)
REGIONAL_INDICATORS = range(0x1F1E6, 0x1F1FF + 1)


def fetch(url: str, path: Path, sha256: str) -> bytes:
    """캐시에 있으면 그것을, 없으면 받아서 — 어느 쪽이든 해시가 다르면 실패한다.
    받은 파일은 해시가 맞을 때만 캐시에 들인다(중단된 다운로드가 캐시에 남지 않게)."""
    if path.exists():
        data = path.read_bytes()
    else:
        path.parent.mkdir(parents=True, exist_ok=True)
        part = path.with_name(path.name + ".part")
        # python.org 배포판 urllib은 macOS 루트 인증서를 못 찾는다 — 시스템 curl을 쓴다
        subprocess.run(["curl", "-fsSL", "-o", str(part), url], check=True)
        data = part.read_bytes()
        if hashlib.sha256(data).hexdigest() == sha256:
            part.rename(path)
        else:
            part.unlink()
    actual = hashlib.sha256(data).hexdigest()
    if actual != sha256:
        sys.exit(f"SHA-256 불일치: {url}\n  기대 {sha256}\n  실제 {actual}\n"
                 "원본이 바뀌었다 — 고정값을 갱신하기 전에 차이를 검토하라")
    return data


def load_cldr(ref: str) -> tuple[list[tuple[str, bytes]], bytes]:
    spec = CLDR_REFS[ref]
    xmls = []
    license_text = b""
    for path, sha in spec["files"].items():
        local = CACHE / spec["commit"] / path.replace("/", "_")
        data = fetch(CLDR_RAW.format(commit=spec["commit"], path=path), local, sha)
        if path == "LICENSE":
            license_text = data
        else:
            xmls.append((path, data))
    return xmls, license_text


def parse_annotations(xmls: list[tuple[str, bytes]]) -> list[tuple[str, str, str]]:
    """(cp, 'keyword'|'tts', 키) 레코드를 파일 순서대로."""
    records = []
    for _, data in xmls:
        for node in ET.fromstring(data).iter("annotation"):
            cp, text = node.get("cp"), (node.text or "")
            if node.get("type") == "tts":
                records.append((cp, "tts", text.strip()))
            else:
                records += [(cp, "keyword", part.strip()) for part in text.split("|")
                            if part.strip()]
    return records


def unicode15_catalog() -> set[str]:
    """Unicode 15.0 기준 카탈로그 — EmojiCatalog.isCatalogued를 iOS 17.0의 유니코드 버전으로."""
    text = fetch(EMOJI_DATA_URL, CACHE / "emoji-data-15.0.txt", EMOJI_DATA_SHA256).decode()
    props: dict[str, set[int]] = {"Emoji_Presentation": set(), "Emoji_Modifier": set()}
    for line in text.splitlines():
        body = line.split("#", 1)[0].strip()
        if not body:
            continue
        span, prop = (part.strip() for part in body.split(";"))
        if prop not in props:
            continue
        first, _, last = span.partition("..")
        props[prop].update(range(int(first, 16), int(last or first, 16) + 1))
    return {chr(v) for v in props["Emoji_Presentation"]
            if v in SWEEP_RANGE and v not in props["Emoji_Modifier"]
            and v not in HAIR_COMPONENTS and v not in REGIONAL_INDICATORS}


def build_index(records, emojis=None, korean_only=False, include_tts=True, first_only=False):
    """키 → 이모지 목록(파일 순서, 중복 제거)과 키 → 이름(tts) 일치 이모지."""
    index: dict[str, list[str]] = {}
    name_match: dict[str, str] = {}
    for cp, kind, key in records:
        if kind == "tts" and not include_tts:
            continue
        if emojis is not None and cp not in emojis:
            continue
        if korean_only and not KEY_PATTERN.match(key):
            continue
        values = index.setdefault(key, [])
        if cp not in values:
            values.append(cp)
        if kind == "tts":
            if key in name_match and name_match[key] != cp:
                sys.exit(f"tts 이름 충돌: {key} → {name_match[key]}, {cp}")
            name_match[key] = cp
    if first_only:
        index = {key: values[:1] for key, values in index.items()}
    return index, name_match


def json_size(index) -> int:
    return len(json.dumps(index, ensure_ascii=False, separators=(",", ":"),
                          sort_keys=True).encode("utf-8"))


def encode(index, name_match) -> bytes:
    entries = sorted(index.items(), key=lambda item: item[0].encode("utf-8"))
    table = bytearray()
    blob = bytearray()
    for key, values in entries:
        key_bytes = key.encode("utf-8")
        value_bytes = SEPARATOR.join(values).encode("utf-8")
        if len(key_bytes) >= 1 << 16 or len(value_bytes) >= 1 << 16 or len(values) >= 1 << 16:
            sys.exit(f"길이 초과: {key}")
        match = name_match.get(key)
        table += struct.pack("<IHHIHH", len(blob), len(key_bytes), len(value_bytes),
                             len(blob) + len(key_bytes),
                             values.index(match) + 1 if match in values else 0, len(values))
        blob += key_bytes + value_bytes
    header = struct.pack("<4sIII", b"TDEM", VERSION, len(entries), 16 + len(table))
    return header + bytes(table) + bytes(blob)


def check_curation(catalog: set[str]) -> int:
    """손질 목록 검사 — 키는 역색인과 같은 꼴, 값은 빈 문자열(띄우지 않음) 또는 iOS 17 카탈로그 이모지."""
    if not CURATION.exists():
        return 0
    data = json.loads(CURATION.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or set(data) - {"override", "fallback"}:
        sys.exit(f"손질 목록 형식 오류: 최상위는 override·fallback 객체만 — {CURATION}")
    count = 0
    for section in ("override", "fallback"):
        for word, emoji in data.get(section, {}).items():
            if not KEY_PATTERN.match(word):
                sys.exit(f"손질 목록 {section}: 키는 한글 2~12자 — {word!r}")
            if emoji != "" and emoji not in catalog:
                sys.exit(f"손질 목록 {section}: {word} → {emoji!r} — Unicode 15.0 카탈로그 밖"
                         "(iOS 17에서 안 그려지거나 텍스트 기본 이모지)")
            count += 1
    return count


def read_words() -> list[tuple[str, int]]:
    """words.tdw → (단어, 빈도), 빈도 내림차순·동률은 단어 오름차순 (convert_words.py 포맷)."""
    data = WORDS.read_bytes()
    magic, version, count, blob_start = struct.unpack_from("<4sIII", data, 0)
    if magic != b"TDWD" or version != 1:
        sys.exit(f"words.tdw 형식 오류: {magic!r} v{version}")
    words = []
    for i in range(count):
        _, _, word_len, word_offset, freq = struct.unpack_from("<IHHII", data, 16 + i * 16)
        start = blob_start + word_offset
        words.append((data[start:start + word_len].decode("utf-8"), freq))
    words.sort(key=lambda item: (-item[1], item[0]))
    return words


def product_index():
    xmls, _ = load_cldr(PRODUCT_REF)
    catalog = unicode15_catalog()
    index, name_match = build_index(parse_annotations(xmls), emojis=catalog, korean_only=True)
    return index, name_match, catalog


def generate() -> None:
    index, name_match, catalog = product_index()
    output = encode(index, name_match)

    # 표본 대조 — 대표 이모지 규칙의 전제(파일 첫 값 ≠ 이름 일치)가 데이터에 살아 있는가
    assert index["자동차"][0] == "🚕" and name_match["자동차"] == "🚗"
    assert name_match["고양이"] == "🐈" and name_match["선물"] == "🎁"
    # 「맥주」는 PDR 2-3절 표와 달리 tts 일치가 있다(🍻 tts = 맥주) — 이름 일치 없는 표본은 「사과」
    assert name_match["사람"] == "🧑" and "사과" not in name_match
    assert "자동차는" not in index
    if not 2_000 <= len(index) <= 4_000:
        sys.exit(f"키 수가 예상 범위를 벗어남: {len(index)}")

    curated = check_curation(catalog)
    OUTPUT.write_bytes(output)
    links = sum(len(values) for values in index.values())
    print(f"완료: {OUTPUT.relative_to(ROOT)} — {PRODUCT_REF}({CLDR_REFS[PRODUCT_REF]['commit'][:9]}), "
          f"Unicode 15.0 카탈로그 {len(catalog)}개, 키 {len(index)}, 연결 {links}, "
          f"이름 일치 {len(name_match)}, {len(output):,}B")
    print(f"손질 목록 검사 통과: {CURATION.name} {curated}항목")


def print_stats(ref: str, host_catalog: Path | None) -> None:
    xmls, _ = load_cldr(ref)
    records = parse_annotations(xmls)
    print(f"# {ref} — {CLDR_REFS[ref]['commit']}")
    print("\n## 입력 파일 (UTF-8 바이트 · 고유 cp · keyword 행 · tts 행)")
    for path, data in xmls:
        nodes = list(ET.fromstring(data).iter("annotation"))
        tts = sum(1 for n in nodes if n.get("type") == "tts")
        print(f"{path}: {len(data):,} · {len({n.get('cp') for n in nodes}):,} · "
              f"{len(nodes) - tts:,} · {tts:,}")
    cps = {cp for cp, _, _ in records}
    print(f"합집합 cp {len(cps):,}, 단일 스칼라 {sum(1 for cp in cps if len(cp) == 1):,}")

    filters = [("Unicode 15.0 카탈로그", unicode15_catalog())]
    if host_catalog:
        filters.insert(0, ("현 호스트 EmojiCatalog",
                           set(host_catalog.read_text(encoding="utf-8").split())))
    for name, catalog in filters:
        print(f"  {name}: {len(catalog):,}개")

    print("\n## 역색인 (고유 키 · 연결 수 · JSON 바이트 · 이진 바이트)")
    rows = [("keyword만, tts 제외", dict(include_tts=False)),
            ("keyword + tts, 전체 cp", {})]
    for name, catalog in filters:
        rows += [(f"{name} cp만", dict(emojis=catalog)),
                 (f"  + 한글 2~12자 키만", dict(emojis=catalog, korean_only=True)),
                 (f"  + 첫 이모지 하나만", dict(emojis=catalog, korean_only=True, first_only=True))]
    for label, options in rows:
        index, name_match = build_index(records, **options)
        links = sum(len(v) for v in index.values())
        print(f"{label}: {len(index):,} · {links:,} · {json_size(index):,} · "
              f"{len(encode(index, name_match)):,}")

    print("\n## 매핑 수 분포 (전체 keyword+tts / 카탈로그 / + 한글 키)")
    columns = [build_index(records)[0]]
    for _, catalog in filters:
        columns += [build_index(records, emojis=catalog)[0],
                    build_index(records, emojis=catalog, korean_only=True)[0]]
    buckets = [("1개", 1, 1), ("2개", 2, 2), ("3~5개", 3, 5), ("6~10개", 6, 10), ("11개 이상", 11, 1 << 30)]
    for label, low, high in buckets:
        print(f"{label}: " + " / ".join(
            f"{sum(1 for v in col.values() if low <= len(v) <= high):,}" for col in columns))
    print("최댓값: " + " / ".join(
        "{} {}개".format(*max(((k, len(v)) for k, v in col.items()), key=lambda kv: kv[1]))
        for col in columns))

    words = read_words()
    print(f"\n## words.tdw — {WORDS.stat().st_size:,}B, {len(words):,}항목, "
          f"SHA-256 {hashlib.sha256(WORDS.read_bytes()).hexdigest()}")
    every_key = build_index(records)[0]
    for name, catalog in [("CLDR 전체", None)] + filters:
        keys = every_key if catalog is None else build_index(records, emojis=catalog)[0]
        parts = []
        for top in (1_000, 5_000, len(words)):
            head = words[:top]
            hits = [freq for word, freq in head if word in keys]
            weight = sum(hits) / sum(freq for _, freq in head) * 100
            parts.append(f"{top:,}: {len(hits):,}({len(hits) / top * 100:.2f}%, 빈도 {weight:.2f}%)")
        print(f"{name} 교집합 — " + " · ".join(parts))

    for name, catalog in filters:
        index, name_match = build_index(records, emojis=catalog, korean_only=True)
        hits = [(word, freq) for word, freq in words if word in index]
        total = sum(freq for _, freq in hits)
        multi = sum(1 for word, _ in hits if len(index[word]) > 1)
        named = [word for word, _ in hits if word in name_match]
        differs = sum(1 for word in named if index[word][0] != name_match[word])
        coverage = [sum(freq for _, freq in hits[:top]) / total * 100 for top in (100, 200, 300)]
        print(f"\n### {name} + 한글 키 × words.tdw")
        print(f"교집합 {len(hits):,} / 한글 키 {len(index):,} (사전에 없는 키 {len(index) - len(hits):,})")
        print(f"다중 매핑 {multi:,} ({multi / len(hits) * 100:.2f}%) · 이름(tts) 일치 {len(named):,} · "
              f"그중 파일 첫 값과 다름 {differs:,}")
        print("빈도 상위 100/200/300의 교집합 빈도 비중: "
              + " / ".join(f"{c:.2f}%" for c in coverage))


def write_curation_csv(path: Path, top: int) -> None:
    index, name_match, _ = product_index()
    hits = [(word, freq) for word, freq in read_words() if word in index]
    total = sum(freq for _, freq in hits)
    path.parent.mkdir(parents=True, exist_ok=True)
    running = 0
    # Excel이 한글을 깨뜨리지 않게 BOM을 붙인다
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.writer(handle)
        writer.writerow(["순위", "단어", "빈도", "누적 빈도 비중(%)", "tts 일치 이모지", "파일 첫 값",
                         "후보 수", "후보 전부", "음절 수", "5음절 이상"])
        for rank, (word, freq) in enumerate(hits[:top], start=1):
            running += freq
            values = index[word]
            writer.writerow([rank, word, freq, f"{running / total * 100:.2f}",
                             name_match.get(word, ""), values[0], len(values), " ".join(values),
                             len(word), "Y" if len(word) >= 5 else ""])
    print(f"완료: {path} — 교집합 {len(hits):,}개 중 상위 {min(top, len(hits))}개 "
          f"(누적 비중 {running / total * 100:.2f}%)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--stats", action="store_true", help="실측 재현표만 출력한다")
    parser.add_argument("--ref", choices=sorted(CLDR_REFS), default=PRODUCT_REF)
    parser.add_argument("--host-catalog", type=Path,
                        help="EmojiCatalog.categories를 한 줄에 하나씩 덤프한 파일(--stats용)")
    parser.add_argument("--curation-csv", type=Path, help="손질 후보표 CSV 경로")
    parser.add_argument("--top", type=int, default=300)
    args = parser.parse_args()
    if args.stats:
        print_stats(args.ref, args.host_catalog)
    elif args.curation_csv:
        write_curation_csv(args.curation_csv, args.top)
    else:
        if args.ref != PRODUCT_REF:
            sys.exit(f"제품 데이터는 {PRODUCT_REF}로만 만든다 — 다른 ref는 --stats 전용")
        generate()


if __name__ == "__main__":
    main()
