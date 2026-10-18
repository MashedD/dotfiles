-- Edge feedback only: normal scrolling never waits for an animation.
local gears = require("gears")
local M = {}
function M.new(redraw, clock)
    local displacement, timer, started, initial = 0, nil, 0, 0
    local spring = {}
    function spring.value() return displacement end
    function spring.reset()
        if timer then timer:stop(); timer = nil end
        displacement = 0
    end
    function spring.kick(excess)
        displacement = math.max(-28, math.min(28, displacement + excess * 0.18))
        initial, started = displacement, clock()
        redraw()
        if timer then return end
        timer = gears.timer.start_new(1 / 60, function()
            local t = clock() - started
            -- Critically damped return: no oscillating text or persistent momentum.
            displacement = initial * (1 + 24 * t) * math.exp(-24 * t)
            if math.abs(displacement) < 0.25 then displacement = 0; timer = nil end
            redraw()
            return timer ~= nil
        end)
    end
    return spring
end
return M
