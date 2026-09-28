-- The host keeps a mod's Lua modules in package.loaded across game sessions
-- (it only purges src.*). After an in-app update without an app restart the
-- new main.lua would get the previous version's modules back from require.
-- main.lua runs in the mod sandbox, whose `package` is an empty stand-in, so
-- the eviction lives here: lib modules load in the global environment and
-- see the real package.loaded.
local Guard = {}

local PREFIX = "mods.STADIUM2_UI."
local STAMP = PREFIX .. "__build"
local SELF = PREFIX .. "lib.cache_guard"

-- Drop every cached module of this mod when `build` differs from the build
-- that loaded them. Returns true when modules were evicted.
function Guard.refresh(build)
  local loaded = package.loaded
  if loaded[STAMP] == build then return false end
  for name in pairs(loaded) do
    if type(name) == "string" and name:sub(1, #PREFIX) == PREFIX and name ~= SELF then
      loaded[name] = nil
    end
  end
  loaded[STAMP] = build
  -- this module reloads fresh next session too
  loaded[SELF] = nil
  return true
end

return Guard
