package.path="./?.lua;./?/init.lua;"..package.path
-- Stadium UI logic without LOVE or the ROM: HP tiers and fill
-- (func_80064590 / the captured 49/94 and 87/87 bars), status names, and the
-- 320x240 placement on landscape and portrait screens.
local UI=require("mods.STADIUM2_UI.lib.stadium_ui")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

-- func_80064590: tier from hp*48/max (>=24 green, >=10 yellow, else red, 0 none).
ok(UI.hpTier(94,94)==0 and UI.hpTier(47,94)==0,"half HP or more is green")
ok(UI.hpTier(46,94)==1 and UI.hpTier(20,94)==1,"below half is yellow")
ok(UI.hpTier(19,94)==2 and UI.hpTier(1,94)==2,"below 10/48 is red")
ok(UI.hpTier(0,94)==3,"0 HP draws no fill")
-- Captured frames: 49/94 fills 22 px, 87/87 fills the whole 43 px bar.
ok(UI.hpFill(49,94)==22 and UI.hpFill(87,87)==43,"bar fill matches the ROM frame")
ok(UI.hpFill(0,50)==0 and UI.hpFill(99,50)==43,"bar fill clamps")
-- Host spellings to the file-35 labels.
ok(UI.statusKey("PSN")=="PSN" and UI.statusKey("poison")=="PSN" and UI.statusKey("TOX")=="PSN","poison")
ok(UI.statusKey("paralyze")=="PAR" and UI.statusKey("PAR")=="PAR","paralysis")
ok(UI.statusKey("sleep")=="SLP" and UI.statusKey("SLP")=="SLP","sleep")
ok(UI.statusKey("freeze")=="FRZ" and UI.statusKey("BRN")=="BRN","freeze and burn")
ok(UI.statusKey(nil)=="OK" and UI.statusKey("PSN",true)=="FNT","none and fainted")
-- Landscape: scale by height, player flush left, opponent flush right.
local wide=UI.placement({x=0,y=0,w=1920,h=1080})
ok(math.abs(wide.scale-4.5)<1e-9 and wide.left==0 and math.abs(wide.right-(1920-1440))<1e-9,
  "16:9: Stadium's layout at screen height, columns pinned to the edges")
local tall=UI.placement({x=10,y=20,w=640,h=576})
ok(math.abs(tall.scale-640/344)<1e-9 and tall.slack>0,"narrow boxes scale by width, extra height is slack")
local tiny=UI.placement({x=0,y=0,w=320,h=240})
ok(tiny.scale<1 and tiny.menuX+UI.MENU_RIGHT*tiny.scale<=320+1e-9,"4:3: the menu row fits the width")
ok(tiny.menuX+UI.MENU_LEFT*tiny.scale>=UI.PLAYER_COLUMN_RIGHT*tiny.scale-1e-9,"menus clear the player's column")

-- Type order from D_84186FE8/D_84186F98 (Rock = 5, Ground = 4, none = 0x12).
ok(UI.typeIndex("ROCK")==5 and UI.typeIndex("ground")==4 and UI.typeIndex("DARK")==17,"Stadium type order")
ok(UI.typeIndex(nil)==0x12 and UI.typeIndex("BIRD")==0x12,"unknown types draw as none")
ok(UI.TYPE_COLOR[5][1]==180 and UI.TYPE_COLOR[10][1]==240,"Rock and Fire tints from the capture")

