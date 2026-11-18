#!/usr/bin/env python3
"""Fetches Sippy's bundled ringtones into Support/Ringtones/.

The ringtones come from lomiri-sounds, the sound set of Ubuntu Touch
(https://gitlab.com/ubports/development/core/lomiri-sounds). Only tracks
under CC0 or CC BY are used; the licenses are taken from that repository's
debian/copyright, the one place upstream records them.

Each track is downloaded at a pinned commit, checked against its SHA-256,
mixed down to mono and written as 16-bit 44.1 kHz WAV, the format
liblinphone's ring player is known to handle here. The level is raised or
lowered by a plain gain (no compression) towards TARGET_LUFS, never past
PEAK_CEILING_DB, so the ringtones ring about equally loud.

Besides the WAVs it writes credits.json (read by the app to name the
authors) and CREDITS.md (the attribution the licenses ask for). Run it
again after changing the table:

    python3 Tools/fetch_ringtones.py

Needs ffmpeg on the PATH (brew install ffmpeg). The output is committed, so
building the app needs neither ffmpeg nor the network.
"""

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
import urllib.parse
import urllib.request

SOURCE_REPO = "https://gitlab.com/ubports/development/core/lomiri-sounds"
SOURCE_COMMIT = "81a224fc8a29c06f6b976792014c11b2eb831abb"
SOURCE_DIR = "share/sounds/lomiri/ringtones"

TARGET_LUFS = -18.0
PEAK_CEILING_DB = -1.0
MONO = "pan=mono|c0=0.5*c0+0.5*c1"

LICENSES = {
    "CC0-1.0": ("CC0 1.0", "https://creativecommons.org/publicdomain/zero/1.0/"),
    "CC-BY-3.0": ("CC BY 3.0", "https://creativecommons.org/licenses/by/3.0/"),
    "CC-BY-4.0": ("CC BY 4.0", "https://creativecommons.org/licenses/by/4.0/"),
}

# (source file, author, year, license, sha256 of the source file)
# The title is the source file's name; folded to ASCII it becomes the WAV's
# name and the name shown in Settings (non-ASCII names in the bundle get
# mangled by unzip tools and break the code signature; see the Makefile).
RINGTONES = [
    ("Call me.ogg", "Anonymous", 2018, "CC0-1.0",
     "70d821709cdc1df89558084794823eb4ca422eb5e5437cdaff11c742bacfdf10"),
    ("Entropy.ogg", "Mauricio Duarte", 2018, "CC-BY-4.0",
     "e74d2d3b802e8127d97fbffe2c087e781ffa7a8f10e977050a573460a00165d6"),
    ("Mangoré.ogg", "Mauricio Duarte", 2018, "CC-BY-4.0",
     "1dbb8d679f2ed6a4adf1ba325c9c03f6487f33ddd01bbd9ff98dbc5fc2b94696"),
    ("Time not Lost.ogg", "Mauricio Duarte", 2018, "CC-BY-4.0",
     "6efb986a09ddfcc9e14c43b67820beac7e1742e62ff3bb756ec87fdd5ed31209"),
    ("Wooden Drive.ogg", "Amber Forest", 2018, "CC-BY-3.0",
     "68959b5e4d03b4e124fdd84657898d0a637b13b8dc8f0b0e2650e0cd93c74b74"),
    ("sakenointi.ogg", "TMetso", 2018, "CC-BY-4.0",
     "c074e42ca7abf5b70e0f569765cfc97221fe971f5464fc64f084247c820ef4cb"),
]

OUT_DIR = os.path.normpath(
    os.path.join(os.path.dirname(__file__), "..", "Support", "Ringtones"))


def source_url(name):
    path = urllib.parse.quote(f"{SOURCE_DIR}/{name}")
    return f"{SOURCE_REPO}/-/raw/{SOURCE_COMMIT}/{path}"


