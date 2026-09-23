-- SPDX-License-Identifier: GPL-3.0-only
--
-- Tiamat Default Life: the survival layer. This file only decides load order.
--
-- Every file below is loaded exactly once and hangs what it exports off the
-- `tdl` global, which the sandbox shares between a mod's own files. The
-- engine's `require` is confined to this directory and does not cache, so a
-- file required twice would run twice; nothing but this file calls it.
--
-- Order matters: config and the hook fan-out first (everything subscribes to
-- them), then registrations (items, blocks, sounds, the HUD script and the
-- worn view, which only work while init.lua is running), then the systems
-- that read all of it.

tdl = {}

-- The host reports a failed load as "errored in init.lua" and nothing more,
-- so say which file and what the error was before letting it through.
local function load(name)
    local ok, result = pcall(require, name)
    if not ok then
        game.log(string.format("tiamat_default_life: %s.lua failed: %s", name, tostring(result)))
        error(result, 0)
    end
    return result
end

tdl.config = load("config")
tdl.util = load("util")
load("hooks")                -- one engine registration per hook, many subscribers
tdl.items = load("items")    -- food, medicine, clothing, the bed and the campfire
tdl.effects = load("effects") -- poison, burning, regeneration and the rest
load("modes")                -- the world's mode, its admins, its ghosts: tdl.command
-- Tick order is load order. The environment is sampled FIRST, so that the
-- vitals tick in the same step acts on what the body is standing in right
-- now and the HUD it pushes already shows the result.
load("environment")          -- what the world is doing to each body: v.env, falls
load("vitals")               -- health, hunger, air, temperature: tdl.get / tdl.damage / tdl.heal
load("drops")                -- stacks lying on the ground, and picking them up
load("screens")              -- the wardrobe and the death screen, in Tiamat Default UI's look
load("death")                -- dying, dropping, respawning
load("actions")              -- eating, sleeping, the wardrobe, explosions, chat commands
load("mobs")                 -- the mob system: spawning, behaviour, being hit, dropping
load("creatures")            -- cow, sheep, pig, crow, bat, as data

-- The HUD: hearts, cookies, bubbles and the thermometer, drawn on the
-- player's machine from the values vitals.lua sends with `game.set_hud`.
--
-- `reserve` keeps the engine's sheets (inventory, pause, dialogs) clear of
-- the bottom rows: the bubbles and thermometer row tops out at 206 virtual
-- pixels (ROW_Y + ROW_GAP in hud.lua), and a little air over it. An engine
-- from before the table form takes the plain file name.
if not pcall(game.register_hud_script, { file = "hud.lua", reserve = 216 }) then
    game.register_hud_script("hud.lua")
end

game.log("tiamat_default_life ready: " .. tdl.items.count .. " items, " .. tdl.effects.count .. " effects, "
    .. #tdl.mobs.order .. " creatures")
