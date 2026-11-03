"""Ambient background music for Quantum Go.

A slow, seamless loop instead of a soundtrack: one A-minor drone that breathes,
plus a few long bell tones that wrap around the loop point so the join is
inaudible. Synthesised from scratch with numpy (no third-party samples), so the
track is original and safe to ship.

    python tools/make_music.py

Writes assets/audio/bgm_quantum.wav (16-bit mono 44.1 kHz, seamless loop).
"""
from __future__ import annotations

import os
import wave

import numpy as np

RATE = 44100
LOOP_SECONDS = 48.0
TAIL_SECONDS = 10.0
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")


def loop_frequency(freq: float) -> float:
    """Snap a frequency so it completes a whole number of cycles in one loop."""
    cycles = max(1, round(freq * LOOP_SECONDS))
    return cycles / LOOP_SECONDS


def drone() -> np.ndarray:
    t = np.tick = None  # placeholder to keep linters quiet about unused imports
    total = int(RATE * (LOOP_SECONDS + TAIL_SECONDS))
    t = np.arange(total) / RATE
    out = np.zeros(total)

    # A minor add9: A2, E3, A3, C4, B4 (the 9th).
    voices = [
        (110.0, 0.42),
        (164.81, 0.22),
        (220.0, 0.18),
        (261.63, 0.14),
        (329.63, 0.10),
        (493.88, 0.05),
    ]
    for index, (freq, gain) in enumerate(voices):
        base = loop_frequency(freq)
        # Two detuned copies; the beat frequency is a whole number of cycles per
        # loop, so the beating also loops cleanly.
        detune = 0.6 / LOOP_SECONDS
        left = np.sin(2 * np.pi * (base - detune) * t + index * 0.7)
        right = np.sin(2 * np.pi * (base + detune) * t + index * 1.3)
        # Slow amplitude breathing, periodic over the loop.
        lfo = 0.72 + 0.28 * np.sin(2 * np.pi * (index + 1) / LOOP_SECONDS * t + index)
        out += (left + right) * 0.5 * gain * lfo

    # A very slow noise wash, heavily smoothed, for air.
    rng = np.random.default_rng(42)
    wash = rng.normal(0.0, 1.0, total)
    kernel = np.exp(-np.linspace(0, 1, 4000) * 4.0)
    kernel /= np.sum(kernel)
    wash = np.convolve(wash, kernel, mode="same")
    breath = 0.55 + 0.45 * np.sin(2 * np.pi * 2 / LOOP_SECONDS * t)
    out += wash * 0.05 * breath

    return out


def bells() -> np.ndarray:
    """Sparse bell tones, wrapped so their tails bleed into the loop start."""
    total = int(RATE * (LOOP_SECONDS + TAIL_SECONDS))
    out = np.zeros(total)
    rng = np.random.default_rng(7)
    # Deterministic schedule: one tone every ~6 s, pitch from the Am pentatonic.
    notes = [440.0, 523.25, 659.25, 783.99, 880.0]
    count = int(LOOP_SECONDS / 6.0)
    for index in range(count):
        start = index * 6.0 + float(rng.uniform(-0.6, 0.6))
        freq = loop_frequency(notes[int(rng.integers(0, len(notes)))])
        offset = int(max(0.0, start) * RATE)
        length = int(RATE * 9.0)
        if offset + length > total:
            length = total - offset
        if length <= 0:
            continue
        local = np.arange(length) / RATE
        env = np.exp(-local / 1.6) * np.minimum(local / 0.02, 1.0)
        tone = np.sin(2 * np.pi * freq * local)
        tone += 0.35 * np.sin(2 * np.pi * freq * 2.0 * local)
        tone += 0.18 * np.sin(2 * np.pi * freq * 2.98 * local)
        out[offset:offset + length] += tone * env * 0.16
    return out


def fold_tail(signal: np.ndarray) -> np.ndarray:
    loop_samples = int(RATE * LOOP_SECONDS)
    head = signal[:loop_samples].copy()
    tail = signal[loop_samples:]
    if tail.size:
        head[:tail.size] += tail[:head.size]
    return head


def main() -> None:
    mix = fold_tail(drone() + bells())

    # Gentle low-pass so it sits behind the board instead of in front of it.
    kernel = np.exp(-np.linspace(0, 1, 12) * 3.0)
    kernel /= np.sum(kernel)
    mix = np.convolve(mix, kernel, mode="same")

    # Normalise to a quiet bed.
    peak = float(np.max(np.abs(mix))) or 1.0
    mix = mix / peak * 0.55

    # Crossfade a few milliseconds at the seam to kill any residual click.
    fade = int(RATE * 0.02)
    mix[:fade] *= np.linspace(0.0, 1.0, fade)
    mix[-fade:] *= np.linspace(1.0, 0.0, fade)

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "bgm_quantum.wav")
    pcm = (mix * 32767).astype(np.int16)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())
    print("wrote", path, "%.1fs" % (len(mix) / RATE), "%.1f MB" % (os.path.getsize(path) / 1048576))


if __name__ == "__main__":
    main()
