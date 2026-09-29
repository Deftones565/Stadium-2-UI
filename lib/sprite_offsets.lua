-- Moves the Pokemon clear of the UI where the engine DRAWS them, not by
-- cutting the finished frame: each side's picture is drawn through the
-- engine's own function, shifted, and the animation sprites over a moved
-- Pokemon go with it. Everything else the engine draws -- the palette
-- flashes, the wave, the shakes, the veil, another mod's field art -- is
-- drawn by the engine over the whole picture as always.
--
-- No engine file is touched: the overrides live on the one battle object
-- (the engine's methods stay on its class), each calls the engine's method
-- through the class, and release() removes them.
--
--   Gen 1: battle.drawPicsLayer (per side, via its onlySide), and for the
--          span of battle.drawAnimLayer, animPlayer.drawSprites.
--   Gen 2: screen.drawPic, screen.drawLiftedRows, and on screen.animView:
--          present (Gold's per-scanline window follows its Pokemon's rows)
--          and drawObjects (runner:oam() shifted for the call).
local Offsets = {}

local offset = { enemy = { 0, 0 }, player = { 0, 0 } }
local boxes = { enemy = { 96, 0, 56, 56 }, player = { 8, 40, 56, 56 } }
local live = function() return false end
local own = setmetatable({}, { __mode = "k" })

-- Whether `fn` is one of these overrides (not another mod's scene).
function Offsets.isOwn(fn) return own[fn] == true end

-- The engine's own method under an override on `obj`.
function Offsets.classMethod(obj, name)
  local mt = getmetatable(obj)
  local index = mt and mt.__index
  if type(index) == "table" then return index[name] end
  if type(index) == "function" then return index(obj, name) end
  return nil
end

-- Game Boy pixels, whole (the picture stays on its pixel grid).
function Offsets.set(enemy, player, spriteBoxes)
  offset.enemy[1] = math.floor((enemy and enemy[1] or 0) + 0.5)
  offset.enemy[2] = math.floor((enemy and enemy[2] or 0) + 0.5)
  offset.player[1] = math.floor((player and player[1] or 0) + 0.5)
  offset.player[2] = math.floor((player and player[2] or 0) + 0.5)
  if spriteBoxes then
    boxes.enemy = spriteBoxes.enemy or boxes.enemy
    boxes.player = spriteBoxes.player or boxes.player
  end
end

function Offsets.get(side)
  if not live() then return 0, 0 end
  local o = offset[side]
  return o[1], o[2]
end

local function moving()
  if not live() then return false end
  return offset.enemy[1] ~= 0 or offset.enemy[2] ~= 0 or offset.player[1] ~= 0 or offset.player[2] ~= 0
end
Offsets.moving = moving

-- The side whose home box holds the point (x, y), or nil.
local function sideAt(x, y)
  for _, side in ipairs({ "enemy", "player" }) do
    local b = boxes[side]
    if x >= b[1] and x < b[1] + b[3] and y >= b[2] and y < b[2] + b[4] then return side end
  end
  return nil
end
Offsets.sideAt = sideAt

-- Copies of OAM entries (x/y at the hardware's +8/+16 bias) with the ones
-- over a moved Pokemon moved with it.
local function shiftOam(list)
  local out = {}
  for i, s in ipairs(list) do
    local side = sideAt(s.x - 8 + 4, s.y - 16 + 4)
    local dx, dy = 0, 0
    if side then dx, dy = Offsets.get(side) end
    if dx ~= 0 or dy ~= 0 then
      local c = {}
      for k, v in pairs(s) do c[k] = v end
      c.x, c.y = s.x + dx, s.y + dy
      out[i] = c
    else
      out[i] = s
    end
  end
  return out
end
Offsets.shiftOam = shiftOam

-- Put `fn` on obj[name] (only when nothing else is there) and remember it.
local installed = {}
local function override(obj, name, fn)
  if rawget(obj, name) ~= nil then return false end
  own[fn] = true
  rawset(obj, name, fn)
  installed[#installed + 1] = { obj, name, fn }
  return true
end

local function withTranslate(dx, dy, fn, ...)
  local g = love.graphics
  g.push()
  g.translate(dx, dy)
  local ok, err = pcall(fn, ...)
  g.pop()
  if not ok then error(err, 0) end
end

-- Gen 1 (src/battle/BattleState.lua).
function Offsets.installGen1(battle)
  override(battle, "drawPicsLayer", function(self, slide, sx, sy, onlySide, skipMenuClip, ...)
    local original = Offsets.classMethod(self, "drawPicsLayer")
    if not moving() then return original(self, slide, sx, sy, onlySide, skipMenuClip, ...) end
    local g = love.graphics
    for _, side in ipairs({ "enemy", "player" }) do
      if onlySide == nil or onlySide == side then
        local dx, dy = Offsets.get(side)
        -- the engine keeps the pics above ITS text box (row 96); with the
        -- UI's box standing in for it, a Pokemon moved down may go lower
        local s1, s2, s3, s4 = g.getScissor()
        local open = dy > 0 and type(self.bottomUIVisible) == "function" and not self:bottomUIVisible()
        if open then g.setScissor() end
        local ok, err = pcall(withTranslate, dx, dy, original, self, slide, sx, sy, side, skipMenuClip, ...)
        if open then
          if s1 then g.setScissor(s1, s2, s3, s4) else g.setScissor() end
        end
        if not ok then error(err, 0) end
      end
    end
  end)
  override(battle, "drawAnimLayer", function(self, colorized, ...)
    local original = Offsets.classMethod(self, "drawAnimLayer")
    local player = self.animPlayer
    if not (moving() and type(player) == "table") or rawget(player, "drawSprites") ~= nil then
      return original(self, colorized, ...)
    end
    local drawSprites = player.drawSprites
    rawset(player, "drawSprites", function(p, sprites, colorFn, ...)
      return drawSprites(p, type(sprites) == "table" and shiftOam(sprites) or sprites, colorFn, ...)
    end)
    local ok, err = pcall(original, self, colorized, ...)
    rawset(player, "drawSprites", nil)
    if not ok then error(err, 0) end
  end)
end

-- Gen 2 (src/ui/gen2/BattleState.lua, src/ui/gen2/BattleAnimView.lua).
local function shiftedRunner(runner)
  local bg = runner.bg
  if not (bg and bg.lcdc and bg.lcdc ~= "BGP" and bg.lyEnd and bg.lyEnd > (bg.lyStart or 0)) then return runner end
  -- BattleBGEffect_SetLCDStatCustoms1: $00-$36 is the enemy's pic, $2f-$5e
  -- the player's; the window follows its Pokemon's rows
  local side = (bg.lyStart or 0) < 0x2f and "enemy" or "player"
  local _, dy = Offsets.get(side)
  if dy == 0 then return runner end
  local rows = {}
  for row = 0, 0x90 do rows[row] = 0 end
  for row = 0, 0x90 do
    local to = row + dy
    if to >= 0 and to <= 0x90 then rows[to] = bg.lyBackup[row] or 0 end
  end
  local view = setmetatable({ lyStart = math.max(0, bg.lyStart + dy),
    lyEnd = math.min(0x90, bg.lyEnd + dy), lyBackup = rows }, { __index = bg })
  return setmetatable({ bg = view }, { __index = runner })
end

function Offsets.installGen2(screen)
  override(screen, "drawPic", function(self, mon, back, ...)
    local original = Offsets.classMethod(self, "drawPic")
    local dx, dy = Offsets.get(back and "player" or "enemy")
    if dx == 0 and dy == 0 then return original(self, mon, back, ...) end
    return withTranslate(dx, dy, original, self, mon, back, ...)
  end)
  override(screen, "drawLiftedRows", function(self, ...)
    local original = Offsets.classMethod(self, "drawLiftedRows")
    local lift = type(self.animPicState) == "function" and self:animPicState("player")
    local side = (lift and lift.lifted) and "player" or "enemy"
    local dx, dy = Offsets.get(side)
    if dx == 0 and dy == 0 then return original(self, ...) end
    return withTranslate(dx, dy, original, self, ...)
  end)
  local view = screen.animView
  if type(view) == "table" then
    override(view, "present", function(self, runner, drawBg, battle, ...)
      local original = Offsets.classMethod(self, "present")
      if not moving() or type(runner) ~= "table" then return original(self, runner, drawBg, battle, ...) end
      return original(self, shiftedRunner(runner), drawBg, battle, ...)
    end)
    override(view, "drawObjects", function(self, runner, battle, ...)
      local original = Offsets.classMethod(self, "drawObjects")
      if not (moving() and type(runner) == "table") or rawget(runner, "oam") ~= nil then
        return original(self, runner, battle, ...)
      end
      local oam = runner.oam
      rawset(runner, "oam", function(r, ...) return shiftOam(oam(r, ...)) end)
      local ok, err = pcall(original, self, runner, battle, ...)
      rawset(runner, "oam", nil)
      if not ok then error(err, 0) end
    end)
  end
end

-- Install on the adapter's battle (once per battle object); `isLive` says
-- whether the UI is drawing (otherwise everything passes straight through).
local target
function Offsets.install(adapter, isLive)
  local state = adapter.battle or adapter.screen
  if state ~= target then
    Offsets.release()
    target = state
  end
  live = type(isLive) == "function" and isLive or live
  if adapter.battle then Offsets.installGen1(adapter.battle)
  elseif adapter.screen then Offsets.installGen2(adapter.screen) end
end

-- Remove every override (an engine battle object keeps nothing of ours).
function Offsets.release()
  for i = #installed, 1, -1 do
    local obj, name, fn = installed[i][1], installed[i][2], installed[i][3]
    if rawget(obj, name) == fn then rawset(obj, name, nil) end
    installed[i] = nil
  end
  target = nil
  Offsets.set(nil, nil)
end

return Offsets
