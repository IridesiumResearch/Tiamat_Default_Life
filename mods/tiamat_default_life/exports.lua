-- SPDX-License-Identifier: GPL-3.0-only
--
-- What other mods may call: the table `game.exports("tiamat_default_life")`
-- answers to a mod that lists this one in `depends` or `optional_depends`.
--
-- Today that is Tiamat Weather, whose contract is its
-- docs/exports-contract.md ("What Life can export for Weather"). It loads
-- after this mod, so it cannot be named back; instead it calls these once at
-- its load to put its burning block into this mod's fire and heat tables.
--
-- # Every function here runs in THIS mod's sandbox
--
-- An error in one would disable this mod because another passed it the wrong
-- thing, so none of them raise: they check what they are given and answer
-- `false` for anything else.
--
-- Bump `version` when a change would break a reader, and only then.

local I = tdl.items

local function block_name(name)
    return type(name) == "string" and #name <= 128 and string.match(name, "^[%w_]+:[%w_]+$") ~= nil
end

--- A whole number in lo..hi as an integer, or nil. `20` and `20.0` alike.
local function whole(n, lo, hi)
    local i = type(n) == "number" and math.tointeger(n) or nil
    if i and i >= lo and i <= hi then return i end
    return nil
end

return {
    version = 1,

    --- Standing in `material` burns: `spec = { damage, ticks, after }` is a
    --- hit of `damage` points every `ticks` ticks, and `after` ticks of
    --- burning once out of it. Answers whether it was taken.
    add_contact_fire = function(material, spec)
        if not block_name(material) or type(spec) ~= "table" then return false end
        local damage, ticks, after = whole(spec.damage, 1, 27), whole(spec.ticks, 1, 1200), whole(spec.after, 0, 1200)
        if not (damage and ticks and after) then return false end
        I.add_contact_fire(material, { damage = damage, ticks = ticks, after = after })
        return true
    end,

    --- Sets `target` on fire for `ticks` (at most a minute): a player's UUID,
    --- or the entity id of one of this mod's creatures. Burning is a point
    --- every half second until it runs out or they reach water. Answers
    --- whether there was anyone to set alight: lightning, say, beside them.
    set_alight = function(target, ticks)
        local t = whole(ticks, 1, 1200)
        if not t then return false end
        if type(target) == "string" then
            if not string.match(target, "^%x+$") then return false end
        elseif math.type(target) ~= "integer" then
            return false
        end
        return tdl.set_alight(target, t) == true
    end,

    --- `material` warms whoever stands near it, `strength` from 0 to 1, as
    --- the campfire does at 1. Answers whether it was taken.
    add_heat_source = function(material, strength)
        if not block_name(material) or type(strength) ~= "number" or strength ~= strength
            or strength < 0 or strength > 1 then
            return false
        end
        I.add_heat_source(material, strength)
        return true
    end,
}
