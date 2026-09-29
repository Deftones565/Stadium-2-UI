-- The engine's full-screen battle effects, carried over to this UI in the
-- normal (2D) battle scene. PORT ADDITION, user-requested: not Stadium 2
-- behaviour. On the Game Boy an effect acts on every pixel of the LCD, the
-- status boxes and text box included; this UI stands in for those, so it
-- takes the same effect.
--
-- Nothing here knows any one effect. The host adapter describes the screen
-- the way the hardware sees it, and this applies that description:
--   lines[0..143] = { dx, dy, pal }  per scanline: X scroll (Game Boy px), the
--                   row offset it samples from, and the palette byte in force
--                   (DMG rBGP: colour i shows shade (pal >> 2i) & 3)
--   pal           = the palette byte outside the scanlines (UI above/below)
--   dx, dy        = whole-screen scroll (shakes)
--   veil          = { r, g, b, a } over every pixel (flashes, fades)
--   elements      = { enemyHud = dx }  one status box moving on its own
-- A 1x144 image carries the line table to one shader pass over a canvas the
-- UI is drawn into. With no effect in force begin() returns false and the UI
-- draws straight to the screen, as without this module.
local Effects = {}

Effects.IDENTITY = 0xe4 -- dc 3, 2, 1, 0

-- Positions are the canvas's own (uv * size, LOVE units), so the pass is the
-- same on any render target and DPI scale.
local SOURCE = [[
extern Image lineTable;      // 1x144: r = dx + 128, g = dy + 128, b = palette byte (/255)
extern vec4 game;            // Game Boy screen: x, y, pixel scale, 0 (units)
extern vec2 shift;           // whole-screen scroll, Game Boy px
extern float basePal;        // palette byte outside the scanlines
extern vec4 veil;
extern vec4 elementRect;     // x, y, w, h (units) of the moving element
extern float elementDx;      // its own scroll, Game Boy px
extern vec2 size;            // canvas size (units)

float shade(float pal, float i) { return mod(floor(pal / pow(4.0, i)), 4.0); }

vec4 effect(vec4 color, Image ui, vec2 uv, vec2 px) {
  vec2 p = uv * size;
  float row = floor((p.y - game.y) / game.z);
  vec2 d = shift;
  float pal = basePal;
  if (row >= 0.0 && row < 144.0) {
    vec4 t = Texel(lineTable, vec2(0.5, (row + 0.5) / 144.0));
    d += vec2(floor(t.r * 255.0 + 0.5) - 128.0, -(floor(t.g * 255.0 + 0.5) - 128.0));
    pal = floor(t.b * 255.0 + 0.5);
  }
  vec2 at = p - d * game.z;
  float ex = elementDx * game.z;
  if (at.x >= elementRect.x + ex && at.x < elementRect.x + elementRect.z + ex
      && at.y >= elementRect.y && at.y < elementRect.y + elementRect.w) {
    at.x -= ex;
  }
  vec4 c = Texel(ui, at / size);
  if (c.a <= 0.0) return vec4(0.0);
  vec3 rgb = c.rgb / c.a;
  // the palette acts on shade: 0 lightest .. 3 darkest, linear between
  float l = dot(rgb, vec3(0.299, 0.587, 0.114));
  float s = clamp((1.0 - l) * 3.0, 0.0, 3.0);
  float i = min(floor(s), 2.0);
  float mapped = mix(shade(pal, i), shade(pal, i + 1.0), s - i);
  rgb = clamp(rgb + ((1.0 - mapped / 3.0) - l), 0.0, 1.0);
  rgb = mix(rgb, veil.rgb, veil.a);
  return vec4(rgb * c.a, c.a) * color;
}
]]
Effects.SOURCE = SOURCE

local state = { canvas = nil, w = 0, h = 0, shader = nil, table = nil, data = nil, failed = false }
local active -- the frame being drawn through the effects

-- Whether a description changes anything at all.
function Effects.inForce(d)
  if type(d) ~= "table" then return false end
  if (d.dx or 0) ~= 0 or (d.dy or 0) ~= 0 then return true end
  if (d.pal or Effects.IDENTITY) ~= Effects.IDENTITY then return true end
  if d.veil and (d.veil[4] or 0) > 0 then return true end
  if d.elements and (d.elements.enemyHud or 0) ~= 0 then return true end
  if d.lines then
    for row = 0, 143 do
      local l = d.lines[row]
      if l and ((l.dx or 0) ~= 0 or (l.dy or 0) ~= 0
          or (l.pal and l.pal ~= Effects.IDENTITY)) then return true end
    end
  end
  return false
end

local function ensure(g, w, h)
  if state.failed then return false end
  local ok = pcall(function()
    if not state.shader then state.shader = g.newShader(SOURCE) end
    if not state.data then
      state.data = love.image.newImageData(1, 144)
      state.table = g.newImage(state.data)
      state.table:setFilter("nearest", "nearest")
    end
    if not state.canvas or state.w ~= w or state.h ~= h then
      if state.canvas then state.canvas:release() end
      -- the screen's own DPI: the UI keeps its full sharpness
      state.canvas = g.newCanvas(w, h, { format = "rgba8" })
      state.w, state.h = w, h
    end
  end)
  -- a device without the shader or canvas: the UI draws as before
  if not ok then state.failed = true end
  return ok
