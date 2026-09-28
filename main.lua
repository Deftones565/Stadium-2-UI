-- Evict this mod's modules cached by a previous version (see
-- lib/cache_guard.lua). MOD_BUILD must match manifest.json's version
-- (stadium2_ui_host_test).
local MOD_BUILD = "1.0.2"
require("mods.STADIUM2_UI.lib.cache_guard").refresh(MOD_BUILD)

local BattleUI = require("mods.STADIUM2_UI.lib.battle_ui")
local Menu = require("mods.STADIUM2_UI.lib.stadium_menu")
local Controller = require("mods.STADIUM2_UI.lib.stadium_controller")
local Glyphs = require("mods.STADIUM2_UI.lib.stadium_button_glyphs")
local Assets = require("mods.STADIUM2_UI.lib.stadium_ui_assets")

return function(mod)
  local function option(key, default)
    if mod.options and mod.options.get then
      local ok, value = pcall(mod.options.get, mod.options, key)
      if ok and value ~= nil then return value end
    end
    return default
  end
  local function warn(message)
    if mod.log and mod.log.warn then pcall(mod.log.warn, mod.log, "%s", tostring(message)) end
  end

  mod.options:define({
    { key = "stadium2_ui_enabled", label = "STADIUM UI", type = "toggle", default = true,
      help = "Pokemon Stadium 2's battle UI, recreated: status panels, message box, command bar, move diamond and info, switch cards and YES/NO. Works on the Game Boy battle and with STADIUM2_IMPORTER's 3D battle (which adds live portraits)." },
    { key = "stadium2_ui_menu_controls", label = "MENU CONTROLS", type = "choice", default = "cursor",
      visible_if = { key = "stadium2_ui_enabled", equals = true },
      choices = { { "CURSOR", "cursor" }, { "STADIUM", "stadium" } },
      help = "With a controller the menus always use Stadium 2's controls: no cursor, A BATTLE, B POKeMON, START RUN, R PACK, C buttons (right stick) pick, hold the D-pad for a move's info, L (LB) cancels. On keyboard, CURSOR keeps the moving cursor (hold R for info); STADIUM uses the controller scheme (C = I/J/K/L). PACK is not in Stadium 2." },
    { key = "stadium2_ui_detail", label = "UI DETAIL", type = "choice", default = "hd",
      visible_if = { key = "stadium2_ui_enabled", equals = true },
      choices = { { "HD", "hd" }, { "N64 PIXELS", "native" } },
      help = "HD smooths the UI's pixel art and font for big screens. N64 PIXELS shows them as crisp pixels, like the N64." },
    { key = "stadium2_ui_controller_icons", label = "CONTROLLER ICONS", type = "choice", default = "auto",
      visible_if = { key = "stadium2_ui_enabled", equals = true },
      choices = { { "AUTO", "auto" }, { "XBOX", "xbox" }, { "PLAYSTATION", "playstation" },
        { "AYN THOR", "ayn_thor" }, { "STEAM DECK", "steamdeck" }, { "NATIVE N64", "native" } },
      help = "AUTO follows the last controller used. Choose a family if a driver or Steam Input hides its identity. Changes prompts only; your control bindings stay in effect." },
    { key = "stadium2_ui_thor_input_mode", label = "THOR INPUT MODE", type = "choice", default = "thor",
      visible_if = { key = "stadium2_ui_controller_icons", equals = "ayn_thor" },
      choices = { { "THOR", "thor" }, { "XBOX", "xbox" } },
      help = "Match the Controller Style on your AYN Thor. XBOX swaps the printed A/B and X/Y prompts." },
  })

  Glyphs.bindMod(mod)
  Glyphs.bindWarning(warn)
  BattleUI.bind(mod, function() return option("stadium2_ui_enabled", true) == true end, warn)
  BattleUI.menuMode = function()
    return option("stadium2_ui_menu_controls", "cursor") == "stadium" and "stadium" or "cursor"
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
    local ok, err = pcall(BattleUI.draw, game, viewport)
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
      Assets.setDetail(option("stadium2_ui_detail", "hd"))
      local icons = option("stadium2_ui_controller_icons", "auto")
      Controller.setStyle(icons)
      Glyphs.setStyle(icons)
      Controller.setThorLayout(option("stadium2_ui_thor_input_mode", "thor"))
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
end
