--- 模块功能：数据链路激活、SOCKET管理(创建、连接、数据收发、状态维护)
-- @module socket
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2017.9.25
require "link"
require "utils"
module(..., package.seeall)

local sockets = {}
-- 单次发送数据最大值
local SENDSIZE = 11200
-- 缓冲区最大下标
local INDEX_MAX = 256
-- 是否有socket正处在链接
local socketsConnected = false
--- SOCKET 是否有可用
-- @return 可用true,不可用false
socket.isReady = link.isReady

local function errorInd(error)
    local coSuspended = {}
    
    for _, c in pairs(sockets) do -- IP状态出错时，通知所有已连接的socket
        c.error = error
        --不能打开如下3行代码，IP出错时，会通知每个socket，socket会主动close
        --如果设置了connected=false，则主动close时，直接退出，不会执行close动作，导致core中的socket资源没释放
        --会引发core中socket耗尽以及socket id重复的问题
        --c.connected = false
        --socketsConnected = c.connected or socketsConnected
        --if error == 'CLOSED' then sys.publish("SOCKET_ACTIVE", socketsConnected) end
        if c.co and coroutine.status(c.co) == "suspended" then
            --coroutine.resume(c.co, false)
            table.insert(coSuspended, c.co)
        end
    end
    
    for k, v in pairs(coSuspended) do
        if v and coroutine.status(v) == "suspended" then
            coroutine.resume(v, false, error)
        end
    end
end

sys.subscribe("IP_ERROR_IND", function()errorInd('IP_ERROR_IND') end)
--sys.subscribe('IP_SHUT_IND', function()errorInd('CLOSED') end)
-- 创建socket函数
local mt = {}
mt.__index = mt
local function socket(protocol, cert)
    local ssl = protocol:match("SSL")
    local co = coroutine.running()
    if not co then
        log.warn("socket.socket: socket must be called in coroutine")
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

--- 创建基于TCP的socket对象
-- @bool[opt=nil] ssl，是否为ssl连接，true表示是，其余表示否
-- @table[opt=nil] cert，ssl连接需要的证书配置，只有ssl参数为true时，才参数才有意义，cert格式如下：
-- {
--     caCert = "ca.crt", --CA证书文件(Base64编码 X.509格式)，如果存在此参数，则表示客户端会对服务器的证书进行校验；不存在则不校验
--     clientCert = "client.crt", --客户端证书文件(Base64编码 X.509格式)，服务器对客户端的证书进行校验时会用到此参数
--     clientKey = "client.key", --客户端私钥文件(Base64编码 X.509格式)
--     clientPassword = "123456", --客户端证书文件密码[可选]
-- }
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
        log.info("socket.connect: ip not ready")
        return false
    end
    
    self.address = address
    self.port = port
    local socket_connect_fnc = (type(socketcore.sock_conn_ext)=="function") and socketcore.sock_conn_ext or socketcore.sock_conn
    if self.protocol == 'TCP' then
        self.id = socket_connect_fnc(0, address, port)
    elseif self.protocol == 'TCPSSL' then
        local cert = {hostName = address}
        if self.cert then
            if self.cert.caCert then
                if self.cert.caCert:sub(1, 1) ~= "/" then self.cert.caCert = "/lua/" .. self.cert.caCert end
                cert.caCert = io.readFile(self.cert.caCert)
            end
            if self.cert.clientCert then
                if self.cert.clientCert:sub(1, 1) ~= "/" then self.cert.clientCert = "/lua/" .. self.cert.clientCert end
                cert.clientCert = io.readFile(self.cert.clientCert)
            end
            if self.cert.clientKey then
                if self.cert.clientKey:sub(1, 1) ~= "/" then self.cert.clientKey = "/lua/" .. self.cert.clientKey end
                cert.clientKey = io.readFile(self.cert.clientKey)
            end
        end
        self.id = socket_connect_fnc(2, address, port, cert)
    else
        self.id = socket_connect_fnc(1, address, port)
    end
    if type(socketcore.sock_conn_ext)=="function" then
        if not self.id or self.id<0 then
            if self.id==-2 then
                require "http"
                --请求腾讯云免费HttpDns解析
                http.request("GET", "119.29.29.29/d?dn=" .. address, nil, nil, nil, 40000,
                    function(result, statusCode, head, body)
                        log.info("socket.httpDnsCb", result, statusCode, head, body)
                        sys.publish("SOCKET_HTTPDNS_RESULT_"..address.."_"..port, result, statusCode, head, body)
                    end)
                local _, result, statusCode, head, body = sys.waitUntil("SOCKET_HTTPDNS_RESULT_"..address.."_"..port)
                
                --DNS解析成功
                if result and statusCode == "200" and body and body:match("^[%d%.]+") then
                    return self:connect(body:match("^([%d%.]+)"),port,timeout)                
                end
            end
            self.id = nil
        end
    end
    if not self.id then
        log.info("socket:connect: core sock conn error", self.protocol, address, port, self.cert)
        return false
    end
    log.info("socket:connect-coreid,prot,addr,port,cert,timeout", self.id, self.protocol, address, port, self.cert, timeout or 120)
    sockets[self.id] = self
    self.wait = "SOCKET_CONNECT"
    self.timerId = sys.timerStart(coroutine.resume, (timeout or 120) * 1000, self.co, false, "TIMEOUT")
    local result, reason = coroutine.yield()
    if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
    if not result then
        log.info("socket:connect: connect fail", reason)
        sys.publish("LIB_SOCKET_CONNECT_FAIL_IND", self.ssl, self.protocol, address, port)
        return false
    end
    log.info("socket:connect: connect ok")
    self.connected = true
    socketsConnected = self.connected or socketsConnected
    sys.publish("SOCKET_ACTIVE", socketsConnected)
    return true, self.id
