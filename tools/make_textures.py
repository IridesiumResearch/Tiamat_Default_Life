# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the item and block textures for mods/tiamat_default_life/textures.

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

OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_life" / "textures"
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

# --- Farming ---------------------------------------------------------------
#
# Crops, produce, tools and the blocks a farm is made of. The crop stages and
# the picked bramble are cross-billboard sprites, so they stand on the bottom
# edge of a transparent canvas; the ground blocks are painted edge to edge.

IRON = rgba(156, 160, 168)
IRON_DARK = rgba(84, 88, 96)
SOIL = rgba(126, 88, 52)
SOIL_DARK = rgba(84, 56, 32)
GRASS_BG = rgba(98, 152, 70)
STRAW = rgba(220, 180, 84)
STRAW_DARK = rgba(150, 110, 40)
ROPE = rgba(200, 162, 106)
ROPE_DARK = rgba(132, 98, 56)
CREAM = rgba(244, 238, 222)
CREAM_DARK = rgba(184, 174, 150)
TURNIP = rgba(154, 92, 174)
TURNIP_DARK = rgba(96, 50, 112)
CAP = rgba(150, 100, 60)
CAP_DARK = rgba(92, 56, 30)


def leaf(cx, cy, rx, ry, angle, colour=LEAF):
    """An ellipse turned by `angle` degrees, then set down at (cx, cy)."""
    return (translate(rotate(ellipse(0, 0, rx, ry), angle), cx, cy), colour)


def stalk(x0, y0, x1, y1, r=0.05, colour=LEAF):
    return (capsule(x0, y0, x1, y1, r), colour)


def drop(cx, cy, r):
    """A teardrop: a circle with a point twice its radius above."""
    point = intersect(halfplane(-1, 0.5, -r), halfplane(1, 0.5, -r), halfplane(0, -1, 0))
    return translate(union(circle(0, 0, r), point), cx, cy)


def scatter(shape_at, colour, dark, spots):
    layers = []
    for cx, cy, angle in spots:
        layers += outlined(translate(rotate(shape_at(), angle), cx, cy), colour, dark, 0.04)
    return layers


def toadstool(cx, base, w, h, cap=CAP, cap_dark=CAP_DARK, stem=CREAM, stem_dark=CREAM_DARK):
    """A mushroom standing at (cx, base): a pale stem under a domed cap."""
    top = base + h
    cap_shape = intersect(ellipse(cx, top - h * 0.45, w, h * 0.55), halfplane(0, -1, top - h * 0.45))
    return [
        *outlined(capsule(cx, base, cx, top - h * 0.35, w * 0.32), stem, stem_dark, 0.04),
        *outlined(cap_shape, cap, cap_dark, 0.05),
        gloss(cx - w * 0.4, top - h * 0.2, w * 0.18, h * 0.10, shade(cap, 0.45)),
    ]


def bucket(inside, glossy=False):
    """A wooden bucket seen from slightly above; `inside` fills the mouth."""
    body = intersect(halfplane(-1, -0.12, -0.56), halfplane(1, -0.12, -0.56), halfplane(0, -1, -0.72), halfplane(0, 1, -0.40))
    mouth = ellipse(0.0, 0.40, 0.60, 0.20)
    handle = intersect(subtract(circle(0.0, 0.40, 0.68), circle(0.0, 0.40, 0.62)), halfplane(0, -1, 0.40))
    layers = [
        (handle, WOOD_DARK),
        *outlined(union(body, mouth), WOOD, WOOD_DARK, 0.06),
        (capsule(-0.26, 0.24, -0.20, -0.66, 0.02), WOOD_DARK),
        (capsule(0.02, 0.24, 0.02, -0.66, 0.02), WOOD_DARK),
        (capsule(0.30, 0.24, 0.24, -0.66, 0.02), WOOD_DARK),
        (intersect(box(0.0, -0.12, 0.70, 0.05), shrink(body, 0.04)), shade(WOOD, 0.35)),
        *outlined(mouth, inside, WOOD_DARK, 0.06),
    ]
    if glossy:
        layers.append(gloss(-0.22, 0.44, 0.16, 0.06, rgba(255, 255, 255, 170)))
    return layers


