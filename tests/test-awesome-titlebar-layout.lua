-- Pure width policy and adapter tests, with no Awesome or X11.
local M=dofile('dotfiles/.config/awesome/titlebar-layout.lua')
for width=1,512 do
    local p=M.plan(width)
    assert(p.width==width and p.height==26)
    assert(p.controls.close and p.rects.close.width==math.min(21,width))
    assert((p.rects.icon~=nil)==(width>=62))
    assert((p.controls.maximize==true)==(width>=85))
    assert((p.controls.minimize==true)==(width>=108))
    assert((p.controls.ontop==true)==(width>=131))
    if width>=62 then assert(p.rects.title.width>=15) end
    local rects={}
    for _,r in pairs(p.rects) do
        assert(r.width>0 and r.height>0 and r.x>=0 and r.y>=0)
        assert(r.x+r.width<=width and r.y+r.height<=26)
        rects[#rects+1]=r
    end
    table.sort(rects,function(a,b) return a.x<b.x end)
    for index=2,#rects do assert(rects[index-1].x+rects[index-1].width<=rects[index].x) end
end
for _,width in ipairs({16,21,24,25,39,40,61,62,84,85,107,108,130,131,160,400}) do
    assert(M.plan(width).rects.close.width==math.min(width,21))
end
for _,value in ipairs({false,'invalid',0,-1,0/0,math.huge,-math.huge}) do
    assert(next(M.plan(value).rects)==nil)
end
assert(next(M.plan(nil).rects)==nil and next(M.plan(400,0).rects)==nil)
assert(M.plan(25.9).width==25 and M.plan('131').controls.ontop)
for height=1,26 do
    for _,r in pairs(M.plan(400,height).rects) do assert(r.height>=0 and r.y+r.height<=height) end
end
-- Match the old align/fixed geometry exactly at ordinary widths.
local p=M.plan(400)
assert(p.rects.icon.x==0 and p.rects.icon.width==22)
assert(p.rects.title.x==22 and p.rects.title.width==284)
for i,name in ipairs({'ontop','minimize','maximize','close'}) do
    local r=p.rects[name]
    assert(r.x==308+(i-1)*23 and r.y==2 and r.width==21 and r.height==22)
end
package.preload['wibox.widget.base']=function() return {
    make_widget=function() return {} end,
    place_widget_at=function(widget,x,y,width,height) return {widget=widget,x=x,y=y,width=width,height=height} end,
} end
local widgets={}
for _,name in ipairs({'icon','title','ontop','minimize','maximize','close'}) do widgets[name]={visible=true} end
local layout=M.create(widgets)
assert(#layout:get_children()==6 and layout:get_children_by_id('titlebar_ontop')[1]==widgets.ontop)
assert(#layout:get_children_by_id('not-a-control')==0)
assert(#layout:layout({},400,26)==6 and #layout:layout({},62,26)==3)
assert(#layout:layout({},16,26)==1 and layout:layout({},16,26)[1].width==16)
assert(#layout:layout({},0,26)==0)
for _,widget in pairs(widgets) do assert(widget.visible==true) end
local w,h=layout:fit({},400,26);assert(w==400 and h==26)
print('Awesome responsive titlebar layout tests passed')
