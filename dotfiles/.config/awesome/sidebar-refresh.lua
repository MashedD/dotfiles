-- Coalesce clock and system-status renders into one sidebar invalidation.
local M = {}

function M.new(options)
    local pending_stats, pending_power, pending_clock, pending_time = nil, nil, false, nil
    local has_stats, has_power, disposed = false, false, false
    local timer
    local function flush()
        if disposed then return false end
        local stats, render_stats = pending_stats, has_stats
        local power, render_power = pending_power, has_power
        local render_clock, timestamp = pending_clock, pending_time
        pending_stats, pending_power = nil, nil
        has_stats, has_power, pending_clock, pending_time = false, false, false, nil
        if render_stats then options.update_stats(stats) end
        if render_power then options.update_power(power) end
        if render_clock then options.update_clock(timestamp) end
        return false
    end
    timer = options.timer {
        timeout = options.delay or 0.05,
        single_shot = true,
        callback = flush,
    }
    local component = {}
    local function schedule()
        if not disposed and not timer.started then timer:start() end
    end
    function component.stats(state)
        if disposed then return end
        pending_stats, has_stats = state, true
        schedule()
    end
    function component.power(state)
        if disposed then return end
        pending_power, has_power = state, true
        schedule()
    end
    function component.clock(timestamp)
        if disposed then return end
        pending_clock, pending_time = true, timestamp
        schedule()
    end
    function component.destroy()
        if disposed then return end
        disposed = true
        pending_stats, pending_power = nil, nil
        has_stats, has_power, pending_clock, pending_time = false, false, false, nil
        if timer.started then timer:stop() end
    end
    return component
end

return M
