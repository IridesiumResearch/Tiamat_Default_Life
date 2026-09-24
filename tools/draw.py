# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""A tiny renderer for clean, simple drawings: flat colours, soft edges.

Shapes are signed-distance functions over a square canvas whose coordinates
run from -1 to 1 (y up). A picture is a list of layers, painted in order;
each layer is a shape and a colour, and a sample takes the colour wherever
the shape's distance is negative. Edges are anti-aliased by supersampling.
Standard library only.
"""
import math
import struct
import zlib

# --- Shapes: each returns a function (x, y) -> signed distance -------------


def circle(cx, cy, r):
    return lambda x, y: math.hypot(x - cx, y - cy) - r


def ellipse(cx, cy, rx, ry):
    k = min(rx, ry)
    return lambda x, y: (math.hypot((x - cx) / rx, (y - cy) / ry) - 1.0) * k


def box(cx, cy, hw, hh, round=0.0):
    def d(x, y):
        dx = abs(x - cx) - hw + round
        dy = abs(y - cy) - hh + round
        return math.hypot(max(dx, 0.0), max(dy, 0.0)) + min(max(dx, dy), 0.0) - round
    return d


def capsule(ax, ay, bx, by, r):
    def d(x, y):
        px, py = x - ax, y - ay
        bxa, bya = bx - ax, by - ay
        h = max(0.0, min(1.0, (px * bxa + py * bya) / (bxa * bxa + bya * bya)))
        return math.hypot(px - bxa * h, py - bya * h) - r
    return d


def halfplane(nx, ny, c):
    """Inside where nx*x + ny*y + c < 0. (nx, ny) need not be unit."""
    n = math.hypot(nx, ny)
    return lambda x, y: (nx * x + ny * y + c) / n


def union(*shapes):
    return lambda x, y: min(s(x, y) for s in shapes)


def intersect(*shapes):
    return lambda x, y: max(s(x, y) for s in shapes)


def subtract(shape, cut):
    return lambda x, y: max(shape(x, y), -cut(x, y))


def shrink(shape, by):
    """The shape with its edge moved inward by `by` (or outward if negative)."""
    return lambda x, y: shape(x, y) + by


def translate(shape, dx, dy):
    return lambda x, y: shape(x - dx, y - dy)


def scale(shape, s):
    return lambda x, y: shape(x / s, y / s) * s


def rotate(shape, degrees):
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    return lambda x, y: shape(c * x + s * y, -s * x + c * y)


def heart(size=1.0):
    """A heart about the origin, about `size` tall. Two lobes and the point."""
    r = 0.5
    cy = 0.32
    b = 0.86
    lobes = union(circle(-0.5, cy, r), circle(0.5, cy, r))
    point = intersect(
        halfplane(-1, -1, -b),   # y > -x - b
        halfplane(1, -1, -b),    # y > x - b
        halfplane(0, 1, -cy),    # y < cy
    )
    return scale(union(lobes, point), size)


def wedge_from_top(fraction, cx=0.0, cy=0.0):
    """The region swept clockwise from straight up through `fraction` of a turn."""
    def d(x, y):
        if fraction >= 1.0:
            return -1.0
        if fraction <= 0.0:
            return 1.0
        a = math.atan2(x - cx, y - cy)      # 0 at the top, clockwise positive
        if a < 0:
            a += 2 * math.pi
        return a / (2 * math.pi) - fraction
    return d


def everything():
    return lambda x, y: -1.0


# --- Colours -----------------------------------------------------------------


def rgba(r, g, b, a=255):
    return (r / 255.0, g / 255.0, b / 255.0, a / 255.0)


def shade(colour, by):
    """Lighter (by > 0) or darker (by < 0)."""
    r, g, b, a = colour
    if by >= 0:
        return (r + (1 - r) * by, g + (1 - g) * by, b + (1 - b) * by, a)
    f = 1 + by
    return (r * f, g * f, b * f, a)


def over(under, top):
    ur, ug, ub, ua = under
    tr, tg, tb, ta = top
    a = ta + ua * (1 - ta)
    if a <= 0:
        return (0.0, 0.0, 0.0, 0.0)
    r = (tr * ta + ur * ua * (1 - ta)) / a
    g = (tg * ta + ug * ua * (1 - ta)) / a
    b = (tb * ta + ub * ua * (1 - ta)) / a
    return (r, g, b, a)


# --- Rendering -----------------------------------------------------------------


def render(layers, size=64, supersample=3, background=None):
    """Paints `layers` — a list of (shape, colour) — into RGBA rows."""
    rows = []
    ss = supersample
    step = 2.0 / (size * ss)
    for py in range(size):
        row = bytearray()
        for px in range(size):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(ss):
                y = 1.0 - (py * ss + sy + 0.5) * step
                for sx in range(ss):
                    x = -1.0 + (px * ss + sx + 0.5) * step
                    colour = background or (0.0, 0.0, 0.0, 0.0)
                    for shape, paint in layers:
                        if shape(x, y) < 0:
                            colour = over(colour, paint)
                    # Accumulate premultiplied, so transparent samples do not
                    # drag colour toward black.
                    acc[0] += colour[0] * colour[3]
                    acc[1] += colour[1] * colour[3]
                    acc[2] += colour[2] * colour[3]
                    acc[3] += colour[3]
            n = ss * ss
            a = acc[3] / n
            if a > 0:
                r, g, b = acc[0] / acc[3], acc[1] / acc[3], acc[2] / acc[3]
            else:
                r, g, b = 0.0, 0.0, 0.0
            row += bytes([int(r * 255 + 0.5), int(g * 255 + 0.5), int(b * 255 + 0.5), int(a * 255 + 0.5)])
        rows.append(row)
    return rows


def png(size, rows):
    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))


def outlined(shape, fill, outline, thickness=0.09):
    """Two layers: the shape in `outline`, then shrunk by `thickness` in `fill`."""
    return [(shape, outline), (shrink(shape, thickness), fill)]
