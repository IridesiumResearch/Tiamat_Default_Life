# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Rasterises a HUD frame dumped by the native harness into a PNG.

The harness (run with LIFE_HUD_DUMP=<dir>) writes one file per HUD state:
`rect px py w h r g b a` and `text px py size r g b a words...`, already
resolved onto a 1920x1080 virtual canvas by the engine's own anchor rule.
This paints the rectangles exactly and the text as a crude block-letter
placeholder of the right height, over a dark, faintly lit ground, so the
layout can be looked at without launching the game. Standard library only.

    python tools/render_hud.py <dump-dir> <out-dir>
"""
import struct
import sys
import zlib
from pathlib import Path

from pngio import read

W, H = 1920, 1080


def png(width, height, pixels):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = bytearray()
    for y in range(height):
        raw.append(0)
        raw += pixels[y]
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
            + chunk(b"IEND", b""))


def blend(pixels, x, y, r, g, b, a):
    if x < 0 or y < 0 or x >= W or y >= H:
        return
    row = pixels[y]
    i = x * 3
    k = a / 255.0
    row[i] = int(row[i] * (1 - k) + r * k)
    row[i + 1] = int(row[i + 1] * (1 - k) + g * k)
    row[i + 2] = int(row[i + 2] * (1 - k) + b * k)


def rect(pixels, x, y, w, h, r, g, b, a):
    x0, y0 = int(round(x)), int(round(y))
    for yy in range(max(0, y0), min(H, y0 + int(h))):
        for xx in range(max(0, x0), min(W, x0 + int(w))):
            blend(pixels, xx, yy, r, g, b, a)


def text(pixels, x, y, size, r, g, b, a, words):
    # Each character is a box a little narrower than it is tall; a space is a gap.
    cw = max(2, int(size * 0.48))
    x0 = int(round(x))
    y0 = int(round(y))
    for i, ch in enumerate(words):
        if ch != " ":
            rect(pixels, x0 + i * cw, y0 + int(size * 0.2), cw - 2, int(size * 0.6), r, g, b, a)


LOADED = {}


def image(pixels, x, y, w, h, path):
    if not path:
        return
    if path not in LOADED:
        LOADED[path] = read(path)
    iw, ih, rows = LOADED[path]
    x0, y0 = int(round(x)), int(round(y))
    for yy in range(h):
        sy = min(ih - 1, yy * ih // h)
        for xx in range(w):
            sx = min(iw - 1, xx * iw // w)
            r, g, b, a = rows[sy][sx]
            if a:
                blend(pixels, x0 + xx, y0 + yy, r, g, b, a)


def ground(pixels):
    # A dim sky-to-ground gradient, so light and dark elements both read.
    for y in range(H):
        t = y / H
        r, g, b = int(70 + 40 * t), int(110 - 30 * t), int(150 - 90 * t)
        pixels[y][:] = bytes([r, g, b]) * W


def main(dump, out):
    out.mkdir(parents=True, exist_ok=True)
    for file in sorted(Path(dump).glob("*.txt")):
        pixels = [bytearray(W * 3) for _ in range(H)]
        ground(pixels)
        for line in file.read_text().splitlines():
            parts = line.split(" ", 8)
            if parts[0] == "rect":
                _, px, py, w, h, r, g, b, a = parts
                rect(pixels, float(px), float(py), float(w), float(h), int(r), int(g), int(b), int(a))
            elif parts[0] == "image":
                _, px, py, w, h, path = line.split(" ", 5)
                image(pixels, float(px), float(py), int(w), int(h), path)
            elif parts[0] == "text":
                _, px, py, size, r, g, b, a, words = parts
                text(pixels, float(px), float(py), int(size), int(r), int(g), int(b), int(a), words)
        (out / (file.stem + ".png")).write_bytes(png(W, H, pixels))
        print("wrote", file.stem)


if __name__ == "__main__":
    main(sys.argv[1], Path(sys.argv[2]))
