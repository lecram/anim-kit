# anim-kit
A bunch of LuaJIT modules that I use to create animated diagrams and maps.

## Surfaces (`anim.surf`)

Surfaces can be either bitmaps (two colors) or bytemaps (up to 256 colors).
Both have very similar APIs, except for color parameters and file exports.
Surfaces don't store actual color information, such as RGB.
Color indices are stored instead.
For bitmaps, there are only two valid colors: 0 and 1.
For bytemaps, any number between 0 and 255 inclusive is a valid color.

```lua
local anim = require "anim"

local width, height = 400, 300
local cx, cy = width/2, height/2
local radius = math.min(width, height)/3
local color = 1

local bitmap = anim.surf.new_bitmap(width, height)
bitmap:disk(cx, cy, radius, color)
bitmap:save_pbm("bitmap.pbm")

local bytemap = anim.surf.new_bytemap(width, height)
bytemap:disk(cx, cy, radius, 1)
bytemap:disk(cx, cy, radius/2, 2)
local colors = {
    {0xFF, 0xFF, 0xFF}, -- white
    {0x00, 0x00, 0x00}, -- black
    {0x00, 0xFF, 0x00}, -- green
}
bytemap:save_ppm("bytemap.ppm", colors)
```

### Surface Methods

```lua
Surf:fill(v)                        -- v is the color index
Surf:pget(x, y)
Surf:pset(x, y, v)
Surf:blit(x, y, surf, sx, sy, w, h)
Surf:disk(cx, cy, r, v)
Surf:line(x0, y0, x1, y1, v, r)     -- r is the line width
Surf:polyline(points, v, r)         -- points = {{x0, y0}, {x1, y1}, ...}
Surf:polylines(polys, v, r)         -- polys = {points0, points1, ...}
Surf:polygon(points, v)
Surf:polygons(polygons, v)          -- polygons = {points0, points1, ...}
```

## Vector Shapes (`anim.poly`)

The module `anim.poly` provides higher-level drawing primitives.
The arrays returned by the functions below can be passed to `Surf:poly*()` methods.

```lua
polylines = anim.poly.dashed(points, pattern)
-- apply dashed pattern to a polyline
-- pattern is an array of integers specifying the length of alternating dashes and gaps
-- pattern = {5, 2, 3, 2} -> -----  ---  -----  ---  -----  ---  -----  ---

polyline = anim.poly.unfold(control_points)
-- convert a sequence of linked Bézier curves to a polyline
-- each item in the control_points array has format {x, y, on_curve}

polygon = anim.poly.ngon(x, y, r, n, mina, maxa)
-- regular polygon
-- mina and maxa are the starting and ending angle
-- by default, mina = 0 and maxa = 2*math.pi

polygon = anim.poly.parc(x, y, r, mina, maxa)
-- approximate an arc between angles mina and maxa

polygon = anim.poly.pcircle(x, y, r)
-- regular polygon that approximates a circle

polyline = anim.poly.arrow_head(x0, y0, x1, y1, w, h)
-- arrow head pointed at (x1, y1), oriented from (x0, y0)
```

## TrueType Fonts (`anim.ttf`)

```lua
font = anim.ttf.load_face("full/path/to/font.ttf")
polygons = font:string(s, pt, x, y, anchor, a)
-- s is the string to be rendered
-- pt is the point size
-- anchor is the position of (x, y) in relation to the text rendered:
--   anchor = V..H, where
--      V is "t" for top, "m" for mid, or "b" for bottom
--      H is "l" for left, "c" for center, or "r" for right
--   by default, anchor = "tl", i.e., top left
-- a is the angle in radians to rotate text (0 by default)
```

## Anti Aliasing (`anim.aa`)

This module performs anti aliasing by downsampling the surface in half.
Each group of 2x2 pixels is converted into one by mixing the four colors.
Some combinatorics is used to add mixed colors to a palette.

```lua
surf:save_ppm("surf-2x.ppm", colors)
palette = anim.aa.get_mixed_colors(colors)
surf = anim.aa.antialias(surf, #colors)
surf:save_ppm("surf-aa.ppm", palette)
```

## Reading and Writing GIF files (`anim.gif`)

Reading frames from a GIF:

```lua
gif = anim.gif.open_gif("dia.gif")
i = 0
for frame in gif:frames() do    -- frame is a Surf object
    i = i + 1
    frame:save_ppm(("frame-%03d.ppm"):format(i), gif.gct)
end
print("saved "..i.." frame(s)")
```

Creating a GIF animation:

```lua
gif = anim.gif.new_gif(f, w, h, colors)     -- f is the file name
gif:add_frame(surf1, delay)      -- delay is in hundreths of a second
gif:add_frame(surf2, delay)
gif:add_frame(surf3, delay)
gif:close()     -- this is important
```
