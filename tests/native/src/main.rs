// SPDX-FileCopyrightText: Iridesium
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

use tiamat_core::{
    BlockPos, MaterialId,
    ent::{self, Entity, EntityId, Owner, Transform},
    fluid::{self, Fluid, FluidId},
    hud::{self, State, Value, Values},
    identity::PlayerUuid,
    inventory::{self, Shape, Stack},
    light::{Light, LightSource},
    particle::{self, BadgeRequest, EmitRequest},
    script::{
        ActionEvent, ChatEvent, DialogEvent, EngineVm, HudLimits, HudVm, JoinEvent, LeaveEvent,
        ScriptVm, VmLimits, WorldEdit,
    },
    phys::Abilities,
    sight::{self, Looked, Reading, Sighting, Skip, Surface},
    sound::{self, LoopRequest, PlayRequest},
    storage::{self, Access as StorageAccess},
    ui::host::{self as uihost, ShowRequest},
};

const MOD: &str = "tiamat_default_life";
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
    /// Loops started and stopped, in order: "+id" and "-id".
    loops: Mutex<Vec<String>>,
}

impl sound::Access for Sounds {
    fn play(&self, request: &PlayRequest) -> u32 {
        self.plays.lock().unwrap().push(request.sound.clone());
        1
    }
    fn start_loop(&self, request: &LoopRequest) -> u32 {
        self.loops.lock().unwrap().push(format!("+{}", request.id));
        1
    }
    fn time_of_day(&self) -> f32 {
        *self.time.lock().unwrap()
    }
    fn stop_loop(&self, request: &sound::StopRequest) -> u32 {
        self.loops.lock().unwrap().push(format!("-{}", request.id));
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
        // The interface mod's hotbar has a HUD of its own; only ours is read.
        if mod_id != MOD {
            return true;
        }
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

/// Every particle burst and every badge, as sent.
#[derive(Default)]
struct Particles {
    bursts: Mutex<Vec<EmitRequest>>,
    badges: Mutex<Vec<BadgeRequest>>,
}

impl particle::Access for Particles {
    fn emit(&self, request: &EmitRequest) -> u32 {
        self.bursts.lock().unwrap().push(request.clone());
        1
    }
    fn show_over(&self, request: &BadgeRequest) -> u32 {
        self.badges.lock().unwrap().push(request.clone());
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
    /// Block ids by name, so a `set_block` from the mod lands in `blocks`
    /// and the mod can read back what it wrote (a crop growing, ground
    /// drying). Filled once the registries are frozen.
    names: Mutex<HashMap<String, MaterialId>>,
    /// Night in a cave: no sun anywhere, for the mushrooms.
    dark: Mutex<bool>,
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
        (occupancy != 0).then(|| Looked::Block {
            domain: "overworld".into(),
            cell: tiamat_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 2, z: z * 3 + 1 },
            material,
            face: [0, 1, 0],
        })
    }
    /// The engine's column walk, the slow way: down from `from` to the first
    /// occupied block. Enough for a crow looking for the ground or a tree.
    fn surface_at(&self, domain: &str, column: [i32; 2], from: i32, depth: u32, _: Skip) -> Option<Surface> {
        for y in (from - depth as i32..=from).rev() {
            if let Reading::Single { material, occupancy } = self.block_at(domain, BlockPos { x: column[0], y, z: column[1] })
                && occupancy != 0
            {
                return Some(Surface { y, material, occupancy, fluid: None });
            }
            if let Some(volume) = self.fluids.lock().unwrap().get(&(column[0], y, column[1]))
                && *volume > 0
            {
                return Some(Surface { y, material: MaterialId(0), occupancy: 0, fluid: Some(Fluid::new(FluidId(1), *volume)) });
            }
        }
        None
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
    fn set_fluid_at(&self, _: &str, pos: BlockPos, fluid: Fluid) -> bool {
        let mut fluids = self.fluids.lock().unwrap();
        if fluid.volume() == 0 {
            fluids.remove(&(pos.x, pos.y, pos.z));
        } else {
            fluids.insert((pos.x, pos.y, pos.z), fluid.volume());
        }
        true
    }
    /// The world's water is the one fluid here, number 1.
    fn fluid_id(&self, name: &str) -> Option<FluidId> {
        (name == "tiamat_default_world:water").then_some(FluidId(1))
    }
}

impl LightSource for World {
    fn light_at(&self, _: &str, _: BlockPos) -> Light {
        if *self.dark.lock().unwrap() { Light::DARK } else { Light::DAYLIGHT }
    }
}

impl World {
    /// An edit lands at once (the engine queues it a tick; nothing here
    /// depends on the gap), as the block named, or as air.
    fn apply(&self, pos: BlockPos, block: &str) {
        self.edits.lock().unwrap().push((pos, block.to_owned()));
        let key = (pos.x, pos.y, pos.z);
        if block == "engine:air" {
            // Explicit air, so a floor under it does not fill it back in.
            self.blocks.lock().unwrap().insert(key, (MaterialId(0), 0));
        } else if let Some(material) = self.names.lock().unwrap().get(block) {
            self.blocks.lock().unwrap().insert(key, (*material, 0x7FF_FFFF));
        }
    }
}

impl WorldEdit for World {
    fn set_block(&self, _: &str, pos: BlockPos, block: &str) -> bool {
        self.apply(pos, block);
        true
    }
    fn set_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
        true
    }
    fn merge_partial(&self, _: &str, pos: BlockPos, block: &str, _: u32) -> bool {
        self.apply(pos, block);
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
    /// What the fake world holds at a block, by name (or "air").
    fn block_name(&self, x: i32, y: i32, z: i32) -> String {
        let Reading::Single { material, occupancy } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else { return "?".into() };
        if occupancy == 0 {
            return "air".into();
        }
        self.materials.iter().find(|(_, m)| **m == material).map(|(n, _)| n.clone()).unwrap_or_else(|| format!("#{}", material.0))
    }
    /// One random tick for the block at a position, as the engine would give it.
    fn random_tick(&mut self, x: i32, y: i32, z: i32) {
        let Reading::Single { material, occupancy } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else { return };
        if occupancy == 0 {
            return;
        }
        let outcome = self.vm.random_tick(&tiamat_core::script::RandomTickEvent { pos: BlockPos { x, y, z }, material });
        assert!(outcome.faults.is_empty(), "mod faulted in random tick: {:?}", outcome.faults);
    }
    /// The stack in the player's hand, as the engine hands it to a hook.
    fn held_stack(&self) -> Option<Stack> {
        let held = (*self.inventory.held.lock().unwrap())?;
        self.inventory.views.lock().unwrap().get("player:main")?.iter().find(|s| s.material == held).cloned()
    }
    /// The place control at the block at a position, with what is held.
    fn use_at(&mut self, x: i32, y: i32, z: i32) -> tiamat_core::script::HookOutcome {
        let Reading::Single { material, .. } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else { panic!("no block") };
        *self.world.aimed.lock().unwrap() = Some((x, y, z));
        let held = self.held_stack();
        self.vm.use_block(&tiamat_core::script::UseEvent {
            player: PLAYER,
            domain: "overworld".into(),
            aim: Some(tiamat_core::script::UseAim { cell: tiamat_core::coords::SubNodePos::new(x * 3 + 1, y * 3 + 2, z * 3 + 1), material }),
            held,
        })
    }
    /// The place control on one of the mod's creatures, with what is held.
    fn use_entity(&mut self, id: u64) -> tiamat_core::script::HookOutcome {
        let held = self.held_stack();
        self.vm.use_entity(&tiamat_core::script::UseEntityEvent { player: PLAYER, target: EntityId(id), owner: None, held })
    }
    /// A dig of the block at a position, completed.
    fn dig_at(&mut self, x: i32, y: i32, z: i32) -> bool {
        let Reading::Single { material, .. } = sight::Access::block_at(&*self.world, "", BlockPos { x, y, z }) else { panic!("no block") };
        let allowed = self
            .vm
            .dig_complete(&tiamat_core::script::DigEvent {
                player: PLAYER,
                target: tiamat_core::SubNodePos { x: x * 3 + 1, y: y * 3 + 1, z: z * 3 + 1 },
                material,
                brush: tiamat_core::dig::Brush::Block,
            })
            .allowed;
        if allowed {
            self.world.apply(BlockPos { x, y, z }, "engine:air");
        }
        allowed
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
    rig_full(prelude, false)
}

/// The same, with Tiamat Default UI loaded first, as a world with both has
/// it: the interface mod's checkout must sit beside this repo as
/// `../Tiamat_Default_Inventory`.
fn rig_ui() -> Rig {
    rig_full("tdl_overrides = { climate = false, world_radius = 500 }
", true)
}

fn rig_full(prelude: &str, with_ui: bool) -> Rig {
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

    // A stand-in for the world mod, so the lava and the bramble exist, and so
    // there is a `biome_under` to ask: it answers one biome everywhere, the
    // grassland unless a test says `biome <id>` in chat (swallowed here).
    vm.load_mod(
        "tiamat_default_world",
        r#"
        for _, id in ipairs({ 'magma', 'bramble', 'dream_stone', 'grass', 'loam', 'leaf_litter', 'mud', 'dirt',
                'packed_dirt', 'dead_wood', 'snow', 'permafrost', 'oak_leaves', 'apple_log', 'fern', 'tall_grass',
                'ladys_mantle', 'ladys_mantle_bloom', 'mycelium', 'mulch', 'moss', 'black_mud', 'reeds', 'heather',
                'lichen', 'glow_cap', 'mushroom_cap', 'monstera', 'pitcher_plant', 'apple_leaves', 'apple_blossom',
                'poppy', 'water' }) do
            game.register_block{ id = id, passable = (id == 'fern' or id == 'tall_grass'
                or id == 'ladys_mantle' or id == 'ladys_mantle_bloom' or id == 'poppy' or id == 'heather') }
        end
        game.register_fluid{ id = "water", material = "water" }
        local here = "rolling_grasslands"
        local aliases = {}
        game.register_on_chat(function(e)
            local id = string.match(e.text, "^biome (%S+)$")
            if id then
                here = id
                return false
            end
            if e.text == "aliases" then
                local list = {}
                for block, dry in pairs(aliases) do list[#list + 1] = block .. ">" .. dry end
                table.sort(list)
                game.chat_to(e.player, table.concat(list, " "))
                return false
            end
        end)
        game.export{ version = 1, biome_under = function(x, y, z) return here end,
            add_soil_alias = function(block, dry) aliases[block] = dry return true end }
        "#,
        &dir,
    )
    .unwrap();
    vm.load_mod("core_gear", "game.register_item{ id = 'sword' }", &dir).unwrap();
    if with_ui {
        let ui = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../../Tiamat_Default_Inventory/mods/tiamat_default_ui");
        let source = std::fs::read_to_string(ui.join("init.lua")).expect("the interface mod beside this repo");
        vm.load_mod("tiamat_default_ui", &source, &ui).expect("the interface mod loads");
    }
    // As mod.toml's `optional_depends` has it: the world always, the
    // interface when it is here.
    let mut after = vec!["tiamat_default_world".to_owned()];
    if with_ui {
        after.push("tiamat_default_ui".to_owned());
    }
    vm.note_dependencies(MOD, &after);
    let init = format!("{prelude}{}", std::fs::read_to_string(dir.join("init.lua")).unwrap());
    vm.load_mod(MOD, &init, &dir).expect("the mod loads");
    // A stand-in for Tiamat Weather, which loads after this mod and puts its
    // burning block into our fire and heat tables through our exports, as
    // its fire.lua does. What it may not do is refused, not raised.
    vm.note_dependencies("tiamat_weather", &[MOD.to_owned()]);
    vm.load_mod(
        "tiamat_weather",
        r#"
        game.register_block{ id = "fire", passable = true }
        local life = game.exports("tiamat_default_life")
        assert(life and life.version == 1, "Life exports version 1")
        assert(life.add_contact_fire("tiamat_weather:fire", { damage = 1, ticks = 20, after = 40 }) == true)
        assert(life.add_heat_source("tiamat_weather:fire", 1.0) == true)
        assert(life.add_contact_fire("not a block", { damage = 1, ticks = 20, after = 40 }) == false)
        assert(life.add_contact_fire("tiamat_weather:fire", { damage = "lots" }) == false)
        assert(life.add_heat_source("tiamat_weather:fire", 7) == false)
        assert(life.set_alight({}, 40) == false)
        "#,
        &dir,
    )
    .expect("the weather stand-in loads and Life's exports answer it");
    // A stand-in for Tiamat Default Craft, which does not exist yet: it
    // registers what it cooks and forges through the exports, and its own
    // crop, and every wrong call is refused rather than raised.
    vm.note_dependencies("tiamat_default_craft", &[MOD.to_owned()]);
    vm.load_mod(
        "tiamat_default_craft",
        r#"
        game.register_item{ id = "stew" }
        game.register_item{ id = "axe" }
        game.register_item{ id = "scythe" }
        game.register_item{ id = "iron_hoe" }
        game.register_item{ id = "hay" }
        game.register_item{ id = "barley_seed" }
        game.register_item{ id = "barley" }
        game.register_block{ id = "barley_1", passable = true, drops = {} }
        game.register_block{ id = "barley_2", passable = true, drops = {} }
        local life = game.exports("tiamat_default_life")
        assert(life and life.version == 1)
        assert(life.add_food("tiamat_default_craft:stew", { food = 6, saturation = 4, effects = { { "hearty", 1200 } }, well_fed = true, sound = "drink" }) == true)
        assert(life.add_food("tiamat_default_craft:stew", { effects = { { "not_an_effect", 10 } } }) == false)
        assert(life.add_food("nobody:nothing", { food = 1 }) == false)
        assert(life.add_weapon("tiamat_default_craft:axe", 4) == true)
        assert(life.add_weapon("tiamat_default_craft:axe", 0) == false)
        assert(life.add_drop("cow", "tiamat_default_craft:hay", 1, 1) == true)
        assert(life.add_drop("dragon", "tiamat_default_craft:hay", 1, 1) == false)
        assert(life.add_feed("tiamat_default_craft:hay", { "cow", "sheep" }) == true)
        assert(life.add_feed("tiamat_default_craft:hay", { "cow", "dragon" }) == false)
        assert(life.add_harvest_tool("tiamat_default_craft:scythe", 3) == true)
        assert(life.add_harvest_tool("tiamat_default_craft:scythe", 50) == false)
        assert(life.add_tilling_tool("tiamat_default_craft:iron_hoe") == true)
        assert(life.add_tilling_tool("tiamat_default_craft:missing") == false)
        assert(life.add_crop{ id = "barley", stages = { "tiamat_default_craft:barley_1", "tiamat_default_craft:barley_2" },
            seed = "tiamat_default_craft:barley_seed", produce = "tiamat_default_craft:barley", soil = "tilled", light = "sun" } == true)
        assert(life.add_crop{ id = "barley", stages = { "tiamat_default_craft:barley_1" },
            seed = "tiamat_default_craft:barley_seed", produce = "tiamat_default_craft:barley", soil = "tilled" } == false)
        assert(life.drop({ x = 1, y = 2 }, { material = "tiamat_default_craft:hay", count = 1 }) == nil)
        game.register_on_chat(function(e)
            if e.text == "craftdrop" then
                assert(life.drop({ x = 100.5, y = 64.5, z = 100.5 }, { material = "tiamat_default_craft:hay", count = 2 }) ~= nil)
                return false
            end
        end)
        "#,
        &dir,
    )
    .expect("the craft stand-in loads and Life's exports answer it");
    vm.freeze().unwrap();
    // The server hands out fluid numbers once every mod has loaded; the
    // world's water is 1 here, the number the fake world answers with.
    vm.set_fluid_ids(&[("tiamat_default_world:water".to_owned(), FluidId(1))]);

    // Noon, so nothing is cold unless a scenario makes it so.
    *sounds.time.lock().unwrap() = 0.5;
    let materials: HashMap<String, MaterialId> = vm.registered_blocks().into_iter().collect();
    *world.names.lock().unwrap() = materials.clone();
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
    r.hold("tiamat_default_life:antidote");
    r.press("use");
    r.tick(1);
    assert!(!r.text("fx").contains("poison"), "the antidote cleared it");
    assert_eq!(r.inventory.units_of("player:main", r.material("tiamat_default_life:antidote")), 27 * 3);
    println!("ok  poison to one point, antidote cured it and was spent");

    // Eating: starve, then an apple is two cookies and a bite of buffer.
    r.say("heal");
    r.say("starve 4");
    r.tick(1);
    assert_eq!(r.number("food"), 4.0);
    assert!(r.flag("hungry"));
    r.hold("tiamat_default_life:apple");
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
    let before = r.inventory.units_of("player:main", r.material("tiamat_default_life:apple"));
    r.press("use");
    r.tick(1);
    assert_eq!(r.inventory.units_of("player:main", r.material("tiamat_default_life:apple")), before);
    assert!(r.text("toast").contains("full"));
    println!("ok  eating an apple, and being too full to");

    // Right mouse with food in hand eats it, as X does: at a block, and at
    // nothing (open sky; engine protocol 76, `anywhere`). Raw meat feeds, and
    // sits badly.
    r.say("heal");
    r.say("starve 4");
    r.hold("tiamat_default_life:raw_meat");
    r.tick(16);
    let meat = r.material("tiamat_default_life:raw_meat");
    let held = r.inventory.views.lock().unwrap()["player:main"].iter().find(|s| s.material == meat).cloned();
    let at_block = Some(tiamat_core::script::UseAim {
        cell: tiamat_core::coords::SubNodePos::new(300, 189, 300),
        material: r.material("tiamat_default_world:grass"),
    });
    for (aim, food, where_) in [(at_block, 7.0, "at a block"), (None, 10.0, "at open sky")] {
        let outcome = r.vm.use_block(&tiamat_core::script::UseEvent {
            player: PLAYER,
            domain: "overworld".into(),
            aim,
            held: held.clone(),
        });
        r.tick(16);
        assert_eq!(r.number("food"), food, "raw meat eaten {where_}, three more: {outcome:?}");
    }
    assert!(r.text("fx").contains("poison"), "and it sits badly");
    r.tick(150);
    r.say("heal");
    r.say("feed");
    r.tick(1);
    println!("ok  right mouse eats what is in hand, at a block or at open sky: raw meat feeds, and poisons");

    // A hot stew warms: the warmth effect shows and the body drifts warm.
    r.say("starve 10");
    r.hold("tiamat_default_life:hot_stew");
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
    let dream = r.material("tiamat_default_world:dream_stone");
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
    let coat = Stack::new(r.material("tiamat_default_life:warm_coat"), 27).unwrap();
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

    // Drowning: the body goes under, and the sea closes over your head.
    r.sounds.loops.lock().unwrap().clear();
    r.entities.body(|b| b.submerged = 1.0);
    r.tick(20);
    assert!(
        r.sounds.loops.lock().unwrap().iter().any(|l| l.ends_with("underwater") && l.starts_with('+')),
        "the underwater loop starts as the head goes under"
    );
    assert!(r.flag("wet"));
    assert!(r.flag("air_show"));
    assert!(r.number("air") < 27.0, "air started draining: {}", r.number("air"));
    r.tick(13 * 27 + 20 * 3 + 10);
    assert_eq!(r.number("air"), 0.0);
    assert!(r.number("hp") <= 27.0 - 9.0, "drowning at a heart a second: {}", r.number("hp"));
    r.entities.body(|b| b.submerged = 0.0);
    r.tick(20);
    assert_eq!(r.number("air"), 27.0, "air came straight back");
    {
        let loops = r.sounds.loops.lock().unwrap();
        let started = loops.iter().filter(|l| l.starts_with('+') && l.ends_with("underwater")).count();
        assert_eq!(started, 1, "started once, not every tick: {loops:?}");
        assert!(loops.last().is_some_and(|l| l.starts_with('-') && l.ends_with("underwater")), "and stopped on surfacing: {loops:?}");
    }
    assert!(r.plays("gasp") >= 1);
    println!("ok  drowned to {} points, surfaced and gasped", r.number("hp"));

    // Lava under the feet: contact damage and burning after.
    r.say("heal");
    r.tick(1);
    let magma = r.material("tiamat_default_world:magma");
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

    // Weather's fire, put in the fire table through our export: it hurts,
    // sets you alight, and flames show on the body while it burns.
    r.say("heal");
    r.tick(1);
    let fire = r.material("tiamat_weather:fire");
    let flames = r.particles.bursts.lock().unwrap().len();
    r.world.put(100, 64, 100, fire);
    r.tick(45);
    assert!(r.number("hp") < 27.0, "Weather's fire burns: {}", r.number("hp"));
    assert!(r.text("fx").contains("burning"), "and sets you alight");
    assert!(r.particles.bursts.lock().unwrap().len() > flames, "flames on the body for all to see");
    r.world.clear();
    r.tick(200);
    assert!(!r.text("fx").contains("burning"), "and it goes out");
    println!("ok  Weather's fire, through the export, burned and set a body alight");

    // Death: a scatter on the ground, a move, a screen, everything reset.
    r.say("heal");
    r.tick(1);
    let apples_before = r.inventory.units_of("player:main", r.material("tiamat_default_life:apple"));
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
    let apples_after = r.inventory.units_of("player:main", r.material("tiamat_default_life:apple"));
    assert!(apples_after < apples_before, "a share of the apples was dropped");
    assert!(r.plays("death") >= 1);
    // And the scatter is picked back up by walking over it.
    r.tick(90);
    let apples_back = r.inventory.units_of("player:main", r.material("tiamat_default_life:apple"));
    assert_eq!(apples_back, apples_before, "walked over the drops and picked them all back up");
    println!("ok  died, dropped a third, respawned shielded, picked it back up");

    // The punch veto is not a veto: another body hitting the player hurts.
    r.tick(70);
    let attacker = PlayerUuid::from_bytes([9; 32]);
    let target = r.entities.0.lock().unwrap().player;
    r.vm.punch(&tiamat_core::script::PunchEvent {
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
    let bed = r.material("tiamat_default_life:bed");
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
    let berries = r.material("tiamat_default_life:berries");
    let before = r.inventory.units_of("player:main", berries);
    r.vm.dig_complete(&tiamat_core::script::DigEvent {
        player: PLAYER,
        target: tiamat_core::SubNodePos { x: 300, y: 190, z: 300 },
        material: r.material("tiamat_default_world:bramble"),
        brush: tiamat_core::dig::Brush::Block,
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
        event: tiamat_core::proto::DialogEvent::Closed,
    });
    for request in r.dialogs.0.lock().unwrap().iter() {
        tiamat_core::ui::check(&request.tree, tiamat_core::ui::Limits::default()).expect("a valid tree");
    }
    println!("ok  the wardrobe and the death screen are valid dialog trees");

    mob_check(&mut r);
    farm_check(&mut r);
    ui_check();
    climate_check();
    modes_check();

    // The HUD script, drawn by the client's own VM, on several states.
    hud_check(&r);

    println!("PASS: tiamat_default_life runs through the engine VM end to end");
}

fn mob_check(r: &mut Rig) {
    // A grass plain under everything, at noon, and nothing about yet.
    let grass = r.material("tiamat_default_world:grass");
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
        // Every kind is its own model now; none is the named stand-in.
        let model = mob.model.as_deref().unwrap_or("");
        assert!(model.starts_with("tiamat_default_life:"), "its own body, not a stand-in: {model}");
        assert_eq!(mob.nametag, None, "a cow looks like a cow and needs no name over it");
        assert!(mob.health.is_some(), "a mob has health");
        let [_, y, _] = mob.transform.to_world();
        if mob.model.as_deref() == Some("tiamat_default_life:crow") {
            assert!(y > 70.0, "crows come in already flying: {y}");
        } else {
            assert!((y - 64.0).abs() < 0.01, "standing on the floor, not in it: {y}");
        }
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
    r.particles.badges.lock().unwrap().clear();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
    r.tick(1);
    assert_eq!(r.mobs()[0].1.health.unwrap().current, 9, "a fist is one point");
    // No hearts over it: a row of them over every mob hit was a nuisance, and
    // `mob_hearts` is off.
    assert!(r.particles.badges.lock().unwrap().is_empty(), "no health bar over a mob");
    let meat = r.material("tiamat_default_life:raw_meat");
    let meat_before = r.inventory.units_of("player:main", meat);
    r.hold("core_gear:sword");
    for _ in 0..2 {
        r.tick(12);
        r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
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
    println!("ok  a cow punched ran off with no hearts over it, slain by sword, and its meat picked up");

    // A cow's pace is the ENTITY's, not a gait's: the engine walks it at the
    // multiple the mod set, and jumping is the engine's own business now.
    r.say("cull");
    r.say("spawn cow 1");
    r.tick(1);
    let (cow, _) = r.mobs()[0].clone();
    let speed_of = |r: &Rig| r.entities.0.lock().unwrap().entities[&cow].speed;
    // Until it sets off: its first pause is a roll of its dice.
    for _ in 0..400 {
        r.tick(1);
        if (speed_of(&r) - 1.0).abs() > 1e-6 {
            break;
        }
    }
    let ambling = speed_of(&r);
    assert!((ambling - 1.1 / 4.3).abs() < 1e-4, "a cow ambles at 1.1 blocks a second: {ambling}");
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
    r.tick(2);
    let fleeing = speed_of(&r);
    assert!((fleeing - 2.8 / 5.6).abs() < 1e-4, "and runs at 2.8: {fleeing}");
    assert_eq!(r.entities.0.lock().unwrap().entities[&cow].anim, tiamat_core::ent::AnimTag::RUN,
        "a fleeing cow plays its run");
    r.say("mob");
    assert!(r.said().contains("flee") && r.said().contains("clip run"), "{}", r.said());
    r.say("cull");
    r.tick(1);
    println!("ok  a cow ambles and runs at its own pace, through the engine's steering");

    // A cow never jumps at a rise; stuck in one place (a hole), it hops
    // once, then walks again, and gives up on the spot if that did not work.
    r.say("cull");
    r.say("spawn cow 1");
    r.tick(1);
    let (cow, _) = r.mobs()[0].clone();
    let (mut walked, mut hops, mut last_hop, mut back_to_back) = (false, 0, None::<u32>, false);
    for t in 0..400u32 {
        {
            let mut store = r.entities.0.lock().unwrap();
            let body = store.entities.get_mut(&cow).unwrap();
            body.on_ground = true;
            body.velocity.0 = [0.0; 3];
        }
        r.put_mob(cow, 90.5, 64.0, 90.5);
        r.tick(1);
        let drive = r.entities.0.lock().unwrap().entities[&cow].drive;
        walked |= drive.walk != [0.0, 0.0];
        if drive.jump {
            hops += 1;
            back_to_back |= last_hop == Some(t.wrapping_sub(1));
            last_hop = Some(t);
        }
    }
    assert!(walked, "it tried to walk");
    assert!(hops >= 1, "stuck, it hops out");
    assert!(hops <= 400 / 60 + 1, "but only now and then, not a hare: {hops} hops");
    assert!(!back_to_back, "and one tick at a time");
    r.say("cull");
    r.tick(1);
    println!("ok  a cow never jumps at a rise, and hops once when stuck: {hops} hops in 400 ticks of being stuck");

    // A bear leaves you be, standing right beside it. Hurt it and it turns:
    // it comes for you and swipes, playing
    // its swing clip, for seven points a blow.
    r.say("heal");
    r.say("spawn bear 1");
    r.tick(1);
    let (bear, body) = r.mobs()[0].clone();
    assert_eq!(body.model.as_deref(), Some("tiamat_default_life:bear"), "a bear is its own model");
    r.put_mob(bear, 102.0, 64.0, 100.5);
    r.tick(60);
    assert_eq!(r.number("hp"), 27.0, "an unprovoked bear harms nobody");
    r.say("mob");
    assert!(!r.said().contains("hunt"), "and hunts nobody: {}", r.said());
    r.particles.badges.lock().unwrap().clear();
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(bear), owner: None });
    r.tick(1);
    assert!(r.particles.badges.lock().unwrap().is_empty(), "no health bar over a bear either");
    r.say("mob");
    assert!(r.said().contains("hunt"), "a hurt bear hunts: {}", r.said());
    let mut swiped = false;
    for _ in 0..40 {
        r.put_mob(bear, 101.5, 64.0, 100.5);
        r.tick(1);
        swiped |= r.entities.0.lock().unwrap().entities[&bear].anim == tiamat_core::ent::AnimTag::SWING;
    }
    assert!(r.number("hp") <= 27.0 - 7.0, "mauled: {}", r.number("hp"));
    assert!(swiped, "and the blow plays its swing");
    r.say("cull");
    r.say("heal");
    r.tick(1);
    println!("ok  a bear ignores you until hurt, then hunts and mauls you, swinging");

    // An animal set alight panics and burns; one that stands in fire until
    // it dies leaves its meat cooked.
    r.say("spawn cow 1");
    r.tick(1);
    let (cow, _) = r.mobs()[0].clone();
    let flames = r.particles.bursts.lock().unwrap().len();
    r.say("ignite 60");
    r.tick(2);
    r.say("mob");
    assert!(r.said().contains("panic"), "a cow on fire panics: {}", r.said());
    r.tick(60);
    assert!(r.mobs()[0].1.health.unwrap().current < 10, "and burns");
    assert!(r.particles.bursts.lock().unwrap().len() > flames, "in flames");
    let fire = r.material("tiamat_weather:fire");
    r.world.put(90, 64, 90, fire);
    for _ in 0..800 {
        if r.mobs().is_empty() {
            break;
        }
        r.put_mob(cow, 90.5, 64.0, 90.5);
        r.tick(1);
    }
    assert!(r.mobs().is_empty(), "burned to death");
    let cooked = r.material("tiamat_default_life:cooked_meat");
    assert!(r.entities.items(MOD).iter().any(|s| s.material == cooked), "and its meat is cooked");
    r.world.clear();
    // The meat, gone too, so the scenarios after this start clean.
    r.entities.0.lock().unwrap().entities.retain(|_, e| e.item.is_none());
    r.say("cull");
    r.tick(1);
    println!("ok  a cow set alight panicked and burned, and burned to death its meat was cooked");

    // Hit, a creature spins round quickly to run rather than flipping about
    // in one tick: never more than the turn rate (0.6) in a tick, and when
    // the way it must go is well behind it, it turns on the spot first. Two
    // starting yaws half a turn apart: one of them is behind the way it runs.
    let wrap = |d: f32| (d + std::f32::consts::PI).rem_euclid(std::f32::consts::TAU) - std::f32::consts::PI;
    let mut spun_on_the_spot = false;
    for start in [0.0f32, std::f32::consts::PI] {
        r.say("cull");
        r.say("spawn cow 1");
        r.tick(1);
        let (cow, _) = r.mobs()[0].clone();
        {
            let mut store = r.entities.0.lock().unwrap();
            let e = store.entities.get_mut(&cow).unwrap();
            e.transform = Transform::from_world(104.5, 64.0, 100.5);
            e.transform.yaw = start;
            e.on_ground = true;
        }
        r.hold_nothing();
        r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(cow), owner: None });
        let mut last = start;
        for _ in 0..12 {
            r.tick(1);
            let (yaw, walk) = {
                let store = r.entities.0.lock().unwrap();
                let e = &store.entities[&cow];
                (e.transform.yaw, e.drive.walk)
            };
            let turned = wrap(yaw - last).abs();
            assert!(turned <= 0.6 + 1e-3, "a hit cow turns at most 0.6 a tick, not {turned}");
            spun_on_the_spot |= turned > 0.3 && walk == [0.0, 0.0];
            last = yaw;
        }
    }
    assert!(spun_on_the_spot, "hit from the way it faces, it spins round on the spot before it runs");
    r.say("cull");
    r.tick(1);
    println!("ok  a cow hit spins round, at most 0.6 a tick, on the spot when it must run the other way");

    // A bat at night: it hunts the player, bites, and wheels away.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("heal");
    r.say("spawn bat 1");
    r.tick(1);
    let bats = r.mobs();
    assert_eq!(bats.len(), 1, "one bat");
    let (bat, body) = bats[0].clone();
    assert_eq!(body.model.as_deref(), Some("tiamat_default_life:bat"), "a bat is its own model");
    let bites = r.plays("bite");
    // Put it on the shoulder: the fake world has no physics to fly it there.
    // It flutters on its run clip, and bites on its swing.
    let (mut fluttered, mut swung) = (false, false);
    for _ in 0..25 {
        r.put_mob(bat, 101.0, 65.5, 100.5);
        r.tick(1);
        let anim = r.entities.0.lock().unwrap().entities[&bat].anim;
        assert!(anim == tiamat_core::ent::AnimTag::RUN || anim == tiamat_core::ent::AnimTag::SWING,
            "a bat in the air flutters or bites: {anim:?}");
        fluttered |= anim == tiamat_core::ent::AnimTag::RUN;
        swung |= anim == tiamat_core::ent::AnimTag::SWING;
    }
    assert!(r.number("hp") < 27.0, "bitten: {}", r.number("hp"));
    assert!(r.plays("bite") > bites);
    assert!(fluttered && swung, "it flutters, and its bite plays its swing");
    // Daylight, and it loses interest.
    *r.sounds.time.lock().unwrap() = 0.5;
    r.say("heal");
    r.put_mob(bat, 101.0, 65.5, 100.5);
    r.tick(60);
    assert_eq!(r.number("hp"), 27.0, "a bat in daylight is harmless");
    println!("ok  a bat bit at night and left off by day");
    r.say("cull");
    r.tick(1);

    // A bat, by day, well away from the player: with a ceiling over it, it
    // goes up and hangs by its feet from the underside, on its idle clip,
    // and lets go and flutters when hurt. On open ground it crawls and eats,
    // and never plays its hanging clip there.
    let stone = r.material("tiamat_default_world:grass");
    for x in 83..=87 {
        for z in 83..=87 {
            r.world.put(x, 72, z, stone);
        }
    }
    r.say("spawn bat 1");
    r.tick(1);
    let (bat, _) = r.mobs()[0].clone();
    let anim_of = |r: &Rig, id: u64| r.entities.0.lock().unwrap().entities[&id].anim;
    let y_of = |r: &Rig, id: u64| r.entities.0.lock().unwrap().entities[&id].transform.to_world()[1];
    let mut roosted = false;
    for _ in 0..4000 {
        r.put_mob(bat, 85.5, 71.3, 85.5);
        r.tick(1);
        if anim_of(&r, bat) == tiamat_core::ent::AnimTag::IDLE {
            roosted = true;
            break;
        }
    }
    assert!(roosted, "a bat under a ceiling goes to roost");
    let hung = y_of(&r, bat);
    assert!((hung - 72.1).abs() < 0.01, "hanging by its feet from the block's underside: {hung}");
    r.tick(40);
    assert_eq!(anim_of(&r, bat), tiamat_core::ent::AnimTag::IDLE, "and it stays hung");
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(bat), owner: None });
    r.tick(2);
    let woken = anim_of(&r, bat);
    assert!(woken == tiamat_core::ent::AnimTag::RUN || woken == tiamat_core::ent::AnimTag::SWING,
        "hurt, it lets go and flies: {woken:?}");
    r.say("cull");
    r.tick(1);
    r.world.clear();

    let grass = r.material("tiamat_default_world:grass");
    *r.world.floor.lock().unwrap() = Some((63, grass));
    r.say("spawn bat 1");
    r.tick(1);
    let (bat, _) = r.mobs()[0].clone();
    let mut ate = false;
    for _ in 0..4000 {
        r.put_mob(bat, 85.5, 64.0, 85.5);
        r.entities.0.lock().unwrap().entities.get_mut(&bat).unwrap().on_ground = true;
        r.tick(1);
        let anim = anim_of(&r, bat);
        assert_ne!(anim, tiamat_core::ent::AnimTag::IDLE, "no hanging on open ground");
        if anim == tiamat_core::ent::AnimTag::SNEAK {
            ate = true;
            break;
        }
    }
    assert!(ate, "a bat comes down to the ground now and then, and eats there");
    r.say("cull");
    r.tick(1);
    *r.world.floor.lock().unwrap() = None;
    println!("ok  a bat roosts hanging under a ceiling, lets go when hurt, and crawls and eats on the ground");

    // A swarm of bats: a dozen in one, each remembering its swarm with the
    // world. It leaves you be, even at night, until you hit one of it; then
    // the whole swarm comes for you.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("heal");
    r.say("spawn swarm");
    r.tick(1);
    let swarm: Vec<u64> = r.mobs().iter().map(|(id, _)| *id).collect();
    assert_eq!(swarm.len(), 12, "a swarm is a dozen");
    for id in &swarm {
        assert!(r.storage.get(MOD, &format!("swarm:{id}")).is_some(), "each bat remembers its swarm");
    }
    for _ in 0..60 {
        for id in &swarm {
            r.put_mob(*id, 101.0, 65.5, 100.5);
        }
        r.tick(1);
    }
    assert_eq!(r.number("hp"), 27.0, "a swarm left alone leaves you alone, even at night");
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(swarm[3]), owner: None });
    let bites = r.plays("bite");
    for _ in 0..20 {
        for id in &swarm {
            r.put_mob(*id, 101.0, 65.5, 100.5);
        }
        r.tick(1);
    }
    let bitten = r.plays("bite") - bites;
    assert!(bitten >= 3, "hit one and the swarm bites, more than the one: {bitten} bites");
    r.say("cull");
    r.tick(1);
    for id in &swarm {
        assert!(r.storage.get(MOD, &format!("swarm:{id}")).is_none(), "culled, the swarm is forgotten");
    }
    *r.sounds.time.lock().unwrap() = 0.5;
    r.say("heal");
    println!("ok  a bat swarm leaves you be until one is hit, then {bitten} bites from the swarm");

