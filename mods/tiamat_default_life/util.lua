-- SPDX-License-Identifier: GPL-3.0-only
--
-- Small helpers with no opinion about the game.

local U = {}

function U.clamp(value, low, high)
    if value < low then return low end
    if value > high then return high end
    return value
end

-- Nearest integer, halves up. `math.floor` gives an integer subtype for a
-- float that is a whole number, which is what storage and HUD values want.
function U.round(value)
    return math.floor(value + 0.5)
end

-- Squared horizontal-and-vertical distance between two positions. Squared,
-- so the compare side gets squared too and nothing takes a root.
function U.dist2(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return dx * dx + dy * dy + dz * dz
end

-- Where a player's body is, or nil if they are not connected.
function U.body(uuid)
    local id = game.player_entity(uuid)
    if id == nil then return nil end
    return game.entity(id)
end

-- The block a position is in.
function U.block_at(pos, dy)
    return { x = math.floor(pos.x), y = math.floor(pos.y + (dy or 0)), z = math.floor(pos.z) }
end

-- A numeric material id for a qualified block or item id, or nil when nothing
-- registered it. `game.get_block_id` errors on an unknown id, which is right
-- for a typo in this mod's own names and wrong for a block another mod may or
-- may not have registered.
function U.material(id)
    local ok, material = pcall(game.get_block_id, id)
    if ok then return material end
    return nil
end

-- Whether a block holds one of the materials in `set` (keyed on numeric
-- ids), returning that material's entry. A mixed block answers for any of
-- its cells.
function U.material_in(set, pos)
    local at = game.get_block(pos)
    if at == nil or at.occupancy == 0 then return nil end
    if at.cells then
        for _, material in ipairs(at.cells) do
            if set[material] then return set[material] end
        end
        return nil
    end
    return set[at.material]
end

-- Flames licking up a burning body, `height` blocks tall, for everyone near
-- to see. Decoration: call it every few ticks while the body burns.
function U.flames(pos, height)
    game.emit_particles{
        pos = { x = pos.x, y = pos.y + height * 0.45, z = pos.z },
        count = 5, size = 0.2, lifetime = 0.5,
        colour = { r = 1.0, g = 0.55, b = 0.12, a = 0.9 },
        area = { x = 0.25, y = height * 0.4, z = 0.25 },
        velocity = { y = 0.8 }, spread = 0.3, gravity = -2, collide = false, radius = 48,
    }
end

-- Resolves a table keyed on qualified ids into one keyed on numeric material
-- ids, dropping what is not registered. Load-time only.
function U.materials(by_id)
    local out = {}
    for id, value in pairs(by_id) do
        local material = U.material(id)
        if material then out[material] = value end
    end
    return out
end

-- A flat record as one storage string: "key=value;key=value". Values are
-- numbers or strings without `;` or `=`.
function U.encode(record)
    local parts = {}
    local keys = {}
    for key in pairs(record) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local value = record[key]
        if type(value) == "number" then
            if value == math.floor(value) then
                value = string.format("%d", value)
            else
                value = string.format("%.4f", value)
            end
        end
        parts[#parts + 1] = key .. "=" .. tostring(value)
    end
    return table.concat(parts, ";")
end

function U.decode(text)
    local record = {}
    if type(text) ~= "string" then return record end
    for key, value in string.gmatch(text, "([%w_]+)=([^;]*)") do
        record[key] = tonumber(value) or value
    end
    return record
end

-- A HUD string is at most 64 bytes.
function U.hud_text(text)
    if #text > 64 then
        return string.sub(text, 1, 61) .. "..."
    end
    return text
end

-- The short name of a qualified id, spaces for underscores.
function U.friendly(id)
    return (string.gsub(string.match(id, ":(.+)$") or id, "_", " "))
end

return U
