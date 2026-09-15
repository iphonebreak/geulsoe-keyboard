#!/usr/bin/env python3
"""개역한글 성경 → bible.tdb 바이너리 변환.

═══ 입력 출처 (이 사슬을 끊지 마라) ═══

  파일    : /Users/Project/LifeBible_flutter/assets/hive/life_bible.hive
  프로젝트 : 같은 모노레포의 **LifeBible_flutter** (Flutter 성경 앱 "One Bible")
  형식    : Hive 박스 (그쪽 `lib/model/Bible.g.dart` typeId 0 — book·chapter·verse·content 4필드)
  크기    : 5,982,133 바이트 / md5 25e09dc8611e04c89def217cf9c0107d (2026-09-15 확인)
  채택일   : 2026-09-15 — 사용자 결정 ("LifeBible 쪽이 맞으니 이쪽 성경 구절을 써야 한다")
  **읽기 전용이다. 이 스크립트는 그 파일에 쓰지 않고, 그 프로젝트를 건드리지 않는다.**

**예전 입력은 `/Users/Project/hive_sample/lib/bibleAdd.dart` 였다. 2026-09-15 에 버렸다.**
그 파일 안에는 출처·판·쇄 표기가 **한 줄도 없었다**(전수 검색 0건). 반론자 IP 감사가
"출처 사슬이 끊겼다"고 지적한 지점이 바로 거기다. 그래서 이 머리말이 길다.

두 데이터는 같은 개역한글인데 **맞춤법 계통이 갈린다.** 옛 입력은 `세째→셋째`·`네째→넷째` 로
손질된 판이고(1988년 맞춤법 개정 **후** 표기), LifeBible 은 `세째` 47건·`네째` 39건으로
**1961년 발행 당시 표기를 유지**한다. 권리자(대한성서공회)가 저작재산권 만료를 공개 확인하면서
**동일성유지권 준수**를 요구했으므로 원문에 가까운 쪽을 쓴다.
다만 **둘 다 `할찌어다 → 할지어다` 축에서는 현대 표기로 손질돼 있다**(양쪽 185건으로 같다) —
LifeBible 이 "1961년 원문 그 자체"라는 뜻은 아니다. 실측: docs/release/bundle-audit.md 부록 C.

═══ 왜 Dart 도구를 부르지 않고 직접 읽나 ═══

LifeBible_flutter 에 공식 덤프 도구 `tool/life_bible_hive_tool.dart` 가 있고
`dart run tool/life_bible_hive_tool.dart dump <out.json>` 으로 같은 내용을 얻는다.
그런데 그걸 빌드 경로에 두면 **Dart SDK + pub 의존성**이 필요해지고, 그 프로젝트 안에서 돌리면
`.dart_tool/` 이 생겨 **읽기 전용 원칙이 깨진다**(그 프로젝트엔 `.dart_tool/` 이 없다).
그래서 아래 `read_hive()` 가 Hive 프레임을 직접 읽는다 — **공식 도구의 덤프와 31,101절이
바이트 단위로 동일함을 확인하고 채택했다**(2026-09-15, 부록 C에 출력 있음).

Hive 프레임: [uint32 길이][키타입 1B][키][값][crc 4B]
  키타입 0 = uint32 키 / 1 = 길이접두 ascii 키
  값: [typeId 1B = 32(커스텀 어댑터)][필드 수 1B] 뒤로 (필드번호 1B + 타입 1B + 값) 반복
      타입 1 = int (**little-endian double 8B** 로 저장된다), 타입 4 = string (uint32 길이 + UTF-8)
  값이 비어 있는 프레임은 **삭제**다. 같은 키가 또 나오면 **뒤가 이긴다**(append-only 파일).

═══ 출력 포맷 (리틀엔디언) — BundledBibleRepository가 mmap으로 읽는다 ═══

  헤더 16B : magic 'TDBB' | version UInt32 | 절 수 UInt32 | 텍스트 시작 오프셋 UInt32
  인덱스   : 절당 12B — book·chapter·verse·byteLength 각 UInt16 + offset UInt32
             (offset은 텍스트 블롭 시작 기준, (book,chapter,verse) 오름차순 정렬)
  블롭     : UTF-8 본문 연속

═══ 권리 ═══

개역한글판(1961)은 **저작재산권 보호기간이 2011-12-31 로 소멸**했다 — 우리 해석이 아니라
권리자(대한성서공회)가 자기 사이트에 공개한 사실이다.
  https://www.bskorea.or.kr/bbs/content.php?co_id=subpage2_3_4_1
같은 곳 저작권 FAQ 는 사용료 없이 쓸 수 있되 **성명표시권·동일성유지권은 남으며 무단 변경·절삭은
허용되지 않는다**고 적는다. 그래서 아래 가드들이 있다 — 본문이 빈 절은 곧 절삭이다.
  https://www.bskorea.or.kr/bbs/board.php?bo_table=copyright_faq&wr_id=5
근거: docs/design-reviews/snippet-autocomplete.md, docs/release/ip-audit.md,
      docs/release/bundle-audit.md 부록 A·B·C

사용: python3 tools/convert_bible.py
"""

