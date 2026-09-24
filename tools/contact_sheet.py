# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Lays every PNG in a directory out on one sheet, scaled up, for a look.

    python tools/contact_sheet.py <dir> <out.png> [scale]
"""
import sys
from pathlib import Path

from draw import png
from pngio import read


def main(folder, out, scale=3):
    files = sorted(Path(folder).glob("*.png"))
    cell = 64 * scale + 12
    columns = 6
    rows_n = (len(files) + columns - 1) // columns
    W, H = columns * cell, rows_n * cell
    canvas = [[(70 + (x // 16 + y // 16) % 2 * 12,) * 3 for x in range(W)] for y in range(H)]
    for index, file in enumerate(files):
        w, h, pixels = read(file)
        ox = (index % columns) * cell + 6
        oy = (index // columns) * cell + 6
        for y in range(64 * scale):
            for x in range(64 * scale):
                sx = min(w - 1, x * w // (64 * scale))
                sy = min(h - 1, y * h // (64 * scale))
                r, g, b, a = pixels[sy][sx]
                if a:
                    k = a / 255.0
                    ur, ug, ub = canvas[oy + y][ox + x]
                    canvas[oy + y][ox + x] = (int(ur * (1 - k) + r * k), int(ug * (1 - k) + g * k), int(ub * (1 - k) + b * k))
    rows = []
    for y in range(H):
        row = bytearray()
        for x in range(W):
            r, g, b = canvas[y][x]
            row += bytes([r, g, b, 255])
        rows.append(row)
    # `png` expects a square; write a rectangle by the same recipe.
    import struct, zlib
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    Path(out).write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
                          + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    print("wrote", out, f"({len(files)} pictures)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 3)
