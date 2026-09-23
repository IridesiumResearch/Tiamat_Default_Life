-- SPDX-License-Identifier: GPL-3.0-only
--
-- Health, hunger, air and body temperature, per player.
--
-- The engine has no damage model and a player's body carries no health
-- (charter rule 1), so all of it lives here, keyed on the UUID (charter rule
-- 13), saved to `game.storage` and pushed to the player's own HUD script with
-- `game.set_hud` every tick (the engine sends only what changed).
--
-- Exports, for the rest of the mod and for the mobs to come:
--
--   tdl.get(uuid)                       the vitals record, or nil
--   tdl.online()                        uuid -> record, everyone here
--   tdl.damage(uuid, amount, kind, opts) hurt somebody; returns what landed
--   tdl.heal(uuid, amount)
--   tdl.feed(uuid, food, saturation)
--   tdl.exhaust(uuid, amount)           spend food, in fractions of a point
--   tdl.toast(uuid, text, ticks)        a line on their HUD for a moment
--   tdl.cue(uuid, name)                 a sound at their body
--   tdl.name(uuid)                      the display name last seen
--   tdl.now                             the tick counter
--
-- Damage kinds: "physical", "fall", "fire", "lava", "poison", "wither",
-- "starvation", "drowning", "freezing", "overheating", "explosion",
-- "radiation". Every one has a face on the HUD and a line on the death screen.

local C = tdl.config
local U = tdl.util
local E = tdl.effects
local I = tdl.items

local players = {}   -- uuid -> vitals record
local names = {}     -- uuid -> display name, for messages only
local now = 0
tdl.now = 0

local SAVE_EVERY = 200
local SAFE_EVERY = 20
local SAFE_STALE_HITS = 100

local function key(uuid)
    return "v:" .. uuid
end

local function fresh()
    return {
        hp = C.spawn_health,
        food = C.spawn_food,
        exhaustion = 0,
        air = C.max_air,
        temp = 0,
        fx = {},
        deaths = 0,
        -- Bookkeeping, not saved.
        hurt_cd = 0, last_hit = 0, last_damage = -1000, invuln = 40, dead = false,
        regen_acc = 0, starve_acc = 0, air_acc = 0, drown_acc = 0, fire_acc = 0, temp_acc = 0, temp_dmg_acc = 0,
        toast = nil, toast_until = 0, flash_until = 0, low_air_gasp = false,
        env = { submerged = false, wet = false, swimming = false, fire = nil, radiation = false,
                ambient = 0, on_ground = true, speed2 = 0 },
        pos = nil,
        safe_recent = nil, safe_old = nil,
        warmth = 0, armour = 0,
    }
end

local function load(uuid)
    local v = fresh()
    local saved = game.storage.get(key(uuid))
    if saved then
        local r = U.decode(saved)
        v.hp = U.clamp(r.hp or v.hp, 1, C.max_health)
        v.food = U.clamp(r.food or v.food, 0, C.max_food)
        v.air = U.clamp(r.air or v.air, 0, C.max_air)
        v.temp = U.clamp(r.temp or 0, -1, 1)
        v.deaths = r.deaths or 0
        E.decode(v, r.fx)
    end
    return v
end

local function save(uuid, v)
    game.storage.set(key(uuid), U.encode{
        hp = v.hp, food = v.food, air = v.air, temp = v.temp, deaths = v.deaths, fx = E.encode(v),
    })
end

function tdl.get(uuid)
    return players[uuid]
end

function tdl.online()
    return players
end

function tdl.name(uuid)
    return names[uuid] or "somebody"
end

function tdl.cue(uuid, name, gain)
    local v = players[uuid]
    local pos = v and v.pos
    if pos == nil then
        local body = U.body(uuid)
        pos = body and body.pos
    end
    if pos then
        game.cue{ cue = name, pos = { x = pos.x, y = pos.y + 1, z = pos.z }, radius = 16, gain = gain }
    end
end

function tdl.toast(uuid, text, ticks)
    local v = players[uuid]
    if v == nil then return end
    v.toast = U.hud_text(text)
    v.toast_until = now + (ticks or 60)
end

--- A line in one player's chat: the answer to a chat word, a refusal, a
--- notice meant to be read back later. Toasts are for the moment-to-moment.
function tdl.say(uuid, text)
    game.chat_to(uuid, text)
end

--- Spends food in fractions; a point comes off when a whole one is owed.
function tdl.exhaust(uuid, amount)
    local v = players[uuid]
    if v == nil then return end
    v.exhaustion = v.exhaustion + amount
    while v.exhaustion >= 1 do
        v.exhaustion = v.exhaustion - 1
        if v.food > 0 then v.food = v.food - 1 end
    end
