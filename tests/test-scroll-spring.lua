local callback, stopped, now = nil, false, 0
package.loaded.gears = {timer = {start_new = function(_, fn)
    callback = fn
    return {stop = function() stopped = true end}
end}}
local spring = dofile('dotfiles/.config/awesome/scroll-spring.lua').new(function() end, function() return now end)
spring.kick(-160)
assert(spring.value() == -28)
now = 0.1
assert(callback() and spring.value() < 0 and spring.value() > -28)
now = 1
assert(not callback() and spring.value() == 0)
spring.kick(160)
assert(spring.value() == 28)
spring.reset()
assert(stopped and spring.value() == 0)
print('Scroll spring bounds, decay and teardown passed')
