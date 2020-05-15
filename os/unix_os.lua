local Scheduler = require("ELScheduler")
local chronos = require("chronos")
local fs = require("fs")
local math = require("math")
local scheduler = Scheduler()
pmd = require "pmd"
unix={}

unix.MSG_UART_RXDATA="receive"
unix.MSG_UART_TX_DONE="sent"
unix.INF_TIMEOUT="int_timeout"
unix.MSG_TIMER="timeout"
unix.MSG_PDP_DEACT_IND="pdp_deact"
unix.POWERON_CHARGER="power_charger"
unix.MSG_INT="pin_int"

unix.MSG_SOCK_RECV_IND="sock_recv_ind"
unix.MSG_SOCK_CLOSE_CNF="sock_close_cnf"
unix.MSG_SOCK_CONN_CNF="sock_conn_cnf"
unix.MSG_SOCK_SEND_CNF="sock_send_cnf"
unix.MSG_SOCK_CLOSE_IND="sock_close_ind"


local function callback(timer)
    local id = timer.param
end

function unix.tick()
    return math.modf(chronos.nanotime()*1000)
end

function unix.get_fs_free_size(...)
    return 1000
end

function unix.make_dir(...)
    return fs.mkdir(...)
end

function unix.set_trace_port(port)
    log.debug("os-unix",string.format("trace port[%d] ",port))
end

function unix.poweron_reason()
    return POWERON_CHARGER
end

function unix.receive(msg_id)
    if msg_id == unix.INF_TIMEOUT then
        while true do
            local ret,timer = scheduler:tick(unix.tick())
            if ret and ret == true then
                local msg = nil
                msg = unix.MSG_TIMER
                return msg, timer.param
            end
            if sys.poll_socket then
                local msg = sys.poll_socket()
                if msg then
                    return msg
                end
            end
            if sys.poll_uart then
                local msg = sys.poll_uart()
                if msg then
                    return msg,msg.uid
                end
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

