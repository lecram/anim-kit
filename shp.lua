local bit = require "bit"

local util = require "util"
local bio = require "bio"

local SF = {}
SF.__index = SF

function SF:read_dbf()
    local fp = io.open(self.path .. ".dbf", "rb")
    local version = bit.band(bio.read_byte(fp), 0x07)
    if version ~= 3 then
        error("only DBF version 5 is supported")
    end
    self.year = 1900 + bio.read_byte(fp)
    self.month = bio.read_byte(fp)
    self.day = bio.read_byte(fp)
    self.nrecs = bio.read_leu32(fp)
    fp:seek("cur", 24)
    local reclen = 0
    local fields = {}
    local byte = bio.read_byte(fp)
    while byte ~= 0x0D do
        local field_name = util.rtrim(string.char(byte) .. fp:read(10), "\000")
        local field_type = fp:read(1)
        fp:seek("cur", 4)
        local field_length = bio.read_byte(fp)
        reclen = reclen + field_length
        local field_dec_count = bio.read_byte(fp)
        local field = {
          name=field_name,
          type=field_type,
          length=field_length,
          dec_count=field_dec_count
        }
        table.insert(fields, field)
        fp:seek("cur", 14)
        byte = bio.read_byte(fp)
    end
    local tab = {}
    for i = 1, self.nrecs do
        if fp:read(1) == "*" then
            fp:seek("cur", reclen)
        else
            local row = {}
            for j = 1, #fields do
                local field = fields[j]
                local cell = util.rtrim(fp:read(field.length), " ")
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

