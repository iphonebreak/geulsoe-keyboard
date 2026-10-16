#!/usr/bin/env python3
"""영어 추천단어 사전(en_50k.txt) → words-en.tdw 바이너리 변환 (B5, 1.3.1).

원본: hermitdave/FrequencyWords content/2018/en/en_50k.txt — **고정 커밋**만 받는다(데이터 CC-BY-SA-4.0).
설계·데이터 품질 계약: docs/design-reviews/english-word-suggestions.md (계획 v1.3.1-plan.md §3-8)

포맷은 한글 words.tdw와 같다(tools/convert_words.py — BundledWordDictionary가 mmap으로 읽는다).
  헤더 16B : magic 'TDWD' | version u32 | 단어 수 u32 | 블롭 시작 u32
  엔트리   : 16B × N — keyOffset u32 | keyLen u16 | wordLen u16 | wordOffset u32 | freq u32  (키 바이트 순 정렬)
  블롭     : 키 UTF-8 + 표시형 UTF-8
**키 = lookupKey(소문자, 직선 아포스트로피)**, 표시형 = 사전 형태(`I'm`·`Monday`·`iPhone`은 손질 목록).

파이프라인(순서가 계약이다):
  ① 고정 원본 읽기 — sha256·크기 불일치면 실패
  ② 정규화 — 소문자화, ’(U+2019) → '
  ③ 필터 — ^[a-z]+(?:'[a-z]+)*$ · 길이 3~20(2글자는 최소 입력 2자보다 길지 않아 후보가 될 수 없다) · 중복 제거(첫 출현)
  ④ 조각 처리(기계) — 어간 조각 14개 → `…n't`(조각 빈도 그대로) · ain 제거 · don 제거(don't가 그 빈도) · won't = won 빈도, won은 −1
  ⑤ 철자 오류형·⑤′ 비단어(잡음·음차)·⑥ 금칙어 — tools/data-en/ 목록과 정확 일치로 제거(부분 문자열 필터 없음)
  ⑦ 축약형 손질(명시 빈도 — 손질 항목끼리 동률이면 실패) · ⑧ 대문자 원형 손질(빈도 그대로)
  ⑨ 정렬 — 빈도 내림차순, 동률이면 손질 항목 먼저, 그다음 키 사전순 · 상한(기본 20,000 — 축소 사다리 --limit)
  ⑩ 기록 — TDWD + 출력 sha256·항목 수·바이트

사용:
  python3 tools/convert_words_en.py                 # 고정 URL에서 원본을 받아 변환
  python3 tools/convert_words_en.py --source FILE   # 받아 둔 원본으로
  python3 tools/convert_words_en.py --check         # 다시 만들어 커밋된 산출물과 바이트가 같은지(다르면 exit 1)
  python3 tools/convert_words_en.py --limit 10000 --output /tmp/x.tdw   # 사다리 단계 시험용
금칙어 목록 원문은 tools/data-en/blocklist.txt에만 둔다 — 이 스크립트는 단어를 출력하지 않는다(개수만).
"""

import argparse
import hashlib
import re
import struct
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = Path(__file__).resolve().parent / "data-en"
OUTPUT = ROOT / "Packages/TadakData/Sources/TadakData/Resources/words-en.tdw"

SOURCE_COMMIT = "072bbed282316a23651aa7068c7173aa7898cf80"
SOURCE_URL = ("https://raw.githubusercontent.com/hermitdave/FrequencyWords/"
              f"{SOURCE_COMMIT}/content/2018/en/en_50k.txt")
SOURCE_SHA256 = "5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458"
SOURCE_BYTES = 622_749

VERSION = 1
DEFAULT_LIMIT = 20_000
WORD = re.compile(r"[a-z]+(?:'[a-z]+)*")
MIN_LEN, MAX_LEN = 3, 20

# ④ 어간 조각 — 축약형으로 바꾸고 조각의 빈도를 그대로 쓴다
STEM_FRAGMENTS = ["didn", "doesn", "isn", "wasn", "wouldn", "haven", "couldn", "aren",
                  "shouldn", "weren", "hasn", "hadn", "mustn", "needn"]
DROPPED_FRAGMENTS = ["ain", "don"]  # ain't는 제품 선택으로 제외, don은 don't가 그 자리를 갖는다


class ConversionError(Exception):
    pass


def read_list(name: str, data_dir: Path = DATA) -> list[str]:
    lines = (data_dir / name).read_text(encoding="utf-8").splitlines()
    return [line.strip() for line in lines if line.strip() and not line.startswith("#")]


def read_tsv(name: str, data_dir: Path = DATA) -> list[list[str]]:
    return [line.split("\t") for line in read_list(name, data_dir)]


def load_source(path: Path) -> bytes:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    if len(raw) != SOURCE_BYTES or digest != SOURCE_SHA256:
        raise ConversionError(f"원본 해시 불일치 — {len(raw)}B sha256 {digest} (기대 {SOURCE_BYTES}B {SOURCE_SHA256})")
    return raw


