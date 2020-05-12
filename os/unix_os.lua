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
unix.POWERON_CHARGER="power_charger"
unix.MSG_INT="pin_int"

local function gettick()
    return chronos.nanotime()*1000
end

local function callback(timer)
    local id = timer.param
end

function unix.set_trace_port(port)
    log.debug("os-unix",string.format("trace port[%d] ",port))
end

function unix.poweron_reason()
    return POWERON_CHARGER
end

function unix.receive(msg_id)
    if msg_id == unix.INF_TIMEOUT then
        local msg = nil
        while true do
            local ret,timer = scheduler:tick(gettick())
            if ret and ret == true then
                msg = unix.MSG_TIMER
                return msg, timer.param
            end
        end
    end
    return nil
end

function unix.timer_stop(id)
    for _, timer in ipairs(scheduler.timers) do
        if timer.param == id then
        timer:remove()
        end
    end
end

function unix.timer_start(id,ms)
    if not id or not ms then return 0 end
    scheduler:timer(ms, 1,nil,id)
    return 1
end

function unix.get_version()
    return "virtual luat"
end

return unix

