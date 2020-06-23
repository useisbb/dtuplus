--- 模块功能：DTU主逻辑
-- @author openLuat
-- @module default
-- @license MIT
-- @copyright openLuat
-- @release 2018.12.27
-- require "cc"
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
require "netLed"
require "lnxall_conf"

module(..., package.seeall)

-- 判断模块类型
local ver = rtos.get_version():upper()
local is4gLod = ver:find("ASR1802")
local is1802S = ver:find("ASR1802S")
local is8910 = ver:find("8910")
local isTTS = ver:find("TTS") or ver:find("8955F")
-- 用户的配置参数
local CONFIG = "/CONFIG.cnf"
-- 串口缓冲区最大值
local SENDSIZE = is4gLod and 8192 or 1460
-- 串口写空闲
local writeIdle = {true, true}
-- 串口读缓冲区
local recvBuff, writeBuff = {{}, {}}, {{}, {}}
-- 串口流量统计
local flowCount, timecnt = {0, 0}, 1
-- 定时采集任务的初始时间
local startTime = {0, 0}
-- 定时采集任务缓冲区
local sendBuff = {{}, {}}
-- 基站定位坐标
local lbs = {lat, lng}
-- login 标记
local login = nil
-- 串口confirm缓冲区
local confirmBuff = {{}, {}}
-- 串口confirm空闲标记
local confirmIdle = {true, true}
-- 配置文件
local dtu = {
    host = "", -- 自定义参数服务器
    passon = 0, --透传标志位
    plate = 0, --识别码标志位
    convert = 0, --hex转换标志位
    reg = 0, -- 登陆注册包
    param_ver = 0, -- 参数版本
    flow = 0, -- 流量监控
    fota = 0, -- 远程升级
    uartReadTime = 500, -- 串口读超时
    netReadTime = 50, -- 网络读超时
    pwrmod = "normal",
    password = "",
    upprot = {}, -- 上行自定义协议
    dwprot = {}, -- 下行自定义协议
    apn = {nil, nil, nil}, -- 用户自定义APN
    cmds = {{}, {}}, -- 自动采集任务参数
    pins = {"", "", ""}, -- 用户自定义IO: netled,netready,rstcnf,
    conf = {{}, {}, {}, {}, {}, {}, {}}, -- 用户通道参数
    preset = {number = "", delay = 1, smsword = "SMS_UPDATE"}, -- 用户预定义的来电电话,延时时间,短信关键字
    uconf = {{1, 115200, 8, uart.PAR_NONE, uart.STOP_1}, {2, 115200, 8, uart.PAR_NONE, uart.STOP_1}}, -- 串口配置表
    gps = {
        fun = {"", "115200", "0", "5", "1", "json", "100", ";", "60"}, -- 用户捆绑GPS的串口,波特率，功耗模式，采集间隔,采集方式支持触发和持续, 报文数据格式支持 json 和 hex，缓冲条数,分隔符,状态报文间隔
        pio = {"", "", "", "", "0", "16"}, -- 配置GPS用到的IO: led脚，vib震动输入脚，ACC输入脚,内置电池充电状态监视脚,adc通道,分压比
    },
    warn = {
        gpio = {},
        adc0 = {},
        adc1 = {},
        vbatt = {}
    },
    task = {}, -- 用户自定义任务列表
}
-- 获取参数版本
io.getParamVer = function()
    return dtu.param_ver
end
---------------------------------------------------------- 开机读取保存的配置文件 ----------------------------------------------------------
-- 自动任务采集
local function autoSampl(uid, t)
    while true do
        sys.waitUntil("AUTO_SAMPL_" .. uid)
        for i = 2, #t do
            local str = t[i]:match("function(.+)end")
            if not str then
                if t[i] ~= "" then write(uid, (t[i]:fromHex())) end
            else
                local res, msg = pcall(loadstring(str))
                if res then sys.publish("NET_SENT_RDY_" .. uid, msg) end
            end
            sys.wait(tonumber(t[1]))
        end
    end
end

if io.exists(CONFIG) then
    -- log.info("CONFIG is value:", io.readFile(CONFIG))
    local dat, res, err = json.decode(io.readFile(CONFIG))
    if res then
        dtu = dat
        if dtu.apn and dtu.apn[1] and dtu.apn[1] ~= "" then link.setAPN(unpack(dtu.apn)) end
        if dtu.cmds and dtu.cmds[1] and tonumber(dtu.cmds[1][1]) then sys.taskInit(autoSampl, 1, dtu.cmds[1]) end
        if dtu.cmds and dtu.cmds[2] and tonumber(dtu.cmds[2][1]) then sys.taskInit(autoSampl, 2, dtu.cmds[2]) end
        if tonumber(dtu.nolog) ~= 1 then _G.LOG_LEVEL = log.LOG_SILENT end
    end
end
---------------------------------------------------------- 用户控制 GPIO 配置 ----------------------------------------------------------
-- 用户可用IO列表
if is1802S then
    pmd.ldoset(7, pmd.VLDO6)
    pios = {
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio20 = pins.setup(20, nil, pio.PULLDOWN),
        pio23 = pins.setup(23, nil, pio.PULLDOWN),
        pio24 = pins.setup(24, nil, pio.PULLDOWN),
        pio25 = pins.setup(25, nil, pio.PULLDOWN),
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
        -- pio29 = pins.setup(29, nil, pio.PULLDOWN),-- UART2 - RXD
        -- pio30 = pins.setup(30, nil, pio.PULLDOWN),-- UART2 - TXD
        pio31 = pins.setup(31, nil, pio.PULLDOWN),
        pio32 = pins.setup(32, 0, pio.PULLUP), -- UART2 485 默认方向脚
        pio33 = pins.setup(33, nil, pio.PULLDOWN),
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
        pio35 = pins.setup(35, nil, pio.PULLDOWN),
        pio36 = pins.setup(36, nil, pio.PULLDOWN),
        pio37 = pins.setup(37, nil, pio.PULLDOWN),
        pio38 = pins.setup(38, nil, pio.PULLDOWN),
        pio39 = pins.setup(39, nil, pio.PULLDOWN),
        pio40 = pins.setup(40, nil, pio.PULLDOWN),
        pio41 = pins.setup(41, nil, pio.PULLDOWN),
        pio42 = pins.setup(42, nil, pio.PULLDOWN),
        pio49 = pins.setup(49, nil, pio.PULLDOWN),
        pio50 = pins.setup(50, nil, pio.PULLDOWN),
        -- pio51 = pins.setup(51, nil, pio.PULLDOWN), -- UART1 rxd
        -- pio52 = pins.setup(52, nil, pio.PULLDOWN), -- uart 1 txd
        pio61 = pins.setup(61, 0, pio.PULLUP), -- UART1 485 默认方向脚
        pio62 = pins.setup(62, nil, pio.PULLDOWN),
        pio63 = pins.setup(63, nil, pio.PULLDOWN),
        pio64 = pins.setup(64, 0, pio.PULLUP), -- NETLED
        pio65 = pins.setup(65, nil, pio.PULLDOWN),
    -- pio66 = pins.setup(66, nil, pio.PULLDOWN),
    }
