
require "link"
require "pins"
require "misc"
require "mqtt"
require "utils"
require "socket"
require "common"
require "create"
require "tracker"


cjson={}

function cjson.decode(json_str)
    return json.decode(json_str)
end

function cjson.encode(json_str)
    return json.encode(json_str)
end

return cjson
