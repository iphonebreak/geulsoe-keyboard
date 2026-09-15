#!/usr/bin/env python3
"""추천단어 사전(ko_50k.txt) → words.tdw 바이너리 변환.

원본: hermitdave/FrequencyWords content/2018/ko/ko_50k.txt (데이터 CC-BY-SA-4.0).
라이선스·채택 근거: docs/design-reviews/word-suggestions.md

포맷 (리틀엔디언) — BundledWordDictionary가 mmap으로 읽는다:
  헤더 16B : magic 'TDWD' | version u32 | 단어 수 u32 | 블롭 시작 u32
  엔트리   : 16B × N — jamoOffset u32 | jamoLen u16 | wordLen u16 | wordOffset u32 | freq u32
             (자모 키 바이트 순 정렬, 오프셋은 블롭 시작 기준)
  블롭     : 자모 키 UTF-8 연속 + 단어 UTF-8 연속

자모 분해는 Swift `HangulSyllable`(HangulEngine)·`JamoDecomposer`(KeyboardCore)와
동일한 표를 복제한다 — 표가 어긋나면 조회가 조용히 실패하므로, Swift 쪽
리소스 로드 테스트("안녕" 접두 조회)가 불일치를 잡는다.

사용: python3 tools/convert_words.py
"""

import re
import struct
import sys
from pathlib import Path

SOURCE = Path(__file__).resolve().parent / "data/ko_50k.txt"
OUTPUT = Path(__file__).resolve().parent.parent / (
    "Packages/TadakData/Sources/TadakData/Resources/words.tdw"
)

VERSION = 1
WORD_PATTERN = re.compile(r"^[가-힣]{2,12}$")

# HangulSyllable의 표 복제 (순서까지 동일해야 한다)
CHOSEONG = list("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
JUNGSEONG = list("ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ")
JONGSEONG = [None] + list("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
COMPOUND_JUNGSEONG = {9: (8, 0), 10: (8, 1), 11: (8, 20), 14: (13, 4),
                      15: (13, 5), 16: (13, 20), 19: (18, 20)}
COMPOUND_JONGSEONG = {3: (1, 19), 5: (4, 22), 6: (4, 27), 9: (8, 1), 10: (8, 16),
                      11: (8, 17), 12: (8, 19), 13: (8, 25), 14: (8, 26),
                      15: (8, 27), 18: (17, 19)}


def decompose(word: str) -> str:
    """음절 문자열 → 평탄한 호환 자모 시퀀스. 겹받침·조합 복모음도 분해한다."""
    out = []
    for ch in word:
        offset = ord(ch) - 0xAC00
        cho, rest = divmod(offset, 21 * 28)
        jung, jong = divmod(rest, 28)
        out.append(CHOSEONG[cho])
        if jung in COMPOUND_JUNGSEONG:
            first, second = COMPOUND_JUNGSEONG[jung]
            out += [JUNGSEONG[first], JUNGSEONG[second]]
        else:
            out.append(JUNGSEONG[jung])
        if jong:
            if jong in COMPOUND_JONGSEONG:
                first, second = COMPOUND_JONGSEONG[jong]
                out += [JONGSEONG[first], JONGSEONG[second]]
            else:
                out.append(JONGSEONG[jong])
    return "".join(out)


def main() -> None:
    entries = []
    seen = set()
    for line in SOURCE.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 2:
            continue
        word, count = parts[0], int(parts[1])
        if not WORD_PATTERN.match(word) or word in seen:
            continue
        seen.add(word)
        entries.append((decompose(word).encode("utf-8"), word.encode("utf-8"),
                        min(count, 0xFFFF_FFFF)))

    if not (20_000 <= len(entries) <= 50_000):
        sys.exit(f"필터 결과가 예상 범위를 벗어남: {len(entries)}")

    # 표본 대조 — 분해 규칙 회귀 방어
    assert decompose("안녕핫") == "ㅇㅏㄴㄴㅕㅇㅎㅏㅅ"
    assert decompose("갃") == "ㄱㅏㄱㅅ"
    assert decompose("회사") == "ㅎㅗㅣㅅㅏ"
    assert decompose("띄어") == "ㄸㅡㅣㅇㅓ"

    entries.sort(key=lambda e: e[0])

    index = bytearray()
    blob = bytearray()
    for jamo, word, freq in entries:
        if len(jamo) >= 1 << 16 or len(word) >= 1 << 16:
            sys.exit(f"길이 초과: {word.decode()}")
        index += struct.pack("<IHHII", len(blob), len(jamo), len(word),
                             len(blob) + len(jamo), freq)
        blob += jamo + word

    header = struct.pack("<4sIII", b"TDWD", VERSION, len(entries), 16 + len(index))
    OUTPUT.write_bytes(header + index + blob)
    total = len(header) + len(index) + len(blob)
    print(f"완료: {OUTPUT} — {len(entries)}단어, {total / 1024 / 1024:.2f}MB")


if __name__ == "__main__":
    main()
