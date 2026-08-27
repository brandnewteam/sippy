#!/usr/bin/env python3
"""Generates Sippy's bundled ringtones into Support/Ringtones/.

Everything is synthesized from scratch (stdlib only), so the output is
CC0/public-domain by construction. Re-run after changing a recipe:

    python3 Tools/make_ringtones.py

Files are mono 16-bit 44.1 kHz WAV; liblinphone loops the whole file, so
each one ends with the ring cadence's silent gap.
"""

import math
import os
import struct
import wave

RATE = 44100
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "Support", "Ringtones")


def write(name, samples):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(
            b"".join(
                struct.pack("<h", max(-32767, min(32767, int(s * 32767))))
                for s in samples
            )
        )
    print(f"wrote {path} ({len(samples) / RATE:.1f}s)")


def silence(dur):
    return [0.0] * int(RATE * dur)


def tone(freqs, dur, amp=0.4, attack=0.01, release=0.04):
    """Steady multi-frequency tone with a click-free envelope."""
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack, (dur - t) / release)
        s = sum(math.sin(2 * math.pi * f * t) for f in freqs) / len(freqs)
        out.append(amp * max(0.0, env) * s)
    return out


def strike(freq, dur, amp=0.4, decay=5.0, partials=((1.0, 1.0), (2.0, 0.5), (3.0, 0.33))):
    """Struck/plucked note: harmonic partials with exponential decay."""
    n = int(RATE * dur)
    norm = sum(a for _, a in partials)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-decay * t) * min(1.0, t / 0.005)
        s = sum(a * math.sin(2 * math.pi * freq * m * t) for m, a in partials) / norm
        out.append(amp * env * s)
    return out


def bell(freq, dur, amp=0.4):
    """Bell strike: slightly inharmonic partials, long decay."""
    partials = ((1.0, 1.0, 1.8), (2.76, 0.55, 2.4), (5.40, 0.25, 3.6), (8.93, 0.12, 5.0))
    n = int(RATE * dur)
    norm = sum(a for _, a, _ in partials)
    out = []
    for i in range(n):
        t = i / RATE
        s = sum(
            a * math.exp(-d * t) * math.sin(2 * math.pi * freq * m * t)
            for m, a, d in partials
        ) / norm
        out.append(amp * min(1.0, t / 0.003) * s)
    return out


def mix(base, overlay, at):
    """Adds overlay into base starting at second `at` (extends base if needed)."""
    start = int(RATE * at)
    need = start + len(overlay) - len(base)
    if need > 0:
        base = base + [0.0] * need
    for i, s in enumerate(overlay):
        base[start + i] += s
    return base


# --- Classic Ring: 425 Hz European cadence, 1 s on / 4 s off ----------------
classic = tone([425], 1.0, amp=0.35) + silence(4.0)
write("Classic Ring.wav", classic)

# --- Dual Tone: North American 440+480 Hz, 2 s on / 4 s off -----------------
dual = tone([440, 480], 2.0, amp=0.35) + silence(4.0)
write("Dual Tone.wav", dual)

# --- Marimba: woody four-note pattern, played twice --------------------------
marimba_partials = ((1.0, 1.0), (4.0, 0.45), (9.2, 0.18))
def marimba_note(freq, amp=0.5):
    return strike(freq, 0.5, amp=amp, decay=9.0, partials=marimba_partials)

pattern = [0.0]
for repeat in range(2):
    base_t = repeat * 1.0
    for i, f in enumerate([659.26, 523.25, 659.26, 783.99]):  # E5 C5 E5 G5
        pattern = mix(pattern, marimba_note(f), base_t + i * 0.18)
write("Marimba.wav", pattern + silence(3.0))

# --- Digital: crisp double beep, twice, then quiet ---------------------------
beep = tone([1046.5], 0.09, amp=0.35, attack=0.005, release=0.02)
digital = beep + silence(0.06) + beep + silence(0.45) + beep + silence(0.06) + beep
write("Digital.wav", digital + silence(3.0))

# --- Bell: single low strike with a long tail --------------------------------
write("Bell.wav", bell(392.0, 3.0, amp=0.5) + silence(2.5))

# --- Chime: ascending three-note chime ---------------------------------------
chime = [0.0]
for i, f in enumerate([523.25, 659.26, 783.99]):  # C5 E5 G5
    chime = mix(chime, bell(f, 1.6, amp=0.35), i * 0.28)
write("Chime.wav", chime + silence(3.0))
