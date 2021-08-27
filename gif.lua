local ffi = require "ffi"
local bit = require "bit"

local bio = require "bio"
local surf = require "surf"
local lzw = require "lzw"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

local write_num = bio.write_lei16

local function write_nums(f, ...)
    local nums = {...}
    for i, n in pairs(nums) do
        write_num(f, n)
    end
end

local function get_depth(n)
    local m, e = math.frexp(n-1)
    return math.max(e, 1)
end

local GIFout = {}
GIFout.__index = GIFout

local function new_gifout(f, w, h, colors)
    if type(f) == "string" then f = io.open(f, "wb") end
    local depth = get_depth(#colors)
    local self = setmetatable({f=f, w=w, h=h, d=depth, gct=colors}, GIFout)
    if depth == 1 then
        self.back = surf.new_bitmap(w, h)
    else
        self.back = surf.new_bytemap(w, h)
    end
    f:write("GIF89a")
    write_nums(f, w, h)
    f:write(string.char(0xF0 + depth - 1, 0, 0)) -- FDSZ, BGINDEX, ASPECT
    local i = 1
    while i <= #colors do
        f:write(string.char(unpack(colors[i])))
        i = i + 1
    end
    while i <= 2^depth do             -- GCT size must be a power of two
        f:write(string.char(0, 0, 0)) -- fill unused colors as black
        i = i + 1
    end
    self.n = 0 -- # of frames added
    return self
end

function GIFout:set_loop(n)
    n = n or 0
    self.f:write("!")
    self.f:write(string.char(0xFF, 0x0B))
    self.f:write("NETSCAPE2.0")
    self.f:write(string.char(0x03, 0x01))
    write_num(self.f, n)
    self.f:write(string.char(0))
end

function GIFout:set_delay(d)
    self.f:write("!")
    self.f:write(string.char(0xF9, 0x04, 0x04))
    write_num(self.f, d)
    self.f:write(string.char(0, 0))
end

function GIFout:get_bbox(frame)
    local w, h = self.w, self.h
    if self.n == 0 then return 0, 0, w, h end
    local xmin, ymin = w, h
    local xmax, ymax = 0, 0
    local back = self.back
    for y = 0, h-1 do
        for x = 0, w-1 do
            if frame:pget(x, y) ~= back:pget(x, y) then
                if x < xmin then xmin = x end
                if y < ymin then ymin = y end
                if x > xmax then xmax = x end
                if y > ymax then ymax = y end
            end
        end
    end
    if xmin == w or ymin == h then return 0, 0, 1, 1 end
    return xmin, ymin, xmax-xmin+1, ymax-ymin+1
end

function GIFout:put_image(frame, x, y, w, h)
    self.f:write(",")
    write_nums(self.f, x, y, w, h)
    self.f:write(string.char(0))
    lzw.encode(self.f, self.d, frame, x, y, w, h) -- IP (Appendix F)
end

function GIFout:add_frame(frame, delay)
    if delay then self:set_delay(delay) end
    local x, y, w, h = self:get_bbox(frame)
    self:put_image(frame, x, y, w, h)
    self.n = self.n + 1
    self.back:blit(x, y, frame, x, y, w, h)
end

function GIFout:close()
    self.f:write(";")
    self.f:close()
end

return {new_gifout=new_gifout}
