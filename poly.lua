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

-- regular polygon
local function ngon(x, y, r, n, mina, maxa)
    mina = mina or 0
    maxa = maxa or 2 * math.pi
    local a = 2 * math.pi / n -- angle between points
    local pgon = {}
    local px, py
    local pa = mina
    while pa < maxa do
        px = x + r * math.cos(pa)
        py = y + r * math.sin(pa)
        table.insert(pgon, {px, py})
        pa = pa + a
    end
    px = x + r * math.cos(maxa)
    py = y + r * math.sin(maxa)
    table.insert(pgon, {px, py})
    return pgon
end

-- approximate an arc between angles mina and maxa
local function parc(x, y, r, mina, maxa)
    local h = 0.5 -- maximum radius-apothem allowed
    local n = math.ceil(math.pi / math.acos(1 - h/r)) -- # of sides
    return ngon(x, y, r, n, mina, maxa)
end

-- regular polygon that approximates a circle
local function pcircle(x, y, r)
    return parc(x, y, r, 0, 2 * math.pi)
end

local function arrow_head(x0, y0, x1, y1, w, h)
    local dx, dy = x1-x0, y1-y0
    local a = math.atan2(dy, dx)    -- line angle
    local b = math.atan2(-dx, dy)   -- perpendicular angle
    local mx, my = math.cos(a), math.sin(a)
    local nx, ny = math.cos(b), math.sin(b)
    local bx, by = x1 - mx * h, y1 - my * h     -- back of arrow
    local lx, ly = bx - nx * w/2, by - ny * w/2 -- left point
    local rx, ry = bx + nx * w/2, by + ny * w/2 -- right point
    bx, by = bx + mx * h/2, by + my * h/2       -- off-curve point
    local control_points = {
      {lx, ly, true},
      {x1, y1, true},
      {rx, ry, true},
      {bx, by, false},
      {lx, ly, true},
    }
    return unfold(control_points)
    --~ return control_points
end

return {
  dashed=dashed, unfold=unfold, bcircle=bcircle, ngon=ngon,
  parc=parc, pcircle=pcircle, arrow_head=arrow_head
}
