-- Clock and system-status changes arriving in one short window share one redraw batch.
local M=dofile('dotfiles/.config/awesome/sidebar-refresh.lua')
local timers={}
local function timer_factory(options)
    local timer={started=false,timeout=options.timeout,single_shot=options.single_shot,
        callback=options.callback,starts=0,stops=0}
    function timer:start() self.started=true;self.starts=self.starts+1 end
    function timer:stop() self.started=false;self.stops=self.stops+1 end
    function timer:fire()
        assert(self.started,'Cannot fire an idle timer')
        self.started=false
        return self.callback()
    end
    timers[#timers+1]=timer
    return timer
end
local updates={}
local component=M.new {
    timer=timer_factory,delay=.05,
    update_stats=function(state) updates[#updates+1]={'stats',state} end,
    update_power=function(state) updates[#updates+1]={'power',state} end,
    update_clock=function(timestamp) updates[#updates+1]={'clock',timestamp} end,
}
local timer=timers[1]
assert(timer.timeout==.05 and timer.single_shot)
local stats={value={network=1}}
local power={value={capacity=80}}
component.clock(1234)
component.stats(stats)
component.power(power)
assert(timer.starts==1 and #updates==0,'Nearby events must share the pending timer')
timer:fire()
assert(#updates==3 and updates[1][1]=='stats' and updates[1][2]==stats)
assert(updates[2][1]=='power' and updates[2][2]==power)
assert(updates[3][1]=='clock' and updates[3][2]==1234,
    'A coalesced batch must render fast/slow status and clock together')

component.clock(2345)
component.clock(2346)
assert(timer.starts==2,'Events arriving after a flush must schedule a new batch')
timer:fire()
assert(#updates==4 and updates[4][2]==2346,'The most recent clock time must win')

component.power(power)
assert(timer.started)
component.destroy()
assert(not timer.started and timer.stops==1,'Destroy must cancel a pending refresh')
component.clock(3456);component.stats(stats);component.power(power)
assert(timer.starts==3 and #updates==4,'Disposed refresh components must ignore new work')
print('Awesome sidebar refresh coalescing tests passed')
