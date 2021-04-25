local bit = require "bit"

local aff = require "aff"

local bnot = bit.bnot
local bor, band = bit.bor, bit.band
local lshift, rshift =  bit.lshift,  bit.rshift

local function log(s)
    io.stderr:write(s .. "\n")
end

local function utf8to32(utf8str)
    assert(type(utf8str) == "string")
    local res, seq, val = {}, 0, nil
    for i = 1, #utf8str do
        local c = string.byte(utf8str, i)
        if seq == 0 then
            table.insert(res, val)
            seq = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or
                  c < 0xF8 and 4 or --c < 0xFC and 5 or c < 0xFE and 6 or
                  error("invalid UTF-8 character sequence")
            val = band(c, 2^(8-seq) - 1)
        else
            val = bor(lshift(val, 6), band(c, 0x3F))
        end
        seq = seq - 1
    end
    table.insert(res, val)
    return res
end

-- Note: TrueType uses big endian for everything.

local function uint(s)
    local x = 0
    for i = 1, #s do
        x = x * 256 + s:byte(i)
    end
    return x
end

local function int(s)
    local x = uint(s)
    local p = 2^(#s*8)
    if x >= p/2 then x = x - p end
    return x
end

local function str(x)
    local s = ""
    while x > 0 do
        s = string.char(x % 256) .. s
        x = math.floor(x / 256)
    end
    return s
end

local Face = {}
Face.__index = Face

function Face:str(n)    return self.fp:read(n) end
function Face:uint8()   return uint(self.fp:read(1)) end
function Face:uint16()  return uint(self.fp:read(2)) end
function Face:uint32()  return uint(self.fp:read(4)) end
function Face:uint64()  return uint(self.fp:read(8)) end
function Face:int8()    return  int(self.fp:read(1)) end
function Face:int16()   return  int(self.fp:read(2)) end
function Face:int32()   return  int(self.fp:read(4)) end
function Face:int64()   return  int(self.fp:read(8)) end

function Face:goto(tag, offset)
    self.fp:seek("set", self.dir[tag].offset + (offset or 0))
end

function Face:getpos()
    return self.fp:seek()
end

function Face:setpos(pos)
    self.fp:seek("set", pos)
end

function Face:offset()
    local scaler_type = self:uint32()
    assert(scaler_type == 0x74727565 or scaler_type == 0x00010000,
        ("invalid scaler type for TrueType: 0x%08X"):format(scaler_type))
    local num_tables = self:uint16()
    --  The entries for search_range, entry_selector and range_shift are used to
    -- facilitate quick binary searches of the table directory. Unless a font 
    -- has a large number of tables, a sequential search will be fast enough.
    local search_range = self:uint16()
    local entry_selector = self:uint16()
    local range_shift = self:uint16()
    self.num_tables = num_tables
end

function Face:directory()
    local dir = {}
    for i = 1, self.num_tables do
        local tag = self:str(4)
        local checksum = self:uint32()
        local offset = self:uint32()
        local length = self:uint32()
        -- TODO: verify checksums
        dir[tag] = {checksum=checksum, offset=offset, length=length}
    end
    self.dir = dir
end

function Face:head()
    self:goto("head")
    local version = self:uint32()
    assert(version == 0x00010000, ("invalid version: 0x%08X"):format(version))
    local revision = self:uint32()
    local checksum_adj = self:uint32()
    local magic = self:uint32()
    assert(magic == 0x5F0F3CF5, ("invalid magic: 0x%08X"):format(magic))
    local flags = self:uint16()
    self.units_per_em = self:uint16()
    local created = self:int64()
    local modified = self:int64()
    local xmin = self:int16()
    local ymin = self:int16()
    local xmax = self:int16()
    local ymax = self:int16()
    local mac_style = self:uint16()
    local lowest_rec_ppem = self:uint16()
    local direction_hint = self:int16()
    self.index_to_loc_fmt = self:int16()
    local glyph_data_fmt = self:int16()
end

function Face:maxp()
    self:goto("maxp")
    local version = self:uint32()
    if version == 0x00005000 then
        self.num_glyphs = self:uint16()
    elseif version == 0x00010000 then
        self.num_glyphs = self:uint16()
        local max_points = self:uint16()
        local max_contours = self:uint16()
        local max_composite_points = self:uint16()
        local max_composite_contours = self:uint16()
        local max_zones = self:uint16()
        local max_twilight_points = self:uint16()
        local max_storage = self:uint16()
        local max_function_defs = self:uint16()
        local max_instruction_defs = self:uint16()
        local max_stack_elements = self:uint16()
        local max_size_of_instructions = self:uint16()
        local max_component_elements = self:uint16()
        local max_component_depth = self:uint16()
    else
        error(("invalid maxp version: 0x%08X"):format(version))
    end
end

function Face:cmap()
    self:goto("cmap")
    local version = self:uint16()
    assert(version == 0, ("invalid cmap version: %d"):format(version))
    local num_subtables = self:uint16()
    local encoding, suboffset
    local ok = false
    for i = 1, num_subtables do
        local platform_id = self:uint16()
        encoding = self:uint16()
        suboffset = self:uint32()
        if platform_id == 0 then        -- platform == Unicode
            ok = true
            break
        elseif platform_id == 3 then    -- platform == Microsoft
            if encoding == 10 or encoding == 1 then
                ok = true
                break
            end
        end
    end
    if not ok then
        error(("could not find Unicode cmap in %d subtables"):format(num_subtables))
    end
    self:goto("cmap", suboffset)
    self:subcmap()
end

function Face:subcmap()
    local format = self:uint16()
    local segs = {}
    local gia = {}
    if format == 4 then
        local length = self:uint16()
        local language = self:uint16()
        assert(language == 0, ("invalid subcmap language: %d"):format(language))
        local seg_count = self:uint16() / 2
        local search_range = self:uint16()
        local entry_selector = self:uint16()
        local range_shift = self:uint16()
        for i = 1, seg_count do
            segs[i] = {end_code=self:uint16()}
        end
        local last = segs[seg_count].end_code
        assert(last == 0xFFFF, ("invalid subcmap last end code: %d"):format(last))
        local pad = self:uint16()
        assert(pad == 0, ("invalid subcmap reserved pad: %d"):format(pad))
        for i = 1, seg_count do
            segs[i].start_code = self:uint16()
        end
        for i = 1, seg_count do
            segs[i].id_delta = self:uint16()
        end
        for i = 1, seg_count do
            segs[i].id_range_offset = self:uint16()
        end
        local gia_len = (length - (16+8*seg_count)) / 2
        for i = 1, gia_len do
            gia[i] = self:uint16()
        end
    -- TODO: support other formats, specially 6 and 12
    else
        error(("unsupported subcmap format: %d"):format(format))
    end
    self.segs, self.gia = segs, gia
end

function Face:os2()
    self:goto("OS/2")
    local version = self:uint16()
    assert(version >= 2, ("invalid OS/2 version: %u"):format(version))
    self.avg_char_width = self:int16()
    self.weight_class = self:uint16()
    self.width_class = self:uint16()
    self.fp:seek("cur", 78)
    self.x_height = self:int16()
    self.cap_height = self:int16()
    self.default_char = self:uint16()
    self.break_char = self:uint16()
end

function Face:hhea()
    self:goto("hhea")
    local versionH = self:uint16()
    local versionL = self:uint16()
    assert(versionH == 1 and versionL == 0,
        ("invalid hhea version: %d.%d"):format(versionH, versionL))
    self.ascent  = self:int16()
    self.descent = self:int16()
    local line_gap = self:int16()
    local advance_width_max = self:uint16()
    local min_left_side_bearing  = self:int16()
    local min_right_side_bearing = self:int16()
    local x_max_extent = self:int16()
    local caret_slope_rise = self:int16()
    local caret_slope_run  = self:int16()
    local caret_offset     = self:int16()
    for i = 1, 4 do
        local reserved = self:uint16()
        assert(reserved == 0, "nonzero reserved field in hhea")
    end
    local metric_data_format = self:int16()
    assert(metric_data_format == 0,
        ("invalid metric data format: %d"):format(metric_data_format))
    self.nlong_hor_metrics = self:uint16()
end

function Face:hmetrics(id)
    local n = self.nlong_hor_metrics -- for readability of expressions below
    local advance, bearing
    if id < n then
        self:goto("hmtx", 4*id)
        advance = self:uint16()
        bearing = self:int16()
    else
        self:goto("hmtx", 4*(n-1))
        advance = self:uint16()
        self:goto("hmtx", 4*n+2*(id-n))
        bearing = self:int16()
    end
    return advance, bearing
end

function Face:kern()
    self:goto("kern")
    local version = self:uint16()
    assert(version == 0, ("invalid kern table version: %d"):format(version))
    local ntables = self:uint16()
    for i = 1, ntables do
        local version = self:uint16()
        local length = self:uint16()
        local format = self:uint8() -- usually 0
        local coverage = self:uint8()
        local horizontal   = band(coverage, 2^0) > 0 -- usually true
        local minimum      = band(coverage, 2^1) > 0 -- usually false (kerning)
        local cross_stream = band(coverage, 2^2) > 0 -- usually false (regular)
        local override     = band(coverage, 2^3) > 0 -- usually false (accumulate)
        assert(band(coverage, 0xF0) == 0, "invalid coverage bits set")
        if format == 0 then
            self.num_kernings = self:uint16()
            local search_range = self:uint16()
            local entry_selector = self:uint16()
            local range_shift = self:uint16()
            local kerning = {}
            for j = 1, self.num_kernings do
                -- glyph indices (left * 2^16 + right)
                local key  = self:uint32()
                -- kerning value
                local value = self:int16()
                kerning[key] = value
            end
            self.kerning = kerning
        else
            log(("unsupported kerning table format: %d"):format(format))
        end
    end
end

function Face:get_kerning(left_id, right_id)
    return self.kerning[left_id * 2^16 + right_id] or 0
end

-- Convert a character code to its glyph id.
function Face:char_index(code)
    local i = 1
    while code > self.segs[i].end_code do i = i + 1 end
    if self.segs[i].start_code > code then return 0 end
    local iro = self.segs[i].id_range_offset
    if iro == 0 then
        return (code + self.segs[i].id_delta) % 0x10000
    else
        local idx = iro + 2 * (code - self.segs[i].start_code)
        idx = idx - (#self.segs - i + 1) * 2
        local id = self.gia[idx/2+1]
        if id > 0 then
            id = (id + self.segs[i].id_delta) % 0x10000
        end
        return id
    end
end

-- helper for Face:glyph()
function Face:pack_outline(points, end_points)
    local outline = {}
    local h = self.cap_height
    local p, q
    local j = 1
    for i = 1, #end_points do
        local contour = {}
        while j <= end_points[i] do
            p = points[j]
            q = {p.x, h-p.y, p.on_curve}
            table.insert(contour, q)
            j = j + 1
        end
        table.insert(outline, contour)
    end
    return outline
end

function Face:glyph(id)
    local suboffset
    if self.index_to_loc_fmt == 0 then      -- short offsets
        self:goto("loca", 2*id)
        suboffset = self:uint16() * 2
    else                                    -- long offsets
        self:goto("loca", 4*id)
        suboffset = self:uint16()
    end
    self:goto("glyf", suboffset)
    local num_contours = self:int16()
    local xmin = self:int16()
    local ymin = self:int16()
    local xmax = self:int16()
    local ymax = self:int16()
    local points, end_points = {}, {}
    if num_contours > 0 then        -- simple glyph
        for i = 1, num_contours do
            end_points[i] = self:uint16() + 1
        end
        local num_points = end_points[#end_points]
        local instruction_length = self:uint16()
        local instructions = self:str(instruction_length)
        local i = 0
        while i < num_points do
            i = i + 1
            local flags = self:uint8()
            assert(flags < 64, "point flag with higher bits set")
            local point = {
                on_curve    = band(flags, 2^0) > 0,
                x_short     = band(flags, 2^1) > 0,
                y_short     = band(flags, 2^2) > 0,
                repeated    = band(flags, 2^3) > 0,
                x_sign_same = band(flags, 2^4) > 0,
                y_sign_same = band(flags, 2^5) > 0
            }
            points[i] = point
            if point.repeated then
                local repeats = self:uint8()
                for j = 1, repeats do
                    i = i + 1
                    points[i] = {
                        on_curve    = point.on_curve,
                        x_short     = point.x_short,
                        y_short     = point.y_short,
                        x_sign_same = point.x_sign_same,
                        y_sign_same = point.y_sign_same
                    }
                end
            end
        end
        local last_x, last_y = 0, 0
        for i = 1, #points do
            if points[i].x_short then
                local x = self:uint8()
                if not points[i].x_sign_same then x = -x end
                points[i].x = last_x + x
            else
                if not points[i].x_sign_same then
                    points[i].x = last_x + self:int16()
                else
                    points[i].x = last_x
                end
            end
            last_x = points[i].x
        end
        for i = 1, #points do
            if points[i].y_short then
                local y = self:uint8()
                if not points[i].y_sign_same then y = -y end
                points[i].y = last_y + y
            else
                if not points[i].y_sign_same then
                    points[i].y = last_y + self:int16()
                else
                    points[i].y = last_y
                end
            end
            last_y = points[i].y
        end
    elseif num_contours < 0 then    -- compound glyph
        local more = true
        while more do
            local flags = self:uint16()
            local args_are_words    = band(flags, 2^0x0) > 0
            local args_are_xy       = band(flags, 2^0x1) > 0
            local round_xy_to_grid  = band(flags, 2^0x2) > 0
            local regular_scale     = band(flags, 2^0x3) > 0
            local obsolete          = band(flags, 2^0x4) > 0
            more                    = band(flags, 2^0x5) > 0
            local irregular_scale   = band(flags, 2^0x6) > 0
            local two_by_two        = band(flags, 2^0x7) > 0
            local instructions      = band(flags, 2^0x8) > 0
            local use_my_metrics    = band(flags, 2^0x9) > 0
            local overlap           = band(flags, 2^0xA) > 0
            local scaled_offset     = band(flags, 2^0xB) > 0
            local unscaled_offset   = band(flags, 2^0xC) > 0
            if obsolete then
                log("warning: glyph component using obsolete flag")
            end
            local gid = self:uint16()
            local pos = self:getpos()
            local sub_points, sub_end_points = self:glyph(gid)
            self:setpos(pos)
            local e, f
            if args_are_xy then
                if args_are_words then
                    e = self:int16()
                    f = self:int16()
                else
                    e = self:int8()
                    f = self:int8()
                end
                if round_xy_to_grid then
                    log("warning: ignoring request to round component offset")
                end
            else
                local i, j
                if args_are_words then
                    i = self:uint16()
                    j = self:uint16()
                else
                    i = self:uint8()
                    j = self:uint8()
                end
                e = points[i].x - sub_points[j].x
                f = points[i].y - sub_points[j].y
            end
            local a, b, c, d = 1, 0, 0, 1
            if regular_scale then
                log("regular scale")
                a = self:int16() / 0x4000
                d = a
            elseif irregular_scale then
                log("irregular scale")
                a = self:int16() / 0x4000
                d = self:int16() / 0x4000
            elseif two_by_two then
                log("2x2 transformation")
                a = self:int16() / 0x4000
                b = self:int16() / 0x4000
                c = self:int16() / 0x4000
                d = self:int16() / 0x4000
            end
            local m = math.max(math.abs(a), math.abs(b))
            local n = math.max(math.abs(c), math.abs(d))
            if math.abs(math.abs(a)-math.abs(c)) <= 0x21/0x10000 then
                m = m * 2
            end
            if math.abs(math.abs(c)-math.abs(d)) <= 0x21/0x10000 then
                n = n * 2
            end
            for i, p in ipairs(sub_points) do
                points[#points+1] = {
                    x=m*(a*p.x/m + c*p.y/m + e),
                    y=n*(b*p.x/n + d*p.y/n + f),
                    on_curve=p.on_curve
                }
            end
            local offset = end_points[#end_points] or 0
            for i, e in ipairs(sub_end_points) do
                end_points[#end_points+1] = offset + e
            end
        end
        -- TODO: read instructions for composite character
    end
    return self:pack_outline(points, end_points)
end

function Face:string(s, pt, x, y, anchor, a)
    anchor = anchor or "tl"
    a = a or 0
    local codes = utf8to32(s)
    local cur_x = 0
    local contours = {}
    local outline
    local li, ri
    local advance, bearing
    for i, code in ipairs(codes) do
        ri = self:char_index(code)
        if i > 1 and self.num_kernings > 0 then
            cur_x = cur_x + self:get_kerning(li, ri)
        end
        outline = self:glyph(ri)
        for j, contour in ipairs(outline) do
            for k, point in ipairs(contour) do
                point[1] = point[1] + cur_x
            end
            table.insert(contours, contour)
        end
        advance, bearing = self:hmetrics(ri)
        cur_x = cur_x + advance
        li = ri
    end
    local ax, ay -- anchor position
    local av, ah = anchor:sub(1, 1), anchor:sub(2, 2)
    if av == "t" then
        ay = 0
    elseif av == "m" then
        ay = self.cap_height / 2
    elseif av == "b" then
        ay = self.cap_height
    end
    if ah == "l" then
        ax = 0
    elseif ah == "c" then
        ax = cur_x / 2
    elseif ah == "r" then
        ax = cur_x
    end
    if ax == nil or ay == nil then
        error("invalid anchor: "..anchor)
    end
    local scl = pt * self.resolution / (72 * self.units_per_em)
    local t = aff.new_affine()
    t:add_translate(-ax, -ay)
    t:add_scale(scl)
    t:add_rotate(a)
    t:add_translate(x, y)
    for i, contour in ipairs(contours) do
        t:apply(contour)
    end
    return contours
end

local function load_face(f)
    if type(f) == "string" then f = io.open(f, "rb") end
    local self = setmetatable({fp=f}, Face)
    self:offset()
    self:directory()
    self:head()
    self:maxp()
    self:cmap()
    if self.dir["hhea"] then
        self:hhea()
    else
        log("no horizontal metrics (hhea+hmtx)")
    end
    if self.dir["kern"] then
        self:kern()
    else
        self.num_kernings = 0
        log("no kerning table (kern)")
    end
    if self.dir["OS/2"] then
        self:os2()
    else
        log("no x-height and Cap-Height (OS/2)")
    end
    self.resolution = 300 -- dpi
    return self
end

return {load_face=load_face}
