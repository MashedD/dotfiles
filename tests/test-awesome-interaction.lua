-- lua tests/test-awesome-interaction.lua
local interaction = dofile('dotfiles/.config/awesome/interaction.lua')
assert(interaction.modifiers_match({}, {}))
assert(interaction.modifiers_match({'Mod4', 'Lock'}, {'Mod4'}))
assert(interaction.modifiers_match({'Mod2'}, {}))
assert(not interaction.modifiers_match({'Shift'}, {}))
assert(not interaction.modifiers_match({'Mod4'}, {}))
local function close_to(a, b) return math.abs(a - b) < 1e-8 end
assert(close_to(interaction.transition_value(0, 100, 10, 1, 10), 0))
assert(close_to(interaction.transition_value(0, 100, 10, 1, 10.5), 50))
assert(close_to(interaction.transition_value(0, 100, 10, 1, 11), 100))
assert(close_to(interaction.transition_value(0, 100, 10, 1, 11.5), 100))
local middle = interaction.transition_value(0, 100, 10, 1, 10.4)
assert(close_to(middle, 40))
assert(close_to(interaction.transition_value(middle, 0, 10.4, 0.6, 10.4), middle))
assert(close_to(interaction.transition_value(middle, 0, 10.4, 0.6, 10.7), 20))
assert(close_to(interaction.transition_value(middle, 0, 10.4, 0.6, 11.1), 0))
assert(interaction.transition_value(80, 0, 20, 0, 20) == 0)
local paint_count, last_paint = 0, nil
local paint = interaction.deduplicate_paint(function(pressed, hovered)
    paint_count = paint_count + 1; last_paint = tostring(pressed)..":"..tostring(hovered)
end)
assert(paint(false, false)); assert(not paint(false, false)); assert(paint(true, false))
assert(paint_count == 2 and last_paint == "true:false")
assert(paint(false, false)); assert(paint(false, true)); assert(not paint(false, true))
assert(paint_count == 4 and last_paint == "false:true")
local old_mousegrabber = _G.mousegrabber
local running, native_stops, native_callback = false, 0, nil
_G.mousegrabber = {
    isrunning = function() return running end,
    run = function(callback) running=true; native_callback=callback end,
    stop = function() running=false; native_stops=native_stops+1 end,
}
local owner_a, owner_b = {}, {}
assert(interaction.start_grab(owner_a, function() return true end, "left_ptr"))
assert(not interaction.start_grab(owner_b, function() return true end))
assert(interaction.owns_grab(owner_a) and not interaction.stop_grab(owner_b) and native_stops == 0)
running = false -- Another owner stopped the native grab; do not stop anything else.
assert(not interaction.owns_grab(owner_a) and interaction.stop_grab(owner_a) and native_stops == 0)
assert(interaction.start_grab(owner_b, function() return false end))
local keep = native_callback({})
if not keep then running = false end
assert(not keep and not running and not interaction.owns_grab(owner_b))
_G.mousegrabber = old_mousegrabber
local count, valid, changed = 0, true, 0
local state = interaction.press_state {
    valid = function() return valid end,
    activate = function() count = count + 1 end,
    changed = function() changed = changed + 1 end,
}
assert(not state.press(3))
state.release(3, true); assert(count == 0)
assert(state.press(1)); assert(count == 0 and state.armed)
state.release(1, true); state.release(1, true); assert(count == 1)
state.press(1); state.move(false); state.release(1, false); assert(count == 1)
state.press(1); state.move(false); state.move(true); state.release(1, true); assert(count == 2)
state.press(1); valid = false; state.release(1, true); assert(count == 2 and not state.armed)
valid = true; state.press(1); state.cancel(); state.release(1, true); assert(count == 2)
state.press(1); state.destroy(); state.release(1, true); assert(count == 2)
assert(not state.press(1) and changed > 0)
print('Awesome interaction tests passed')
