-- Input for the Stadium UI menus (STADIUM UI option).
--
-- Runs from the mod's input.step hook, which the engine calls before it
-- promotes this tick's presses, so every action here reaches the battle on
-- the same tick. Actions go through the host's own menu state and the
-- public mod.input taps; no engine function is patched.
--
-- Stadium 2's own handlers (michiiik 0ed78d4, US):
-- * command bar func_84139EB0: pressed A = BATTLE, B = POKeMON, Start = RUN;
-- * move select func_8413A53C: held D-pad up/right/down/left = info card of
--   move 1..4 (func_8413A12C), held R = CHECK (func_84139F44), pressed L =
--   cancel, pressed C-up/right/down/left = move 1..4; A is not read.
--
-- Two control styles:
-- * Stadium controls (a controller is in use, or MENU CONTROLS = STADIUM):
--   exactly the handlers above, with no cursor. The host's A is withheld on
--   the move and switch screens, where Stadium does not read it, so an
--   invisible cursor can never pick anything.
-- * Cursor (keyboard or touch with MENU CONTROLS = CURSOR, the default): the
--   host's cursor and A work unchanged and the Stadium menus mark the
--   cursor; R held shows the cursor move's info card.
-- Either way B = POKeMON, Start = RUN and R = PACK on the command bar (the
-- host command menus ignore those buttons), C buttons pick, L cancels, and
-- a tap on a tab, move or card picks it. PACK is not in Stadium 2.
--
-- Generated controller prompts are a port extension. Native N64 glyphs
-- remain available on keyboard and through the icon preference.
-- This mod's module root ("mods.STADIUM2_UI", or wherever it is embedded,
-- e.g. STADIUM2_IMPORTER's ui/ submodule): taken from this module's name.
local ROOT = (...):match("^(.*)%.lib%.[^%.]+$") or "mods.STADIUM2_UI"
local UI = require(ROOT .. ".lib.stadium_ui")
local Controller = require(ROOT .. ".lib.stadium_controller")
local ButtonGlyphs = require(ROOT .. ".lib.stadium_button_glyphs")

local Menu = {}

-- Keyboard keys for the N64 buttons the host has no binding for, and the
-- gamepad axis flicks that stand in for the C buttons.
Menu.bindings = {
  keyboard = { CUP = "i", CLEFT = "j", CDOWN = "k", CRIGHT = "l" },
  stick = { axisX = "rightx", axisY = "righty", threshold = 0.6 },
}

local held = {}
local taps = {}
-- "pad" or "keyboard": the device that pressed last (touch leaves it as is)
local device
-- switch screen: which row of three the C buttons address (parties of 4..6)
local switchRow = 1

local function currentC()
  local now, from = {}, nil
  local keyboard = love and love.keyboard
  if keyboard and keyboard.isDown then
    for button, key in pairs(Menu.bindings.keyboard) do
      local ok, down = pcall(keyboard.isDown, key)
      if ok and down then now[button] = true; from = "keyboard" end
    end
  end
  local joystick = love and love.joystick
  if joystick and joystick.getJoysticks then
    local stick = Menu.bindings.stick
    local active = Controller.activeJoystick()
    for _, js in ipairs(active and {active} or {}) do
      if js:isGamepad() then
        local x, y = js:getGamepadAxis(stick.axisX), js:getGamepadAxis(stick.axisY)
        if y < -stick.threshold then now.CUP = true; from = "pad"
        elseif y > stick.threshold then now.CDOWN = true; from = "pad" end
        if x < -stick.threshold then now.CLEFT = true; from = "pad"
        elseif x > stick.threshold then now.CRIGHT = true; from = "pad" end
      end
    end
  end
  return now, from
end

local function padConnected()
  local joystick = love and love.joystick
  if not (joystick and joystick.getJoysticks) then return false end
  local ok, list = pcall(joystick.getJoysticks)
  if not ok then return false end
  for _, js in ipairs(list) do
    local okPad, isPad = pcall(js.isGamepad, js)
    if okPad and isPad then return true end
  end
  return false
end

-- The host tags every press with its source ("key:x", "pad:a", "joy:3",
-- "stick", "hat...", "touch:a", "mod:..."); the latest physical one decides.
local function sourceDevice(source)
  if type(source) ~= "string" then return nil end
  if source:match("^key:") then return "keyboard" end
  if source:match("^pad:") or source:match("^joy:") or source == "stick" or source:match("^hat") then
    return "pad"
  end
  return nil