    // A ghost: at night, a long way off, it stays; anyone within forty
    // blocks and it is gone in a breath of mist. By day it does not stay.
    let ghost_near = |r: &mut Rig, x: f64, ticks: u32| -> bool {
        r.say("spawn ghost 1");
        let ghost = r.mobs().iter().map(|(id, _)| *id).max().expect("a ghost");
        for _ in 0..ticks {
            if !r.mobs().iter().any(|(id, _)| *id == ghost) {
                return false;
            }
            r.put_mob(ghost, x, 64.0, 100.5);
            r.tick(1);
        }
        r.mobs().iter().any(|(id, _)| *id == ghost)
    };
    *r.sounds.time.lock().unwrap() = 0.9;
    assert!(ghost_near(r, 160.5, 40), "sixty blocks off at night, a ghost stays");
    r.say("cull");
    let bursts = r.particles.bursts.lock().unwrap().len();
    assert!(!ghost_near(r, 130.5, 40), "thirty blocks off, it is gone");
    assert!(r.particles.bursts.lock().unwrap().len() > bursts, "in a breath of mist");
    r.say("cull");
    *r.sounds.time.lock().unwrap() = 0.5;
    assert!(!ghost_near(r, 160.5, 40), "and by day, however far off, it is gone");
    r.say("cull");
    r.tick(1);
    println!("ok  a ghost keeps forty blocks off: far off at night it stays, nearer or by day it is gone in mist");

