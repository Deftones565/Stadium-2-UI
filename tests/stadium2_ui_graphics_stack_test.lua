package.path="./?.lua;./?/init.lua;"..package.path
-- One failing piece must never cost the whole HUD.
--
-- LOVE keeps one graphics transform stack for the whole frame and refuses a
-- push past 64 levels ("Maximum stack depth reached"). The UI's safe draw
-- entries (tryDrawPanels / tryDrawMessage / tryDrawMenu) push "all", call
-- the draw under pcall and pop once; the draw inside pushes its own
-- transform. When the inner draw throws, its push is never popped, the
-- single pop takes it instead, and the outer push stays: one level leaks per
-- failing frame. After 64 frames every push fails, and with it every panel,
-- the message box and the menus: a device-specific error in one card
-- becomes "no HUD at all" a second later, reported once.
--
-- This stub is LOVE 11.5's stack rule (same limit and messages); everything
-- else the UI draws with is a no-op.
local MAX_DEPTH=64
local depth=0
local function object(w,h)
  local methods={
    getDimensions=function() return w or 16,h or 16 end,
    getWidth=function() return w or 16 end,
    getHeight=function() return h or 16 end,
    getPixel=function() return 0,0,0,0 end,
    newImageData=function() return object(w,h) end,
    getFilter=function() return "linear","linear" end,
  }
  return setmetatable({},{__index=function(_,k) return methods[k] or function() return nil end end})
end
local graphics={
  push=function()
    if depth>=MAX_DEPTH then error("Maximum stack depth reached (more pushes than pops?)",2) end
    depth=depth+1
  end,
  pop=function()
    if depth<=0 then error("Minimum stack depth reached (more pops than pushes?)",2) end
    depth=depth-1
  end,
  getStackDepth=function() return depth end,
  newImage=function(src)
    return object(src and src.getWidth and src:getWidth(),src and src.getHeight and src:getHeight())
  end,
  newCanvas=function(w,h) return object(w,h) end,
  newQuad=function() return object() end,
  newFont=function() return object(8,12) end,
  getFont=function() return object(8,12) end,
  getColor=function() return 1,1,1,1 end,
  getCanvas=function() return nil end,
  getScissor=function() return nil end,
  getDimensions=function() return 1280,720 end,
  getWidth=function() return 1280 end,
  getHeight=function() return 720 end,
  transformPoint=function(x,y) return x,y end,
}
setmetatable(graphics,{__index=function() return function() end end})
love={graphics=graphics,
  image={newImageData=function(w,h) return object(w,h) end},
  timer={getTime=os.clock}}

local UI=require("mods.STADIUM2_UI.lib.stadium_ui")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
ok(UI.available()==true,"the painted UI art builds under the stub")

local area={x=0,y=0,w=1280,h=720}
local panels={player={},enemy={}}
local warn=function() end

-- A card that throws every frame (any per-device failure inside a panel).
local statusPanel=UI.statusPanel
UI.statusPanel=function() error("device refused a texture") end
local lost
for frame=1,100 do
  local okFrame,drew=pcall(function()
    UI.tryDrawPanels(area,panels,warn)
    return UI.tryDrawMessage(area,{"Wild PIDGEY","appeared!"},"player",warn)
  end)
  if not (okFrame and drew) then lost=lost or frame end
end
ok(lost==nil,"a failing status card leaves the message box drawing (lost from frame "
  ..tostring(lost)..", graphics stack depth "..depth..")")
ok(depth==0,"the graphics stack is back where it was after every frame (depth "..depth..")")
UI.statusPanel=statusPanel

-- The same for a menu whose drawing throws after pushing.
depth=0
lost=nil
for frame=1,100 do
  local okFrame,drew=pcall(function()
    UI.tryDrawMenu(area,function() graphics.push() error("menu piece refused") end,warn)
    return UI.tryDrawMessage(area,{"What will","PIKACHU do?"},"player",warn)
  end)
  if not (okFrame and drew) then lost=lost or frame end
end
ok(lost==nil,"a failing menu leaves the message box drawing (lost from frame "..tostring(lost)..")")
ok(depth==0,"and the graphics stack balanced (depth "..depth..")")

print(checks.." checks passed (Stadium UI graphics stack)")
