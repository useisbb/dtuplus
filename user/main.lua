--必须在这个位置定义PROJECT和VERSION变量
--PROJECT：ascii string类型，可以随便定义，只要不使用,就行
--VERSION：ascii string类型，如果使用Luat物联云平台固件升级的功能，必须按照"X.X.X"定义，X表示1位数字；否则可随便定义
PROJECT = "iRTU"
VERSION = "1.8.11"
PRODUCT_KEY = "DPVrZXiffhEUBeHOUwOKTlESam3aXvnR"

--加载日志功能模块，并且设置日志输出等级
--如果关闭调用log模块接口输出的日志，等级设置为log.LOG_SILENT即可
print(package.path)
print(package.cpath)
-- require "zmq"
require "log"

-- LOG_LEVEL = log.LOGLEVEL_INFO
LOG_LEVEL = log.LOGLEVEL_TRACE
require "sys"
require "net"
require "utils"
require "patch"


if rtos.get_version():upper():find("ASR1802") then
    rtos.set_trace_port(2)
elseif rtos.get_version():upper():find("8955") then
    require "wdt"
    wdt.setup(pio.P0_30, pio.P0_31)
end
--加载错误日志管理功能模块【强烈建议打开此功能】
--如下2行代码，只是简单的演示如何使用errDump功能，详情参考errDump的api
-- require "errDump"
-- errDump.request("udp://ota.airm2m.com:9072")
-- require "ntp"
-- ntp.timeSync(24, function()log.info(" AutoTimeSync is Done!") end)

--加载lnxall数据处理
require "test"

--启动系统框架
sys.init(0, 0)
sys.run()
