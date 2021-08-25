local bio = require "bio"

local abs = math.abs
local rad, deg = math.rad, math.deg
local cos, sin, tan = math.cos, math.sin, math.tan
local acos, asin, atan, atan2 = math.acos, math.asin, math.atan, math.atan2
local sqrt = math.sqrt
local pi, huge = math.pi, math.huge

-- == Utilities ==

-- region is a list of polygons in geographic coordinates.

local function distance(lon1, lat1, lon2, lat2, r)
    r = r or 6378137
    local dlat = rad(lat2 - lat1)
    local dlon = rad(lon2 - lon1)
    lat1, lat2 = rad(lat1), rad(lat2)
    local a1, a2, a, c
    a1 = sin(dlat/2) * sin(dlat/2)
    a2 = sin(dlon/2) * sin(dlon/2) * cos(lat1) * cos(lat2)
    a = a1 + a2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    return r * c
end

local function bbox(region)
    local x0, y0, x1, y1 = huge, huge, -huge, -huge
    for _, polygon in ipairs(region) do
        for _, point in ipairs(polygon) do
            local x, y = unpack(point)
            x0 = x < x0 and x or x0
            y0 = y < y0 and y or y0
            x1 = x > x1 and x or x1
            y1 = y > y1 and y or y1
        end
    end
    return x0, y0, x1, y1
end