    // A swamp hag in the dark: she comes for you, and her staff poisons.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("heal");
    r.say("spawn swamp_hag 1");
    r.tick(1);
    let hag = r.mobs().iter().map(|(id, _)| *id).max().expect("a hag");
    for _ in 0..60 {
        r.put_mob(hag, 101.5, 64.0, 100.5);
        r.tick(1);
    }
    assert!(r.number("hp") < 27.0, "struck by her staff: {}", r.number("hp"));
    assert!(r.text("fx").contains("poison"), "and poisoned");
    r.say("cull");
    r.tick(150);
    assert!(!r.text("fx").contains("poison"), "and the poison wears off");
    r.say("heal");
    r.tick(1);
    *r.sounds.time.lock().unwrap() = 0.5;
    println!("ok  a swamp hag in the dark strikes with her staff, and it poisons");

    // A cave troll: come near and it lumbers off; hit it and it hunts you,
    // and keeps on, remembered with the world.
    r.say("heal");
    r.say("spawn cave_troll 1");
    r.tick(1);
    let troll = r.mobs().iter().map(|(id, _)| *id).max().expect("a troll");
    // Five blocks off: it walks off (the engine steers it, so what it is
    // doing is read back with `mob`).
    {
        let mut store = r.entities.0.lock().unwrap();
        let e = store.entities.get_mut(&troll).unwrap();
        e.transform = Transform::from_world(105.5, 64.0, 100.5);
        e.on_ground = true;
    }
    r.tick(30);
    r.say("mob cave_troll");
    assert!(r.said().contains("withdraw"), "five blocks off, a troll walks away: {}", r.said());
    assert_eq!(r.number("hp"), 27.0, "and harms nobody");
    // Hit, it hunts you; long after a hunt would have run out, it still is.
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(troll), owner: None });
    r.tick(1);
    assert!(r.storage.get(MOD, &format!("grudge:{troll}")).is_some(), "it remembers who hit it");
    r.say("god");
    for _ in 0..600 {
        r.put_mob(troll, 112.5, 64.0, 100.5);
        r.tick(1);
    }
    r.say("god");
    r.put_mob(troll, 112.5, 64.0, 100.5);
    r.tick(12);
    r.say("mob cave_troll");
    assert!(r.said().contains("hunt"), "six hundred ticks on, it is still coming for you: {}", r.said());
    r.say("cull");
    r.tick(1);
    assert!(r.storage.get(MOD, &format!("grudge:{troll}")).is_none(), "culled, the grudge is forgotten");
    r.say("heal");
    println!("ok  a cave troll walks off from anyone near, and hit, hunts them for good");

    // The scarecrow: it stands where it is put and does not move; hit it and
    // it follows at a distance, never striking; against an apple tree it eats.
    let grass = r.material("tiamat_default_world:grass");
    *r.world.floor.lock().unwrap() = Some((63, grass));
    r.say("heal");
    r.say("spawn scarecrow 1");
    r.tick(1);
    let (scarecrow, body) = r.mobs().into_iter().find(|(_, e)| e.model.as_deref() == Some("tiamat_default_life:scarecrow")).expect("a scarecrow");
    assert_eq!(body.model.as_deref(), Some("tiamat_default_life:scarecrow"));
    let drive_of = |r: &Rig| r.entities.0.lock().unwrap().entities[&scarecrow].drive;
    let anim_of = |r: &Rig| r.entities.0.lock().unwrap().entities[&scarecrow].anim;
    let yaw_of = |r: &Rig| r.entities.0.lock().unwrap().entities[&scarecrow].transform.yaw;
    let put = |r: &Rig, x: f64, z: f64| {
        r.put_mob(scarecrow, x, 64.0, z);
        r.entities.0.lock().unwrap().entities.get_mut(&scarecrow).unwrap().on_ground = true;
    };
    for _ in 0..200 {
        put(&r, 110.5, 100.5);
        r.tick(1);
        assert_eq!(drive_of(&r).walk, [0.0, 0.0], "a scarecrow nobody has hit does not move");
    }
    r.hold_nothing();
    r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(scarecrow), owner: None });
    r.tick(1);
    let hp = r.number("hp");
    // Far off (the player is at 100.5, 100.5): it comes on, once it has
    // spun round to face the way (a few ticks at the turn rate; putting it
    // there resets its yaw, so it is put once and left to turn).
    put(&r, 160.5, 100.5);
    r.tick(10);
    let toward = drive_of(&r).walk;
    assert!(toward[0] < 0.0, "sixty blocks off, it comes toward you: {toward:?}");
    // Close: it backs away, still facing you, without turning first.
    put(&r, 106.5, 100.5);
    r.tick(3);
    let away = drive_of(&r).walk;
    assert!(away[0] > 0.0, "six blocks off, it steps back: {away:?}");
    // Between: it stands, and turns to watch you.
    put(&r, 127.5, 100.5);
    r.tick(3);
    assert_eq!(drive_of(&r).walk, [0.0, 0.0], "twenty-seven blocks off, it stands");
    let _ = yaw_of(&r);
    // It never strikes, however long it keeps you company.
    for _ in 0..200 {
        put(&r, 104.0, 100.5);
        r.tick(1);
    }
    assert_eq!(r.number("hp"), hp, "a scarecrow never hurts you");
    // Against an apple tree, it stops and eats.
    let apple = r.material("tiamat_default_world:apple_log");
    r.world.put(110, 64, 100, apple);
    let mut ate = false;
    for _ in 0..40 {
        put(&r, 109.5, 100.5);
        r.tick(1);
        ate |= anim_of(&r) == tiamat_core::ent::AnimTag::SNEAK;
    }
    assert!(ate, "an apple tree to hand, it eats");
    r.world.clear();
    // Whom it follows is kept with the world, and forgotten when it dies.
    let key = format!("stalk:{scarecrow}");
    assert!(r.storage.get(MOD, &key).is_some(), "it remembers whom it follows");
    r.hold("core_gear:sword");
    for _ in 0..6 {
        r.vm.punch(&tiamat_core::script::PunchEvent { attacker: PLAYER, target: EntityId(scarecrow), owner: None });
        r.tick(12);
    }
    assert!(r.mobs().iter().all(|(id, _)| *id != scarecrow), "a sword ends it");
    assert!(r.storage.get(MOD, &key).is_none(), "and it forgets you");
    r.hold_nothing();
    r.say("cull");
    r.tick(1);
    *r.world.floor.lock().unwrap() = None;
    println!("ok  a scarecrow stands still, then hit follows at eighteen to thirty-six blocks, never strikes, eats at an apple tree");

    // A crow, by day and by night. The fake world has no physics, so it is
    // held where the test wants it, well away from the player, and `plan`
    // puts it on each of its flight plans in turn.
    let grass = r.material("tiamat_default_world:grass");
    let leaves = r.material("tiamat_default_world:oak_leaves");
    *r.world.floor.lock().unwrap() = Some((63, grass));
    r.say("spawn crow 1");
    r.tick(1);
    let (crow, body) = r.mobs()[0].clone();
    assert_eq!(body.model.as_deref(), Some("tiamat_default_life:crow"), "a crow is its own model");
    let hold = |r: &Rig, y: f64, ground: bool| {
        r.put_mob(crow, 85.5, y, 85.5);
        r.entities.0.lock().unwrap().entities.get_mut(&crow).unwrap().on_ground = ground;
    };
    let clip = |r: &Rig| r.entities.0.lock().unwrap().entities[&crow].anim;
    let heading = |r: &mut Rig| {
        r.say("mob crow");
        r.said()
    };
    // In the air it keeps a plan, crossing or circling, and every clip it
    // plays is a wing clip: gliding with its wings out, beating them now and then.
    // Held above any cruising height (ten to eighteen blocks over the floor
    // at 63), so it is coming down and glides, beating its wings now and then.
    let (mut soared, mut flapped) = (false, false);
    for _ in 0..600 {
        hold(&r, 95.0, false);
        r.tick(1);
        let anim = clip(&r);
        assert!(anim == tiamat_core::ent::AnimTag::RUN || anim == tiamat_core::ent::AnimTag::SWING,
            "a crow in the air soars or flaps: {anim:?}");
        soared |= anim == tiamat_core::ent::AnimTag::RUN;
        flapped |= anim == tiamat_core::ent::AnimTag::SWING;
    }
    assert!(soared && flapped, "it glides with its wings out, and beats them now and then");
    let said = heading(r);
    assert!(
        ["transit", "circle", "to_tree", "land"].iter().any(|plan| said.contains(plan)),
        "keeping a flight plan: {said}"
    );
    r.say("plan circle");
    hold(&r, 80.0, false);
    r.tick(1);
    assert!(heading(r).contains("circle"), "it wheels when told");

    // Into a tree: over a canopy, it picks a branch and settles there, and sits.
    *r.world.floor.lock().unwrap() = Some((63, leaves));
    r.say("plan tree");
    assert!(r.said().contains("to_tree"), "it picks a tree: {}", r.said());
    hold(&r, 64.0, true);
    r.tick(1);
    for _ in 0..40 {
        hold(&r, 64.0, true);
        r.tick(1);
        assert_eq!(clip(&r), tiamat_core::ent::AnimTag::IDLE, "sitting in the tree");
    }
    assert!(heading(r).contains("treed"), "and stays there");
    // Walk up to it, and it is off, beating its wings.
    r.put_mob(crow, 95.5, 64.0, 100.5);
    r.tick(12);
    assert_eq!(clip(&r), tiamat_core::ent::AnimTag::SWING, "approached, it flaps off");

    // Now and then down to the ground: it walks and pecks there.
    *r.world.floor.lock().unwrap() = Some((63, grass));
    r.say("plan land");
    let mut landed = false;
    for _ in 0..200 {
        hold(&r, 64.0, true);
        r.tick(1);
        let anim = clip(&r);
        if anim == tiamat_core::ent::AnimTag::IDLE || anim == tiamat_core::ent::AnimTag::SNEAK {
            landed = true;
            break;
        }
    }
    assert!(landed, "a crow told to land comes down to the ground");

    // After dark, right beside you, it does you no harm.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("heal");
    r.say("plan transit");
    for _ in 0..200 {
        r.put_mob(crow, 101.0, 65.5, 100.5);
        r.tick(1);
    }
    assert_eq!(r.number("hp"), 27.0, "a crow at night harms nobody");
    *r.sounds.time.lock().unwrap() = 0.5;

    // Flown on past everyone, it leaves the world.
    // (Any fright it was still flying off from ends first.)
    r.say("plan transit");
    for _ in 0..120 {
        if r.mobs().iter().all(|(id, _)| *id != crow) {
            break;
        }
        r.put_mob(crow, 400.5, 80.0, 400.5);
        r.tick(1);
    }
    assert!(r.mobs().iter().all(|(id, _)| *id != crow), "a crow gone past everyone is gone");
    r.say("cull");
    r.tick(1);
    *r.world.floor.lock().unwrap() = None;
    println!("ok  a crow crosses, circles, sits in a tree and leaves it when approached, lands, harms nobody, and flies out of the world");
    *r.world.floor.lock().unwrap() = None;
}

