-- SPDX-License-Identifier: GPL-3.0-only
--
-- Everything this mod registers: food, medicine, clothing, two blocks, the
-- sounds, the worn view and the two actions. Registration window only, so
-- all of it lives in one file that init.lua runs once.
--
-- An item here is a definition table the rest of the mod reads by material
-- id: `tdl.items.by_material[held.material]` answers "what does eating this
-- do". The engine knows only that the thing exists and cannot be placed.

local U = tdl.util

local M = { defs = {}, by_material = {}, count = 0 }

--- Registers an item and remembers what it does.
---
--- `def.kind` is "food", "medicine" or "clothing". Food and medicine share
--- the fields `food`, `saturation`, `heal`, `effects` (a list of
--- `{ id, ticks }`), `cures` (a list of effect ids removed), `sound`, and
--- `temperature` ("warm" or "cool", a lasting shift). Clothing has `warmth`
--- (+1 warm, -1 cool) and `armour` (a fraction of physical damage kept off).
local function item(id, name, description, def)
    local material = game.register_item{
        id = id,
        name = name,
        description = description,
        texture = "textures/" .. id .. ".png",
    }
    def.id = game.mod_id .. ":" .. id
    def.short = id
    def.name = name
    def.material = material
    M.defs[def.id] = def
    M.by_material[material] = def
    M.count = M.count + 1
    return def
end

-- Food ----------------------------------------------------------------------
--
-- `food` is in points (two to a cookie); `saturation` is added on top and
-- fills the hidden buffer above the cookies. Numbers follow the classic
-- feel: a snack, a meal, and something special.

item("apple", "Apple", "Crisp. Two cookies.",
    { kind = "food", food = 4, saturation = 1, sound = "eat" })
item("berries", "Berries", "Picked from a bramble. A bite.",
    { kind = "food", food = 2, saturation = 0, sound = "eat" })
item("bread", "Bread", "A loaf. Filling.",
    { kind = "food", food = 5, saturation = 3, sound = "eat" })
item("raw_meat", "Raw meat", "Better cooked. Eating it raw sits badly.",
    { kind = "food", food = 3, saturation = 0, sound = "eat", effects = { { "poison", 100 } } })
item("cooked_meat", "Cooked meat", "The staple. Four cookies and a full belly.",
    { kind = "food", food = 8, saturation = 6, sound = "eat", well_fed = true })
item("hot_stew", "Hot stew", "Warms you through for a good while.",
    { kind = "food", food = 6, saturation = 4, sound = "drink", temperature = "warm", well_fed = true })
item("cool_melon", "Cool melon", "Cools you down for a good while.",
    { kind = "food", food = 3, saturation = 1, sound = "eat", temperature = "cool" })
item("honey", "Honey", "Sweet. Mends a little on its own.",
    { kind = "food", food = 3, saturation = 2, heal = 3, sound = "drink", effects = { { "regeneration", 100 } } })
item("golden_apple", "Golden apple", "Heals, then keeps healing, and hardens you for a while.",
    { kind = "food", food = 4, saturation = 5, heal = 6, sound = "eat",
      effects = { { "regeneration", 200 }, { "resistance", 400 } } })

-- Medicine ------------------------------------------------------------------

-- The one healing item: a heart at once, three more over a few seconds,
-- and it puts a fire out.
item("bandage", "Bandage", "A heart now and three more over a few seconds. Puts out a fire.",
    { kind = "medicine", sound = "heal", heal = 3, effects = { { "regeneration", 225 } }, cures = { "burning" }, needs_injury = true })
item("antidote", "Antidote", "Clears poison, wither and radiation.",
    { kind = "medicine", sound = "drink", cures = { "poison", "wither", "radiation" }, needs_affliction = true })

-- Clothing ------------------------------------------------------------------
--
-- Worn in the `worn` view (open it with the wardrobe key). No numbers on the
-- label: this one keeps you warm, that one keeps you cool.

item("warm_coat", "Warm coat", "Keeps you warm. Wear it.",
    { kind = "clothing", warmth = 1, armour = 0.10 })
item("cool_cloak", "Cool cloak", "Keeps you cool. Wear it.",
    { kind = "clothing", warmth = -1, armour = 0.05 })

game.register_view{ id = "worn", slots = 4 }
M.worn_view = game.mod_id .. ":worn"

-- Blocks --------------------------------------------------------------------

