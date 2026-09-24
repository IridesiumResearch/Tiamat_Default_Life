# SPDX-License-Identifier: GPL-3.0-only
"""Brings recordings from the project's sound library into the mod.

The library is `../Tiamat Sounds`, beside this repo, and is not part of it:
hundreds of megabytes of takes, most of them for other mods (weather, the
world's ambience, the interface) or for creatures that do not exist yet.
This script names the ones Life uses and converts each into the form the
engine wants: Ogg Vorbis (the brief's preference, and it sidesteps the WAV
reader's refusal of files carrying editor metadata, which these do),
mono (a creature's voice is placed in the world and panned by the engine;
a stereo take would carry its own left and right), 44.1 kHz, and brought
to one loudness so that `gain` in items.lua is a mix decision rather than
a repair.

    python tools/import_sounds.py            # converts what is missing
    python tools/import_sounds.py --force    # and redoes the rest

Needs ffmpeg on the PATH, with libvorbis. Everything else is the standard
library, like the other tools.
"""
import argparse
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIBRARY = os.path.normpath(os.path.join(HERE, "..", "..", "Tiamat Sounds"))
SOUNDS = os.path.normpath(os.path.join(HERE, "..", "mods", "tiamat_default_life", "sounds"))

# The sound id in the mod (its file is sounds/<id>.ogg) and the take it comes from.
RECORDINGS = {
    "moo": "2/Firefly_audio_ASMR-like_Minecraft_world_sounds__cow_moo_variation1.wav",
    "baa": "2/Firefly_audio_ASMR-like_Minecraft_world_sounds__sheep_ba_variation4.wav",
    "oink": "2/Firefly_audio_ASMR-like_Minecraft_world_sounds__pig_oink_variation3.wav",
    "oink_2": "2/Firefly_audio_ASMR-like_Minecraft_world_sounds__pig_oink_variation4.wav",
    "snort": "2/Horse_Nose_Blow.wav",
    "bleat": "2/Firefly_audio_minecraft_ASMR_sound_effects__goat_variation1.wav",
    "bell": "2/Firefly_audio_minecraft_ASMR_sound_effects__Deer___Stag_variation4.wav",
    "growl": "2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation1.wav",
    "growl_2": "2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation3.wav",
    "growl_3": "2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation4.wav",
    "caw": "2/Firefly_audio_minecraft_like_sound_effects_slight_ASMR_lean__cro_variation1.wav",
    "caw_2": "2/Mob_Tame_Crow_Valley.wav",
    "squeak": "2/Firefly_audio_minecraft_ASMR_sound_effects__bat_variation1.wav",
    "flap": "2/Firefly_audio_minecraft_ASMR_sound_effects__bat_wing_flap_variation1.wav",
    "underwater": "2/Firefly_audio_ASMR_minecraft_like_sound_effects__undersea_variation2.wav",
}

# One loudness for every take, in LUFS, with a ceiling under clipping.
LOUDNESS = "loudnorm=I=-18:TP=-2:LRA=11"


def convert(source, target):
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", source,
         "-af", LOUDNESS, "-ac", "1", "-ar", "44100",
         "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "5", target],
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
    for sound, take in sorted(RECORDINGS.items()):
        source = os.path.join(LIBRARY, take)
        target = os.path.join(SOUNDS, sound + ".ogg")
        if os.path.exists(target) and not args.force:
            print(f"kept      {sound}.ogg")
            continue
        convert(source, target)
        print(f"converted {sound}.ogg  <- {take}  ({os.path.getsize(target)} bytes)")


if __name__ == "__main__":
    main()
