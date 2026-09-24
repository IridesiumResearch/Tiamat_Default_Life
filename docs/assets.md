<!-- SPDX-FileCopyrightText: Iridesium -->
<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Assets register

One line per binary file that is not Iridesium's original work by hand or by
this repository's own tools: its source, its author, its licence, and where
that licence is in the tree.

Everything not listed here is Iridesium's and GPL-3.0-only like the code: the
item textures (`mods/tiamat_default_life/textures/`, from
`tools/make_textures.py` and finished in Affinity), the
HUD icons (`icons/`, from `tools/make_icons.py`) and the placeholder sounds
(the `.wav` files in `sounds/`, from `tools/make_sounds.py`).

**Status: incomplete.** The files below are AI-generated. Which generator
made each one, and under what terms, is not yet recorded, so neither the
author nor the licence column is settled. Until it is, nothing here should be
read as a licence grant beyond what the generator's terms allow. Fill in each
line and remove this paragraph.

## Creature models

The modeller's exports are in `assets/source/`; each is re-skinned and sized
for the engine by `tools/skin_glb.py` into `mods/tiamat_default_life/models/`,
with its texture beside it as a `.png`.

| Files | Source | Author | Licence | Licence in tree |
|---|---|---|---|---|
| `assets/source/Tiamat Life AI <Creature>.glb` (16: Bat, Bear, Bunny, Cow, Crow, Fox, Goat, Horse, Mammoth, Pig, Scarecrow, Sheep, Spider, Squirrel, Stag, Wolf) and `assets/source/Tiamat Life AI Pig.jpg` | AI-generated; generator to be confirmed | to be confirmed | to be confirmed (generator's terms) | none yet |
| `mods/tiamat_default_life/models/<creature>.glb` and `.png` (16 of each) | derived from the files above by `tools/skin_glb.py` | as above | as above | none yet |

## Creature voices and the underwater loop

Taken from the project's sound library (`../Tiamat Sounds`, outside this
repository) and converted to mono Ogg by `tools/import_sounds.py`, which
names each take by content hash. The library file each came from is given.

| File in `mods/tiamat_default_life/sounds/` | Library file | Source | Author | Licence | Licence in tree |
|---|---|---|---|---|---|
| `moo.ogg` | `2/Firefly_audio_ASMR-like_Minecraft_world_sounds__cow_moo_variation1.wav` | AI-generated; the filename indicates Adobe Firefly, to be confirmed | to be confirmed | to be confirmed | none yet |
| `baa.ogg` | `2/Firefly_audio_ASMR-like_Minecraft_world_sounds__sheep_ba_variation4.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `oink.ogg` | `2/Firefly_audio_ASMR-like_Minecraft_world_sounds__pig_oink_variation3.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `oink_2.ogg` | `2/Firefly_audio_ASMR-like_Minecraft_world_sounds__pig_oink_variation4.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `bleat.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__goat_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `bell.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__Deer___Stag_variation4.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `growl.ogg` | `2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `growl_2.ogg` | `2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation3.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `growl_3.ogg` | `2/Firefly_audio_minecraft_like_sound_effects__grizzly_Bear_variation4.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `caw.ogg` | `2/Firefly_audio_minecraft_like_sound_effects_slight_ASMR_lean__cro_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `squeak.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__bat_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `flap.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__bat_wing_flap_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `yip.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__fox_variation1.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `bark.ogg` | `2/Firefly_audio_ASMR-like_Minecraft_world_sounds__dog_bark_variation2.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `trumpet.ogg` | `2/Firefly_audio_minecraft_ASMR_sound_effects__elephant_variation4.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `underwater.ogg` | `2/Firefly_audio_ASMR_minecraft_like_sound_effects__undersea_variation2.wav` | as `moo.ogg` | to be confirmed | to be confirmed | none yet |
| `snort.ogg` | `2/Horse_Nose_Blow.wav` | AI-generated; generator to be confirmed | to be confirmed | to be confirmed | none yet |
| `caw_2.ogg` | `2/Mob_Tame_Crow_Valley.wav` | AI-generated; generator to be confirmed | to be confirmed | to be confirmed | none yet |
| `hiss.ogg` | `2/Mob_Hostile_Spider_Warning.wav` | AI-generated; generator to be confirmed | to be confirmed | to be confirmed | none yet |
| `hiss_2.ogg` | `First Test Sounds/Mob_Hostile_Spider_01.mp3` | AI-generated; generator to be confirmed | to be confirmed | to be confirmed | none yet |
