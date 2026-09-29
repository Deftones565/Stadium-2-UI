-- The real Gen 1 battle draw with this UI's draw-time sprite offsets
-- (lib/sprite_offsets.lua) and the engine's own full-screen effects.
-- Run from the game root (needs a Red import for the battle pictures):
--   love mods/STADIUM2_UI/tests/drivers/engine_effects
-- POKEPORT_ASSETS overrides where the imported assets are
-- (default ~/.local/share/pokemon-love2d/red/).
--
-- Renders the engine's BattleState:draw() into its 160x144 canvas and checks
-- that a moved Pokemon is drawn where it is moved (nothing left behind), that
-- the engine's palette flash and wave act on the whole picture with the
-- moved Pokemon in it (no hole, no cut), that animation sprites over a moved
-- Pokemon go with it, and that release() leaves the engine as it was.
local root=love.filesystem.getWorkingDirectory()
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local home=os.getenv('HOME') or ''
local ASSETS=os.getenv('POKEPORT_ASSETS') or (home..'/.local/share/pokemon-love2d/red/')

local checks,failures=0,0
local function ok(v,m)
  checks=checks+1
  if not v then failures=failures+1 print('FAIL '..m) else print('PASS '..m) end
end

-- the imported pictures live outside this test's LOVE file system
local function readImports()
  local newImage=love.graphics.newImage
  love.graphics.newImage=function(src,...)
    if type(src)=='string' and not love.filesystem.getInfo(src) then
      local f=io.open(ASSETS..src,'rb')
      if f then
        local bytes=f:read('*a');f:close()
        return newImage(love.filesystem.newFileData(bytes,src),...)
      end
    end
    return newImage(src,...)
  end
  local newImageData=love.image.newImageData
  love.image.newImageData=function(src,...)
    if type(src)=='string' and not love.filesystem.getInfo(src) then
      local f=io.open(ASSETS..src,'rb')
      if f then
        local bytes=f:read('*a');f:close()
        return newImageData(love.filesystem.newFileData(bytes,src),...)
      end
    end
    return newImageData(src,...)
  end
end

local function same(r1,g1,b1,r0,g0,b0) return math.abs(r1-r0)+math.abs(g1-g0)+math.abs(b1-b0)<.02 end

