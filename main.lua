-- Evict this mod's modules cached by a previous version (see
-- lib/cache_guard.lua). MOD_BUILD must match manifest.json's version
-- (stadium2_ui_host_test).
local MOD_BUILD = "1.1.2"
require("mods.STADIUM2_UI.lib.cache_guard").refresh(MOD_BUILD)

local Embed = require("mods.STADIUM2_UI.lib.embed")
local StadiumUI = require("mods.STADIUM2_UI.lib.stadium_ui")

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

  -- The hooks, draw and input live in lib/embed.lua, shared with mods that
  -- embed this UI (STADIUM2_IMPORTER's ui/ submodule).
  Embed.install(mod, {
    warn = warn,
    enabled = function() return option("stadium2_ui_enabled", true) == true end,
    menuControls = function() return option("stadium2_ui_menu_controls", "cursor") end,
    detail = function() return option("stadium2_ui_detail", "hd") end,
    controllerIcons = function() return option("stadium2_ui_controller_icons", "auto") end,
    thorMode = function() return option("stadium2_ui_thor_input_mode", "thor") end,
  })

  -- For mods that depend on this one (STADIUM2_IMPORTER's in-battle
  -- evolution shows its texts in Stadium's message box through these).
  if mod.exports then
    mod.exports.enabled = function() return option("stadium2_ui_enabled", true) == true end
    mod.exports.messageAvailable = function() return StadiumUI.available() == true end
    mod.exports.toLatin1 = StadiumUI.toLatin1
    -- area = {x, y, w, h} in window units; lines in Latin-1; side "player" | "enemy"
    mod.exports.drawMessage = function(area, lines, side, warnFn)
      return StadiumUI.tryDrawMessage(area, lines, side, warnFn)
    end
  end
end
