-- The Stadium UI over a host battle: finds the battle on the state stack,
-- answers the host's visibility hooks, and draws in render.hud.
--
-- Standalone: the host hides its own status HUD and bottom box through the
-- public battle.status_hud_visible / battle.bottom_ui_visible hooks while
-- this UI owns them, and hides the party menu / YES/NO it stands in for
-- through screen.render_visible. No engine function is patched.
--
-- With STADIUM2_IMPORTER installed its 3D battle composes the host HUD only
-- when that HUD is visible, so this UI replaces it there too. Portraits use
-- the importer's exported model renderer when it is present (optional).
-- If the importer's own STADIUM UI option is on, this mod stands aside so
-- the two never draw or handle input twice.
-- This mod's module root ("mods.STADIUM2_UI", or wherever it is embedded,
-- e.g. STADIUM2_IMPORTER's ui/ submodule): taken from this module's name.
local ROOT = (...):match("^(.*)%.lib%.[^%.]+$") or "mods.STADIUM2_UI"
local UI = require(ROOT .. ".lib.stadium_ui")
local Menu = require(ROOT .. ".lib.stadium_menu")
local Portrait = require(ROOT .. ".lib.stadium_portrait")
local SpritePortrait = require(ROOT .. ".lib.sprite_portrait")
local Gen1 = require(ROOT .. ".lib.host_gen1")
local Gen2 = require(ROOT .. ".lib.host_gen2")
local Effects = require(ROOT .. ".lib.screen_effects")

local BattleUI = {}

local modRef, enabledFn, warnFn
local adapter -- the adapter for the battle found last

function BattleUI.bind(mod, enabled, warn)
  modRef, enabledFn, warnFn = mod, enabled, warn
end

local function warn(message)
  if type(warnFn) == "function" then pcall(warnFn, message) end
end

-- The importer's own integrated Stadium UI, if it is switched on.
local deferReported
function BattleUI.importerOwnsUi()
  -- embedded in the importer, this IS the importer's STADIUM UI
  if BattleUI.embedded then return false end
  local Importer = package.loaded["mods.STADIUM2_IMPORTER.lib.importer"]
  if type(Importer) ~= "table" or type(Importer.stadiumUiEnabled) ~= "function" then return false end
  local ok, on = pcall(Importer.stadiumUiEnabled)
  if ok and on == true then
    if not deferReported then
      deferReported = true
      warn("STADIUM2_IMPORTER's own STADIUM UI option is on; turn it off to use this mod's UI")
    end
    return true
  end
  return false
end

local function importerExports()
  local find = modRef and modRef.find
  if type(find) ~= "function" then return nil end
  local ok, handle = pcall(find, modRef, "STADIUM2_IMPORTER")
  return ok and handle and handle.exports or nil
end

-- STADIUM2_IMPORTER presents an evolution in its 3D scene (its own camera,
-- text box and hidden host screens): this UI stands aside meanwhile.
function BattleUI.importerEvolution()
  local exports = importerExports()
  local presented = exports and exports.evolutionPresented
  if type(presented) ~= "function" then return false end
  local ok, on = pcall(presented)
  return ok and on == true
end

-- The adapter for the battle on `game`'s state stack, or nil.
function BattleUI.adapterFor(game)
  local states = game and game.stack and game.stack.states
  if type(states) ~= "table" then adapter = nil return nil end
  for i = #states, 1, -1 do
    local state = states[i]
    if Gen1.owns(state) then
      if not (adapter and adapter.battle == state) then adapter = Gen1.new(state) end
      return adapter
    elseif Gen2.owns(state) then
      if not (adapter and adapter.screen == state) then adapter = Gen2.new(state) end
      return adapter
    end
  end
  adapter = nil
  return nil
end

function BattleUI.current() return adapter end

function BattleUI.active()
  if not adapter then return false end
  if type(enabledFn) == "function" and not enabledFn() then return false end
  if BattleUI.importerOwnsUi() then return false end
  return UI.available() == true
end

-- The battle adapter when `state` is (or belongs to) the current battle.
local function forState(state)
  if not (adapter and BattleUI.active()) then return nil end
  local own = adapter.battle or adapter.screen
  if state == own or (type(state) == "table" and state.battle == own) then return adapter end
  if adapter.screen and state == adapter.screen.battle then return adapter end
  return nil
end

-- battle.status_hud_visible: the Stadium panels replace the host status HUD.
function BattleUI.statusVisible(state)
  return forState(state) == nil
end

-- battle.bottom_ui_visible: the host skips its text box / menus while the
-- Stadium message box or menus own them.
function BattleUI.bottomVisible(state)
  local a = forState(state)
  if not a then return true end
  local ok, owned = pcall(a.messageOwned, a)
  return not (ok and owned)
end

-- screen.render_visible: the host party menu / YES/NO the Stadium cards
-- stand in for.
function BattleUI.hidesState(state)
  if not (adapter and BattleUI.active()) then return false end
  if BattleUI.importerEvolution() then return false end
  local text = BattleUI.hostText()
  if text then
    for _, box in ipairs(text.hide or {}) do if box == state then return true end end
    return false
  end
  local ok, menu = pcall(adapter.menuContext, adapter)
  if not ok or not menu then return false end
  local okH, hides = pcall(adapter.hidesState, adapter, state, menu)
  return okH and hides == true
end

