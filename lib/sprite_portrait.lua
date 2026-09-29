-- Portraits for sprite battles: when the battle shows the Game Boy sprites
-- (no 3D models), the portrait box shows the Pokemon's front sprite,
-- coloured the way the host battle colours it, on the portrait grey.
-- Rendered at the box's on-screen size so the sprite stays sharp.
local SpritePortrait = {}
SpritePortrait.BACKGROUND = { 74 / 255, 74 / 255, 74 / 255, 1 }

local slots = {}
local bounds = setmetatable({}, { __mode = "k" })

-- The opaque area of a sprite (front sprites sit in a padded 56 px frame),
-- measured once per image through a scratch canvas.
function SpritePortrait.contentBounds(g, image)
  if bounds[image] then return bounds[image] end
  local w, h = image:getDimensions()
  local box = { 0, 0, w, h }
  local ok = pcall(function()
    local canvas = g.newCanvas(w, h, { format = "rgba8", dpiscale = 1 })
    g.push("all")
    g.setCanvas(canvas)
    g.origin()
    g.setScissor()
    g.setShader()
    g.clear(0, 0, 0, 0)
    g.setColor(1, 1, 1, 1)
    g.draw(image, 0, 0)
    g.pop()
    local data = canvas:newImageData()
    canvas:release()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local _, _, _, a = data:getPixel(x, y)
        if a > 0.05 then
          if x < x0 then x0 = x end
          if x > x1 then x1 = x end
          if y < y0 then y0 = y end
          if y > y1 then y1 = y end
        end
      end
    end
    data:release()
    if x1 >= x0 then box = { x0, y0, x1 - x0 + 1, y1 - y0 + 1 } end
  end)
  if not ok then box = { 0, 0, w, h } end
  bounds[image] = box
  return box
end

-- sprite = { image = LOVE image, draw = fn(drawImage) } from a host
-- adapter (draw wraps the host's colouring around drawImage).
function SpritePortrait.render(side, sprite, pixels)
  local g = love and love.graphics
  if not (g and sprite and sprite.image) then return nil end
  local size = math.max(32, math.min(512, math.ceil(tonumber(pixels) or 32)))
  local slot = slots[side]
  if not slot or slot.size ~= size then
    if slot and slot.canvas and slot.canvas.release then pcall(slot.canvas.release, slot.canvas) end
    local ok, canvas = pcall(g.newCanvas, size, size, { format = "rgba8", dpiscale = 1 })
    if not ok then return nil end
    pcall(canvas.setFilter, canvas, "linear", "linear")
    slot = { canvas = canvas, size = size }
    slots[side] = slot
  end
  local image = sprite.image
  -- the visible sprite fitted to the box with a small margin, standing on
  -- its bottom edge like a close portrait
  local b = SpritePortrait.contentBounds(g, image)
  local scale = size * 0.9 / math.max(b[3], b[4])
  local x = math.floor((size - b[3] * scale) / 2 - b[1] * scale)
  local y = math.floor(size - size * 0.04 - b[4] * scale - b[2] * scale)
  g.push("all")
  local ok, err = pcall(function()
    g.setCanvas(slot.canvas)
    g.origin()
    g.setScissor()
    g.clear(SpritePortrait.BACKGROUND)
    g.setColor(1, 1, 1, 1)
    local filter = image.getFilter and { image:getFilter() }
    if image.setFilter then image:setFilter("nearest", "nearest") end
    local function drawImage() g.draw(image, x, y, 0, scale, scale) end
    if type(sprite.draw) == "function" then sprite.draw(drawImage) else drawImage() end
    if filter and image.setFilter then image:setFilter(filter[1], filter[2]) end
  end)
  g.pop()
  if not ok then return nil, err end
  return slot.canvas
end

function SpritePortrait.release()
  for side, slot in pairs(slots) do
    if slot.canvas and slot.canvas.release then pcall(slot.canvas.release, slot.canvas) end
    slots[side] = nil
  end
end

return SpritePortrait
