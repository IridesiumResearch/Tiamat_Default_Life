-- SPDX-FileCopyrightText: Iridesium
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
-- And in any mode there are ADMINS, who may be indestructible (`god`), raise
-- the dead (`revive`) and use the testing words. Admins ARE the server's
-- operators (`game.is_operator`): whoever first joins a world, which in a
-- world you host is you, and whoever the engine's own `/op` names after.
--
-- Flying and going anywhere (`tp`) are POWERS. In a creative world every
-- admin has them. In a survival world (Default, Adventure) nobody does but
-- the world's OWNER — the first admin it ever saw, remembered with the world
-- — and only once they take them with `powers on`, which the whole server
-- is told. They last the session, or until `powers off`. The engine lets an
-- operator fly whatever a mod says (docs/engine-asks.md, ask 21), so until
-- that is answered an admin can still fly with N; `tp` is this mod's, and
-- is shut.
--
--   tdl.mode                          "Default" | "Creative" | "Adventure"
--   tdl.is_admin(uuid)
--   tdl.is_owner(uuid)                the world's first admin
--   tdl.has_powers(uuid)              may fly and `tp`
--   tdl.is_ghost(uuid), tdl.set_ghost(uuid, on)
--   tdl.is_invulnerable(uuid)         creative, god, or a ghost
--   tdl.command(word, level, fn)      a chat word for "anyone", "creative" or "admin"

local C = tdl.config
local U = tdl.util

tdl.mode = C.mode

local gods = {}         -- uuid -> true, for the session
local powers = {}       -- uuid -> true, for the session: the owner, having taken them
local ghosts = {}       -- uuid -> true, loaded from storage per player
local by_name = {}      -- lowercased display name -> uuid, for who is here

local GHOST_LINE = "You died in this world. You can walk it and watch it, and nothing more."

-- Admins ---------------------------------------------------------------------------

function tdl.is_admin(uuid)
    return game.is_operator(uuid)
end

--- The world's owner: the first admin it ever saw, remembered with the world.
function tdl.is_owner(uuid)
    return game.storage.get("owner") == uuid and tdl.is_admin(uuid)
end

--- May fly and go anywhere: any admin in a creative world; in a survival
--- world, the owner, having taken their powers.
function tdl.has_powers(uuid)
    if not tdl.is_admin(uuid) then return false end
    if tdl.mode == "Creative" then return true end
    return powers[uuid] == true and tdl.is_owner(uuid)
end

--- Says one line to everybody here.
local function tell_all(text)
    for who in pairs(tdl.online()) do tdl.say(who, text) end
end

function tdl.is_ghost(uuid)
    return ghosts[uuid] == true
end

function tdl.set_ghost(uuid, on)
    ghosts[uuid] = on and true or nil
    game.storage.set("ghost:" .. uuid, on and true or nil)
end

--- An admin who asked for it; somebody `/deop`ed stops being one at once.
function tdl.is_god(uuid)
    return gods[uuid] == true and tdl.is_admin(uuid)
end

--- Whether nothing can hurt them and nothing drains: a creative world, an
--- admin who asked for it, or somebody already dead.
function tdl.is_invulnerable(uuid)
    return tdl.mode == "Creative" or ghosts[uuid] == true or tdl.is_god(uuid)
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
            tdl.say(uuid, GHOST_LINE)
            return
        end
        if level == "admin" and not tdl.is_admin(uuid) then
            tdl.say(uuid, "That is for admins.")
            return
        end
        if level == "creative" and not (tdl.mode == "Creative" or tdl.is_admin(uuid)) then
            tdl.say(uuid, "That is for creative worlds, or admins.")
            return
        end
        fn(uuid, rest)
    end)
end

-- Arriving and leaving ----------------------------------------------------------------------

tdl.on_join(function(event)
    by_name[string.lower(event.name)] = event.player
    -- The first admin this world ever sees is its owner, for good.
    if game.storage.get("owner") == nil and tdl.is_admin(event.player) then
        game.storage.set("owner", event.player)
    end
    if game.storage.get("ghost:" .. event.player) == true then
        ghosts[event.player] = true
    end
end)

tdl.on_leave(function(event)
    by_name[string.lower(event.name)] = nil
    gods[event.player] = nil
    powers[event.player] = nil
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
    tdl.say(uuid, line)
end)

tdl.command("god", "admin", function(uuid)
    gods[uuid] = not gods[uuid] or nil
    tdl.say(uuid, gods[uuid] and "Nothing can hurt you." or "You can be hurt again.")
end)

--- powers on | off: the owner of a survival world takes flight and `tp`,
--- and everybody is told.
tdl.command("powers", "admin", function(uuid, rest)
    if tdl.mode == "Creative" then
        tdl.say(uuid, "In a creative world every admin flies and goes anywhere already.")
        return
    end
    -- A world made before owners were remembered takes the first admin to ask.
    if game.storage.get("owner") == nil then game.storage.set("owner", uuid) end
    if not tdl.is_owner(uuid) then
        tdl.say(uuid, "Only the owner of this world can take powers in it.")
        return
    end
    if rest == "on" then
        if powers[uuid] then tdl.say(uuid, "You have them already.") return end
        powers[uuid] = true
        tell_all(tdl.name(uuid) .. ", the owner of this world, has given themselves the power to fly and to teleport.")
    elseif rest == "off" then
        if not powers[uuid] then tdl.say(uuid, "You have none to put down.") return end
        powers[uuid] = nil
        tell_all(tdl.name(uuid) .. " has put their powers down.")
    else
        tdl.say(uuid, "powers on, or powers off. " .. (powers[uuid] and "You have them." or "You have none."))
    end
end)

--- tp <x> <y> <z>, tp <name>, tp home: a power (see the top of this file).
tdl.command("tp", "admin", function(uuid, rest)
    if not tdl.has_powers(uuid) then
        tdl.say(uuid, "Only the owner can teleport in a survival world, and only having taken their powers (powers on).")
        return
    end
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
        tdl.say(uuid, "tp <x> <y> <z>, tp <name>, or tp home.")
        return
    end
    if game.move_player(uuid, target) then
        tdl.say(uuid, string.format("Moved to %d, %d, %d.", math.floor(target.x), math.floor(target.y), math.floor(target.z)))
    else
        tdl.say(uuid, "The world would not have it.")
    end
end)

tdl.command("revive", "admin", function(uuid, rest)
    local who = rest ~= "" and tdl.uuid_of(rest) or uuid
    if who == nil or not tdl.is_ghost(who) then
        tdl.say(uuid, "revive <name>: nobody here by that name is dead.")
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
    tdl.say(who, "You live again.")
    if who ~= uuid then tdl.say(uuid, tdl.name(who) .. " lives again.") end
end)

--- The admins who are here. Making one is the engine's `/op`.
tdl.command("admins", "admin", function(uuid)
    local names = {}
    for _, who in pairs(by_name) do
        if game.is_operator(who) then
            names[#names + 1] = tdl.name(who) .. (tdl.is_owner(who) and " (the owner)" or "")
        end
    end
    table.sort(names)
    tdl.say(uuid, "Admins here: " .. table.concat(names, ", ") .. ". Make more with /op.")
end)

game.log("tiamat_default_life: a " .. tdl.mode .. " world")

return {}
