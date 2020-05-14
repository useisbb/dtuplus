--- 模块功能：GPS模块管理
-- @module gpsv2
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.08.28
require "utils"
module(..., package.seeall)

-- GPS任务线程ID
local GPS_CO
--串口配置
local uartID, uartBaudrate = 2, 115200
-- 下载超时设置单位分钟
local timeout = 5 * 60000
-- 设置星历和基站定位的循环定时器时间
local EPH_UPDATE_INTERVAL = 4 * 3600
-- 星历写入标记
local ephFlag = false
--GPS开启标志，true表示开启状态，false或者nil表示关闭状态
local openFlag
--GPS定位标志，true表示，其余表示未定位
local fixFlag = false
-- 经纬度类型和数据
local latitudeType, latitude, longitudeType, longitude = "N", "", "E", ""
-- 海拔，速度，时速,方向角
local altitude, speed, kmHour, azimuth = "0", "0", "0", "0"
-- 参与定位的卫星个数,GPS和北斗可见卫星个数
local usedSateCnt, viewedGpsSateCnt, viewedBdSateCnt = "0", "0", "0"
-- 可用卫星号，UTC时间
local SateSn, UtcTime
-- 大地高，度分经度，度分纬度
local Sep, Ggalng, Ggalat
-- GPS和北斗GSV解析保存的表
local gpgsvTab, bdgsvTab = {}, {}
-- GPGSV解析后的CNO信息
local gsvCnoTab = {}
-- 基站定位坐标
local lbs_lat, lbs_lng
-- 日志开关
local isLog = true
--解析GPS模块返回的信息

-- 阻塞模式读取串口数据，需要线程支持
-- @return 返回以\r\n结尾的一行数据
-- @usage local str = gpsv2.read()
local function read()
    return "xxxxxxxxxxxxxxxx"
end
-- GPS串口写命令操作
-- @string cmd，GPS指令(cmd格式："$PGKC149,1,115200*"或者"$PGKC149,1,115200*XX\r\n")
-- @bool isFull，cmd是否为完整的指令格式，包括校验和以及\r\n；true表示完整，false或者nil为不完整
-- @return nil
-- @usage gpsv2.writeCmd(cmd)
local function writeCmd(cmd, isFull)

end

-- GPS串口写数据操作
-- @string str,HEX形式的字符串
-- @return 无
-- @usage gpsv2.writeData(str)
local function writeData(str)
    uart.write(uartID, (str:fromHex()))
-- log.info("gpsv2.writeData", str)
end
-- AIR530的校验和算法
local function hexCheckSum(str)
    local sum = 0
    for i = 5, str:len(), 2 do
        sum = bit.bxor(sum, tonumber(str:sub(i, i + 1), 16))
    end
    return string.upper(string.format("%02X", sum))
end
local function setFastFix(lat, lng)
    if not lat or not lng or not openFlag or os.time() < 1514779200 then return end
    local tm = os.date("*t")
    tm = common.timeZoneConvert(tm.year, tm.month, tm.day, tm.hour, tm.min, tm.sec, 8, 0)
    t = tm.year .. "," .. tm.month .. "," .. tm.day .. "," .. tm.hour .. "," .. tm.min .. "," .. tm.sec .. "*"
    -- log.info("写入秒定位需要的坐标和时间:", lat, lng, t)
    writeCmd("$PGKC634," .. t)
    writeCmd("$PGKC634," .. t)
    writeCmd("$PGKC635," .. lat .. "," .. lng .. ",0," .. t)
end

-- 定时自动下载坐标和星历的任务
local function getlbs(result, lat, lng, addr)
    if result and lat and lng then
        lbs_lat, lbs_lng = lat, lng
        setFastFix(lat, lng)
    end
end

local function saveEph(timeout)
    sys.taskInit(function()
        while true do
            local code, head, data = httpv2.request("GET", "download.openluat.com/9501-xingli/brdcGPD.dat_rda", timeout)
            if tonumber(code) and tonumber(code) == 200 then
                log.info("保存下载的星历:", io.writeFile(GPD_FILE, data))
                ephFlag = false
                break
            end
        end
    end)
end

--- 打开GPS模块
-- @number id，UART ID，支持1和2，1表示UART1，2表示UART2
-- @number baudrate，波特率，支持1200,2400,4800,9600,10400,14400,19200,28800,38400,57600,76800,115200,230400,460800,576000,921600,1152000,4000000
-- @nunber mode,功耗模式0正常功耗，2周期唤醒
-- @number sleepTm,间隔唤醒的时间 秒
-- @param fnc,外部模块使用的电源管理函数
-- @return 无
-- @usage gpsv2.open()
-- @usage gpsv2.open(2, 115200, 0, 1)  -- 打开GPS，串口2，波特率115200，正常功耗模式，1秒1个点
-- @usage gpsv2.open(2, 115200, 2, 5) -- 打开GPS，串口2，波特率115200，周期低功耗模式1秒输出，5秒睡眠
function open(id, baudrate, mode, sleepTm, fnc)

end
--- 关闭GPS模块
-- @param fnc,外部模块使用的电源管理函数
-- @return 无
-- @usage gpsv2.close()
function close(id, fnc)

    log.info("----------------------------------- GPS CLOSE -----------------------------------")
end



--- 获取GPS模块是否处于开启状态
-- @return bool result，true表示开启状态，false或者nil表示关闭状态
-- @usage gpsv2.isOpen()
function isOpen()
    return openFlag
end

--- 获取GPS模块是否定位成功
-- @return bool result，true表示定位成功，false或者nil表示定位失败
-- @usage gpsv2.isFix()
function isFix()
    return fixFlag
