// SPDX-License-Identifier: GPL-3.0-only
//
// The mod, run for real: the engine's script VM with a fake server around it.
//
// Nothing here is mocked at the Lua level. The mod's own files load through
// `EngineVm::load_mod`, its hooks fire through the same trait the server
// calls, and the HUD script is drawn by the same `HudVm` a client runs. What
// is faked is the world: one player body whose position, ground contact and
// velocity the test sets; an inventory; a map of blocks and fluid; storage;
// the operator list, each player's chat, what they may do and what they aim at.

use std::{
    collections::{BTreeMap, HashMap},
    path::PathBuf,
    sync::{Arc, Mutex},
};

use tiamot_core::{
    BlockPos, MaterialId,
    ent::{self, Entity, EntityId, Owner, Transform},
    fluid::{self, Fluid, FluidId},
    hud::{self, State, Value, Values},
    identity::PlayerUuid,
    inventory::{self, Shape, Stack},
    light::{Light, LightSource},
    particle::{self, EmitRequest},
    script::{
        ActionEvent, ChatEvent, DialogEvent, EngineVm, HudLimits, HudVm, JoinEvent, LeaveEvent,
        ScriptVm, VmLimits, WorldEdit,
    },
    phys::Abilities,
    sight::{self, Looked, Reading, Sighting},
    sound::{self, LoopRequest, PlayRequest},
    storage::{self, Access as StorageAccess},
    ui::host::{self as uihost, ShowRequest},
};

const MOD: &str = "tiamot_default_life";
const PLAYER: [u8; 32] = [7; 32];

// --- Fakes -------------------------------------------------------------------

#[derive(Default)]
struct Storage(Mutex<BTreeMap<(String, String), storage::Value>>);

impl storage::Access for Storage {
    fn get(&self, mod_id: &str, key: &str) -> Option<storage::Value> {
        self.0.lock().unwrap().get(&(mod_id.into(), key.into())).cloned()
    }
    fn set(&self, mod_id: &str, key: &str, value: Option<storage::Value>) {
        let mut map = self.0.lock().unwrap();
        match value {
            Some(v) => {
                map.insert((mod_id.into(), key.into()), v);
            }
            None => {
                map.remove(&(mod_id.into(), key.into()));
            }
        }
    }
    fn keys(&self, mod_id: &str) -> Vec<String> {
        self.0
            .lock()
            .unwrap()
            .keys()
            .filter(|(m, _)| m == mod_id)
            .map(|(_, k)| k.clone())
            .collect()
    }
}

struct EntityStore {
    entities: HashMap<u64, Entity>,
    next: u64,
    player: u64,
    moved_to: Vec<[f64; 3]>,
    shoves: Vec<[f32; 3]>,
    abilities: HashMap<[u8; 32], Option<Abilities>>,
}

#[derive(Clone)]
struct Entities(Arc<Mutex<EntityStore>>);

impl Entities {
    fn new() -> Self {
        let mut body = Entity::at(Transform::from_world(100.5, 64.0, 100.5), "engine:player");
        body.owner = Some(Owner(PlayerUuid::from_bytes(PLAYER)));
        body.on_ground = true;
        let mut entities = HashMap::new();
        entities.insert(1, body);
        Self(Arc::new(Mutex::new(EntityStore {
            entities,
            next: 2,
            player: 1,
            moved_to: Vec::new(),
            shoves: Vec::new(),
            abilities: HashMap::new(),
        })))
    }
    fn body(&self, edit: impl FnOnce(&mut Entity)) {
        let mut store = self.0.lock().unwrap();
        let id = store.player;
        edit(store.entities.get_mut(&id).unwrap());
    }
    fn set_position(&self, x: f64, y: f64, z: f64) {
        self.body(|b| {
            let yaw = b.transform.yaw;
            b.transform = Transform::from_world(x, y, z);
            b.transform.yaw = yaw;
        });
    }
    fn items(&self, source: &str) -> Vec<Stack> {
        self.0
            .lock()
            .unwrap()
            .entities
            .values()
            .filter(|e| e.source == source)
            .filter_map(|e| e.item.clone())
            .collect()
    }
}

impl ent::Access for Entities {
    fn spawn(&self, entity: Entity) -> Option<EntityId> {
        let mut store = self.0.lock().unwrap();
        let id = store.next;
        store.next += 1;
        store.entities.insert(id, entity);
        Some(EntityId(id))
    }
    fn despawn(&self, id: EntityId) -> bool {
        self.0.lock().unwrap().entities.remove(&id.0).is_some()
    }
    fn get(&self, id: EntityId) -> Option<Entity> {
        self.0.lock().unwrap().entities.get(&id.0).cloned()
    }
    fn patch(&self, id: EntityId, patch: &ent::Patch) -> bool {
        let mut store = self.0.lock().unwrap();
        match store.entities.get_mut(&id.0) {
            Some(entity) => patch.apply(entity),
            None => false,
        }
    }
    fn player(&self, uuid: [u8; 32]) -> Option<EntityId> {
        (uuid == PLAYER).then(|| EntityId(self.0.lock().unwrap().player))
    }
    fn within(&self, centre: [f64; 3], radius: f64, source: Option<&str>) -> Vec<EntityId> {
        let store = self.0.lock().unwrap();
        let mut found: Vec<(f64, u64)> = store
            .entities
            .iter()
            .filter(|(_, e)| source.is_none_or(|s| e.source == s))
            .filter_map(|(id, e)| {
                let [x, y, z] = e.transform.to_world();
                let d2 = (x - centre[0]).powi(2) + (y - centre[1]).powi(2) + (z - centre[2]).powi(2);
                (d2 <= radius * radius).then_some((d2, *id))
            })
            .collect();
        found.sort_by(|a, b| a.0.partial_cmp(&b.0).unwrap().then(a.1.cmp(&b.1)));
        found.into_iter().map(|(_, id)| EntityId(id)).collect()
    }
    fn move_player(&self, uuid: [u8; 32], to: [f64; 3]) -> bool {
        if uuid != PLAYER {
            return false;
        }
        let mut store = self.0.lock().unwrap();
        store.moved_to.push(to);
        let id = store.player;
        let body = store.entities.get_mut(&id).unwrap();
        let yaw = body.transform.yaw;
        body.transform = Transform::from_world(to[0], to[1], to[2]);
        body.transform.yaw = yaw;
        true
    }
    fn select_slot(&self, _: [u8; 32], _: u16) -> bool {
        true
    }
    fn shove_player(&self, uuid: [u8; 32], impulse: [f32; 3]) -> bool {
        if uuid != PLAYER {
            return false;
        }
        self.0.lock().unwrap().shoves.push(impulse);
        true
    }
    fn transfer(&self, _: EntityId, _: &str, _: [f64; 3]) -> bool {
        false
    }
    fn set_abilities(&self, uuid: [u8; 32], abilities: Option<Abilities>) -> bool {
        self.0.lock().unwrap().abilities.insert(uuid, abilities);
        true
    }
}

#[derive(Default)]
struct Inventory {
    views: Mutex<HashMap<String, Vec<Stack>>>,
    held: Mutex<Option<MaterialId>>,
}

impl Inventory {
    fn units_of(&self, view: &str, material: MaterialId) -> u32 {
        self.views
            .lock()
            .unwrap()
            .get(view)
            .map(|v| v.iter().filter(|s| s.material == material).map(|s| s.units).sum())
            .unwrap_or(0)
    }
}

