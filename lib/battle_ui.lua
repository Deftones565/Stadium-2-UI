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
local UI = require("mods.STADIUM2_UI.lib.stadium_ui")
local Menu = require("mods.STADIUM2_UI.lib.stadium_menu")
local Portrait = require("mods.STADIUM2_UI.lib.stadium_portrait")
local SpritePortrait = require("mods.STADIUM2_UI.lib.sprite_portrait")
local Gen1 = require("mods.STADIUM2_UI.lib.host_gen1")
local Gen2 = require("mods.STADIUM2_UI.lib.host_gen2")

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
  local ok, menu = pcall(adapter.menuContext, adapter)
  if not ok or not menu then return false end
  local okH, hides = pcall(adapter.hidesState, adapter, state, menu)
  return okH and hides == true
end

function BattleUI.menuContext()
  if not (adapter and BattleUI.active()) then return nil end
  local ok, menu = pcall(adapter.menuContext, adapter)
  return ok and menu or nil
end

-- Screen area in window units: the whole window in landscape (as the
-- importer's widescreen battle), the game frame in portrait.
local function areaFor(viewport)
  local w, h = viewport.width or 0, viewport.height or 0
  if w >= h then return { x = 0, y = 0, w = w, h = h } end
  return { x = viewport.gameX or 0, y = viewport.gameY or 0,
    w = viewport.gameWidth or w, h = viewport.gameHeight or h }
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
  elseif menu.kind == "switch" then
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
    w = (UI.MENU_RIGHT - UI.MENU_LEFT) * k, h = UI.menuBottom(kind, rows) * k }
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
local ENEMY_MOVES = candidates({ 0, -BattleUI.MAX_MOVE, -2 }, { 0, BattleUI.MAX_MOVE, 2 })
local ENEMY_MOVES_NO_BOX = candidates({ 0, -BattleUI.MAX_MOVE, -2 }, { 0, BattleUI.MAX_DOWN_NO_BOX, 2 })
local PLAYER_MOVES = candidates({ 0, BattleUI.MAX_MOVE, 2 }, { 0, -BattleUI.MAX_MOVE, -2 })

local function boxRect(g, box, dx, dy, top)
  local y0 = box[2] + (top or 0)
  return { x = g.x + (box[1] + dx) * g.s, y = g.y + (y0 + dy) * g.s,
    w = box[3] * g.s, h = (box[2] + box[4] - y0) * g.s }
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
function BattleUI.spriteMoves(game, obstacles, enemyTop, farDown)
  local enemy, enemyClear = bestMove(farDown and ENEMY_MOVES_NO_BOX or ENEMY_MOVES, function(dx, dy)
    return boxRect(game, BattleUI.ENEMY_BOX, dx, dy, enemyTop)
  end, obstacles)
  local enemyRect = boxRect(game, BattleUI.ENEMY_BOX, enemy[1], enemy[2], enemyTop)
  local player, playerClear = bestMove(PLAYER_MOVES, function(dx, dy)
    return boxRect(game, BattleUI.PLAYER_BOX, dx, dy)
  end, obstacles, enemyRect)
  return enemy, player, enemyClear, playerClear
end

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

