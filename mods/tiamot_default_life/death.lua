-- SPDX-License-Identifier: GPL-3.0-only
--
-- Dying, and coming back.
--
-- Clear but not cruel: some of what you carried is scattered where you fell,
-- most is kept, and you wake at your bed if you have one or else where you
-- last stood safely. There is no body to leave behind (the engine steps a
-- player's body from their own inputs), so a death is a screen, a scatter and
-- a move, all in the tick it happened.
--
--   tdl.die(uuid, kind, cause)   called by tdl.damage when health reaches zero
--   tdl.set_bed(uuid, pos)       remembered per player, keyed on the UUID
--   tdl.bed(uuid)                the bed's block position, or nil

local C = tdl.config
local U = tdl.util
local E = tdl.effects
local I = tdl.items

local CAUSES = {
    physical = "were slain",
    fall = "fell from a great height",
    fire = "burned to death",
    lava = "tried to swim in lava",
    poison = "were poisoned",
    wither = "withered away",
    starvation = "starved",
    drowning = "drowned",
    freezing = "froze to death",
    overheating = "overheated",
    explosion = "were blown up",
    radiation = "succumbed to radiation",
}

local function bed_key(uuid)
    return "bed:" .. uuid
end

function tdl.set_bed(uuid, pos)
    game.storage.set(bed_key(uuid), string.format("%d %d %d", pos.x, pos.y, pos.z))
end

function tdl.bed(uuid)
    local text = game.storage.get(bed_key(uuid))
    if type(text) ~= "string" then return nil end
    local x, y, z = string.match(text, "^(%-?%d+) (%-?%d+) (%-?%d+)$")
    if x == nil then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
end

--- The bed, if it is still a bed. An unloaded chunk answers nil from
--- `get_block`, and the bed is taken on trust then: the world loads around a
--- player wherever they are put.
local function bed_spawn(uuid)
    local bed = tdl.bed(uuid)
    if bed == nil then return nil end
    local at = game.get_block(bed)
    if at ~= nil and at.material ~= I.bed then
        game.storage.set(bed_key(uuid), nil)
        return nil
    end
    return { x = bed.x + 0.5, y = bed.y + C.respawn_above_bed, z = bed.z + 0.5 }
end

--- Scatters one stack in `fraction` of a view where the body was; a
--- fraction of one is everything.
local function scatter(uuid, v, pos, fraction, view)
    local n = 0
    for _, stack in ipairs(game.inventory(uuid, view)) do
        local units
        if stack.shape then
            -- A cut: whole items of it, so the shape stays a shape.
            local per = stack.units // math.max(1, stack.count)
            units = (stack.count // fraction) * per
        else
            units = stack.units // fraction
        end
        if units > 0 then
            local took = game.take(uuid, {
                material = stack.material, units = units, shape = stack.shape, detail = stack.detail, view = view,
            })
            if took > 0 then
                n = n + 1
                -- Fanned out around the spot from a counter rather than a
                -- random draw (charter rule 4): two servers scatter alike.
                local dx = ((n * 7) % 5 - 2) * 0.15
                local dz = ((n * 3) % 5 - 2) * 0.15
                -- Owned by the one who died, so a respawn on the spot does
                -- not scoop everything back up before it has landed.
                tdl.drop({ x = pos.x, y = pos.y + 1.0, z = pos.z }, {
                    material = stack.material, units = took, shape = stack.shape, detail = stack.detail,
                }, { owner = uuid, velocity = { x = dx, y = 0.35, z = dz } })
            end
        end
    end
    return n
end

local function death_screen(uuid, line, after)
    game.show_dialog{
        player = uuid,
        form = "death",
        compact = true,
        tree = {
            type = "container", direction = "column", gap = 10, padding = 16, align = "center",
            children = {
                { type = "label", text = "You died", style = { text_size = 28, text_colour = { 230, 70, 70 } } },
                { type = "label", text = line, style = { text_size = 18, text_colour = { 210, 210, 210 } } },
                { type = "label", text = after or "Some of what you carried is where you fell.", style = { text_size = 15, text_colour = { 160, 160, 160 } } },
                { type = "button", name = "respawn", text = "Carry on" },
            },
        },
    }
end

tdl.on_dialog("death", function(event)
    if event.kind == "pressed" and event.name == "respawn" then
        game.close_dialog{ player = event.player, form = "death" }
    end
end)

function tdl.die(uuid, kind, cause)
    local v = tdl.get(uuid)
    if v == nil or v.dead then return end
    v.dead = true
    v.deaths = v.deaths + 1

    local body = U.body(uuid)
    local pos = body and body.pos or v.pos
    tdl.cue(uuid, "death")

    local line = "You " .. (cause or CAUSES[kind] or "died") .. "."
    game.log(string.format("tiamot_default_life: %s %s (%s)", tdl.name(uuid), cause or CAUSES[kind] or kind, kind))

    -- One life: everything falls, worn and carried, and the player stays
    -- where they fell as a ghost. There is no waking up.
    if tdl.mode == "Adventure" then
        if pos then
            scatter(uuid, v, pos, 1)
            scatter(uuid, v, pos, 1, I.worn_view)
        end
        tdl.set_ghost(uuid, true)
        v.hp, v.fx, v.dead = 0, {}, false
        v.env.fire = nil
        local last = "You " .. (cause or CAUSES[kind] or "died") .. ". Your one life is spent."
        tdl.toast(uuid, last, 200)
        death_screen(uuid, last, "Everything you carried is where you fell. You may walk the world and watch it.")
        return
    end

    if pos then
        scatter(uuid, v, pos, C.drop_fraction)
    end

    -- Where to wake up.
    local target = bed_spawn(uuid) or v.safe_old or v.safe_recent
    if target == nil and pos then
        target = { x = pos.x, y = pos.y + 1, z = pos.z }
    end
    if target then
        game.move_player(uuid, target)
    end

    -- The body is whole again: full hearts, full cookies and no buffer.
    v.hp = C.max_health
    v.food = C.respawn_food
    v.exhaustion = 0
    v.air = C.max_air
    v.temp = 0
    v.fx = {}
    v.invuln = C.respawn_invulnerable_ticks
    v.hurt_cd, v.last_hit = 0, 0
    v.fall_peak, v.was_ground, v.last_vy = nil, true, 0
    v.last_damage = tdl.now
    v.env.fire = nil
    v.dead = false

    tdl.toast(uuid, line, 120)
    death_screen(uuid, line)
end

return {}
