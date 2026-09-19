# SPDX-License-Identifier: GPL-3.0-only
"""Draws the poses `model_check` dumps, textured, without launching the game.

`model_check` (with MODEL_POSE_DUMP set) poses a model with the engine's own
skinning and writes each pose as text. This rasterises every pose from the
side and from the front, with the model's texture, a depth buffer and a
little shading, and lays them out on one sheet: what the engine would draw,
as far as shape, assembly, UVs and animation go. Needs Pillow.

    python tools/render_model.py <pose-dir> <texture> <out.png>
"""
import sys
from pathlib import Path

from PIL import Image

CELL = 210          # one tile of the sheet
SCALE = 26          # pixels per cell of model space


def load(path):
    verts, faces = [], []
    for line in Path(path).read_text().splitlines():
        parts = line.split()
        if parts[0] == "v":
            verts.append(tuple(float(p) for p in parts[1:]))
        elif parts[0] == "f":
            faces.append(tuple(int(p) for p in parts[1:]))
    return verts, faces


def draw(tile, verts, faces, texture, view):
    """view "side": looking along -X, +Z to the right. "front": looking along -Z."""
    tw, th = texture.size
    tex = texture.load()
    px = tile.load()
    depth = [[-1e9] * CELL for _ in range(CELL)]
    ox, oy = CELL / 2, CELL - 24

    def project(v):
        x, y, z = v[0], v[1], v[2]
        if view == "side":
            return ox + z * SCALE, oy - y * SCALE, x
        return ox + x * SCALE, oy - y * SCALE, z

    for a, b, c in faces:
        pa, pb, pc = project(verts[a]), project(verts[b]), project(verts[c])
        area = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0])
        if abs(area) < 1e-9:
            continue
        # A touch of light from the face's tilt, so planes read apart.
        va, vb, vc = verts[a], verts[b], verts[c]
        ux, uy, uz = vb[0] - va[0], vb[1] - va[1], vb[2] - va[2]
        wx, wy, wz = vc[0] - va[0], vc[1] - va[1], vc[2] - va[2]
        nx, ny, nz = uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx
        length = (nx * nx + ny * ny + nz * nz) ** 0.5 or 1.0
        light = 0.72 + 0.28 * max(0.0, (0.3 * nx + 0.8 * ny + 0.5 * nz) / length)
        x0 = max(0, int(min(pa[0], pb[0], pc[0])))
        x1 = min(CELL - 1, int(max(pa[0], pb[0], pc[0])) + 1)
        y0 = max(0, int(min(pa[1], pb[1], pc[1])))
        y1 = min(CELL - 1, int(max(pa[1], pb[1], pc[1])) + 1)
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                sx, sy = x + 0.5, y + 0.5
                w0 = ((pb[0] - sx) * (pc[1] - sy) - (pb[1] - sy) * (pc[0] - sx)) / area
                w1 = ((pc[0] - sx) * (pa[1] - sy) - (pc[1] - sy) * (pa[0] - sx)) / area
                w2 = 1 - w0 - w1
                if w0 < 0 or w1 < 0 or w2 < 0:
                    continue
                d = w0 * pa[2] + w1 * pb[2] + w2 * pc[2]
                if d <= depth[y][x]:
                    continue
                depth[y][x] = d
                u = w0 * va[3] + w1 * vb[3] + w2 * vc[3]
                v = w0 * va[4] + w1 * vb[4] + w2 * vc[4]
                r, g, b_ = tex[int(u % 1.0 * tw) % tw, int(v % 1.0 * th) % th][:3]
                px[x, y] = (int(r * light), int(g * light), int(b_ * light))
    # The ground line.
    for x in range(CELL):
        if depth[int(oy)][x] == -1e9:
            px[x, int(oy)] = (70, 90, 60)


def main(pose_dir, texture_path, out):
    texture = Image.open(texture_path).convert("RGB")
    poses = sorted(Path(pose_dir).glob("*.txt"), key=lambda p: (".rest" not in p.name, p.name))
    sheet = Image.new("RGB", (CELL * len(poses), CELL * 2), (112, 140, 168))
    for column, pose in enumerate(poses):
        verts, faces = load(pose)
        for row, view in enumerate(("side", "front")):
            tile = Image.new("RGB", (CELL, CELL), (112, 140, 168))
            draw(tile, verts, faces, texture, view)
            sheet.paste(tile, (column * CELL, row * CELL))
        print("drew", pose.stem)
    sheet.save(out)
    print("wrote", out, "—", ", ".join(p.stem.split(".", 1)[1] for p in poses))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
