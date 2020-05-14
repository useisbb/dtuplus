require "pm"
require "link"
require "pins"
require "misc"
require "mqtt"
require "utils"
require "socket"
require "httpv2"
require "common"
require "create"
require "tracker"
require "patch"

lua_pack={}

function lua_pack.bpack(format, ... )
    if not format then return nil end
    local dy_format = format
    dy_format = string.gsub(dy_format,'C','b')
    dy_format = string.gsub(dy_format,'s','h')
    dy_format = string.gsub(dy_format,'S','H')
    local packed = pack.pack( dy_format, ... )
    return packed
end

function lua_pack.bunpack( string, format, init )
    if not string or not format then return nil end
    local dy_format = format
    dy_format = string.gsub(dy_format,'C','b')
    dy_format = string.gsub(dy_format,'s','h')
    dy_format = string.gsub(dy_format,'S','H')
    return pack.unpack( string, dy_format, init )
end

return lua_pack
