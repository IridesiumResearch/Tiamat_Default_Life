-- SPDX-FileCopyrightText: Iridesium
-- SPDX-License-Identifier: GPL-3.0-only
--
-- One of each engine hook for the whole mod, with subscribers.
--
-- The engine keeps ONE callback per hook per mod: a second registration is
-- refused or quietly replaces the first. So every file that wants a tick, a
-- punch, a chat word or an action subscribes here, and this file holds the
-- engine's single registration of each.

local ticks = {}
local words = {}
local punches = {}
local actions = {}
local joins = {}
local leaves = {}
local dialogs = {}
local digs = {}
local places = {}
local steps = {}
local uses = {}

-- Runs `fn(dt_ticks)` every tick, after everything subscribed before it.
---@param fn fun(dt_ticks: integer)
function tdl.on_tick(fn)
    ticks[#ticks + 1] = fn
end

-- Runs `fn(player, rest)` when a player says `word` (case-insensitive), alone
-- or followed by more words, and swallows the message.
---@param word string
---@param fn fun(player: string, rest: string)
function tdl.on_chat(word, fn)
    assert(not words[word], "chat word registered twice: " .. word)
    words[word] = fn
end

-- Runs `fn(event)` for every punch. Returning `false` cancels it.
function tdl.on_punch(fn)
    punches[#punches + 1] = fn
end

-- Runs `fn(event)` when a player presses or releases the qualified action `id`.
function tdl.on_action(id, fn)
    actions[id] = actions[id] or {}
    local list = actions[id]
    list[#list + 1] = fn
end

function tdl.on_join(fn)
    joins[#joins + 1] = fn
end

function tdl.on_leave(fn)
    leaves[#leaves + 1] = fn
end

-- Runs `fn(event)` for events from the dialog this mod showed as `form`
-- (unqualified; the engine reports it qualified).
function tdl.on_dialog(form, fn)
    dialogs[game.mod_id .. ":" .. form] = fn
end

-- Runs `fn(event)` when a dig completes. Returning `false` refuses it.
function tdl.on_dig_complete(fn)
    digs[#digs + 1] = fn
end

-- Runs `fn(event)` before a placement. The first non-nil return wins.
function tdl.on_place(fn)
    places[#places + 1] = fn
end

-- Runs `fn(id, dt)` once a tick for every entity this mod spawned.
function tdl.on_entity_step(fn)
    steps[#steps + 1] = fn
end

-- Runs `fn(event)` when a player USES a block (the place control with
-- nothing to place), or uses at nothing: then `event.x`, `event.y`, `event.z`
-- and `event.material` are nil and `event.held` is what it always is. Return
-- a string or `false` to handle it; the first handler to do so stops the rest.
function tdl.on_use(fn)
    uses[#uses + 1] = fn
end

game.register_on_tick(function(dt_ticks)
    for _, fn in ipairs(ticks) do
        fn(dt_ticks)
    end
end)

game.register_on_chat(function(event)
    local first, rest = string.match(event.text, "^%s*(%S+)%s*(.*)$")
    if first == nil then return end
    local fn = words[string.lower(first)]
    if fn == nil then return end
    fn(event.player, rest)
    return false
end)

game.register_on_punch(function(event)
    for _, fn in ipairs(punches) do
        if fn(event) == false then
            return false
        end
    end
end)

game.register_on_action(function(event)
    local list = actions[event.id]
    if list == nil then return end
    for _, fn in ipairs(list) do
        fn(event)
    end
end)

game.register_on_player_join(function(event)
    for _, fn in ipairs(joins) do
        fn(event)
    end
end)

game.register_on_player_leave(function(event)
    for _, fn in ipairs(leaves) do
        fn(event)
    end
end)

game.register_on_dialog_event(function(event)
    local fn = dialogs[event.form]
    if fn then fn(event) end
end)

game.register_on_dig_complete(function(event)
    for _, fn in ipairs(digs) do
        -- `false` refuses in the engine's words, a string in the mod's own.
        local verdict = fn(event)
        if verdict ~= nil and verdict ~= true then
            return verdict
        end
    end
end)

game.register_on_entity_step(function(id, dt)
    for _, fn in ipairs(steps) do
        fn(id, dt)
    end
end)

if game.register_on_use then
    local function dispatch(event)
        for _, fn in ipairs(uses) do
            local verdict = fn(event)
            if verdict ~= nil and verdict ~= true then
                return verdict
            end
        end
    end
    -- `anywhere` (engine protocol 76): the place control at open sky, or past
    -- reach, arrives too, with no cell, so what is held is eaten wherever the
    -- player looks. An older engine ignores the option and asks only at a
    -- block.
    game.register_on_use(dispatch, { anywhere = true })
end

game.register_on_place(function(event)
    for _, fn in ipairs(places) do
        local verdict = fn(event)
        if verdict ~= nil then
            return verdict
        end
    end
end)

return {}