end

function Menu.noteDevice(game, cFrom)
  local input = game and game.input
  local queue = input and input.pressQueue
  local sources = input and input.sources
  if type(queue) == "table" and type(sources) == "table" then
    for _, button in ipairs(queue) do
      for source in pairs(sources[button] or {}) do
        device = sourceDevice(source) or device
      end
    end
  end
  if cFrom then device = cFrom end
  if device == nil then device = padConnected() and "pad" or "keyboard" end
  return device
end

function Menu.device() return device end

function Menu.gamepad(event)
  if Controller.observe(event) then device = "pad" end
end

function Menu.stadiumControls(mode)
  return mode == "stadium" or device == "pad"
end

-- Edges since the previous step.
function Menu.cEdges(now)
  local from
  if not now then now, from = currentC() end
  local edges = {}
  for button in pairs(now) do
    if not held[button] then edges[button] = true end
  end
  held = now
  return edges, from
end

-- Touch (port addition): a short press on a Stadium target acts when it is
-- released (the next step); a long press on a Pokemon card shows its STATUS
-- and on a move its info, and they stay up until the next tap, which only
-- closes them.
Menu.LONG_PRESS = .45 -- seconds held (without moving) for a long press
Menu.DRAG_SLOP = 16   -- window units a press may move and still count
local presses = {}
local touchStatus, touchInfo -- member / move slot shown by a long press

function Menu.now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

