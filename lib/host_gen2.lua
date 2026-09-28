-- Gen 2 (src.ui.gen2.BattleState) data and menus for the Stadium UI, read
-- straight from the host battle screen. Ported from STADIUM2_IMPORTER's
-- lib/gen2_battle.lua scene methods, without its 3D scene.
local UI = require("mods.STADIUM2_UI.lib.stadium_ui")

local Gen2 = {}
Gen2.__index = Gen2

Gen2.TABS = { { button = "A", label = "BATTLE", hostIndex = 1 },
  { button = "B", label = "POK\233MON", hostIndex = 2 }, { button = "S", label = "RUN", hostIndex = 4 },
  { button = "R", label = "PACK", hostIndex = 3 } }

-- Phases whose bottom text is Stadium's message box. "menu" covers the
-- command prompt while it types; the YES/NO phases type their question
-- here before the YES/NO window takes over.
local MESSAGE_PHASES = { resolving = true, intro = true, ["locked-in"] = true,
  ["refuse-switch"] = true, ["refuse-shift"] = true, ["refuse-move"] = true,
  ["refuse-menu"] = true, ["shift-intro"] = true, ["learn-intro"] = true,
  ["cant-escape-then-switch"] = true, menu = true,
  ["ask-nickname"] = true, ["ask-shift"] = true, ["ask-next-mon"] = true,
  ["ask-forget"] = true, ["stop-learning"] = true }

-- Gold's YesNoBox phases and the field holding each one's cursor (1 = YES).
local YESNO = { ["ask-nickname"] = "nicknameIndex", ["ask-shift"] = "shiftIndex",
  ["ask-next-mon"] = "nextMonIndex", ["ask-forget"] = "forgetChoice",
  ["stop-learning"] = "forgetChoice" }

local SUB_IDS = { battle_switch = "SWITCH", stats = "STATS" }

local SHINY_ATTACK = {
  [2] = true, [3] = true, [6] = true, [7] = true, [10] = true, [11] = true, [14] = true, [15] = true,
}

function Gen2.module()
  return package.loaded["src.ui.gen2.BattleState"]
end

function Gen2.owns(state)
  local BattleState = Gen2.module()
  return BattleState ~= nil and type(state) == "table" and getmetatable(state) == BattleState
end

function Gen2.new(screen)
  return setmetatable({ screen = screen, side = "player" }, Gen2)
end

function Gen2:game() return self.screen.game end

local function call(screen, name, ...)
  local fn = screen and screen[name]
  if type(fn) ~= "function" then return nil end
  local ok, value = pcall(fn, screen, ...)
  return ok and value or nil
end

function Gen2:mon(side)
  local screen = self.screen
  if screen.activeMon then
    local ok, mon = pcall(screen.activeMon, screen, side)
    if ok then return mon end
  end
  return screen.battle and screen.battle[side] or nil
end

function Gen2:speciesOf(mon)
  if not mon then return nil end
  local dex
  if type(mon.species) == "number" then dex = math.floor(mon.species)
  else
    local data = self.screen.game and self.screen.game.data
    local def = data and data.pokemon and data.pokemon[mon.species]
    dex = def and tonumber(def.dex or def.index)
    dex = dex and math.floor(dex) or nil
  end
  if not (dex and dex >= 1 and dex <= 251) then return nil end
  local shiny
  if mon.shiny ~= nil then shiny = mon.shiny and true or false
  else
    local d = mon.dvs
    shiny = d and d.defense == 10 and d.speed == 10 and d.special == 10
      and SHINY_ATTACK[d.attack] == true or false
  end
  return dex, shiny and "shiny" or "normal"
end

function Gen2:substitute(side, mon)
  local battle = self.screen.battle
  if not (battle and battle.volatile and mon) then return false end
  local ok, volatile = pcall(battle.volatile, battle, mon)
  return ok and volatile and (tonumber(volatile.substitute) or 0) > 0 or false
end

function Gen2:live()
  local screen = self.screen
  local enemy = screen.showEnemyHud and not screen.showEnemyTrainer
  local player = screen.showPlayerHud and not screen.showPlayerTrainer
    and not screen.tutorial
  return enemy and true or false, player and true or false
end

