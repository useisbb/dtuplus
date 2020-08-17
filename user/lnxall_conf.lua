--- 模块功能：作为lnxall 的配置管理
require "pins"
require "utils"
require "socket"
require "http"
require "common"
require "create"
require "tracker"
module(..., package.seeall)


-- PREFIX
PREFIX_PATH= rtos.get_version() == "virtual luat" and "./luat_file" or ""
LUA_DIR = PREFIX_PATH .. "/lua/"
TMP_DIR= PREFIX_PATH .. '/download/'
LNXALL_DIR=PREFIX_PATH .. '/lnxall/'
LNXALL_rs485=PREFIX_PATH .. '/lnxall/rs485_port_cfg.json'
LNXALL_mqtt=PREFIX_PATH .. '/lnxall/mqtt_server.json'
LNXALL_nodes_cfg=PREFIX_PATH .. '/lnxall/nodes_cfg.json'
LNXALL_nodes_temp=PREFIX_PATH .. '/lnxall/templates_cfg.json'
LNXALL_remote_log_cfg=PREFIX_PATH .. '/lnxall/remote_log_cfg.json'
LNXALL_transparent_cfg=PREFIX_PATH .. '/lnxall/transparent_cfg.json'
LNXALL_factory_info=PREFIX_PATH .. '/lnxall/factory_info.json'

local parity_map={}
-- lnxall 0 -> luat 2
parity_map[0] = 2
parity_map[1] = 1
parity_map[2] = 0

nodes_cfg={}
nodes_temp={}
period_list={}

_G.nodes_cfg = nodes_cfg
_G.nodes_temp = nodes_temp

local stopbit_map={0,1}
local dir_io_map={'pio23'}

local cookid = 0

lx_mqtt={"LNXALL",300,180,"mqtt.lnxall.com",3883,"localuser","dywl@galaxy",1,"M/imei/#;","G/imei/LogIn",2,0,1}

-- 如果配置目录不存在，创建目录
if not io.exists(LUA_DIR) then
    rtos.make_dir(LUA_DIR)
end

if not io.exists(LNXALL_DIR) then
    rtos.make_dir(LNXALL_DIR)
end
if not io.exists(TMP_DIR) then
    rtos.make_dir(TMP_DIR)
end

-- -- 测试透传配置
-- local str = '{"common_socket_cfg":[{"protocol_type":"TCP","socket_addr":"10.3.1.217","socket_port":12345,"binding_port":"RS485_1","frame_header":"02","frame_tail":"03","login_packet":"FF 0D 09 01","heartbeat_packet":"FF 0D 09 02","heartbeat_interval":300}]}'
-- io.writeFile(LNXALL_transparent_cfg, str, 'w')

-- -- 测试串口配置
-- local str = '{"mi":63901221,"rs485_cfg":[{"disable":0,"parity":0,"port":"RS485_1","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_2","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_3","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_4","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1}],"timestamp":1587102806,"version":"uJloPlpCA3Bd"}'
-- io.writeFile(LNXALL_rs485, str, 'w')

-- -- 测试mqtt配置
-- local str = '{"host": "mqtt.lnxall.com","port": 3883,"user": "localuser","pass": "dywl@galaxy"}'
-- io.writeFile(LNXALL_mqtt, str, 'w')


-- -- 测试节点配置
-- local str = '{"nodes_cfg":[{"connect_port":"RS485_1","depth":0,"product_key":"23505558","sn":"44444444444","template_id":"23505558","term_addr":"02"}]}'
-- io.writeFile(LNXALL_nodes_cfg, str, 'w')


-- -- 测试模板配置
-- local str = '{"template_cfg":[{"communication_timeout":0,"logout_times":0,"offline_times":0,"parser_url":"http://qa.iot.lnxall.com/iot/download/gateway-cfg/script_demo.lua","protocol":"GW_PROTC_MODBUS","report_period":0,"service_cfg":[{"direction":0,"identifier":"weiyishangbao","instruction_code":0,"report_period":10,"server_period":10},{"direction":1,"identifier":"weiyishangbao","instruction_code":0,"report_period":0,"server_period":0}],"template_id":"23505558","use_parser_url":1}]}'
-- io.writeFile(LNXALL_nodes_temp, str, 'w')


-- -- 测试远程日志配置
-- local str = '{"log_ip":"qa.frps.lnxall.com","log_level":5,"log_port":5002,"log_proto":"tcp","mi":94240998,"timestamp":1590143903}'
-- io.writeFile(LNXALL_remote_log_cfg, str, 'w')


-- -- 测试脚本  -- LuatTools 会把没有require的文件,忽略下载导致require失败
-- script_demo = require "script_demo"

