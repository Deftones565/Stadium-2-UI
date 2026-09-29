package.path="./?.lua;./?/init.lua;"..package.path
-- Draw-time sprite offsets on a Gen 2 battle screen (lib/sprite_offsets.lua),
-- against stand-ins with the host's method shapes (src/ui/gen2/BattleState
-- drawPic / drawLiftedRows, BattleAnimView present / drawObjects). The Gen 1
-- path is checked against the real engine draw in
-- tests/drivers/engine_effects.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local translated={}
love={graphics={push=function() translated[#translated+1]={0,0} end,pop=function() end,
  translate=function(x,y) local t=translated[#translated] t[1],t[2]=t[1]+x,t[2]+y end,
  getScissor=function() return nil end,setScissor=function() end}}

local Offsets=require("mods.STADIUM2_UI.lib.sprite_offsets")

local Screen={}
Screen.__index=Screen
local picCalls={}
function Screen:drawPic(mon,back) picCalls[#picCalls+1]={back=back,t=translated[#translated]} end
function Screen:drawLiftedRows() picCalls[#picCalls+1]={lifted=true,t=translated[#translated]} end
function Screen:animPicState(side) return self.lift[side] end
local View={}
View.__index=View
local seen={}
function View:present(runner) seen.bg=runner.bg end
function View:drawObjects(runner) seen.oam=runner:oam() end
local Runner={}
Runner.__index=Runner
function Runner:oam() return self.objects end

local lyBackup={}
for i=0,0x90 do lyBackup[i]=0 end
for i=0,0x36 do lyBackup[i]=0x02 end
local runner=setmetatable({objects={{x=120+8,y=20+16,tile=1},{x=80+8,y=100+16,tile=2}},
  bg={lcdc="SCX",lyStart=0,lyEnd=0x36,lyBackup=lyBackup,scx=0,scy=0}},Runner)
local screen=setmetatable({lift={player={},enemy={}},animView=setmetatable({},View)},Screen)

local isLive=true
Offsets.install({screen=screen},function() return isLive end)
ok(Offsets.isOwn(rawget(screen,"drawPic")) and Offsets.isOwn(rawget(screen.animView,"present")),
  "the overrides sit on this screen and its view only")
ok(rawget(Screen,"drawPic") and not Offsets.isOwn(Screen.drawPic),"the host class keeps its methods")

-- no offsets: straight through
screen:drawPic({},true)
ok(picCalls[1].back==true and #translated==0,"no offset: the host draws the pic untouched")

Offsets.set({-16,8},{24,-4},{enemy={96,0,56,56},player={8,40,64,56}})
picCalls,translated={}, {}
screen:drawPic({},false); screen:drawPic({},true)
ok(picCalls[1].t[1]==-16 and picCalls[1].t[2]==8,"the enemy pic draws at its offset")
ok(picCalls[2].t[1]==24 and picCalls[2].t[2]==-4,"the player's back pic draws at its offset")

-- OAM over the enemy moves with it; OAM elsewhere stays
screen.animView:drawObjects(runner)
ok(seen.oam[1].x==128-16 and seen.oam[1].y==36+8,"an animation sprite over the enemy moves with it")
ok(seen.oam[2].x==88 and seen.oam[2].y==116,"one elsewhere stays")
ok(runner.objects[1].x==128,"the runner's own objects are not changed")
ok(rawget(runner,"oam")==nil,"the OAM shift lasts only for that draw")

-- Gold's per-scanline window on the enemy's rows follows its 8 px drop
screen.animView:present(runner)
ok(seen.bg.lyStart==8 and seen.bg.lyEnd==0x36+8,"the enemy's scanline window follows its rows")
ok(seen.bg.lyBackup[8]==0x02 and seen.bg.lyBackup[4]==0,"the per-row values move with it")
ok(runner.bg.lyStart==0 and runner.bg.lyBackup[4]==0x02,"the engine's own registers are untouched")

-- lifted rows (Withdraw, Dig) go with their side
screen.lift.player={lifted=true}
picCalls,translated={}, {}
screen:drawLiftedRows()
ok(picCalls[1].t[1]==24 and picCalls[1].t[2]==-4,"the player's lifted rows move with it")

-- the UI not drawing: everything passes straight through
isLive=false
picCalls,translated={}, {}
screen:drawPic({},false)
ok(#translated==0,"UI not drawing: the host draws as always")
isLive=true

Offsets.release()
ok(rawget(screen,"drawPic")==nil and rawget(screen,"drawLiftedRows")==nil
  and rawget(screen.animView,"present")==nil and rawget(screen.animView,"drawObjects")==nil,
  "release() takes every override off")
print(checks.." checks passed (draw-time sprite offsets, Gen 2)")