function SF:print_summary(n)
    n = n or 5
    local sep = ":"
    for i = 1, #self.fields do
        local field = self.fields[i]
        local row = {field.name}
        for j = 1, n do
            table.insert(row, self.tab[j][i])
        end
        print(table.concat(row, sep))
    end
    print("records".. sep .. #self.tab)
    print("shape".. sep .. self.header.shape)
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

local function read_bbox(fp)
    local bbox = {}
    bbox.xmin = bio.read_led64(fp)
    bbox.ymin = bio.read_led64(fp)
    bbox.xmax = bio.read_led64(fp)
    bbox.ymax = bio.read_led64(fp)
    return bbox
end

-- SHX and SHP share the same header structure!
local function read_sf_header(fp)
    local file_code = bio.read_bei32(fp)
    if file_code ~= 9994 then
        error("does not seem to be a shapefile (invalid FileCode)")
    end
    fp:seek("cur", 20) -- unused, always all-zero
    local file_len = bio.read_bei32(fp)
    local version = bio.read_lei32(fp)
    if version ~= 1000 then
        error("invalid shapefile version")
    end
    local header = {}
    header.shape = shape_name[bio.read_lei32(fp)]
    header.bbox = read_bbox(fp)
    header.zmin = bio.read_led64(fp)
    header.zmax = bio.read_led64(fp)
    header.mmin = bio.read_led64(fp)
    header.mmax = bio.read_led64(fp)
    return header
end

function SF:read_shx()
    local fp = io.open(self.path .. ".shx", "rb")
    self.header = read_sf_header(fp)
    self.index = {}
    for i = 1, self.nrecs do
        local offset = bio.read_bei32(fp)
        local length = bio.read_bei32(fp)
        table.insert(self.index, {offset=offset, length=length})
    end
    io.close(fp)
end

function SF:read_record_header(index)
    local fp = self.fp
    fp:seek("set", self.index[index].offset * 2)
    local num = bio.read_bei32(fp)
    local len = bio.read_bei32(fp)
    local shape = shape_name[bio.read_lei32(fp)]
    return num, len, shape
end

function SF:read_bbox(index)
    local shape_name = self.header.shape
    assert(
        util.startswith(shape_name, "polyline") or
        util.startswith(shape_name, "polygon") or
        util.startswith(shape_name, "multipoint"),
        ("%s shape doesn't have bbox"):format(shape_name)
    )
    local num, len, shape = self:read_record_header(index)
    if shape == "null" then
        return nil
    end
    return read_bbox(self.fp)
end

function SF:read_polygons(index, proj)
    assert(util.startswith(self.header.shape, "polygon"), "type mismatch")
    local fp = self.fp
    local num, len, shape = self:read_record_header(index)
    if shape == "null" then
        return nil
    end
    local bbox = read_bbox(fp)
    local nparts = bio.read_lei32(fp)
    --~ print(nparts)
    local npoints = bio.read_lei32(fp)
    local total = bio.read_lei32(fp) -- first index is always zero?
    local lengths = {}
    for i = 2, nparts do
        local index = bio.read_lei32(fp)
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
                    local x = bio.read_led64(fp)
                    local y = bio.read_led64(fp)
                    if proj ~= nil then
                        x, y = proj:map(x, y)
                    end
                    return {x, y}
                end
            end
        end
    end
end

function SF:close()
    io.close(self.fp)
end

function SF:save_cache(fname, k, proj, scale, filter)
    local indices = {}
    for i = 1, #self.tab do
        local row = self.tab[i]
        local rec = {}
        for j = 1, #self.fields do
            rec[self.fields[j].name] = row[j]
        end
        local key = filter(rec)
        if key ~= nil then
            table.insert(indices, {i, key:sub(1, 16)})
        end
    end
    local cache = io.open(fname, "w")
    bio.write_beu32(cache, util.round(1000 / scale))
    bio.write_byte(cache, k)
    for i = 1, #indices do
        local index, key = unpack(indices[i])
        cache:write(key, string.rep("\0", 20 - #key))
    end
    cache:write(string.rep("\0", 20)) -- end list of entries
    for i = 1, #indices do
        local index, key = unpack(indices[i])
        local offset = cache:seek()
        cache:seek("set", i * 20 + 1)
        bio.write_beu32(cache, offset)
        cache:seek("set", offset)
        local bb, lens, polys = self:read_polygons(index)
        bio.write_beu16(cache, #lens)
        for poly in polys do
            local ox, oy = unpack(poly())
            ox, oy = proj:map(ox, oy)
            ox, oy = util.round(ox * scale), util.round(oy * scale)
            bio.write_bei16(cache, ox)
            bio.write_bei16(cache, oy)
            local rice = bio.rice_w(cache, k)
            for point in poly do
                local x, y = unpack(point)
                x, y = proj:map(x, y)
                x, y = util.round(x * scale), util.round(y * scale)
                local dx, dy = x-ox, y-oy
                if dx ~= 0 or dy ~= 0 then
                    rice:put_signed(dx)
                    rice:put_signed(dy)
                    ox, oy = x, y
                end
            end
            rice:put_signed(0)
            rice:put_signed(0)
            rice:flush()
        end
    end
    cache:close()
end

local function open_shapefile(path)
    local self = setmetatable({path=path}, SF)
    self:read_dbf()
    self:read_shx()
    self.fp = io.open(path .. ".shp", "rb")
    return self
end

local Cache = {}
Cache.__index = Cache

function Cache:keys()
    local cache = self.fp
    local offset = 5
    return function()
        cache:seek("set", offset)
        offset = offset + 20
        local ckey = cache:read(16)
        if ckey:byte() ~= 0 then
            return ckey:sub(1, ckey:find("\0")-1)
        end
    end
end

function Cache:get_polys(key)
    local cache = self.fp
    cache:seek("set", 5)
    local ckey = cache:read(16)
    local offset = -1
    while ckey:byte() ~= 0 do
        if ckey:sub(1, ckey:find("\0")-1) == key then
            offset = bio.read_beu32(cache)
            break
        end
        cache:seek("cur", 4)
        ckey = cache:read(16)
    end
    assert(offset > 0, ("key '%s' not found in cache"):format(key))
    cache:seek("set", offset)
    local npolys = bio.read_beu16(cache)
    return function()
        if npolys > 0 then
            npolys = npolys - 1
            local ox, oy = bio.read_bei16(cache), bio.read_bei16(cache)
            local rice = bio.rice_r(cache, self.k)
            local x, y = 0, 0
            return function()
                if x ~= ox or y ~= oy then
                    x, y = ox, oy
                    local dx, dy = rice:get_signed(), rice:get_signed()
                    ox, oy = ox+dx, oy+dy
                    return {x * self.s, y * self.s}
                end
            end
        end
    end
end

local function load_cache(fname)
    local self = setmetatable({}, Cache)
    self.fp = io.open(fname, "r")
    self.s = bio.read_beu32(self.fp) / 1000
    self.k = bio.read_byte(self.fp)
    return self
end

return {open_shapefile=open_shapefile, load_cache=load_cache}
