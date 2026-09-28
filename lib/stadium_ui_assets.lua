-- The Stadium UI's art, painted in code at load (no ROM, no image files):
-- card strip, bracket frame, command and move tabs, HP bar, digits,
-- labels, status tags, type labels, party balls, D-pad, the N64 button
-- icons and the fonts. Same texture sets, sizes and entries as the game's
-- UI archive files 30..36 so the layout code draws them unchanged; the
-- shapes and shading follow the game's look but are this mod's own art.
--
-- UI DETAIL = HD enlarges every texture 4x with edge-restoring
-- interpolation and draws it filtered; N64 PIXELS keeps the 1x pixels.
-- This mod's module root ("mods.STADIUM2_UI", or wherever it is embedded,
-- e.g. STADIUM2_IMPORTER's ui/ submodule): taken from this module's name.
local ROOT = (...):match("^(.*)%.lib%.[^%.]+$") or "mods.STADIUM2_UI"
local Font = require(ROOT .. ".lib.pixel_font")

local Assets = {}

Assets.GLYPH_W, Assets.GLYPH_H = 16, 12
Assets.SMALL_GLYPH_H = 10
Assets.HD_SCALE = 4
Assets.HD_EDGE = 0.12

local floor, min, max, char, byte = math.floor, math.min, math.max, string.char, string.byte

-- ---------------------------------------------------------------- painting
local Pix = {}
Pix.__index = Pix

local function newPix(w, h)
  return setmetatable({ w = w, h = h, px = {} }, Pix)
end

-- Grey value v (or colour r, g, b in 0..255) with alpha a.
function Pix:set(x, y, v, a, r, g, b)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
  v = floor(max(0, min(1, v)) * 255 + 0.5)
  self.px[y * self.w + x + 1] = { r or v, g or v, b or v, floor((a or 1) * 255 + 0.5) }
end

function Pix:get(x, y)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return nil end
  return self.px[y * self.w + x + 1]
end

function Pix:rgba()
  local out = {}
  for i = 1, self.w * self.h do
    local p = self.px[i]
    out[i] = p and char(p[1], p[2], p[3], p[4]) or "\0\0\0\0"
  end
  return table.concat(out)
end

local INK, OUTLINE = 1, 0.07
local SHADOW_A = 0.55

-- Stamp glyph rows with ink at (x, y) (top of the 7-row body).
local function stamp(p, rows, x, y, v)
  for ry, row in ipairs(rows) do
    for rx = 1, #row do
      if row:sub(rx, rx) == "#" then p:set(x + rx - 1, y + ry - 1, v or INK) end
    end
  end
end