# Produce

TURNIP_ROOT = union(circle(0.0, -0.20, 0.54), drop(0.0, -1.0, 0.16))
picture("turnip", [
    leaf(-0.28, 0.44, 0.34, 0.11, 60),
    leaf(0.30, 0.46, 0.34, 0.11, -60),
    leaf(0.0, 0.54, 0.34, 0.11, 90, LEAF_DARK),
    *outlined(TURNIP_ROOT, CREAM, TURNIP_DARK, 0.06),
    (intersect(shrink(TURNIP_ROOT, 0.06), halfplane(0, -1, -0.02)), TURNIP),
    gloss(-0.22, 0.08, 0.10, 0.12, rgba(230, 200, 240, 200)),
])

HEAP = union(ellipse(0.0, -0.50, 0.78, 0.32), circle(0.0, -0.36, 0.44))
picture("rice", [
    *outlined(HEAP, CREAM, CREAM_DARK, 0.06),
    *scatter(lambda: ellipse(0, 0, 0.12, 0.05), shade(CREAM, 0.5), CREAM_DARK,
             [(-0.44, -0.46, 20), (-0.12, -0.30, -30), (0.20, -0.22, 15), (0.46, -0.44, -20),
              (0.02, -0.56, 40), (-0.30, -0.66, -10), (0.30, -0.64, 25), (0.0, 0.02, -15)]),
])

picture("mushroom", toadstool(0.0, -0.90, 0.62, 1.30) + [
    (circle(-0.24, 0.30, 0.07), shade(CAP, 0.5)),
    (circle(0.18, 0.44, 0.06), shade(CAP, 0.5)),
    (circle(0.34, 0.16, 0.05), shade(CAP, 0.5)),
])

EGG = union(ellipse(0.0, -0.16, 0.50, 0.54), ellipse(0.0, 0.08, 0.42, 0.62))
picture("egg", [
    *outlined(EGG, rgba(226, 196, 160), rgba(160, 118, 80), 0.06),
    gloss(-0.20, 0.24, 0.10, 0.18, rgba(255, 244, 230, 200)),
])

picture("milk", bucket(rgba(246, 243, 234), glossy=True))
picture("bucket", bucket(rgba(48, 30, 18)))
picture("water_bucket", bucket(rgba(72, 142, 212), glossy=True))

SHEAF = [(-0.52, 0.48), (-0.26, 0.62), (0.0, 0.70), (0.26, 0.62), (0.52, 0.48)]
picture("wheat", [
    *[stalk(0.0, -0.90, tx, ty, 0.05, STRAW) for tx, ty in SHEAF],
    *[layer for tx, ty in SHEAF
      for layer in outlined(translate(rotate(ellipse(0, 0, 0.10, 0.24), -tx * 40), tx, ty + 0.14), STRAW, STRAW_DARK, 0.04)],
    *outlined(rotate(box(0.0, -0.36, 0.34, 0.09, 0.04), 8), ROPE, ROPE_DARK, 0.04),
])

SEED_SPOTS = [(-0.50, 0.40, 30), (0.10, 0.52, -20), (0.56, 0.20, 60), (-0.20, 0.06, -50),
              (0.30, -0.16, 10), (-0.58, -0.30, -30), (0.02, -0.46, 45), (0.50, -0.56, -10), (-0.30, -0.70, 20)]
