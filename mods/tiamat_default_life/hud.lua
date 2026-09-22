-- SPDX-License-Identifier: GPL-3.0-only
--
-- The vitals HUD: hearts, cookies, bubbles when you are under, a
-- thermometer only when you are too hot or too cold, a tint at the edges of
-- the screen when something is wrong, and a line of text now and then.
--
-- This runs on the PLAYER's machine, once a frame, in a sandbox with a
-- budget of about 200,000 instructions and 512 draw commands. Everything it
-- knows arrives in `state.values`, set by vitals.lua with `game.set_hud`;
-- everything it does is `hud.image`, `hud.rect` and `hud.text`. It draws
-- and does not compute: the server has already decided every number here.
--
-- The pictures are PNGs in `icons/`, drawn by content hash. A heart loses
-- a pie wedge for every third; a cookie is bitten for the half; a bubble
-- shrinks with the air in it; a shield, faint or cracked, says whether your
-- clothing answers the weather. The hashes below are written by
-- `tests/native --bin hashes` and are not edited by hand.

-- ICONS BEGIN (written by tests/native --bin hashes; do not edit by hand)
local ICONS = {
    bubble = "a4733e270723365521152f63dc362aa70265a8bd2bfc040c83d0ee48b8608673",
    cookie_empty = "05350defe5bbb1ee6976a9f876a0806c4657a8edda0db3f6bf379dee43733b6d",
    cookie_full = "636696cc2bc64d1a538fc98244aed674874b35dfcec7638da0ea0fbb07484ab9",
    cookie_half = "b289a1b889139778f8d31c1e78c560167bf4e6894f298e1c4b0ffb8f737ec514",
    heart_1 = "64cc87377267ded25ad4ce7d17a391497f4743d68a302446ff04fe6a6f54267d",
    heart_2 = "6179c570f6247da558cfe4b4d29c0dcfddeb2bf736bd4cc24c77cc381714be92",
    heart_empty = "ed9093b89481c14e58283ae0c27e08937b1fdaedcfc272bece6865b48a832b3b",
    heart_flash = "bed7fe750c69adcb481e6968138521204e0faa37cc4ea15a61eb8d8077c93223",
    heart_full = "0b8944c859499dcf53e390e0b5b6efc4273760c97a936436cda890aea4738fcb",
    shield = "22f7383bfe806ef3656ca4c88766d84cdf64622129208d03ed50817b07af4cc0",
    shield_broken = "df9c56671587aabc7373b36dd5091eb018a52549ee54f09e7d119d815c25403a",
    shield_faint = "77c8a21806b9100aa0a7753ce926f15419271cfeb57b162d8d17d92455c3fe8d",
    thermo_cold = "840d70aa1ad8b9f02e1a4785c9558fbd69f457e36320bc3351fbf606ea6e2700",
    thermo_hot = "ccca7952329e5ca9bb84f365867bed7cf9f93b968472ea4502737da31ebb1d74",
}
-- ICONS END

local ICON = 30                -- virtual pixels a heart or cookie is drawn at
local PITCH = 32               -- one to the next
local ROW_Y = 172              -- top of the vitals row, from the bottom of the screen
local ROW_GAP = 34             -- rows above it (bubbles, thermometer)
local HALF_WIDTH = 351         -- the hotbar's half width; the rows line up with its ends
local COUNT = 9

local INK = { 235, 235, 235, 255 }
local DIM = { 180, 180, 180, 255 }
local SHADOW = { 0, 0, 0, 140 }
local COLD = { 120, 190, 255, 255 }
local HOT = { 255, 130, 40, 255 }

local EFFECT_NAMES = {
    burning = { "Burning", { 255, 150, 60, 255 } },
    poison = { "Poisoned", { 120, 200, 80, 255 } },
    wither = { "Withering", { 150, 150, 150, 255 } },
    radiation = { "Irradiated", { 200, 230, 90, 255 } },
    regeneration = { "Regenerating", { 255, 120, 160, 255 } },
    resistance = { "Resistant", { 170, 170, 220, 255 } },
    warmth = { "Warmed", { 255, 190, 120, 255 } },
    cooling = { "Cooled", { 150, 210, 255, 255 } },
    well_fed = { "Well fed", { 230, 200, 120, 255 } },
    rested = { "Well rested", { 190, 230, 190, 255 } },
}

