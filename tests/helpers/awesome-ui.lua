-- Utilities loaded only by tests on the private Awesome/Xvfb process.
local H = {}
function H.visible_drawins()
    local count = 0
    for _, drawin in ipairs(root.drawins()) do if drawin.visible then count = count + 1 end end
    return count
end
function H.titlebar_controls(client)
    local result = {}
    local bars = client and client._private and client._private.titlebars
    local drawable = bars and bars.top and bars.top.drawable
    local widget = drawable and drawable.widget
    for _, child in ipairs(widget and widget:get_all_children() or {}) do
        if child.get_children_by_id then
            for _, id in ipairs({"titlebar_minimize", "titlebar_maximize", "titlebar_close"}) do
                local found = child:get_children_by_id(id)[1]
                if found then result[id] = found end
            end
        end
    end
    return result
end
function H.rgb(pattern)
    local r, g, b = pattern:get_rgba()
    return string.format("#%02x%02x%02x", math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
function H.component_disposed(group, components)
    if not group.disposed or mousegrabber.isrunning() then return false end
    for _, tip in ipairs(group.tooltips) do if tip.visible then return false end end
    for _, component in pairs(components) do
        if not component.ui.disposed or component.bar_panel and component.bar_panel.visible then return false end
        for _, tip in ipairs(component.ui.tooltips) do if tip.visible then return false end end
    end
    return true
end
function H.widgets(root_widget, id)
    local found = {}
    for _, widget in ipairs(root_widget:get_all_children()) do
        if widget.get_children_by_id then
            for _, child in ipairs(widget:get_children_by_id(id)) do found[#found + 1] = child end
        end
    end
    return found
end
return H
