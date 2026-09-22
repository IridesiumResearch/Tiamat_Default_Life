// SPDX-License-Identifier: GPL-3.0-only
//
// Runs a `.glb` through the engine's own model reader and says what it made
// of it: accepted or refused and why, and for an accepted one the mesh, the
// skeleton, the clips and the box it stands in (in cells, three to a block).
//
//     cargo run --offline --manifest-path tests/native/Cargo.toml --bin model_check -- <file.glb> [...]
//
// With MODEL_POSE_DUMP=<dir> it also poses the model with the engine's own
// skinning, at rest and at the start and the half of every clip, and writes each pose as
// text (`v x y z u v` lines, then `f a b c` lines) for tools/render_model.py
// to draw. What the engine would draw, without a window.

use tiamat_core::model::{self, Limits};

fn main() {
    let files: Vec<String> = std::env::args().skip(1).collect();
    if files.is_empty() {
        eprintln!("usage: model_check <file.glb> [...]");
        std::process::exit(2);
    }
    let mut refused = 0;
    for file in files {
        let bytes = std::fs::read(&file).expect("the file");
        println!("{file}  ({} bytes)", bytes.len());
        match model::load_isolated(&bytes, &Limits::default()) {
            Ok(m) => {
                let mut lo = [f32::MAX; 3];
                let mut hi = [f32::MIN; 3];
                for v in &m.vertices {
                    for a in 0..3 {
                        lo[a] = lo[a].min(v.position[a]);
                        hi[a] = hi[a].max(v.position[a]);
                    }
                }
                println!("  ACCEPTED: {} vertices, {} indices", m.vertices.len(), m.indices.len());
                println!("  box (cells): min {lo:.2?} max {hi:.2?}  size {:.2?}",
                    [hi[0] - lo[0], hi[1] - lo[1], hi[2] - lo[2]]);
                println!("  joints: {}", m.skin.joints.len());
                for (i, j) in m.skin.joints.iter().enumerate() {
                    println!("    {i}: {:?} parent {:?}", j.name, j.parent);
                }
                println!("  clips: {}", m.clips.len());
                for c in &m.clips {
                    println!("    {:?}: {} channels, {:.2} s", c.name, c.channels.len(), c.duration);
                }
                if let Ok(dir) = std::env::var("MODEL_POSE_DUMP") {
                    std::fs::create_dir_all(&dir).unwrap();
                    let stem = std::path::Path::new(&file).file_stem().unwrap().to_string_lossy().to_string();
                    let mut poses: Vec<(String, Option<&model::Clip>, f32)> = vec![("rest".into(), None, 0.0)];
                    for c in &m.clips {
                        for (label, at) in [("a", 0.0), ("b", 0.5)] {
                            poses.push((format!("{}_{label}", c.name), Some(c), c.duration * at));
                        }
                    }
                    for (name, clip, time) in poses {
                        let palette = model::skinning_matrices(&m, clip, time);
                        let mut out = String::new();
                        for v in &m.vertices {
                            let mut p = [0.0f32; 3];
                            for (joint, weight) in v.joints.iter().zip(v.weights) {
                                if weight == 0.0 {
                                    continue;
                                }
                                let k = &palette[usize::from(*joint)];
                                let [x, y, z] = v.position;
                                // Column-major: column c is k[4c..4c+4].
                                for a in 0..3 {
                                    p[a] += weight * (k[a] * x + k[4 + a] * y + k[8 + a] * z + k[12 + a]);
                                }
                            }
                            out.push_str(&format!("v {} {} {} {} {}
", p[0], p[1], p[2], v.uv[0], v.uv[1]));
                        }
                        for t in m.indices.chunks(3) {
                            out.push_str(&format!("f {} {} {}
", t[0], t[1], t[2]));
                        }
                        std::fs::write(format!("{dir}/{stem}.{name}.txt"), out).unwrap();
                    }
                    println!("  poses written to {dir}");
                }
            }
            Err(err) => {
                refused += 1;
                println!("  REFUSED: {err}");
            }
        }
    }
    std::process::exit(if refused > 0 { 1 } else { 0 });
}