/// The Spindle's radial climate, read off the player's position: the
// Fitting a sheet ------------------------------------------------------------------
//
// Tiamat Default UI's own check, trimmed to what a tab of ours can get wrong:
// the engine's layout run over the whole screen at the room a window gives a
// framed sheet, with a ruler that sizes text as that mod's faces run. Nothing
// on the screen scrolls, so a slot squeezed too small or out of square, a
// label with no room for its text, or anything spilling out of its parent is
// a screen that does not work at that window.

use tiamat_core::ui::{self as ui_layout, Widget};

struct Ruler;

fn text_size(text: &str, style: &ui_layout::Style) -> (i32, i32) {
    let size = f32::from(style.text_size.unwrap_or(14));
    let per = if style.font.as_deref() == Some("tiamat_default_ui:display") { 0.84 } else { 0.63 };
    let chars = text.chars().count() as f32;
    ((chars * size * per).ceil() as i32, (size * 1.3).ceil() as i32)
}

impl ui_layout::Measure for Ruler {
    fn natural(&self, widget: &Widget, style: &ui_layout::Style) -> (i32, i32) {
        match widget {
            Widget::Label { text } => text_size(text, style),
            Widget::Button { text } => {
                let (w, h) = text_size(text, style);
                (w + 16, h + 8)
            }
            Widget::ItemSlot { .. } => (36, 36),
            _ => (0, 0),
        }
    }
}

