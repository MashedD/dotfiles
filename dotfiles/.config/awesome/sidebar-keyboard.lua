-- One modal owner; adapters provide widgets, native grabs and presentation.
local M = {}
local owner
local modifiers = {Shift_L=true,Shift_R=true,Control_L=true,Control_R=true,
    Alt_L=true,Alt_R=true,Super_L=true,Super_R=true,ISO_Level3_Shift=true,
    Caps_Lock=true,Num_Lock=true}
function M.new(o)
    local c = {active=false, entries=o.targets}
    local current, index, grab, held, super = nil, 1, nil, {}, false
    local generation=0
    function c.stop()
        if not c.active and not grab then return end
        generation=generation+1
        c.active=false
        if owner==c then owner=nil end
        local old=grab; grab=nil
        if old then o.stop(old) end
        current=nil; held={}; super=false
        o.changed()
    end
    local function guarded(fn)
        local ok,err=xpcall(fn,debug.traceback)
        if not ok then c.stop(); if o.report then o.report(err) end end
        return ok
    end
    function c.generation() return generation end
    function c.target()
        if not c.active then return end
        local targets=o.targets()
        if #targets==0 then c.stop(); return end
        for i,t in ipairs(targets) do
            if current and t.id==current.id then current=t; index=i; return t end
        end
        local section=current and current.section
        for i,t in ipairs(targets) do
            if section and t.id==section..':header' then current=t; index=i; return t end
        end
        index=math.min(index,#targets); current=targets[index]
        return current
    end
    local function move(delta,absolute)
        local target=c.target(); if not target then return end
        local targets=o.targets()
        index=absolute or ((index-1+delta)%#targets+1)
        current=targets[index]; o.changed()
    end
    local function activate(fn,exit)
        if not fn then return end
        if exit then c.stop() end
        fn()
        if c.active then c.target(); o.changed() end
    end
    function c.event(mods,key,event)
        if not c.active then return end
        guarded(function()
            if not o.eligible() then c.stop(); return end
            local shift,extra,win=false,false,false
            for _,m in ipairs(mods) do
                if m=='Shift' then shift=true
                elseif m=='Mod4' then win=true
                elseif m~='Lock' and m~='Mod2' then extra=true end
            end
            if key=='ISO_Left_Tab' then key='Tab'; shift=true end
            key=({[' ']='space',Prior='Page_Up',Next='Page_Down',KP_Prior='Page_Up',KP_Next='Page_Down',
                KP_Left='Left',KP_Right='Right',KP_Up='Up',KP_Down='Down',KP_Home='Home',KP_End='End'})[key] or key
            if event=='release' then
                held[key]=nil
                if key=='s' or key=='S' then held.entry=nil end
                if key=='Super_L' or key=='Super_R' then
                    local tap=super; super=false
                    if tap then c.stop(); o.start_menu() end
                end
                return
            end
            if modifiers[key] then
                if key=='Super_L' or key=='Super_R' then super=not extra and not shift
                else super=false end
                return
            end
            super=false
            if win and not extra and not shift and key:lower()=='s' then
                if not held.entry then c.stop() end
                return
            end
            if key=='s' or key=='S' then held.entry=nil end
            if key=='Escape' and not extra and not win then c.stop(); return end
            local t=c.target(); if not t then return end
            local shortcut=o.shortcut and o.shortcut(mods,key)
            if shortcut then activate(shortcut,true); return end
            if extra or win then return end
            if key=='Tab' then move(shift and -1 or 1); return end
            if key=='Return' or key=='KP_Enter' or key=='space' then
                if held[key] then return end
                held[key]=true
                if key=='space' and t.space then activate(t.space,false)
                else activate(t.activate,t.exit) end
                return
            end
            if t.key and t.key(key) then o.changed(); return end
            if key=='Home' then move(0,1)
            elseif key=='End' then move(0,#o.targets())
            elseif key=='Up' or key=='Left' then move(-1)
            elseif key=='Down' or key=='Right' then move(1)
            end -- Other application input is deliberately ignored: Escape exits.
        end)
    end
    function c.toggle()
        if owner then owner.stop(); return end
        if not o.eligible() or not o.available() then return end
        guarded(function()
            c.active=true; owner=c; current=nil; index=1
            held={entry=true}; super=false
            if not c.target() then return end
            local token=generation
            grab=o.start(function(...)
                if c.active and generation==token then return c.event(...) end
            end)
            assert(grab,'Could not acquire sidebar keyboard grab')
            o.changed()
        end)
    end
    return c
end
return M