function love.load()
  local probe=io.open(ASSETS..'assets/generated/battle/back/pikachub.png','rb')
  if not probe then
    print('SKIP: engine effects test (no Red import at '..ASSETS..')')
    love.event.quit(0) return
  end
  probe:close()
  readImports()
  local okRun,err=pcall(function()
    local Data=require('src.core.Data')
    Data:load()
    local Pokemon=require('src.pokemon.Pokemon')
    local BattleState=require('src.battle.BattleState')
    local save=require('src.core.SaveData').newGame()
    save.party={Pokemon.new(Data,'PIKACHU',10)}
    local game={data=Data,save=save,stack={states={}},input={pressQueue={}}}
    local battle=BattleState.newWild(game,'PIDGEY',5)
    ok(battle and battle:colorMode(),'a real Gen 1 battle in the colour pipeline')
    local Offsets=require('mods.STADIUM2_UI.lib.sprite_offsets')
    local canvas=love.graphics.newCanvas(160,144)
    local function render(fx)
      battle.fx=fx
      love.graphics.setCanvas(canvas);love.graphics.clear(1,1,1,1)
      battle:draw()
      love.graphics.setCanvas()
      return canvas:newImageData()
    end
    local plain=render(nil)
    local pr,pg,pb=plain:getPixel(80,50) -- the field between the two Pokemon
    local liveNow=true
    Offsets.install({battle=battle},function() return liveNow end)
    ok(Offsets.isOwn(rawget(battle,'drawPicsLayer')),'the override sits on this battle object only')
    ok(rawget(BattleState,'drawPicsLayer')==Offsets.classMethod(battle,'drawPicsLayer'),'the engine class keeps its own method')

    local EDX,EDY,PDX,PDY=-24,20,30,-12
    Offsets.set({EDX,EDY},{PDX,PDY},{enemy={96,0,56,56},player={0,32,72,64}})
    local moved=render(nil)
    -- every picture pixel of the player's back sprite is drawn shifted
    local hits,total=0,0
    for y=40,95 do for x=8,63 do
      local r,g,b=plain:getPixel(x,y)
      if not same(r,g,b,pr,pg,pb) and x+PDX<160 and y+PDY>=0 then
        total=total+1
        local r1,g1,b1=moved:getPixel(x+PDX,y+PDY)
        if same(r1,g1,b1,r,g,b) then hits=hits+1 end
      end
    end end
    ok(total>200 and hits/total>.97,('the player Pokemon is drawn where it is moved (%d/%d)'):format(hits,total))
    -- and nothing of it is left at home (field shows through)
    local left=0
    for y=60,95 do for x=8,30 do
      local r,g,b=moved:getPixel(x,y)
      if not same(r,g,b,pr,pg,pb) then left=left+1 end
    end end
    ok(left<20,('nothing left behind at the old place (%d pixels)'):format(left))

    -- the engine's inverted palette ($1b), moved and not: the same picture
    -- everywhere the Pokemon are not, so no patch or hole
    local inv={bgp={[0]=3,2,1,0}}
    local invPlain,invMoved=(function() liveNow=false local a=render(inv) liveNow=true return a end)(),render(inv)
    local ir,ig,ib=invPlain:getPixel(80,50)
    ok(not same(ir,ig,ib,pr,pg,pb),'the flash changes the field colour')
    local r,g,b=invMoved:getPixel(20,90) -- the player's old place, now empty
    ok(same(r,g,b,ir,ig,ib),'the flash covers the moved-from place like the rest of the field (no hole)')
    local r2,g2,b2=invMoved:getPixel(40+PDX,70+PDY)
    local r3,g3,b3=invPlain:getPixel(40,70)
    ok(same(r2,g2,b2,r3,g3,b3),'the moved Pokemon takes the flash like the unmoved one')

    -- the wave bends the whole picture, the moved Pokemon with it. During
    -- the wave the engine draws the Pokemon grey and colours them by screen
    -- region (grayPics + the zone pass), so compare where the picture is
    -- (field or not), not its exact colour.
    local offsets={0,0,0,0,0,1,1,1,2,2,2,2,2,1,1,1,0,0,0,0,0,-1,-1,-1,-2,-2,-2,-2,-2,-1,-1,-1}
    local function field(img,x,y) local r,g,b=img:getPixel(x,y) return same(r,g,b,pr,pg,pb) end
    local function waveMatch(waved,flat)
      local good,n=0,0
      for y=0,95 do
        local o=offsets[(y*2+6)%32+1]
        for x=4,155 do
          n=n+1
          if field(waved,x,y)==field(flat,x-o,y) then good=good+1 end
        end
      end
      return good/n
    end
    local wave={wavy={left=10,phase=6}}
    local movedMatch=waveMatch(render(wave),moved)
    liveNow=false
    local plainMatch=waveMatch(render(wave),plain)
    liveNow=true
    -- (the wave frame draws the Pokemon by another route than the plain
    -- frame, so neither ratio is 1: what matters is that moving them does
    -- not change how the engine's wave treats the picture)
    ok(movedMatch>=plainMatch-.002,('with the Pokemon moved the wave bends the picture as it does unmoved (%.4f vs %.4f)')
      :format(movedMatch,plainMatch))

    -- animation sprites over a moved Pokemon go with it; the rest stay
    local drawn={}
    local Player={}
    Player.__index=Player
    function Player:draw(colorFn) return self:drawSprites(self.sprites,colorFn) end
    function Player:drawSprites(sprites) for _,s in ipairs(sprites) do drawn[#drawn+1]={s.x,s.y} end end
    battle.animPlaying=true
    battle.animPlayer=setmetatable({sprites={{x=30+8,y=70+16},{x=80+8,y=20+16},{x=120+8,y=20+16}}},Player)
    render(nil)
    ok(drawn[1][1]==38+PDX and drawn[1][2]==86+PDY,'a sprite over the player Pokemon moves with it')
    ok(drawn[2][1]==88 and drawn[2][2]==36,'a sprite over the open field stays where the engine put it')
    ok(drawn[3][1]==128+EDX and drawn[3][2]==36+EDY,'a sprite over the enemy Pokemon moves with it')
    ok(rawget(battle.animPlayer,'drawSprites')==nil,'the sprite shift lasts only for that draw')
    battle.animPlaying=false;battle.animPlayer=nil

    -- not drawing (the UI off): the engine draws as it always does
    liveNow=false
    local off=render(nil)
    ok(off:getString()==plain:getString(),'with the UI not drawing the engine picture is untouched')
    liveNow=true
    Offsets.release()
    ok(rawget(battle,'drawPicsLayer')==nil and rawget(battle,'drawAnimLayer')==nil,'release() takes every override off')
    ok(render(nil):getString()==plain:getString(),'after release the engine draws exactly as before')
  end)
  if not okRun then failures=failures+1 print('FAIL '..tostring(err)) end
  print(('%d checks, %d failed (engine effects with draw-time sprite offsets)'):format(checks,failures))
  love.event.quit(failures==0 and 0 or 1)
end