end

--- 获取返回值为度的10&7方的整数值（度*10^7的值）
-- @return number,number,INT32整数型,经度,维度,符号(正东负西,正北负南)
-- @usage gpsv2.getIntLocation()
function getIntLocation()
    local lng, lat = "0.0", "0.0"
    lng = longitudeType == "W" and ("-" .. longitude) or longitude
    lat = latitudeType == "S" and ("-" .. latitude) or latitude
    if lng and lat and lng ~= "" and lat ~= "" then
        local integer, decimal = lng:match("(%d+).(%d+)")
        if tonumber(integer) and tonumber(decimal) then
            decimal = decimal:sub(1, 7)
            local tmp = (integer % 100) * 10 ^ 7 + decimal * 10 ^ (7 - #decimal)
            lng = ((integer - integer % 100) / 100) * 10 ^ 7 + (tmp - tmp % 60) / 60
        end
        integer, decimal = lat:match("(%d+).(%d+)")
        if tonumber(integer) and tonumber(decimal) then
            decimal = decimal:sub(1, 7)
            tmp = (integer % 100) * 10 ^ 7 + decimal * 10 ^ (7 - #decimal)
            lat = ((integer - integer % 100) / 100) * 10 ^ 7 + (tmp - tmp % 60) / 60
        end
        return lng, lat
    end
    return 0, 0
end
--- 获取基站定位的经纬度信息dd.dddd
function getDeglbs()
    return lbs_lng or "0.0", lbs_lat or "0.0"
end

--- 获取度格式的经纬度信息dd.dddddd
-- @return string,string,固件为非浮点时返回度格式的字符串经度,维度,符号(正东负西,正北负南)
-- @return float,float,固件为浮点的时候，返回浮点类型
-- @usage gpsv2.getLocation()
function getDegLocation()
    local lng, lat = getIntLocation()
    if float then return lng / 10 ^ 7, lat / 10 ^ 7 end
    return string.format("%d.%07d", lng / 10 ^ 7, lng % 10 ^ 7), string.format("%d.%07d", lat / 10 ^ 7, lat % 10 ^ 7)
end

--- 获取度分格式的经纬度信息ddmm.mmmm
-- @return string,string,返回度格式的字符串经度,维度,符号(正东负西,正北负南)
-- @usage gpsv2.getCentLocation()
function getCentLocation()
    if float then return tonumber(Ggalng or 0), tonumber(Ggalat or 0) end
    return Ggalng or 0, Ggalat or 0
end

--- 获取海拔
-- @return number altitude，海拔，单位米
-- @usage gpsv2.getAltitude()
function getAltitude()
    return tonumber(altitude and altitude:match("(%d+)")) or 0
end

--- 获取速度
-- @return number kmSpeed，第一个返回值为公里每小时的速度
-- @return number nmSpeed，第二个返回值为海里每小时的速度
-- @usage gpsv2.getSpeed()
function getSpeed()
    local integer = tonumber(speed and speed:match("(%d+)")) or 0
    return (integer * 1852 - (integer * 1852 % 1000)) / 1000, integer
end

--- 获取时速(KM/H)的整数型和浮点型(字符串)
function getKmHour()
    return tonumber(kmHour and kmHour:match("(%d+)")) or 0, (float and tonumber(kmHour) or kmHour) or "0"
end

--- 获取方向角
-- @return number Azimuth，方位角
-- @usage gpsv2.getAzimuth()
function getAzimuth()
    return tonumber(azimuth and azimuth:match("(%d+)")) or 0
end

--- 获取可见卫星的个数
-- @return number count，可见卫星的个数
-- @usage gpsv2.getViewedSateCnt()
function getViewedSateCnt()
    return (tonumber(viewedGpsSateCnt) or 0) + (tonumber(viewedBdSateCnt) or 0)
end

--- 获取定位使用的卫星个数
-- @return number count，定位使用的卫星个数
-- @usage gpsv2.getUsedSateCnt()
function getUsedSateCnt()
    return tonumber(usedSateCnt) or 0
end

--- 获取RMC语句中的UTC时间
-- 只有同时满足如下两个条件，返回值才有效
-- 1、开启了GPS，并且定位成功
-- 2、调用setParseItem接口，第一个参数设置为true
-- @return table utcTime，UTC时间，nil表示无效，例如{year=2018,month=4,day=24,hour=11,min=52,sec=10}
-- @usage gpsv2.getUtcTime()
function getUtcTime()
    return UtcTime
end

--- 获取定位使用的大地高
-- @return number sep，大地高
-- @usage gpsv2.getSep()
function getSep()
    return tonumber(Sep) or 0
end

--- 获取GSA语句中的可见卫星号
-- 只有同时满足如下两个条件，返回值才有效
-- 1、开启了GPS，并且定位成功
-- 2、调用setParseItem接口，第三个参数设置为true
-- @return string viewedSateId，可用卫星号，""表示无效
-- @usage gpsv2.getSateSn()
function getSateSn()
    return tonumber(SateSn) or 0
end
--- 获取BDGSV解析结果
-- @return table, GSV解析后的数组
-- @usage gpsv2.getBDGsv()
function getBDGsv()
    return bdgsvTab
end
--- 获取GPGSV解析结果
-- @return table, GSV解析后的数组
-- @usage gpsv2.getGPGsv()
function getGPGsv()
    return gpgsvTab
end
--- 获取GPSGSV解析后的CNO数据
function getCno()
    return gsvCnoTab
end

--- 是否显示日志
function openLog(v)
    isLog = v == nil and true or v
end
