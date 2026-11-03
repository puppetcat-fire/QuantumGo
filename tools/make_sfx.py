"""Procedural sound effects for Quantum Go.

Every sound is synthesised from scratch with numpy — no third-party samples — so
the assets are original and safe to ship commercially.

    python tools/make_sfx.py

Writes 16-bit mono 44.1 kHz WAV files into assets/audio/.

Design notes
------------
* Stone placement is the sound a player hears most often, so it is built from
  two layers: a short filtered noise transient (the "tick" of stone on wood)
  and a fast-decaying resonant body. The game additionally randomises pitch and
  volume slightly per move so repeated placements never sound machine-gunned.
* Split and collapse are the only "big" moments: the split rises and shimmers,
  the collapse falls and swallows.
* Everything is peak-normalised to a comfortable level, with short fades so no
  clip or click survives at the edges.
"""
from __future__ import annotations

import os
import wave

import numpy as np

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")


def _t(seconds: float) -> np.ndarray:
    return np.arange(int(RATE * seconds), dtype=np.float64) / RATE


def _fade(signal: np.ndarray, seconds: float = 0.004) -> np.ndarray:
    count = min(int(RATE * seconds), len(signal) // 3) or 1
    signal[:count] *= np.linspace(0.0, 1.0, count)
    signal[-count:] *= np.linspace(1.0, 0.0, count)
    return signal


def _lowpass(signal: np.ndarray, width: int = 24) -> np.ndarray:
    kernel = np.exp(-np.linspace(0.0, 1.0, width) * 4.0)
    kernel /= np.sum(kernel)
    return np.convolve(signal, kernel, mode="same")


def _write(name: str, samples: np.ndarray, peak: float = 0.7) -> None:
    os.makedirs(OUT, exist_ok=True)
    data = np.asarray(samples, dtype=np.float64)
    data = _fade(data)
    maximum = float(np.max(np.abs(data))) or 1.0
    data = data / maximum * peak
    pcm = (data * 32767).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())
    print("wrote", path, "%.2fs" % (len(data) / RATE))


def stone(pitch: float = 1.0, seed: int = 0) -> np.ndarray:
    """Stone on wood: a bright transient plus a short resonant body."""
    t = _t(0.20)
    rng = np.random.default_rng(100 + seed)

    # Transient: broadband noise, band-limited, very short.
    noise = rng.normal(0.0, 1.0, len(t))
    band = np.diff(noise, n=1, prepend=0.0)  # high-pass tilt for a crisper attack
    click = band * np.exp(-t / 0.006) * 0.55

    # Body: two detuned modes with independent decays, like a small wooden board.
    body = np.zeros_like(t)
    for freq, gain, decay in (
        (235.0 * pitch, 0.75, 0.038),
        (410.0 * pitch, 0.34, 0.026),
        (640.0 * pitch, 0.16, 0.015),
    ):
        body += gain * np.sin(2 * np.pi * freq * t + rng.uniform(0, 6.28)) * np.exp(-t / decay)

    # A touch of wood creak: low-passed noise riding the body envelope.
    creak = _lowpass(rng.normal(0.0, 1.0, len(t)), 60) * np.exp(-t / 0.05) * 0.18

    return click + body * 0.9 + creak


def split() -> np.ndarray:
    """Reality tearing: two voices drift apart, with a shimmer on top."""
    t = _t(0.85)
    rise_a = np.linspace(150.0, 430.0, len(t))
    rise_b = np.linspace(160.0, 760.0, len(t))
    left = np.sin(2 * np.pi * np.cumsum(rise_a) / RATE)
    right = np.sin(2 * np.pi * np.cumsum(rise_b) / RATE)
    sweep = (left + right) * 0.45 * np.minimum(t / 0.02, 1.0) * np.exp(-t / 0.42)

    shimmer = np.zeros_like(t)
    rng = np.random.default_rng(7)
    for freq, gain, decay in ((1320.0, 0.16, 0.22), (1980.0, 0.12, 0.16), (2640.0, 0.07, 0.12)):
        shimmer += gain * np.sin(2 * np.pi * freq * t + rng.uniform(0, 6.28)) * np.exp(-t / decay)
    shimmer *= np.minimum(t / 0.03, 1.0)

    # Low whoosh underneath: filtered noise swelling then falling.
    whoosh = _lowpass(rng.normal(0.0, 1.0, len(t)), 90)
    whoosh *= np.exp(-((t - 0.18) ** 2) / (2 * 0.12 ** 2)) * 0.5
    return sweep + shimmer + whoosh