elseif is4gLod then
    pmd.ldoset(7, pmd.VLDO6)
    pios = {
        pio23 = pins.setup(23, 0, pio.PULLUP), -- 默认UART1的485方向控制脚
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
        pio33 = pins.setup(33, nil, pio.PULLDOWN),
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
        pio35 = pins.setup(35, nil, pio.PULLDOWN),
        pio36 = pins.setup(36, nil, pio.PULLDOWN),
        pio55 = pins.setup(55, nil, pio.PULLDOWN),
        pio56 = pins.setup(56, nil, pio.PULLDOWN),
        pio59 = pins.setup(59, 0, pio.PULLUP), -- 默认UART2的485方向控制脚
        pio62 = pins.setup(62, nil, pio.PULLDOWN),
        pio63 = pins.setup(63, nil, pio.PULLDOWN),
        pio64 = pins.setup(64, nil, pio.PULLDOWN), -- NETLED
        pio65 = pins.setup(65, nil, pio.PULLDOWN), -- NETREADY
        pio67 = pins.setup(67, nil, pio.PULLDOWN),
        pio68 = pins.setup(68, nil, pio.PULLDOWN), -- RSTCNF
        pio69 = pins.setup(69, nil, pio.PULLDOWN),
        pio70 = pins.setup(70, nil, pio.PULLDOWN),
        pio71 = pins.setup(71, nil, pio.PULLDOWN),
        pio72 = pins.setup(72, nil, pio.PULLDOWN),
        pio73 = pins.setup(73, nil, pio.PULLDOWN),
        pio74 = pins.setup(74, nil, pio.PULLDOWN),
        pio75 = pins.setup(75, nil, pio.PULLDOWN),
        pio76 = pins.setup(76, nil, pio.PULLDOWN),
        pio77 = pins.setup(77, nil, pio.PULLDOWN),
        pio78 = pins.setup(78, nil, pio.PULLDOWN),
        pio79 = pins.setup(79, nil, pio.PULLDOWN),
        pio80 = pins.setup(80, nil, pio.PULLDOWN),
        pio81 = pins.setup(81, nil, pio.PULLDOWN),
    }
