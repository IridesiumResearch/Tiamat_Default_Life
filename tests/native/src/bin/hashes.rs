// SPDX-License-Identifier: GPL-3.0-only
//
// Writes the content hashes of the HUD icons into hud.lua.
//
// `hud.image` draws a picture by its content hash — BLAKE3 over the file's
// bytes with the engine's domain prefix — and a HUD script cannot compute
// one, so the hashes have to be written into the script. This does that: it
// hashes every PNG in `icons/` with the engine's own function and replaces
// the block between the two ICONS markers in hud.lua. Run it after changing
// or replacing any icon:
//
//     cargo run --offline --manifest-path tests/native/Cargo.toml --bin hashes

use std::path::PathBuf;

fn main() {
    let mod_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods/tiamot_default_life");
    let icons = mod_dir.join("icons");
    let hud = mod_dir.join("hud.lua");

    let mut names: Vec<String> = std::fs::read_dir(&icons)
        .expect("icons directory")
        .filter_map(|entry| {
            let path = entry.ok()?.path();
            (path.extension()?.to_str()? == "png").then(|| path.file_stem()?.to_str().map(str::to_owned))?
        })
        .collect();
    names.sort();

    let mut block = String::from("local ICONS = {\n");
    for name in &names {
        let bytes = std::fs::read(icons.join(format!("{name}.png"))).expect("icon bytes");
        let hash = tiamot_core::content::hash_bytes(&bytes);
        let hex: String = hash.iter().map(|b| format!("{b:02x}")).collect();
        block.push_str(&format!("    {name} = \"{hex}\",\n"));
        println!("{name}  {hex}");
    }
    block.push_str("}\n");

    let source = std::fs::read_to_string(&hud).expect("hud.lua");
    let begin = "-- ICONS BEGIN";
    let end = "-- ICONS END";
    let start = source.find(begin).expect("the ICONS BEGIN marker in hud.lua");
    let start = start + source[start..].find('\n').unwrap() + 1;
    let stop = source.find(end).expect("the ICONS END marker in hud.lua");
    let rewritten = format!("{}{}{}", &source[..start], block, &source[stop..]);
    if rewritten != source {
        std::fs::write(&hud, rewritten).expect("write hud.lua");
        println!("hud.lua updated with {} icon hashes", names.len());
    } else {
        println!("hud.lua already current ({} icons)", names.len());
    }
}
