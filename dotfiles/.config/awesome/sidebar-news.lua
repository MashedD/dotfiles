-- Full-height, sidebar-adjacent RSS inbox; feed I/O and persistence live in desktop-news.
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
    local popup, popup_widget, current_state, action_error
    local row_lifetime
    local view_unread, view_category = true, "all"
    local scroll_offset, scroll_target, content_height = 0, 0, 0
    local content_width, content_dpi
    local viewport_height = options.list_height
    local scrollbar_dragging
    local scrollbar_owner = {}
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
    local measured_rows = {}
    local viewport = wibox.widget.base.make_widget()
    local scrollbar
    local function max_scroll()
        return math.max(0, content_height - viewport_height)
    end
    local function clamp_scroll(value)
        return math.max(0, math.min(max_scroll(), value))
    end
    local function redraw_scroll()
        viewport:emit_signal("widget::layout_changed")
        viewport:emit_signal("widget::redraw_needed")
        if scrollbar then scrollbar:emit_signal("widget::redraw_needed") end
    end
    local module_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
    local spring = dofile(module_dir .. "scroll-spring.lua").new(
        redraw_scroll, options.interaction.monotonic_time)
    ui.add(spring.reset)
    local function scroll_to(value)
        local next_offset = clamp_scroll(value)
        if next_offset == scroll_offset and next_offset == scroll_target then return false end
        scroll_offset, scroll_target = next_offset, next_offset
        redraw_scroll()
        return true
    end
    local function measure_content(context, width)
        local dpi = context and context.dpi
        if content_width ~= width or content_dpi ~= dpi then
            -- Measure once per content/width change, not once per wheel event.
            measured_rows = {}
            local top = 0
            for _, row in ipairs(list:get_children()) do
                local _, height = wibox.widget.base.fit_widget(viewport, context, row, width, 2^20)
                measured_rows[#measured_rows + 1] = {widget = row, top = top, height = height}
                top = top + height + list.spacing
            end
            content_width, content_dpi = width, dpi
            content_height = math.max(0, top - (#measured_rows > 0 and list.spacing or 0))
        end
        return content_height
    end
    viewport.fit = function(_, context, width)
        local list_width = math.max(0, width - 14)
        local height = measure_content(context, list_width)
        return list_width, math.min(height, options.list_height)
    end
    viewport.layout = function(_, context, width, height)
        local measured = measure_content(context, width)
        content_height, viewport_height = measured, height
        scroll_offset, scroll_target = clamp_scroll(scroll_offset), clamp_scroll(scroll_target)
        -- Virtualize the hierarchy: offscreen stories must not participate in
        -- drawing, hit testing or hierarchy updates. Binary search the first row.
        local low, high = 1, #measured_rows
        while low <= high do
            local middle = math.floor((low + high) / 2)
            local row = measured_rows[middle]
            if row.top + row.height <= scroll_offset then low = middle + 1
            else high = middle - 1 end
        end
        local placements = {}
        local bottom = scroll_offset + height
        for index = low, #measured_rows do
            local row = measured_rows[index]
            if row.top >= bottom then break end
            placements[#placements + 1] = wibox.widget.base.place_widget_at(
                row.widget, 0, row.top - scroll_offset - spring.value(), width, row.height)
        end
        component.visible_row_count = #placements
        return placements
    end
    viewport.draw = function() end
    viewport.before_draw_children = function(_, _, cr, width, height)
        cr:save(); cr:rectangle(0, 0, width, height); cr:clip()
    end
    viewport.after_draw_children = function(_, _, cr)
        cr:restore()
    end
    viewport.forced_height = options.list_height
    function component.scroll_by(delta, edge_feedback)
        local requested = scroll_target + delta
        if edge_feedback and max_scroll() > 0 and requested ~= clamp_scroll(requested) then
            spring.kick(requested - clamp_scroll(requested))
        else
            spring.reset()
        end
        return scroll_to(requested)
    end
    component.viewport = viewport

    scrollbar = wibox.widget.base.make_widget()
    scrollbar.forced_width = 14
    scrollbar.fit = function(_, _, width, height) return width, height end
    local function thumb_geometry(height)
        if content_height <= viewport_height or viewport_height <= 0 then return 0, height end
        local thumb_height = math.min(height, math.max(28,
            math.floor(height * viewport_height / content_height)))
        local range = math.max(0, height - thumb_height)
        local top = max_scroll() > 0 and range * scroll_offset / max_scroll() or 0
        return top, thumb_height
    end
    scrollbar.draw = function(_, _, cr, width, height)
        cr:set_source(gears.color(palette.scrollbar_track)); cr:rectangle(0, 0, width, height); cr:fill()
        local rail_width = 4
        local rail_x = math.floor((width - rail_width) / 2)
        cr:set_source(gears.color(palette.scrollbar_rail)); cr:rectangle(rail_x, 0, rail_width, height); cr:fill()
        local top, thumb_height = thumb_geometry(height)
        cr:set_source(appearance.gradient("scrollbar", math.max(1, thumb_height)))
        cr:rectangle(math.max(0, rail_x - 2), top, math.min(width, rail_width + 4), thumb_height); cr:fill()
        cr:set_source(gears.color(palette.scrollbar_highlight))
        cr:rectangle(math.max(0, rail_x - 1), top + 1, math.min(width, rail_width + 2), 1); cr:fill()
    end
    scrollbar:connect_signal("button::press", function(_, _, y, button, _, geometry)
        if button ~= 1 or max_scroll() <= 0 or mousegrabber.isrunning() or not geometry
            or not geometry.hierarchy or not geometry.drawable then return end
        local top, thumb_height = thumb_geometry(viewport_height)
        local range = math.max(1, viewport_height - thumb_height)
        if y < top or y > top + thumb_height then
            component.scroll_by((y < top and -1 or 1) * math.max(80, viewport_height * 0.8))
            return
        end
        local matrix = geometry.hierarchy:get_matrix_from_device()
        local window_geometry = geometry.drawable.drawable:geometry()
        matrix = matrix:translate(-window_geometry.x, -window_geometry.y)
        local grab_offset = y - top
        scrollbar_dragging = true
        local started = options.interaction.start_grab(scrollbar_owner, function(pointer)
            if not scrollbar_dragging or ui.disposed or not popup.visible then return false end
            local _, local_y = matrix:transform_point(pointer.x, pointer.y)
            local new_top = math.max(0, math.min(range, local_y - grab_offset))
            scroll_to((new_top / range) * max_scroll())
            if pointer.buttons[1] then return true end
            scrollbar_dragging = false
            return false
        end, "sb_v_double_arrow")
        if not started then scrollbar_dragging = false end
    end)
    component.scrollbar = scrollbar

    local popup_status = options.label("Waiting for first feed refresh…", palette.muted, 9, false)
    popup_status.wrap = "word_char"
    local title = options.label("NEWS READER", palette.title, 10, true, "center")
    local toolbar = wibox.layout.fixed.horizontal()
    toolbar.spacing = 4
    local filter_rows = wibox.layout.fixed.vertical()
    filter_rows.spacing = 2
    component.filter_rows = filter_rows
    local filter_lifetime, filter_signature
    local update_popup_list_height
    local list_column = wibox.layout.fixed.vertical()
    list_column.spacing = 5
    local scroll_row = wibox.layout.fixed.horizontal()
    scroll_row.spacing = 0
    scroll_row:add(viewport)
    scroll_row:add(scrollbar)
    scroll_row.forced_height = options.list_height
    list_column:add(popup_status)
    list_column:add(scroll_row)

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
        scroll_offset, scroll_target = 0, 0
        content_width, content_dpi, content_height = nil, nil, 0
        viewport:emit_signal("widget::layout_changed")
        list_column:emit_signal("widget::layout_changed")
        if scrollbar then scrollbar:emit_signal("widget::redraw_needed") end
    end
    local function render_filters(value)
        local categories = value and value.categories or {}
        local signature_parts = {}
        for _, category in ipairs(categories) do
            signature_parts[#signature_parts + 1] = category.id .. "\0" .. category.label
        end
        local signature = table.concat(signature_parts, "\n")
        if signature ~= filter_signature then
            filter_signature = signature
            if filter_lifetime then filter_lifetime.destroy() end
            filter_lifetime = options.interaction.lifetime()
            filter_rows:reset()
            component.category_buttons = {}
            local row, row_width
            local width_limit = math.max(1, options.popup_width - 16)
            local function add_filter(category_id, label)
                local width = category_id == "all" and 52 or math.min(110, math.max(58, #label * 6 + 16))
                local spacing = row and #row:get_children() > 0 and row.spacing or 0
                if not row or row_width + spacing + width > width_limit then
                    row = wibox.layout.fixed.horizontal()
                    row.spacing = 3
                    row_width = 0
                    filter_rows:add(row)
                    spacing = 0
                end
                local button = options.button(label, function()
                    view_category = category_id
                    component.render(current_state)
                end, width, filter_lifetime)
                component.category_buttons[category_id] = button
                row:add(button)
                row_width = row_width + spacing + width
            end
            add_filter("all", "All")
            local available = {all = true}
            for _, category in ipairs(categories) do
                available[category.id] = true
                add_filter(category.id, category.label)
            end
            if not available[view_category] then view_category = "all" end
        end
        for category, button in pairs(component.category_buttons) do
            local label = category == "all" and "All" or (value and value.category_map
                and value.category_map[category] and value.category_map[category].label or category)
            button.set_text((category == view_category and "• " or "") .. label)
        end
        component.unread_button.set_text((view_unread and "• " or "") .. "Unread")
        component.all_button.set_text((not view_unread and "• " or "") .. "All")
        if update_popup_list_height then update_popup_list_height() end
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
        render_filters(state and state.value)
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
    component.category_buttons = {}
    local right_actions = wibox.layout.fixed.horizontal()
    right_actions.spacing = 4
    right_actions:add(options.button("Mark all read", function() perform_action("mark-all-read") end, 102, ui))
    right_actions:add(options.button("Refresh", function() data.refresh("news") end, 62, ui))
    local close_button = options.button("×", function() component.hide() end, 28, ui)
    right_actions:add(close_button)
    toolbar:add(top_actions)
    toolbar:add(wibox.widget {title, widget = wibox.container.place})
    toolbar:add(right_actions)
    popup_widget = wibox.widget {
        {toolbar, forced_height = 30, bg = appearance.gradient("selected", 30),
            widget = wibox.container.background},
        {filter_rows, bg = "#17283bf5",
            widget = wibox.container.background},
        {list_column, left = 8, right = 8, top = 8, bottom = 8,
            widget = wibox.container.margin},
        forced_width = options.popup_width,
        spacing = 0,
        layout = wibox.layout.fixed.vertical,
    }
    update_popup_list_height = function()
        local _, natural_height = popup_widget:fit({dpi = s.dpi or 96}, options.popup_width, 2^20)
        local target_height = math.floor(math.max(120,
            options.list_height + options.popup_height - 2 - natural_height))
        if target_height == options.list_height then return end
        options.list_height = target_height
        viewport.forced_height = target_height
        scroll_row.forced_height = target_height
        list_column:emit_signal("widget::layout_changed")
        popup_widget:emit_signal("widget::layout_changed")
    end
    popup = awful.popup {
        screen = s, visible = false, ontop = true, type = "utility",
        width = options.popup_width, height = options.popup_height,
        minimum_width = options.popup_width, maximum_width = options.popup_width,
        minimum_height = options.popup_height, maximum_height = options.popup_height,
        bg = palette.bg, fg = palette.text,
        border_width = 1, border_color = palette.active_border,
        shape = gears.shape.rectangle, restrict_workarea = false,
        widget = popup_widget,
    }
    component.popup = popup
    local function position_popup()
        if not s.sidebar then return end
        local screen_geo, side = s.geometry, s.sidebar
        local left = side.x - popup.width
        local right = side.x + side.width
        local fits_left = left >= screen_geo.x
        local fits_right = right + popup.width <= screen_geo.x + screen_geo.width
        local x = fits_left and left or (fits_right and right
            or math.max(screen_geo.x, screen_geo.x + screen_geo.width - popup.width))
        popup.x, popup.y = math.floor(x), math.floor(side.y)
    end
    popup:connect_signal("property::height", position_popup)
    popup:connect_signal("property::width", position_popup)
    component.body, component.open_button = body, nil
    component.item_controls = {}
    component.unread_label = count_text

    function component.hide()
        popup.visible = false
        spring.reset()
        if scrollbar_dragging then
            scrollbar_dragging = false
            options.interaction.stop_grab(scrollbar_owner)
        end
        if active_instance == component then active_instance = nil end
        if open_button then open_button.set_text("Open") end
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
        popup.visible = true
        position_popup()
        active_instance = component
        if open_button then open_button.set_text("Close") end
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
    popup:connect_signal("button::press", function(_, _, _, button)
        if button == 4 then component.scroll_by(-160, true)
        elseif button == 5 then component.scroll_by(160, true) end
    end)
    local attached = false
    function component.attach()
        if attached or not s.sidebar then return end
        attached = true
        ui.connect(s.sidebar, "property::visible", function()
            if not s.sidebar.visible then component.hide() end
        end)
    end
    ui.connect(s, "property::geometry", function() component.hide() end)
    local destroyed = false
    function component.destroy()
        if destroyed then return end
        destroyed = true
        component.hide()
        if row_lifetime then row_lifetime.destroy(); row_lifetime = nil end
        if filter_lifetime then filter_lifetime.destroy(); filter_lifetime = nil end
        popup:disconnect_signal("property::height", position_popup)
        popup:disconnect_signal("property::width", position_popup)
    end
    ui.add(component.destroy)
    component.render(nil)
    return component
end

return M
