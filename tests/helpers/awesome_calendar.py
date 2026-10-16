"""Date-rollover checks on the harness's real calendar, never the system clock."""
from pathlib import Path


def verify_rollover(*, lua, env, wait):
    assert env['AWESOME_TEST_MODE']=='1'
    path=Path(env['HOME'])/'Documents/calendar.md'
    original=path.read_bytes()
    cases=[('2024-01-30','2024-01-31'), ('2024-01-31','2024-02-01'),
           ('2024-02-28','2024-02-29'), ('2024-02-29','2024-03-01'),
           ('2024-12-31','2025-01-01'), ('2025-03-01','2025-03-09'),
           ('2025-03-09','2025-03-08'), ('2024-03-30','2024-03-31'),
           ('2024-10-26','2024-10-27')]
    dates=sorted({date for pair in cases for date in pair}|{'2030-06-01','2030-06-02','2030-06-03'})
    path.write_text(''.join(f'{date} 08:15 Rollover {date}\n' for date in dates)
                    +'2024-01-31 12:30 Extra important entry\n')
    lua('''local s=screen[1]; __calendar_rollover_saved={month=s.sidebar_calendar_month(),
        date=s.sidebar_calendar_selected_date(),collapsed=s.sidebar_sections.calendar.collapsed,
        mode=s.sidebar_mode,offset=s.sidebar_scroll_offset(),focus=client.focus,
        timer_started=s.sidebar_calendar_timer.started}
        if s.sidebar_calendar_timer.started then s.sidebar_calendar_timer:stop() end
        assert(s.sidebar_keyboard.active and s.sidebar_keyboard.target().id=='calendar:grid')''')
    try:
        payload=','.join('{%r,%r}'%pair for pair in cases)
        functions='''local s=screen[1]; local original_date=os.date
            local function with_day(date,callback)
                local stamp=os.time{year=tonumber(date:sub(1,4)),month=tonumber(date:sub(6,7)),day=tonumber(date:sub(9,10)),hour=12}
                os.date=function(format,time) return original_date(format,time or stamp) end
                local ok,err=xpcall(callback,debug.traceback)
                os.date=original_date
                if not ok then error(err) end
            end
            local function selected(date)
                assert(s.sidebar_calendar_selected_date()==date,'Wrong selected date: '..date)
                assert(s.sidebar_calendar_month()==date:sub(1,7),'Wrong displayed month: '..date)
                assert(s.sidebar_calendar_day_cells()[date],'Missing selected cell: '..date)
                local expected=date=='2024-01-31' and 2 or 1
                local count=0
                for _,entry in ipairs(s.sidebar_calendar_entries) do
                    if entry.date==date then assert(entry.day=='today');count=count+1 end
                end
                assert(count==expected,'Wrong today entries: '..date)
                assert(#s.sidebar_calendar_events_widget:get_children()==expected,'Wrong displayed event count')
                local text={}
                for _,child in ipairs(s.sidebar_calendar_events_widget:get_all_children()) do
                    if type(child.get_text)=='function' then text[#text+1]=child:get_text() end
                end
                assert(table.concat(text,' '):find('Rollover '..date,1,true),'Missing displayed event text')
                assert(client.focus==__calendar_rollover_saved.focus,'Calendar stole focus')
            end
            local function appearance()
                local s=screen[1]
                local palette=dofile(awesome.conffile:match('^(.*)/')..'/appearance.lua').palette
                local headers=s.sidebar_calendar_grid:get_children()[1]:get_children()
                local expected={'Mo','Tu','We','Th','Fr','Sa','Su'}
                assert(#headers==7)
                for index,header in ipairs(headers) do
                    local markup=header:get_children()[1].markup
                    local color=markup:match("foreground='([^']+)'")
                    assert(markup:find(expected[index],1,true),'Wrong weekday heading: '..index)
                    assert(color==(index>=6 and palette.calendar_weekend or palette.muted),
                        'Wrong weekday heading color: '..index)
                end
                local cells=s.sidebar_calendar_day_cells()
                local function foreground(date)
                    return cells[date]:get_children()[1].markup:match("foreground='([^']+)'")
                end
                local function background(date)
                    local _,r,g,b=cells[date].bg:get_rgba()
                    return string.format('#%02x%02x%02x',math.floor(r*255+0.5),
                        math.floor(g*255+0.5),math.floor(b*255+0.5))
                end
                assert(foreground('2030-06-08')==palette.calendar_weekend,
                    'Ordinary Saturday lacks weekend foreground')
                assert(background('2030-06-08')==palette.calendar_weekend_bg,
                    'Ordinary Saturday lacks weekend background')
                assert(foreground('2030-06-02')==palette.teal,
                    'Weekend event lost event emphasis')
                assert(foreground('2030-06-01')==palette.neon,
                    'Weekend today lost today emphasis')
                assert(background('2030-06-01')=='#1d5944',
                    'Selected weekend lost selection background')
                s.sidebar_calendar_select_date('2030-06-08')
                cells=s.sidebar_calendar_day_cells()
                assert(foreground('2030-06-08')==palette.calendar_weekend,
                    'Selected weekend lost weekend foreground')
                assert(background('2030-06-08')=='#1d5944',
                    'Selected weekend lost selection background')
                assert(cells['2030-06-08'].border_width==1 and cells['2030-06-08'].border_color,
                    'Selected weekend lost its selection border')
                s.sidebar_calendar_select_date('2030-06-01')
            end'''
        code=functions+'''
            local ok=pcall(function() with_day('2024-01-01',function() error('Clock restore probe') end) end)
            assert(not ok and os.date==original_date,'Failure leaked fake clock')
            for _,pair in ipairs({__CASES__}) do
                with_day(pair[1],function()
                    s.sidebar_calendar_refresh()
                    s.sidebar_calendar_next_action();s.sidebar_calendar_next_action()
                    local viewed=s.sidebar_calendar_month()
                    local chosen=viewed..'-15'
                    s.sidebar_calendar_select_date(chosen);s.sidebar_calendar_refresh()
                    assert(s.sidebar_calendar_selected_date()==chosen and s.sidebar_calendar_month()==viewed,
                        'Same-day refresh interrupted browsing')
                end)
                local old_cell=s.sidebar_keyboard.target().resolve()
                with_day(pair[2],function()
                    s.sidebar_calendar_refresh();selected(pair[2])
                    local target=s.sidebar_keyboard.target()
                    assert(s.sidebar_keyboard.active and target.id=='calendar:grid')
                    assert(target.resolve()==s.sidebar_calendar_day_cells()[pair[2]] and target.resolve()~=old_cell,
                        'Keyboard retained a detached calendar cell')
                    s.sidebar_calendar_next_action()
                    local viewed=s.sidebar_calendar_month()
                    s.sidebar_calendar_select_date(viewed..'-12');s.sidebar_calendar_refresh()
                    assert(s.sidebar_calendar_month()==viewed and s.sidebar_calendar_selected_date()==viewed..'-12',
                        'Rollover reset more than once on the same day')
                end)
            end
            with_day('2030-06-01',function()
                s.sidebar_calendar_refresh();selected('2030-06-01');appearance()
            end)
            assert(s.sidebar_keyboard.active and s.sidebar_keyboard.target().id=='calendar:grid')
            assert(os.date==original_date,'Clock wrapper leaked')
            return true'''
        assert 'true' in lua(code.replace('__CASES__',payload))
        # Allow a real layout/draw while navigation is still active. The fixture
        # timer is paused so real-time refresh cannot race the scoped fake date.
        wait('''local s=screen[1]; local widget=s.sidebar_calendar_day_cells()['2030-06-01']
            local function visible(hierarchy)
                if hierarchy:get_widget()==widget then
                    local w,h=hierarchy:get_size(); local _,y=hierarchy:get_matrix_to_device():transform_point(0,0)
                    local top=s.sidebar_header.forced_height+s.sidebar_clock_card.forced_height
                    return w>0 and h>0 and y>=top-1 and y+h<=top+s.sidebar_scroll_view.forced_height+1
                end
                for _,child in ipairs(hierarchy:get_children()) do if visible(child) then return true end end
                return false
            end
            return tostring(s.sidebar_keyboard.active and s.sidebar_keyboard.target().resolve()==widget
                and visible(s.sidebar._drawable._widget_hierarchy))''','"true"')
        code=functions+'''
            s.sidebar_sections.calendar.toggle_action()
            assert(s.sidebar_sections.calendar.collapsed)
            with_day('2030-06-02',function()
                s.sidebar_calendar_refresh();selected('2030-06-02')
                assert(s.sidebar_sections.calendar.collapsed and s.sidebar_keyboard.active)
                assert(s.sidebar_keyboard.target().id=='calendar:header')
            end)
            s.sidebar_mode=0;s.sidebar_update_mode()
            with_day('2030-06-03',function()
                s.sidebar_calendar_refresh();selected('2030-06-03')
                assert(not s.sidebar.visible and s.sidebar_mode==0 and s.sidebar_sections.calendar.collapsed)
                assert(not s.sidebar_keyboard.active)
            end)
            assert(os.date==original_date,'Clock wrapper leaked')
            return true'''
        assert 'true' in lua(code)
    finally:
        path.write_bytes(original)
        lua('''local s=screen[1]; local old=__calendar_rollover_saved
            s.sidebar_keyboard.stop();s.sidebar_calendar_refresh()
            if old then
                if s.sidebar_sections.calendar.collapsed~=old.collapsed then s.sidebar_sections.calendar.toggle_action() end
                local y,m=old.month:match('(%d+)%-(%d+)');local cy,cm=s.sidebar_calendar_month():match('(%d+)%-(%d+)')
                local delta=(tonumber(y)-tonumber(cy))*12+tonumber(m)-tonumber(cm)
                for i=1,math.abs(delta) do if delta>0 then s.sidebar_calendar_next_action() else s.sidebar_calendar_previous_action() end end
                s.sidebar_calendar_select_date(old.date);s.sidebar_mode=old.mode;s.sidebar_update_mode()
                s.sidebar_scroll_by(old.offset-s.sidebar_scroll_offset())
                if old.timer_started and not s.sidebar_calendar_timer.started then s.sidebar_calendar_timer:start() end
            end
            __calendar_rollover_saved=nil''')
