#!/usr/bin/env python3
"""잠금 팩(.gspack) 상호운용 시험 벡터 생성기 — PDR external-snippet-packs.md 12-11.

`tools/gspack/gspack.py`(파이썬 독립 구현)로 고정 파일과 `vectors.json`을 만든다. 앱 시험
(`swift test --package-path Packages/PackImport --filter GSPack`)은 **커밋된 파일만** 읽는다.

- salt·nonce는 벡터 id에서 유도한 **고정값**이라 다시 돌려도 같은 바이트가 나온다(`--check`가 비교).
- 12-6 작동 예시(AAD 87바이트 16진·파생 키·암호문)를 **그대로 재현하는지 단언**한다 — 틀리면 아무것도 쓰지 않는다.
- 만든 뒤 모든 벡터를 같은 파이썬 검증기로 다시 풀어 기대 코드와 맞는지 확인한다(Swift가 두 번째 독립 구현이다).
- 비밀번호는 **시험 전용 값**이다. vectors.json에 UTF-8 16진으로 든다(NUL·NFD를 그대로 보존).
- 수 MB짜리 경계(V27 ③·V28 ①)는 커밋하지 않는다 — Swift 시험 안에서 만든다.

사용:
  python3 tools/gspack/make_vectors.py          # 고정 파일 다시 쓰기
  python3 tools/gspack/make_vectors.py --check  # 커밋된 파일과 같은지만 확인(쓰지 않음)
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import sys
import unicodedata
from pathlib import Path

sys.dont_write_bytecode = True  # tools/gspack/에 __pycache__를 남기지 않는다
sys.path.insert(0, str(Path(__file__).resolve().parent))
import gspack  # noqa: E402  (같은 폴더의 파이썬 독립 구현)

REPO = Path(__file__).resolve().parents[2]
OUT_DIR = REPO / "Packages/PackImport/Tests/PackImportTests/Fixtures/gspack"
FAST = 300_000  # 시험 시간을 줄이려고 대부분 하한을 쓴다(V01·12-6 예시·V15·V20 경계만 다르다)

# ── 12-6 작동 예시 (설계 문서의 [실측] 값) ──────────────────────────────────
SPEC_AAD_HEX = ("0000000c6765756c736f652d7061636b0001000000086373762d757466380000001970626b6466322d7368613235362b"
                "6165732d3235362d67636d000927c000000010ecb0acec86a1eab08020ec8398ed948c00000000")
SPEC_PASSWORD = "샘플비밀번호-2026"
SPEC_PASSWORD_HEX = "ec8398ed948cebb984ebb080ebb288ed98b82d32303236"
SPEC_SALT = bytes(range(0x10, 0x20))
SPEC_NONCE = bytes(range(0xA0, 0xAC))
SPEC_KEY_HEX = "0d49353d3c8a5c5ada032ce31753dfe39df5177a25d3554ca0ae31015c984893"
SPEC_PLAINTEXT = "#이름,찬송가 샘플\n번호,본문\n1,가나다\n".encode("utf-8")
SPEC_CIPHERTEXT_B64 = "GS8ROstM9CdUmOuCaB6mlUthEGIgXKgpbqAKqBe3uO3BTXLl6L7tLJLEPLYM1wzdQl9hBgUcp2ygHWcL0s1geK9lJA=="
SPEC_FILE_TEXT = """{
  "format": "geulsoe-pack",
  "version": 1,
  "inner": "csv-utf8",
  "meta": {
    "name": "찬송가 샘플",
    "rights": ""
  },
  "encryption": {
    "scheme": "pbkdf2-sha256+aes-256-gcm",
    "iterations": 600000,
    "salt": "EBESExQVFhcYGRobHB0eHw==",
    "nonce": "oKGio6Slpqeoqaqr"
  },
  "ciphertext": "GS8ROstM9CdUmOuCaB6mlUthEGIgXKgpbqAKqBe3uO3BTXLl6L7tLJLEPLYM1wzdQl9hBgUcp2ygHWcL0s1geK9lJA=="
}
"""

CSV_KO = "단축어,본문\n안녕,안녕하세요\n감사,감사합니다\n".encode("utf-8")
CSV_EN = b"trigger,body\nhi,hello there\n"


def fixed_bytes(label: str, size: int) -> bytes:
    return hashlib.sha256(f"gspack-vector:{label}".encode("utf-8")).digest()[:size]


class Builder:
    """파일·벡터 목록을 메모리에 모은다 — 다 맞으면 한 번에 쓴다."""

    def __init__(self):
        self.files: dict[str, bytes] = {}
        self.vectors: list[dict] = []
        self.key_cache: dict[tuple, bytes] = {}

    # 파일

    def add_file(self, name: str, data: bytes) -> str:
        assert name not in self.files or self.files[name] == data, name
        self.files[name] = data
        return name

    def seal(self, label: str, plaintext: bytes, password: str, name: str, rights: str,
             iterations: int = FAST) -> tuple[gspack.Envelope, bytes]:
        salt, nonce = fixed_bytes(f"{label}:salt", 16), fixed_bytes(f"{label}:nonce", 12)
        cache_key = (gspack.password_bytes(password), salt, iterations)
        key = self.key_cache.get(cache_key)
        if key is None:
            key = gspack.derive_key(*cache_key)
            self.key_cache[cache_key] = key
        return gspack.seal_with_key(plaintext, key, name, rights, iterations, salt, nonce), key

    # 벡터

    def vector(self, vid: str, case: str, file: str, password: str, expect: str) -> None:
        self.vectors.append({
            "id": vid,
            "case": case,
            "file": file,
            "password_utf8_hex": password.encode("utf-8").hex(),
            "expect": expect,
        })


def envelope_dict(env: gspack.Envelope) -> dict:
    return gspack.envelope_object(env)


def dumps(obj, *, ensure_ascii: bool = False) -> bytes:
    return (json.dumps(obj, ensure_ascii=ensure_ascii, indent=2) + "\n").encode("utf-8")


def with_bit_flipped(data: bytes, index: int) -> bytes:
    raw = bytearray(data)
    raw[index] ^= 0x01
    return bytes(raw)


def spec_example(b: Builder) -> None:
    aad = gspack.build_aad("찬송가 샘플", "", 600_000)
    assert len(aad) == 87 and aad.hex() == SPEC_AAD_HEX, "12-6 AAD 불일치"
    pw = gspack.password_bytes(SPEC_PASSWORD)
    assert pw.hex() == SPEC_PASSWORD_HEX, "12-6 비밀번호 바이트 불일치"
    key = gspack.derive_key(pw, SPEC_SALT, 600_000)
    assert key.hex() == SPEC_KEY_HEX, "12-6 파생 키 불일치"
    env = gspack.seal_with_key(SPEC_PLAINTEXT, key, "찬송가 샘플", "", 600_000, SPEC_SALT, SPEC_NONCE)
    assert base64.b64encode(env.sealed).decode("ascii") == SPEC_CIPHERTEXT_B64, "12-6 암호문 불일치"
    rendered = gspack.render(env)
    assert rendered == SPEC_FILE_TEXT.encode("utf-8"), "12-2 예시 파일 텍스트 불일치"
    b.add_file("v00-worked-example.gspack", rendered)
    b.vector("V00", "12-6 작동 예시(600,000)", "v00-worked-example.gspack", SPEC_PASSWORD, "ok")


def positive_vectors(b: Builder) -> dict[str, tuple[gspack.Envelope, bytes]]:
    """V01~V09·V13·V20 경계·V22·V24 경계 — 열리는 파일."""
    made: dict[str, tuple[gspack.Envelope, bytes]] = {}

    def make(file: str, vid: str, case: str, plaintext: bytes, password: str, name: str, rights: str,
             iterations: int = FAST, *, ensure_ascii: bool = False) -> gspack.Envelope:
        env, key = b.seal(file, plaintext, password, name, rights, iterations)
        b.add_file(file, gspack.render(env, ensure_ascii=ensure_ascii))
        b.vector(vid, case, file, password, "ok")
        made[file] = (env, key)
        return env

    make("v01-minimal.gspack", "V01", "정상 최소 — ASCII 이름·빈 출처·ASCII 비밀번호·600,000",
         CSV_EN, "correct horse 2026", "Sample Pack", "", 600_000)
    make("v02-korean.gspack", "V02", "한글 이름·출처·본문", CSV_KO, "한글비밀번호-2026", "인사말 모음", "글쇠 예시 · 자유 이용")
    make("v03-bom.gspack", "V03", "평문이 UTF-8 BOM으로 시작 — BOM 벗고 일치", gspack.UTF8_BOM + CSV_KO,
         "bom-password-1", "BOM 팩", "")
    make("v03-double-bom.gspack", "V03-double", "BOM 두 번 — 평문 CSV 디코더(F8)처럼 둘 다 벗긴다",
         gspack.UTF8_BOM * 2 + CSV_KO, "bom-password-2", "BOM 두 번", "")
    make("v03-triple-bom.gspack", "V03-triple", "BOM 세 번 — 둘만 벗기고 U+FEFF 하나는 글자에 남는다",
         gspack.UTF8_BOM * 3 + CSV_KO, "bom-password-3", "BOM 세 번", "")

    nfc = "한글비번테스트"
    make("v04-nfc-password.gspack", "V04", "NFC 비밀번호로 만든 파일을 NFC로 연다", CSV_KO, nfc, "정규화 팩", "")
    nfd = unicodedata.normalize("NFD", nfc)
    assert nfd != nfc
    b.vector("V04-nfd", "같은 파일을 NFD(한글 자모 분해형)로 입력", "v04-nfc-password.gspack", nfd, "ok")

    decomposed = "café-Å-क़-pass"
    make("v05-combining.gspack", "V05", "결합 문자·NFC 구성 제외(U+212B·U+0958) 입력으로 만든 파일", CSV_EN,
         decomposed, "Combining", "")
    b.vector("V05-composed", "U+00E9·U+00C5·U+0915 U+093C로 입력", "v05-combining.gspack",
             "café-Å-क़-pass", "ok")
    b.vector("V05-mixed", "섞인 형태(U+00E9 + U+212B + U+0958)", "v05-combining.gspack",
             "café-Å-क़-pass", "ok")

    make("v06-nul-password.gspack", "V06", "비밀번호에 NUL — 바이트 길이 KDF", CSV_EN, "ab\u0000cd-nul-pass", "NUL", "")
    b.vector("V06-truncated", "NUL 앞에서 잘린 비밀번호(C 문자열처럼)", "v06-nul-password.gspack", "ab", "M4")

    make("v07-fullwidth.gspack", "V07-self", "전각 비밀번호 파일을 전각으로 연다", CSV_EN, "ＡＢＣＤ１２３４", "Fullwidth", "")
    b.vector("V07", "전각으로 만든 파일을 ASCII로 연다(NFKC가 아니다)", "v07-fullwidth.gspack", "ABCD1234", "M4")

    pw256 = "가" * 85 + "a"
    assert len(pw256.encode("utf-8")) == 256
    make("v08-password-256.gspack", "V08", "비밀번호 256바이트 경계", CSV_EN, pw256, "Long password", "")

    make("v09-empty-meta.gspack", "V09", "이름·출처 빈 문자열", CSV_EN, "empty-meta-pass", "", "")
    b.vector("V10", "틀린 비밀번호", "v02-korean.gspack", "한글비밀번호-2027", "M4")
    make("v13-empty-plaintext.gspack", "V13", "빈 평문(암호문 = tag 16B)", b"", "empty-plain-pass", "빈 팩", "")

    make("v20-iterations-300000.gspack", "V20-300000", "iterations 하한 300,000", CSV_EN, "iter-pass-1", "Iter", "", 300_000)
    make("v20-iterations-2000000.gspack", "V20-2000000", "iterations 상한 2,000,000", CSV_EN, "iter-pass-1", "Iter", "",
         2_000_000)

    emoji_name, rights = "이모지 😀 팩", "출처 ✓ 🎉"
    env22 = make("v22-raw.gspack", "V22-raw", "메타 원문 UTF-8", CSV_KO, "escape-pass-22", emoji_name, rights)
    escaped = gspack.render(env22).decode("utf-8")
    for text in (emoji_name, rights):
        upper = "".join(ch if ord(ch) < 0x80 else
                        "".join(f"\\u{unit:04X}" for unit in _utf16_units(ch)) for ch in text)
        escaped = escaped.replace(json.dumps(text, ensure_ascii=False), f'"{upper}"', 1)
    assert "\\uD83D\\uDE00" in escaped
    b.add_file("v22-escaped.gspack", escaped.encode("utf-8"))
    b.vector("V22-escaped", "같은 메타를 \\uXXXX(대문자·서로게이트 쌍)로 쓴 파일 — 같은 AAD", "v22-escaped.gspack",
             "escape-pass-22", "ok")

    make("v24-name-40.gspack", "V24-name-40", "이름 40자(한글) 경계", CSV_EN, "limit-pass-24", "가" * 40, "")
    make("v24-rights-120.gspack", "V24-rights-120", "출처 120자 경계", CSV_EN, "limit-pass-24", "x", "r" * 120)

    # 공백 변형 — 토큰 사이 \t·\r\n은 받는다(같은 AAD)
    env02, _ = made["v02-korean.gspack"]
    spaced = json.dumps(envelope_dict(env02), ensure_ascii=False, indent="\t").replace("\n", "\r\n") + "\r\n"
    b.add_file("v25-whitespace-tabs-crlf.gspack", spaced.encode("utf-8"))
    b.vector("V25-whitespace", "토큰 사이 탭·CRLF", "v25-whitespace-tabs-crlf.gspack", "한글비밀번호-2026", "ok")
    return made


def _utf16_units(ch: str) -> list[int]:
    raw = ch.encode("utf-16-be")
    return [int.from_bytes(raw[i:i + 2], "big") for i in range(0, len(raw), 2)]


def tamper_vectors(b: Builder, made) -> None:
    """V11·V12·V14·V15 — 파일만 바꾼다(AAD·키 재계산 없음) → M4."""
    env02, _ = made["v02-korean.gspack"]
    env01, _ = made["v01-minimal.gspack"]
    pw02, pw01 = "한글비밀번호-2026", "correct horse 2026"

    def write(file: str, vid: str, case: str, obj: dict, password: str) -> None:
        b.add_file(file, dumps(obj))
        b.vector(vid, case, file, password, "M4")

    obj = envelope_dict(env02)
    obj["ciphertext"] = base64.b64encode(with_bit_flipped(env02.sealed, len(env02.sealed) - 1)).decode()
    write("v11-tag-flip.gspack", "V11", "tag 마지막 바이트 1비트 뒤집음", obj, pw02)
    obj = envelope_dict(env02)
    obj["ciphertext"] = base64.b64encode(with_bit_flipped(env02.sealed, 0)).decode()
    write("v12-body-flip.gspack", "V12", "암호문 본문 1비트 뒤집음", obj, pw02)
    obj = envelope_dict(env02)
    obj["meta"]["name"] = "인사말 모음!"
    write("v14-name-changed.gspack", "V14-name", "meta.name만 바꿈", obj, pw02)
    obj = envelope_dict(env02)
    obj["meta"]["rights"] = "다른 출처"
    write("v14-rights-changed.gspack", "V14-rights", "meta.rights만 바꿈", obj, pw02)
    obj = envelope_dict(env01)
    obj["encryption"]["iterations"] = 600_001
    write("v15-iterations-changed.gspack", "V15-iterations", "iterations 600000→600001", obj, pw01)
    obj = envelope_dict(env02)
    obj["encryption"]["salt"] = base64.b64encode(with_bit_flipped(env02.salt, 3)).decode()
    write("v15-salt-flip.gspack", "V15-salt", "salt 1비트", obj, pw02)
    obj = envelope_dict(env02)
    obj["encryption"]["nonce"] = base64.b64encode(with_bit_flipped(env02.nonce, 5)).decode()
    write("v15-nonce-flip.gspack", "V15-nonce", "nonce 1비트", obj, pw02)


def inner_vectors(b: Builder) -> None:
    """V29 — 복호 성공 + 안쪽이 UTF-8 아님 → M5."""
    cases = [
        ("v29-cp949.gspack", "V29-cp949", "안쪽이 CP949", "단축어,본문\n안녕,안녕하세요\n".encode("cp949")),
        ("v29-utf16-bom.gspack", "V29-utf16", "안쪽이 UTF-16LE BOM", "﻿단축어,본문\n".encode("utf-16-le")),
        ("v29-bom-then-invalid.gspack", "V29-bom-invalid", "UTF-8 BOM 뒤 잘못된 바이트", gspack.UTF8_BOM + b"\xb0\xa1"),
        ("v29-surrogate.gspack", "V29-surrogate", "UTF-8로 인코딩한 서로게이트(ED A0 80)", b"a\xed\xa0\x80b"),
    ]
    for file, vid, case, plaintext in cases:
        env, _ = b.seal(file, plaintext, "inner-pass-29", "Inner", "")
        b.add_file(file, gspack.render(env))
        b.vector(vid, case, file, "inner-pass-29", "M5")


def structural_vectors(b: Builder, made) -> None:
    """V16~V19·V20 거부·V21·V23~V26 — 전부 KDF 전 거부."""
    env02, _ = made["v02-korean.gspack"]
    pw = "한글비밀번호-2026"
    base_text = gspack.render(env02).decode("utf-8")
    base = envelope_dict(env02)

    def raw(file: str, vid: str, case: str, text: str | bytes, expect: str = "M1") -> None:
        data = text if isinstance(text, bytes) else text.encode("utf-8")
        b.add_file(file, data)
        b.vector(vid, case, file, pw, expect)

    def edited(file: str, vid: str, case: str, edit, expect: str = "M1") -> None:
        obj = json.loads(json.dumps(base))
        edit(obj)
        raw(file, vid, case, dumps(obj), expect)

    def replaced(file: str, vid: str, case: str, old: str, new: str, expect: str = "M1") -> None:
        assert base_text.count(old) == 1, old
        raw(file, vid, case, base_text.replace(old, new), expect)

    # V16 중복 키
    replaced("v16-dup-version.gspack", "V16-version", "최상위 version 두 번", '"version": 1,', '"version": 1,\n  "version": 1,')
    replaced("v16-dup-name.gspack", "V16-name", "meta.name 두 번", '"name": "인사말 모음",',
             '"name": "인사말 모음",\n    "name": "인사말 모음",')
    replaced("v16-dup-escaped.gspack", "V16-escaped", "이스케이프 중복 — \"form\\u0061t\"", '"format": "geulsoe-pack",',
             '"format": "geulsoe-pack",\n  "form\\u0061t": "geulsoe-pack",')
    # V17 모르는 키
    edited("v17-unknown-top.gspack", "V17-top", "최상위 모르는 키", lambda o: o.update(comment="x"))
    edited("v17-hint.gspack", "V17-hint", "encryption.hint(A4 — 힌트 키 거부)", lambda o: o["encryption"].update(hint="생일"))
    edited("v17-meta-extra.gspack", "V17-meta", "meta 모르는 키", lambda o: o["meta"].update(author="x"))
    # V18 버전
    raw("v18-v2-arbitrary.gspack", "V18-v2", "version 2 + 나머지 구조 임의(배열·null 포함)",
        '{"format": "geulsoe-pack", "version": 2, "payload": [1, 2.5, true, null], "x": {"y": "z"}}\n', "M2")
    edited("v18-v2-v1shape.gspack", "V18-v2-v1shape", "version 2 + v1 모양", lambda o: o.update(version=2), "M2")
    replaced("v18-v-huge.gspack", "V18-huge", "version 큰 정수(30자리)", '"version": 1,', '"version": 123456789012345678901234567890,', "M2")
    raw("v18-v2-depth3.gspack", "V18-depth3", "version 2 + 깊이 3",
        '{"format": "geulsoe-pack", "version": 2, "a": {"b": {}}}', "M2")
    raw("v18-v2-depth4.gspack", "V18-depth4", "version 2 + 깊이 4 — 구문 단계(ⓑ)가 먼저",
        '{"format": "geulsoe-pack", "version": 2, "a": {"b": {"c": {}}}}', "M1")
    for suffix, literal in [("zero", "0"), ("string", '"1"'), ("float", "1.0"), ("exp", "1e0"),
                            ("leading-zero", "01"), ("negative", "-1"), ("negative-zero", "-0"), ("plus", "+1"),
                            ("float2", "2.0"), ("null", "null"), ("true", "true")]:
        replaced(f"v18-version-{suffix}.gspack", f"V18-{suffix}", f"version {literal}", '"version": 1,', f'"version": {literal},')
    raw("v18-no-format-v2.gspack", "V18-no-format", "format 없이 version 2", '{"version": 2}', "M1")
    # V19 고정값·최상위 타입
    replaced("v19-scheme.gspack", "V19-scheme", "scheme 모르는 값", '"pbkdf2-sha256+aes-256-gcm"', '"pbkdf2-sha512+aes-256-gcm"')
    replaced("v19-inner.gspack", "V19-inner", "inner 모르는 값", '"csv-utf8"', '"xlsx"')
    replaced("v19-format.gspack", "V19-format", "format 다른 값", '"geulsoe-pack"', '"geulsoe-pack2"')
    replaced("v19-format-case.gspack", "V19-format-case", "format 대소문자", '"geulsoe-pack"', '"Geulsoe-pack"')
    raw("v19-top-array.gspack", "V19-array", "최상위 배열", '[{"format": "geulsoe-pack", "version": 1}]')
    raw("v19-top-string.gspack", "V19-string", "최상위 문자열", '"geulsoe-pack"')
    # V20 iterations 거부
    for suffix, literal in [("299999", "299999"), ("2000001", "2000001"), ("float", "300000.0"), ("exp", "3e5"),
                            ("11-digits", "10000000000"), ("negative", "-300000"), ("string", '"300000"'),
                            ("huge", "9" * 400)]:
        replaced(f"v20-iterations-{suffix}.gspack", f"V20-{suffix}", f"iterations {literal[:20]}",
                 '"iterations": 300000,', f'"iterations": {literal},')
    # V21 base64
    salt = base["encryption"]["salt"]
    nonce = base["encryption"]["nonce"]
    assert salt.endswith("==") and nonce[-1] != "="
    bad_salts = {
        "no-padding": salt.rstrip("="),
        "url-safe": "-" + salt[1:],
        "newline": salt[:8] + "\\n" + salt[8:],
        "space": salt[:8] + " " + salt[8:],
        "short-padding": salt[:-1],
        "noncanonical": _noncanonical(salt),
        "15-bytes": base64.b64encode(env02.salt[:15]).decode(),
        "17-bytes": base64.b64encode(env02.salt + b"\x00").decode(),
        "inner-padding": salt[:4] + "=" + salt[5:],
    }
    for suffix, value in bad_salts.items():
        replaced(f"v21-salt-{suffix}.gspack", f"V21-salt-{suffix}", f"salt {suffix}", f'"salt": "{salt}"', f'"salt": "{value}"')
    for suffix, value in {"11-bytes": base64.b64encode(env02.nonce[:11]).decode(),
                          "13-bytes": base64.b64encode(env02.nonce + b"\x00").decode()}.items():
        replaced(f"v21-nonce-{suffix}.gspack", f"V21-nonce-{suffix}", f"nonce {suffix}", f'"nonce": "{nonce}"', f'"nonce": "{value}"')
    ct = base["ciphertext"]
    replaced("v21-ct-noncanonical.gspack", "V21-ct-noncanonical", "ciphertext 남는 비트 ≠ 0",
             f'"ciphertext": "{ct}"', f'"ciphertext": "{_noncanonical(ct)}"')
    replaced("v21-ct-urlsafe.gspack", "V21-ct-urlsafe", "ciphertext URL-safe 글자",
             f'"ciphertext": "{ct}"', f'"ciphertext": "_{ct[1:]}"')
    edited("v21-ct-15-bytes.gspack", "V21-ct-15", "ciphertext 15바이트(tag보다 짧다)",
           lambda o: o.update(ciphertext=base64.b64encode(env02.sealed[:15]).decode()))
    edited("v21-ct-empty.gspack", "V21-ct-empty", "ciphertext 빈 문자열", lambda o: o.update(ciphertext=""))
    # V23 메타 서로게이트·제어 문자
    for suffix, literal in [("lone-high", "\\ud800"), ("lone-low", "\\udc00"), ("high-then-ascii", "\\ud800\\u0041"),
                            ("nul", "a\\u0000b"), ("bel", "a\\u0007b"), ("u2028", "a\\u2028b"), ("u2029-raw", "a b"),
                            ("del", "a\\u007fb"), ("c1", "a\\u0085b"), ("tab", "a\\tb")]:
        replaced(f"v23-name-{suffix}.gspack", f"V23-{suffix}", f"meta.name {suffix}",
                 '"name": "인사말 모음"', f'"name": "{literal}"')
    replaced("v23-rights-newline.gspack", "V23-rights-newline", "meta.rights 줄바꿈",
             '"rights": "글쇠 예시 · 자유 이용"', '"rights": "글쇠\\n예시"')
    replaced("v23-key-lone-surrogate.gspack", "V23-key", "모르는 키 이름에 짝 없는 서로게이트",
             '"inner": "csv-utf8",', '"inner": "csv-utf8",\n  "\\udfff": 1,')
    # V24 길이 초과
    for suffix, name in [("41-chars", "a" * 41), ("41-korean", "가" * 41), ("121-scalars", "a" * 121),
                         ("bytes-168", "👍🏽" * 21)]:
        edited(f"v24-name-{suffix}.gspack", f"V24-name-{suffix}", f"meta.name {suffix}",
               lambda o, n=name: o["meta"].update(name=n))
    for suffix, rights in [("121-chars", "r" * 121), ("bytes-488", "👍🏽" * 61)]:
        edited(f"v24-rights-{suffix}.gspack", f"V24-rights-{suffix}", f"meta.rights {suffix}",
               lambda o, r=rights: o["meta"].update(rights=r))
    # V25 봉투 겉모양
    raw("v25-bom.gspack", "V25-bom", "봉투 BOM 시작", gspack.UTF8_BOM + base_text.encode("utf-8"))
    raw("v25-truncated.gspack", "V25-truncated", "잘린 JSON", base_text[: len(base_text) // 2])
    raw("v25-trailing-garbage.gspack", "V25-garbage", "토큰 뒤 쓰레기", base_text + "x")
    raw("v25-two-objects.gspack", "V25-two", "객체 두 개", base_text + "{}")
    raw("v25-plain-csv.gspack", "V25-csv", "평문 CSV를 이름만 .gspack", CSV_KO)
    raw("v25-empty.gspack", "V25-empty", "빈 파일", b"")
    raw("v25-form-feed.gspack", "V25-formfeed", "토큰 사이 폼 피드(JSON 공백 아님)", base_text.replace("{\n", "{\f\n", 1))
    raw("v25-invalid-utf8.gspack", "V25-invalid-utf8", "봉투가 UTF-8 아님", base_text.encode("utf-8").replace(
        "인사말".encode("utf-8"), "인사말".encode("cp949")))
    raw("v25-nan.gspack", "V25-nan", "NaN 리터럴", base_text.replace('"version": 1,', '"version": NaN,'))
    raw("v25-deep.gspack", "V25-deep", "깊은 중첩(재귀 방어)", "[" * 1200 + "]" * 1200)
    # V26 누락·타입
    for key in gspack.ENVELOPE_KEYS:
        edited(f"v26-missing-{key}.gspack", f"V26-missing-{key}", f"최상위 {key} 누락", lambda o, k=key: o.pop(k))
    edited("v26-meta-name-only.gspack", "V26-meta-name", "meta에 name만", lambda o: o["meta"].pop("rights"))
    edited("v26-meta-rights-only.gspack", "V26-meta-rights", "meta에 rights만", lambda o: o["meta"].pop("name"))
    for key in gspack.ENCRYPTION_KEYS:
        edited(f"v26-encryption-missing-{key}.gspack", f"V26-enc-{key}", f"encryption.{key} 누락",
               lambda o, k=key: o["encryption"].pop(k))
    edited("v26-meta-string.gspack", "V26-meta-type", "meta가 문자열", lambda o: o.update(meta="x"))
    edited("v26-encryption-array.gspack", "V26-enc-type", "encryption이 배열", lambda o: o.update(encryption=[]))
    edited("v26-ciphertext-number.gspack", "V26-ct-type", "ciphertext가 숫자", lambda o: o.update(ciphertext=1))
    edited("v26-name-number.gspack", "V26-name-type", "meta.name이 숫자", lambda o: o["meta"].update(name=1))
    edited("v26-rights-null.gspack", "V26-rights-null", "meta.rights가 null", lambda o: o["meta"].update(rights=None))
    edited("v26-salt-bool.gspack", "V26-salt-bool", "salt가 불리언", lambda o: o["encryption"].update(salt=True))


def _noncanonical(text: str) -> str:
    """패딩 앞 마지막 글자의 남는 비트를 켠다 — 관대한 디코더는 같은 바이트로 읽는다."""
    body = text.rstrip("=")
    padding = text[len(body):]
    assert padding, "패딩이 있어야 남는 비트가 있다"
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    last = alphabet.index(body[-1])
    return body[:-1] + alphabet[last | 1] + padding


def verify_all(b: Builder) -> None:
    """만든 벡터를 파이썬 검증기로 다시 풀어 기대와 맞추고, 열리는 것엔 평문 해시·AAD를 적는다."""
    for vector in b.vectors:
        data = b.files[vector["file"]]
        password = bytes.fromhex(vector["password_utf8_hex"]).decode("utf-8")
        try:
            envelope = gspack.parse_envelope(data)
        except gspack.GSPackError as failure:
            assert failure.code == vector["expect"], (vector["id"], failure.code)
            vector["stage"] = "parse"
            continue
        vector["stage"] = "open"
        vector["aad_hex"] = gspack.build_aad(envelope.name, envelope.rights, envelope.iterations).hex()
        vector["iterations"] = envelope.iterations
        try:
            _, text = gspack.open_envelope(envelope, password)
        except gspack.GSPackError as failure:
            assert failure.code == vector["expect"], (vector["id"], failure.code)
            continue
        assert vector["expect"] == "ok", (vector["id"], "열렸다")
        vector["text_sha256"] = hashlib.sha256(text.encode("utf-8")).hexdigest()
        vector["text_utf8_bytes"] = len(text.encode("utf-8"))


def build() -> Builder:
    b = Builder()
    spec_example(b)
    made = positive_vectors(b)
    tamper_vectors(b, made)
    inner_vectors(b)
    structural_vectors(b, made)
    verify_all(b)
    ids = [v["id"] for v in b.vectors]
    assert len(ids) == len(set(ids)), "벡터 id 중복"
    # V22 — 이스케이프 파일과 원문 파일은 같은 AAD
    aad = {v["id"]: v.get("aad_hex") for v in b.vectors}
    assert aad["V22-raw"] == aad["V22-escaped"]
    b.add_file("vectors.json", vectors_json(b.vectors))
    return b


def vectors_json(vectors: list[dict]) -> bytes:
    """사람이 읽게 한글 그대로, 벡터 하나에 한 줄(비밀번호는 16진이라 NUL·NFD도 그대로 남는다)."""
    header = {
        "generator": "tools/gspack/make_vectors.py",
        "spec": "docs/design-reviews/external-snippet-packs.md 12-11",
        "note": "비밀번호는 시험 전용 값이다. expect: ok | M1~M5. stage: parse(KDF 전 거부) | open(KDF 1회)",
    }
    lines = [f'  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)},' for key, value in header.items()]
    rows = ",\n".join(f"    {json.dumps(vector, ensure_ascii=False)}" for vector in vectors)
    return ("{\n" + "\n".join(lines) + '\n  "vectors": [\n' + rows + "\n  ]\n}\n").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="커밋된 고정 파일과 같은지만 본다")
    args = parser.parse_args()
    b = build()
    total = sum(len(data) for data in b.files.values())
    if args.check:
        existing = {p.name for p in OUT_DIR.glob("*")} if OUT_DIR.exists() else set()
        mismatched = [name for name, data in b.files.items()
                      if not (OUT_DIR / name).exists() or (OUT_DIR / name).read_bytes() != data]
        stale = sorted(existing - set(b.files))
        if mismatched or stale:
            print(f"불일치 {len(mismatched)}개 · 남는 파일 {len(stale)}개: {(mismatched + stale)[:10]}")
            return 1
        print(f"일치: 파일 {len(b.files)}개 · {total:,}바이트 · 벡터 {len(b.vectors)}개")
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale in OUT_DIR.glob("*"):
        if stale.name not in b.files and stale.suffix in (".gspack", ".json"):
            os.remove(stale)
    for name, data in b.files.items():
        (OUT_DIR / name).write_bytes(data)
    print(f"썼다: {OUT_DIR.relative_to(REPO)} — 파일 {len(b.files)}개 · {total:,}바이트 · 벡터 {len(b.vectors)}개")
    return 0


if __name__ == "__main__":
    sys.exit(main())
