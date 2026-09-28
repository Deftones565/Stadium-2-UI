-- 4x4 camera matrices for the portrait renders (copied from
-- STADIUM2_IMPORTER's lib/renderer.lua; row-major, as its renderer expects).
local Matrix = {}
local sin, cos, sqrt = math.sin, math.cos, math.sqrt

function Matrix.matMul(a, b)
  local o = {}
  for r = 0, 3 do
    for c = 0, 3 do
      local v = 0
      for k = 0, 3 do v = v + a[r * 4 + k + 1] * b[k * 4 + c + 1] end
      o[r * 4 + c + 1] = v
    end
  end
  return o
end

function Matrix.perspective(fovy, aspect, near, far, shiftX, shiftY)
  local f = 1 / math.tan(fovy * 0.5)
  shiftX, shiftY = tonumber(shiftX) or 0, tonumber(shiftY) or 0
  return {
    f / aspect, 0, -shiftX, 0,
    0, f, -shiftY, 0,
    0, 0, (far + near) / (near - far), (2 * far * near) / (near - far),
    0, 0, -1, 0,
  }
end

function Matrix.lookAt(ex, ey, ez, tx, ty, tz)
  local fx, fy, fz = tx - ex, ty - ey, tz - ez
  local fl = sqrt(fx * fx + fy * fy + fz * fz)
  if fl == 0 then fl = 1 end
  fx, fy, fz = fx / fl, fy / fl, fz / fl
  local ux, uy, uz = 0, 1, 0
  local sx, sy, sz = fy * uz - fz * uy, fz * ux - fx * uz, fx * uy - fy * ux
  local sl = sqrt(sx * sx + sy * sy + sz * sz)
  if sl == 0 then sx, sy, sz, sl = 1, 0, 0, 1 end
  sx, sy, sz = sx / sl, sy / sl, sz / sl
  ux, uy, uz = sy * fz - sz * fy, sz * fx - sx * fz, sx * fy - sy * fx
  return {
    sx, sy, sz, -(sx * ex + sy * ey + sz * ez),
    ux, uy, uz, -(ux * ex + uy * ey + uz * ez),
    -fx, -fy, -fz, fx * ex + fy * ey + fz * ez,
    0, 0, 0, 1,
  }
end

function Matrix.normalMatrix(yaw, pitch, flipY, out)
  local y = yaw or 0
  local p = pitch or 0
  local sy, cyaw = sin(y), cos(y)
  local sp, cp = sin(p), cos(p)
  local fy = flipY == false and 1 or -1
  out = out or {}
  out[1], out[2], out[3] = cyaw, sy * sp * fy, sy * cp
  out[4], out[5], out[6] = 0, cp * fy, -sp
  out[7], out[8], out[9] = -sy, cyaw * sp * fy, cyaw * cp
  return out
end

return Matrix
