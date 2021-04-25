--[[
Affine transformation matrix:
  | a c e |
  | b d f |
  | 0 0 1 |
]]

local Affine = {}
Affine.__index = Affine

function Affine:reset()
    self.a = 1; self.c = 0; self.e = 0
    self.b = 0; self.d = 1; self.f = 0
end

function Affine:add_custom(a, b, c, d, e, f)
    local na = a*self.a + c*self.b
    local nb = b*self.a + d*self.b
    local nc = a*self.c + c*self.d
    local nd = b*self.c + d*self.d
    local ne = a*self.e + c*self.f + e
    local nf = b*self.e + d*self.f + f
    self.a = na; self.c = nc; self.e = ne
    self.b = nb; self.d = nd; self.f = nf
end

function Affine:add_squeeze(k)
    self:add_custom(k, 0, 0, 1/k, 0, 0)
end

function Affine:add_scale(x, y)
    y = y or x
    self:add_custom(x, 0, 0, y, 0, 0)
end

function Affine:add_hshear(h)
    self:add_custom(1, 0, h, 1, 0, 0)
end

function Affine:add_vshear(v)
    self:add_custom(1, v, 0, 1, 0, 0)
end

function Affine:add_rotate(a)
    local c, s = math.cos(a), math.sin(a)
    self:add_custom(c, -s, s, c, 0, 0)
end

function Affine:add_translate(x, y)
    self:add_custom(1, 0, 0, 1, x, y)
end

function Affine:apply(points)
    local x, y
    for i, p in ipairs(points) do
        x = self.a*p[1] + self.c*p[2] + self.e
        y = self.b*p[1] + self.d*p[2] + self.f
        p[1], p[2] = x, y
    end
end

local function new_affine()
    local self = setmetatable({}, Affine)
    self:reset()
    return self
end

return {new_affine=new_affine}