end

function tdl.feed(uuid, food, saturation)
    local v = players[uuid]
    if v == nil then return end
    v.food = math.min(C.max_food, v.food + (food or 0))
    v.food = math.min(C.max_food, v.food + (saturation or 0))
end

function tdl.heal(uuid, amount)
    local v = players[uuid]
    if v == nil or v.dead then return 0 end
    local before = v.hp
    v.hp = math.min(C.max_health, v.hp + amount)
    return v.hp - before
end

--- Hurts a player.
---
--- `opts`: `quiet` skips the hurt cooldown (for ticking damage that already
--- paces itself); `floor` is a health the hit will not take them below;
--- `push` is an impulse for `game.push_player`; `cause` is a line for the
--- death screen instead of the kind's own; `force` ignores respawn
--- protection. Returns the points that actually came off.
function tdl.damage(uuid, amount, kind, opts)
    opts = opts or {}
    local v = players[uuid]
    if v == nil or v.dead then return 0 end
    if v.invuln > 0 and not opts.force then return 0 end
    -- A creative world, an admin who asked, or somebody already dead.
    if tdl.is_invulnerable(uuid) and not opts.force then return 0 end

    local scale = E.damage_scale(v, kind)
    if kind == "physical" or kind == "explosion" then
        scale = scale * (1 - U.clamp(v.armour, 0, 0.8))
    end
    amount = U.round(amount * scale)
    if amount <= 0 then return 0 end

    -- The classic cooldown: hits inside half a second of one another only
    -- land the amount by which they exceed the last one, so a burst reads as
    -- one blow rather than a machine gun.
    local dealt = amount
    if not opts.quiet then
        if v.hurt_cd > 0 then
            dealt = amount - v.last_hit
            if dealt <= 0 then
                v.last_hit = math.max(v.last_hit, amount)
                return 0
            end
        end
        v.last_hit = amount
        v.hurt_cd = C.hurt_cooldown_ticks
    end

    if opts.floor and v.hp - dealt < opts.floor then
        dealt = math.max(0, v.hp - opts.floor)
    end
    if dealt <= 0 then return 0 end

    v.hp = v.hp - dealt
    v.last_damage = now
    v.flash_until = now + 8
    v.exhaustion = v.exhaustion + dealt * C.exhaust_per_damage
    tdl.cue(uuid, "hurt")
    if opts.push then
        game.push_player(uuid, opts.push)
    end

    if v.hp <= 0 then
        v.hp = 0
        tdl.die(uuid, kind, opts.cause)
    end
    return dealt
end

-- The tick -------------------------------------------------------------------

local function tick_food(uuid, v, dt)
    local env = v.env
    local rate = C.exhaust_idle
    if env.swimming then
        rate = C.exhaust_swim
    elseif env.speed2 >= C.speed_sprinting * C.speed_sprinting then
        rate = C.exhaust_sprint
    elseif env.speed2 >= C.speed_walking * C.speed_walking then
        rate = C.exhaust_walk
    end
    if v.temp >= C.temp_uncomfortable or v.temp <= -C.temp_uncomfortable then
        rate = rate * C.exhaust_temperature
    end
    if E.has(v, "rested") then
        rate = rate * C.exhaust_rested
    end
    tdl.exhaust(uuid, rate * dt)

    -- Regeneration, paid for in food.
    if v.hp < C.max_health and now - v.last_damage >= C.regen_quiet_ticks then
        local period
        if v.food > C.visible_food then
            period = C.regen_fast_ticks
        elseif v.food >= C.regen_slow_min_food then
            period = C.regen_slow_ticks
        end
        if period and E.has(v, "well_fed") then
            period = period * 0.75
        end
        if period then
            v.regen_acc = v.regen_acc + dt
            while v.regen_acc >= period do
                v.regen_acc = v.regen_acc - period
                if tdl.heal(uuid, 1) > 0 then
                    tdl.exhaust(uuid, C.regen_food_cost)
                end
            end
        else
            v.regen_acc = 0
        end
    else
        v.regen_acc = 0
    end

    -- Starvation, to a floor.
    if v.food <= 0 then
        v.starve_acc = v.starve_acc + dt
        while v.starve_acc >= C.starve_ticks do
            v.starve_acc = v.starve_acc - C.starve_ticks
            tdl.damage(uuid, 1, "starvation", { quiet = true, floor = C.starve_floor })
        end
    else
        v.starve_acc = 0
    end
end