-- Host text the Stadium box stands in for outside the battle's own
-- messages (the evolution's texts), when no Stadium menu is open.
function BattleUI.hostText()
  if not (adapter and BattleUI.active()) or type(adapter.hostText) ~= "function" then return nil end
  if BattleUI.importerEvolution() then return nil end
  local ok, text = pcall(adapter.hostText, adapter)
  return ok and text or nil
end

function BattleUI.menuContext()
  if not (adapter and BattleUI.active()) then return nil end
  local ok, menu = pcall(adapter.menuContext, adapter)
  return ok and menu or nil
end

-- Screen area in window units: the whole window in landscape (as the
-- importer's widescreen battle), the game frame in portrait.
-- The menu kind the layout makes room for: the switch screen's held STATUS
-- card (Stadium controls) is taller than one row of cards.
function BattleUI.layoutKind(menu)
  if not menu then return nil end
  if menu.kind == "switch" and type(Menu.statusMember) == "function" and Menu.statusMember() then
    return "switchstatus"
  end
  return menu.kind
end

-- The top of the on-screen touch controls in the lower half of a window of
-- height h (nil when none are shown).
local TOUCH_CONTROLS = { "dpad", "a", "b", "start", "select" }
function BattleUI.touchControlsTop(h)
  local TC = package.loaded["src.core.TouchControls"]
  if type(TC) ~= "table" or type(TC.visible) ~= "function" or type(TC.layout) ~= "function" then return nil end
  local okV, visible = pcall(TC.visible, TC)
  if not (okV and visible) then return nil end
  local okL, L = pcall(TC.layout, TC)
  if not (okL and type(L) == "table") then return nil end
  local top
  for _, name in ipairs(TOUCH_CONTROLS) do
    local z = L[name]
    if type(z) == "table" and tonumber(z.cy) and tonumber(z.w) and z.cy > h / 2 then
      local y = z.cy - z.w / 2
      if not top or y < top then top = y end
    end
  end
  return top
end

-- Screen area in window units: the whole window in landscape (as the
-- importer's widescreen battle). Portrait: the whole width, from the top of
-- the window down to the touch controls (never above the Game Boy screen's
-- bottom), so the cards and menus use the space above the game screen and
-- the message box the space below it.
-- safe = {x, y, w, h}: the window's safe rect (notch, status bar), if known.
function BattleUI.areaFor(viewport, controlsTop, safe)
  local w, h = viewport.width or 0, viewport.height or 0
  if w >= h then return { x = 0, y = 0, w = w, h = h } end
  local left, top, width = 0, 0, w
  if safe and safe.w and safe.w > 0 and safe.h and safe.h > 0 then
    left, top, width = safe.x or 0, safe.y or 0, safe.w
  end
  local gameBottom = (viewport.gameY or 0) + (viewport.gameHeight or h)
  local bottom = h
  if safe and safe.h and safe.h > 0 then bottom = math.min(bottom, (safe.y or 0) + safe.h) end
  if controlsTop then bottom = math.min(bottom, controlsTop) end
  bottom = math.max(bottom, math.min(h, gameBottom))
  return { x = left, y = top, w = width, h = bottom - top }
end

local function safeRect()
  local ok, SafeArea = pcall(require, "src.core.SafeArea")
  if not (ok and type(SafeArea) == "table" and type(SafeArea.windowRect) == "function") then return nil end
  local okR, x, y, w, h = pcall(SafeArea.windowRect)
  if not (okR and tonumber(x) and tonumber(y) and tonumber(w) and tonumber(h)) then return nil end
  return { x = x, y = y, w = w, h = h }
end

local function areaFor(viewport)
  local w, h = viewport.width or 0, viewport.height or 0
  if w >= h then return BattleUI.areaFor(viewport) end
  return BattleUI.areaFor(viewport, BattleUI.touchControlsTop(h), safeRect())
end

-- The importer's 3D battle is on screen (its models stand in the arena).
local function modelBattle()
  local exports = importerExports()
  local current = exports and exports.getActiveBattleScene
  if type(current) ~= "function" then return false end
  local ok, scene = pcall(current)
  return ok and scene ~= nil
end

-- Is the battle drawn by a mod? Any mod that replaces the host battle's
-- drawing functions (the importer's 3D scene, voxel/art scenes, ...) makes
-- this a modded scene, which gets the Stadium layout proper; the host's own
-- scene gets the engine layout (message box under the player's sprite).
-- The importer keeps its patches installed with its 3D scene off, so its
-- functions count only while that scene is active.
-- Only the functions that draw the Pokemon themselves: UI mods patch draw
-- or drawHUDs without replacing the scene.
local DRAW_METHODS = { "drawPicsLayer", "drawAnimLayer", "drawPic" }
local reportedFor = setmetatable({}, { __mode = "k" })

local function sourceOf(fn)
  if type(fn) ~= "function" or not (debug and debug.getinfo) then return nil end
  local ok, info = pcall(debug.getinfo, fn, "S")
  return ok and info and info.source or nil
end

function BattleUI.sceneModded(state)
  if type(state) ~= "table" then return false end
  local importerScene
  for _, name in ipairs(DRAW_METHODS) do
    local source = sourceOf(state[name])
    if source and not source:match("^@?src/") then
      local modded
      if source:find("STADIUM2_IMPORTER", 1, true) then
        if importerScene == nil then importerScene = modelBattle() end
        modded = importerScene
      else
        modded = true
      end
      if modded then
        if not reportedFor[state] then
          reportedFor[state] = true
          warn(("modded battle scene (%s from %s): Stadium layout"):format(name, source))
        end
        return true
      end
    end
  end
  return modelBattle()
end

-- 3D battle: the live model portrait (importer renderer and camera data).
-- Sprite battle: the Pokemon's front sprite.
local function portraitFor(a, side, panel)
  if not (panel and panel.dex) then return nil end
  if modelBattle() then
    local exports = importerExports()
    local newRenderer = exports and exports.newRenderer
    if type(newRenderer) ~= "function" then return nil end
    return Portrait.render(side, { dex = panel.dex, variant = panel.variant,
      opponent = side == "enemy", pixels = UI.portraitPixels, newRenderer = newRenderer })
  end
  if type(a.frontSprite) ~= "function" then return nil end
  local ok, sprite = pcall(a.frontSprite, a, panel.mon)
  if not (ok and sprite) then return nil end
  return SpritePortrait.render(side, sprite, UI.portraitPixels)
end

-- render.hud: the whole Stadium UI for the current battle.
-- The normal battle scene (the host's own, not the importer's 3D battle)
-- keeps the Stadium message box up under the menus, where the host's text
-- box would otherwise leave empty space. What it says there (port
-- addition, chosen by the user): the screen's prompt, or for YES/NO the
-- question.
local UTF8_POKEMON = "POK\195\169MON"
function BattleUI.prompt(a, menu)
  if not menu then return nil end
  if menu.kind == "yesno" then return a:messageLines() end
  local okName, name = pcall(a.activeName, a)
  name = okName and name or nil
  if menu.kind == "command" then
    return { name and ("What will " .. name .. " do?") or "What will you do?" }
  elseif menu.kind == "moves" then
    return { name and ("Which move will " .. name .. " use?") or "Which move?" }
  elseif menu.kind == "stats" then
    -- the "grew to level" line stays up under the stats
    return a:messageLines()
  elseif menu.kind == "pack" then
    -- the PACK's own text (a message page, a description), else a prompt
    local okV, view = pcall(a.packView, a, menu)
    if okV and view then
      if view.message and #view.message > 0 then return view.message end
      if view.description then return view.description end
    end
    return { "Use which item?" }
  elseif menu.kind == "switch" then
    -- the host party menu's own prompt (item use, forced switch, ...)
    local okP, text = pcall(a.partyPrompt, a, menu.menu)
    if okP and text then
      local lines = {}
      for line in text:gmatch("[^\n]+") do lines[#lines + 1] = line end
      if #lines > 0 then return lines end
    end
    return { "Choose a " .. UTF8_POKEMON .. "." }
  end
  return nil
end

-- Normal battle scene: the message box sits in the Game Boy screen's own
-- text area, just under the player's sprite box (both games end it at
-- row 96 of 144), centred on the Game Boy screen, at Stadium's size where
-- it fits (height trimmed to the space under the sprite).
BattleUI.SPRITE_BOTTOM = 96
-- The host's WIDE battle layout (OPTION -> BATTLE LAYOUT -> WIDE) draws a
-- 304x144 screen whose battlefield ends at row 104.
BattleUI.WIDE_SPRITE_BOTTOM = 104
function BattleUI.engineMessageRect(area, viewport, spriteBottom)
  local place = UI.placement(area)
  local k = place.scale
  local s = (viewport.gameHeight or 144) / 144
  local gx, gy = viewport.gameX or 0, viewport.gameY or 0
  local frame = 4 * k -- the card's bracket frame and shadow around its body
  local top = gy + (spriteBottom or BattleUI.SPRITE_BOTTOM) * s + frame
  local bottom = math.min(gy + 144 * s, area.y + area.h) - frame
  local h = math.min(UI.MESSAGE.h * k, bottom - top)
  local cx = gx + (viewport.gameWidth or 160 * s) / 2
  local half = math.min(UI.MESSAGE.w * k / 2, cx - area.x - frame, area.x + area.w - cx - frame)
  if half <= 20 * k or h <= 14 * k then return nil, k end
  return { x = cx - half, y = top, w = half * 2, h = h }, k
end

local function overlaps(a, b)
  return a and b and a.x < b.x + b.w and a.x + a.w > b.x and a.y < b.y + b.h and a.y + a.h > b.y
end
BattleUI.overlaps = overlaps

-- Window rectangle of the open menu (its frames and hints included).
function BattleUI.menuRect(area, kind, rows)
  local place = UI.placement(area)
  local k = place.scale
  return { x = place.menuX + UI.MENU_LEFT * k, y = place.top,
    w = (UI.menuRight(kind) - UI.MENU_LEFT) * k, h = UI.menuBottom(kind, rows) * k }
end

-- Stage offset of the opponent's column in the cards' normal layout:
-- bottom-anchored (the screen's extra height), moved down clear of the menu
-- and up clear of a message box, within the screen. Returns dy, compact:
-- compact means only the card and tag fit (portrait and balls are left out
-- for that moment); nil when not even the card fits (hidden for that
-- moment rather than overlapping).
function BattleUI.enemyOffset(area, menuKind, rows, box)
  local place = UI.placement(area)
  local k = place.scale
  local p = UI.PANEL.enemy
  local bottom = p.tagY + p.tagH + 7
  local menu = menuKind and BattleUI.menuRect(area, menuKind, rows) or nil
  for _, compact in ipairs({ false, true }) do
    local top = compact and (p.y - 4) or (p.y - 45)
    local dy = place.slack
    if menu and overlaps(UI.enemyColumnRect(area, dy, compact), menu) then
      dy = math.max(dy, UI.menuBottom(menuKind, rows) + 2 - top)
    end
    if box and overlaps(UI.enemyColumnRect(area, dy, compact), box) then
      dy = math.min(dy, math.floor((box.y - place.top) / k - 2 - bottom))
    end
    dy = math.min(dy, place.slack + 240 - bottom)
    local column = UI.enemyColumnRect(area, dy, compact)
    if column.y >= area.y and not overlaps(column, menu) and not overlaps(column, box) then
      return dy, compact
    end
  end
  return nil
end

-- ------------------------------------------------------------------
-- The default engine scene: the host draws the whole battle into one
-- 160x144 picture, so a Pokemon cannot be moved on its own. Its sprite box
-- can: render.compose hands this mod the frame's picture (Gen 1: the game
-- canvas and its palette zones; Gen 2: the finished frame), and before the
-- UI is drawn each box that would touch the UI is covered with the
-- background and drawn again, moved just far enough (the opponent's down or
-- left, the player's right or up), gliding when a menu opens or closes.
-- Anything drawn over a box (a hit effect) moves with it.
BattleUI.ENEMY_BOX = { 96, 0, 56, 56 }
BattleUI.PLAYER_BOX = { 8, 40, 56, 56 }
BattleUI.MAX_MOVE = 40            -- Game Boy pixels
BattleUI.GLIDE = 12               -- per second (exponential ease)

local captured -- this frame's render.compose picture
function BattleUI.capture(renderer, ctx)
  captured = ctx and { renderer = renderer, ctx = ctx } or nil
  return false
end

-- Candidate moves nearest first: the opponent's box goes down or left, the
-- player's right or up (away from the menus and cards, inside the field).
local function candidates(xs, ys)
  local list = {}
  for dx = xs[1], xs[2], xs[3] do
    for dy = ys[1], ys[2], ys[3] do list[#list + 1] = { dx, dy, dx * dx + dy * dy } end
  end
  table.sort(list, function(a, b) return a[3] < b[3] end)
  return list
end
-- The opponent's box may go down to row 96 (the top of the Game Boy text
-- area) with the prompt box up, or to the screen's last row without it.
BattleUI.MAX_DOWN_NO_BOX = 144 - 56
-- ...and sideways from 40 left to the screen's right edge (8 px).
local ENEMY_MOVES = candidates({ 8, -BattleUI.MAX_MOVE, -2 }, { 0, BattleUI.MAX_MOVE, 2 })
local ENEMY_MOVES_NO_BOX = candidates({ 8, -BattleUI.MAX_MOVE, -2 }, { 0, BattleUI.MAX_DOWN_NO_BOX, 2 })
-- The player's box has the open middle of the field to its right (up to
-- x 154 of 160); square windows put its card right above it.
BattleUI.MAX_RIGHT = 90
local PLAYER_MOVES = candidates({ 0, BattleUI.MAX_RIGHT, 2 }, { 0, -BattleUI.MAX_MOVE, -2 })
-- with the prompt box out of the way the player's box may also go down,
-- into the Game Boy text area (to the screen's last row)
local PLAYER_MOVES_NO_BOX = candidates({ 0, BattleUI.MAX_RIGHT, 2 }, { 144 - 96, -BattleUI.MAX_MOVE, -2 })

-- Inset half a window pixel: a box that only touches the UI's edge (the
-- player's box ending on row 96, the engine box starting there) is clear;
-- rounding must not move it (a moved copy leaves the pic's last rows behind).
local function boxRect(g, box, dx, dy, top)
  local y0 = box[2] + (top or 0)
  return { x = g.x + (box[1] + dx) * g.s + .5, y = g.y + (y0 + dy) * g.s + .5,
    w = box[3] * g.s - 1, h = (box[2] + box[4] - y0) * g.s - 1 }
end

-- The moves (Game Boy pixels) that keep each box clear of `obstacles`.
-- game = {x, y, s} (window units per Game Boy pixel); enemyTop = blank rows
-- at the top of the opponent's box (its sprite's visible top).
local function overlapArea(a, b)
  if not overlaps(a, b) then return 0 end
  local w = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
  local h = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
  return w * h
end

-- The nearest clear move; with none (a tiny window), the move that leaves
-- the least overlap. Returns the move and whether it is clear.
local function bestMove(list, rectFor, obstacles, extra)
  local best, bestArea
  for _, m in ipairs(list) do
    local r = rectFor(m[1], m[2])
    local area = extra and overlapArea(r, extra) or 0
    for _, o in pairs(obstacles) do area = area + overlapArea(r, o) end
    if area == 0 then return { m[1], m[2] }, true end
    if not bestArea or area < bestArea then best, bestArea = { m[1], m[2] }, area end
  end
  return best or { 0, 0 }, false
end

-- farDown: the prompt box is out of the way, so the opponent may go lower.
-- The two boxes are chosen together: among the opponent's nearest clear
-- places, the first that also leaves the player's box a clear place.
local JOINT_TRIES = 48
function BattleUI.spriteMoves(game, obstacles, enemyTop, farDown)
  local enemyBox = game.enemyBox or BattleUI.ENEMY_BOX
  local playerBox = game.playerBox or BattleUI.PLAYER_BOX
  local function enemyRect(m) return boxRect(game, enemyBox, m[1], m[2], enemyTop) end
  local function playerFor(er)
    return bestMove(farDown and PLAYER_MOVES_NO_BOX or PLAYER_MOVES, function(dx, dy)
      return boxRect(game, playerBox, dx, dy)
    end, obstacles, er)
  end
  local tried = 0
  local firstEnemy
  for _, m in ipairs(farDown and ENEMY_MOVES_NO_BOX or ENEMY_MOVES) do
    local er = enemyRect(m)
    local clear = true
    for _, o in pairs(obstacles) do if overlaps(er, o) then clear = false break end end
    if clear then
      firstEnemy = firstEnemy or { m[1], m[2] }
      local player, playerClear = playerFor(er)
      if playerClear then return { m[1], m[2] }, player, true, true end
      tried = tried + 1
      if tried >= JOINT_TRIES then break end
    end
  end
  -- no pair is clear: the opponent's nearest clear place (or its least
  -- overlapping one) and the player's least overlapping place
  local enemy, enemyClear = firstEnemy, firstEnemy ~= nil
  if not enemy then
    enemy = bestMove(farDown and ENEMY_MOVES_NO_BOX or ENEMY_MOVES, function(dx, dy)
      return enemyRect({ dx, dy })
    end, obstacles)
  end
  local player, playerClear = playerFor(enemyRect(enemy))
  return enemy, player, enemyClear, playerClear
end

-- Whether both boxes, moved by e and p, are clear of every obstacle.
function BattleUI.movesClear(game, obstacles, enemyTop, e, p)
  local er = boxRect(game, game.enemyBox or BattleUI.ENEMY_BOX, e[1], e[2], enemyTop)
  local pr = boxRect(game, game.playerBox or BattleUI.PLAYER_BOX, p[1], p[2])
  for _, o in pairs(obstacles) do
    if overlaps(er, o) or overlaps(pr, o) then return false end
  end
  return true
end

-- Menus that may cover the sprite boxes: the move diamond and the party
-- cards are brief picks, so the sprites hold where they were rather than
-- moving again for them (only the prompt box and cards still push them).
BattleUI.MENUS_OVER_SPRITES = { moves = true, switch = true, pack = true, stats = true }

-- Blank rows at the top of the opponent's box: its sprite stands on the
-- box's bottom edge (both games bottom-align front pics in the 7x7 slot).
local function enemyTop(a)
  local ok, image = pcall(a.enemyImage, a)
  if not (ok and image and image.getDimensions) then return 0 end
  local _, h = image:getDimensions()
  if h > 56 then return 0 end
  local b = SpritePortrait.contentBounds(love.graphics, image)
  return math.max(0, 56 - h + (b and b[2] or 0))
end

local glide = { enemy = { 0, 0 }, player = { 0, 0 } }
-- the targets last chosen (held while a menu that may cover them is up)
local held
local function ease(cur, target, dt)
  local t = math.min(1, dt * BattleUI.GLIDE)
  cur[1] = cur[1] + (target[1] - cur[1]) * t
  cur[2] = cur[2] + (target[2] - cur[2]) * t
  if math.abs(cur[1] - target[1]) < 0.05 then cur[1] = target[1] end
  if math.abs(cur[2] - target[2]) < 0.05 then cur[2] = target[2] end
end

local function paper(a)
  local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
  if okP and PaletteFX.paperShade then
    local game = a:game()
    local ok, r, gg, b = pcall(PaletteFX.paperShade, game and game.data)
    if ok and r then return r, gg, b end
  end
  return 1, 1, 1
end

-- Gen 1's paper as this frame shows it: a white picture put through the
-- battle's own zone pass (BattleState:drawZonePass), so a full-screen palette
-- effect (Night Shade's flash, a dark screen) colours the cover the way it
-- colours the field around it. nil when the host cannot (no colour pipeline).
local paperSrc, paperCanvas
local function paperPicture(a)
  local battle = a.battle
  if not (battle and type(battle.drawZonePass) == "function"
      and type(battle.colorMode) == "function") then return nil end
  local okC, colour = pcall(battle.colorMode, battle)
  if not (okC and colour) then return nil end
  local g = love.graphics
  if not paperSrc then
    local okP = pcall(function()
      local data = love.image.newImageData(160, 144)
      data:mapPixel(function() return 1, 1, 1, 1 end)
      local src = g.newImage(data)
      local canvas = g.newCanvas(160, 144)
      pcall(canvas.setFilter, canvas, "nearest", "nearest")
      paperSrc, paperCanvas = src, canvas
    end)
    if not okP then return nil end
  end
  local prev = g.getCanvas()
  g.push()
  g.origin()
  g.setCanvas(paperCanvas)
  g.clear(1, 1, 1, 1)
  local ok = pcall(battle.drawZonePass, battle, paperSrc, 0, 0)
  g.setCanvas(prev)
  g.pop()
  g.setShader()
  g.setScissor()
  return ok and paperCanvas or nil
end

-- Cover the boxes and draw them moved (this frame's captured picture).
local function drawMoved(a, game, moves)
  local frame = captured
  if not frame then return end
  local g = love.graphics
  local ctx = frame.ctx
  g.push("all")
  local ok, err = pcall(function()
    g.setShader()
    g.setScissor()
    local gen2 = ctx.generation == 2 and ctx.sceneCanvas
    local scene = gen2 and ctx.sceneCanvas
    local sw, sh
    if gen2 then sw, sh = scene:getDimensions() end
    local paperPic = not gen2 and paperPicture(a) or nil
    -- the backgrounds first, then the moved boxes (a box may move over the
    -- other's old place)
    for _, m in ipairs(moves) do
      local from = boxRect(game, m.box, 0, 0)
      if gen2 then
        -- Gold's paper: the blank top-left corner of its own frame
        local q = g.newQuad(ctx.ox + 1 * ctx.scale, ctx.oy + 1 * ctx.scale, 1, 1, sw, sh)
        g.setColor(1, 1, 1, 1)
        g.draw(scene, q, from.x, from.y, 0, from.w, from.h)
        q:release()
      elseif paperPic then
        g.setColor(1, 1, 1, 1)
        frame.renderer:blitCanvas(paperPic, game.s, game.s, ctx.zones, game.s, game.s,
          game.x, game.y, from.x, from.y, from.w, from.h, ctx.dpiX, ctx.dpiY)
      else
        g.setColor(paper(a))
        g.rectangle("fill", from.x, from.y, from.w, from.h)
      end
    end
    g.setColor(1, 1, 1, 1)
    for _, m in ipairs(moves) do
      local to = boxRect(game, m.box, m.dx, m.dy)
      if gen2 then
        local s = ctx.scale
        local q = g.newQuad(ctx.ox + m.box[1] * s, ctx.oy + m.box[2] * s, m.box[3] * s, m.box[4] * s, sw, sh)
        g.draw(scene, q, to.x, to.y, 0, game.s / s, game.s / s)
        q:release()
      else
        frame.renderer:blitCanvas(ctx.uiCanvas, game.s, game.s, ctx.zones, game.s, game.s,
          game.x + m.dx * game.s, game.y + m.dy * game.s, to.x, to.y, to.w, to.h, ctx.dpiX, ctx.dpiY)
      end
    end
  end)
  g.pop()
  if not ok then warn("sprite move failed: " .. tostring(err)) end
end

-- The engine scene this frame (the host's own classic scene, no world
-- backdrop, and render.compose delivered its picture).
local function spritesMovable(a)
  local frame = captured
  if not (frame and frame.ctx) or frame.ctx.worldActive then return false end
  local state = a.battle or a.screen
  if type(state.isWideBattleLayout) == "function" then
    local ok, wide = pcall(state.isWideBattleLayout, state)
    if ok and wide then return false end
  end
  return true
end

function BattleUI.enemyPortraitOverGame(area, viewport, shift)
  local place = UI.placement(area)
  local k = place.scale
  local p = UI.PANEL.enemy
  local x = place.right + (p.x + 31) * k
  local y = place.top + (p.y + (shift or 0) - 35) * k
  local gx, gy = viewport.gameX or 0, viewport.gameY or 0
  local gw, gh = viewport.gameWidth or 0, viewport.gameHeight or 0
  return x < gx + gw and x + 32 * k > gx and y < gy + gh and y + 32 * k > gy
end

-- Gen 1's EXP lands at once (no bar in the game): the Stadium bar climbs to
-- it, filling and starting over for each level gained. Gen 2's host bar
-- already crawls, so its value is shown as it is.
BattleUI.EXP_RATE = 1.2 -- bar lengths per second
local expShown
function BattleUI.expGlide(mon, level, target, dt)
  if not (mon and level and target) then expShown = nil return target end
  local s = expShown
  if not s or s.mon ~= mon or level < s.level or level > s.level + 5 then
    expShown = { mon = mon, level = level, value = target }
    return target
  end
  local step = BattleUI.EXP_RATE * (dt or 0)
  if level > s.level then
    s.value = s.value + step
    if s.value >= 1 then s.level, s.value = s.level + 1, 0 end
  elseif target < s.value then s.value = target
  else s.value = math.min(target, s.value + step) end
  return s.level < level and s.value or math.min(s.value, target)
end

-- When the Stadium UI last drew (the Gen 2 stats box cover only holds
-- while it is drawing).
local lastDraw = -math.huge
local function now() return love and love.timer and love.timer.getTime and love.timer.getTime() or 0 end
function BattleUI.drawing(a)
  return adapter == a and BattleUI.active() and now() - lastDraw < 0.25
end

local enemyPanelRect -- where the opponent's card was drawn last (screen effects)
local function drawBody(game, viewport)
  local a = BattleUI.adapterFor(game)
  if not (a and viewport and BattleUI.active()) then return false end
  lastDraw = now()
  if BattleUI.importerEvolution() then return true end
  if type(a.coverStatsBox) == "function" then
    pcall(a.coverStatsBox, a, function() return BattleUI.drawing(a) end)
  end
  if a.track then pcall(a.track, a) end
  local area = areaFor(viewport)
  local menu = BattleUI.menuContext()
  local okOwned, owned = pcall(a.messageOwned, a)
  owned = okOwned and owned
  -- normal battle scene: the message box sits under the sprite box, and
  -- stays up under the menus with the screen's prompt
  local engineScene = not BattleUI.sceneModded(a.battle or a.screen)
  if engineScene and BattleUI.onEngineScene then pcall(BattleUI.onEngineScene) end
  local frame = captured
  captured = nil
  local engineRect, engineK
  if engineScene then
    local state = a.battle or a.screen
    local wide = type(state.isWideBattleLayout) == "function" and pcall(state.isWideBattleLayout, state)
      and state:isWideBattleLayout()
    engineRect, engineK = BattleUI.engineMessageRect(area, viewport,
      wide and BattleUI.WIDE_SPRITE_BOTTOM or BattleUI.SPRITE_BOTTOM)
  end
  local function drawBox(lines, side)
    if engineScene then
      if engineRect then return UI.tryDrawMessageAt(engineRect, engineK, lines, side, warn) end
      return false
    end
    return UI.tryDrawMessage(area, lines, side, warn)
  end
  -- the evolution's texts: only the Stadium box (no cards, no moved sprite
  -- boxes over the evolution scene)
  local hostText = not menu and BattleUI.hostText() or nil
  if hostText then
    if type(a.coverHostText) == "function" then
      pcall(a.coverHostText, a, hostText, function() return BattleUI.drawing(a) end)
    end
    if hostText.lines and #hostText.lines > 0 then drawBox(hostText.lines, "player") end
    return true
  end
  -- a box shown with a menu: the switch screen's refusal message, or in
  -- the normal battle scene the screen's prompt
  local rows = 1
  local refusal
  if menu and menu.kind == "switch" then
    local okM, members = pcall(a.members, a, menu.menu)
    rows = okM and math.max(1, math.ceil(#members / 3)) or 1
    local okV, view = pcall(a.menuView, a, menu)
    refusal = okV and type(view.message) == "string" and view.message ~= "" and view.message or nil
  end
  if menu and menu.kind == "pack" then
    -- a PACK message holds the pack like a refusal (it always stays up)
    local okV, view = pcall(a.packView, a, menu)
    if okV and view and view.message and #view.message > 0 then
      refusal = table.concat(view.message, "\n")
    end
  end
  local boxLines
  if refusal then
    boxLines = {}
    for line in refusal:gmatch("[^\n]+") do boxLines[#boxLines + 1] = line end
  elseif menu and (engineScene or menu.kind == "switch" or menu.kind == "pack") then
    -- the engine scene keeps the screen's prompt up; every scene shows the
    -- party menu's (so an item's target is always clear)
    boxLines = BattleUI.prompt(a, menu)
  end
  local okPanels, panels = pcall(a.panels, a)
  if not okPanels then panels = nil end
  -- Outside the engine scene a plain switch keeps the opponent's card ahead
  -- of its prompt; choosing an item's target always shows the prompt.
  if boxLines and not refusal and not engineScene and menu.kind == "switch"
    and panels and panels.enemy and not panels.enemy.ballsOnly
    and BattleUI.enemyOffset(area, "switch", rows, UI.messageRect(area)) == nil then
    local okI, itemUse = pcall(a.partyItemUse, a, menu.menu)
    if not (okI and itemUse) then boxLines = nil end
  end
  local messageBox = boxLines or (owned and not menu)
  local boxRect
  if boxLines then boxRect = engineScene and engineRect or UI.messageRect(area) end
  if panels then
    for _, side in ipairs({ "player", "enemy" }) do
      local p = panels[side]
      if p and not p.ballsOnly then
        -- a portrait the device refuses is left out; the rest still draws
        local okPortrait, portrait = pcall(portraitFor, a, side, p)
        p.portrait = okPortrait and portrait or nil
        if not okPortrait then warn("portrait failed: " .. tostring(portrait)) end
      end
    end
    -- the opponent's column moves clear of the menu and of any box
    if panels.enemy and not (owned and not menu) then
      local dy, compact = BattleUI.enemyOffset(area, menu and BattleUI.layoutKind(menu), rows, boxRect)
      if dy == nil then panels.enemy = nil
      else
        panels.enemy.shiftY, panels.enemy.compact = dy, compact
        if engineScene and BattleUI.enemyPortraitOverGame(area, viewport, dy) then
          panels.enemy.portrait = nil
        end
      end
    end
  end
  enemyPanelRect = panels and panels.enemy
    and UI.enemyColumnRect(area, panels.enemy.shiftY or 0, panels.enemy.compact) or nil
  if panels and panels.player and panels.player.exp and a.battle then
    local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
    panels.player.exp = BattleUI.expGlide(panels.player.mon, panels.player.level, panels.player.exp, dt)
  end
  -- engine scene: move the sprite boxes clear of everything drawn below
  captured = frame
  if engineScene and spritesMovable(a) then
    local k = UI.placement(area).scale
    local obstacles = {}
    local overSprites = menu and BattleUI.MENUS_OVER_SPRITES[menu.kind]
    if menu and not overSprites then obstacles.menu = BattleUI.menuRect(area, menu.kind, rows) end
    if engineRect and messageBox then
      obstacles.box = { x = engineRect.x - 4 * k, y = engineRect.y - 4 * k,
        w = engineRect.w + 8 * k, h = engineRect.h + 8 * k }
    end
    local messageLayout = owned and not menu
    local place = UI.placement(area)
    if panels and panels.player then
      obstacles.player = messageLayout
        and { x = place.left + 21 * k, y = place.top + 15 * k, w = 75 * k, h = 69 * k }
        or { x = place.left + 21 * k, y = place.top + 15 * k, w = 75 * k, h = UI.PLAYER_COLUMN_H * k }
    end
    if panels and panels.enemy then
      obstacles.enemy = messageLayout
        and { x = place.right + 228 * k, y = place.top + 15 * k, w = 75 * k, h = 69 * k }
        or UI.enemyColumnRect(area, panels.enemy.shiftY or 0, panels.enemy.compact)
    end
    local boxes = type(a.spriteBoxes) == "function" and a:spriteBoxes() or {}
    local gameRect = { x = viewport.gameX or 0, y = viewport.gameY or 0,
      s = (viewport.gameWidth or 160) / 160,
      enemyBox = boxes.enemy or BattleUI.ENEMY_BOX, playerBox = boxes.player or BattleUI.PLAYER_BOX }
    local top = enemyTop(a)
    local enemyTarget, playerTarget, eClear, pClear
    if overSprites and held and BattleUI.movesClear(gameRect, obstacles, top, held.enemy, held.player) then
      enemyTarget, playerTarget, eClear, pClear = held.enemy, held.player, true, true
    else
      enemyTarget, playerTarget, eClear, pClear = BattleUI.spriteMoves(gameRect, obstacles, top)
    end
    -- No clean place: first the cards leave out their portrait and balls
    -- for that moment (the prompt stays up), and only then does the prompt
    -- step aside so the sprites can go lower (battle messages always stay).
    local compactObstacles
    if not (eClear and pClear) and not messageLayout then
      compactObstacles = {}
      for n, o in pairs(obstacles) do compactObstacles[n] = o end
      if panels and panels.player then
        compactObstacles.player = { x = place.left + 21 * k, y = place.top + 15 * k, w = 75 * k, h = 69 * k }
      end
      if panels and panels.enemy then
        compactObstacles.enemy = UI.enemyColumnRect(area, panels.enemy.shiftY or 0, true)
      end
      local e2, p2, c1, c2 = BattleUI.spriteMoves(gameRect, compactObstacles, top)
      if c1 and c2 then
        enemyTarget, playerTarget, eClear, pClear = e2, p2, true, true
        if panels.player then panels.player.compact = true end
        if panels.enemy then panels.enemy.compact = true end
      end
    end
    if not (eClear and pClear) and boxLines and not refusal and obstacles.box then
      local without = {}
      for n, o in pairs(compactObstacles or obstacles) do if n ~= "box" then without[n] = o end end
      local e2, p2, e2Clear, p2Clear = BattleUI.spriteMoves(gameRect, without, top, true)
      if e2Clear and p2Clear then
        enemyTarget, playerTarget = e2, p2
        boxLines = nil
        if compactObstacles then
          if panels.player then panels.player.compact = true end
          if panels.enemy then panels.enemy.compact = true end
        end
      end
    end
    held = { enemy = enemyTarget, player = playerTarget }
    local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
    ease(glide.enemy, enemyTarget, dt)
    ease(glide.player, playerTarget, dt)
    local moves = {}
    if glide.enemy[1] ~= 0 or glide.enemy[2] ~= 0 then
      moves[#moves + 1] = { box = gameRect.enemyBox, dx = glide.enemy[1], dy = glide.enemy[2] }
    end
    if glide.player[1] ~= 0 or glide.player[2] ~= 0 then
      moves[#moves + 1] = { box = gameRect.playerBox, dx = glide.player[1], dy = glide.player[2] }
    end
    -- the moved boxes are copies of the already affected Game Boy frame:
    -- straight to the screen, not through the screen effects again
    if #moves > 0 then Effects.direct(function() drawMoved(a, gameRect, moves) end) end
  end
  captured = nil
  if boxLines then drawBox(boxLines, "player") end
  if panels then UI.tryDrawPanels(area, panels, warn, owned and not menu) end
  if menu then
    local okMoves, moves = true, nil
    if menu.kind == "moves" then okMoves, moves = pcall(a.moves, a) end
    local view = a:menuView(menu)
    view.kind, view.tabs, view.game = menu.kind, menu.tabs, game
    view.mode = BattleUI.menuMode and BattleUI.menuMode() or "cursor"
    view.moves = okMoves and moves or nil
    if menu.kind == "switch" then view.members, view.message = a:members(menu.menu), nil end
    if menu.kind == "yesno" then view.lines, view.yesIndex = a:messageLines(), menu.yesIndex end
    if menu.kind == "stats" then
      local okS, stats = pcall(a.statsView, a, menu)
      if okS and stats then view.name, view.level, view.rows = stats.name, stats.level, stats.rows end
    end
    if menu.kind == "pack" then
      local okP, pack = pcall(a.packView, a, menu)
      if okP and pack then for key, value in pairs(pack) do view[key] = value end end
      view.message = nil
    end
    UI.tryDrawMenu(area, function() Menu.draw(view) end, warn)
  elseif owned then
    -- messages: both cards move to the top row, so the box has the width
    drawBox(a:messageLines(), a:messageSide())
  end
  return true
end

-- The engine's full-screen effects this frame (normal battle scene only: the
-- importer's 3D battle has Stadium's own), or nil. PORT ADDITION.
local function screenEffects(a)
  if not (a and type(a.screenEffects) == "function") then return nil end
  if BattleUI.sceneModded(a.battle or a.screen) then return nil end
  local ok, d = pcall(a.screenEffects, a)
  d = ok and type(d) == "table" and d or {}
  -- the host's own veil (battle-entry flash, fade from white) is painted
  -- under the UI; the UI takes it too, the stronger of it and the battle's
  local veil = Effects.hostVeil()
  if veil and (veil[4] or 0) > ((d.veil and d.veil[4]) or 0) then d.veil = veil end
  return d
end

function BattleUI.draw(game, viewport)
  local a = BattleUI.adapterFor(game)
  local through = false
  if a and viewport and BattleUI.active() then
    local okB, began = pcall(function() return Effects.begin(screenEffects(a), viewport, enemyPanelRect) end)
    through = okB and began
  end
  local ok, result = pcall(drawBody, game, viewport)
  if through then
    local okF, err = pcall(Effects.finish)
    if not okF then warn("screen effects failed: " .. tostring(err)) end
  end
  if not ok then error(result, 0) end
  return result
end

function BattleUI.release()
  if adapter and type(adapter.release) == "function" then pcall(adapter.release, adapter) end
  glide = { enemy = { 0, 0 }, player = { 0, 0 } }
  held = nil
  expShown = nil
  captured = nil
  enemyPanelRect = nil
  Effects.release()
  Portrait.release()
  SpritePortrait.release()
  adapter, deferReported = nil, nil
end

return BattleUI
