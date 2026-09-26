# SPDX-FileCopyrightText: Iridesium
# SPDX-License-Identifier: GPL-3.0-only
"""Turns a rig of rigid parts into one skinned mesh the engine can draw.

Modelling tools often export a blocky creature as separate meshes, each
PARENTED to a bone and carrying no joint weights. That is valid glTF, and the
engine's reader accepts it, but it reads a vertex with no weights as "joint 0,
where it lies", and it ignores node transforms: every part lands on the origin
and follows the body. This rewrites such a file as the engine wants it:

- one mesh, every vertex weighted wholly to the bone its part hung from,
  with positions in rest space and proper inverse bind matrices. A mesh
  that is ALREADY skinned keeps its own weights, and is placed by its bind
  pose, which must be the rig's rest pose (the tool checks);
- the armature above the root bone baked away (its Z-up turn and scale go
  into the root bone and into the root bone's animation keys), since the
  reader builds the skeleton from the joints alone;
- sized in CELLS (three to a block) to a given length, feet on y = 0,
  centred, and facing +Z, which is the way the engine's bodies face;
- a clip played faster or slower if asked (`--speed walk=2`), since the
  engine plays a clip at its own pace and a modeller's walk may be timed for
  a slower body than the one the game moves;
- clips renamed to lower case, which is how the engine matches a clip to an
  animation tag: idle, walk, run, swing, swim, sneak;
- no images, materials or textures: the engine refuses embedded images, and
  a model's texture travels beside it.

Standard library only:

    python tools/skin_glb.py <in.glb> <out.glb> --length 6.0 [--rename Eating=sneak] [--speed walk=2] [--axis z]
"""
import argparse
import json
import math
import struct

# --- small linear algebra: row-major 4x4 lists, quaternions as (x, y, z, w) ---


def identity():
    return [[1.0 if r == c else 0.0 for c in range(4)] for r in range(4)]


def matmul(a, b):
    return [[sum(a[r][k] * b[k][c] for k in range(4)) for c in range(4)] for r in range(4)]


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def quat_rotate(q, v):
    x, y, z, w = q
    vx, vy, vz = v
    # v + 2w(q x v) + 2 q x (q x v)
    cx, cy, cz = y * vz - z * vy, z * vx - x * vz, x * vy - y * vx
    dx, dy, dz = y * cz - z * cy, z * cx - x * cz, x * cy - y * cx
    return (vx + 2 * (w * cx + dx), vy + 2 * (w * cy + dy), vz + 2 * (w * cz + dz))


def quat_norm(q):
    n = math.sqrt(sum(c * c for c in q)) or 1.0
    return tuple(c / n for c in q)


def trs_matrix(t, q, s):
    x, y, z, w = q
    r = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
    m = identity()
    for i in range(3):
        for j in range(3):
            m[i][j] = r[i][j] * s[j]
        m[i][3] = t[i]
    return m


def invert(m):
    n = 4
    a = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(m)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(a[r][col]))
        if abs(a[pivot][col]) < 1e-12:
            raise ValueError("a singular transform in the rig")
        a[col], a[pivot] = a[pivot], a[col]
        p = a[col][col]
        a[col] = [v / p for v in a[col]]
        for r in range(n):
            if r != col and a[r][col] != 0.0:
                f = a[r][col]
                a[r] = [v - f * w for v, w in zip(a[r], a[col])]
    return [row[n:] for row in a]


def apply(m, v):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] + m[i][3] for i in range(3))


def apply_normal(m_inv, v):
    # The inverse transpose, so a squashed part keeps honest normals.
    n = tuple(m_inv[0][i] * v[0] + m_inv[1][i] * v[1] + m_inv[2][i] * v[2] for i in range(3))
    length = math.sqrt(sum(c * c for c in n)) or 1.0
    return tuple(c / length for c in n)


# --- reading a GLB --------------------------------------------------------------

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


class Glb:
    def __init__(self, path):
        data = open(path, "rb").read()
        magic, version, _ = struct.unpack("<4sII", data[:12])
        assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
        at = 12
        self.json, self.bin = None, b""
        while at < len(data):
            length, kind = struct.unpack("<I4s", data[at:at + 8])
            body = data[at + 8:at + 8 + length]
            if kind == b"JSON":
                self.json = json.loads(body)
            elif kind.startswith(b"BIN"):
                self.bin = body
            at += 8 + length

    def read(self, index):
        acc = self.json["accessors"][index]
        view = self.json["bufferViews"][acc["bufferView"]]
        fmt, size = COMPONENT[acc["componentType"]]
        width = WIDTH[acc["type"]]
        stride = view.get("byteStride") or size * width
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        out = []
        for i in range(acc["count"]):
            o = start + i * stride
            values = struct.unpack_from("<" + fmt * width, self.bin, o)
            if acc.get("normalized") and fmt in "BH":
                values = tuple(v / (255.0 if fmt == "B" else 65535.0) for v in values)
            out.append(values if width > 1 else values[0])
        return out


