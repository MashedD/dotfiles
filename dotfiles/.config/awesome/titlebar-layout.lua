-- Width policy is pure; the adapter only allocates children, never changes visibility.
local M = {}
local order={'icon','title','ontop','minimize','maximize','close'}
local function pixels(value)
    value=tonumber(value)
    if not value or value~=value or value==math.huge or value==-math.huge then return 0 end
    return math.max(0,math.floor(value))
end
function M.plan(width,height)
    local w,h=pixels(width),pixels(height==nil and 26 or height)
    local result={width=w,height=h,rects={},controls={}}
    if w==0 or h==0 then return result end
    local controls={'close'}
    if w>=85 then table.insert(controls,1,'maximize') end
    if w>=108 then table.insert(controls,1,'minimize') end
    if w>=131 then table.insert(controls,1,'ontop') end
    -- 62..84 keeps only Close; 40..61 additionally omits the icon.
    local icon=w>=62 and 22 or 0
    local margin=w>=25 and 2 or 0
    local button=math.min(21,w)
    local row=#controls*button+(#controls-1)*2+2*margin
    local title_width=math.max(0,w-row-icon)
    if icon>0 then result.rects.icon={x=0,y=0,width=icon,height=h} end
    if title_width>0 then result.rects.title={x=icon,y=0,width=title_width,height=h} end
    local inset=math.min(2,math.max(0,(h-1)/2))
    for index,name in ipairs(controls) do
        result.controls[name]=true
        result.rects[name]={x=w-row+margin+(index-1)*(button+2),y=inset,width=button,height=h-2*inset}
    end
    return result
end
function M.create(widgets)
    local base=require('wibox.widget.base')
    local layout=base.make_widget(nil,nil,{enable_properties=true})
    function layout:get_children()
        local children={}
        for _,name in ipairs(order) do children[#children+1]=assert(widgets[name],name) end
        return children
    end
    function layout:get_children_by_id(id)
        for _,name in ipairs(order) do
            if id=='titlebar_'..name then return {widgets[name]} end
        end
        return {}
    end
    function layout:fit(_,width,height)
        local plan=M.plan(width,height)
        return plan.width,plan.height
    end
    function layout:layout(_,width,height)
        local plan=M.plan(width,height)
        local result={}
        for _,name in ipairs(order) do
            local r=plan.rects[name]
            if r then result[#result+1]=base.place_widget_at(widgets[name],r.x,r.y,r.width,r.height) end
        end
        return result
    end
    return layout
end
return M
