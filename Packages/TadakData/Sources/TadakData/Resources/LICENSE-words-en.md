# `words-en.tdw` — 라이선스 고지 / Licence notice

이 파일은 **같은 디렉터리의 `words-en.tdw` 한 파일에만** 적용된다. 저장소의 나머지(소스 코드·다른 데이터 파일)는 대상이 아니다.
This notice applies to **`words-en.tdw` in this directory only** — not to the source code or to the other data files beside it.

---

## 한국어

`words-en.tdw` 는 아래 저작물의 **2차적 저작물(Adapted Material)** 이며,
**Creative Commons 저작자표시-동일조건변경허락 4.0 국제 (CC BY-SA 4.0)** 로 배포한다.

- **원저작물** — FrequencyWords, 영어 `en_50k` 목록 (OpenSubtitles 2018 기반)
- **저작자** — Hermit Dave
- **원저작물 위치(고정 커밋)** — https://github.com/hermitdave/FrequencyWords/blob/072bbed282316a23651aa7068c7173aa7898cf80/content/2018/en/en_50k.txt
  (커밋 `072bbed282316a23651aa7068c7173aa7898cf80`, 622,749 B, sha256 `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458`)
- **원저작물 라이선스** — 위 **고정 커밋의 README 표기**는 *"MIT License for codes. CC-by-sa-3.0 for contents."* 이고,
  저작자의 **현행 표기**(같은 저장소 `master` README, 2026-10-14 확인)는 *"MIT License for code. CC-by-sa-4.0 for content."* 이다.
  `words-en.tdw` 는 content(데이터)에서 파생됐다. **CC BY-SA 3.0 §4(b)** 는 2차적 저작물을 같은 요소를 가진 **이후 버전**(4.0 포함)으로
  배포하는 것을 허용하므로, 이 파일은 **CC BY-SA 4.0** 으로 배포한다(저작자 현행 표기와도 같다).
- **라이선스 전문** — https://creativecommons.org/licenses/by-sa/4.0/legalcode (한국어: https://creativecommons.org/licenses/by-sa/4.0/deed.ko)

### 개변 사실 (§3(a)(1)(B))

원 목록을 그대로 옮긴 것이 아니다. `tools/convert_words_en.py` 가 다음을 한다.

1. 소문자로 바꾸고 굽은 아포스트로피(’)를 곧은 것(')으로 바꾼다. 영문자와 단어 안 아포스트로피로만 된 3~20자 낱말만 남기고 중복을 없앤다.
2. 축약형이 쪼개져 생긴 어간 조각(`didn` 등 14개)을 축약형(`didn't` 등)으로 바꾸고, 일부 조각(`ain`·`don`)을 빼며 `won't` 를 더한다.
3. 아포스트로피가 빠진 철자 오류형·자막 잡음 토큰·부적절한 낱말을 정확히 일치하는 것만 뺀다.
4. 축약형(`I'm` 등)과 대문자 원형(요일·월·언어·국적 등 — `Monday`·`English`·`iPhone`)을 손질 목록으로 더하거나 표기를 바꾼다.
5. 빈도로 다시 줄 세워 상위 20,000개만 남기고, 조회 키를 붙여 mmap 이진 탐색용 이진 포맷으로 다시 쓴다.

선별·재배열·신규 항목 부가가 모두 일어났으므로 단순 포맷 변환이 아니라 2차적 저작물이다.

### 왜 이 파일이 여기 있나

CC BY-SA 4.0 §3(b)(1) 은 2차적 저작물을 같은(또는 호환) 라이선스로 배포할 것을 요구하고, §2(a)(5)(B) 는 추가 제한 조건을 금지한다.
이 저장소 루트에는 라이선스 파일이 없으므로(기본값은 저작권 유보) **이 파일이 그 허락을 명시적으로 준다.**
앱 안의 출처 표기(설정 > 정보 > 오픈소스 및 출처)는 귀속 요건을, 이 파일은 배포 라이선스를 밝힌다 — 둘은 다르다.
이 라이선스는 이 사전 파일에만 적용된다 — 앱 소스나 다른 데이터에 같은 라이선스를 요구하지 않는다.

---

## English

`words-en.tdw` is **Adapted Material** derived from the work below, distributed under the
**Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** licence.

- **Original work** — FrequencyWords, English `en_50k` list (based on OpenSubtitles 2018)
- **Creator** — Hermit Dave
- **Source (pinned commit)** — https://github.com/hermitdave/FrequencyWords/blob/072bbed282316a23651aa7068c7173aa7898cf80/content/2018/en/en_50k.txt
  (commit `072bbed282316a23651aa7068c7173aa7898cf80`, 622,749 bytes, sha256 `5351ff405b1126ef555791dd4d9798a48e3e9a501a9fc481a9da957752cfb458`)
- **Upstream licence** — the README **at the pinned commit** states *"MIT License for codes. CC-by-sa-3.0 for contents."*;
  the creator's **current** statement (`master` README, checked 2026-10-14) is *"MIT License for code. CC-by-sa-4.0 for content."*
  `words-en.tdw` derives from the content. **CC BY-SA 3.0 §4(b)** permits distributing Adapted Material under a **later version**
  with the same License Elements (including 4.0), so this file is distributed under **CC BY-SA 4.0** (matching the creator's current statement).
- **Licence text** — https://creativecommons.org/licenses/by-sa/4.0/legalcode

### Notice of modification (§3(a)(1)(B))

`tools/convert_words_en.py`:

1. lower-cases entries and maps the curly apostrophe (’) to a straight one ('); keeps only 3-20 letter words made of Latin letters
   and inner apostrophes; removes duplicates;
2. turns split contraction stems (14, e.g. `didn`) into contractions (`didn't`), drops some stems (`ain`, `don`) and adds `won't`;
3. removes, by exact match only, apostrophe-less misspellings, subtitle noise tokens and inappropriate words;
4. adds contractions (e.g. `I'm`) and capitalised forms (weekdays, months, languages and nationalities, `iPhone`) from curated lists;
5. re-ranks by frequency, keeps the top 20,000, attaches lookup keys and rewrites the list as a binary format for mmap binary search.

Selection, rearrangement and the addition of new entries make this Adapted Material rather than a mere format conversion.
This licence applies to this dictionary file only; it does not extend to the app source or to other data.