picture("wheat_seeds", scatter(lambda: ellipse(0, 0, 0.15, 0.09), rgba(200, 150, 70), rgba(126, 86, 34), SEED_SPOTS))
picture("turnip_seeds", scatter(lambda: circle(0, 0, 0.11), rgba(76, 52, 40), rgba(34, 22, 16), SEED_SPOTS))
picture("rice_seeds", scatter(lambda: ellipse(0, 0, 0.17, 0.06), CREAM, CREAM_DARK, SEED_SPOTS))
picture("melon_seeds", scatter(lambda: drop(0, -0.08, 0.11), rgba(240, 226, 190), rgba(176, 150, 100), SEED_SPOTS))

picture("spores", toadstool(0.0, -0.92, 0.30, 0.50) + [
    (circle(cx, cy, r), rgba(230, 222, 200, 210))
    for cx, cy, r in ((-0.40, 0.10, 0.07), (-0.10, 0.30, 0.09), (0.28, 0.14, 0.08), (0.50, 0.40, 0.06),
                      (-0.56, 0.44, 0.06), (0.10, 0.62, 0.07), (-0.24, 0.66, 0.05), (0.42, 0.68, 0.05),
                      (-0.06, -0.02, 0.06), (0.62, -0.10, 0.05), (-0.62, -0.14, 0.05))
])


def thorny(x0, y0, x1, y1, thorns):
    """A dark cane with small thorns sticking out along it."""
    layers = [stalk(x0, y0, x1, y1, 0.08, rgba(34, 68, 36))]
    for t, side in thorns:
        px, py = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        nx, ny = -(y1 - y0), x1 - x0
        n = (nx * nx + ny * ny) ** 0.5
        layers.append(stalk(px, py, px + nx / n * 0.18 * side, py + ny / n * 0.18 * side, 0.035, rgba(34, 68, 36)))
    return layers


picture("bramble_cane", [
    *thorny(-0.72, -0.76, 0.72, 0.76, [(0.2, 1), (0.4, -1), (0.6, 1), (0.8, -1)]),
    leaf(-0.22, 0.30, 0.26, 0.11, 60, LEAF_DARK),
    leaf(0.36, -0.10, 0.24, 0.10, -30, LEAF),
])

# Tools

picture("hoe", [
    *outlined(capsule(-0.80, -0.82, 0.24, 0.40, 0.08), WOOD, WOOD_DARK, 0.05),
    *outlined(translate(rotate(box(0, 0, 0.54, 0.18, 0.05), -45), 0.50, 0.32), IRON, IRON_DARK, 0.05),
    gloss(0.36, 0.54, 0.05, 0.14, rgba(240, 240, 250, 170)),
])

# A crescent: a circle less a smaller one set up and to the right, so the blade
# is thick at the bottom left and tapers to a point at the top.
BLADE = intersect(subtract(circle(0.10, 0.22, 0.62), circle(0.26, 0.36, 0.56)), halfplane(1, 0, -0.35))
picture("sickle", [
    *outlined(capsule(0.12, -0.36, 0.46, -0.88, 0.09), WOOD, WOOD_DARK, 0.05),
    *outlined(BLADE, IRON, IRON_DARK, 0.05),
    gloss(-0.38, 0.08, 0.05, 0.18, rgba(240, 240, 250, 170)),
])

RING = subtract(circle(0, 0, 0.22), circle(0, 0, 0.12))
picture("shears", [
    *outlined(rotate(capsule(0, -0.06, 0, 0.82, 0.10), 22), IRON, IRON_DARK, 0.05),
    *outlined(rotate(capsule(0, -0.06, 0, 0.82, 0.10), -22), IRON, IRON_DARK, 0.05),
    *outlined(capsule(0.0, -0.06, -0.30, -0.50, 0.06), IRON, IRON_DARK, 0.04),
    *outlined(capsule(0.0, -0.06, 0.30, -0.50, 0.06), IRON, IRON_DARK, 0.04),
    *outlined(translate(RING, -0.38, -0.66), IRON, IRON_DARK, 0.04),
    *outlined(translate(RING, 0.38, -0.66), IRON, IRON_DARK, 0.04),
    (circle(0.0, -0.06, 0.07), IRON_DARK),
    gloss(0.14, 0.46, 0.04, 0.16, rgba(240, 240, 250, 170)),
])

