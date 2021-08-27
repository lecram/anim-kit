-- binary input/output

local ffi = require "ffi"
local bit = require "bit"

-- ZigZag encoding to map signed to unsigned integers
local function s2u(n)
    return bit.bxor(bit.lshift(n, 1), bit.arshift(n, 31))
end

-- ZigZag decoding to map unsigned back to signed integers
local function u2s(n)
    return bit.bxor(bit.rshift(n, 1), -bit.band(n, 1))
end

local function read_byte(fp)
    return fp:read(1):byte(1)
end

local function read_leu16(fp)
    return read_byte(fp) + bit.lshift(read_byte(fp), 8)
end

local function read_leu32(fp)
    return read_leu16(fp) + bit.lshift(read_leu16(fp), 16)
end

local function read_beu16(fp)
    return bit.lshift(read_byte(fp), 8) + read_byte(fp)
end

local function read_beu32(fp)
    return bit.lshift(read_beu16(fp), 16) + read_beu16(fp)
end

local function signed(u, nbits)
    local p = 2^(nbits-1)
    if u >= p then u = u - p - p end
    return u
end

local function read_lei16(fp)
    return signed(read_leu16(fp), 16)
end

local function read_lei32(fp)
    return signed(read_leu32(fp), 32)
end

local function read_bei16(fp)
    return signed(read_beu16(fp), 16)
end

local function read_bei32(fp)
    return signed(read_beu32(fp), 32)
end

local function read_led64(fp)
    return ffi.cast("double *", ffi.new("char[8]", fp:read(8)))[0]
end

local function write_byte(fp, n)
    fp:write(string.char(n))
end

local function write_beu16(fp, n)
    write_byte(fp, bit.rshift(n, 8))
    write_byte(fp, bit.band(n, 0xFF))
end

local function write_beu32(fp, n)
    write_beu16(fp, bit.rshift(n, 16))
    write_beu16(fp, bit.band(n, 0xFFFF))
end

local function write_lei16(fp, n)
    write_byte(fp, bit.band(n, 0xFF))
    write_byte(fp, bit.rshift(n, 8))
end

local function write_bei16(fp, n)
    if n < 0 then
        n = n + 0x10000
    end
    write_beu16(fp, n)
end

local RiceR = {}
RiceR.__index = RiceR

function RiceR:get_bit()
    if self.n == 0 then
        self.b = read_byte(self.fp)
        self.n = 8
    end
    self.n = self.n - 1
    return bit.band(bit.rshift(self.b, self.n), 1)
end

function RiceR:get_unsigned()
    local q = 0
    while self:get_bit() == 1 do
        q = q + 1
    end
    local r = 0
    for i = 1, self.k do
        r = bit.bor(bit.lshift(r, 1), self:get_bit())
    end
    return bit.bor(bit.lshift(q, self.k), r)
end

function RiceR:get_signed()
    return u2s(self:get_unsigned())
end

local function rice_r(fp, k)
    local self = setmetatable({}, RiceR)
    self.fp = fp    -- already opened file, read mode
    self.k = k or 0 -- rice parameter
    self.b = 0      -- value of last byte read
    self.n = 0      -- number of bits available in self.b
    return self
end

local RiceW = {}
RiceW.__index = RiceW

function RiceW:put_bit(b)
    self.n = self.n - 1
    self.b = bit.bor(self.b, bit.lshift(b, self.n))
    if self.n == 0 then
        self:flush()
    end
end

function RiceW:flush()
    if self.n ~= 8 then
        write_byte(self.fp, self.b)
        self.b = 0
        self.n = 8
    end
end

function RiceW:put_unsigned(n)
    for i = 1, bit.rshift(n, self.k) do
        self:put_bit(1)
    end
    self:put_bit(0)
    for i = self.k-1, 0, -1 do
        self:put_bit(bit.band(bit.rshift(n, i), 1))
    end
end

function RiceW:put_signed(n)
    self:put_unsigned(s2u(n))
end

local function rice_w(fp, k)
    local self = setmetatable({}, RiceW)
    self.fp = fp    -- already opened file, write mode
    self.k = k or 0 -- rice parameter
    self.b = 0      -- value of next byte to write
    self.n = 8      -- number of bits available in self.b
    return self
end

return {
    read_byte=read_byte, read_leu16=read_leu16, read_leu32=read_leu32,
    read_beu16=read_beu16, read_beu32=read_beu32, read_lei16=read_lei16,
    read_lei32=read_lei32, read_bei16=read_bei16, read_bei32=read_bei32,
    read_led64=read_led64, write_byte=write_byte, write_beu16=write_beu16,
    write_beu32=write_beu32, write_lei16=write_lei16, write_bei16=write_bei16,
    rice_r=rice_r, rice_w=rice_w
}
