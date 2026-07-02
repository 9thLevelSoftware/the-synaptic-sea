#!/usr/bin/env python3
"""Generate deterministic placeholder audio clips for Domain 9 (audio bus +
pipeline) proof-of-stream-loading. Stdlib `wave` only, no randomness — every
re-run produces byte-identical output so the committed .wav files are a
reproducible build artifact, not a one-off asset.

Produces:
  data/audio/sfx/tool_pickup.wav      ~0.25s 16-bit mono PCM @ 22050 Hz
  data/audio/music/exploration_base.wav ~1.5s 16-bit mono PCM @ 22050 Hz, loopable

Both are pure sine-wave synthesis with a linear fade-in/fade-out envelope so
the loop point (music clip) and the transient (sfx clip) do not click.
"""
from __future__ import annotations

import math
import os
import struct
import wave

SAMPLE_RATE = 22050
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _envelope(i: int, n: int, fade_samples: int) -> float:
    """Linear fade-in/fade-out envelope, 1.0 in the steady region."""
    if n <= 0:
        return 0.0
    if i < fade_samples:
        return i / float(fade_samples)
    if i >= n - fade_samples:
        return (n - 1 - i) / float(fade_samples)
    return 1.0


def _write_sine_wav(path: str, duration_s: float, frequencies: list[float], amplitude: float, fade_s: float) -> None:
    n = int(SAMPLE_RATE * duration_s)
    fade_samples = max(1, int(SAMPLE_RATE * fade_s))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)  # 16-bit
        wf.setframerate(SAMPLE_RATE)
        frames = bytearray()
        for i in range(n):
            t = i / float(SAMPLE_RATE)
            sample = 0.0
            for freq in frequencies:
                sample += math.sin(2.0 * math.pi * freq * t)
            sample /= float(len(frequencies))
            sample *= amplitude * _envelope(i, n, fade_samples)
            clamped = max(-1.0, min(1.0, sample))
            frames += struct.pack("<h", int(clamped * 32767.0))
        wf.writeframes(bytes(frames))


def main() -> int:
    # SFX: a short two-tone "pickup" chirp (ascending interval), 0.25s.
    sfx_path = os.path.join(ROOT, "data", "audio", "sfx", "tool_pickup.wav")
    _write_sine_wav(sfx_path, duration_s=0.25, frequencies=[880.0, 1320.0], amplitude=0.6, fade_s=0.02)
    print(f"wrote {sfx_path}")

    # Music base layer: a low sustained drone, 1.5s, loop-friendly (full-cycle
    # fade-in/out at the same envelope on both ends so LOOP_FORWARD does not click).
    music_path = os.path.join(ROOT, "data", "audio", "music", "exploration_base.wav")
    _write_sine_wav(music_path, duration_s=1.5, frequencies=[110.0, 220.0], amplitude=0.4, fade_s=0.05)
    print(f"wrote {music_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
