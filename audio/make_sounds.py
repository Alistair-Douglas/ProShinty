#!/usr/bin/env python3
"""Synthesises the match sound effects in audio/sfx/.

Every sound is generated from scratch here (no recordings), so the WAVs are
ours and released CC0 with the rest of the audio folder. Re-run to rebuild:

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


def highpass(x, hz, order=2):
    return sosfilt(butter(order, hz, btype="high", fs=RATE, output="sos"), x)


def resonator(x, freq, bw):
    """Two-pole resonant filter: a formant or a ringing mode."""
    r = np.exp(-np.pi * bw / RATE)
    a1 = -2 * r * np.cos(2 * np.pi * freq / RATE)
    a2 = r * r
    return lfilter([1 - r], [1, a1, a2], x)


def mode(t, freq, decay, amp=1.0):
    """A damped sine: one ringing mode of a struck object."""
    return amp * np.sin(2 * np.pi * freq * t + rng.uniform(0, 6.28)) * np.exp(-t / decay)


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


def fade(x, fade_in=0.005, fade_out=0.02):
    n_in, n_out = int(fade_in * RATE), int(fade_out * RATE)
    env = np.ones(len(x))
    if n_in:
        env[:n_in] = np.linspace(0, 1, n_in)
    if n_out:
        env[-n_out:] = np.linspace(1, 0, n_out)
    return x * env


# ------------------------------------------------------------- stick sounds

def thwack(tone):
    """The caman's ash head striking the hard ball: a crack, the wood ringing, a thump."""
    t = t_axis(0.32)
    crack = rng.normal(0, 1, len(t)) * np.exp(-t / 0.0025)
    crack = highpass(crack, 1200)
    wood = sum(mode(t, f * tone * rng.uniform(0.97, 1.03), d, a)
               for f, d, a in [(640, 0.045, 1.0), (1180, 0.030, 0.7), (1930, 0.018, 0.5),
                               (2870, 0.010, 0.35), (4100, 0.006, 0.25)])
    thump = mode(t, 150 * tone, 0.035, 1.3) * (1 - np.exp(-t / 0.002))
    rattle = band(rng.normal(0, 1, len(t)), 900, 4500) * np.exp(-t / 0.028) * 0.5
    return fade(crack * 1.6 + wood + thump + rattle, 0.0005, 0.05)


def tap():
    """A soft touch: the ball stopped or nudged on the stick."""
    t = t_axis(0.16)
    wood = sum(mode(t, f * rng.uniform(0.97, 1.03), d, a)
               for f, d, a in [(520, 0.030, 1.0), (980, 0.018, 0.5), (1650, 0.010, 0.3)])
    knock = lowpass(rng.normal(0, 1, len(t)) * np.exp(-t / 0.004), 2500)
    return fade(lowpass(wood + knock * 0.8, 3000), 0.001, 0.03)


def clack():
    """Caman on caman: two sticks clashing, hard and high with no ball in it."""
    t = t_axis(0.22)
    crack = highpass(rng.normal(0, 1, len(t)) * np.exp(-t / 0.0015), 2000)
    wood = sum(mode(t, f * rng.uniform(0.97, 1.03), d, a)
               for f, d, a in [(1050, 0.030, 1.0), (1720, 0.022, 0.8), (2650, 0.015, 0.6),
                               (3700, 0.008, 0.4)])
    # a second, slightly later knock: the other stick
    t2 = np.maximum(t - 0.012, 0)
    wood2 = sum(mode(t2, f, d, a) for f, d, a in [(1240, 0.020, 0.6), (2050, 0.012, 0.4)]) * (t > 0.012)
    return fade(crack * 1.4 + wood + wood2, 0.0005, 0.04)


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


def claps(t, rate, start, length):
    """Applause: many hands, each clap a short filtered burst."""
    out = np.zeros(len(t))
    n = int(rate * length)
    for when in rng.uniform(start, start + length, n):
        i = int(when * RATE)
        k = int(0.012 * RATE)
        if i + k >= len(t):
            continue
        burst = rng.normal(0, 1, k) * np.exp(-np.arange(k) / (0.0025 * RATE))
        out[i:i + k] += burst * rng.uniform(0.3, 1.0)
    return band(out, 700, 6000)


def cheer(seconds=6.5, voices=70):
    """The crowd going up for a goal: a roar that swells, cheers, claps and fades."""
    t = t_axis(seconds)
    roar = np.zeros(len(t))
    for _ in range(voices):
        onset = rng.uniform(0.0, 0.35) + abs(rng.normal(0, 0.12))
        hold = rng.uniform(1.4, 3.6)
        attack = rng.uniform(0.08, 0.25)
        tail = rng.uniform(0.6, 1.4)
        env = np.clip((t - onset) / attack, 0, 1) * np.exp(-np.maximum(t - onset - hold, 0) / tail)
        env *= 1 + 0.35 * np.sin(2 * np.pi * rng.uniform(0.5, 2.0) * t + rng.uniform(0, 6))
        f0 = rng.choice([rng.uniform(110, 190), rng.uniform(190, 330)], p=[0.7, 0.3])
        roar += voice(t, f0, rng.choice(list(VOWELS)), env, rise=rng.uniform(0.1, 0.45)) * rng.uniform(0.4, 1.0)
    swell = np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 2.2, 0) / 1.6)
    hiss = band(rng.normal(0, 1, len(t)), 300, 3500) * swell
    roar = roar / np.max(np.abs(roar))
    clap = claps(t, 260, 0.9, seconds - 1.5)
    clap *= np.exp(-np.maximum(t - 3.0, 0) / 1.2)
    clap = clap / np.max(np.abs(clap))
    whistles = sum(mode(np.maximum(t - s, 0), f, 0.35, 1) * (t > s) * np.clip((t - s) / 0.05, 0, 1)
                   for s, f in [(0.6, 2350), (1.3, 2600)])
    mix = roar * 1.0 + hiss * 0.25 + clap * 0.35 + whistles * 0.05
    return fade(lowpass(mix, 6000), 0.02, 0.8)


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


def ooh(seconds=2.2, voices=45):
    """The crowd's 'ooh' at a save or a near miss."""
    t = t_axis(seconds)
    out = np.zeros(len(t))
    for _ in range(voices):
        onset = abs(rng.normal(0.05, 0.08))
        env = np.clip((t - onset) / 0.15, 0, 1) * np.exp(-np.maximum(t - onset - 0.5, 0) / 0.45)
        f0 = rng.uniform(110, 260)
        out += voice(t, f0, "oh", env, rise=-rng.uniform(0.05, 0.2), vib=4) * rng.uniform(0.4, 1.0)
    return fade(lowpass(out, 3000), 0.01, 0.3)


if __name__ == "__main__":
    for i, tone in enumerate([1.0, 0.93, 1.07]):
        write("thwack_%d" % (i + 1), thwack(tone))
    write("tap", tap(), 0.7)
    write("clack", clack())
    write("cheer_1", cheer())
    write("cheer_2", cheer(7.0, 80))
    write("ooh", ooh(), 0.8)
    write("crowd_loop", murmur(), 0.6)
