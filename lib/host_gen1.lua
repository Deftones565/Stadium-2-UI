-- Gen 1 (src.battle.BattleState) data and menus for the Stadium UI, read
-- straight from the host battle. Ported from STADIUM2_IMPORTER's
-- lib/gen1_battle.lua scene methods, without its 3D scene.
-- This mod's module root ("mods.STADIUM2_UI", or wherever it is embedded,
-- e.g. STADIUM2_IMPORTER's ui/ submodule): taken from this module's name.
local ROOT = (...):match("^(.*)%.lib%.[^%.]+$") or "mods.STADIUM2_UI"
local UI = require(ROOT .. ".lib.stadium_ui")

local Gen1 = {}
Gen1.__index = Gen1

-- Stadium tabs over the host's FIGHT/PKMN/ITEM/RUN (menuIndex 1..4).
Gen1.TABS = { { button = "A", label = "BATTLE", hostIndex = 1 },
  { button = "B", label = "POK\233MON", hostIndex = 2 }, { button = "S", label = "RUN", hostIndex = 4 },
  { button = "R", label = "PACK", hostIndex = 3 } }

local SHINY_ATTACK = {
  [2] = true, [3] = true, [6] = true, [7] = true, [10] = true, [11] = true, [14] = true, [15] = true,
}

local function safeCall(obj, name, ...)
  local fn = obj and obj[name]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, obj, ...)
  return ok and value or nil
end

function Gen1.module()
  return package.loaded["src.battle.BattleState"]
end

function Gen1.owns(state)
  local BattleState = Gen1.module()
  return BattleState ~= nil and type(state) == "table" and getmetatable(state) == BattleState
end

function Gen1.new(battle)
  return setmetatable({ battle = battle }, Gen1)
end

function Gen1:game() return self.battle.game end

-- Portrait species and colouring (importer battle_actor defaultDex/Shiny).
function Gen1:speciesOf(mon)
  if not mon then return nil end
  local dex
  if type(mon.species) == "number" then dex = math.floor(mon.species)
  else
    local data = self.battle.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    dex = def and tonumber(def.dex or def.index)
    dex = dex and math.floor(dex) or nil
  end
  if not (dex and dex >= 1 and dex <= 151) then return nil end
  local shiny
  if mon.shiny ~= nil then shiny = mon.shiny and true or false
  else
    local d = mon.dvs
    shiny = d and d.defense == 10 and d.speed == 10 and d.special == 10
      and SHINY_ATTACK[d.attack] == true or false
  end
  return dex, shiny and "shiny" or "normal"
end

function Gen1:substitute(side)
  local b = self.battle[side]
  return b and b.substituteHP and not b.substitutePending and true or false
end

-- Which status cards and ball rows the host would show now.
function Gen1:live()
  local battle = self.battle
  local slide = (battle.introSlide or 0) * 4
  if slide ~= 0 then return false, false, false, false end
  local enemy = battle.enemy and not battle.showEnemyTrainer
    and not battle.enemySendingOut and not safeCall(battle, "growInScale", battle.enemy)
    and not battle.introBalls and not battle.enemy.fainted
  local player = battle.player and not (battle.safari or battle.demo)
    and not battle.showPlayerBack
  local intro = battle.introBalls == true
  local enemyBalls = (battle.showEnemyBalls and battle.enemyParty)
    or (intro and battle.enemyParty and (battle.kind == "trainer" or battle.kind == "link"))
  local playerBalls = intro and type(battle.playerPartyView) == "function"
  return enemy and true or false, player and true or false,
    enemyBalls and true or false, playerBalls and true or false
end

function Gen1:party(side)
  local battle = self.battle
  if side == "player" then
    local ok, view = pcall(battle.playerPartyView, battle)
    return ok and view or nil
  elseif battle.kind == "trainer" or battle.kind == "link" then
    return battle.enemyParty
  end
  return nil
end