import struct
import sys
from pathlib import Path

SOURCE = Path("/Users/Project/LifeBible_flutter/assets/hive/life_bible.hive")
OUTPUT = Path(__file__).resolve().parent.parent / (
    "Packages/TadakData/Sources/TadakData/Resources/bible.tdb"
)

EXPECTED_VERSE_COUNT = 31_102
EXPECTED_BOOKS = 66
VERSION = 1

# Hive 값 타입
_TYPE_ADAPTER = 32   # typeId 0 인 커스텀 어댑터(Bible) — Hive 는 커스텀에 32 를 더한다
_TYPE_INT = 1
_TYPE_STRING = 4


def read_hive(path: Path) -> dict:
    """Hive 박스에서 (book, chapter, verse) → 본문 을 읽는다. 프레임 구조는 머리말 참조."""
    data = path.read_bytes()
    records: dict = {}
    pos = 0
    frames = 0
    while pos < len(data):
        if pos + 4 > len(data):
            sys.exit(f"프레임 헤더가 잘렸다: offset {pos}")
        (length,) = struct.unpack_from("<I", data, pos)
        if length < 9 or pos + length > len(data):
            sys.exit(f"프레임 길이가 이상하다: offset {pos}, 길이 {length}")
        frame = data[pos:pos + length]
        p = 4
        key_type = frame[p]
        p += 1
        if key_type == 0:
            (key,) = struct.unpack_from("<I", frame, p)
            p += 4
        elif key_type == 1:
            key_len = frame[p]
            p += 1
            key = frame[p:p + key_len].decode("utf-8")
            p += key_len
        else:
            sys.exit(f"알 수 없는 키 타입 {key_type}: offset {pos}")

        value_end = length - 4  # 끝 4바이트는 crc
        if p == value_end:
            records.pop(key, None)  # 값이 없는 프레임 = 삭제
        else:
            type_id = frame[p]
            p += 1
            if type_id != _TYPE_ADAPTER:
                sys.exit(f"예상 밖 typeId {type_id}: offset {pos}")
            field_count = frame[p]
            p += 1
            fields: dict = {}
            for _ in range(field_count):
                index = frame[p]
                p += 1
                value_type = frame[p]
                p += 1
                if value_type == _TYPE_INT:
                    (number,) = struct.unpack_from("<d", frame, p)
                    p += 8
                    fields[index] = int(number)
                elif value_type == _TYPE_STRING:
                    (text_len,) = struct.unpack_from("<I", frame, p)
                    p += 4
                    fields[index] = frame[p:p + text_len].decode("utf-8")
                    p += text_len
                else:
                    sys.exit(f"알 수 없는 값 타입 {value_type}: offset {pos}")
            if p != value_end:
                sys.exit(f"값 끝이 프레임과 안 맞는다: offset {pos}")
            records[key] = (fields[0], fields[1], fields[2], fields[3])
        frames += 1
        pos += length
    print(f"Hive 프레임 {frames}개 → 살아 있는 레코드 {len(records)}개", file=sys.stderr)
    verses = {(b, c, v): t for b, c, v, t in records.values()}
    if len(verses) != len(records):
        sys.exit(f"(책,장,절) 키가 겹친다: 레코드 {len(records)} → 고유 키 {len(verses)}")
    return verses