impl inventory::Access for Inventory {
    fn contents(&self, _: [u8; 32], view: &str) -> Vec<Stack> {
        self.views.lock().unwrap().get(view).cloned().unwrap_or_default()
    }
    fn give(&self, _: [u8; 32], view: &str, stack: Stack) -> bool {
        let mut views = self.views.lock().unwrap();
        let list = views.entry(view.to_owned()).or_default();
        if let Some(existing) = list
            .iter_mut()
            .find(|s| s.material == stack.material && s.shape == stack.shape && s.detail == stack.detail)
        {
            existing.units += stack.units;
        } else {
            list.push(stack);
        }
        true
    }
    fn held(&self, _: [u8; 32]) -> Option<Stack> {
        let material = (*self.held.lock().unwrap())?;
        self.views
            .lock()
            .unwrap()
            .get("player:main")?
            .iter()
            .find(|s| s.material == material)
            .cloned()
    }
    fn take(
        &self,
        _: [u8; 32],
        view: &str,
        material: MaterialId,
        shape: Option<Shape>,
        detail: Option<&str>,
        units: u32,
    ) -> u32 {
        let mut views = self.views.lock().unwrap();
        let Some(list) = views.get_mut(view) else { return 0 };
        let mut got = 0;
        for stack in list.iter_mut() {
            if stack.material == material && stack.shape == shape && stack.detail.as_deref() == detail {
                let take = units.saturating_sub(got).min(stack.units);
                stack.units -= take;
                got += take;
            }
        }
        list.retain(|s| s.units > 0);
        got
    }
}

#[derive(Default)]
struct Sounds {
    plays: Mutex<Vec<String>>,
    time: Mutex<f32>,
}

impl sound::Access for Sounds {
    fn play(&self, request: &PlayRequest) -> u32 {
        self.plays.lock().unwrap().push(request.sound.clone());
        1
    }
    fn start_loop(&self, _: &LoopRequest) -> u32 {
        1
    }
    fn time_of_day(&self) -> f32 {
        *self.time.lock().unwrap()
    }
    fn stop_loop(&self, _: &sound::StopRequest) -> u32 {
        0
    }
    fn set_time_of_day(&self, fraction: f32) -> bool {
        *self.time.lock().unwrap() = fraction.rem_euclid(1.0);
        true
    }
}

/// The HUD values, and the two other things the engine answers through the
/// same trait: who is an operator, and each player's chat.
#[derive(Default)]
struct Huds {
    values: Mutex<HashMap<[u8; 32], Values>>,
    operators: Mutex<Vec<[u8; 32]>>,
    chat: Mutex<Vec<([u8; 32], String)>>,
}

impl Huds {
    fn of(&self, player: [u8; 32]) -> Values {
        self.values.lock().unwrap().get(&player).cloned().unwrap_or_default()
    }
    fn op(&self, player: [u8; 32]) {
        self.operators.lock().unwrap().push(player);
    }
    fn deop(&self, player: [u8; 32]) {
        self.operators.lock().unwrap().retain(|p| *p != player);
    }
    /// The last line said to a player, or empty.
    fn said_to(&self, player: [u8; 32]) -> String {
        let chat = self.chat.lock().unwrap();
        chat.iter().rev().find(|(p, _)| *p == player).map(|(_, t)| t.clone()).unwrap_or_default()
    }
}

impl hud::Access for Huds {
    fn set_hud(&self, mod_id: &str, player: [u8; 32], values: Values) -> bool {
        assert_eq!(mod_id, MOD);
        self.values.lock().unwrap().insert(player, values);
        true
    }
    fn is_operator(&self, player: [u8; 32]) -> bool {
        self.operators.lock().unwrap().contains(&player)
    }
    fn chat_to(&self, player: [u8; 32], text: &str) -> bool {
        self.chat.lock().unwrap().push((player, text.to_owned()));
        true
    }
}

/// Every particle burst, as sent.
#[derive(Default)]
struct Particles(Mutex<Vec<EmitRequest>>);

impl particle::Access for Particles {
    fn emit(&self, request: &EmitRequest) -> u32 {
        self.0.lock().unwrap().push(request.clone());
        1
    }
}

#[derive(Default)]
struct Dialogs(Mutex<Vec<ShowRequest>>);

impl uihost::Access for Dialogs {
    fn show(&self, request: &ShowRequest) -> bool {
        self.0.lock().unwrap().push(request.clone());
        true
    }
    fn close(&self, _: &str, _: &str) -> bool {
        true
    }
}

#[derive(Default)]
struct World {
    blocks: Mutex<HashMap<(i32, i32, i32), (MaterialId, u32)>>,
    fluids: Mutex<HashMap<(i32, i32, i32), u32>>,
    edits: Mutex<Vec<(BlockPos, String)>>,
    /// Solid ground everywhere at and below a height, of one material.
    floor: Mutex<Option<(i32, MaterialId)>>,
    /// The block the player's crosshair is on, if any.
    aimed: Mutex<Option<(i32, i32, i32)>>,
}

impl World {
    fn put(&self, x: i32, y: i32, z: i32, material: MaterialId) {
        self.blocks.lock().unwrap().insert((x, y, z), (material, 0x7FF_FFFF));
    }
    fn clear(&self) {
        self.blocks.lock().unwrap().clear();
        self.fluids.lock().unwrap().clear();
    }
}

impl sight::Access for World {
    fn line_of_sight(&self, _: &str, _: [f64; 3], _: [f64; 3]) -> Sighting {
        Sighting::Clear
    }
    fn looking_at(&self, uuid: [u8; 32]) -> Option<Looked> {
        let (x, y, z) = (*self.aimed.lock().unwrap())?;
        if uuid != PLAYER {
            return None;
        }
        let Reading::Single { material, occupancy } = self.block_at("", BlockPos { x, y, z }) else { return None };
        (occupancy != 0).then(|| Looked {
            domain: "overworld".into(),
            cell: tiamot_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 2, z: z * 3 + 1 },
            material,
            face: [0, 1, 0],
        })
    }
    fn block_at(&self, _: &str, pos: BlockPos) -> Reading {
        match self.blocks.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some((material, occupancy)) => Reading::Single { material: *material, occupancy: *occupancy },
            None => match *self.floor.lock().unwrap() {
                Some((top, material)) if pos.y <= top => Reading::Single { material, occupancy: 0x7FF_FFFF },
                _ => Reading::Single { material: MaterialId(0), occupancy: 0 },
            },
        }
    }
}

impl fluid::Access for World {
    fn fluid_at(&self, _: &str, pos: BlockPos) -> Fluid {
        match self.fluids.lock().unwrap().get(&(pos.x, pos.y, pos.z)) {
            Some(volume) => Fluid::new(FluidId(1), *volume),
            None => Fluid::EMPTY,
        }
    }
    fn set_fluid_at(&self, _: &str, _: BlockPos, _: Fluid) -> bool {
        true
    }
    fn fluid_id(&self, _: &str) -> Option<FluidId> {
        None
    }
}

impl LightSource for World {
    fn light_at(&self, _: &str, _: BlockPos) -> Light {
        Light::DAYLIGHT
    }
}

impl WorldEdit for World {
    fn set_block(&self, _: &str, pos: BlockPos, block: &str) -> bool {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        true
    }
    fn set_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        true
    }
    fn merge_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        true
    }
}

// --- The run ------------------------------------------------------------------