end

-- The size (units) of what render.hud draws on: the host's present canvas,
-- or the window.
local function targetSize(g, target)
  if type(target) == "userdata" and target.getDimensions then return target:getDimensions() end
  if type(target) == "table" and type(target[1]) == "userdata" then return target[1]:getDimensions() end
  return g.getDimensions()
end

-- Start drawing the UI through the description `d` (viewport = the frame's
-- metrics, for the Game Boy screen's place). false: nothing in force (or no
-- support) -- draw directly.
function Effects.begin(d, viewport, elementRect)
  active = nil
  if not Effects.inForce(d) then return false end
  local g = love and love.graphics
  if not (g and viewport) then return false end
  local previous = g.getCanvas()
  local w, h = targetSize(g, previous)
  w, h = math.floor(w or 0), math.floor(h or 0)
  local scale = (viewport.gameHeight or 0) / 144
  if w <= 0 or h <= 0 or scale <= 0 or not ensure(g, w, h) then return false end
  local lines = d.lines
  state.data:mapPixel(function(_, row)
    local l = lines and lines[row]
    local dx = l and l.dx or 0
    local dy = l and l.dy or 0
    local pal = l and l.pal or d.pal or Effects.IDENTITY
    return (math.max(-127, math.min(127, dx)) + 128) / 255,
      (math.max(-127, math.min(127, dy)) + 128) / 255, pal / 255, 1
  end)
  state.table:replacePixels(state.data)
  active = { d = d, viewport = viewport, scale = scale, previous = previous, rect = elementRect }
  g.setCanvas(state.canvas)
  g.clear(0, 0, 0, 0)
  return true
end

-- Draw straight to the screen while the effects are running (for what is
-- already a copy of the affected Game Boy frame, like the moved sprite boxes).
function Effects.direct(fn)
  if not active then return fn() end
  local g = love.graphics
  g.setCanvas(active.previous)
  local ok, err = pcall(fn)
  g.setCanvas(state.canvas)
  if not ok then error(err, 0) end
end

-- Put the UI drawn since begin() on screen through the effects.
function Effects.finish()
  local frame = active
  active = nil
  if not frame then return end
  local g = love.graphics
  local d, vp, s = frame.d, frame.viewport, frame.scale
  g.setCanvas(frame.previous)
  g.push("all")
  local ok, err = pcall(function()
    g.origin()
    g.setScissor()
    local sh = state.shader
    sh:send("lineTable", state.table)
    sh:send("game", { vp.gameX or 0, vp.gameY or 0, s, 0 })
    sh:send("shift", { d.dx or 0, d.dy or 0 })
    sh:send("basePal", d.pal or Effects.IDENTITY)
    sh:send("veil", d.veil or { 0, 0, 0, 0 })
    local r = frame.rect
    sh:send("elementRect", r and { r.x, r.y, r.w, r.h } or { 0, 0, 0, 0 })
    sh:send("elementDx", r and d.elements and d.elements.enemyHud or 0)
    sh:send("size", { state.w, state.h })
    g.setShader(sh)
    g.setColor(1, 1, 1, 1)
    g.setBlendMode("alpha", "premultiplied")
    g.draw(state.canvas, 0, 0)
  end)
  g.pop()
  if not ok then
    -- never lose the UI to the effects: show it plain, and stop using them
    state.failed = true
    g.push("all")
    g.setShader()
    g.setBlendMode("alpha", "premultiplied")
    pcall(g.draw, state.canvas, 0, 0)
    g.pop()
    error(err, 0)
  end
end

function Effects.release()
  for _, key in ipairs({ "canvas", "shader", "table", "data" }) do
    if state[key] and state[key].release then pcall(state[key].release, state[key]) end
    state[key] = nil
  end
  state.w, state.h, state.failed = 0, 0, false
  active = nil
end

-- The screen veil the host paints over its whole frame (Renderer.screenVeil:
-- the battle-entry flash, the fade in from white): { r, g, b, a } or nil.
function Effects.hostVeil()
  local Renderer = package.loaded["src.render.Renderer"]
  local veil = type(Renderer) == "table" and Renderer.screenVeil or nil
  if type(veil) ~= "table" then return nil end
  if #veil >= 4 then return { veil[1], veil[2], veil[3], veil[4] } end
  if type(veil[1]) == "table" then return { veil[1][1], veil[1][2], veil[1][3], veil[2] } end
  if veil[2] then return { veil[1], veil[1], veil[1], veil[2] } end
  return nil
end

-- A shade map ({[0]=a, b, c, d}: colour i shows shade map[i]) as a DMG byte.
function Effects.byte(map)
  if type(map) ~= "table" then return nil end
  return (map[0] or 0) + 4 * (map[1] or 1) + 16 * (map[2] or 2) + 64 * (map[3] or 3)
end

return Effects
