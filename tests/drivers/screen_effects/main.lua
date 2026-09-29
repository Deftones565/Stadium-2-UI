-- The engine's full-screen effects on the Stadium UI (lib/screen_effects.lua;
-- a user-requested port addition). Run from the game root:
--   love mods/STADIUM2_UI/tests/drivers/screen_effects
--
-- Draws a Gen 1 battle's command menu through the real render.hud hook with
-- the engine's effect state set on the battle (BattleState.fx and
-- activeBgp), and compares the UI's pixels with the same frame unaffected.
-- Gen 2's reader is checked against the host's own BattleAnimView.
local root=love.filesystem.getWorkingDirectory()
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local PREFIX='mods.STADIUM2_UI.'
local W,H=1280,720

local checks,failures=0,0
local function ok(v,m)
  checks=checks+1
  if not v then failures=failures+1 print('FAIL '..m) else print('PASS '..m) end
end

local BS1={}
package.loaded["src.battle.BattleState"]=BS1
for _,name in ipairs({"src.ui.gen2.BattleState","src.ui.PartyMenu","src.ui.ChoiceBox","src.ui.gen2.PartyMenu"}) do
  package.loaded[name]={}
end

local mon={hp=10,level=5,stats={hp=20},species=25,dvs={attack=1,defense=1,speed=1,special=1}}
local game={stack={states={}},save={player={name="RED"}},input={pressQueue={}}}
local battle=setmetatable({game=game,phase="menu",menuIndex=1,kind="wild",frame=0,
  player={mon=mon,name="PIKACHU",shownHP=10},
  enemy={mon={hp=5,level=3,stats={hp=9},species=16},name="PIDGEY",shownHP=5},
  playerPartyView=function() return {mon} end,
  visibleText=function() return {"What will","PIKACHU do?"} end,
  activeBgp=function(self) local fx=self.fx if not fx then return nil end return fx.bgp end},BS1)
game.stack.states={battle}

local hooks={}
local mod={hooks={wrap=function(_,name,fn) hooks[name]=hooks[name] or {};table.insert(hooks[name],fn) end},
  events={on=function() end},assets={path=function(_,p) return p end},
  read=function() return nil end,find=function() return nil end,
  options={get=function() return nil end,define=function() end},exports={},log={warn=function() end}}
