require "cjson"

json={}

function json.encode(...)
    return cjson.encode(...)
end

function json.decode(...)
    local str = cjson.decode(...)
    if str then
        return str,true
    else
        return nil,false
    end
end

return json
