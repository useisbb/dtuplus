local Scheduler = require("ELScheduler")

local n = ...
n = tonumber(n) or 1e3

local scheduler = Scheduler()

local count = 0
local function cb_inc(timer)
  count = count+1
end

print("create "..n.." timers")
for i=1,n do
  scheduler:timer(i,-1,cb_inc)
end

