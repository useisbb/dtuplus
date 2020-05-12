local Scheduler = require("ELScheduler")
local chronos = require("chronos")
local sleep = require("sleep")
local json = require("json")
local scheduler = Scheduler()

unix={}

unix.MSG_UART_RXDATA="receive"
unix.MSG_UART_TX_DONE="sent"
unix.INF_TIMEOUT="int_timeout"
unix.MSG_TIMER="timeout"
unix.MSG_PDP_DEACT_IND="pdp_deact"

local function gettick()
    return chronos.nanotime()*1000
end

local function callback(timer)
    local id = timer.param
    log.info("timer id:",id)
end

function unix.receive(msg_id)
    if msg_id == unix.INF_TIMEOUT then
        local msg = nil
        while true do
            local ret,timer = scheduler:tick(gettick())
            if ret and ret == true then
                msg = MSG_TIMER
                return msg, timer.param
            end
        end
    end
end

function unix.timer_stop(id)
    for _, timer in ipairs(scheduler.timers) do
        if timer.param == id then
        timer:remove()
        end
    end
end

function unix.timer_start(id,ms)
    if not id or not ms or not callback then return 0 end
    local t1 = ms + gettick()
    scheduler:timer(t1, 1,callback,id)
    return 1
end

function unix.get_version()
    return "virtual luat"
end

return unix


-- timer_start(12,2000,cb)
-- timer_start(23,3000,cb)
-- timer_start(45,1000,cb)
