-- Native adapter: no focusable window, polling timer, or input-catching overlay.
local awful=require('awful')
local gears=require('gears')
local keyboard=dofile((awesome.conffile:match('^(.*)/') or '.')..'/sidebar-keyboard.lua')
local M={}
-- Classic awful menus/prompts use a stack: remove our owner before another grab
-- starts, rather than resuming a stale sidebar session when that grab ends.
local native_owner
local native_run=awful.keygrabber.run
awful.keygrabber.run=function(callback)
    if native_owner and callback~=native_owner.native_grab then native_owner.stop() end
    return native_run(callback)
end
local function bounds(hierarchy,widget)
    if not hierarchy then return end
    if hierarchy:get_widget()==widget then
        local w,h=hierarchy:get_size()
        local x,y,width,height=hierarchy:get_matrix_to_device():transform_rectangle(0,0,w,h)
        return {x=x,y=y,width=width,height=height}
    end
    for _,child in ipairs(hierarchy:get_children()) do
        local r=bounds(child,widget); if r then return r end
    end
end
function M.create(o)
    local s,panel,ui=o.screen,o.panel,o.ui
    local controller
    local presented=false
    local function changed()
        if ui.disposed or not s.valid then return end
        if presented~=controller.active then
            presented=controller.active
            if s.sidebar_update_mode then s.sidebar_update_mode() end
        end
        panel.widget:emit_signal('widget::redraw_needed')
    end
    controller=keyboard.new {
        eligible=function()
            return not ui.disposed and s.valid and panel.visible and s.sidebar_mode>0
                and s.sidebar_keyboard_allowed and s.sidebar_keyboard_allowed()
        end,
        available=function() return not keygrabber.isrunning() and not mousegrabber.isrunning() end,
        start=function(callback)
            controller.native_grab=callback; native_owner=controller
            local ok,token=pcall(awful.keygrabber.run,callback)
            if not ok then native_owner=nil; controller.native_grab=nil; error(token) end
            return token
        end,
        stop=function(token)
            if native_owner==controller then native_owner=nil end
            controller.native_grab=nil
            awful.keygrabber.stop(token)
        end,
        targets=o.targets,changed=changed,
        shortcut=function(modifiers,key)
            if s.sidebar_keyboard_shortcut then return s.sidebar_keyboard_shortcut(modifiers,key) end
        end,
        start_menu=function() if s.sidebar_keyboard_start_menu then s.sidebar_keyboard_start_menu() end end,
        report=function(err) awesome.emit_signal('debug::error',err) end,
    }
    s.sidebar_keyboard=controller
    local root_widget=panel.widget
    local original=root_widget.after_draw_children
    root_widget.after_draw_children=function(self,context,cr,width,height)
        if original then original(self,context,cr,width,height) end
        if not controller.active then return end
        local t=controller.target(); if not t then return end
        local widget=t.resolve and t.resolve() or t.widget
        local hierarchy=panel._drawable._widget_hierarchy
        local r=bounds(hierarchy,widget)
        if not r then return end
        local clip={x=0,y=0,width=width,height=height}
        if t.section and not t.fixed then
            clip=bounds(hierarchy,o.scroll.view) or clip
            local delta=0
            if r.y<clip.y then delta=r.y-clip.y
            elseif r.height<=clip.height and r.y+r.height>clip.y+clip.height then
                delta=r.y+r.height-clip.y-clip.height
            end
            if math.abs(delta)>0.5 then
                local offset=o.scroll.offset()
                local next_offset=math.max(0,math.min(o.scroll.max(),offset+delta))
                if next_offset~=offset and not controller.pending then
                    controller.pending=true
                    local generation=controller.generation()
                    gears.timer.delayed_call(function()
                        controller.pending=false
                        if not controller.active or ui.disposed or controller.generation()~=generation then return end
                        local selected=controller.target()
                        local selected_widget=selected and (selected.resolve and selected.resolve() or selected.widget)
                        if selected and selected.id==t.id and selected_widget==widget then o.scroll.set_offset(next_offset)
                        else panel.widget:emit_signal('widget::redraw_needed') end
                    end)
                end
            end
        end
        cr:save(); cr:rectangle(clip.x,clip.y,clip.width,clip.height); cr:clip()
        cr:set_source_rgba(0.33,1,0.6,1); cr:set_line_width(2)
        cr:rectangle(r.x+1,r.y+1,math.max(0,r.width-2),math.max(0,r.height-2)); cr:stroke(); cr:restore()
    end
    ui.connect(panel,'button::press',controller.stop)
    if s.panel then ui.connect(s.panel,'button::press',controller.stop) end
    ui.connect(o.scroll.bar_panel,'button::press',controller.stop)
    ui.connect(panel,'property::visible',function() if not panel.visible then controller.stop() end end)
    local function class_connect(object,signal,callback)
        callback=callback or controller.stop
        object.connect_signal(signal,callback)
        ui.add(function() object.disconnect_signal(signal,callback) end)
    end
    class_connect(client,'focus')
    class_connect(client,'unfocus')
    class_connect(tag,'property::selected',function(t) if t.screen==s then controller.stop() end end)
    ui.connect(s,'property::geometry',controller.stop)
    ui.connect(s,'removed',controller.stop)
    ui.add(function() controller.stop(); root_widget.after_draw_children=original end)
    return controller
end
return M