local function centroid(region)
    local epsilon = 1e-10
    local x0, y0, x1, y1 = bbox(region)
    local lon0 = (x0 + x1) / 2
    local lat0 = (y0 + y1) / 2
    local lon1, lat1
    while true do
        local prj = Proj("AzimuthalEqualArea", {lon0, lat0})
        local cw = {}
        for i, polygon in ipairs(region) do
            local xys = {}
            for j, point in ipairs(polygon) do
                xys[j] = {prj:map(unpack(point))}
            end
            if xys[#xys][0] ~= xys[1][0] or xys[#xys][1] ~= xys[1][1] then
                xys[#xys+1] = xys[1]
            end
            -- http://en.wikipedia.org/wiki/Centroid#Centroid_of_polygon
            local cx, cy, sa = 0, 0, 0
            for j = 1, #xys-1 do
                local x0, y0 = unpack(xys[j])
                local x1, y1 = unpack(xys[j+1])
                local f = x0 * y1 - x1 * y0
                cx = cx + (x0 + x1) * f
                cy = cy + (y0 + y1) * f
                sa = sa + f
            end
            cx = cx / (3 * sa)
            cy = cy / (3 * sa)
            cw[#cw+1] = {cx, cy, sa}
        end
        local cx, cy, sw = 0, 0, 0
        for i = 1, #cw do
            local x, y, w = unpack(cw[i])
            cx = cx + x * w
            cy = cy + y * w
            sw = sw + w
        end
        cx = cx / sw
        cy = cy / sw
        lon1, lat1 = prj:inv(cx, cy)
        if abs(lon1-lon0) <= epsilon and abs(lat1-lat0) <= epsilon then
            break
        end
        lon0, lat0 = lon1, lat1
    end
    return lon1, lat1
end

-- == Projections ==

-- Lambert Azimuthal Equal-Area Projection for the Spherical Earth.

local AzimuthalEqualArea = {}
AzimuthalEqualArea.__index = AzimuthalEqualArea

function AzimuthalEqualArea:map(lon, lat)
    lon, lat = rad(lon), rad(lat)
    lon = lon - self.lon
    local k, x, y
    k = sqrt(2 / (1 + sin(self.lat) * sin(lat) + cos(self.lat) * cos(lat) * cos(lon)))
    x = self.r * k * cos(lat) * sin(lon)
    y = self.r * k * (cos(self.lat) * sin(lat) - sin(self.lat) * cos(lat) * cos(lon))
    return x, y
end

function AzimuthalEqualArea:inv(x, y)
    local p = sqrt(x*x + y*y)
    local c = 2 * asin(p / (2 * self.r))
    local lon, lat
    -- FIXME: In the formulas below, should it be atan or atan2?
    if self.lat == pi / 2 then
        -- North Polar Aspect.
        lon = self.lon + atan(x/(-y))
    elseif self.lat == -pi / 2 then
        -- South Polar Aspect.
        lon = self.lon + atan(x/y)
    else
        -- Any other Oblique Aspect.
        local den = p * cos(self.lat) * cos(c) - y * sin(self.lat) * sin(c)
        lon = self.lon + atan(x * sin(c) / den)
    end
    lat = asin(cos(c) * sin(self.lat) + y * sin(c) * cos(self.lat) / p)
    lon, lat = deg(lon), deg(lat)
    return lon, lat
end

function AzimuthalEqualArea:model()
    return {type="sphere", r=self.r}
end

local projs = {
    AzimuthalEqualArea=AzimuthalEqualArea
}

-- Generic projection interface.

local function Proj(name, origin, radius)
    local proj = {}
    proj.name = name
    proj.lon, proj.lat = unpack(origin or {0, 0})
    proj.lon, proj.lat = rad(proj.lon), rad(proj.lat)
    proj.r = radius or 6378137
    return setmetatable(proj, projs[name])
end

-- == Frames ==

--[[
 A frame stores information that specify the relation between the Earth's
geometry (geodesy) and a particular map geometry (usually in 2D). Each map has a
frame over which multiple layers of entities are drawn. There are two parameters
that define a unique frame:
* a projection;
* a bounding box on the projected (plane) space.

 The projection parameter must be fully specified, including the center of the
projection, the orientation of the projection and the Earth model used (sphere
or ellipsoid) along with its parameters.

 The bounding box is specified as two points, determining minimal an maximal
coordinates. The coordinate system for the bounding box is the projected one,
but without scale, i.e. with meters as unit.
]]

local sep = ":"

local Frame = {}
Frame.__index = Frame

function Frame:map(lon, lat)
    local x, y = self.proj:map(lon, lat)
    x = (x - self.bbox.x0) * self.s
    y = self.h - (y - self.bbox.y0) * self.s
    return x, y
end

function Frame:set_height(h)
    local mw = self.bbox.x1 - self.bbox.x0
    local mh = self.bbox.y1 - self.bbox.y0
    self.h = h
    self.s = h / mh
    self.w = math.floor(mw * self.s + 0.5)
end

function Frame:mapped(polys)
    return function()
        local points = polys()
        if points then
            return function()
                local point = points()
                if point then
                    local lat, lon = unpack(point)
                    local x, y = self:map(lat, lon)
                    return {x, y}
                end
            end
        end
    end
end

function Frame:near(bb)
    -- not strictly correct, since projected geobbox != 2D rectangle
    -- just used to limit cache and avoid 16-bit overflows
    local ns = {}
    local add_ll = function(lon, lat)
        local x, y = self:map(lon, lat)
        table.insert(ns, abs(x-self.w/2))
        table.insert(ns, abs(y-self.h/2))
    end
    add_ll(bb.xmin, bb.ymin)
    add_ll(bb.xmax, bb.ymin)
    add_ll(bb.xmax, bb.ymax)
    add_ll(bb.xmin, bb.ymax)
    return math.max(unpack(ns)) < math.max(self.w, self.h)*2
end

function Frame:save_cache(fname, k, sf, filter)
    local indices = {}
    for i = 1, #sf.tab do
        local row = sf.tab[i]
        local rec = {}
        for j = 1, #sf.fields do
            rec[sf.fields[j].name] = row[j]
        end
        local key = filter(rec)
        if key ~= nil then
            if self:near(sf:read_bbox(i)) then
                table.insert(indices, {i, key:sub(1, 16)})
            end
        end
    end
    local cache = io.open(fname, "w")
    bio.write_beu16(cache, self.w)
    bio.write_beu16(cache, self.h)
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
        local bb, lens, polys = sf:read_polygons(index)
        bio.write_beu16(cache, #lens)
        for poly in self:mapped(polys) do
            local ox, oy = unpack(poly())
            ox, oy = math.floor(ox + 0.5), math.floor(oy + 0.5)
            bio.write_bei16(cache, ox)
            bio.write_bei16(cache, oy)
            local rice = bio.rice_w(cache, k)
            for point in poly do
                local x, y = unpack(point)
                x, y = math.floor(x + 0.5), math.floor(y + 0.5)
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

function Frame:save(fname)
    local frm = io.open(fname, "w")
    local model = self.proj:model()
    frm:write("type", sep, model.type, "\n")
    if model.type == "ellipsoid" then
        frm:write("a", sep, model.a, "\n")
        frm:write("b", sep, model.b, "\n")
        frm:write("e", sep, model.e, "\n")
        frm:write("f", sep, model.f, "\n")
    elseif model.type == "sphere" then
        frm:write("r", sep, model.r, "\n")
    end
    frm:write("proj", sep, self.proj.name, "\n")
    frm:write("lon", sep, deg(self.proj.lon), "\n")
    frm:write("lat", sep, deg(self.proj.lat), "\n")
    frm:write("x0", sep, self.bbox.x0, "\n")
    frm:write("y0", sep, self.bbox.y0, "\n")
    frm:write("x1", sep, self.bbox.x1, "\n")
    frm:write("y1", sep, self.bbox.y1, "\n")
    frm:close()
end

local function new_frame(proj, bbox)
    local self = setmetatable({}, Frame)
    self.proj = proj
    self.bbox = bbox
    self.w, self.h, self.s = bbox.x1-bbox.x0, bbox.y1-bbox.y0, 1
    return self
end

local function load_frame(fname)
    local self = setmetatable({}, Frame)
    local frm = io.open(fname, "r")
    local function get(field)
        local line = frm:read()
        local got = line:sub(1, #field)
        assert(got == field, "expected field "..field.." but got "..got)
        return line:sub(#field+#sep+1)
    end
    local model = {}
    model.type = get "type"
    if model.type == "ellipsoid" then
        model.a = tonumber(get "a")
        model.b = tonumber(get "b")
        model.e = tonumber(get "e")
        model.f = tonumber(get "f")
    elseif model.type == "sphere" then
        model.r = tonumber(get "r")
    end
    local proj_name = get "proj"
    local proj_lon = tonumber(get "lon")
    local proj_lat = tonumber(get "lat")
    proj = Proj(proj_name, {proj_lon, proj_lat}, model.r)
    local bbox = {}
    bbox.x0 = tonumber(get "x0")
    bbox.y0 = tonumber(get "y0")
    bbox.x1 = tonumber(get "x1")
    bbox.y1 = tonumber(get "y1")
    frm:close()
    return new_frame(proj, bbox)
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
    assert(offset > 0, ("key '%s' not found in cache '%s'"):format(key, fname))
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
                    return {x, y}
                end
            end
        end
    end
end

local function load_cache(fname)
    local self = setmetatable({}, Cache)
    self.fp = io.open(fname, "r")
    self.w = bio.read_beu16(self.fp)
    self.h = bio.read_beu16(self.fp)
    self.k = bio.read_byte(self.fp)
    return self
end

return {
    distance=distance, bbox=bbox, centroid=centroid, Proj=Proj,
    new_frame=new_frame, load_frame=load_frame, load_cache=load_cache
}
