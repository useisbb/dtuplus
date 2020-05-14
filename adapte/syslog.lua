syslog={}
local prefix = 'user'
function syslog.openlog(name, _ , set_level)
    prefix = name
end

function syslog.syslog(level, ...)
    print(prefix .. level, ...)
end
-- syslog.syslog("LOG_WARNING", "Hi all " .. os.time())
return syslog
