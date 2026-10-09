# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Makes the white stag's skin from the stag's. Standard library only.

    python tools/make_white_stag.py

Reads `models/stag.png` and writes `models/white_stag.png`: every colour
taken to its brightness and lifted most of the way to white, with a faint
cool cast, so the coat's shading survives as soft grey and the darkest
parts (eyes, nose, hooves) stay dark enough to read. Run it again whenever
the stag's skin changes; the white stag wears the stag's own model.
"""
from pathlib import Path

from draw import png
from pngio import read

MODELS = Path(__file__).resolve().parent.parent / "mods" / "tiamat_default_life" / "models"

LIFT = 0.12        # how much of the distance to white is left: lower is whiter
DARK = 48          # below this brightness a pixel is a feature, and kept dark


def whiten(r, g, b, a):
    lum = (r * 299 + g * 587 + b * 114) // 1000
    if lum < DARK:
        grey = 40 + lum // 2
        return grey, grey, grey + 4, a
    v = 255 - int((255 - lum) * LIFT)
    return max(v - 4, 0), max(v - 1, 0), min(v + 3, 255), a


def main():
    width, height, rows = read(MODELS / "stag.png")
    assert width == height, "the skin is square"
    out = [[c for px in row for c in whiten(*px)] for row in rows]
    (MODELS / "white_stag.png").write_bytes(png(width, out))
    print("wrote white_stag.png")


if __name__ == "__main__":
    main()
