#!/usr/bin/env python3
"""B5 E16 — 영어 사전 변환기 재현성 시험(계획 v1.3.1-plan.md §3-8).

  python3 tools/test_convert_words_en.py

합성 원본(네트워크 없음)으로 ① 원본 해시 불일치 → 실패 ② 같은 입력 → 같은 출력 바이트·해시
③ 손질 항목 빈도 동률 → 실패 ④ 손질 키 충돌 → 실패를 고정한다. 받아 둔 실제 원본이 임시 폴더에 있으면
⑤ 커밋된 words-en.tdw와 재생성 결과가 바이트까지 같은지(`--check`와 같은 판정)도 본다.
"""

import struct
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import convert_words_en as converter  # noqa: E402

STEMS = converter.STEM_FRAGMENTS


def synthetic_source() -> bytes:
    words = ["you", "the", "hello", "help", "won", "don", "ain"] + STEMS + ["monday", "apple", "zebra"]
    lines = [f"{word} {10_000 - index * 10}" for index, word in enumerate(words)]
    return ("\n".join(lines) + "\n").encode()


def data_dir(contractions: str = "I'm\ti'm\t9999\n", capitals: str = "monday\tMonday\n") -> Path:
    folder = Path(tempfile.mkdtemp(prefix="words-en-test-"))
    for name in ("blocklist.txt", "misspellings.txt", "noise.txt"):
        (folder / name).write_text("# 비어 있음\n", encoding="utf-8")
    (folder / "contractions.tsv").write_text(contractions, encoding="utf-8")
    (folder / "capitals.tsv").write_text(capitals, encoding="utf-8")
    return folder


class ConverterReproducibilityTests(unittest.TestCase):

    def test_source_hash_mismatch_fails(self):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as handle:
            handle.write(synthetic_source())
        with self.assertRaises(converter.ConversionError):
            converter.load_source(Path(handle.name))

    def test_same_input_same_output(self):
        folder = data_dir()
        first, stats1 = converter.build(synthetic_source(), data_dir=folder)
        second, stats2 = converter.build(synthetic_source(), data_dir=folder)
        self.assertEqual(first, second)
        self.assertEqual(stats1["sha256"], stats2["sha256"])
        magic, version, count, blob = struct.unpack("<4sIII", first[:16])
        self.assertEqual((magic, version), (b"TDWD", 1))
        self.assertEqual(blob, 16 + 16 * count)

    def test_mechanical_and_curated_forms(self):
        _, stats = converter.build(synthetic_source(), data_dir=data_dir())
        words = stats["ranked_words"]
        self.assertIn("didn't", words)
        self.assertNotIn("didn", words)
        self.assertNotIn("don", words)
        self.assertNotIn("ain", words)
        self.assertIn("don't", words)
        self.assertLess(words.index("won't"), words.index("won"), "won't는 won 바로 앞(같은 빈도, won은 −1)")
        self.assertIn("I'm", words)
        self.assertIn("Monday", words)
        self.assertNotIn("monday", words)

    def test_curated_frequency_tie_fails(self):
        folder = data_dir(contractions="I'm\ti'm\t9999\nI'll\ti'll\t9999\n")
        with self.assertRaises(converter.ConversionError):
            converter.build(synthetic_source(), data_dir=folder)

    def test_curated_key_collision_fails(self):
        folder = data_dir(contractions="Hello\thello\t9999\n")
        with self.assertRaises(converter.ConversionError):
            converter.build(synthetic_source(), data_dir=folder)

    def test_limit_cuts_by_frequency(self):
        _, stats = converter.build(synthetic_source(), limit=3, data_dir=data_dir())
        self.assertEqual(stats["kept"], 3)
        self.assertEqual(stats["ranked_words"][0], "you")

    def test_committed_output_matches_real_source(self):
        cached = Path(tempfile.gettempdir()) / f"en_50k-{converter.SOURCE_COMMIT[:12]}.txt"
        if not cached.exists():
            self.skipTest("실제 원본이 임시 폴더에 없다 — `python3 tools/convert_words_en.py --check`로 확인")
        output, _ = converter.build(converter.load_source(cached))
        self.assertEqual(output, converter.OUTPUT.read_bytes())


if __name__ == "__main__":
    unittest.main(verbosity=2)