struct Rig {
    vm: EngineVm,
    storage: Arc<Storage>,
    entities: Entities,
    inventory: Arc<Inventory>,
    sounds: Arc<Sounds>,
    huds: Arc<Huds>,
    dialogs: Arc<Dialogs>,
    world: Arc<World>,
    particles: Arc<Particles>,
    materials: HashMap<String, MaterialId>,
}

impl Rig {
    fn number(&self, key: &str) -> f64 {
        match self.huds.of(PLAYER).get(key) {
            Some(Value::Number(n)) => *n,
            other => panic!("hud `{key}` is {other:?}, not a number"),
        }
    }
    fn flag(&self, key: &str) -> bool {
        match self.huds.of(PLAYER).get(key) {
            Some(Value::Flag(f)) => *f,
            other => panic!("hud `{key}` is {other:?}, not a flag"),
        }
    }
    fn say_as(&mut self, player: [u8; 32], text: &str) {
        self.vm.chat(&ChatEvent { player, text: text.into() });
        assert!(self.vm.faulted_mods().is_empty(), "faulted after `{text}`: {:?}", self.vm.faulted_mods());
    }
    fn text(&self, key: &str) -> String {
        match self.huds.of(PLAYER).get(key) {
            Some(Value::Text(t)) => t.clone(),
            other => panic!("hud `{key}` is {other:?}, not text"),
        }
    }
    fn tick(&mut self, n: u32) {
        for _ in 0..n {
            let faults = self.vm.tick(1).expect("the tick itself");
            assert!(faults.is_empty(), "mod faulted in tick: {faults:?}");
            let mut ours: Vec<u64> = self
                .entities
                .0
                .lock()
                .unwrap()
                .entities
                .iter()
                .filter(|(_, e)| e.source == MOD && e.item.is_none())
                .map(|(id, _)| *id)
                .collect();
            // In id order, as the server steps them: the mod rolls its dice
            // per step, and a hash map's order would reshuffle every run.
            ours.sort_unstable();
            if !ours.is_empty() {
                let fault = self.vm.entity_step(MOD, &ours, 1).expect("the step itself");
                assert!(fault.is_none(), "mod faulted in entity step: {fault:?}");
            }
        }
        assert!(self.vm.faulted_mods().is_empty(), "faulted: {:?}", self.vm.faulted_mods());
    }
    fn say(&mut self, text: &str) {
        self.vm.chat(&ChatEvent { player: PLAYER, text: text.into() });
        assert!(self.vm.faulted_mods().is_empty(), "faulted after `{text}`: {:?}", self.vm.faulted_mods());
    }
    fn press(&mut self, action: &str) {
        for pressed in [true, false] {
            self.vm.action(&ActionEvent { player: PLAYER, id: format!("{MOD}:{action}"), pressed });
        }
        assert!(self.vm.faulted_mods().is_empty(), "faulted after `{action}`: {:?}", self.vm.faulted_mods());
    }
    fn material(&self, id: &str) -> MaterialId {
        *self.materials.get(id).unwrap_or_else(|| panic!("no material {id}"))
    }
    fn hold(&self, id: &str) {
        let material = self.material(id);
        let mut views = self.inventory.views.lock().unwrap();
        let list = views.entry("player:main".into()).or_default();
        if !list.iter().any(|s| s.material == material) {
            list.push(Stack::new(material, 27 * 4).unwrap());
        }
        drop(views);
        *self.inventory.held.lock().unwrap() = Some(material);
    }
    fn hold_nothing(&self) {
        *self.inventory.held.lock().unwrap() = None;
    }
    fn mobs(&self) -> Vec<(u64, Entity)> {
        let mut out: Vec<(u64, Entity)> = self
            .entities
            .0
            .lock()
            .unwrap()
            .entities
            .iter()
            .filter(|(_, e)| e.source == MOD && e.item.is_none())
            .map(|(id, e)| (*id, e.clone()))
            .collect();
        out.sort_by_key(|(id, _)| *id);
        out
    }
    fn put_mob(&self, id: u64, x: f64, y: f64, z: f64) {
        let mut store = self.entities.0.lock().unwrap();
        let mob = store.entities.get_mut(&id).unwrap();
        mob.transform = Transform::from_world(x, y, z);
    }
    /// The last abilities said for the player.
    fn abilities(&self) -> Option<Abilities> {
        self.entities.0.lock().unwrap().abilities.get(&PLAYER).copied().flatten()
    }
    fn said(&self) -> String {
        self.huds.said_to(PLAYER)
    }
    fn plays(&self, sound: &str) -> usize {
        self.sounds.plays.lock().unwrap().iter().filter(|s| s.ends_with(sound)).count()
    }
}

fn rig() -> Rig {
    // The fake world sits at the origin, which on the Spindle is the frozen
    // Crown: climate off, and a 500-block disc so the origin's neighbourhood
    // counts as the temperate ring for spawning.
    rig_with("tdl_overrides = { climate = false, world_radius = 500 }\n")
}

fn rig_with(prelude: &str) -> Rig {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
    let mut vm = EngineVm::create(VmLimits::default()).unwrap();

    let storage = Arc::new(Storage::default());
    let entities = Entities::new();
    let inventory = Arc::new(Inventory::default());
    let sounds = Arc::new(Sounds::default());
    let huds = Arc::new(Huds::default());
    let dialogs = Arc::new(Dialogs::default());
    let world = Arc::new(World::default());
    let particles = Arc::new(Particles::default());

    vm.set_storage_access(storage.clone());
    vm.set_entity_access(Arc::new(entities.clone()));
    vm.set_inventory_access(inventory.clone());
    vm.set_sound_access(sounds.clone());
    vm.set_hud_access(huds.clone());
    vm.set_dialog_access(dialogs.clone());
    vm.set_sight_access(world.clone());
    vm.set_fluid_access(world.clone());
    vm.set_light_source(world.clone());
    vm.set_world_edit(world.clone());
    vm.set_particle_access(particles.clone());

    // A stand-in for the world mod, so the lava and the bramble exist.
    vm.load_mod(
        "tiamot_default_world",
        "for _, id in ipairs({ 'magma', 'bramble', 'dream_stone', 'grass', 'loam', 'leaf_litter', 'mud', 'dirt', 'packed_dirt', 'dead_wood', 'snow', 'permafrost', 'fern', 'tall_grass', 'ladys_mantle', 'ladys_mantle_bloom' }) do game.register_block{ id = id, passable = (id == 'fern' or id == 'tall_grass' or id == 'ladys_mantle' or id == 'ladys_mantle_bloom') } end",
        &dir,
    )
    .unwrap();
    vm.load_mod("core_gear", "game.register_item{ id = 'sword' }", &dir).unwrap();
    let init = format!("{prelude}{}", std::fs::read_to_string(dir.join("init.lua")).unwrap());
    vm.load_mod(MOD, &init, &dir).expect("the mod loads");
    vm.freeze().unwrap();

    // Noon, so nothing is cold unless a scenario makes it so.
    *sounds.time.lock().unwrap() = 0.5;
    let materials = vm.registered_blocks().into_iter().collect();
    Rig { vm, storage, entities, inventory, sounds, huds, dialogs, world, particles, materials }
}