function Gen2:panels()
  local screen = self.screen
  local enemyLive, playerLive = self:live()
  local out = {}
  for _, side in ipairs({ "player", "enemy" }) do
    local live = side == "player" and playerLive or enemyLive
    local mon = live and self:mon(side)
    if mon then
      local hp = call(screen, "hudHp", mon, side) or mon.hp or 0
      local status = call(screen, "hudStatus", mon, side)
      local tag
      if side == "player" then
        local save = screen.save
        tag = save and save.player and save.player.name or nil
      else
        local trainer = screen.battle and screen.battle.trainer
        tag = type(trainer) == "table" and (trainer.name or trainer.className) or nil
      end
      local panel = { mon = mon, name = call(screen, "name", mon) or mon.nickname or mon.name or "",
        level = mon.level, hp = math.floor(hp),
        maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or hp,
        status = UI.statusKey(status, (mon.hp or 0) <= 0),
        gender = mon.gender == "male" and "M" or mon.gender == "female" and "F" or nil,
        tag = tag }
      local battle = screen.battle
      local party = battle and (side == "player" and battle.party or (tag and battle.enemyParty) or nil)
      if type(party) == "table" then panel.balls = UI.partyBallStates(party) end
      if not self:substitute(side, mon) then panel.dex, panel.variant = self:speciesOf(mon) end
      if side == "player" then
        -- the EXP bar the host HUD crawls (shownExp of its 64 px, CalcExpBar),
        -- at the level it is crawling through
        local Hud = package.loaded["src.ui.gen2.BattleHud"]
        local length = Hud and tonumber(Hud.EXP_LENGTH_PX) or 64
        panel.exp = math.max(0, math.min(1, (tonumber(screen.shownExp) or 0) / length))
        if tonumber(screen.shownLevel) then panel.level = screen.shownLevel end
      end
      out[side] = panel
    elseif not live then
      -- the host's intro / send-out ball rows, as Stadium balls
      local rows, battle = screen.ballRows, screen.battle
      if type(rows) == "table" and rows[side] and battle then
        local party = side == "player" and battle.party or battle.enemyParty
        if type(party) == "table" then out[side] = { ballsOnly = true, balls = UI.partyBallStates(party) } end
      end
    end
  end
  return out
end

-- The battler's front sprite, drawn through Gold's GBC palette for the
-- species (as BattleState:drawPic colours it).
function Gen2:frontSprite(mon)
  local screen = self.screen
  if not (mon and type(screen.pic) == "function") then return nil end
  local ok, image, trueColor = pcall(screen.pic, screen, mon, false)
  if not (ok and image) then return nil end
  local Palettes = package.loaded["src.world.gen2.Palettes"]
  local GbcPalette = package.loaded["src.render.GbcPalette"]
  local colors = Palettes and screen.palettes and Palettes.monColors
    and Palettes.monColors(screen.palettes, mon.species, mon.shiny)
  local draw
  if colors and GbcPalette and GbcPalette.with and GbcPalette.available()
      and not (trueColor and GbcPalette.mode == "gbc") then
    draw = function(drawImage) GbcPalette.with(colors, drawImage) end
  end
  return { image = image, draw = draw }
end

