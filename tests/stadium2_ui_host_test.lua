package.path="./?.lua;./?/init.lua;"..package.path
-- The Stadium UI over host battles (stubs, no LOVE): Gen 1 and Gen 2 menu
-- contexts, message ownership, the visibility hook answers, hidden host
-- states, the Gen 2 move side, deferring to the importer's own UI, and
-- main.lua's hooks and build stamp.
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local BS1,BS2={},{}
local PartyMenu,ChoiceBox,PartyMenu2={}, {}, {}
package.loaded["src.battle.BattleState"]=BS1
package.loaded["src.ui.gen2.BattleState"]=BS2
package.loaded["src.ui.PartyMenu"]=PartyMenu
package.loaded["src.ui.ChoiceBox"]=ChoiceBox
package.loaded["src.ui.gen2.PartyMenu"]=PartyMenu2

local UI=require("mods.STADIUM2_UI.lib.stadium_ui")
UI.available=function() return true end
local BattleUI=require("mods.STADIUM2_UI.lib.battle_ui")
local enabled=true
BattleUI.bind({},function() return enabled end,function() end)

-- Gen 1 ---------------------------------------------------------------
local mon={hp=10,level=5,stats={hp=20},species=25,dvs={attack=1,defense=1,speed=1,special=1}}
local game1={stack={states={}},save={player={name="RED"}}}
local b1=setmetatable({game=game1,phase="menu",menuIndex=1,kind="wild",
  player={mon=mon,name="PIKACHU",shownHP=10},enemy={mon={hp=5,level=3,stats={hp=9},species=16},name="PIDGEY",shownHP=5},
  playerPartyView=function() return {mon} end,visibleText=function() return {"PIKACHU used","TACKLE!"} end},BS1)
game1.stack.states={b1}
local a1=BattleUI.adapterFor(game1)
ok(a1 and a1.battle==b1,"finds the Gen 1 battle on the stack")
ok(BattleUI.menuContext().kind=="command","Gen 1 menu phase: the command bar")
ok(BattleUI.bottomVisible(b1)==false,"the host's bottom box is hidden under the Stadium menu")
ok(BattleUI.statusVisible(b1)==false,"the host's status HUD is hidden")
local panels=a1:panels()
ok(panels.player and panels.player.name=="PIKACHU" and panels.player.hp==10 and panels.player.maxHp==20,"player panel data")
ok(panels.player.dex==25 and panels.player.variant=="normal","portrait species")
ok(panels.enemy and panels.enemy.level==3,"enemy panel data")
b1.phase="moveSelect"; b1.player.curMoves={{id="TACKLE",pp=30}}
ok(BattleUI.menuContext().kind=="moves","move select: the move diamond")
b1.phase="messages"
ok(BattleUI.menuContext()==nil and BattleUI.bottomVisible(b1)==false,"messages: the Stadium message box owns the bottom")
ok(a1:messageLines()[2]=="TACKLE!","message lines from the host")
b1.visibleText=function() return nil end
ok(a1:messageLines()[1]=="PIKACHU used","text-less stretch keeps the last message")
b1.animAttackerIsPlayer=false
ok(a1:messageSide()=="enemy","message tint follows the attacker")
local choice=setmetatable({labels={"YES","NO"},index=1},ChoiceBox)
game1.stack.states={b1,choice}
local ctx=BattleUI.menuContext()
ok(ctx.kind=="yesno" and BattleUI.hidesState(choice),"battle YES/NO: Stadium window, host box hidden")
ctx.select(2); ok(choice.index==2,"YES/NO select drives the host cursor")
local party=setmetatable({battle=b1,party={mon,mon},index=1},PartyMenu)
game1.stack.states={b1,party}
ctx=BattleUI.menuContext()
ok(ctx.kind=="switch" and ctx.memberCount==2 and BattleUI.hidesState(party),"party menu: switch cards, host list hidden")
game1.stack.states={b1}; b1.phase="menu"
b1.player.substituteHP=5
ok(a1:panel("player").dex==nil,"no portrait for the Substitute doll")
b1.player.substituteHP=nil

-- The battle bag (Gen 1): the Stadium item list stands in for the host box.
local ListMenu,TextBox={}, {}
package.loaded["src.ui.ListMenu"]=ListMenu
package.loaded["src.render.TextBox"]=TextBox
local bag=setmetatable({kind="bag",title="ITEMS",index=1,scroll=0,cursorRows=3,
  items={{value="POTION",label="POTION",count=3},{value="POKE_BALL",label="POK\195\169 BALL",count=5},
    {value="ANTIDOTE",label="ANTIDOTE",count=1},{value="BIKE",label="BICYCLE"},{cancel=true,label="CANCEL"}}},ListMenu)
