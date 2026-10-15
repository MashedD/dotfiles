-- lua tests/test-awesome-appearance.lua
package.preload.gears = function() return {color = function(spec) return spec end} end
local appearance = dofile('dotfiles/.config/awesome/appearance.lua')
local function rgb(hex)
    return {tonumber(hex:sub(2,3),16)/255, tonumber(hex:sub(4,5),16)/255,
        tonumber(hex:sub(6,7),16)/255, #hex == 9 and tonumber(hex:sub(8,9),16)/255 or 1}
end
local function luminance(c)
    local sum = 0
    for i, weight in ipairs({0.2126, 0.7152, 0.0722}) do
        local v = c[i] <= 0.04045 and c[i]/12.92 or ((c[i]+0.055)/1.055)^2.4
        sum = sum + weight*v
    end
    return sum
end
local function contrast(fg, bg)
    local a,b = luminance(fg),luminance(bg)
    return (math.max(a,b)+0.05)/(math.min(a,b)+0.05)
end
local function sample(stops, position, wallpaper)
    local low, high = stops[1], stops[#stops]
    for i=2,#stops do
        if stops[i][1] >= position then low, high = stops[i-1], stops[i]; break end
    end
    local a,b = rgb(low[2]),rgb(high[2])
    local ratio = (position-low[1])/(high[1]-low[1])
    local out = {}
    local alpha = a[4]+(b[4]-a[4])*ratio
    for i=1,3 do out[i]=(a[i]+(b[i]-a[i])*ratio)*alpha+wallpaper*(1-alpha) end
    return out
end
for name, foregrounds in pairs({
    blue = {'title','text','green','amber'}, selected = {'title'},
    inactive = {'inactive','minimized'}, card = {'text','muted','teal'},
    forest = {'text','muted'},
}) do
    for _,foreground in ipairs(foregrounds) do
        for _,wallpaper in ipairs({0,1}) do
            -- Highlights are decorative; text begins below the top 10%.
            for step=10,100 do
                local c = contrast(rgb(appearance.palette[foreground]),sample(appearance.stops[name],step/100,wallpaper))
                assert(c >= 4.5, string.format('%s/%s at %d%%: %.2f',name,foreground,step,c))
            end
        end
    end
end
assert(appearance.remaining_color(21) == appearance.palette.green)
assert(appearance.remaining_color(20) == appearance.palette.amber)
assert(appearance.remaining_color(10) == appearance.palette.red)
assert(appearance.remaining_color(0) == appearance.palette.red)
assert(appearance.remaining_color(10,10,5) == appearance.palette.amber)
assert(appearance.remaining_color(5,10,5) == appearance.palette.red)
assert(appearance.trash_color(true) == appearance.palette.amber)
assert(appearance.trash_color(false) == appearance.palette.green)
assert(appearance.trash_color(nil) == appearance.palette.text)
assert(appearance.gradient('selected',26).to[2] == 26)
print('Awesome appearance contrast tests passed')