local function tick_air(uuid, v, dt)
    if v.env.submerged then
        if v.air > 0 then
            v.air_acc = v.air_acc + dt
            while v.air_acc >= C.air_drain_ticks and v.air > 0 do
                v.air_acc = v.air_acc - C.air_drain_ticks
                v.air = v.air - 1
                if v.air % 3 == 0 then tdl.cue(uuid, "bubble", 0.6) end
            end
            if v.air < 9 then v.low_air_gasp = true end
        else
            v.drown_acc = v.drown_acc + dt
            while v.drown_acc >= C.drown_ticks do
                v.drown_acc = v.drown_acc - C.drown_ticks
                tdl.damage(uuid, C.drown_damage, "drowning", { quiet = true })
            end
        end
    else
        v.air_acc, v.drown_acc = 0, 0
        if v.air < C.max_air then
            v.air = math.min(C.max_air, v.air + C.air_refill_per_tick * dt)
            if v.low_air_gasp then
                tdl.cue(uuid, "gasp")
                v.low_air_gasp = false
            end
        end
    end
end

local function tick_fire(uuid, v, dt)
    local fire = v.env.fire
    if v.env.submerged or v.env.wet then
        -- Water puts you out.
        if E.has(v, "burning") then E.remove(v, "burning") end
        v.fire_acc = 0
        return
    end
    if fire then
        v.fire_acc = v.fire_acc + dt
        while v.fire_acc >= fire.ticks do
            v.fire_acc = v.fire_acc - fire.ticks
            tdl.damage(uuid, fire.damage, fire.damage >= C.lava_damage and "lava" or "fire", { quiet = true })
            tdl.cue(uuid, "burn", 0.7)
        end
        E.apply(v, "burning", fire.after)
    else
        v.fire_acc = 0
    end
    -- Alight, in the fire or after it: flames on the body for all to see.
    if E.has(v, "burning") and v.pos then
        v.flame_acc = (v.flame_acc or 0) + dt
        if v.flame_acc >= C.flame_every then
            v.flame_acc = 0
            U.flames(v.pos, 1.8)
        end
    end
    if v.env.radiation then
        E.apply(v, "radiation", C.radiation_ticks)
    end
end

local function tick_temperature(uuid, v, dt)
    v.temp_acc = v.temp_acc + dt
    if v.temp_acc >= C.temp_sample_ticks then
        v.temp_acc = v.temp_acc - C.temp_sample_ticks
        local clothing = U.clamp(v.warmth, -2, 2) * C.temp_clothing
        local ambient = U.clamp(v.env.ambient + E.temperature(v) + clothing, -1, 1)
        v.temp = v.temp + (ambient - v.temp) * C.temp_drift
        if v.temp > -0.005 and v.temp < 0.005 then v.temp = 0 end
    end
    if v.temp >= C.temp_extreme or v.temp <= -C.temp_extreme then
        local every = v.temp < 0 and C.freeze_damage_ticks or C.temp_damage_ticks
        v.temp_dmg_acc = v.temp_dmg_acc + dt
        while v.temp_dmg_acc >= every do
            v.temp_dmg_acc = v.temp_dmg_acc - every
            tdl.damage(uuid, C.temp_damage, v.temp > 0 and "overheating" or "freezing", { quiet = true })
        end
    else
        v.temp_dmg_acc = 0
    end
end

-- Where to put somebody back: the last place they stood safely, sampled
-- twice so a respawn lands where they were a little while ago rather than
-- on the edge they just fell off.
local function sample_safe(v)
    if v.pos and v.env.on_ground and not v.env.submerged and not v.env.fire
        and v.hp >= 9 and now - v.last_damage > SAFE_STALE_HITS then
        v.safe_old = v.safe_recent or v.pos
        v.safe_recent = { x = v.pos.x, y = v.pos.y, z = v.pos.z }
    end
end

--- The weather shield: whether what you wear answers the weather you are
--- in. Keyed on the SURROUNDINGS (the ambient before clothing), not the
--- body: a coat that is working keeps the body comfortable, and that is
--- exactly when it should show. "ok" is the faint shield, "broken" the
--- cracked one, "" nothing to say. A warm coat in the heat is no shield.
local function shield_state(v)
    local ambient = v.env.ambient
    if ambient <= -C.temp_show then
        return v.warmth > 0 and "ok" or "broken"
    elseif ambient >= C.temp_show then
        return v.warmth < 0 and "ok" or "broken"
    end
    return ""
end