# 시편 72:19 에 20절이 마침표로 이어 붙어 있다 — 갈라낼 자리와 기대 문자열.
_PSALM_72_19_JOINED = (
    "그 영화로운 이름을 영원히 찬송할지어다 온 땅에 그 영광이 충만할지어다 아멘 아멘."
    " 이새의 아들 다윗의 기도가 필하다"
)


def split_psalm_72(verses: dict) -> None:
    """**시편 72:20 을 되돌린다 — LifeBible 이 유일하게 절을 잃은 자리다.**

    LifeBible 에는 72:20 레코드가 없고 20절 본문이 19절 끝에 마침표로 이어 붙어 있다.
    그래서 31,101절이다. 본문에 마침표가 들어간 절이 전체에 5개뿐인데 이 자리가 그중 하나다.

    **정본은 19절과 20절을 따로 찍는다** — 대한성서공회 개역한글판 시편 72편에서
    18·19·20 이 각각 번호를 달고 있고 20절이 이 편의 마지막 절임을 직접 확인했다(2026-09-15).
    즉 정본이 묶어 찍은 합병절이 아니라 **LifeBible 쪽 결손**이다. 그대로 두면
    「시편 72편 20절」이 조회되지 않고 절 수도 한 절 모자란다 — 그게 곧 절삭이다.

    **글자를 지어내지 않는다.** 이어 붙인 자리를 되가를 뿐이고, 갈라낸 두 문자열은 정본이
    보여 준 19절·20절 본문과 그대로 일치한다. 원본이 바뀌면 조용히 지나가지 않도록
    **기대 문자열 완전 일치**를 걸어 둔다.
    """
    if (19, 72, 20) in verses:
        return  # 이미 따로 있으면 건드리지 않는다
    actual = verses.get((19, 72, 19))
    if actual != _PSALM_72_19_JOINED:
        sys.exit(
            "시편 72:19 가 예상과 다르다 — 원본이 바뀌었을 수 있다. 확인하고 이 함수를 고쳐라.\n"
            f"  기대: {_PSALM_72_19_JOINED}\n  실제: {actual}"
        )
    head, _, tail = _PSALM_72_19_JOINED.partition(". ")
    verses[(19, 72, 19)] = head.rstrip(".")
    verses[(19, 72, 20)] = tail
    print(f"시편 72:19/20 분리 — 19절 끝 '…{verses[(19, 72, 19)][-9:]}' / 20절 '{tail}'",
          file=sys.stderr)


