local ffi = require "ffi"
local bit = require "bit"

ffi.cdef[[
double hypot(double x, double y);
double copysign(double x, double y);
]]
local hypot = ffi.C.hypot
local copysign = ffi.C.copysign

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

local function round(x)
    local i, f = math.modf(x + copysign(0.5, x))
    return i
end

local BitMap = {}
BitMap.__index = BitMap

local function new_bitmap(w, h)
    local self = setmetatable({w=w, h=h}, BitMap)
    self.t = math.ceil(w / 8) -- stride, i.e., bytes/row
    self.p = ffi.new("unsigned char[?]", self.t * self.h)
    return self
end

function BitMap:fill(v)
    ffi.fill(self.p, self.t * self.h, v)
end

function BitMap:inside(x, y)
    return x >= 0 and x < self.w and y >= 0 and y < self.h
end

function BitMap:_index_shift_mask(x, y)
    local index = y * self.t + math.floor(x / 8)
    local shift = (7-x) % 8
    local mask = lshift(1, shift)
    return index, shift, mask
end

function BitMap:pget(x, y)
    if not self:inside(x, y) then return 0 end
    local index, shift, mask = self:_index_shift_mask(x, y)
    return rshift(band(self.p[index], mask), shift)
end

function BitMap:pset(x, y, v)
    if not self:inside(x, y) then return end
    local index, shift, mask = self:_index_shift_mask(x, y)
    local byte = self.p[index]
    if v > 0 then
        byte = bor(byte, mask)
    else
        byte = band(byte, bnot(mask))
    end
    self.p[index] = byte
end

function BitMap:hline(x, y, w, v)
    -- TODO: optimize this using ffi.fill() for large enough w?
    for i = x, x+w-1 do
        self:pset(i, y, v)
    end
end

function BitMap:vline(x, y, h, v)
    for i = y, y+h-1 do
        self:pset(x, i, v)
    end
end

function BitMap:disk(cx, cy, r, v)
    if r == 0 then
        self:pset(cx, cy, v)
        return
    end
    local x, y, d = r, 0, 1-r
    while x >= y do
        self:hline(cx-x, cy+y, 2*x, v)
        self:hline(cx-y, cy+x, 2*y, v)
        self:hline(cx-x, cy-y, 2*x, v)
        self:hline(cx-y, cy-x, 2*y, v)
        y = y + 1
        if d <= 0 then
            d = d + 2*y + 1
        else
            x = x - 1
            d = d + 2*(y-x) + 1
        end
    end
end

function BitMap:line(x0, y0, x1, y1, v, r)
    r = r or 0
    if x1 == x0 then
        local x, y, h
        if y1 > y0 then
            x, y, h = x0, y0, y1-y0
        else
            x, y, h = x0, y1, y0-y1
        end
        self:vline(x, y, h, v)
        for i = 1, r do
            self:vline(x-i, y, h, v)
            self:vline(x+i, y, h, v)
        end
    elseif y1 == y0 then
        local x, y, w
        if x1 > x0 then
            x, y, w = x0, y0, x1-x0
        else
            x, y, w = x1, y0, x0-x1
        end
        self:hline(x, y, w, v)
        for i = 1, r do
            self:hline(x, y-i, w, v)
            self:hline(x, y+i, w, v)
        end
    else
        local dx, dy = x1-x0, y1-y0
        local sx, sy = copysign(1, dx), copysign(1, dy)
        local de = math.abs(dy / dx)
        local e = 0
        local x, y = x0, y0
        while x ~= x1 do
            self:disk(x, y, r, v)
            e = e + de
            while e >= 0.5 do
                self:disk(x, y, r, v)
                y = y + sy
                e = e - 1
            end
            x = x + sx
        end
    end
end

function BitMap:polyline(points, v, r)
    local x0, y0, x1, y1
    x0, y0 = unpack(points[1])
    for i = 2, #points do
        x1, y1 = unpack(points[i])
        self:line(x0, y0, x1, y1, v, r)
        x0, y0 = x1, y1
    end
end

function BitMap:polygon(points, v)
    local scans = {}
    for i = 0, self.h-1 do
        scans[i] = {}
    end
    local x0, y0, x1, y1
    local ax, ay, bx, by -- same line as above, but enforce ay < by
    -- collect crossings
    x0, y0 = unpack(points[1])
    for i = 2, #points do
        x1, y1 = unpack(points[i])
        if y1 ~= y0 then
            if y0 < y1 then
                ax, ay, bx, by = x0, y0, x1, y1
            else
                ax, ay, bx, by = x1, y1, x0, y0
            end
            local slope = (bx-ax) / (by-ay)
            ay = round(ay)
            while ay < by do
                if ay >= 0 and ay < self.h then
                    table.insert(scans[ay], ax)
                end
                ax = ax + slope
                ay = ay + 1
            end
        end
        x0, y0 = x1, y1
    end
    -- fill scanlines
    for i = 0, self.h-1 do
        local scan = scans[i]
        table.sort(scan)
        for j = 1, #scan, 2 do
            ax, bx = round(scan[j]), round(scan[j+1])
            self:hline(ax, i, bx-ax, v)
        end
    end
end

function BitMap:save_pbm(fname)
    local pbm = io.open(fname, "wb")
    pbm:write("P4\n", self.w, " ", self.h, "\n")
    local row = self.p + 0
    for y = 0, self.h-1 do
        pbm:write(ffi.string(row, self.t))
        row = row + self.t
    end
    pbm:close()
end

return {new_bitmap=new_bitmap}
