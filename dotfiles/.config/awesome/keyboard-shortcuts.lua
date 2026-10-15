-- Dispatch existing WM callbacks while a modal widget owns the keyboard.
-- No XTest input, modifier changes, or duplicated action implementations.
local M={}
local function signature(modifiers)
    local result={}
    for _,modifier in ipairs(modifiers) do
        if modifier~='Lock' and modifier~='Mod2' then result[#result+1]=modifier end
    end
    table.sort(result)
    return table.concat(result,'+')
end
function M.new()
    local entries={}
    local registry={}
    function registry.add(modifiers,key,callback,client)
        local names={[key:lower()]=true}
        -- These are the four physical desktop keys in this configuration.
        -- Accept shifted US/Polish keysyms as well as the digit itself.
        local digits={['#10']={'1','exclam','!'},['#11']={'2','at','@'},
            ['#12']={'3','numbersign','#'},['#13']={'4','dollar','$'}}
        for _,name in ipairs(digits[key] or {}) do names[name]=true end
        entries[#entries+1]={modifiers=signature(modifiers),names=names,callback=callback,client=client}
    end
    function registry.find(modifiers,key,focused)
        local mods=signature(modifiers)
        for _,entry in ipairs(entries) do
            if entry.modifiers==mods and entry.names[key:lower()] then
                if entry.client then
                    if focused and focused.valid then return function() entry.callback(focused) end end
                else return entry.callback end
            end
        end
    end
    return registry
end
return M