-- Menu input: C buttons pick moves, L cancels, Stadium mode maps B/Start/R.
local Menu=require("mods.STADIUM2_UI.lib.stadium_menu")
local picked,taps
local function reset() picked,taps=nil,{} end
local function tap(button) taps[#taps+1]=button end
local game={input={pressQueue={}}}
reset()
local moves={kind="moves",moveCount=4,select=function(i) picked=i end}
Menu.step(game,moves,"cursor",tap,{})
Menu.step(game,moves,"cursor",tap,{CRIGHT=true})
ok(picked==2 and taps[1]=="a","C-right picks move 2 and confirms")
reset(); Menu.step(game,moves,"cursor",tap,{CRIGHT=true})
ok(picked==nil and #taps==0,"a held C button does not repeat")
reset(); Menu.step(game,moves,"cursor",tap,{})
Menu.step(game,{kind="moves",moveCount=2,select=function(i) picked=i end},"cursor",tap,{CDOWN=true})
ok(picked==nil,"a C button past the move count does nothing")
reset(); game.input.pressQueue={"l"}
Menu.step(game,moves,"cursor",tap,{})
ok(taps[1]=="b","L cancels through the host's B")
local tabs={{button="A",hostIndex=1},{button="B",hostIndex=2},{button="S",hostIndex=4},{button="R",hostIndex=3}}
local command={kind="command",tabs=tabs,select=function(i) picked=i end}
reset(); game.input.pressQueue={"b"}
Menu.step(game,command,"cursor",tap,{})
ok(picked==2 and taps[1]=="a","B opens POKeMON in cursor mode too")
reset(); game.input.pressQueue={"a"}
Menu.step(game,command,"cursor",tap,{})
ok(picked==nil and #taps==0,"cursor mode leaves A to the host cursor")
reset(); game.input.pressQueue={"b"}
Menu.step(game,command,"stadium",tap,{})
ok(picked==2 and taps[1]=="a","Stadium mode: B opens POKeMON")
reset(); game.input.pressQueue={"start"}
Menu.step(game,command,"stadium",tap,{})
ok(picked==4 and taps[1]=="a","Stadium mode: Start runs")
reset(); game.input.pressQueue={"a"}
Menu.step(game,command,"stadium",tap,{})
ok(picked==1 and #taps==0,"Stadium mode: A selects BATTLE and the host's A confirms")

-- The Stadium bar is one row (BATTLE, POKeMON, RUN, PACK = host 1, 2, 4, 3):
-- left/right step along it, up/down never reach the host's 2x2 grid.
local hostIndex=1
local bar={kind="command",tabs=tabs,select=function(i) hostIndex=i end,current=function() return hostIndex end}
reset(); game.input.pressQueue={"right"}
Menu.step(game,bar,"cursor",tap,{})
ok(hostIndex==2 and #game.input.pressQueue==0,"right: BATTLE -> POKeMON")
game.input.pressQueue={"right"}; Menu.step(game,bar,"cursor",tap,{})
ok(hostIndex==4,"right: POKeMON -> RUN (host index 4)")
game.input.pressQueue={"right"}; Menu.step(game,bar,"cursor",tap,{})
game.input.pressQueue={"right"}; Menu.step(game,bar,"cursor",tap,{})
ok(hostIndex==3,"right: RUN -> PACK, then clamps")
game.input.pressQueue={"left"}; Menu.step(game,bar,"cursor",tap,{})
ok(hostIndex==4,"left: PACK -> RUN")
game.input.pressQueue={"up","down"}; Menu.step(game,bar,"cursor",tap,{})
ok(hostIndex==4 and #game.input.pressQueue==0 and #taps==0,"up/down are withheld")

-- Switch screen: C-left/C-up/C-right pick members 1..3 through the host's
-- party menu (A opens its submenu, then SWITCH is chosen next tick).
local sub,subAction=false,nil
local switch={kind="switch",memberCount=3,select=function(i) picked=i end,
  submenuOpen=function() return sub end,
  selectSub=function(action) subAction=action return true end}
Menu.reset(); reset(); game.input.pressQueue={}
Menu.step(game,switch,"cursor",tap,{})
Menu.step(game,switch,"cursor",tap,{CUP=true})
ok(picked==2 and taps[1]=="a","C-up picks member 2 and opens the host submenu")
reset(); sub=true
Menu.step(game,switch,"cursor",tap,{})
ok(subAction=="battle_switch" and taps[1]=="a","the next tick chooses SWITCH")
reset(); sub=false; subAction=nil; game.input.pressQueue={"a"}
Menu.step(game,switch,"cursor",tap,{})
reset(); sub=true; game.input.pressQueue={}
Menu.step(game,switch,"cursor",tap,{})
ok(subAction=="battle_switch","the host's own A switches directly, as selecting does in Stadium")
reset(); sub=false; subAction=nil
Menu.step(game,nil,"cursor",tap,{})
sub=true
Menu.step(game,switch,"cursor",tap,{})
ok(subAction==nil,"a pending pick does not survive leaving the switch screen")

-- A controller in use means Stadium controls (func_8413A53C / func_84139EB0):
-- no cursor, A withheld where Stadium does not read it, D-pad held shows a
-- move's info card; the keyboard keeps the cursor.
Menu.reset(); reset()
local held={}
local padGame={input={pressQueue={"a"},sources={a={["pad:a"]=true}},
  isDown=function(_,b) return held[b]==true end}}
Menu.step(padGame,moves,"cursor",tap,{})
ok(Menu.device()=="pad" and Menu.stadiumControls("cursor"),"a pad press switches to Stadium controls")
ok(#padGame.input.pressQueue==0 and picked==nil,"the pad's A is withheld on the move screen")
held.right=true
ok(Menu.infoSlot(padGame,"cursor",1,4)==2,"D-pad right held shows move 2's info (func_8413A12C(1))")
held.right=nil; held.left=true
ok(Menu.infoSlot(padGame,"cursor",1,3)==nil,"no info card past the move count")
held.left=nil
local keyGame={input={pressQueue={"a"},sources={a={["key:z"]=true}},
  isDown=function(_,b) return held[b]==true end}}
Menu.step(keyGame,moves,"cursor",tap,{})
ok(Menu.device()=="keyboard" and not Menu.stadiumControls("cursor"),"a key press goes back to the cursor")
ok(#keyGame.input.pressQueue==1,"the keyboard's A reaches the host cursor")
held.r=true
ok(Menu.infoSlot(keyGame,"cursor",3,4)==3,"cursor controls: R held shows the cursor move's info")
held.r=nil
ok(Menu.stadiumControls("stadium"),"MENU CONTROLS = STADIUM uses Stadium controls on the keyboard")

-- Switch screen, from the game's handlers (func_8413B468 / func_8413B5D4):
-- three members C-left/C-up/C-right; four to six B, C-left, C-up / A,
-- C-down, C-right; the held D-pad shows a member's STATUS; R held + pick
-- checks; L cancels.
Menu.reset(); reset(); sub=false; subAction=nil
local six={kind="switch",memberCount=6,select=function(i) picked=i end,
  submenuOpen=function() return sub end,
  selectSub=function(action) subAction=action return true end}
local three={kind="switch",memberCount=3,select=function(i) picked=i end,
  submenuOpen=function() return sub end,
  selectSub=function(action) subAction=action return true end}
local rowGame={input={pressQueue={},sources={},isDown=function(_,b) return held[b]==true end}}
local function step(ctx,c,queue) rowGame.input.pressQueue=queue or {}; return Menu.step(rowGame,ctx,"stadium",tap,c or {}) end
step(three); step(three,{CUP=true})
ok(picked==2,"three: C-up picks member 2")
reset(); sub=true; step(three)
ok(subAction=="battle_switch","and switches")
reset(); sub=false; subAction=nil
step(six); step(six,{CUP=true})
ok(picked==3,"six: C-up picks member 3")
reset(); step(six); step(six,{CDOWN=true})
ok(picked==5,"six: C-down picks member 5")
reset(); step(six); step(six,{CRIGHT=true})
ok(picked==6,"six: C-right picks member 6")
reset(); picked=nil; step(six,nil,{"b"})
ok(picked==1 and #rowGame.input.pressQueue==0,"six: B picks member 1 (not the host's back)")
reset(); picked=nil; step(six,nil,{"a"})
ok(picked==4,"six: A picks member 4")
reset(); picked=nil; step(three,nil,{"a"})
ok(picked==nil,"three: A is not a pick")
-- CHECK (user request): hold R and hold a member's button for its STATUS
reset(); picked=nil
held.r=true
step(three); step(three,{CUP=true})
ok(Menu.statusMember()==2 and picked==nil,"three: R + C-up shows member 2's status, no switch")
step(three,{})
ok(Menu.statusMember()==nil,"letting go of C-up: the cards again")
step(six,{CDOWN=true})
ok(Menu.statusMember()==5,"six: R + C-down shows member 5")
held.b=true; step(six,{})
ok(Menu.statusMember()==1 and picked==nil,"six: R + B shows member 1")
held.b=nil; held.a=true; step(six,{})
ok(Menu.statusMember()==4 and picked==nil,"six: R + A shows member 4")
held.a=nil; held.r=nil; step(six,{CDOWN=true})
ok(Menu.statusMember()==nil,"without R the buttons do not show status")
held.left=true; step(six)
ok(Menu.statusMember()==nil,"the D-pad no longer shows status")
held.left=nil
-- CURSOR controls: R held shows the cursor's member
local cur={kind="switch",memberCount=3,current=function() return 3 end,select=function(i) picked=i end,
  submenuOpen=function() return false end,selectSub=function() return true end}
held.r=true; rowGame.input.pressQueue={}; Menu.step(rowGame,cur,"cursor",tap,{})
ok(Menu.statusMember()==3,"CURSOR: R held shows the cursor's member")
held.r=nil; Menu.step(rowGame,cur,"cursor",tap,{})
ok(Menu.statusMember()==nil,"and letting go of R closes it")
-- L: cancel
reset()
local tapped={}
rowGame.input.pressQueue={"l"}
Menu.step(rowGame,six,"stadium",function(b) tapped[#tapped+1]=b end,{})
ok(tapped[1]=="b","L cancels the switch screen")
Menu.step(rowGame,nil,"cursor",tap,{})
ok(Menu.statusMember()==nil,"leaving the switch screen clears the status view")

-- Touch: a long press shows a card's STATUS / a move's info until the next
-- tap, which only closes it; a short press still picks (on release).
do
  local UIm=require("mods.STADIUM2_UI.lib.stadium_ui")
  local clock=0
  local savedNow=Menu.now
  Menu.now=function() return clock end
  local savedHit=UIm.hitAt
  local target="switch:2"
  UIm.hitAt=function() return target end
  Menu.reset(); reset(); picked=nil
  local g2={input={pressQueue={},sources={},isDown=function() return false end}}
  local ctx={kind="switch",memberCount=6,select=function(i) picked=i end,
    submenuOpen=function() return false end,selectSub=function() return true end}
  Menu.pointer({phase="pressed",id=1,x=10,y=10})
  clock=0.2; Menu.step(g2,ctx,"cursor",tap,{})
  ok(Menu.statusMember()==nil and picked==nil,"a press shorter than a long press does nothing yet")
  clock=0.5; Menu.step(g2,ctx,"cursor",tap,{})
  ok(Menu.statusMember()==2 and picked==nil,"held long: member 2's STATUS, no switch")
  Menu.pointer({phase="released",id=1,x=10,y=10})
  Menu.step(g2,ctx,"cursor",tap,{})
  ok(Menu.statusMember()==2 and picked==nil,"releasing the long press keeps the STATUS up")
  Menu.pointer({phase="pressed",id=2,x=10,y=10}); Menu.pointer({phase="released",id=2,x=10,y=10})
  ok(Menu.step(g2,ctx,"cursor",tap,{})=="dismiss" and Menu.statusMember()==nil and picked==nil,
    "the next tap closes it without switching")
  Menu.pointer({phase="pressed",id=3,x=10,y=10}); Menu.pointer({phase="released",id=3,x=10,y=10})
  Menu.step(g2,ctx,"cursor",tap,{})
  ok(picked==2,"a tap switches, on release")
  -- moves: the info card
  target="move:3"; picked=nil
  local moves={kind="moves",moveCount=4,select=function(i) picked=i end}
  Menu.pointer({phase="pressed",id=4,x=10,y=10})
  clock=2; Menu.step(g2,moves,"cursor",tap,{})
  ok(Menu.infoSlot(g2,"cursor",1,4)==3 and picked==nil,"long press on a move: its info")
  Menu.pointer({phase="released",id=4,x=10,y=10})
  Menu.pointer({phase="pressed",id=5,x=10,y=10}); Menu.pointer({phase="released",id=5,x=10,y=10})
  Menu.step(g2,moves,"cursor",tap,{})
  ok(Menu.infoSlot(g2,"cursor",1,4)==nil and picked==nil,"a tap closes the move info")
  -- a drag is neither a tap nor a long press
  Menu.pointer({phase="pressed",id=6,x=10,y=10}); Menu.pointer({phase="moved",id=6,x=60,y=10})
  clock=5; Menu.step(g2,moves,"cursor",tap,{})
  Menu.pointer({phase="released",id=6,x=60,y=10}); Menu.step(g2,moves,"cursor",tap,{})
  ok(Menu.infoSlot(g2,"cursor",1,4)==nil and picked==nil,"a drag does nothing")
  Menu.now=savedNow; UIm.hitAt=savedHit; Menu.reset()
end

-- Going back: the L CANCEL tab (L, a tap on it, or the cursor on it).
do
  local UIm=require("mods.STADIUM2_UI.lib.stadium_ui")
  Menu.reset()
  local idx=3
  local g3={input={pressQueue={},sources={},isDown=function() return false end}}
  local ctx={kind="switch",memberCount=3,current=function() return idx end,select=function(i) idx=i end,
    submenuOpen=function() return false end,selectSub=function() return true end}
  local tapped={}
  local function go(queue,mode) g3.input.pressQueue=queue; tapped={}
    return Menu.step(g3,ctx,mode or "cursor",function(b) tapped[#tapped+1]=b end,{}) end
  ok(go({"l"},"stadium")=="cancel" and tapped[1]=="b","Stadium controls: L goes back")
  ok(go({"l"})=="cancel" and tapped[1]=="b","CURSOR controls: L goes back too")
  local savedHit=UIm.hitAt
  UIm.hitAt=function() return "cancel" end
  Menu.pointer({phase="pressed",id=9,x=1,y=1}); Menu.pointer({phase="released",id=9,x=1,y=1})
  ok(go({})=="cancel" and tapped[1]=="b","a tap on L CANCEL goes back")
  UIm.hitAt=savedHit
  idx=3
  ok(go({"down"})=="cancel-focus" and Menu.cancelFocus() and #g3.input.pressQueue==0,
    "CURSOR: down from the last member moves onto L CANCEL")
  ok(go({"up"})=="cancel-leave" and not Menu.cancelFocus(),"up leaves it")
  go({"down"})
  ok(go({"a"})=="cancel" and tapped[1]=="b" and not Menu.cancelFocus(),"A on L CANCEL goes back")
  idx=2
  ok(go({"down"})~="cancel-focus" and not Menu.cancelFocus(),"down elsewhere stays the host's")
  ctx.hostCancel=true; idx=3
  ok(go({"down"})~="cancel-focus","a host list with its own CANCEL row (Gen 2) keeps down")
  Menu.reset()
end

-- YES/NO (UI element 14/15): NO sits left of YES, so left/right pick
-- directly; A and B stay the host's.
Menu.reset(); reset()
local yes={kind="yesno",select=function(i) picked=i end}
local ynGame={input={pressQueue={"left"},sources={}}}
Menu.step(ynGame,yes,"cursor",tap,{})
ok(picked==2 and #taps==0,"left picks NO without confirming")
reset(); ynGame.input.pressQueue={"right"}
Menu.step(ynGame,yes,"cursor",tap,{})
ok(picked==1,"right picks YES")
reset(); ynGame.input.pressQueue={"a"}
Menu.step(ynGame,yes,"stadium",tap,{})
ok(#ynGame.input.pressQueue==1 and #taps==0,"A reaches the host's YES/NO in either control style")
ok(UI.YESNO.x==92 and UI.YESNO.y==17 and UI.YESNO.w==204 and UI.YESNO.h==50
  and UI.YESNO.optionY==26,"YES/NO window geometry from D_84186DD8..DF8")

-- HD UI upscale (port extension): 4x, flat areas unchanged, soft gradients
-- interpolated (no bands), hard edges re-sharpened, no dark fringe on
-- transparent texels.
local Assets=require("mods.STADIUM2_UI.lib.stadium_ui_assets")
local function px(r,g,b,a) return string.char(r,g,b,a) end
local flat=px(200,100,50,255):rep(4)
local up,uw,uh=Assets.upscale(flat,2,2,4)
ok(uw==8 and uh==8 and #up==8*8*4,"4x output size")
ok(up:sub(1,4)==px(200,100,50,255) and up:sub(-4)==px(200,100,50,255),"flat colour stays exact")
local grad=px(100,100,100,255)..px(110,110,110,255)
local gu=Assets.upscale(grad,2,1,4)
local mid=gu:byte(3*4+1)
ok(mid>100 and mid<110,"a soft gradient is interpolated, not stepped")
local hard=px(0,0,0,255)..px(255,255,255,255)
local hu=Assets.upscale(hard,2,1,4)
local near,edge=hu:byte(2*4+1),hu:byte(3*4+1)
ok(near<40 and edge<128,"a hard edge stays sharp (smoothstep)")
local halo=px(255,255,255,255)..px(0,0,0,0)
local tu=Assets.upscale(halo,2,1,4)
ok(tu:byte(7*4+4)==0 and tu:byte(7*4+1)==255,"transparent texels keep the neighbour colour (no dark fringe)")
Assets.setDetail("native"); ok(Assets.detail()=="native","N64 PIXELS detail")
Assets.setDetail("hd"); ok(Assets.detail()=="hd","HD detail")

-- Portrait eye (func_800371B4): target + (sin yaw cos pitch, sin pitch,
-- cos yaw cos pitch) * distance, angles quantised to the 4096-entry tables.
local Portrait=require("mods.STADIUM2_UI.lib.stadium_portrait")
local ex,ey,ez=Portrait.eye({pitch=0,yaw=0,distance=100,x=2,y=15})
ok(math.abs(ex-2)<1e-9 and math.abs(ey-15)<1e-9 and math.abs(ez-100)<1e-9,"yaw 0 looks down -z from +z")
ex,ey,ez=Portrait.eye({pitch=0,yaw=16384,distance=50,x=0,y=0})
ok(math.abs(ex-50)<1e-9 and math.abs(ez)<1e-9,"yaw 0x4000 puts the eye on +x")
ex,ey,ez=Portrait.eye({pitch=16384,yaw=0,distance=10,x=0,y=0})
ok(math.abs(ey-10)<1e-9,"pitch 0x4000 puts the eye overhead")
local a1={Portrait.eye({pitch=0,yaw=17,distance=1000,x=0,y=0})}
local a2={Portrait.eye({pitch=0,yaw=16,distance=1000,x=0,y=0})}
ok(a1[1]==a2[1],"angles use the table index (angle >> 4)")

-- Sharp portraits (port extension): twice the on-screen box, 32 px steps,
-- capped; no size keeps the native 32x32 buffer.
ok(Portrait.canvasSize(nil)==32 and Portrait.canvasSize(20)==32,"native 32x32 without an on-screen size")
ok(Portrait.canvasSize(144)==288 and Portrait.canvasSize(130)==288,"1080p box renders at 288")
ok(Portrait.canvasSize(4000)==Portrait.SHARP_MAX,"size is capped")

print(("%d checks passed (Stadium UI)"):format(checks))
