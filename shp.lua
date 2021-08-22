local ffi = require "ffi"
local bit = require "bit"

local function rtrim(s, c)
    local i = #s
    while s:sub(i, i) == c do
        i = i - 1
    end
    return s:sub(1, i)
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

local SF = {}
SF.__index = SF

function SF:read_dbf()
    local fp = io.open(self.path .. ".dbf", "rb")
    local version = bit.band(read_byte(fp), 0x07)
    if version ~= 3 then
        error("only DBF version 5 is supported")
    end
    self.year = 1900 + read_byte(fp)
    self.month = read_byte(fp)
    self.day = read_byte(fp)
    self.nrecs = read_leu32(fp)
    fp:seek("cur", 24)
    local reclen = 0
    local fields = {}
    local byte = read_byte(fp)
    while byte ~= 0x0D do
        local field_name = rtrim(string.char(byte) .. fp:read(10), "\000")
        local field_type = fp:read(1)
        fp:seek("cur", 4)
        local field_length = read_byte(fp)
        reclen = reclen + field_length
        local field_dec_count = read_byte(fp)
        local field = {
          name=field_name,
          type=field_type,
          length=field_length,
          dec_count=field_dec_count
        }
        table.insert(fields, field)
        fp:seek("cur", 14)
        byte = read_byte(fp)
    end
    local tab = {}
    for i = 1, self.nrecs do
        if fp:read(1) == "*" then
            fp:seek("cur", reclen)
        else
            local row = {}
            for j = 1, #fields do
                local field = fields[j]
                local cell = rtrim(fp:read(field.length), " ")
                if field.type == "F" or field.type == "N" then
                    cell = tonumber(cell)
                end
                table.insert(row, cell)
            end
            table.insert(tab, row)
        end
    end
    self.fields = fields
    self.tab = tab
    io.close(fp)
end

function SF:search(field_name, value)
    local col
    for i = 1, #self.fields do
        if self.fields[i].name == field_name then
            col = i
            break
        end
    end
    if col ~= nil then
        for i = 1, self.nrecs do
            if self.tab[i][col] == value then
                return i
            end
        end
    end
end

function SF:tab2csv(sep, fp)
    -- TODO: refactor to use table.concat(str_list, sep)
    sep = sep or ":"
    fp = fp or io.output()
    for i = 1, #self.fields do
        if i > 1 then
            fp:write(sep)
        end
        fp:write(self.fields[i].name)
    end
    fp:write("\n")
    for i = 1, #self.tab do
        for j = 1, #self.fields do
            if j > 1 then
                fp:write(sep)
            end
            local cell = self.tab[i][j]
            fp:write(cell)
        end
        fp:write("\n")
    end
end

local shape_name = {
    [ 0] = "null",          [31] = "multipatch",
    [ 1] = "point",   [ 3] = "polyline",   [ 5] = "polygon",   [ 8] = "multipoint",
    [11] = "point-z", [13] = "polyline-z", [15] = "polygon-z", [18] = "multipoint-z",
    [21] = "point-m", [23] = "polyline-m", [25] = "polygon-m", [28] = "multipoint-m",
}

local function startswith(s1, s2)
    return s1:sub(1, #s2) == s2
end

local function read_bbox(fp)
    local bbox = {}
    bbox.xmin = read_led64(fp)
    bbox.ymin = read_led64(fp)
    bbox.xmax = read_led64(fp)
    bbox.ymax = read_led64(fp)
    return bbox
end

-- SHX and SHP share the same header structure!
local function read_sf_header(fp)
    local file_code = read_bei32(fp)
    if file_code ~= 9994 then
        error("does not seem to be a shapefile (invalid FileCode)")
    end
    fp:seek("cur", 20) -- unused, always all-zero
    local file_len = read_bei32(fp)
    local version = read_lei32(fp)
    if version ~= 1000 then
        error("invalid shapefile version")
    end
    local header = {}
    header.shape = shape_name[read_lei32(fp)]
    header.bbox = read_bbox(fp)
    header.zmin = read_led64(fp)
    header.zmax = read_led64(fp)
    header.mmin = read_led64(fp)
    header.mmax = read_led64(fp)
    return header
end

function SF:read_shx()
    local fp = io.open(self.path .. ".shx", "rb")
    self.header = read_sf_header(fp)
    self.index = {}
    for i = 1, self.nrecs do
        local offset = read_bei32(fp)
        local length = read_bei32(fp)
        table.insert(self.index, {offset=offset, length=length})
    end
    io.close(fp)
end

function SF:read_record_header(index)
    local fp = self.fp
    fp:seek("set", self.index[index].offset * 2)
    local num = read_bei32(fp)
    local len = read_bei32(fp)
    local shape = shape_name[read_lei32(fp)]
    return num, len, shape
end

function SF:read_polygons(index)
    assert(startswith(self.header.shape, "polygon"), "type mismatch")
    local fp = self.fp
    local num, len, shape = self:read_record_header(index)
    if shape == "null" then
        return nil
    end
    local bbox = read_bbox(fp)
    local nparts = read_lei32(fp)
    --~ print(nparts)
    local npoints = read_lei32(fp)
    local total = read_lei32(fp) -- first index is always zero?
    local lengths = {}
    for i = 2, nparts do
        local index = read_lei32(fp)
        table.insert(lengths, index - total)
        total = index
    end
    table.insert(lengths, npoints - total)
    local i = 0
    return bbox, lengths, function()
        i = i + 1
        if i <= #lengths then
            local j = 0
            local length = lengths[i]
            return function()
                j = j + 1
                if j <= length then
                    local x = read_led64(fp)
                    local y = read_led64(fp)
                    return {x, y}
                end
            end
        end
    end
end

function SF:close()
    io.close(self.fp)
end

local function open_shapefile(path)
    local self = setmetatable({path=path}, SF)
    self:read_dbf()
    self:read_shx()
    self.fp = io.open(path .. ".shp", "rb")
    return self
end

return {open_shapefile=open_shapefile}
