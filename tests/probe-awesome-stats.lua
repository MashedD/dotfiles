-- Opt-in, read-only statistics probe. loadfile(path)(true) exposes fake-test helpers.
local M = {}
local ROOT = '/sys/class/power_supply/'
function M.summarize(values)
    local sorted = {}
    for i, value in ipairs(values) do sorted[i] = value end
    table.sort(sorted)
    if #sorted == 0 then return nil end
    return {median=sorted[math.ceil(#sorted*.5)], p95=sorted[math.ceil(#sorted*.95)], maximum=sorted[#sorted]}
end
function M.new(runtime)
    local probe = {metrics={}}
    local function metric(label)
        local m = probe.metrics[label]
        if not m then
            m = {attempts=0, errors=0, values={}, failed={}}
            probe.metrics[label] = m
        end
        return m
    end
    -- Measured parent scopes include nested scopes; never sum rows as exclusive costs.
    local function measure(label, fn)
        local m = metric(label)
        m.attempts = m.attempts+1
        local start = runtime.now()
        local result = table.pack(pcall(fn))
        local elapsed = math.max(0, runtime.now()-start)
        if not result[1] or result[2] == nil then
            m.errors = m.errors+1
            m.failed[#m.failed+1] = elapsed
            return nil
        end
        m.values[#m.values+1] = elapsed
        return table.unpack(result, 2, result.n)
    end
    local function read(path, label)
        return measure('file '..(label or path), function()
            local file = runtime.open(path)
            if not file then return nil end
            local ok, value = pcall(function() return file:read('*a') end)
            local closed, close_result = pcall(function() return file:close() end)
            if not ok or not closed or close_result == nil or close_result == false then return nil end
            return value
        end)
    end
    local function label_supply(name)
        if name:match('^BAT%d+$') or name:match('^hidpp_battery_%d+$') then return name end
        return '<other>' -- Do not print arbitrary device names/serials.
    end
    function probe.filesystem()
        return measure('subsystem filesystem', function()
            local info = runtime.query_filesystem()
            if not info then return nil end
            local total = info:get_attribute_uint64('filesystem::size')
            local free = info:get_attribute_uint64('filesystem::free')
            if not total or not free or total <= 0 then return nil end
            return total, free
        end)
    end
    function probe.battery()
        return measure('subsystem battery', function()
            local enumerator = measure('enumeration open', function() return runtime.enumerate(ROOT) end)
            if not enumerator then return nil end
            local ok, laptop_capacity, laptop_state, mouse_capacity, mouse_state = pcall(function()
                local capacities, states = {}, {}
                local mouse_capacity, mouse_state
                while true do
                    local result = measure('enumeration next', function()
                        return {entry=enumerator:next_file()}
                    end)
                    -- EOF is a successful enumeration operation, not an unavailable sensor.
                    if not result then error('enumeration failed', 0) end
                    local entry=result.entry
                    if not entry then break end
                    local name = entry:get_name()
                    local base = ROOT..name
                    local label = ROOT..label_supply(name)
                    local supply_type = read(base..'/type', label..'/type') or ''
                    if name:match('^BAT') and supply_type:match('^Battery') then
                        local capacity = tonumber(read(base..'/capacity', label..'/capacity'))
                        if capacity then
                            capacities[#capacities+1] = capacity
                            states[#states+1] = (read(base..'/status', label..'/status') or 'Unknown'):gsub('%s+$','')
                        end
                    elseif name:match('^hidpp_battery') and supply_type:match('^Battery') and not mouse_capacity then
                        mouse_capacity = tonumber(read(base..'/capacity', label..'/capacity'))
                        mouse_state = (read(base..'/status', label..'/status') or 'Unknown'):gsub('%s+$','')
                    end
                end
                local laptop_capacity, laptop_state
                if #capacities > 0 then
                    local sum=0; for _, value in ipairs(capacities) do sum=sum+value end
                    laptop_capacity=math.floor(sum/#capacities+.5)
                    laptop_state=table.concat(states, ', ')
                end
                return laptop_capacity, laptop_state, mouse_capacity, mouse_state
            end)
            local closed = measure('enumeration close', function()
                local result = enumerator:close()
                return result ~= false and result ~= nil and true or nil
            end)
            if not ok or not closed then return nil end
            -- Availability affects metrics, not selection/aggregation semantics.
            if laptop_capacity == nil and mouse_capacity == nil then return nil end
            return {laptop_capacity, laptop_state, mouse_capacity, mouse_state}
        end)
    end
    function probe.network()
        return measure('subsystem network', function()
            local data = read('/proc/net/dev')
            if not data then return nil end
            local rx, tx=0,0
            for line in data:gmatch('[^\n]+') do
                local name, counters=line:match('^%s*([^:]+):%s*(.*)')
                if name and name:gsub('%s','') ~= 'lo' then
                    local values={}
                    for value in counters:gmatch('%d+') do values[#values+1]=tonumber(value) end
                    rx,tx=rx+(values[1] or 0),tx+(values[9] or 0)
                end
            end
            return rx,tx
        end)
    end
    function probe.batch()
        return measure('batch total', function()
            local total,free=probe.filesystem()
            local battery=probe.battery()
            local rx,tx=probe.network()
            local stat=read('/proc/stat')
            local meminfo=read('/proc/meminfo')
            -- A usable parent result may still have unavailable leaf reads; the
            -- per-file error counts remain authoritative for partial sensors.
            if not total or not battery or not rx or not stat or not meminfo then return nil end
            return true
        end)
    end
    function probe.run(samples)
        for i=1,samples do
            probe.batch()
            if i<samples then runtime.sleep(1) end
        end
    end
    function probe.report()
        local lines={'Durations in milliseconds; nested rows overlap (do not sum).',
                     'operation\tattempts\tsuccess\terror/unavailable\tmedian\tp95\tmax\tfailure-p95'}
        local labels={}; for label in pairs(probe.metrics) do labels[#labels+1]=label end
        table.sort(labels)
        for _,label in ipairs(labels) do
            local m=probe.metrics[label]
            local s,f=M.summarize(m.values),M.summarize(m.failed)
            local function format(value) return value and string.format('%.3f', value*1000) or 'n/a' end
            lines[#lines+1]=table.concat({label,m.attempts,#m.values,m.errors,format(s and s.median),
                format(s and s.p95),format(s and s.maximum),format(f and f.p95)},'\t')
        end
        return table.concat(lines,'\n')
    end
    return probe
end
function M.control_runtime(clock)
    return {
        now=clock, sleep=function() end,
        query_filesystem=function()
            return {get_attribute_uint64=function(_,key) return key=='filesystem::size' and 1000 or 100 end}
        end,
        enumerate=function()
            local index=0
            local names={'ADP1','BAT1','hidpp_battery_0'}
            return {next_file=function()
                index=index+1; local name=names[index]
                return name and {get_name=function() return name end} or nil
            end, close=function() return true end}
        end,
        open=function(path)
            local value=path==ROOT..'ADP1/type' and 'Mains'
                or path:match('/type$') and 'Battery' or path:match('/capacity$') and '50'
                or path:match('/status$') and 'Charging' or path=='/proc/net/dev' and 'eth0: 1 0 0 0 0 0 0 0 2'
                or 'fixture'
            return {read=function() return value end,close=function() return true end}
        end,
    }
end
function M.options(args)
    local control=false
    if args[1]=='--control' then
        control=true
        local remaining={}; for i=2,#args do remaining[#remaining+1]=args[i] end
        args=remaining
    end
    local samples=60
    if #args==1 and (args[1]=='--help' or args[1]=='-h') then return nil,'help' end
    if #args~=0 then
        if #args~=2 or args[1]~='--samples' or not args[2]:match('^%d+$') then return nil,'invalid' end
        samples=tonumber(args[2])
        if not samples or samples<1 or samples>10000 then return nil,'invalid' end
    end
    return samples,nil,control
end
function M.runtime()
    local lgi=require('lgi')
    local Gio,GLib=lgi.Gio,lgi.GLib
    return {
        now=function() return GLib.get_monotonic_time()/1000000 end,
        sleep=function(seconds) GLib.usleep(seconds*1000000) end,
        open=function(path) return io.open(path,'r') end,
        enumerate=function(path) return Gio.File.new_for_path(path):enumerate_children('standard::name',0) end,
        query_filesystem=function()
            return Gio.File.new_for_path('/'):query_filesystem_info('filesystem::size,filesystem::free',nil)
        end,
    }
end
function M.main(args)
    local samples,reason,control=M.options(args)
    if not samples then
        local stream=reason=='help' and io.stdout or io.stderr
        stream:write('Usage: lua5.3 tests/probe-awesome-stats.lua [--control] [--samples 1..10000]\n')
        return reason=='help' and 0 or 64
    end
    local ok,runtime=pcall(M.runtime)
    if not ok then io.stderr:write('Probe setup failed: use a Lua version with lgi Gio/GLib (Awesome uses lua5.3 on this machine).\n'); return 1 end
    if control then runtime=M.control_runtime(runtime.now) end
    local probe=M.new(runtime)
    probe.run(samples)
    print('Samples: '..samples..(control and '; fake/no-I/O control; no sleeping.' or '; one second sleep between batches; read-only standalone process.'))
    print(probe.report())
    return 0
end
if ... == true then return M end
os.exit(M.main(arg))
