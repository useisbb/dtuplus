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
local baud_map = {}
baud_map["115200"]=rs232.RS232_BAUD_115200
baud_map["57600"]=rs232.RS232_BAUD_57600
baud_map["19200"]=rs232.RS232_BAUD_19200
baud_map["9600"]=rs232.RS232_BAUD_9600
baud_map["4800"]=rs232.RS232_BAUD_4800
baud_map["2400"]=rs232.RS232_BAUD_2400

uart.port={{id = 1, handle = nil, name = "/dev/ttyUSB0",rxbuff={},sent=false},{id = 2, handle = nil,name = "/dev/ttyS5",rxbuff={},sent=false}}

-- local rxbuff={}

function uart.setup(id, baud, databits, parity, stopbits,msgmode,txDoneReport)
    if type(id) == "string" and id == uart.ATC  then  log.debug("peripheral-uart","AT虚拟串口配置") return end
    if not id or  not baud or not databits or  id < 1 or id > 2 then
        log.error("peripheral-uart","input param set failed",id, baud, databits)
        return
    end
    log.debug("peripheral-uart","serial setup id:",id)
    log.info("peripheral-uart","id=" , id)
    log.info("peripheral-uart","baud=" , baud)
    log.info("peripheral-uart","databits=" , databits)
    log.info("peripheral-uart","parity=" , parity)
    log.info("peripheral-uart","stopbits=" , stopbits)
    if not  msgmode or msgmode == 0 then log.info("peripheral-uart","received event enable") end
    if txDoneReport and txDoneReport == 1 then log.info("peripheral-uart","sent event enable") end
    -- open port
    local e, p = rs232.open(uart.port[id].name)
    if e ~= rs232.RS232_ERR_NOERROR then
        -- handle error
        log.error("peripheral-uart","input param set failed",id, uart.port[id].name)
        return
    else
        uart.port[id].handle = p
        log.info("peripheral-uart",p)
        assert(p:set_baud_rate(baud_map[baud and type(baud) == "string" and baud or string.format("%d",baud)]) == rs232.RS232_ERR_NOERROR)
        -- assert(p:set_data_bits(databits and type(databits) == "string" and databits or string.format("%d",databits)) == rs232.RS232_ERR_NOERROR)
        assert(p:set_parity(par_map[parity+1]) == rs232.RS232_ERR_NOERROR)
        -- assert(p:set_stop_bits(stopbits and type(stopbits) == "string" and stopbits or string.format("%d",stopbits)) == rs232.RS232_ERR_NOERROR)
    end

end

function uart.write(id, ...)
    log.debug("peripheral-uart",string.format("serial[%d] write",id))
    if not uart.port[id].handle then
        log.error("peripheral-uart",string.format("serial[%d] write failed,port not open",id))
        return
    end
    for i = 1, select('#', ... ) do
        local data = select(i, ... )
        if data and type(data) == "number" then
            log.info("peripheral-uart",string.format("Hex:%X",data))
        elseif data and type(data) == "string" then
            log.info("peripheral-uart",string.format("Hex:%s",data:toHex()))
            local err, len_written = uart.port[id].handle:write(data)
        end
    end
    uart.port[id].sent = true
end


function uart.getchar(id)
    local data = 0x31
    log.debug("peripheral-uart",string.format("serial[%d] getchar",id))
    log.info("peripheral-uart",string.format("Hex:%X",data))
end


function uart.read(id,fmt)
    log.debug("peripheral-uart",string.format("serial[%d] read",id))
    -- local bin = '\2\3\5\6\2\4'
    -- local str = '1234567'
    -- table.insert( rxbuff,str)
    -- local data = table.remove( rxbuff, 1 )
    local data = table.concat(uart.port[id].rxbuff)
    for i = 1,#uart.port[id].rxbuff do
        table.remove( uart.port[id].rxbuff, 1 )
    end

    if data then
        log.info("peripheral-uart",string.format("Hex:%s",data:toHex()))
    end
    return data or ""
end

function uart.close(id)
    log.debug("peripheral-uart",string.format("serial[%d] close",id))
end

function uart.set_rs485_oe(id,dir)
    log.debug("peripheral-uart",string.format("serial[%d] dir %s",id,dir))
end

function uart.poll_uart()
    for _, port in pairs(uart.port) do
        if port.handle then
            if port.sent and port.sent == true then
                port.sent = false
                msg={}
                msg.msgid = rtos.MSG_UART_TX_DONE
                msg.uid = port.id
                -- log.info("peripheral-uart","on sent")
                return msg
            end

            local count = 0
            local data_read=""
            -- 读串口有数据自动拼包
            repeat
                local err, data, size = port.handle:read(100, 5)
                if count == 0 and not data then count = 6 end --如果第一包没有数据就不继续等待
                if data then data_read = data_read .. data end
                count = count + 1
            until( count > 5 )
            -- 直接读串口不在这里拼包,可能会丢包
            -- local err, data_read, size = port.handle:read(100, 5)

            if data_read and #data_read > 1 then
                msg={}
                table.insert(port.rxbuff,data_read)
                msg.msgid = rtos.MSG_UART_RXDATA
                msg.uid = port.id
                log.info("peripheral-uart",string.format("on received event"))
                return msg
            end
        end
    end
end

return uart
