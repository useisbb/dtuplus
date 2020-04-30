--- 模块功能：远程升级.
-- 参考 http://ask.openluat.com/article/916 加深对远程升级功能的理解
-- @module update
-- @author openLuat
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.29

require "misc"
require "http"
require "log"
require "common"

module(..., package.seeall)

local sUpdating,sCbFnc,sUrl,sPeriod,SRedir,sLocation,fotastart
local sProcessedLen = 0
--local sBraekTest = 0

local function httpDownloadCbFnc(result,statusCode,head)
    log.info("update.httpDownloadCbFnc",result,statusCode,head,sCbFnc,sPeriod)
    sys.publish("UPDATE_DOWNLOAD",result,statusCode,head)
end

local function processOta(stepData,totalLen,statusCode)
    if stepData and totalLen then
        if statusCode=="200" or statusCode=="206" then            
            if rtos.fota_process((sProcessedLen+stepData:len()>totalLen) and stepData:sub(1,totalLen-sProcessedLen) or stepData,totalLen)~=0 then 
                log.error("updata.processOta","fail")
                return false
            else
                sProcessedLen = sProcessedLen + stepData:len()
                log.info("updata.processOta",totalLen,sProcessedLen,(sProcessedLen*100/totalLen).."%")
                --if sProcessedLen*100/totalLen==sBraekTest then return false end
                if sProcessedLen*100/totalLen>=100 then return true end
            end
        elseif statusCode:sub(1,1)~="3" and stepData:len()==totalLen and totalLen>0 and totalLen<=200 then
            local msg = stepData:match("\"msg\":%s*\"(.-)\"")
            if msg and msg:len()<=200 then
                log.warn("update.error",common.ucs2beToUtf8((msg:gsub("\\u","")):fromHex()))
            end
        end
    end
end

function clientTask()
    sUpdating = true
    --不要省略此处代码，否则下文中的misc.getImei有可能获取不到
    while not socket.isReady() do sys.waitUntil("IP_READY_IND") end
    while true do
        local retryCnt = 0
        sProcessedLen = 0
        while true do
            --sBraekTest = sBraekTest+30
            log.info("update.http.request",sLocation,sUrl,sProcessedLen,sBraekTest,fotastart)
            if not fotastart then break end
            http.request("GET",
                     sLocation or ((sUrl or "iot.openluat.com/api/site/firmware_upgrade").."?project_key=".._G.PRODUCT_KEY
                            .."&imei="..misc.getImei().."&device_key="..misc.getSn()
                            .."&firmware_name=".._G.PROJECT.."_"..rtos.get_version().."&version=".._G.VERSION..(sRedir and "&need_oss_url=1" or "")),
                     nil,{["Range"]="bytes="..sProcessedLen.."-"},nil,60000,httpDownloadCbFnc,processOta)
                     
            local _,result,statusCode,head = sys.waitUntil("UPDATE_DOWNLOAD")
            log.info("update.waitUntil UPDATE_DOWNLOAD",result,statusCode)
            if result then
                log.info("update.rtos.fota_end",rtos.fota_end())
                if statusCode=="200" or statusCode=="206" then                    
                    if sCbFnc then
                        sCbFnc(true)
                    else
                        sys.restart("UPDATE_DOWNLOAD_SUCCESS")
                    end
                elseif statusCode:sub(1,1)=="3" and head and head["Location"] then
                    sUpdating,sLocation = false,head["Location"]
                    print("update.timerStart",head["Location"])
                    return sys.timerStart(request,2000)
                else
                    if sCbFnc then sCbFnc(false) end
                end
                break
            else
                retryCnt = retryCnt+1
                if retryCnt==30 then
                    rtos.fota_end()
                    if sCbFnc then sCbFnc(false) end
                    break
                end
            end
        end
        
        sProcessedLen = 0
        
        if sPeriod then
            sys.wait(sPeriod)
            if rtos.fota_start()~=0 then 
                log.error("update.request","fota_start fail")
                fotastart = false
            else
                fotastart = true
            end
        else
            break
        end
    end
    sUpdating = false
end

--- 启动远程升级功能
-- @function[opt=nil] cbFnc，每次执行远程升级功能后的回调函数，回调函数的调用形式为：
-- cbFnc(result)，result为true表示升级包下载成功，其余表示下载失败
--如果没有设置此参数，则升级包下载成功后，会自动重启
-- @string[opt=nil] url，使用http的get命令下载升级包的url，如果没有设置此参数，默认使用Luat iot平台的url
-- 如果用户设置了url，注意：仅传入完整url的前半部分(如果有参数，即传入?前一部分)，http.lua会自动添加?以及后面的参数，例如：
-- 设置的url="www.userserver.com/api/site/firmware_upgrade"，则http.lua会在此url后面补充下面的参数
-- "?project_key=".._G.PRODUCT_KEY
-- .."&imei="..misc.getimei()
-- .."&device_key="..misc.getsn()
-- .."&firmware_name=".._G.PROJECT.."_"..rtos.get_version().."&version=".._G.VERSION
-- 如果redir设置为true，还会补充.."&need_oss_url=1"
-- @number[opt=nil] period，单位毫秒，定时启动远程升级功能的间隔，如果没有设置此参数，仅执行一次远程升级功能
-- @bool[opt=nil] redir，是否访问重定向到阿里云的升级包，使用Luat提供的升级服务器时，此参数才有意义
-- 为了缓解Luat的升级服务器压力，从2018年7月11日起，在iot.openluat.com新增或者修改升级包的升级配置时，升级文件会备份一份到阿里云服务器
-- 如果此参数设置为true，会从阿里云服务器下载升级包；如果此参数设置为false或者nil，仍然从Luat的升级服务器下载升级包
-- @return nil
-- @usage
-- update.request()
-- update.request(cbFnc)
-- update.request(cbFnc,"www.userserver.com/update")
-- update.request(cbFnc,nil,4*3600*1000)
-- update.request(cbFnc,nil,4*3600*1000,true)
function request(cbFnc,url,period,redir)
    if rtos.fota_start()~=0 then 
        log.error("update.request","fota_start fail")
        fotastart = false
        return
    else
        fotastart = true
    end
    sCbFnc,sUrl,sPeriod,sRedir = cbFnc or sCbFnc,url or sUrl,period or sPeriod,sRedir or redir
    log.info("update.request",sCbFnc,sUrl,sPeriod,sRedir)
    if not sUpdating then        
        sys.taskInit(clientTask)
    end
end
