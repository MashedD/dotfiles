-- Pure document-parser regression tests, no X11 or real documents.
local calendar = dofile('dotfiles/.config/awesome/sidebar-calendar.lua')
local path = os.tmpname()
local file = assert(io.open(path, 'w'))
file:write('2024-02-29 08:15-09:00 Leap day\n2025-02-29 Invalid day\n',
    '2024-03-01 visit: 12:30, Appointment & notes\n2024-03-02 All day\n',
    'not an event\n2024-13-01 Bad month\n')
file:close()
local entries = calendar.read(path, true)
os.remove(path)
assert(#entries == 3)
assert(entries[1].date == '2024-02-29' and entries[1].time == '08:15-09:00')
assert(entries[2].time == '12:30' and entries[2].text == 'visit: Appointment & notes')
assert(entries[3].time == nil and entries[3].text == 'All day')
assert(#calendar.read(path, true) == 0)
print('Awesome calendar parser tests passed')
