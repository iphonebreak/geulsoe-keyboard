# `emoji.tde` — 라이선스 고지 / Licence notice

이 파일은 **같은 디렉터리의 `emoji.tde` 한 파일에만** 적용된다.
저장소의 나머지(소스 코드·다른 데이터 파일)는 대상이 아니다. `EmojiCuration.json`(손질 목록)은
이 저장소가 직접 고른 짝이라 이 고지의 대상이 아니다.

This notice applies to **`emoji.tde` in this directory only** — not to the source code, to the other
data files beside it, or to `EmojiCuration.json` (pairs chosen by this project).

---

## 한국어

`emoji.tde` 는 Unicode CLDR 한국어 이모지 주석을 변환한 데이터이며, 원 데이터의
**Unicode License v3 (SPDX `Unicode-3.0`)** 조건에 따라 아래 저작권·허가 고지를 함께 싣는다.

- **원 데이터** — Unicode CLDR `common/annotations/ko.xml`, `common/annotationsDerived/ko.xml`
- **버전** — CLDR 48.2 (`release-48-2`), 커밋 `11299982335beb974c1c63c45265184e759c0f41`
- **위치** — https://github.com/unicode-org/cldr/tree/11299982335beb974c1c63c45265184e759c0f41/common/annotations
- **라이선스** — 같은 커밋의 `LICENSE`(아래 원문, SHA-256 `b49d0e9f8ead51ca8b7df6fec89cc3ae6809198b4b9d43c74216da0118f23f5b`)

### 변환 내용

`tools/convert_emoji.py` 가 다음을 한다.

1. 키워드(`|` 분할)와 tts(짧은 이름)를 모두 검색 키로 삼아 **단어 → 이모지** 역색인으로 뒤집는다.
2. 한글 음절 2~12자 키(`^[가-힣]{2,12}$`)만 남긴다.
3. Unicode 15.0 `emoji-data.txt` 기준으로 이모지 표현이 기본인 단일 코드포인트만 남긴다
   (피부색·머리색 구성요소·지역 표시자 제외).
4. 키마다 tts가 키와 같은 이모지의 순번을 덧붙여 mmap 이진 탐색용 이진 포맷으로 다시 쓴다.

## English

`emoji.tde` is converted from the Unicode CLDR Korean emoji annotations
(`common/annotations/ko.xml`, `common/annotationsDerived/ko.xml`, CLDR 48.2, commit
`11299982335beb974c1c63c45265184e759c0f41`). As required by the **Unicode License v3**, the copyright
and permission notice is reproduced below. `tools/convert_emoji.py` inverts keywords and tts names
into a word → emoji index, keeps Hangul keys of 2-12 syllables and single code points with default
emoji presentation per Unicode 15.0 `emoji-data.txt`, and writes a binary format for mmap lookup.

---

```text
UNICODE LICENSE V3

COPYRIGHT AND PERMISSION NOTICE

Copyright © 2004-2026 Unicode, Inc.

NOTICE TO USER: Carefully read the following legal agreement. BY
DOWNLOADING, INSTALLING, COPYING OR OTHERWISE USING DATA FILES, AND/OR
SOFTWARE, YOU UNEQUIVOCALLY ACCEPT, AND AGREE TO BE BOUND BY, ALL OF THE
TERMS AND CONDITIONS OF THIS AGREEMENT. IF YOU DO NOT AGREE, DO NOT
DOWNLOAD, INSTALL, COPY, DISTRIBUTE OR USE THE DATA FILES OR SOFTWARE.

Permission is hereby granted, free of charge, to any person obtaining a
copy of data files and any associated documentation (the "Data Files") or
software and any associated documentation (the "Software") to deal in the
Data Files or Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, and/or sell
copies of the Data Files or Software, and to permit persons to whom the
Data Files or Software are furnished to do so, provided that either (a)
this copyright and permission notice appear with all copies of the Data
Files or Software, or (b) this copyright and permission notice appear in
associated Documentation.

THE DATA FILES AND SOFTWARE ARE PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
THIRD PARTY RIGHTS.

IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS INCLUDED IN THIS NOTICE
BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT OR CONSEQUENTIAL DAMAGES,
OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS,
WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION,
ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THE DATA
FILES OR SOFTWARE.

Except as contained in this notice, the name of a copyright holder shall
not be used in advertising or otherwise to promote the sale, use or other
dealings in these Data Files or Software without prior written
authorization of the copyright holder.

SPDX-License-Identifier: Unicode-3.0
```