def collapse() -> np.ndarray:
    """A universe being observed out of existence: a fall and a long swallow."""
    t = _t(1.1)
    rng = np.random.default_rng(11)
    fall = np.linspace(560.0, 48.0, len(t))
    voice = np.sin(2 * np.pi * np.cumsum(fall) / RATE)
    voice += 0.4 * np.sin(2 * np.pi * np.cumsum(fall * 0.5) / RATE)
    voice *= np.exp(-t / 0.42)

    rumble = _lowpass(rng.normal(0.0, 1.0, len(t)), 140)
    rumble *= np.exp(-((t - 0.30) ** 2) / (2 * 0.18 ** 2)) * 0.8

    # Vacuum tail: noise thinning out as the branch disappears.
    tail = _lowpass(rng.normal(0.0, 1.0, len(t)), 40) * np.exp(-t / 0.5) * 0.35
    return voice * 0.75 + rumble + tail


def pass_sound() -> np.ndarray:
    """A soft, neutral tap: passing is a non-action."""
    t = _t(0.28)
    tone = np.sin(2 * np.pi * 620 * t) * np.exp(-t / 0.05) * 0.55
    tone += np.sin(2 * np.pi * 930 * t) * np.exp(-t / 0.03) * 0.22
    tone += _lowpass(np.random.default_rng(3).normal(0, 1, len(t)), 40) * np.exp(-t / 0.02) * 0.2
    return tone


def click_sound() -> np.ndarray:
    t = _t(0.08)
    rng = np.random.default_rng(5)
    noise = rng.normal(0, 1, len(t)) * np.exp(-t / 0.005)
    tone = np.sin(2 * np.pi * 1450 * t) * np.exp(-t / 0.010)
    return noise * 0.45 + tone * 0.55


def mark_sound() -> np.ndarray:
    """Marking a dead stone: a short downward tick, clearly not a move."""
    t = _t(0.18)
    drop = np.linspace(900.0, 480.0, len(t))
    tone = np.sin(2 * np.pi * np.cumsum(drop) / RATE) * np.exp(-t / 0.05)
    tick = np.random.default_rng(13).normal(0, 1, len(t)) * np.exp(-t / 0.004) * 0.3
    return tone * 0.6 + tick


def confirm_sound() -> np.ndarray:
    """Confirming the score: two rising notes, calm and final."""
    t = _t(0.55)
    out = np.zeros_like(t)
    for index, freq in enumerate((523.25, 783.99)):
        start = int(RATE * 0.10 * index)
        segment = np.sin(2 * np.pi * freq * t[start:]) * np.exp(-t[start:] / 0.28)
        segment += 0.25 * np.sin(2 * np.pi * freq * 2.0 * t[start:]) * np.exp(-t[start:] / 0.16)
        out[start:] += segment * 0.7
    return out


def chord(notes: list[float], decay: float = 0.55) -> np.ndarray:
    duration = 1.5
    t = _t(duration)
    out = np.zeros_like(t)
    rng = np.random.default_rng(17)
    for index, freq in enumerate(notes):
        start = int(RATE * 0.085 * index)
        segment = np.sin(2 * np.pi * freq * t[start:] + rng.uniform(0, 6.28)) * np.exp(-t[start:] / decay)
        segment += 0.22 * np.sin(2 * np.pi * freq * 2 * t[start:]) * np.exp(-t[start:] / (decay * 0.6))
        segment += 0.10 * np.sin(2 * np.pi * freq * 3 * t[start:]) * np.exp(-t[start:] / (decay * 0.4))
        out[start:] += segment * 0.6
    return out


def main() -> None:
    _write("stone_black.wav", stone(pitch=0.94, seed=0))
    _write("stone_white.wav", stone(pitch=1.07, seed=1))
    _write("split.wav", split(), peak=0.72)
    _write("collapse.wav", collapse(), peak=0.78)
    _write("pass.wav", pass_sound(), peak=0.5)
    _write("click.wav", click_sound(), peak=0.4)
    _write("mark.wav", mark_sound(), peak=0.55)
    _write("confirm.wav", confirm_sound(), peak=0.55)
    _write("win.wav", chord([523.25, 659.25, 783.99, 1046.50]), peak=0.68)
    _write("lose.wav", chord([392.00, 329.63, 261.63, 196.00], decay=0.7), peak=0.68)


if __name__ == "__main__":
    main()
