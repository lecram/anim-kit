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

local function read_leuvlp(fp)
    local x, y = 0, 0
    local s = 0
    repeat
        local byte = fp:read(1):byte(1)
        l, r = bit.band(bit.rshift(byte, 4), 0x07), bit.band(byte, 0x07)
        x = bit.bor(bit.lshift(l, s), x)
        y = bit.bor(bit.lshift(r, s), y)
        s = s + 3
    until bit.band(byte, 0x88) == 0
    return x, y
end

local function read_leivlp(fp)
    local x, y = read_leuvlp(fp)
    if bit.band(x, 1) == 1 then x = (x+1)/2 elseif x ~= 0 then x = -(x/2) end
    if bit.band(y, 1) == 1 then y = (y+1)/2 elseif y ~= 0 then y = -(y/2) end
    return x, y
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

local function write_leuvlp(fp, x, y)
    repeat
        local byte = bit.bor(bit.lshift(bit.band(x, 0x07), 4), bit.band(y, 0x07))
        x, y = bit.rshift(x, 3), bit.rshift(y, 3)
        if x ~= 0 or y ~= 0 then
            byte = bit.bor(byte, 0x88)
        end
        fp:write(string.char(byte))
    until x == 0 and y == 0
end

local function write_leivlp(fp, x, y)
    if x < 0 then x = -2*x elseif x > 0 then x = x*2-1 end
    if y < 0 then y = -2*y elseif y > 0 then y = y*2-1 end
    write_leuvlp(fp, x, y)
end

return {
    read_byte=read_byte, read_leu16=read_leu16, read_leu32=read_leu32,
    read_beu16=read_beu16, read_beu32=read_beu32, read_lei16=read_lei16,
    read_lei32=read_lei32, read_bei16=read_bei16, read_bei32=read_bei32,
    read_led64=read_led64, read_leuvlp=read_leuvlp, read_leivlp=read_leivlp,
    write_beu16=write_beu16, write_beu32=write_beu32, write_bei16=write_bei16,
    write_leuvlp=write_leuvlp, write_leivlp=write_leivlp
}
