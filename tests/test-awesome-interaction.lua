-- lua tests/test-awesome-interaction.lua
local interaction = dofile('dotfiles/.config/awesome/interaction.lua')
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
