---模块功能：网络管理、信号查询、GSM网络状态查询、网络指示灯控制、临近小区信息查询
-- @module net
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.02.17

require "sys"
require "pio"
require "log"
require "utils"
module(..., package.seeall)

--加载常用的全局函数至本地
local publish = sys.publish

--netmode define
NetMode_noNet=   0
NetMode_GSM=     1--2G
NetMode_EDGE=    2--2.5G
NetMode_TD=      3--3G
NetMode_LTE=     4--4G
NetMode_WCDMA=   5--3G
local netMode = NetMode_noNet

--GSM网络状态：
--INIT：开机初始化中的状态
--REGISTERED：注册上GSM网络
--UNREGISTER：未注册上GSM网络
local state = "INIT"
--SIM卡状态：true为异常，false或者nil为正常
local simerrsta
-- 飞行模式状态
flyMode = false

--lac：位置区ID
--ci：小区ID
--rssi：信号强度
local lac, ci, rssi = "", "", 0

--cellinfo：当前小区和临近小区信息表
--multicellcb：获取多小区的回调函数
local cellinfo, multicellcb = {}

--- 设置飞行模式
-- @bool mode，true:飞行模式开，false:飞行模式关
-- @return nil
-- @usage net.switchFly(mode)
function switchFly(mode)
	if flyMode == mode then return end
	flyMode = mode
	log.debug("net",string.format("setting fly mode %d(true:飞行模式开，false:飞行模式关)",flyMode))
end

--- 获取netmode
-- @return number netMode,注册的网络类型
-- 0：未注册
-- 1：2G GSM网络
-- 2：2.5G EDGE数据网络
-- 3：3G TD网络
-- 4：4G LTE网络
-- 5：3G WCDMA网络
-- @usage net.getNetMode()
function getNetMode()
	netMode = 4
	return netMode
end

--- 获取GSM网络注册状态
-- @return string state,GSM网络注册状态，
-- "INIT"表示正在初始化
-- "REGISTERED"表示已注册
-- "UNREGISTER"表示未注册
-- @usage net.getState()
function getState()
	state = "REGISTERED"
	return state
end

--- 获取当前小区的mcc
-- @return string mcc,当前小区的mcc，如果还没有注册GSM网络，则返回sim卡的mcc
-- @usage net.getMcc()
function getMcc()
	cellinfo[1].mcc = 0x01
	return cellinfo[1].mcc and string.format("%x",cellinfo[1].mcc) or sim.getMcc()
end

--- 获取当前小区的mnc
-- @return string mcn,当前小区的mnc，如果还没有注册GSM网络，则返回sim卡的mnc
-- @usage net.getMnc()
function getMnc()
	cellinfo[1].mnc = 0x01
	return cellinfo[1].mnc and string.format("%x",cellinfo[1].mnc) or sim.getMnc()
end

--- 获取当前位置区ID
-- @return string lac,当前位置区ID(16进制字符串，例如"18be")，如果还没有注册GSM网络，则返回""
-- @usage net.getLac()
function getLac()
	lac = "18be"
	return lac
end

--- 获取当前小区ID
-- @return string ci,当前小区ID(16进制字符串，例如"93e1")，如果还没有注册GSM网络，则返回""
-- @usage net.getCi()
function getCi()
	ci = "93e1"
	return ci
end

--- 获取信号强度
-- @return number rssi,当前信号强度(取值范围0-31)
-- @usage net.getRssi()
function getRssi()
	rssi = 31
	return rssi
end

--- 获取当前和临近位置区、小区以及信号强度的拼接字符串
-- @return string cellInfo,当前和临近位置区、小区以及信号强度的拼接字符串，例如："6311.49234.30;6311.49233.23;6322.49232.18;"
-- @usage net.getCellInfo()
function getCellInfo()
	return "6311.49234.30;6311.49233.23;6322.49232.18;"
end

--- 获取当前和临近位置区、小区、mcc、mnc、以及信号强度的拼接字符串
-- @return string cellInfo,当前和临近位置区、小区、mcc、mnc、以及信号强度的拼接字符串，例如："460.01.6311.49234.30;460.01.6311.49233.23;460.02.6322.49232.18;"
-- @usage net.getCellInfoExt()
function getCellInfoExt()
	return "460.01.6311.49234.30;460.01.6311.49233.23;460.02.6322.49232.18;"
end


--- 设置查询信号强度和基站信息的间隔
-- @number ... 查询周期,参数可变，参数为nil只查询1次，参数1是信号强度查询周期，参数2是基站查询周期
-- @return bool ，true：设置成功，false：设置失败
-- @usage net.startQueryAll()
-- @usage net.startQueryAll(60000) -- 1分钟查询1次信号强度，只立即查询1次基站信息
-- @usage net.startQueryAll(60000,600000) -- 1分钟查询1次信号强度，10分钟查询1次基站信息
function startQueryAll(...)
	log.debug("net",string.format("start request signle and baseband info"))
    if flyMode then
        log.info("sim.startQuerAll", "flyMode:", flyMode)
    end
    return true
end

--- 停止查询信号强度和基站信息
-- @return 无
-- @usage net.stopQueryAll()
function stopQueryAll()
	log.debug("net",string.format("stop request signle and baseband info"))
end

local sEngMode
--- 设置工程模式
-- @number[opt=1] mode，工程模式，目前仅支持0和1
-- mode为0时，不支持临近小区查询，休眠时功耗较低
-- mode为1时，支持临近小区查询，但是休眠时功耗较高
-- @return nil
-- @usage
-- net.setEngMode(0)
function setEngMode(mode)
	log.debug("net",string.format("set eng mode %d",mode))
end


