#!/usr/bin/env python3
"""글쇠 잠금 팩(.gspack) 파이썬 도구 — 라이브러리 + CLI.

설계 SSOT: docs/design-reviews/external-snippet-packs.md 12절(12-2 형식·12-3 상한·12-4 비밀번호·
12-5 KDF/AEAD·12-6 AAD·12-7 실패 코드·12-8 안쪽 CSV·12-9 제작 규칙·12-11 벡터).

★ **독립 구현이다** — 앱(Swift `PackImport/GSPack*`)과 코드를 나누지 않는다. 같은 코드로 만든 파일을
같은 코드가 푸는 시험은 증거가 아니므로(12-11 원칙), 이 파일은 표준 `json`·`hashlib`·`base64`와
`cryptography`(AESGCM)만으로 같은 규칙을 다시 짠다. 개발용 도구다 — 앱·키보드에 실리지 않는다.

★ 비밀번호·평문을 출력하지 않는다. 비밀번호는 인자로 받지 않는다(환경 변수 `GSPACK_PASSWORD` 또는 getpass).
출력은 경로·바이트 수·평문 SHA-256뿐이다.

사용:
  python3 tools/gspack/gspack.py make --csv IN.csv --name 이름 [--rights 출처] --out OUT.gspack [--iterations 600000] [--force]
  python3 tools/gspack/gspack.py verify --in X.gspack
"""
from __future__ import annotations

import argparse
import base64
import binascii
import getpass
import hashlib
import json
import os
import re
import sys
import unicodedata
from dataclasses import dataclass

# ── 고정값·상한 (12-2·12-3·12-4·12-5) ─────────────────────────────────────────

FORMAT = "geulsoe-pack"
VERSION = 1
INNER = "csv-utf8"
SCHEME = "pbkdf2-sha256+aes-256-gcm"

ENVELOPE_BYTES = 4_100_000            # ① 봉투
CIPHERTEXT_B64_CHARS = 4_000_024      # ② base64 글자 (디코드 전)
CIPHERTEXT_BYTES = 3_000_016          # ③ 디코드한 암호문‖tag
PLAINTEXT_BYTES = 3_000_000           # ④ 복호화본 = PackLimits.fileBytes
ITERATIONS_MIN = 300_000
ITERATIONS_MAX = 2_000_000
ITERATIONS_MAX_DIGITS = 10
MAKER_ITERATIONS = 600_000
PASSWORD_MAX_BYTES = 256
MAKER_PASSWORD_MIN_CODE_POINTS = 8
SALT_BYTES = 16
NONCE_BYTES = 12
TAG_BYTES = 16
KEY_BYTES = 32
MAX_DEPTH = 3

# PackLimits.name / PackLimits.license — (글자, UTF-8 바이트, 스칼라).
# 파이썬 표준 라이브러리에는 grapheme 분할이 없어 「글자」 축은 **코드 포인트 수**로 잰다 —
# 코드 포인트 ≥ grapheme이므로 앱(Swift `String.count`)보다 **보수적**이다(제작기가 만든 이름은 앱이 반드시 받는다).
NAME_LIMIT = (40, 160, 120)
RIGHTS_LIMIT = (120, 480, 360)

UTF8_BOM = b"\xef\xbb\xbf"
ENVELOPE_KEYS = ("format", "version", "inner", "meta", "encryption", "ciphertext")
META_KEYS = ("name", "rights")
ENCRYPTION_KEYS = ("scheme", "iterations", "salt", "nonce")

# 실패 코드 (12-7). EMPTY = 빈 비밀번호(KDF 시도 안 함)
M1, M2, M3, M4, M5, M6, EMPTY = "M1", "M2", "M3", "M4", "M5", "M6", "EMPTY"


