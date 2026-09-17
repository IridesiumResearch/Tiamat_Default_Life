# SPDX-License-Identifier: GPL-3.0-only
"""Reads an 8-bit RGBA or RGB PNG into rows of (r, g, b, a). Standard library only.

Enough of the format for the pictures this repository makes and the ones a
person is likely to hand it: one image, no interlacing, all five filters.
"""
import struct
import zlib


def read(path):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    pos = 8
    idat = b""
    width = height = channels = None
    while pos < len(data):
        length, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            width, height, depth, colour, _, _, interlace = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and interlace == 0, f"{path}: only 8-bit, non-interlaced PNGs"
            channels = {2: 3, 6: 4}[colour]
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
    raw = zlib.decompress(idat)
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    at = 0
    for _ in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = previous[i]
            c = previous[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 255
            elif filt == 2:
                line[i] = (line[i] + b) & 255
            elif filt == 3:
                line[i] = (line[i] + (a + b) // 2) & 255
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 255
        pixels = []
        for x in range(width):
            i = x * channels
            if channels == 4:
                pixels.append((line[i], line[i + 1], line[i + 2], line[i + 3]))
            else:
                pixels.append((line[i], line[i + 1], line[i + 2], 255))
        rows.append(pixels)
        previous = line
    return width, height, rows
