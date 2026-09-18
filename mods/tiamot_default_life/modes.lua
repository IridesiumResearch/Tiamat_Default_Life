-- SPDX-License-Identifier: GPL-3.0-only
--
-- The three worlds, and who may bend their rules.
--
-- A world is made in one of three MODES, chosen on the new-world screen and
-- fixed for its life (a world option, declared in mod.toml):
--
--   Default     survival as the rest of this mod describes it.
--   Creative    nobody can be hurt, nothing drains, and every player may
--               hand themselves the kit. Building, not surviving.
--   Adventure   one life. Die and everything you carried falls where you
--               fell, and you stay in the world as a ghost: you may walk
--               it and watch it, and touch nothing in it again.
--
-- And in any mode there are ADMINS, who may be indestructible (`god`), go
-- anywhere (`tp`), raise the dead (`revive`) and use the testing words.
-- Flight is the engine's own power and is its operators' already; the
-- engine cannot yet tell a mod who its operators are, so this mod keeps its
-- own list, which starts the way the engine's does: whoever first joins a
-- world is its admin, which in a world you host is you. Admins make more
-- with `op <name>`.
--
--   tdl.mode                          "Default" | "Creative" | "Adventure"
--   tdl.is_admin(uuid)
--   tdl.is_ghost(uuid), tdl.set_ghost(uuid, on)
--   tdl.is_invulnerable(uuid)         creative, god, or a ghost
--   tdl.command(word, level, fn)      a chat word for "anyone", "creative" or "admin"

local C = tdl.config
local U = tdl.util

tdl.mode = C.mode

local admins = nil      -- uuid -> true, loaded from storage at the first join
local gods = {}         -- uuid -> true, for the session
local ghosts = {}       -- uuid -> true, loaded from storage per player
local by_name = {}      -- lowercased display name -> uuid, for who is here

local GHOST_LINE = "You died in this world. You can walk it and watch it, and nothing more."

-- Admins ---------------------------------------------------------------------------

local function load_admins()
    if admins then return end
    admins = {}
    local text = game.storage.get("admins")
    if type(text) == "string" then
        for uuid in string.gmatch(text, "[^,]+") do admins[uuid] = true end
    end
end

