-- Fast fake-I/O tests: no real /proc/sysfs reads, lgi, or sleeping.
local M=assert(loadfile('tests/probe-awesome-stats.lua'))(true)
local ROOT='/sys/class/power_supply/'
local function fixture(options)
    options=options or {}
    local now, closes, enum_closes, sleeps=0,0,0,{}
    local files={
        [ROOT..'BAT1/type']='Battery\n', [ROOT..'BAT1/capacity']='50', [ROOT..'BAT1/status']='Charging\n',
        [ROOT..'BAT2/type']='Battery\n', [ROOT..'BAT2/capacity']='70', [ROOT..'BAT2/status']='Full\n',
        [ROOT..'hidpp_battery_0/type']='Battery', [ROOT..'hidpp_battery_0/capacity']='85', [ROOT..'hidpp_battery_0/status']='Discharging',
        [ROOT..'hidpp_battery_1/type']='Battery', [ROOT..'hidpp_battery_1/capacity']='1',
        [ROOT..'ADP1-PRIVATE-SERIAL/type']='Mains',
        ['/proc/stat']='cpu fixture-secret', ['/proc/meminfo']='memory fixture-secret',
        ['/proc/net/dev']='lo: 100 0 0 0 0 0 0 0 200\n eth0: 10 0 0 0 0 0 0 0 20\n wlan0: 30 0 0 0 0 0 0 0 40',
    }
    if options.missing then files[options.missing]=nil end
    local names=options.names or {'BAT1','BAT2','hidpp_battery_0','hidpp_battery_1','ADP1-PRIVATE-SERIAL'}
    local opens={}
    local runtime={
        now=function() return now end,
        sleep=function(seconds) sleeps[#sleeps+1]=seconds end,
        query_filesystem=function()
            now=now+.002
            if options.filesystem_error then error('sensitive-error') end
            return {get_attribute_uint64=function(_,key) return key=='filesystem::size' and 1000 or 100 end}
        end,
        open=function(path)
            opens[#opens+1]=path; now=now+.001
            if options.open_error==path then error('sensitive-error') end
            if files[path]==nil then return nil end
            return {
                read=function()
                    now=now+.002
                    if options.read_error==path then error('sensitive-error') end
                    return files[path]
                end,
                close=function()
                    now=now+.001; closes=closes+1
                    if options.close_error==path then error('sensitive-error') end
                    return true
                end,
            }
        end,
        enumerate=function()
            now=now+.001
            if options.enum_open_error then error('sensitive-error') end
            local index=0
            return {
                next_file=function()
                    now=now+.001; index=index+1
                    if options.enum_next_error then error('sensitive-error') end
                    local name=names[index]
                    return name and {get_name=function() return name end} or nil
                end,
                close=function()
                    now=now+.001; enum_closes=enum_closes+1
                    if options.enum_close_error then error('sensitive-error') end
                    return true
                end,
            }
        end,
    }
    return M.new(runtime),function() return {closes=closes,enum_closes=enum_closes,sleeps=sleeps,opens=opens} end
end
local function close(a,b) assert(math.abs(a-b)<1e-9,tostring(a)..' ~= '..tostring(b)) end
local summary=M.summarize({10,1,4,2,3})
assert(summary.median==3 and summary.p95==10 and summary.maximum==10)
assert(M.summarize({})==nil)
local values={2,1}; M.summarize(values); assert(values[1]==2)
local p,state=fixture()
local battery=p.battery(); assert(battery[1]==60 and battery[2]=='Charging, Full' and battery[3]==85)
for _,path in ipairs(state().opens) do assert(path~=ROOT..'hidpp_battery_1/capacity') end
local rx,tx=p.network(); assert(rx==40 and tx==60)
p.run(2)
assert(#state().sleeps==1 and state().sleeps[1]==1)
local leaf=p.metrics['file '..ROOT..'BAT1/capacity']; close(leaf.values[1],.004)
assert(p.metrics['subsystem battery'].values[1]>.004)
assert(p.metrics['batch total'].values[1]>=p.metrics['subsystem filesystem'].values[1])
assert(p.metrics['enumeration next'].errors==0) -- Includes successful EOF.
local report=p.report()
assert(not report:find('fixture-secret',1,true) and not report:find('PRIVATE-SERIAL',1,true))
assert(report:find('<other>/type',1,true))
assert(report:find('nested rows overlap',1,true))
for _,kind in ipairs({'missing','open_error','read_error','close_error'}) do
    local options={[kind]='/proc/stat'}
    local probe,st=fixture(options)
    probe.batch()
    local m=probe.metrics['file /proc/stat']
    assert(m.errors==1 and #m.values==0 and #m.failed==1)
    assert(probe.metrics['file /proc/meminfo'].attempts==1)
    assert(probe.metrics['batch total'].errors==1)
    if kind=='read_error' or kind=='close_error' then assert(st().closes==#st().opens) end
    assert(not probe.report():find('sensitive-error',1,true))
end
for _,kind in ipairs({'enum_open_error','enum_next_error','enum_close_error','filesystem_error'}) do
    local probe,st=fixture({[kind]=true})
    probe.batch()
    assert(probe.metrics['file /proc/stat'].attempts==1)
    if kind=='enum_next_error' or kind=='enum_close_error' then assert(st().enum_closes==1) end
    if kind=='enum_open_error' then assert(st().enum_closes==0) end
end
p,state=fixture({names={}}); assert(p.battery()==nil and state().enum_closes==1)
assert(p.report():find('n/a',1,true))
p=fixture({read_error=ROOT..'BAT1/type'}); p.battery()
assert(p.metrics['file '..ROOT..'BAT1/type'].errors==1)
assert(M.options({})==60 and M.options({'--samples','1'})==1)
for _,args in ipairs({{'--samples','0'},{'--samples','-1'},{'--samples','nan'},
                      {'--samples','1.5'},{'--samples','10001'},{'--other'},{'--help','extra'}}) do
    local value,reason=M.options(args); assert(value==nil and reason=='invalid')
end
local original=M.runtime
M.runtime=function() error('private setup details') end
local stderr,diagnostic=io.stderr,''
io.stderr={write=function(_,value) diagnostic=diagnostic..value end}
assert(M.main({})==1)
io.stderr=stderr
assert(diagnostic:find('Probe setup failed',1,true) and not diagnostic:find('private setup details',1,true))
M.runtime=original
local clock_calls=0
local control=M.new(M.control_runtime(function() clock_calls=clock_calls+1; return clock_calls*.000001 end))
control.run(2)
assert(control.metrics['batch total'].errors==0 and control.metrics['batch total'].attempts==2)
assert(control.metrics['enumeration next'].attempts==8)
local n,reason,is_control=M.options({'--control','--samples','2'})
assert(n==2 and reason==nil and is_control)
print('Awesome statistics probe tests passed')
