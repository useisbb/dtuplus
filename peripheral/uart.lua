require "log"

local LINESIZE = 16

uart={}
uart.ATC="at-uart"


local rxbuff={}

function uart.setup(id, baud, databits, parity, stopbits,msgmode,txDoneReport)
    if not id or  not baud or not databits then
        log.error("peripheral-uart","串口配置参数错误",id, baud, databits)
        return
    end
    log.info("peripheral-uart","id=" , id)
    log.info("peripheral-uart","baud=" , baud)
    log.info("peripheral-uart","databits=" , databits)
    log.info("peripheral-uart","parity=" , parity)
    log.info("peripheral-uart","stopbits=" , stopbits)
    if not  msgmode or msgmode == 0 then log.info("peripheral-uart","使能接收消息事件") end
    if txDoneReport and txDoneReport == 1 then log.info("peripheral-uart","使能发送完成消息事件") end
end

function uart.write(id, ...)
    log.debug("peripheral-uart",string.format("串口[%d] write",id))
    for i = 1, select('#', ... ) do
        local data = select(i, ... )
        if data and type(data) == "number" then
            log.info("peripheral-uart",string.format("Hex:%X",data))
        elseif data and type(data) == "string" then
            log.info("peripheral-uart",string.format("String:%s",data))
        end
    end
end


function uart.getchar(id)
    local data = 0x31
    log.debug("peripheral-uart",string.format("串口[%d] getchar",id))
    log.info("peripheral-uart",string.format("Hex:%X",data))
end


function uart.read(id,fmt)
    log.debug("peripheral-uart",string.format("串口[%d] read",id))
    local bin = '\2\3\5\6\2\4'
    local str = '1234567'
    table.insert( rxbuff,str)
    local data = table.remove( rxbuff, 1 )
    if data and type(data) == "number" then
        log.info("peripheral-uart",string.format("Hex:%X",data))
    elseif data and type(data) == "string" then
        log.info("peripheral-uart",string.format("String:%s",data))
    end
    return data
end

return uart