# Animal goods

COIL = subtract(circle(0.0, -0.06, 0.60), circle(0.0, -0.06, 0.32))
picture("lead", [
    *outlined(COIL, ROPE, ROPE_DARK, 0.05),
    (subtract(circle(0.0, -0.06, 0.48), circle(0.0, -0.06, 0.44)), ROPE_DARK),
    *outlined(capsule(0.36, 0.26, 0.56, 0.48, 0.07), ROPE, ROPE_DARK, 0.04),
    *outlined(subtract(circle(0.66, 0.66, 0.26), circle(0.66, 0.66, 0.13)), ROPE, ROPE_DARK, 0.04),
])

FLEECE = union(circle(-0.36, 0.04, 0.36), circle(0.30, 0.10, 0.38), circle(0.0, 0.34, 0.34),
               circle(-0.16, -0.36, 0.34), circle(0.30, -0.34, 0.32), circle(0.0, -0.06, 0.40))
picture("wool", [
    *outlined(FLEECE, CREAM, rgba(184, 180, 172), 0.06),
    (circle(-0.36, 0.04, 0.24), shade(CREAM, -0.05)),
    (circle(0.30, -0.34, 0.20), shade(CREAM, -0.05)),
    gloss(-0.06, 0.34, 0.12, 0.10, rgba(255, 255, 255, 220)),
])

PLUME = translate(rotate(union(ellipse(0, 0.08, 0.20, 0.62), ellipse(0, 0.30, 0.16, 0.48)), 40), 0.04, 0.10)
NOTCH = translate(rotate(union(capsule(-0.30, -0.06, 0.02, -0.06, 0.04), capsule(-0.28, 0.20, 0.02, 0.20, 0.04)), 40), 0.0, 0.0)
picture("feather", [
    *outlined(capsule(0.54, -0.58, 0.72, -0.82, 0.05), rgba(228, 226, 218), rgba(150, 148, 140), 0.03),
    *outlined(subtract(PLUME, NOTCH), rgba(58, 60, 66), rgba(22, 24, 28), 0.05),
    (capsule(-0.42, 0.66, 0.52, -0.52, 0.03), rgba(216, 214, 206)),
])

HIDE = union(box(0.0, 0.0, 0.66, 0.50, 0.24), circle(-0.62, 0.42, 0.20), circle(0.66, 0.40, 0.18),
             circle(-0.64, -0.44, 0.18), circle(0.62, -0.46, 0.20), circle(0.0, 0.58, 0.16))
picture("hide", [
    *outlined(HIDE, rgba(200, 160, 110), rgba(138, 98, 58), 0.08),
    (circle(-0.24, 0.10, 0.12), rgba(186, 144, 96)),
    (ellipse(0.26, -0.12, 0.16, 0.10), rgba(186, 144, 96)),
    (circle(0.10, 0.32, 0.07), rgba(186, 144, 96)),
])

BONE_SHAPE = union(capsule(-0.46, -0.46, 0.46, 0.46, 0.12),
                   circle(-0.62, -0.36, 0.17), circle(-0.40, -0.60, 0.17),
                   circle(0.62, 0.36, 0.17), circle(0.40, 0.60, 0.17))
picture("bone", [
    *outlined(BONE_SHAPE, rgba(240, 234, 216), rgba(170, 160, 140), 0.06),
    gloss(-0.14, 0.02, 0.06, 0.18, rgba(255, 255, 255, 170)),
])

