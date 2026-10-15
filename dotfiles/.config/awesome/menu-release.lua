-- Change awful.menu items from press-to-execute to release-inside activation.
local M = {}
function M.install(menu, awful, gears, mouse)
    if menu._release_inside_installed then return end
    menu._release_inside_installed = true
    local add, delete, hide = menu.add, menu.delete, menu.hide

    local function bind_item(owner, item)
        local armed = false
        item._background:buttons(gears.table.join(
            awful.button({}, 1, function()
                armed = owner.wibox and owner.wibox.visible
            end, function()
                local point = mouse.coords()
                local inside = false
                if owner.wibox and point then
                    for _, found in ipairs(owner.wibox:find_widgets(
                        point.x - owner.wibox.x, point.y - owner.wibox.y)) do
                        if found.widget == item._background then inside = true; break end
                    end
                end
                local activate = armed and inside and owner.wibox and owner.wibox.visible
                armed = false
                if not activate then return end
                local index = gears.table.hasitem(owner.items, item)
                if index then
                    owner:item_enter(index, {mouse = true})
                    owner:exec(index, {exec = true, mouse = true})
                end
            end),
            awful.button({}, 3, function() owner:hide() end)))
        item._release_cancel = function() armed = false end
    end

    menu.add = function(owner, args, index)
        local old_count = #owner.items
        add(owner, args, index)
        if #owner.items == old_count then return end
        local item = owner.items[index or #owner.items]
        if item then bind_item(owner, item) end
    end
    menu.delete = function(owner, number)
        local index = type(number) == "table" and gears.table.hasitem(owner.items, number) or number
        local item = owner.items[index]
        if item and item._release_cancel then item._release_cancel() end
        return delete(owner, number)
    end
    menu.hide = function(owner, ...)
        for _, item in ipairs(owner.items) do
            if item._release_cancel then item._release_cancel() end
        end
        return hide(owner, ...)
    end
end
return M
