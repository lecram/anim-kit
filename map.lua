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
    lon = lon - self.lon0
    local k, x, y
    k = sqrt(2 / (1 + sin(self.lat0) * sin(lat) + cos(self.lat0) * cos(lat) * cos(lon)))
    x = self.r * k * cos(lat) * sin(lon)
    y = self.r * k * (cos(self.lat0) * sin(lat) - sin(self.lat0) * cos(lat) * cos(lon))
    return x, y
end

function AzimuthalEqualArea:inv(x, y)
    local p = sqrt(x*x + y*y)
    local c = 2 * asin(p / (2 * self.r))
    local lon, lat
    -- FIXME: In the formulas below, should it be atan or atan2?
    if self.lat0 == pi / 2 then
        -- North Polar Aspect.
        lon = self.lon0 + atan(x/(-y))
    elseif self.lat0 == -pi / 2 then
        -- South Polar Aspect.
        lon = self.lon0 + atan(x/y)
    else
        -- Any other Oblique Aspect.
        local den = p * cos(self.lat0) * cos(c) - y * sin(self.lat0) * sin(c)
        lon = self.lon0 + atan(x * sin(c) / den)
    end
    lat = asin(cos(c) * sin(self.lat0) + y * sin(c) * cos(self.lat0) / p)
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
    proj.lon0, proj.lat0 = unpack(origin or {0, 0})
    proj.lon0, proj.lat0 = rad(proj.lon0), rad(proj.lat0)
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

local function save_frame(fname, model, projection, bounding)
    local frm = io.open(fname, "w")
    frm:write("type", sep, model.type, "\n")
    if model.type == "ellipsoid" then
        frm:write("a", sep, model.a, "\n")
        frm:write("b", sep, model.b, "\n")
        frm:write("e", sep, model.e, "\n")
        frm:write("f", sep, model.f, "\n")
    elseif model.type == "sphere" then
        frm:write("r", sep, model.r, "\n")
    end
    frm:write("proj", sep, projection.name, "\n")
    frm:write("lon", sep, math.deg(projection.lon0), "\n")
    frm:write("lat", sep, math.deg(projection.lat0), "\n")
    frm:write("x0", sep, bounding.x0, "\n")
    frm:write("y0", sep, bounding.y0, "\n")
    frm:write("x1", sep, bounding.x1, "\n")
    frm:write("y1", sep, bounding.y1, "\n")
    frm:close()
end

local function load_frame(fname)
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
    local projection = {}
    projection.name = get "proj"
    projection.lon = tonumber(get "lon")
    projection.lat = tonumber(get "lat")
    local bounding = {}
    bounding.x0 = tonumber(get "x0")
    bounding.y0 = tonumber(get "y0")
    bounding.x1 = tonumber(get "x1")
    bounding.y1 = tonumber(get "y1")
    frm:close()
    return model, projection, bounding
end

local Frame = {}
Frame.__index = Frame

function Frame:map(lon, lat)
    local x, y = self.prj:map(lon, lat)
    x = (x - self.bb.x0) * self.s
    y = self.h - (y - self.bb.y0) * self.s
    return x, y
end

function Frame:set_height(h)
    local mw = self.bb.x1 - self.bb.x0
    local mh = self.bb.y1 - self.bb.y0
    self.h = h
    self.s = h / mh
    self.w = math.floor(mw * self.s + 0.5)
end

function Frame:mapped(points)
    return coroutine.wrap(function()
        for p in points do
            local lat, lon = unpack(p)
            local x, y = self:map(lat, lon)
            coroutine.yield({x, y})
        end
    end)
end

local function new_frame(fname)
    local self = setmetatable({}, Frame)
    local m, p, b = load(fname)
    self.bb = b
    self.prj = proj.Proj(p.name, {p.lon, p.lat}, m.r)
    return self
end

return {
    distance=distance, bbox=bbox, centroid=centroid, Proj=Proj,
    save_frame=save_frame, load_frame=load_frame, new_frame=new_frame
}