function BattleUI.draw(game, viewport)
  local a = BattleUI.adapterFor(game)
  if not (a and viewport and BattleUI.active()) then return false end
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
  local boxLines
  if refusal then
    boxLines = {}
    for line in refusal:gmatch("[^\n]+") do boxLines[#boxLines + 1] = line end
  elseif menu and engineScene then
    boxLines = BattleUI.prompt(a, menu)
  end
  local messageBox = boxLines or (owned and not menu)
  local boxRect
  if boxLines then boxRect = engineScene and engineRect or UI.messageRect(area) end
  local okPanels, panels = pcall(a.panels, a)
  if not okPanels then panels = nil end
  if panels then
    for _, side in ipairs({ "player", "enemy" }) do
      local p = panels[side]
      if p and not p.ballsOnly then p.portrait = portraitFor(a, side, p) end
    end
    -- the opponent's column moves clear of the menu and of any box
    if panels.enemy and not (owned and not menu) then
      local dy, compact = BattleUI.enemyOffset(area, menu and menu.kind, rows, boxRect)
      if dy == nil then panels.enemy = nil
      else
        panels.enemy.shiftY, panels.enemy.compact = dy, compact
        if engineScene and BattleUI.enemyPortraitOverGame(area, viewport, dy) then
          panels.enemy.portrait = nil
        end
      end
    end
  end
  -- engine scene: move the sprite boxes clear of everything drawn below
  captured = frame
  if engineScene and spritesMovable(a) then
    local k = UI.placement(area).scale
    local obstacles = {}
    if menu then obstacles.menu = BattleUI.menuRect(area, menu.kind, rows) end
    if engineRect and messageBox then
      obstacles.box = { x = engineRect.x - 4 * k, y = engineRect.y - 4 * k,
        w = engineRect.w + 8 * k, h = engineRect.h + 8 * k }
    end
    local messageLayout = owned and not menu
    local place = UI.placement(area)
    if panels and panels.player then
      obstacles.player = messageLayout
        and { x = place.left + 21 * k, y = place.top + 15 * k, w = 75 * k, h = 69 * k }
        or { x = place.left + 21 * k, y = place.top + 15 * k, w = 75 * k, h = 112 * k }
    end
    if panels and panels.enemy then
      obstacles.enemy = messageLayout
        and { x = place.right + 228 * k, y = place.top + 15 * k, w = 75 * k, h = 69 * k }
        or UI.enemyColumnRect(area, panels.enemy.shiftY or 0, panels.enemy.compact)
    end
    local gameRect = { x = viewport.gameX or 0, y = viewport.gameY or 0,
      s = (viewport.gameWidth or 160) / 160 }
    local top = enemyTop(a)
    local enemyTarget, playerTarget, eClear, pClear = BattleUI.spriteMoves(gameRect, obstacles, top)
    -- a big Pokemon with a tall menu open: the prompt steps aside for that
    -- moment so the sprite can move clear (battle messages always stay)
    if not (eClear and pClear) and boxLines and not refusal and obstacles.box then
      local without = {}
      for n, o in pairs(obstacles) do if n ~= "box" then without[n] = o end end
      local e2, p2, e2Clear, p2Clear = BattleUI.spriteMoves(gameRect, without, top, true)
      if e2Clear and p2Clear then
        enemyTarget, playerTarget = e2, p2
        boxLines = nil
      end
    end
    local dt = love.timer and love.timer.getDelta and love.timer.getDelta() or 1 / 60
    ease(glide.enemy, enemyTarget, dt)
    ease(glide.player, playerTarget, dt)
    local moves = {}
    if glide.enemy[1] ~= 0 or glide.enemy[2] ~= 0 then
      moves[#moves + 1] = { box = BattleUI.ENEMY_BOX, dx = glide.enemy[1], dy = glide.enemy[2] }
    end
    if glide.player[1] ~= 0 or glide.player[2] ~= 0 then
      moves[#moves + 1] = { box = BattleUI.PLAYER_BOX, dx = glide.player[1], dy = glide.player[2] }
    end
    if #moves > 0 then drawMoved(a, gameRect, moves) end
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
    UI.tryDrawMenu(area, function() Menu.draw(view) end, warn)
  elseif owned then
    -- messages: both cards move to the top row, so the box has the width
    drawBox(a:messageLines(), a:messageSide())
  end
  return true
end

function BattleUI.release()
  glide = { enemy = { 0, 0 }, player = { 0, 0 } }
  captured = nil
  Portrait.release()
  SpritePortrait.release()
  adapter, deferReported = nil, nil
end

return BattleUI