-- Status card data (shown HP and status lag the engine as the host's do).
function Gen1:panel(side)
  local battle, b = self.battle, self.battle[side]
  if not (b and b.mon) then return nil end
  local hp = b.shownHP or b.mon.hp or 0
  hp = hp > (b.mon.hp or 0) and math.ceil(hp) or math.floor(hp)
  local status = b.shownStatus
  if status and battle.statusLabel then
    local ok, label = pcall(battle.statusLabel, battle, { status = status })
    if ok then status = label end
  end
  local tag
  if side == "player" then
    local save = battle.game and battle.game.save
    tag = save and save.player and save.player.name or nil
  elseif battle.trainer and battle.kind ~= "wild" then
    tag = battle.trainer.name
  end
  local party = self:party(side)
  local dex, variant
  if not self:substitute(side) then dex, variant = self:speciesOf(b.mon) end
  return { mon = b.mon, name = b.name or "", level = b.mon.level, hp = hp,
    exp = side == "player" and self:expFraction(b.mon) or nil,
    maxHp = b.mon.stats and b.mon.stats.hp or b.mon.maxHP or hp,
    status = UI.statusKey(status, b.fainted), tag = tag,
    balls = party and UI.partyBallStates(party) or nil,
    dex = dex, variant = variant }
end

-- How far the Pokemon is from this level to the next (0..1), by its growth
-- curve (Growth.expForLevel, as the summary screen's EXP to next level).
-- Gen 1 has no EXP bar; the Stadium card's is an addition. Level 100: full.
function Gen1:expFraction(mon)
  if not (mon and tonumber(mon.exp) and tonumber(mon.level)) then return nil end
  local def = self.battle.data and self.battle.data.pokemon and self.battle.data.pokemon[mon.species]
  local okG, Growth = pcall(require, "src.pokemon.Growth")
  if not (def and okG and type(Growth) == "table" and Growth.expForLevel) then return nil end
  if mon.level >= 100 then return 1 end
  local ok1, base = pcall(Growth.expForLevel, def.growthRate, mon.level)
  local ok2, nextExp = pcall(Growth.expForLevel, def.growthRate, mon.level + 1)
  if not (ok1 and ok2 and base and nextExp and nextExp > base) then return nil end
  return math.max(0, math.min(1, (mon.exp - base) / (nextExp - base)))
end

-- The battler's front sprite, coloured as the battle colours its pics
-- (speciesSprite registers the species palette; picImage applies the
-- current COLORS mode and fades).
function Gen1:frontSprite(mon)
  local battle = self.battle
  if not (mon and type(battle.speciesSprite) == "function") then return nil end
  local ok, image = pcall(battle.speciesSprite, battle, mon.species, false)
  if not (ok and image) then return nil end
  if type(battle.picImage) == "function" then
    local okPic, shown = pcall(battle.picImage, battle, image)
    if okPic and shown then image = shown end
  end
  return { image = image }
end

function Gen1:panels()
  local enemyLive, playerLive, enemyBalls, playerBalls = self:live()
  local out = {}
  for _, side in ipairs({ "player", "enemy" }) do
    local live = side == "player" and playerLive or enemyLive
    local balls = side == "player" and playerBalls or enemyBalls
    if live then out[side] = self:panel(side)
    elseif balls then
      local party = side == "player" and self:party("player") or self.battle.enemyParty
      if type(party) == "table" then out[side] = { ballsOnly = true, balls = UI.partyBallStates(party) } end
    end
  end
  return out
end

-- The host party menu this battle opened (PKMN, or a forced replacement),
-- and the refusal box it pushed over itself if one is up (PartyMenu:refuse:
-- "... is already out!", "There's no will to fight!").
function Gen1:partyMenu()
  local battle = self.battle
  local states = battle.game and battle.game.stack and battle.game.stack.states
  local top = states and states[#states]
  if not top then return nil end
  local ok, PartyMenu = pcall(require, "src.ui.PartyMenu")
  if not ok then return nil end
  local text
  if getmetatable(top) ~= PartyMenu then
    local okT, TextBox = pcall(require, "src.render.TextBox")
    local under = states[#states - 1]
    if not (okT and getmetatable(top) == TextBox and under and getmetatable(under) == PartyMenu) then return nil end
    top, text = under, top
  end
  -- item use and plain picks drive the same cards (TM/HM and evolution
  -- stones keep the host's ABLE / NOT ABLE list)
  if top.battle ~= battle or top.tmhm or top.evoStone then return nil end
  return top, text
end

-- The party menu's own prompt ("Use item on which POKeMON?", ...).
function Gen1:partyPrompt(menu)
  if type(menu.bottomMessage) ~= "function" then return nil end
  local ok, text = pcall(menu.bottomMessage, menu)
  return ok and type(text) == "string" and text ~= "" and text or nil
end

function Gen1:partyItemUse(menu)
  return menu ~= nil and menu.itemUse == true
end

-- The battle bag (the ListMenu of kind "bag" opened over this battle) and
-- the message box it pushed over itself, if one is up (a refused item).
function Gen1:packMenu()
  local battle = self.battle
  local states = battle.game and battle.game.stack and battle.game.stack.states
  if type(states) ~= "table" then return nil end
  local okL, ListMenu = pcall(require, "src.ui.ListMenu")
  if not okL then return nil end
  local function isBag(s) return type(s) == "table" and getmetatable(s) == ListMenu and s.kind == "bag" end
  local n = #states
  local bag, text
  if isBag(states[n]) then bag = states[n]
  else
    local okT, TextBox = pcall(require, "src.render.TextBox")
    if okT and type(states[n]) == "table" and getmetatable(states[n]) == TextBox and isBag(states[n - 1]) then
      bag, text = states[n - 1], states[n]
    end
  end
  if not bag then return nil end
  for i = 1, n do
    if states[i] == battle then return bag, text end
  end
  return nil
end

-- The Stadium item list's contents (Menu.draw's `pack` view).
function Gen1:packView(menu)
  local bag = menu.menu
  local rows = {}
  for i, item in ipairs(bag.items or {}) do
    rows[i] = { name = item.label or "", count = item.count, cancel = item.cancel == true }
  end
  local okS, Strings = pcall(require, "src.core.Strings")
  local title = bag.title or "ITEMS"
  if okS and Strings then
    local okT, shown = pcall(Strings, title)
    if okT and type(shown) == "string" then title = shown end
  end
  local message
  if menu.text and type(menu.text.visibleText) == "function" then
    local okV, lines = pcall(menu.text.visibleText, menu.text)
    message = okV and type(lines) == "table" and lines or nil
  end
  return { title = title, rows = rows, index = bag.index, message = message }
end

-- Host text over the battle outside its own message phases: the
-- evolution's "is evolving" / "evolved into" / "learned" boxes (TextBox
-- states over the battle and the EvolutionState movie, the intro's frame
-- hold included). Returns { lines, hide = {states}, evolution = bool } for
-- the Stadium box, or nil. A box over any other screen (the bag) is not
-- this.
function Gen1:hostText()
  local battle = self.battle
  local states = battle.game and battle.game.stack and battle.game.stack.states
  if type(states) ~= "table" then return nil end
  local okT, TextBox = pcall(require, "src.render.TextBox")
  local okE, EvolutionState = pcall(require, "src.ui.EvolutionState")
  if not okT then return nil end
  local base
  for i = #states, 1, -1 do
    if states[i] == battle then base = i break end
  end
  if not base or base == #states then return nil end
  local boxes, evolution, top = {}, false, nil
  for i = base + 1, #states do
    local s = states[i]
    local mt = type(s) == "table" and getmetatable(s) or nil
    if mt == TextBox then boxes[#boxes + 1] = s; top = s
    elseif okE and mt == EvolutionState then evolution = true
    elseif type(s) == "table" and mt == nil and i == #states and getmetatable(states[i - 1] or {}) == TextBox then
      -- the intro's DelayFrames hold (a bare state over its box)
    else
      return nil
    end
  end
  if not (top or evolution) then return nil end
  local lines
  if top and type(top.visibleText) == "function" then
    local ok, visible = pcall(top.visibleText, top)
    lines = ok and type(visible) == "table" and visible or nil
  end
  return { lines = lines or {}, hide = boxes, evolution = evolution }
end

-- The level-up stats window (BattleState.StatBox, PrintStatsBox) over this
-- battle.
function Gen1:statBox()
  local battle = self.battle
  local states = battle.game and battle.game.stack and battle.game.stack.states
  local top = type(states) == "table" and states[#states] or nil
  local BattleState = Gen1.module()
  local StatBox = BattleState and BattleState.StatBox
  if not (top and StatBox and getmetatable(top) == StatBox and top.mon) then return nil end
  for _, state in ipairs(states) do
    if state == battle then return top end
  end
  return nil
end

local function hostString(text)
  local okS, Strings = pcall(require, "src.core.Strings")
  if okS and Strings then
    local ok, shown = pcall(Strings, text)
    if ok and type(shown) == "string" then return shown end
  end
  return text
end

-- The stats window's rows, as PrintStatsBox lists them.
function Gen1:statsView(menu)
  local mon = menu.menu.mon
  local s = mon.stats or {}
  local def = self.battle.data and self.battle.data.pokemon and self.battle.data.pokemon[mon.species]
  return { name = mon.nickname or (def and def.name) or "", level = mon.level,
    rows = { { hostString("ATTACK"), s.attack }, { hostString("DEFENSE"), s.defense },
      { hostString("SPEED"), s.speed }, { hostString("SPECIAL"), s.special } } }
end

-- The host's battle YES/NO with the default labels.
function Gen1:choiceBox()
  local battle = self.battle
  local states = battle.game and battle.game.stack and battle.game.stack.states
  local top = states and states[#states]
  if not top or states[#states - 1] ~= battle then return nil end
  local ok, ChoiceBox = pcall(require, "src.ui.ChoiceBox")
  if not ok or getmetatable(top) ~= ChoiceBox then return nil end
  local labels = top.labels
  if type(labels) ~= "table" or labels[1] ~= "YES" or labels[2] ~= "NO" then return nil end
  return top
end

function Gen1:menuContext()
  local battle = self.battle
  local choice = self:choiceBox()
  if choice then
    return { kind = "yesno", menu = choice, yesIndex = choice.index,
      select = function(i) if choice.pending == nil then choice.index = i end end }
  end
  local party, refusal = self:partyMenu()
  if party then
    local members = party.party or battle:playerPartyView() or {}
    return { kind = "switch", menu = party, text = refusal, memberCount = #members,
      current = function() return party.index end,
      select = function(i) if not refusal then party.index = i end end,
      submenuOpen = function() return party.submenu ~= nil end,
      selectSub = function(action)
        for i, entry in ipairs(party.subItems or {}) do
          if entry.action == action then party.subIndex = i; return true end
        end
        return false
      end }
  end
  local statBox = self:statBox()
  if statBox then return { kind = "stats", menu = statBox } end
  local bag, text = self:packMenu()
  if bag then
    -- one row per press: no held-key repeat (at high game speed it ran
    -- through the list faster than an item could be picked)
    if type(bag.hold) == "table" then bag.hold.enabled = false end
    return { kind = "pack", menu = bag, text = text,
      select = function(i)
        if text or not bag.items[i] then return end
        bag.index = i
        -- keep the host's own window around the cursor (its 3 cursor rows)
        local rows = bag.cursorRows or bag.rows or 3
        if i - (bag.scroll or 0) > rows then bag.scroll = i - rows end
        if i - (bag.scroll or 0) < 1 then bag.scroll = i - 1 end
      end,
      current = function() return bag.index end }
  end
  if battle.safari or battle.demo then return nil end
  -- the command bar and move diamond only while the battle itself has the
  -- input (not under a screen it opened)
  local states = battle.game and battle.game.stack and battle.game.stack.states
  if type(states) == "table" and #states > 0 and states[#states] ~= battle then return nil end
  if battle.phase == "menu" then
    if battle.player and battle.player.mon and (battle.player.mon.hp or 0) <= 0 then return nil end
    return { kind = "command", tabs = Gen1.TABS,
      select = function(i) battle.menuIndex = i end,
      current = function() return battle.menuIndex end }
  elseif battle.phase == "moveSelect" and not battle.moveSwapIndex then
    local moves = battle.player and battle.player.curMoves or {}
    return { kind = "moves", moveCount = #moves,
      select = function(i) battle.moveIndex = i end }
  end
  return nil
end

-- The whole message phase, including the text-less stretches during move
-- animations (the box keeps the last message, as Stadium's does).
function Gen1:messageOwned()
  if self:menuContext() then self.lastLines = nil return true end
  local battle = self.battle
  return battle.phase == "messages" and type(battle.visibleText) == "function"
end

function Gen1:messageLines()
  local battle = self.battle
  local ok, lines = pcall(battle.visibleText, battle)
  if not (ok and lines) then return self.lastLines or {} end
  local shown = battle.shown or {}
  local out = {}
  for i, text in ipairs(lines) do
    local typed = shown[i] and #shown[i] or #text
    out[i] = typed < #text and text:sub(1, typed) or text
  end
  self.lastLines = out
  return out
end

-- Where each side's picture sits on the 160x144 screen {x, y, w, h}: the
-- opponent's 7x7 slot at tile (12,0); the player's back pic is drawn 2x at
-- x = 8 - its left padding, standing on row 96 (backPlacement), so its box
-- runs from the left edge up to row 32.
Gen1.SPRITE_BOXES = { enemy = { 96, 0, 56, 56 }, player = { 0, 32, 72, 64 } }
function Gen1:spriteBoxes() return Gen1.SPRITE_BOXES end

-- The picture in the opponent's 7x7 slot (the trainer's during the intro).
function Gen1:enemyImage()
  local battle = self.battle
  if battle.showEnemyTrainer and battle.trainerPic then return battle.trainerPic end
  return battle.enemy and battle.enemy.sprite or nil
end

-- The player's active Pokemon's name (menu prompts).
function Gen1:activeName()
  local b = self.battle.player
  return b and b.mon and b.name or nil
end

function Gen1:messageSide()
  return self.battle.animAttackerIsPlayer == false and "enemy" or "player"
end

function Gen1:members(menu)
  local battle = self.battle
  local out = {}
  local moveDefs = battle.data and battle.data.moves or {}
  for i, mon in ipairs(menu.party or battle:playerPartyView() or {}) do
    local def = battle.data and battle.data.pokemon and battle.data.pokemon[mon.species]
    -- the switch screen's STATUS card: types and moves with PP
    local moves = {}
    for k, move in ipairs(mon.moves or {}) do
      local mdef = moveDefs[move.id] or {}
      local basePp = mdef.pp or move.pp or 0
      moves[k] = { name = mdef.name or tostring(move.id), type = mdef.type, pp = move.pp or 0,
        maxPp = basePp + (move.ppUps or 0) * math.floor(basePp / 5) }
    end
    out[i] = { name = mon.nickname or (def and def.name) or "", level = mon.level,
      hp = mon.hp or 0, maxHp = mon.stats and mon.stats.hp or mon.hp or 0,
      status = UI.statusKey(mon.status, (mon.hp or 0) <= 0),
      types = def and def.types or nil, moves = moves }
  end
  return out
end

-- Gen 1 has no move descriptions: the info card uses Stadium 2's text for
-- the same move number (lib/move_descriptions.lua).
local descriptions
local function stadiumDescription(number)
  if not number then return nil end
  if descriptions == nil then
    local ok, t = pcall(require, ROOT .. ".lib.move_descriptions")
    descriptions = ok and type(t) == "table" and t or false
  end
  return descriptions and descriptions[number] or nil
end

function Gen1:moves()
  local battle = self.battle
  local out = {}
  local data = battle.data and battle.data.moves or {}
  for i, move in ipairs(battle.player and battle.player.curMoves or {}) do
    local def = data[move.id] or {}
    local basePp = def.pp or move.pp or 0
    local number = tonumber(def.index or def.num)
    out[i] = { name = def.name or tostring(move.id), type = def.type, pp = move.pp or 0,
      maxPp = basePp + (move.ppUps or 0) * math.floor(basePp / 5),
      power = def.power, accuracy = def.accuracy, number = number,
      description = def.description or stadiumDescription(number) }
  end
  return out
end

-- View fields for Menu.draw.
function Gen1:menuView(menu)
  local message = menu.kind == "switch" and menu.menu.message or nil
  if menu.kind == "switch" and menu.text and type(menu.text.visibleText) == "function" then
    local ok, lines = pcall(menu.text.visibleText, menu.text)
    if ok and type(lines) == "table" and #lines > 0 then message = table.concat(lines, "\n") end
  end
  return { commandIndex = self.battle.menuIndex, moveIndex = self.battle.moveIndex,
    switchIndex = menu.kind == "switch" and menu.menu.index or nil, message = message }
end

-- The host states the Stadium menus stand in for.
function Gen1:hidesState(state, menu)
  if menu == nil then return false end
  if menu.kind == "pack" then return state == menu.menu or (menu.text ~= nil and state == menu.text) end
  if menu.kind == "stats" then return state == menu.menu end
  if menu.kind == "switch" and menu.text ~= nil and state == menu.text then return true end
  return (menu.kind == "switch" or menu.kind == "yesno") and menu.menu == state
end

-- The engine's full-screen effects this frame, as lib/screen_effects.lua
-- describes a screen (read only; BattleState.drawClassic applies the same
-- state to the Game Boy picture).
-- AnimationWavyScreen's per-scanline SCX offsets (pokered
-- engine/battle/animations.asm WavyScreenLineOffsets; BattleState.applyWavy).
Gen1.WAVY_OFFSETS = { 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1,
  0, 0, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2, -2, -1, -1, -1 }
function Gen1:screenEffects()
  local b = self.battle
  local fx = b.fx
  if not fx then return nil end
  local d = { elements = {} }
  -- window shakes, and the animations-off fallback alternation
  local sx, sy = fx.shakeX or 0, fx.shakeY or 0
  if sx == 0 and sy == 0 and fx.shake and fx.shake > 0 then
    sx = (b.frame or 0) % 4 < 2 and 2 or -2
  end
  d.dx, d.dy = sx, sy
  -- the shade map in force (a running flash wins over the persistent one)
  local okMap, map = pcall(b.activeBgp, b)
  d.pal = okMap and map and require(ROOT .. ".lib.screen_effects").byte(map) or nil
  if fx.wavy then
    local lines, phase = {}, fx.wavy.phase or 0
    for row = 0, 143 do
      lines[row] = { dx = Gen1.WAVY_OFFSETS[(row * 2 + phase) % 32 + 1], dy = 0 }
    end
    d.lines = lines
  end
  -- AnimationShakeEnemyHUD moves just the enemy status box
  d.elements.enemyHud = fx.hudShakeX or 0
  -- the white flicker of flash moves without the subanimation player
  if fx.flash and fx.flash > 0 and (b.frame or 0) % 4 < 2 then d.veil = { 1, 1, 1, 0.85 } end
  return d
end

return Gen1
