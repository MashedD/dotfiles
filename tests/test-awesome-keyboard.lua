local M=dofile('dotfiles/.config/awesome/sidebar-keyboard.lua')
local function fixture()
    local f={eligible=true,available=true,changes=0,stops=0,actions=0,replays={},menus=0,errors={},shortcuts={}}
    f.items={{id='clock',activate=function() f.actions=f.actions+1 end},
        {id='a:header',section='a'}, {id='a:child',section='a'}, {id='b:header',section='b'}}
    f.options={
        eligible=function() return f.eligible end, available=function() return f.available end,
        targets=function() return f.items end,
        start=function(callback) f.callback=callback; return callback end,
        stop=function(token) assert(token==f.callback); f.stops=f.stops+1 end,
        changed=function() f.changes=f.changes+1 end,
        shortcut=function(_,key) return f.shortcuts[key] end,
        start_menu=function() f.menus=f.menus+1 end,
        report=function(err) f.errors[#f.errors+1]=err end,
    }
    f.c=M.new(f.options)
    function f.key(key,mods,event) f.c.event(mods or {},key,event or 'press') end
    function f.enter() f.c.toggle(); f.key('s',{},'release') end
    return f
end
local f=fixture(); f.enter(); assert(f.c.active and f.c.target().id=='clock')
f.key('Tab'); assert(f.c.target().id=='a:header')
f.key('ISO_Left_Tab',{'Shift','Lock','Mod2'}); assert(f.c.target().id=='clock')
f.key('Up'); assert(f.c.target().id=='b:header')
f.key('Home'); f.key('Return'); f.key('Return'); assert(f.actions==1)
f.key('Return',{},'release'); f.key('Return'); assert(f.actions==2)
f.key('Return',{},'release'); f.key('End'); assert(f.c.target().id=='b:header')
f.key('Home'); f.key('Tab'); f.key('Tab'); assert(f.c.target().id=='a:child')
table.remove(f.items,3); assert(f.c.target().id=='a:header')
f.items={f.items[3],f.items[1],f.items[2]}; assert(f.c.target().id=='a:header')
f.key('Tab'); assert(f.c.target().id=='b:header')
f.key('Escape'); assert(not f.c.active and f.stops==1 and #f.replays==0)
f.c.stop(); assert(f.stops==1)
-- Space can be a local secondary action while Enter launches and exits first.
f=fixture(); f.items[1].space=function() assert(f.c.active); f.actions=f.actions+1 end
f.items[1].exit=true; f.items[1].activate=function() assert(not f.c.active); f.actions=f.actions+1 end
f.enter(); f.key('space'); assert(f.c.active and f.actions==1)
f.key('Return'); assert(not f.c.active and f.actions==2)
-- Entry press/repeats must not immediately toggle the new session off.
f=fixture(); f.c.toggle(); f.key('s',{'Mod4'}); assert(f.c.active)
f.key('s',{'Mod4'},'release'); f.key('s',{'Mod4'}); assert(not f.c.active)
f.enter(); f.key('Super_L'); f.key('Super_L',{},'release'); assert(f.menus==1 and not f.c.active)
f.shortcuts.p=function() assert(not f.c.active); f.actions=f.actions+1 end
f.enter(); f.key('Super_L'); f.key('p',{'Mod4'}); assert(not f.c.active and f.actions==1)
f.enter(); f.key('a'); f.key('c',{'Control'}); assert(f.c.active and #f.replays==0)
f.key('Escape')
-- Eligibility, acquisition failures, callback failures, interruption, stale events.
f=fixture(); f.eligible=false; f.c.toggle(); assert(not f.c.active and not f.callback)
f.eligible=true; f.available=false; f.c.toggle(); assert(not f.c.active and not f.callback)
f.available=true; f.enter(); local old=f.callback; f.c.stop(); f.enter()
old({},'Escape','press'); assert(f.c.active)
f.eligible=false; f.key('Tab'); assert(not f.c.active)
f.eligible=true; f.items[1].activate=function() error('activation failed') end
f.enter(); f.key('Return'); assert(not f.c.active and #f.errors==1)
f=fixture(); f.enter(); local g=fixture(); g.c.toggle(); assert(not f.c.active and not g.c.active)
g.enter(); assert(g.c.active); g.c.stop()
f=fixture(); f.enter(); f.items={}; assert(not f.c.target() and not f.c.active)
f=fixture(); f.options.start=function() error('native acquisition failed') end
f.c.toggle(); assert(not f.c.active and #f.errors==1 and f.stops==0)
f=fixture(); f.enter(); f.key('Next'); assert(f.c.active); f.key('Prior'); assert(f.c.active); f.c.stop()
for _,path in ipairs({'sidebar-keyboard.lua','sidebar-keyboard-view.lua','keyboard-shortcuts.lua'}) do
    local file=assert(io.open('dotfiles/.config/awesome/'..path));local source=file:read('*a');file:close()
    assert(not source:find('fake_input',1,true) and not source:find('key.execute',1,true),path)
end
local registry=dofile('dotfiles/.config/awesome/keyboard-shortcuts.lua').new()
local calls=0
registry.add({'Mod4'},'p',function() calls=calls+1 end)
registry.add({'Mod4','Shift'},'#10',function() calls=calls+10 end)
local client={valid=true}
registry.add({'Mod1'},'space',function(c) assert(c==client); calls=calls+100 end,true)
registry.find({'Lock','Mod2','Mod4'},'P')()
registry.find({'Shift','Mod4'},'exclam')()
assert(not registry.find({'Mod4'},'exclam') and not registry.find({'Mod1'},'space'))
registry.find({'Mod1'},'space',client)();assert(calls==111)
client.valid=false; assert(not registry.find({'Mod1'},'space',client))
local C=dofile('dotfiles/.config/awesome/sidebar-calendar.lua')
for _,case in ipairs{
    {'2024-01-31','Page_Down','2024-02-29'}, {'2025-01-31','Page_Down','2025-02-28'},
    {'2024-03-31','Page_Up','2024-02-29'}, {'2024-12-31','Right','2025-01-01'},
    {'2024-01-01','Left','2023-12-31'}, {'2024-03-30','Right','2024-03-31'},
    {'2024-03-31','Right','2024-04-01'}, {'2024-10-26','Down','2024-11-02'},
    {'2024-04-01','Up','2024-03-25'}, {'2024-02-01','End','2024-02-29'},
} do assert(C.move_date(case[1],case[2])==case[3],table.concat(case,':')) end
assert(C.move_date('2024-01-01','Home','2026-10-15')=='2026-10-15')
assert(C.move_date('2024-01-01','Tab')==nil)
print('Awesome sidebar keyboard tests passed')