elseif is8910 then
    pmd.ldoset(15, pmd.LDO_VLCD)
    pmd.ldoset(15, pmd.LDO_VMMC)
    pios = {
        pio0 = pins.setup(0, nil, pio.PULLDOWN),
        pio2 = pins.setup(2, nil, pio.PULLDOWN),
        pio3 = pins.setup(3, nil, pio.PULLDOWN),
        -- pio6 = pins.setup(6, nil, pio.PULLDOWN),
        pio7 = pins.setup(7, nil, pio.PULLDOWN),
        pio9 = pins.setup(9, nil, pio.PULLDOWN),
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio12 = pins.setup(12, nil, pio.PULLDOWN),
        pio13 = pins.setup(13, nil, pio.PULLDOWN),
        pio14 = pins.setup(14, nil, pio.PULLDOWN),
        pio15 = pins.setup(15, nil, pio.PULLDOWN),
        pio16 = pins.setup(16, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio19 = pins.setup(19, nil, pio.PULLDOWN),
        pio24 = pins.setup(24, nil, pio.PULLDOWN),
        pio25 = pins.setup(25, nil, pio.PULLDOWN),
        pio26 = pins.setup(26, nil, pio.PULLDOWN),
        pio27 = pins.setup(27, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN),
    }
else
    require "cc"
    pmd.ldoset(7, pmd.LDO_VLCD)
    pmd.ldoset(7, pmd.LDO_VMMC)
    pios = {
        pio2 = pins.setup(2, nil, pio.PULLDOWN), -- 默认UART1的485方向控制脚
        pio3 = pins.setup(3, nil, pio.PULLDOWN), -- 默认netready信号
        pio6 = pins.setup(6, nil, pio.PULLDOWN), -- 默认UART2的485方向控制脚
        pio7 = pins.setup(7, nil, pio.PULLDOWN),
        pio8 = pins.setup(8, nil, pio.PULLDOWN),
        pio9 = pins.setup(9, nil, pio.PULLDOWN),
        pio10 = pins.setup(10, nil, pio.PULLDOWN),
        pio11 = pins.setup(11, nil, pio.PULLDOWN),
        pio12 = pins.setup(12, nil, pio.PULLDOWN),
        pio13 = pins.setup(13, nil, pio.PULLDOWN),
        pio14 = pins.setup(14, nil, pio.PULLDOWN),
        pio15 = pins.setup(15, nil, pio.PULLDOWN),
        pio16 = pins.setup(16, nil, pio.PULLDOWN),
        pio17 = pins.setup(17, nil, pio.PULLDOWN),
        pio18 = pins.setup(18, nil, pio.PULLDOWN),
        pio28 = pins.setup(28, nil, pio.PULLDOWN), -- 默认202 NETLED
        pio29 = pins.setup(29, nil, pio.PULLDOWN), -- 默认恢复默认值
        pio33 = pins.setup(33, nil, pio.PULLDOWN), -- 默认800 NETLED
        pio34 = pins.setup(34, nil, pio.PULLDOWN),
    }
end

-- 网络READY信号
if not dtu.pins or not dtu.pins[2] or not pios[dtu.pins[2]] then -- 这么定义是为了和之前的代码兼容
    netready = pins.setup((is4gLod and 65) or (is8910 and 4) or 3, 0)
else
    netready = pins.setup(tonumber(dtu.pins[2]:sub(4, -1)), 0)
    pios[dtu.pins[2]] = nil
end

-- 重置DTU
if not dtu.pins or not dtu.pins[3] or not pios[dtu.pins[3]] then -- 这么定义是为了和之前的代码兼容
    pins.setup((is1802S or is8910 and 17) or (is4gLod and 68) or 29, function(msg)
        if msg ~= cpu.INT_GPIO_POSEDGE then
            if io.exists(CONFIG) then os.remove(CONFIG) end
            if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
            if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
            if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
            sys.restart("软件恢复出厂默认值: OK")
        end
    end, pio.PULLUP)
else
    pins.setup(tonumber(dtu.pins[3]:sub(4, -1)), function(msg)
        if msg ~= cpu.INT_GPIO_POSEDGE then
            if io.exists(CONFIG) then os.remove(CONFIG) end
            if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
            if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
            if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
            sys.restart("软件恢复出厂默认值: OK")
        end
    end, pio.PULLUP)
    pios[dtu.pins[3]] = nil
end
-- NETLED指示灯任务
local function blinkPwm(ledPin, light, dark)
    ledPin(1)
    sys.wait(light)
    ledPin(0)
    sys.wait(dark)
end
local function netled(led)
    local ledpin = pins.setup(led, 1)
    while true do
        -- GSM注册中
        while not link.isReady() do blinkPwm(ledpin, 100, 100) end
        while link.isReady() do
            if create.getDatalink() then
                netready(1)
                blinkPwm(ledpin, 200, 1800)
            else
                netready(0)
                blinkPwm(ledpin, 500, 500)
            end
        end
        sys.wait(100)
    end
end
if not dtu.pins or not dtu.pins[1] or not pios[dtu.pins[1]] then -- 这么定义是为了和之前的代码兼容
    sys.taskInit(netled, (is4gLod and 64) or (is8910 and 1) or 33)
else
    sys.taskInit(netled, tonumber(dtu.pins[1]:sub(4, -1)))
    pios[dtu.pins[1]] = nil
end
---------------------------------------------------------- DTU 任务部分 ----------------------------------------------------------
-- 配置串口
if dtu.pwrmod ~= "energy" then pm.wake("mcuUart.lua") end

-- 每隔1分钟重置串口计数
sys.timerLoopStart(function()
    flow = tonumber(dtu.flow)
    if flow and flow ~= 0 then
        if flowCount[1] > flow then
            uart.on(1, "receive")
            uart.close(1)
            log.info("uart","uart1.read length count:", flowCount[1])
        end
        if flowCount[2] > flow then
            uart.on(2, "receive")
            uart.close(2)
            log.info("uart","uart2.read length count:", flowCount[2])
        end
    end
    if timecnt > 60 then
        timecnt = 1
        flowCount = {0, 0}
    else
        timecnt = timecnt + 1
    end
end, 1000)

-- 串口写数据处理
function write(uid, str)
    if not str or str == "" then return end
    if str ~= true then
        for i = 1, #str, SENDSIZE do
            table.insert(writeBuff[uid], str:sub(i, i + SENDSIZE - 1))
        end
        log.info("uart","uart" .. uid .. ".write data length:", writeIdle[uid], #str)
    end
    if writeIdle[uid] and writeBuff[uid][1] then
        local s = writeBuff[uid][1]
        if 0 ~= uart.write(uid, s) then
            table.remove(writeBuff[uid], 1)
            writeIdle[uid] = false
            log.info("uart","UART_" .. uid .. " writing ...",(s:toHex()))
        end
    end
end

local function writeDone(uid)
    if #writeBuff[uid] == 0 then
        writeIdle[uid] = true
        sys.publish("uart","UART_" .. uid .. "_WRITE_DONE")
        log.debug("uart","UART_" .. uid .. " write done!")
    else
        writeIdle[uid] = false
        local s = table.remove(writeBuff[uid], 1)
        uart.write(uid, s)
        log.info("uart","UART_" .. uid .. " writing",(s:toHex()))
    end
end

-- DTU配置工具默认的方法表
cmd = {}
cmd.config = {
    ["pipe"] = function(t, num)dtu.conf[tonumber(num)] = t return "OK" end, -- "1"-"7" 为通道配置
    ["A"] = function(t)dtu.apn = t return "OK" end, -- APN 配置
    ["B"] = function(t)dtu.cmds[tonumber(table.remove(t, 1)) or 1] = t return "OK" end, -- 自动任务下发配置
    ["pins"] = function(t)dtu.pins = t return "OK" end, -- 自定义GPIO
    ["host"] = function(t)dtu.host = t[1] return "OK" end, -- 自定义参数升级服务器
    ["0"] = function(t)-- 读取整个DTU的参数配置
        local password = ""
        dtu.passon, dtu.plate, dtu.convert, dtu.reg, dtu.param_ver, dtu.flow, dtu.fota, dtu.uartReadTime, dtu.pwrmod, password, dtu.netReadTime, dtu.nolog = unpack(t)
        if password == dtu.password or dtu.password == "" or dtu.password == nil then
            dtu.password = password
            io.writeFile(CONFIG, json.encode(dtu))
            sys.timerStart(sys.restart, 1000, "Setting parameters have been saved!")
            return "OK"
        else
            return "PASSWORD ERROR"
        end
    end,
    ["8"] = function(t)-- 串口配置默认方法
        local tmp = "1200,2400,4800,9600,14400,19200,28800,38400,57600,115200,230400,460800,921600"
        if t[1] and t[2] and t[3] and t[4] and t[5] then
            if ("1,2"):find(t[1]) and tmp:find(t[2]) and ("7,8"):find(t[3]) and ("0,1,2"):find(t[4]) and ("0,2"):find(t[5]) then
                dtu.uconf[tonumber(t[1])] = t
                return "OK"
            else
                return "ERROR"
            end
        end
    end,
    ["9"] = function(t)-- 预置白名单
        dtu.preset.number, dtu.preset.delay, dtu.preset.smsword = unpack(t)
        dtu.preset.delay = tonumber(dtu.preset.delay) or 1
        return "OK"
    end,
    ["readconfig"] = function(t)-- 读取整个DTU的参数配置
        if t[1] == dtu.password or dtu.password == "" or dtu.password == nil then
            if io.exists(CONFIG) then return io.readFile(CONFIG) end
            return "ERROR"
        else
            return "PASSWORD ERROR"
        end
    end,
    ["writeconfig"] = function(t, s)-- 读取整个DTU的参数配置
        local str = s:match("(.+)\r\n") and s:match("(.+)\r\n"):sub(20, -1) or s:sub(20, -1)
        local dat, result, errinfo = json.decode(str)
        if result then
            if dtu.password == dat.password or dtu.password == "" or dtu.password == nil then
                io.writeFile(CONFIG, str)
                sys.timerStart(sys.restart, 1000, "Setting parameters have been saved!")
                return "OK"
            else
                return "PASSWORD ERROR"
            end
        else
            return "JSON ERROR"
        end
    end
}
cmd.rrpc = {
    ["getver"] = function(t) return "rrpc,getver," .. _G.VERSION end,
    ["getcsq"] = function(t) return "rrpc,getcsq," .. (net.getRssi() or "error ") end,
    ["getadc"] = function(t) return "rrpc,getadc," .. create.getADC(tonumber(t[1]) or 0) end,
    ["reboot"] = function(t)sys.timerStart(sys.restart, 1000, "Remote reboot!") return "OK" end,
    ["getimei"] = function(t) return "rrpc,getimei," .. (misc.getImei() or "error") end,
    ["getimsi"] = function(t) return "rrpc,getimsi," .. (sim.getImsi() or "error") end,
    ["getvbatt"] = function(t) return "rrpc,getvbatt," .. misc.getVbatt() end,
    ["geticcid"] = function(t) return "rrpc,geticcid," .. (sim.getIccid() or "error") end,
    ["getproject"] = function(t) return "rrpc,getproject," .. _G.PROJECT end,
    ["getlocation"] = function(t) return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0) end,
    ["getreallocation"] = function(t)
        lbsLoc.request(function(result, lat, lng, addr)
            if result then
                lbs.lat, lbs.lng = lat, lng
                create.setLocation(lat, lng)
            end
        end)
        return "rrpc,location," .. (lbs.lat or 0) .. "," .. (lbs.lng or 0)
    end,
    ["gettime"] = function(t)
        if ntp.isEnd() then
            local c = misc.getClock()
            return "rrpc,nettime," .. string.format("%04d,%02d,%02d,%02d,%02d,%02d\r\n", c.year, c.month, c.day, c.hour, c.min, c.sec)
        else
            return "rrpc,nettime,error"
        end
    end,
    ["setpio"] = function(t) if pios["pio" .. t[1]] then pios["pio" .. t[1]](tonumber(t[2]) or 0) return "OK" end return "ERROR" end,
    ["getpio"] = function(t) if pios["pio" .. t[1]] then return "rrpc,getpio" .. t[1] .. "," .. pios["pio" .. t[1]]() end return "ERROR" end,
    ["getsht"] = function(t) local tmp, hum = iic.sht(2, tonumber(t[1])) return "rrpc,getsht," .. (tmp or 0) .. "," .. (hum or 0) end,
    ["getam2320"] = function(t) local tmp, hum = iic.am2320(2, tonumber(t[1])) return "rrpc,getam2320," .. (tmp or 0) .. "," .. (hum or 0) end,
    ["netstatus"] = function(t) return "rrpc,netstatus," .. (create.getDatalink() and "RDY" or "NORDY") end,
    ["gps_wakeup"] = function(t)sys.publish("REMOTE_WAKEUP") return "rrpc,gps_wakeup,OK" end,
    ["gps_getsta"] = function(t) return "rrpc,gps_getsta," .. tracker.deviceMessage(t[1] or "json") end,
    ["gps_getmsg"] = function(t) return "rrpc,gps_getmsg," .. tracker.locateMessage(t[1] or "json") end,
    ["upconfig"] = function(t)sys.publish("UPDATE_DTU_CNF") return "rrpc,upconfig,OK" end,
    ["function"] = function(t)log.info("rrpc,function:", table.concat(t, ",")) return "rrpc,function," .. (loadstring(table.concat(t, ","))() or "OK") end,
    ["tts_play"] = function(t)
        if not isTTS then return "rrpc,tts_play,not_tts_lod" end
        local str = string.upper(t[1]) == "GB2312" and common.gb2312ToUtf8(t[2]) or t[2]
        audio.play(1, "TTS", str, tonumber(t[3]) or 7, nil, false, 0)
        return "rrpc,tts_play,OK"
    end
}

local function reloadFactory()
    if io.exists(lnxall_conf.LNXALL_factory_info) then
        local str = io.readFile(lnxall_conf.LNXALL_factory_info)
        local obj = json.decode(str)
        if obj  and misc.setGatewayID and type(misc.setGatewayID)  == "function" then
            misc.setGatewayID(obj.sn)
        end
        if obj  and misc.setRunMode and type(misc.setRunMode)  == "function"  then
            misc.setRunMode(obj.run_mode)
        end
        if obj  and misc.setProductName and type(misc.setProductName)  == "function"  then
            misc.setProductName(obj.product)
        end
    else
        log.warn("Factory","Not factory file was read")
    end
end


-- 出厂工具通过串口工具修改配置工厂配置 factory [options] <param> ...
local function factoryCmd(cmd)
    log.info("Factory",cmd)
    cmd = string.gsub(string.gsub(cmd,"\r", ""),"\n", "")
    local t = cmd:split(' ')
    local sn,date,hwver,product = nil,nil,nil,nil
    local change = nil
    local obj = {}
    table.remove(t, 1)
    local i=1
    while #t > 0  do
        local options = table.remove(t, 1) i = i + 1
        local param = nil
        if options == 'show' then
            log.info("Factory","|key|     |value|")
            if io.exists(lnxall_conf.LNXALL_factory_info) then
                local json_str = io.readFile(lnxall_conf.LNXALL_factory_info)
                for k,v in pairs(json_str and json.decode(json_str)) do
                    log.info("Factory",k,"=",v)
                end
            else
                log.warn("Factory","Not factory file was read")
            end
            break
        elseif options == '-sn' or options == '-date' or options == '-mac' or options == '-hwver' or options == '-product' then
            param = table.remove(t, 1) i = i + 1
            obj[options:sub(2,-1)] = param
            change = true
            log.info("Factory",options:sub(2,-1),"=",param)
        elseif options == 'check' then
            sys.publish("FACTORY_CHECK_START")
            break
        end
    end
    if change and change == true then
        obj["run_mode"] = 0
        log.info("Factory","save factory info",json.encode(obj))
        io.writeFile(lnxall_conf.LNXALL_factory_info,json.encode(obj))
        if io.exists(lnxall_conf.LNXALL_factory_info) then
            local json_str = io.readFile(lnxall_conf.LNXALL_factory_info)
            uart.write(uid,string.format("|key|\t|value|\n"))
            for k,v in pairs(json_str and json.decode(json_str)) do
                uart.write(uid, string.format("|%s|\t|%s|\n",k,v))
            end
        else
            uart.write(uid, "Write SN Failed\n")
        end
        reloadFactory()
    end
end

function uart_timeout(uid,str)
    local uid = 1
    log.info("maybe miss recive data with uart_" .. uid)
    confirmIdle[uid] = true
    local str = table.remove(confirmBuff[uid])
    if str then sys.publish("NET_RECV_WAIT_" .. uid, uid, str) end

end

-- 串口读指令
local function read(uid)
    local s = table.concat(recvBuff[uid])
    recvBuff[uid] = {}
    -- 串口流量统计
    flowCount[uid] = flowCount[uid] + #s
    -- log.info("UART_" .. uid .. "read length:", #s)
    log.info("UART_" .. uid .. " read:", (s:toHex()))
    log.info("串口流量统计值:", flowCount[uid])
    -- 根据透传标志位判断是否解析数据
    if s:sub(1, 3) == "+++" or s:sub(1, 5):match("(.+)\r\n") == "+++" then
        write(uid, "OK\r\n")
        if io.exists(CONFIG) then os.remove(CONFIG) end
        if io.exists("/alikey.cnf") then os.remove("/alikey.cnf") end
        if io.exists("/qqiot.dat") then os.remove("/qqiot.dat") end
        if io.exists("/bdiot.dat") then os.remove("/bdiot.dat") end
        sys.restart("Restore default parameters:", "OK")
    end

    if s:sub(1,1) == "\n" or s:sub(1,2) == "\r\n" then
        uart.write(uid, "luat OK\n")
        return
    end

    if s:sub(1, 7) == "factory" then
        local status,error = pcall(factoryCmd,s)
        if not status then
            log.error("uart",error)
        end
        return
    end
    -- DTU的参数配置
    if s:sub(1, 7) == "config," or s:sub(1, 5) == "rrpc," then
        local t = s:match("(.+)\r\n") and s:match("(.+)\r\n"):split(',') or s:split(',')
        local first = table.remove(t, 1)
        local second = table.remove(t, 1) or ""
        if tonumber(second) and tonumber(second) > 0 and tonumber(second) < 8 then
            write(uid, cmd[first]["pipe"](t, second) .. "\r\n")
            return
        else
            if cmd[first][second] then write(uid, cmd[first][second](t, s) .. "\r\n") return end
        end
    end
    -- 执行单次HTTP指令
    if s:sub(1, 5) == "http," then
        local str = ""
        local idx1, idx2, jsonstr = s:find(",[\'\"](.+)[\'\"],")
        if jsonstr then
            str = s:sub(1, idx1) .. s:sub(idx2, -1)
        else
            -- 判是不是json，如果不是json，则是普通的字符串
            idx1, idx2, jsonstr = s:find(",([%[{].+[%]}]),")
            if jsonstr then
                str = s:sub(1, idx1) .. s:sub(idx2, -1)
            else
                str = s
            end
        end
        local t = str:match("(.+)\r\n") and str:match("(.+)\r\n"):split(',') or str:split(',')
        if not socket.isReady() then write(uid, "NET_NORDY\r\n") return end
        sys.taskInit(function(t, uid)
            local code, head, body = httpv2.request(t[2]:upper(), t[3], (t[4] or 10) * 1000, nil, jsonstr or t[5], tonumber(t[6]) or 1, t[7], t[8])
            log.info("uart http response:", body)
            write(uid, body)
        end, t, uid)
        return
    end
    -- 执行单次SOCKET透传指令
    if s:sub(1, 4):upper() == "TCP," or s:sub(1, 4):upper() == "UDP," then
        -- local t = s:match("(.+)\r\n") and s:match("(.+)\r\n"):split(',') or s:split(',')
        s = s:match("(.+)\r\n") or s
        if not socket.isReady() then
            write(uid, "NET_NORDY\r\n")
            return
        end
        sys.taskInit(function(uid, prot, ip, port, ssl, timeout, data)
            local c = prot:upper() == "TCP" and socket.tcp(ssl and ssl:lower() == "ssl") or socket.udp()
            while not c:connect(ip, port) do sys.wait(2000) end
            if c:send(data) then
                write(uid, "SEND_OK\r\n")
                local r, s = c:recv(timeout * 1000)
                if r then write(uid, s) end
            else
                write(uid, "SEND_ERR\r\n")
            end
            c:close()
        end, uid, s:match("(.-),(.-),(.-),(.-),(.-),(.+)"))
        return
    end
    -- 添加设备识别码
    if tonumber(dtu.passon) == 1 then
        local interval, samptime = create.getTimParam()
        if interval[uid] > 0 then -- 定时采集透传模式
            -- 这里注意间隔时长等于预设间隔时长的时候就要采集,否则1秒的采集无法采集
            if os.difftime(os.time(), startTime[uid]) >= interval[uid] then
                if os.difftime(os.time(), startTime[uid]) < interval[uid] + samptime[uid] then
                    table.insert(sendBuff[uid], s)
                elseif startTime[uid] == 0 then
                    -- 首次上电立刻采集1次
                    table.insert(sendBuff[uid], s)
                    startTime[uid] = os.time() - interval[uid]
                else
                    startTime[uid] = os.time()
                    if #sendBuff[uid] ~= 0 then
                        sys.publish("NET_SENT_RDY_" .. uid, tonumber(dtu.plate) == 1 and misc.getImei() .. table.concat(sendBuff[uid]) or table.concat(sendBuff[uid]))
                        sendBuff[uid] = {}
                    end
                end
            else
                sendBuff[uid] = {}
            end
        else -- 正常透传模式
            sys.publish("NET_SENT_RDY_" .. uid, s)
        end
    else
        -- 非透传模式,解析数据
        if s:sub(1, 5) == "send," then
            sys.publish("NET_SENT_RDY_" .. s:sub(6, 6), s:sub(8, -1))
        else
            -- lnxall 协议解析数据
            sys.publish("NET_SENT_RDY_" .. uid, s)
            --停用超时计数器
            sys.timerStopAll(uart_timeout)
            -- write(uid, "ERROR\r\n")
            confirmIdle[uid] = true

            local str = table.remove(confirmBuff[uid])
            if str then sys.publish("NET_RECV_WAIT_" .. uid, uid, str) end
        end
    end
end

-- uart 的初始化配置函数
function uart_INIT(i, uconf)
    local id = (is8910 and i == 2) and 3 or i
    if id == 3 then return end
    uart.setup(i, uconf[i][2], uconf[i][3], uconf[i][4], uconf[i][5], nil, 1)
    uart.on(i, "sent", writeDone)
    uart.on(i, "receive", function(uid, length)
        table.insert(recvBuff[uid], uart.read(uid, length or 8192))
        sys.timerStart(sys.publish, 800, "UART_RECV_WAIT_" .. uid, uid)
    end)
    -- 处理串口接收到的数据
    sys.subscribe("UART_RECV_WAIT_" .. i, read)
    sys.subscribe("UART_SENT_RDY_" .. i, write)
    -- 网络数据写串口延时分帧
    sys.subscribe("NET_RECV_WAIT_" .. i, function(uid, str)
        if not str or #str < 2 then return end

        if confirmIdle[uid] and confirmIdle[uid] == true then --空闲
            if tonumber(dtu.netReadTime) and tonumber(dtu.netReadTime) > 5 then
                for j = 1, #str, SENDSIZE do
                    table.insert(writeBuff[uid], str:sub(j, j + SENDSIZE - 1))
                end
                sys.timerStart(sys.publish, tonumber(dtu.netReadTime) or 30, "UART_SENT_RDY_" .. uid, uid, true)
            else
                sys.publish("UART_SENT_RDY_" .. uid, uid, str)
                log.info("UART_SENT_RDY_" .. uid,(str:toHex()))
            end
            --创建超时timeout
            sys.timerStart(uart_timeout, 1500, uid,str)
            confirmIdle[uid] = false
        else

            table.insert(confirmBuff[uid],str)--排队发送
        end

    end)
    -- 485方向控制
    if not dtu.uconf[i][6] or dtu.uconf[i][6] == "" then -- 这么定义是为了和之前的代码兼容
        default["dir" .. i] = i == 1 and (is1802S and 61 or (is4gLod and 23 or 2)) or (is1802S and 32 or (is4gLod and 59 or 6))
    else
        if pios[dtu.uconf[i][6]] then
            default["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
            pios[dtu.uconf[i][6]] = nil
        else
            default["dir" .. i] = nil
        end
    end
    if default["dir" .. i] then
        pins.setup(default["dir" .. i], 0)
        uart.set_rs485_oe(i, default["dir" .. i])
    end
    -- 为了模拟linux 系统启动消息,出厂工具上电可以检查到设备
    uart.write(i, "luat running\n")
end
------------------------------------------------ 远程任务 ----------------------------------------------------------
-- 远程自动更新参数和更新固件任务每隔24小时检查一次
sys.taskInit(function()
    local rst, code, head, body, url = false
    while true do
        rst = false
        if not socket.isReady() and not sys.waitUntil("IP_READY_IND", 600000) then sys.restart("Network initialization failed!") end
        if dtu.host and dtu.host ~= "" then
            local param = {product_name = _G.PROJECT, param_ver = dtu.param_ver, imei = misc.getImei()}
            code, head, body = httpv2.request("GET", dtu.host, 30000, param, nil, 1)
        else
            url = "dtu.openluat.com/api/site/device/" .. misc.getImei() .. "/param?product_name=" .. _G.PROJECT .. "&param_ver=" .. dtu.param_ver
            code, head, body = httpv2.request("GET", url, 30000, nil, nil, 1, misc.getImei() .. ":" .. misc.getMuid())
        end
        if tonumber(code) == 200 and body then
            -- log.info("Parameters issued from the server:", body)
            local dat, res, err = json.decode(body)
            if res and tonumber(dat.param_ver) ~= tonumber(dtu.param_ver) then
                io.writeFile(CONFIG, body)
                rst = true
            end
        end

        -- 检查是否有更新程序
        if tonumber(dtu.fota) == 1 then
            if is4gLod and rtos.fota_start() == 0 then
                url = "iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY
                    .. "&imei=" .. misc.getImei() .. "&device_key=" .. misc.getSn()
                    .. "&firmware_name=" .. _G.PROJECT .. "_" .. rtos.get_version() .. "&version=" .. _G.VERSION
                code, head, body = httpv2.request("GET", url, 30000, nil, nil, nil, nil, nil, nil, rtos.fota_process)
                if tonumber(code) == 200 or tonumber(code) == 206 then rst = true end
                rtos.fota_end()
            elseif not is4gLod then
                url = "iot.openluat.com/api/site/firmware_upgrade?project_key=" .. _G.PRODUCT_KEY
                    .. "&imei=" .. misc.getImei() .. "&device_key=" .. misc.getSn()
                    .. "&firmware_name=" .. _G.PROJECT .. "_" .. rtos.get_version() .. "&version=" .. _G.VERSION
                code, head, body = httpv2.request("GET", url, 30000)
                if tonumber(code) == 200 and body and #body > 1024 then
                    io.writeFile("/luazip/update.bin", body)
                    rst = true
                end
            end
        end
        if rst then sys.restart("DTU Parameters or firmware are updated!") end
        ---------- 基站坐标查询 ----------
        lbsLoc.request(function(result, lat, lng, addr)
            if result then
                lbs.lat, lbs.lng = lat, lng
                create.setLocation(lat, lng)
            end
        end)
        ---------- 启动网络任务 ----------
        sys.publish("DTU_PARAM_READY")
        log.warn("短信或电话请求更新:", sys.waitUntil("UPDATE_DTU_CNF", 86400000))
    end
end)

sys.timerLoopStart(function()
    log.info("打印占用的内存:", _G.collectgarbage("count"))-- 打印占用的RAM
    log.info("打印可用的空间", rtos.get_fs_free_size())-- 打印剩余FALSH，单位Byte
    socket.printStatus()
end, 10000)

local callFlag = false
sys.subscribe("CALL_INCOMING", function(num)
    log.info("Telephone number:", num)
    if num:match(dtu.preset.number) then
        if not callFlag then
            callFlag = true
            sys.timerStart(cc.hangUp, dtu.preset.delay * 1000, num)
            sys.timerStart(sys.publish, (dtu.preset.delay + 5) * 1000, "UPDATE_DTU_CNF")
        end
    else
        cc.hangUp(num)
    end
end)

sys.subscribe("CALL_DISCONNECTED", function()
    callFlag = false
    sys.timerStopAll(cc.hangUp)
end)

sms.setNewSmsCb(function(num, data, datetime)
    log.info("Procnewsms", num, data, datetime)
    if num:match(dtu.preset.number) and data == dtu.preset.smsword then
        sys.publish("UPDATE_DTU_CNF")
    end
end)

-- 初始化配置UART1和UART2


local uidgps = dtu.gps and dtu.gps.fun and tonumber(dtu.gps.fun[1])
local config = lnxall_conf.get_uart_param()
if config and #config > 0 then
    if #config  >= 1 and tonumber(config[1][1]) == 1 then uart_INIT(1, config) end
    if #config  >= 2 and tonumber(config[2][1]) == 2 then uart_INIT(2, config) end
else
    if uidgps ~= 1 and dtu.uconf and dtu.uconf[1] and tonumber(dtu.uconf[1][1]) == 1 then uart_INIT(1, dtu.uconf)   end
    if uidgps ~= 2 and dtu.uconf and dtu.uconf[2] and tonumber(dtu.uconf[2][1]) == 2 then uart_INIT(2, dtu.uconf)   end
end

-- 启动GPS任务
if uidgps then
    -- 从pios列表去掉自定义的io
    if dtu.gps.pio then
        for i = 1, 3 do if pios[dtu.gps.pio[i]] then pios[dtu.gps.pio[i]] = nil end end
    end
    sys.taskInit(tracker.sensMonitor, unpack(dtu.gps.pio))
    sys.taskInit(tracker.alert, unpack(dtu.gps.fun))
end

---------------------------------------------------------- 预警任务线程 ----------------------------------------------------------
if dtu.warn and dtu.warn.gpio and #dtu.warn.gpio > 0 then
    for i = 1, #dtu.warn.gpio do
        pins.setup(tonumber(dtu.warn.gpio[i][1]:sub(4, -1)), function(msg)
            if (msg == cpu.INT_GPIO_NEGEDGE and tonumber(dtu.warn.gpio[i][2]) == 1) or (msg == cpu.INT_GPIO_POSEDGE and tonumber(dtu.warn.gpio[i][3]) == 1) then
                if tonumber(dtu.warn.gpio[i][6]) == 1 then sys.publish("NET_SENT_RDY_" .. dtu.warn.gpio[i][5], dtu.warn.gpio[i][4]) end
                if dtu.preset and tonumber(dtu.preset.number) then
                    if tonumber(dtu.warn.gpio[i][7]) == 1 then sms.send(dtu.preset.number, common.utf8ToGb2312(dtu.warn.gpio[i][4])) end
                    if tonumber(dtu.warn.gpio[i][8]) == 1 then
                        if cc and cc.dial then
                            cc.dial(dtu.preset.number, 5)
                        else
                            ril.request(string.format("%s%s;", "ATD", dtu.preset.number), nil, nil, 5)
                        end
                    end
                end
            end
        end, pio.PULLUP)
    end
end

local function adcWarn(adcid, und, lowv, over, highv, diff, msg, id, sfreq, upfreq, net, note, tel)
    local upcnt, scancnt, adcValue, voltValue = 0, 0, 0, 0
    diff = tonumber(diff) or 1
    lowv = tonumber(lowv) or 1
    highv = tonumber(highv) or 4200
    while true do
        -- 获取ADC采样电压
        scancnt = scancnt + 1
        if scancnt == tonumber(sfreq) then
            if adcid == 0 or adcid == 1 then
                adc.open(adcid)
                adcValue, voltValue = adc.read(adcid)
                if adcValue ~= 0xFFFF or voltValue ~= 0xFFFF then
                    voltValue = (voltValue - voltValue % 3) / 3
                end
                adc.close(adcid)
            else
                voltValue = misc.getVbatt()
            end
            scancnt = 0
        end
        -- 处理上报
        if ((tonumber(und) == 1 and voltValue < tonumber(lowv)) or (tonumber(over) == 1 and voltValue > tonumber(highv))) then
            if upcnt == 0 then
                if tonumber(net) == 1 then sys.publish("NET_SENT_RDY_" .. id, msg) end
                if tonumber(note) == 1 and dtu.preset and tonumber(dtu.preset.number) then sms.send(dtu.preset.number, common.utf8ToGb2312(msg)) end
                if tonumber(tel) == 1 and dtu.preset and tonumber(dtu.preset.number) then
                    if cc and cc.dial then
                        cc.dial(dtu.preset.number, 5)
                    else
                        ril.request(string.format("%s%s;", "ATD", dtu.preset.number), nil, nil, 5)
                    end
                end
                upcnt = tonumber(upfreq)
            else
                upcnt = upcnt - 1
            end
        end
        -- 解除警报
        if voltValue > tonumber(lowv) + tonumber(diff) and voltValue < tonumber(highv) - tonumber(diff) then upcnt = 0 end
        sys.wait(1000)
    end
end
if dtu.warn and dtu.warn.adc0 and dtu.warn.adc0[1] then
    sys.taskInit(adcWarn, 0, unpack(dtu.warn.adc0))
end
if dtu.warn and dtu.warn.adc1 and dtu.warn.adc1[1] then
    sys.taskInit(adcWarn, 1, unpack(dtu.warn.adc1))
end
if dtu.warn and dtu.warn.vbatt and dtu.warn.vbatt[1] then
    sys.taskInit(adcWarn, 9, unpack(dtu.warn.vbatt))
end

-- 如果lx_mqtt存在,添加通道8
if lnxall_conf.lx_mqtt then
    local configs = lnxall_conf.transparent_param()
    if configs then
        for i,config in ipairs(configs) do
        table.insert(dtu.conf,i,config)
        end
    end
    table.insert(dtu.conf,lnxall_conf.lx_mqtt )
end

-- 判断一下兼容lib库,如果没有新库不会报错
if log.remote_cfg and type(log.remote_cfg) == "function" then
    log.remote_cfg(lnxall_conf.remote_log_param())-- reload log config
end

-- ---------------------------------------------------------- 远程日志线程 ----------------------------------------------------------
sys.taskInit(function()
    if not socket.isReady() and not sys.waitUntil("IP_READY_IND", rstTim) then sys.restart("网络初始化失败!") end

    while true do
        local remote_addr = nil
        if log.get_remote_addr and type(log.get_remote_addr) == "function" then
            remote_addr = log.get_remote_addr()
        end
        local timeout = 5 * 60 * 1000
        local protocol = remote_addr:match("(%a+)://")
        sys.wait(10*60*1000)
        while true do
            if not remote_addr or remote_addr == "" then break end
            if protocol~="http" and protocol~="udp" and protocol~="tcp" then
                log.error("remote.log","remote log request invalid protocol",protocol)
                break
            end
            local log = log.get_remote_log()

            if protocol=="http" then
                http.request("POST",remote_addr,nil,nil,log,20000,httpPostCbFnc)
                _,result = sys.waitUntil("ERRDUMP_HTTP_POST")
            else
                local host,port = remote_addr:match("://(.+):(%d+)$")
                if not host then
                    log.error("remote.log","request invalid host port")
                else
                    local sck = protocol=="udp" and socket.udp() or socket.tcp()
                    if sck:connect(host,port,timeout) then
                        result = sck:send(log)
                        sys.wait(300)
                        sck:close()
                    end
                end
            end
            sys.wait(100)
        end
    end
end)

-- ---------------------------------------------------------- 参数配置,任务转发，线程守护主进程----------------------------------------------------------
sys.taskInit(create.connect, pios, dtu.conf, dtu.reg, tonumber(dtu.convert) or 0, (tonumber(dtu.passon) == 0), dtu.upprot, dtu.dwprot)


local function reload()
    lnxall_conf.reload()
    status.reload()
end

function JJ_Msg_subscribe()
    lost_count = 0
    run_led_status = 0
    sys.timerLoopStart(function()
        pins.setup(pio.P0_27, run_led_status)
        if run_led_status == 0 then run_led_status  = 1
        else run_led_status  = 0 end
    end,500)
    netLed.setup(true, pio.P0_28, pio.P2_1)
    -- ********************** 异步消息下行配置 ********************************
    sys.subscribe("JJ_NET_RECV_" .. "LoginRsp",function(status)
        if status then
            login = 'login'
            lost_count = 0
        end
    end)
    sys.subscribe("JJ_NET_RECV_" .. "Active",function()
        lost_count = 0
    end)
    sys.subscribe("JJ_NET_RECV_" .. "Rs485",function(payload)
        if payload then io.writeFile(lnxall_conf.LNXALL_rs485, payload) end
        local config = lnxall_conf.get_uart_param()
        if config and #config > 0 then
            for i=1,#config do default.reload_uart(i,config) end
        end
    end)
    sys.subscribe("JJ_NET_RECV_" .. "RunMode",function(payload)
        local mode = json.decode(payload)
        if mode and mode.run_mode and io.exists(lnxall_conf.LNXALL_factory_info) then
            local str = io.readFile(lnxall_conf.LNXALL_factory_info)
            local obj = json.decode(str)
            if not obj.sn then
                log.warn("runMode", "Need before do factory process")
            else
                obj.run_mode = mode.run_mode
                io.writeFile(lnxall_conf.LNXALL_factory_info,json.encode(obj))
            end
        end
    end)
    sys.subscribe("JJ_NET_RECV_" .. "Transparent",function(payload)
        local local_cfg = nil
        if io.exists(lnxall_conf.LNXALL_transparent_cfg) then
            local_cfg, res, err = json.decode(io.readFile(lnxall_conf.LNXALL_transparent_cfg) or '')
        end
        local remote_cfg, res, err = json.decode(payload)
        -- 如果配置没变不重启
        if not local_cfg or local_cfg.version ~= remote_cfg.version then
            if payload then io.writeFile(lnxall_conf.LNXALL_transparent_cfg, payload) end
            -- 设定一定的延迟生效,如果有配置推送过来从新延迟
            sys.timerStart(function()
                sys.restart("透传配置变更重启!!!")
            end,3*1000)
        end
    end)
    sys.subscribe("JJ_NET_RECV_" .. "Rstart", function()
        sys.timerStart(function()
            sys.restart("远程重启命令重启!!!")
        end,3*1000)
    end)
    sys.subscribe("JJ_NET_RECV_" .. "Remote_log",function(payload)
        if payload then io.writeFile(lnxall_conf.LNXALL_remote_log_cfg, payload) end
        local remote_addr = nil
        if log.remote_cfg and type(log.remote_cfg) == "function" then
            log.remote_cfg(lnxall_conf.remote_log_param())-- reload log config
        end
    end)

-- ********************** 同步消息读取配置状态 ********************************
    sys.subscribe("JJ_NET_RECV_" .. "GetVersion", function(payload)
        local msg = json.decode(payload)
        local str =  json.encode({
            mi = msg.mi,
            timestamp = os.time(),
            soft_ver = _G.VERSION
            })
        if str then
            sys.publish("JJ_NET_SEND_MSG_" .. "RespVersion", str)
        end
    end)

-- ********************** 设备主动发起消息 ********************************
    sys.timerLoopStart(function()
        if login and login == 'login' then
            if lost_count > 5 then login = nil log.warn('disconnect platform by heart beat timeout',status) end
            sys.publish("JJ_NET_SEND_MSG_" .. "HeartBeat")
            lost_count = lost_count + 1
        else
            local str =  json.encode({
                mi = lnxall_conf.msgid(),
                timestamp = os.time(),
                arch = 'none',
                soft_ver = _G.VERSION,
                imei=misc.getImei(),
                product=misc.getProductName(),
                product = misc.getProductName and type(misc.getProductName)  == "function" and misc.getProductName(),
                run_mode = misc.getRunMode and type(misc.getRunMode)  == "function" and misc.getRunMode() or 0
                })
            if str then
                sys.publish("JJ_NET_SEND_MSG_" .. "LoginReq", str)
            end
        end
    end, 60 * 1000)
end

-- ********************** 异步消息下行配置(需要独立协程处理,含有辅助业务逻辑) ********************************
sys.taskInit(function()
    while true do
        local result, data  = nil,nil
        result, data = sys.waitUntil("JJ_NET_RECV_" .. "NodesCfg",100)
        if result and result == true and data then
            if not lnxall_conf.downloadByJson(data,lnxall_conf.LNXALL_nodes_cfg,2000) then
                log.warn("node.config",'download nodes config files failed!',status)
            end
            -- 设定一定的延迟生效,如果有配置推送过来从新延迟
            if sys.timerIsActive(reload) then sys.timerStop(reload) end
            sys.timerStart(reload, 5000)
        end
    end
end)

sys.taskInit(function()
    while true do
        local result, data  = nil,nil
        result, data = sys.waitUntil("JJ_NET_RECV_" .. "NodesTemp",100)
        if result and result == true and data then
            local ret,json_in = lnxall_conf.downloadByJson(data,nil,2000)
            if ret and ret == true and json_in then
                local obj = json.decode(json_in)
                if obj and obj.template_cfg then
                    for _,temp in ipairs(obj.template_cfg)do
                        -- 去除不用保存的项节省内存
                        temp.tag_cfg=nil
                        temp.event_cfg=nil
                        temp.mac_info=nil
                        for _,service_cfg in ipairs(temp.service_cfg) do --找服务
                            if service_cfg.param then service_cfg.param = nil end
                        end

                        if temp.use_parser_url and temp.use_parser_url == 1 and temp.parser_url then
                            local part = temp.parser_url:split("/")
                            if part and #part >= 0 then
                                local file = part[#part]
                                log.info("node.template","script name:" .. file)
                                if not file then log.warn("template parser_url: " .. temp.parser_url .. ' split index: ' .. #part .. 'failed') break end
                                -- 文件下载包本地
                                local ret,lua_str = lnxall_conf.download(temp.parser_url)
                                -- log.info("node.template","download template script file:" .. lua_str)
                                if not ret or ret == false then
                                    log.warn("node.template","download link:" .. temp.parser_url .. ' failed')
                                else
                                    if not string.match(lua_str, "local function protocol_") then
                                        --如果是编解码函数没有local要添加module,替换原来全局函数名
                                        lua_str = string.gsub(lua_str, "function protocol_", "local function protocol_",2)
                                        --加上后缀,不要去对齐
                                        local suffix = "mod={} \nfunction mod.protocol_decode(...)  return protocol_decode(...) end \nfunction mod.protocol_encode(...)  return protocol_encode(...) end \nreturn mod\n"
                                        lua_str = lua_str .. suffix
                                    end

                                    local lua_path = string.format("%s/%s/%s",lnxall_conf.PREFIX_PATH or "","lua",file)
                                    log.info("node.template",'nodes templates script file: ',lua_path,#lua_str)
                                    io.writeFile(lua_path, lua_str)
                                    lua_str = nil suffix = nil
                                    collectgarbage("collect")
                                end
                            else
                                log.warn("node.template","template url split failed,url: ",temp.parser_url)
                            end
                        else
                            log.warn("node.template","parser_url be must required,template:" .. "")
                        end
                    end

                    -- 保存经过删除的配置
                    io.writeFile(lnxall_conf.LNXALL_nodes_temp, cjson.encode(obj))
                    log.info("node.template",'nodes templates file' .. cjson.encode(obj))
                    json_in = nil obj = nil
                    collectgarbage("collect")
                    -- 设定一定的延迟生效,如果有配置推送过来从新延迟
                    if sys.timerIsActive(reload) then sys.timerStop(reload) end
                    sys.timerStart(reload, 5000)
                else
                    log.warn("node.template","decode json string failed ,json: ",json_in)
                end
            else
                log.error("node.template","download nodes template failed ,json body: ",json_in)
            end
        end
    end
end)

function reload_uart(i, uconf)
    local id = (is8910 and i == 2) and 3 or i
    if id == 3 then return end
    log.info("reload.uart",i,json.encode(uconf))
    uart.close(id)
    uart.setup(id, uconf[i][2], uconf[i][3], uconf[i][4], uconf[i][5], nil, 1)
    uart.on(i, "sent", writeDone)
    uart.on(i, "receive", function(uid, length)
        table.insert(recvBuff[uid], uart.read(uid, length or 8192))
        sys.timerStart(sys.publish, tonumber(dtu.uartReadTime) or 500, "UART_RECV_WAIT_" .. uid, uid)
    end)
    -- 485方向控制
    if not dtu.uconf[i][6] or dtu.uconf[i][6] == "" then -- 这么定义是为了和之前的代码兼容
        default["dir" .. i] = i == 1 and (is1802S and 61 or (is4gLod and 23 or 2)) or (is1802S and 32 or (is4gLod and 59 or 6))
    else
        if pios[dtu.uconf[i][6]] then
            default["dir" .. i] = tonumber(dtu.uconf[i][6]:sub(4, -1))
            pios[dtu.uconf[i][6]] = nil
        else
            default["dir" .. i] = nil
        end
    end
    if default["dir" .. i] then
        pins.close(default["dir" .. i])
        pins.setup(default["dir" .. i], 0)
        uart.set_rs485_oe(i, default["dir" .. i])
    end
end

reloadFactory()
JJ_Msg_subscribe()

sys.taskInit(function()
    while true do
        if sys.waitUntil("FACTORY_CHECK_START", 30* 1000) then
            if not misc.getGatewayID() then log.error("Factory", "Need do factory process") end
            log.info("factory", "check running....")
            local connected = nil
            if socket.isReady()  then
                for i = 1,2 do
                    local code, head, body = httpv2.request("GET", "baidu.com", 1000)
                    if code and tonumber(code) == 200 and body and #body > 0 then connected = true break end
                end
            end
            local obj={
                sn=misc.getGatewayID() or "NONE SN",
                imei=misc.getImei(),
                product=misc.getProductName(),
                timestamp=os.time(),
                data={
                    wwan={
                        {interfaces="4g",error_code=connected and 0 or 1,error_msg=connected and "" or "unknow"}
                    },
                    uart={
                        {interfaces="uart1",error_code=0,error_msg=""}
                    }
                }
            }
            sys.publish("NET_RECV_WAIT_" .. 1,1,"test_result:" .. json.encode(obj) .. "\nluat OK")
        end
    end
end)


---------------------------------------------------------- 用户自定义任务初始化 ---------------------------------------------------------
if dtu.task and #dtu.task ~= 0 then
    for i = 1, #dtu.task do
        if dtu.task[i] and dtu.task[i]:match("function(.+)end") then
            sys.taskInit(loadstring(dtu.task[i]:match("function(.+)end")))
        end
    end
end
