-- binary input/output

local ffi = require "ffi"
local bit = require "bit"

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

local function write_beu16(fp, n)
    fp:write(string.char(bit.rshift(n, 8), bit.band(n, 0xFF)))
end

local function write_beu32(fp, n)
    write_beu16(fp, bit.rshift(n, 16))
    write_beu16(fp, bit.band(n, 0xFFFF))
end

local function write_bei16(fp, n)
    if n < 0 then
        n = n + 0x10000
    end
    write_beu16(fp, n)
end

return {
    read_byte=read_byte, read_leu16=read_leu16, read_leu32=read_leu32,
    read_beu16=read_beu16, read_beu32=read_beu32, read_lei16=read_lei16,
    read_lei32=read_lei32, read_bei16=read_bei16, read_bei32=read_bei32,
    read_led64=read_led64, write_beu16=write_beu16, write_beu32=write_beu32,
    write_bei16=write_bei16
}
