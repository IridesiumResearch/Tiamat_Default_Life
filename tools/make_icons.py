# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Generates the HUD icons in mods/tiamat_default_life/icons.

Clean, simple drawings, 64 pixels square, drawn on the screen at about 30:
hearts that lose a pie wedge for every third, cookies for hunger with a bite
out of the half one, a light blue ring for a bubble, and a weather shield.
**A file that already exists is kept**, so a hand-drawn picture dropped in
under the same name is never overwritten; `--force` regenerates them all.
`shield_faint.png` is always derived from `shield.png` at half opacity.
After changing any icon, run the hasher so the HUD script knows the file:

    python tools/make_icons.py
    cargo run --offline --manifest-path tests/native/Cargo.toml --bin hashes
"""
from pathlib import Path

from draw import (box, capsule, circle, ellipse, heart, intersect, outlined, png, render,
                  rgba, shade, shrink, subtract, union, wedge_from_top)

OUT = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_life" / "icons"
SIZE = 64

RED = rgba(220, 44, 52)
RED_EMPTY = rgba(60, 22, 26, 200)
OUTLINE = rgba(38, 10, 14)
FLASH = rgba(255, 236, 236)
COOKIE = rgba(214, 160, 92)
COOKIE_OUTLINE = rgba(112, 68, 30)
COOKIE_EMPTY = rgba(64, 44, 28, 200)
CHIP = rgba(92, 52, 26)
BUBBLE = rgba(176, 220, 255, 235)
BUBBLE_FILL = rgba(200, 232, 255, 70)
WHITE = rgba(255, 255, 255, 210)

PICTURES = {}


def picture(name, layers):
    PICTURES[name] = layers


# Hearts ----------------------------------------------------------------------
#
# The heart sits a little high so its point has room. A missing third is a
# pie wedge cut from the top, clockwise: a full heart, then one with its
# right lobe gone, then only the left lobe, then the empty outline.

HEART = heart(0.78)
HEART_AT = (0.0, 0.02)


def heart_layers(remaining, fill=RED):
    layers = outlined(HEART, RED_EMPTY, OUTLINE, 0.085)
    if remaining > 0:
        lit = intersect(shrink(HEART, 0.085), wedge_from_top(remaining, *HEART_AT))
        layers.append((lit, fill))
        # A soft highlight on the left lobe, only while that lobe is lit.
        layers.append((intersect(ellipse(-0.36, 0.30, 0.16, 0.10), wedge_from_top(remaining, *HEART_AT)),
                       shade(fill, 0.45)))
    return layers


picture("heart_full", heart_layers(1.0))
picture("heart_2", heart_layers(2 / 3))
picture("heart_1", heart_layers(1 / 3))
picture("heart_empty", heart_layers(0.0))
picture("heart_flash", heart_layers(1.0, FLASH))

# Cookies -----------------------------------------------------------------------

COOKIE_SHAPE = circle(0.0, 0.0, 0.80)
CHIPS = [(-0.28, 0.26, 0.11), (0.24, 0.30, 0.10), (0.34, -0.18, 0.11), (-0.16, -0.30, 0.10), (-0.42, -0.10, 0.08), (0.02, 0.02, 0.09)]


def cookie_layers(shape, fill, outline, chips):
    layers = outlined(shape, fill, outline, 0.08)
    if chips:
        for cx, cy, r in CHIPS:
            layers.append((intersect(circle(cx, cy, r), shrink(shape, 0.12)), CHIP))
    return layers


BITE = circle(0.62, 0.52, 0.46)
picture("cookie_full", cookie_layers(COOKIE_SHAPE, COOKIE, COOKIE_OUTLINE, True))
picture("cookie_half", cookie_layers(subtract(COOKIE_SHAPE, BITE), COOKIE, COOKIE_OUTLINE, True))
picture("cookie_empty", outlined(COOKIE_SHAPE, COOKIE_EMPTY, rgba(40, 26, 16), 0.08))

# Bubble --------------------------------------------------------------------------

RING = subtract(circle(0, 0, 0.86), circle(0, 0, 0.64))
picture("bubble", [
    (circle(0, 0, 0.64), BUBBLE_FILL),
    (RING, BUBBLE),
    (ellipse(-0.30, 0.36, 0.14, 0.09), WHITE),
])

# Thermometer, in two moods --------------------------------------------------------

TUBE = capsule(0.0, 0.55, 0.0, -0.25, 0.20)
BULB = circle(0.0, -0.52, 0.34)


def thermometer(mercury, glass=rgba(236, 240, 244), colour=RED):
    shape = union(TUBE, BULB)
    layers = outlined(shape, glass, rgba(60, 64, 70), 0.08)
    layers.append((shrink(BULB, 0.16), colour))
    layers.append((capsule(0.0, mercury, 0.0, -0.4, 0.10), colour))
    for y in (0.45, 0.25, 0.05):
        layers.append((box(0.36, y, 0.10, 0.02), rgba(60, 64, 70)))
    return layers


picture("thermo_hot", thermometer(0.45, colour=rgba(255, 120, 40)))
picture("thermo_cold", thermometer(-0.05, colour=rgba(110, 180, 255)))

# The weather shield -----------------------------------------------------------
#
# Whole when what you wear answers the weather, cracked when it does not.
# Placeholders; the real ones are hand-drawn.

SHIELD = intersect(box(0.0, 0.10, 0.62, 0.72, 0.18), union(box(0.0, 0.30, 0.62, 0.52), circle(0.0, -0.10, 0.62)))
SHIELD_FILL = rgba(64, 80, 110)
SHIELD_EDGE = rgba(220, 226, 236)
CRACK = union(
    capsule(-0.10, 0.80, 0.08, 0.30, 0.05), capsule(0.08, 0.30, -0.12, -0.10, 0.05),
    capsule(-0.12, -0.10, 0.10, -0.55, 0.05),
)
picture("shield", [
    *outlined(SHIELD, SHIELD_FILL, SHIELD_EDGE, 0.09),
    (circle(0.0, 0.16, 0.16), rgba(250, 220, 90)),
    (ellipse(0.02, -0.16, 0.30, 0.13), rgba(230, 236, 244)),
])
picture("shield_broken", [
    *outlined(SHIELD, shade(SHIELD_FILL, -0.3), rgba(160, 150, 150), 0.09),
    (intersect(CRACK, SHIELD), rgba(0, 0, 0, 0)),
    (intersect(CRACK, SHIELD), rgba(30, 20, 24)),
])


def faded(name, source, alpha):
    """Writes `name` as `source` with its alpha scaled: the HUD cannot fade
    an image itself, so the faint shield is a file."""
    from pngio import read
    width, height, rows = read(OUT / f"{source}.png")
    out = []
    for row in rows:
        line = bytearray()
        for r, g, b, a in row:
            line += bytes([r, g, b, int(a * alpha)])
        out.append(line)
    if width != height:
        raise SystemExit(f"{source}.png must be square")
    (OUT / f"{name}.png").write_bytes(png(width, out))
    print("wrote", name, f"({source} at {int(alpha * 100)}%)")


def main(force=False):
    OUT.mkdir(parents=True, exist_ok=True)
    for name, layers in PICTURES.items():
        target = OUT / f"{name}.png"
        if target.exists() and not force:
            print("kept ", name)
            continue
        target.write_bytes(png(SIZE, render(layers, SIZE, 3)))
        print("wrote", name)
    # Derived, always: it follows whatever shield.png is now.
    faded("shield_faint", "shield", 0.5)


if __name__ == "__main__":
    import sys
    main(force="--force" in sys.argv)