-- A dark 1 px outline around all bright ink (8-neighbourhood).
local function outline(p)
  local marks = {}
  for y = 0, p.h - 1 do
    for x = 0, p.w - 1 do
      if not p:get(x, y) then
        local near = false
        for dy = -1, 1 do
          for dx = -1, 1 do
            local q = p:get(x + dx, y + dy)
            if q and q[4] > 200 and (q[1] + q[2] + q[3]) > 300 then near = true end
          end
        end
        if near then marks[#marks + 1] = { x, y } end
      end
    end
  end
  for _, m in ipairs(marks) do p:set(m[1], m[2], OUTLINE) end
end

local function textWidth(text, gap)
  local w = 0
  for i = 1, #text do
    local rows = Font.rows(text:byte(i))
    if rows then w = w + Font.width(rows) + gap end
  end
  return max(0, w - gap)
end

-- Outlined text label (1 px between letters, packed if it would not fit).
local function label(text, w, h, align, gap)
  gap = gap or 1
  -- pack the letters when the spaced label would overflow its slot
  if textWidth(text, gap) + 2 > w then gap = 0 end
  local tw = textWidth(text, gap)
  w = max(w, tw + 2)
  local p = newPix(w, h)
  local x = align == "center" and floor((w - tw) / 2) or 1
  for i = 1, #text do
    local rows = Font.rows(text:byte(i))
    if rows then
      stamp(p, rows, x, 1)
      x = x + Font.width(rows) + gap
    end
  end
  outline(p)
  return p
end

-- A piecewise curve through {t, value} keys, smoothstepped between keys.
local function curve(keys, t)
  for i = 1, #keys - 1 do
    local a, b = keys[i], keys[i + 1]
    if t >= a[1] and t <= b[1] then
      local u = (t - a[1]) / (b[1] - a[1])
      u = u * u * (3 - 2 * u)
      return a[2] + (b[2] - a[2]) * u
    end
  end
  return keys[#keys][2]
end

-- ------------------------------------------------------------------ pieces
-- 64x1 card strip (stretched over each card and tinted): light at a third,
-- darkest near the right, lifting at the edge; alpha 0.8.
local function strip()
  local p = newPix(64, 1)
  local keys = { { 0, 0.45 }, { 0.30, 0.83 }, { 0.86, 0.36 }, { 1, 0.62 } }
  for x = 0, 63 do p:set(x, 0, curve(keys, x / 63), 0.8) end
  return p
end

-- 16x4 bracket frame pieces (see UI.card): cols 0-3 top-left / left edge,
-- 4-7 top edge / top-right, 8-11 bottom-left / bottom edge, 12-15
-- bottom-right / right edge. Black outline, light top-left bevel, dark
-- bottom-right bevel and a translucent drop shadow.
local function frame()
  local p = newPix(16, 4)
  local function s(x, y, v, a) p:set(x, y, v, a) end
  s(2, 2, 0); s(3, 2, 0); s(2, 3, 0); s(3, 3, 1)
  s(4, 2, 0); s(5, 2, 0); s(6, 2, 0); s(4, 3, 1); s(5, 3, 0.8); s(6, 3, 0)
  s(9, 0, 0); s(10, 0, 0.8); s(11, 0, 0.4)
  s(9, 1, 0); s(10, 1, 0); s(11, 1, 0)
  s(11, 2, 0, SHADOW_A); s(11, 3, 0, SHADOW_A)
  s(12, 0, 0.4); s(13, 0, 0); s(14, 0, 0, SHADOW_A); s(15, 0, 0, SHADOW_A)
  s(12, 1, 0); s(13, 1, 0); s(14, 1, 0, SHADOW_A); s(15, 1, 0, SHADOW_A)
  for x = 12, 15 do s(x, 2, 0, SHADOW_A); s(x, 3, 0, SHADOW_A) end
  return p
end

-- A slanted tab: outlined parallelogram, light top line and left bevel,
-- horizontal gradient, dark bottom line and a drop shadow.
local function tab(w, h, keys)
  local p = newPix(w, h)
  local body, slant = h - 3, 3
  local function span(y)
    local off = floor(slant * (1 - y / (body - 1)) + 0.5)
    return off, w - 3 - (slant - off)
  end
  for y = 0, body - 1 do
    local x0, x1 = span(y)
    for x = x0 + 2, x1 + 2 do p:set(x, y + 2, 0, SHADOW_A) end
  end
  for y = 0, body - 1 do
    local x0, x1 = span(y)
    for x = x0, x1 do
      local v
      if y == 0 or y == body - 1 or x == x0 or x == x1 then v = 0
      elseif y == 1 or x <= x0 + 1 then v = 1
      elseif y == body - 2 then v = 0.4
      else v = curve(keys, (x - x0) / (x1 - x0)) end
      p:set(x, y, v)
    end
  end
  return p
end

-- HP bar (16x6, stretched and tinted): outline and a rounded bevel.
local function hpBar()
  local p = newPix(16, 6)
  local rows = { 0, 0.78, 1, 0.78, 0.45, 0 }
  for y = 0, 5 do
    for x = 0, 15 do
      if not ((y == 0 or y == 5) and x == 0) then p:set(x, y, x == 0 and 0 or rows[y + 1]) end
    end
  end
  return p
end

-- Digit strip (8x9 cells): 0-9, '/', 'L', '-'. Bold: every stroke is two
-- pixels wide, like the game's chunky HP and PP digits.
local function digits()
  local p = newPix(112, 9)
  local chars = "0123456789/L-"
  for i = 1, #chars do
    local rows = Font.rows(chars:byte(i))
    local x = (i - 1) * 8 + 1 + floor((5 - Font.width(rows)) / 2)
    stamp(p, rows, x, 1)
    stamp(p, rows, x + 1, 1)
  end
  outline(p)
  return p
end

-- "HP:" in small capitals (16x7).
local function hpLabel()
  local p = newPix(16, 7)
  stamp(p, { "#.#.##..", "#.#.#.#.", "###.##.#", "#.#.#...", "#.#.#..#" }, 1, 1)
  outline(p)
  return p
end

-- The D-pad cross (16x12): outlined, lit upper-left, drop shadow.
local function dpad()
  local p = newPix(16, 12)
  local function inCross(x, y)
    return (x >= 4 and x <= 6 and y >= 1 and y <= 9) or (y >= 4 and y <= 6 and x >= 1 and x <= 9)
  end
  for y = 0, 11 do
    for x = 0, 15 do
      if inCross(x - 1, y - 1) and not inCross(x, y) then p:set(x, y, 0, SHADOW_A) end
    end
  end
  for y = 0, 11 do
    for x = 0, 15 do
      if inCross(x, y) then
        local edge = not (inCross(x - 1, y) and inCross(x + 1, y) and inCross(x, y - 1) and inCross(x, y + 1))
        p:set(x, y, edge and 0 or ((x <= 5 and y <= 5) and 1 or 0.72))
      end
    end
  end
  return p
end

-- Party balls (8x8): a Poke Ball, and the fainted cross.
local function ball()
  local p = newPix(8, 8)
  local shape = { ".####.", "#rrrr#", "#rWrr#", "#kkkk#", "#wwww#", ".####." }
  for y, row in ipairs(shape) do
    for x = 1, #row do
      if row:sub(x, x) ~= "." then p:set(x, y, 0, SHADOW_A) end
    end
  end
  for y, row in ipairs(shape) do
    for x = 1, #row do
      local c, px, py = row:sub(x, x), x - 1, y - 1
      if c == "#" or c == "k" then p:set(px, py, 0.08)
      elseif c == "r" then p:set(px, py, 0, 1, 225, 40, 40)
      elseif c == "W" then p:set(px, py, 0, 1, 255, 190, 190)
      elseif c == "w" then p:set(px, py, 0.95) end
    end
  end
  return p
end

local function fainted()
  local p = newPix(8, 8)
  stamp(p, { "#...#", ".#.#.", "..#..", ".#.#.", "#...#" }, 1, 1)
  for i, v in pairs(p.px) do if v then p.px[i] = { 255, 230, 0, 255 } end end
  outline(p)
  return p
end

-- ------------------------------------------------------------------ fonts
local function fontSet(glyphH, withOutline)
  local order = { 32 }
  for c = 33, 126 do order[#order + 1] = c end
  order[#order + 1] = 0xE9
  order[#order + 1] = Font.MALE:byte()
  order[#order + 1] = Font.FEMALE:byte()
  local font = { map = {}, widths = {}, glyphs = {}, glyphH = glyphH, count = 0 }
  for index, code in ipairs(order) do
    local rows = Font.rows(code)
    if rows then
      local p = newPix(Assets.GLYPH_W, glyphH)
      stamp(p, rows, 1, withOutline and 2 or 1)
      if withOutline then outline(p) end
      font.map[code] = index
      font.glyphs[index] = p:rgba()
      -- advance = ink width + 1 (big font: width - 2; small font: width - 1)
      font.widths[index] = Font.width(rows) + (withOutline and 3 or 2)
      font.count = font.count + 1
    end
  end
  font.male, font.female = font.map[Font.MALE:byte()], font.map[Font.FEMALE:byte()]
  return font
end

function Assets.glyphFor(font, code)
  return font and font.map[code] or nil
end

-- Pen advance of a big-font glyph (width - 2, as the layout expects).
function Assets.advance(font, glyph)
  return (font.widths[glyph] or 7) - 2
end

-- ------------------------------------------------------------------ build
local TYPE_NAMES = { [0] = "Bug", "Dragon", "Electric", "???", "Dark", "Fighting", "Fire",
  "Flying", "Ghost", "Grass", "Ground", "Ice", "Normal", "Poison", "Psychic", "Rock",
  "Steel", "Water" }
local STATUS_NAMES = { [0] = "Bn", "Ft", "Ic", "Nm", "Pz", "Pn", "Sp" }

local built
-- The painted pixel sets (RGBA strings), built once.
function Assets.load()
  if built then return built end
  local sets = { [30] = {}, [31] = {}, [32] = {}, [33] = {}, [34] = {}, [35] = {}, [36] = {} }
  local function put(file, entry, p) sets[file][entry] = { w = p.w, h = p.h, rgba = p:rgba() } end
  put(31, 0, strip())
  put(32, 0, label("ACCURACY", 48, 10))
  put(32, 2, dpad())
  put(32, 3, label("MOVE", 32, 9))
  put(32, 4, label("STATUS", 32, 9))
  put(32, 5, hpBar())
  put(32, 6, hpLabel())
  put(32, 7, digits())
  put(32, 8, label("POWER", 48, 10))
  put(33, 0, tab(64, 14, { { 0, 0.97 }, { 0.40, 1 }, { 0.62, 0.78 }, { 1, 0.36 } }))
  put(33, 1, tab(96, 18, { { 0, 0.66 }, { 0.22, 0.97 }, { 0.46, 0.9 }, { 1, 0.4 } }))
  put(33, 3, frame())
  put(34, 0, ball())
  put(34, 1, fainted())
  for i = 0, 6 do put(35, i, label(STATUS_NAMES[i], 32, 9)) end
  for i = 0, 17 do put(36, i, label(TYPE_NAMES[i], 32, 11, "center")) end
  -- file 30 (N64 button icons) is vector art, made in images()
  for i = 0, 8 do
    local key = i == 6 or i == 7
    sets[30][i] = { w = key and 24 or 16, h = key and 17 or 18 }
  end
  built = { sets = sets, font = fontSet(Assets.GLYPH_H, true), small = fontSet(Assets.SMALL_GLYPH_H, false) }
  return built
end

-- ------------------------------------------------------------------ detail
local detail = "hd"
function Assets.setDetail(value) detail = value == "native" and "native" or "hd" end
function Assets.detail() return detail end

local function sharpen(t)
  t = (t - 0.2) / 0.6
  if t <= 0 then return 0 elseif t >= 1 then return 1 end
  return t * t * (3 - 2 * t)
end

-- 4x enlargement: bilinear interpolation of premultiplied RGBA, re-sharpened
-- where the four source texels differ strongly (outlines); transparent
-- texels keep the nearby art's colour so filtering leaves no dark fringe.
function Assets.upscale(rgba, w, h, k)
  local R, G, B, A = {}, {}, {}, {}
  for i = 0, w * h - 1 do
    local r, g, b, a = byte(rgba, i * 4 + 1, i * 4 + 4)
    a = a / 255
    R[i], G[i], B[i], A[i] = r / 255 * a, g / 255 * a, b / 255 * a, a
  end
  local edge = Assets.HD_EDGE
  local W, H = w * k, h * k
  local out = {}
  local function channel(C, i00, i10, i01, i11, fx, fy)
    local c00, c10, c01, c11 = C[i00], C[i10], C[i01], C[i11]
    local v = (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy
    local lo, hi = min(c00, c10, c01, c11), max(c00, c10, c01, c11)
    if hi - lo > edge then v = lo + (hi - lo) * sharpen((v - lo) / (hi - lo)) end
    return v
  end
  for oy = 0, H - 1 do
    local sy = (oy + 0.5) / k - 0.5
    local y0 = floor(sy)
    local fy = sy - y0
    local ya, yb = max(0, min(h - 1, y0)), max(0, min(h - 1, y0 + 1))
    for ox = 0, W - 1 do
      local sx = (ox + 0.5) / k - 0.5
      local x0 = floor(sx)
      local fx = sx - x0
      local xa, xb = max(0, min(w - 1, x0)), max(0, min(w - 1, x0 + 1))
      local i00, i10, i01, i11 = ya * w + xa, ya * w + xb, yb * w + xa, yb * w + xb
      local a = channel(A, i00, i10, i01, i11, fx, fy)
      local r, g, b = 0, 0, 0
      if a > 0.002 then
        r = channel(R, i00, i10, i01, i11, fx, fy) / a
        g = channel(G, i00, i10, i01, i11, fx, fy) / a
        b = channel(B, i00, i10, i01, i11, fx, fy) / a
      else
        local s = 0
        for dy = -1, 1 do
          local yy = max(0, min(h - 1, floor(sy + 0.5) + dy))
          for dx = -1, 1 do
            local xx = max(0, min(w - 1, floor(sx + 0.5) + dx))
            local i = yy * w + xx
            local ai = A[i]
            if ai > 0 then s = s + ai; r = r + R[i]; g = g + G[i]; b = b + B[i] end
          end
        end
        if s > 0 then r, g, b = r / s, g / s, b / s end
        a = 0
      end
      out[oy * W + ox + 1] = char(floor(min(1, r) * 255 + 0.5), floor(min(1, g) * 255 + 0.5),
        floor(min(1, b) * 255 + 0.5), floor(min(1, a) * 255 + 0.5))
    end
  end
  return table.concat(out), W, H
end

-- LOVE images for the painted art, built once per detail level.
local imagesBy = {}
function Assets.images()
  if imagesBy[detail] then return imagesBy[detail] end
  if not (love and love.image and love.graphics) then return nil, "LOVE graphics unavailable" end
  local assets = Assets.load()
  local k = detail == "hd" and Assets.HD_SCALE or 1
  local function image(w, h, rgba)
    if k > 1 then rgba = Assets.upscale(rgba, w, h, k) end
    local img = love.graphics.newImage(love.image.newImageData(w * k, h * k, "rgba8", rgba))
    if k > 1 then img:setFilter("linear", "linear") else img:setFilter("nearest", "nearest") end
    return img
  end
  local Buttons = require(ROOT .. ".lib.stadium_n64_buttons")
  local out = { sets = {}, glyphs = {}, smallGlyphs = {}, k = k }
  for file, set in pairs(assets.sets) do
    out.sets[file] = {}
    for i, e in pairs(set) do
      if file == 30 then
        local icon = Buttons.image(i, e.w, e.h)
        if icon then out.sets[file][i] = { image = icon, w = e.w, h = e.h, k = Buttons.SCALE } end
      else
        out.sets[file][i] = { image = image(e.w, e.h, e.rgba), w = e.w, h = e.h, k = k }
      end
    end
  end
  for i, rgba in pairs(assets.font.glyphs) do out.glyphs[i] = image(Assets.GLYPH_W, Assets.GLYPH_H, rgba) end
  for i, rgba in pairs(assets.small.glyphs) do out.smallGlyphs[i] = image(Assets.GLYPH_W, Assets.SMALL_GLYPH_H, rgba) end
  out.font, out.small = assets.font, assets.small
  imagesBy[detail] = out
  return out
end

-- Portrait camera records are Stadium 2 data: available only through
-- STADIUM2_IMPORTER (which has the ROM) when it is installed.
function Assets.portraitRecord(_, species, opponent)
  local Importer = package.loaded["mods.STADIUM2_IMPORTER.lib.stadium_portrait_data"]
    or package.loaded["mods.STADIUM2_IMPORTER.lib.stadium_ui_assets"]
  if type(Importer) ~= "table" or type(Importer.load) ~= "function" then return nil end
  local ok, loaded = pcall(Importer.load)
  if not (ok and loaded) then return nil end
  local okR, record = pcall(Importer.portraitRecord, loaded, species, opponent)
  return okR and record or nil
end

function Assets.release()
  imagesBy, built = {}, nil
end

return Assets