fn main() {
    let mut r = rig();
    assert_eq!(r.vm.registered_hud_scripts().len(), 1);
    // The engine makes the first player of a hosted world its operator.
    r.huds.op(PLAYER);

    // Joining: fresh vitals, a welcome, values on the HUD after one tick.
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    r.tick(1);
    assert_eq!(r.number("hp"), 27.0);
    assert_eq!(r.number("food"), 18.0, "visible food is capped at the cookies");
    assert_eq!(r.number("air"), 27.0);
    assert!(!r.flag("air_show"));
    assert!(!r.flag("temp_show"));
    assert!(r.text("toast").starts_with("Welcome, Alice"));
    println!("ok  join: hearts full, cookies full, nothing else showing");

    // Standing still for a while costs nothing visible and faults nothing.
    r.tick(300);
    assert_eq!(r.number("hp"), 27.0);
    assert!(r.text("toast").is_empty(), "the welcome has gone");
    println!("ok  300 quiet ticks");

    // A hit: hearts come off, the flash shows, the hurt sound plays.
    r.say("hurt 5");
    r.tick(1);
    assert_eq!(r.number("hp"), 22.0);
    assert!(r.flag("hurt"));
    assert!(r.plays("hurt") >= 1);
    r.tick(10);
    assert!(!r.flag("hurt"));
    // Regeneration: spawn food is 22, above the visible 18, so the buffer
    // heals a point a second once the quiet time has passed.
    r.tick(60 + 20 * 5 + 5);
    assert_eq!(r.number("hp"), 27.0, "healed back on saturation");
    println!("ok  hurt 5, flashed, regenerated on the hidden buffer");

    // Poison ticks a point every 25 ticks and stops at the last point.
    r.say("poison 2000");
    r.tick(1);
    assert!(r.text("fx").contains("poison"));
    r.tick(25 * 40);
    assert_eq!(r.number("hp"), 1.0, "poison never kills");
    r.hold("tiamot_default_life:antidote");
    r.press("use");
    r.tick(1);
    assert!(!r.text("fx").contains("poison"), "the antidote cleared it");
    assert_eq!(r.inventory.units_of("player:main", r.material("tiamot_default_life:antidote")), 27 * 3);
    println!("ok  poison to one point, antidote cured it and was spent");

    // Eating: starve, then an apple is two cookies and a bite of buffer.
    r.say("heal");
    r.say("starve 4");
    r.tick(1);
    assert_eq!(r.number("food"), 4.0);
    assert!(r.flag("hungry"));
    r.hold("tiamot_default_life:apple");
    r.tick(16);
    r.press("use");
    r.tick(1);
    assert_eq!(r.number("food"), 9.0, "4 + 4 food + 1 saturation");
    assert!(r.plays("eat") >= 1);
    assert!(r.text("toast").contains("apple"));
    // Full players are told so and keep their food. The cooldown is waited
    // out BEFORE the feed, so the press lands on exactly full cookies.
    r.tick(16);
    r.say("feed");
    let before = r.inventory.units_of("player:main", r.material("tiamot_default_life:apple"));
    r.press("use");
    r.tick(1);
    assert_eq!(r.inventory.units_of("player:main", r.material("tiamot_default_life:apple")), before);
    assert!(r.text("toast").contains("full"));
    println!("ok  eating an apple, and being too full to");

    // A hot stew warms: the warmth effect shows and the body drifts warm.
    r.say("starve 10");
    r.hold("tiamot_default_life:hot_stew");
    r.tick(16);
    r.press("use");
    r.tick(1);
    assert!(r.text("fx").contains("warmth"));
    assert!(r.text("fx").contains("well_fed"));
    r.tick(400);
    assert!(r.number("temp") > 0.3, "warmed to {}", r.number("temp"));
    assert!(r.flag("temp_show"));
    println!("ok  stew warmed the body to {:.2}, thermometer showing", r.number("temp"));

    // Cold: a cold source beside the feet, at night, drives the body cold.
    r.say("heal");
    let dream = r.material("tiamot_default_world:dream_stone");
    r.world.put(101, 63, 100, dream);
    r.world.put(102, 63, 100, dream);
    *r.sounds.time.lock().unwrap() = 0.05;
    r.tick(1400);
    assert!(r.number("temp") < -0.5, "cooled to {}", r.number("temp"));
    assert!(r.flag("cold"));
    assert_eq!(r.text("shield"), "broken", "cold surroundings and nothing warm on: the cracked shield");
    let slowed = r.abilities().expect("abilities were said");
    assert!((slowed.speed - 0.8).abs() < 1e-6, "the cold slow the body: {slowed:?}");
    r.world.clear();
    *r.sounds.time.lock().unwrap() = 0.5;
    println!("ok  cold stone at night chilled the body to {:.2}", r.number("temp"));

    // A coat, worn, brings it back.
    r.say("kit");
    let coat = Stack::new(r.material("tiamot_default_life:warm_coat"), 27).unwrap();
    r.inventory.views.lock().unwrap().entry(format!("{MOD}:worn")).or_default().push(coat);
    r.tick(900);
    assert!(r.number("temp") > -0.3, "the coat warmed things to {}", r.number("temp"));
    // Still night and cold out, but the coat answers it: the faint shield.
    *r.sounds.time.lock().unwrap() = 0.05;
    r.tick(20);
    assert_eq!(r.text("shield"), "ok", "a warm coat in the cold: the faint shield");
    *r.sounds.time.lock().unwrap() = 0.5;
    r.tick(20);
    assert_eq!(r.text("shield"), "", "mild weather: no shield at all");
    r.inventory.views.lock().unwrap().remove(&format!("{MOD}:worn"));
    assert_eq!(r.abilities().map(|a| a.speed), Some(1.0), "warm again, full speed again");
    println!("ok  a warm coat brought it back to {:.2}, and the body its speed", r.number("temp"));

    // An empty stomach will not sprint; a meal lets it again.
    r.say("starve 0");
    r.tick(1);
    assert_eq!(r.abilities().map(|a| a.sprint), Some(false), "starving: no sprint");
    r.say("feed");
    r.tick(1);
    assert_eq!(r.abilities().map(|a| a.sprint), Some(true));
    assert_eq!(r.abilities().map(|a| a.fly), Some(false), "nobody flies by this mod in a default world");
    assert_eq!(r.abilities().map(|a| a.wind_sky), Some(true), "an admin may wind the sky");
    r.huds.deop(PLAYER);
    r.tick(1);
    assert_eq!(r.abilities().map(|a| a.wind_sky), Some(false), "nobody else may, where nights are meant");
    r.huds.op(PLAYER);
    r.tick(1);
    println!("ok  abilities: cold slows, an empty stomach walks, only admins wind the sky, and the client is told");

    // A fall: up in the air for a moment, then hard ground twenty blocks down.
    r.say("heal");
    r.tick(1);
    r.entities.body(|b| b.on_ground = false);
    r.entities.set_position(100.5, 84.0, 100.5);
    r.tick(3);
    r.entities.body(|b| {
        b.velocity.0[1] = -4.0;
    });
    r.tick(1);
    r.entities.set_position(100.5, 64.0, 100.5);
    r.entities.body(|b| {
        b.on_ground = true;
        b.velocity.0[1] = 0.0;
        b.fell = 20.0;
    });
    r.tick(1);
    r.entities.body(|b| b.fell = 0.0);
    // (20 - 3) * 1.15 = 19.55, rounded to 20.
    assert_eq!(r.number("hp"), 7.0, "a twenty-block fall is most of you, and not all");
    assert!(r.plays("thud") >= 1);
    println!("ok  a twenty-block fall took 20 points");

    // Flying down the same distance is not a fall: the engine lands the body
    // with nothing fallen, and nothing is owed.
    r.say("heal");
    r.tick(1);
    r.entities.body(|b| b.on_ground = false);
    r.entities.set_position(100.5, 84.0, 100.5);
    r.tick(3);
    r.entities.set_position(100.5, 64.0, 100.5);
    r.entities.body(|b| b.on_ground = true);
    r.tick(1);
    assert_eq!(r.number("hp"), 27.0, "a flight down is not a fall");
    println!("ok  a flight down cost nothing");

    // Drowning: the body goes under.
    r.entities.body(|b| b.submerged = 1.0);
    r.tick(20);
    assert!(r.flag("wet"));
    assert!(r.flag("air_show"));
    assert!(r.number("air") < 27.0, "air started draining: {}", r.number("air"));
    r.tick(13 * 27 + 20 * 3 + 10);
    assert_eq!(r.number("air"), 0.0);
    assert!(r.number("hp") <= 27.0 - 9.0, "drowning at a heart a second: {}", r.number("hp"));
    r.entities.body(|b| b.submerged = 0.0);
    r.tick(20);
    assert_eq!(r.number("air"), 27.0, "air came straight back");
    assert!(r.plays("gasp") >= 1);
    println!("ok  drowned to {} points, surfaced and gasped", r.number("hp"));

    // Lava under the feet: contact damage and burning after.
    r.say("heal");
    r.tick(1);
    let magma = r.material("tiamot_default_world:magma");
    let chilled = r.number("temp");
    r.world.put(100, 63, 100, magma);
    r.tick(45);
    assert!(r.number("hp") <= 27.0 - 12.0, "lava: {}", r.number("hp"));
    assert!(r.text("fx").contains("burning"));
    assert!(r.number("temp") > chilled + 0.1, "standing on lava warms: {} -> {}", chilled, r.number("temp"));
    r.world.clear();
    r.tick(200);
    assert!(!r.text("fx").contains("burning"), "burning went out");
    println!("ok  lava burned and the fire went out");

    // Death: a scatter on the ground, a move, a screen, everything reset.
    r.say("heal");
    r.tick(1);
    let apples_before = r.inventory.units_of("player:main", r.material("tiamot_default_life:apple"));
    let dialogs_before = r.dialogs.0.lock().unwrap().len();
    r.say("die");
    r.tick(1);
    assert_eq!(r.number("hp"), 27.0);
    assert_eq!(r.number("food"), 18.0);
    assert!(r.flag("shielded"));
    assert!(r.text("toast").contains("gave up"));
    assert_eq!(r.dialogs.0.lock().unwrap().len(), dialogs_before + 1, "a death screen was shown");
    assert!(r.entities.0.lock().unwrap().moved_to.len() >= 1, "the player was moved");
    let dropped = r.entities.items(MOD);
    assert!(!dropped.is_empty(), "something was scattered");
    let apples_after = r.inventory.units_of("player:main", r.material("tiamot_default_life:apple"));
    assert!(apples_after < apples_before, "a share of the apples was dropped");
    assert!(r.plays("death") >= 1);
    // And the scatter is picked back up by walking over it.
    r.tick(90);
    let apples_back = r.inventory.units_of("player:main", r.material("tiamot_default_life:apple"));
    assert_eq!(apples_back, apples_before, "walked over the drops and picked them all back up");
    println!("ok  died, dropped a third, respawned shielded, picked it back up");

    // The punch veto is not a veto: another body hitting the player hurts.
    r.tick(70);
    let attacker = PlayerUuid::from_bytes([9; 32]);
    let target = r.entities.0.lock().unwrap().player;
    r.vm.punch(&tiamot_core::script::PunchEvent {
        attacker: *attacker.as_bytes(),
        target: EntityId(target),
        owner: Some(PLAYER),
    });
    r.tick(1);
    assert_eq!(r.number("hp"), 26.0, "a bare fist is one point");
    println!("ok  a punch from another player landed for one");

    // Sleep: beside a bed, at night, everything comes back and the bed is home.
    r.say("hurt 9");
    r.tick(1);
    let bed = r.material("tiamot_default_life:bed");
    r.world.put(101, 64, 100, bed);
    r.hold_nothing();
    *r.sounds.time.lock().unwrap() = 0.5;
    r.tick(16);
    r.press("use");
    r.tick(1);
    assert!(r.text("toast").contains("only sleep at night"));
    assert!(r.storage.get(MOD, &format!("bed:{}", PlayerUuid::from_bytes(PLAYER).to_hex())).is_some());
    *r.sounds.time.lock().unwrap() = 0.9;
    r.tick(120);
    r.press("use");
    r.tick(1);
    assert_eq!(r.number("hp"), 27.0);
    assert!(r.text("fx").contains("rested"));
    assert!(r.plays("rested") >= 1);
    assert_eq!(*r.sounds.time.lock().unwrap(), 0.25, "alone in the world, a night slept is a night ended");
    assert!(r.text("toast").contains("morning"), "{}", r.text("toast"));
    r.world.clear();
    println!("ok  slept at night, healed, well rested, woke at dawn, bed set as home");

    // X sleeps in the bed the crosshair is on, out of reach of the feet.
    r.world.put(104, 64, 100, bed);
    *r.world.aimed.lock().unwrap() = Some((104, 64, 100));
    *r.sounds.time.lock().unwrap() = 0.9;
    r.tick(120);
    r.press("use");
    r.tick(1);
    let home = r.storage.get(MOD, &format!("bed:{}", PlayerUuid::from_bytes(PLAYER).to_hex()));
    assert!(format!("{home:?}").contains("104"), "the aimed bed is home: {home:?}");
    *r.world.aimed.lock().unwrap() = None;
    r.world.clear();
    println!("ok  X on a bed across the room sleeps in that bed");

    // An explosion nearby shoves and hurts.
    let shoves = r.entities.0.lock().unwrap().shoves.len();
    r.say("boom");
    r.tick(1);
    assert!(r.number("hp") < 27.0);
    assert!(r.entities.0.lock().unwrap().shoves.len() > shoves);
    assert!(r.plays("boom") >= 1);
    println!("ok  boom");

    // Foraging: digging a bramble yields berries.
    let berries = r.material("tiamot_default_life:berries");
    let before = r.inventory.units_of("player:main", berries);
    r.vm.dig_complete(&tiamot_core::script::DigEvent {
        player: PLAYER,
        target: tiamot_core::SubNodePos { x: 300, y: 190, z: 300 },
        material: r.material("tiamot_default_world:bramble"),
        brush: tiamot_core::dig::Brush::Block,
    });
    assert_eq!(r.inventory.units_of("player:main", berries), before + 27);
    println!("ok  a bramble dug is berries in the bag");

    // Leaving saves; joining again loads the same numbers.
    r.say("starve 7");
    r.tick(1);
    r.vm.player_leave(&LeaveEvent { player: PLAYER, name: "Alice".into() });
    let saved = r.storage.get(MOD, &format!("v:{}", PlayerUuid::from_bytes(PLAYER).to_hex()));
    assert!(matches!(saved, Some(storage::Value::Text(ref t)) if t.contains("food=7")), "{saved:?}");
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    r.tick(1);
    assert_eq!(r.number("food"), 7.0, "food came back from storage");
    println!("ok  vitals survive leaving and rejoining");

    // The wardrobe opens and closes.
    let n = r.dialogs.0.lock().unwrap().len();
    r.press("wardrobe");
    assert_eq!(r.dialogs.0.lock().unwrap().len(), n + 1);
    r.vm.dialog_event(&DialogEvent {
        player: PLAYER,
        mod_id: MOD.into(),
        form: format!("{MOD}:wardrobe"),
        event: tiamot_core::proto::DialogEvent::Closed,
    });
    for request in r.dialogs.0.lock().unwrap().iter() {
        tiamot_core::ui::check(&request.tree, tiamot_core::ui::Limits::default()).expect("a valid tree");
    }
    println!("ok  the wardrobe and the death screen are valid dialog trees");

    mob_check(&mut r);
    pace_check();
    climate_check();
    modes_check();

    // The HUD script, drawn by the client's own VM, on several states.
    hud_check(&r);

    println!("PASS: tiamot_default_life runs through the engine VM end to end");
}

