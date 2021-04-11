local ffi = require "ffi"

ffi.cdef[[
double hypot(double x, double y);
]]
local hypot = ffi.C.hypot

local function dashed(points, pattern)
    local x0, y0, x1, y1
    local cx, cy
    local i, j
    local d, h
    local polylines = {}
    local polyline
    local draw = true
    x0, y0 = unpack(points[1])
    polyline = {{x0, y0}}
    i = 2
    x1, y1 = unpack(points[i])
    j = 1
    d = pattern[j]
    while true do
        h = hypot(x1-x0, y1-y0)
        if d < h then
            cx = x0 + (x1-x0)*d/h
            cy = y0 + (y1-y0)*d/h
            if draw then
                table.insert(polyline, {cx, cy})
                table.insert(polylines, polyline)
            else
                polyline = {{cx, cy}}
            end
            x0, y0 = cx, cy
            draw = not draw
            if j < #pattern then j = j + 1 else j = 1 end
            d = pattern[j]
        else
            if draw then
                table.insert(polyline, {x1, y1})
            end
            d = d - h
            if i < #points then i = i + 1 else break end
            x0, y0 = x1, y1
            x1, y1 = unpack(points[i])
        end
    end
    if draw then
        table.insert(polyline, points[i])
        table.insert(polylines, polyline)
    end
    return polylines
end

-- convert bezier curve {{ax, ay}, {bx, by}, {cx, cy}} to polyline
local function bezier(curve)
    local h
    local dx, dy, ex, ey, fx, fy
    local a, b, c = unpack(curve)
    local ax, ay = unpack(a)
    local bx, by = unpack(b)
    local cx, cy = unpack(c)
    local points = {{ax, ay}}
    local stack = {curve}
    while #stack > 0 do
        a, b, c = unpack(table.remove(stack))
        ax, ay = unpack(a)
        bx, by = unpack(b)
        cx, cy = unpack(c)
        h = math.abs((ax-cx)*(by-ay)-(ax-bx)*(cy-ay))/hypot(cx-ax, cy-ay)
        if h > 1 then -- split curve
            dx, dy = (ax+bx)/2, (ay+by)/2
            fx, fy = (bx+cx)/2, (by+cy)/2
            ex, ey = (dx+fx)/2, (dy+fy)/2
            table.insert(stack, {{ex, ey}, {fx, fy}, {cx, cy}})
            table.insert(stack, {{ax, ay}, {dx, dy}, {ex, ey}})
        else -- add point to polyline
            table.insert(points, {cx, cy})
        end
    end
    return points
end

return {dashed=dashed, bezier=bezier}
