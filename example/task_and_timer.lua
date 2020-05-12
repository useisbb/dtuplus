require "common"
require "link"
require "pins"
require "utils"

module(..., package.seeall)

local count = 0
sys.timerLoopStart(function()
    log.info("count:", count)
    count = count +1
end, 1000)

sys.taskInit(function()
    while true do
        log.info("======= task 1 done ====")
        sys.wait(3000)
    end
end)

sys.taskInit(function()
    while true do
        log.info("======= task 2 done ====")
        sys.wait(1000)
    end
end)


sys.taskInit(function()
    while true do
        log.info("======= task 1 done ====")
        sys.wait(1000)
        sys.publish("TEST_MSG","123","abc")
    end
end)



sys.taskInit(function()
    while true do

        -- sys.wait(1000)
        local result, data,data2 = sys.waitUntil("TEST_MSG", 500)
        log.info("======= task 2 done ====",result,data,data2)
    end
end)

sys.subscribe("TEST_MSG", function(data,data2)
    log.info("======= task 2 subscribe ====",data,data2)
end)
