-- Inactive clock representations must not invalidate the sidebar wibox.
local counts = {clock_redraws=0, digital_writes=0}
local function widget(kind)
    local state = {kind=kind}
    local methods = {
        buttons=function(self, value) state.buttons=value end,
        add=function(self, child)
            state.children=state.children or {};state.children[#state.children+1]=child
        end,
        connect_signal=function() end,
        emit_signal=function(self, name)
            if state.kind=='clock' and name=='widget::redraw_needed' then
                counts.clock_redraws=counts.clock_redraws+1
            end
        end,
    }
    return setmetatable({}, {
        __index=function(_, key) return methods[key] or state[key] end,
        __newindex=function(_, key, value)
            state[key]=value
            if state.kind=='digital' and key=='markup' then
                counts.digital_writes=counts.digital_writes+1
            end
        end,
    })
end

package.preload.awful=function()
    return {button=function(...) return {...} end}
end
package.preload.gears=function()
    return {table={join=function(...) return {...} end}}
end
package.preload.wibox=function()
    local widget_type=setmetatable({}, {__call=function(_, spec)
        return widget('composite')
    end})
    widget_type.base={make_widget=function() return widget('clock') end}
    return {
        widget=widget_type,
        layout={fixed={vertical=function() return widget('layout') end}},
        container={place={}},
    }
end
package.preload.lgi=function() return {cairo={}} end

local component_module=dofile('dotfiles/.config/awesome/sidebar-clock.lua')
local disposed=false
local ui={disposed=false}
function ui.destroy() disposed=true;ui.disposed=true end
function ui.tip() end
function ui.connect() end
local interaction={lifetime=function() return ui end}
local function label(text)
    return widget(text=='00:00:00' and 'digital' or (text=='' and 'date' or 'label'))
end
local component=component_module.create {
    interaction=interaction,
    appearance={palette={scrollbar_highlight='#abcdef'}},
    label=label,
    card=function(_, height) local result=widget('card');result.forced_height=height;return result end,
    on_mode=function() end,
}
assert(component.mode=='text')
local base=os.time()+10
component.tick(base)
local clock_before=counts.clock_redraws
local digital_before=counts.digital_writes
component.tick(base+1)
assert(counts.clock_redraws==clock_before,
    'Digital mode must not invalidate the hidden analog clock')
assert(counts.digital_writes==digital_before+1,
    'Digital clock text must update while text mode is active')

component.set_mode('analog')
local clock_analog=counts.clock_redraws
local digital_analog=counts.digital_writes
assert(clock_analog==clock_before+1,'Entering analog mode must draw the current time')
component.tick(base+2)
assert(counts.clock_redraws==clock_analog+1,
    'Analog mode must redraw the visible clock as seconds change')
assert(counts.digital_writes==digital_analog,
    'Analog mode must not update the hidden digital textbox')

component.set_mode('text')
local clock_text=counts.clock_redraws
local digital_text=counts.digital_writes
assert(digital_text==digital_analog+1,'Entering digital mode must refresh its current time')
assert(component.digital.markup:find(os.date('%H:%M:%S'),1,true),
    'The digital display must show the current time immediately after switching modes')
component.tick(base+3)
assert(counts.clock_redraws==clock_text,
    'Digital mode must leave the hidden analog clock untouched')
assert(counts.digital_writes==digital_text+1,
    'Digital mode must continue updating visible time text')
local unchanged=counts.digital_writes
component.set_mode('text')
assert(counts.digital_writes==unchanged,'Setting the active mode again must be a no-op')
component.destroy()
component.tick(base+4)
assert(disposed and counts.digital_writes==unchanged,
    'Disposed clock components must not continue updating widgets')
print('Awesome clock component redraw tests passed')
