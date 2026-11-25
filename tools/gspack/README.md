# tools/gspack — 잠금 팩(`.gspack`) 파이썬 도구

설계 SSOT: `docs/design-reviews/external-snippet-packs.md` 12절 (형식 12-2 · 상한 12-3 · 비밀번호 12-4 · KDF/AEAD 12-5 · AAD 12-6 · 실패 코드 12-7 · 안쪽 CSV 12-8 · 제작 규칙 12-9 · 벡터 12-11).

**앱 코드(Swift `Packages/PackImport/Sources/PackImport/GSPack*.swift`)와 코드를 나누지 않는 독립 구현이다.** 같은 코드로 만든 파일을 같은 코드가 푸는 시험은 증거가 아니라서(12-11), 표준 `json`·`hashlib`·`base64`와 `cryptography`의 `AESGCM`만으로 같은 규칙을 다시 짰다. 개발용 도구이며 앱·키보드에 실리지 않는다.

## 준비

- Python 3.12 이상, `cryptography`(확인한 버전 48.0.0) — `python3 -m pip install cryptography`

## 파일 목록

| 파일 | 하는 일 |
|---|---|
| `gspack.py` | 라이브러리(`build_aad`·`seal_with_key`·`parse_envelope`·`open_envelope`) + CLI(`make`·`verify`) |
| `make_vectors.py` | 시험 벡터 고정 파일 + `vectors.json` 생성 → `Packages/PackImport/Tests/PackImportTests/Fixtures/gspack/` |

## 쓰는 법

```bash
# 잠그기 — 비밀번호는 입력 창에서 두 번(또는 환경 변수 GSPACK_PASSWORD). 인자로는 받지 않는다
python3 tools/gspack/gspack.py make --csv 팩.csv --name "팩 이름" [--rights "출처"] --out 팩.gspack [--iterations 600000] [--force]

# 풀어 보기 — 내용은 출력하지 않는다. OK + 평문 SHA-256, 또는 실패 코드(M1~M6·EMPTY)
python3 tools/gspack/gspack.py verify --in 팩.gspack

# 시험 벡터 다시 만들기 / 커밋된 파일과 같은지만 확인
python3 tools/gspack/make_vectors.py
python3 tools/gspack/make_vectors.py --check
```

- 출력은 **경로·바이트 수·평문 SHA-256뿐**이다. 비밀번호·평문은 어디에도 찍지 않는다.
- `GSPACK_PASSWORD`는 셸 기록·프로세스 환경에 남을 수 있다 — 사람이 쓸 때는 입력 창을 쓴다(환경 변수는 자동화용).

## 제작 규칙 (`make`, 12-4·12-9)

- 비밀번호: NFC, 코드 포인트 8개 이상, UTF-8 256바이트 이하, 앞뒤 공백·제어 문자(U+0000~U+001F·U+007F) 거부
- 팩 이름: 필수 — 앞뒤 공백 제거 → NFC → 1자 이상·`PackLimits.name` 이내·제어 문자 없음
- 출처: 선택 — NFC·`PackLimits.license` 이내·제어 문자 없음(자르지 않는다)
- CSV: 엄격 UTF-8·비어 있지 않음·3,000,000바이트 이하. **바이트 그대로**(BOM 포함) 잠근다 — 변환·인코딩 추정 없음
- 결과를 다시 파싱하고 같은 키로 풀어 평문 바이트가 같은지 확인한 뒤에만 파일을 쓴다(기존 파일은 `--force` 없이는 덮어쓰지 않는다)

**알려진 차이 — 「글자」 축:** 파이썬 표준 라이브러리에는 grapheme 분할이 없어 이름·출처의 글자 수(40·120)를 **코드 포인트 수**로 잰다.
코드 포인트 수 ≥ Swift `String.count`이므로 앱보다 **보수적**이다 — 이 도구가 만든 파일은 앱이 반드시 받지만, 결합 문자·이모지 조합이
많은 이름은 앱이 받을 수 있어도 이 도구(`make`·`verify`)가 거부할 수 있다. 벡터는 이 차이가 나는 구간을 쓰지 않는다.

## 시험 벡터

- `make_vectors.py`는 salt·nonce를 벡터 id에서 유도한 고정값으로 써서 다시 돌려도 같은 바이트를 낸다.
- 12-6 작동 예시(AAD 87바이트 16진·파생 키·암호문·12-2 예시 파일 글자)를 **그대로 재현하는지 단언**하고, 만든 모든 벡터를 파이썬 검증기로 다시 풀어
  기대 코드와 맞는지 확인한 뒤에만 쓴다. Swift 시험(`swift test --package-path Packages/PackImport --filter GSPack`)이 같은 파일을 두 번째 구현으로 확인한다.
- 대부분 반복 수 300,000(시험 시간), V01·12-6 예시·V15는 600,000, V20 경계는 300,000·2,000,000.
- 수 MB 경계 V27(③)·V28(①)은 커밋하지 않고 Swift 시험 안에서 만든다. V30(확장자 분기)은 가져오기 세션 몫이라 여기 없다.
- `vectors.json`의 비밀번호는 **시험 전용 값**이고 UTF-8 16진으로 든다(NUL·NFD를 그대로 보존).