local warnings={}
require(PREFIX..'lib.embed').install(mod,{enabled=function() return true end,
  warn=function(m) warnings[#warnings+1]=m end})
local Gen1=require(PREFIX..'lib.host_gen1')

local scale=H/144
local viewport={width=W,height=H,gameX=(W-160*scale)/2,gameY=0,gameWidth=160*scale,gameHeight=144*scale,scale=scale}
local canvas

local function frame(fx)
  battle.fx=fx
  local g=love.graphics
  g.setCanvas(canvas);g.clear(0,0,0,0)
  for _,step in ipairs(hooks['input.step'] or {}) do pcall(step,function() end,game,1/30) end
  for _,hud in ipairs(hooks['render.hud']) do hud(function() end,game,viewport) end
  g.setCanvas();g.setShader();g.origin();g.setColor(1,1,1,1)
  return canvas:newImageData()
end

local function lum(r,g,b) return .299*r+.587*g+.114*b end
-- mean brightness of the opaque pixels, and how many there are
local function brightness(img)
  local sum,n=0,0
  for y=0,H-1,3 do for x=0,W-1,3 do
    local r,g,b,a=img:getPixel(x,y)
    if a>.99 then sum=sum+lum(r,g,b);n=n+1 end
  end end
  return n>0 and sum/n or 0,n
end
-- fraction of sampled pixels where img at (x,y) equals base at (x-ox,y-oy)
local function matchShifted(base,img,ox,oy,y0,y1)
  local same,n=0,0
  for y=math.max(y0 or 0,0),math.min(y1 or H-1,H-1),3 do
    for x=math.max(0,ox),W-1+math.min(0,ox),3 do
      local r1,g1,b1,a1=img:getPixel(x,y)
      local r0,g0,b0,a0=base:getPixel(x-ox,y-oy)
      if a0>0 or a1>0 then
        n=n+1
        if math.abs(r1-r0)+math.abs(g1-g0)+math.abs(b1-b0)+math.abs(a1-a0)<.02 then same=same+1 end
      end
    end
  end
  return n>0 and same/n or 1
end

function love.load()
  -- a frozen clock: frames differ only by the effect (the UI animates)
  love.timer.getTime=function() return 100 end
  love.timer.getDelta=function() return 0 end
  canvas=love.graphics.newCanvas(W,H,{format='rgba8',dpiscale=1})
  local base=frame(nil)
  local b0,n0=brightness(base)
  ok(n0>1000,('the UI draws (%d sampled pixels)'):format(n0))

  ok(matchShifted(base,frame(nil),0,0)==1,'two plain frames are identical (a fair baseline)')
  local same=frame({})
  ok(matchShifted(base,same,0,0)==1,'no effect in force: the UI is drawn as it always was')

  -- AnimationFlashScreen's inverted palette ($1b: 3, 2, 1, 0)
  local inv=frame({bgp={[0]=3,2,1,0}})
  local b1=brightness(inv)
  ok(math.abs(b1-(1-b0))<.08,('inverted palette inverts the UI (brightness %.2f -> %.2f)'):format(b0,b1))

  -- the persistent dark screen ($6f: 3, 3, 2, 1): the lightest shade shows
  -- as the darkest, so the UI's light pixels go dark
  local function light(img)
    local n=0
    for y=0,H-1,3 do for x=0,W-1,3 do
      local r,g,b,a=img:getPixel(x,y)
      if a>.99 and lum(r,g,b)>.8 then n=n+1 end
    end end
    return n
  end
  local dark=frame({bgp={[0]=3,3,2,1}})
  local l0,l1=light(base),light(dark)
  ok(l0>100 and l1<l0*.1,('dark screen palette: light UI pixels go dark (%d -> %d)'):format(l0,l1))

  -- a whole-screen shake of +2 Game Boy px moves every UI pixel by 2*scale
  local shaken=frame({shakeX=2,shakeY=0})
  ok(matchShifted(base,shaken,math.floor(2*scale+.5),0)>.97,'screen shake moves the whole UI with the screen')

  -- the wavy screen: each row by WavyScreenLineOffsets at its phase
  local wavy=frame({wavy={left=10,phase=0}})
  local row=8 -- (8*2+0)%32+1 = 17 -> 0 ; row 5: (10)%32+1 = 11 -> 2
  local y5=math.floor(5*scale)+1
  ok(Gen1.WAVY_OFFSETS[11]==2 and matchShifted(base,wavy,math.floor(2*scale+.5),0,y5,y5+math.floor(scale)-2)>.97,
    'wavy screen: a row with offset 2 moves 2 px')
  local y8=math.floor(row*scale)+1
  ok(matchShifted(base,wavy,0,0,y8,y8+math.floor(scale)-2)>.97,'wavy screen: a row with offset 0 stays')

  -- AnimationShakeEnemyHUD: only the opponent's card moves
  local frameBase=frame(nil) -- settles enemyPanelRect
  local hud=frame({hudShakeX=2})
  ok(matchShifted(frameBase,hud,0,0)<1 and matchShifted(frameBase,hud,0,0)>.5,
    'enemy HUD shake moves part of the UI, not all of it')

  -- a white veil over the UI
  local veiled=frame({flash=4})
  battle.frame=0
  ok(brightness(veiled)>b0+.2,'the flash veil lightens the UI')

  -- Gen 2: Gold's registers through the host's own BattleAnimView
  local okView,View=pcall(require,'src.ui.gen2.BattleAnimView')
  if okView and type(View)=='table' and View.scanlines then
    local Gen2=require(PREFIX..'lib.host_gen2')
    local lyBackup={}
    for i=0,0x90 do lyBackup[i]=0 end
    for i=10,20 do lyBackup[i]=0xfe end -- SCX -2 on rows 11..21
    local a=setmetatable({screen={anim={bg={scx=3,scy=0,bgp=0x1b,lcdc='SCX',lyStart=10,lyEnd=20,lyBackup=lyBackup}}}},{__index=Gen2})
    local d=a:screenEffects()
    ok(d.dx==-3 and d.pal==0x1b,'Gen 2: hSCX and wBGP carried as they are')
    ok(d.lines and d.lines[15].dx==2 and d.lines[5].dx==0,'Gen 2: the per-scanline SCX rows, as the host draws them')
  else
    ok(false,'Gen 2 BattleAnimView loads')
  end

  -- cost: the UI's draw with no effect in force and with one (report only)
  local clock=os.clock
  local function time(fx,n)
    local g=love.graphics
    battle.fx=fx
    local t=clock()
    for _=1,n do
      g.setCanvas(canvas)
      for _,hud in ipairs(hooks['render.hud']) do hud(function() end,game,viewport) end
      g.setCanvas()
    end
    canvas:newImageData(1,1,0,0,1,1):release() -- wait for the GPU to finish
    return (clock()-t)/n*1000
  end
  time(nil,20)
  print(('cost per frame: no effect %.3f ms, wavy + inverted %.3f ms (CPU, %s)'):format(time(nil,300),
    time({wavy={left=10,phase=4},bgp={[0]=3,2,1,0}},300),select(4,love.graphics.getRendererInfo())))
  print(('%d checks, %d failed (screen effects on the Stadium UI)'):format(checks,failures))
  love.event.quit(failures==0 and 0 or 1)
end