function Gen2:partyMenu()
  local screen = self.screen
  local states = screen.game and screen.game.stack and screen.game.stack.states
  local top = states and states[#states]
  if not top then return nil end
  local ok, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  if not ok or getmetatable(top) ~= PartyMenu or top.battle ~= true then return nil end
  if top.tmhm or top.itemUse then return nil end
  return top
end

-- The party menu's own prompt ("Use on which POKeMON?", ...), with Gold's
-- <PK><MN> glyph pair spelled out.
function Gen2:partyPrompt(menu)
  if not menu then return nil end
  -- the prompt PartyMenu:draw prints (item_effects.asm:2016)
  local okM, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  local prompts = okM and type(PartyMenu) == "table" and PartyMenu.PROMPTS or {}
  local text, builtin = menu.prompt, menu.promptIsBuiltin
  if menu.switchFrom and prompts.moveTo then text, builtin = prompts.moveTo, true
  elseif menu.softboiledFrom and prompts.useItem then text, builtin = prompts.useItem, true end
  if builtin and type(text) == "string" then
    local okS, Strings = pcall(require, "src.core.Strings")
    if okS and Strings then
      local okT, shown = pcall(Strings, text)
      if okT and type(shown) == "string" then text = shown end
    end
  end
  if type(text) ~= "string" or text == "" then return nil end
  return (text:gsub("<PK><MN>", "POK\195\169MON"))
end

function Gen2:partyItemUse(menu)
  if not menu then return false end
  if menu.softboiledFrom then return true end
  local okM, PartyMenu = pcall(require, "src.ui.gen2.PartyMenu")
  local prompts = okM and type(PartyMenu) == "table" and PartyMenu.PROMPTS
  return prompts ~= nil and prompts.useItem ~= nil and menu.prompt == prompts.useItem
end

-- The battle PACK (BattlePack) open over this battle.
function Gen2:packMenu()
  local states = self.screen.game and self.screen.game.stack and self.screen.game.stack.states
  local top = type(states) == "table" and states[#states] or nil
  if not top then return nil end
  local ok, PackMenu = pcall(require, "src.ui.gen2.PackMenu")
  if not ok or getmetatable(top) ~= PackMenu or top.give then return nil end
  local okB, inBattle = pcall(top.inBattle, top)
  if not (okB and inBattle) then return nil end
  for _, state in ipairs(states) do
    if state == self.screen then return top end
  end
  return nil
end

local function hostString(text)
  if type(text) ~= "string" then return text end
  local okS, Strings = pcall(require, "src.core.Strings")
  if okS and Strings then
    local ok, shown = pcall(Strings, text)
    if ok and type(shown) == "string" then text = shown end
  end
  return (text:gsub("<PK><MN>", "POK\195\169MON"))
end

local SUBMENU_LABELS = { use = "USE", give = "GIVE", toss = "TOSS", sel = "SEL", quit = "QUIT" }

-- The Stadium item list's contents (Menu.draw's `pack` view): the pocket's
-- rows and CANCEL, the USE / QUIT submenu, and the text the PACK prints in
-- its bottom box (a message page, else the item's description).
function Gen2:packView(menu)
  local pack = menu.menu
  local rows = {}
  for i, row in ipairs(pack.rows or {}) do
    local name = row.name or ""
    if row.tmhmLabel then name = row.tmhmLabel .. " " .. (row.teaches or name) end
    rows[i] = { name = hostString(name), count = row.showCount and row.count or nil }
  end
  rows[#rows + 1] = { name = hostString("CANCEL"), cancel = true }
  local okP, pocket = pcall(pack.pocket, pack)
  local view = { title = okP and pocket and hostString(pocket.label) or "PACK", pockets = true,
    rows = rows, index = pack.index }
  if pack.submenu then
    local labels = {}
    for i, id in ipairs(pack.submenu.rows or {}) do labels[i] = hostString(SUBMENU_LABELS[id] or id) end
    view.submenu = { labels = labels, index = pack.submenu.index }
  end
  if pack.message then
    local okPg, pages = pcall(pack.pagesFor, pack, pack.message)
    local page = okPg and type(pages) == "table" and pages[pack.messagePage or 1] or {}
    local okN, player = pcall(pack.playerName, pack)
    local lines = {}
    for i, line in ipairs(page) do
      lines[i] = hostString((tostring(line):gsub("{PLAYER}", okN and player or "")))
    end
    view.message = lines
  else
    local okD, text = pcall(pack.description, pack)
    if okD and type(text) == "string" and text ~= "" then
      local first, second = text:match("^(.-)<NEXT>(.*)$")
      if not first then first, second = text:match("^(.-)\n(.*)$") end
      view.description = { hostString(first or text), second and hostString(second) or nil }
    end
  end
  return view
end

-- The level-up stats box (phase "stats-box"): the stats drawStatsBox prints,
-- recomputed from the base stats the way it does (core.asm:7208-7213).
local STATS_ROWS = { { "ATTACK", "attack" }, { "DEFENSE", "defense" },
  { "SPCL.ATK", "specialAttack" }, { "SPCL.DEF", "specialDefense" }, { "SPEED", "speed" } }

function Gen2:statsView(menu)
  local screen, mon = self.screen, menu.mon
  local stats = mon.stats
  local data = screen.game and screen.game.data
  local okM, Mon = pcall(require, "src.battle.gen2.Mon")
  if okM and type(Mon) == "table" and Mon.partySpecies and Mon.stats then
    local okS, species = pcall(Mon.partySpecies, mon)
    local def = okS and data and data.pokemon and data.pokemon[species]
    if def and def.baseStats then
      local ok, fresh = pcall(Mon.stats, def.baseStats, mon.dvs, mon.level, mon.statExp)
      if ok and type(fresh) == "table" then stats = fresh end
    end
  end
  stats = stats or {}
  local rows = {}
  for i, row in ipairs(STATS_ROWS) do rows[i] = { hostString(row[1]), stats[row[2]] } end
  return { name = call(screen, "name", mon) or mon.nickname or mon.name or "", level = mon.level, rows = rows }
end

-- The screen draws its stats box itself (no hook around it), so while the
-- Stadium card stands in for it this battle screen's drawStatsBox skips the
-- host box; the original runs whenever the Stadium UI is not drawing (the
-- option off, the mod gone). The override lives on this one battle screen.
function Gen2:coverStatsBox(covered)
  local screen = self.screen
  if rawget(screen, "drawStatsBox") then return end
  local BattleState = Gen2.module()
  local original = BattleState and BattleState.drawStatsBox
  if type(original) ~= "function" then return end
  local cover
  cover = function(s, ...)
    if rawget(s, "drawStatsBox") == cover and covered() then return end
    return original(s, ...)
  end
  screen.drawStatsBox = cover
  self.statsCover = cover
end

-- The evolution screen (EvolutionAnim, opaque, over this battle) and its
-- text: { lines, evolution = true, scene = the screen }.
function Gen2:hostText()
  local states = self.screen.game and self.screen.game.stack and self.screen.game.stack.states
  local top = type(states) == "table" and states[#states] or nil
  if not top then return nil end
  local ok, EvolutionAnim = pcall(require, "src.ui.gen2.EvolutionAnim")
  if not ok or getmetatable(top) ~= EvolutionAnim then return nil end
  local found = false
  for _, state in ipairs(states) do
    if state == self.screen then found = true break end
  end
  if not found then return nil end
  local lines = {}
  for i, line in ipairs(type(top.lines) == "table" and top.lines or {}) do lines[i] = hostString(tostring(line)) end
  return { lines = lines, evolution = true, scene = top }
end

-- The evolution screen prints its text inside drawPanel; while the Stadium
-- box shows it, that screen's drawPanel runs without its lines (the pic and
-- balls unchanged). The override lives on that one screen.
function Gen2:coverHostText(text, covered)
  local scene = text and text.scene
  if not scene or rawget(scene, "drawPanel") then return end
  local EvolutionAnim = getmetatable(scene)
  local original = EvolutionAnim and EvolutionAnim.drawPanel
  if type(original) ~= "function" then return end
  local cover
  cover = function(s, ...)
    if rawget(s, "drawPanel") ~= cover or not covered() then return original(s, ...) end
    local lines = s.lines
    s.lines = nil
    local ok, err = pcall(original, s, ...)
    s.lines = lines
    if not ok then error(err, 0) end
  end
  scene.drawPanel = cover
  self.textCovers = self.textCovers or {}
  self.textCovers[scene] = cover
end

function Gen2:release()
  if self.statsCover and rawget(self.screen, "drawStatsBox") == self.statsCover then
    self.screen.drawStatsBox = nil
  end
  self.statsCover = nil
  for scene, cover in pairs(self.textCovers or {}) do
    if rawget(scene, "drawPanel") == cover then scene.drawPanel = nil end
  end
  self.textCovers = nil
end

function Gen2:onTop()
  local states = self.screen.game and self.screen.game.stack and self.screen.game.stack.states
  return states ~= nil and states[#states] == self.screen
end

function Gen2:menuContext()
  local screen = self.screen
  local field = YESNO[screen.phase]
  if field and (screen.messageTimer or 0) <= 0 and self:onTop() then
    return { kind = "yesno", field = field, yesIndex = screen[field],
      select = function(i) screen[field] = i end }
  end
  local pack = self:packMenu()
  if pack then
    local busy = function() return pack.message or pack.submenu or pack.switching or pack.qtyState or pack.confirm end
    return { kind = "pack", menu = pack,
      select = function(i)
        if busy() then return end
        pack.index = i
        pcall(pack.ensureVisible, pack)
      end,
      current = function() return pack.index end,
      pocket = function(delta)
        if not busy() then pcall(pack.switchPocket, pack, delta) end
      end,
      submenuOpen = function() return pack.submenu ~= nil end,
      selectSub = function(i)
        if pack.submenu and pack.submenu.rows and pack.submenu.rows[i] then pack.submenu.index = i; return true end
        return false
      end }
  end
  local party = self:partyMenu()
  if party then
    return { kind = "switch", menu = party, memberCount = #(party.party or {}),
      select = function(i) party.index = i end,
      submenuOpen = function() return party.submenu ~= nil end,
      selectSub = function(action)
        local sub = party.submenu
        for i, item in ipairs(sub and sub.items or {}) do
          if item.id == SUB_IDS[action] then sub.index = i; return true end
        end
        return false
      end }
  end
  -- the command bar and move diamond only while the battle has the input
  if not self:onTop() then return nil end
  if screen.phase == "stats-box" and screen.statsBoxMon then
    return { kind = "stats", mon = screen.statsBoxMon }
  end
  if screen.phase == "menu" and not screen.contest and (screen.messageTimer or 0) <= 0 then
    return { kind = "command", tabs = Gen2.TABS,
      select = function(i) screen.menuIndex = i end,
      current = function() return screen.menuIndex end }
  elseif screen.phase == "moves" and not screen.moveSwapIndex then
    local ok, moves = pcall(screen.playerMoves, screen)
    return { kind = "moves", moveCount = ok and #moves or 0,
      select = function(i) screen.moveIndex = i end }
  end
  return nil
end

function Gen2:messageOwned()
  if self:menuContext() then self.lastLines = nil return true end
  local screen = self.screen
  -- the Bug Contest's own menu keeps the native box
  if screen.phase == "menu" and screen.contest then return false end
  return MESSAGE_PHASES[screen.phase] == true
end

function Gen2:messageLines()
  local screen = self.screen
  if type(screen.messageLines) ~= "function" then return self.lastLines or {} end
  local ok, lines = pcall(screen.messageLines, screen)
  if ok and type(lines) == "table" and #lines > 0 then
    self.lastLines = lines
    return lines
  end
  return self.lastLines or {}
end

-- Gold resolves a whole turn before presenting it, so battle.move_used
-- fires early. The side on screen is taken from the presentation queue: a
-- "move" event leaving the queue head is the move now being shown.
function Gen2:track()
  local queue = self.screen.queue
  local head = type(queue) == "table" and queue[1] or nil
  local prev = self.head
  if prev and prev ~= head and type(prev) == "table" and prev.kind == "move"
      and (prev.side == "player" or prev.side == "enemy") then
    self.side = prev.side
  end
  self.head = head
end

function Gen2:messageSide() return self.side or "player" end

-- Where each side's picture sits on the 160x144 screen {x, y, w, h}: the
-- opponent's 7x7 frontpic box at tile (12,0), the player's 6x6 backpic box
-- at tile (2,6) (with a little room for scaled pics).
Gen2.SPRITE_BOXES = { enemy = { 96, 0, 56, 56 }, player = { 8, 40, 64, 56 } }
function Gen2:spriteBoxes() return Gen2.SPRITE_BOXES end

-- The picture in the opponent's 7x7 slot (the trainer's during the intro).
function Gen2:enemyImage()
  local screen = self.screen
  if screen.showEnemyTrainer and screen.enemyTrainerImage then return screen.enemyTrainerImage end
  local mon = self:mon("enemy")
  if not (mon and type(screen.pic) == "function") then return nil end
  local ok, image = pcall(screen.pic, screen, mon, false)
  return ok and image or nil
end

-- The player's active Pokemon's name (menu prompts).
function Gen2:activeName()
  local mon = self:mon("player")
  if not mon then return nil end
  return call(self.screen, "name", mon) or mon.nickname or mon.name
end

function Gen2:members(menu)
  local screen = self.screen
  local out = {}
  for i, mon in ipairs(menu.party or {}) do
    local name = call(screen, "name", mon) or mon.nickname or mon.name or ""
    out[i] = { name = mon.isEgg and "EGG" or name, level = mon.level, hp = mon.hp or 0,
      maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or mon.hp or 0,
      status = UI.statusKey(mon.status, (mon.hp or 0) <= 0),
      gender = mon.gender == "male" and "M" or mon.gender == "female" and "F" or nil }
  end
  return out
end

local function moveNumber(data, move)
  local number = tonumber(move)
  if number then return number end
  local def = data and data.moves and data.moves[move]
  return def and (tonumber(def.index) or tonumber(def.number) or tonumber(def.id)) or nil
end

function Gen2:moves()
  local screen = self.screen
  local ok, moves = pcall(screen.playerMoves, screen)
  local data = screen.game and screen.game.data
  local defs = data and data.moves or {}
  local Mon = package.loaded["src.battle.gen2.Mon"]
  local out = {}
  for i, move in ipairs(ok and moves or {}) do
    local def = defs[move.id] or {}
    local maxPp = move.maxPp
    if not maxPp and Mon and Mon.maxPpOf then
      local okPp, value = pcall(Mon.maxPpOf, move, data)
      maxPp = okPp and value or nil
    end
    out[i] = { name = def.name or tostring(move.id), type = def.type, pp = move.pp or 0,
      maxPp = maxPp or def.pp or 0, power = def.power, accuracy = def.accuracy,
      number = moveNumber(data, move.id), description = def.description }
  end
  return out
end

function Gen2:menuView(menu)
  local screen = self.screen
  local result = menu.kind == "switch" and menu.menu.itemResult or nil
  return { commandIndex = screen.menuIndex, moveIndex = screen.moveIndex,
    switchIndex = menu.kind == "switch" and menu.menu.index or nil,
    message = type(result) == "table" and result.text or nil }
end

function Gen2:hidesState(state, menu)
  return menu ~= nil and (menu.kind == "switch" or menu.kind == "pack") and menu.menu == state
end

return Gen2
