-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- The creatures living in Tiamat Default Structures' sites (its ST-L1).
--
-- A site declares who lives there — `inhabitants = { { kind =
-- "tiamat_default_life:<short id>", count, young? } }` — and Structures says
-- when it is first entered, by anyone, once: `on_first_entry(fn(site))`.
-- This mod listens and puts its own kinds there, on the floor near the
-- site's root, at home in it as a spawned creature is at home where it was
-- put. Kinds another mod names are that mod's to spawn from the same event.
-- Nothing respawns: once the barrow's rats are dead, the barrow is empty.
--
-- Structures loads before this mod (`optional_depends`) and never names it;
-- the owner of a creature reads the place, as Progress reads our `on_kill`.
-- Without Structures, or before it exports anything, this is nothing.
--
-- The listener runs in THIS mod's sandbox, called from Structures' move
-- hook, so a fault in it would disable this mod: it is guarded, and a site
-- it cannot read is a log line.

local U = tdl.util
local MOBS = tdl.mobs

local M = {}
tdl.sites = M

local PREFIX = game.mod_id .. ":"
local MAX_COUNT = 16          -- of one kind, from one entry of one site
local MAX_TOTAL = 32          -- of everything, from one site
local TRIES = 12              -- spots looked at for each group before giving up

--- A whole number in lo..hi, or nil.
local function whole(n, lo, hi)
    local i = type(n) == "number" and math.tointeger(n) or nil
    if i and i >= lo and i <= hi then return i end
    return nil
end

local function point(p)
    if type(p) ~= "table" then return nil end
    local x, y, z = p.x or p[1], p.y or p[2], p.z or p[3]
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return nil end
    return { x = math.floor(x), y = math.floor(y), z = math.floor(z) }
end

--- How far from the root to look, in blocks: half the site's width when it
--- says what its bounds are (`{ min, max }`), else a few blocks.
local function reach_of(site)
    local b = type(site.bounds) == "table" and site.bounds
    local lo, hi = b and point(b.min), b and point(b.max)
    if lo and hi then
        return U.clamp(math.max(hi.x - lo.x, hi.z - lo.z) // 2, 1, 16), lo, hi
    end
    return 4, nil, nil
end

local function within(p, lo, hi)
    if lo == nil then return true end
    return p.x >= lo.x and p.x <= hi.x + 1 and p.z >= lo.z and p.z <= hi.z + 1
end

--- A floor to stand some on, near the root and inside the bounds, or nil.
local function spot(root, reach, lo, hi)
    for i = 1, TRIES do
        local r = i == 1 and 0 or reach
        local x, z = root.x + U.between(-r, r), root.z + U.between(-r, r)
        local feet = MOBS.ground_at(x, z, root.y)
        if feet and within(feet, lo, hi) then return feet end
    end
    return nil
end

local function populate(site)
    if type(site) ~= "table" or type(site.inhabitants) ~= "table" then return end
    -- Our creatures live in the overworld.
    if site.domain ~= nil and site.domain ~= "overworld" then return end
    local root = point(site.root)
    if root == nil then return end
    local reach, lo, hi = reach_of(site)
    local total = 0
    for _, who in ipairs(site.inhabitants) do
        local kind = type(who) == "table" and type(who.kind) == "string"
            and who.kind:sub(1, #PREFIX) == PREFIX and who.kind:sub(#PREFIX + 1)
        local count = type(who) == "table" and whole(who.count or 1, 1, MAX_COUNT)
        if kind and count and MOBS.kinds[kind] and total < MAX_TOTAL then
            count = math.min(count, MAX_TOTAL - total)
            local feet = spot(root, reach, lo, hi)
            if feet then
                local ids = tdl.spawn_mob(kind, feet, count, { young = who.young == true })
                total = total + #ids
            else
                game.log(string.format("tiamat_default_life: no floor for %s at the site %s",
                    kind, tostring(site.id)))
            end
        end
    end
end

--- What Structures calls; also the test's way in.
function M.populate(site)
    local ok, why = pcall(populate, site)
    if not ok then
        game.log("tiamat_default_life: a site's inhabitants were not put there: " .. tostring(why))
    end
end

local structures = game.exports and game.exports("tiamat_default_structures")
if structures and type(structures.on_first_entry) == "function" then
    M.listening = structures.on_first_entry(M.populate) ~= false
    game.log("tiamat_default_life: sites' inhabitants " .. (M.listening and "spawn" or "were refused"))
end

return M