# --- writing one ---------------------------------------------------------------------


class Writer:
    def __init__(self):
        self.bin = bytearray()
        self.views = []
        self.accessors = []

    def add(self, values, kind, component, target=None, minmax=False, normalized=False):
        fmt, size = COMPONENT[component]
        width = WIDTH[kind]
        while len(self.bin) % 4:
            self.bin.append(0)
        offset = len(self.bin)
        flat = []
        for v in values:
            flat.extend(v if width > 1 else (v,))
        self.bin += struct.pack("<" + fmt * len(flat), *flat)
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(self.bin) - offset}
        if target:
            view["target"] = target
        self.views.append(view)
        acc = {"bufferView": len(self.views) - 1, "componentType": component, "count": len(values), "type": kind}
        if normalized:
            acc["normalized"] = True
        if minmax:
            cols = list(zip(*values)) if width > 1 else [values]
            acc["min"] = [min(c) for c in cols]
            acc["max"] = [max(c) for c in cols]
        self.accessors.append(acc)
        return len(self.accessors) - 1


def convert(source, target, length_cells, renames, flip, speeds=None, axis=None):
    speeds = speeds or {}
    g = Glb(source)
    j = g.json
    nodes = j["nodes"]
    skin = j["skins"][0]
    joints = skin["joints"]
    joint_slot = {node: slot for slot, node in enumerate(joints)}

    parent = {}
    for index, node in enumerate(nodes):
        for child in node.get("children", []):
            parent[child] = index

    def local_trs(index):
        n = nodes[index]
        if "matrix" in n:
            raise SystemExit("a node uses a raw matrix; export with TRS transforms")
        return (tuple(n.get("translation", (0, 0, 0))), tuple(n.get("rotation", (0, 0, 0, 1))),
                tuple(n.get("scale", (1, 1, 1))))

    # The root bone, and whatever stands above it (the armature object): a
    # chain of transforms the engine will not read, to be folded into the bone.
    roots = [n for n in joints if parent.get(n) not in joint_slot]
    if len(roots) != 1:
        raise SystemExit(f"expected one root bone, found {len(roots)}")
    root = roots[0]
    above = identity()
    above_q, above_s = (0.0, 0.0, 0.0, 1.0), 1.0
    chain = []
    n = parent.get(root)
    while n is not None:
        chain.append(n)
        n = parent.get(n)
    for n in reversed(chain):
        t, q, s = local_trs(n)
        if max(s) - min(s) > 1e-4:
            raise SystemExit("the armature is scaled unevenly; apply its scale in the modelling tool")
        above = matmul(above, trs_matrix(t, q, s))
        above_q = quat_mul(above_q, q)
        above_s *= s[0]

    def world_with(prefix):
        """World rest matrices for every node, with `prefix` standing above the scene."""
        cache = {}

        def world(index):
            if index not in cache:
                local = trs_matrix(*local_trs(index))
                p = parent.get(index)
                cache[index] = matmul(world(p) if p is not None else prefix, local)
            return cache[index]
        return world

    # The parts: every node with a mesh, and the bone it hangs from.
    parts = []
    for index, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        if "skin" in node:
            # Already skinned: its own weights, slot None.
            parts.append((index, None))
            continue
        bone = index
        while bone is not None and bone not in joint_slot:
            bone = parent.get(bone)
        if bone is None:
            bone = root
        parts.append((index, joint_slot[bone]))

    ibms = []
    if "inverseBindMatrices" in skin:
        for flat in g.read(skin["inverseBindMatrices"]):
            ibms.append([[flat[c * 4 + r] for c in range(4)] for r in range(4)])

    def bind_space(world):
        """Where a skinned mesh's vertices stand at rest: joint world times its
        inverse bind, the same for every joint when the bind pose is the rest
        pose. Anything else would need re-skinning, so it is refused."""
        if not ibms:
            raise SystemExit("a skinned mesh with no inverse bind matrices")
        first = matmul(world(joints[0]), ibms[0])
        scale = max(abs(first[r][c]) for r in range(3) for c in range(4)) or 1.0
        for slot, joint in enumerate(joints):
            m = matmul(world(joint), ibms[slot])
            worst = max(abs(m[r][c] - first[r][c]) for r in range(3) for c in range(4))
            if worst > 1e-3 * scale:
                raise SystemExit(f"joint {nodes[joint].get('name')} is not at its bind pose in the rest pose; "
                                 "apply the pose as rest in the modelling tool")
        return first

    def gather(world):
        positions, normals, uvs, bones, weights, indices = [], [], [], [], [], []
        for index, slot in parts:
            m = bind_space(world) if slot is None else world(index)
            m_inv = invert(m)
            for prim in j["meshes"][nodes[index]["mesh"]]["primitives"]:
                a = prim["attributes"]
                base = len(positions)
                pos = g.read(a["POSITION"])
                nor = g.read(a["NORMAL"]) if "NORMAL" in a else [(0.0, 1.0, 0.0)] * len(pos)
                tex = g.read(a["TEXCOORD_0"]) if "TEXCOORD_0" in a else [(0.0, 0.0)] * len(pos)
                positions += [apply(m, v) for v in pos]
                normals += [apply_normal(m_inv, v) for v in nor]
                uvs += [tuple(t) for t in tex]
                if slot is None:
                    if "JOINTS_0" not in a or "WEIGHTS_0" not in a:
                        raise SystemExit("a skinned mesh with no JOINTS_0 / WEIGHTS_0")
                    js = [tuple(int(x) for x in v) for v in g.read(a["JOINTS_0"])]
                    ws = [tuple(float(x) for x in v) for v in g.read(a["WEIGHTS_0"])]
                    for jv, wv in zip(js, ws):
                        total = sum(wv) or 1.0
                        bones.append(jv)
                        weights.append(tuple(x / total for x in wv))
                else:
                    bones += [(slot, 0, 0, 0)] * len(pos)
                    weights += [(1.0, 0.0, 0.0, 0.0)] * len(pos)
                idx = g.read(prim["indices"]) if "indices" in prim else list(range(len(pos)))
                indices += [base + i for i in idx]
        return positions, normals, uvs, bones, weights, indices

    # First pass, as exported, to measure it: how long, where the feet are,
    # and which end the head is on.
    positions, *_ = gather(world_with(identity()))
    lo = [min(p[a] for p in positions) for a in range(3)]
    hi = [max(p[a] for p in positions) for a in range(3)]
    span = [hi[a] - lo[a] for a in range(3)]
    # The longer of the two flat spans is nose to tail, unless told otherwise:
    # a bird exported with its wings spread is wider than it is long.
    long_axis = 2 if span[2] >= span[0] else 0
    if axis is not None:
        long_axis = "xyz".index(axis)
    heads = [n for n in joints if "head" in nodes[n].get("name", "").lower()]
    rest = world_with(identity())
    facing_back = False
    if heads:
        head_at = apply(rest(heads[0]), (0, 0, 0))
        centre = (lo[long_axis] + hi[long_axis]) / 2
        facing_back = head_at[long_axis] < centre
    turn = 0.0
    if long_axis == 0:
        turn = 90.0 if facing_back else -90.0
    elif facing_back:
        turn = 180.0
    if flip:
        turn += 180.0
    k = length_cells / span[long_axis]

    # The standing transform: turned to face +Z, sized to cells, centred, feet down.
    half = math.radians(turn) / 2
    stand_q = (0.0, math.sin(half), 0.0, math.cos(half))
    cx, cz = (lo[0] + hi[0]) / 2, (lo[2] + hi[2]) / 2
    moved = quat_rotate(stand_q, (-cx, -lo[1], -cz))
    stand_t = tuple(c * k for c in moved)
    stand = trs_matrix(stand_t, stand_q, (k, k, k))

    # Everything above the root bone, as one even-scaled TRS.
    over = matmul(stand, above)
    over_q = quat_norm(quat_mul(stand_q, above_q))
    over_s = k * above_s
    over_t = (over[0][3], over[1][3], over[2][3])

    def lift(t, q, s):
        """A root-bone local transform, with everything above it folded in."""
        rotated = quat_rotate(over_q, tuple(c * over_s for c in t))
        return (tuple(over_t[a] + rotated[a] for a in range(3)),
                quat_norm(quat_mul(over_q, q)), tuple(c * over_s for c in s))

    positions, normals, uvs, bones, weights, indices = gather(world_with(stand))

    # The new skeleton: the bones alone, the root carrying what stood above it.
    new_index = {old: new for new, old in enumerate(joints)}
    out_nodes = []
    for old in joints:
        t, q, s = local_trs(old)
        if old == root:
            t, q, s = lift(t, q, s)
        node = {"name": nodes[old].get("name", f"bone{new_index[old]}"),
                "translation": list(t), "rotation": list(q), "scale": list(s)}
        kids = [new_index[c] for c in nodes[old].get("children", []) if c in new_index]
        if kids:
            node["children"] = kids
        out_nodes.append(node)

    def new_world(index, cache={}):
        if index not in cache:
            n = out_nodes[index]
            local = trs_matrix(n["translation"], n["rotation"], n["scale"])
            up = next((p for p, c in enumerate(out_nodes) if index in c.get("children", [])), None)
            cache[index] = matmul(new_world(up), local) if up is not None else local
        return cache[index]

    w = Writer()
    a_pos = w.add(positions, "VEC3", 5126, 34962, minmax=True)
    a_nor = w.add(normals, "VEC3", 5126, 34962)
    a_uv = w.add(uvs, "VEC2", 5126, 34962)
    a_joint = w.add(bones, "VEC4", 5121, 34962)
    # Weights as bytes, 255 to one, which the engine reads as normalised: a
    # quarter of the size of floats, and a big mesh is under the engine's
    # model limit only so. Rounded so each vertex's four still sum to 255.
    def to_bytes(wv):
        out = [round(x * 255) for x in wv]
        out[out.index(max(out))] += 255 - sum(out)
        return tuple(out)
    a_weight = w.add([to_bytes(wv) for wv in weights], "VEC4", 5121, 34962, normalized=True)
    wide = len(positions) > 65535
    a_index = w.add(indices, "SCALAR", 5125 if wide else 5123, 34963)
    # Column-major, as glTF stores a matrix.
    binds = []
    for slot in range(len(joints)):
        inv = invert(new_world(slot))
        binds.append(tuple(inv[r][c] for c in range(4) for r in range(4)))
    a_bind = w.add(binds, "MAT4", 5126)

    animations = []
    still, thinned = [0], [0]
    for anim in j.get("animations", []):
        name = anim.get("name", "")
        name = renames.get(name, name).lower()
        samplers, channels = [], []
        for channel in anim["channels"]:
            node = channel["target"].get("node")
            path = channel["target"]["path"]
            if node not in new_index or path not in ("translation", "rotation", "scale"):
                continue
            sampler = anim["samplers"][channel["sampler"]]
            if sampler.get("interpolation", "LINEAR") == "CUBICSPLINE":
                raise SystemExit(f"clip {name}: cubic keys; bake to linear when exporting")
            times = g.read(sampler["input"])
            factor = speeds.get(name, 1.0)
            if factor != 1.0:
                times = [tuple(t / factor for t in v) if isinstance(v, (tuple, list)) else v / factor for v in times]
            keys = [tuple(v) for v in g.read(sampler["output"])]
            if node == root:
                # The root's keys are in the armature's space; bring them along.
                rt, rq, rs = local_trs(root)
                if path == "translation":
                    keys = [lift(v, rq, rs)[0] for v in keys]
                elif path == "rotation":
                    keys = [lift(rt, v, rs)[1] for v in keys]
                else:
                    keys = [lift(rt, rq, v)[2] for v in keys]
            # A channel that holds its bone at rest for the whole clip is
            # dropped: the engine starts every bone at rest and a clip only
            # overrides what it drives, so it changes nothing, and a big rig
            # that keys every bone in every clip is over the engine's channel
            # limit otherwise (the ghost). A rotation and its negation are one.
            rest = out_nodes[new_index[node]][path]
            def at_rest(v):
                same = max(abs(a - b) for a, b in zip(v, rest))
                if path == "rotation":
                    same = min(same, max(abs(a + b) for a, b in zip(v, rest)))
                return same < 1e-4
            if all(at_rest(v) for v in keys):
                still[0] += 1
                continue
            # Keys the straight line between their neighbours already gives,
            # to within a hair, are dropped: exporters sample every frame, and
            # a big rig's clips are most of its file otherwise (the cave troll).
            if sampler.get("interpolation", "LINEAR") == "LINEAR" and len(keys) > 2:
                if path == "rotation":
                    # One hemisphere, so a key and its neighbours interpolate the short way.
                    for i in range(1, len(keys)):
                        if sum(a * b for a, b in zip(keys[i], keys[i - 1])) < 0:
                            keys[i] = tuple(-c for c in keys[i])
                kept = [0]
                for i in range(1, len(keys) - 1):
                    a, b = kept[-1], i + 1
                    gap = times[b] - times[a]
                    f = (times[i] - times[a]) / gap if gap else 0.0
                    guess = [x + (y - x) * f for x, y in zip(keys[a], keys[b])]
                    if max(abs(g - k) for g, k in zip(guess, keys[i])) > 1e-4:
                        kept.append(i)
                kept.append(len(keys) - 1)
                thinned[0] += len(keys) - len(kept)
                times = [times[i] for i in kept]
                keys = [keys[i] for i in kept]
            a_in = w.add(times, "SCALAR", 5126, minmax=True)
            a_out = w.add(keys, "VEC4" if path == "rotation" else "VEC3", 5126)
            samplers.append({"input": a_in, "output": a_out, "interpolation": sampler.get("interpolation", "LINEAR")})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": new_index[node], "path": path}})
        animations.append({"name": name, "samplers": samplers, "channels": channels})

    mesh_node = {"name": "body", "mesh": 0, "skin": 0}
    out_nodes.append(mesh_node)
    out = {
        "asset": {"version": "2.0", "generator": "tiamat_default_life tools/skin_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [new_index[root], len(out_nodes) - 1]}],
        "nodes": out_nodes,
        "meshes": [{"name": "body", "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nor, "TEXCOORD_0": a_uv,
                           "JOINTS_0": a_joint, "WEIGHTS_0": a_weight},
            "indices": a_index, "mode": 4}]}],
        "skins": [{"joints": list(range(len(joints))), "inverseBindMatrices": a_bind,
                   "skeleton": new_index[root]}],
        "animations": animations,
        "accessors": w.accessors,
        "bufferViews": w.views,
        "buffers": [{"byteLength": len(w.bin)}],
    }
    text = json.dumps(out, separators=(",", ":")).encode()
    text += b" " * (-len(text) % 4)
    blob = bytes(w.bin) + b"\x00" * (-len(w.bin) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(target, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(text), b"JSON") + text)
        f.write(struct.pack("<I4s", len(blob), b"BIN\x00") + blob)

    lo2 = [min(p[a] for p in positions) for a in range(3)]
    hi2 = [max(p[a] for p in positions) for a in range(3)]
    print(f"parts {len(parts)} ({sum(1 for _, slot in parts if slot is None)} already skinned) -> one mesh: {len(positions)} vertices, {len(indices) // 3} triangles, {len(joints)} bones")
    print(f"as exported: {span[0]:.2f} x {span[1]:.2f} x {span[2]:.2f}; long axis {'xyz'[long_axis]}, "
          f"head toward {'-' if facing_back else '+'}; turned {turn:.0f} degrees, scaled x{k:.2f}")
    print("in cells: " + " x ".join(f"{hi2[a] - lo2[a]:.2f}" for a in range(3))
          + f"  (blocks: {(hi2[0]-lo2[0])/3:.2f} wide, {(hi2[1]-lo2[1])/3:.2f} tall, {(hi2[2]-lo2[2])/3:.2f} long); feet at y = {lo2[1]:.3f}")
    print("clips: " + ", ".join(f"{a['name']} ({len(a['channels'])} channels"
                                + (f", x{speeds[a['name']]:g} speed" if a['name'] in speeds else "") + ")" for a in animations)
          + (f"; {still[0]} channels holding a bone at rest dropped" if still[0] else "")
          + (f"; {thinned[0]} keys on a straight line dropped" if thinned[0] else ""))
    print(f"wrote {target} ({total} bytes)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("target")
    ap.add_argument("--length", type=float, default=6.0, help="nose to tail, in cells (three to a block)")
    ap.add_argument("--rename", action="append", default=[], metavar="Old=new", help="rename a clip")
    ap.add_argument("--flip", action="store_true", help="turn it round, if the head was guessed wrong")
    ap.add_argument("--axis", choices=("x", "z"), help="nose to tail along this axis, if the wider span is not it")
    ap.add_argument("--speed", action="append", default=[], metavar="clip=factor",
                    help="play a clip (by its final name) this many times faster")
    args = ap.parse_args()
    convert(args.source, args.target, args.length,
            dict(pair.split("=", 1) for pair in args.rename), args.flip,
            {k.lower(): float(v) for k, v in (pair.split("=", 1) for pair in args.speed)}, args.axis)
