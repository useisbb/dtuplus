--- 模块功能：查询sim卡状态、iccid、imsi、mcc、mnc
-- @module sim
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.02.13
require "ril"
require "sys"
module(..., package.seeall)


--sim卡的imsi、sim卡的iccid
local imsi, iccid, status

--- 获取sim卡的iccid
-- @return string ,返回iccid，如果还没有读取出来，则返回nil
-- @usage 注意：开机lua脚本运行之后，会发送at命令去查询iccid，所以需要一定时间才能获取到iccid。开机后立即调用此接口，基本上返回nil
-- @usage sim.getIccid()
function getIccid()
    return iccid
end

--- 获取sim卡的imsi
-- @return string ,返回imsi，如果还没有读取出来，则返回nil
-- @usage 开机lua脚本运行之后，会发送at命令去查询imsi，所以需要一定时间才能获取到imsi。开机后立即调用此接口，基本上返回nil
-- @usage sim.getImsi()
function getImsi()
    return imsi
end

--- 获取sim卡的mcc
-- @return string ,返回值：mcc，如果还没有读取出来，则返回""
-- @usage 注意：开机lua脚本运行之后，会发送at命令去查询imsi，所以需要一定时间才能获取到imsi。开机后立即调用此接口，基本上返回""
-- @usage sim.getMcc()
function getMcc()
    return (imsi ~= nil and imsi ~= "") and string.sub(imsi, 1, 3) or ""
end

--- 获取sim卡的getmnc
-- @return string ,返回mnc，如果还没有读取出来，则返回""
-- @usage   注意：开机lua脚本运行之后，会发送at命令去查询imsi，所以需要一定时间才能获取到imsi。开机后立即调用此接口，基本上返回""
-- @usage sim.getMnc()
function getMnc()
    return (imsi ~= nil and imsi ~= "") and string.sub(imsi, 4, 5) or ""
end

--- 获取sim卡的状态
-- @return bool ,true表示sim卡正常，false或者nil表示未检测到卡或者卡异常
-- @usage   开机lua脚本运行之后，会发送at命令去查询状态，所以需要一定时间才能获取到状态。开机后立即调用此接口，基本上返回nil
-- @usage sim.getStatus()
function getStatus()
    return status
end

--[[
函数名：rsp
功能  ：本功能模块内“通过虚拟串口发送到底层core软件的AT命令”的应答处理
参数  ：
cmd：此应答对应的AT命令
success：AT命令执行结果，true或者false
response：AT命令的应答中的执行结果字符串
intermediate：AT命令的应答中的中间信息
返回值：无
]]
local function rsp(cmd, success, response, intermediate)
    if cmd == "AT+ICCID" then
        iccid = string.match(intermediate, "%+ICCID: (.+)")
    elseif cmd == "AT+CIMI" then
        imsi = intermediate
        --产生一个内部消息IMSI_READY，通知已经读取imsi
        sys.publish("IMSI_READY")
    end
end

--[[
函数名：urc
-- 功能  ：本功能模块内“注册的底层core通过虚拟串口主动上报的通知”的处理
参数  ：
data：通知的完整字符串信息
prefix：通知的前缀
返回值：无
]]
local function urc(data, prefix)
    --sim卡状态通知
    if prefix == "+CPIN" then
        status = false
        --sim卡正常
        if data == "+CPIN: READY" then
            status = true
            ril.request("AT+ICCID")
            ril.request("AT+CIMI")
            sys.publish("SIM_IND", "RDY")
        --未检测到sim卡
        elseif data == "+CPIN: NOT INSERTED" then
            sys.publish("SIM_IND", "NIST")
        else
            --sim卡pin开启
            if data == "+CPIN: SIM PIN" then
                sys.publish("SIM_IND_SIM_PIN")
            end
            sys.publish("SIM_IND", "NORDY")
        end
    end
end

function set2gSim()
    ril.request("AT+MEDCR=0,8,1")
    ril.request("AT+MEDCR=0,17,240")
    ril.request("AT+MEDCR=0,19,1")
end

--注册AT+CCID命令的应答处理函数
ril.regRsp("+ICCID", rsp)
--注册AT+CIMI命令的应答处理函数
ril.regRsp("+CIMI", rsp)
--注册+CPIN通知的处理函数
ril.regUrc("+CPIN", urc)