M.bed = game.register_block{
    id = "bed",
    name = "Bed",
    description = "Sleep in it at night to heal up and make it home.",
    hardness = 0.5,
    textures = { all = "textures/bed.png" },
}

M.campfire = game.register_block{
    id = "campfire",
    name = "Campfire",
    description = "Warms whoever stands near it. Do not stand in it.",
    hardness = 0.4,
    textures = { all = "textures/campfire.png" },
    light_emit = { r = 15, g = 9, b = 2 },
}

-- Sounds --------------------------------------------------------------------
--
-- Registered here and raised as cues by name from the systems, so a sound
-- pack can rebind any of them without touching this mod.

for _, sound in ipairs({
    { id = "hurt", gain = 0.8, pitch_variance = 0.10 },
    { id = "eat", gain = 0.7, pitch_variance = 0.08 },
    { id = "drink", gain = 0.7, pitch_variance = 0.05 },
    { id = "heal", gain = 0.6 },
    { id = "bubble", gain = 0.5, pitch_variance = 0.20 },
    { id = "gasp", gain = 0.7 },
    { id = "burn", gain = 0.6, pitch_variance = 0.15 },
    { id = "death", gain = 0.9 },
    { id = "thud", gain = 0.9, pitch_variance = 0.10 },
    { id = "rested", gain = 0.6 },
    { id = "boom", gain = 1.0, pitch_variance = 0.10 },
    { id = "bite", gain = 0.8, pitch_variance = 0.15 },
    { id = "moo", gain = 0.7, pitch_variance = 0.12 },
    { id = "baa", gain = 0.7, pitch_variance = 0.15 },
    { id = "oink", gain = 0.7, pitch_variance = 0.15 },
    { id = "caw", gain = 0.6, pitch_variance = 0.20 },
    { id = "squeak", gain = 0.5, pitch_variance = 0.25 },
}) do
    game.register_sound{ id = sound.id, file = "sounds/" .. sound.id .. ".wav",
        gain = sound.gain, pitch_variance = sound.pitch_variance }
    game.bind_sound(sound.id, sound.id)
end

-- The HUD's pictures ----------------------------------------------------------
--
-- A HUD script names a picture only when it draws one, by which time the
-- frame is being painted and nothing has asked the server for the bytes; a
-- picture nobody registered draws as the client's magenta "not arrived"
-- box for ever. Registering puts each file in the table a client fetches on
-- join. The hash answered here is the same one `tests/native --bin hashes`
-- writes into hud.lua, so the script's table and the server's agree.
--
-- Guarded, so an engine from before `register_picture` still loads the mod
-- (with pink hearts, which is the engine telling you to update it).
M.icons = {}
M.icon_names = {
    "heart_full", "heart_2", "heart_1", "heart_empty", "heart_flash",
    "cookie_full", "cookie_half", "cookie_empty",
    "bubble", "thermo_hot", "thermo_cold",
    "shield", "shield_faint", "shield_broken",
}
if game.register_picture then
    for _, name in ipairs(M.icon_names) do
        M.icons[name] = game.register_picture{ id = "icon_" .. name, file = "icons/" .. name .. ".png" }
    end
else
    game.log("tiamot_default_life: this engine has no game.register_picture; HUD pictures will not arrive")
end

-- Actions -------------------------------------------------------------------
--
-- The engine owns the keys (charter rule 11); these are suggestions, chosen
-- clear of the engine's own defaults and the reference mods' (E inventory,
-- Q drop, Z gear, C chisel, R tool, F offhand, N fly, T chat, and the
-- engine's debug letters B, G, H, K, L, V, Y). See docs/controls.md.

game.register_action{
    id = "use",
    default_key = "KeyX",
    description = "Eat or use what you are holding; sleep when beside a bed",
}
game.register_action{
    id = "wardrobe",
    default_key = "KeyO",
    description = "Open the worn slots: clothing for warm and cold",
}

-- Numeric ids for the world's blocks this mod reacts to, resolved once. A
-- block the loaded world does not have is simply absent from these tables.
local C = tdl.config
M.contact_fire = U.materials(C.contact_fire)
M.heat_sources = U.materials(C.heat_sources)
M.cold_sources = U.materials(C.cold_sources)
M.radiation_blocks = U.materials(C.radiation_blocks)
M.weapons = U.materials(C.weapons)
M.forage = U.materials(C.forage)

return M
