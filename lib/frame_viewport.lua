-- The frame's viewport for render.hud. The host passes what
-- Renderer:endFrame returned; a mod that wraps endFrame and forgets to
-- return its result hands render.hud nil instead (TERRARIUM 1.30.1's
-- DayTint does this whenever its day tint is on, i.e. except at full
-- daylight), and a UI that needs the viewport then draws nothing. The same
-- table is rebuilt here from Renderer:frameRects, the metrics endFrame
-- builds its return value from (side-effect free).
local FrameViewport = {}

local function renderer(game)
  local r = game and game.renderer
  if type(r) == "table" and type(r.frameRects) == "function" then return r end
  local loaded = package.loaded["src.render.Renderer"]
  if type(loaded) == "table" and type(loaded.frameRects) == "function" then return loaded end
  return nil
end

-- Renderer:endFrame's return value, from Renderer:frameRects.
function FrameViewport.rebuild(game)
  local r = renderer(game)
  if not r then return nil end
  local ok, R = pcall(r.frameRects, r)
  if not (ok and type(R) == "table") then return nil end
  return {
    width = R.ww, height = R.wh,
    gameX = R.ox, gameY = R.oy,
    gameWidth = R.vpw, gameHeight = R.vph,
    scale = R.Sp,
    dpiX = R.dpiX, dpiY = R.dpiY,
    viewX = R.vux, viewY = R.vuy, viewWidth = R.vuw, viewHeight = R.vuh,
  }
end

local reported = false
-- `viewport` when the host passed one, else the rebuilt one (reported once).
function FrameViewport.resolve(game, viewport, warn)
  if type(viewport) == "table" then return viewport end
  local rebuilt = FrameViewport.rebuild(game)
  if not reported and type(warn) == "function" then
    reported = true
    pcall(warn, rebuilt
      and "render.hud had no viewport (a mod's Renderer:endFrame wrap dropped its return value); rebuilt from Renderer:frameRects"
      or "render.hud had no viewport and Renderer:frameRects is unavailable; the UI is not drawn")
  end
  return rebuilt
end

return FrameViewport
