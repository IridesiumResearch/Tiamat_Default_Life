# SPDX-License-Identifier: GPL-3.0-only
"""Generates the item and block textures for mods/tiamot_default_life/textures.

Clean, simple drawings, 64 pixels square: flat colours with soft edges and
one highlight, the way the HUD icons are drawn. The engine draws an item as
a flat picture in a slot, so these are pictures; the two blocks (bed,
campfire) tile a face, so they are painted edge to edge. A file that
already exists is kept, so a hand-drawn picture under the same name is
never overwritten; `--force` regenerates them all. Standard library only;
run from the repository root:

    python tools/make_textures.py
"""
from pathlib import Path

from draw import (box, capsule, circle, ellipse, everything, halfplane, intersect, outlined, png, render,
                  rgba, rotate, shade, shrink, subtract, translate, union)

OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamot_default_life" / "textures"
SIZE = 64

PICTURES = {}


def picture(name, layers, background=None):
    PICTURES[name] = (layers, background)


def gloss(cx, cy, rx, ry, colour):
    return (ellipse(cx, cy, rx, ry), colour)


STEM = rgba(96, 64, 36)
LEAF = rgba(92, 150, 58)
LEAF_DARK = rgba(60, 104, 40)

# --- Food ------------------------------------------------------------------


def apple(body, dark, light):
    fruit = union(circle(-0.22, -0.12, 0.56), circle(0.22, -0.12, 0.56))
    layers = outlined(fruit, body, dark, 0.07)
    layers.append((intersect(shrink(fruit, 0.07), halfplane(0, -1, -0.32)), body))
    layers.append(gloss(-0.34, 0.16, 0.14, 0.20, light))
    layers.append((capsule(0.02, 0.36, 0.06, 0.72, 0.06), STEM))
    layers.append((rotate(translate(ellipse(0, 0, 0.26, 0.11), 0.30, 0.56), 25), LEAF))
    return layers


picture("apple", apple(rgba(204, 44, 44), rgba(120, 22, 26), rgba(255, 170, 160, 200)))
picture("golden_apple", apple(rgba(236, 190, 64), rgba(150, 108, 22), rgba(255, 245, 190, 220)))

BERRY = rgba(96, 48, 130)
BERRY_DARK = rgba(50, 22, 72)
picture("berries", [
    (capsule(0.0, 0.20, -0.10, 0.78, 0.05), STEM),
    (rotate(translate(ellipse(0, 0, 0.30, 0.12), 0.26, 0.60), -30), LEAF),
    *outlined(circle(-0.30, 0.10, 0.34), BERRY, BERRY_DARK),
    *outlined(circle(0.30, 0.00, 0.34), BERRY, BERRY_DARK),
    *outlined(circle(0.00, -0.42, 0.34), BERRY, BERRY_DARK),
    gloss(-0.40, 0.22, 0.10, 0.07, rgba(200, 170, 230, 200)),
    gloss(0.20, 0.12, 0.10, 0.07, rgba(200, 170, 230, 200)),
    gloss(-0.10, -0.30, 0.10, 0.07, rgba(200, 170, 230, 200)),
])

CRUST = rgba(206, 146, 74)
CRUST_DARK = rgba(132, 86, 36)
LOAF = union(box(0.0, -0.10, 0.74, 0.40, 0.34), ellipse(0.0, 0.14, 0.62, 0.30))
picture("bread", [
    *outlined(LOAF, CRUST, CRUST_DARK, 0.07),
    (intersect(shrink(LOAF, 0.07), halfplane(0, 1, 0.34)), shade(CRUST, -0.15)),
    (rotate(translate(capsule(0, -0.16, 0, 0.16, 0.04), -0.30, 0.10), 20), shade(CRUST, 0.35)),
    (rotate(translate(capsule(0, -0.16, 0, 0.16, 0.04), 0.0, 0.14), 20), shade(CRUST, 0.35)),
    (rotate(translate(capsule(0, -0.16, 0, 0.16, 0.04), 0.30, 0.10), 20), shade(CRUST, 0.35)),
])


def meat(flesh, dark, marble):
    chunk = rotate(ellipse(0.16, -0.10, 0.62, 0.42), 30)
    bone = capsule(-0.36, 0.30, -0.70, 0.66, 0.11)
    return [
        *outlined(bone, rgba(236, 228, 208), rgba(170, 160, 140), 0.06),
        (circle(-0.72, 0.68, 0.14), rgba(236, 228, 208)),
        (circle(-0.60, 0.80, 0.12), rgba(236, 228, 208)),
        *outlined(chunk, flesh, dark, 0.07),
        (rotate(translate(ellipse(0, 0, 0.30, 0.09), 0.10, 0.00), 30), marble),
        gloss(0.30, 0.10, 0.12, 0.08, shade(flesh, 0.4)),
    ]


