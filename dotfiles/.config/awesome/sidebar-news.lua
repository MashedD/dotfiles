-- Scrollable, screen-anchored RSS inbox; feed I/O and persistence live in desktop-news.
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local gstring = require("gears.string")
local M = {}
local active_instance

local function escape(value)
    return gstring.xml_escape(tostring(value or ""))
end

function M.filtered(items, unread_only, category)
    local result = {}
    for _, item in ipairs(items or {}) do
        if (not unread_only or not item.read)
            and (category == "all" or item.category == category) then
            result[#result + 1] = item
        end
    end
    return result
end

function M.new(options)
    local s, ui, data = options.screen, options.ui, options.data
    local appearance, palette = options.appearance, options.appearance.palette
    local popup, current_state, action_error
    local row_lifetime
    local view_unread, view_category = true, "all"
    local scroll_offset, content_height = 0, 0
    local escape_binding, leave_timer
    local component = {ui = ui}

    local count_text = options.label("Loading news…", palette.muted, 9, false)
    local open_button
    local body_row = wibox.layout.align.horizontal()
    body_row:set_left(count_text)
    local body_actions = wibox.layout.fixed.horizontal()
    body_actions.spacing = 4
    body_row:set_right(body_actions)
    local body = wibox.widget {body_row, left = 2, right = 2, widget = wibox.container.margin}

    local list = wibox.layout.fixed.vertical()
    list.spacing = 5
    local viewport = wibox.widget.base.make_widget()
    viewport.fit = function(_, context, width)
        local _, height = wibox.widget.base.fit_widget(viewport, context, list, width, 2^20)
        content_height = height
        return width, math.min(height, options.list_height)
    end
    viewport.layout = function(_, context, width, height)
        local _, measured = wibox.widget.base.fit_widget(viewport, context, list, width, 2^20)
        content_height = measured
        scroll_offset = math.max(0, math.min(scroll_offset, math.max(0, content_height - height)))
        return {wibox.widget.base.place_widget_at(list, 0, -scroll_offset, width, content_height)}
    end
    viewport.draw = function() end
    viewport.before_draw_children = function(_, _, cr, width, height)
        cr:save(); cr:rectangle(0, 0, width, height); cr:clip()
    end
    viewport.after_draw_children = function(_, _, cr)
        cr:restore()
    end
    function component.scroll_by(delta)
        local maximum = math.max(0, content_height - options.list_height)
        local next_offset = math.max(0, math.min(maximum, scroll_offset + delta))
        if next_offset == scroll_offset then return false end
        scroll_offset = next_offset
        viewport:emit_signal("widget::layout_changed")
        viewport:emit_signal("widget::redraw_needed")
        return true
    end
    component.viewport = viewport

    local popup_status = options.label("Waiting for first feed refresh…", palette.muted, 9, false)
    popup_status.wrap = "word_char"
    local title = options.label("NEWS READER", palette.title, 10, true, "center")
    local toolbar = wibox.layout.fixed.horizontal()
    toolbar.spacing = 4
    local filter_row = wibox.layout.fixed.horizontal()
    filter_row.spacing = 3
    local list_column = wibox.layout.fixed.vertical()
    list_column.spacing = 5
    list_column:add(popup_status)
    list_column:add(viewport)

    local function set_markup(widget, markup)
        widget.markup = markup
    end
    local function subtitle(item)
        if item.published and item.published > 0 then
            return item.source .. "  ·  " .. os.date("%d %b %H:%M", item.published)
        end
        return item.source
    end
    local function perform_action(name, item_id)
        local argv = {options.helper, name}
        if item_id then argv[#argv + 1] = item_id end
        data.command(argv, data.parsers.parse_news, function(value, err)
            if value then
                action_error = nil
                data.publish("news", value)
            else
                action_error = err or "News action failed"
                component.render(data.state("news"))
            end
        end)
    end
    local function open_story(item)
        if not item.url or not item.url:match("^https?://[^%s]+$") then
            action_error = "This story has no safe web link"
            component.render(data.state("news"))
            return
        end
        local ok, result = pcall(awful.spawn, {"firefox", "--new-tab", item.url})
        if not ok or not result then
            action_error = "Could not launch Firefox"
            component.render(data.state("news"))
            return
        end
        perform_action("mark-read", item.id)
    end
    local function news_row(item)
        local source = options.label(escape(subtitle(item)), palette.muted, 8, false)
        local headline = options.label(escape(item.title), item.read and palette.muted or palette.title,
            10, not item.read)
        headline.wrap, headline.valign = "word_char", "top"
        local summary_text = item.summary ~= "" and item.summary or "No description provided."
        local summary = options.label(escape(summary_text), palette.text, 9, false)
        summary.wrap, summary.valign = "word_char", "top"
        local actions = wibox.layout.fixed.horizontal()
        actions.spacing = 4
        local open = options.button(item.url and "Open in Firefox" or "No link", function()
            if item.url then open_story(item) end
        end, 104, row_lifetime)
        local toggle = options.button(item.read and "Mark unread" or "Mark read", function()
            perform_action(item.read and "mark-unread" or "mark-read", item.id)
        end, 88, row_lifetime)
        local remove = options.button("Remove", function() perform_action("remove", item.id) end, 64, row_lifetime)
        actions:add(open); actions:add(toggle); actions:add(remove)
        component.item_controls[item.id] = {open = open, toggle = toggle, remove = remove}
        local row = wibox.widget {
            {
                source, headline, summary,
                {actions, halign = "right", widget = wibox.container.place},
                spacing = 4, layout = wibox.layout.fixed.vertical,
            },
            left = 8, right = 8, top = 6, bottom = 6,
            bg = item.read and "#111e2df5" or "#182a3cf5",
            border_width = 1, border_color = palette.line,
            widget = wibox.container.background,
        }
        return row
    end
    local function render_list(value)
        if row_lifetime then row_lifetime.destroy() end
        row_lifetime = options.interaction.lifetime()
        list:reset()
        component.item_controls = {}
        local matching = M.filtered(value and value.items or {}, view_unread, view_category)
        for _, item in ipairs(matching) do list:add(news_row(item)) end
        if #matching == 0 then
            local message
            if action_error then message = "News action failed: " .. action_error
            elseif not value or #value.items == 0 then message = "No stories yet. Check the configured feed or add approved RSS/Atom URLs."
            elseif view_unread then message = "No unread stories in this view."
            else message = "No stories in this category." end
            local empty = options.label(escape(message), palette.muted, 9, false)
            empty.wrap, empty.valign = "word_char", "top"
            list:add(wibox.widget {empty, left = 8, right = 8, top = 12, bottom = 12,
                widget = wibox.container.margin})
        end
        scroll_offset = 0
        viewport:emit_signal("widget::layout_changed")
        list_column:emit_signal("widget::layout_changed")
    end
    local function render_filters()
        for category, button in pairs(component.category_buttons or {}) do
            button.set_text((category == view_category and "• " or "") .. options.category_names[category])
        end
        component.unread_button.set_text((view_unread and "• " or "") .. "Unread")
        component.all_button.set_text((not view_unread and "• " or "") .. "All")
    end
    local function update_summary(state)
        local value = state and state.value
        local unread = value and value.unread or 0
        set_markup(count_text, string.format("<span foreground='%s'>%d unread</span>",
            unread > 0 and palette.teal or palette.muted, unread))
        if state and state.error then
            set_markup(popup_status, string.format("<span foreground='%s'>STALE · %s</span>",
                palette.amber, escape(state.error)))
        elseif value then
            local errors = {}
            for _, feed in ipairs(value.feeds or {}) do
                if feed.error and feed.error ~= "" then
                    errors[#errors + 1] = feed.label .. ": " .. feed.error
                end
            end
            if #errors > 0 then
                set_markup(popup_status, string.format("<span foreground='%s'>Feed issue · %s</span>",
                    palette.amber, escape(table.concat(errors, " · "))))
            elseif value.source_updated and value.source_updated > 0 then
                local visible_items = #M.filtered(value.items, view_unread, view_category)
                local scroll_hint = visible_items > 5 and " · Scroll for more" or ""
                set_markup(popup_status, string.format("<span foreground='%s'>Last checked %s · %d unread%s</span>",
                    palette.muted, os.date("%d %b %H:%M", value.source_updated), unread, scroll_hint))
            else
                set_markup(popup_status, "<span foreground='" .. palette.muted .. "'>Waiting for a successful feed refresh</span>")
            end
        elseif state and state.error then
            set_markup(popup_status, "<span foreground='" .. palette.amber .. "'>Feed unavailable</span>")
        end
    end
    function component.render(state)
        if ui.disposed then return end
        current_state = state
        update_summary(state)
        render_filters()
        render_list(state and state.value)
    end

    local top_actions = wibox.layout.fixed.horizontal()
    top_actions.spacing = 4
    local unread_button = options.button("Unread", function()
        view_unread = true; component.render(current_state)
    end, 70, ui)
    local all_button = options.button("All", function()
        view_unread = false; component.render(current_state)
    end, 52, ui)
    component.unread_button, component.all_button = unread_button, all_button
    top_actions:add(unread_button); top_actions:add(all_button)
    local category_buttons = {}
    for _, category in ipairs({"all", "general", "bydgoszcz", "torun", "cinema"}) do
        local button = options.button(options.category_names[category], function()
            view_category = category; component.render(current_state)
        end, category == "bydgoszcz" and 84 or 72, ui)
        category_buttons[category] = button
        filter_row:add(button)
    end
    component.category_buttons = category_buttons
    local right_actions = wibox.layout.fixed.horizontal()
    right_actions.spacing = 4
    right_actions:add(options.button("Mark all read", function() perform_action("mark-all-read") end, 102, ui))
    right_actions:add(options.button("Refresh", function() data.refresh("news") end, 62, ui))
    local close_button = options.button("×", function() component.hide() end, 28, ui)
    right_actions:add(close_button)
    toolbar:add(top_actions)
    toolbar:add(wibox.widget {title, widget = wibox.container.place})
    toolbar:add(right_actions)
    local popup_widget = wibox.widget {
        {toolbar, forced_height = 30, bg = appearance.gradient("selected", 30),
            widget = wibox.container.background},
        {filter_row, forced_height = 28, bg = "#17283bf5",
            widget = wibox.container.background},
        {list_column, left = 8, right = 8, top = 8, bottom = 8,
            widget = wibox.container.margin},
        forced_width = options.popup_width,
        spacing = 0,
        layout = wibox.layout.fixed.vertical,
    }
    popup = awful.popup {
        screen = s, visible = false, ontop = true, type = "utility",
        width = options.popup_width, maximum_width = options.popup_width,
        maximum_height = options.popup_height, minimum_width = options.popup_width,
        bg = palette.bg, fg = palette.text,
        border_width = 1, border_color = palette.active_border,
        shape = gears.shape.rectangle, restrict_workarea = false,
        preferred_positions = {"left", "right", "top", "bottom"},
        preferred_anchors = {"middle", "front", "back"},
        offset = {x = 8, y = 0}, widget = popup_widget,
    }
    component.popup = popup
    local current_anchor
    local function position_popup()
        if not current_anchor then return end
        local screen_geo = s.geometry
        local left = s.sidebar.x - popup.width - 8
        local right = s.sidebar.x + s.sidebar.width + 8
        local x = left >= screen_geo.x and left
            or math.min(right, screen_geo.x + screen_geo.width - popup.width)
        local y = current_anchor.y + current_anchor.height / 2 - popup.height / 2
        y = math.max(screen_geo.y, math.min(y, screen_geo.y + screen_geo.height - popup.height))
        popup.x, popup.y = math.floor(x), math.floor(y)
    end
    popup:connect_signal("property::height", position_popup)
    popup:connect_signal("property::width", position_popup)
    component.body, component.open_button = body, nil
    component.item_controls = {}
    component.unread_label = count_text

    local function remove_escape_binding()
        if not escape_binding then return end
        local current = root.keys()
        local remaining = {}
        for _, key in ipairs(current) do
            if key ~= escape_binding then remaining[#remaining + 1] = key end
        end
        root.keys(remaining)
        escape_binding = nil
    end
    local function add_escape_binding()
        if escape_binding then return end
        escape_binding = awful.key({}, "Escape", function() component.hide() end,
            {description = "close sidebar news", group = "sidebar"})
        root.keys(gears.table.join(root.keys(), escape_binding))
    end
    function component.hide()
        if not popup.visible then
            if active_instance == component then active_instance = nil end
            remove_escape_binding()
            return
        end
        popup.visible = false
        if active_instance == component then active_instance = nil end
        remove_escape_binding()
        if leave_timer.started then leave_timer:stop() end
    end
    function component.open()
        if ui.disposed or not s.valid or not s.sidebar or not s.sidebar.visible then return end
        if popup.visible then component.hide(); return end
        if active_instance and active_instance ~= component then active_instance.hide() end
        if options.dismiss then options.dismiss() end
        local state = data.state("news")
        if state.updated == nil or state.stale or not state.value
            or os.time() - (state.value.last_attempt or 0) >= 1800 then
            data.refresh("news")
        end
        component.render(state)
        local anchor = options.anchor()
        if not anchor then return end
        current_anchor = anchor
        popup.visible = true
        position_popup()
        active_instance = component
        add_escape_binding()
    end
    open_button = options.button("Open", component.open, 66, ui)
    component.open_button = open_button
    body_actions:add(open_button)
    component.close_button = close_button
    component.refresh_button = right_actions:get_children()[2]
    component.mark_all_button = right_actions:get_children()[1]
    component.view_category = function() return view_category end
    component.view_unread = function() return view_unread end
    component.scroll_offset = function() return scroll_offset end
    component.filtered_items = function()
        return M.filtered(current_state and current_state.value and current_state.value.items or {},
            view_unread, view_category)
    end
    local function on_mouse_enter()
        if leave_timer.started then leave_timer:stop() end
    end
    local function on_mouse_leave()
        if leave_timer.started then leave_timer:stop() end
        leave_timer:start()
    end
    popup:connect_signal("mouse::enter", on_mouse_enter)
    popup:connect_signal("mouse::leave", on_mouse_leave)
    popup:connect_signal("button::press", function(_, _, _, button)
        if button == 4 then component.scroll_by(-100)
        elseif button == 5 then component.scroll_by(100) end
    end)
    leave_timer = gears.timer {timeout = 0.55, single_shot = true, callback = function()
        if popup.visible then component.hide() end
    end}
    local attached = false
    function component.attach()
        if attached or not s.sidebar then return end
        attached = true
        ui.connect(s.sidebar, "property::visible", function()
            if not s.sidebar.visible then component.hide() end
        end)
    end
    ui.connect(s, "property::geometry", function() component.hide() end)
    local function close_on_focus(c)
        if popup.visible and c.screen == s then component.hide() end
    end
    client.connect_signal("focus", close_on_focus)
    ui.add(function() client.disconnect_signal("focus", close_on_focus) end)
    local destroyed = false
    function component.destroy()
        if destroyed then return end
        destroyed = true
        component.hide()
        if leave_timer.started then leave_timer:stop() end
        if row_lifetime then row_lifetime.destroy(); row_lifetime = nil end
        popup:disconnect_signal("mouse::enter", on_mouse_enter)
        popup:disconnect_signal("mouse::leave", on_mouse_leave)
        popup:disconnect_signal("property::height", position_popup)
        popup:disconnect_signal("property::width", position_popup)
    end
    ui.add(component.destroy)
    component.render(nil)
    return component
end

return M
