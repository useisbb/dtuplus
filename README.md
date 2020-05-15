#DTU+
## 概述
基于lua5.1引擎和标准lua库.实现运行在linux平台的luatOS
运行lua5.1以及以上环境,部分语法可能不支持,例如
    ```
    module(..., package.seeall)
    ```
## 环境部署&运行
### 首先确保lua5.1  luarocks 安装
* @ubuntu
    ```
    run "sudo apt install lua5.1"
    run "sudo apt install luarocks"
    ```
* openwrt
    ```
    opkg install lua5.1"
    opkg install luarocks"
    ```
### 运行环境部署脚本
    ```
    git clone -b virtureDtu http://10.3.1.144/lnxall/dtuplus.git
    cd dtuplus/
    ./setenv.sh
    ./startup.sh
    ```

## 主要扩展
* 挖空GPIO LED 等函数body
* 适配PC uart
* 适配socket 与 lsocket
* 适配os 相关lib
* 移除4g模组相关代码

## 目录结构
    ```
    .
    ├── adapte              适配air720和原openwrt的库
    ├── example
    ├── lib                 luat核心代码
    ├── luat_file           平台下载文件保存路径
    ├── os                  OS相关的lib
    ├── parser_script       本地测试脚本的位置
    ├── peripheral          OS外设
    ├── README.md
    ├── setenv.sh           运行环境配置脚本
    ├── statrup.sh          运行脚本
    ├── test.sh
    └── user                用户业务逻辑
    ```


## lnxall 下配置本地测试代码修改
* user/lnxall_conf.lua
如下代码测试时打开,下面的屏蔽,测试完成务必屏蔽掉
```
-- 测试串口配置
local str = '{"mi":63901221,"rs485_cfg":[{"disable":0,"parity":0,"port":"RS485_1","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_2","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_3","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1},{"disable":0,"parity":0,"port":"RS485_4","protocol":"GW_PROTC_MODBUS","speed":9600,"stop":1}],"timestamp":1587102806,"version":"uJloPlpCA3Bd"}'
-- if not io.exists(LNXALL_rs485) then
    io.writeFile(LNXALL_rs485, str, 'w')
-- end

-- 测试mqtt配置
local str = '{"host": "mqtt.lnxall.com","port": 3883,"user": "localuser","pass": "dywl@galaxy"}'
-- if not io.exists(LNXALL_mqtt) then
    io.writeFile(LNXALL_mqtt, str, 'w')
-- end

-- 测试节点配置
local str = '{"nodes_cfg":[{"connect_port":"RS485_1","depth":0,"product_key":"23505558","sn":"44444444444","template_id":"23505558","term_addr":"02"}]}'
-- if not io.exists(LNXALL_nodes_cfg) then
    io.writeFile(LNXALL_nodes_cfg, str, 'w')
-- end

-- 测试模板配置
local str = '{"template_cfg":[{"communication_timeout":0,"logout_times":0,"offline_times":0,"parser_url":"http://qa.iot.lnxall.com/iot/download/gateway-cfg/script_demo.lua","protocol":"GW_PROTC_MODBUS","report_period":0,"service_cfg":[{"direction":0,"identifier":"weiyishangbao","instruction_code":0,"report_period":10,"server_period":10},{"direction":1,"identifier":"weiyishangbao","instruction_code":0,"report_period":0,"server_period":0}],"template_id":"23505558","use_parser_url":1}]}'
-- if not io.exists(LNXALL_nodes_temp) then
    io.writeFile(LNXALL_nodes_temp, str, 'w')
-- end

-- 测试脚本  -- LuatTools 会把没有require的文件,忽略下载导致require失败
script_demo = require "script_demo"

```



## 与AIR720 user/目录下代码不同
```

```