picture("raw_meat", meat(rgba(214, 78, 92), rgba(140, 36, 52), rgba(246, 208, 210, 220)))
picture("cooked_meat", meat(rgba(150, 86, 44), rgba(88, 46, 22), rgba(200, 140, 90, 220)))

BOWL = rgba(124, 84, 52)
BOWL_DARK = rgba(70, 44, 26)
STEW = rgba(184, 100, 42)
picture("hot_stew", [
    (capsule(-0.30, 0.66, -0.22, 0.88, 0.05), rgba(240, 240, 240, 140)),
    (capsule(0.00, 0.62, 0.08, 0.86, 0.05), rgba(240, 240, 240, 140)),
    (capsule(0.30, 0.66, 0.38, 0.88, 0.05), rgba(240, 240, 240, 140)),
    *outlined(intersect(circle(0.0, 0.10, 0.82), halfplane(0, 1, -0.10)), BOWL, BOWL_DARK, 0.07),
    *outlined(ellipse(0.0, 0.10, 0.82, 0.26), STEW, BOWL_DARK, 0.06),
    (circle(-0.30, 0.12, 0.10), rgba(220, 150, 60)),
    (circle(0.24, 0.08, 0.09), rgba(120, 150, 70)),
    (circle(0.02, 0.18, 0.07), rgba(220, 150, 60)),
    (box(0.0, -0.70, 0.40, 0.06, 0.06), BOWL_DARK),
])

RIND = rgba(70, 150, 82)
RIND_DARK = rgba(40, 100, 56)
FLESH = rgba(232, 96, 116)
# A wedge: a big circle cut by a straight edge, so the rind is the arc.
WEDGE = intersect(circle(-0.35, -0.45, 1.15), halfplane(-0.55, -1.0, -0.15))
picture("cool_melon", [
    *outlined(WEDGE, RIND, RIND_DARK, 0.07),
    (shrink(WEDGE, 0.20), rgba(232, 240, 220)),
    (shrink(WEDGE, 0.28), FLESH),
    *[(intersect(circle(cx, cy, r), shrink(WEDGE, 0.34)), rgba(40, 28, 30))
      for cx, cy, r in ((0.02, 0.06, 0.06), (0.30, -0.10, 0.06), (-0.10, -0.24, 0.06), (0.20, 0.26, 0.05))],
])

AMBER = rgba(234, 172, 56)
AMBER_DARK = rgba(170, 112, 26)
JAR = box(0.0, -0.16, 0.56, 0.58, 0.22)
picture("honey", [
    *outlined(JAR, AMBER, AMBER_DARK, 0.07),
    (box(0.0, 0.10, 0.50, 0.06), shade(AMBER, -0.2)),
    gloss(-0.30, -0.10, 0.10, 0.34, rgba(255, 240, 200, 170)),
    *outlined(box(0.0, 0.58, 0.44, 0.16, 0.06), rgba(150, 104, 62), rgba(96, 62, 34), 0.06),
])

# --- Medicine --------------------------------------------------------------

GAUZE = rgba(240, 236, 226)
GAUZE_DARK = rgba(176, 168, 150)
ROLL = box(0.0, 0.0, 0.62, 0.42, 0.30)
picture("bandage", [
    (box(0.40, -0.44, 0.44, 0.10, 0.06), GAUZE),
    *outlined(ROLL, GAUZE, GAUZE_DARK, 0.07),
    (circle(-0.30, 0.00, 0.20), GAUZE_DARK),
    (circle(-0.30, 0.00, 0.10), GAUZE),
    (box(0.24, 0.0, 0.04, 0.32), rgba(200, 190, 170)),
    (box(0.44, 0.0, 0.04, 0.32), rgba(200, 190, 170)),
])

POTION = rgba(94, 204, 116, 235)
POTION_DARK = rgba(46, 130, 70)
GLASS = rgba(190, 220, 240, 200)
BOTTLE = union(box(0.0, -0.28, 0.46, 0.44, 0.24), box(0.0, 0.30, 0.16, 0.30, 0.04))
picture("antidote", [
    *outlined(BOTTLE, GLASS, rgba(110, 140, 170), 0.06),
    (intersect(shrink(BOTTLE, 0.10), halfplane(0, 1, 0.02)), POTION),
    gloss(-0.22, -0.20, 0.08, 0.28, rgba(255, 255, 255, 170)),
    *outlined(box(0.0, 0.66, 0.18, 0.14, 0.05), rgba(150, 104, 62), rgba(96, 62, 34), 0.05),
])

