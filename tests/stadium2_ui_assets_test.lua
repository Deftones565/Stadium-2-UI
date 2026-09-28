package.path="./?.lua;./?/init.lua;"..package.path
-- The painted UI art (no ROM): every texture the layout draws exists at the
-- game's sizes, the fonts cover the battle text, and nothing reads a ROM.
local Assets=require("mods.STADIUM2_UI.lib.stadium_ui_assets")
local Font=require("mods.STADIUM2_UI.lib.pixel_font")
local checks=0
local function ok(v,m) checks=checks+1 if not v then error("FAIL "..m,0) end end

local a=Assets.load()
local function has(file,entry,w,h)
  local e=a.sets[file] and a.sets[file][entry]
  ok(e and e.w>=w and e.h>=h,("set %d #%d is at least %dx%d"):format(file,entry,w,h))
  if e and e.rgba then ok(#e.rgba==e.w*e.h*4,("set %d #%d pixel data"):format(file,entry)) end
end
has(31,0,64,1); has(33,3,16,4); has(33,0,64,14); has(33,1,94,17)
has(32,0,48,10); has(32,2,16,12); has(32,3,32,8); has(32,4,32,8); has(32,5,16,6)
has(32,6,16,7); has(32,7,112,9); has(32,8,48,10); has(34,0,8,8); has(34,1,8,8)
for i=0,6 do has(35,i,32,9) end
for i=0,17 do has(36,i,32,9) end
for i=0,8 do ok(a.sets[30][i]~=nil,"N64 button icon "..i) end
ok(a.sets[31][0].rgba:byte(4)==204,"card strip is 0.8 alpha")
-- Fonts cover the battle text.
for _,text in ipairs({"PIKACHU's THUNDERBOLT!","What will CYNDAQUIL do?","POK\233MON 0123456789/-.,:"}) do
  for i=1,#text do
    ok(Assets.glyphFor(a.font,text:byte(i))~=nil,("big font has %q"):format(text:sub(i,i)))
    ok(Assets.glyphFor(a.small,text:byte(i))~=nil,("small font has %q"):format(text:sub(i,i)))
  end
end
ok(a.font.male and a.font.female,"gender marks")
local A=Assets.glyphFor(a.font,65)
ok(Assets.advance(a.font,A)==Font.width(Font.glyphs.A)+1,"advance = ink width + 1")
ok(#a.font.glyphs[A]==Assets.GLYPH_W*Assets.GLYPH_H*4,"16x12 glyph cells")
-- No ROM: the module never touches a ROM or the importer's files.
local src=io.open("mods/STADIUM2_UI/lib/stadium_ui_assets.lua"):read("*a")
ok(not src:find("baseroms",1,true) and not src:find("Rom.",1,true),"no ROM access in the art module")
print(("%d checks passed (painted UI art)"):format(checks))
