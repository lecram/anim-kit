local ffi = require "ffi"
local bit = require "bit"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

-- == Encoder ==

local BUFout = {}
BUFout.__index = BUFout

local function new_buffer_out(f)
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
    local buf = new_buffer_out(f)
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

local BUFin = {}
BUFin.__index = BUFin

local function new_buffer_in(f)
    local self = setmetatable({}, BUFin)
    self.f = f      -- already opened file, read mode
    self.s = 0      -- number of bytes available in block
    self.b = 0      -- value of last byte read
    self.n = 0      -- number of bits available in self.b
    return self
end

function BUFin:get_key(size)
    local key = 0
    for i = 1, size do
        if self.s == 0 then
            self.s = self.f:read(1):byte(1)
            assert(self.s > 0, "unexpected end-of-block")
        end
        if self.n == 0 then
            self.b = self.f:read(1):byte(1)
            self.n = 8
            self.s = self.s - 1
        end
        key = bor(key, lshift(band(rshift(self.b, 8-self.n), 1), i-1))
        self.n = self.n - 1
    end
    return key
end

local CodeTable = {}
CodeTable.__index = CodeTable

local function new_code_table(key_size)
    local self = setmetatable({}, CodeTable)
    self.len = lshift(1, key_size)
    self.tab = {}
    for key = 0, self.len+1 do
        self.tab[key] = {length=1, prefix=0xFFF, suffix=key}
    end
    self.len = self.len + 2 -- clear & stop
    return self
end

function CodeTable:add_entry(length, prefix, suffix)
    self.tab[self.len] = {length=length, prefix=prefix, suffix=suffix}
    self.len = self.len + 1
    if band(self.len, self.len-1) == 0 then
        return 1
    end
    return 0
end

local function decode(f, d, s, fx, fy, w, h)
    local key_size = f:read(1):byte(1)
    assert(key_size == math.max(d, 2), "invalid code size")
    local buf = new_buffer_in(f)
    local clear = lshift(key_size, 1)
    local stop = clear + 1
    key_size = key_size + 1
    local init_key_size = key_size
    local key = buf:get_key(key_size)
    assert(key == clear, "expected clear code, got "..key)
    local code_table, table_is_full, entry, str_len, ret
    local frm_off = 0 -- pixels read
    local frm_size = w * h
    while frm_off < frm_size do
        if key == clear then
            key_size = init_key_size
            code_table = new_code_table(key_size-1)
            table_is_full = false
        elseif not table_is_full then
            ret = code_table:add_entry(str_len+1, key, entry.suffix)
            if code_table.len == 0x1000 then
                ret = 0
                table_is_full = true
            end
        end
        key = buf:get_key(key_size)
        if key ~= clear then
            if key == stop or key == 0x1000 then break end
            if ret == 1 then key_size = key_size + 1 end
            entry = code_table.tab[key]
            str_len = entry.length
            for i = 1, str_len do
                local p = frm_off + entry.length - 1
                local x = p % w
                local y = math.floor(p / w)
                s:pset(fx+x, fy+y, entry.suffix)
                if entry.prefix == 0xFFF then
                    break
                else
                    entry = code_table.tab[entry.prefix]
                end
            end
            frm_off = frm_off + str_len
            if key < code_table.len-1 and not table_is_full then
                code_table.tab[code_table.len-1].suffix = entry.suffix
            end
        end
    end
    while buf.s > 0 do
        f:seek("cur", buf.s)
        buf.s = f:read(1):byte(1)
    end
end

return {encode=encode, decode=decode}
