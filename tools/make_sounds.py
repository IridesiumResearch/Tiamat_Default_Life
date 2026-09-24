# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the cue sounds for mods/tiamat_default_life/sounds.

Short synthesised WAVs: a hurt grunt, a chew, a gulp, a chime for healing, a
bubble, a crackle and a low tone for dying. Placeholders in the classic
style, written straight out of the standard library's `wave` module so the
files are exactly one `fmt ` chunk and one `data` chunk, which is what the
engine's strict WAV reader wants. Run from the repository root:

    python tools/make_sounds.py
"""
import math
import random
import struct
import wave
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_life" / "sounds"
RATE = 22050


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    clipped = [max(-1.0, min(1.0, s)) for s in samples]
    with wave.open(str(OUT / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32000)) for s in clipped))
    print("wrote", name)


def seconds(length):
    return int(RATE * length)


def env(i, n, attack=0.01, release=0.3):
    a = seconds(attack)
    r = seconds(release)
    if i < a:
        return i / max(1, a)
    if i > n - r:
        return max(0.0, (n - i) / max(1, r))
    return 1.0


def tone(freq_from, freq_to, length, gain=0.6, shape="sine", attack=0.01, release=0.2):
    n = seconds(length)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / n
        f = freq_from + (freq_to - freq_from) * t
        phase += 2 * math.pi * f / RATE
        if shape == "square":
            s = 1.0 if math.sin(phase) > 0 else -1.0
        elif shape == "saw":
            s = (phase / math.pi) % 2.0 - 1.0
        else:
            s = math.sin(phase)
        out.append(s * gain * env(i, n, attack, release))
    return out


def noise(length, gain=0.5, lowpass=0.2, attack=0.005, release=0.15, seed=1):
    rng = random.Random(seed)
    n = seconds(length)
    out = []
    last = 0.0
    for i in range(n):
        last += (rng.uniform(-1, 1) - last) * lowpass
        out.append(last * gain * env(i, n, attack, release))
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    out = [0.0] * n
    for p in parts:
        for i, s in enumerate(p):
            out[i] += s
    return out


def concat(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p
        out += [0.0] * seconds(gap)
    return out


def main():
    # A short, low grunt with a noisy edge: being hit.
    write("hurt", mix(tone(220, 120, 0.22, 0.5, "saw", release=0.15), noise(0.18, 0.3, 0.35, seed=3)))
    # Three soft chews.
    chew = mix(noise(0.07, 0.6, 0.12, seed=7), tone(160, 90, 0.07, 0.25, release=0.05))
    write("eat", concat(chew, chew, chew, gap=0.06))
    # A gulp: a quick downward swoop.
    write("drink", mix(tone(500, 180, 0.18, 0.4, release=0.08), noise(0.12, 0.2, 0.2, seed=5)))
    # A rising two-note chime: healing, a good sleep.
    write("heal", concat(tone(660, 660, 0.12, 0.35, release=0.08), tone(990, 990, 0.25, 0.35, release=0.2), gap=0.0))
    # A bubble: a little pop that rises.
    write("bubble", tone(300, 900, 0.08, 0.35, release=0.05))
    # A gasp for air: breathy noise rising.
    write("gasp", noise(0.35, 0.45, 0.5, attack=0.15, release=0.1, seed=11))
    # A crackle: bursts of filtered noise.
    write("burn", concat(noise(0.05, 0.5, 0.3, seed=21), noise(0.04, 0.4, 0.3, seed=22), noise(0.06, 0.5, 0.3, seed=23), gap=0.03))
    # Dying: a low falling tone that takes its time.
    write("death", mix(tone(180, 55, 0.9, 0.5, "saw", release=0.6), noise(0.6, 0.15, 0.1, release=0.5, seed=9)))
    # A dull thump: landing hard.
    write("thud", mix(tone(90, 40, 0.16, 0.7, release=0.12), noise(0.1, 0.4, 0.1, seed=13)))
    # A soft shimmer for a well-rested morning.
    write("rested", concat(tone(523, 523, 0.1, 0.3, release=0.06), tone(659, 659, 0.1, 0.3, release=0.06), tone(784, 784, 0.3, 0.3, release=0.25)))
    # A blast.
    write("boom", mix(tone(120, 30, 0.6, 0.8, "saw", release=0.5), noise(0.5, 0.7, 0.08, release=0.45, seed=17)))
    # A bite: a short snap.
    write("bite", mix(noise(0.06, 0.8, 0.5, seed=31), tone(400, 150, 0.08, 0.4, release=0.04)))
    # The creatures' voices are recordings now, brought in by
    # tools/import_sounds.py as sounds/<id>.ogg; nothing here makes them.


if __name__ == "__main__":
    main()
