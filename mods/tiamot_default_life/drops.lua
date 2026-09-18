-- SPDX-License-Identifier: GPL-3.0-only
--
-- Stacks lying on the ground, and picking them back up.
--
-- The engine draws a dropped stack and decides nothing else about it
-- (charter rule 1): how long it lasts, who may take it and when are written
-- here. This is the same shape as the reference `core_gear` loop, kept
-- separate because that mod only looks after what IT threw, and what a death
-- scatters, or an animal leaves behind, is this mod's.
--
--   tdl.drop(pos, stack, opts)   puts a stack on the ground; returns the entity id
--
-- `stack` is `{ material, units, shape, detail }`, the shape `game.inventory`
-- reports. `opts.velocity` throws it; `opts.owner` is a UUID that may not
-- pick it up for a moment, so a thrown thing does not come straight back.

local U = tdl.util

local REACH = 1.5              -- blocks
local SETTLE = 60              -- ticks a dropper waits before taking it back
local DESPAWN = 20 * 60 * 5    -- five minutes

local tracked = {}             -- entity id -> { owner, ticks }

function tdl.drop(pos, stack, opts)
    opts = opts or {}
    local id = game.spawn_entity{
        pos = { x = pos.x, y = pos.y, z = pos.z },
        item = { material = stack.material, units = stack.units, shape = stack.shape, detail = stack.detail },
        collider = { width = 0.5, height = 0.5 },
    }
    if id == nil then return nil end
    if opts.velocity then
        game.set_entity(id, { velocity = opts.velocity })
    end
    tracked[id] = { owner = opts.owner, ticks = 0 }
    return id
end

tdl.on_tick(function(dt)
    -- Anything of ours lying near a player that this session does not
    -- remember (the world was closed and reopened) is adopted as settled.
    for uuid, v in pairs(tdl.online()) do
        if v.pos then
            for _, id in ipairs(game.entities_in_radius(v.pos, REACH + 1, game.mod_id)) do
                if tracked[id] == nil then
                    local item = game.entity(id)
                    if item and item.item then
                        tracked[id] = { owner = nil, ticks = SETTLE }
                    end
                end
            end
        end
    end

    for id, watch in pairs(tracked) do
        local item = game.entity(id)
        if item == nil or item.item == nil then
            tracked[id] = nil
        else
            watch.ticks = watch.ticks + dt
            if watch.ticks > DESPAWN then
                game.despawn_entity(id)
                tracked[id] = nil
            else
                for _, near in ipairs(game.entities_in_radius(item.pos, REACH, "engine:player")) do
                    local person = game.entity(near)
                    if person and person.owner then
                        local mine = person.owner == watch.owner
                        local v = tdl.get(person.owner)
                        if not (mine and watch.ticks < SETTLE) and v and not v.dead and not tdl.is_ghost(person.owner) then
                            game.give(person.owner, {
                                material = item.item.material,
                                shape = item.item.shape,
                                units = item.item.units,
                                detail = item.item.detail,
                            })
                            game.despawn_entity(id)
                            tracked[id] = nil
                            break
                        end
                    end
                end
            end
        end
    end
end)

return {}
