#!/usr/bin/env python3
"""Synthesises the background crowd murmur, audio/sfx/crowd_loop.wav.

It is generated from scratch (no recordings), so it is ours and released CC0.
The recorded sounds are listed in audio/README.md. Re-run to rebuild:

    python3 -m pip install numpy scipy
    python3 audio/make_sounds.py

A fixed seed keeps the output identical between runs.
"""
import os
import wave

import numpy as np
from scipy.signal import butter, lfilter, sosfilt

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sfx")
rng = np.random.default_rng(1893)  # the year the Camanachd Association was founded


def t_axis(seconds):
    return np.arange(int(seconds * RATE)) / RATE


def band(x, lo, hi, order=2):
    sos = butter(order, [lo, hi], btype="band", fs=RATE, output="sos")
    return sosfilt(sos, x)


def lowpass(x, hz, order=2):
    return sosfilt(butter(order, hz, btype="low", fs=RATE, output="sos"), x)


def resonator(x, freq, bw):
    """Two-pole resonant filter: a formant or a ringing mode."""
    r = np.exp(-np.pi * bw / RATE)
    a1 = -2 * r * np.cos(2 * np.pi * freq / RATE)
    a2 = r * r
    return lfilter([1 - r], [1, a1, a2], x)


def write(name, x, peak=0.9):
    x = np.asarray(x, dtype=np.float64)
    x = x / (np.max(np.abs(x)) + 1e-9) * peak
    data = (x * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote", name, "%.2fs" % (len(x) / RATE))


# ------------------------------------------------------------- crowd sounds

VOWELS = {  # formant frequencies (Hz) for a rough "ah", "oh", "eh", "ay"
    "ah": [(730, 90), (1090, 110), (2440, 160)],
    "oh": [(570, 80), (840, 100), (2410, 160)],
    "eh": [(530, 80), (1840, 120), (2480, 160)],
    "ay": [(660, 90), (1720, 120), (2410, 160)],
}


def voice(t, f0, vowel, env, rise=0.0, vib=5.0):
    """One supporter's voice: a buzzing source shaped by a vowel's formants."""
    pitch = f0 * (1 + rise * np.clip(t / 0.6, 0, 1)) * (1 + 0.02 * np.sin(2 * np.pi * vib * t + rng.uniform(0, 6)))
    pitch *= 1 + 0.01 * lowpass(rng.normal(0, 1, len(t)), 8) * 30
    phase = np.cumsum(pitch) / RATE
    src = 2 * (phase % 1.0) - 1  # sawtooth
    src += 0.3 * rng.normal(0, 1, len(t))  # breath
    out = sum(resonator(src, f * rng.uniform(0.93, 1.07), bw) for f, bw in VOWELS[vowel])
    return out * env


def murmur(seconds=12.0, voices=28):
    """Background crowd: chatter and the odd shout, made to loop seamlessly."""
    total = seconds + 1.0
    t = t_axis(total)
    out = np.zeros(len(t))
    for _ in range(voices):
        # each person talks in bursts of syllables
        env = np.zeros(len(t))
        when = rng.uniform(0, 1.5)
        while when < total:
            length = rng.uniform(0.08, 0.3)
            i0, i1 = int(when * RATE), int(min(when + length, total) * RATE)
            env[i0:i1] = np.hanning(max(i1 - i0, 2))[: i1 - i0]
            when += length + rng.exponential(0.25) + (rng.uniform(0.5, 2.0) if rng.random() < 0.15 else 0)
        f0 = rng.uniform(95, 230)
        out += voice(t, f0, rng.choice(list(VOWELS)), env, vib=rng.uniform(3, 7)) * rng.uniform(0.3, 1.0)
    out = out / np.max(np.abs(out))
    out += band(rng.normal(0, 1, len(t)), 250, 2500) * 0.12
    out = lowpass(out, 3500)
    # crossfade the extra second onto the start so the loop has no seam
    n, x = int(seconds * RATE), int(1.0 * RATE)
    loop = out[:n].copy()
    ramp = np.linspace(0, 1, x)
    loop[:x] = out[:x] * ramp + out[n:n + x] * (1 - ramp)
    return loop


if __name__ == "__main__":
    write("crowd_loop", murmur(), 0.6)
