-- Document parsing and Monday-first inline calendar, independent of screen state.
local M = {}
function M.read(path, include_all)
    local file = io.open(path, "r")
    if not file then return {} end
    local today = os.date("%Y-%m-%d")
    local all, past, current, future = {}, {}, {}, {}
    for line in file:lines() do
        local year, month, day, description = line:match("^%s*(%d%d%d%d)%-(%d%d)%-(%d%d)%s+(.+)%s*$")
        if year then
            year, month, day = tonumber(year), tonumber(month), tonumber(day)
            if day > 0 and month > 0 and month <= 12 then
                local stamp = os.time {year = year, month = month, day = day, hour = 12}
                if os.date("%Y-%m-%d", stamp) == string.format("%04d-%02d-%02d", year, month, day) then
                    local a, b = description:find("%d%d:%d%d%s*%-%s*%d%d:%d%d")
                    if not a then a, b = description:find("%d%d:%d%d") end
                    local time = a and description:sub(a, b):gsub("%s+", "") or nil
                    local text = description
                    if a then
                        text = description:sub(1, a - 1) .. description:sub(b + 1)
                        text = text:gsub(":%s*,", ":", 1):gsub("^%s*[,;:]%s*", "")
                    end
                    text = text:gsub("%s+", " "):gsub("^%s+", "")
                        :gsub("^%s*[,;:]%s*", ""):gsub("%s*[,;:]%s*$", "")
                    local entry = {date = os.date("%Y-%m-%d", stamp), timestamp = stamp, time = time, text = text}
                    entry.day = entry.date < today and "past" or (entry.date == today and "today" or "future")
                    all[#all + 1] = entry
                    local bucket = entry.day == "past" and past or (entry.day == "today" and current or future)
                    bucket[#bucket + 1] = entry
                end
            end
        end
    end
    file:close()
    local function less(a, b)
        if a.date ~= b.date then return a.date < b.date end
        return (a.time or "") < (b.time or "")
    end
    table.sort(all, less)
    if include_all then return all end
    table.sort(past, less); table.sort(current, less); table.sort(future, less)
    local entries = {}
    if #past > 0 then entries[#entries + 1] = past[#past] end
    for _, entry in ipairs(current) do entries[#entries + 1] = entry end
    for i = 1, math.min(3, #future) do entries[#entries + 1] = future[i] end
    return entries
end
-- Calendar arithmetic uses local noon, including across DST boundaries.
function M.move_date(date, key, today)
    local y,m,d=date:match('^(%d+)%-(%d+)%-(%d+)$')
    y,m,d=tonumber(y),tonumber(m),tonumber(d)
    if not y or not m or not d then return end
    local days={Left=-1,Right=1,Up=-7,Down=7}
    if days[key] then d=d+days[key]
    elseif key=='Page_Up' or key=='Page_Down' then
        local month=os.date('*t',os.time{year=y,month=m+(key=='Page_Up' and -1 or 1),day=1,hour=12})
        y,m=month.year,month.month
        d=math.min(d,tonumber(os.date('%d',os.time{year=y,month=m+1,day=0,hour=12})))
    elseif key=='Home' then return today or os.date('%Y-%m-%d')
    elseif key=='End' then d=tonumber(os.date('%d',os.time{year=y,month=m+1,day=0,hour=12}))
    elseif key~='Current' then return end
    return os.date('%Y-%m-%d',os.time{year=y,month=m,day=d,hour=12})
end
if not awesome then return M end
local awful = require("awful")
local gears = require("gears")
local wibox = require("wibox")
local gstring = require("gears.string")
function M.create(options)
    local ui = options.interaction.lifetime()
    local palette, label = options.appearance.palette, options.label
    local entries, cells = {}, {}
    local selected = os.date("%Y-%m-%d")
    local observed_day = selected
    local view_month = os.time {year = tonumber(selected:sub(1,4)), month = tonumber(selected:sub(6,7)), day = 1, hour = 12}
    local title = label("", "#edfaff", 10, true, "center")
    local selected_title = label("", palette.teal, 9, true)
    local grid, events = wibox.layout.fixed.vertical(), wibox.layout.fixed.vertical()
    grid.spacing, events.spacing = 2, 3
    local weekdays = {"Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"}
    local component = {grid = grid, events = events, weekday_order = table.concat(weekdays), ui = ui}
    local render
    local function open()
        if not ui.disposed and not options.blocked() then options.open() end
    end
    local function row(entry)
        local now = os.date("*t")
        local yesterday = os.date("%Y-%m-%d", os.time {year = now.year, month = now.month, day = now.day - 1, hour = 12})
        local dc, tc, ec, weight = palette.muted, palette.muted, palette.muted, "normal"
        if entry.day == "today" then dc, tc, ec, weight = palette.neon, "#ffe08a", "#ffffff", "bold"
        elseif entry.day == "future" then dc, tc, ec = palette.teal, palette.green, palette.text end
        local short_date = os.date("%d.%m", entry.timestamp)
        local date_text = entry.day == "today" and ("TODAY · " .. short_date)
            or (entry.date == yesterday and ("YDAY · " .. short_date) or os.date("%a · %d.%m", entry.timestamp):upper())
        local metadata = wibox.widget {
            label(date_text, dc, 9, true), label(entry.time or "ALL DAY", tc, 9, false),
            spacing = 1, forced_width = 82, layout = wibox.layout.fixed.vertical,
        }
        local event_label = wibox.widget {
            markup = string.format("<span foreground='%s' size='10pt' weight='%s'>%s</span>", ec, weight, gstring.xml_escape(entry.text)),
            wrap = "word_char", valign = "top", widget = wibox.widget.textbox,
        }
        local content = wibox.widget {
            {
                {forced_width = 2, bg = dc, widget = wibox.container.background},
                {
                    {metadata, event_label, spacing = 7, layout = wibox.layout.fixed.horizontal},
                    left = 6, right = 5, top = 3, bottom = 3, widget = wibox.container.margin,
                }, layout = wibox.layout.fixed.horizontal,
            }, bg = "#0c1b15", border_width = 1, border_color = "#254238", widget = wibox.container.background,
        }
        content:connect_signal("mouse::enter", function() content.bg = "#152b21" end)
        content:connect_signal("mouse::leave", function() content.bg = "#0c1b15" end)
        content:buttons(gears.table.join(awful.button({}, 1, open)))
        return content
    end
    function component.select_date(date)
        if ui.disposed or options.blocked() then return end
        selected = date
        render()
    end
    function component.shift_month(delta)
        if ui.disposed then return end
        local current = os.date("*t", view_month)
        view_month = os.time {year = current.year, month = current.month + delta, day = 1, hour = 12}
        selected = os.date("%Y-%m-%d", view_month)
        render()
    end
    local function action(text, callback, tooltip)
        local widget = wibox.widget {
            label(text, "#d7eee8", 9, true, "center"), forced_width = 30, forced_height = 26,
            bg = options.button_normal, border_width = 1, border_color = palette.bevel_light,
            widget = wibox.container.background,
        }
        if options.bind then options.bind(widget, callback) else widget:buttons(gears.table.join(awful.button({}, 1, callback))) end
        ui.tip(widget, tooltip)
        return widget
    end
    component.previous = action("◀", function() component.shift_month(-1) end, "Previous month")
    component.next = action("▶", function() component.shift_month(1) end, "Next month")
    local navigation = wibox.layout.align.horizontal()
    navigation:set_left(component.previous); navigation:set_middle(title); navigation:set_right(component.next)
    local body = wibox.widget {
        navigation, {grid, halign = "center", widget = wibox.container.place}, selected_title, events,
        spacing = 5, layout = wibox.layout.fixed.vertical,
    }
    component.widget = options.wrap(body)
    render = function()
        if ui.disposed then return end
        local view = os.date("*t", view_month)
        title.text = os.date("%B %Y", view_month)
        local stamp = os.time {year = tonumber(selected:sub(1, 4)), month = tonumber(selected:sub(6, 7)), day = tonumber(selected:sub(9, 10)), hour = 12}
        selected_title.text = os.date("%A · %d %B %Y", stamp)
        local by_date = {}
        for _, event in ipairs(entries) do by_date[event.date] = (by_date[event.date] or 0) + 1 end
        grid:reset(); cells = {}
        local weekday_row = wibox.layout.fixed.horizontal()
        weekday_row.spacing = 2
        for index, name in ipairs(weekdays) do
            local weekend = index >= 6
            weekday_row:add(wibox.widget {
                label(name, weekend and palette.amber or palette.muted, 9, true, "center"),
                forced_width = 36, forced_height = 16, widget = wibox.container.background,
            })
        end
        grid:add(weekday_row)
        local first = (os.date("*t", view_month).wday + 5) % 7
        local days = tonumber(os.date("%d", os.time {year = view.year, month = view.month + 1, day = 0, hour = 12}))
        local weeks, day = math.ceil((first + days) / 7), 1
        for week = 1, weeks do
            local line = wibox.layout.fixed.horizontal()
            line.spacing = 2
            for column = 1, 7 do
                local index = (week - 1) * 7 + column - 1
                if index < first or day > days then
                    line:add(wibox.widget {forced_width = 36, forced_height = 27, widget = wibox.container.background})
                else
                    local date = string.format("%04d-%02d-%02d", view.year, view.month, day)
                    local is_selected, has_events = date == selected, by_date[date] ~= nil
                    local weekend = column >= 6
                    local color = date == os.date("%Y-%m-%d") and palette.neon
                        or (has_events and palette.teal or (weekend and palette.amber or palette.text))
                    local background = is_selected and "#1d5944"
                        or (has_events and "#10291f" or (weekend and "#211c12" or "#0e1d17"))
                    local cell = wibox.widget {
                        label(tostring(day), color, 9, is_selected or has_events or weekend, "center"),
                        forced_width = 36, forced_height = 24,
                        bg = background,
                        border_width = is_selected and 1 or 0, border_color = palette.neon, widget = wibox.container.background,
                    }
                    cell:buttons(gears.table.join(awful.button({}, 1, function() component.select_date(date) end)))
                    cells[date] = cell; line:add(cell); day = day + 1
                end
            end
            grid:add(line)
        end
        events:reset()
        local count = 0
        for _, entry in ipairs(entries) do
            if entry.date == selected then events:add(row(entry)); count = count + 1 end
        end
        if count == 0 then
            local empty = label("No events for this date", palette.muted, 9, false)
            empty:buttons(gears.table.join(awful.button({}, 1, open)))
            events:add(empty)
        end
        grid:emit_signal("widget::layout_changed"); events:emit_signal("widget::layout_changed")
        component.widget:emit_signal("widget::layout_changed")
    end
    function component.refresh()
        if ui.disposed then return end
        -- Follow a new local day once; same-day refreshes preserve browsing.
        local today = os.date("%Y-%m-%d")
        if today ~= observed_day then
            observed_day, selected = today, today
            view_month = os.time {year = tonumber(today:sub(1,4)), month = tonumber(today:sub(6,7)), day = 1, hour = 12}
        end
        entries = M.read(options.path, true)
        options.on_entries(entries)
        render()
    end
    function component.keyboard_key(key)
        if ui.disposed or options.blocked() then return false end
        local base = cells[selected] and selected or os.date('%Y-%m-01',view_month)
        local date = M.move_date(base,key)
        if not date then return false end
        selected=date
        view_month=os.time{year=tonumber(date:sub(1,4)),month=tonumber(date:sub(6,7)),day=1,hour=12}
        render()
        return true
    end
    function component.keyboard_cell() return cells[selected] or cells[os.date('%Y-%m-01',view_month)] end
    function component.month() return os.date("%Y-%m", view_month) end
    function component.selected_date() return selected end
    function component.day_cells() return cells end
    function component.destroy()
        if ui.disposed then return end
        ui.destroy()
        component.previous:buttons({}); component.next:buttons({})
        for _, child in ipairs(body:get_all_children()) do child:buttons({}) end
    end
    component.refresh()
    return component
end
return M
