--- 模块功能：数据链路激活(创建、连接、状态维护)
-- @module link
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.20
--4G网络下不手动激活pdp，注册上网后发cgdcont?等默认承载激活后上报IP_READY_IND，
--2G网络下，先cgact?查询有任一一路pdp激活，则直接上报IP_READY_IND，否则cgact激活cid_manual

require"net"

module(..., package.seeall)

local ready = true
local gprsAttached
local cid_manual=5

function isReady() return ready end

-- apn，用户名，密码
local apnname, username, password
local dnsIP
local authProt,authApn,authUser,authPassword

function setAPN(apn, user, pwd)
    apnname, username, password = apn, user, pwd
end

function setDnsIP(ip1, ip2)
    dnsIP = "\"" .. (ip1 or "") .. "\",\"" .. (ip2 or "") .. "\""
end

--- 设置专网卡APN(注意：在main.lua中，尽可能靠前的位置调用此接口)
-- 第一次设置成功之后，软件会自动重启，因为重启后才能生效
-- @number[opt=0] prot，加密方式， 0:不加密  1:PAP  2:CHAP
-- @string[opt=""] apn，apn名称
-- @string[opt=""] user，apn用户名
-- @string[opt=""] pwd，apn密码
-- @return nil
-- @usage
-- c = link.setAuthApn(2,"MYAPN","MYNAME","MYPASSWORD")
function setAuthApn(prot,apn,user,pwd)
    authProt,authApn,authUser,authPassword = prot or 0,apn or "",user or "",pwd or ""
    log.debug("link",string.format("设置APN prot %d (0:不加密  1:PAP  2:CHAP),apn %s, user %s, pwd %s",prot,apn,user,pwd))
end

function shut()
	log.debug("link",string.format("shut"))
end

