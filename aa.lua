local bit = require "bit"

local surf = require "surf"

local lshift, rshift =  bit.lshift,  bit.rshift

-- ByteMaps (and GIFs) have a maximum of 256 colors
-- we're anti-aliasing by mixing four pixels in one (k=4)
-- the maximum n where C(n+k-1, k) < 256 is 7
-- so we only need factorials up to 7+4-1=10
local fact = {1, 2, 6, 24, 120, 720, 5040, 40320, 362880, 3628800}
fact[0] = 1

-- binomial coefficient
-- returns zero if n < k
local function C(n, k)
    return n >= k and fact[n] / fact[k] / fact[n-k] or 0
end

-- index of a combination with repetition
-- n must be ordered
local function I(n, base)
    local a, b, c, d = unpack(n)
    local N = base + 3
    return C(N, 4) - C(N-a-1, 4) - C(N-b-2, 3) - C(N-c-3, 2) - C(N-d-4, 1) - 1
end

-- helper to generate combinations with repetition in lexicographical order
local function next_mix(n, base)
    for i = 4, 1, -1 do
        if n[i] < base-1 then
            n[i] = n[i] + 1
            for j = i+1, 4 do
                n[j] = n[j-1]
            end
            break
        end
    end
end

local function test_combinations()
    local base = 7
    local n = {0, 0, 0, 0}
    local i = 0
    while i < C(base+3, 4) do
        assert(I(n, base) == i)
        i = i + 1
        next_mix(n, base)
    end
    print(i.." tests passed")
end

local function antialias(bytemap, colors)
    local base = #colors
    assert(base >= 2 and base <= 7)
    -- output has half dimensions
    -- discard last row/column for odd dimensions
    local w = rshift(bytemap.w, 1)
    local h = rshift(bytemap.h, 1)
    local outmap = surf.new_bytemap(w, h)
    local n = {} -- indices of colors to be mixed
    local dx, dy -- coordinates in input bytemap (d is for "double")
    for y = 0, h-1 do
        dy = lshift(y, 1)
        for x = 0, w-1 do
            dx = lshift(x, 1)
            n[1] = bytemap:pget(dx  , dy  )
            n[2] = bytemap:pget(dx+1, dy  )
            n[3] = bytemap:pget(dx  , dy+1)
            n[4] = bytemap:pget(dx+1, dy+1)
            assert(math.max(unpack(n)) < base)
            table.sort(n)
            local v = I(n, base)
            outmap:pset(x, y, v)
        end
    end
    -- now just build the palette of mixed colors
    local function mixed_rgb(n)
        local c1 = colors[n[1]+1]
        local c2 = colors[n[2]+1]
        local c3 = colors[n[3]+1]
        local c4 = colors[n[4]+1]
        -- compute the average RGB of the four colors
        local r = rshift(c1[1] + c2[1] + c3[1] + c4[1], 2)
        local g = rshift(c1[2] + c2[2] + c3[2] + c4[2], 2)
        local b = rshift(c1[3] + c2[3] + c3[3] + c4[3], 2)
        return r, g, b
    end
    n = {0, 0, 0, 0}
    local palette = {{mixed_rgb(n)}}
    for i = 2, C(base+3, 4) do
        next_mix(n, base)
        table.insert(palette, {mixed_rgb(n)})
    end
    return outmap, palette
end

return {antialias=antialias}
