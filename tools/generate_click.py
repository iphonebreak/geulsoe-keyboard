#!/usr/bin/env python3
"""키 클릭음 생성 — Keyboard/Resources/key_click.wav

시스템 `playInputClick`은 크기를 못 바꾼다. 소리 크기 조절(사용자 요청 2026-09-02)을 위해
번들 클릭음을 AVAudioPlayer로 자체 재생한다 (PDR feedback-intensity). 외부 샘플을 쓰지 않고
합성한다 — 라이선스 문제 없음, 저장소에 이 스크립트만 있으면 재생성 가능.

소리 설계: 짧은 노이즈 버스트(기계식 '탁')에 감쇠 사인(약간의 몸통)을 섞고 지수 감쇠.
길이 40ms, 44.1kHz 모노 16비트 — 약 3.5KB.

    python3 tools/generate_click.py
"""

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
DURATION = 0.040
OUT = Path(__file__).resolve().parent.parent / "Keyboard" / "Resources" / "key_click.wav"


def main() -> None:
    random.seed(7)  # 결정적 출력 — 재생성해도 바이트가 같다
    n = int(RATE * DURATION)
    samples = []
    prev = 0.0
    for i in range(n):
        t = i / RATE
        # 노이즈: 1차 저역 필터로 '쉿' 대신 '탁'에 가깝게
        white = random.uniform(-1, 1)
        prev = prev + 0.35 * (white - prev)
        noise = prev * math.exp(-t / 0.004)
        # 몸통: 1.6kHz 감쇠 사인 + 약한 3.2kHz 배음
        body = (math.sin(2 * math.pi * 1600 * t) + 0.3 * math.sin(2 * math.pi * 3200 * t)) * math.exp(-t / 0.007)
        # 어택 0.5ms 램프 — 클릭 잡음(DC 점프) 방지
        attack = min(1.0, t / 0.0005)
        samples.append(attack * (0.9 * noise + 0.5 * body))

    peak = max(abs(s) for s in samples) or 1.0
    scale = 0.85 / peak
    # 끝 2ms 페이드아웃 — 잔여 신호가 뚝 끊기지 않게
    fade_n = int(RATE * 0.002)
    for i in range(fade_n):
        samples[n - fade_n + i] *= 1 - i / fade_n

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples))
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {n} samples)")


if __name__ == "__main__":
    main()
