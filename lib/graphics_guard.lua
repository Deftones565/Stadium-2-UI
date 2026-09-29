-- LOVE keeps one graphics transform stack for the whole frame and refuses a
-- push past 64 levels. A draw that throws after its own push() leaves that
-- level behind; under pcall that happens again every frame, and after 64
-- frames every push fails and the whole UI with it. Guard.run draws inside
-- push("all")/pop and always leaves the stack at the depth it found.
local Guard = {}

local function depthOf(g)
  if type(g.getStackDepth) ~= "function" then return nil end
  local ok, depth = pcall(g.getStackDepth)
  return ok and tonumber(depth) or nil
end

-- Pop back to `depth` (levels a failed draw left behind); true when it did.
function Guard.unwind(g, depth)
  if not depth then return false end
  local now = depthOf(g)
  local popped = false
  while now and now > depth do
    if not pcall(g.pop) then break end
    popped = true
    now = depthOf(g)
  end
  return popped
end

-- ok, err of fn(...) run inside push("all")/pop.
function Guard.run(g, fn, ...)
  local depth = depthOf(g)
  g.push("all")
  local ok, err = pcall(fn, ...)
  if depth then Guard.unwind(g, depth) else pcall(g.pop) end
  return ok, err
end

Guard.depth = depthOf

return Guard
