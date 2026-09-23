-- SPDX-License-Identifier: GPL-3.0-only
--
-- The mod's two screens, the wardrobe and the death screen, in Tiamat
-- Default UI's look.
--
-- That mod owns the game's interface: its inventory screen, its fonts, its
-- iron frames. So the wardrobe is a TAB on its screen, beside Inventory and
-- Crafting, built from its own widgets, and the death screen, which is a
-- moment of its own rather than a tab, is a dialog built from the same
-- widgets. It is an optional dependency (mod.toml): without it, both are
-- plain dialogs in the client's own face, and the mod works the same.
--
--   tdl.screens.toggle_wardrobe(uuid)      the wardrobe key
--   tdl.screens.death(uuid, line, after)   the death screen
--
-- Everything called on the UI mod answers nil and a reason rather than
-- raising, and a callback it calls here (`build`) is ours: an error in it
-- disables THIS mod, so it is kept to building a table.

local I = tdl.items

local S = {}
tdl.screens = S

local ui = game.exports and game.exports("tiamat_default_ui")
if ui and ui.version ~= 1 then
    game.log("tiamat_default_life: tiamat_default_ui exports version " .. tostring(ui.version)
        .. ", not 1; using plain screens")
    ui = nil
end
S.ui = ui ~= nil

local WARDROBE_TAB = game.mod_id .. ":wardrobe"
local RED = { 230, 70, 70, 255 }
local WARDROBE_HINT = "Clothing here keeps you warm, or cool. Two layers is plenty."

--- A deep copy into plain tables. What another mod's builders answer is a
--- read-only view; the UI mod rebuilds a tab's tree itself, but a dialog we
--- show ourselves is handed to the engine, so it gets our own tables.
local function plain(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = plain(v) end
    return out
end

-- The wardrobe, as a tab ----------------------------------------------------------
--
-- The four worn slots over what you carry: page one of the pack, then quick
-- access, in the Inventory tab's order, so clothing is dragged across on one
-- screen. The engine moves every item; the tab only says which slots show.
--
-- One block nine cells wide, centred, stacked rather than side by side: at
-- 800x600 the sheet's body is about 544 by 272, and nine cells beside
-- anything else would be squeezed out of square. The native check lays it
-- out at every window from 800x600 to 1920x1080.

local tab_ok = false
if ui then
    local w, z = ui.widgets, ui.sizes
    local brass = ui.theme.colours.brass

    local function cells(view, first, count)
        local row = {}
        for i = 0, count - 1 do row[#row + 1] = w.slot(view, first + i) end
        return w.row(row, z.cell, z.cell_gap)
    end

    local WIDTH = 9 * z.cell + 8 * z.cell_gap

    local ok, why = ui.add_tab{
        id = WARDROBE_TAB,
        label = "Wardrobe",
        order = 30,
        build = function(_)
            local heading = plain(w.label("WORN", 16, brass))
            heading.size = 70
            local worn = {}
            worn[1] = heading
            for i = 1, 4 do worn[#worn + 1] = w.slot(I.worn_view, i) end
            worn[#worn + 1] = w.space(1)
            local block = {
                type = "container", direction = "column", align = "stretch", gap = z.gap, size = WIDTH,
                children = {
                    w.row(worn, z.cell, z.cell_gap),
                    cells("player:main", 10, 9),
                    cells("player:main", 19, 9),
                    cells("player:main", 1, 9),
                    w.space(1),
                    w.hint(WARDROBE_HINT),
                },
            }
            return w.box("row", { w.space(1), block, w.space(1) }, 0)
        end,
    }
    tab_ok = ok == true
    if not tab_ok then
        game.log("tiamat_default_life: no wardrobe tab (" .. tostring(why) .. "); using a plain dialog")
    end
end

-- Without the UI mod: a dialog of our own.
local wardrobe_open = {}

local function plain_wardrobe()
    return {
        type = "container", direction = "column", gap = 8, padding = 12,
        children = {
            { type = "label", text = "Worn", style = { text_size = 22 } },
            { type = "label", text = WARDROBE_HINT, style = { text_size = 15, text_colour = { 170, 170, 170 } } },
            { type = "item_grid", view = I.worn_view, columns = 4, first = 1, count = 4 },
            { type = "spacer", size = 8 },
            { type = "label", text = "Carried", style = { text_size = 22 } },
            { type = "item_grid", view = "player:main", columns = 9, first = 1, count = 27 },
        },
    }
end

--- The wardrobe key: opens the inventory screen on the Wardrobe tab, or
--- closes it if that is what is showing.
function S.toggle_wardrobe(uuid)
    if tab_ok then
        if ui.is_open(uuid) and ui.current_tab(uuid) == WARDROBE_TAB then
            ui.close(uuid)
        else
            ui.open(uuid, WARDROBE_TAB)
        end
        return
    end
    if wardrobe_open[uuid] then
        game.close_dialog{ player = uuid, form = "wardrobe" }
        wardrobe_open[uuid] = nil
    else
        game.show_dialog{ player = uuid, form = "wardrobe", tree = plain_wardrobe() }
        wardrobe_open[uuid] = true
    end
end

tdl.on_dialog("wardrobe", function(event)
    if event.kind == "closed" then wardrobe_open[event.player] = nil end
end)

tdl.on_leave(function(event)
    wardrobe_open[event.player] = nil
end)

-- The death screen ----------------------------------------------------------------

local function death_tree(line, after)
    if ui then
        local w = ui.widgets
        return plain(w.box("column", {
            w.label("YOU DIED", 26, RED),
            w.text(line, 17),
            w.hint(after),
            w.space(0, 6),
            w.row({ w.wide_button("respawn", "Carry on", true) }, ui.sizes.row),
        }, 10, 16))
    end
    return {
        type = "container", direction = "column", gap = 10, padding = 16, align = "center",
        children = {
            { type = "label", text = "You died", style = { text_size = 28, text_colour = RED } },
            { type = "label", text = line, style = { text_size = 18, text_colour = { 210, 210, 210 } } },
            { type = "label", text = after, style = { text_size = 15, text_colour = { 160, 160, 160 } } },
            { type = "button", name = "respawn", text = "Carry on" },
        },
    }
end

--- Shows the death screen: what happened, and what became of your things.
function S.death(uuid, line, after)
    game.show_dialog{
        player = uuid,
        form = "death",
        compact = true,
        tree = death_tree(line, after or "Some of what you carried is where you fell."),
    }
end

tdl.on_dialog("death", function(event)
    if event.kind == "pressed" and event.name == "respawn" then
        game.close_dialog{ player = event.player, form = "death" }
    end
end)

return S
