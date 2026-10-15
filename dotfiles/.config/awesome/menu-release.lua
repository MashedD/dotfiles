-- Release-inside behavior for Awesome's native menu entries.
local M = {}
function M.install(menu, interaction, awful, gears)
    if menu._release_inside_installed then return end
    menu._release_inside_installed = true
    local add, delete, hide = menu.add, menu.delete, menu.hide

    local function bind_item(owner, item)
        local group = interaction.lifetime()
        local normal_width = item._background.border_width or 0
        item._release_group = group
        item._background:buttons(gears.table.join(
            awful.button({}, 1, function() end),
            awful.button({}, 3, function() owner:hide() end)))
        item._release_binding = interaction.bind_button(item._background, {
            width = item.width, height = item.height, modifiers = {},
            valid = function() return owner.wibox and owner.wibox.visible end,
            activate = function()
                local index = gears.table.hasitem(owner.items, item)
                if index then
                    owner:item_enter(index, {mouse = true})
                    owner:exec(index, {exec = true, mouse = true})
                end
            end,
            paint = function(pressed)
                item._background.border_width = pressed and 1 or normal_width
                item._background.border_color = item.theme.fg_focus
            end,
        }, group)
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
        if item and item._release_group then item._release_group.destroy() end
        return delete(owner, number)
    end
    menu.hide = function(owner, ...)
        for _, item in ipairs(owner.items) do
            if item._release_binding then item._release_binding.cancel() end
        end
        return hide(owner, ...)
    end
end
return M
