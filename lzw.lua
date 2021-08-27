local ffi = require "ffi"
local bit = require "bit"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

-- == Encoder ==

local BUFout = {}
BUFout.__index = BUFout

local function new_buffer(f)
    local self = setmetatable({f=f, offset=0, partial=0}, BUFout)
    self.buf = ffi.new("char[255]")
    return self
end

function BUFout:put_key(key, size)
    local offset, partial = self.offset, self.partial
    local f, buf = self.f, self.buf
    local byte_offset, bit_offset = math.floor(offset / 8), offset % 8
    partial = bor(partial, lshift(key, bit_offset))
    local bits_to_write = bit_offset + size
    while bits_to_write >= 8 do
        buf[byte_offset] = band(partial, 0xFF)
        byte_offset = byte_offset + 1
        if byte_offset == 0xFF then -- flush
            f:write(string.char(0xFF))
            f:write(ffi.string(buf, 0xFF))
            byte_offset = 0
        end
        partial = rshift(partial, 8)
        bits_to_write = bits_to_write - 8
    end
    self.offset = (offset + size) % (0xFF * 8)
    self.partial = partial
end

function BUFout:end_key()
    local offset, partial = self.offset, self.partial
    local f, buf = self.f, self.buf
    local byte_offset = math.floor(offset / 8)
    if offset % 8 ~= 0 then
        buf[byte_offset] = band(partial, 0xFF)
        byte_offset = byte_offset + 1
    end
    if byte_offset > 0 then
        f:write(string.char(byte_offset))
        f:write(ffi.string(buf, byte_offset))
    end
    f:write(string.char(0))
    self.offset, self.partial = 0, 0
end


local function new_trie(degree)
    local children = {}
    for key = 0, degree-1 do
        children[key] = {key=key, children={}}
    end
    return {children=children}
end

local function encode(f, d, s, x, y, w, h)
    local buf = new_buffer(f)
    local code_size = math.max(d, 2)
    f:write(string.char(code_size))
    local degree = 2 ^ code_size
    local root = new_trie(degree)
    local clear, stop = degree, degree + 1
    local nkeys = degree + 2 -- skip clear code and stop code
    local node = root
    local key_size = code_size + 1
    buf:put_key(clear, key_size)
    for j = y, y+h-1 do
        for i = x, x+w-1 do
            local index = band(s:pget(i, j), degree-1)
            local child = node.children[index]
            if child ~= nil then
                node = child
            else
                buf:put_key(node.key, key_size)
                if nkeys < 0x1000 then
                    if nkeys == 2 ^ key_size then
                        key_size = key_size + 1
                    end
                    node.children[index] = {key=nkeys, children={}}
                    nkeys = nkeys + 1
                else
                    buf:put_key(clear, key_size)
                    root = new_trie(degree)
                    node = root
                    nkeys = degree + 2
                    key_size = code_size + 1
                end
                node = root.children[index]
            end
        end
    end
    buf:put_key(node.key, key_size)
    buf:put_key(stop, key_size)
    buf:end_key()
end

-- == Decoder ==

local function decode(f, d, s, x, y, w, h)
    local code_size = f:read(1):byte(1)
    assert(code_size == math.max(d, 2), "invalid code size")
    repeat
        local size = f:read(1):byte(1)
        f:seek("cur", size)
    until size == 0
end

return {encode=encode, decode=decode}