/// The room a sheet gets in a window: three quarters of its height, 4:3,
/// clear of the tallest HUD reserve (ours, 216 of 1080), less the sheet's
/// margins, its Close bar and the interface's frame.
fn sheet_room(w: f32, h: f32) -> (i32, i32) {
    let reserve = (216.0 / 1080.0 * h).clamp(0.0, h / 2.0);
    let height = (h * 0.75).min(h - reserve).max(120.0);
    let width = (height * 4.0 / 3.0).min(w * 0.9).max(160.0);
    let height = (width * 3.0 / 4.0).min(height).max(120.0);
    ((width - 16.0 - 24.0) as i32, (height - 48.0 - 24.0) as i32)
}

fn misfits(tree: &ui_layout::Tree, area: (i32, i32)) -> Vec<String> {
    let laid = ui_layout::layout(tree, ui_layout::Rect::new(0, 0, area.0, area.1), &Ruler);
    let mut found = Vec::new();
    walk_fit(tree, 0, &laid, None, &mut found);
    found
}

fn walk_fit(tree: &ui_layout::Tree, at: usize, laid: &ui_layout::Laid, parent: Option<ui_layout::Rect>, found: &mut Vec<String>) {
    let node = &tree.nodes[at];
    let r = laid.rect;
    if let Some(p) = parent
        && (r.x < p.x || r.y < p.y || r.x + r.w > p.x + p.w || r.y + r.h > p.y + p.h)
    {
        found.push(format!("{:?} spills out of its parent: {r:?} in {p:?}", node.widget));
    }
    match &node.widget {
        Widget::ItemSlot { view, index } => {
            let ratio = r.w as f32 / r.h.max(1) as f32;
            if r.w.min(r.h) < 36 || !(0.8..=1.25).contains(&ratio) {
                found.push(format!("{view} slot {} is {}x{}", index + 1, r.w, r.h));
            }
        }
        Widget::Label { text } | Widget::Button { text } if !text.is_empty() => {
            let (w, h) = text_size(text, &node.style);
            let pad = if matches!(node.widget, Widget::Button { .. }) { 8 } else { 0 };
            if w + pad > r.w || h > r.h + 4 {
                found.push(format!("{text:?} needs {}x{} and has {}x{}", w + pad, h, r.w, r.h));
            }
        }
        _ => {}
    }
    let first = node.children.first as usize;
    for (n, child) in laid.children.iter().enumerate() {
        walk_fit(tree, first + n, child, Some(r), found);
    }
}