game1.stack.states={b1,bag}; b1.phase="menu"
local packCtx=BattleUI.menuContext()
ok(packCtx and packCtx.kind=="pack" and BattleUI.hidesState(bag),"Gen 1 bag: Stadium item list, host box hidden")
ok(BattleUI.bottomVisible(b1)==false,"the host's bottom box stays hidden under the item list")
packCtx.select(5); ok(bag.index==5 and bag.scroll==2,"row pick drives the host cursor and its 3-row window")
local pv=a1:packView(packCtx)
ok(pv.title=="ITEMS" and #pv.rows==5 and pv.rows[1].count==3 and pv.rows[4].count==nil and pv.rows[5].cancel,"item rows, counts and CANCEL")
ok(BattleUI.prompt(a1,packCtx)[1]=="Use which item?","item list prompt")
local refused=setmetatable({visibleText=function() return {"OAK: RED!","This isn't the"} end},TextBox)
game1.stack.states={b1,bag,refused}
packCtx=BattleUI.menuContext()
ok(packCtx.kind=="pack" and BattleUI.hidesState(refused) and BattleUI.hidesState(bag),"a message over the bag: both hidden")
ok(BattleUI.prompt(a1,packCtx)[1]=="OAK: RED!","the bag's message shows in the Stadium box")
packCtx.select(1); ok(bag.index==5,"the list holds still under a message")
game1.stack.states={b1,{}}
ok(BattleUI.menuContext()==nil,"another screen over the battle: no command bar (its D-pad stays its own)")
game1.stack.states={b1}

-- Level-up stats (Gen 1): the Stadium card stands in for the StatBox.
local StatBox={}
BS1.StatBox=StatBox
local sb=setmetatable({mon={nickname="PIKACHU",level=41,species=25,stats={attack=60,defense=45,speed=90,special=55}}},StatBox)
b1.phase="messages"; b1.visibleText=function() return {"PIKACHU grew","to level 41!"} end
game1.stack.states={b1,sb}
local statCtx=BattleUI.menuContext()
ok(statCtx and statCtx.kind=="stats" and BattleUI.hidesState(sb),"Gen 1 stats: Stadium card, host window hidden")
local sv=a1:statsView(statCtx)
ok(sv.name=="PIKACHU" and sv.level==41 and #sv.rows==4 and sv.rows[1][1]=="ATTACK" and sv.rows[3][2]==90,"the host's four stats")
ok(BattleUI.prompt(a1,statCtx)[1]=="PIKACHU grew","the grew-to-level line stays in the box")
ok(UI.menuBottom("stats")>=19+15+5*12+3+4,"the stats card fits five rows")
game1.stack.states={b1}; b1.phase="menu"

-- Evolution (Gen 1): its text boxes over the battle go to the Stadium box.
local EvolutionState={}
package.loaded["src.ui.EvolutionState"]=EvolutionState
local intro=setmetatable({visibleText=function() return {"What?","PIKACHU is"} end},TextBox)
local hold={t=0,update=function() end,draw=function() end}
game1.stack.states={b1,intro,hold}
local ht=BattleUI.hostText()
ok(ht and ht.lines[1]=="What?" and not ht.evolution and BattleUI.hidesState(intro),"evolving text: Stadium box, host box hidden")
ok(BattleUI.menuContext()==nil,"no menu over the evolution")
local movie=setmetatable({},EvolutionState)
game1.stack.states={b1,intro,movie}
ht=BattleUI.hostText()
ok(ht and ht.evolution and ht.lines[1]=="What?" and BattleUI.hidesState(intro) and not BattleUI.hidesState(movie),"movie: the scene stays native, its text in the Stadium box")
local done=setmetatable({visibleText=function() return {"PIKACHU evolved","into RAICHU!"} end},TextBox)
game1.stack.states={b1,intro,movie,done}
ht=BattleUI.hostText()
ok(ht.lines[2]=="into RAICHU!" and BattleUI.hidesState(done) and BattleUI.hidesState(intro),"evolved text in the Stadium box")
game1.stack.states={b1,bag,refused}
ok(BattleUI.hostText()==nil,"a box over the bag is the bag's, not host text")
game1.stack.states={b1}
ok(BattleUI.hostText()==nil,"nothing over the battle: no host text")

-- EXP bar: Gen 1 from the growth curve, gliding up and over a level.
package.loaded["src.pokemon.Growth"]={expForLevel=function(_,lv) return lv*100 end}
b1.data={pokemon={[25]={name="PIKACHU",growthRate="MEDIUM_FAST"}}}
local expMon={level=10,exp=1050,species=25,hp=10,stats={hp=20}}
ok(math.abs(a1:expFraction(expMon)-0.5)<1e-9,"Gen 1 EXP: half way to the next level")
expMon.level=100; ok(a1:expFraction(expMon)==1,"level 100: full bar")
local glideMon={}
ok(BattleUI.expGlide(glideMon,10,0.5,0)==0.5,"first sight: the bar starts where the EXP is")
ok(math.abs(BattleUI.expGlide(glideMon,10,0.8,0.1)-0.62)<1e-9,"then climbs toward new EXP")
local v=BattleUI.expGlide(glideMon,11,0.1,0.5)
ok(v==0,"a level gained: the bar fills, then starts over")
ok(math.abs(BattleUI.expGlide(glideMon,11,0.1,0.05)-0.06)<1e-9 and BattleUI.expGlide(glideMon,11,0.1,1)==0.1,"and climbs to the new level's EXP")
ok(BattleUI.expGlide({},11,0.3,0.1)==0.3,"another Pokemon: no glide")

-- Picking the Pokemon already out: the host's refusal box over its party
-- list stays in the Stadium layout (cards, refusal in the Stadium box).
local outParty=setmetatable({battle=b1,party={mon,mon},index=1},PartyMenu)
local outBox=setmetatable({visibleText=function() return {"PIKACHU is","already out!"} end},TextBox)
game1.stack.states={b1,outParty,outBox}; b1.phase="messages"
local outCtx=BattleUI.menuContext()
ok(outCtx and outCtx.kind=="switch" and outCtx.text==outBox,"refusal over the party: still the Stadium cards")
ok(BattleUI.hidesState(outParty) and BattleUI.hidesState(outBox),"host list and its refusal box both hidden")
ok(a1:menuView(outCtx).message=="PIKACHU is\nalready out!","the refusal shows in the Stadium box")
outCtx.select(2); ok(outParty.index==1,"the cards hold still under the refusal")
local Menu=require("mods.STADIUM2_UI.lib.stadium_menu")
local tapped
local outGame={input={pressQueue={"a"},isDown=function() return false end}}
Menu.step(outGame,outCtx,"stadium",function(b) tapped=b end)
ok(outGame.input.pressQueue[1]=="a" and tapped==nil,"A reaches the refusal box (not withheld, no switch pick)")
game1.stack.states={b1}; b1.phase="menu"

-- Deferring and disabling -------------------------------------------------
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"]={stadiumUiEnabled=function() return true end}
ok(BattleUI.menuContext()==nil and BattleUI.statusVisible(b1)==true,"stands aside for the importer's own Stadium UI")
package.loaded["mods.STADIUM2_IMPORTER.lib.importer"]={stadiumUiEnabled=function() return false end}
enabled=false
ok(BattleUI.bottomVisible(b1)==true and BattleUI.statusVisible(b1)==true,"STADIUM UI off: host UI untouched")
enabled=true

-- Gen 2 ---------------------------------------------------------------
local g2mon={hp=30,level=20,maxHp=40,species=155,gender="female"}
local game2={stack={states={}},data={moves={TACKLE={name="TACKLE",type="NORMAL",pp=35,power=35,accuracy=95,description="A full-body charge."}}}}
local screen=setmetatable({game=game2,phase="menu",menuIndex=1,messageTimer=0,showPlayerHud=true,showEnemyHud=true,
  save={player={name="GOLD"}},battle={party={g2mon},enemyParty={},trainer={name="FALKNER"},volatile=function() return {} end},
  activeMon=function(_,side) return g2mon end,name=function(_,m) return "CYNDAQUIL" end,
  hudHp=function(_,m) return m.hp end,hudStatus=function() return nil end,
  playerMoves=function() return {{id="TACKLE",pp=30}} end,
  messageLines=function() return {"CYNDAQUIL used","TACKLE!"} end,queue={}},BS2)
game2.stack.states={screen}
local a2=BattleUI.adapterFor(game2)
ok(a2 and a2.screen==screen,"finds the Gen 2 battle screen")
ok(BattleUI.menuContext().kind=="command","Gen 2 menu phase: the command bar")
screen.messageTimer=5
ok(BattleUI.menuContext()==nil and BattleUI.bottomVisible(screen)==false,"prompt still typing: the Stadium message box")
screen.messageTimer=0
local p2=a2:panels()
ok(p2.player.name=="CYNDAQUIL" and p2.player.gender=="F" and p2.player.maxHp==40,"Gen 2 panel data")
ok(p2.enemy.tag=="FALKNER","trainer tag")
screen.phase="moves"
local moves=a2:moves()
ok(moves[1].name=="TACKLE" and moves[1].description=="A full-body charge.","move info uses the host's description")
screen.phase="ask-shift"; screen.shiftIndex=1
ctx=BattleUI.menuContext()
ok(ctx.kind=="yesno" and ctx.yesIndex==1,"Gen 2 YesNoBox: the Stadium window")
ctx.select(2); ok(screen.shiftIndex==2,"YES/NO select drives Gold's cursor")
screen.phase="menu"; screen.contest=true
ok(BattleUI.menuContext()==nil and BattleUI.bottomVisible(screen)==true,"Bug Contest menu stays native")
screen.contest=nil
-- The battle PACK (Gen 2): pockets, USE/QUIT, messages and descriptions.
local PackMenu2={}
PackMenu2.__index=PackMenu2
package.loaded["src.ui.gen2.PackMenu"]=PackMenu2
function PackMenu2:inBattle() return self.battle end
function PackMenu2:pocket() return {id="ITEM",label="ITEMS"} end
function PackMenu2:ensureVisible() self.visible=true end
function PackMenu2:switchPocket(d) self.pocketMoved=d end
function PackMenu2:pagesFor(lines) return {{lines[1],lines[2]},{lines[3]}} end
function PackMenu2:playerName() return "GOLD" end
function PackMenu2:description() return "Restores HP by<NEXT>20 points." end
local pack=setmetatable({battle=true,index=1,rows={{id="POTION",name="POTION",count=2,showCount=true},
  {id="TM_01",name="TM01",tmhmLabel="01",teaches="DYNAMICPUNCH",count=1,showCount=true}}},PackMenu2)
game2.stack.states={screen,pack}; screen.phase="menu"
local pc2=BattleUI.menuContext()
ok(pc2 and pc2.kind=="pack" and BattleUI.hidesState(pack),"Gen 2 PACK: Stadium item list, host screen hidden")
pc2.select(2); ok(pack.index==2 and pack.visible,"row pick drives the PACK cursor")
pc2.pocket(1); ok(pack.pocketMoved==1,"pocket arrows switch pockets")
local v2=a2:packView(pc2)
ok(v2.pockets and v2.title=="ITEMS" and #v2.rows==3 and v2.rows[3].cancel,"pocket rows and CANCEL")
ok(v2.rows[2].name=="01 DYNAMICPUNCH","TM rows read as the move")
ok(v2.description[1]=="Restores HP by" and v2.description[2]=="20 points.","description split at <NEXT>")
pack.submenu={rows={"use","quit"},index=1}
v2=a2:packView(pc2)
ok(v2.submenu.labels[1]=="USE" and v2.submenu.labels[2]=="QUIT","USE / QUIT submenu")
ok(pc2.selectSub(2) and pack.submenu.index==2,"submenu pick")
pc2.select(1); ok(pack.index==2,"list holds under the submenu")
pack.submenu=nil
pack.message={"OAK: {PLAYER}!","This isn't the","time to use that!"}; pack.messagePage=1
ok(BattleUI.prompt(a2,pc2)[1]=="OAK: GOLD!" and BattleUI.prompt(a2,pc2)[2]=="This isn't the","PACK message page in the Stadium box")
pack.message=nil
game2.stack.states={screen,{}}
ok(BattleUI.menuContext()==nil,"Gen 2: another screen on top, no command bar")
game2.stack.states={screen}
-- Level-up stats (Gen 2): the screen's own stats box is covered only while
-- the Stadium UI is drawing.
local hostDrew=0
function BS2.drawStatsBox() hostDrew=hostDrew+1 end
screen.phase="stats-box"; screen.statsBoxMon={level=21,stats={attack=30,defense=31,specialAttack=40,specialDefense=41,speed=50}}
local st2=BattleUI.menuContext()
ok(st2 and st2.kind=="stats","Gen 2 stats-box phase: the Stadium card")
local sv2=a2:statsView(st2)
ok(#sv2.rows==5 and sv2.rows[3][1]=="SPCL.ATK" and sv2.rows[5][2]==50 and sv2.level==21,"Gen 2's five stats")
local covering=true
a2:coverStatsBox(function() return covering end)
screen:drawStatsBox(screen.statsBoxMon)
ok(hostDrew==0,"host stats box skipped while the Stadium UI draws")
covering=false
screen:drawStatsBox(screen.statsBoxMon)
ok(hostDrew==1,"host stats box back when the Stadium UI is not drawing")
a2:release()
ok(rawget(screen,"drawStatsBox")==nil,"release removes the cover")
screen.phase="menu"; screen.statsBoxMon=nil
screen.shownExp=32; screen.shownLevel=20
ok(a2:panels().player.exp==0.5 and a2:panels().player.level==20,"Gen 2 EXP: the host's crawling bar and level")
screen.shownExp=nil; screen.shownLevel=nil
-- Evolution (Gen 2): the EvolutionAnim's lines, its drawPanel covered.
local EvolutionAnim={}
EvolutionAnim.__index=EvolutionAnim
package.loaded["src.ui.gen2.EvolutionAnim"]=EvolutionAnim
local seen
function EvolutionAnim:drawPanel() seen=self.lines end
local anim=setmetatable({lines={"Congratulations! Your","CYNDAQUIL"}},EvolutionAnim)
game2.stack.states={screen,anim}
local h2=BattleUI.hostText()
ok(h2 and h2.evolution and h2.lines[2]=="CYNDAQUIL","Gen 2 evolution text for the Stadium box")
local cov=true
a2:coverHostText(h2,function() return cov end)
anim:drawPanel(); ok(seen==nil and anim.lines[1]=="Congratulations! Your","host panel drawn without its lines, which stay intact")
cov=false; anim:drawPanel(); ok(seen and seen[1]=="Congratulations! Your","lines back when the Stadium UI is not drawing")
a2:release(); ok(rawget(anim,"drawPanel")==nil,"release removes the evolution cover")
game2.stack.states={screen}
local ev={kind="move",side="enemy"}
screen.queue={ev}; a2:track(); screen.queue={}; a2:track()
ok(a2:messageSide()=="enemy","the move leaving the queue sets the message side")

-- Sprite battles: the portrait is the front sprite, coloured by the host.
local frontImg,shownImg={}, {}
b1.speciesSprite=function(_,species,isPlayer) ok(species==25 and isPlayer==false,"front sprite of the battler") return frontImg end
b1.picImage=function(_,img) return img==frontImg and shownImg or img end
local s1=a1:frontSprite(mon)
ok(s1 and s1.image==shownImg,"Gen 1: speciesSprite front, coloured through picImage")
local g2img={}
screen.pic=function(_,m,back) ok(m==g2mon and back==false,"Gen 2 front pic") return g2img,false end
package.loaded["src.world.gen2.Palettes"]={monColors=function() return {{255,255,255},{0,0,0}} end}
local used
package.loaded["src.render.GbcPalette"]={available=function() return true end,with=function(c,fn) used=c fn() end,mode="gbc"}
screen.palettes={}
local s2=a2:frontSprite(g2mon)
ok(s2 and s2.image==g2img and type(s2.draw)=="function","Gen 2: pic with a palette draw")
local drew; s2.draw(function() drew=true end)
ok(drew and used,"Gen 2 sprite drawn through GbcPalette.with")
ok(a2:panels().player.mon==g2mon,"panels carry the battler for its sprite")

-- Normal battle scene: the prompt box under the menus.
b1.phase="menu"; game1.stack.states={b1}
BattleUI.adapterFor(game1)
local cmd=BattleUI.menuContext()
ok(BattleUI.prompt(a1,cmd)[1]=="What will PIKACHU do?","command prompt names the active Pokemon")
b1.phase="moveSelect"
ok(BattleUI.prompt(a1,BattleUI.menuContext())[1]=="Which move will PIKACHU use?","move prompt")
game1.stack.states={b1,party}
ok(BattleUI.prompt(a1,BattleUI.menuContext())[1]=="Choose a POK\195\169MON.","switch prompt")
local itemParty=setmetatable({battle=b1,party={mon,mon},index=1,itemUse=true,
  bottomMessage=function() return "Use item on which\nPOK\195\169MON?" end},PartyMenu)
game1.stack.states={b1,itemParty}
local itemCtx=BattleUI.menuContext()
ok(itemCtx and itemCtx.kind=="switch" and BattleUI.hidesState(itemParty),"item use: Stadium cards, host list hidden")
local itemLines=BattleUI.prompt(a1,itemCtx)
ok(itemLines[1]=="Use item on which" and itemLines[2]=="POK\195\169MON?","item use shows the host's own prompt")
ok(a1:partyItemUse(itemParty)==true and a1:partyItemUse(party)==false,"item use is told apart from a switch")
itemParty.tmhm=true
ok((BattleUI.menuContext() or {}).kind~="switch","TM/HM keeps the host's ABLE list")
local Gen2Host=require("mods.STADIUM2_UI.lib.host_gen2")
ok(Gen2Host.partyPrompt(nil,{prompt="Use on which <PK><MN>?"})=="Use on which POK\195\169MON?","Gen 2 prompt spells out <PK><MN>")
game1.stack.states={b1,choice}; b1.phase="messages"
b1.visibleText=function() return {"Will you switch","POKeMON?"} end
ok(BattleUI.prompt(a1,BattleUI.menuContext())[1]=="Will you switch","YES/NO shows its question")
game1.stack.states={b1}
screen.phase="menu"; screen.contest=nil; BattleUI.adapterFor(game2)
ok(BattleUI.prompt(a2,{kind="command"})[1]=="What will CYNDAQUIL do?","Gen 2 prompt uses the host's name")

local fullColumn
-- Any screen: nothing overlaps and nothing leaves the screen, for every
-- menu, the message layout, the engine scene's prompt box and a refusal box.
local function inside(r,area) return r.x>=area.x-0.5 and r.y>=area.y-0.5
  and r.x+r.w<=area.x+area.w+0.5 and r.y+r.h<=area.y+area.h+0.5 end
local sizes={{320,240},{480,432},{640,480},{800,600},{1024,768},{1280,720},{1366,768},
  {1920,1080},{2560,1080},{3440,1440},{5120,1440},{1024,1024},{1080,972},{720,648}}
for _,size in ipairs(sizes) do
  local W,H=size[1],size[2]
  local area={x=0,y=0,w=W,h=H}
  local sc=math.min(H/144,W/160); local gw,gh=160*sc,144*sc
  local vp={width=W,height=H,gameX=(W-gw)/2,gameY=(H-gh)/2,gameWidth=gw,gameHeight=gh}
  local place=UI.placement(area); local k=place.scale
  local player={x=place.left+21*k,y=place.top+15*k,w=75*k,h=UI.PLAYER_COLUMN_H*k}
  local label=W.."x"..H
  local scenarios={
    {menu="command"},{menu="moves"},{menu="info"},{menu="yesno"},
    {menu="switch",rows=1},{menu="switch",rows=2},
    {menu="switch",rows=2,refusal=true},{menu="command",engine=true},
    {menu="yesno",engine=true},{menu="moves",engine=true},{menu="switch",rows=1,engine=true},
    {menu="switch",rows=2,engine=true},{menu="pack",refusal=true},{menu="pack",engine=true},
    {menu="stats",engine=true},{menu="stats",refusal=true},
    {message=true},{message=true,engine=true}}
  for _,sc2 in ipairs(scenarios) do
    local name=label.." "..(sc2.menu or "message")..(sc2.rows==2 and "x2" or "")..(sc2.engine and " engine" or "")..(sc2.refusal and " refusal" or "")
    local rects={}
    local box
    if sc2.engine then box=BattleUI.engineMessageRect(area,vp)
    elseif sc2.message or sc2.refusal then box=UI.messageRect(area) end
    if sc2.message then
      -- message layout: both cards on the top row, box at the bottom
      rects.player={x=place.left+21*k,y=place.top+15*k,w=75*k,h=69*k}
      rects.enemy={x=place.right+228*k,y=place.top+15*k,w=75*k,h=69*k}
    else
      rects.player=player
      rects.menu=BattleUI.menuRect(area,sc2.menu,sc2.rows)
      local dy,compact=BattleUI.enemyOffset(area,sc2.menu,sc2.rows,box)
      if dy then rects.enemy=UI.enemyColumnRect(area,dy,compact) end
      if dy and not compact and not box then fullColumn=(fullColumn or 0)+1 end
    end
    rects.box=box
    for n,r in pairs(rects) do ok(inside(r,area),name..": "..n.." stays on screen") end
    local names={} for n in pairs(rects) do names[#names+1]=n end
    for a=1,#names do for b=a+1,#names do
      ok(not BattleUI.overlaps(rects[names[a]],rects[names[b]]),name..": "..names[a].." and "..names[b].." do not overlap")
    end end
    if sc2.engine and box then ok(box.y>=vp.gameY+96*(gh/144),name..": engine box under the sprite box") end
    -- the card itself is only ever hidden when a two-row switch screen and
    -- a box leave no gap
    if not sc2.message and not (sc2.rows==2 and box) then
      ok(rects.enemy~=nil,name..": opponent's card has room")
    end
  end
end

-- Modded scene: any mod's replacement of the battle's drawing functions;
-- the importer's patches only while its 3D scene is active.
local function fnFrom(source) return assert(loadstring("return function() end", source))() end
local hostState={draw=fnFrom("@src/battle/BattleState.lua"),drawPicsLayer=fnFrom("@src/battle/BattleState.lua")}
local importerScene=nil
BattleUI.bind({find=function(_,id) if id=="STADIUM2_IMPORTER" then
  return {exports={getActiveBattleScene=function() return importerScene end}} end end},
  function() return enabled end,function() end)
ok(not BattleUI.sceneModded(hostState),"the host's own scene is the engine scene")
local voxel={draw=hostState.draw,drawPicsLayer=fnFrom("@mods/BATTLE_ART_VOXEL_FORK/lib/scene.lua")}
ok(BattleUI.sceneModded(voxel),"another mod's battle drawing is a modded scene")
local uiMod={draw=fnFrom("@mods/gen1_modern_ui/lib/battle.lua"),drawHUDs=fnFrom("@mods/gen1_modern_ui/lib/hud.lua"),
  drawPicsLayer=hostState.drawPicsLayer}
ok(not BattleUI.sceneModded(uiMod),"a UI mod patching draw/drawHUDs keeps the engine scene")
local patched={draw=hostState.draw,drawPicsLayer=fnFrom("@mods/STADIUM2_IMPORTER/lib/gen1_battle.lua")}
ok(not BattleUI.sceneModded(patched),"importer patches with its 3D scene off: engine scene")
importerScene={}
ok(BattleUI.sceneModded(patched) and BattleUI.sceneModded(hostState),"importer 3D scene active: modded scene")
importerScene=nil
-- The wide layout's battlefield ends at row 104.
local wideVp={width=1920,height=1080,gameX=(1920-304*7.5)/2,gameY=0,gameWidth=304*7.5,gameHeight=1080}
local wr=BattleUI.engineMessageRect({x=0,y=0,w=1920,h=1080},wideVp,BattleUI.WIDE_SPRITE_BOTTOM)
ok(wr and wr.y>=104*7.5 and math.abs(wr.x+wr.w/2-960)<1,"wide layout: under row 104, centred")

-- The module cache guard evicts a previous build's modules.
local Guard=require("mods.STADIUM2_UI.lib.cache_guard")
package.loaded["mods.STADIUM2_UI.__build"]="0.0.1"
package.loaded["mods.STADIUM2_UI.lib.stale_example"]={}
ok(Guard.refresh("9.9.9")==true and package.loaded["mods.STADIUM2_UI.lib.stale_example"]==nil,"old build: modules evicted")
ok(Guard.refresh("9.9.9")==false,"same build: cache kept")
ok(not io.open("mods/STADIUM2_UI/main.lua"):read("*a"):find("package.loaded",1,true),
  "main.lua (sandboxed) leaves package.loaded to the guard")

-- Default engine scene: each sprite box moves just far enough to clear the
-- open menu, the cards and the box; small sprites move less; nothing moves
-- when nothing is in the way.
for _,size in ipairs(sizes) do
  local W,H=size[1],size[2]
  local area={x=0,y=0,w=W,h=H}
  local sc=math.min(H/144,W/160); local gw,gh=160*sc,144*sc
  local vp={width=W,height=H,gameX=(W-gw)/2,gameY=(H-gh)/2,gameWidth=gw,gameHeight=gh}
  local game={x=vp.gameX,y=vp.gameY,s=sc}
  local place=UI.placement(area); local k=place.scale
  local label=W.."x"..H.." sprites"
  for _,kind in ipairs({"command","moves","info","yesno","switch"}) do
    local obstacles={menu=BattleUI.menuRect(area,kind,1),
      player={x=place.left+21*k,y=place.top+15*k,w=75*k,h=UI.PLAYER_COLUMN_H*k}}
    local e,p,eClear,pClear=BattleUI.spriteMoves(game,obstacles,0)
    ok(e[2]>=0 and e[2]<=40 and e[1]<=8 and e[1]>=-40,label.." "..kind..": opponent moves down/sideways within limits")
    ok(game.x+(96+e[1]+56)*sc<=game.x+160*sc+0.5,label.." "..kind..": opponent stays on the Game Boy screen")
    local er={x=game.x+(96+e[1])*sc,y=game.y+e[2]*sc,w=56*sc,h=56*sc}
    local pr={x=game.x+(8+p[1])*sc,y=game.y+(40+p[2])*sc,w=56*sc,h=56*sc}
    if eClear then
      for n,o in pairs(obstacles) do ok(not BattleUI.overlaps(er,o),label.." "..kind..": opponent clear of "..n) end
      -- a sprite with 20 blank rows at the top needs to move no further
      local e2,_,e2Clear=BattleUI.spriteMoves(game,obstacles,20)
      ok(e2Clear and e2[1]*e2[1]+e2[2]*e2[2]<=e[1]*e[1]+e[2]*e[2],label.." "..kind..": a shorter sprite moves no further")
    end
    if pClear then
      for n,o in pairs(obstacles) do ok(not BattleUI.overlaps(pr,o),label.." "..kind..": player clear of "..n) end
    end
    if W>=H and W>=480 then
      -- with the prompt box stepped aside the opponent may go lower: every
      -- landscape screen then has a clear place
      local e3,p3,e3Clear,p3Clear=BattleUI.spriteMoves(game,obstacles,0,true)
      ok(e3Clear and p3Clear,label.." "..kind..": clear once the prompt steps aside")
      local e3r={x=game.x+(96+e3[1])*sc,y=game.y+e3[2]*sc,w=56*sc,h=56*sc}
      ok(e3r.y+e3r.h<=game.y+144*sc+0.5,label.." "..kind..": still on the Game Boy screen")
      ok(game.y+(40+p3[2]+56)*sc<=game.y+144*sc+0.5,label.." "..kind..": player's box still on the screen")
    end
  end
  local e0,p0=BattleUI.spriteMoves(game,{},0)
  ok(e0[1]==0 and e0[2]==0 and p0[1]==0 and p0[2]==0,label..": nothing in the way, nothing moves")
end
-- Gen 1's real boxes (the 2x back pic reaches x 0..72, rows 32..96): a
-- moved box never leaves part of the sprite behind or touches the UI.
do
  local Gen1=require("mods.STADIUM2_UI.lib.host_gen1")
  for _,size in ipairs(sizes) do
    local W,H=size[1],size[2]
    local area={x=0,y=0,w=W,h=H}
    local sc=math.min(H/144,W/160)
    local game={x=(W-160*sc)/2,y=(H-144*sc)/2,s=sc,enemyBox=Gen1.SPRITE_BOXES.enemy,playerBox=Gen1.SPRITE_BOXES.player}
    local place=UI.placement(area); local k=place.scale
    for _,kind in ipairs({"command","moves"}) do
      local obstacles={menu=BattleUI.menuRect(area,kind,1),player={x=place.left+21*k,y=place.top+15*k,w=75*k,h=UI.PLAYER_COLUMN_H*k}}
      local e,p,ec,pc=BattleUI.spriteMoves(game,obstacles,0)
      local pb=game.playerBox
      local pr={x=game.x+(pb[1]+p[1])*sc,y=game.y+(pb[2]+p[2])*sc,w=pb[3]*sc,h=pb[4]*sc}
      if pc then for n,o in pairs(obstacles) do ok(not BattleUI.overlaps(pr,o),W.."x"..H.." gen1 "..kind..": player's whole back pic clear of "..n) end end
      ok(pr.x>=game.x-0.5 and pr.x+pr.w<=game.x+160*sc+0.5,W.."x"..H.." gen1 "..kind..": back pic stays on the Game Boy screen")
    end
  end
end

do -- 16:9: the command bar alone moves the opponent a little, not to the bottom
  local sc=7.5; local game={x=(1920-1200)/2,y=0,s=sc}
  local e=BattleUI.spriteMoves(game,{menu=BattleUI.menuRect({x=0,y=0,w=1920,h=1080},"command",1)},0)
  ok(e[2]>0 and e[2]<=24,"1920x1080 command bar: the opponent moves down a little ("..e[1]..","..e[2]..")")
  print(("  16:9 command bar: opponent's box moves (%d, %d) Game Boy pixels"):format(e[1],e[2]))
  local d=BattleUI.spriteMoves(game,{menu=BattleUI.menuRect({x=0,y=0,w=1920,h=1080},"moves",1)},0)
  print(("  16:9 move diamond: opponent's box moves (%d, %d)"):format(d[1],d[2]))
end

do -- the move diamond and party cards may cover the sprites; the command bar may not
  ok(BattleUI.MENUS_OVER_SPRITES.moves and BattleUI.MENUS_OVER_SPRITES.switch,"moves and party menus may cover the sprites")
  ok(not BattleUI.MENUS_OVER_SPRITES.command and not BattleUI.MENUS_OVER_SPRITES.yesno,"command bar and YES/NO still push them")
  local sc=7.5; local game={x=(1920-1200)/2,y=0,s=sc}
  local area={x=0,y=0,w=1920,h=1080}
  local held=BattleUI.spriteMoves(game,{menu=BattleUI.menuRect(area,"command",1)},0)
  ok(BattleUI.movesClear(game,{},0,held,{0,0}),"with no obstacles a held place stays clear")
  ok(not BattleUI.movesClear(game,{menu=BattleUI.menuRect(area,"moves",1)},0,{0,0},{0,0}),
    "the move diamond does cover the unmoved opponent (so holding matters)")
  ok(BattleUI.movesClear(game,{menu=BattleUI.menuRect(area,"command",1)},0,held,{0,0}),"the command bar's place is clear of it")
end

-- main.lua --------------------------------------------------------------
local manifest=io.open("mods/STADIUM2_UI/manifest.json"):read("*a")
local main=io.open("mods/STADIUM2_UI/main.lua"):read("*a")
ok(main:find('local MOD_BUILD = "'..manifest:match('"version": "([^"]+)"')..'"',1,true),"build stamp matches the manifest")
ok(not manifest:find("required_imports",1,true),"no ROM import required")
package.loaded["mods.STADIUM2_UI.__build"]=manifest:match('"version": "([^"]+)"')
local wrapped,events={}, {}
local mod={options={define=function() end,get=function() return nil end},
  hooks={wrap=function(_,name) wrapped[name]=true end},events={on=function(_,name) events[name]=true end},
  log={warn=function() end}}
assert(loadfile("mods/STADIUM2_UI/main.lua"))()(mod)
for _,name in ipairs({"battle.status_hud_visible","battle.bottom_ui_visible","screen.render_visible","render.hud","input.step","input.pointer"}) do
  ok(wrapped[name],"hooks "..name)
end
ok(not wrapped["input.gamepad"],"input.gamepad waits for the first Stadium menu")
ok(events["battle.ended"],"releases on battle end")

-- Embedded (STADIUM2_IMPORTER's ui/ submodule): every module loads under the
-- embedding mod's root, never back under mods.STADIUM2_UI.
do
  local root="mods.EMBEDDER.ui"
  local libDir="mods/STADIUM2_UI/lib/"
  local names={}
  for line in io.popen('ls '..libDir):lines() do
    local n=line:match("^(.-)%.lua$")
    if n then names[#names+1]=n end
  end
  for _,n in ipairs(names) do
    package.preload[root..".lib."..n]=function(name) return assert(loadfile(libDir..n..".lua"))(name) end
  end
  local before={}
  for k in pairs(package.loaded) do before[k]=true end
  local Embed=require(root..".lib.embed")
  ok(Embed.ROOT==root,"embedded: the module root comes from the module name")
  ok(Embed.BattleUI~=BattleUI,"embedded: its own UI state, apart from a standalone copy")
  local strays={}
  for k in pairs(package.loaded) do
    if not before[k] and type(k)=="string" and k:find("STADIUM2_UI",1,true) then strays[#strays+1]=k end
  end
  ok(#strays==0,"embedded: nothing loads under mods.STADIUM2_UI ("..table.concat(strays,",")..")")
  local ewrapped={}
  local emod={hooks={wrap=function(_,name) ewrapped[name]=true end},events={on=function() end},
    assets={path=function(_,p) return "PATH:"..p end}}
  local enabledNow=false
  Embed.install(emod,{embedded=true,assetBase="ui/",enabled=function() return enabledNow end})
  ok(ewrapped["render.hud"] and ewrapped["battle.bottom_ui_visible"],"embedded: installs the same hooks")
  ok(Embed.BattleUI.embedded==true and Embed.BattleUI.importerOwnsUi()==false,"embedded: never defers to its host mod")
end

print(("%d checks passed (Stadium UI host integration)"):format(checks))
