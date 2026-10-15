-- Fake async completions; no sysfs, lgi, Awesome, or real timers.
local M=dofile('dotfiles/.config/awesome/sidebar-battery.lua')
local function fixture(options)
    options=options or {}
    local pending,reads,cancelled={}, {},0
    local enum_closed=0
    local values={
        BAT1={type='Battery',status='Charging\n'}, BAT2={type='Battery',status='Full\n'},
        hidpp_battery_0={type='Battery',capacity='0',status='Discharging\n'},
        hidpp_battery_1={type='Battery',capacity='99'}, ADP1={type='Mains'},
    }
    local runtime={
        enumerate=function()
            if options.enumerate_error then error('enumerate failed') end
            local names=options.names or {'ADP1','BAT1','BAT2','hidpp_battery_0','hidpp_battery_1'}
            local index=0
            return {next_file=function()
                index=index+1
                if options.next_error then error('next failed') end
                local name=names[index]
                return name and {get_name=function() return name end} or nil
            end,close=function() enum_closed=enum_closed+1; return not options.close_error end}
        end,
        read=function(path)
            reads[#reads+1]=path
            local name,key=path:match('/([^/]+)/([^/]+)$')
            assert(not (name:match('^BAT') and key=='capacity'), 'Synchronous laptop capacity read!')
            if options.status_error and key=='status' then error('status unavailable') end
            return values[name] and values[name][key]
        end,
        load=function(path,done)
            if options.dispatch_error then error('dispatch failed') end
            local name=path:match('/([^/]+)/capacity$')
            pending[name]=done
            return function() cancelled=cancelled+1 end
        end,
    }
    local calls,result=0
    local fetch=M.new(runtime)
    local cancel=fetch(function(...) calls=calls+1; result=table.pack(...) end)
    return {
        fetch=fetch, cancel=cancel, pending=pending, reads=reads,
        state=function() return calls,result,cancelled,enum_closed end,
    }
end
local f=fixture(); assert(f.state()==0)
f.pending.BAT2('80'); assert(f.state()==0)
f.pending.BAT1('0')
local calls,result,cancel_count,closed=f.state()
assert(calls==1 and result[1]==40 and result[2]=='Charging, Full' and result[3]==0 and closed==1)
f.pending.BAT1('100'); assert(f.state()==1) -- Duplicate callback cannot republish.
for _,path in ipairs(f.reads) do assert(not path:find('hidpp_battery_1/capacity',1,true)) end
f=fixture(); f.pending.BAT1(nil); f.pending.BAT2('not a number')
calls,result=f.state(); assert(calls==1 and result[1]==nil and result[3]==0)
local recovered
f.fetch(function(...) recovered=table.pack(...) end)
f.pending.BAT1('50'); f.pending.BAT2('70')
assert(recovered[1]==60 and recovered[3]==0)
f=fixture({status_error=true,names={'BAT1'}}); f.pending.BAT1('50')
calls,result=f.state(); assert(result[1]==50 and result[2]=='Unknown')
f=fixture({names={}}); calls,result=f.state(); assert(calls==1 and result[1]==nil and result[5]==nil)
f=fixture({names={'hidpp_battery_0'}}); calls,result=f.state(); assert(result[3]==0)
f=fixture({dispatch_error=true}); calls,result=f.state(); assert(calls==1 and result[1]==nil)
for _,kind in ipairs({'enumerate_error','next_error','close_error'}) do
    f=fixture({[kind]=true}); calls,result,cancel_count,closed=f.state()
    assert(calls==1 and result[5]=='Cannot enumerate batteries')
    if kind~='enumerate_error' then assert(closed==1) end
end
f=fixture(); f.cancel(); f.cancel()
calls,result,cancel_count,closed=f.state(); assert(calls==0 and closed==1)
local _,_,cancelled=f.state(); assert(cancelled==2)
f.pending.BAT1('50'); f.pending.BAT2('60'); assert(f.state()==0)
-- A fresh fetch after cancellation is independent of the ignored old completions.
local new_calls=0
local old_ready=f.pending.BAT1
local stop=f.fetch(function() new_calls=new_calls+1 end)
old_ready('99'); assert(new_calls==0)
f.pending.BAT1('70'); f.pending.BAT2('90'); assert(new_calls==1)
stop(); assert(new_calls==1)
-- The adapter dispatches Gio async I/O, finishing only from its callback.
local callback,gio_cancelled,delivered=nil,0,0
local file={load_contents_async=function(self,cancel,ready) callback=ready end,
            load_contents_finish=function() return '42','etag' end}
local previous=package.loaded.lgi
package.loaded.lgi={Gio={File={new_for_path=function() return file end},
    Cancellable=function() return {cancel=function() gio_cancelled=gio_cancelled+1 end} end}}
local runtime=M.runtime(function() end)
local cancel=runtime.load('/fixture/capacity',function(value) assert(value=='42'); delivered=delivered+1 end)
assert(delivered==0 and type(callback)=='function')
callback(file,{}); assert(delivered==1)
cancel(); assert(gio_cancelled==1)
file.load_contents_finish=function() error('read failed') end
runtime.load('/fixture/capacity',function(value) assert(value==nil); delivered=delivered+1 end)
callback(file,{}); assert(delivered==2)
package.loaded.lgi=previous
print('Awesome asynchronous battery tests passed')