/// With Tiamat Default UI: the wardrobe is a tab on its inventory screen, and
/// the death screen wears its fonts.
fn ui_check() {
    let mut r = rig_ui();
    r.huds.op(PLAYER);
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    r.tick(1);
    let shown = |r: &Rig| r.dialogs.0.lock().unwrap().len();
    let last = |r: &Rig| r.dialogs.0.lock().unwrap().last().cloned().unwrap();

    let n = shown(&r);
    r.press("wardrobe");
    assert_eq!(shown(&r), n + 1, "the wardrobe key opens the inventory screen");
    let screen = last(&r);
    let tree = format!("{:?}", screen.tree);
    assert!(tree.contains("tiamat_default_life:worn"), "on the Wardrobe tab, worn slots showing");
    assert!(tree.contains("player:main"), "with what you carry beside them");
    assert!(tree.contains("Wardrobe"), "a tab of its own in the strip");
    tiamat_core::ui::check(&screen.tree, tiamat_core::ui::Limits::default()).expect("a valid tree");
    let mut failed = Vec::new();
    for (w, h) in [(800.0, 600.0), (1024.0, 768.0), (1280.0, 720.0), (1366.0, 768.0), (1920.0, 1080.0)] {
        let area = sheet_room(w, h);
        for problem in misfits(&screen.tree, area) {
            failed.push(format!("{w}x{h} ({}x{} room): {problem}", area.0, area.1));
        }
    }
    assert!(failed.is_empty(), "the wardrobe tab does not fit:
  {}", failed.join("
  "));
    // Pressed again, it closes; and again, it opens.
    r.press("wardrobe");
    let n = shown(&r);
    r.press("wardrobe");
    assert_eq!(shown(&r), n + 1, "and opens again");

    r.say("die");
    r.tick(1);
    let death = r.dialogs.0.lock().unwrap().iter().rev().find(|d| d.form.ends_with("death")).cloned()
        .expect("a death screen");
    let tree = format!("{:?}", death.tree);
    assert!(tree.contains("tiamat_default_ui:display"), "in the interface's display face: {tree}");
    assert!(tree.contains("tiamat_default_ui:text"), "and its text face");
    tiamat_core::ui::check(&death.tree, tiamat_core::ui::Limits::default()).expect("a valid tree");
    println!("ok  with Tiamat Default UI: the wardrobe is its tab, the death screen wears its look");
}

/// temperate ring is comfortable, the Glass Waste hot, the Crown frozen.
fn climate_check() {
    let mut r = rig_with("");
    r.huds.op(PLAYER);
    r.vm.player_join(&JoinEvent { player: PLAYER, name: "Alice".into() });
    let grass = r.material("tiamat_default_world:grass");
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

    // Spawning by biome, the world's own answer for the spot: each kind only
    // where it would really live, crows anywhere on dry land, nothing at sea.
    let kinds_in = |r: &mut Rig, biome: &str| -> Vec<String> {
        r.say(&format!("biome {biome}"));
        r.entities.set_position(15300.5, 64.0, 0.5);
        r.say("cull");
        r.tick(1);
        r.tick(100 * 12);
        let mut kinds: Vec<String> = r
            .mobs()
            .iter()
            .filter(|(_, e)| {
                let [x, _, z] = e.transform.to_world();
                (x - 15300.5).abs() < 120.0 && z.abs() < 120.0
            })
            .filter_map(|(_, e)| kind_of(e))
            .collect();
        kinds.sort();
        kinds.dedup();
        kinds
    };
    let grassland = kinds_in(&mut r, "rolling_grasslands");
    assert!(grassland.iter().any(|k| k == "cow" || k == "sheep" || k == "horse"), "grassland has its herds: {grassland:?}");
    for k in ["bear", "stag", "goat", "bat", "spider", "mammoth", "wolf", "squirrel"] {
        assert!(!grassland.iter().any(|g| g == k), "no {k} out on the open grassland by day: {grassland:?}");
    }
    let taiga = kinds_in(&mut r, "taiga");
    assert!(!taiga.is_empty(), "the taiga has its animals");
    for k in ["cow", "horse", "pig", "goat", "bat"] {
        assert!(!taiga.iter().any(|t| t == k), "no {k} in the taiga: {taiga:?}");
    }
    let salt = kinds_in(&mut r, "salt_pan");
    assert_eq!(salt, vec!["crow".to_owned()], "only crows over the salt pan");
    let sea = kinds_in(&mut r, "deep_ocean");
    assert!(sea.is_empty(), "nothing of ours at sea: {sea:?}");
    // After dark the spiders come out, on any land; by day there were none.
    *r.sounds.time.lock().unwrap() = 0.9;
    r.say("god");
    let night = kinds_in(&mut r, "rolling_grasslands");
    assert!(night.iter().any(|k| k == "spider"), "spiders on the grassland at night: {night:?}");
    assert!(!night.iter().any(|k| k == "cow" || k == "sheep"), "and the day's herds do not appear then: {night:?}");
    r.say("god");
    *r.sounds.time.lock().unwrap() = 0.5;
    let cave = kinds_in(&mut r, "mossy_limestone");
    assert!(cave.is_empty(), "a lit cave by day holds none of the surface animals: {cave:?}");
    // How often, by biome: `odds` says each kind's weight where you stand.
    let odds = |r: &mut Rig, biome: &str| -> std::collections::HashMap<String, u32> {
        r.say(&format!("biome {biome}"));
        r.say("odds");
        let said = r.said();
        let list = said.split_once(": ").map(|(_, l)| l.to_owned()).unwrap_or_default();
        list.split(", ")
            .filter_map(|e| e.rsplit_once(' '))
            .filter_map(|(k, w)| w.parse().ok().map(|w| (k.to_owned(), w)))
            .collect()
    };
    let w = |m: &std::collections::HashMap<String, u32>, k: &str| m.get(k).copied().unwrap_or(0);
    let mountains = odds(&mut r, "alpine_highlands");
    assert!(w(&mountains, "sheep") > w(&mountains, "cow") && w(&mountains, "cow") > 0,
        "up in the mountains, sheep over cattle, and cattle rare but there: {mountains:?}");
    let jungle = odds(&mut r, "jungle");
    assert!(w(&jungle, "pig") > 0 && w(&jungle, "sheep") == 0, "pigs in the jungle, and no sheep: {jungle:?}");
    let fen = odds(&mut r, "peat_fen");
    assert!(w(&fen, "pig") > w(&fen, "cow") && w(&fen, "sheep") == 0, "the swamp is the pigs': {fen:?}");
    let pasture = odds(&mut r, "rolling_grasslands");
    for k in ["cow", "sheep"] {
        assert!(w(&pasture, k) > w(&pasture, "horse") && w(&pasture, "horse") > 0, "{k} commoner than horses on the pasture: {pasture:?}");
    }
    let woods = odds(&mut r, "temperate_woodlands");
    assert!(w(&woods, "stag") < w(&woods, "pig") && w(&woods, "bear") < w(&woods, "stag"),
        "in the woods, pigs over deer over bears: {woods:?}");
    r.say("biome rolling_grasslands");
    println!("ok  climate: temperate comfortable, Glass Waste hot, Crown cold; creatures keep to their own biomes, crows anywhere on land");
}

const BOB: [u8; 32] = [9; 32];


/// A mob's kind: its model, if it has one of its own, else its nametag.
/// The farm, end to end: tilling, sowing, growing by random tick, harvest,
/// water, foraging for the first seed, and the animals' domestic lives.
fn farm_check(r: &mut Rig) {
    let grass = r.material("tiamat_default_world:grass");
    *r.world.floor.lock().unwrap() = Some((63, grass));
    *r.sounds.time.lock().unwrap() = 0.5;
    r.world.clear();
    r.say("cull");
    r.say("heal");
    r.say("feed");
    r.tick(1);
    let units = |r: &Rig, id: &str| r.inventory.units_of("player:main", r.material(id));
    let stack = |r: &Rig, id: &str, n: u32| {
        let material = r.material(id);
        let mut views = r.inventory.views.lock().unwrap();
        let list = views.entry("player:main".into()).or_default();
        list.retain(|s| s.material != material);
        list.push(Stack::new(material, 27 * n).unwrap());
        drop(views);
        *r.inventory.held.lock().unwrap() = Some(material);
    };

    // Tilled ground is the world's dirt, to the world.
    r.say("aliases");
    let aliases = r.said();
    assert!(aliases.contains("tiamat_default_life:farmland>tiamat_default_world:dirt"), "farmland is a soil alias of dirt: {aliases}");
    assert!(aliases.contains("tiamat_default_life:wet_farmland>tiamat_default_world:dirt"), "and so is wet farmland: {aliases}");

    // A hoe tills grass; beside water the ground is wet from the start.
    stack(r, "tiamat_default_life:hoe", 1);
    r.use_at(100, 63, 101);
    assert_eq!(r.block_name(100, 63, 101), "tiamat_default_life:farmland", "a hoe tills grass");
    r.world.fluids.lock().unwrap().insert((104, 63, 101), 27);
    r.use_at(103, 63, 101);
    assert_eq!(r.block_name(103, 63, 101), "tiamat_default_life:wet_farmland", "tilled beside water, it is wet");
    r.world.put(100, 64, 105, grass);
    r.world.put(100, 63, 105, grass);
    r.use_at(100, 63, 105);
    assert_eq!(r.block_name(100, 63, 105), "tiamat_default_world:grass", "nothing tills under a block");
    println!("ok  a hoe tills grass to tilled ground, wet where water is near");

    // Sowing: wheat on dry ground, rice only on wet.
    stack(r, "tiamat_default_life:wheat_seeds", 4);
    r.use_at(100, 63, 101);
    assert_eq!(r.block_name(100, 64, 101), "tiamat_default_life:wheat_1", "wheat sown on tilled ground");
    assert_eq!(units(r, "tiamat_default_life:wheat_seeds"), 27 * 3, "one seed spent");
    r.use_at(100, 63, 101);
    assert_eq!(units(r, "tiamat_default_life:wheat_seeds"), 27 * 3, "not on a block already sown");
    stack(r, "tiamat_default_life:rice_seeds", 2);
    r.use_at(101, 63, 101);
    assert_eq!(r.block_name(101, 64, 101), "air", "rice will not take on grass");
    r.use_at(103, 63, 101);
    assert_eq!(r.block_name(103, 64, 101), "tiamat_default_life:rice_1", "rice sown on wet tilled ground");
    println!("ok  seeds sow on tilled ground; rice wants it wet");

    // Growth, a random tick at a time: on wet ground in the sun, every turn
    // is a stage; ripe, it stays ripe.
    r.world.put(100, 63, 101, r.material("tiamat_default_life:wet_farmland"));
    r.random_tick(100, 64, 101);
    assert_eq!(r.block_name(100, 64, 101), "tiamat_default_life:wheat_2", "one turn, one stage, on wet ground");
    r.random_tick(100, 64, 101);
    assert_eq!(r.block_name(100, 64, 101), "tiamat_default_life:wheat_3", "and ripe");
    r.random_tick(100, 64, 101);
    assert_eq!(r.block_name(100, 64, 101), "tiamat_default_life:wheat_3", "ripe stays ripe");
    // On dry ground a turn advances a third of the time; out of its biomes a
    // third of that. In the dark, never.
    r.world.put(100, 63, 101, r.material("tiamat_default_life:farmland"));
    let mut turns = 0;
    for _ in 0..8 {
        r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_1"));
        while r.block_name(100, 64, 101) == "tiamat_default_life:wheat_1" && turns < 400 {
            r.random_tick(100, 64, 101);
            turns += 1;
        }
    }
    assert!(turns > 10 && turns < 400, "on dry ground a stage takes a few turns: {turns} for eight");
    *r.world.dark.lock().unwrap() = true;
    for _ in 0..30 {
        r.random_tick(100, 64, 101);
    }
    assert_eq!(r.block_name(100, 64, 101), "tiamat_default_life:wheat_2", "nothing grows in the dark");
    *r.world.dark.lock().unwrap() = false;
    println!("ok  a crop grows a stage a turn on wet ground, slower dry, never dark; {turns} turns dry");

    // Harvest: a ripe crop dug bare-handed gives its produce and seeds; with
    // a sickle twice the produce; unripe, only the seed back.
    r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_3"));
    r.hold_nothing();
    let (wheat0, seeds0) = (units(r, "tiamat_default_life:wheat"), units(r, "tiamat_default_life:wheat_seeds"));
    assert!(r.dig_at(100, 64, 101), "a crop may be dug");
    let hand = units(r, "tiamat_default_life:wheat") - wheat0;
    assert!((27..=54).contains(&hand), "a hand's harvest is one or two: {hand}");
    assert!(units(r, "tiamat_default_life:wheat_seeds") > seeds0, "and seeds back");
    let mut best = 0;
    for _ in 0..6 {
        r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_3"));
        stack(r, "tiamat_default_life:sickle", 1);
        let before = units(r, "tiamat_default_life:wheat");
        r.dig_at(100, 64, 101);
        best = best.max(units(r, "tiamat_default_life:wheat") - before);
    }
    assert!(best >= 27 * 3, "a sickle harvests twice as much: best of six was {best}");
    r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_1"));
    let (wheat1, seeds1) = (units(r, "tiamat_default_life:wheat"), units(r, "tiamat_default_life:wheat_seeds"));
    r.dig_at(100, 64, 101);
    assert_eq!(units(r, "tiamat_default_life:wheat"), wheat1, "an unripe crop gives no produce");
    assert_eq!(units(r, "tiamat_default_life:wheat_seeds"), seeds1 + 27, "only its seed back");
    // The ground dug from under a crop takes the crop with it, seed back.
    r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_2"));
    r.dig_at(100, 63, 101);
    r.tick(1);
    assert_eq!(r.block_name(100, 64, 101), "air", "the crop went with its ground");
    assert_eq!(units(r, "tiamat_default_life:wheat_seeds"), seeds1 + 54, "and gave its seed back");
    println!("ok  harvest: produce and seed ripe, seed only unripe, a sickle doubles it, dug ground takes the crop");

    // Water: tilled ground dries without water in reach, wets with it, and
    // bare dry ground goes back to earth.
    r.world.fluids.lock().unwrap().clear();
    r.world.put(110, 63, 110, r.material("tiamat_default_life:wet_farmland"));
    let mut turns = 0;
    while r.block_name(110, 63, 110) == "tiamat_default_life:wet_farmland" && turns < 40 {
        r.random_tick(110, 63, 110);
        turns += 1;
    }
    assert_eq!(r.block_name(110, 63, 110), "tiamat_default_life:farmland", "wet ground with no water near dries");
    r.world.fluids.lock().unwrap().insert((112, 62, 110), 9);
    r.random_tick(110, 63, 110);
    assert_eq!(r.block_name(110, 63, 110), "tiamat_default_life:wet_farmland", "water two blocks off, one down, wets it");
    r.world.fluids.lock().unwrap().clear();
    r.world.put(111, 63, 110, r.material("tiamat_default_life:farmland"));
    let mut turns = 0;
    while r.block_name(111, 63, 110) == "tiamat_default_life:farmland" && turns < 60 {
        r.random_tick(111, 63, 110);
        turns += 1;
    }
    assert_eq!(r.block_name(111, 63, 110), "tiamat_default_world:dirt", "bare tilled ground goes back to earth");
    // A bucket scoops water and waters a field; poured elsewhere it is a block of water.
    r.world.fluids.lock().unwrap().insert((105, 63, 101), 27);
    r.world.put(105, 63, 101, MaterialId(0));
    r.world.blocks.lock().unwrap().insert((105, 63, 101), (MaterialId(0), 0));
    stack(r, "tiamat_default_life:bucket", 1);
    let full = units(r, "tiamat_default_life:water_bucket");
    r.use_at(105, 63, 101);
    assert_eq!(units(r, "tiamat_default_life:water_bucket"), full + 27, "a bucket of water");
    assert_eq!(units(r, "tiamat_default_life:bucket"), 0);
    assert!(r.world.fluids.lock().unwrap().get(&(105, 63, 101)).is_none(), "and the water is gone from the block");
    for (x, z) in [(120, 120), (121, 120), (121, 121)] {
        r.world.put(x, 63, z, r.material("tiamat_default_life:farmland"));
    }
    stack(r, "tiamat_default_life:water_bucket", 1);
    r.use_at(120, 63, 120);
    assert_eq!(r.block_name(121, 63, 121), "tiamat_default_life:wet_farmland", "watered, the field and its neighbours");
    assert_eq!(units(r, "tiamat_default_life:bucket"), 27, "the bucket is empty again");
    stack(r, "tiamat_default_life:water_bucket", 1);
    r.use_at(130, 63, 130);
    assert_eq!(r.world.fluids.lock().unwrap().get(&(130, 64, 130)).copied(), Some(27), "poured on grass: a block of water on it");
    println!("ok  tilled ground dries and wets by what is near; a bucket scoops, waters and pours");

    // Trampling: a body that lands on tilled ground treads it flat, crop and all.
    r.world.put(100, 63, 101, r.material("tiamat_default_life:wet_farmland"));
    r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_2"));
    r.entities.set_position(100.5, 64.0, 101.5);
    r.entities.body(|b| b.fell = 2.0);
    r.tick(1);
    r.entities.body(|b| b.fell = 0.0);
    assert_eq!(r.block_name(100, 63, 101), "tiamat_default_world:dirt", "landed on, tilled ground is earth");
    assert_eq!(r.block_name(100, 64, 101), "air", "and the crop is flattened");
    r.entities.set_position(100.5, 64.0, 100.5);
    println!("ok  a landing tramples tilled ground and the crop on it");

    // The first seed: foraged from the wild plant that stands for the crop,
    // by chance; and the apple, from an apple leaf.
    let tall_grass = r.material("tiamat_default_world:tall_grass");
    r.hold_nothing();
    let before = units(r, "tiamat_default_life:wheat_seeds");
    for _ in 0..40 {
        r.world.put(100, 64, 108, tall_grass);
        r.dig_at(100, 64, 108);
    }
    assert!(units(r, "tiamat_default_life:wheat_seeds") > before, "tall grass dug gives wheat seeds now and then");
    let apple_leaves = r.material("tiamat_default_world:apple_leaves");
    let before = units(r, "tiamat_default_life:apple");
    for _ in 0..60 {
        r.world.put(100, 66, 108, apple_leaves);
        r.dig_at(100, 66, 108);
    }
    assert!(units(r, "tiamat_default_life:apple") > before, "an apple leaf broken has an apple in it now and then");
    // A bramble picked by hand gives berries and stands bare until they grow back.
    let bramble = r.material("tiamat_default_world:bramble");
    r.world.put(100, 64, 109, bramble);
    let berries = units(r, "tiamat_default_life:berries");
    r.use_at(100, 64, 109);
    assert_eq!(units(r, "tiamat_default_life:berries"), berries + 27, "berries picked");
    assert_eq!(r.block_name(100, 64, 109), "tiamat_default_life:bramble_picked", "the bramble stands bare");
    let mut turns = 0;
    while r.block_name(100, 64, 109) != "tiamat_default_world:bramble" && turns < 40 {
        r.random_tick(100, 64, 109);
        turns += 1;
    }
    assert_eq!(r.block_name(100, 64, 109), "tiamat_default_world:bramble", "and the berries grow back");
    // A cane plants a bramble.
    stack(r, "tiamat_default_life:bramble_cane", 1);
    r.use_at(100, 63, 112);
    assert_eq!(r.block_name(100, 64, 112), "tiamat_default_world:bramble", "a cane planted on grass is a bramble");
    // Mushrooms: spores on a cave floor, in the dark.
    let mycelium = r.material("tiamat_default_world:mycelium");
    r.world.put(100, 63, 115, mycelium);
    stack(r, "tiamat_default_life:spores", 2);
    r.use_at(100, 63, 115);
    assert_eq!(r.block_name(100, 64, 115), "tiamat_default_life:mushroom_1", "spores take on mycelium");
    r.random_tick(100, 64, 115);
    assert_eq!(r.block_name(100, 64, 115), "tiamat_default_life:mushroom_1", "but not in the sun");
    *r.world.dark.lock().unwrap() = true;
    r.random_tick(100, 64, 115);
    assert_eq!(r.block_name(100, 64, 115), "tiamat_default_life:mushroom_2", "in the dark they come up");
    *r.world.dark.lock().unwrap() = false;
    println!("ok  first seeds are foraged, brambles are picked and regrow, spores grow in the dark");

    // Craft's stand-in: its scythe harvests threefold, its hoe tills, its
    // barley grows by our rules, its stew is eaten and makes you hearty, its
    // hay feeds a cow and drops from one.
    r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_3"));
    stack(r, "tiamat_default_craft:scythe", 1);
    let mut best = 0;
    for _ in 0..6 {
        r.world.put(100, 64, 101, r.material("tiamat_default_life:wheat_3"));
        let before = units(r, "tiamat_default_life:wheat");
        r.dig_at(100, 64, 101);
        best = best.max(units(r, "tiamat_default_life:wheat") - before);
    }
    assert!(best >= 27 * 4, "another mod's scythe harvests threefold: {best}");
    stack(r, "tiamat_default_craft:iron_hoe", 1);
    r.use_at(101, 63, 101);
    assert_eq!(r.block_name(101, 63, 101), "tiamat_default_life:farmland", "another mod's hoe tills");
    stack(r, "tiamat_default_craft:barley_seed", 2);
    r.use_at(101, 63, 101);
    assert_eq!(r.block_name(101, 64, 101), "tiamat_default_craft:barley_1", "another mod's crop is sown");
    r.world.put(101, 63, 101, r.material("tiamat_default_life:wet_farmland"));
    r.random_tick(101, 64, 101);
    assert_eq!(r.block_name(101, 64, 101), "tiamat_default_craft:barley_2", "and grows by our rules");
    r.hold_nothing();
    let before = units(r, "tiamat_default_craft:barley");
    r.dig_at(101, 64, 101);
    assert!(units(r, "tiamat_default_craft:barley") > before, "and is harvested");
    r.say("starve 4");
    stack(r, "tiamat_default_craft:stew", 1);
    r.tick(16);
    r.press("use");
    r.tick(1);
    assert_eq!(r.number("food"), 14.0, "another mod's stew feeds: 4 + 6 + 4");
    assert!(r.text("fx").contains("hearty"), "and makes you hearty");
    r.say("craftdrop");
    r.tick(3);
    assert!(units(r, "tiamat_default_craft:hay") >= 54, "a stack another mod dropped through us was picked up");
    println!("ok  another mod's tools, crop, food and drops go through the exports");

    // The animals. Two cows fed on wheat breed; the calf is small, eats
    // nothing, and grows up. No ground from here on, so nothing else
    // wanders in while the minutes pass.
    *r.world.floor.lock().unwrap() = None;
    r.world.clear();
    r.say("feed");
    r.say("cull");
    r.say("spawn cow 2");
    r.tick(1);
    let cows: Vec<u64> = r.mobs().iter().map(|(id, _)| *id).collect();
    assert_eq!(cows.len(), 2);
    for (i, id) in cows.iter().enumerate() {
        r.put_mob(*id, 102.5 + i as f64, 64.0, 100.5);
    }
    stack(r, "tiamat_default_life:wheat", 4);
    r.use_entity(cows[0]);
    r.tick(1);
    assert_eq!(units(r, "tiamat_default_life:wheat"), 27 * 3, "the cow ate a sheaf");
    assert!(r.text("toast").contains("eats"), "{}", r.text("toast"));
    r.use_entity(cows[0]);
    assert_eq!(units(r, "tiamat_default_life:wheat"), 27 * 3, "a fed cow eats no more");
    r.use_entity(cows[1]);
    r.tick(12);
    assert!(cows.iter().any(|id| r.storage.get(MOD, &format!("breed:{id}")).is_some()), "a fed pair is expecting, remembered with the world");
    for _ in 0..2400 / 20 + 1 {
        for (i, id) in cows.iter().enumerate() {
            r.put_mob(*id, 102.5 + i as f64, 64.0, 100.5);
        }
        r.tick(20);
    }
    let herd = r.mobs();
    assert_eq!(herd.len(), 3, "a calf: {}", herd.len());
    let (calf, body) = herd.iter().find(|(id, _)| !cows.contains(id)).cloned().expect("the calf");
    assert_eq!(body.model.as_deref(), Some("tiamat_default_life:cow_young"), "the calf is the small body");
    assert_eq!(body.health.map(|h| h.current), Some(5), "on half the health");
    stack(r, "tiamat_default_life:wheat", 2);
    let refused = r.use_entity(calf);
    assert_eq!(units(r, "tiamat_default_life:wheat"), 27 * 2, "a calf is not fed");
    assert!(refused.reason.as_deref().unwrap_or("").contains("young"), "{:?}", refused.reason);
    for _ in 0..(20 * 60 * 10) / 100 + 1 {
        r.tick(100);
    }
    let grown = r.mobs();
    assert_eq!(grown.len(), 3, "still three");
    assert!(grown.iter().all(|(_, e)| e.model.as_deref() == Some("tiamat_default_life:cow")), "and all grown");
    println!("ok  two cows fed on wheat breed a calf, which is small, eats nothing and grows up");

    // Milk, and what it does; wool; an egg.
    let cow = r.mobs()[0].0;
    stack(r, "tiamat_default_life:bucket", 1);
    let milk = units(r, "tiamat_default_life:milk");
    r.use_entity(cow);
    assert_eq!(units(r, "tiamat_default_life:milk"), milk + 27, "a bucket of milk");
    stack(r, "tiamat_default_life:bucket", 1);
    let refused = r.use_entity(cow);
    assert_eq!(units(r, "tiamat_default_life:bucket"), 27, "and no more for a while");
    assert!(refused.reason.as_deref().unwrap_or("").contains("while"), "{:?}", refused.reason);
    r.say("poison 400");
    r.say("starve 10");
    stack(r, "tiamat_default_life:milk", 1);
    r.tick(16);
    r.press("use");
    r.tick(1);
    assert!(!r.text("fx").contains("poison"), "milk settles a poisoned stomach");
    assert_eq!(units(r, "tiamat_default_life:bucket"), 27 * 2, "the bucket comes back");
    r.say("cull");
    r.say("spawn sheep 1");
    r.tick(1);
    let sheep = r.mobs()[0].0;
    stack(r, "tiamat_default_life:shears", 1);
    r.use_entity(sheep);
    assert!(units(r, "tiamat_default_life:wool") >= 27, "shorn");
    let wool = units(r, "tiamat_default_life:wool");
    r.use_entity(sheep);
    assert_eq!(units(r, "tiamat_default_life:wool"), wool, "and not again yet");
    r.say("cull");
    r.say("spawn hen 1");
    r.tick(1);
    let (hen, body) = r.mobs()[0].clone();
    assert!(body.nametag.is_some() && body.model.as_deref() == Some("engine:humanoid"), "a hen wears the stand-in body, named");
    let egg = r.material("tiamat_default_life:egg");
    for _ in 0..(20 * 60 * 8) / 100 + 1 {
        r.put_mob(hen, 120.5, 64.0, 120.5);
        r.tick(100);
    }
    assert!(r.entities.items(MOD).iter().any(|s| s.material == egg), "the hen laid an egg");
    println!("ok  a cow gives milk that cures poison, a sheep gives wool, a hen lays");

    // A lead: the animal follows, and the rope comes off at a distance.
    r.say("cull");
    r.say("spawn cow 1");
    r.tick(1);
    let cow = r.mobs()[0].0;
    stack(r, "tiamat_default_life:lead", 1);
    r.use_entity(cow);
    r.tick(1);
    assert!(r.text("toast").contains("lead"), "{}", r.text("toast"));
    r.put_mob(cow, 106.5, 64.0, 100.5);
    r.entities.0.lock().unwrap().entities.get_mut(&cow).unwrap().on_ground = true;
    r.tick(12);
    let walk = r.entities.0.lock().unwrap().entities[&cow].drive.walk;
    assert!(walk[0] < 0.0, "six blocks off, a led cow comes after you: {walk:?}");
    r.put_mob(cow, 101.5, 64.0, 100.5);
    r.tick(3);
    assert_eq!(r.entities.0.lock().unwrap().entities[&cow].drive.walk, [0.0, 0.0], "beside you it stands");
    r.put_mob(cow, 120.5, 64.0, 100.5);
    r.tick(3);
    r.put_mob(cow, 101.5, 64.0, 100.5);
    r.use_entity(cow);
    r.tick(1);
    assert!(r.text("toast").contains("You lead"), "the rope came off at twenty blocks, so this puts it on again: {}", r.text("toast"));
    r.say("cull");
    r.tick(1);
    println!("ok  a led cow follows and stands by you, and the lead breaks at a distance");

    // A gate opens and shuts; a hive fills beside flowers and gives honey;
    // a wild hive is found under the flower forest's trees.
    r.world.put(103, 64, 101, r.material("tiamat_default_life:gate"));
    r.hold_nothing();
    r.use_at(103, 64, 101);
    assert_eq!(r.block_name(103, 64, 101), "tiamat_default_life:gate_open");
    r.use_at(103, 64, 101);
    assert_eq!(r.block_name(103, 64, 101), "tiamat_default_life:gate");
    r.world.put(100, 66, 101, r.material("tiamat_default_life:beehive"));
    for _ in 0..20 {
        r.random_tick(100, 66, 101);
    }
    assert_eq!(r.block_name(100, 66, 101), "tiamat_default_life:beehive", "no flowers, no honey");
    r.world.put(102, 64, 102, r.material("tiamat_default_world:poppy"));
    let mut turns = 0;
    while r.block_name(100, 66, 101) == "tiamat_default_life:beehive" && turns < 30 {
        r.random_tick(100, 66, 101);
        turns += 1;
    }
    assert_eq!(r.block_name(100, 66, 101), "tiamat_default_life:beehive_full", "flowers near, it fills");
    let honey = units(r, "tiamat_default_life:honey");
    r.use_at(100, 66, 101);
    assert!(units(r, "tiamat_default_life:honey") > honey, "honey taken");
    assert_eq!(r.block_name(100, 66, 101), "tiamat_default_life:beehive", "and the hive is empty again");
    let leaves = r.material("tiamat_default_world:oak_leaves");
    for x in 60..140 {
        for z in 60..140 {
            r.world.put(x, 72, z, leaves);
        }
    }
    r.say("biome flower_forest");
    r.tick(100 * 40);
    let hives: Vec<String> = r.storage.0.lock().unwrap().keys().filter(|(m, k)| m == MOD && k.starts_with("hive:")).map(|(_, k)| k.clone()).collect();
    assert!(!hives.is_empty(), "a wild hive was found under the canopy");
    let placed = r.world.blocks.lock().unwrap().values().filter(|(m, _)| *m == r.material("tiamat_default_life:beehive")).count();
    assert!(placed >= hives.len(), "and stands under the leaves: {placed} of {}", hives.len());
    r.say("biome rolling_grasslands");
    r.world.clear();
    r.say("cull");
    r.tick(1);
    println!("ok  a gate swings, a hive fills beside flowers and gives honey, wild hives hang in the flower forest");
    *r.world.floor.lock().unwrap() = None;
}

fn kind_of(e: &Entity) -> Option<String> {
    match e.model.as_deref() {
        Some(m) if m != "engine:humanoid" => Some(m.rsplit(':').next().unwrap_or(m).to_owned()),
        _ => e.nametag.as_ref().map(|n| format!("{n:?}")),
    }
}

fn dig(r: &mut Rig) -> bool {
    r.vm
        .dig_complete(&tiamat_core::script::DigEvent {
            player: PLAYER,
            target: tiamat_core::SubNodePos { x: 300, y: 190, z: 300 },
            material: r.material("tiamat_default_world:grass"),
            brush: tiamat_core::dig::Brush::Block,
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
    assert!(c.inventory.units_of("player:main", c.material("tiamat_default_life:apple")) > 0, "anyone may take the kit");
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
    let apple = a.material("tiamat_default_life:apple");
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
    // The icon hashes pasted into hud.lua are the engine's hashes of the
    // files in icons/, today. When the engine's hashing changes (the Tiamot to
    // Tiamat rename changed its prefix) every one of them names a picture the
    // client has never been sent, and every heart is a magenta box in play.
    // Checked here, so it fails in the harness and not on the screen; the
    // cure is `cargo run --offline --manifest-path tests/native/Cargo.toml --bin hashes`.
    let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../mods").join(MOD);
    let script = std::fs::read_to_string(dir.join("hud.lua")).expect("hud.lua");
    let table = &script[script.find("-- ICONS BEGIN").expect("ICONS BEGIN")..script.find("-- ICONS END").expect("ICONS END")];
    let mut checked = 0;
    for line in table.lines() {
        let Some((name, rest)) = line.trim().split_once(" = \"") else { continue };
        let pasted = rest.trim_end_matches("\",");
        let bytes = std::fs::read(dir.join("icons").join(format!("{name}.png"))).expect("the icon's file");
        let hash = tiamat_core::content::hash_bytes(&bytes);
        let hex: String = hash.iter().map(|b| format!("{b:02x}")).collect();
        assert_eq!(pasted, hex, "hud.lua's hash for `{name}` is stale: run the hasher (--bin hashes)");
        checked += 1;
    }
    assert!(checked >= 14, "every icon in hud.lua checked: {checked}");
    println!("ok  hud.lua's {checked} icon hashes are the engine's own");
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
            use tiamat_core::hud::Command;
            let width = 1920.0;
            let mut lines = Vec::new();
            // Icons are named by hash on the wire; name them by file here.
            let icons = dir.join("icons");
            let mut by_hash = std::collections::HashMap::new();
            if let Ok(entries) = std::fs::read_dir(&icons) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if let Ok(bytes) = std::fs::read(&path) {
                        by_hash.insert(tiamat_core::content::hash_bytes(&bytes), path);
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