class GSPackError(Exception):
    """값 없는 실패 — 코드만 든다(비밀번호·평문·봉투 값을 담지 않는다)."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Envelope:
    name: str
    rights: str
    iterations: int
    salt: bytes
    nonce: bytes
    sealed: bytes  # 암호문 ‖ tag(뒤 16B)


# ── AAD (12-6) ───────────────────────────────────────────────────────────────

def _field(text: str) -> bytes:
    raw = text.encode("utf-8")
    return len(raw).to_bytes(4, "big") + raw


def build_aad(name: str, rights: str, iterations: int) -> bytes:
    """F(format) ‖ U16(version) ‖ F(inner) ‖ F(scheme) ‖ U32(iterations) ‖ F(name) ‖ F(rights) — 정규화 없음."""
    return b"".join([
        _field(FORMAT),
        VERSION.to_bytes(2, "big"),
        _field(INNER),
        _field(SCHEME),
        iterations.to_bytes(4, "big"),
        _field(name),
        _field(rights),
    ])


# ── 비밀번호·KDF·AEAD (12-4·12-5) ───────────────────────────────────────────

def password_bytes(password: str) -> bytes:
    """수신 규칙: NFC → UTF-8. 자르지 않는다. 빈 값 → EMPTY, 256B 초과 → M6."""
    if password == "":
        raise GSPackError(EMPTY)
    raw = unicodedata.normalize("NFC", password).encode("utf-8")
    if len(raw) > PASSWORD_MAX_BYTES:
        raise GSPackError(M6)
    return raw


def derive_key(password: bytes, salt: bytes, iterations: int) -> bytes:
    return hashlib.pbkdf2_hmac("sha256", password, salt, iterations, KEY_BYTES)


def _aesgcm(key: bytes):
    try:
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    except ImportError:  # pragma: no cover — 개발 도구 설치 안내
        sys.exit("cryptography 패키지가 필요합니다: python3 -m pip install cryptography")
    return AESGCM(key)


def seal_with_key(plaintext: bytes, key: bytes, name: str, rights: str, iterations: int,
                  salt: bytes, nonce: bytes) -> Envelope:
    sealed = _aesgcm(key).encrypt(nonce, plaintext, build_aad(name, rights, iterations))
    return Envelope(name, rights, iterations, salt, nonce, sealed)


def envelope_object(env: Envelope) -> dict:
    """12-2 키 순서 그대로."""
    return {
        "format": FORMAT,
        "version": VERSION,
        "inner": INNER,
        "meta": {"name": env.name, "rights": env.rights},
        "encryption": {
            "scheme": SCHEME,
            "iterations": env.iterations,
            "salt": base64.b64encode(env.salt).decode("ascii"),
            "nonce": base64.b64encode(env.nonce).decode("ascii"),
        },
        "ciphertext": base64.b64encode(env.sealed).decode("ascii"),
    }


def render(env: Envelope, *, ensure_ascii: bool = False) -> bytes:
    """제작기 출력 형식 — JSON.stringify(obj, null, 2) + 끝 줄바꿈 하나와 같은 모양."""
    return (json.dumps(envelope_object(env), ensure_ascii=ensure_ascii, indent=2) + "\n").encode("utf-8")


def open_with_key(env: Envelope, key: bytes) -> bytes:
    """GCM open → ④ 상한. 돌려주는 것은 BOM을 벗기기 전 평문 바이트."""
    from cryptography.exceptions import InvalidTag
    if len(key) != KEY_BYTES:
        raise GSPackError(M4)
    try:
        plaintext = _aesgcm(key).decrypt(env.nonce, env.sealed, build_aad(env.name, env.rights, env.iterations))
    except InvalidTag:
        raise GSPackError(M4) from None
    if len(plaintext) > PLAINTEXT_BYTES:
        raise GSPackError(M3)
    return plaintext


def inner_text(plaintext: bytes) -> str:
    """12-8 — 엄격 UTF-8(대체 문자 복구 없음), 실패 → M5. UTF-8 BOM을 벗기고, BOM이 있었으면 바로 뒤 U+FEFF 하나를
    더 뗀다(BOM 두 번 붙은 파일 — 앱 평문 CSV 디코더의 F8 규칙과 같은 결과). BOM 없이 시작하면 아무것도 떼지 않는다."""
    had_bom = plaintext.startswith(UTF8_BOM)
    body = plaintext[len(UTF8_BOM):] if had_bom else plaintext
    try:
        text = body.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raise GSPackError(M5) from None
    return text[1:] if had_bom and text.startswith("\ufeff") else text


def open_envelope(env: Envelope, password: str) -> tuple[bytes, str]:
    """비밀번호 → KDF → open → 안쪽 글자. (평문 바이트, 글자)를 돌려준다."""
    key = derive_key(password_bytes(password), env.salt, env.iterations)
    plaintext = open_with_key(env, key)
    return plaintext, inner_text(plaintext)


# ── 엄격 봉투 파서 (12-2 검사 순서 ⓐ~ⓕ — KDF 전) ───────────────────────────

class _Malformed(Exception):
    pass


class _IntLiteral:
    __slots__ = ("literal",)

    def __init__(self, literal: str):
        self.literal = literal


class _FloatLiteral:
    __slots__ = ("literal",)

    def __init__(self, literal: str):
        self.literal = literal


def _pairs_hook(pairs):
    keys = [key for key, _ in pairs]
    if len(set(keys)) != len(keys):          # 이스케이프를 푼 뒤 비교(json이 이미 풀었다)
        raise _Malformed()
    return dict(pairs)


def _reject_constant(_name):
    raise _Malformed()                        # NaN·Infinity는 JSON이 아니다


def _check_tree(value, depth: int) -> None:
    """깊이(컨테이너 기준 ≤ 3)와 짝 없는 서로게이트(json은 '\\ud800'을 그대로 받는다)."""
    if isinstance(value, (dict, list)):
        depth += 1
        if depth > MAX_DEPTH:
            raise _Malformed()
        items = value.items() if isinstance(value, dict) else ((None, v) for v in value)
        for key, child in items:
            if key is not None:
                _check_text(key)
            _check_tree(child, depth)
    elif isinstance(value, str):
        _check_text(value)


def _check_text(text: str) -> None:
    if any(0xD800 <= ord(ch) <= 0xDFFF for ch in text):
        raise _Malformed()


def _parse_json(data: bytes):
    """ⓑ — 엄격 UTF-8, BOM 거부, RFC 8259 문법, 중복 키, 깊이, 서로게이트, 쓰레기."""
    if data.startswith(UTF8_BOM):
        raise _Malformed()
    try:
        text = data.decode("utf-8", errors="strict")
        value = json.loads(text, object_pairs_hook=_pairs_hook, parse_int=_IntLiteral,
                           parse_float=_FloatLiteral, parse_constant=_reject_constant)
    except (UnicodeDecodeError, ValueError, RecursionError):
        raise _Malformed() from None
    _check_tree(value, 0)
    return value


_FORBIDDEN_META = re.compile("[\u0000-\u001f\u007f-\u009f  ]")
_B64_ALPHABET = re.compile(r"[A-Za-z0-9+/=]*")


def _meta_ok(text: str, limit: tuple[int, int, int]) -> bool:
    characters, utf8_bytes, scalars = limit
    return (not _FORBIDDEN_META.search(text)
            and len(text) <= characters            # 코드 포인트(보수적 — NAME_LIMIT 주석)
            and len(text.encode("utf-8")) <= utf8_bytes
            and len(text) <= scalars)


def b64_canonical(text: str) -> bytes | None:
    """정규형 base64만 — 표준 알파벳, 패딩 필수, 재인코딩 일치."""
    if not _B64_ALPHABET.fullmatch(text) or len(text) % 4:
        return None
    body = text.rstrip("=")
    if len(text) - len(body) > 2 or "=" in body:
        return None
    try:
        raw = base64.b64decode(text, validate=True)
    except binascii.Error:
        return None
    return raw if base64.b64encode(raw).decode("ascii") == text else None


def parse_envelope(data: bytes) -> Envelope:
    """ⓐ~ⓕ. 실패하면 GSPackError(M1/M2/M3)."""
    # ⓐ
    if len(data) > ENVELOPE_BYTES:
        raise GSPackError(M3)
    try:
        top = _parse_json(data)                                                  # ⓑ
        if not isinstance(top, dict) or top.get("format") != FORMAT:            # ⓒ
            raise _Malformed()
        version = top.get("version")                                             # ⓓ
        if not isinstance(version, _IntLiteral):
            raise _Malformed()
        if version.literal != "1":
            if version.literal.startswith("-") or version.literal == "0":
                raise _Malformed()
            raise GSPackError(M2)
        # ⓔ
        if set(top) != set(ENVELOPE_KEYS) or top["inner"] != INNER:
            raise _Malformed()
        meta, encryption = top["meta"], top["encryption"]
        if not isinstance(meta, dict) or set(meta) != set(META_KEYS):
            raise _Malformed()
        name, rights = meta["name"], meta["rights"]
        if not (isinstance(name, str) and isinstance(rights, str)
                and _meta_ok(name, NAME_LIMIT) and _meta_ok(rights, RIGHTS_LIMIT)):
            raise _Malformed()
        if not isinstance(encryption, dict) or set(encryption) != set(ENCRYPTION_KEYS):
            raise _Malformed()
        if encryption["scheme"] != SCHEME:
            raise _Malformed()
        iterations = encryption["iterations"]
        if (not isinstance(iterations, _IntLiteral) or iterations.literal.startswith("-")
                or len(iterations.literal) > ITERATIONS_MAX_DIGITS):
            raise _Malformed()
        rounds = int(iterations.literal)
        if not ITERATIONS_MIN <= rounds <= ITERATIONS_MAX:
            raise _Malformed()
        salt_text, nonce_text, ct_text = encryption["salt"], encryption["nonce"], top["ciphertext"]
        if not all(isinstance(v, str) for v in (salt_text, nonce_text, ct_text)):
            raise _Malformed()
        # ⓕ
        salt, nonce = b64_canonical(salt_text), b64_canonical(nonce_text)
        if salt is None or len(salt) != SALT_BYTES or nonce is None or len(nonce) != NONCE_BYTES:
            raise _Malformed()
        if not _B64_ALPHABET.fullmatch(ct_text):
            raise _Malformed()
        if len(ct_text) > CIPHERTEXT_B64_CHARS:                                   # ② 디코드 전
            raise GSPackError(M3)
        sealed = b64_canonical(ct_text)
        if sealed is None:
            raise _Malformed()
        if len(sealed) > CIPHERTEXT_BYTES:                                       # ③
            raise GSPackError(M3)
        if len(sealed) < TAG_BYTES:
            raise _Malformed()
    except _Malformed:
        raise GSPackError(M1) from None
    return Envelope(name, rights, rounds, salt, nonce, sealed)


def verify_bytes(data: bytes, password: str) -> tuple[bytes, str]:
    """봉투 바이트 + 비밀번호 → (평문 바이트, 글자). 실패는 GSPackError."""
    return open_envelope(parse_envelope(data), password)


# ── 제작 규칙 (12-4·12-9) — 실패 메시지에 값을 넣지 않는다 ─────────────────

_CONTROL = re.compile("[\u0000-\u001f\u007f]")


def maker_password(password: str) -> bytes:
    normalized = unicodedata.normalize("NFC", password)
    if _CONTROL.search(normalized):
        raise ValueError("비밀번호에 제어 문자를 쓸 수 없습니다.")
    if normalized != normalized.strip() or normalized[:1] == "﻿" or normalized[-1:] == "﻿":
        raise ValueError("비밀번호 앞뒤에 공백을 둘 수 없습니다.")
    if len(normalized) < MAKER_PASSWORD_MIN_CODE_POINTS:
        raise ValueError(f"비밀번호는 {MAKER_PASSWORD_MIN_CODE_POINTS}자 이상이어야 합니다.")
    raw = normalized.encode("utf-8")
    if len(raw) > PASSWORD_MAX_BYTES:
        raise ValueError(f"비밀번호는 UTF-8 {PASSWORD_MAX_BYTES}바이트(한글 약 85자)까지입니다.")
    return raw


def maker_name(name: str) -> str:
    normalized = unicodedata.normalize("NFC", name.strip())
    if not normalized:
        raise ValueError("팩 이름은 필수입니다.")
    if not _meta_ok(normalized, NAME_LIMIT):
        raise ValueError("팩 이름이 너무 길거나 제어 문자가 있습니다(40자·160바이트 이내).")
    return normalized


def maker_rights(rights: str) -> str:
    normalized = unicodedata.normalize("NFC", rights)
    if not _meta_ok(normalized, RIGHTS_LIMIT):
        raise ValueError("출처가 너무 길거나 제어 문자가 있습니다(120자·480바이트 이내).")
    return normalized


def maker_csv(data: bytes) -> bytes:
    """엄격 UTF-8·비어 있지 않음·≤ 3,000,000B. 바이트 그대로 쓴다(변환 없음, BOM도 그대로)."""
    if len(data) > PLAINTEXT_BYTES:
        raise ValueError("CSV가 너무 큽니다(3,000,000바이트까지).")
    body = data[len(UTF8_BOM):] if data.startswith(UTF8_BOM) else data
    if not body:
        raise ValueError("CSV가 비어 있습니다.")
    try:
        body.decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        raise ValueError("CSV가 UTF-8이 아닙니다. 엑셀에서 『CSV UTF-8(쉼표로 분리)』로 저장해 주세요.") from None
    return data


# ── CLI ──────────────────────────────────────────────────────────────────────

def _read_limited(path: str, limit: int) -> bytes:
    with open(path, "rb") as handle:
        return handle.read(limit + 1)


def _read_password(confirm: bool) -> str:
    from_env = os.environ.get("GSPACK_PASSWORD")
    if from_env is not None:
        return from_env
    first = getpass.getpass("비밀번호: ")
    if confirm and getpass.getpass("비밀번호 확인: ") != first:
        raise ValueError("두 비밀번호가 다릅니다.")
    return first


def _command_make(args) -> int:
    if not ITERATIONS_MIN <= args.iterations <= ITERATIONS_MAX:
        raise ValueError(f"반복 수는 {ITERATIONS_MIN:,}~{ITERATIONS_MAX:,}입니다.")
    if os.path.exists(args.out) and not args.force:
        raise ValueError("출력 파일이 이미 있습니다(덮어쓰려면 --force).")
    csv_bytes = maker_csv(_read_limited(args.csv, PLAINTEXT_BYTES))
    name = maker_name(args.name)
    rights = maker_rights(args.rights)
    password = maker_password(_read_password(confirm=True))

    salt, nonce = os.urandom(SALT_BYTES), os.urandom(NONCE_BYTES)
    key = derive_key(password, salt, args.iterations)
    output = render(seal_with_key(csv_bytes, key, name, rights, args.iterations, salt, nonce))

    # 자체 점검(12-9 4) — 다시 파싱 + 같은 키로 복호해 평문 바이트가 같은지(KDF 재실행 없음)
    reparsed = parse_envelope(output)
    if open_with_key(reparsed, key) != csv_bytes:
        raise ValueError("자체 점검 실패 — 파일을 쓰지 않았습니다.")

    with open(args.out, "wb") as handle:
        handle.write(output)
    print(f"만듦: {args.out}")
    print(f"봉투 {len(output):,}바이트 · 평문 SHA-256 {hashlib.sha256(csv_bytes).hexdigest()}")
    return 0


def _command_verify(args) -> int:
    data = _read_limited(args.input, ENVELOPE_BYTES)
    try:
        envelope = parse_envelope(data)
        plaintext, _ = open_envelope(envelope, _read_password(confirm=False))
    except GSPackError as failure:
        print(failure.code)
        return 1
    print(f"OK 평문 {len(plaintext):,}바이트 · SHA-256 {hashlib.sha256(plaintext).hexdigest()}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="글쇠 잠금 팩(.gspack) 만들기·검증 — 비밀번호는 GSPACK_PASSWORD 또는 입력 창")
    commands = parser.add_subparsers(dest="command", required=True)

    make = commands.add_parser("make", help="CSV를 .gspack으로 잠근다")
    make.add_argument("--csv", required=True, help="UTF-8 CSV 파일")
    make.add_argument("--name", required=True, help="팩 이름(필수)")
    make.add_argument("--rights", default="", help="출처(선택)")
    make.add_argument("--out", required=True, help="출력 .gspack 경로")
    make.add_argument("--iterations", type=int, default=MAKER_ITERATIONS)
    make.add_argument("--force", action="store_true", help="출력 파일 덮어쓰기")

    verify = commands.add_parser("verify", help=".gspack을 풀어 본다(내용은 출력하지 않는다)")
    verify.add_argument("--in", dest="input", required=True)

    args = parser.parse_args(argv)
    try:
        return _command_make(args) if args.command == "make" else _command_verify(args)
    except ValueError as problem:
        print(f"오류: {problem}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
