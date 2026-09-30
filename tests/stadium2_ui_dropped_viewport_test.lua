package.path="./?.lua;./?/init.lua;"..package.path
-- A mod that wraps Renderer:endFrame without returning its result hands
-- render.hud a nil viewport: TERRARIUM 1.30.1's DayTint.install does this
-- whenever its day tint is on (evening, night, dawn):
--   function Renderer:endFrame(zones, worldZones)
--     ...
--     local ok, err = pcall(inner, self, zones, worldZones)
--     gfx.draw = draw
--     if not ok then error(err, 0) end
--   end                                   -- (no return)
-- BattleUI.draw needs the viewport, so the whole Stadium UI disappeared.
-- The UI must rebuild it from Renderer:frameRects (what endFrame returns).
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

-- the host renderer: endFrame returns the frame's viewport from frameRects
local Renderer={}
function Renderer:frameRects()
  return {ww=1920,wh=1080,pw=1920,ph=1080,dpiX=1,dpiY=1,vx=0,vy=0,cut=false,
    vux=0,vuy=0,vuw=1920,vuh=1080,Sp=7,Sx=7,Sy=7,uiw=160,uih=144,
    vpw=1120,vph=1008,ox=400,oy=36}
end
function Renderer:endFrame()
  local R=self:frameRects()
  return {width=R.ww,height=R.wh,gameX=R.ox,gameY=R.oy,gameWidth=R.vpw,gameHeight=R.vph,
    scale=R.Sp,dpiX=R.dpiX,dpiY=R.dpiY,viewX=R.vux,viewY=R.vuy,viewWidth=R.vuw,viewHeight=R.vuh}
end
local engineViewport=Renderer:endFrame()
-- TERRARIUM's tinted endFrame (the shape above)
local inner=Renderer.endFrame
function Renderer:endFrame(zones,worldZones)
  local okI,err=pcall(inner,self,zones,worldZones)
  if not okI then error(err,0) end
end
package.loaded["src.render.Renderer"]=Renderer
ok(Renderer:endFrame()==nil,"the wrapped endFrame returns nothing (the bug's cause)")

-- the UI's render.hud, with BattleUI.draw recording what it is given
local BattleUI=require("mods.STADIUM2_UI.lib.battle_ui")
local Embed=require("mods.STADIUM2_UI.lib.embed")
local received,drawn
BattleUI.draw=function(_,viewport) drawn=true received=viewport return true end
local wrapped={}
local warnings={}
local mod={hooks={wrap=function(_,name,fn) wrapped[name]=fn end},
  events={on=function() end},options={get=function() return nil end}}
Embed.install(mod,{warn=function(m) warnings[#warnings+1]=m end})
ok(type(wrapped["render.hud"])=="function","the UI wraps render.hud")

local game={renderer=Renderer}
wrapped["render.hud"](function() end,game,Renderer:endFrame())
ok(drawn,"the UI still draws")
ok(type(received)=="table","with a viewport although render.hud got nil")
for _,k in ipairs({"width","height","gameX","gameY","gameWidth","gameHeight","scale",
    "dpiX","dpiY","viewX","viewY","viewWidth","viewHeight"}) do
  ok(received[k]==engineViewport[k],"rebuilt viewport."..k.." matches endFrame's ("..tostring(received[k])..")")
end
ok(#warnings==1 and warnings[1]:find("dropped",1,true),"the dropped viewport is reported once")
wrapped["render.hud"](function() end,game,nil)
ok(#warnings==1,"and only once")

-- a viewport the host did pass is used as is
wrapped["render.hud"](function() end,game,engineViewport)
ok(received==engineViewport,"a passed viewport is untouched")
print(checks.." checks passed (Stadium UI with a dropped render.hud viewport)")