local function icon(name, x, y, size, anchor)
    local hash = ICONS[name]
    if hash == nil then return end
    size = size or ICON
    hud.image{ anchor = anchor or "bottom", x = x, y = y, w = size, h = size, hash = hash }
end

-- The status tray: the bottom-right corner, where protections, effects,
-- potions and spells show. Measured from the corner: with the
-- "bottom_right" anchor, x and y are how far the picture's LEFT and TOP
-- edges stand in from the right and the bottom.
local TRAY_MARGIN = 24
local TRAY_ICON = ICON * 5     -- a protection is drawn large: 150 virtual pixels
local TRAY_LINE = 22

--- Hearts, nine of them, left of the middle. Three points each; a missing
--- third is a wedge gone from the picture.
local HEART_BY_POINTS = { "heart_1", "heart_2", "heart_full" }

local function hearts(hp, hurt)
    local x0 = -HALF_WIDTH
    for i = 0, COUNT - 1 do
        local points = hp - i * 3
        local name = "heart_empty"
        if points >= 3 then
            name = hurt and "heart_flash" or "heart_full"
        elseif points > 0 then
            name = HEART_BY_POINTS[points]
        end
        icon(name, x0 + i * PITCH, ROW_Y)
    end
end

--- Cookies, nine, right of the middle, filling from the right the way the
--- classics do. Two points each; one point is a cookie with a bite out of it.
local function cookies(food, hungry, starving)
    local x0 = HALF_WIDTH - COUNT * PITCH + (PITCH - ICON)
    for i = 0, COUNT - 1 do
        local x = x0 + (COUNT - 1 - i) * PITCH
        local points = food - i * 2
        local name = "cookie_empty"
        if points >= 2 then
            name = "cookie_full"
        elseif points == 1 then
            name = "cookie_half"
        end
        icon(name, x, ROW_Y)
    end
    if starving then
        hud.text{ anchor = "bottom", x = HALF_WIDTH - 78, y = ROW_Y + 24, text = "Starving", size = 16, colour = { 255, 120, 90, 255 } }
    elseif hungry then
        hud.text{ anchor = "bottom", x = HALF_WIDTH - 70, y = ROW_Y + 24, text = "Hungry", size = 16, colour = DIM }
    end
end

--- Bubbles above the cookies, when there is anything to say about air. A
--- bubble with less in it is drawn smaller, centred in its place.
local BUBBLE_SIZE = { 14, 22, ICON }

local function bubbles(air)
    local y = ROW_Y + ROW_GAP
    local x0 = HALF_WIDTH - COUNT * PITCH + (PITCH - ICON)
    for i = 0, COUNT - 1 do
        local points = air - i * 3
        if points > 0 then
            local size = BUBBLE_SIZE[points >= 3 and 3 or points]
            local inset = (ICON - size) // 2
            icon("bubble", x0 + (COUNT - 1 - i) * PITCH + inset, y - inset, size)
        end
    end
end

--- A thermometer above the hearts, and a word beside it.
local function thermometer(temp, hot, cold, extreme)
    local x = -HALF_WIDTH
    local y = ROW_Y + ROW_GAP
    icon(temp > 0 and "thermo_hot" or "thermo_cold", x, y)
    local word
    if extreme then
        word = temp > 0 and "Overheating!" or "Freezing!"
    elseif hot then
        word = "Hot"
    elseif cold then
        word = "Cold"
    else
        word = temp > 0 and "Warm" or "Chilly"
    end
    hud.text{ anchor = "bottom", x = x + ICON + 6, y = y - 5, text = word, size = 17, colour = temp > 0 and HOT or COLD }
end

--- The weather shield, large in the status tray: faint when what you wear
--- answers the weather, cracked when it does not. Returns how much of the
--- tray's height it took, so what stacks above it starts clear of it.
local function shield(state)
    if state == nil or state == "" then return 0 end
    icon(state == "ok" and "shield_faint" or "shield_broken",
        TRAY_MARGIN + TRAY_ICON, TRAY_MARGIN + TRAY_ICON, TRAY_ICON, "bottom_right")
    return TRAY_ICON + 10