local function save_admins()
    local list = {}
    for uuid in pairs(admins) do list[#list + 1] = uuid end
    table.sort(list)
    game.storage.set("admins", table.concat(list, ","))
end

function tdl.is_admin(uuid)
    return admins ~= nil and admins[uuid] == true
end

function tdl.is_ghost(uuid)
    return ghosts[uuid] == true
end

function tdl.set_ghost(uuid, on)
    ghosts[uuid] = on and true or nil
    game.storage.set("ghost:" .. uuid, on and true or nil)
end

function tdl.is_god(uuid)
    return gods[uuid] == true
end

--- Whether nothing can hurt them and nothing drains: a creative world, an
--- admin who asked for it, or somebody already dead.
function tdl.is_invulnerable(uuid)
    return tdl.mode == "Creative" or gods[uuid] == true or ghosts[uuid] == true
end

--- An online player's UUID by their display name, case-insensitive.
function tdl.uuid_of(name)
    return by_name[string.lower(name or "")]
end

-- Chat words with a door on them -------------------------------------------------------

--- Registers a chat word. `level` is who may say it: "anyone"; "creative",
--- which is everybody in a creative world and admins anywhere; or "admin".
function tdl.command(word, level, fn)
    tdl.on_chat(word, function(uuid, rest)
        if tdl.is_ghost(uuid) and level ~= "anyone" and not tdl.is_admin(uuid) then
            tdl.toast(uuid, GHOST_LINE, 80)
            return
        end
        if level == "admin" and not tdl.is_admin(uuid) then
            tdl.toast(uuid, "That is for admins.", 60)
            return
        end
        if level == "creative" and not (tdl.mode == "Creative" or tdl.is_admin(uuid)) then
            tdl.toast(uuid, "That is for creative worlds, or admins.", 60)
            return
        end
        fn(uuid, rest)
    end)
end

-- Arriving and leaving ----------------------------------------------------------------------

tdl.on_join(function(event)
    load_admins()
    by_name[string.lower(event.name)] = event.player
    if next(admins) == nil then
        -- Nobody has ever run this world: whoever is first does.
        admins[event.player] = true
        save_admins()
        game.log("tiamot_default_life: " .. event.name .. " is this world's first admin")
    end
    if game.storage.get("ghost:" .. event.player) == true then
        ghosts[event.player] = true
    end
end)

tdl.on_leave(function(event)
    by_name[string.lower(event.name)] = nil
    gods[event.player] = nil
    ghosts[event.player] = nil
end)

-- A ghost touches nothing ---------------------------------------------------------------------
--
-- Loaded before vitals and the mobs, so these refusals come first.

tdl.on_dig_complete(function(event)
    if tdl.is_ghost(event.player) then return GHOST_LINE end
end)

tdl.on_place(function(event)
    if tdl.is_ghost(event.player) then return GHOST_LINE end
end)

tdl.on_use(function(event)
    if tdl.is_ghost(event.player) then return GHOST_LINE end
end)

tdl.on_punch(function(event)
    if tdl.is_ghost(event.attacker) then return false end
end)

-- The words ---------------------------------------------------------------------------------------

tdl.command("mode", "anyone", function(uuid)
    local line = "This is a " .. tdl.mode .. " world."
    if tdl.mode == "Adventure" then line = line .. " One life." end
    if tdl.is_admin(uuid) then line = line .. " You are an admin." end
    tdl.toast(uuid, line, 100)
end)

tdl.command("op", "admin", function(uuid, rest)
    local who = tdl.uuid_of(rest)
    if who == nil then
        tdl.toast(uuid, "op <name>: nobody here by that name.")
        return
    end
    admins[who] = true
    save_admins()
    tdl.toast(uuid, tdl.name(who) .. " is an admin.")
    tdl.toast(who, "You are an admin of this world.", 100)
end)

tdl.command("deop", "admin", function(uuid, rest)
    local who = tdl.uuid_of(rest)
    if who == nil then
        tdl.toast(uuid, "deop <name>: nobody here by that name.")
        return
    end
    local count = 0
    for _ in pairs(admins) do count = count + 1 end
    if count <= 1 then
        tdl.toast(uuid, "A world keeps at least one admin.")
        return
    end
    admins[who] = nil
    gods[who] = nil
    save_admins()
    tdl.toast(uuid, tdl.name(who) .. " is no longer an admin.")
end)

tdl.command("god", "admin", function(uuid)
    gods[uuid] = not gods[uuid] or nil
    tdl.toast(uuid, gods[uuid] and "Nothing can hurt you." or "You can be hurt again.", 80)
end)

--- tp <x> <y> <z>, tp <name>, tp home.
tdl.command("tp", "admin", function(uuid, rest)
    local x, y, z = string.match(rest, "^(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
    local target
    if x then
        target = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    elseif rest == "home" then
        local bed = tdl.bed(uuid)
        if bed then target = { x = bed.x + 0.5, y = bed.y + C.respawn_above_bed, z = bed.z + 0.5 } end
    else
        local who = tdl.uuid_of(rest)
        local body = who and U.body(who)
        if body then target = { x = body.pos.x, y = body.pos.y, z = body.pos.z } end
    end
    if target == nil then
        tdl.toast(uuid, "tp <x> <y> <z>, tp <name>, or tp home.")
        return
    end
    if game.move_player(uuid, target) then
        local v = tdl.get(uuid)
        if v then v.fall_peak, v.was_ground = nil, true end
        tdl.toast(uuid, string.format("Moved to %d, %d, %d.", math.floor(target.x), math.floor(target.y), math.floor(target.z)))
    else
        tdl.toast(uuid, "The world would not have it.")
    end
end)

tdl.command("revive", "admin", function(uuid, rest)
    local who = rest ~= "" and tdl.uuid_of(rest) or uuid
    if who == nil or not tdl.is_ghost(who) then
        tdl.toast(uuid, "revive <name>: nobody here by that name is dead.")
        return
    end
    tdl.set_ghost(who, false)
    local v = tdl.get(who)
    if v then
        v.hp, v.food, v.air, v.temp = C.max_health, C.respawn_food, C.max_air, 0
        v.invuln = C.respawn_invulnerable_ticks
        v.last_damage = tdl.now
    end
    tdl.cue(who, "rested")
    tdl.toast(who, "You live again.", 100)
    if who ~= uuid then tdl.toast(uuid, tdl.name(who) .. " lives again.") end
end)

tdl.command("admins", "admin", function(uuid)
    local names = {}
    for who in pairs(admins) do names[#names + 1] = tdl.name(who) end
    table.sort(names)
    tdl.toast(uuid, "Admins: " .. table.concat(names, ", "), 100)
end)

game.log("tiamot_default_life: a " .. tdl.mode .. " world")

return {}
