require "log"
rs232 = require("luars232")
local LINESIZE = 16

-- Linux
-- name = "/dev/ttyUSBS0"

-- (Open)BSD
-- name = "/dev/cua00"

-- Windows
-- name = "COM1"

uart={}
uart.ATC="at-uart"
uart.PAR_EVEN=0
uart.PAR_ODD=1
uart.PAR_NONE=2

local par_map={rs232.RS232_PARITY_EVEN,rs232.RS232_PARITY_ODD,rs232.RS232_PARITY_NONE}


uart.port={{id = 1, handle = nil, name = "/dev/ttyUSB0",rxbuff={}},{id = 2, handle = nil,name = "/dev/ttyS5",rxbuff={}}}

-- local rxbuff={}

function uart.setup(id, baud, databits, parity, stopbits,msgmode,txDoneReport)
    if type(id) == "string" and id == uart.ATC  then  log.debug("peripheral-uart","AT虚拟串口配置") return end
    if not id or  not baud or not databits or  id < 1 or id > 2 then
        log.error("peripheral-uart","串口配置参数错误",id, baud, databits)
        return
    end
    log.debug("peripheral-uart","物理串口配置",id)
    log.info("peripheral-uart","id=" , id)
    log.info("peripheral-uart","baud=" , baud)
    log.info("peripheral-uart","databits=" , databits)
    log.info("peripheral-uart","parity=" , parity)
    log.info("peripheral-uart","stopbits=" , stopbits)
    if not  msgmode or msgmode == 0 then log.info("peripheral-uart","使能接收消息事件") end
    if txDoneReport and txDoneReport == 1 then log.info("peripheral-uart","使能发送完成消息事件") end
    -- open port
    local e, p = rs232.open(uart.port[id].name)
    if e ~= rs232.RS232_ERR_NOERROR then
        -- handle error
        log.error("peripheral-uart","串口配置参数错误",id, uart.port[id].name)
        return
    else

        uart.port[id].handle = p
        print("========== port",p,uart.port[1].handle)
        assert(p:set_baud_rate(baud and type(baud) == "string" and baud or string.format("%d",baud)) == rs232.RS232_ERR_NOERROR)
        assert(p:set_data_bits(databits and type(databits) == "string" and databits or string.format("%d",databits)) == rs232.RS232_ERR_NOERROR)
        assert(p:set_parity(par_map[uart.parity]) == rs232.RS232_ERR_NOERROR)
        assert(p:set_stop_bits(stopbits and type(stopbits) == "string" and stopbits or string.format("%d",stopbits)) == rs232.RS232_ERR_NOERROR)
    end

end

function uart.write(id, ...)
    log.debug("peripheral-uart",string.format("串口[%d] write",id))
    if not uart.port[id].handle then
        log.error("peripheral-uart",string.format("串口[%d] write failed,port not open",id))
        return
    end
    for i = 1, select('#', ... ) do
        local data = select(i, ... )
        if data and type(data) == "number" then
            log.info("peripheral-uart",string.format("Hex:%X",data))
        elseif data and type(data) == "string" then
            log.info("peripheral-uart",string.format("String:%s",data))
            local err, len_written = uart.port[id].handle:write(data)
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
    -- local bin = '\2\3\5\6\2\4'
    -- local str = '1234567'
    -- table.insert( rxbuff,str)
    -- local data = table.remove( rxbuff, 1 )
    if data and type(data) == "number" then
        log.info("peripheral-uart",string.format("Hex:%X",data))
    elseif data and type(data) == "string" then
        log.info("peripheral-uart",string.format("String:%s",data))
    end
    return data or ""
end

function uart.close(id)
    log.debug("peripheral-uart",string.format("串口[%d] close",id))
end

function uart.set_rs485_oe(id,dir)
    log.debug("peripheral-uart",string.format("串口[%d] dir %s",id,dir))
end

function uart.poll_uart()
    for _, port in pairs(uart.port) do
    -- print(port.id,port.handle)
            -- local err, data_read, size = port.handle:read(20, 1000)
            -- print("uart event:",err, data_read, size)
            -- if data_read and type(ret) == "table" then
            --     msg={}
            --     msg.id = rtos.MSG_UART_RXDATA
            --     msg.socket_index = port.id
            --     return msg
            -- end
    end
end

return uart