def main() -> None:
    raw = read_hive(SOURCE)
    split_psalm_72(raw)
    verses = [(b, c, v, t) for (b, c, v), t in raw.items()]

    if len(verses) != EXPECTED_VERSE_COUNT:
        sys.exit(f"절 수 불일치: {len(verses)} != {EXPECTED_VERSE_COUNT}")
    books = {v[0] for v in verses}
    if books != set(range(1, EXPECTED_BOOKS + 1)):
        sys.exit(f"책 번호 불일치: {sorted(books)[:5]}… ~ {sorted(books)[-1]}")

    # 장마다 절 번호가 1..N 으로 이어져야 한다 — 가운데가 빠진 장을 잡는다
    chapters: dict = {}
    for book, chapter, verse, _ in verses:
        chapters.setdefault((book, chapter), []).append(verse)
    broken = [key for key, nums in chapters.items()
              if sorted(nums) != list(range(1, len(nums) + 1))]
    if broken:
        sys.exit(f"절 번호가 1..N 으로 이어지지 않는 장 {len(broken)}개: {broken[:5]}")

    # **빈 본문은 곧 「절삭」이다** — 권리자가 명시적으로 금지한 것이고, 사용자에게는
    # 「로마서 9장 2절」을 쳤을 때 빈 내용이 삽입되는 버그로 보인다.
    # 정본이 두 절을 "1-2" 로 묶어 찍은 합병절의 뒷절은 빈 문자열이 아니라
    # `(N절에 포함되어 있음)` 표기를 갖는다(LifeBible 21건). 정본이 실제로 없는 절에 쓰는
    # `(없음)` 13건도 본문이 있으므로 여기 걸리지 않는다.
    empty = [(b, c, v) for b, c, v, t in verses if not t.strip()]
    if empty:
        for b, c, v in empty[:20]:
            print(f"빈 본문: {b} {c}:{v}", file=sys.stderr)
        sys.exit(
            f"빈 본문 {len(empty)}건 — 본문이 비면 「절삭」이 된다(동일성유지권). "
            "합병절이면 뒷절에 '(N절에 포함되어 있음)' 을 넣어라."
        )

    # 합병절 표기는 **한 형식만 쓴다** — `(N절에 포함되어 있음)`.
    # 옛 입력(bibleAdd.dart)에는 네 형식이 섞여 있었다: 빈 문자열 · `상동` · `12절과 상동` ·
    # `8절과 같음` · 앞 숫자가 잘린 `과 동일함`. LifeBible 은 처음부터 한 형식이지만
    # 입력이 또 바뀔 때를 대비해 가드를 남겨 둔다.
    # **완전 일치로만 본다** — 실제 본문에 `동일하니라`·`상동`을 부분 포함하는 절이 있어
    # (출 12:49 등) 부분 일치로 잡으면 성경 본문을 오탐한다.
    legacy_markers = {"상동", "과 동일함", "12절과 상동", "8절과 같음"}
    legacy = [(b, c, v, t) for b, c, v, t in verses if t in legacy_markers]
    if legacy:
        for b, c, v, t in legacy:
            print(f"옛 합병절 표기: {b} {c}:{v} = {t}", file=sys.stderr)
        sys.exit(
            f"옛 합병절 표기 {len(legacy)}건 — '(N절에 포함되어 있음)' 한 형식으로만 쓴다. "
            "가리킬 절 번호는 정본에서 확인해라."
        )

    # 알려진 절 대조 — 변환이 본문을 훼손하지 않았는지 표본 확인
    by_key = {(b, c, v): t for b, c, v, t in verses}
    assert by_key[(1, 1, 1)] == "태초에 하나님이 천지를 창조하시니라"
    assert by_key[(66, 22, 21)] == "주 예수의 은혜가 모든 자들에게 있을지어다 아멘"
    assert by_key[(43, 3, 16)].startswith("하나님이 세상을 이처럼 사랑하사")  # 요 3:16
    assert by_key[(19, 72, 20)] == "이새의 아들 다윗의 기도가 필하다"

    # **1961년 표기가 살아 있는지** — 현대 맞춤법으로 손질된 판을 다시 집어오면 여기서 걸린다.
    # 이 판을 고른 이유 자체가 이 표기이므로, 조용히 옛 데이터로 돌아가는 것을 막는다.
    old_spelling = sum(t.count("세째") + t.count("네째") for t in by_key.values())
    if old_spelling < 80:
        sys.exit(
            f"「세째·네째」가 {old_spelling}건뿐이다(기대 86건) — 1988년 맞춤법 개정 후 표기로 "
            "손질된 판일 수 있다. 입력을 확인해라."
        )

    verses.sort(key=lambda v: (v[0], v[1], v[2]))

    index = bytearray()
    blob = bytearray()
    for book, chapter, verse, text in verses:
        data = text.encode("utf-8")
        if len(data) >= 1 << 16:
            sys.exit(f"본문이 UInt16 길이를 초과: {book} {chapter}:{verse}")
        index += struct.pack("<HHHHI", book, chapter, verse, len(data), len(blob))
        blob += data

    header = struct.pack("<4sIII", b"TDBB", VERSION, len(verses), 16 + len(index))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(header + index + blob)
    total = len(header) + len(index) + len(blob)
    print(f"완료: {OUTPUT} — {len(verses)}절, {total / 1024 / 1024:.2f}MB "
          f"(인덱스 {len(index) // 1024}KB + 블롭 {len(blob) / 1024 / 1024:.2f}MB)")


if __name__ == "__main__":
    main()