end

--- Bands along the four edges of the screen, in a colour, fading inward.
--- Width unknown to a script, so the horizontal bands are drawn far wider
--- than any window.
local function edges(colour, alpha, depth)
    local steps = 4
    for step = 1, steps do
        local a = math.floor(alpha / steps)
        local band = math.floor(depth * step / steps)
        local c = { colour[1], colour[2], colour[3], a }
        hud.rect{ anchor = "top", x = -4000, y = 0, w = 8000, h = band, colour = c }
        hud.rect{ anchor = "bottom", x = -4000, y = band, w = 8000, h = band, colour = c }
        hud.rect{ anchor = "left", x = 0, y = -540, w = band, h = 1080, colour = c }
        hud.rect{ anchor = "right", x = band, y = -540, w = band, h = 1080, colour = c }
    end
end

--- The active effects, named, stacked in the status tray above whatever
--- protection is showing. `above` is the height already taken.
local function effects(list, above)
    if list == nil or list == "" then return end
    local n = 0
    for id in string.gmatch(list, "[^,]+") do
        local entry = EFFECT_NAMES[id]
        if entry and n < 8 then
            hud.text{ anchor = "bottom_right", x = TRAY_MARGIN + TRAY_ICON,
                y = TRAY_MARGIN + above + (n + 1) * TRAY_LINE,
                text = entry[1], size = 17, colour = entry[2] }
            n = n + 1
        end
    end
end

--- A line of text over the hotbar, for a moment.
local function toast(text)
    if text == nil or text == "" then return end
    local size = 20
    local width = #text * (size * 0.48)
    local y = ROW_Y + ROW_GAP * 3
    hud.text{ anchor = "bottom", x = -width / 2 + 1, y = y - 1, text = text, size = size, colour = SHADOW }
    hud.text{ anchor = "bottom", x = -width / 2, y = y, text = text, size = size, colour = INK }
end

hud.on_draw(function(state)
    local v = state.values
    if v.hp == nil then
        -- Nothing sent yet: the server has not welcomed this player.
        return
    end

    -- Tints first, under everything.
    if v.hurt then
        edges({ 200, 30, 30 }, 170, 120)
    end
    if v.wet and v.air < 27 then
        edges({ 10, 30, 70 }, math.min(160, 50 + math.floor((27 - v.air) * 4)), 160)
    end
    if v.extreme then
        if v.temp > 0 then edges({ 255, 110, 30 }, 120, 160) else edges({ 150, 200, 255 }, 120, 160) end
    elseif v.hot then
        edges({ 255, 130, 40 }, 70, 100)
    elseif v.cold then
        edges({ 140, 190, 255 }, 70, 100)
    end
    if v.fx and string.find(v.fx, "poison", 1, true) then
        edges({ 80, 160, 40 }, 60, 90)
    end
    if v.fx and string.find(v.fx, "wither", 1, true) then
        edges({ 40, 40, 40 }, 90, 110)
    end

    -- A creative world has no survival to show: no hearts, no cookies.
    if not v.creative then
        hearts(v.hp, v.hurt)
        cookies(v.food, v.hungry, v.starving)
        if v.air_show then
            bubbles(v.air)
        end
        if v.temp_show then
            thermometer(v.temp, v.hot, v.cold, v.extreme)
        end
    end
    if v.ghost then
        local line = "You died in this world. It goes on without you."
        hud.text{ anchor = "bottom", x = -(#line * 9.6) / 2, y = ROW_Y + ROW_GAP * 2, text = line, size = 20, colour = { 200, 200, 210, 255 } }
    elseif v.god then
        hud.text{ anchor = "bottom", x = -HALF_WIDTH, y = ROW_Y + ROW_GAP + 20, text = "Indestructible", size = 16, colour = { 255, 220, 120, 255 } }
    end

    -- The status tray, bottom right: protections, then effects above them.
    local taken = shield(v.shield)
    effects(v.fx, taken)
    toast(v.toast)
end)
