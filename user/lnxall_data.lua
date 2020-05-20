require "pm"
require "iic"
require "sms"
require "link"
require "pins"
require "misc"
require "mqtt"
require "utils"
require "lbsLoc"
require "socket"
require "audio"
require "httpv2"
require "common"
require "create"
require "tracker"

require "lnxall_conf"
local status = require "status"

cjson = require "cjson"
bcd = require "bcd"
syslog = require "syslog"
dyutils = require "dyutils"
lpack = require "lua_pack"
base64 = require "base64"
bit = require "bit"

bnot = bit.bnot band, bor, bxor = bit.band, bit.bor, bit.bxor lshift, rshift, rol = bit.lshift, bit.rshift, bit.rol
bpack = lpack.bpack bunpack = lpack.bunpack

-- 两个串口独立的命令索引表
local ident_table={{},{}}
local module_name={}


if io.exists(lnxall_conf.LNXALL_nodes_temp) then
    local dat, res, err = json.decode(io.readFile(lnxall_conf.LNXALL_nodes_temp) or '')
    nodes_temp = dat.template_cfg
end

local function service_resopnse(json)
    log.info("lnxall_data.date report",'report data to lnxall platform')
    sys.publish("JJ_NET_SEND_MSG_" .. "SevsData",json or '')
end

function inxallStart()
    -- 网络数据->串口
    sys.subscribe("JJ_NET_RECV_" .. "DownLinkMsg",function(payload)
        local uid = 1 -- 串口1
        log.debug("lnxall_data.downlink",payload)
        if not payload then
            log.warn("lnxall_data.downlink",'protocol module received control message from lnxall was nil')
            return
        end
        local obj = json.decode(payload)
        local input={}
        local output={}
        input.term_addr=lnxall_conf.sn2addr(obj and obj.sn or nil)
        if not input.term_addr then
            log.warn("lnxall_data.downlink","sn:" .. obj.sn .. " couldn`t convert any term_ddr")
            return
        end
        log.info("lnxall_data.downlink","device sn:" .. obj.sn .. " addr:" .. input.term_addr .. " cloud->uart")
        input.identifier = obj.identifier
        input.mi = obj.mi
        input.sn = obj.sn
        input.time=os.time()

        -- 记录下行命令
        ident_table[uid] = input
        -- tx count
        status.tx_add(obj.sn)

        log.info("lnxall_data.downlink",'immediate message sn:' .. obj.sn or '' .. 'identifier:' .. obj.identifier or '' .. 'mi:' .. obj.mi)
        local str = json.encode(input)
        local func = lnxall_conf.scriptEncodeBysn(obj.sn)
        if func then
            -- 下面的json_str 其实是bin_str
            local ret,func_ret,json_str,json_len = pcall(func,str or '',str and #str or 0)
            if ret and ret == true and func_ret and json_str and func_ret == true or func_ret == 0 then
                if lnxall_conf.portBysn(obj.sn) == 'RS485_1' then
                    uid = 1
                end

                -- 不是json输出
                local bin
                output,ret = json.decode(json_str)
                if not ret then
                    bin = string.fromHex(json_str)
                    log.info("lnxall_data.downlink",'downlink binary message with hex string pack:',json_str)
                else       -- base64数据
                    bin = output.b64_data and base64.decode(output.b64_data)
                    log.info("lnxall_data.downlink",'downlink binary message with base64 of json:',json_str)
                end
                sys.publish("NET_RECV_WAIT_" .. uid,uid,bin)
            else
                log.warn("lnxall_data.downlink",'raw data called protocol decode failed,error:' .. func_ret)
            end
        else
            log.error("lnxall_data.downlink",'encode funtion of  protocol script was nil')
        end
    end)

    -- 串口数据->网络
    sys.subscribe("NET_SENT_RDY_" .. 1,function(rawdata)
        local uid = 1 -- 串口1
        if not rawdata then
            log.warn("lnxall_data.uplink",'protocol module received raw data from uart was nil')
            return
        end
        local input={}
        local output={}
        local func = nil
        --分为三种种情况
        --  1.仅仅主动上报,此时ident_table[uid] 查不到下行数据
        --  2.仅仅下行,加被动应答,此时ident_table[uid] 查的到下行数据
        --  3.主动上报和下行控制同时存在

        if not ident_table[uid] then return end
        v = ident_table[uid]
        local valid = false
        if v.sn and v.identifier  and v.mi then
            local timeout = lnxall_conf.commonTimeBysn(v.sn)
            if timeout and timeout == 0 or v.time and os.time() <= v.time + timeout then  valid = true
            end
        end
        input.raw_data=string.toHex(rawdata)
        input.b64_data=base64.encode(rawdata)
        if valid and valid == true then --sn, identifier, mi 这些值在下行数据发送时被保存
            log.info("lnxall_data.uplink",'downlink command or data response parse function')
            input.identifier=v.identifier
            func = lnxall_conf.scriptDecodeBysn(v.sn)
        else --主动上报,不能依赖下行保存信息
            log.info("lnxall_data.uplink",'uplink data parse function')
            v.mi = nil v.sn = nil v.identifier = nil
            func = lnxall_conf.scriptDecodeByport(uid)
        end
        if func then
            local str = json.encode(input)
            local ret,func_ret,json_str,json_len = pcall(func,str or '',str and #str or 0)
            if ret and ret == true and func_ret and json_str and func_ret == true or func_ret == 0 then
                local tags = json.decode(json_str or '{}')
                output.mi = v.mi or 0
                output.timestamp = os.time()
                output.sn = v.sn or lnxall_conf.addr2sn(tags and tags.term_addr or nil)
                if not output.sn then log.error("lnxall_data.uplink","term_addr:" .. tags.term_addr .. " couldn`t convert any sn")
                else log.info("lnxall_data.uplink","device sn:" .. output.sn .. " addr:" .. obj.term_addr .. " uart->cloud")
                end
                output.identifier = v.identifier or tags.identifier
                tags.identifier = nil
                tags.term_addr = nil
                output.tags = tags

                if not v.identifier then
                    -- rx count
                    status.rx_add(output.sn)
                else
                    -- tx resp count
                    status.resp_add(output.sn)
                end

                service_resopnse(json.encode(output))
            else
                log.warn("lnxall_data.uplink",'raw data call protocol decode failed,error:' , func_ret)
            end
        else
            log.error("lnxall_data.uplink",'decode funtion of protocol script was nil')
        end
    end)
end


local function testLoop(id)
    while true do
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end
        -- function download(link , saveFile,timeout)
        sys.wait(5000)
    end
end

sys.taskInit(testLoop, 1)

inxallStart()
