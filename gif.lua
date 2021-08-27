local ffi = require "ffi"
local bit = require "bit"

local bio = require "bio"
local surf = require "surf"
local lzw = require "lzw"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

-- == Encoder ==

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

local function new_gif(f, w, h, colors)
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

-- == Decoder ==

local read_num = bio.read_lei16

local GIFin = {}
GIFin.__index = GIFin

local function open_gif(f)
    if type(f) == "string" then f = io.open(f, "rb") end
    assert(f:read(6) == "GIF89a", "invalid signature")
    local w, h = read_num(f), read_num(f)
    local fdsz = bio.read_byte(f)
    local has_gct = rshift(fdsz, 7) == 1
    local d = band(fdsz, 7) + 1
    local bg = bio.read_byte(f)
    f:seek("cur", 1) -- ASPECT:u8
    local self = setmetatable({f=f, w=w, h=h, d=d, bg=bg}, GIFin)
    self.gct = has_gct and self:read_color_table(d) or {}
    if d == 1 then
        self.surf = surf.new_bitmap(w, h)
    else
        self.surf = surf.new_bytemap(w, h)
    end
    return self
end

function GIFin:read_color_table(d)
    local ct = {}
    local ncolors = lshift(1, d)
    for i = 1, ncolors do
        local r = bio.read_byte(self.f)
        local g = bio.read_byte(self.f)
        local b = bio.read_byte(self.f)
        table.insert(ct, {r, g, b})
    end
    return ct
end

function GIFin:discard_sub_blocks()
    repeat
        local size = bio.read_byte(self.f)
        self.f:seek("cur", size)
    until size == 0
end

function GIFin:read_graphic_control_ext()
    assert(bio.read_byte(self.f) == 0x04, "invalid GCE block size")
    local rdit = bio.read_byte(self.f)
    self.disposal = band(rshift(rdit, 2), 3)
    self.input = band(rshift(rdit, 1), 1) == 1
    local transp = band(rdit, 1) == 1
    self.delay = read_num(self.f)
    local tindex = bio.read_byte(self.f)
    self.tindex = transp and tindex or -1
    self.f:seek("cur", 1) -- end-of-block
end

function GIFin:read_application_ext()
    assert(bio.read_byte(self.f) == 0x0B, "invalid APP block size")
    local app_ip = self.f:read(8)
    local app_auth_code = self.f:read(3)
    if app_ip == "NETSCAPE" then
        self.f:seek("cur", 2) -- always 0x03, 0x01
        self.loop = read_num(self.f)
        self.f:seek("cur", 1) -- end-of-block
    else
        self:discard_sub_blocks()
    end
end

function GIFin:read_ext()
    local label = bio.read_byte(self.f)
    if label == 0xF9 then
        self:read_graphic_control_ext()
    elseif label == 0xFF then
        self:read_application_ext()
    else
        error(("unknown extension: %02X"):format(label))
    end
end

function GIFin:read_image()
    local x, y = read_num(self.f), read_num(self.f)
    local w, h = read_num(self.f), read_num(self.f)
    local fisrz = bio.read_byte(self.f)
    local has_lct = band(rshift(fisrz, 7), 1) == 1
    --~ assert(not has_lct, "unsupported GIF feature: Local Color Table")
    local interlace = band(rshift(fisrz, 6), 1) == 1
    assert(not interlace, "unsupported GIF feature: Interlaced Frame")
    local d = band(fisrz, 7) + 1
    local lct = has_lct and self:read_color_table(d) or {}
    d = has_lct and d or self.d
    lzw.decode(self.f, d, self.surf, x, y, w, h) -- IP (Appendix F)
end

function GIFin:get_frame()
    local sep = self.f:read(1)
    while sep ~= "," do
        if sep == ";" then
            return 0
        elseif sep == "!" then
            self:read_ext()
        else
            return -1
        end
        sep = self.f:read(1)
    end
    if self:read_image() == -1 then
        return -1
    end
    return 1
end

function GIFin:close()
    self.f:close()
end

return {new_gif=new_gif, open_gif=open_gif}
