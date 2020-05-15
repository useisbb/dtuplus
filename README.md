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
## 与AIR720 user/目录下代码不同
```

```