def ascii_name(title):
    """Mangoré -> Mangore: drop accents, refuse anything else non-ASCII."""
    folded = unicodedata.normalize("NFKD", title).encode("ascii", "ignore").decode()
    if len(folded) != len(unicodedata.normalize("NFKC", title)):
        sys.exit(f"{title}: can't be folded to an ASCII file name")
    return folded


def download(name, sha256):
    request = urllib.request.Request(
        source_url(name), headers={"User-Agent": "sippy-fetch-ringtones"})
    data = urllib.request.urlopen(request).read()
    digest = hashlib.sha256(data).hexdigest()
    if digest != sha256:
        sys.exit(f"{name}: SHA-256 is {digest}, expected {sha256}")
    return data


def measure(path):
    """Integrated loudness (LUFS) and true peak (dBFS) of the mono mix."""
    log = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", path,
         "-af", f"{MONO},ebur128=peak=true", "-f", "null", "-"],
        check=True, capture_output=True, text=True).stderr
    loudness = re.findall(r"^\s+I:\s+(-?[\d.]+) LUFS", log, re.M)[-1]
    peak = re.findall(r"^\s+Peak:\s+(-?[\d.]+) dBFS", log, re.M)[-1]
    return float(loudness), float(peak)


def convert(source, destination, gain_db):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", source,
         "-af", f"{MONO},volume={gain_db:.2f}dB",
         "-ar", "44100", "-c:a", "pcm_s16le",
         "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:a", "+bitexact",
         destination],
        check=True)


def credits_markdown(entries):
    lines = [
        "# Ringtone credits",
        "",
        "Sippy's bundled ringtones come from",
        f"[lomiri-sounds]({SOURCE_REPO}), the sound set of Ubuntu Touch, at commit",
        f"`{SOURCE_COMMIT[:12]}`. The licenses below are the ones recorded in that",
        "repository's `debian/copyright`.",
        "",
        "Each file was converted from Ogg Vorbis stereo to 16-bit 44.1 kHz mono WAV,",
        "with its level changed by the gain listed; nothing else was altered.",
        "`Tools/fetch_ringtones.py` reproduces them.",
        "",
        "| Ringtone | Author | License | Gain |",
        "| --- | --- | --- | --- |",
    ]
    for entry in entries:
        name, url = LICENSES[entry["license"]]
        author = f"{entry['author']}, {entry['year']}"
        lines.append(
            f"| [{entry['title']}]({entry['source']}) | {author} "
            f"| [{name}]({url}) | {entry['gain_db']:+.1f} dB |")
    lines += [
        "",
        "The CC BY licenses ask for this attribution to stay with the files; it is",
        "copied into the app bundle next to them. The licensors do not endorse",
        "Sippy and offer the material without warranties.",
        "",
    ]
    return "\n".join(lines)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    entries = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, author, year, license_id, sha256 in RINGTONES:
            title = os.path.splitext(name)[0]
            source = os.path.join(tmp, name)
            with open(source, "wb") as f:
                f.write(download(name, sha256))
            loudness, peak = measure(source)
            gain = min(TARGET_LUFS - loudness, PEAK_CEILING_DB - peak)
            output = ascii_name(title) + ".wav"
            convert(source, os.path.join(OUT_DIR, output), gain)
            print(f"{output}: {loudness:.1f} LUFS, peak {peak:.1f} dBFS, gain {gain:+.1f} dB")
            entries.append({
                "file": output,
                "title": title,
                "author": author,
                "year": year,
                "license": license_id,
                "source": source_url(name),
                "gain_db": round(gain, 1),
            })

    with open(os.path.join(OUT_DIR, "credits.json"), "w") as f:
        json.dump(
            [{**entry,
              "licenseName": LICENSES[entry["license"]][0],
              "licenseURL": LICENSES[entry["license"]][1]}
             for entry in entries],
            f, indent=2, ensure_ascii=False)
        f.write("\n")
    with open(os.path.join(OUT_DIR, "CREDITS.md"), "w") as f:
        f.write(credits_markdown(entries))


if __name__ == "__main__":
    main()
