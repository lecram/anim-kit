local ffi = require "ffi"
local bit = require "bit"

local util = require "util"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

local Surf = {}

function Surf:inside(x, y)
    return x >= 0 and x < self.w and y >= 0 and y < self.h
end

function Surf:hline(x, y, w, v)
    for i = x, x+w-1 do
        self:pset(i, y, v)
    end
end

function Surf:vline(x, y, h, v)
    for i = y, y+h-1 do
        self:pset(x, i, v)
    end
end

function Surf:disk(cx, cy, r, v)
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

function Surf:line(x0, y0, x1, y1, v, r)
    r = r or 0
    local dx, dy = x1-x0, y1-y0
    local n = math.max(math.abs(dx), math.abs(dy))
    local sx, sy = dx/n, dy/n
    local x, y = x0, y0
    self:disk(math.floor(x), math.floor(y), r, v)
    for i = 1, n do
        x = x + sx
        y = y + sy
        self:disk(math.floor(x), math.floor(y), r, v)
    end
end

function Surf:polyline(points, v, r)
    points = util.func_iter(points)
    local x0, y0, x1, y1
    x0, y0 = unpack(points())
    for point in points do
        x1, y1 = unpack(point)
        self:line(x0, y0, x1, y1, v, r)
        x0, y0 = x1, y1
    end
end

function Surf:polylines(polylines, v, r)
    polylines = util.func_iter(polylines)
    for points in polylines do
        self:polyline(points, v, r)
    end
end

local function cross_comp(a, b)
    return a[1] < b[1]
end

function Surf:scan(points)
    points = util.func_iter(points)
    if not self.scans then
        self.scans = {}
        for i = 0, self.h-1 do
            self.scans[i] = {}
        end
    end
    local x0, y0, x1, y1
    local ax, ay, bx, by -- same line as above, but enforce ay < by
    local sign
    x0, y0 = unpack(points())
    for point in points do
        x1, y1 = unpack(point)
        if y1 ~= y0 then
            if y0 < y1 then
                ax, ay, bx, by = x0, y0, x1, y1
                sign =  1
            else
                ax, ay, bx, by = x1, y1, x0, y0
                sign = -1
            end
            local slope = (bx-ax) / (by-ay)
            ay, by = util.round(ay), util.round(by)
            while ay < by do
                if ay >= 0 and ay < self.h then
                    table.insert(self.scans[ay], {ax, sign})
                end
                ax = ax + slope
                ay = ay + 1
            end
        end
        x0, y0 = x1, y1
    end
end

function Surf:fill_scans(v)
    local scan, wind
    local x, sign
    local ax, bx
    for i = 0, self.h-1 do
        scan = self.scans[i]
        table.sort(scan, cross_comp)
        wind = 0
        for j, cross in ipairs(scan) do
            x, sign = unpack(cross)
            if wind == 0 then
                ax = math.floor(x)
            end
            wind = wind + sign
            if wind == 0 then
                bx = math.ceil(x)
                self:hline(ax, i, bx-ax, v)
            end
        end
    end
    self.scans = nil
end

function Surf:polygon(points, v)
    self:scan(points)
    self:fill_scans(v)
end

function Surf:polygons(polygons, v)
    polygons = util.func_iter(polygons)
    for points in polygons do
        self:scan(points)
    end
    self:fill_scans(v)
end

function Surf:blit(x, y, surf, sx, sy, w, h)
    for j = 0, h-1 do
        for i = 0, w-1 do
            self:pset(x+i, y+j, surf:pget(sx+i, sy+j))
        end
    end
end

local BitMap = {}

function BitMap:fill(v)
    ffi.fill(self.p, self.t * self.h, v)
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

setmetatable(BitMap, {__index=Surf})

local function new_bitmap(w, h)
    local self = setmetatable({w=w, h=h}, {__index=BitMap})
    self.t = math.ceil(w / 8) -- stride, i.e., bytes/row
    self.p = ffi.new("unsigned char[?]", self.t * self.h)
    return self
end

local ByteMap = {}

function ByteMap:fill(v)
    ffi.fill(self.p, self.w * self.h, v)
end

function ByteMap:pget(x, y)
    if not self:inside(x, y) then return 0 end
    return self.p[y*self.w+x]
end

function ByteMap:pset(x, y, v)
    if not self:inside(x, y) then return end
    self.p[y*self.w+x] = v
end

function ByteMap:save_ppm(fname, colors)
    local ppm = io.open(fname, "wb")
    ppm:write("P6\n", self.w, " ", self.h, "\n", 255, "\n")
    for i = 0, self.w*self.h-1 do
        ppm:write(string.char(unpack(colors[self.p[i]+1])))
    end
    ppm:close()
end

setmetatable(ByteMap, {__index=Surf})

local function new_bytemap(w, h)
    local self = setmetatable({w=w, h=h}, {__index=ByteMap})
    self.p = ffi.new("unsigned char[?]", self.w * self.h)
    return self
end

return {new_bitmap=new_bitmap, new_bytemap=new_bytemap}
