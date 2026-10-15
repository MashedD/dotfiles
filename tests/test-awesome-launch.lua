-- lua tests/test-awesome-launch.lua
local module = dofile('dotfiles/.config/awesome/sidebar-launch.lua')
local installed = {kitty = '/bin/kitty', btop = '/bin/btop'}
local executable = {['/bin/kitty'] = true, ['/bin/btop'] = true, ['/games/q2.sh'] = false}
local launched, notifications, logs = {}, {}, {}
local launch = module.new {
    resolve = function(name) return installed[name] end,
    executable = function(path) return executable[path] == true end,
    spawn = function(argv)
        launched[#launched + 1] = argv
        if argv[1] == 'spawn-error' then return 'cannot execute' end
        return 123
    end,
    notify = function(label, message) notifications[#notifications + 1] = label .. ':' .. message end,
    log = function(message) logs[#logs + 1] = message end,
}
local terminal = {label = 'Terminal', argv = {'kitty'}, requires = {'kitty'}}
assert(launch.tooltip(terminal) == 'Terminal')
assert(launch.run(terminal) and #launched == 1 and #notifications == 0)
local monitor = {label = 'Monitor', argv = {'kitty', 'btop'}, requires = {'kitty', 'btop'}}
installed.btop = nil
assert(launch.tooltip(monitor) == 'Monitor · Missing: btop')
local ok, missing = launch.run(monitor)
assert(not ok and missing == 'btop' and #launched == 1 and #notifications == 1)
installed.btop = '/bin/btop'
installed['spawn-error'] = '/bin/spawn-error'
executable['/bin/spawn-error'] = true
assert(launch.run(monitor) and #launched == 2, 'a missing app can recover without restart')
local script = {label = 'Quake 2', argv = {'/games/q2.sh'}, requires = {'/games/q2.sh'}}
assert(launch.tooltip(script):find('Missing: /games/q2.sh', 1, true))
executable['/games/q2.sh'] = true
assert(launch.run(script) and #launched == 3)
local failing = {label = 'Broken', argv = {'spawn-error'}}
local failed, reason = launch.run(failing)
assert(not failed and reason == 'cannot execute' and #notifications == 2)
local malicious = {label = 'X & <Y>', argv = {'kitty'}, requires = {'missing<&'}}
assert(launch.tooltip(malicious) == 'X &amp; &lt;Y&gt; · Missing: missing&lt;&amp;')
local fallback
local offline = module.new {
    resolve = function() return nil end, executable = function() return false end,
    spawn = function() error('must not spawn') end,
    notify = function() error('notify-send unavailable') end,
    log = function(message) fallback = message end,
}
assert(not offline.run(malicious) and fallback:find('notify%-send unavailable'))
print('Awesome launch tests passed')