SINEW = subtract(ellipse(0.0, 0.04, 0.62, 0.46), ellipse(0.0, 0.04, 0.44, 0.28))
picture("sinew", [
    *outlined(capsule(-0.44, -0.30, -0.80, -0.72, 0.07), rgba(220, 196, 150), ROPE_DARK, 0.04),
    *outlined(capsule(0.44, -0.30, 0.78, -0.70, 0.07), rgba(220, 196, 150), ROPE_DARK, 0.04),
    *outlined(SINEW, rgba(220, 196, 150), ROPE_DARK, 0.05),
    *[(intersect(translate(rotate(capsule(0, -0.10, 0, 0.10, 0.025), a), cx, cy), shrink(SINEW, 0.05)), ROPE_DARK)
      for cx, cy, a in ((-0.40, 0.36, -40), (0.0, 0.46, 0), (0.40, 0.36, 40), (0.54, -0.10, 80), (-0.54, -0.10, -80),
                        (-0.30, -0.30, -140), (0.30, -0.30, 140))],
])

# Ground and structures

FURROWS = union(*[capsule(-1.2, y, 1.2, y, 0.09) for y in (0.62, 0.20, -0.22, -0.64)])
CLODS = [(circle(-0.60, 0.42, 0.09)), (circle(0.30, 0.44, 0.07)), (circle(-0.10, 0.00, 0.08)),
         (circle(0.62, -0.02, 0.06)), (circle(-0.50, -0.44, 0.07)), (circle(0.22, -0.42, 0.09)), (circle(0.70, -0.84, 0.06))]
picture("farmland", [
    (FURROWS, SOIL_DARK),
    *[(clod, shade(SOIL, 0.18)) for clod in CLODS],
], background=SOIL)

WET = rgba(86, 64, 48)
picture("wet_farmland", [
    (FURROWS, rgba(50, 36, 28)),
    *[(capsule(-0.6, y + 0.03, 0.9, y + 0.03, 0.025), rgba(150, 140, 150, 110)) for y in (0.62, 0.20, -0.22, -0.64)],
    *[(clod, shade(WET, 0.16)) for clod in CLODS],
], background=WET)

POSTS = [*outlined(box(-0.56, 0.0, 0.13, 1.20), WOOD, WOOD_DARK, 0.05),
         *outlined(box(0.56, 0.0, 0.13, 1.20), WOOD, WOOD_DARK, 0.05)]
PLANKS = [*outlined(box(0.0, 0.38, 1.20, 0.14), WOOD, WOOD_DARK, 0.05),
          *outlined(box(0.0, -0.30, 1.20, 0.14), WOOD, WOOD_DARK, 0.05)]
picture("fence", [*PLANKS, *POSTS], background=GRASS_BG)

picture("gate", [
    *PLANKS,
    *outlined(rotate(box(0.0, 0.04, 0.74, 0.11), 32), WOOD, WOOD_DARK, 0.05),
    *POSTS,
    *outlined(box(0.58, 0.06, 0.10, 0.16, 0.04), IRON, IRON_DARK, 0.04),
], background=GRASS_BG)

picture("gate_open", [
    *outlined(box(-0.36, 0.04, 0.06, 0.62, 0.02), shade(WOOD, -0.1), WOOD_DARK, 0.03),
    *POSTS,
], background=GRASS_BG)


def skep(straw, straw_dark, extra):
    dome = intersect(circle(0.0, -0.30, 0.82), halfplane(0, -1, -0.84))
    return [
        *outlined(dome, straw, straw_dark, 0.06),
        *[(intersect(capsule(-1.0, y, 1.0, y, 0.03), shrink(dome, 0.06)), straw_dark) for y in (0.30, 0.06, -0.18, -0.42, -0.66)],
        gloss(-0.34, 0.28, 0.10, 0.08, shade(straw, 0.4)),
        (circle(0.0, -0.66, 0.11), rgba(40, 24, 12)),
        *extra,
    ]


HIVE_BG = rgba(62, 40, 24)
picture("beehive", skep(STRAW, STRAW_DARK, []), background=HIVE_BG)
picture("beehive_full", skep(rgba(226, 170, 60), rgba(150, 100, 30), [
    (drop(-0.10, -0.92, 0.07), AMBER),
    (drop(0.12, -0.86, 0.05), AMBER),
    (capsule(-0.10, -0.76, -0.10, -0.86, 0.04), AMBER),
]), background=HIVE_BG)

