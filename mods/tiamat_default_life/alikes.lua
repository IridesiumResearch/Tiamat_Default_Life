-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- Alikes: what the players are, behind the scenes, and the bodies they are
-- drawn in (engine ask 23). Once any body is registered every player is
-- drawn as one, by everybody and by themselves in third person; the FIRST
-- registered is everyone's until `game.set_player_model` says otherwise,
-- which is why the Male Alike leads the list: he is who you spawn in as.
--
-- A body is the look and nothing else. The collider, the eye and the
-- first-person hand stay the player's own, so a body is made to their size:
-- 5.4 cells tall (`tools/skin_glb.py --height 5.4`), feet at y = 0, facing
-- +Z, with the clips idle, walk, run, swing, swim, sneak and crawl.
--
-- Which body is the player's own choice: the `body` setting in mod.toml,
-- on the start screen's Mods tab and the in-game settings page, read on
-- join and looked at again every couple of seconds, since nothing says
-- when it changes. The engine keeps none of it; it is said on every join.
--
-- `skins` are further PNGs a body may wear (`game.set_player_skin`), each
-- painted on that body's own UVs; the model's `texture` is the default.
-- None yet, and a player's own PNG waits on the engine.

local M = { bodies = {} }
tdl.alikes = M

local BODIES = {
    { id = "male_alike", model = "models/male_alike.glb", texture = "models/male_alike.png", skins = {} },
    { id = "female_alike", model = "models/female_alike.glb", texture = "models/female_alike.png", skins = {} },
}

-- The setting's answers, as mod.toml spells them, to the bodies.
local CHOICE = { Male = "male_alike", Female = "female_alike" }
local SETTING = game.mod_id .. ":body"
local LOOK_EVERY = 40

-- Behind a pcall, as the creatures' models are: a body the engine refuses
-- is a log line, and players stay the engine's own figure.
if game.register_player_model then
    for _, body in ipairs(BODIES) do
        local ok, why = pcall(game.register_model, { id = body.id, file = body.model, texture = body.texture })
        if ok then
            ok, why = pcall(game.register_player_model, { id = body.id, model = body.id, skins = body.skins })
        end
        if ok then
            M.bodies[#M.bodies + 1] = body.id
        else
            game.log("tiamat_default_life: the " .. body.id .. " body is not worn: " .. tostring(why))
        end
    end
end

local registered = {}
for _, id in ipairs(M.bodies) do registered[id] = true end

local worn = {}

--- Puts a player in the body they chose, if it is not the one they wear.
local function dress(uuid)
    local id = CHOICE[game.setting(uuid, SETTING)]
    if not (id and registered[id]) then id = M.bodies[1] end
    if id == nil or worn[uuid] == id then return end
    if game.set_player_model(uuid, id) then worn[uuid] = id end
end

tdl.on_join(function(event)
    worn[event.player] = nil
    dress(event.player)
end)

tdl.on_leave(function(event)
    worn[event.player] = nil
end)

local since = 0
tdl.on_tick(function(dt)
    since = since + dt
    if since < LOOK_EVERY then return end
    since = 0
    for uuid in pairs(tdl.online()) do dress(uuid) end
end)

return M
