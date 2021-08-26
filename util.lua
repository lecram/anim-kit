local ffi = require "ffi"

ffi.cdef[[
double hypot(double x, double y);
double copysign(double x, double y);
]]
local hypot = ffi.C.hypot
local copysign = ffi.C.copysign

local function round(x)
    local i, f = math.modf(x + copysign(0.5, x))
    return i
end

local function rtrim(s, c)
    local i = #s
    while s:sub(i, i) == c do
        i = i - 1
    end
    return s:sub(1, i)
end

local function startswith(s1, s2)
    return s1:sub(1, #s2) == s2
end

local function func_iter(seq)
    if type(seq) == "table" then
        local i = 0
        return function()
            i = i + 1
            if i <= #seq then
                return seq[i]
            end
        end
    else
        return seq
    end
end

return {
    hypot=hypot, copysign=copysign, round=round,
    rtrim=rtrim, startswith=startswith,
    func_iter=func_iter
}