picture("bramble_picked", [
    *thorny(-0.80, -0.90, 0.20, 0.80, [(0.25, 1), (0.5, -1), (0.75, 1)]),
    *thorny(0.70, -0.92, -0.30, 0.60, [(0.3, -1), (0.6, 1), (0.85, -1)]),
    *thorny(-0.86, 0.20, 0.86, 0.36, [(0.3, 1), (0.7, -1)]),
    leaf(-0.44, 0.50, 0.22, 0.10, 40, LEAF_DARK),
    leaf(0.52, -0.16, 0.22, 0.10, -50, LEAF_DARK),
    leaf(0.06, -0.40, 0.20, 0.09, 20, LEAF),
])

# Crop stages: sprites standing on the bottom edge.

picture("wheat_1", [
    stalk(-0.32, -1.0, -0.44, -0.46, 0.05),
    stalk(0.02, -1.0, 0.06, -0.30, 0.05),
    stalk(0.36, -1.0, 0.44, -0.50, 0.05),
])

picture("wheat_2", [
    *[stalk(x, -1.0, x + dx, 0.10, 0.05) for x, dx in ((-0.56, -0.08), (-0.20, -0.02), (0.14, 0.02), (0.50, 0.08))],
    *[(ellipse(x + dx, 0.18, 0.08, 0.18), shade(LEAF, 0.25)) for x, dx in ((-0.56, -0.08), (-0.20, -0.02), (0.14, 0.02), (0.50, 0.08))],
    stalk(-0.40, -1.0, -0.72, -0.40, 0.045, LEAF_DARK),
    stalk(0.32, -1.0, 0.70, -0.44, 0.045, LEAF_DARK),
])

RIPE = [(-0.62, -0.12), (-0.30, -0.02), (0.02, 0.06), (0.34, -0.02), (0.64, -0.12)]
picture("wheat_3", [
    *[stalk(x * 0.7, -1.0, x, 0.44 + dy, 0.045, STRAW) for x, dy in RIPE],
    *[layer for x, dy in RIPE for layer in outlined(ellipse(x, 0.62 + dy, 0.11, 0.30), STRAW, STRAW_DARK, 0.04)],
    *[(ellipse(x - 0.03, 0.72 + dy, 0.03, 0.14), shade(STRAW, 0.4)) for x, dy in RIPE],
    stalk(-0.30, -1.0, -0.80, -0.30, 0.04, shade(STRAW, -0.2)),
    stalk(0.30, -1.0, 0.80, -0.34, 0.04, shade(STRAW, -0.2)),
])


def rosette(size):
    return [
        leaf(-0.24 * size, -1.0 + 0.30 * size, 0.42 * size, 0.15 * size, 55, LEAF_DARK),
        leaf(0.24 * size, -1.0 + 0.30 * size, 0.42 * size, 0.15 * size, -55, LEAF_DARK),
        leaf(-0.44 * size, -1.0 + 0.18 * size, 0.36 * size, 0.13 * size, 20),
        leaf(0.44 * size, -1.0 + 0.18 * size, 0.36 * size, 0.13 * size, -20),
        leaf(0.0, -1.0 + 0.42 * size, 0.42 * size, 0.15 * size, 90),
    ]


picture("turnip_1", rosette(0.8))
picture("turnip_2", rosette(1.4))
picture("turnip_3", [
    *rosette(1.9),
    *outlined(intersect(circle(0.0, -1.06, 0.40), halfplane(0, -1, -1.0)), CREAM, TURNIP_DARK, 0.05),
    (intersect(circle(0.0, -1.06, 0.35), halfplane(0, -1, -0.86)), TURNIP),
])

picture("rice_1", [
    stalk(-0.30, -1.0, -0.46, -0.30, 0.03),
    stalk(0.0, -1.0, 0.04, -0.14, 0.03),
    stalk(0.32, -1.0, 0.48, -0.36, 0.03),
])