fn mob_check(r: &mut Rig) {
    // A grass plain under everything, at noon, and nothing about yet.
    let grass = r.material("tiamot_default_world:grass");
    *r.world.floor.lock().unwrap() = Some((63, grass));
    *r.sounds.time.lock().unwrap() = 0.5;
    r.say("cull");
    r.tick(1);
    assert!(r.mobs().is_empty());

    // Spawning: passes every hundred ticks put farm animals and crows on
    // the grass around the player, in groups, under their caps.
    r.tick(100 * 12);
    let spawned = r.mobs();
    assert!(spawned.len() >= 4, "animals appeared on the grass: {}", spawned.len());
    let mut kinds: Vec<String> = spawned.iter().filter_map(|(_, e)| kind_of(e)).collect();
    kinds.sort();
    kinds.dedup();
    assert!(kinds.len() >= 2, "more than one kind: {kinds:?}");
    for (_, mob) in &spawned {
        // The cow and the pig are their own models; a kind with none yet is
        // the named stand-in.
        if matches!(mob.model.as_deref(), Some("tiamot_default_life:cow" | "tiamot_default_life:pig")) {
            assert_eq!(mob.nametag, None, "a cow looks like a cow and needs no name over it");
        } else {
            assert_eq!(mob.model.as_deref(), Some("engine:humanoid"), "a stand-in body");
            assert_ne!(mob.nametag, None, "a stand-in's kind rides on its nametag");
        }
        assert!(mob.health.is_some(), "a mob has health");
        let [_, y, _] = mob.transform.to_world();
        assert!((y - 64.0).abs() < 0.01, "standing on the floor, not in it: {y}");
    }
    assert!(!kinds.iter().any(|k| k.contains("Bat")), "no bats in daylight on open grass");
    println!("ok  spawning: {} mobs of {} kinds on the grass by day", spawned.len(), kinds.len());
    r.say("cull");
    r.tick(1);
    // No ground from here on, so nothing else wanders in mid-scenario.
    *r.world.floor.lock().unwrap() = None;

    // A cow, punched: it loses a point and runs; a sword finishes it and it
    // leaves meat behind, which the player then picks up.
    r.say("spawn cow 1");
    r.tick(1);
    let cows = r.mobs();
    assert_eq!(cows.len(), 1, "one cow");
    let (cow, _) = cows[0].clone();
    r.hold_nothing();
    r.particles.0.lock().unwrap().clear();
    r.vm.punch(&tiamot_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
    r.tick(1);
    assert_eq!(r.mobs()[0].1.health.unwrap().current, 9, "a fist is one point");
    // Five hearts over it, for the one who hit it: 9 points left in red, the
    // one it lost flashing white, nothing dark yet. Thirteen pixels a heart.
    {
        let bursts = r.particles.0.lock().unwrap();
        assert_eq!(bursts.len(), 5 * 13, "five hearts of pixels");
        assert!(bursts.iter().all(|b| b.player == Some(PlayerUuid::from_bytes(PLAYER))), "for the hitter only");
        let white = bursts.iter().filter(|b| b.burst.colour[1] > 200).count();
        assert!(white > 0 && white < 13, "the point it lost flashes white: {white} pixels");
        let top = bursts.iter().map(|b| b.burst.pos[1]).fold(f64::MIN, f64::max);
        let cow_y = r.mobs()[0].1.transform.to_world()[1];
        assert!(top > cow_y + 1.5, "above the cow: {top} over {cow_y}");
    }
    let meat = r.material("tiamot_default_life:raw_meat");
    let meat_before = r.inventory.units_of("player:main", meat);
    r.hold("core_gear:sword");
    for _ in 0..2 {
        r.tick(12);
        r.vm.punch(&tiamot_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
    }
    r.tick(1);
    assert!(r.mobs().is_empty(), "the cow is gone");
    assert!(!r.entities.items(MOD).is_empty(), "meat on the ground");
    // Walk over to it: the drop lies where the cow stood, four blocks off.
    let drops: Vec<u64> = r
        .entities
        .0
        .lock()
        .unwrap()
        .entities
        .iter()
        .filter(|(_, e)| e.source == MOD && e.item.is_some())
        .map(|(id, _)| *id)
        .collect();
    for id in drops {
        r.put_mob(id, 100.5, 64.5, 100.5);
    }
    r.tick(5);
    assert!(r.inventory.units_of("player:main", meat) > meat_before, "and in the bag");
    println!("ok  a cow punched showed its hearts, ran off, slain by sword, and its meat picked up");

    // A walker jumps only when it is stuck. A punched cow runs; while its
    // body is moving it never jumps, whatever the ground ahead. Held still
    // (a hole, a wall), it jumps after half a second of trying.
    r.say("spawn cow 1");
    r.tick(1);
    let (cow, _) = r.mobs()[0].clone();
    r.hold_nothing();
    r.vm.punch(&tiamot_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
    let set_cow = |r: &Rig, vx: f32| {
        let mut store = r.entities.0.lock().unwrap();
        let body = store.entities.get_mut(&cow).unwrap();
        body.on_ground = true;
        body.velocity.0 = [vx, 0.0, 0.0];
    };
    let jumping = |r: &Rig| r.entities.0.lock().unwrap().entities[&cow].drive.jump;
    for _ in 0..30 {
        set_cow(&r, 0.4);
        r.tick(1);
        assert!(!jumping(&r), "a cow on the move does not jump");
    }
    let mut jumped = false;
    for _ in 0..12 {
        set_cow(&r, 0.0);
        r.tick(1);
        jumped |= jumping(&r);
    }
    assert!(jumped, "a cow going nowhere jumps to get out");
    r.say("cull");
    r.tick(1);
    println!("ok  a cow jumps only when it is stuck");

    // A bat at night: it hunts the player, bites, and wheels away.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("heal");
    r.say("spawn bat 1");
    r.tick(1);
    let bats = r.mobs();
    assert_eq!(bats.len(), 1, "one bat");
    let (bat, _) = bats[0].clone();
    let bites = r.plays("bite");
    // Put it on the shoulder: the fake world has no physics to fly it there.
    r.put_mob(bat, 101.0, 65.5, 100.5);
    r.tick(25);
    assert!(r.number("hp") < 27.0, "bitten: {}", r.number("hp"));
    assert!(r.plays("bite") > bites);
    // Daylight, and it loses interest.
    *r.sounds.time.lock().unwrap() = 0.5;
    r.say("heal");
    r.put_mob(bat, 101.0, 65.5, 100.5);
    r.tick(60);
    assert_eq!(r.number("hp"), 27.0, "a bat in daylight is harmless");
    println!("ok  a bat bit at night and left off by day");
    r.say("cull");
    r.tick(1);
    *r.world.floor.lock().unwrap() = None;
}

/// The Spindle's radial climate, read off the player's position: the
/// temperate ring is comfortable, the Glass Waste hot, the Crown frozen.
fn climate_check() {
    let mut r = rig_with("");
    r.huds.op(PLAYER);
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    let grass = r.material("tiamot_default_world:grass");
    *r.world.floor.lock().unwrap() = Some((63, grass));

    // The spawn plain, at noon: nothing to report.
    r.entities.set_position(15300.5, 64.0, 0.5);
    r.tick(600);
    assert!(r.number("temp").abs() < 0.3, "temperate ring is comfortable: {}", r.number("temp"));
    assert!(!r.flag("temp_show"));
    // Whatever appeared on the plain meanwhile is culled here, while it is
    // still within reach: the fake store lists the whole world.
    r.say("cull");
    r.tick(1);
    assert!(r.mobs().is_empty(), "the plain is empty again");

    // The Glass Waste (t 0.42 to 0.48), about as hot as the disc gets.
    r.entities.set_position(26500.5, 64.0, 0.5);
    r.tick(900);
    assert!(r.flag("hot"), "the Glass Waste is hot: {}", r.number("temp"));
    assert_eq!(r.text("shield"), "broken", "no cool cloak on: cracked shield");

    // Under the axis: the ice cap.
    r.entities.set_position(0.5, 64.0, 0.5);
    r.tick(900);
    assert!(r.flag("cold"), "the Crown is cold: {}", r.number("temp"));

    // Spawning by ring: on the Glass Waste no farm animal appears, whatever
    // is underfoot; crows and bats keep to their own rings too.
    r.entities.set_position(26500.5, 64.0, 0.5);
    r.tick(100 * 8);
    let there: Vec<String> = r.mobs().iter().filter_map(|(_, e)| kind_of(e)).collect();
    assert!(there.is_empty(), "nothing of ours lives on the Glass Waste: {there:?}");
    // And on the spawn plain they do.
    r.entities.set_position(15300.5, 64.0, 0.5);
    r.tick(100 * 8);
    assert!(!r.mobs().is_empty(), "the temperate ring has its animals");
    println!("ok  climate: temperate comfortable, Glass Waste hot, Crown cold; creatures keep to their rings");
}

const BOB: [u8; 32] = [9; 32];

/// A walker at `pace = 0.5` pushes on every other tick and coasts on the rest,
/// through the engine's own physics on flat ground: it should settle at about
/// half the walk, and not lurch.
fn pace_check() {
    use tiamot_core::phys::{Body, Intent, Solid, Tuning, step};
    struct Ground;
    impl Solid for Ground {
        fn solid(&self, _: i32, y: i32, _: i32) -> bool {
            y < 0
        }
    }
    let walk = |push: bool| Intent { walk: if push { [1.0, 0.0] } else { [0.0, 0.0] }, ..Intent::default() };
    let run = |pace: f32| {
        let mut body = Body { position: [0.0, 0.0, 0.0], velocity: [0.0; 3], on_ground: true, jump_cooldown: 0 };
        let (mut acc, mut lo, mut hi) = (0.0f32, f32::MAX, 0.0f32);
        for tick in 0..200 {
            acc += pace;
            let push = acc >= 1.0;
            if push {
                acc -= 1.0;
            }
            let before = body.position[0];
            body = step(&Ground, body, walk(push), &Tuning::DEFAULT);
            if tick >= 100 {
                let moved = body.position[0] - before;
                lo = lo.min(moved);
                hi = hi.max(moved);
            }
        }
        (body.position[0], lo, hi)
    };
    let (full, _, _) = run(1.0);
    let (half, lo, hi) = run(0.5);
    let ratio = half / full;
    assert!((ratio - 0.5).abs() < 0.08, "half pace covers half the ground: {ratio:.2}");
    assert!(lo > 0.0 && hi / lo < 1.8, "and never stops between pushes: {lo:.3}..{hi:.3} cells a tick");
    println!("ok  pace 0.5: {ratio:.2} of the walk, {lo:.3} to {hi:.3} cells a tick");
}

/// A mob's kind: its model, if it has one of its own, else its nametag.
fn kind_of(e: &Entity) -> Option<String> {
    match e.model.as_deref() {
        Some(m) if m != "engine:humanoid" => Some(m.rsplit(':').next().unwrap_or(m).to_owned()),
        _ => e.nametag.as_ref().map(|n| format!("{n:?}")),
    }
}

fn dig(r: &mut Rig) -> bool {
    r.vm
        .dig_complete(&tiamot_core::script::DigEvent {
            player: PLAYER,
            target: tiamot_core::SubNodePos { x: 300, y: 190, z: 300 },
            material: r.material("tiamot_default_world:grass"),
            brush: tiamot_core::dig::Brush::Block,
        })
        .allowed
}

/// Admins, and the three kinds of world.
fn modes_check() {
    // A default world. Admins are the server's operators: Alice is one, Bob
    // is not, and the answers come back in chat.
    let mut r = rig();
    r.huds.op(PLAYER);
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    r.vm.player_join(&JoinEvent { player: BOB, name: "Bob".into() });
    r.tick(1);
    r.say_as(BOB, "god");
    r.tick(1);
    assert!(r.huds.said_to(BOB).contains("admins"), "Bob is refused: {}", r.huds.said_to(BOB));
    r.say_as(BOB, "hurt 5");
    r.tick(1);
    assert!(r.huds.said_to(BOB).contains("admins"), "the testing words are admin words too");

    r.tick(60);
    r.say("god");
    r.say("hurt 5");
    r.tick(1);
    assert_eq!(r.number("hp"), 27.0, "an indestructible admin is not hurt");
    assert!(r.flag("god"));
    r.say("god");
    r.say("hurt 5");
    r.tick(1);
    assert_eq!(r.number("hp"), 22.0, "and can be again");

    r.say("tp 10 70 -4");
    assert_eq!(r.entities.0.lock().unwrap().moved_to.last().copied(), Some([10.0, 70.0, -4.0]));

    // The engine's `/op` makes Bob one, and he is at once.
    r.huds.op(BOB);
    r.say_as(BOB, "god");
    r.tick(1);
    assert!(r.huds.said_to(BOB).contains("Nothing can hurt you"), "Bob was made an admin");
    r.say("admins");
    assert!(r.said().contains("Alice") && r.said().contains("Bob"), "{}", r.said());
    // And `/deop` takes it all back, god included.
    r.huds.deop(BOB);
    r.say_as(BOB, "hurt 5");
    r.tick(1);
    assert!(r.huds.said_to(BOB).contains("admins"), "Bob is refused again");
    assert!(!matches!(r.huds.of(BOB).get("god"), Some(Value::Flag(true))), "a deopped god is mortal");
    println!("ok  admins: the server's operators; god, tp and admins work, are refused to others, and end at deop");

    // A creative world: nothing hurts, nothing drains, the kit is everybody's.
    let mut c = rig_with("tdl_overrides = { climate = false, world_radius = 500, mode = 'Creative' }\n");
    c.huds.op(PLAYER);
    c.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    c.vm.player_join(&JoinEvent { player: BOB, name: "Bob".into() });
    c.tick(70);
    c.say("hurt 9");
    c.entities.body(|b| b.submerged = 1.0);
    c.tick(2000);
    assert_eq!(c.number("hp"), 27.0);
    assert_eq!(c.number("food"), 18.0);
    assert_eq!(c.number("air"), 27.0, "nobody drowns in a creative world");
    assert!(c.flag("creative"));
    assert_eq!(c.abilities().map(|a| a.fly), Some(true), "everybody flies in a creative world");
    c.say_as(BOB, "kit");
    assert!(c.inventory.units_of("player:main", c.material("tiamot_default_life:apple")) > 0, "anyone may take the kit");
    c.say_as(BOB, "boom");
    c.tick(1);
    assert!(c.huds.said_to(BOB).contains("admins"), "but not the rest");
    println!("ok  creative: no harm, no hunger, no drowning, flight for all; the kit is open to all");

    // An adventure world: one life.
    let mut a = rig_with("tdl_overrides = { climate = false, world_radius = 500, mode = 'Adventure' }\n");
    a.huds.op(PLAYER);
    a.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    a.tick(70);
    assert!(a.text("toast").contains("one life"));
    a.say("kit");
    let apple = a.material("tiamot_default_life:apple");
    assert!(a.inventory.units_of("player:main", apple) > 0);
    assert!(dig(&mut a), "the living dig");
    a.say("die");
    a.tick(1);
    assert!(a.flag("ghost"), "dead for good");
    assert_eq!(a.number("hp"), 0.0);
    assert_eq!(a.inventory.units_of("player:main", apple), 0, "everything fell");
    assert!(!a.entities.items(MOD).is_empty());
    assert!(a.entities.0.lock().unwrap().moved_to.is_empty(), "there is no waking up somewhere else");
    assert!(!dig(&mut a), "a ghost digs nothing");
    a.tick(200);
    assert_eq!(a.inventory.units_of("player:main", apple), 0, "and picks nothing up, even standing on it");
    a.hold_nothing();
    a.press("use");
    a.tick(1);
    assert!(a.text("toast").contains("only watch"));

    // Still dead after leaving and coming back.
    a.vm.player_leave(&LeaveEvent { player: PLAYER, name: "Alice".into() });
    a.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    a.tick(1);
    assert!(a.flag("ghost"), "death outlasts a rejoin");
    assert!(!dig(&mut a));

    // An admin can raise the dead, themselves included.
    a.say("revive");
    a.tick(1);
    assert!(!a.flag("ghost"));
    assert_eq!(a.number("hp"), 27.0);
    assert!(dig(&mut a), "and the living dig again");
    println!("ok  adventure: one life, everything falls, a ghost touches nothing, and only an admin undoes it");
}

fn hud_check(r: &Rig) {
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
    let source = std::fs::read_to_string(dir.join("hud.lua")).unwrap();

    let mut states: Vec<(&str, Values)> = Vec::new();
    let live = r.huds.of(PLAYER);
    states.push(("live", live.clone()));

    let mut full = live.clone();
    for (k, v) in [
        ("hp", Value::Number(27.0)), ("food", Value::Number(18.0)), ("air", Value::Number(27.0)),
        ("air_show", Value::Flag(false)), ("temp_show", Value::Flag(false)), ("hurt", Value::Flag(false)),
        ("toast", Value::Text(String::new())), ("fx", Value::Text(String::new())),
    ] {
        full.insert(k.into(), v);
    }
    states.push(("full", full.clone()));

    let mut worst = full.clone();
    for (k, v) in [
        ("hp", Value::Number(4.0)), ("food", Value::Number(3.0)), ("air", Value::Number(5.0)),
        ("air_show", Value::Flag(true)), ("wet", Value::Flag(true)), ("temp", Value::Number(-0.93)),
        ("temp_show", Value::Flag(true)), ("cold", Value::Flag(true)), ("extreme", Value::Flag(true)),
        ("hurt", Value::Flag(true)), ("hungry", Value::Flag(true)), ("starving", Value::Flag(false)),
        ("fx", Value::Text("burning,poison,wither,radiation,regeneration,resistance,warmth,rested".into())),
        ("toast", Value::Text("You are having a very bad time of it, and it shows.".into())),
        ("shielded", Value::Flag(true)), ("shield", Value::Text("broken".into())),
    ] {
        worst.insert(k.into(), v);
    }
    states.push(("everything at once", worst));

    let mut thirds = full.clone();
    thirds.insert("hp".into(), Value::Number(13.0));
    thirds.insert("food".into(), Value::Number(7.0));
    thirds.insert("air".into(), Value::Number(16.0));
    thirds.insert("air_show".into(), Value::Flag(true));
    thirds.insert("temp".into(), Value::Number(0.6));
    thirds.insert("temp_show".into(), Value::Flag(true));
    thirds.insert("hot".into(), Value::Flag(true));
    thirds.insert("shield".into(), Value::Text("ok".into()));
    states.push(("partial hearts and cookies", thirds));

    let mut ghost = full.clone();
    ghost.insert("hp".into(), Value::Number(0.0));
    ghost.insert("ghost".into(), Value::Flag(true));
    states.push(("a ghost", ghost));

    let mut creative = full.clone();
    creative.insert("creative".into(), Value::Flag(true));
    creative.insert("toast".into(), Value::Text("Nothing here can hurt you.".into()));
    states.push(("creative", creative));

    states.push(("before any values", Values::new()));

    for (name, values) in states {
        let mut hud = HudVm::new(HudLimits::default()).unwrap();
        hud.load(MOD, &source).expect("hud.lua loads");
        let mut state = State::default();
        state.values.insert(MOD.into(), values);
        let faults = hud.draw(&state);
        assert!(faults.is_empty(), "hud faults on `{name}`: {faults:?}");
        assert!(!hud.is_disabled(MOD));
        let commands = hud.with_frame(|f| f.commands().len()).unwrap();
        println!("ok  hud `{name}`: {commands} draw commands");
        // With LIFE_HUD_DUMP set, write every state's resolved commands to a
        // directory, one file each, for tools/render_hud.py to rasterise.
        if let Ok(dump) = std::env::var("LIFE_HUD_DUMP") {
            use tiamot_core::hud::Command;
            let width = 1920.0;
            let mut lines = Vec::new();
            // Icons are named by hash on the wire; name them by file here.
            let icons = dir.join("icons");
            let mut by_hash = std::collections::HashMap::new();
            if let Ok(entries) = std::fs::read_dir(&icons) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if let Ok(bytes) = std::fs::read(&path) {
                        by_hash.insert(tiamot_core::content::hash_bytes(&bytes), path);
                    }
                }
            }
            hud.with_frame(|f| {
                for command in f.commands() {
                    match command {
                        Command::Rect { anchor, x, y, w, h, colour } => {
                            let (px, py) = anchor.resolve(width, *x, *y);
                            lines.push(format!("rect {px} {py} {w} {h} {} {} {} {}", colour[0], colour[1], colour[2], colour[3]));
                        }
                        Command::Text { anchor, x, y, text, size, colour } => {
                            let (px, py) = anchor.resolve(width, *x, *y);
                            lines.push(format!("text {px} {py} {size} {} {} {} {} {}", colour[0], colour[1], colour[2], colour[3], text));
                        }
                        Command::Image { anchor, x, y, w, h, hash } => {
                            let (px, py) = anchor.resolve(width, *x, *y);
                            let path = by_hash.get(hash).map(|p| p.display().to_string()).unwrap_or_default();
                            lines.push(format!("image {px} {py} {w} {h} {path}"));
                        }
                        _ => {}
                    }
                }
            });
            std::fs::create_dir_all(&dump).unwrap();
            let file = format!("{}.txt", name.replace(' ', "_"));
            std::fs::write(PathBuf::from(&dump).join(file), lines.join("
")).unwrap();
        }
        if name != "before any values" && name != "creative" {
            // Nine hearts and nine cookies at the least, each one image.
            assert!(commands >= 18, "the HUD drew almost nothing for `{name}`: {commands}");
        }
    }
}