if io.exists(LNXALL_mqtt) then
    local dat, res, err = json.decode(io.readFile(LNXALL_mqtt) or '')
    if res and dat then
        lx_mqtt[4] = dat['host'] or ''
        lx_mqtt[5] = tonumber(dat['port']) or 1883
        lx_mqtt[6] = dat['user'] or ''
        lx_mqtt[7] = dat['pass'] or ''
    else
        log.info("lnxall_config.mqtt",'mqtt config file error, ',err)
    end
end

function msgid()
    if cookid > 1000000 then cookid = 0 end
    cookid = cookid + 1
    return cookid
end


local function cbFncFile(result,prompt,head,filePath)
    if result and head then
        for k,v in pairs(head) do
            log.info("lnxall_config.download","http.cbFncFile",k..": "..v)
        end
    end
    if result and filePath then
        --输出文件内容，如果文件太大，一次性读出文件内容可能会造成内存不足，分次读出可以避免此问题
        local size = io.fileSize(filePath)
        log.info("lnxall_config.download",string.format("download file name:%s ,size:%d Bytes ",filePath,size))
        if size<=1024*20 then
            local body = io.readFile(filePath)
            sys.publish(filePath,body) --用文件名做消息id
        else
            log.warn("lnxall_config.download","File too large,bytes:",lua_str)
        end
    end
    -- 如果是临时文件直接删除
    if string.find(filePath,TMP_DIR) then os.remove(filePath) end
end

