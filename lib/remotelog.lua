--- 模块功能：数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.25

require "log"
require "link"
local ls  = require "lsocket"
module(..., package.seeall)

local sockets = {}
-- 单次发送数据最大值
local SENDSIZE = 11200

-- 是否有socket正处在链接
local socketsConnected = 0

-- 创建socket函数
local mt = {}
mt.__index = mt
local function socket(protocol, cert)
    local ssl = protocol:match("SSL")
    local co = coroutine.running()
    if not co then
        print("socket.socket: socket must be called in coroutine")
        return nil
    end
    -- 实例的属性参数表
    local o = {
        id = nil,
        protocol = protocol,
        ssl = ssl,
        cert = cert,
        co = co,
        input = {},
        output = {},
        wait = "",
        connected = false,
        iSubscribe = false,
        subMessage = nil,
        isBlock = false,
        msg = nil,
    }
    return setmetatable(o, mt)
end


-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage
-- c = socket.tcp()
-- c = socket.tcp(true)
-- c = socket.tcp(true, {caCert="ca.crt"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key"})
-- c = socket.tcp(true, {caCert="ca.crt", clientCert="client.crt", clientKey="client.key", clientPassword="123456"})
function tcp(ssl, cert)
    return socket("TCP" .. (ssl == true and "SSL" or ""), (ssl == true) and cert or nil)
end

--- 创建基于UDP的socket对象
-- @return client，创建成功返回socket客户端对象；创建失败返回nil
-- @usage c = socket.udp()
function udp()
    return socket("UDP")
end


--- 连接服务器
-- @string address 服务器地址，支持ip和域名
-- @param port string或者number类型，服务器端口
-- @number[opt=120] timeout 可选参数，连接超时时间，单位秒
-- @return bool result true - 成功，false - 失败
-- @return string ,id '0' -- '8' ,返回通道ID编号
-- @usage  c = socket.tcp(); c:connect();
function mt:connect(address, port, timeout)
    assert(self.co == coroutine.running(), "socket:connect: coroutine mismatch")

    if not link.isReady() then
        print("socket.connect: ip not ready")
        return false
    end

    self.address = address
    self.port = port
    if self.protocol == 'TCP' or self.protocol == 'UDP' then
        client, err = ls.connect(self.protocol,address, port)
        if not client then
            print("socket","connect error: "..err,self.protocol,address, port)
        end

        -- wait for connect() to succeed or fail
        ls.select(nil, {client},10)
        ok, err = client:status()
        if not ok then
        end
        self.id = client
    end

    if not self.id then
        return false
    end
    sockets[self.id] = self
    self.wait = "SOCKET_CONNECT"

    if not self.connected then
        self.connected = true
        socketsConnected = socketsConnected+1
        sys.publish("SOCKET_ACTIVE", socketsConnected>0)
    end

    return true, self.id
end

--- 发送数据
-- @string data 数据
-- @number[opt=120] timeout 可选参数，发送超时时间，单位秒
-- @return result true - 成功，false - 失败
-- @usage  c = socket.tcp(); c:connect(); c:send("12345678");
function mt:send(data, timeout)
    assert(self.co == coroutine.running(), "socket:send: coroutine mismatch")
    if self.error then
        print('socket.client:send', 'error', self.error)
        return false
    end
    -- print("socket.send", "total " .. string.len(data or "") .. " bytes", "first 30 bytes", (data or ""):sub(1, 30))
    for i = 1, string.len(data or ""), SENDSIZE do
        -- 按最大MTU单元对data分包
        self.wait = "SOCKET_SEND"
        local nbytes ,msg = self.id:send(data:sub(i, i + SENDSIZE - 1))
        if not nbytes or nbytes == false  then
            print("socket:send", "send fail", nbytes,msg)
            sys.publish("LIB_SOCKET_SEND_FAIL_IND", self.ssl, self.protocol, self.address, self.port)
            return false
        end
    end
    return true
end


--- 销毁一个socket
-- @return nil
-- @usage  c = socket.tcp(); c:connect(); c:send("123"); c:close()
function mt:close()
    assert(self.co == coroutine.running(), "socket:close: coroutine mismatch")
    if self.iSubscribe then
        sys.unsubscribe(self.iSubscribe, self.subMessage)
        self.iSubscribe = false
    end
    --此处不要再判断状态，否则在连接超时失败时，conneted状态仍然是未连接，会导致无法close
    --if self.connected then
    -- print("socket:sock_close", self.id)
    local result, reason

    if self.id then
        self.id:close()
        self.wait = "SOCKET_CLOSE"
    end
    if self.connected then
        self.connected = false
        if socketsConnected>0 then
            socketsConnected = socketsConnected-1
        end
        sys.publish("SOCKET_ACTIVE", socketsConnected>0)
    end
    --end
    if self.id ~= nil then
        sockets[self.id] = nil
    end
end




function clientTask()
    while true do
        local remote_addr = nil
                -- 判断一下兼容lib库,如果没有新库不会报错
        if log.remote_cfg and type(log.remote_cfg) == "function" then
            log.remote_cfg(lnxall_conf.remote_log_param())-- reload log config
        end

        if log.get_remote_addr and type(log.get_remote_addr) == "function" then
            remote_addr = log.get_remote_addr()
        end
        local protocol = remote_addr:match("(%a+)://")
        sys.wait(1000)
        while true do
            if not remote_addr or remote_addr == "" then break end
            if protocol~="http" and protocol~="udp" and protocol~="tcp" then
                print("remote.log","remote log request invalid protocol",protocol)
                break
            end
            local msg = log.get_remote_log()
            if protocol=="http" then
                http.request("POST",remote_addr,nil,nil,msg,20000,httpPostCbFnc)
                _,result = sys.waitUntil("ERRDUMP_HTTP_POST")
            else
                local host,port = remote_addr:match("://(.+):(%d+)$")
                if not host then
                    print("remote.log","request invalid host port")
                else
                    local sck = protocol=="udp" and udp() or tcp()
                    if sck:connect(host,port) then
                        result = sck:send(msg)
                        sys.wait(300)
                        sck:close()
                    end
                end
            end
            sys.wait(100)
        end
    end
end

--- 启动远程日志功能
-- @function[opt=nil] cbFnc，每次执行远程升级功能后的回调函数，回调函数的调用形式为：
-- @return nil
-- @usage
-- remotelog.request()
function request()
    local msg
    if log.get_remote_addr == nil or log.get_remote_log == nil then
        log.error("remote log","hook not found in log.lua!")
        return
    end
    repeat
        msg = log.get_remote_log()
    until msg == nil --如果没有log 就退出

    if true then
        sys.taskInit(clientTask)
    end
end
