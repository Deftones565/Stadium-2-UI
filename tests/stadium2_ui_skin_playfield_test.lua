package.path="./?.lua;./?/init.lua;"..package.path
-- Touch skins. With a skin (Options > touch controls > skin; RetroArch and
-- Delta overlays) the game draws only inside the skin's screen cutout
-- (src/render/Playfield.lua), which render.hud's viewport reports as
-- viewX/viewY/viewWidth/viewHeight, and TouchControls:drawSkin paints the
-- skin's console-shell art over the rest of the window after render.hud.
-- A HUD laid out on the whole window lands under that art: the player sees
-- no HUD at all (the host's own boxes are switched off for the Stadium UI).
-- The layout must stay inside the cutout.
local BattleUI=require("mods.STADIUM2_UI.lib.battle_ui")
local UI=require("mods.STADIUM2_UI.lib.stadium_ui")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end
local function inside(a,r)
  return a.x>=r.x-1e-6 and a.y>=r.y-1e-6 and a.x+a.w<=r.x+r.w+1e-6 and a.y+a.h<=r.y+r.h+1e-6
end
local function show(a) return ("%g,%g %gx%g"):format(a.x,a.y,a.w,a.h) end

-- No skin: Gen 1's viewport reports the whole window as the view.
local plain={width=2400,height=1080,gameX=840,gameY=108,gameWidth=720,gameHeight=648,
  viewX=0,viewY=0,viewWidth=2400,viewHeight=1080}
local a=BattleUI.layoutArea(plain)
ok(a.x==0 and a.y==0 and a.w==2400 and a.h==1080,"no skin: the whole window ("..show(a)..")")
-- Gen 2's viewport has no view fields.
a=BattleUI.layoutArea({width=2400,height=1080,gameX=840,gameY=108,gameWidth=720,gameHeight=648})
ok(a.w==2400 and a.h==1080,"Gen 2 viewport: the whole window")

-- Landscape skin: a console shell with the screen hole in the middle.
local cut={x=600,y=90,w=1200,h=720}
local skinned={width=2400,height=1080,gameX=640,gameY=90,gameWidth=800,gameHeight=720,
  viewX=cut.x,viewY=cut.y,viewWidth=cut.w,viewHeight=cut.h}
a=BattleUI.layoutArea(skinned)
ok(inside(a,cut),"landscape skin: the HUD is laid out inside the screen cutout ("..show(a)..")")
local p=UI.placement(a)
ok(p.left>=cut.x-1e-6 and p.top>=cut.y-1e-6,"Stadium's layout starts inside the cutout")
ok(p.right+UI.PANEL.enemy.x*p.scale<=cut.x+cut.w+1e-6,"and its right column ends inside it")

-- Portrait skin: the screen hole in the upper half, the pad art below.
cut={x=0,y=180,w=1080,h=972}
skinned={width=1080,height=2400,gameX=0,gameY=180,gameWidth=1080,gameHeight=972,
  viewX=cut.x,viewY=cut.y,viewWidth=cut.w,viewHeight=cut.h}
a=BattleUI.layoutArea(skinned)
ok(inside(a,cut),"portrait skin: the HUD stays out of the pad art ("..show(a)..")")

print(checks.." checks passed (Stadium UI inside a touch skin's screen)")