# --- Clothing --------------------------------------------------------------

WOOL = rgba(128, 82, 48)
WOOL_DARK = rgba(78, 48, 28)
FUR = rgba(226, 206, 176)
COAT = union(box(0.0, -0.10, 0.62, 0.66, 0.16), box(0.0, 0.34, 0.86, 0.24, 0.12))
picture("warm_coat", [
    *outlined(COAT, WOOL, WOOL_DARK, 0.07),
    (box(0.0, -0.70, 0.56, 0.08), FUR),
    (box(0.0, 0.56, 0.36, 0.10, 0.05), FUR),
    (box(0.0, -0.12, 0.04, 0.56), WOOL_DARK),
    (circle(0.16, 0.14, 0.05), WOOL_DARK),
    (circle(0.16, -0.14, 0.05), WOOL_DARK),
    (circle(0.16, -0.42, 0.05), WOOL_DARK),
])

SILK = rgba(158, 206, 236)
SILK_DARK = rgba(90, 140, 180)
# A cloak hangs: narrow at the shoulders, wide at the hem, cut flat below.
CLOAK = intersect(halfplane(-1.0, 0.55, -0.70), halfplane(1.0, 0.55, -0.70), halfplane(0, -1, -0.78))
picture("cool_cloak", [
    *outlined(CLOAK, SILK, SILK_DARK, 0.07),
    *outlined(circle(0.0, 0.52, 0.30), SILK, SILK_DARK, 0.07),
    (circle(0.0, 0.48, 0.16), shade(SILK, -0.3)),
    (capsule(0.0, 0.20, 0.0, -0.66, 0.03), SILK_DARK),
])

# --- Blocks ----------------------------------------------------------------
#
# Painted edge to edge: a block face has no transparent corner.

WOOD = rgba(116, 80, 46)
WOOD_DARK = rgba(80, 52, 30)
BLANKET = rgba(176, 44, 48)
PILLOW = rgba(238, 234, 222)
picture("bed", [
    (box(0.0, 0.0, 0.86, 0.92, 0.06), rgba(226, 222, 212)),
    (box(0.0, -0.18, 0.86, 0.66, 0.06), BLANKET),
    (box(0.0, 0.10, 0.86, 0.05), shade(BLANKET, -0.25)),
    (box(0.0, 0.60, 0.66, 0.20, 0.10), PILLOW),
    (box(0.0, 0.56, 0.50, 0.03), rgba(200, 194, 180)),
], background=WOOD)

ASH = rgba(74, 66, 62)
LOG = rgba(104, 72, 42)
LOG_DARK = rgba(66, 44, 26)
FLAME = rgba(244, 150, 40)
FLAME_CORE = rgba(255, 224, 110)
picture("campfire", [
    (circle(-0.62, -0.72, 0.20), rgba(120, 112, 108)),
    (circle(0.66, -0.74, 0.18), rgba(120, 112, 108)),
    (circle(0.02, -0.82, 0.16), rgba(120, 112, 108)),
    *outlined(rotate(capsule(-0.62, 0, 0.62, 0, 0.12), 18), LOG, LOG_DARK, 0.05),
    *outlined(rotate(capsule(-0.62, 0, 0.62, 0, 0.12), -18), LOG, LOG_DARK, 0.05),
    (union(circle(0.0, -0.06, 0.40), intersect(halfplane(-1.0, 0.72, -0.30), halfplane(1.0, 0.72, -0.30), halfplane(0, -1, -0.10))), FLAME),
    (union(circle(0.0, -0.14, 0.20), intersect(halfplane(-1.0, 0.5, -0.12), halfplane(1.0, 0.5, -0.12), halfplane(0, -1, -0.16))), FLAME_CORE),
], background=ASH)


def main(force=False):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (layers, background) in PICTURES.items():
        target = OUT / f"{name}.png"
        if target.exists() and not force:
            print("kept ", name)
            continue
        target.write_bytes(png(SIZE, render(layers, SIZE, 3, background)))
        print("wrote", name)


if __name__ == "__main__":
    import sys
    main(force="--force" in sys.argv)
