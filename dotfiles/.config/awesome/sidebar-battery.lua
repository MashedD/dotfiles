-- Only laptop capacity is asynchronous; fast sysfs reads retain their semantics.
local M = {}
function M.new(runtime)
    return function(done)
        local root = '/sys/class/power_supply/'
        local laptops, mouse_capacity, mouse_state = {}, nil, nil
        local enumerator
        local ok = pcall(function()
            enumerator = runtime.enumerate(root)
            if not enumerator then error('enumeration unavailable') end
            while true do
                local entry = enumerator:next_file()
                if not entry then break end
                local name = entry:get_name()
                local supply_type = runtime.read(root..name..'/type') or ''
                if name:match('^BAT') and supply_type:match('^Battery') then
                    laptops[#laptops+1] = root..name
                elseif name:match('^hidpp_battery') and supply_type:match('^Battery') and not mouse_capacity then
                    mouse_capacity = tonumber(runtime.read(root..name..'/capacity'))
                    mouse_state = (runtime.read(root..name..'/status') or 'Unknown'):gsub('%s+$','')
                end
            end
        end)
        local closed = true
        if enumerator then
            local success, result = pcall(enumerator.close, enumerator)
            closed = success and result ~= false and result ~= nil
        end
        if not ok or not closed then
            done(nil,nil,nil,nil,'Cannot enumerate batteries')
            return
        end
        local remaining, cancelled, completed = #laptops, false, false
        local capacities, states, cancel_reads = {}, {}, {}
        local function finish()
            if cancelled or completed or remaining > 0 then return end
            completed = true
            local sum, count, status = 0, 0, {}
            for index=1,#laptops do
                if capacities[index] then
                    sum, count = sum+capacities[index], count+1
                    status[#status+1] = states[index]
                end
            end
            done(count>0 and math.floor(sum/count+.5) or nil,
                 count>0 and table.concat(status,', ') or nil, mouse_capacity, mouse_state)
        end
        local function cancel()
            if cancelled or completed then return end
            cancelled = true
            for _, stop in ipairs(cancel_reads) do pcall(stop) end
        end
        for index, path in ipairs(laptops) do
            local returned = false
            local function ready(value)
                if cancelled or completed or returned then return end
                returned = true
                capacities[index] = tonumber(value)
                if capacities[index] then
                    local success, state = pcall(runtime.read, path..'/status')
                    states[index] = ((success and state) or 'Unknown'):gsub('%s+$','')
                end
                remaining = remaining-1
                finish()
            end
            local started, stop = pcall(runtime.load, path..'/capacity', ready)
            if not started then ready(nil)
            elseif type(stop)=='function' and not returned then cancel_reads[#cancel_reads+1]=stop end
        end
        finish()
        return cancel
    end
end
function M.runtime(read)
    local Gio = require('lgi').Gio
    return {
        read=read,
        enumerate=function(root)
            return Gio.File.new_for_path(root):enumerate_children('standard::name',0)
        end,
        load=function(path, done)
            local cancel = Gio.Cancellable()
            Gio.File.new_for_path(path):load_contents_async(cancel, function(file, result)
                local ok, contents = pcall(file.load_contents_finish, file, result)
                done(ok and contents or nil)
            end)
            return function() cancel:cancel() end
        end,
    }
end
return M