-- 注意:saveFile 存放路径不能是/download/,否则文件不能被下载
function download(link , saveFile,timeout)
    if link then
        log.info("lnxall_config.download",'download : ' .. link,saveFile)
        -- 如果没有传进来需要保存的文件名,是临时文件

        local file = saveFile or string.format( "%s/%s",TMP_DIR,lnxall_conf.getUrlFileName(link) or "")
        http.request("GET",link,nil,nil,nil,10000,cbFncFile,file)
        local result, body = sys.waitUntil(file,timeout or 30000) --用文件名做消息id
        if result and body and #body > 20 then
            if saveFile then
                io.writeFile(saveFile, body)
                log.warn("lnxall_config.download",'save nodes config file:',saveFile,#body)
            end
            return true,body
        else
            log.error("lnxall_config.download",'download failed: ')
        end
    else
        log.error("lnxall_config.download",'download failed, link:',link)
    end
    return false
end

function downloadByJson(json_str, saveFile,timeout)
    obj = json.decode(json_str)
    if obj and obj.URL then
        return download(obj.URL,saveFile,timeout)
    else
        log.error("lnxall_config.download",'download by json.URL failed, json:',json_str)
    end
    return false
end

function sn2addr(sn)
    if sn then
        for k,v in ipairs(nodes_cfg)do
            if v and v['sn'] == sn then
                return v['term_addr']
            end
        end
    else
        log.error("lnxall_config.sn2addr",'sn2addr must with sn')
    end
    return nil
end

function addr2sn(term_addr)
    if term_addr then
        for k,v in ipairs(nodes_cfg)do
            if v and v['term_addr'] and tonumber(v['term_addr'],16) == tonumber(term_addr,16) then  -- 兼容不同脚本输出的大小写或者补0
                return v['sn']
            end
        end
    else
        log.error("lnxall_config.ddr2sn",'addr2sn must with term_addr')
    end
    return nil
end

function portBysn(sn)
    if sn then
        for k,v in ipairs(nodes_cfg)do
            if v and v['sn'] == sn then
                return v['connect_port']
            end
        end
    end
    return nil
end

local function require_modules(modules)
    for k,v in ipairs(modules)do
        if v then
            local res, msg = nil,nil
            -- 如果有分隔符 分隔符前面是包原始名,后是重命名
            local part = string.split(v,";")
            if #part == 1 then
                res, msg = pcall(loadstring(string.format( "%s = require \"%s\"\n",part[1],part[1])))
            else
                res, msg = pcall(loadstring(string.format( "%s = require \"%s\"\n",part[2],part[1])))
            end
            if res and res == true then
                log.info("lnxall_config.dy_require",'require template module:' .. v .. ' success')
            else
                log.warn("lnxall_config.dy_require",'require template module:' .. v .. ' failed,error' .. msg)
            end
        end
    end
end

local function bind_module_func(modules)
    for k,v in ipairs(modules)do
        -- 通过脚本名称找模板id->用模板id找设备模板->对设备模板赋值
        local bind = string.format('\
        local %s = require \"%s\"\
        local cjson = require \"cjson\"\
        if not _G.nodes_cfg or not _G.nodes_temp then \
        print(\"nodes config or template was invalid \",cjson.encode(_G.nodes_cfg),cjson.encode(_G.nodes_temp))\
        end\
        local decode,encode,template_id = nil,nil,nil\
        decode = %s.protocol_decode\
        encode = %s.protocol_encode\
        for _,temp in ipairs(_G.nodes_temp) do\
            if temp and temp.parser_url and string.find(temp.parser_url,\"%s\") then template_id = temp.template_id break end\
        end\
        print(\"template_id:\",template_id,\"function point:\",encode, decode)\
        for _,node in ipairs(_G.nodes_cfg) do\
            if node and node.template_id and template_id and template_id == node.template_id then\
                node.protocol_decode = decode\
                node.protocol_encode = encode\
            end\
        end\n'
        ,v,v,v,v,v)
        log.debug("lnxall_config.bind.module","called module name:",bind,loadstring(bind))
        local res, msg = pcall(loadstring(bind))
        if res and res == true then
            log.info("lnxall_config.bind.module",'bind protocol to device,module:' .. v .. ' success')
        else
            log.warn("lnxall_config.bind.module",'bind protocol to device,module:' .. v .. ' failed,error ' .. msg)
        end

    end

    for k,v in ipairs(nodes_cfg)do
        if v then
            log.info("lnxall_conf.bind.module",v['sn'],v['template_id'],v['protocol_encode'],v['protocol_decode'])
        end
    end
end

local function parser_period_service()
    for _,temp in ipairs(nodes_temp) do
        if temp.service_cfg  then --找模板
            for _,node in ipairs(nodes_cfg) do  --确认模板被应用的设备有哪些
                if temp.template_id == node.template_id and node.sn then
                    for _,service_cfg in ipairs(temp.service_cfg) do --找服务
                        if service_cfg.identifier and service_cfg.report_period and service_cfg.server_period and service_cfg.direction == 0 and service_cfg.server_period > 0  and service_cfg.report_period > 0 then
                            local period={
                                    identifier = service_cfg.identifier,
                                    sn = node.sn,
                                    mi = 0,
                                    intv_sample = service_cfg.report_period,  -- 直接使用上报周期做采样
                                    -- intv_sample = service_cfg.server_period
                                    last_sample = os.time()
                            }
                            table.insert(period_list,period)
                            -- table.insert(report_list,period)
                        end
                    end
                end
            end
        end
    end
end

function period_service_poll()
    for k,v in ipairs(period_list)do
        if v then
            if os.difftime(os.time(),v.last_sample) >= v.intv_sample then
                v.last_sample = os.time()
                log.info("lnxall_config.period_service",v.sn,v.identifier,v.intv_sample)
                local obj = {}
                obj.identifier =  v.identifier
                obj.sn = v.sn
                obj.timestamp = os.time()
                obj.mi=0
                local payload = json.encode(obj)
                return payload
            end
        end
    end
end

function get_uart_param()
    if io.exists(LNXALL_rs485) then
        rs_485 = {}
        local dat, res, err = json.decode(io.readFile(LNXALL_rs485) or '')
        -- local dat, res, err = json.decode(io.readFile(LNXALL_rs485))
        if res and dat and dat.rs485_cfg then
            for k,v in pairs(dat.rs485_cfg)do
                tmp={}
                tmp[1] = k
                tmp[2] = v['speed']
                tmp[3] = 8
                tmp[4] = parity_map[(v['parity'] and 0)]
                tmp[5] = stopbit_map[(v['stop'] and 1)]
                if dir_io_map[k] then
                    tmp[6] = dir_io_map[k]
                end
                table.insert(rs_485,tmp)
                if(k == 2)then break end
            end
            return rs_485
        else
            log.error("lnxall_config.uart",'485 config file error, ',err)
        end
    end
    return nil
end

function remote_log_param()
    if io.exists(LNXALL_remote_log_cfg) then
        local obj, res, err = json.decode(io.readFile(LNXALL_remote_log_cfg) or '')
        if res and obj then
            local addr
            if obj and obj.log_ip and obj.log_port and obj.log_proto and obj.log_level then
                addr = string.format( "%s://%s:%s",obj.log_proto,obj.log_ip,obj.log_port)
            else log.warn("default","remote log param error!") return  end
            if obj.log_level < 1 or obj.log_level > 8 then sys.warn("default","remote log level error!") return end
            return addr,obj.log_level
        else
            log.error("lnxall_config.log",'remote log config file error, ',err)
        end
    end
    return nil
end


function transparent_param()
    if io.exists(LNXALL_transparent_cfg) then
        local obj, res, err = json.decode(io.readFile(LNXALL_transparent_cfg) or '')
        if res and obj and obj.common_socket_cfg and #obj.common_socket_cfg >= 1 then
            local sockets = obj.common_socket_cfg
            local configs={}
            for i,socket in ipairs(sockets) do
                if socket and socket.protocol_type and socket.socket_addr and socket.socket_port then
                    tmp={
                        socket.protocol_type,
                        string.format("0x%s",socket.heartbeat_packet or "00"),
                        socket.heartbeat_interval or 0,
                        socket.socket_addr,
                        string.format("%d",socket.socket_port),
                        tonumber(string.sub(socket.binding_port,7)),
                        "",
                        "",
                        "",
                        "",
                        socket.login_packet and string.format("0x%s",socket.login_packet) or "",
                        socket.frame_header,
                        socket.frame_tail

                    }
                    table.insert( configs,tmp)
                end
            end
            return configs
        else
            log.warn("lnxall_config.transparent",'transparent config file error, ',err)
        end
    end
    return nil
end

function reload()
    log.info("lnxall_config.reload","lnxall config reload")
    if io.exists(lnxall_conf.LNXALL_nodes_cfg) then
        nodes_cfg = nil
        local dat, res, err = json.decode(io.readFile(lnxall_conf.LNXALL_nodes_cfg) or '')
        log.info("lnxall_config.nodes_cfg","load nodes config size:",json.encode(dat),dat, res, err)
        nodes_cfg= dat.nodes_cfg
        _G.nodes_cfg = nodes_cfg
        log.info("lnxall_config.nodes_cfg","load nodes config size:",#nodes_cfg,json.encode(nodes_cfg))
    end

    if io.exists(lnxall_conf.LNXALL_nodes_temp) then

        nodes_temp = nil
        local template_module_name={}
        local dat, res, err = json.decode(io.readFile(lnxall_conf.LNXALL_nodes_temp) or '')
        nodes_temp= dat.template_cfg
        _G.nodes_temp = nodes_temp
        log.info("lnxall_config.nodes_template","load nodes template size:",#nodes_temp,json.encode(nodes_temp))

        -- 在模板里找出,模板名字
        for k,v in ipairs(nodes_temp)do
            if v and v.parser_url then
                local part = v.parser_url:split("/")
                if part and #part >= 0 then
                    local file = part[#part]
                    log.info("lnxall_config.nodes_template",'parser script name of nodes template:', file)
                    table.insert(template_module_name,string.match(file,'(.+).lua'))
                end
            else
                log.warn("lnxall_config.nodes_template",'cound`t parser script in nodes template:', v['template_id'])
            end
        end

        -- --动态require 解析脚本用到的适配库
        -- require_modules(REQUIRE_ADAPTE_LIB)

        --把协议里的decode encode函数映射到局部变量
        bind_module_func(template_module_name)

        --读取需要周期配置的命令

    end
    -- 周期下行服务创建
    if #nodes_temp > 0 and  #nodes_cfg > 0 then
        parser_period_service()
    end
end

function scriptDecodeBysn(sn)
    if sn then
        for k,v in ipairs(nodes_cfg)do
            if v and v['sn'] == sn then
                return v['protocol_decode']
            end
        end
    end
    return nil
end

function scriptEncodeBysn(sn)
    if sn then
        for k,v in ipairs(nodes_cfg)do
            if v and v['sn'] == sn then
                return v['protocol_encode']
            end
        end
    end
    return nil
end

function offlineTimeBysn(sn)
    if sn then
        for _,node in ipairs(nodes_cfg) do  --确认模板被应用的设备有哪些
            if node.sn == sn then
                for _,temp in ipairs(nodes_temp) do
                    if temp.template_id == node.template_id then
                        return temp.offline_times
                    end
                end
            end
        end
    end
    return nil
end

function commonTimeBysn(sn)
    if sn then
        for _,node in ipairs(nodes_cfg) do  --确认模板被应用的设备有哪些
            if node.sn == sn then
                for _,temp in ipairs(nodes_temp) do
                    if temp.template_id == node.template_id then
                        return temp.communication_timeout
                    end
                end
            end
        end
    end
    return nil
end

function scriptDecodeByport(port)
    if port then
        local template_ids = {}
        local protocol_decode = nil
        local port_name = (type(port) == 'number') and string.format( "RS485_%d",port) or port
        log.info("lnxall_config.fetch_script","fetch script with port name",port_name)
        for _,node in ipairs(nodes_cfg) do  --确认模板被应用的设备有哪些
            if node.connect_port == port_name then
                local found = false
                protocol_decode = node.protocol_decode
                for _,t in ipairs(template_ids) do
                    if t == node.template_id then  found = true break end
                end
                if not found then table.insert(template_ids,node.template_id) end --记录模板ID
            end
        end
        if #template_ids == 0 then log.warn("lnxall_config.fetch_script",string.format("no one template bind port:%s",port_name)) return nil
        elseif #template_ids > 1 then log.warn("lnxall_config.fetch_script",string.format("mulit template bind port:%s",port_name)) return nil
        else return protocol_decode
        end
    end
    return nil
end


function getUrlFileName(url,symbol)
    local part = string.split(url,symbol or "/")
    if part and #part >= 0 then  return part[#part]
    else return nil
    end
end

reload()
