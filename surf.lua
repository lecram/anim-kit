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
    -- TODO: only check bounds in user-facing methods, for performance
    assert(self:inside(x, y))
    local index = y * self.t + math.floor(x / 8)
    local shift = (7-x) % 8
    local mask = lshift(1, shift)
    return index, shift, mask
end

function BitMap:pget(x, y)
    local index, shift, mask = self:_index_shift_mask(x, y)
    return rshift(band(self.p[index], mask), shift)
end

function BitMap:pset(x, y, v)
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

function BitMap:line(x0, y0, x1, y1, v)
    if x1 == x0 then
        if y1 > y0 then
            self:vline(x0, y0, y1 - y0)
        else
            self:vline(x0, y1, y0 - y1)
        end
    elseif y1 == y0 then
        if x1 > x0 then
            self:hline(x0, y0, x1 - x0)
        else
            self:hline(x1, y0, x0 - x1)
        end
    else
        local dx, dy = x1-x0, y1-y0
        local sx, sy = copysign(1, dx), copysign(1, dy)
        local de = math.abs(dy / dx)
        local e = 0
        local x, y = x0, y0
        while x ~= x1 do
            self:pset(x, y, v)
            e = e + de
            while e >= 0.5 do
                self:pset(x, y, v)
                y = y + sy
                e = e - 1
            end
            x = x + sx
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