local function push_hud(uuid, v)
    local temp = U.round(v.temp * 100) / 100
    game.set_hud(uuid, {
        hp = v.hp,
        food = math.min(v.food, C.visible_food),
        air = v.air,
        air_show = v.env.submerged or v.air < C.max_air,
        temp = temp,
        temp_show = temp >= C.temp_show or temp <= -C.temp_show,
        hot = temp >= C.temp_uncomfortable,
        cold = temp <= -C.temp_uncomfortable,
        extreme = temp >= C.temp_extreme or temp <= -C.temp_extreme,
        hurt = now < v.flash_until,
        toast = (v.toast and now < v.toast_until) and v.toast or "",
        fx = E.hud_string(v),
        hungry = v.food <= C.low_food,
        starving = v.food <= 0,
        wet = v.env.submerged,
        shielded = v.invuln > 0,
        shield = shield_state(v),
        ghost = tdl.is_ghost(uuid),
        creative = tdl.mode == "Creative",
        god = tdl.is_god(uuid),
    })
end

--- What the body may do, which the client predicts with: cold slows you, an
--- empty stomach will not sprint, and everybody flies in a creative world.
--- Winding the sky is refused where nights are meant: it lights the player's
--- own night. Admins and creative worlds keep it.
--- Said only when it changes; the engine forgets it when the player leaves,
--- and a rejoin loads a fresh record, which says it again.
local function push_abilities(uuid, v)
    local whole = tdl.is_invulnerable(uuid) or v.dead
    local cold = not whole and v.temp <= -C.temp_uncomfortable
    local speed = cold and C.cold_speed or 1
    local sprint = whole or v.food > 0
    local fly = tdl.mode == "Creative"
    local wind_sky = fly or tdl.is_admin(uuid)
    local said = string.format("%s %s %s %s", speed, sprint, fly, wind_sky)
    if said == v.abilities then return end
    v.abilities = said
    game.set_player_abilities(uuid, { speed = speed, sprint = sprint, fly = fly, wind_sky = wind_sky })
end

tdl.on_join(function(event)
    names[event.player] = event.name
    local v = load(event.player)
    players[event.player] = v
    if tdl.is_ghost(event.player) then
        v.hp = 0
        tdl.toast(event.player, "You died in this world. It goes on without you.", 160)
    elseif tdl.mode == "Adventure" then
        tdl.toast(event.player, "Welcome, " .. event.name .. ". You have one life.", 140)
    elseif tdl.mode == "Creative" then
        tdl.toast(event.player, "Welcome, " .. event.name .. ". Nothing here can hurt you.", 120)
    else
        tdl.toast(event.player, "Welcome, " .. event.name .. ". Stay fed and stay warm.", 120)
    end
end)

tdl.on_leave(function(event)
    local v = players[event.player]
    if v then
        save(event.player, v)
        players[event.player] = nil
    end
end)

tdl.on_tick(function(dt)
    now = now + dt
    tdl.now = now
    for uuid, v in pairs(players) do
        if v.hurt_cd > 0 then v.hurt_cd = v.hurt_cd - dt end
        if v.invuln > 0 then v.invuln = v.invuln - dt end
        if tdl.is_invulnerable(uuid) then
            -- Nothing drains. The living are kept whole; a ghost stays as it fell.
            if not tdl.is_ghost(uuid) then
                v.hp, v.food, v.air, v.temp = C.max_health, C.max_food, C.max_air, 0
            end
            v.fx = {}
        elseif not v.dead then
            E.tick(uuid, v, dt)
            tick_food(uuid, v, dt)
            tick_air(uuid, v, dt)
            tick_fire(uuid, v, dt)
            tick_temperature(uuid, v, dt)
        end
        if now % SAFE_EVERY == 0 then sample_safe(v) end
        push_hud(uuid, v)
        push_abilities(uuid, v)
        if now % SAVE_EVERY == 0 then save(uuid, v) end
    end
end)

-- A punch on a player is damage; the engine only reports it (charter rule 1).
tdl.on_punch(function(event)
    if event.owner == nil or not C.pvp then return end
    if event.owner == event.attacker then return end
    local victim = players[event.owner]
    if victim == nil then return end

    local damage = C.fist_damage
    local held = game.held(event.attacker)
    if held and I.weapons[held.material] then
        damage = I.weapons[held.material]
    end

    -- Away from whoever swung, sideways and a little up.
    local push
    local attacker = U.body(event.attacker)
    if attacker and victim.pos then
        local dx, dz = victim.pos.x - attacker.pos.x, victim.pos.z - attacker.pos.z
        local length = math.sqrt(dx * dx + dz * dz)
        if length > 0.001 then
            push = { x = dx / length * C.knockback, y = C.knockback_up, z = dz / length * C.knockback }
        end
    end
    tdl.damage(event.owner, damage, "physical", {
        push = push,
        cause = "slain by " .. tdl.name(event.attacker),
    })
end)

return {}