end

--- 异步收发选择器
-- @number keepAlive,服务器和客户端最大通信间隔时间,也叫心跳包最大时间,单位秒
-- @string pingreq,心跳包的字符串
-- @return boole,false 失败，true 表示成功
function mt:asyncSelect(keepAlive, pingreq)
    assert(self.co == coroutine.running(), "socket:asyncSelect: coroutine mismatch")
    if self.error then
        log.warn('socket.client:asyncSelect', 'error', self.error)
        return false
    end
    
    self.wait = "SOCKET_SEND"
    --log.info("socket.asyncSelect #self.output",#self.output)
    while #self.output ~= 0 do
        local data = table.concat(self.output)
        self.output = {}
        for i = 1, string.len(data), SENDSIZE do
            -- 按最大MTU单元对data分包
            socketcore.sock_send(self.id, data:sub(i, i + SENDSIZE - 1))
            if self.timeout then
                self.timerId = sys.timerStart(coroutine.resume, self.timeout * 1000, self.co, false, "TIMEOUT")
            end
            --log.info("socket.asyncSelect self.timeout",self.timeout)
            local result, reason = coroutine.yield()
            if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
            sys.publish("SOCKET_ASYNC_SEND", result)
            if not result then
                sys.publish("LIB_SOCKET_SEND_FAIL_IND", self.ssl, self.protocol, self.address, self.port)
                --log.warn('socket.asyncSelect', 'send error')
                return false
            end
        end
    end
    self.wait = "SOCKET_WAIT"
    sys.publish("SOCKET_SEND", self.id)
    if keepAlive and keepAlive ~= 0 then
        if type(pingreq) == "function" then
            sys.timerStart(pingreq, keepAlive * 1000)
        else
            sys.timerStart(self.asyncSend, keepAlive * 1000, self, pingreq or "\0")
        end
    end
    return coroutine.yield()
end

function mt:getAsyncSend()
    if self.error then return 0 end
    return #(self.output)
end
--- 异步发送数据
-- @string data 数据
-- @number[opt=nil] timeout 可选参数，发送超时时间，单位秒；为nil时表示不支持timeout
-- @return result true - 成功，false - 失败
-- @usage  c = socket.tcp(); c:connect(); c:asyncSend("12345678");
function mt:asyncSend(data, timeout)
    if self.error then
        log.warn('socket.client:asyncSend', 'error', self.error)
        return false
    end
    self.timeout = timeout
    table.insert(self.output, data or "")
    --log.info("socket.asyncSend",self.wait)
    if self.wait == "SOCKET_WAIT" then coroutine.resume(self.co, true) end
    return true
end
--- 异步接收数据
-- @return nil, 表示没有收到数据
-- @return data 如果是UDP协议，返回新的数据包,如果是TCP,返回所有收到的数据,没有数据返回长度为0的空串
-- @usage c = socket.tcp(); c:connect()
-- @usage data = c:asyncRecv()
function mt:asyncRecv()
    if #self.input == 0 then return "" end
    if self.protocol == "UDP" then
        return table.remove(self.input)
    else
        local s = table.concat(self.input)
        self.input = {}
        return s
    end
end

--- 发送数据
-- @string data 数据
-- @number[opt=120] timeout 可选参数，发送超时时间，单位秒
-- @return result true - 成功，false - 失败
-- @usage  c = socket.tcp(); c:connect(); c:send("12345678");
function mt:send(data, timeout)
    assert(self.co == coroutine.running(), "socket:send: coroutine mismatch")
    if self.error then
        log.warn('socket.client:send', 'error', self.error)
        return false
    end
    log.debug("socket.send", "total " .. string.len(data or "") .. " bytes", "first 30 bytes", (data or ""):sub(1, 30))
    for i = 1, string.len(data or ""), SENDSIZE do
        -- 按最大MTU单元对data分包
        self.wait = "SOCKET_SEND"
        socketcore.sock_send(self.id, data:sub(i, i + SENDSIZE - 1))
        self.timerId = sys.timerStart(coroutine.resume, (timeout or 120) * 1000, self.co, false, "TIMEOUT")
        local result, reason = coroutine.yield()
        if self.timerId and reason ~= "TIMEOUT" then sys.timerStop(self.timerId) end
        if not result then
            log.info("socket:send", "send fail", reason)
            sys.publish("LIB_SOCKET_SEND_FAIL_IND", self.ssl, self.protocol, self.address, self.port)
            return false
        end
    end
    return true
end

--- 接收数据
-- @number[opt=0] timeout 可选参数，接收超时时间，单位毫秒
-- @string[opt=nil] msg 可选参数，控制socket所在的线程退出recv阻塞状态
-- @bool[opt=nil] msgNoResume 可选参数，控制socket所在的线程退出recv阻塞状态，false或者nil表示“在recv阻塞状态，收到msg消息，可以退出阻塞状态”，true表示不退出
-- @return result 数据接收结果，true表示成功，false表示失败
-- @return data 如果成功的话，返回接收到的数据；超时时返回错误为"timeout"；msg控制退出时返回msg的字符串
-- @return param 如果是msg返回的false，则data的值是msg，param的值是msg的参数
-- @usage c = socket.tcp(); c:connect()
-- @usage result, data = c:recv()
-- @usage false,msg,param = c:recv(60000,"publish_msg")
function mt:recv(timeout, msg, msgNoResume)
    assert(self.co == coroutine.running(), "socket:recv: coroutine mismatch")
    if self.error then
        log.warn('socket.client:recv', 'error', self.error)
        return false
    end
    self.msgNoResume = msgNoResume
    if msg and not self.iSubscribe then
        self.iSubscribe = msg
        self.subMessage = function(data)
            if data then table.insert(self.output, data) end
            if self.wait == "+RECEIVE" and not self.msgNoResume then coroutine.resume(self.co, 0xAA) end
        end
        sys.subscribe(msg, self.subMessage)
    end
    if msg and #self.output > 0 then sys.publish(msg, false) end
    if #self.input == 0 then
        self.wait = "+RECEIVE"
        if timeout and timeout > 0 then
            local r, s = sys.wait(timeout)
            if r == nil then
                return false, "timeout"
            elseif r == 0xAA then
                local dat = table.concat(self.output)
                self.output = {}
                return false, msg, dat
            else
                return r, s
            end
        else
            local r, s = coroutine.yield()
            if r == 0xAA then
                local dat = table.concat(self.output)
                self.output = {}
                return false, msg, dat
            else
                return r, s
            end
        end
    end
    
    if self.protocol == "UDP" then
        return true, table.remove(self.input)
    else
        log.warn("-------------------使用缓冲区---------------")
        local s = table.concat(self.input)
        self.input = {}
        if self.isBlock then table.insert(self.input, socketcore.sock_recv(self.msg.socket_index, self.msg.recv_len)) end
        return true, s
    end
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
    log.info("socket:sock_close", self.id)
    local result, reason
    self.connected = false
    if self.id then
        socketcore.sock_close(self.id)
        self.wait = "SOCKET_CLOSE"
        while true do
            result, reason = coroutine.yield()
            if reason == "RESPONSE" then break end
        end
    end
    socketsConnected = self.connected or socketsConnected
    sys.publish("SOCKET_ACTIVE", socketsConnected)
    --end
    if self.id ~= nil then
        sockets[self.id] = nil
    end
end

local function on_response(msg)
    local t = {
        [rtos.MSG_SOCK_CLOSE_CNF] = 'SOCKET_CLOSE',
        [rtos.MSG_SOCK_SEND_CNF] = 'SOCKET_SEND',
        [rtos.MSG_SOCK_CONN_CNF] = 'SOCKET_CONNECT',
    }
    if not sockets[msg.socket_index] then
        log.warn('response on nil socket', msg.socket_index, t[msg.id], msg.result)
        return
    end
    if sockets[msg.socket_index].wait ~= t[msg.id] then
        log.warn('response on invalid wait', sockets[msg.socket_index].id, sockets[msg.socket_index].wait, t[msg.id], msg.socket_index)
        return
    end
    log.info("socket:on_response:", msg.socket_index, t[msg.id], msg.result)
    if type(socketcore.sock_destroy) == "function" then
        if (msg.id == rtos.MSG_SOCK_CONN_CNF and msg.result ~= 0) or msg.id == rtos.MSG_SOCK_CLOSE_CNF then
            socketcore.sock_destroy(msg.socket_index)
        end
    end
    coroutine.resume(sockets[msg.socket_index].co, msg.result == 0, "RESPONSE")
end

rtos.on(rtos.MSG_SOCK_CLOSE_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CONN_CNF, on_response)
rtos.on(rtos.MSG_SOCK_SEND_CNF, on_response)
rtos.on(rtos.MSG_SOCK_CLOSE_IND, function(msg)
    log.info("socket.rtos.MSG_SOCK_CLOSE_IND")
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    sockets[msg.socket_index].connected = false
    sockets[msg.socket_index].error = 'CLOSED'
    socketsConnected = sockets[msg.socket_index].connected or socketsConnected
    sys.publish("SOCKET_ACTIVE", socketsConnected)
    --[[
    if type(socketcore.sock_destroy) == "function" then
        socketcore.sock_destroy(msg.socket_index)
    end]]
    coroutine.resume(sockets[msg.socket_index].co, false, "CLOSED")
end)
rtos.on(rtos.MSG_SOCK_RECV_IND, function(msg)
    if not sockets[msg.socket_index] then
        log.warn('close ind on nil socket', msg.socket_index, msg.id)
        return
    end
    
    -- local s = socketcore.sock_recv(msg.socket_index, msg.recv_len)
    -- log.debug("socket.recv", "total " .. msg.recv_len .. " bytes", "first " .. 30 .. " bytes", s:sub(1, 30))
    if sockets[msg.socket_index].wait == "+RECEIVE" then
        coroutine.resume(sockets[msg.socket_index].co, true, socketcore.sock_recv(msg.socket_index, msg.recv_len))
    else -- 数据进缓冲区，缓冲区溢出采用覆盖模式
        if #sockets[msg.socket_index].input > INDEX_MAX then
            log.error("socket recv", "out of stack", "block")
            -- sockets[msg.socket_index].input = {}
            sockets[msg.socket_index].isBlock = true
            sockets[msg.socket_index].msg = msg
        else
            sockets[msg.socket_index].isBlock = false
            table.insert(sockets[msg.socket_index].input, socketcore.sock_recv(msg.socket_index, msg.recv_len))
        end
        sys.publish("SOCKET_RECV", msg.socket_index)
    end
end)

--- 设置TCP层自动重传的参数
-- @number[opt=4] retryCnt，重传次数；取值范围0到12
-- @number[opt=16] retryMaxTimeout，限制每次重传允许的最大超时时间(单位秒)，取值范围1到16
-- @return nil
-- @usage
-- setTcpResendPara(3,8)
-- setTcpResendPara(4,16)
function setTcpResendPara(retryCnt, retryMaxTimeout)
    ril.request("AT+TCPUSERPARAM=6," .. (retryCnt or 4) .. ",7200," .. (retryMaxTimeout or 16))
end

-- setTcpResendPara(1, 16)
--- 打印所有socket的状态
-- @return 无
-- @usage socket.printStatus()
function printStatus()
    for _, client in pairs(sockets) do
        for k, v in pairs(client) do
            log.info('socket.printStatus', 'client', client.id, k, v)
        end
    end
end
