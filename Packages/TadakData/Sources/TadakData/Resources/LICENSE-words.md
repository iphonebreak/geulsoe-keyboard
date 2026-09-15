# `words.tdw` — 라이선스 고지 / Licence notice

이 파일은 **같은 디렉터리의 `words.tdw` 한 파일에만** 적용된다.
저장소의 나머지(소스 코드·`bible.tdb`·`Snippets.json`·`Greetings.json`·`Themes.json`)는 대상이 아니다.

This notice applies to **`words.tdw` in this directory only** — not to the source code or to the
other data files beside it (`bible.tdb`, `Snippets.json`, `Greetings.json`, `Themes.json`).

---

## 한국어

`words.tdw` 는 아래 저작물의 **2차적 저작물(Adapted Material)** 이며,
**Creative Commons 저작자표시-동일조건변경허락 4.0 국제 (CC BY-SA 4.0)** 로 배포한다.

- **원저작물** — FrequencyWords, 한국어 `ko_50k` 목록 (OpenSubtitles 2018 기반)
- **저작자** — Hermit Dave
- **원저작물 위치** — https://github.com/hermitdave/FrequencyWords
- **원저작물 라이선스** — 업스트림 표기 그대로: *"MIT License for code. CC-by-sa-4.0 for content."*
  `words.tdw` 가 파생된 것은 **content(데이터)** 쪽이므로 CC BY-SA 4.0 이 적용된다.
- **라이선스 전문** — https://creativecommons.org/licenses/by-sa/4.0/legalcode
  (한국어: https://creativecommons.org/licenses/by-sa/4.0/deed.ko)

### 개변 사실 (§3(a)(1)(B))

원 목록을 그대로 옮긴 것이 아니다. `tools/convert_words.py` 가 다음을 한다.

1. 한글 음절 2~12자인 표제어만 정규식(`^[가-힣]{2,12}$`)으로 걸러 낸다 — 숫자·로마자·기호가
   섞인 항목과 1자·13자 이상인 항목은 버린다.
2. 중복 표제어를 제거한다.
3. **각 낱말의 자모 분해 키를 새로 계산해 붙인다** — 원 목록에 없던 데이터다.
4. 자모 키 기준으로 재정렬해 mmap 이진 탐색용 이진 포맷으로 다시 쓴다.

즉 선별·재배열·신규 데이터 부가가 모두 일어났으므로 단순 포맷 변환이 아니라 2차적 저작물이다.

### 왜 이 파일이 여기 있나

CC BY-SA 4.0 §3(b)(1) 은 2차적 저작물을 **같은 라이선스(또는 호환 라이선스)로 배포할 것**을
요구하고, §2(a)(5)(B) 는 수령자의 권리 행사를 제한하는 **추가 조건을 얹는 것을 금지**한다.
이 저장소 루트에는 라이선스 파일이 없고, 라이선스가 명시되지 않은 공개 저장소의 기본값은
**저작권 유보**다 — 그 상태로 두면 파생물에 원 라이선스보다 엄격한 조건을 얹은 것이 되어
위 두 조항에 걸린다. **이 파일이 그 허락을 명시적으로 준다.**

앱 안의 출처 표기(설정 > 정보 > 오픈소스 및 출처)는 귀속(§3(a)) 요건을 충족한다.
이 파일은 그것과 별개로 **배포 라이선스 자체**를 밝히는 것이다 — 둘은 다르다.

근거와 경위: `docs/release/ip-audit.md` 2절.

---

## English

`words.tdw` is **Adapted Material** derived from the work below, and is distributed under the
**Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)** licence.

- **Original work** — FrequencyWords, Korean `ko_50k` list (based on OpenSubtitles 2018)
- **Creator** — Hermit Dave
- **Source** — https://github.com/hermitdave/FrequencyWords
- **Upstream licence** — as stated upstream: *"MIT License for code. CC-by-sa-4.0 for content."*
  `words.tdw` derives from the **content**, so CC BY-SA 4.0 applies.
- **Licence text** — https://creativecommons.org/licenses/by-sa/4.0/legalcode

### Notice of modification (§3(a)(1)(B))

The list was not copied verbatim. `tools/convert_words.py`:

1. keeps only headwords of 2-12 Hangul syllables (`^[가-힣]{2,12}$`), dropping anything with
   digits, Latin letters or punctuation;
2. removes duplicate headwords;
3. **computes and attaches a decomposed-jamo key for each word** — data not present upstream;
4. re-sorts by that key and rewrites the list as a binary format for mmap binary search.

Selection, rearrangement and the addition of new data make this Adapted Material rather than a
mere format conversion.

### Why this file exists

CC BY-SA 4.0 §3(b)(1) requires Adapted Material to be released under the same (or a compatible)
licence, and §2(a)(5)(B) forbids imposing additional terms that restrict a recipient's exercise of
the licensed rights. This repository has no root licence file, and the default for a public
repository with no stated licence is **all rights reserved** — which would impose terms stricter
than the original. **This file supplies the missing grant.**

The in-app credits screen (Settings › Info › Open source and sources) satisfies the attribution
requirement of §3(a); this file states the **distribution licence**, which is a separate obligation.

Background: `docs/release/ip-audit.md`, section 2.
