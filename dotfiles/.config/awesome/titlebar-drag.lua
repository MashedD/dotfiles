-- Drag-to-restore titlebar movement and workarea edge snapping.
local M = {}

function M.edge_action(point, geometry, distance)
    distance = distance or 16
    if point.y <= geometry.y + distance then return "maximize" end
    if point.x <= geometry.x + distance then return "left" end
    if point.x >= geometry.x + geometry.width - distance then return "right" end
end

function M.restore_geometry(maximized, restored, origin, pointer)
    local ratio = maximized.width > 0 and (origin.x - maximized.x) / maximized.width or 0.5
    ratio = math.max(0, math.min(1, ratio))
    local title_offset = origin.y - maximized.y
    return {
        x = pointer.x - ratio * restored.width,
        y = pointer.y - title_offset,
        width = restored.width,
        height = restored.height,
    }
end

function M.new(runtime)
    local threshold = runtime.threshold or 4
    local active = setmetatable({}, {__mode = "k"})
    local controller = {}

    -- Ordinary titlebar moves stay on Awesome's native path. Observe only these
    -- sessions to add top-edge maximize and preserve click-without-drag behavior.
    runtime.resize.add_move_callback(function(c, geometry)
        local state = active[c]
        if not state then return geometry end
        local pointer = runtime.mouse.coords()
        local dx, dy = pointer.x - state.origin.x, pointer.y - state.origin.y
        if dx * dx + dy * dy >= threshold * threshold then state.dragged = true end
        return geometry
    end, "mouse.move")
    runtime.resize.add_leave_callback(function(c, geometry)
        local state = active[c]
        if not state then return geometry end
        active[c] = nil
        if not state.dragged or not c.valid then return state.original end
        local pointer = runtime.mouse.coords()
        local target_screen = runtime.mouse.screen or c.screen
        if target_screen and M.edge_action(pointer, target_screen.geometry, 16) == "maximize" then
            c.screen = target_screen
            c.maximized = false
            c.maximized_horizontal, c.maximized_vertical = false, false
            c.maximized = true
            return nil
        end
        return geometry
    end, "mouse.move")

    function controller.move(c)
        if not c or not c.valid or c.fullscreen then return false end
        if not c.floating then
            runtime.native_move(c)
            return false
        end

        if not c.maximized then
            active[c] = {origin = runtime.mouse.coords(), original = c:geometry(), dragged = false}
            runtime.native_move(c)
            return true
        end

        local mouse = runtime.mouse
        local origin = mouse.coords()
        local maximized = c:geometry()
        local original = c:geometry()
        local centered = runtime.placement.centered(mouse, {parent = c, pretend = true})
        local offset = {x = centered.x - origin.x, y = centered.y - origin.y}
        local dragged = false
        local args = {placement = runtime.placement.under_mouse, offset = offset, snap = false}

        args.move_callback = function(client, geometry)
            local pointer = mouse.coords()
            local dx, dy = pointer.x - origin.x, pointer.y - origin.y
            if not dragged and dx * dx + dy * dy >= threshold * threshold then
                dragged, args.snap = true, runtime.snap_distance
                client.maximized = false
                client.maximized_horizontal, client.maximized_vertical = false, false
                local restored = client:geometry()
                local next_geometry = M.restore_geometry(maximized, restored, origin, pointer)
                args.offset = {
                    x = next_geometry.x - (pointer.x - restored.width / 2),
                    y = next_geometry.y - (pointer.y - restored.height / 2),
                }
                return next_geometry
            end
            return dragged and geometry or original
        end

        args.leave_callback = function(client, geometry)
            if not dragged or not client.valid then return nil end
            local pointer = mouse.coords()
            local target_screen = mouse.screen or client.screen
            local action = target_screen and M.edge_action(pointer, target_screen.geometry, 16)
            if action == "maximize" then
                client.screen = target_screen
                client.maximized = false
                client.maximized_horizontal, client.maximized_vertical = false, false
                client.maximized = true
                return nil
            elseif action == "left" or action == "right" then
                client.screen = target_screen
                runtime.snap(client, action == "right")
                return nil
            end
            return geometry
        end

        runtime.resize(c, "mouse.move", args)
        return true
    end

    return controller
end

return M