function Menu.pointer(event)
  if type(event) ~= "table" or not (event.x and event.y) then return end
  local id = event.id or "mouse"
  if event.phase == "pressed" then
    presses[id] = { x = event.x, y = event.y, t = Menu.now() }
  elseif event.phase == "moved" then
    local p = presses[id]
    if p and (math.abs(event.x - p.x) > Menu.DRAG_SLOP or math.abs(event.y - p.y) > Menu.DRAG_SLOP) then
      p.dragged = true
    end
  elseif event.phase == "released" then
    local p = presses[id]
    presses[id] = nil
    if p and not p.long and not p.dragged then taps[#taps + 1] = { x = p.x, y = p.y } end
  elseif event.phase == "cancelled" then
    presses[id] = nil
  end
end

-- Presses held long enough become long presses (checked each step).
local function longPresses()
  local now, out = Menu.now(), {}
  for _, p in pairs(presses) do
    if not p.long and not p.dragged and now - p.t >= Menu.LONG_PRESS then
      p.long = true
      out[#out + 1] = p
    end
  end
  return out
end

function Menu.touchStatus() return touchStatus end
function Menu.touchInfo() return touchInfo end

local C_SLOT = { CUP = 1, CRIGHT = 2, CDOWN = 3, CLEFT = 4 }
-- Switch screen, from the game's own handlers (US asm, fragment79_393CA0):
--   func_8413B468, parties of three (element 0xB): C-left, C-up, C-right
--     switch to members 1-3; the held D-pad's left, up, right shows their
--     status (func_8413AB2C).
--   func_8413B5D4, parties of four to six (element 0xC): B, C-left, C-up
--     switch to members 1-3 and A, C-down, C-right to 4-6; the held D-pad's
--     up/down picks the status row (latched) and left/right the column: up
--     row left 1, up 2, right 3; down row left 4, down 5, right 6.
--   Both: R held = CHECK (func_8413A6CC), L = cancel (func_84139958).
-- The port's STATUS (user request, not the game's D-pad STATUS): hold R and
-- hold a member's button to see its STATUS card while both are held (CURSOR
-- controls: hold R for the cursor's member); a long press does it on touch.
local PICK_THREE = { CLEFT = 1, CUP = 2, CRIGHT = 3 }
local PICK_SIX = { CLEFT = 2, CUP = 3, CDOWN = 5, CRIGHT = 6 } -- B = 1, A = 4
local statusMember = nil
-- CURSOR controls: the cursor on the switch screen's L CANCEL tab (Gen 1's
-- party list has no CANCEL row of its own; Gen 2's does, at count + 1)
local cancelFocus = false
function Menu.cancelFocus() return cancelFocus end

-- The member whose status shows: R held with its button (or the cursor's
-- member), or a long press's, else nil.
function Menu.statusMember() return statusMember or touchStatus end
-- func_8413A53C's D-pad order (up, right, down, left = move 1..4).
local DPAD_SLOT = { { "up", 1 }, { "right", 2 }, { "down", 3 }, { "left", 4 } }

-- A switch-screen pick spans two ticks: the host's A opens its SWITCH/STATS
-- submenu, then the wanted entry is chosen.
local pendingSub

local function pending(game)
  local out = {}
  local queue = game and game.input and game.input.pressQueue
  if type(queue) == "table" then
    for _, button in ipairs(queue) do out[button] = true end
  end
  return out
end

-- Withhold a queued host press this tick (it never becomes an edge).
local function withhold(game, button)
  local queue = game and game.input and game.input.pressQueue
  if type(queue) ~= "table" then return end
  for i = #queue, 1, -1 do
    if queue[i] == button then table.remove(queue, i) end
  end
end

local function isDown(game, button)
  local input = game and game.input
  if not (input and type(input.isDown) == "function") then return false end
  local ok, down = pcall(input.isDown, input, button)
  return ok and down == true
end

-- The move whose info card shows: D-pad held (Stadium controls,
-- func_8413A53C) or R held on the cursor move (cursor controls).
function Menu.infoSlot(game, mode, cursor, moveCount)
  moveCount = moveCount or 4
  if touchInfo and touchInfo <= moveCount then return touchInfo end
  if Menu.stadiumControls(mode) then
    for _, d in ipairs(DPAD_SLOT) do
      if isDown(game, d[1]) and d[2] <= moveCount then return d[2] end
    end
    return nil
  end
  if isDown(game, "r") and cursor and cursor <= moveCount then return cursor end
  return nil
end

function Menu.switchRow(memberCount)
  local rows = math.max(1, math.ceil((memberCount or 0) / 3))
  if switchRow > rows then switchRow = 1 end
  return switchRow
end

-- ctx (from the battle scene):
--   { kind = "command", select = fn(hostIndex), current = fn() -> hostIndex,
--     tabs = { {hostIndex=..}, ... } }
--   { kind = "moves", select = fn(slot), moveCount = n }
--   { kind = "switch", select = fn(i), memberCount = n, submenuOpen = fn(),
--     selectSub = fn(action) }
--   { kind = "yesno", select = fn(i) } (1 = YES, 2 = NO)
--   { kind = "pack", select = fn(i), current = fn(), pocket = fn(delta)?,
--     submenuOpen = fn()?, selectSub = fn(i)? }
-- tap = fn(button) queues a host button press (mod.input:tap).
function Menu.step(game, ctx, mode, tap, cNow)
  Controller.update(game)
  if device == "pad" and love and love.joystick and love.joystick.getJoysticks
      and not Controller.activeJoystick() then device = "keyboard" end
  local edges, cFrom = Menu.cEdges(cNow)
  Menu.noteDevice(game, cFrom)
  local stadium = Menu.stadiumControls(mode)
  local pressedTaps = taps
  taps = {}
  if not ctx or ctx.kind ~= "switch" then
    pendingSub = nil; switchRow = 1; statusMember = nil; touchStatus = nil
    cancelFocus = false
  end
  if not ctx or ctx.kind ~= "moves" then touchInfo = nil end
  -- long presses: a Pokemon card's STATUS, a move's info
  for _, p in ipairs(longPresses()) do
    local id = UI.hitAt(p.x, p.y)
    local member = id and tonumber(id:match("^switch:(%d+)$"))
    local slot = id and tonumber(id:match("^move:(%d+)$"))
    if member and ctx and ctx.kind == "switch" then touchStatus = member end
    if slot and ctx and ctx.kind == "moves" then touchInfo = slot end
  end
  -- the next tap only closes a card a long press opened
  if (touchStatus or touchInfo) and #pressedTaps > 0 then
    touchStatus, touchInfo = nil, nil
    pressedTaps = {}
    if ctx then return "dismiss" end
  end
  if not ctx or type(tap) ~= "function" then return nil end
  local queued = pending(game)
  if ctx.kind == "command" then
    local choose
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^command:(%d+)$"))
      if i then choose = i end
    end
    if not choose then
      for i, t in ipairs(ctx.tabs or {}) do
        if t.button == "A" and queued.a and stadium then
          -- the host's own A then confirms this entry
          ctx.select(t.hostIndex)
        elseif (t.button == "B" and queued.b) or (t.button == "S" and queued.start)
            or (t.button == "R" and queued.r) then
          choose = i
        end
      end
    end
    if choose and ctx.tabs and ctx.tabs[choose] then
      ctx.select(ctx.tabs[choose].hostIndex)
      tap("a")
      return "command:" .. choose
    end
    -- The host menu is a 2x2 grid; the Stadium bar is one row, so the
    -- D-pad is taken over here: left/right step along the tabs (clamped,
    -- as the host's cursor clamps), up/down do nothing.
    local left, right = queued.left, queued.right
    for _, button in ipairs({ "left", "right", "up", "down" }) do withhold(game, button) end
    if (left or right) and ctx.tabs and type(ctx.current) == "function" then
      local at = 1
      for i, t in ipairs(ctx.tabs) do
        if t.hostIndex == ctx.current() then at = i end
      end
      local to = math.max(1, math.min(#ctx.tabs, at + (right and 1 or -1)))
      if left and right then to = at end
      ctx.select(ctx.tabs[to].hostIndex)
      return "tab:" .. to
    end
  elseif ctx.kind == "switch" then
    -- a refusal box over the list: A / B are the box's until it closes
    if ctx.text then pendingSub = nil; return nil end
    if ctx.submenuOpen() then
      if pendingSub then
        local want = pendingSub
        pendingSub = nil
        if ctx.selectSub(want) then tap("a"); return "sub:" .. want end
      end
      return nil
    end
    pendingSub = nil
    local count = ctx.memberCount or 0
    local six = count > 3
    local member
    for button, m in pairs(six and PICK_SIX or PICK_THREE) do
      if edges[button] then member = m end
    end
    statusMember = nil
    local checking = isDown(game, "r")
    if stadium then
      if six then
        if queued.b then member = 1 end
        if queued.a then member = 4 end
        withhold(game, "b")
      end
      withhold(game, "a")
      if checking then
        -- CHECK: R held with a member's button held shows its STATUS
        local want
        for button, m in pairs(six and PICK_SIX or PICK_THREE) do
          if held[button] then want = m end
        end
        if six then
          if isDown(game, "b") then want = 1 end
          if isDown(game, "a") then want = 4 end
        end
        statusMember = want and want <= count and want or nil
        member = nil
      end
    else
      if checking then
        -- CHECK (CURSOR controls): R held shows the cursor's member
        local at = type(ctx.current) == "function" and ctx.current() or nil
        statusMember = at and at <= count and at or nil
        member = nil
      end
      -- CURSOR controls: down from the last member moves onto L CANCEL
      local at = type(ctx.current) == "function" and ctx.current() or nil
      if cancelFocus then
        for _, button in ipairs({ "left", "right", "up", "down", "a" }) do withhold(game, button) end
        if queued.up or queued.left then cancelFocus = false; return "cancel-leave" end
        if queued.a then cancelFocus = false; tap("b"); return "cancel" end
        if queued.b then cancelFocus = false end
        return nil
      elseif queued.down and at == count and not ctx.hostCancel then
        withhold(game, "down")
        cancelFocus = true
        return "cancel-focus"
      end
    end
    -- L (the L CANCEL tab, or a tap on it): back
    local cancel = queued.l
    for _, t in ipairs(pressedTaps) do
      if UI.hitAt(t.x, t.y) == "cancel" then cancel = true end
    end
    if cancel then
      cancelFocus = false
      withhold(game, "l")
      tap("b")
      return "cancel"
    end
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^switch:(%d+)$"))
      if i then member = i end
    end
    if member and member <= count then
      ctx.select(member)
      tap("a")
      pendingSub = "battle_switch"
      return "switch:" .. member
    end
    if not stadium then
      if queued.a and not checking then
        -- selecting a member switches, as in Stadium; the host's A opens its
        -- submenu this tick and SWITCH is chosen on the next
        pendingSub = "battle_switch"
      end
    end
  elseif ctx.kind == "yesno" then
    -- Stadium lays NO left of YES; the host toggles with up/down, so
    -- left/right (and a tap) pick directly. A and B stay the host's.
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^yesno:(%d)$"))
      if i then
        ctx.select(i)
        tap("a")
        return "yesno:" .. i
      end
    end
    if queued.left then ctx.select(2); return "no" end
    if queued.right then ctx.select(1); return "yes" end
  elseif ctx.kind == "stats" then
    -- A / B close it as before; a tap on the card does the same
    for _, t in ipairs(pressedTaps) do
      if UI.hitAt(t.x, t.y) == "stats" then tap("a"); return "stats" end
    end
  elseif ctx.kind == "pack" then
    -- the host list keeps its own D-pad, A and B; taps pick directly
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local sub = id and tonumber(id:match("^packsub:(%d+)$"))
      local row = id and tonumber(id:match("^pack:(%d+)$"))
      local pocket = id and tonumber(id:match("^pocket:(%-?%d+)$"))
      if sub and ctx.selectSub and ctx.selectSub(sub) then
        tap("a")
        return "packsub:" .. sub
      elseif row and not (ctx.submenuOpen and ctx.submenuOpen()) then
        if type(ctx.current) == "function" and ctx.current() == row then
          tap("a")
          return "pack:" .. row
        end
        ctx.select(row)
        return "packrow:" .. row
      elseif pocket and ctx.pocket then
        ctx.pocket(pocket)
        return "pocket:" .. pocket
      end
    end
  elseif ctx.kind == "moves" then
    if stadium then withhold(game, "a") end
    local slot
    for button, i in pairs(C_SLOT) do
      if edges[button] then slot = i end
    end
    for _, t in ipairs(pressedTaps) do
      local id = UI.hitAt(t.x, t.y)
      local i = id and tonumber(id:match("^move:(%d+)$"))
      if i then slot = i end
    end
    if slot and slot <= (ctx.moveCount or 0) then
      ctx.select(slot)
      tap("a")
      return "move:" .. slot
    end
    if queued.l then
      tap("b")
      return "cancel"
    end
  end
  return nil
end

-- Draw the open menu. view = { kind, tabs, commandIndex, members,
-- switchIndex, moves, moveIndex, message, lines, yesIndex, game, mode }.
function Menu.draw(view)
  ButtonGlyphs.setContext(view.game, device)
  local stadium = Menu.stadiumControls(view.mode)
  if view.kind == "command" then
    local selected
    if not stadium then
      for i, t in ipairs(view.tabs or {}) do
        if t.hostIndex == view.commandIndex then selected = i end
      end
    end
    UI.commandBar(view.tabs or {}, selected)
  elseif view.kind == "switch" then
    local members = view.members or {}
    -- the held D-pad's member (Stadium controls) or a long-pressed card:
    -- its STATUS card instead
    local shown = Menu.statusMember()
    if shown and members[shown] then
      UI.switchStatus(members[shown])
      return
    end
    -- the cursor on L CANCEL: the port's (Gen 1) or the host's CANCEL row (Gen 2)
    local onCancel = not stadium and (cancelFocus or (view.switchIndex or 0) > #members)
    UI.switchCards(members, not stadium and not onCancel and view.switchIndex or nil, onCancel)
    -- a refusal ("There's no will to fight!") from the hidden host menu
    local message = view.message
    if type(message) == "string" and message ~= "" then
      local lines = {}
      for line in message:gmatch("[^\n]+") do lines[#lines + 1] = UI.toLatin1(line) end
      UI.messageBox(lines, "player")
    end
  elseif view.kind == "yesno" then
    -- host text is UTF-8; the ROM font is Latin-1
    local lines = {}
    for i, line in ipairs(view.lines or {}) do lines[i] = UI.toLatin1(line) end
    UI.yesNo(lines, view.yesIndex)
  elseif view.kind == "pack" then
    UI.packList(view)
  elseif view.kind == "stats" then
    UI.statsCard(view)
  elseif view.kind == "moves" then
    local moves = view.moves or {}
    local info = Menu.infoSlot(view.game, view.mode, view.moveIndex, #moves)
    local slot = info and UI.MOVE_SLOTS[info]
    if slot and moves[info] then
      UI.moveInfo(moves[info], slot.button)
    else
      UI.moveDiamond(moves, not stadium and view.moveIndex or nil)
      UI.hint(3)
    end
  end
end

function Menu.reset()
  held, taps, pendingSub, switchRow, device = {}, {}, nil, 1, nil
  presses, touchStatus, touchInfo = {}, nil, nil
  cancelFocus = false
  statusMember = nil
end

return Menu
