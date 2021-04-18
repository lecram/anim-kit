local ffi = require "ffi"

ffi.cdef[[
double hypot(double x, double y);
]]
local hypot = ffi.C.hypot

local sqrt2 = math.sqrt(2)

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
    local a, b, c, h
    local ax, ay, bx, by, cx, cy
    local dx, dy, ex, ey, fx, fy
    local points = {}
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

-- convert a sequence of linked Bézier curves to a polyline
local function unfold(control_points)
    local s, a, b
    local px, py, qx, qy, rx, ry
    s = control_points[1]
    b = control_points[2]
    local points = {s}
    local sub
    if b[3] then
        table.insert(points, b)
        s = b
    end
    for i = 3, #control_points do
        a = b
        b = control_points[i]
        if a[3] then
            if b[3] then
                table.insert(points, b)
                s = b
            end
        else
            if b[3] then
                px, py, _ = unpack(s)
                qx, qy, _ = unpack(a)
                rx, ry, _ = unpack(b)
                sub = bezier({{px, py}, {qx, qy}, {rx, ry}})
                for i, p in ipairs(sub) do
                    table.insert(points, p)
                end
                s = b
            else
                px, py, _ = unpack(s)
                qx, qy, _ = unpack(a)
                rx, ry, _ = unpack(b)
                rx, ry = (qx+rx)/2, (qy+ry)/2
                sub = bezier({{px, py}, {qx, qy}, {rx, ry}})
                for i, p in ipairs(sub) do
                    table.insert(points, p)
                end
                s = {rx, ry, true}
            end
        end
    end
    return points
end

-- bezigon that approximates a circle
local function bcircle(x, y, r)
    local a = r * (sqrt2-1)
    return {
        {x  , y+r, true},
        {x+a, y+r, false},
        {x+r, y+a, false},
        {x+r, y-a, false},
        {x+a, y-r, false},
        {x-a, y-r, false},
        {x-r, y-a, false},
        {x-r, y+a, false},
        {x-a, y+r, false},
        {x  , y+r, true}
    }
end

-- regular polygon that approximates a circle
local function pcircle(x, y, r)
    local h = 0.5 -- maximum radius-apothem allowed
    local n = math.ceil(math.pi / math.acos(1 - h/r)) -- # of sides
    local a = 2 * math.pi / n -- angle between points
    local pgon = {}
    local px, py
    local pa = 0
    for i = 1, n do
        px = x + r * math.cos(pa)
        py = y + r * math.sin(pa)
        table.insert(pgon, {px, py})
        pa = pa + a
    end
    table.insert(pgon, pgon[1]) -- repeat first point to close polygon
    return pgon
end

return {dashed=dashed, unfold=unfold, bcircle=bcircle, pcircle=pcircle}
