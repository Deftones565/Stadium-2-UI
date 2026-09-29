-- Installs the Stadium 2 battle UI into a mod: the visibility hooks, the
-- window-space draw, menu input and cleanup. The standalone STADIUM2_UI mod
-- (main.lua) and a mod that embeds this repository (STADIUM2_IMPORTER's ui/
-- submodule) both install through here, so there is one UI codebase.
--
-- cfg (all optional):
--   enabled()        -> bool, the UI is on (default: always)
--   menuControls()   -> "cursor" | "stadium"
--   detail()         -> "hd" | "native"
--   controllerIcons()-> "auto" | "xbox" | "playstation" | "ayn_thor" | "steamdeck" | "native"
--   thorMode()       -> "thor" | "xbox"
--   assetBase        -> this UI's folder inside `mod` ("" standalone, "ui/" embedded)
--   embedded         -> true inside another mod (it never defers to it)
--   warn(message)
local ROOT = (...):match("^(.*)%.lib%.[^%.]+$") or "mods.STADIUM2_UI"
local BattleUI = require(ROOT .. ".lib.battle_ui")
local Menu = require(ROOT .. ".lib.stadium_menu")
local Controller = require(ROOT .. ".lib.stadium_controller")
local Glyphs = require(ROOT .. ".lib.stadium_button_glyphs")
local Assets = require(ROOT .. ".lib.stadium_ui_assets")
local Guard = require(ROOT .. ".lib.graphics_guard")

local Embed = {}
Embed.ROOT = ROOT
Embed.BattleUI = BattleUI

local function call(fn, default)
  if type(fn) ~= "function" then return default end
  local ok, value = pcall(fn)
  if ok and value ~= nil then return value end
  return default
end

function Embed.install(mod, cfg)
  cfg = cfg or {}
  local function warn(message)
    if type(cfg.warn) == "function" then pcall(cfg.warn, tostring(message))
    elseif mod.log and mod.log.warn then pcall(mod.log.warn, mod.log, "%s", tostring(message)) end
  end

  BattleUI.embedded = cfg.embedded == true
  Glyphs.bindMod(mod, cfg.assetBase or "")
  Glyphs.bindWarning(warn)
  BattleUI.bind(mod, function() return call(cfg.enabled, true) == true end, warn)
  BattleUI.menuMode = function()
    return call(cfg.menuControls, "cursor") == "stadium" and "stadium" or "cursor"
  end

  -- The host's own status HUD, bottom box and the party menu / YES/NO the
  -- Stadium UI stands in for (public visibility hooks; nothing is patched).
  mod.hooks:wrap("battle.status_hud_visible", function(next, state, ...)
    if state and state.game then BattleUI.adapterFor(state.game) end
    if not BattleUI.statusVisible(state) then return false end
    return next(state, ...)
  end, 110)
  mod.hooks:wrap("battle.bottom_ui_visible", function(next, state, ...)
    if not BattleUI.bottomVisible(state) then return false end
    return next(state, ...)
  end, 110)
  mod.hooks:wrap("screen.render_visible", function(next, state, ...)
    local ok, hides = pcall(BattleUI.hidesState, state)
    if ok and hides then return false end
    return next(state, ...)
  end, 110)

  -- The default engine scene: render.compose hands over the frame's picture
  -- so the sprite boxes can be moved clear of the UI (the host still
  -- composes the frame). Installed on the first engine battle: a compose
  -- subscriber makes Gold draw through an extra canvas.
  local composeWrapped = false
  BattleUI.onEngineScene = function()
    if composeWrapped then return end
    composeWrapped = true
    mod.hooks:wrap("render.compose", function(next, renderer, ctx, ...)
      pcall(BattleUI.capture, renderer, ctx)
      return next(renderer, ctx, ...)
    end, 110)
  end

  -- Drawn over the finished frame (and over STADIUM2_IMPORTER's 3D battle).
  mod.hooks:wrap("render.hud", function(next, game, viewport, ...)
    local result = next(game, viewport, ...)
    local g = love and love.graphics
    local depth = g and Guard.depth(g)
    local ok, err = pcall(BattleUI.draw, game, viewport)
    -- never hand the engine a deeper graphics stack than it gave us
    if g then Guard.unwind(g, depth) end
    if not ok then warn("Stadium UI draw failed: " .. tostring(err)) end
    return result
  end, 110)

  -- Gamepad shoulders: the host binds LB/RB to game speed and returns before
  -- they become L/R, so while a Stadium menu is open they are handed to the
  -- host's own Input:gamepadpressed. Installed on the first Stadium menu:
  -- the host mutes its pad-repair polling while a mod owns input.gamepad.
  local padWrapped = false
  local function wrapPad()
    if padWrapped then return end
    padWrapped = true
    mod.hooks:wrap("input.gamepad", function(next, game, event)
      Menu.gamepad(event)
      if type(event) == "table" and event.phase == "pressed"
          and (event.button == "leftshoulder" or event.button == "rightshoulder")
          and BattleUI.menuContext() then
        local input = game and game.input
        if input and type(input.gamepadpressed) == "function" then
          input:gamepadpressed(event.joystick, event.button)
          return
        end
      end
      return next(game, event)
    end, 7)
  end

  -- Menu input acts before the engine promotes this tick's presses.
  mod.hooks:wrap("input.step", function(next, game, dt)
    pcall(function()
      BattleUI.adapterFor(game)
      Assets.setDetail(call(cfg.detail, "hd"))
      local icons = call(cfg.controllerIcons, "auto")
      Controller.setStyle(icons)
      Glyphs.setStyle(icons)
      Controller.setThorLayout(call(cfg.thorMode, "thor"))
    end)
    local ctx = BattleUI.menuContext()
    if ctx then pcall(wrapPad) end
    pcall(Menu.step, game, ctx, BattleUI.menuMode(), function(button)
      if mod.input and mod.input.tap then pcall(mod.input.tap, mod.input, game, button) end
    end)
    return next(game, dt)
  end, 7)
  mod.hooks:wrap("input.pointer", function(next, owner, event)
    Menu.pointer(event)
    return next(owner, event)
  end, 120)

  mod.events:on("battle.ended", function()
    BattleUI.release()
    Menu.reset()
  end)
  return BattleUI
end

return Embed
