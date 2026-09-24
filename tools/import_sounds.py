# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Brings recordings from the project's sound library into the mod.

The library is `../Tiamat Sounds`, beside this repo, and is not part of it:
hundreds of megabytes of takes, most of them for other mods (weather, the
world's ambience, the interface) or for creatures that do not exist yet.
This script names the ones Life uses and converts each into the form the
engine wants: Ogg Vorbis (the brief's preference, and it sidesteps the WAV
reader's strictness about extra chunks), mono (a creature's voice is placed
in the world and panned by the engine; a stereo take would carry its own
left and right), 44.1 kHz, and brought to one loudness so that `gain` in
items.lua is a mix decision rather than a repair.

A take is found by its CONTENT, the first sixteen hex digits of its
SHA-256, wherever it sits in the library and whatever it is called, so the
library can be sorted and renamed freely without this script following.

    python tools/import_sounds.py            # converts what is missing
    python tools/import_sounds.py --force    # and redoes the rest

Needs ffmpeg on the PATH, with libvorbis. Everything else is the standard
library, like the other tools.
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIBRARY = os.path.normpath(os.path.join(HERE, "..", "..", "Tiamat Sounds"))
SOUNDS = os.path.normpath(os.path.join(HERE, "..", "mods", "tiamat_default_life", "sounds"))
AUDIO = (".wav", ".mp3", ".m4a", ".ogg", ".flac")

# The sound id in the mod (its file is sounds/<id>.ogg) and the take it comes from.
RECORDINGS = {
    "moo": "88e75ae8c2cda6eb",       # a cow
    "baa": "b3d4f0cd5f8a75fb",       # a sheep
    "oink": "0e3d0479de920ccd",      # a pig
    "oink_2": "9be15a8a355b476d",    # a pig, another take
    "snort": "967a11b64844e8e5",     # a horse blowing through its nose
    "bleat": "06733bfaee99e207",     # a goat
    "bell": "65950341ae23703f",      # a stag's bellow
    "growl": "36b57afe8c0a69ef",     # a bear
    "growl_2": "3f9cc28a0f49521d",   # a bear, another take
    "growl_3": "d083281e0c3c3572",   # and a third
    "caw": "a11afb8735936043",       # a crow
    "caw_2": "69d6db920e10b802",     # a crow over a valley
    "squeak": "b043123bdf34a054",    # a bat
    "flap": "bdb20ee4f78600c1",      # a bat's wings
    "yip": "848f5b5b9df9f017",       # a fox
    "bark": "02411d5aed815cfc",      # a dog's bark, for the wolf until there is a howl
    "trumpet": "6f3f9789ab78926e",   # an elephant, for the mammoth
    "hiss": "a497e45b4d22de1e",      # a spider's warning
    "hiss_2": "8d577e2ffbf01cf3",    # a spider
    "underwater": "cd14f11e0ed389b1",  # the sea, heard from under it
}

# One loudness for every take, in LUFS, with a ceiling under clipping.
LOUDNESS = "loudnorm=I=-18:TP=-2:LRA=11"


def fingerprint(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()[:16]


def index_library():
    """Every audio file in the library, by fingerprint."""
    found = {}
    for root, _, files in os.walk(LIBRARY):
        for name in files:
            if name.lower().endswith(AUDIO):
                path = os.path.join(root, name)
                found.setdefault(fingerprint(path), path)
    return found


def convert(source, target):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", source,
         "-af", LOUDNESS, "-ac", "1", "-ar", "44100", "-c:a", "libvorbis", "-q:a", "5", target],
        check=True,
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true", help="convert again even where the .ogg exists")
    args = ap.parse_args()
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg is not on the PATH")
    if not os.path.isdir(LIBRARY):
        sys.exit(f"no sound library at {LIBRARY}")
    library = None
    for sound, take in sorted(RECORDINGS.items()):
        target = os.path.join(SOUNDS, sound + ".ogg")
        if os.path.exists(target) and not args.force:
            print(f"kept      {sound}.ogg")
            continue
        if library is None:
            library = index_library()
        source = library.get(take)
        if source is None:
            print(f"MISSING   {sound}.ogg: no take {take} in the library")
            continue
        convert(source, target)
        print(f"converted {sound}.ogg  ({os.path.getsize(target)} bytes)")


if __name__ == "__main__":
    main()