def build(raw: bytes, limit: int = DEFAULT_LIMIT, data_dir: Path = DATA) -> tuple[bytes, dict]:
    """원본 바이트 → (TDWD 바이트, 통계). 입력이 같으면 출력 바이트가 같다(E16)."""
    # ②③ 정규화·필터·중복 제거
    entries: dict[str, dict] = {}
    order = 0
    for line in raw.decode("utf-8").splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        key = parts[0].lower().replace("’", "'")
        if not WORD.fullmatch(key) or not (MIN_LEN <= len(key) <= MAX_LEN) or key in entries:
            continue
        entries[key] = {"display": key, "freq": int(parts[1]), "curated": False, "order": order}
        order += 1
    stats = {"filtered": len(entries)}

    # ④ 조각 처리(기계)
    curated_freqs: dict[int, str] = {}

    def add_curated(key: str, display: str, freq: int) -> None:
        if key in entries:
            raise ConversionError(f"손질 키가 이미 사전에 있다: {key}")
        if freq in curated_freqs:
            raise ConversionError(f"손질 항목 빈도 동률: {key} = {curated_freqs[freq]} ({freq})")
        curated_freqs[freq] = key
        entries[key] = {"display": display, "freq": freq, "curated": True, "order": -1}

    for stem in STEM_FRAGMENTS:
        fragment = entries.pop(stem, None)
        if fragment is None:
            raise ConversionError(f"어간 조각이 원본에 없다: {stem}")
        add_curated(stem + "'t", stem + "'t", fragment["freq"])
    don = entries.pop("don", None)
    entries.pop("ain", None)
    if don is None or "won" not in entries:
        raise ConversionError("don·won이 원본에 없다")
    add_curated("don't", "don't", don["freq"])
    add_curated("won't", "won't", entries["won"]["freq"])
    entries["won"]["freq"] -= 1

    # ⑤⑤′⑥ 정확 일치 제거
    removed = {}
    for name in ("misspellings.txt", "noise.txt", "blocklist.txt"):
        words = set(read_list(name, data_dir))
        removed[name] = sum(1 for word in words if entries.pop(word, None) is not None)
    stats["removed"] = removed

    # ⑦ 축약형 손질(명시 빈도)
    contractions = read_tsv("contractions.tsv", data_dir)
    for display, key, freq in contractions:
        add_curated(key, display, int(freq))
    # ⑧ 대문자 원형 손질(빈도 그대로)
    capitals = read_tsv("capitals.tsv", data_dir)
    stats["capitals_missing"] = 0
    for key, display in capitals:
        if key not in entries:
            stats["capitals_missing"] += 1   # 원본에 없거나 위에서 걸러졌다 — 손질하지 않는다
            continue
        if display.lower() != key:
            raise ConversionError(f"대문자 손질 표시형이 키와 다르다: {key}")
        entries[key]["display"] = display

    # ⑨ 정렬·상한 — 빈도 내림차순, 동률이면 손질 먼저, 그다음 키 사전순
    ranked = sorted(entries.items(), key=lambda kv: (-kv[1]["freq"], not kv[1]["curated"], kv[0]))
    kept = ranked[:limit]
    stats["total"] = len(entries)
    stats["kept"] = len(kept)

    # ⑩ TDWD — 키 바이트 순
    rows = sorted(((key.encode("utf-8"), value["display"].encode("utf-8"), value["freq"]) for key, value in kept),
                  key=lambda row: row[0])
    index, blob = bytearray(), bytearray()
    for key, word, freq in rows:
        if not key.isascii() or not word.isascii():
            raise ConversionError("ASCII가 아닌 항목")
        index += struct.pack("<IHHII", len(blob), len(key), len(word), len(blob) + len(key), min(freq, 0xFFFF_FFFF))
        blob += key + word
    output = struct.pack("<4sIII", b"TDWD", VERSION, len(rows), 16 + len(index)) + bytes(index) + bytes(blob)
    stats["bytes"] = len(output)
    stats["sha256"] = hashlib.sha256(output).hexdigest()
    stats["ranked_words"] = [value["display"] for _, value in kept]
    return output, stats


def fetch_source() -> Path:
    """고정 URL에서 받아 임시 폴더에 둔다(해시는 `load_source`가 본다). urllib이 인증서로 실패하면 curl로 다시 받는다"""
    target = Path(tempfile.gettempdir()) / f"en_50k-{SOURCE_COMMIT[:12]}.txt"
    if not target.exists():
        try:
            urllib.request.urlretrieve(SOURCE_URL, target)
        except OSError:
            subprocess.run(["curl", "-fsSL", SOURCE_URL, "-o", str(target)], check=True)
    return target


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--source", type=Path)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        raw = load_source(args.source or fetch_source())
        output, stats = build(raw, args.limit)
    except ConversionError as error:
        print(f"실패: {error}", file=sys.stderr)
        return 1
    summary = (f"{stats['kept']}단어(필터 {stats['filtered']} → 처리 뒤 {stats['total']}) · {stats['bytes']}B · "
               f"sha256 {stats['sha256']} · 제거 {stats['removed']} · 대문자 손질 미적용 {stats['capitals_missing']}")
    if args.check:
        current = args.output.read_bytes() if args.output.exists() else b""
        if current != output:
            print(f"불일치: {args.output}가 재생성 결과와 다르다 — {summary}", file=sys.stderr)
            return 1
        print(f"일치: {summary}")
        return 0
    args.output.write_bytes(output)
    print(f"완료: {args.output} — {summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