TUFT = [(-0.10, -0.70, 0.30), (-0.10, -0.36, 0.34), (-0.10, -0.06, 0.16), (-0.10, 0.28, 0.06), (-0.10, 0.58, 0.20),
        (0.10, 0.74, -0.16), (0.10, 0.52, -0.34), (0.10, 0.20, -0.30), (0.10, -0.24, -0.10)]
picture("rice_2", [
    *[stalk(x, -1.0, x + tx, ty, 0.03, LEAF_DARK if i % 2 else LEAF) for i, (x, tx, ty) in enumerate(TUFT)],
])

HEADS = [(-0.60, 0.36, -0.36), (-0.24, 0.62, -0.10), (0.10, 0.70, 0.12), (0.44, 0.58, 0.30), (0.70, 0.30, 0.44)]
picture("rice_3", [
    *[stalk(x * 0.4, -1.0, x, y, 0.03) for x, y, _ in HEADS],
    stalk(-0.20, -1.0, -0.76, -0.14, 0.03, LEAF_DARK),
    stalk(0.20, -1.0, 0.78, -0.10, 0.03, LEAF_DARK),
    *[(translate(rotate(ellipse(0, 0, 0.06, 0.20), 20 if x < 0 else -20), x + dx, y - 0.16), rgba(228, 216, 172)) for x, y, dx in HEADS],
])

picture("melon_1", [
    stalk(0.0, -1.0, 0.0, -0.44, 0.04),
    leaf(-0.28, -0.32, 0.26, 0.20, 20),
    leaf(0.28, -0.32, 0.26, 0.20, -20),
])

VINE = [
    stalk(-0.90, -0.94, -0.30, -0.70, 0.04, LEAF_DARK),
    stalk(-0.30, -0.70, 0.20, -0.86, 0.04, LEAF_DARK),
    stalk(0.20, -0.86, 0.80, -0.62, 0.04, LEAF_DARK),
    stalk(-0.30, -0.70, -0.16, -0.20, 0.04, LEAF_DARK),
    leaf(-0.68, -0.60, 0.24, 0.18, 30),
    leaf(-0.02, -0.14, 0.26, 0.20, -10),
    leaf(0.36, -0.60, 0.24, 0.18, 15),
    leaf(0.78, -0.40, 0.22, 0.16, -40),
]
FLOWER = union(*[circle(0.56 + 0.13 * dx, 0.02 + 0.13 * dy, 0.10) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (0.7, 0.7), (-0.7, 0.7), (0.7, -0.7), (-0.7, -0.7))])
picture("melon_2", [
    *VINE,
    stalk(0.36, -0.60, 0.56, 0.0, 0.03, LEAF_DARK),
    (FLOWER, rgba(244, 208, 60)),
    (circle(0.56, 0.02, 0.09), rgba(224, 140, 40)),
])

MELON = circle(0.30, -0.56, 0.42)
picture("melon_3", [
    *VINE,
    *outlined(MELON, RIND, RIND_DARK, 0.06),
    *[(intersect(translate(rotate(capsule(0, -0.50, 0, 0.50, 0.035), a), 0.30, -0.56), shrink(MELON, 0.06)), RIND_DARK)
      for a in (-40, -13, 13, 40)],
    gloss(0.14, -0.36, 0.08, 0.10, shade(RIND, 0.45)),
])

picture("mushroom_1", [
    *toadstool(-0.30, -1.0, 0.16, 0.34, shade(CAP, 0.25), CAP_DARK),
    *toadstool(0.26, -1.0, 0.13, 0.26, shade(CAP, 0.25), CAP_DARK),
])

picture("mushroom_2", [
    *toadstool(-0.44, -1.0, 0.34, 0.80),
    *toadstool(0.40, -1.0, 0.40, 1.00),
    *toadstool(0.02, -1.0, 0.22, 0.46),
])


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
