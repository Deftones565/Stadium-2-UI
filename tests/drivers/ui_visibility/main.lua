-- Does the Stadium UI draw at all? A player reports no UI with only
-- STADIUM2_IMPORTER installed (on Android). Run from the game root:
--   love mods/STADIUM2_UI/tests/drivers/ui_visibility
--
-- Installs the UI the way each setup does (lib/embed.lua, as the importer's
-- 0.19.x ui/ copy or as this mod's main.lua), draws a Gen 1 battle's command
-- menu through the real render.hud hook into a canvas, and counts the pixels
-- the UI drew. Setups whose UI should be off are expected blank; the rest are
-- expected drawn, including on phone screens and with resources a phone may
-- refuse (a driver refusing one kind of resource, or one failure, must not
-- cost the whole UI).
local root=love.filesystem.getWorkingDirectory()
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local UI_DIR=root..'/mods/STADIUM2_UI/'
local PREFIX='mods.STADIUM2_UI.'

local BS1,PartyMenu,ChoiceBox,PartyMenu2,BS2
local function stubs()
  BS1,BS2,PartyMenu,ChoiceBox,PartyMenu2={}, {}, {}, {}, {}
  package.loaded["src.battle.BattleState"]=BS1
  package.loaded["src.ui.gen2.BattleState"]=BS2
  package.loaded["src.ui.PartyMenu"]=PartyMenu
  package.loaded["src.ui.ChoiceBox"]=ChoiceBox
  package.loaded["src.ui.gen2.PartyMenu"]=PartyMenu2
end

local function fresh()
  for name in pairs(package.loaded) do
    if name:sub(1,#PREFIX)==PREFIX then package.loaded[name]=nil end
  end
  stubs()
end

-- a Gen 1 battle at its command menu
local function battle()
  local mon={hp=10,level=5,stats={hp=20},species=25,dvs={attack=1,defense=1,speed=1,special=1}}
  local game={stack={states={}},save={player={name="RED"}},input={pressQueue={}}}
  local b=setmetatable({game=game,phase="menu",menuIndex=1,kind="wild",
    player={mon=mon,name="PIKACHU",shownHP=10},
    enemy={mon={hp=5,level=3,stats={hp=9},species=16},name="PIDGEY",shownHP=5},
    playerPartyView=function() return {mon} end,
    visibleText=function() return {"What will","PIKACHU do?"} end},BS1)
  game.stack.states={b}
  return game
end

local function fakeMod()
  local hooks={}
  return {
    hooks={wrap=function(_,name,fn) hooks[name]=hooks[name] or {};table.insert(hooks[name],fn) end},
    events={on=function() end},
    assets={path=function(_,p) return p end},
    read=function(_,path) local f=io.open(UI_DIR..path,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end,
    find=function() return nil end,
    options={get=function() return nil end,define=function() end},
    exports={},
    log={warn=function() end},
  },hooks
end

-- "graphics.newCanvas" -> love.graphics; "Canvas:newImageData" -> the
-- methods table every LOVE Canvas shares (so object methods can be refused too)
local methodTables={}
local function target(path)
  local lib,fn=path:match('^(%w+)%.(%w+)$')
  if lib then return love[lib],fn end
  local typ,m=path:match('^(%w+):(%w+)$')
  return assert(methodTables[typ],'no sample '..tostring(typ)),m
end

-- one scenario: install, draw, count the UI's pixels
local function run(s)
  fresh()
  local g=love.graphics
  local restore={}
  -- the test's own canvas, target and read-back are never refused
  local newCanvas,setCanvas,readBack=g.newCanvas,g.setCanvas,methodTables.Canvas.newImageData
  for path,refuse in pairs(s.fail or {}) do
    local t,fn=target(path)
    local real=t[fn];restore[#restore+1]={t,fn,real}
    local calls=0
    t[fn]=function(...)
      calls=calls+1
      if refuse(calls,...) then error(path..' refused on this device (test)',2) end
      return real(...)
    end
  end
  if s.record then
    for _,path in ipairs(s.record.candidates) do
      local t,fn=target(path)
      local real=t[fn]
      if type(real)=='function' then
        restore[#restore+1]={t,fn,real}
        t[fn]=function(...) s.record.used[path]=true return real(...) end
      end
    end
  end
  local warnings={}
  local result
  local ok,err=pcall(function()
    local Embed=require(PREFIX..'lib.embed')
    local mod,hooks=fakeMod()
    Embed.install(mod,{embedded=s.embedded,assetBase=s.embedded and 'ui/' or '',
      enabled=s.enabled,warn=function(m) warnings[#warnings+1]=m end})
    local game=battle()
    for _,step in ipairs(hooks['input.step'] or {}) do pcall(step,function() end,game,1/30) end
    local W,H=s.w or 1280,s.h or 720
    local scale=math.min(W/160,H/144)
    local gw,gh=160*scale,144*scale
    local viewport={width=W,height=H,gameX=(W-gw)/2,gameY=s.portrait and 0 or (H-gh)/2,
      gameWidth=gw,gameHeight=gh,scale=scale}
    local canvas=newCanvas(W,H,{format='rgba8',dpiscale=1})
    -- two frames: the second shows whether the UI recovers from a refusal
    for _=1,2 do
      setCanvas(canvas);g.clear(0,0,0,0)
      for _,hud in ipairs(hooks['render.hud'] or {}) do hud(function() return nil end,game,viewport) end
      setCanvas(canvas) -- whatever target the UI left bound
    end
    setCanvas();g.setShader();g.origin();g.setColor(1,1,1,1)
    local data=readBack(canvas)
    local drawn=0
    for y=0,H-1,4 do for x=0,W-1,4 do
      local _,_,_,a=data:getPixel(x,y);if a>0 then drawn=drawn+1 end
    end end
    data:release();canvas:release()
    result=drawn
  end)
  for _,r in ipairs(restore) do r[1][r[2]]=r[3] end
  g.setCanvas();g.setShader();g.origin()
  return ok and result or nil,err,warnings
end

local importerOption=nil -- a fresh importer install: STADIUM UI never set
local SCENARIOS={
  -- STADIUM2_IMPORTER 0.19.x: the embedded copy, on only with its STADIUM UI
  -- option (default false)
  {name='importer 0.19.x alone, STADIUM UI left at default',embedded=true,
    enabled=function() return importerOption==true end,expect='missing'},
  {name='importer 0.19.x alone, STADIUM UI switched on',embedded=true,
    enabled=function() return true end,expect='drawn'},
  -- this mod (main.lua): STADIUM UI defaults on
  {name='Stadium 2 UI mod, defaults',enabled=function() return true end,expect='drawn'},
  {name='Stadium 2 UI mod, STADIUM UI off',enabled=function() return false end,expect='missing'},
  {name='phone portrait 1080x2400',w=1080,h=2400,portrait=true,enabled=function() return true end,expect='drawn'},
  {name='phone landscape 2400x1080',w=2400,h=1080,enabled=function() return true end,expect='drawn'},
  {name='small phone portrait 720x1280',w=720,h=1280,portrait=true,enabled=function() return true end,expect='drawn'},
}
local function always() return true end
local function first(n) return n==1 end
-- GLES2 phones without full NPOT support refuse mipmapped non-power-of-two images
local function mipmapped(_,_,settings) return type(settings)=='table' and settings.mipmaps==true end

-- Resources and features a phone driver can refuse: every constructor, render
-- targets, canvas read-back, filtering. Drawing primitives are not refusable.
local function refusable()
  local list={}
  for _,lib in ipairs({'graphics','image','font'}) do
    for name,v in pairs(love[lib] or {}) do
      if type(v)=='function' and (name:match('^new') or name=='setCanvas') then
        list[#list+1]=lib..'.'..name
      end
    end
  end
  for _,m in ipairs({'Canvas:newImageData','Canvas:renderTo','Canvas:setFilter','Image:setFilter',
      'Image:setMipmapFilter','Image:replacePixels','ImageData:mapPixel','ImageData:encode'}) do
    list[#list+1]=m
  end
  table.sort(list)
  return list
end
function love.load()
  print(love.graphics.getRendererInfo())
  local g=love.graphics
  local sampleCanvas=g.newCanvas(4,4)
  local sampleData=love.image.newImageData(4,4)
  local sampleImage=g.newImage(sampleData)
  for typ,obj in pairs({Canvas=sampleCanvas,Image=sampleImage,ImageData=sampleData}) do
    methodTables[typ]=debug.getmetatable(obj).__index
  end
  -- which refusable calls one normal frame of the UI actually makes
  local record={candidates=refusable(),used={}}
  run({name='record',enabled=function() return true end,record=record})
  local used={}
  for path in pairs(record.used) do used[#used+1]=path end
  table.sort(used)
  print('refusable calls the UI makes: '..table.concat(used,', '))
  -- the UI is drawn from images and quads: refusing every
  -- one of those leaves nothing to draw (no device does); one refusal of each
  -- must still be survived
  local unavoidable={['graphics.newImage']=true,['graphics.newQuad']=true}
  for _,path in ipairs(used) do
    SCENARIOS[#SCENARIOS+1]={name='device refuses every '..path,fail={[path]=always},
      enabled=function() return true end,expect=unavoidable[path] and 'missing' or 'drawn'}
    SCENARIOS[#SCENARIOS+1]={name='device refuses the first '..path,fail={[path]=first},
      enabled=function() return true end,expect='drawn'}
  end
  SCENARIOS[#SCENARIOS+1]={name='GLES2: mipmapped NPOT images refused',fail={['graphics.newImage']=mipmapped},
    enabled=function() return true end,expect='drawn'}
  local failures=0
  for _,s in ipairs(SCENARIOS) do
    local drawn,err,warnings=run(s)
    local got=drawn==nil and 'error' or (drawn>50 and 'drawn' or 'missing')
    local pass=got==s.expect
    if not pass then failures=failures+1 end
    print(('%s %-52s expected %-7s got %-7s pixels=%s%s'):format(pass and 'PASS ' or 'FAIL ',s.name,
      s.expect,got,tostring(drawn),
      (drawn==nil and ('  '..tostring(err):match('[^\n]*')))
        or (#warnings>0 and ('  warn: '..tostring(warnings[1]):match('[^\n]*'))) or ''))
  end
  print(failures==0 and 'Stadium UI visibility: every setup as expected'
    or ('Stadium UI visibility: %d setup(s) not as expected'):format(failures))
  love.event.quit(failures==0 and 0 or 1)
end
